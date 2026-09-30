# Manual Olist download

Olist is a static snapshot on Kaggle, not a live source; the project
downloads it by hand once. Rationale for skipping the Kaggle CLI is
in `docs/PROJECT_LOG.md` under the `Kaggle download stays manual`
decision entry.

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

5. `.gitignore` excludes `data/**/*.csv` (with an explicit exception
   for `data/tableau_export/*.csv`, which we do commit as snapshots
   — see `docs/tableau_setup.md`). Olist CSVs stay local.

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
