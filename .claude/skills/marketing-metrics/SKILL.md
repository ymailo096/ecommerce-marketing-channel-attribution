---
name: marketing-metrics
description: Use when writing or reviewing any dbt model, SQL query, or metric calculation involving CAC, LTV, repeat purchase rate, ROAS, or channel attribution in this project — ensures the locked formulas and granularity rules are followed exactly, not re-derived from memory.
---

# Marketing Channel Attribution — Locked Metric Definitions

This project answers one question: which marketing channel is actually
most efficient once you look past the cost of the first order. Every
metric below exists to serve that question — do not add new metrics
without updating PROJECT_PLAN.md first.

## Channel assignment
Channel is a synthetic attribute assigned per customer (not per order),
fixed at their first-purchase month:
- Deterministic hash of `customer_unique_id` (FARM_FINGERPRINT) into one of 4 channels
- Weights: Organic/Direct ~40%, Google Ads ~25%, Facebook/Instagram Ads ~20%, Email/Referral ~15%

## Granularity trap
`ad_spend` lives at channel+month grain — coarser than orders/customers.
Always aggregate customers to channel+month BEFORE joining to ad_spend.
Never join ad_spend directly to an order-level or customer-level table —
this causes silent fan-out inflation of spend.

## Locked metric formulas (do not modify without checking PROJECT_PLAN.md)

1. CAC by channel = ad_spend(channel, month) / count(new customers of that channel acquired in that month)
2. Repeat purchase rate (90-day cohort) = % of a channel's first-purchase-month cohort that placed a second order within 90 days of their first order
3. LTV-proxy (90 days) = sum(order_payments.payment_value) within 90 days of each customer's first order, aggregated by channel
4. ROAS = LTV-proxy / CAC
5. A/B test — separate, standalone; never mixed into the channel-level metrics above

## Before writing any query using these metrics
- Confirm which grain you are at before any join to ad_spend
- Never compute a rate/ratio metric with a naive AVG of already-aggregated numbers — recompute from raw sums
- Cross-check any new metric calculation against the rule-of-three ad hoc verified numbers before trusting it
