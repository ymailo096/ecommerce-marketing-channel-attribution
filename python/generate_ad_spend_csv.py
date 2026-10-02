"""Generate the synthetic ad_spend CSV using only Python stdlib.

Grain: (channel, month), 4 channels x 26 months = 104 rows, seed=42
so the CSV is reproducible bit-for-bit across runs. Writes to
`data/synthetic/ad_spend.csv` at the repo root.

Deliberately uses only `csv` + `random` + `datetime` (no numpy, no
pandas) so it works on a bare Python 3 install with no venv or pip.
The bq CLI takes it from there:

    bq load --source_format=CSV --skip_leading_rows=1 --location=EU \\
      --replace --schema="channel:STRING,month:DATE,spend_brl:NUMERIC" \\
      olist_raw.ad_spend data/synthetic/ad_spend.csv

Spend ranges are picked so Organic ends up by far the cheapest on
CAC. Because LTV is flat across channels by design (channel is
independent of purchase behaviour — see int_customer_channel.sql),
that cheap CAC carries straight through to a far higher ROAS too;
it does not reverse. The "misleading metric" this project exposes
isn't a CAC-vs-ROAS ranking flip — it's that an unusually cheap
CAC should be read as a data-quality flag (likely under-reported
spend), not a genuine efficiency win. See README's "Methodological
lesson" section.
"""
from __future__ import annotations

import csv
import random
from datetime import date
from pathlib import Path

CHANNELS = ["Organic", "Google Ads", "Facebook/Instagram Ads", "Email/Referral"]

SPEND_RANGES_BRL: dict[str, tuple[int, int]] = {
    "Organic":                (500, 1_500),   # SEO/content baseline
    "Google Ads":             (8_000, 15_000),
    "Facebook/Instagram Ads": (5_000, 10_000),
    "Email/Referral":         (500, 2_000),
}

MONTH_START = date(2016, 9, 1)
MONTH_END = date(2018, 10, 1)
SEED = 42

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = REPO_ROOT / "data" / "synthetic" / "ad_spend.csv"


def month_range(start: date, end: date) -> list[date]:
    y, m, out = start.year, start.month, []
    while (y, m) <= (end.year, end.month):
        out.append(date(y, m, 1))
        m += 1
        if m == 13:
            m, y = 1, y + 1
    return out


def main() -> None:
    r = random.Random(SEED)
    months = month_range(MONTH_START, MONTH_END)

    rows = []
    for channel in CHANNELS:
        lo, hi = SPEND_RANGES_BRL[channel]
        for month in months:
            rows.append(
                {
                    "channel": channel,
                    "month": month.isoformat(),
                    "spend_brl": round(r.uniform(lo, hi), 2),
                }
            )

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["channel", "month", "spend_brl"])
        w.writeheader()
        w.writerows(rows)

    print(
        f"wrote {OUT_PATH.relative_to(REPO_ROOT)} — "
        f"{len(rows)} rows ({len(CHANNELS)} channels x {len(months)} months)"
    )


if __name__ == "__main__":
    main()
