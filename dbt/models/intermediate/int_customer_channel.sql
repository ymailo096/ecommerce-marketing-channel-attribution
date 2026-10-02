-- Grain: 1 row per customer_unique_id (the stable buyer id).
--
-- Two grain reductions happen here — this is the FIRST layer where
-- we move away from per-order/per-customer_id rows:
--   1. stg_customers has 1:many customer_id → customer_unique_id
--      (repeat buyers get a new customer_id every order). GROUP BY
--      customer_unique_id collapses those back to one row per person.
--   2. stg_orders is joined by customer_id — safe INNER JOIN because
--      customer_id is unique in BOTH tables (99,441 rows in each,
--      one-to-one relationship confirmed 2026-09-29). No fan-out.
--
-- Channel assignment — from docs/PROJECT_BRIEF.md section 4:
--   Deterministic FARM_FINGERPRINT hash of customer_unique_id into 4
--   buckets, weights Organic 40 / Google Ads 25 / FB-IG 20 / Email 15.
--   Assigned to customer_unique_id, so once a buyer's channel is set
--   at their first order, it never changes on future orders. This
--   matches the "channel fixed at first-purchase month" rule in the
--   brief.

{{ config(materialized='table') }}

with customer_orders as (
    -- 99,441 rows: 1:1 join on customer_id (see stg_orders comment).
    select
        c.customer_unique_id,
        o.order_purchase_timestamp
    from {{ ref('stg_customers') }} c
    inner join {{ ref('stg_orders') }} o
        using (customer_id)
),

first_purchase as (
    -- Reduces from customer_id (99,441) → customer_unique_id (~96k).
    -- MIN(order_purchase_timestamp) per unique buyer = when they
    -- became a "new customer" for CAC attribution purposes.
    select
        customer_unique_id,
        min(order_purchase_timestamp) as first_purchase_at,
        date_trunc(date(min(order_purchase_timestamp)), month) as first_purchase_month
    from customer_orders
    group by customer_unique_id
)

select
    customer_unique_id,
    first_purchase_at,
    first_purchase_month,
    case
        when mod(abs(farm_fingerprint(customer_unique_id)), 100) < 40 then 'Organic'
        when mod(abs(farm_fingerprint(customer_unique_id)), 100) < 65 then 'Google Ads'
        when mod(abs(farm_fingerprint(customer_unique_id)), 100) < 85 then 'Facebook/Instagram Ads'
        else 'Email/Referral'
    end as channel
from first_purchase
