# Kickoff Prompt — UX Polish Session

Paste this into a new Claude Code session to kick off the next work session.

---

## Prompt

You are continuing work on **Enzo**, a personal iOS cycling companion app (SwiftUI, iOS 17+, Swift 6). This is a planning + implementation session for UX polish.

**Start by reading these files in full before doing or saying anything else:**
1. `Claude.MD` — project rules, stack, build status, hard rules
2. `handoff.MD` — what was done last session and what to do next
3. `ux-audit.md` — the full UX/UI audit with the 10-phase work plan we'll be executing

Do NOT read `scratch.md`.

---

## What happened last session

We did a comprehensive iOS UX/UI audit of every screen in the app. Chad reviewed the audit and annotated 27 items with "--> DO THIS:" markers — confirming he wants all of them addressed. I organized the 27 items into a 10-phase work plan in `ux-audit.md`. **No code was written** — this was entirely a planning session.

## What to do this session

**First: ask Chad** whether he wants to start UX polish (Phases A–C of `ux-audit.md`) or first complete the SwiftData UAT checklist that has been pending since two sessions ago. Don't assume — ask.

If UX polish:
- Start with **Phase A** (safe deletes), then **Phase B** (bug fixes), then **Phase C** (settings polish).
- Full details for each phase are in `ux-audit.md` and `handoff.MD`.
- After A, B, C, ask Chad before continuing to Phase D.

If UAT:
- The SwiftData migration UAT is a 5-step device checklist (fresh install → persistence → goal persistence → reset + re-sync → disconnect + reconnect). Guide Chad through each step one at a time. Stop and wait for him to test before moving to the next step.

## Non-negotiable rules for this session

1. **Do NOT write a single line of code without presenting your plan first and getting explicit approval from Chad.** Before touching any file, describe exactly what you're going to change (file name, what's being removed/added/modified) and wait for a green light. Do not start implementing while presenting the plan.

2. **Commit after every single logical change.** One change = one commit. Descriptive message. Do not batch multiple changes into one commit. This lets Chad revert individual changes cleanly.

3. **Stop and prompt Chad whenever he needs to do something manually** — build the app, test on device, run through a UI flow, etc. Do not continue past a manual step. Wait for his confirmation before proceeding.

4. **Read `ux-audit.md` carefully** before proposing any implementation. Each phase has specific files and specific changes. Don't improvise beyond what's in the plan without flagging it.

5. **Build must compile before every commit.** Do not commit code that doesn't build.

## Quick reference: Phase A, B, C scope

### Phase A — Safe deletes
- `FitnessChartView.swift`: remove chart tap interaction (the `chartOverlay` block + `selectedSnapshot` state)
- `MonthDetailSheet.swift`: delete the file entirely
- `PromptChipsView.swift`: delete the file entirely

### Phase B — Bug fixes
- `GoalSettingView.swift`: sort Path B segments by `strikeScore` before `.prefix(3)`
- `ArcView.swift`: wrap streaming scroll-to-bottom in `withAnimation(.easeOut(duration: 0.1))`
- `GoalSettingView.swift`: fix `strikeLabelColor()` to map the current 5-tier labels

### Phase C — Settings polish (all in `SettingsSheet.swift`)
- Always show last-synced timestamp on the Sync row
- Add `.confirmationDialog` before "Reset sync history" executes
- Change "Disconnect Strava" to `.systemRed` + add `.confirmationDialog`

Full phase descriptions, affected files, and notes are in `ux-audit.md`.
