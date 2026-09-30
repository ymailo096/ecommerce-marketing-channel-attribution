"""Dump the four marts to CSVs for Tableau Public import.

Tableau Public Desktop (the free variant of Tableau Desktop that
Tableau Public accepts uploads from) has no BigQuery connector —
only file-based sources (CSV, JSON, Excel, PDF, Google Sheets).
So the Tableau flow for this project is: (a) run this script to
snapshot the marts as CSVs, (b) point Tableau Public Desktop at
those CSV files, (c) build the workbook, (d) publish.

Output: `data/tableau_export/<mart>.csv`, one file per mart.

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
MARTS = [
    "mart_cac_by_channel",
    "mart_ltv_by_channel",
    "mart_repeat_rate_by_channel",
    "mart_roas_by_channel",
]

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = REPO_ROOT / "data" / "tableau_export"


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    for mart in MARTS:
        table_id = f"{PROJECT_ID}.{DATASET}.{mart}"
        sql = f"SELECT * FROM `{table_id}` ORDER BY channel, month"
        df = client.query(sql).result().to_dataframe()
        out_path = OUT_DIR / f"{mart}.csv"
        df.to_csv(out_path, index=False)
        print(f"wrote {out_path.relative_to(REPO_ROOT)}  ({len(df)} rows)")


if __name__ == "__main__":
    main()
