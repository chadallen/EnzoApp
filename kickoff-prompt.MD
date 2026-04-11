# Kickoff Prompt — Paste This Into Next Session

---

Read `CLAUDE.md` and `handoff.MD` before doing anything else. Do NOT read `scratch.md` or `UI-punch-list.md`.

## Where we are

Enzo is a personal iOS cycling app that connects to Strava, computes fitness scores from HR data, and uses an AI companion (named Enzo) to narrate training trajectory and surface PR opportunities.

We recently completed a **Supabase → SwiftData migration** — all persistence moved from remote Supabase REST API to on-device SwiftData (SQLite). The migration code is complete and committed (commits 87ec584 + bf798a0). The build compiles and unit tests pass. **However, the migration has never been tested against live Strava data on a real device.**

Last session we moved the project directory from `/Users/chadallen/EnzoApp` to `/Users/chadallen/projects/EnzoApp` and verified the build still succeeds (iPhone 17 Pro simulator, Xcode 26, iOS 26.3.1).

## What needs to happen now

**UAT (User Acceptance Testing) for the SwiftData migration.** Guide me through the 5-step checklist in `handoff.MD`. Fix any bugs found along the way.

The checklist:
1. Fresh install — delete app, reinstall, connect Strava, sync, verify data populates
2. Persistence across relaunch — force-quit, reopen, verify data survives
3. Goal persistence — set goal, force-quit, verify it sticks
4. Reset sync + re-sync — wipe via Settings, re-sync, verify repopulation
5. Disconnect + reconnect — full disconnect, reconnect, verify clean state

After UAT passes, move to deferred cleanup:
1. Fix `GoalSettingView.strikeLabelColor()` (maps old 3-tier labels)
2. Fix stale labels in `enzo-voice.MD`
3. Step 11b: Enzo voice/prompt tuning

## Rules for this session

- **Do NOT write a single line of code without presenting a plan and getting my explicit approval.**
- **Prompt me when I need to test something on device or perform a manual action.** Stop and wait for my response — do not continue past a manual step.
- **Make FREQUENT commits with good descriptive messages** — one thing per commit, so we can easily revert individual changes.
- Build must compile before any commit. Run tests before marking any fix done.
- Key files: `EnzoApp/Models/SwiftDataModels.swift`, `EnzoApp/App/AppState.swift`, `EnzoApp/Services/SyncService.swift`
- Reference: `migration-supabase-to-swiftdata.md` has the full migration plan and architecture diagrams
