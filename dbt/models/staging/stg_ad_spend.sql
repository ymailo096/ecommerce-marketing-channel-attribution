-- Grain: 1 row per (channel, month). 4 channels × 26 months = 104 rows.
--
-- CRITICAL: this table is DELIBERATELY coarser than orders/customers.
-- The whole rule from docs/PROJECT_BRIEF.md §3 (ad_spend grain):
-- downstream metrics must aggregate customers/orders to (channel, month)
-- BEFORE joining to this. Joining ad_spend at order- or customer-level
-- silently multiplies spend across every row on the finer side and
-- inflates CAC. That's the pit the whole modeling stack is designed
-- to keep us out of.
--
-- Source table was loaded with an explicit schema (channel STRING,
-- month DATE, spend_brl NUMERIC), so no casting needed here.

{{ config(materialized='table') }}

select
    channel,
    month,
    spend_brl
from {{ source('olist_raw', 'ad_spend') }}
