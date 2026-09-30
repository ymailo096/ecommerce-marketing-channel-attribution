---
name: verify-rigorously
description: Use before declaring any calculation, dbt model, or cross-check "verified", "matches", or "correct" in this project — forces actual evidence over confident claims.
---

# Verification Discipline

Never write "verified", "matches exactly", or "точно" as a bare claim.
Every such statement must be backed by showing the actual compared numbers
side by side (ad hoc value vs dbt mart value, or expected vs actual), not
just an assertion that they match.

Before marking any rule-of-three step "done":
1. Re-run the granularity/fan-out check on every new JOIN (same checklist
   already applied to CAC: is either side of the join at a coarser grain
   than expected? Could this JOIN multiply rows?).
2. Check WHERE vs HAVING placement, NULL handling in aggregates, and
   whether GROUP BY covers every non-aggregated SELECT column.
3. If a result could plausibly be interpreted two different ways (like the
   flat LTV-by-channel finding), state the uncertainty explicitly and name
   what evidence would change the interpretation, instead of picking one
   confident narrative.
4. Do not round or approximate a comparison to declare "close enough"
   without saying by how much they differ and why that gap is acceptable.

If you find yourself about to write "this confirms..." or "as expected...",
stop and check whether you actually re-derived the number or are pattern-
matching to what you expected to see.
