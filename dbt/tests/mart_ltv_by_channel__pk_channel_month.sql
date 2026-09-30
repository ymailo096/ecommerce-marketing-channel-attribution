-- Uniqueness check on the composite primary key (channel, month)
-- of mart_ltv_by_channel. Same rationale as
-- mart_cac_by_channel__pk_channel_month.sql — fails if any pair
-- duplicates, which would indicate upstream JOIN fan-out.

select
    channel,
    month,
    count(*) as n
from {{ ref('mart_ltv_by_channel') }}
group by channel, month
having count(*) > 1
