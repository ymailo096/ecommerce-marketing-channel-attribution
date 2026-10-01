-- Grain: 1 row per (channel, first_purchase_month) — same grain as
-- mart_cac_by_channel and mart_ltv_by_channel. cohort_size is
-- guaranteed identical to the other two marts for any (channel, month)
-- (all three derive from int_customer_channel and preserve its grain).
--
-- Formula (docs/PROJECT_BRIEF.md §5, metric #2):
--   repeat_rate = repeaters(90d) / cohort_size
-- stored as a FRACTION (0.0234), not a percent (2.34) — presentation
-- multiplication by 100 is a display concern for the dashboard, not
-- for the mart itself.
--
-- LEFT JOIN from int_customer_channel to int_customer_repeat_90d for
-- symmetry with mart_ltv_by_channel: in Olist every customer has ≥1
-- order and therefore appears in int_customer_repeat_90d, so INNER
-- and LEFT produce identical numbers. LEFT is defensively correct if
-- a future edge case ever leaves a customer out of the repeat-flag
-- table (they still count in cohort_size, with 0 repeaters).

{{ config(materialized='table') }}

select
    ch.channel,
    ch.first_purchase_month                            as month,
    count(*)                                           as cohort_size,
    sum(coalesce(r.has_repeat_within_90d, 0))          as repeaters,
    safe_divide(
        sum(coalesce(r.has_repeat_within_90d, 0)),
        count(*)
    )                                                  as repeat_rate
from {{ ref('int_customer_channel') }} ch
left join {{ ref('int_customer_repeat_90d') }} r
    using (customer_unique_id)
group by ch.channel, ch.first_purchase_month
