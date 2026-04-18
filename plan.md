# Enzo — Plan

This is the living status document. `PRD.md` is the product spec and is not modified here. `CLAUDE.md` is the project rulebook.

Architecture decisions: `docs/adr/`. Feature design docs: `docs/plans/YYYY-MM-DD-<topic>-design.md`.

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
| — | UX polish Phases A–C, D (partial), E (partial) | ✅ Done |
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

**Build state:** All commits on `main`, pushed. Migrated to three-file + beads workflow.
**⚠️ Build has NOT been tested in simulator post-redesign.** This must happen before continuing UX polish.

Project state at migration: Segment-focused redesign complete. Core features (Strava sync, fitness computation, segment scoring, Enzo chat) all built. Remaining work is UX polish phases D–J and Step 11b (Enzo voice tuning). All remaining tasks filed in beads — run `bd ready` to see next work.

**UX audit phase status:**
- Phase A (safe deletes): **Complete** — all fitness/Arc views deleted
- Phase B (bug fixes): **Complete** — moot items gone (GoalSettingView deleted), streaming scroll done in SegmentDetailView
- Phase C (settings polish): **Complete** — last-synced visible, confirm dialogs, systemRed disconnect
- Phase D (touch targets): **Partial** — alternating rows removed; touch target sizing and reduce motion still pending
- Phase E (navigation): **Partial** — tabs removed, gate removed; SegmentDetailView double title still pending
- Phase F (onboarding polish): Pending
- Phase G (chart/main UI): Largely moot (chart deleted); sync indicator still open
- Phase H (typography): Pending
- Phase I (feedback/empty states): Pending
- Phase J (dark mode): **Blocked** — requires dark color palette design decisions before any code

---

## What Remains (priority order)

### 1. Build + smoke test (do first)
Run in simulator. Walk through:
- Connect (Strava OAuth) → sync → segment list
- Tap segment → SegmentDetailView → "Ask Enzo" → chat follow-up
- Settings → sync, reset, disconnect confirm dialogs
- Back navigation, goal setting

### 2. SwiftData UAT (5-step device checklist)
Requires physical device. Steps:
1. Fresh install — verify sync works end-to-end
2. Kill + relaunch — verify snapshots and segments persist
3. Set a goal — kill + relaunch — verify goal persists
4. Settings → Reset sync history → re-sync — verify data re-fetches correctly
5. Disconnect → reconnect → sync — verify clean slate

### 3. UX polish — Phase D (touch targets, remaining)
Files: `EnzoApp/EnzoAppApp.swift`, `EnzoApp/Features/Segments/SegmentsView.swift`
- Gear icon: `.frame(width: 44, height: 44).contentShape(Rectangle())`
- Sort menu: verify 44pt tappable area
- Pulsing "Strike now" donut: gate on `@Environment(\.accessibilityReduceMotion)`

### 4. UX polish — Phase E (navigation, remaining)
File: `EnzoApp/Features/Segments/SegmentDetailView.swift`
- Segment name appears in both `.navigationTitle` (inline) and large title in scroll content — remove or shorten the inline title
- Optional: restore native nav bar in MainTabView for large-title-on-scroll behavior

### 5. UX polish — Phase F (onboarding)
Files: `EnzoApp/Features/Onboarding/ConnectView.swift`, `EnzoApp/Features/Onboarding/SyncProgressView.swift`
- Replace `padding(.bottom, 52)` with `.safeAreaInset(edge: .bottom)`
- Add `ProgressView()` spinner above phase text in SyncProgressView
- Add 1–2 lines of privacy disclosure copy in ConnectView

### 6. Step 11b — Enzo voice/prompt tuning
- Update stale labels in `skills/enzo-voice.MD` (still has old fitness + readiness label names)
- Tune `segmentAssessmentPrompt` in `AppState.swift` via playground first: `python3 scripts/enzo_playground.py`
- Update `ClaudeService.swift` system prompt if needed after playground testing

### 7. UX polish — Phase H (typography)
Files: `SegmentsView.swift`, `EnzoAppApp.swift`
- Replace `.system(size: 11)` in SegmentStrikeRow donut with `.caption2` + `.minimumScaleFactor(0.6)`
- Replace `.system(size: 20)` on gear icon with a named text style

### 8. UX polish — Phase I (feedback/empty states)
Files: `SegmentDetailView.swift`, `SegmentsView.swift`
- Goal-set confirmation toast after `setGoal` action
- Empty state for fresh install (currently shows preview segment data)

### 9. UX polish — Phase J (dark mode)
**Blocked.** Design decisions required first:
- Define dark palette for all `Color.enzoXxx` tokens (enzoBg, enzoCard, enzoPrimary, enzoSecondary, enzoAccent, etc.)
- Define `enzoUserBubble` dark-mode-appropriate color
- Only start after palette is agreed on

---

## Known Issues / Deferred

| Issue | Notes |
|---|---|
| **Demo jitter in SyncService** | ±0.25 deterministic noise in `syncPhase2`. Do NOT remove without Chad's explicit instruction. Tagged "DEMO — Remove before shipping." |
| **`enzo-voice.MD` stale labels** | System prompt section has old fitness + readiness label names. Fix before any prompt work in Step 11b. |
| **`segmentAssessmentPrompt` needs tuning** | The opening "Ask Enzo" prompt in `AppState.segmentAssessmentPrompt`. Use playground before touching `AppState.swift`. |
| **phase2ActivityLimit = 25** | Do not raise without Chad's instruction. |
| **SegmentDetailView double title** | Segment name in both `.navigationTitle` and scroll content header. Phase E. |
| **Sync progress indicator** | No visible indicator in main UI during manual sync. Phase G. |
| **Empty state UI** | Fresh install shows preview segment data. Phase I. |
| **Dark mode** | Phase J — do not start without dark palette defined. `.preferredColorScheme(.light)` stays until then. |
| **Step 12: Strava webhooks** | Not needed for beta. |
