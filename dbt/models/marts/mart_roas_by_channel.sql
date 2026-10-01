-- Grain: 1 row per (channel, month) — same as the three input marts.
-- No aggregation, no GROUP BY: this is a pure 3-way join on the
-- composite key (channel, month).
--
-- Uniqueness of (channel, month) in each input was verified empirically
-- before this model was first committed (PROJECT_LOG,
-- rule-of-three log, ROAS row):
--   mart_cac_by_channel         104 rows / 104 distinct keys
--   mart_ltv_by_channel          91 rows /  91 distinct keys
--   mart_repeat_rate_by_channel  91 rows /  91 distinct keys
-- So 1:1:1 on the composite key — INNER JOIN cannot multiply rows.
--
-- Formula (docs/PROJECT_BRIEF.md §5, metric #4):
--   ROAS = LTV-proxy / CAC
-- Identity: (ltv_total_brl / cohort_size) / (spend_brl / cohort_size)
--         = ltv_total_brl / spend_brl.
-- We compute in per-customer form (ltv_per_customer_brl / cac_brl)
-- because that framing matches the CAC/LTV mart columns directly.
-- The identity is a useful sanity check — a one-liner
-- SELECT ltv_total_brl/spend_brl vs roas would confirm on demand.
--
-- JOIN choice (the standard granularity re-check): INNER on all three. A
-- row here is meaningful only when all three metrics are computable
-- for the same (channel, month). 13 (channel, month) combinations
-- from CAC (early months with ad spend but no customers acquired
-- yet in Olist) fall out — that's correct: ROAS is undefined without
-- a cohort to attribute revenue to.
--
-- NULL guard: SAFE_DIVIDE on ROAS. cac_brl = 0 or NULL → roas NULL,
-- not a runtime error.
--
-- cohort_size is picked from the CAC side (via new_customer_count).
-- Since all three inputs derive from int_customer_channel and preserve
-- its grain, cohort_size is identical across CAC.new_customer_count,
-- LTV.cohort_size, and repeat_rate.cohort_size. A future dbt test
-- could assert equality; for now the identity is documented here.

{{ config(materialized='table') }}

select
    cac.channel,
    cac.month,
    cac.new_customer_count                              as cohort_size,
    cac.spend_brl,
    cac.cac_brl,
    ltv.ltv_total_brl,
    ltv.ltv_per_customer_brl,
    rr.repeaters,
    rr.repeat_rate,
    safe_divide(ltv.ltv_per_customer_brl, cac.cac_brl)  as roas
from {{ ref('mart_cac_by_channel') }}         cac
inner join {{ ref('mart_ltv_by_channel') }}         ltv
    using (channel, month)
inner join {{ ref('mart_repeat_rate_by_channel') }} rr
    using (channel, month)
