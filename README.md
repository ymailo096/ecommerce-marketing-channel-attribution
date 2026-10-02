# Marketing Metrics Methodology (CAC · LTV · ROAS)

> **Business question:** How can marketing teams calculate CAC,
> 90-day LTV-proxy and ROAS reliably when customer acquisition data
> and advertising spend are stored at different grains, and the
> source dataset lacks channel information? This project focuses
> on metric methodology and data validation — not on evaluating
> real channel performance.

This project answers it using a real e-commerce order dataset
(Olist) joined to a synthetic ad-spend/channel layer (Olist ships
no channel/UTM field), validated with a rule-of-three methodology:
each metric is first computed as an ad hoc SQL query, then
re-expressed as a dbt model that matches the ad hoc result exactly,
then enforced in CI with dbt tests.

> **Channel assignment and `ad_spend` are synthetic**, with a
> fixed seed and independent of real purchase behaviour by design.
> Olist ships no channel/UTM field, so each customer is bucketed by
> a deterministic `FARM_FINGERPRINT(customer_unique_id)` hash into
> 4 weighted channels, and `ad_spend` is generated per
> `(channel, month)` from a seeded Python script. Orders,
> customers, and payments are the real anonymized Brazilian
> marketplace data. **Cross-channel comparisons in the tables
> below are illustrative of the methodology, not real investment
> recommendations.**

## Locked metric formulas

Also written out in full in [`docs/PROJECT_BRIEF.md §5`](docs/PROJECT_BRIEF.md).

| # | Metric                     | Formula                                                                                     |
|---|----------------------------|---------------------------------------------------------------------------------------------|
| 1 | CAC by channel             | `ad_spend(channel, month) / new_customers(channel, month)`                                  |
| 2 | Repeat purchase rate (90d) | % of channel's first-month cohort with a 2nd order within 90 days                           |
| 3 | LTV-proxy (90d)            | `SUM(payment_value)` within 90 days of each customer's first order, aggregated by channel   |
| 4 | ROAS                       | `LTV-proxy / CAC`                                                                           |

A separate, standalone A/B-test simulation (repeat-rate lift, two-proportion z-test in stdlib only) lives in [`python/ab_test_repeat_rate.py`](python/ab_test_repeat_rate.py) — deliberately kept out of the channel-attribution metrics above; see [`docs/PROJECT_LOG.md`](docs/PROJECT_LOG.md) for the full result.

## Verified 2017-11 snapshot (Olist's Black Friday peak)

| Channel                 | New customers | Spend (BRL) | CAC (BRL) | 90d LTV-proxy (BRL) | Repeat rate | ROAS   |
|-------------------------|--------------:|------------:|----------:|-------------------:|------------:|-------:|
| Organic                 |         2,907 |    1,149.88 |      0.40 |             165.65 |       1.96% | 418.78 |
| Email/Referral          |         1,091 |    1,688.12 |      1.55 |             158.09 |       1.74% | 102.17 |
| Facebook/Instagram Ads  |         1,386 |    6,145.24 |      4.43 |             158.24 |       2.09% |  35.69 |
| Google Ads              |         1,920 |   12,932.00 |      6.74 |             164.99 |       2.34% |  24.50 |

Every number here was verified twice: once via a hand-computed ad hoc
SQL query, then again as the same slice from the corresponding dbt
mart — both agree to at least 4 decimal places. Full evidence in
[`docs/PROJECT_LOG.md`](docs/PROJECT_LOG.md).

## Methodological lesson

With this channel-neutral customer base, **because LTV is
approximately equal across channels by design, the observed ROAS
differences are primarily driven by CAC.** Organic looks ~17×
cheaper than Google Ads on CAC. 90d LTV-proxy per customer ranges
158–166 BRL across the four channels (~5% spread) — consistent
with the design, since channel assignment is independent of
customer behaviour and per-channel LTV averages should converge
to the population mean. This was checked with a one-way Welch's
ANOVA on customer-level 90-day LTV-proxy by channel
(F = 0.71, p = 0.55), which found no evidence of a channel
effect at α = 0.05.

The takeaway isn't "shift budget into Organic". It's that **an
unusually cheap CAC should trigger a data-quality check before any
budget decision**. In a real business, a near-zero CAC on any
channel is more likely to reflect under-reported spend (SEO
tools, content operations, referral bonuses, brand halo) than a
genuine cost advantage; the methodological discipline is to verify
the spend data before touching the budget — and to confirm what
"spend" actually covers before comparing CAC across channels at all.

## Data contract / assumptions

Read this before drawing any conclusions from the numbers above.

- **CAC here is media spend only, not full CAC.** `ad_spend` captures
  channel media cost alone — it excludes agency fees, creative
  production, tooling, salaries, affiliate payouts, discounts,
  promotions, and referral incentives that a real CAC would include.
  Treat the numbers above as a blended channel acquisition cost based
  on synthetic spend, not a production-grade CAC.
- **Channel is synthetic.** Olist ships no channel/UTM/campaign field,
  so channel is assigned by a deterministic
  `MOD(ABS(FARM_FINGERPRINT(customer_unique_id)), 100)` bucket
  (weights Organic 40 / Google Ads 25 / FB-IG 20 / Email 15). Same
  customer always lands in the same bucket; the assignment has no
  causal relationship to their purchase behaviour.
- **`ad_spend` is synthetic.** Generated by
  [`python/generate_ad_spend_csv.py`](python/generate_ad_spend_csv.py)
  with `random.Random(42)` and hand-picked per-channel BRL ranges.
  Fixed seed → identical numbers on any re-run.
