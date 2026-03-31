# Session Handoff — Score UI Cleanup (ready to implement)

## What was completed last session (Score Cleanup)

| Change | Files touched | Commit |
|---|---|---|
| Remove % symbols from all fitness and readiness score displays | `SegmentDetailView.swift`, `GoalHeaderView.swift`, `FitnessRingView.swift` | ac57716 |
| Percentile-based normalization (5th/95th) for fitness scores | `FitnessCalculator.swift`, `SyncService.swift`, `FitnessCalculatorTests.swift` | e5ce9e3 |
| Fix missing `import Foundation` in SegmentScorerTests (pre-existing bug) | `SegmentScorerTests.swift` | e5ce9e3 |
| Remove recency discount from strike score formula | `SegmentScorer.swift`, `SegmentScorerTests.swift` | 524a2e4 |

## What happened in the most recent session (planning only)

Read docs, reviewed the Score UI Cleanup plan. No code was written. Git is clean on main. The plan below is fully designed and ready to implement.

---

## Current app state

All changes committed and pushed. Working tree is clean. Branch: `main`.

**Important — Chad must do this before testing score values:**
**Settings → Reset sync history → Sync now**
This rewrites all fitness snapshots (percentile normalization) and segment scores (without recency discount). Do this before any score values make sense on device.

---

## Next session: Score UI Cleanup (implement this)

### Overview

The SegmentDetailView and GoalHeaderView currently show three things: current fitness, fitness-at-PR, and readiness score. We are simplifying to two: **current fitness** and **readiness score**. The "fitness at time of PR" value is confusing and redundant — users need to know how fit they are now and whether they're ready to beat the PR, not what their fitness was when they set it.

`fitnessValueAtPR` stays in the data model and is still used internally by `SegmentScorer.strikeScore()`. We are only removing its display.

---

### Change 1: `EnzoApp/Features/Segments/SegmentDetailView.swift`

**Remove the entire "FITNESS COMPARISON" card** — the `VStack` containing the section header, the two `fitnessBlock` calls with the arrow between them, and the `deltaLine` text below. This is the card that shows "Building 63 → Building 63 / You're at Building — roughly the same fitness...".

**Remove the `deltaLine` computed property** — it references `segment.fitnessValueAtPR` and `segment.fitnessDelta` and is only used by the deleted card.

**Remove the `fitnessBlock` private helper function** — it was only used by the fitness comparison card.

**Rewrite the `strikeLine` computed property** — the current "No brainer" case says *"You're in better shape now than when you set this PR."* That implicitly references PR fitness. Replace all three cases with self-contained copy:

```swift
private var strikeLine: String {
    switch segment.strikeScore {
    case 0.70...:
        return "You're fit and trending in the right direction. A good window to go after it."
    case 0.45..<0.70:
        return "Getting close — a few more weeks of consistent riding and the timing will be right."
    default:
        return "Not quite there yet. Worth targeting once you've built more fitness."
    }
}
```

**After the change**, SegmentDetailView has three cards: segment stats, readiness, goal/set-goal. The `pillColor` computed property and everything in the readiness card stays.

---

### Change 2: `EnzoApp/Features/Arc/GoalHeaderView.swift`

The `goalContent` body currently builds a 3-column `HStack`: Segment stats | divider | Current fitness | divider | PR fitness.

**Remove the PR fitness column** — the `VStack` with the "PR fitness" caption, `prLabel` text, and `prPct` value.

**Remove the second divider** — the `Rectangle` between current fitness and PR fitness.

**Remove the `prLabel` and `prPct` local variables** — they're only used by the deleted column. `currentPct` stays (used by the current fitness column). The `goalSegment` lookup stays (still needed for the segment stats column).

**After the change:** GoalHeaderView shows Segment stats | divider | Current fitness. Two columns.

---

### Change 3: `EnzoApp/Features/Arc/FitnessRingView.swift`

**Add a second donut for goal segment readiness score** next to the existing fitness donut on the Today tab header.

Currently the header ring row is: `[fitness donut] [STATUS + LAST RIDE stats] [Spacer]`

New layout: `[fitness donut] [readiness donut] [STATUS + LAST RIDE stats] [Spacer]`

The readiness donut:
- Only renders when `goalSegment != nil` and goal segment name is non-empty
- Value: `goalSegment.strikeScore` (0.0–1.0), same `SectorMark` pattern as the fitness ring
- Ring color: green (`enzoGoal`) for ≥ 0.70, amber (`enzoAmber`) for 0.45–0.70, secondary (`enzoSecondary`) for < 0.45. Define this as a private computed var on `FitnessRingView`.
- Center label: `Int(goalSegment.strikeScore * 100)` — same style as the fitness score
- Frame: same 120×120 as the fitness donut
- Below the donut, a small caption label: the goal segment name, truncated, in `enzoSecondary caption2`
- Below the fitness donut, add a matching caption: "FITNESS" — so both donuts are labeled below

The goal progress bar (current fitness fill vs PR tick) currently lives below the ring row. **Remove the goal progress bar entirely** — it referenced `fitnessValueAtPR` for the PR tick and the "PR · X" label, which we're removing everywhere. The readiness donut replaces it as the "how close am I to the PR?" signal on the header.

**`FitnessRingView` signature change:** no new parameters needed — `goalSegment: SegmentScore?` already exists.

---

### Files to check before starting

Read these before writing any code — they may also reference PR fitness:

- `EnzoApp/Features/Arc/PROpportunitiesCard.swift` — check for any PR fitness label references in the row display
- `EnzoApp/Features/Segments/SegmentsView.swift` — check `SegmentStrikeRow` subtitle

If either references `fitnessValueAtPR` in the display layer, remove those references in the same pass.

---

### Test changes

No test changes needed. All tests operate on the model and scoring logic, not the UI layer.

---

### Commit strategy

Four commits in order:
1. `SegmentDetailView`: remove fitness comparison card, rewrite strikeLine
2. `GoalHeaderView`: remove PR fitness column
3. `FitnessRingView`: add readiness donut, remove goal progress bar
4. Any cleanup in `PROpportunitiesCard` / `SegmentsView` if needed

---

### Supabase state reminder

The `segment_scores` table still has `fitness_value_at_pr` and `current_fitness_value` columns — these stay. We are only changing the display layer. No migration needed.

---

## Build notes from previous sessions (Score Cleanup)

**Percentile normalization (5th/95th percentile)**
`FitnessCalculator.percentile(_:of:)` added as a pure static helper. `SyncService.computeSnapshots` now uses `percentile(5, ...)` and `percentile(95, ...)` instead of absolute `min()`/`max()`. Prevents outlier months (illness, minimal riding) from compressing all normal months into a narrow band. Fitness values will spread more meaningfully across the 0–100 range after re-sync.

**Recency discount removed from strike score**
`SegmentScorer.strikeScore` no longer applies a ×0.85 discount when the PR was set within 30 days. The hidden penalty created confusing contradictions (same fitness as PR day → still "not quite ready"). The `prDate` parameter is kept in the function signature for now (marked as unused in the docstring) — can be removed in a later cleanup pass.

**% symbols removed**
All fitness and readiness score displays no longer show `%`. These are scores (0–100), not percentages of something.

**SegmentScorerTests was missing `import Foundation`**
Pre-existing bug — caused build failures when running any test suite. Fixed in commit `e5ce9e3`.
