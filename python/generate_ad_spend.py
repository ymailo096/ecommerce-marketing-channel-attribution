"""Generate the synthetic `ad_spend` table and load it into `olist_raw`.

Grain: (channel, month) — deliberately COARSER than order-level rows.
This mismatch is the whole point (PROJECT_BRIEF.md §3.3): joining `ad_spend`
directly onto orders would fan out spend across every order row and
silently inflate CAC. Every metric that reads `ad_spend` must first
aggregate customers/orders to (channel, month) and only then join.

Design choices:
- Seed = 42, fixed. Same seed → same numbers, so anyone re-running the
  pipeline gets identical results.
- Currency = BRL, to match `order_payments.payment_value` in Olist.
- Monthly ranges vary by channel to make the analysis interesting:
    * Organic ~zero spend (SEO/content baseline only) — CAC on Organic
      should be near-zero on paper, which is exactly the "misleading
      metric" the project is designed to expose.
    * Google Ads = highest paid budget.
    * Facebook/Instagram Ads = medium-high.
    * Email/Referral = small (tool + referral bonuses).
- Range = 2016-09 through 2018-10 — Olist's known data range. Kept in
  code (not queried live) so this script is self-contained and can run
  before the Olist tables exist.
"""
from __future__ import annotations

from datetime import date

import numpy as np
import pandas as pd
from google.cloud import bigquery

from bq_client import get_client, get_config

CHANNELS = ["Organic", "Google Ads", "Facebook/Instagram Ads", "Email/Referral"]

# Monthly spend ranges (BRL). Chosen so ROAS ends up ordered differently
# from CAC — Organic looks best by CAC but not by ROAS once LTV is folded
# in. That contrast is the payoff of the project.
SPEND_RANGES_BRL: dict[str, tuple[int, int]] = {
    "Organic": (500, 1_500),
    "Google Ads": (8_000, 15_000),
    "Facebook/Instagram Ads": (5_000, 10_000),
    "Email/Referral": (500, 2_000),
}

MONTH_START = date(2016, 9, 1)
MONTH_END = date(2018, 10, 1)
SEED = 42


def month_range(start: date, end: date) -> list[date]:
    months = []
    y, m = start.year, start.month
    while (y, m) <= (end.year, end.month):
        months.append(date(y, m, 1))
        m += 1
        if m == 13:
            m, y = 1, y + 1
    return months


def build_ad_spend() -> pd.DataFrame:
    rng = np.random.default_rng(SEED)
    months = month_range(MONTH_START, MONTH_END)

    rows = []
    for channel in CHANNELS:
        lo, hi = SPEND_RANGES_BRL[channel]
        # Uniform sample per month — simple, reproducible, avoids fake
        # seasonality we can't defend.
        spends = rng.uniform(lo, hi, size=len(months))
        for month, spend in zip(months, spends):
            rows.append(
                {
                    "channel": channel,
                    "month": month,
                    "spend_brl": round(float(spend), 2),
                }
            )
    df = pd.DataFrame(rows)
    return df


def load_to_bq(df: pd.DataFrame) -> None:
    cfg = get_config()
    client = get_client()
    table_id = f"{cfg['project']}.{cfg['raw_dataset']}.ad_spend"

    # Force schema types instead of autodetect: `month` should be DATE
    # (first day of month), not inferred as TIMESTAMP, so downstream
    # joins on DATE_TRUNC work cleanly.
    schema = [
        bigquery.SchemaField("channel", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("month", "DATE", mode="REQUIRED"),
        bigquery.SchemaField("spend_brl", "NUMERIC", mode="REQUIRED"),
    ]
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()
    table = client.get_table(table_id)
    print(
        f"loaded ad_spend → {table_id}  "
        f"({table.num_rows:,} rows, "
        f"{len(CHANNELS)} channels × {df['month'].nunique()} months)"
    )


def main() -> None:
    df = build_ad_spend()
    print("preview:")
    print(df.head(8).to_string(index=False))
    print(f"total spend by channel (BRL):")
    print(df.groupby("channel")["spend_brl"].sum().round(0).to_string())
    load_to_bq(df)


if __name__ == "__main__":
    main()
