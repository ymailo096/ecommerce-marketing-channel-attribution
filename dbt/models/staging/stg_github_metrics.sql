-- Grain: 1 row per (fetched_at, repo). Append-only time series
-- populated by python/github_metrics_pull.py once per scheduled run
-- of the daily cron. Not used by the CAC/LTV/ROAS marts — this is
-- the "genuinely live" evidence that the pipeline runs on a real
-- schedule (docs/PROJECT_BRIEF.md §3.2), and the source of any future
-- repo-momentum dashboards.

{{ config(materialized='table') }}

select
    fetched_at,
    repo,
    stars,
    forks,
    contributors
from {{ source('olist_raw', 'github_metrics') }}
