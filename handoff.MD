# Session Handoff — UAT: SwiftData Migration (next session)

## What was completed this session

| Change | Details | Commit |
|---|---|---|
| Project moved to `/Users/chadallen/projects/EnzoApp` | Build verified against iPhone 17 Pro sim (Xcode 26, iOS 26.3.1) | — |
| Gitignore | Added `.claude/settings.json`, `__pycache__/`, `*.MP4` | f02f8d3 |
| PRD.md | Section 3 backend updated from "Supabase" to "SwiftData" | 00e76be |
| NaN fix in FitnessRingView | `max(0.001, ...)` guard on both SectorMark angles — prevented CoreGraphics NaN crash on empty state | 852ee96 |
| Swift 6 concurrency warnings | `nonisolated(unsafe)` on static lets, `nonisolated` on static methods, `Sendable` + `nonisolated init` on DTOs — zero warnings now | 20441ea, 78e0d1f |
| ConnectView redesign | Real app icon (EnzoIcon imageset), welcome copy from `Config.connectWelcomeText`, plain "Connect" button | 6117730 |
| Kickoff prompt created | `kickoff-prompt.MD` added | f02f8d3 |

---

## Architecture (SwiftData, unchanged)

```
AppState.loadContext()  → ModelContext.fetch(FitnessSnapshotModel) → SwiftData (on-device)
SyncService.syncPhase1() → returns [FitnessSnapshotRow] to AppState
AppState.syncPhase1()   → calls upsertSnapshot() for each row → ModelContext
SyncService.syncPhase2(fitnessSnapshots:) → returns [SegmentScoreRow] to AppState
AppState.syncPhase2()   → calls upsertSegmentScore() for each row → ModelContext
AppState.setGoal()      → ModelContext.insert(GoalModel) directly
authenticate()          → Strava OAuth only, no Supabase call, no UUID
```

---

## Current app state

All changes committed and pushed. Branch: `main`. Working tree clean.

**Build status:** BUILD SUCCEEDED (iPhone 17 Pro simulator, Xcode 26, iOS 26.3.1), zero warnings  
**Test status:** All tests pass except 2 pre-existing failures unrelated to migration:
- `SegmentScorerTests/lowScoreWhenLessFitThanPR()` — pre-existing
- `AthleteContextTests/contextPayloadHistoryOrder()` — pre-existing

**Runtime logging:** Active via `NSLog` throughout AppState. Stream with:
```bash
log stream --predicate 'process == "EnzoApp"' --level debug
```

---

## Next session: UAT — SwiftData migration acceptance testing

The migration code is complete but has never been run against live Strava data on a real device. **The agent's job is to guide Chad through the checklist and fix any bugs found.** No new features until UAT passes.

### UAT checklist

Run these in order. Each must pass before moving to the next.

**1. Fresh install**
- Delete the app from the device
- Build and install fresh (new ConnectView will show)
- Connect Strava (OAuth flow)
- Run Phase 1 + Phase 2 sync (onboarding flow)
- Verify: fitness chart populates with real data
- Verify: Targets tab shows segment list with real segments
- Verify: Strike scores and labels are correct

**2. Persistence across relaunch**
- Force-quit the app
- Reopen
- Verify: fitness chart still shows — no blank state, no re-sync needed
- Verify: segments still load — data survived relaunch

**3. Goal persistence**
- Set a goal segment in Targets tab
- Force-quit, reopen
- Verify: same goal segment is still active

**4. Reset sync + re-sync**
- Settings → Reset sync history
- Verify: local store wiped (segments + chart revert to preview/empty)
- Sync now (manual sync from settings)
- Verify: data repopulates correctly

**5. Disconnect + reconnect**
- Settings → Disconnect
- Verify: app returns to ConnectView, all data cleared
- Reconnect Strava, run sync
- Verify: clean state, no stale data

### After UAT passes

Once all 5 checklist items pass, move on to deferred cleanup (in order):
1. `GoalSettingView.strikeLabelColor()` — maps old 3-tier labels, all fall through to amber
2. `enzo-voice.MD` stale labels — fix before any prompt work
3. Step 11b: Enzo voice/prompt tuning — playground first, never touch ClaudeService.swift without it

---

## Key files

| File | What it does |
|---|---|
| `EnzoApp/Models/SwiftDataModels.swift` | @Model classes + ModelContainer.enzo |
| `EnzoApp/App/AppState.swift` | loadContext, loadSegments, syncPhase1/2, setGoal, upsert helpers |
| `EnzoApp/Services/SyncService.swift` | Phase 1 + Phase 2 sync logic |
| `EnzoApp/Features/Onboarding/ConnectView.swift` | New onboarding screen |
| `EnzoApp/Utils/Config.swift` | API keys + `connectWelcomeText` UI copy |
| `migration-supabase-to-swiftdata.md` | Full migration architecture reference |

---

## Working rules for next agent

- **Read CLAUDE.md and handoff.MD before doing anything.**
- **Do NOT read scratch.md or UI-punch-list.md.**
- **Do not write a single line of code without presenting a plan and getting explicit approval from Chad.**
- **Prompt Chad when he needs to test on device or perform a manual action** — stop and wait, don't continue past a manual step.
- Make frequent small commits — one change per commit, descriptive message.
- Build must compile before any commit. Run `xcodebuild test` before marking any fix done.

---

## Deferred items (carry forward)

- **Demo jitter in SyncService** — `±0.25` deterministic noise seeded from `segId` in `syncPhase2`. Tagged "DEMO — Remove before shipping." Do not remove until Chad explicitly approves.
- **`enzo-voice.MD` stale labels** — system prompt section has old fitness labels. Fix before any prompt work in Step 11b.
- **GoalSettingView.strikeLabelColor()** — maps old 3-tier labels, all 5-tier labels fall through to amber.
- **phase2ActivityLimit = 25** — do not raise without Chad's instruction.
- **FitnessChartView axis polish** — x-axis label overlap, Y-axis hidden.
- **Sync progress indicator** — no visible indicator during manual sync from SettingsSheet.
- **Empty state UI** — After fresh install with no sync, fitness ring and chart show blank/grey with no explanation. Should show a prompt when `snapshots.isEmpty`. Deferred.
- **Step 12: Strava webhooks** — not needed for beta.
