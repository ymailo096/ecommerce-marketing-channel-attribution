-- Flag if CAC = 0 exactly for any (channel, month). Near-zero CAC
-- is expected (Organic 2017-11 = 0.40 BRL, per the verified
-- snapshot), and safe_divide correctly returns NULL for the
-- 0/0 case — but an EXACT 0 in cac_brl means spend_brl was 0 with
-- new_customer_count > 0, which either implies:
--   * a bug in the ad_spend generator (spend ranges start at 500,
--     so a 0 there would be a regression);
--   * or a corrupted source row (someone loaded a bad CSV).
-- Either way we want CI to fail loudly rather than let ROAS spike
-- to +Infinity silently on the next run.

select
    channel,
    month,
    spend_brl,
    new_customer_count,
    cac_brl
from {{ ref('mart_cac_by_channel') }}
where cac_brl = 0
