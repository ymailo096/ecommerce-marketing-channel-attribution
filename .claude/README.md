# `.claude/` — agent tooling

This directory holds AI-agent context that also happens to be useful
project documentation. It is committed to the repo on purpose.

## `skills/`

- **`marketing-metrics/SKILL.md`** — the locked, project-wide
  definitions of channel assignment, the granularity trap around
  `ad_spend`, and the four metric formulas (CAC, repeat purchase
  rate, LTV-proxy, ROAS). Every SQL model in the repo defers to
  this — see the `marketing-metrics skill` references in the model
  comments and in [`docs/PROJECT_LOG.md`](../docs/PROJECT_LOG.md).
- **`verify-rigorously/SKILL.md`** — the discipline used before
  declaring anything "verified" or "matches exactly" in this repo.
  Requires side-by-side comparison, re-derived numbers, and named
  interpretation uncertainty rather than confident narration.

These files are auto-loaded by Claude Code when it runs in this
directory, but they read fine as plain project docs on GitHub. If
you're editing a SQL model or writing a new metric, read
`marketing-metrics/SKILL.md` first.
