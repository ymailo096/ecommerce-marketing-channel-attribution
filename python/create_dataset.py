"""Create the raw dataset in BigQuery (idempotent).

Sandbox note: creating a dataset works in sandbox mode, but tables in a
sandbox project have a hard 60-day expiration and cannot be extended past
that. Once billing is attached (Phase 2), we can drop the expiration.
"""
from __future__ import annotations

from google.api_core.exceptions import Conflict
from google.cloud import bigquery

from bq_client import get_client, get_config


def main() -> None:
    cfg = get_config()
    client = get_client()

    dataset_id = f"{cfg['project']}.{cfg['raw_dataset']}"
    dataset = bigquery.Dataset(dataset_id)
    dataset.location = cfg["location"]
    dataset.description = (
        "Raw Olist tables + synthetic ad_spend, loaded via batch LOAD jobs. "
        "Managed by python/load_olist_raw.py and python/generate_ad_spend_csv.py."
    )

    try:
        client.create_dataset(dataset)
        print(f"created dataset {dataset_id} in {cfg['location']}")
    except Conflict:
        print(f"dataset {dataset_id} already exists — nothing to do")


if __name__ == "__main__":
    main()
