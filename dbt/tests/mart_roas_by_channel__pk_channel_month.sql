-- Uniqueness check on the composite primary key (channel, month)
-- of mart_roas_by_channel. This one is the highest-risk of the four
-- to regress: mart_roas_by_channel is a 3-way INNER JOIN of the
-- other three marts on (channel, month), so any duplicate in ANY
-- input silently multiplies rows here.

select
    channel,
    month,
    count(*) as n
from {{ ref('mart_roas_by_channel') }}
group by channel, month
having count(*) > 1
