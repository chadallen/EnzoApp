# ADR 0010 — Per-segment OLS regression for PR probability over global heuristic score

**Date:** 2026-04-21  
**Status:** Accepted

## Context

The original "strike score" was a global heuristic: `clamp(0.75 + fitnessDelta + prAgeBonus + effortGapModifier, 0, 1)`. It produced a single number meant to convey PR readiness but had no statistical grounding and couldn't produce a probability.

For the v2 fitness algorithm, two approaches to segment readiness were considered:

- **Global CTL threshold (simpler):** Compare current CTL to the CTL at the time the PR was set. Display a ratio or gap. Easy to implement, interpretable, but treats all segments identically and ignores freshness.
- **Per-segment OLS regression (chosen):** For each starred segment, fit `elapsed_time = β₀ + β₁·CTL + β₂·TSB` from the athlete's effort history. Use the normal CDF on the residuals to produce a PR probability.

## Decision

Fit a separate linear regression model for each starred segment using the athlete's own effort history. Solve via normal equations using `simd_double3x3.inverse` (no LAPACK). Output PR probability via `P(effort < prTime) = Φ((prTime − ŷ) / σ)`.

## Rationale

- The regression personalizes the model: it learns how *this athlete* performs on *this specific segment* at various CTL/TSB levels. A generic CTL threshold cannot capture this.
- The normal CDF output is more actionable than a 0–1 heuristic — "73% chance" is meaningful, "Almost there" is vague.
- `simd_double3x3` makes the 3×3 normal equations trivial (~25 lines) without any external dependency. LAPACK would add complexity with no benefit for a fixed-3-parameter problem.
- Graceful degradation: segments with `isValid == false` (wrong-sign β₁, singular matrix, no data) fall back to a plain-language naive fallback string.
- The spec's minimum effort threshold was lowered to n ≥ 1 (from the original proposal's n ≥ 8) so the model fires for segments with limited history while extrapolation warnings handle out-of-range predictions.

## Consequences

- Regression quality depends on effort history volume. Segments with < 3 efforts produce a deterministic (not probabilistic) result (sigmaResid = 0).
- Wrong-sign β₁ guard (`beta1 > 0`) catches confounded models; `isValid = false` prevents bad predictions from reaching the UI.
- Extrapolation flag is shown when today's CTL/TSB is outside `[ctlMin × 0.9, ctlMax × 1.1]` or `[tsbMin − 20, tsbMax + 20]`.
- `SegmentFitnessModel` stores the full regression state (all β coefficients, σ, ranges, prTime, prCTL) for display-time prediction without re-computation.
- Per-segment fetch strategy (`/segments/{id}/all_efforts`) replaces per-activity detail fetches, reducing API calls proportional to starred segment count rather than recent activity count.
