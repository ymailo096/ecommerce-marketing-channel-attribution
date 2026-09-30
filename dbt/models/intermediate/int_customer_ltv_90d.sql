-- Grain: 1 row per customer_unique_id who has ≥1 payment within
-- 90 days of their first order (in Olist that's all of them —
-- every order has ≥1 payment installment).
--
-- Formula (locked in `marketing-metrics` skill, §"Locked metric
-- formulas" #3): sum(order_payments.payment_value) over all orders
-- of a customer placed within 90 days of that customer's first
-- order. Aggregation up to (channel, month) happens in the mart —
-- this model deliberately stays at customer grain so future models
-- (retention analyses, LTV-vs-CAC per customer) can reuse it.
--
-- Grain trace (sql-query-rigor §"Перед будь-яким JOIN"):
--   stg_customers        1:1 on customer_id  → stg_orders (99,441 rows)
--   stg_orders           1:many on order_id  → stg_order_payments
--                                              (~103,886 rows total)
--   int_customer_channel 1:1 on customer_unique_id (already deduped)
--                                              → filters via BETWEEN,
--                                                doesn't multiply rows
-- After GROUP BY customer_unique_id → ~96k rows.
--
-- Kept as one SELECT (no wrapper CTE) per sql-query-rigor's minimum-
-- abstraction rule — the join is straightforward once the grain
-- trace is written out.

{{ config(materialized='table') }}

select
    c.customer_unique_id,
    sum(p.payment_value) as ltv_90d_brl
from {{ ref('stg_customers') }} c
inner join {{ ref('stg_orders') }} o
    using (customer_id)
inner join {{ ref('stg_order_payments') }} p
    using (order_id)
inner join {{ ref('int_customer_channel') }} ch
    on ch.customer_unique_id = c.customer_unique_id
where o.order_purchase_timestamp
      between ch.first_purchase_at
          and timestamp_add(ch.first_purchase_at, interval 90 day)
group by c.customer_unique_id
