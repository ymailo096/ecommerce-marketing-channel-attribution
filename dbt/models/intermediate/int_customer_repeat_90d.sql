-- Grain: 1 row per customer_unique_id, with `has_repeat_within_90d`
-- ∈ {0, 1} — 1 when the customer placed at least one order strictly
-- AFTER their first_purchase_at and within 90 days of it.
--
-- Formula (docs/PROJECT_BRIEF.md §5, metric #2): repeat purchase
-- rate is the % of a channel's first-purchase-month cohort with a
-- second order within 90 days. This model provides the per-customer
-- 0/1 signal; the aggregation to (channel, month) percent lives in
-- `mart_repeat_rate_by_channel`.
--
-- Grain trace (standard JOIN granularity check):
--   int_customer_channel  1 row per customer_unique_id (already deduped)
--   stg_customers         1:many on customer_unique_id (repeat buyers
--                           get one row per customer_id, so N ≥ 1 rows)
--   stg_orders            1:1 on customer_id (each customer_id maps to
--                           one order).
-- So per customer_unique_id we get N rows where N = their total orders.
-- MAX(CASE ...) is idempotent under this fan-out — it collapses back to
-- one row per customer regardless of how many orders they placed.
-- No count/sum here, so the fan-out cannot inflate a metric.

{{ config(materialized='table') }}

select
    ch.customer_unique_id,
    max(case
        when o.order_purchase_timestamp >  ch.first_purchase_at
         and o.order_purchase_timestamp <= timestamp_add(ch.first_purchase_at, interval 90 day)
        then 1 else 0
    end) as has_repeat_within_90d
from {{ ref('int_customer_channel') }} ch
join {{ ref('stg_customers') }} c using (customer_unique_id)
join {{ ref('stg_orders')    }} o using (customer_id)
group by ch.customer_unique_id
