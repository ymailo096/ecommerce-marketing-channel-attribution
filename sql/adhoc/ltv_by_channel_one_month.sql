-- Ad hoc LTV-proxy (90-day window) by channel for the 2017-11 cohort.
-- CLAUDE.md §10 rule-of-three step 1: verified manually before any
-- dbt model gets built on top. Nothing here is persisted — SELECT
-- only, Sandbox-safe.
--
-- Formula (locked by marketing-metrics skill, §"Locked metric formulas" #3):
--   LTV-proxy(90d)(channel) =
--       sum(order_payments.payment_value) over all orders of a customer
--       placed within 90 days of that customer's first order,
--       then aggregated by channel.
--
-- Aligned with the CAC ad hoc query: restricted to the 2017-11
-- cohort (Olist's busiest month = Black Friday) so we can eyeball
-- LTV per customer next to CAC per customer for the same cohort.
--
-- Grain trace (sql-query-rigor §"Перед будь-яким JOIN"):
--   * `orders`         — 1 row per order (99,441)
--   * `customers`      — 1 row per customer_id (99,441). Same
--                         customer_unique_id can appear on multiple
--                         customer_id rows (repeat buyers).
--   * `order_payments` — 1 row per (order_id, payment_sequential),
--                         103,886 rows because some orders have multiple
--                         installments (1:many with orders).
--
-- Fan-out check:
--   orders JOIN customers on customer_id  → 1:1 (customer_id unique
--     in both tables)                       → 99,441 rows
--   + JOIN order_payments on order_id     → 1:many (avg ~1.04 payment
--     rows per order)                       → 103,886 rows
--   SUM(payment_value) at customer level  → collapses to
--     ~96k customer_unique_id rows.
--   Aggregating those to (channel, month) is 1:many at the customer
--   side, so COUNT(*) counts customers (safe) and SUM(ltv_90d_brl)
--   sums per-customer totals (safe).
--
-- Rounding: to 2 dp only in the final SELECT for readable output —
-- doesn't affect the mart's precision.

WITH
first_purchase AS (
  -- One row per customer_unique_id with their earliest order timestamp.
  -- INNER JOIN on customer_id is safe (1:1). GROUP BY collapses
  -- multiple customer_id rows for repeat buyers.
  SELECT
    c.customer_unique_id,
    MIN(o.order_purchase_timestamp)                                AS first_purchase_at,
    DATE_TRUNC(DATE(MIN(o.order_purchase_timestamp)), MONTH)       AS first_purchase_month
  FROM `olist_raw.orders` o
  JOIN `olist_raw.customers` c USING (customer_id)
  GROUP BY c.customer_unique_id
),

channels AS (
  -- Assign channel via deterministic hash of customer_unique_id
  -- (marketing-metrics §"Channel assignment", weights 40/25/20/15).
  SELECT
    fp.customer_unique_id,
    fp.first_purchase_at,
    fp.first_purchase_month,
    CASE
      WHEN MOD(ABS(FARM_FINGERPRINT(fp.customer_unique_id)), 100) < 40 THEN 'Organic'
      WHEN MOD(ABS(FARM_FINGERPRINT(fp.customer_unique_id)), 100) < 65 THEN 'Google Ads'
      WHEN MOD(ABS(FARM_FINGERPRINT(fp.customer_unique_id)), 100) < 85 THEN 'Facebook/Instagram Ads'
      ELSE 'Email/Referral'
    END AS channel
  FROM first_purchase fp
),

customer_orders AS (
  -- All orders per customer_unique_id (may include the same customer's
  -- later re-orders under a NEW customer_id). We keep the per-order
  -- purchase timestamp to filter to the 90-day window per-customer.
  SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp
  FROM `olist_raw.orders` o
  JOIN `olist_raw.customers` c USING (customer_id)
),

customer_ltv_90d AS (
  -- Sum payment_value across all installments of all orders placed
  -- within 90 days of the customer's first order (inclusive of that
  -- first order itself — the interval starts at first_purchase_at
  -- + 0 seconds).
  SELECT
    ch.customer_unique_id,
    ch.channel,
    ch.first_purchase_month,
    SUM(p.payment_value) AS ltv_90d_brl
  FROM channels ch
  JOIN customer_orders co
    ON co.customer_unique_id = ch.customer_unique_id
   AND co.order_purchase_timestamp BETWEEN ch.first_purchase_at
                                        AND TIMESTAMP_ADD(ch.first_purchase_at, INTERVAL 90 DAY)
  JOIN `olist_raw.order_payments` p
    ON p.order_id = co.order_id
  GROUP BY ch.customer_unique_id, ch.channel, ch.first_purchase_month
),

busiest_month AS (
  SELECT DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS month
  FROM `olist_raw.orders`
  GROUP BY month
  ORDER BY COUNT(*) DESC
  LIMIT 1
)

SELECT
  first_purchase_month                              AS cohort_month,
  channel,
  COUNT(*)                                          AS cohort_size,
  ROUND(SUM(ltv_90d_brl), 2)                        AS ltv_total_brl,
  ROUND(SUM(ltv_90d_brl) / COUNT(*), 2)             AS ltv_per_customer_brl
FROM customer_ltv_90d
WHERE first_purchase_month = (SELECT month FROM busiest_month)
GROUP BY channel, first_purchase_month
ORDER BY ltv_per_customer_brl DESC;
