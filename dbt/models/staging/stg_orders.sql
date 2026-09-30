-- Grain: 1 row per order (99,441 rows).
-- customer_id in this table is 1:1 with orders — each customer_id
-- appears exactly once here and exactly once in stg_customers, so joining
-- customers to orders on customer_id will NOT fan out (multiplication
-- factor = 1). This 1:1-ness is the reason int_customer_channel can
-- safely inner-join the two tables before grouping.

{{ config(materialized='table') }}

select
    order_id,
    customer_id,
    order_status,
    cast(order_purchase_timestamp        as timestamp) as order_purchase_timestamp,
    cast(order_approved_at               as timestamp) as order_approved_at,
    cast(order_delivered_carrier_date    as timestamp) as order_delivered_carrier_date,
    cast(order_delivered_customer_date   as timestamp) as order_delivered_customer_date,
    cast(order_estimated_delivery_date   as timestamp) as order_estimated_delivery_date
from {{ source('olist_raw', 'orders') }}
