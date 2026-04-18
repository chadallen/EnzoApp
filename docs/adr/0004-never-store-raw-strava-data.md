# ADR-0004: Never store raw Strava data

**Date:** 2026-04-17
**Status:** Accepted

## Context

Strava provides detailed activity data including GPS traces, HR time series, and segment efforts. Storing this data locally would simplify re-computation (no need to re-fetch) but raises privacy concerns, violates Strava's data usage terms for derived-metric apps, and creates a large on-device footprint.

## Decision

Never persist raw Strava data. All activity data is fetched, computed in-memory, and discarded. Only derived output (fitness snapshots, segment scores) is written to the SwiftData store.

## Consequences

- App is compliant with Strava's data usage policies
- On-device storage footprint is small (three SwiftData model types, O(months) + O(segments) rows)
- Re-computing requires a Strava API call; full re-sync is triggered via Settings → Reset sync history
- Incremental sync (via `lastPhase2SyncTimestamp`) minimizes re-fetch cost in practice
