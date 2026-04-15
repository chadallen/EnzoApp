# Kickoff Prompt — Post-Redesign Polish Session

Paste this into a new Claude Code session to kick off the next work session.

---

## Prompt

You are continuing work on **Enzo**, a personal iOS cycling companion app (SwiftUI, iOS 17+, Swift 6). The previous session completed a major architectural redesign.

**Start by reading these files in full before doing or saying anything else:**
1. `CLAUDE.md` — project rules, stack, build status, hard rules
2. `handoff.MD` — what was done last session and what to do next
3. `plan.md` — the redesign initiative that was just completed (for context on what changed)

Do NOT read `scratch.md`.

---

## What happened last session

A **Segment-Focused Redesign** was executed — 7 commits, all on `main`, all pushed. This was a major pivot:

- **Deleted** all fitness ring, chart, briefing, and goal-setting views (`ArcView`, `FitnessRingView`, `FitnessChartView`, `ArcBriefingView`, `GoalHeaderView`, `LookaheadSuggestionView`, `GoalSettingView`, `MonthDetailSheet`, `PromptChipsView`, `PROpportunitiesCard`)
- **New main screen:** Segment list only (no fitness ring, no chart, no auto-briefing)
- **New segment detail:** Stats + readiness score + "Ask Enzo" button that opens a per-segment chat thread
- **Navigation simplified:** Single NavigationStack wrapping SegmentsView — no tabs
- **Onboarding simplified:** GoalSettingView gate removed — after sync completes, user goes directly to segment list
- **ClaudeService updated:** Multi-turn conversation history support added, stale readiness labels fixed
- **AppState cleaned up:** Briefing/lookahead code removed, `sendSegmentMessage()` and `segmentAssessmentPrompt()` added
- **SettingsSheet polished:** Last-synced always visible, confirm dialogs on reset and disconnect, disconnect button now red

Several ux-audit items (Phases A, B, C, D partial, E partial) were addressed as part of this redesign.

The **build has not been tested in the simulator** since the redesign. That should happen at the start of this session.

---

## What to do this session

**First: ask Chad** which of these he wants to start with:

1. **Build + smoke test** — run the app in the simulator, walk through the key flows (connect → sync → segment list → segment detail → Ask Enzo → settings). This is the recommended first step given the scope of change.
2. **Continue UX polish** — remaining phases: D (touch targets, reduce motion), E (double title fix, optional native nav bar), F (onboarding), H (typography), I (goal toast), J (dark mode — requires design decisions first).
3. **SwiftData UAT** — 5-step device checklist (fresh install → persistence → goal persistence → reset + re-sync → disconnect + reconnect). Still pending from earlier sessions.

Don't assume — ask Chad before doing anything.

---

## Non-negotiable rules for this session

1. **Do NOT write a single line of code without presenting your plan first and getting explicit approval from Chad.** Before touching any file, describe exactly what you're going to change (file name, what's being removed/added/modified) and wait for a green light. Do not start implementing while presenting the plan.

2. **Commit after every single logical change.** One change = one commit. Descriptive message. Do not batch multiple changes into one commit. This lets Chad revert individual changes cleanly.

3. **Stop and prompt Chad whenever he needs to do something manually** — build the app, test in simulator, run through a UI flow, test on device, etc. Do not continue past a manual step. Wait for his confirmation before proceeding.

4. **Build must compile before every commit.** Do not commit code that doesn't build.

5. **Use `NSLog()` not `print()`** — `print()` doesn't appear in the Sweetpad log stream.

---

## Quick reference: remaining UX polish work

### Phase D — Touch targets (partial, pending)
- Gear icon in `MainTabView.topBar`: add `.frame(width: 44, height: 44).contentShape(Rectangle())`
- Sort menu in `SegmentsView.sortBar`: verify 44pt tappable area
- Pulsing "Strike now" donut in `SegmentStrikeRow`: gate on `@Environment(\.accessibilityReduceMotion)`

### Phase E — Navigation fixes (partial, pending)
- `SegmentDetailView`: segment name appears in both `.navigationTitle` (inline) and the `headerSection` largeTitle — remove or shorten the inline title
- Optional: restore native nav bar in `MainTabView` (large-title-on-scroll behavior)

### Phase F — Onboarding polish (pending)
- `ConnectView`: replace `padding(.bottom, 52)` with `.safeAreaInset(edge: .bottom)`
- `SyncProgressView`: add `ProgressView()` spinner above phase text
- `ConnectView`: add 1–2 lines of privacy disclosure copy

### Phases H, I, J — Later
- **H:** Typography — replace fixed-size fonts with named styles
- **I:** Goal-set toast, empty state for fresh install
- **J:** Dark mode — requires design decisions before touching code
