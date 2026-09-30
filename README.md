# E-commerce Marketing Channel Attribution

Which marketing channel is actually most efficient once you look past
the cost of the first order — i.e. how much revenue does a customer
generate over the following months after acquisition?

Every metric and every SQL model in this project exists to answer
that one question.

**Stack:** BigQuery · dbt · Python (stdlib + `google-cloud-bigquery`) ·
GitHub Actions (cron) · Tableau Public

## Architecture

```
        ┌─────────────────────────┐      ┌────────────────────────┐
        │ Olist Kaggle CSVs (raw) │      │ GitHub API (daily pull)│
        └────────────┬────────────┘      └───────────┬────────────┘
                     │  bq load                       │  Python + cron
                     ▼                                ▼
        ┌─────────────────────────────────────────────────────────┐
        │            BigQuery — dataset `olist_raw`               │
        │  customers, orders, order_items, order_payments,        │
        │  ad_spend (synthetic, seeded, channel+month grain),     │
        │  github_metrics                                         │
        └───────────────────────────┬─────────────────────────────┘
                                    │  dbt run
                                    ▼
        ┌─────────────────────────────────────────────────────────┐
        │           BigQuery — dataset `olist_dbt`                │
        │                                                         │
        │  staging       stg_customers, stg_orders,               │
        │                stg_order_items, stg_order_payments,     │
        │                stg_ad_spend  (1:1 with source)          │
        │                                                         │
        │  intermediate  int_customer_channel                     │
        │                  (per customer_unique_id)               │
        │                int_new_customers_by_channel_month       │
        │                  (per channel+month)                    │
        │                                                         │
        │  marts         mart_cac_by_channel                      │
        │                  (per channel+month, joined 1:1)        │
        │                mart_ltv_by_channel        (Phase 2)     │
        │                mart_repeat_rate_by_channel (Phase 2)    │
        │                mart_roas_by_channel        (Phase 2)    │
        └───────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
                          Tableau Public dashboard
                          (link once Phase 5 lands)
```

The synthetic `ad_spend` table lives at **channel+month grain — deliberately
coarser than orders**. Every downstream model that touches it must first
aggregate customer/order rows to channel+month; joining spend directly
onto order-level rows is the fan-out trap this project is designed to
teach avoiding. The intermediate layer is where that grain reconciliation
happens on purpose, before the mart.

## Metrics (locked — see `.claude/skills/marketing-metrics/SKILL.md`)

| # | Metric                     | Formula                                                                                     |
|---|----------------------------|---------------------------------------------------------------------------------------------|
| 1 | CAC by channel             | `ad_spend(channel, month) / new_customers(channel, month)`                                  |
| 2 | Repeat purchase rate (90d) | % of channel's first-month cohort with a 2nd order within 90 days                           |
| 3 | LTV-proxy (90d)            | `SUM(payment_value)` within 90 days of each customer's first order, aggregated by channel   |
| 4 | ROAS                       | `LTV-proxy / CAC`                                                                           |
| 5 | A/B test                   | Simulated experiment, z-test / p-value in Python (standalone; never mixed into 1–4)         |

## Key finding

> *(Placeholder — filled once Phase 2 is complete and the four marts
> are all populated. Expected shape: "Channel X looks best on CAC but
> worst on repeat purchase rate and LTV, so its real ROAS is lower
> than channel Y — recommend reallocating N% of budget from X to Y".
> The 2017-11 CAC snapshot in `docs/PROJECT_LOG.md` already hints at
> Organic's suspicious cheapness on CAC alone.)*

## Live dashboard

> *(Tableau Public link — placeholder until Phase 5.)*

## Run it locally

Prereqs: a GCP project with BigQuery API enabled and a dataset
`olist_raw` in region **EU**, plus `gcloud` CLI authenticated
(`gcloud auth login` for `bq` + `gcloud auth application-default login`
for dbt / Python libraries).

The Olist CSVs are downloaded manually from
[Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
into `data/olist/`. See [`docs/kaggle_download.md`](docs/kaggle_download.md).

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

# 3. Rebuild the dbt marts.
source .venv/bin/activate
cd dbt && dbt run           # materializes 8 tables in olist_dbt

# 4. Ad hoc verification query (rule-of-three step 1 — matches mart exactly).
bq query --use_legacy_sql=false --location=EU --format=pretty \
  --nouse_cache < sql/adhoc/cac_by_channel_one_month.sql
```

## What's where

| Path                              | Purpose                                                    |
|-----------------------------------|------------------------------------------------------------|
| `CLAUDE.md`                       | Fixed project brief (scope, metrics, phases — do not edit) |
| `docs/PROJECT_LOG.md`             | Decision log + rule-of-three log + current status          |
| `docs/kaggle_download.md`         | Manual Olist download steps                                |
| `docs/bigquery_setup.md`          | BigQuery / gcloud setup notes                              |
| `.claude/skills/marketing-metrics/` | Locked metric definitions (Claude-agent-discoverable skill) |
| `sql/adhoc/`                      | One-off verified queries (rule-of-three step 1)            |
| `dbt/models/`                     | staging → intermediate → marts (rule-of-three step 2)      |
| `python/`                         | ad_spend generator, GitHub API pull (Phase 4)              |
| `.github/workflows/`              | Cron schedule (Phase 4)                                    |
| `data/olist/`, `data/synthetic/`  | Local CSVs (gitignored)                                    |
