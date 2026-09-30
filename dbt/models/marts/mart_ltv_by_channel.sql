-- Grain: 1 row per (channel, first_purchase_month) — LTV-proxy per
-- acquisition cohort. Same grain as `mart_cac_by_channel`, so ROAS
-- (LTV / CAC) can be composed by joining them on (channel, month).
--
-- LEFT JOIN from int_customer_channel to int_customer_ltv_90d — a
-- defensively-correct choice: any buyer with no payments in their
-- 90-day window (edge case; doesn't occur in Olist because every
-- order has ≥1 payment installment) still counts toward cohort_size
-- with LTV = 0. Ad hoc query used INNER JOIN, which for the current
-- data gives the same numbers — cross-checked exactly on 2017-11.
--
-- cohort_size is guaranteed identical to
-- `mart_cac_by_channel.new_customer_count` for the same (channel,
-- month) because both start from int_customer_channel and preserve
-- its grain — that's the whole reason to align the grain across marts.
--
-- ltv_per_customer_brl uses SAFE_DIVIDE — no divide-by-zero even in
-- the (impossible for Olist) case of cohort_size = 0.

{{ config(materialized='table') }}

select
    ch.channel,
    ch.first_purchase_month                          as month,
    count(*)                                         as cohort_size,
    sum(coalesce(ltv.ltv_90d_brl, 0))                as ltv_total_brl,
    safe_divide(
        sum(coalesce(ltv.ltv_90d_brl, 0)),
        count(*)
    )                                                as ltv_per_customer_brl
from {{ ref('int_customer_channel') }} ch
left join {{ ref('int_customer_ltv_90d') }} ltv
    using (customer_unique_id)
group by ch.channel, ch.first_purchase_month
