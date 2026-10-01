-- Grain: 1 row per (order_id, payment_sequential) — a single payment
-- installment for an order. Multiple installments per order are common
-- (row count 103,886 > order count 99,441). Not used by CAC — kept in
-- staging for LTV-proxy work (sum of payment_value within 90 days of
-- first order, per docs/PROJECT_BRIEF.md §5).

{{ config(materialized='table') }}

select
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    cast(payment_value as numeric) as payment_value
from {{ source('olist_raw', 'order_payments') }}
