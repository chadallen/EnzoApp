# Session Handoff — UX Polish (next session)

## What was completed this session

| Change | Details |
|---|---|
| iOS UX/UI audit | Full audit of every view against iOS HIG. Created `ux-audit.md` — 27 annotated items Chad marked "--> DO THIS:", organized into 10 phases (A–J) |
| `Claude.MD` updated | Build status, UI hard rule (dark mode planned), deferred items now reference `ux-audit.md` |
| No code was written | This was a planning/audit session only |

---

## Priority question for next session

**Ask Chad at the start:** Do you want to start UX polish (Phases A–C of `ux-audit.md`) or first complete the SwiftData UAT checklist from the previous handoff?

The UAT checklist is still fully pending (5-step device test, details in git history or the previous handoff). Recommend asking before diving in.

---

## Next session work: `ux-audit.md` Phases A, B, C

If Chad wants to do UX work, start with these three phases in order. They are all low-risk, contained, and can be done without device testing.

### Phase A — Safe deletes (no design decisions, just removal)

1. **Remove chart tap interaction from `FitnessChartView.swift`** — delete the entire `chartOverlay` block (the `GeometryReader` + `onTapGesture` that sets `selectedSnapshot`) and the `.sheet(isPresented: $showingDetail)` modifier. Also remove `@State private var selectedSnapshot` and `@State private var showingDetail`.
2. **Delete `MonthDetailSheet.swift`** — it was only used by the chart tap.
3. **Delete `PromptChipsView.swift`** — Chad confirmed: no prompt chips.

### Phase B — Bug fixes (one-liners and near-one-liners)

4. **Path B top segments sort** — In `GoalSettingView.pathBList`, change `appState.segments.prefix(3)` to `appState.segments.sorted { $0.strikeScore > $1.strikeScore }.prefix(3)`.
5. **Streaming scroll animation** — In `ArcView.scrollContent`, wrap the `onChange(of: appState.streamingText)` scroll call in `withAnimation(.easeOut(duration: 0.1)) { ... }`.
6. **`strikeLabelColor()` stale labels** — In `GoalSettingView`, update the switch to match the current 5-tier labels: "Strike now", "Almost there", "Worth a shot", "Getting there", "Build first". Map to `.enzoGoal`, `.enzoChartPrimary`, `.enzoAmber`, `.enzoSecondary`, `.enzoSecondary` respectively.

### Phase C — Settings polish (all changes in `SettingsSheet.swift`)

7. **Show "last synced" always** — Change the Sync row so `sublabel` always shows the last synced timestamp, not just when syncing. Pass `lastSyncedText` (not `nil`) when not actively syncing.
8. **Confirm before "Reset sync history"** — Add `.confirmationDialog` gating the reset action.
9. **Disconnect: systemRed + confirmation** — Change `isDestructive` rows to use `Color(.systemRed)` instead of `Color.enzoAmber`. Add `.confirmationDialog` before executing disconnect.

### After A, B, C

Ask Chad whether to continue to Phase D (touch targets) or do the SwiftData UAT. Full phase descriptions are in `ux-audit.md`.

---

## Current app state

All changes committed and pushed. Branch: `main`. Working tree clean.

**Build status:** Should be BUILD SUCCEEDED — no code was touched this session, last known good build was from the prior session (iPhone 17 Pro simulator, Xcode 26, iOS 26.3.1, zero warnings).

---

## Key files

| File | What it does |
|---|---|
| `ux-audit.md` | Full UX/UI audit + 10-phase work plan — the primary reference for next session |
| `EnzoApp/Features/Arc/FitnessChartView.swift` | Phase A: remove chart tap overlay |
| `EnzoApp/Features/Arc/MonthDetailSheet.swift` | Phase A: delete this file |
| `EnzoApp/Features/Arc/PromptChipsView.swift` | Phase A: delete this file |
| `EnzoApp/Features/Arc/GoalSettingView.swift` | Phase B: Path B sort + strikeLabelColor fix |
| `EnzoApp/Features/Arc/ArcView.swift` | Phase B: streaming scroll animation |
| `EnzoApp/Features/Onboarding/SettingsSheet.swift` | Phase C: last synced, confirmations, systemRed |

---

## Working rules for next agent

- **Read `Claude.MD`, `handoff.MD`, and `ux-audit.md` before doing anything.**
- **Do NOT read `scratch.md`.**
- **Do not write a single line of code without presenting a plan and getting explicit approval from Chad.** Present the specific changes you plan to make (what files, what lines, what the change is) and wait for a green light.
- **Commit after every single logical change** — one change per commit, descriptive message. Do not batch.
- **Prompt Chad when manual testing is needed** — stop and wait, do not continue past a manual step.
- Build must compile before any commit.
- Use `NSLog()` not `print()` for any debug logging.

---

## Deferred items (carry forward)

- **Demo jitter in SyncService** — `±0.25` deterministic noise in `syncPhase2`. Do not remove without Chad's approval.
- **`enzo-voice.MD` stale labels** — Fix before any prompt work in Step 11b.
- **phase2ActivityLimit = 25** — do not raise without Chad's instruction.
- **Dark mode (Phase J)** — Requires design decisions first (see `ux-audit.md` Phase J table). Do not start without explicit approval and the dark color palette defined.
- **Step 12: Strava webhooks** — not needed for beta.
