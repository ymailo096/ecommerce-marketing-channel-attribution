-- Grain: 1 row per customer_id (Olist's per-order customer id).
-- WARNING: customer_id is NOT the stable buyer id. The same physical
-- buyer gets a new customer_id for each order they place; their
-- stable id is customer_unique_id. Downstream models that count
-- buyers must dedupe on customer_unique_id.

{{ config(materialized='table') }}

select
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
from {{ source('olist_raw', 'customers') }}
