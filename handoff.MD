# Session Handoff — Readiness Score Differentiation (ready to plan)

## What was completed this session (Score UI Cleanup + UI Polish)

| Change | Files touched | Commit |
|---|---|---|
| Remove fitness comparison card from SegmentDetailView, rewrite strikeLine | `SegmentDetailView.swift` | 47ea493 |
| GoalHeaderView: remove PR fitness column, two-column layout | `GoalHeaderView.swift` | c2c236c |
| FitnessRingView: add readiness donut, remove goal progress bar | `FitnessRingView.swift` | 1ae2d67 |
| FitnessRingView: 'Readiness' label under readiness donut | `FitnessRingView.swift` | f5414a5 |
| FitnessRingView: add goal segment name below donuts | `FitnessRingView.swift` | 0c759c2 |
| GoalHeaderView: add readiness donut to Targets header | `GoalHeaderView.swift` | 5310923 |
| SegmentScorer: expand to 5 readiness tiers (Strike now / Almost there / Worth a shot / Getting there / Build first) | `SegmentScorer.swift`, `SegmentScorerTests.swift`, `FitnessRingView.swift`, `GoalHeaderView.swift` | 66ccf8d |
| SegmentScorer: rebase strike score to 0.75 at parity (was 0.50) | `SegmentScorer.swift`, `SegmentScorerTests.swift` | 778c794 |
| GoalHeaderView: segment stats + readiness donut fill header | `GoalHeaderView.swift` | 67638fe |
| GoalHeaderView: iterative header layout work (label as hero, then pill, then final) | `GoalHeaderView.swift` | b35a42a, 354bddb, 419e663, 63c1999, 3d86064 |
| ArcView: fix goal overwrite on nav-pop (remove loadContext from ArcView.task) | `ArcView.swift` | 3903bad |
| FitnessRingView: 'Target:' prefix, match status font size | `FitnessRingView.swift` | 07e30a1 |
| Today tab: consolidate to single Enzo card (lookahead only, accent bar) | `ArcView.swift`, `ArcBriefingView.swift` | 12f7bb2 |
| ArcInputBar: increase placeholder text contrast | `ArcInputBar.swift` | 9ae31f3 |
| FitnessRingView: remove athlete name greeting | `FitnessRingView.swift` | 817c7ba |
| SegmentsView: larger, higher contrast readiness chips | `SegmentsView.swift` | 5e864eb |
| FitnessRingView: restore greeting with time-of-day and first name only | `FitnessRingView.swift` | 77958e8 |

---

## Current app state

All changes committed and pushed. Working tree is clean. Branch: `main`.

**Important — Chad must re-sync to pick up the updated strike score formula:**
**Settings → Reset sync history → Sync now**
This rewrites `strikeScore` and `strikeLabel` stored in Supabase with the new 0.75 parity baseline and 5-tier labels.

---

## Current Targets tab header layout

```
Current target segment
Hawk Hill          [readiness donut]
Almost there
─────────────────────────────────────
Mar 2024  ·  4:32  ·  2.8 mi  ·  +1,234 ft
```

Segment name (subheadline), strike label below it (larger, colored), readiness donut top-right, single-line segment stats at the bottom.

## Current Today tab header layout

```
Good afternoon, Chad
[fitness donut]  [readiness donut]  STATUS  LAST RIDE
                                    Building ↑  Yesterday
FITNESS          READINESS
Target: Hawk Hill
```

Two donuts side by side, status/last ride stats to the right, segment name below.

---

## Next session: Readiness Score Differentiation

### The problem

All segments currently show the same (or very similar) readiness scores. This is not a bug — it's a structural issue with the formula:

`score = clamp(0.75 + (currentFitness - fitnessAtPR) × 1.0, 0, 1)`

`currentFitness` is the same for every segment (it's the athlete's global fitness). `fitnessAtPR` varies per segment, but if most PRs were set during a similar period (which is common), the deltas are all similar and scores cluster together.

### The goal

Make readiness scores meaningfully different across segments. A segment where you set your PR at peak fitness should score lower than one where you set it while recovering. The score should reflect how realistic a PR attempt is *for that specific segment* given your current state.

