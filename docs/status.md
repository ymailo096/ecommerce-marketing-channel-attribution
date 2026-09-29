# Project Status — Working Notes

Live, ephemeral status of what's set up, what's blocked, and what
constraints Claude Code needs to respect in the next session. This
complements the fixed brief in `CLAUDE.md`; when they conflict, the
brief wins on scope/metrics, this file wins on current environment.

Last updated: 2026-09-29.

## Environment

- **Python 3.9** is the system Python. Google's libraries print a
  FutureWarning ("end of life"), but everything works — for our own
  Python scripts. gcloud CLI 587 refuses to run on Python 3.9 and
  needs 3.10+, which isn't installed here.
- **We routed around that by using Google Colab** for Phase 1 instead
  of local gcloud. See `notebooks/setup_and_cac.ipynb` — it does auth
  via `google.colab.auth.authenticate_user()` (no ADC, no service
  account key) and runs the whole Phase-1 pipeline (create dataset →
  load Olist → gen ad_spend → run CAC query) end-to-end.
- **`.venv/`** at the repo root holds the Python deps for the
  eventual local scripts (`python/*.py`). Activate with
  `source .venv/bin/activate`. Not used from Colab.
- **gcloud SDK** is extracted at `~/Downloads/google-cloud-sdk/` but
  broken (Python 3.9). Kept there in case we install Python 3.10+
  later. `install.sh` has already added the SDK's `bin/` to `~/.zshrc`.
- **No Homebrew**.
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

- **`notebooks/setup_and_cac.ipynb`** — the actively used Phase-1
  notebook, runs end-to-end in Colab. Auth, dataset creation, Olist
  load, ad_spend generation, and the ad hoc CAC query all in one file.
- `data/olist/` — all 9 Olist CSVs downloaded and ready to upload
  into Colab.
- `sql/adhoc/cac_by_channel_one_month.sql` — the ad hoc CAC query,
  kept in a plain .sql file too (inlined into the notebook when
  regenerated). This is the source of truth for the SQL.
- Local Python scripts (`python/bq_client.py`, `create_dataset.py`,
  `load_olist_raw.py`, `generate_ad_spend.py`, `run_adhoc_cac.py`) —
  functionally correct but currently unusable because local ADC isn't
  set up. Kept for the future when we have local BigQuery auth (e.g.
  Phase 2 with dbt).

## How to run Phase 1 (via Colab)

1. Open https://colab.research.google.com/ in the browser.
2. **File → Upload notebook** → pick
   `notebooks/setup_and_cac.ipynb` from this repo.
3. Run cells 1-3 (setup + auth). Cell 3 opens a Google OAuth dialog —
   sign in with the account that owns the
   `ecommerce-channel-attribution` GCP project.
4. Run cells 5-6 (create `olist_raw` dataset in EU).
5. Left sidebar → **Files** icon → **Upload** — upload these four
   from `data/olist/`:
   - `olist_customers_dataset.csv`
   - `olist_orders_dataset.csv`
   - `olist_order_items_dataset.csv`
   - `olist_order_payments_dataset.csv`
6. Run cell 8 (sanity check the uploads landed).
7. Run cells 10, 12, 13 (LOAD Olist tables, generate + LOAD ad_spend).
8. Run cells 15-16 (execute the CAC query, show the DataFrame).
9. Eyeball the manual-verification checklist at the end.

## What's blocked on billing (Phase 2)

- dbt setup (`~/.dbt/profiles.yml`, `dbt/dbt_project.yml`).
- Any table materialization / persisted mart.
- Views may work in sandbox but haven't been tested here.
- Local Python scripts under `python/` — need local ADC, which needs
  gcloud, which needs Python 3.10+. Deferred until we decide it's
  worth setting up (Colab may cover everything through Phase 3).
