# Enzo — Project Brief for Claude Code

Enzo is a personal iOS cycling companion. It connects to Strava, computes a relative fitness score from HR history, and uses an AI companion (also named Enzo) to narrate training trajectory and surface PR opportunities.

Full spec: `PRD.md`. Preview data for Steps 1–5: Section 18 of spec — use exact values, don't invent.
Build gotchas: @.claude/rules/build-notes.md — check before making changes in any area covered there.

---

## Stack

- **iOS 17+, SwiftUI only.** No UIKit. No third-party UI libraries.
- **Swift Charts** for all data visualization.
- **`@Observable` + `async/await`** throughout. No Combine, no older state patterns.
- **SwiftData** for local persistence (derived metrics only — never raw Strava data). No Supabase.
- **Anthropic Claude API** (`claude-sonnet-4-6`) for AI features.
- **Strava OAuth 2.0** for authentication and data access.
- **No third-party dependencies** unless the spec explicitly names one.

---

## Hard Rules

**Naming** — The AI companion is **Enzo** in all user-facing code and copy. Never use "Claude", "AI", or "assistant" anywhere the user can see.

**Secrets** — Never hardcode keys. All secrets: `Config/Debug.xcconfig` → Info.plist → `Utils/Config.swift`. User tokens: Keychain via `KeychainHelper.swift`. xcconfig files are gitignored — never commit them.

**Data** — Never store raw Strava activity data. Compute in memory, write only derived output to the local SwiftData store.

**Testing** — Write unit tests alongside every logic file. Swift Testing (not XCTest). Test pure functions only. Every view needs a `#Preview` with hardcoded data. Run tests before marking any step done.

**UI** — Light mode only. Background `#FAFAFA`, cards `#F7F7FA`, primary `#000000`, secondary `#666666`, accent `#FC5201`. All colors via `Color.enzoXxx` constants — never raw hex in views. No streaks, no guilt, no missed-workout states.

**Commits** — One thing per commit. If the message needs "and", split it. Commit before moving to the next step.

---

## Skills

Read the relevant skill file before starting that type of work.

| Task | Read |
|---|---|
| Building any view | `skills/swift-design.MD` |
| Writing UI copy or Enzo responses | `skills/enzo-voice.MD` |
| Architecture decisions or new files | `skills/swift-patterns.MD` |
| Logic, services, data transformation | `skills/testing.md` |

---

## Build Status

- [x] Steps 1–9: Project setup → Phase 2 sync + segment scoring
- [x] Step 10: Onboarding flow (ConnectView, SyncProgressView, auth gating)
- [x] Step 11: Polish pass
- [x] UI Refactor: light mode, top-tab nav (Today/Targets)
- [x] Today tab: FitnessRingView donut, chart timeframe picker, dynamic Y scale
- [x] Targets tab: GoalHeaderView header, SegmentDetailView as goal-setting entry point, distance/elevation wired
- [x] Score cleanup: % removed, percentile normalization, recency discount removed
- [x] Score UI: 5-tier readiness labels, dual donuts, 0.75 parity, goal overwrite bug fixed
- [x] Readiness differentiation: PR age bonus + effort gap modifier, demo jitter, dark mode fix, chip colors
- [x] Persistence migration: Supabase → SwiftData (local on-device SQLite)
- [ ] **UAT: SwiftData migration acceptance testing** ← next session
- [ ] Step 11b: Enzo voice/prompt tuning
- [ ] Step 12: Strava webhooks (deferred — not needed for beta)

---

## Deferred Items

- **Demo jitter in SyncService** — ±0.25 deterministic noise in `syncPhase2`. Remove before shipping.
- **`enzo-voice.MD` stale labels** — system prompt section has old fitness + readiness label names. Fix in Step 11b before touching any prompts.
- **GoalSettingView.strikeLabelColor()** — maps old 3-tier labels, all fall through to amber. Fix in Step 11b.
- **phase2ActivityLimit = 25** — do not raise without Chad's instruction.
- **FitnessChartView axis polish** — x-axis label overlap, Y-axis hidden. Needs dedicated time.
- **Sync progress indicator** — no visible indicator in main UI during manual sync from SettingsSheet.
- **Step 12: Strava webhooks** — not needed for beta.

---

## Persistence Layer (SwiftData)

All derived data is stored on-device via SwiftData. No remote backend. Models live in `EnzoApp/Models/SwiftDataModels.swift`:

- `FitnessSnapshotModel` — monthly fitness history, keyed on month Date (unique)
- `SegmentScoreModel` — segment PRs + strike scores, keyed on stravaSegmentId (unique)
- `GoalModel` — active/historical goals, isActive flag, one active at a time

**Container:** `ModelContainer.enzo` (shared singleton in SwiftDataModels.swift)  
**Access:** `AppState.modelContext` (mainContext, @MainActor)  
**Upsert pattern:** fetch-first by unique key, update fields or insert new — see `AppState.upsertSnapshot()` and `upsertSegmentScore()`  
**Wipe on reset:** `AppState.resetSyncHistory()` deletes all FitnessSnapshotModel + SegmentScoreModel rows  
**Wipe on disconnect:** `AppState.disconnect()` deletes all three model types

Identity is `strava_athlete_id` in Keychain only — no Supabase UUID, no remote user table.

---

## Prompt Playground

Iterate on Enzo's prompts without building the app. Use this before touching `ClaudeService.swift` or `AppState.swift`.

```bash
python3 scripts/enzo_playground.py --mode chat --message "What should I do this week?"
python3 scripts/enzo_playground.py --mode briefing --fitness building --trend up
```

Full usage: `scripts/README.md`. Requires `ANTHROPIC_API_KEY` in env.
When happy with a prompt, paste it into: `ClaudeService.swift` → `systemPrompt` or `AppState.swift` → static prompt functions.

---

## How to Work

**Starting a session** — Read this file + `handoff.MD`. Check build status. Read relevant `PRD.MD` section for the current step.

**Unclear requirement** — Spec is source of truth. Ask before building if it doesn't cover it.

**Spec conflicts with what's built** — Flag it. Don't silently pick one.

**End of session** — Update build status here. Write handoff prompt to `handoff.MD`. Commit and push.

**GitHub** — https://github.com/chadallen/EnzoApp (private)
