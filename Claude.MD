# Enzo — Project Brief for Claude Code

Enzo is a personal iOS cycling companion. It connects to Strava, computes a relative fitness score from HR history, and uses an AI companion (also named Enzo) to narrate training and surface PR opportunities via per-segment chat.

Product spec: `PRD.md`. Build status and what to work on next: `plan.md`.
Build gotchas: `.claude/rules/build-notes.md` — check before making changes in any area covered there.

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

**UI** — Light and dark mode will both be supported (Phase J of `ux-audit.md`). Until Phase J is complete, the app is forced to light mode via `.preferredColorScheme(.light)` — do not remove this yet. Background `#FAFAFA`, cards `#F7F7FA`, primary `#000000`, secondary `#666666`, accent `#FC5201`. All colors via `Color.enzoXxx` constants — never raw hex in views. No streaks, no guilt, no missed-workout states.

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

Identity is `strava_athlete_id` in Keychain only — no remote user table.

---

## Prompt Playground

Iterate on Enzo's prompts without building the app. Use this before touching `ClaudeService.swift` or `AppState.swift`.

```bash
python3 scripts/enzo_playground.py --mode chat --message "What should I do this week?"
```

Full usage: `scripts/README.md`. Requires `ANTHROPIC_API_KEY` in env.
When happy with a prompt, paste it into `ClaudeService.swift` → `systemPrompt` or `AppState.swift` → `segmentAssessmentPrompt`.

---

## How to Work

**Starting a session** — Read this file + `plan.md`. `plan.md` has current status and what to work on next.

**Unclear requirement** — `PRD.md` is the product spec. Ask before building if it doesn't cover it.

**Spec conflicts with what's built** — Flag it. Don't silently pick one.

**End of session** — Use `/end-session` skill to update `plan.md`, commit, and push.

**GitHub** — https://github.com/chadallen/EnzoApp (private)
