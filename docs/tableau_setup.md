# Tableau Public dashboard — setup

Phase 5. Builds a public dashboard on top of the four marts, then
pastes the resulting URL into README's "Live dashboard" section.

## Why we export to CSV first

Tableau Public Desktop (the free variant, the only one Tableau
Public accepts uploads from) has no BigQuery connector — the only
supported inputs are file-based (CSV, JSON, Excel, PDF, Google
Sheets). Live BigQuery inside Tableau needs the paid Tableau
Desktop, which won't publish to Tableau Public either. So the flow
here is:

1. Snapshot the marts to CSVs on disk.
2. Point Tableau Public Desktop at those CSVs.
3. Build the workbook.
4. Save to Tableau Public.

Steps 3–4 are GUI-only; nothing headless.

## Prereqs

- **Tableau Public Desktop** — free, download from
  `public.tableau.com/en-us/s/download`. The existing
  `~/Documents/My Tableau Repository/` folder was created by a
  previous install and is compatible.
- **Tableau Public account** — free sign-up at
  `public.tableau.com`.

## 1. Snapshot the marts to one combined CSV

Local prereq: `gcloud auth application-default login` and dbt has
been run at least once (so `olist_dbt.mart_*` exist). Then:

```bash
source .venv/bin/activate
python python/export_marts_to_csv.py
```

Writes one file to `data/tableau_export/marts.csv` — a 4-way INNER
JOIN of the four marts on `(channel, month)`. 91 rows × 10 columns,
all metrics in one flat table so Tableau doesn't need to set up
joins itself. Column list is in
[`data/README.md`](../data/README.md).

The file is committed to the repo as a static snapshot (it's a
deterministic output of dbt on Olist's static input, so it doesn't
drift). Re-run the script to refresh after any model change.

## 2. Import into Tableau Public Desktop

1. Open Tableau Public Desktop → **Connect** → **Text file**.
2. Pick `data/tableau_export/marts.csv`.
3. Tableau shows the schema preview. Confirm `month` is parsed as
   Date, not String. If it's String, right-click the field →
   **Change Data Type** → **Date**.

That's it — one data source, no join/relationship UI to configure
on the Tableau side.

## 3. Build the dashboard

Aim: one page, four things a portfolio reviewer can absorb in ~20 s.

1. **KPI row across the top** (four tiles, one per channel):
   `channel`, `new_customers`, `cac_brl`, `ltv_per_customer_brl`,
   `roas`. Filter to `month = 2017-11-01` for the "Black Friday
   snapshot" framing the README uses, or make month a dropdown so
   the viewer can pick.
2. **Time-series line chart** (bottom-left half):
   - X: `month`
   - Y: `roas`
   - Color: `channel`
   - Filter to months with meaningful cohorts. `month >=
     2017-01-01` is a safe cutoff — the earliest few months of
     Olist have single-digit cohort sizes per channel and the ROAS
     values there are noise. `marts.csv` includes those rows; you
     can spot them because `new_customers` there is `1`–`10`.
3. **Bar chart** (bottom-right half):
   - X: `channel`
   - Y: `roas` for the selected month
   - Color: `channel`
4. **Text annotation** somewhere visible:
   > Channel assignment and `ad_spend` are synthetic. See project
   > README for why ROAS ordering is not a channel-efficiency signal.

## 4. Publish

1. **File → Save to Tableau Public As…**
2. Sign in to your Tableau Public account.
3. Name it e.g. `ecommerce-channel-attribution`; save.
4. Tableau Public opens the browser to the published dashboard URL.
   Copy that URL.

## 5. Paste the URL back into the repo

Two places:

- `README.md` → the `## Live dashboard` section → replace the
  placeholder with `[Live dashboard on Tableau Public](URL)`.
- `docs/PROJECT_LOG.md` → the `Current status → Phase 5` line →
  mark ✅ with the URL and the publish date.

Then commit and push:

```bash
git add -A
git commit -m "docs: Tableau Public dashboard live"
git push
```

## 6. Refresh strategy

Because the source is a static CSV (not a live BigQuery
connection), the published dashboard doesn't auto-refresh. To
update after a code change to the marts:

```bash
python python/export_marts_to_csv.py   # regenerate marts.csv
# re-open the workbook in Tableau Public Desktop, then
# File → Save to Tableau Public As… → same name, overwrite
```

For the portfolio piece, one manual re-publish after a couple of
weeks of accumulated cron runs (so the time-series chart is
visibly non-trivial) is enough.
