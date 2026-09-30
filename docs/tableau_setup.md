# Tableau Public dashboard — setup

Phase 5. Builds a public dashboard on top of the four marts already
in BigQuery, then paste the resulting URL into README's "Live
dashboard" section.

Nothing in this guide can run headlessly — Tableau Desktop + Tableau
Public are GUI-only, and publishing requires signing into your
Tableau Public account interactively. This doc walks through the
minimum path.

## Prereqs

- **Tableau Desktop** — you already have `~/Documents/My Tableau
  Repository/` from a previous project, so it's installed.
- **Tableau Public account** — free, `public.tableau.com/en-us/s/`.
  If you don't have one, sign up (email + password).
- **BigQuery connection**: Tableau supports Google BigQuery natively.
  Connects via OAuth to the same Google account that owns
  `ecommerce-channel-attribution`. No service account needed for the
  dashboard — Tableau Public dashboards refresh on demand from the
  user's own credential when they open the file locally, and the
  published version is a static snapshot.

## Connect Tableau to BigQuery

1. Open Tableau Desktop → **Connect** → **To a Server** → **Google
   BigQuery**.
2. Sign in with `ymailo096@gmail.com`; consent to Tableau's OAuth
   request (same shape as any other Google OAuth dialog).
3. **Billing project**: `ecommerce-channel-attribution`.
4. **Dataset**: `olist_dbt`.
5. Drag these four tables onto the canvas as separate data sources
   (or one blended source — either works; separate is simpler for a
   first pass):
   - `mart_cac_by_channel`
   - `mart_ltv_by_channel`
   - `mart_repeat_rate_by_channel`
   - `mart_roas_by_channel`  ← the single most useful one; contains
     everything joined already, one row per (channel, month).

If Tableau asks for a location it should be `EU` (matches the
dataset's region — anything else and BigQuery refuses to join).

## Minimum dashboard for the "Live dashboard" link

Aim: one page, four things a portfolio reviewer can absorb in ~20 s.
Use `mart_roas_by_channel` as the primary source — every field is
already on it.

1. **KPI row across the top** (four small tiles, one per channel):
   channel name, latest-month cohort size, CAC, LTV/customer, ROAS.
   Filter to `month = 2017-11-01` for the "Black Friday snapshot"
   framing that the README already uses; or make month a dropdown
   filter so a viewer can pick.
2. **Time-series line chart** (bottom-left half):
   - X: `month`
   - Y: `roas` (dual axis with `cac_brl` optional)
   - Color: `channel`
   - Filter to months where every channel has data
     (`month >= 2016-12-01` is a safe cutoff — earlier months have
     tiny cohorts and noisy ROAS).
3. **Bar chart** (bottom-right half):
   - X: `channel`
   - Y: `roas` for the selected month
   - Colored by channel
4. **Text annotation** anywhere visible:
   > Channel assignment and ad_spend are synthetic. See project
   > README for the "why ROAS ordering ≠ channel efficiency" caveat.

## Publish

1. **Server → Tableau Public → Save to Tableau Public…**
2. Sign in with your Tableau Public account.
3. Name it e.g. `ecommerce-channel-attribution`; publish.
4. Tableau Public opens the browser to the published dashboard URL.
   Copy that URL.

## Paste the URL back

Edit two places in the repo:

- `README.md` → the `## Live dashboard` section → replace the
  placeholder line with `[Live dashboard on Tableau Public](URL)`.
- `docs/PROJECT_LOG.md` → the `Current status → Phase 5` line →
  mark ✅ with the URL and the publish date.

Then `git add -A && git commit -m "docs: Tableau Public dashboard
live" && git push`.

## Refresh strategy

Tableau Public **does not refresh from BigQuery** automatically — it
publishes an extract. So the published dashboard is a snapshot as
of when you last hit "Save to Tableau Public". Options:

- **Manual re-publish once every couple of weeks** — matches this
  project's cadence and the freeze framing.
- **Tableau Public "keep data fresh" toggle**: only works for a
  handful of connectors, BigQuery isn't one of them via Tableau
  Public (only Tableau Server / Cloud offer scheduled refresh
  against BigQuery). Not going to help here.

For a portfolio piece, one manual re-publish after a couple of
weeks of accumulated cron runs (so the time-series is visibly non-
trivial) is enough. Don't over-engineer it.
