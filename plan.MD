# Enzo — Plan

This is the living status document. `PRD.md` is the product spec and is not modified here. `CLAUDE.md` is the project rulebook.

Architecture decisions: `docs/adr/`. Feature design docs: `docs/plans/YYYY-MM-DD-<topic>-design.md`.

**Active epic:** none — EnzoApp-iue complete
**Also open:** EnzoApp-55p.6 — Enzo voice/prompt tuning (P2)

---

## Overall Build Sequence

| Step | Description | Status |
|---|---|---|
| 1 | Project setup, Xcode, Sweetpad, signing | ✅ Done |
| 2 | Arc UI (static, hardcoded data) | ✅ Done |
| 3 | Claude API wired, streaming | ✅ Done |
| 4 | Goal setting UI | ✅ Done |
| 5 | Data models (Supabase-era, later migrated) | ✅ Done |
| 6 | Strava OAuth | ✅ Done |
| 7 | Historical sync Phase 1 (activity fetch + fitness computation) | ✅ Done |
| 8 | Context payload + live Enzo | ✅ Done |
| 9 | Historical sync Phase 2 + segment scoring | ✅ Done |
| 10 | Onboarding flow (ConnectView, SyncProgressView, auth gating) | ✅ Done |
| 11 | Polish pass | ✅ Done |
| — | UI refactor: light mode, top-tab nav (Today/Targets) | ✅ Done |
| — | Score cleanup + 5-tier labels + readiness differentiation | ✅ Done |
| — | Persistence migration: Supabase → SwiftData (on-device SQLite) | ✅ Done |
| — | Swift 6 concurrency warnings resolved | ✅ Done |
| — | ConnectView redesign | ✅ Done |
| — | UX/UI audit (`ux-audit.md`, 27 items, 10-phase plan) | ✅ Done |
| — | Segment-Focused Redesign (see below) | ✅ Done |
| — | UX polish Phases A–I (D–I completed 2026-04-17) | ✅ Done |
| 11b | Enzo voice/prompt tuning | ⬜ Pending (EnzoApp-55p.6) |
| — | Segment UX Improvements (EnzoApp-75h, 14 tasks) | ✅ Done |
| — | UX Phase J — dark mode + semantic colors | ✅ Done |
| — | Fitness Algorithm v2 — CTL/TSB + OLS regression (EnzoApp-y69) | ✅ Done |
| — | Refocus UI on starred segments (EnzoApp-iue) | ✅ Done |
| — | SwiftData UAT — simulator + device smoke test (EnzoApp-55p.2) | ✅ Done |
| 12 | Strava webhooks | ⬜ Deferred (not needed for beta) |

---

## Segment-Focused Redesign (completed 2026-04-14)

Major architectural pivot — 7 commits on `main`:

1. Deleted all Arc/fitness views (ArcView, FitnessRingView, FitnessChartView, ArcBriefingView, GoalHeaderView, LookaheadSuggestionView, PROpportunitiesCard, MonthDetailSheet, PromptChipsView, GoalSettingView). Moved ArcMessageView + ArcInputBar to `Features/Segments/`.
2. Simplified navigation: removed tab picker, removed GoalSettingView onboarding gate. `hasCompletedOnboarding` now set in `SyncProgressView.onComplete`.
3. Cleaned SegmentsView: removed GoalHeaderView from top, uniform row backgrounds.
4. ClaudeService: multi-turn conversation history support, fixed stale readiness labels in system prompt.
5. AppState: removed briefing/lookahead code, added `sendSegmentMessage()` + `segmentAssessmentPrompt()`.
6. SegmentDetailView: "Ask Enzo" button + per-segment chat thread with animated scroll.
7. SettingsSheet: last-synced always visible, confirm dialogs on reset and disconnect, disconnect now `Color(.systemRed)`.

**New app structure:**
- Main screen → SegmentsView (segment list, sorted by opportunity, goal segment starred)
- Segment detail → SegmentDetailView (stats, readiness score, "Ask Enzo" → chat)
- Fitness score computed silently, powers strikeScore — never shown in UI

---

## Current Status — 2026-04-30 (Session 8)

**Build state:** All commits on `main`, pushed. Working tree clean.

**This session:** Completed EnzoApp-iue epic (all 3 tasks via `/build-tasks --auto`): removed the misleading All/Starred filter from SegmentsView (iue.1), updated ConnectView copy to mention starred segments (iue.2), and built the Find Segments discovery feature surfacing frequently-ridden unstarred segments (iue.3, with 10 tests). Also ran SwiftData UAT (55p.2) via ios-ui-test on simulator — all 5 steps passed. During UAT discovered and fixed a real bug: `SyncProgressView` would get permanently stuck on long first-syncs because `syncHasStarted` was never set when `isSyncing` was already true when the view appeared (commit 772d5a6, closed EnzoApp-aeh). Also established that NSLog is only readable via Sweetpad's terminal panel (not via `log stream` on iOS 26 simulator). New iPhone setup assisted — Sweetpad is the launch path, not `xcrun simctl launch`.

**Next session:** `EnzoApp-55p.6` (Enzo voice/prompt tuning — fix stale labels in enzo-voice.MD, tune segmentAssessmentPrompt via playground). Or tackle the first-sync performance bug (sequential SwiftData upserts with 200+ activities) if that becomes a blocking issue on real device.

