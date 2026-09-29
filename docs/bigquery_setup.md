# BigQuery Access Plan

How the project reaches BigQuery from a local machine (dbt / SQL / Python)
and from the GitHub Actions cron. Written before any modeling work so we
don't discover the auth story mid-flight.

Environment on this Mac at the time of writing:
- Python 3.9 (system).
- No `gcloud`, no `bq`, no Homebrew installed.
- No GCP project yet.

## 1. Which BigQuery tier we're using

BigQuery has a permanent free tier that fits this project easily:
- 10 GB storage per month, free.
- 1 TB of query bytes scanned per month, free.

Olist is ~100 MB uncompressed and the marts we build on top of it are
smaller still, so both limits are far out of reach. **Even so, billing
must be enabled on the GCP project**: BigQuery refuses to run queries on
a project with no billing account attached, free tier or not. Attach a
card, then set a low **billing budget + alert** (e.g. \$1/month → email
alert at 50%) so an accidentally huge query doesn't quietly cost money.

## 2. GCP project + dataset — one-time setup (user does this)

Done in the GCP web console — I can't do these steps for you (they need
your Google account).

1. **Create a project** at https://console.cloud.google.com — suggested
   id: `ecommerce-attribution-<something-unique>`. Note the project id;
   dbt and Python both need it.
2. **Enable BigQuery API** for that project (Console → APIs & Services →
   Enable → search "BigQuery API").
3. **Attach a billing account** to the project (required even for free
   tier), then set a budget alert as above.
4. **Create a dataset** inside the project — suggested name
   `olist_raw`, **region: `EU` (multi-region)** — decided 2026-09-29.
   Every other dataset we add later (`olist_staging`, `olist_marts`,
   etc.) must be created in the same `EU` region: BigQuery cannot
   join tables across regions, and it silently fails with a
   "Not found: Dataset … was not found in location EU" error rather
   than doing a cross-region copy. Keeping raw isolated makes it
   obvious what came from the source vs. what we built.

## 3. Local auth — pick one of two paths

Two ways to let dbt / Python on this Mac talk to BigQuery. We only need
one; **path A is what we'll use unless you already have a preferred flow.**

### Path A — Application Default Credentials via `gcloud` (recommended)

Pros: no key file on disk, no secret to accidentally commit, standard
Google-recommended flow for local development.

1. Install the `gcloud` CLI (no Homebrew here → use the official installer:
   https://cloud.google.com/sdk/docs/install-sdk). Runs an interactive
   installer; ~5 min.
2. `gcloud init` → log in with the same Google account that owns the
   project, select the project.
3. `gcloud auth application-default login` → opens a browser, grants
   local libraries (dbt-bigquery, `google-cloud-bigquery`) permission to
   act as you. Credentials are stored under
   `~/.config/gcloud/application_default_credentials.json`; nothing
   project-local, nothing committed.
4. dbt profile then just points at the project + dataset; no `keyfile`
   entry needed.

### Path B — Service account JSON key

Only if path A is blocked for some reason (corporate policy, etc.).
Pros: nothing to install locally beyond Python libs. Cons: you're
managing a long-lived credential file on disk — easy to leak into git.

1. Console → IAM & Admin → Service Accounts → Create service account
   `dbt-local`.
2. Grant it roles: **BigQuery Data Editor** + **BigQuery Job User**
   (scoped to this project — no org-wide anything).
3. Create a JSON key for it, download to somewhere **outside** the repo,
   e.g. `~/.config/gcp/ecommerce-attribution-sa.json` — the repo's
   `.gitignore` already excludes `.env`, but a service-account JSON
   shouldn't live near the repo at all.
4. Set `GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcp/ecommerce-attribution-sa.json`
   in your shell profile.

## 4. Python + dbt install (local, once GCP is ready)

We'll use a project-local virtualenv so it's disposable:

```bash
cd /Users/admin/Documents/ecommerce-marketing-attribution
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install dbt-bigquery google-cloud-bigquery pandas
```

`.venv/` should be added to `.gitignore` before the first commit that
creates it (already covered by the general Python patterns we'll add).

## 5. dbt profile — where credentials actually resolve

dbt looks at `~/.dbt/profiles.yml` by default. Skeleton for path A
(no keyfile):

```yaml
ecommerce_attribution:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth              # uses ADC from `gcloud auth application-default login`
      project: <your-gcp-project-id>
      dataset: olist_staging     # dbt's default output dataset (dev)
      location: EU               # must match the dataset region from §2.4 — decided EU
      threads: 4
      timeout_seconds: 300
```

For path B, swap `method: oauth` for `method: service-account` and add
`keyfile: /Users/admin/.config/gcp/ecommerce-attribution-sa.json`.

`profiles.yml` lives outside the repo on purpose — it holds
environment-specific config, not project code. The project itself will
have a `dbt/dbt_project.yml` that references the profile name
`ecommerce_attribution`.

## 6. Loading Olist into BigQuery (once auth works)

After the Kaggle CSV zip is downloaded to `data/` (deferred — see brief §3.1):

```python
# python/load_olist_to_bq.py — skeleton, to be written later
from google.cloud import bigquery
client = bigquery.Client(project="<project-id>")
# For each CSV in data/olist/*.csv:
#   load_table_from_file into olist_raw.<table_name>
#   with autodetect=True, write_disposition=WRITE_TRUNCATE
```

Alternatively `bq load` from CLI — same result, less code. Decide when
we get there; both are fine.

## 7. GitHub Actions cron — auth story

The cron in `.github/workflows/` needs its own credentials — a local
`gcloud` login won't help. Standard approach:

1. Create a **second** service account, `github-actions-runner`, with the
   same BigQuery roles as path B above.
2. Store its JSON key as a repo secret `GCP_SA_KEY`.
3. In the workflow, use `google-github-actions/auth@v2` with
   `credentials_json: ${{ secrets.GCP_SA_KEY }}`.

Better alternative — **Workload Identity Federation** (no long-lived key
in a secret): configure once, and Actions authenticates via short-lived
tokens. Slightly more setup, materially safer. We'll pick between them
in the automation phase; not urgent now.

## 8. Verification — how we know auth works before writing models

Once path A or B is set up, one-liner check from the venv:

```bash
python -c "from google.cloud import bigquery; \
  print([d.dataset_id for d in bigquery.Client(project='<project-id>').list_datasets()])"
```

Should print `['olist_raw']` (or whatever datasets exist). If it prints
that, dbt will work too — same credentials, same library underneath.

## 9. Open items for the user

Before we can move forward on §10 of the brief (ad hoc CAC SQL):

- [x] Dataset region — **EU multi-region** (decided 2026-09-29).
- [ ] Create the GCP project + dataset (§2) — dataset in `EU`.
- [ ] Attach billing + set a \$1/month alert (§2.3).
- [ ] Choose path A or B for local auth (§3) and run through it.
- [ ] Send me the project id — I'll wire the dbt profile + Python load
      script to it (region is already fixed at `EU`).

Kaggle download itself stays deferred until this is in place; there's no
point downloading 45 MB of CSV until we know which BigQuery project it's
landing in.
