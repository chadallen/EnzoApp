# Enzo — Plan

This is the living status document. `PRD.md` is the product spec and is not modified here. `CLAUDE.md` is the project rulebook.

Architecture decisions: `docs/adr/`. Feature design docs: `docs/plans/YYYY-MM-DD-<topic>-design.md`.

**Active epic:** EnzoApp-75h — Segment UX Improvements (14 tasks)

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
| 11b | Enzo voice/prompt tuning | ⬜ Pending (EnzoApp-55p.6, EnzoApp-75h.9) |
| — | Segment UX Improvements (EnzoApp-75h, 14 tasks) | 🔄 Active |
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
| **Device UAT pending** | `55p.2` — 5-step SwiftData checklist on physical device not yet run. |
| **Demo jitter in SyncService** | ±0.25 deterministic noise in `syncPhase2`. Do NOT remove without Chad's explicit instruction. Tagged "DEMO — Remove before shipping." |
| **`enzo-voice.MD` stale labels** | Skill has old fitness + readiness label names. Fix as part of `55p.6` (prompt tuning). |
| **phase2ActivityLimit = 25** | Do not raise without Chad's instruction. |
| **Dark mode** | Phase J — blocked on dark palette design decisions. `.preferredColorScheme(.light)` stays until palette is agreed. |
| **Step 12: Strava webhooks** | Not needed for beta. |
