-- Uniqueness check on the composite primary key (channel, month) of
-- mart_cac_by_channel. Fails (returns rows) if any (channel, month)
-- pair appears more than once — that would indicate JOIN fan-out
-- upstream and every derived metric would be wrong.
--
-- Backs up the empirical uniqueness check we ran once by hand
-- (PROJECT_LOG entry 2026-09-30 ROAS row: CAC 104/104 keys). Now it
-- runs on every `dbt test` (including every CI run on push to
-- main), so a regression fails loudly instead of silently
-- corrupting the mart.

select
    channel,
    month,
    count(*) as n
from {{ ref('mart_cac_by_channel') }}
group by channel, month
having count(*) > 1
