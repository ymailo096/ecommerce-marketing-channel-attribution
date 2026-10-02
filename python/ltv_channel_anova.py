"""One-way Welch's ANOVA on customer-level 90-day LTV-proxy by channel.

Backs the README's "LTV is approximately equal across channels by design"
claim with an actual statistical test instead of eyeballing a 158–166 BRL
spread. Mirrors the exact LTV-proxy construction already used in
`sql/adhoc/ltv_by_channel_one_month.sql` and the dbt
`int_customer_ltv_90d` model, but returns one row per customer (not
pre-aggregated to channel grain) so the test sees within-group variance.

Design choice: Welch's one-way ANOVA (not standard Fisher's F), because
the four channel groups range 1,091–2,907 customers in the 2017-11
cohort and group variances are not assumed equal — Welch is robust to
both unequal sizes and heteroscedasticity.

Implementation choice: `pingouin.welch_anova` over a hand-rolled Welch F.
Pingouin is a well-tested stats package built on scipy; writing the
Satterthwaite denominator by hand would duplicate work and add a
custom-code audit surface for no gain. Cost: one extra dependency
(`pingouin~=0.5`, declared in requirements.txt), which pulls scipy +
statsmodels transitively.

Cohort: November 2017 — same cohort as the README's "Verified 2017-11
snapshot" table and the LTV-proxy evidence row in docs/PROJECT_LOG.md,
so this test backs the number the reader actually sees in the project's
headline table.

Reproducible: no random sampling, no bootstrapping — the query is a
deterministic re-expression of the 2017-11 cohort's per-customer LTV
and the test is deterministic given the same input. Running this file
on the same project should always print the same F, p, and eta-squared.
"""
from __future__ import annotations

import pingouin as pg

from bq_client import get_client

CUSTOMER_LEVEL_LTV_QUERY = """
with first_purchase as (
  select
    c.customer_unique_id,
    min(o.order_purchase_timestamp) as first_purchase_at,
    date_trunc(date(min(o.order_purchase_timestamp)), month) as first_purchase_month
  from `olist_raw.orders` o
  join `olist_raw.customers` c using (customer_id)
  group by c.customer_unique_id
),
channels as (
  select
    fp.customer_unique_id,
    fp.first_purchase_at,
    fp.first_purchase_month,
    case
      when mod(abs(farm_fingerprint(fp.customer_unique_id)), 100) < 40 then 'Organic'
      when mod(abs(farm_fingerprint(fp.customer_unique_id)), 100) < 65 then 'Google Ads'
      when mod(abs(farm_fingerprint(fp.customer_unique_id)), 100) < 85 then 'Facebook/Instagram Ads'
      else 'Email/Referral'
    end as channel
  from first_purchase fp
),
customer_orders as (
  select
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp
  from `olist_raw.orders` o
  join `olist_raw.customers` c using (customer_id)
),
customer_ltv_90d as (
  select
    ch.customer_unique_id,
    ch.channel,
    ch.first_purchase_month,
    sum(p.payment_value) as ltv_proxy_90d
  from channels ch
  join customer_orders co
    on co.customer_unique_id = ch.customer_unique_id
   and co.order_purchase_timestamp between ch.first_purchase_at
                                       and timestamp_add(ch.first_purchase_at, interval 90 day)
  join `olist_raw.order_payments` p
    on p.order_id = co.order_id
  group by ch.customer_unique_id, ch.channel, ch.first_purchase_month
)
select customer_unique_id, channel, ltv_proxy_90d
from customer_ltv_90d
where first_purchase_month = date '2017-11-01'
"""


def main() -> None:
    client = get_client()
    df = client.query(CUSTOMER_LEVEL_LTV_QUERY).to_dataframe()

    print(f"Rows (customers in 2017-11 cohort): {len(df)}")
    print()
    print("Per-channel 90-day LTV-proxy (BRL) — n, mean, std, min, max:")
    summary = df.groupby("channel")["ltv_proxy_90d"].agg(["count", "mean", "std", "min", "max"])
    print(summary.round(2).to_string())
    print()

    result = pg.welch_anova(dv="ltv_proxy_90d", between="channel", data=df)
    f_stat = float(result["F"].iloc[0])
    ddof1 = float(result["ddof1"].iloc[0])
    ddof2 = float(result["ddof2"].iloc[0])
    p_value = float(result["p-unc"].iloc[0])
    eta_sq = float(result["np2"].iloc[0])

    print("One-way Welch's ANOVA — customer-level 90-day LTV-proxy by channel:")
    print(f"  F({ddof1:.0f}, {ddof2:.2f}) = {f_stat:.4f}")
    print(f"  p-value               = {p_value:.6f}")
    print(f"  eta-squared (np2)     = {eta_sq:.6f}")
    print()
    if p_value < 0.05:
        print(f"Verdict (alpha=0.05): REJECT null. A statistically detectable")
        print(f"channel effect exists; eta^2 = {eta_sq:.4f} characterises its size")
        print(f"(fraction of total LTV variance attributable to channel).")
    else:
        print(f"Verdict (alpha=0.05): FAIL to reject null. No evidence of a")
        print(f"channel effect on customer-level 90-day LTV-proxy.")


if __name__ == "__main__":
    main()
