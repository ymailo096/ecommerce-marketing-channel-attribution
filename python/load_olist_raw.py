"""Load Olist CSVs into `olist_raw` via batch LOAD jobs.

Loads exactly the four tables the CAC analysis needs — orders,
order_items, order_payments, customers. Other Olist tables (products,
sellers, geolocation, reviews) are ignored on purpose: the locked scope
in PROJECT_BRIEF.md §5 doesn't use them.

Uses `load_table_from_file` (batch LOAD job) — NOT `CREATE TABLE AS
SELECT`, which requires billing (BigQuery Sandbox blocks CTAS).

Assumes the CSVs live at `data/olist/*.csv` at the repo root — download
them manually from Kaggle (see docs/kaggle_download.md).
"""
from __future__ import annotations

import sys
from pathlib import Path

from google.cloud import bigquery

from bq_client import get_client, get_config

REPO_ROOT = Path(__file__).resolve().parents[1]
OLIST_DIR = REPO_ROOT / "data" / "olist"

# Kaggle filename → BigQuery table name. Kept explicit so a stray extra
# CSV in data/olist/ can't accidentally get loaded.
TABLES = {
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_customers_dataset.csv": "customers",
}


def load_one(client: bigquery.Client, csv_path: Path, table_id: str) -> None:
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,  # Olist schemas are stable and small; autodetect is fine here.
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    with csv_path.open("rb") as fh:
        job = client.load_table_from_file(fh, table_id, job_config=job_config)
    job.result()  # raises on failure
    table = client.get_table(table_id)
    print(f"  loaded {csv_path.name} → {table_id}  ({table.num_rows:,} rows)")


def main() -> None:
    cfg = get_config()
    client = get_client()

    if not OLIST_DIR.exists():
        sys.exit(
            f"missing {OLIST_DIR} — download Olist CSVs from Kaggle first "
            f"(see docs/kaggle_download.md)"
        )

    missing = [name for name in TABLES if not (OLIST_DIR / name).exists()]
    if missing:
        sys.exit(
            "missing Olist CSVs in data/olist/: "
            + ", ".join(missing)
            + " — see docs/kaggle_download.md"
        )

    for csv_name, table_name in TABLES.items():
        table_id = f"{cfg['project']}.{cfg['raw_dataset']}.{table_name}"
        load_one(client, OLIST_DIR / csv_name, table_id)


if __name__ == "__main__":
    main()