## Current Status — 2026-04-21 (Session 5)

**Build state:** All commits on `main`, pushed. Tests passing (183 tests).

**This session:** Designed and began implementing Fitness Algorithm v2 (EnzoApp-y69). Replaced the HR-efficiency fitness model and heuristic strike score with a CTL/ATL/TSB Performance Management Chart + per-segment OLS regression. New SwiftData models: `ActivityModel`, `DailyFitnessModel`, `StarredSegmentModel`, `SegmentEffortModel`, `SegmentFitnessModel`. New utilities: `LTHREstimator`, `TSSCalculator`, `DailyFitnessBuilder`, `SegmentOLSSolver` (simd_double3x3), `PRPredictor` (normal CDF via erf()). New Strava fetch methods for activities, starred segments, and segment efforts. Full sync pipeline wired into `AppState.syncV2()` replacing Phase 1 + Phase 2 (fht, my2, 1uc, cqa, wdi, h44, mkx, 95i all closed). UI partially updated: `SegmentScore` extended with v2 prediction fields, `SegmentDetailView` readiness card shows probability %, predicted time ± 1σ range, extrapolation warning. `segmentAssessmentPrompt` updated with probability context. 51 new algorithm tests added. Remaining in `EnzoApp-1tl`: delete legacy `FitnessSnapshotModel` + `SegmentScoreModel` definitions and `FitnessCalculator.swift` + `SegmentScorer.swift`.

**Next session:** `EnzoApp-1tl` (finish UI cutover — delete legacy models/calculators, ~30 min). Then `EnzoApp-55p.2` (SwiftData UAT on physical device) or `EnzoApp-06k` (starred segment filter, P2).

## Current Status — 2026-04-20 (Session 4)

**Build state:** 2 commits ahead of origin, unpushed. Tests passing.

**This session:** Closed the 75h epic with its final 2 tasks — elevation profile chart in `SegmentDetailView` (75h.6, Swift Charts AreaMark with enzoChartPrimary tokens) and the segment map spike (75h.5, recommendation written to beads notes: MapPolyline via on-demand stream fetch). Decided and implemented Phase J dark mode: adaptive `UIColor` trait closures in `Color+Enzo.swift`, `enzoUserBubble` token added, `.preferredColorScheme(.light)` removed (55p.9). Fixed pre-existing bug: user bubble text was black on dark navy (now `.white`). Researched Strava CTL API — not available via any public endpoint; findings captured in beads (15y). Discussed CTL/TSB computation from suffer_score and power data — paused for later. Implemented starred segment filter in Phase 2 (06k) then rolled back at Chad's request along with the CTL spike doc commit.

**Next session:** `EnzoApp-06k` (starred segment filter, P2 — reimplement) or `EnzoApp-55p.2` (SwiftData UAT, P1 — needs physical device).

## Current Status — 2026-04-20 (Session 3)

**Build state:** All commits on `main`, pushed. Working tree clean. Tests passing.

**This session:** Completed 8 tasks from EnzoApp-75h. Also resolved a disk-full build failure (cleared unavailable simulators, freed ~9 GB). Key work: extracted shared `StrikeScoreDonut` component (compact 44pt / hero 120pt) and moved readiness card to top of detail view (75h.3, 75h.7). Built `HeroSegmentCard` pinned above segment list when goal is set, with auto-chat navigation via `SegmentNavigation` enum (75h.10). Simplified Settings to Sync + Disconnect only (75h.11). Fixed re-sync to keep list visible with slim banner instead of full-screen spinner (75h.15). Grouped segment list into 5 labeled tier sections (75h.13). Added `EffortRecord` + `effortsJSON` SwiftData field + effort history list in `SegmentDetailView`, populated during Phase 2 sync (75h.4). Added `.searchable()` search bar with flat filtered results (75h.14). Created research spike `EnzoApp-15y` for Strava CTL/fitness API investigation.

## Current Status — 2026-04-19 (Session 2)

**Build state:** All commits on `main`, pushed. Working tree clean. Tests passing.

**This session:** Completed 5 tasks from EnzoApp-75h. Fixed `disconnect()` to use ephemeral browser session so reconnect forces real OAuth (75h.12). Shortened Enzo's opening segment response to 2-4 sentences via explicit prompt instruction (75h.9). Eliminated dark user-bubble flash on "Ask Enzo" tap using `isHidden` flag on `ArcMessage` (75h.8). Added `SegmentLoadingView` with 5 cycling phrases (75h.1). Added dismissible onboarding hint card when no goal set (75h.2). Also fixed 2 pre-existing test failures (`contextPayload` sort order, stale `prDate` in scorer test) and restored `StravaAthlete` memberwise init.

---

## Known Issues / Blockers

| Issue | Notes |
|---|---|
| **`enzo-voice.MD` stale labels** | Skill has old fitness + readiness label names. Fix as part of `55p.6` (prompt tuning). |
| **First-sync performance** | 200+ activities causes very long sync (10+ min on device) due to sequential SwiftData upserts in `upsertActivityModel` and `upsertDailyFitness` loops. Tracked as open bug — not blocking beta. |
| **NSLog on iOS 26 simulator** | Only visible in Sweetpad's terminal panel. `log stream` redacts message bodies. Always launch via Sweetpad, not `xcrun simctl launch`. |
| **Step 12: Strava webhooks** | Not needed for beta. |
