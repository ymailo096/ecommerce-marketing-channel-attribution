# Project Status — Working Notes

Live, ephemeral status of what's set up, what's blocked, and what
constraints Claude Code needs to respect in the next session. This
complements the fixed brief in `CLAUDE.md`; when they conflict, the
brief wins on scope/metrics, this file wins on current environment.

Last updated: 2026-09-29.

## Environment

- **Python 3.9** is the system Python. Google's libraries print a
  FutureWarning ("end of life"), but everything works. If we hit a
  hard blocker later, migrating to Python 3.11+ via Miniconda (no
  admin password required) is the fallback.
- **`.venv/`** at the repo root holds the Python deps. Activate with
  `source .venv/bin/activate`. Pinned in `requirements.txt`.
- **No Homebrew**, **no gcloud CLI** installed as of this note.
- Repo is `git init`-ed but **has no GitHub remote yet**.

## BigQuery — Sandbox mode (no billing)

Billing is deliberately **not** attached to the GCP project
`ecommerce-channel-attribution`. This forces BigQuery Sandbox mode,
which imposes:

- **No CTAS** (`CREATE TABLE AS SELECT`) — that's why dbt is deferred
  to Phase 2 (dbt's table materializations use CTAS).
- **No DML** (`INSERT`, `UPDATE`, `MERGE`, `DELETE`).
- **No streaming inserts** (`insertAll` API).
- **Batch LOAD jobs are fine** — `load_table_from_file` and
  `load_table_from_dataframe` both work.
- Plain `SELECT` queries are fine.
- Tables auto-expire after 60 days and the limit can't be extended in
  sandbox — re-load if you come back after two months.

**Practical rule for now:** every write to BigQuery goes through a LOAD
job in a Python script. Anything that would need to persist a query
result (marts, materialized views, dbt models) waits for Phase 2.

## What's ready

- `python/bq_client.py` — reads `.env`, returns a `bigquery.Client`
  bound to project + region.
- `python/create_dataset.py` — creates `olist_raw` in `EU`, idempotent.
- `python/load_olist_raw.py` — batch-LOAD the four Olist CSVs
  (orders, order_items, order_payments, customers) into `olist_raw`.
- `python/generate_ad_spend.py` — build the synthetic ad_spend
  DataFrame (seeded, channel + month grain, BRL) and LOAD it into
  `olist_raw.ad_spend`.
- `sql/adhoc/cac_by_channel_one_month.sql` — the ad hoc CAC query
  (rule-of-three step 1).
- `python/run_adhoc_cac.py` — runs the SQL against BigQuery and prints
  the result.

## What's blocked on the user

- Install `gcloud` CLI (macOS installer; needs admin password) →
  `gcloud auth application-default login`. Without ADC, nothing in
  `python/` can talk to BigQuery.
- Download Olist CSVs from Kaggle → put under `data/olist/`
  (see `docs/kaggle_download.md`).

## What's blocked on billing (Phase 2)

- dbt setup (`~/.dbt/profiles.yml`, `dbt/dbt_project.yml`).
- Any table materialization / persisted mart.
- Views may work in sandbox but haven't been tested here.

## Playbook once user unblocks the above

```bash
cd /Users/admin/Documents/ecommerce-marketing-attribution
source .venv/bin/activate

# 1. verify auth
python python/bq_client.py

# 2. create raw dataset
python python/create_dataset.py

# 3. load Olist CSVs (requires data/olist/ populated)
python python/load_olist_raw.py

# 4. generate + load synthetic ad_spend
python python/generate_ad_spend.py

# 5. run the ad hoc CAC query and eyeball the result
python python/run_adhoc_cac.py
```
