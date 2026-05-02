# ADR-0011: Replace Goal Segment with Starred Segments as User Curation Model

**Date:** 2026-05-01
**Status:** Accepted

## Context

The app originally organized the segment list around a single "goal segment" — a user-chosen target stored in `GoalModel` and surfaced via a pinned `HeroSegmentCard`. This created a goal-oriented UX where the whole app funneled toward one segment. In practice, users want to monitor and improve on multiple segments, and the goal concept added friction (you had to set a goal before the main screen felt useful) without meaningful benefit. Strava already provides a native mechanism for curating segments of interest: the starred segment API.

## Decision

Remove `GoalModel`, `HeroSegmentCard`, `FindSegmentsSheet`, and all goal state from `AppState`. Use Strava's starred segment flag (`isStarred`) as the sole curation mechanism. The main list shows only starred segments. Users discover and add new segments via an Add Segments page that draws from the local 90-day recency store and syncs star/unstar actions back to Strava via PUT `/segments/{id}/starred`.

## Alternatives Considered

**Keep GoalModel alongside starred segments** — Would allow a "featured" segment while still showing a broader list. Rejected because it adds complexity without a clear user need. The strike score already surfaces the best PR opportunity at the top of the sorted list.

**Multi-goal support** — Extend GoalModel to support multiple goals. Rejected as over-engineering: it replicates what Strava's star system already does, tied to Enzo's own storage instead of the user's existing Strava preferences.

**Keep goal UX, populate from starred** — Wire the goal segment to the Strava star. Rejected because the "goal" framing implies a single focus, which conflicts with the browsing behavior the app actually supports.

## Consequences

- App becomes exploratory: users can track many segments without committing to one target.
- Curation lives in Strava, so it persists across reinstalls and reflects the user's actual Strava preferences.
- Removes complexity: `GoalModel`, `HeroSegmentCard`, `FindSegmentsSheet`, `SuggestedSegment`, `setGoal()`, `isGoalSegment` — all deleted.
- Requires a new Add Segments page to replace `FindSegmentsSheet`'s discovery role.
- Existing installs lose any saved goal data on next launch — acceptable at this stage (pre-beta).