### Ideas to explore (present these to Chad and get his input before writing anything)

**Option A — Factor in segment-specific trend**
`SegmentScore` already stores `trendDirection` per segment. This could be used as a stronger signal than the global trend. A segment where your recent efforts are improving should score higher.

**Option B — Factor in time since PR**
Segments with older PRs are more likely to be beatable as training evolves. A PR set 3 years ago during a peak is a different target than one set last month. Could add a small recency bonus (opposite of the removed discount — not a penalty for recent PRs, but a bonus for old ones).

**Option C — Factor in number of attempts**
Segments you've ridden many times are more predictable. If `lastEffortSeconds` is close to `prSeconds`, that's a different signal than being 2 minutes off pace.

**Option D — Relative difficulty signal**
Use distance and elevation together to estimate segment difficulty, then weight the score by how well your current fitness matches that difficulty profile.

**Recommended starting point:** Discuss options with Chad. Start with Option A (segment-specific trend as a stronger weight) and Option B (time-since-PR bonus) as they require no new data. Options C and D need additional Strava data that may not be synced yet.

### Data available in SegmentScore today
- `strikeScore: Double` — current readiness (0–1)
- `strikeLabel: String` — stored label
- `fitnessValueAtPR: Double` — athlete fitness when PR was set
- `currentFitnessValue: Double` — athlete's current global fitness
- `trendDirection: String` — "up" / "flat" / "down" (per segment? or global? — verify)
- `prDate: String` — date PR was set ("yyyy-MM-dd")
- `lastEffortSeconds: Int?` — time of most recent effort on this segment
- `prSeconds: Int` — PR time

---

## Working rules for next session

- Read CLAUDE.md, handoff.MD before doing anything. Do NOT read scratch.md or UI-punch-list.md.
- Do not write a single line of code without presenting the plan and getting explicit approval from Chad.
- Make frequent, small commits — one change per commit, descriptive message, so individual changes can be reverted.
- When Chad needs to test on device or perform a manual action (re-sync, Supabase migration, etc.), stop and prompt him explicitly before continuing.

---

## Build notes from this session

**Strike score parity baseline changed to 0.75**
Formula is now `clamp(0.75 + delta × 1.0, 0, 1)`. At parity (same fitness as when PR was set), score = 0.75 → "Almost there". Previously 0.50 ("Worth a shot"). Re-sync required to update stored values.

**5-tier readiness labels**
| Score | Label |
|---|---|
| ≥ 0.80 | Strike now |
| 0.65–0.80 | Almost there |
| 0.45–0.65 | Worth a shot |
| 0.25–0.45 | Getting there |
| < 0.25 | Build first |

Colors: green (`enzoGoal`) / blue (`enzoChartPrimary`) / amber (`enzoAmber`) / grey / grey.

**Goal overwrite bug fixed**
`ArcView.task` was calling `loadContext()` on every NavigationStack pop, which re-fetched from Supabase before `saveGoal()` finished writing — wiping the newly set goal. Fix: `loadContext()` removed from `ArcView.task`. It only runs from `RootView.task` (once per launch). `generateLookahead()` remains in `ArcView.task` (safe — guarded, no-ops if content exists).

**Today tab consolidated to single Enzo card**
`ArcBriefingView` now shows the lookahead response only ("WHAT TO DO NEXT"). `LookaheadSuggestionView` is no longer rendered in `ArcView`. `generateBriefing()` no longer called from `ArcView.task`. `briefingText` / `isGeneratingBriefing` still exist on `AppState` (used in goal-confirm flow) — not removed.

**Targets header final layout**
Segment name (subheadline) → strike label (larger, colored, no pill) → HStack with segment stats left + readiness donut right → single-line stats row (date · PR time · distance · elevation).

**strikeLabelColor in GoalSettingView is stale**
`GoalSettingView.strikeLabelColor()` still maps old labels ("No brainer", "Worth a shot") to colors. After the 5-tier label rename, the color logic will fall through to `.enzoAmber` for all new labels. Fix in next session alongside any GoalSettingView work.
