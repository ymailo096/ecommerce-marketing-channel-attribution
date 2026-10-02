-- Grain: 1 row per (channel, first_purchase_month).
--
-- This is THE model that reconciles grain with `stg_ad_spend` — after
-- this step, both sides of the eventual CAC join are at (channel, month)
-- grain. Doing this reduction here (intermediate layer) instead of
-- inside mart_cac_by_channel keeps the mart layer a clean join over
-- matching-grain inputs, which is exactly the pattern the project
-- brief requires: aggregate customers to channel+month BEFORE joining
-- to ad_spend (docs/PROJECT_BRIEF.md section 3, ad_spend grain).
--
-- `count(*)` is safe here because int_customer_channel is guaranteed
-- to have 1 row per customer_unique_id (its GROUP BY key). So
-- count(*) == count(distinct customer_unique_id); the extra DISTINCT
-- would be over-engineering.

{{ config(materialized='table') }}

select
    channel,
    first_purchase_month as month,
    count(*) as new_customer_count
from {{ ref('int_customer_channel') }}
group by channel, first_purchase_month
