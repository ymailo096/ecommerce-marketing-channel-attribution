-- Ad hoc CAC by channel for the single busiest month in Olist.
-- CLAUDE.md §10 rule-of-three step 1: verified manually before anything
-- else gets built on top. Nothing here is persisted — SELECT only,
-- Sandbox-safe.
--
-- Contract:
--   * Channel is a deterministic hash of customer_unique_id → 4 buckets
--     with the weights from CLAUDE.md §4 (Organic 40, Google Ads 25,
--     FB/IG 20, Email/Referral 15). Same customer → always same channel.
--   * First-purchase month per customer_unique_id = the month of that
--     customer's earliest order_purchase_timestamp.
--   * "Busiest month" = the month with the most orders across the whole
--     `orders` table (proxy for meaningful sample size).
--   * CAC(channel) = ad_spend(channel, busiest_month)
--                    / (new customers acquired in that channel in that month).
--
-- Fan-out guardrail (CLAUDE.md §8): `ad_spend` is at (channel, month)
-- grain. We first aggregate customers to (channel, month) in the
-- `new_customers` CTE, then join `ad_spend` on those two keys. Never
-- join `ad_spend` directly onto `orders` or `order_items`.
--
-- Placeholders `{project}.{raw_dataset}` are filled in by
-- python/run_adhoc_cac.py at execution time.

WITH
-- One row per customer_unique_id with a deterministic channel bucket.
-- `customers` has one row per `customer_id`, and the same person can
-- appear under multiple `customer_id` values across repeat orders, so
-- we dedupe by customer_unique_id first — otherwise the hash would be
-- fine (deterministic) but we'd count them multiple times downstream.
channels AS (
  SELECT
    customer_unique_id,
    CASE
      WHEN MOD(ABS(FARM_FINGERPRINT(customer_unique_id)), 100) < 40 THEN 'Organic'
      WHEN MOD(ABS(FARM_FINGERPRINT(customer_unique_id)), 100) < 65 THEN 'Google Ads'
      WHEN MOD(ABS(FARM_FINGERPRINT(customer_unique_id)), 100) < 85 THEN 'Facebook/Instagram Ads'
      ELSE 'Email/Referral'
    END AS channel
  FROM `{project}.{raw_dataset}.customers`
  GROUP BY customer_unique_id
),

-- One row per customer_unique_id with their first-purchase month.
-- Uses order_purchase_timestamp (when the customer placed the order),
-- not the delivery or approval timestamps.
first_purchase AS (
  SELECT
    c.customer_unique_id,
    DATE_TRUNC(DATE(MIN(o.order_purchase_timestamp)), MONTH) AS first_purchase_month
  FROM `{project}.{raw_dataset}.orders` o
  JOIN `{project}.{raw_dataset}.customers` c
    ON o.customer_id = c.customer_id
  GROUP BY c.customer_unique_id
),

-- The single busiest month across all orders. Kept as its own CTE so
-- the choice is visible in the output (not hidden behind a scalar
-- subquery).
busiest_month AS (
  SELECT DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS month
  FROM `{project}.{raw_dataset}.orders`
  GROUP BY month
  ORDER BY COUNT(*) DESC
  LIMIT 1
),

-- Aggregate new customers to (channel, month) grain BEFORE joining to
-- ad_spend — CLAUDE.md §8 fan-out rule.
new_customers AS (
  SELECT
    ch.channel,
    fp.first_purchase_month AS month,
    COUNT(*) AS new_customer_count
  FROM first_purchase fp
  JOIN channels ch USING (customer_unique_id)
  WHERE fp.first_purchase_month = (SELECT month FROM busiest_month)
  GROUP BY ch.channel, fp.first_purchase_month
)

SELECT
  nc.month                                    AS busiest_month,
  nc.channel,
  nc.new_customer_count,
  s.spend_brl,
  ROUND(s.spend_brl / nc.new_customer_count, 2) AS cac_brl
FROM new_customers nc
JOIN `{project}.{raw_dataset}.ad_spend` s
  ON s.channel = nc.channel
 AND s.month = nc.month
ORDER BY cac_brl ASC;
