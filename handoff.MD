# Session Handoff — SwiftData Migration UAT (next session)

## What was completed this session (Supabase → SwiftData migration)

| Change | Files touched | Commits |
|---|---|---|
| SwiftData @Model classes + shared ModelContainer | `Models/SwiftDataModels.swift` (new) | 87ec584 |
| SyncService: removed supabaseService, returns data instead of writing | `Services/SyncService.swift` | 87ec584 |
| AppState: removed supabaseUserId + supabaseService, wired ModelContext | `App/AppState.swift` | 87ec584 |
| EnzoAppApp: inject .modelContainer(ModelContainer.enzo) | `EnzoAppApp.swift` | 87ec584 |
| Deleted SupabaseService.swift | `Services/SupabaseService.swift` (deleted) | 87ec584 |
| Updated Supabase DTO comments to be storage-agnostic | `Models/FitnessSnapshot+Supabase.swift`, `SegmentScore+Supabase.swift`, `Goal+Supabase.swift`, `AthleteContext.swift` | 87ec584 |
| Cleaned Config.swift, KeychainHelper, Info.plist (removed Supabase keys) | `Utils/Config.swift`, `Utils/KeychainHelper.swift`, `Info.plist` | 87ec584 |
| xcconfig: removed SUPABASE_HOST, SUPABASE_URL, SUPABASE_ANON_KEY | `Config/Debug.xcconfig`, `Config/Release.xcconfig` (gitignored) | — |
| Updated SyncServiceTests: removed userId param from computeSnapshots calls | `EnzoAppTests/SyncServiceTests.swift` | 87ec584 |
| Replaced SupabaseServiceTests with row DTO unit tests | `EnzoAppTests/SupabaseServiceTests.swift` | 87ec584 |
| Added migration plan doc | `migration-supabase-to-swiftdata.md` (new) | 87ec584 |
| Inline documentation pass on all modified files | `SwiftDataModels.swift`, `AppState.swift`, `SyncService.swift` | bf798a0 |

---

## Architecture changes — what moved where

### Before
```
AppState.loadContext()  → SupabaseService (HTTP GET) → Supabase REST API
SyncService.syncPhase1() → writes FitnessSnapshotRow via SupabaseService
SyncService.syncPhase2() → reads + writes via SupabaseService
AppState.setGoal()      → SupabaseService.saveGoal() (HTTP POST)
authenticate()          → SupabaseService.createUser() → gets UUID back
```

### After
```
AppState.loadContext()  → ModelContext.fetch(FitnessSnapshotModel) → SwiftData (on-device)
SyncService.syncPhase1() → returns [FitnessSnapshotRow] to AppState
AppState.syncPhase1()   → calls upsertSnapshot() for each row → ModelContext
SyncService.syncPhase2(fitnessSnapshots:) → returns [SegmentScoreRow] to AppState
AppState.syncPhase2()   → calls upsertSegmentScore() for each row → ModelContext
AppState.setGoal()      → ModelContext.insert(GoalModel) directly
authenticate()          → Strava OAuth only, no Supabase call, no UUID
```

### Key design decisions
- **No user_id foreign key** — single-user device, every model instance implicitly belongs to the authenticated athlete
- **No supabaseUserId** — removed from AppState, Keychain, authenticate(), and all sync guards
- **SyncService owns no persistence** — it computes and returns; AppState owns ModelContext and writes
- **Upsert pattern** — fetch by unique key (month or stravaSegmentId), update fields if found, insert if not
- **Identity** — `strava_athlete_id` in Keychain only. Display name + last activity date → UserDefaults
- **CloudKit path** — swapping `ModelConfiguration(isStoredInMemoryOnly: false)` for `ModelConfiguration(cloudKitContainerIdentifier:)` enables iCloud sync with one line change

---

## Current app state

All changes committed and pushed. Working tree is clean. Branch: `main`.

**Build status:** BUILD SUCCEEDED (tested against iPhone 17 Pro simulator)  
**Test status:** All tests pass except 2 pre-existing failures unrelated to this migration:
- `SegmentScorerTests/lowScoreWhenLessFitThanPR()` — pre-existing
- `AthleteContextTests/contextPayloadHistoryOrder()` — pre-existing

---

## Next session: UAT — SwiftData migration acceptance testing

The migration has not been run on a real device against live Strava data. The next session is acceptance testing. **The agent's job is to guide Chad through the checklist and fix any bugs found.** No new features until UAT passes.

### UAT checklist

Run these in order. Each one must pass before moving to the next.

**1. Fresh install**
- Delete the app from the device
- Build and install fresh
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
- Verify: no network calls to Supabase (it's gone — any Supabase errors would indicate stale code)

**3. Goal persistence**
- Set a goal segment in Targets tab
- Force-quit
- Reopen
- Verify: same goal segment is still active (marked with goal indicator)

**4. Reset sync + re-sync**
- Settings → Reset sync history
- Verify: local store is wiped (segments and fitness chart should revert to preview/empty)
- Sync now (manual sync from settings)
- Verify: data repopulates correctly

**5. Disconnect + reconnect**
- Settings → Disconnect
- Verify: app returns to ConnectView, all data cleared
- Reconnect Strava
- Run sync again
- Verify: clean state, no stale data from previous session

### After UAT passes

Once all 5 checklist items pass, move on to deferred cleanup (in order):
1. `GoalSettingView.strikeLabelColor()` — maps old 3-tier labels, all fall through to amber. One-line fix per label.
2. `enzo-voice.MD` stale labels — update system prompt section with current 5-tier fitness + readiness labels before any prompt work
3. Step 11b: Enzo voice/prompt tuning — use `scripts/enzo_playground.py` first, never touch ClaudeService.swift without playground validation

---

## Key files for next session

| File | What it does |
|---|---|
| `EnzoApp/Models/SwiftDataModels.swift` | @Model classes + ModelContainer.enzo — the persistence schema |
| `EnzoApp/App/AppState.swift` | loadContext, loadSegments, syncPhase1/2, setGoal, upsert helpers |
| `EnzoApp/Services/SyncService.swift` | Phase 1 returns (count, snapshots, lastActivityDate); Phase 2 takes fitnessSnapshots, returns [SegmentScoreRow] |
| `migration-supabase-to-swiftdata.md` | Full migration plan with architecture diagrams — good reference |

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

- **Demo jitter in SyncService** — `±0.25` deterministic noise seeded from `segId` in `syncPhase2`. Marked "DEMO — Remove before shipping." Do not remove until Chad explicitly approves.
- **`enzo-voice.MD` stale labels** — system prompt section has old fitness labels (Peak shape, Strong base...) and old readiness labels. Fix before any prompt work in Step 11b.
- **GoalSettingView.strikeLabelColor()** — maps old 3-tier labels, all 5-tier labels fall through to amber.
- **phase2ActivityLimit = 25** — do not raise without Chad's instruction.
- **FitnessChartView axis polish** — x-axis label overlap, Y-axis hidden.
- **Sync progress indicator** — no visible indicator in main UI during manual sync from SettingsSheet.
- **Step 12: Strava webhooks** — not needed for beta.
