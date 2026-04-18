# ADR-0007: Segment-focused redesign — single root view over tabbed navigation

**Date:** 2026-04-17
**Status:** Accepted

## Context

The original app structure had a tabbed navigation (Today tab with ArcView fitness ring + briefing, Targets tab with segment list) and a separate GoalSettingView onboarding gate. This added complexity: two entry points, redundant navigation, and Arc/fitness views that duplicated information already expressed by segment strike scores. User testing showed the segment list with Enzo chat was the core value; the Arc view added noise.

## Decision

Delete all Arc/fitness views (ArcView, FitnessRingView, FitnessChartView, ArcBriefingView, GoalHeaderView, etc.) and remove the tab picker. Make `SegmentsView` the single root view. Fitness score is computed silently to power strike scores — never shown in the UI. Per-segment Enzo chat replaces the global briefing.

Completed 2026-04-14 across 7 commits on `main`.

## Consequences

- Navigation is a single `NavigationStack`: SegmentsView → SegmentDetailView
- Fitness computation still runs; it just doesn't have a dedicated UI surface
- `hasCompletedOnboarding` is now set in `SyncProgressView.onComplete` (no GoalSettingView gate)
- Chat is scoped to individual segments via `AppState.sendSegmentMessage()` — no global briefing
- Significantly less code to maintain; deleted views are gone, not hidden
- UX phases D–J from `ux-audit.md` continue from this new baseline
