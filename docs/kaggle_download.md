# Manual Olist download (no Kaggle CLI needed)

We don't have Kaggle API credentials set up on this machine, and the
project shouldn't strictly need automation for the download — it's a
one-off. Manual steps below take ~2 minutes.

## Steps

1. Open https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
2. If you're not already signed in to Kaggle, sign in (free account).
3. Click the **Download** button (top right) → downloads a single ZIP
   named something like `archive.zip` (~45 MB).
4. Unzip it to `data/olist/` inside the repo root, so the layout is:

   ```
   data/olist/
     ├── olist_customers_dataset.csv
     ├── olist_geolocation_dataset.csv
     ├── olist_order_items_dataset.csv
     ├── olist_order_payments_dataset.csv
     ├── olist_order_reviews_dataset.csv
     ├── olist_orders_dataset.csv
     ├── olist_products_dataset.csv
     ├── olist_sellers_dataset.csv
     └── product_category_name_translation.csv
   ```

   The load script (`python/load_olist_raw.py`) only ingests four of
   these — orders, order_items, order_payments, customers — but you can
   safely leave all nine in `data/olist/`; the extras are ignored.

5. `.gitignore` already excludes `data/*.csv`, so the CSVs won't be
   committed.

## Sanity check

From the repo root:

```bash
ls data/olist/olist_orders_dataset.csv \
   data/olist/olist_order_items_dataset.csv \
   data/olist/olist_order_payments_dataset.csv \
   data/olist/olist_customers_dataset.csv
```

All four paths should exist. If any is missing, the unzip put the files
elsewhere — move them into `data/olist/` and re-run the check.

## Why not the Kaggle API?

Automating the download via `pip install kaggle` + `kaggle datasets
download olistbr/brazilian-ecommerce` needs a `~/.kaggle/kaggle.json`
API token, which:

- Is a long-lived credential I can't create on your behalf.
- Would sit next to the repo for a benefit (one-time re-download) that
  doesn't recur — Olist is a static snapshot, not a live source.

If we later need a fresh copy programmatically (e.g. from CI), the
Kaggle CLI can be set up then; for now, the manual download is simpler
and safer.
