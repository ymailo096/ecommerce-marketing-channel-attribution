"""Export the four marts as one flat CSV for Tableau Public import.

Tableau Public Desktop (the free variant Tableau Public accepts
uploads from) has no BigQuery connector — only file-based sources
(CSV, JSON, Excel, PDF, Google Sheets). So the Tableau flow for
this project is: (a) run this script to snapshot the marts, (b)
point Tableau Public Desktop at the single CSV, (c) build the
workbook, (d) publish. No joins/relationships to set up on the
Tableau side — the join is done here, once.

Output: `data/tableau_export/marts.csv`.
Grain: (channel, month). 91 rows — only (channel, month) pairs
where all four marts have data; the 13 early-Olist months where
ad_spend exists but no customers were acquired are dropped (ROAS
is undefined for those). Column count: 10, listed in the SQL below.

Auth: Application Default Credentials — set by
`gcloud auth application-default login` locally, or by
`google-github-actions/auth` in CI. No keyfile handled here.
"""
from __future__ import annotations

from pathlib import Path

from google.cloud import bigquery

PROJECT_ID = "ecommerce-channel-attribution"
DATASET = "olist_dbt"
LOCATION = "EU"

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = REPO_ROOT / "data" / "tableau_export" / "marts.csv"

# 4-way INNER JOIN on (channel, month). mart_roas is itself a 3-way
# join of the other three, so this is slightly redundant on paper —
# but doing all four here makes the column provenance explicit for
# anyone reading the script, and we take `roas` directly from the
# mart that owns it rather than recomputing.
JOIN_SQL = f"""
SELECT
    cac.channel,
    cac.month,
    cac.new_customer_count                   AS new_customers,
    cac.spend_brl,
    cac.cac_brl,
    ltv.ltv_total_brl,
    ltv.ltv_per_customer_brl,
    rr.repeaters,
    rr.repeat_rate,
    roas.roas
FROM `{PROJECT_ID}.{DATASET}.mart_cac_by_channel`         AS cac
INNER JOIN `{PROJECT_ID}.{DATASET}.mart_ltv_by_channel`        AS ltv  USING (channel, month)
INNER JOIN `{PROJECT_ID}.{DATASET}.mart_repeat_rate_by_channel` AS rr   USING (channel, month)
INNER JOIN `{PROJECT_ID}.{DATASET}.mart_roas_by_channel`       AS roas USING (channel, month)
ORDER BY channel, month
"""


def main() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    df = client.query(JOIN_SQL).result().to_dataframe()
    df.to_csv(OUT_PATH, index=False)
    print(f"wrote {OUT_PATH.relative_to(REPO_ROOT)}  ({len(df)} rows, {len(df.columns)} cols)")
    print(f"columns: {list(df.columns)}")


if __name__ == "__main__":
    main()
