-- Grain: 1 row per (channel, month) — CAC by channel by acquisition month.
--
-- CAC formula (locked in `marketing-metrics` skill):
--   CAC = ad_spend(channel, month) / count(new customers of that
--         channel acquired in that month)
--
-- Both join inputs are already at (channel, month) grain:
--   - int_new_customers_by_channel_month: (channel, month) is unique
--     by construction (GROUP BY those two keys).
--   - stg_ad_spend: (channel, month) is unique by construction of the
--     source table (4 channels × 26 months = 104 rows).
-- Join is 1:1 on the composite key — no fan-out.
--
-- FULL OUTER JOIN vs INNER (the ad hoc query used INNER):
--   - Kept as FULL OUTER because a mart is meant to be complete: it
--     should show months with spend but no new customers (early Olist
--     months) and — defensively — cohorts with no spend row.
--   - For any (channel, month) where BOTH exist, the numeric result is
--     identical to the ad hoc INNER JOIN. That's the invariant that
--     lets us cross-check 2017-11 (all four channels have both).
--
-- Divide-by-zero handling: SAFE_DIVIDE returns NULL when denominator
-- is 0 or NULL, so cac_brl is NULL for (channel, month) with spend but
-- zero acquisitions, rather than raising a runtime error.
--
-- No rounding: presentation-layer concern. Consumers can format as needed.

{{ config(materialized='table') }}

with new_customers as (
    select channel, month, new_customer_count
    from {{ ref('int_new_customers_by_channel_month') }}
),

ad_spend as (
    select channel, month, spend_brl
    from {{ ref('stg_ad_spend') }}
)

-- With JOIN ... USING, BigQuery merges the join keys into single
-- columns already coalesced across sides, so no manual COALESCE
-- needed on `channel` / `month`.
select
    channel,
    month,
    n.new_customer_count,
    a.spend_brl,
    safe_divide(a.spend_brl, n.new_customer_count) as cac_brl
from ad_spend a
full outer join new_customers n
    using (channel, month)