- **LTV being flat across channels is expected by design.** Because
  channel is a random hash of customer_unique_id (independent of every
  purchase-behaviour attribute), per-channel LTV averages have to
  converge to the population mean. The 158–166 BRL spread is sampling
  noise, not a "cheap CAC channel loses on LTV" signal. Do **not**
  patch the pipeline to introduce a difference.
- **Everything else is real.** Orders, customers, and payments are
  the actual anonymized Brazilian marketplace dataset from Olist on
  Kaggle — 99,441 orders across 2016-09 → 2018-10.
- **Contracts enforced on every change.** `dbt test` enforces the
  composite `(channel, month)` uniqueness of every mart, `not_null`
  on `stg_ad_spend`, and a no-exact-zero-CAC guard; a change that
  would break any of these fails CI instead of landing in `olist_dbt`.

## Live dashboard

*(Tableau Public link — placeholder until Phase 5 lands.)*

---

## Stack

BigQuery · dbt · Python (stdlib + `google-cloud-bigquery`) · GitHub
Actions (`dbt run` + `dbt test` on push) · Tableau Public

## Architecture

```
        ┌─────────────────────────┐      ┌──────────────────────────┐
        │ Olist Kaggle CSVs (raw) │      │ Synthetic ad_spend        │
        │  (manual download)      │      │  (python/, seeded)        │
        └────────────┬────────────┘      └────────────┬──────────────┘
                     │  bq load                        │  bq load
                     ▼                                 ▼
        ┌─────────────────────────────────────────────────────────┐
        │            BigQuery — dataset `olist_raw`               │
        │  customers, orders, order_items, order_payments,        │
        │  ad_spend (channel+month grain)                         │
        └───────────────────────────┬─────────────────────────────┘
                                    │  dbt run
                                    ▼
        ┌─────────────────────────────────────────────────────────┐
        │           BigQuery — dataset `olist_dbt`                │
        │                                                         │
        │  staging       stg_customers, stg_orders,               │
        │                stg_order_items, stg_order_payments,     │
        │                stg_ad_spend                             │
        │                                                         │
        │  intermediate  int_customer_channel                     │
        │                  (per customer_unique_id)               │
        │                int_new_customers_by_channel_month       │
        │                int_customer_ltv_90d                     │
        │                int_customer_repeat_90d                  │
        │                                                         │
        │  marts         mart_cac_by_channel                      │
        │                mart_ltv_by_channel                      │
        │                mart_repeat_rate_by_channel              │
        │                mart_roas_by_channel                     │
        └───────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
                          Tableau Public dashboard
                          (link once Phase 5 lands)
```

The synthetic `ad_spend` table lives at **channel+month grain —
deliberately coarser than orders**. Every downstream model that
touches it must first aggregate customer/order rows to channel+month;
joining spend directly onto order-level rows is the fan-out trap
the intermediate layer prevents by aggregating up first. That grain
reconciliation happens on purpose, in the intermediate layer, before
the mart.

## Run it locally

Prereqs: a GCP project with BigQuery API enabled and a dataset
`olist_raw` in region **EU**, plus `gcloud` CLI authenticated
(`gcloud auth login` for `bq` + `gcloud auth application-default
login` for dbt / Python libraries). The Olist CSVs are downloaded
manually from
[Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
into `data/olist/` (see [`docs/kaggle_download.md`](docs/kaggle_download.md)).

```bash
# 1. Load raw Olist tables (idempotent thanks to --replace).
for pair in \
  "orders:olist_orders_dataset.csv" \
  "customers:olist_customers_dataset.csv" \
  "order_items:olist_order_items_dataset.csv" \
  "order_payments:olist_order_payments_dataset.csv"; do
  table="${pair%%:*}"; file="${pair##*:}"
  bq load --source_format=CSV --autodetect --skip_leading_rows=1 \
    --location=EU --replace \
    "olist_raw.$table" "data/olist/$file"
done

# 2. Generate + load synthetic ad_spend (stdlib, no pip deps).
python3 python/generate_ad_spend_csv.py       # writes data/synthetic/ad_spend.csv
bq load --source_format=CSV --skip_leading_rows=1 --location=EU --replace \
  --schema="channel:STRING,month:DATE,spend_brl:NUMERIC" \
  olist_raw.ad_spend data/synthetic/ad_spend.csv

# 3. Create the Python environment and install dependencies.
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install dbt-bigquery

# 4. Rebuild the dbt marts.
cd dbt && dbt run           # materializes 13 tables in olist_dbt
dbt test                    # 8 contracts: PK uniqueness per mart, not_null, no-zero-CAC

# 5. Ad hoc verification query (rule-of-three step 1 — matches mart exactly).
bq query --use_legacy_sql=false --location=EU --format=pretty \
  --nouse_cache < sql/adhoc/cac_by_channel_one_month.sql
```

## What's where

| Path                              | Purpose                                                    |
|-----------------------------------|------------------------------------------------------------|
| `docs/PROJECT_BRIEF.md`           | Fixed project brief (scope, metrics, phases — do not edit) |
| `docs/PROJECT_LOG.md`             | Decision log + rule-of-three log + current status          |
| `docs/kaggle_download.md`         | Manual Olist download steps                                |
| `docs/tableau_setup.md`           | Tableau Public dashboard build + publish                   |
| `sql/adhoc/`                      | One-off verified queries (rule-of-three step 1)            |
| `dbt/models/`                     | staging → intermediate → marts (rule-of-three step 2)      |
| `python/`                         | `ad_spend` generator; mart-CSV export for the Tableau feed |
| `data/olist/`, `data/synthetic/`  | Local CSVs (gitignored)                                    |
