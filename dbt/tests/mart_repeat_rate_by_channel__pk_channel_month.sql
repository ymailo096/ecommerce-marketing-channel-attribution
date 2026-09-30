-- Uniqueness check on the composite primary key (channel, month)
-- of mart_repeat_rate_by_channel.

select
    channel,
    month,
    count(*) as n
from {{ ref('mart_repeat_rate_by_channel') }}
group by channel, month
having count(*) > 1
