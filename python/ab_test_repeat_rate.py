"""A/B test — did the new post-purchase email nurture lift 90-day repeat rate?

Standalone mini-case per docs/PROJECT_BRIEF.md §5.5 / docs/PROJECT_BRIEF.md §5
§5. Deliberately NOT mixed into the CAC/LTV/ROAS mart story — this
is the "know your stats" check, not part of channel attribution.

Simulation design:
    * Randomized controlled experiment, 5,000 new customers per arm
      (order-of-magnitude match for an Olist cohort-month — 2017-11
      had ~7,300 new customers).
    * Control arm: baseline 90-day repeat rate = 2.05%, the actual
      overall Olist 2017-11 value from mart_repeat_rate_by_channel.
    * Test arm: hypothetical nurture sequence lifts repeat rate to
      2.75% (absolute +0.7 pp, relative +34%). Plausible for an email
      program, small enough that detection is not guaranteed —
      whether the z-test rejects is a real question at this n.
    * α = 0.05, two-tailed, seed = 42 for reproducibility.

Stack: Python stdlib only — `math.erf` for the standard-normal CDF,
`random.Random(42)` for the Bernoulli draws. No scipy dependency,
which keeps the script runnable on a bare `python3` install.
"""
from __future__ import annotations

import math
import random


N_PER_ARM = 5_000
P_CONTROL = 0.0205
P_TEST    = 0.0275
SEED      = 42
ALPHA     = 0.05


def phi(z: float) -> float:
    """Standard normal CDF."""
    return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))


def two_proportion_ztest(x1: int, n1: int, x2: int, n2: int) -> dict:
    """Two-proportion z-test comparing p2 to p1.

    Returns absolute lift (p2 - p1), z-statistic (pooled-variance),
    two-tailed p-value, and 95% CI for the lift (unpooled variance,
    the standard choice for reporting an effect size).
    """
    p1 = x1 / n1
    p2 = x2 / n2
    p_pool = (x1 + x2) / (n1 + n2)
    se_pooled = math.sqrt(p_pool * (1 - p_pool) * (1 / n1 + 1 / n2))
    z = (p2 - p1) / se_pooled
    p_value = 2 * (1 - phi(abs(z)))
    se_unpooled = math.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2)
    lift = p2 - p1
    ci_low  = lift - 1.96 * se_unpooled
    ci_high = lift + 1.96 * se_unpooled
    return {
        "p1": p1, "p2": p2, "lift": lift,
        "z": z, "p_value": p_value,
        "ci_low": ci_low, "ci_high": ci_high,
    }


def simulate_bernoulli_successes(rate: float, n: int, rng: random.Random) -> int:
    return sum(1 for _ in range(n) if rng.random() < rate)


def main() -> None:
    rng = random.Random(SEED)
    x_control = simulate_bernoulli_successes(P_CONTROL, N_PER_ARM, rng)
    x_test    = simulate_bernoulli_successes(P_TEST,    N_PER_ARM, rng)

    print("Design:")
    print(f"  cohort size per arm:              {N_PER_ARM:,}")
    print(f"  simulated repeat rate — control:  {P_CONTROL*100:.2f}%")
    print(f"  simulated repeat rate — test:     {P_TEST*100:.2f}%")
    print(f"  seed:                             {SEED}")
    print()

    print("Observed:")
    print(f"  control: {x_control:>3} / {N_PER_ARM} = {100*x_control/N_PER_ARM:.2f}%")
    print(f"  test:    {x_test:>3} / {N_PER_ARM} = {100*x_test/N_PER_ARM:.2f}%")
    print()

    r = two_proportion_ztest(x_control, N_PER_ARM, x_test, N_PER_ARM)
    print("Two-proportion z-test (two-tailed):")
    print(f"  absolute lift (test − control): {r['lift']*100:+.2f} pp")
    print(f"  z-statistic:                    {r['z']:+.3f}")
    print(f"  p-value:                        {r['p_value']:.4g}")
    print(f"  95% CI for lift:                [{r['ci_low']*100:+.2f} pp, {r['ci_high']*100:+.2f} pp]")
    print()

    decision = (
        "REJECT null (significant lift)"
        if r["p_value"] < ALPHA
        else "FAIL TO REJECT null (not significant at this n)"
    )
    print(f"  α = {ALPHA} → {decision}")


if __name__ == "__main__":
    main()
