# Enzo — Project Brief for Claude Code

Enzo is a personal iOS cycling companion. It connects to Strava, computes a relative fitness score from HR history, and uses an AI companion (also named Enzo) to narrate training and surface PR opportunities via per-segment chat.

Product spec: `PRD.md`. Build status and what to work on next: `plan.MD`.
Build gotchas: `.claude/rules/build-notes.md` — check before making changes in any area covered there.
Design system: `docs/enzo-design.md` — color tokens, typography, components, layout rules.

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

Test command: `xcodebuild test -scheme EnzoApp -destination 'platform=iOS Simulator,name=iPhone 17'` (~5 min cold). If build artifacts are warm from the same session, use `test-without-building` instead (~30s). Pre-boot the simulator once per session: `xcrun simctl boot "iPhone 17"`. Don't re-run the full suite at end-session if build-tasks already verified them this session.

**UI** — Light and dark mode supported (Phase J complete). Adaptive colors use `UIColor { traits in }` closures in `Color+Enzo.swift`. Accent `#FC5201` is fixed across modes; bg/card/primary/secondary are adaptive. `enzoUserBubble` is always a dark surface — use `.white` text on it, not `enzoPrimary`. All colors via `Color.enzoXxx` — never raw hex in views. No streaks, no guilt, no missed-workout states.

**Commits** — One thing per commit. If the message needs "and", split it. Commit before moving to the next step.

---

## Skills

Read the relevant skill file before starting that type of work.

| Task | Read |
|---|---|
| Building any view | `docs/enzo-design.md` + global `swift-design` skill |
| Writing UI copy or Enzo responses | `skills/enzo-voice/skill.MD` |
| Architecture decisions or new files | global `swift-patterns` skill |
| Logic, services, data transformation | `skills/testing/skill.md` |
| Testing a UI flow end-to-end | Use `ios-ui-test` skill (global) |

---

## Persistence Layer (SwiftData)

All derived data is stored on-device via SwiftData. No remote backend. Models live in `EnzoApp/Models/SwiftDataModels.swift`:

- `ActivityModel` — one Strava cycling activity, TSS computed on ingest, keyed on stravaId (unique)
- `DailyFitnessModel` — CTL/ATL/TSB values, one row per calendar day, keyed on date (unique)
- `StarredSegmentModel` — segments starred on Strava or ridden within 90 days, keyed on segmentId (unique)
- `SegmentEffortModel` — one effort per segment ride, keyed on stravaEffortId (unique)
- `SegmentFitnessModel` — per-segment OLS regression state (β coefficients, σ, PR time), keyed on segmentId (unique)
- `GoalModel` — active/historical goals, isActive flag, one active at a time

**Container:** `ModelContainer.enzo` (shared singleton in SwiftDataModels.swift)
**Access:** `AppState.modelContext` (mainContext, @MainActor)
**Upsert pattern:** fetch-first by unique key, update fields or insert new
**Wipe on reset:** `AppState.resetSyncHistory()` deletes all models except GoalModel
**Wipe on disconnect:** `AppState.disconnect()` deletes all six model types

Identity is `strava_athlete_id` in Keychain only — no remote user table.

---

## How to Work

**Starting a session** — Use `/start-session`. It reads this file, `plan.MD`, and beads state to orient and propose a plan.

**Unclear requirement** — `PRD.md` is the product spec. Ask before building if it doesn't cover it.

**Spec conflicts with what's built** — Flag it. Don't silently pick one.

**End of session** — Use `/end-session` to update `plan.MD`, commit, and push.

**GitHub** — https://github.com/chadallen/EnzoApp (private)

---

## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd ready` for next tasks.

Skills: `/start-session`, `/end-session`, `/adr`
