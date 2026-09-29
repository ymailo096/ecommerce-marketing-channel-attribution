"""Run the ad hoc CAC-by-channel query and print the result.

Rule-of-three step 1: this is what we manually eyeball before promoting
CAC into a persisted mart. Nothing is written back to BigQuery.
"""
from __future__ import annotations

from pathlib import Path

from bq_client import get_client, get_config

REPO_ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = REPO_ROOT / "sql" / "adhoc" / "cac_by_channel_one_month.sql"


def main() -> None:
    cfg = get_config()
    client = get_client()

    sql_template = SQL_PATH.read_text()
    sql = sql_template.replace("{project}", cfg["project"]).replace(
        "{raw_dataset}", cfg["raw_dataset"]
    )

    print(f"running {SQL_PATH.relative_to(REPO_ROOT)} against {cfg['project']}")
    df = client.query(sql).result().to_dataframe()

    if df.empty:
        print("(no rows returned — check the data was loaded)")
        return

    print()
    print(df.to_string(index=False))
    print()
    print(
        f"total new customers this month: {int(df['new_customer_count'].sum())}"
    )
    print(f"total spend this month (BRL):   {float(df['spend_brl'].sum()):,.2f}")


if __name__ == "__main__":
    main()
