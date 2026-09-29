# Project Status — Working Notes

Live, ephemeral status of what's set up, what's blocked, and what
constraints Claude Code needs to respect in the next session. This
complements the fixed brief in `CLAUDE.md`; when they conflict, the
brief wins on scope/metrics, this file wins on current environment.

Last updated: 2026-09-29.

## Environment

- **System Python is 3.9.6** (both `/usr/bin/python3` and
  `/Library/Developer/CommandLineTools/usr/bin/python3`). Google Cloud
  SDK 587 needs Python 3.10+ for its bundled urllib3 (fails with
  `TypeError: unsupported operand type(s) for |: 'type' and 'type'` in
  urllib3's `_base_connection.py`).
- **Python 3.12.14 installed via `uv`** at
  `$HOME/.local/share/uv/python/cpython-3.12-macos-x86_64-none/bin/python3.12`
  — dedicated for gcloud/bq. System Python 3.9 stays untouched.
- **`~/.zshrc`** exports `CLOUDSDK_PYTHON` at that 3.12 path and adds
  `$HOME/.local/bin:$HOME/Downloads/google-cloud-sdk/bin` to `PATH`.
  Open a fresh terminal to get both. No pyenv, no Miniconda, no
  Homebrew.
- **Google Cloud SDK 587.0.0** at `~/Downloads/google-cloud-sdk/`.
  `gcloud` and `bq` both work.
- **Repo `.venv`** at repo root — Python 3.9 with google-cloud-bigquery
  pinned. Currently unused by the active pipeline (bq CLI does
  everything). Kept for future dbt / Python-scripted stages if we
  want them.
- Repo is `git init`-ed but **has no GitHub remote yet**.

## GCP auth

- `gcloud auth login` — user creds for `ymailo096@gmail.com` (needed
  for the `bq` CLI itself).
- `gcloud auth application-default login` — ADC in
  `~/.config/gcloud/application_default_credentials.json`
  (for any Python google-cloud library).
- `gcloud config set project ecommerce-channel-attribution` — default
  project (BQ needs this even when tables are fully qualified).
- Quota project attached to ADC — same project.

## BigQuery — Sandbox mode (no billing)

Billing is deliberately **not** attached to `ecommerce-channel-attribution`.
Sandbox limits:

- **No CTAS** (`CREATE TABLE AS SELECT`) — that's why dbt is deferred
  to Phase 2 (dbt's default materializations use CTAS).
- **No DML** (`INSERT`, `UPDATE`, `MERGE`, `DELETE`).
- **No streaming inserts** (`insertAll` API).
- **Batch LOAD jobs are fine** — that's what `bq load` uses.
- Plain `SELECT` queries are fine.
- Tables auto-expire after 60 days and the limit can't be extended in
  sandbox — re-load if you come back after two months.

## What's ready

- **`olist_raw`** dataset in region **EU** — created via BigQuery web
  console + confirmed via `bq ls`.
- **4 raw tables** loaded via `bq load` (batch LOAD jobs, sandbox-safe):
  `orders` (99,441), `customers` (99,441), `order_items` (112,650),
  `order_payments` (103,886). Row counts match public Olist.
- **`ad_spend`** table — synthetic, `channel + month` grain, 104 rows
  (4 channels × 26 months, 2016-09 to 2018-10). Generated with Python
  stdlib (`csv` + `random`, seed 42), no pip deps. Source at
  `data/synthetic/ad_spend.csv` (gitignored).
- **`sql/adhoc/cac_by_channel_one_month.sql`** — the ad hoc CAC query,
  now written with unqualified `olist_raw.<table>` refs so it runs
  directly via `bq query < sql/adhoc/cac_by_channel_one_month.sql`.

## Rule-of-three step 1 — verified 2026-09-29

Result of the CAC query for Olist's busiest month (2017-11, Black Friday):

| Channel | New customers | Spend (BRL) | CAC (BRL) |
|---|---|---|---|
| Organic | 2,907 | 1,149.88 | 0.40 |
| Email/Referral | 1,091 | 1,688.12 | 1.55 |
| Facebook/Instagram Ads | 1,386 | 6,145.24 | 4.43 |
| Google Ads | 1,920 | 12,932.00 | 6.74 |

Manual checks:
- Busiest month = 2017-11 matches Olist's known Black Friday peak.
- Channel weights: 39.8% / 26.3% / 19.0% / 14.9% — within 1pp of the
  designed 40/25/20/15 (7,304 new customers total).
- Organic CAC 17× lower than Google Ads — this is the "misleading
  metric" the project is designed to expose. Once LTV is folded in,
  the ranking should flip.

## Playbook — reproduce the whole thing

```bash
# Open a fresh terminal so .zshrc PATH / CLOUDSDK_PYTHON are picked up.
cd ~/Documents/ecommerce-marketing-attribution

# 1. sanity-check auth
bq ls --location=EU               # should print: olist_raw

# 2. (Re-)load the 4 Olist tables. Idempotent thanks to --replace.
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

# 3. Regenerate ad_spend.csv (stdlib) + load.
python3 -c "
import csv, random
from datetime import date
CH = ['Organic','Google Ads','Facebook/Instagram Ads','Email/Referral']
R  = {'Organic':(500,1500),'Google Ads':(8000,15000),
      'Facebook/Instagram Ads':(5000,10000),'Email/Referral':(500,2000)}
def months(s,e):
    y,m,o=s.year,s.month,[]
    while (y,m)<=(e.year,e.month):
        o.append(date(y,m,1)); m+=1
        if m==13: m,y=1,y+1
    return o
r=random.Random(42)
with open('data/synthetic/ad_spend.csv','w',newline='') as fh:
    w=csv.DictWriter(fh,['channel','month','spend_brl']); w.writeheader()
    for c in CH:
        lo,hi=R[c]
        for m in months(date(2016,9,1),date(2018,10,1)):
            w.writerow({'channel':c,'month':m.isoformat(),'spend_brl':round(r.uniform(lo,hi),2)})
"
bq load --source_format=CSV --skip_leading_rows=1 --location=EU --replace \
  --schema="channel:STRING,month:DATE,spend_brl:NUMERIC" \
  olist_raw.ad_spend data/synthetic/ad_spend.csv

# 4. Run the ad hoc CAC query.
bq query --use_legacy_sql=false --location=EU --format=pretty \
  --nouse_cache < sql/adhoc/cac_by_channel_one_month.sql
```

## What's blocked on billing (Phase 2)

- dbt setup and any table materialization / persisted mart.
- Views are TBD in sandbox — haven't tested.
- Local Python scripts under `python/` (`load_olist_raw.py` etc.) —
  functionally correct but currently redundant now that `bq` CLI does
  the same work with fewer moving parts. Kept for when dbt lands.

## What's deprecated / removed

- `notebooks/setup_and_cac.ipynb` — removed. The Colab detour added
  more fragility than the underlying gcloud-Python-version problem
  actually warranted (chained: browser automation, OAuth popup,
  10MB file_upload limit, forced gzip workaround, notebook
  auto-indent bug). Fixing the root cause — Python 3.12 for gcloud
  via `uv` — took two commands.
