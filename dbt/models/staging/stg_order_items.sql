-- Grain: 1 row per (order_id, order_item_id) — one line item within
-- an order. An order can have multiple items (that's why row count
-- 112,650 > order count 99,441). Not used by CAC — kept in staging
-- for future LTV and repeat-purchase work.

{{ config(materialized='table') }}

select
    order_id,
    order_item_id,
    product_id,
    seller_id,
    cast(shipping_limit_date as timestamp) as shipping_limit_date,
    cast(price         as numeric) as price,
    cast(freight_value as numeric) as freight_value
from {{ source('olist_raw', 'order_items') }}
