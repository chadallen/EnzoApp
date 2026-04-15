# Enzo — Implementation Plan

This file tracks the active implementation work. The PRD (`PRD.md`) is the product spec and is not modified here.

---

## Current Initiative: Segment-Focused Redesign

### Direction

The app is being simplified to focus on segment PRs and browsing opportunities — moving away from the fitness-score-first model. The core use case is **pre-ride**: open the app, see what your chances are on the segments you'll encounter today, optionally ask Enzo about a specific one.

**New structure:**
- **Main screen** — segment list, sorted by opportunity, goal segment pinned at top. No fitness ring, no chart, no auto-briefing.
- **Segment detail** — segment stats, readiness score, "Ask Enzo" button. Tapping Ask Enzo generates a segment-specific assessment, then an input bar appears for follow-up questions (mini-chat scoped to that segment).
- **Settings** — unchanged.

**Key decisions:**
- Fitness score is still computed silently and powers strike scores — it just never surfaces in the UI.
- The goal concept remains: one segment can be pinned as your current goal. Setting a goal happens from the segment detail view, not a forced onboarding step.
- Enzo chat is per-segment and session-scoped (no persistence across navigations).
- After onboarding sync, users land directly on the segment list — no forced goal-selection gate.

---

## Commit Plan

### Commit 1 — Delete dead views
**Status: pending**

Delete these files entirely:
- `EnzoApp/Features/Arc/ArcView.swift`
- `EnzoApp/Features/Arc/FitnessRingView.swift`
- `EnzoApp/Features/Arc/FitnessChartView.swift`
- `EnzoApp/Features/Arc/ArcBriefingView.swift`
- `EnzoApp/Features/Arc/GoalHeaderView.swift`
- `EnzoApp/Features/Arc/LookaheadSuggestionView.swift`
- `EnzoApp/Features/Arc/PROpportunitiesCard.swift`
- `EnzoApp/Features/Arc/MonthDetailSheet.swift`
- `EnzoApp/Features/Arc/PromptChipsView.swift`
- `EnzoApp/Features/Arc/GoalSettingView.swift`

Keep: `ArcMessageView.swift`, `ArcInputBar.swift`, `ArcMessage.swift` — reused in segment detail.

---

### Commit 2 — Simplify navigation shell
**Status: pending**

`EnzoApp/EnzoAppApp.swift`:
- `MainTabView`: remove tab picker (`tabPicker`) and `ZStack` with opacity switching. NavigationStack wraps `SegmentsView` only.
- `RootView`: remove the `GoalSettingView` gate (`!appState.hasCompletedOnboarding`). Mark `hasCompletedOnboarding = true` at the end of onboarding sync (in `SyncProgressView.onComplete`) instead of requiring goal selection.

---

### Commit 3 — Clean SegmentsView
**Status: pending**

`EnzoApp/Features/Segments/SegmentsView.swift`:
- Remove `GoalHeaderView(...)` from the top of the view body.
- Remove alternating row backgrounds — use uniform `Color.enzoBg` for all rows (ux-audit Phase D).
- Convert segment rows from `.onTapGesture` to `Button { } label: { NavigationLink(...) }` with `.buttonStyle(.plain)` for proper press state and accessibility (ux-audit Phase D).

---

### Commit 4 — Update ClaudeService
**Status: pending**

`EnzoApp/Services/ClaudeService.swift`:
- Update `stream(userMessage:context:)` to accept an optional `history: [ArcMessage]` parameter (default empty).
- When history is non-empty, build a proper multi-turn messages array: first message includes the full context payload, subsequent turns are alternating user/assistant.
- Fix system prompt: update stale readiness labels from old 3-tier ("No brainer", "Worth a shot", "Not quite ready") to current 5-tier ("Strike now", "Almost there", "Worth a shot", "Getting there", "Build first").

---

### Commit 5 — Update AppState
**Status: pending**

`EnzoApp/App/AppState.swift`:
- **Remove:** `briefingText`, `lookaheadText`, `isGeneratingBriefing`, `isGeneratingLookahead`, `arcMessages`, `generateBriefing()`, `generateLookahead()`, `briefingPrompt()`, `lookaheadPrompt()`.
- **Keep:** `isStreaming`, `streamingText`, `sendMessage()`.
- **Add:** `sendSegmentMessage(_ text: String, segment: SegmentScore, history: [ArcMessage]) async` — prepends segment-specific context (name, PR, strike score, last effort, readiness label) to the first message in the conversation.
- **Add:** `static func segmentAssessmentPrompt(segment: SegmentScore, athleteContext: AthleteContext) -> String` — the opening prompt Enzo receives when the user taps "Ask Enzo" on a segment.

---

### Commit 6 — Enzo chat in SegmentDetailView
**Status: pending**

`EnzoApp/Features/Segments/SegmentDetailView.swift`:
- Add local state: `@State private var messages: [ArcMessage]`, `@State private var inputText`, `@State private var isStreaming`, `@State private var streamingText`.
- Add "Ask Enzo" button below the readiness card. Tapping it calls `appState.sendSegmentMessage` with the initial assessment prompt.
- Once at least one message exists, show the message thread (reuse `ArcMessageView`) and `ArcInputBar` for follow-ups.
- Wrap scroll-to-bottom in `withAnimation(.easeOut(duration: 0.1))` (ux-audit Phase B).
- Messages are session-scoped — cleared on view disappear (or just let them go when navigating away).

---

### Commit 7 — Settings polish
**Status: pending**

`EnzoApp/Features/Onboarding/SettingsSheet.swift` (ux-audit Phase C):
- Always show last-synced timestamp as the `sublabel` on the Sync row (not just when syncing).
- Add `.confirmationDialog` before "Reset sync history" executes.
- Change "Disconnect Strava" icon + label color from `Color.enzoAmber` to `Color(.systemRed)`.
- Add `.confirmationDialog` before disconnect executes.

---

## UX Audit Coverage

Items from `ux-audit.md` addressed by this initiative:

| Phase | Item | Addressed in |
|---|---|---|
| A | Delete MonthDetailSheet | Commit 1 |
| A | Delete PromptChipsView | Commit 1 |
| B | Streaming scroll animation | Commit 6 |
| B | Path B sort (strikeLabelColor) | Moot — GoalSettingView deleted |
| C | Last synced always visible | Commit 7 |
| C | Confirm before reset | Commit 7 |
| C | Disconnect → systemRed + confirm | Commit 7 |
| D | Segment rows → Button | Commit 3 |
| D | Remove alternating row backgrounds | Commit 3 |
| E | Navigation refactor (remove tabs) | Commit 2 |

Remaining ux-audit phases (D touch targets, F onboarding polish, G chart polish, H typography, I empty states, J dark mode) are deferred to subsequent sessions.

---

## Deferred (carry forward)

- **Demo jitter in SyncService** — ±0.25 deterministic noise. Do not remove without Chad's instruction.
- **phase2ActivityLimit = 25** — do not raise without Chad's instruction.
- **Dark mode (Phase J)** — requires design decisions on dark color palette before starting.
- **Step 12: Strava webhooks** — not needed for beta.
- **UAT: SwiftData migration** — 5-step device checklist, still pending.
- **ux-audit Phases D (remaining), F, G, H, I** — deferred to next session.
