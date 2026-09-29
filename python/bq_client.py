"""Shared BigQuery client factory.

Reads project id and location from `.env` (or the environment) and returns
a `bigquery.Client` bound to them. Kept intentionally tiny — every script
that touches BigQuery goes through this so the project + region are set
in exactly one place.

Auth is delegated to Application Default Credentials (ADC), set up locally
via `gcloud auth application-default login`. No key files are read here.
"""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import bigquery

REPO_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(REPO_ROOT / ".env")


def get_config() -> dict[str, str]:
    project = os.getenv("GCP_PROJECT_ID")
    location = os.getenv("BQ_LOCATION", "EU")
    raw = os.getenv("BQ_RAW_DATASET", "olist_raw")
    if not project:
        raise RuntimeError(
            "GCP_PROJECT_ID is not set. Copy .env.example to .env and fill it in."
        )
    return {"project": project, "location": location, "raw_dataset": raw}


def get_client() -> bigquery.Client:
    cfg = get_config()
    # `location` on the Client is a default for jobs; queries/loads
    # inherit it unless overridden. Matches the dataset region.
    return bigquery.Client(project=cfg["project"], location=cfg["location"])


if __name__ == "__main__":
    # Smoke test: prove auth works and list datasets in the project.
    cfg = get_config()
    client = get_client()
    print(f"project={cfg['project']} location={cfg['location']}")
    datasets = list(client.list_datasets())
    if datasets:
        for ds in datasets:
            print(f"  dataset: {ds.dataset_id}")
    else:
        print("  (no datasets yet)")
