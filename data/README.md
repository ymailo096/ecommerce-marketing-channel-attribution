# `data/`

What's here, what isn't, and why.

## `olist/`: raw Olist CSVs (not committed)

The Brazilian e-commerce dataset from Kaggle:
`olistbr/brazilian-ecommerce`. Nine CSVs totalling ~120 MB. Not
committed, since it's a third-party dataset that's trivially
re-fetchable and shouldn't be mirrored in the repo. Download it
manually with the steps in
[`docs/kaggle_download.md`](../docs/kaggle_download.md), then load
the four tables we use (`orders`, `customers`, `order_items`,
`order_payments`) into BigQuery with the `bq load` loop in
[`README.md`](../README.md) or with
[`python/load_olist_raw.py`](../python/load_olist_raw.py).

## `synthetic/ad_spend.csv`: generated, not committed

The synthetic ad-spend table at `(channel, month)` grain. 104 rows,
seed = 42, deterministic, so anyone running
[`python/generate_ad_spend_csv.py`](../python/generate_ad_spend_csv.py)
gets a byte-identical file. Not committed because it regenerates in
under a second from a stdlib-only script; keeping it in git would
only add noise if the spend ranges ever change.

## `tableau_export/marts.csv`: single combined mart, **committed**

One flat CSV, 91 rows × 10 columns, at `(channel, month)` grain.
The output of a 4-way INNER JOIN of the dbt marts
(`mart_cac_by_channel`, `mart_ltv_by_channel`,
`mart_repeat_rate_by_channel`, `mart_roas_by_channel`) on
`(channel, month)`. Columns:

| Column                 | From                                 |
|------------------------|--------------------------------------|
| `channel`              | all four (join key)                  |
| `month`                | all four (join key)                  |
| `new_customers`        | `mart_cac_by_channel.new_customer_count` |
| `spend_brl`            | `mart_cac_by_channel.spend_brl`      |
| `cac_brl`              | `mart_cac_by_channel.cac_brl`        |
| `ltv_total_brl`        | `mart_ltv_by_channel.ltv_total_brl`  |
| `ltv_per_customer_brl` | `mart_ltv_by_channel.ltv_per_customer_brl` |
| `repeaters`            | `mart_repeat_rate_by_channel.repeaters` |
| `repeat_rate`          | `mart_repeat_rate_by_channel.repeat_rate` |
| `roas`                 | `mart_roas_by_channel.roas`          |

**Why committed**: two reasons that both apply.
1. **Portfolio visibility**: a reviewer browsing the repo on GitHub
   can open this file and see the actual mart numbers without
   needing BigQuery access.
2. **Tableau Public feed**: Tableau Public Desktop (the free
   variant Tableau Public accepts uploads from) has no BigQuery
   connector, only flat-file sources. The dashboard reads this file
   directly, so having the joined mart as one CSV means Tableau
   doesn't have to re-create the (channel, month) joins on its
   side. See [`docs/tableau_setup.md`](../docs/tableau_setup.md)
   for the publish flow.

**Why one file, not four**: `mart_roas_by_channel` is already the
3-way INNER JOIN of CAC + LTV + repeat, so the four underlying
marts share the same `(channel, month)` grain and the join is
unambiguous. Shipping one flat table instead of four avoids making
every Tableau viewer re-derive the join.

**Regenerate** after any model change:

```bash
source .venv/bin/activate
python python/export_marts_to_csv.py       # overwrites marts.csv
```

Deterministic given static Olist plus seeded ad_spend; regeneration
should produce bit-identical output until the dbt models change.
