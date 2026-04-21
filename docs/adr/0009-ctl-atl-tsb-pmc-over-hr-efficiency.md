# ADR 0009 — CTL/ATL/TSB Performance Management Chart over HR-efficiency fitness model

**Date:** 2026-04-21  
**Status:** Accepted

## Context

Enzo needed a fitness model to drive segment PR readiness scoring. The original implementation used a custom HR-efficiency metric (distance-per-heartbeat, normalized via percentile across all-time history) to produce a 0–1 fitness value. This value was combined with PR age and effort gap into a heuristic "strike score."

Two approaches were considered for the v2 fitness algorithm:

- **HR-efficiency (existing):** Custom metric computed from distance, elevation, HR, and duration. Percentile-normalized. Intuitive but not grounded in sport science and difficult to explain to users.
- **CTL/ATL/TSB PMC (chosen):** Standard Performance Management Chart model used by TrainingPeaks, Garmin, and most serious cycling training software. CTL (42-day EMA of TSS) = fitness; ATL (7-day EMA) = fatigue; TSB = CTL − ATL = form.

## Decision

Replace HR-efficiency with CTL/ATL/TSB. TSS is computed from power (when `device_watts == true`) with HR-based fallback using LTHR estimated from the 95th percentile of average HR across 20–90 minute rides.

## Rationale

- CTL/ATL/TSB is the industry standard — athletes familiar with training platforms will recognize the concepts immediately.
- TSB cleanly separates fitness (CTL) from readiness (TSB), enabling the per-segment OLS regression to use both as independent predictors.
- The HR-efficiency model had no natural way to produce a probability — it could only produce a relative score. CTL/ATL enables a normal-CDF probability via regression residuals.
- LTHR estimation from 95th percentile of 20–90 min rides requires no user input and degrades gracefully (floor = 1 qualifying ride).

## Consequences

- `FitnessSnapshotModel` and `SegmentScoreModel` replaced by `ActivityModel`, `DailyFitnessModel`, `StarredSegmentModel`, `SegmentEffortModel`, `SegmentFitnessModel`.
- `FitnessCalculator.swift` and `SegmentScorer.swift` deleted.
- Sync strategy changes from per-activity detail fetches to starred-segment effort fetches.
- User-facing fitness labels (Epic / Strong / Building / Baseline / Recovering) are retired — replaced by PR probability percentage.
- FTP stored in UserDefaults (`athleteFTP`) as optional Double; power-based TSS unavailable until user sets it.
