# E-commerce Marketing Channel Attribution — Project Brief

> Paste this whole file as the first message to Claude Code, or save it as
> `PROJECT_PLAN.md` (or `CLAUDE.md`) in the repo root so Claude Code reads it
> automatically as project context.

## 1. Business Question (the one thing this project must answer)

An online store spends budget across several marketing channels. Which
channel is actually most efficient once you look past the cost of the first
order — i.e. how much revenue does a customer generate over the following
months after acquisition?

Every metric and every SQL model in this project exists to answer this one
question. Do not add analysis that doesn't serve it.

## 2. Locked Scope — do not expand without explicit sign-off

**In scope (v1):**
- Olist Brazilian e-commerce dataset (real orders/payments/freight/customers)
- A daily-refreshed "live" data source via the GitHub API (stars/forks/
  contributors for a couple of repos)
- A synthetic `ad_spend` table (see §4)
- SQL + dbt modeling in BigQuery
- One simulated A/B test with a significance test in Python
- Scheduling via GitHub Actions (cron)
- A Tableau Public dashboard
- A GitHub README + (optionally) a mirrored Notion page

**Explicitly out of scope for v1** (revisit only if there is spare time
at the very end):
- Airflow
- Any ML / forecasting model
- n8n (if added later, it is a thin notification layer on top of the
  existing pipeline — never a replacement for the GitHub Actions cron core)
- Power BI (Tableau only)

## 3. Data Sources

1. **Olist dataset** (Kaggle, real anonymized Brazilian marketplace data):
   orders, order_items, order_payments, customers, order_reviews.
2. **GitHub API**: a small Python script pulls stars/forks/contributor counts
   for a few chosen repos daily — this is the genuinely "live" piece that
   proves the pipeline runs on a real schedule, not a one-off snapshot.
3. **Synthetic `ad_spend` table**: generated with a fixed random seed
   (reproducible), at **channel + month** granularity — deliberately coarser
   than order-level. This granularity mismatch is intentional: it forces
   correct join/aggregation logic (aggregate customers to channel+month
   *before* joining to spend, never join spend directly to the order-level
   table) and mirrors a fan-out trap worth documenting in the README.

## 4. Channel Assignment Logic

Olist has no channel field, so channel is a synthetic attribute assigned to
each **customer**, fixed at their first-purchase date (their acquisition
channel):

- Deterministic hash of `customer_unique_id` → one of 4 channels, so the
  same customer always lands in the same channel (no separate mapping table
  needed, fully reproducible).
- Weighted, not uniform, to look realistic:
  - Organic / Direct — ~40%
  - Google Ads — ~25%
  - Facebook / Instagram Ads — ~20%
  - Email / Referral — ~15%

## 5. Locked Metrics — closed list, do not add more

1. **CAC by channel** = `ad_spend(channel, month) / count(new customers of
   that channel acquired in that month)`. Must be computed after aggregating
   new customers to channel+month grain — joining ad_spend straight onto the
   order-level table will silently inflate spend via fan-out.
2. **Repeat purchase rate (90-day cohort)** = % of a channel's first-
   purchase-month cohort that placed a second order within 90 days of their
   first order.
3. **LTV-proxy (90 days)** = `sum(order_payments.payment_value)` within 90
   days of each customer's first order, aggregated by channel.
4. **ROAS** = LTV-proxy / CAC — the final channel comparison metric.
5. **A/B test** (separate, standalone mini-case — do not mix into the
   channel analysis above): simulate an experiment (e.g. a checkout change),
   compute statistical significance in Python (z-test / p-value).

## 6. Definition of Done (the project is not finished without all three)

- A one-page written insight in the style: "channel X looks best on CAC but
  worst on repeat purchase rate and LTV, so its real ROAS is lower than
  channel Y — recommend reallocating N% of budget from X to Y, and here is
  why." Backed by the actual numbers from the marts.
- A working Tableau Public dashboard on top of the marts layer.
- Automation that has actually run on a schedule (GitHub Actions cron) for
  at least a couple of weeks, with a visible run history as proof.

## 7. Phases

1. **Data** — load Olist as the core business tables; write the GitHub API
   pull script; generate the synthetic `ad_spend` table; assign channel per
   customer.
2. **Modeling (SQL/dbt)** — staging (raw tables as-is) → intermediate
   (granularity reconciliation, cohort = first-purchase month) → marts
   (repeat-purchase rate by cohort, LTV-proxy, CAC/ROAS by channel).
   Document *why* any UNION ALL / aggregation choice was made, not just what
   it does.
3. **A/B test** — simulate the experiment, compute significance in Python.
4. **Automation** — GitHub Actions cron runs the GitHub API pull + `dbt run`
   on a schedule for real, over multiple weeks. n8n (optional, later) sits
   only at the notification/delivery end (e.g. posting a summary to Slack),
   never replaces this core.
5. **Visualization** — Tableau Public dashboard over the marts: retention
   curve, LTV/ROAS by channel, funnel.
6. **Documentation** — GitHub README explaining the architecture and every
   non-obvious decision; optionally mirror the same "why this, not that"
   reasoning in Notion.

## 8. Working Conventions

- All code comments and variable names in English (this repo is for a
  public portfolio).
- Document every non-obvious technical decision inline or in the README —
  "why this, not that," not just what the code does.
- Before writing any join, explicitly check granularity / fan-out risk.
  `ad_spend` is intentionally coarser-grained than `orders` — never join it
  directly at order level.
- Follow the rule of three: first compute a metric ad hoc and manually
  verify it's correct, second write down the exact logic as a spec, third
  automate it. Do not automate a calculation that hasn't been manually
  verified first.
- If a requirement is ambiguous, ask before generating a large chunk of
  code rather than guessing.

## 9. Suggested Repo Structure

```
/sql/          -- staging / intermediate / marts SQL (or dbt models)
/python/       -- GitHub API pull script, ad_spend generator, A/B test stats
/dbt/          -- dbt project (if used instead of raw SQL folders)
/.github/workflows/  -- the cron workflow(s)
README.md
```

## 10. Immediate First Task

Rule-of-three step 1 for CAC: write a single ad hoc SQL query that computes
CAC by channel for **one specific month** using the raw/staging Olist
tables + assigned channel + the synthetic `ad_spend` table. Show the result
for manual verification before building anything else on top of it.
