-- Ad hoc 90-day repeat purchase rate by channel for the 2017-11 cohort.
-- PROJECT_BRIEF.md section 10 rule-of-three step 1: verified manually before any
-- dbt model gets built on top. Nothing here is persisted — SELECT
-- only, Sandbox-safe.
--
-- Formula (locked by docs/PROJECT_BRIEF.md section 5, metric #2):
--   Repeat purchase rate (90-day cohort) =
--       % of a channel's first-purchase-month cohort that placed
--       a second order within 90 days of their first order.
--
-- "Second order within 90 days" here means: at least one order
-- strictly LATER than first_purchase_at AND ≤ 90 days after it.
-- If the customer has orders on days 0 + 50 + 200, the day-50 order
-- makes them a repeater; if on 0 + 100, no repeat (100d > 90d).
--
-- Aligned with the CAC and LTV ad hocs: restricted to 2017-11
-- (Olist's busiest month) so cohort_size can be cross-checked
-- against the CAC's new_customer_count (must match exactly:
-- 2907/1920/1386/1091).
--
-- Grain trace (standard JOIN granularity check):
--   * `orders`    — 1 row per order (99,441).
--   * `customers` — 1 row per customer_id (99,441). Repeat buyers
--                   appear on multiple customer_id rows sharing the
--                   same customer_unique_id.
--   * customer_unique_id → many customer_id → many orders.
--
-- Fan-out check inside `repeats` CTE:
--   channels JOIN customers on customer_unique_id → 1:many (repeat
--     buyers get multiple rows here), and each of those customer_id
--     rows joins 1:1 to `orders`. So per customer_unique_id we get
--     N rows where N = their total order count.
--   MAX(CASE WHEN in-window THEN 1 ELSE 0 END) GROUP BY
--     customer_unique_id then collapses back to per-customer 1/0.
--   No spend/count metric involved here, so fan-out doesn't
--   contaminate the numerator — MAX is idempotent under row
--   duplication.
--
-- Expected numbers: Olist's overall repeat purchase rate is very low
-- (single-digit percent), and because channel is a random hash of
-- customer_unique_id (docs/PROJECT_BRIEF.md section 4), per-channel rates should sit
-- within a couple of percentage points of each other. Any large gap
-- would indicate a query bug, not a real signal.

WITH
first_purchase AS (
  SELECT
    c.customer_unique_id,
    MIN(o.order_purchase_timestamp)                          AS first_purchase_at,
    DATE_TRUNC(DATE(MIN(o.order_purchase_timestamp)), MONTH) AS first_purchase_month
  FROM `olist_raw.orders` o
  JOIN `olist_raw.customers` c USING (customer_id)
  GROUP BY c.customer_unique_id
),

channels AS (
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

repeats AS (
  -- Per customer: 1 if any of their orders happen STRICTLY after
  -- first_purchase_at AND within 90 days of it.
  SELECT
    ch.customer_unique_id,
    MAX(CASE
      WHEN o.order_purchase_timestamp >  ch.first_purchase_at
       AND o.order_purchase_timestamp <= TIMESTAMP_ADD(ch.first_purchase_at, INTERVAL 90 DAY)
      THEN 1 ELSE 0
    END) AS has_repeat_within_90d
  FROM channels ch
  JOIN `olist_raw.customers` c USING (customer_unique_id)
  JOIN `olist_raw.orders`    o USING (customer_id)
  GROUP BY ch.customer_unique_id
),

busiest_month AS (
  SELECT DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS month
  FROM `olist_raw.orders`
  GROUP BY month
  ORDER BY COUNT(*) DESC
  LIMIT 1
)

SELECT
  ch.first_purchase_month                                        AS cohort_month,
  ch.channel,
  COUNT(*)                                                       AS cohort_size,
  SUM(r.has_repeat_within_90d)                                   AS repeaters,
  ROUND(SUM(r.has_repeat_within_90d) / COUNT(*) * 100, 2)        AS repeat_rate_pct
FROM channels ch
JOIN repeats r USING (customer_unique_id)
WHERE ch.first_purchase_month = (SELECT month FROM busiest_month)
GROUP BY ch.channel, ch.first_purchase_month
ORDER BY repeat_rate_pct DESC;
