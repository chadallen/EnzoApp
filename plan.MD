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
| 11b | Enzo voice/prompt tuning | ⬜ Pending |
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

## Current Status — 2026-04-17

**Build state:** All commits on `main`, pushed. Working tree clean.
**⚠️ Build has NOT been tested in simulator post-redesign.** This must happen before shipping.

**This session:** Migrated to three-file + beads workflow (7 ADRs, `docs/adr/`, `docs/plans/`). Ran epic executor on `EnzoApp-55p` — completed 5 of 9 tasks: UX polish phases D, E, F, H, I all done. Remaining: smoke test (`55p.1`), device UAT (`55p.2`), prompt tuning (`55p.6`), dark mode (`55p.9`, blocked).

**UX audit phase status:**
- Phase A–C: Complete
- Phase D (touch targets): **Complete** — gear icon + sort menu 44pt, donut animation gated on `accessibilityReduceMotion`
- Phase E (navigation): **Complete** — `.navigationTitle` removed from SegmentDetailView, no more double title
- Phase F (onboarding polish): **Complete** — safe area insets, sync spinner, privacy copy in ConnectView
- Phase G (chart/main UI): Largely moot (chart deleted); sync indicator in main list now shows via `hasRealSegmentData` flag
- Phase H (typography): **Complete** — semantic text styles replace raw font sizes
- Phase I (feedback/empty states): **Complete** — goal-set toast, proper empty + loading states
- Phase J (dark mode): **Blocked** — requires dark color palette design decisions before any code

---

## Known Issues / Blockers

| Issue | Notes |
|---|---|
| **Build untested post-redesign** | Simulator smoke test (`EnzoApp-55p.1`) not yet run. Do before shipping anything. |
| **Demo jitter in SyncService** | ±0.25 deterministic noise in `syncPhase2`. Do NOT remove without Chad's explicit instruction. Tagged "DEMO — Remove before shipping." |
| **`enzo-voice.MD` stale labels** | Skill has old fitness + readiness label names. Fix as part of `55p.6` (prompt tuning). |
| **`segmentAssessmentPrompt` needs tuning** | Opening "Ask Enzo" prompt in `AppState.segmentAssessmentPrompt`. Use playground before touching `AppState.swift`. |
| **phase2ActivityLimit = 25** | Do not raise without Chad's instruction. |
| **Re-sync shows spinner over existing data** | When user triggers manual re-sync from Settings, `SegmentsView` replaces the segment list with a loading spinner for the duration. Confirm with Chad whether this is the desired behavior. |
| **Dark mode** | Phase J — blocked on dark palette design decisions. `.preferredColorScheme(.light)` stays until palette is agreed. |
| **Step 12: Strava webhooks** | Not needed for beta. |
