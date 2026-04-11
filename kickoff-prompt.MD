# Kickoff Prompt — Paste This Into Next Session

---

Read `CLAUDE.md` and `handoff.MD` before doing anything else. Do NOT read `scratch.md` or `UI-punch-list.md`.

## Where we are

Enzo is a personal iOS cycling app that connects to Strava, computes fitness scores from HR data, and uses an AI companion (named Enzo, powered by Claude) to narrate training trajectory and surface PR opportunities.

**Stack:** iOS 17+, SwiftUI only, SwiftData for local persistence, Anthropic Claude API, Strava OAuth 2.0. No Supabase (removed), no UIKit, no third-party UI libs.

## What was done this session

- **Project moved** from `/Users/chadallen/EnzoApp` → `/Users/chadallen/projects/EnzoApp`. Build verified.
- **NaN crash fixed** in `FitnessRingView` — zero-angle SectorMark with `angularInset` produced CoreGraphics NaN on fresh install. Added `max(0.001, ...)` guard. (commit 852ee96)
- **Swift 6 concurrency warnings cleared** — Xcode 26 flags `static let` stored properties as implicitly `@MainActor`. Fixed with `nonisolated(unsafe)` on static lets, `nonisolated` on static methods, and explicit `nonisolated init(from:)` on DTO structs. Zero warnings now. (commits 20441ea, 78e0d1f)
- **ConnectView redesigned** — real app icon (EnzoIcon imageset), welcome copy pulled from `Config.connectWelcomeText`, plain "Connect" button. (commit 6117730)
- Build is clean: BUILD SUCCEEDED, zero warnings, two pre-existing test failures unrelated to any of this work.

## What needs to happen next

**UAT (User Acceptance Testing) for the SwiftData migration.** The migration code is complete and has been for a couple sessions, but it has never been tested against live Strava data on a real device. Guide me through the 5-step checklist in `handoff.MD`. Fix any bugs found along the way.

The checklist (in order — each must pass before the next):
1. Fresh install — delete app, reinstall (will see new ConnectView), connect Strava, sync, verify data populates
2. Persistence across relaunch — force-quit, reopen, verify data survives without re-sync
3. Goal persistence — set goal, force-quit, verify it sticks
4. Reset sync + re-sync — wipe via Settings, re-sync, verify repopulation
5. Disconnect + reconnect — full disconnect, reconnect, verify clean state

After UAT passes, move to deferred cleanup (in order):
1. Fix `GoalSettingView.strikeLabelColor()` (maps old 3-tier labels)
2. Fix stale labels in `enzo-voice.MD`
3. Step 11b: Enzo voice/prompt tuning

## Rules for this session

- **Do NOT write a single line of code without presenting a plan and getting my explicit approval.**
- **Prompt me when I need to test something on device or perform a manual action.** Stop and wait — do not continue past a manual step.
- **Make FREQUENT commits with descriptive messages** — one thing per commit, so we can easily revert individual changes.
- Build must compile before any commit. Run tests before marking any fix done.
- Runtime logging is active — stream it with: `log stream --predicate 'process == "EnzoApp"' --level debug`

## Key files

- `EnzoApp/Models/SwiftDataModels.swift` — persistence schema
- `EnzoApp/App/AppState.swift` — loadContext, syncPhase1/2, setGoal, upsert helpers
- `EnzoApp/Services/SyncService.swift` — sync logic
- `EnzoApp/Features/Onboarding/ConnectView.swift` — new onboarding screen
- `EnzoApp/Utils/Config.swift` — API keys + `connectWelcomeText` copy
- `migration-supabase-to-swiftdata.md` — full migration architecture reference
