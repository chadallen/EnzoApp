# Handoff — Session ending 2026-03-29

## What was completed this session

Step 7: Historical Sync Phase 1 — fully implemented, smoke-tested against real data, and committed.

**Commits this session:**
- `d936be2` — Add FitnessCalculator: efficiency, fitnessValue, trendDirection, fitnessLabel
- `a76e580` — Add SyncService: paginated Strava fetch, fitness snapshot computation
- `8800319` — Add isSyncing, supabaseUserId, syncPhase1() to AppState; persist userId in Keychain
- `9684e17` — Fix AppState: initialize SyncService in init() — lazy var incompatible with @Observable

**Build status:** 75 tests passing (up from 34). Build succeeds. App launches into ArcView with hardcoded data (live context is Step 8).

**Smoke test results:** Sync ran successfully on device. 97 rows written to `fitness_snapshots` in Supabase. All `trend_direction` values are `"flat"` — the ±0.05 threshold in `FitnessCalculator.trendDirection` may need tuning. Different fitness labels are present across months (Recovering, Baseline, Building, Strong, Epic) so the label bands are working. Trend threshold review is the first task in Step 8.

---

## What was built

### `FitnessCalculator.swift` (Utils/)
Pure static enum. No network, no state.
- `efficiency(distanceKm:elevationGainM:sportType:durationHours:avgHR:)` — returns nil if < 30 min or avgHR == 0; gravel gets ×1.15; elevation adds 0.01 km per metre
- `fitnessValue(recentEfficiencies:allTimeMin:allTimeMax:)` — normalizes 0.0–1.0
- `trendDirection(recentFourWeeks:priorFourWeeks:)` — "up"/"flat"/"down" at ±0.05 threshold (may need tuning — see smoke test note above)
- `fitnessLabel(for:)` — Epic/Strong/Building/Baseline/Recovering
- `cyclingTypes: Set<String>` — the 5 qualifying sport types

### `SyncService.swift` (Services/)
Swift actor. Key design: `isQualifying(_:)` and `computeSnapshots(from:userId:)` are static — testable without network.
- `syncPhase1(userId:)` — refresh token → paginate all activities → filter → compute → upsert to Supabase
- Pagination: 200/page, stops when batch < 200
- 2-month rolling window for fitness value; this month's rides only for hours/count stats
- Trend: last 4 weeks vs prior 4 weeks from month end; defaults to "flat" if either window is empty
- `avgEfficiency` is set on the FitnessSnapshotRow

### `AppState` updates
- `supabaseUserId: UUID?` — populated from `createUser()` return, persisted to Keychain as `"supabase_user_id"`
- `isSyncing: Bool` — set true during sync, false on completion
- `syncPhase1() async` — calls `SyncService.syncPhase1(userId:)`; errors are silently caught (Step 8 surfaces sync state in UI)
- `authenticate()` now stores the Supabase UUID (was discarding it in Step 6)
- Service init pattern: create `StravaService` and `SupabaseService` as local lets first, then pass to `SyncService` — required because `lazy var` is incompatible with `@Observable`

### `SupabaseService` update
- Added `fetchUserId(stravaAthleteId:)` — fallback lookup for pre-Step 7 users whose UUID wasn't cached in Keychain

---

## What comes next: Step 8 — Context Payload + Live Enzo

### Before writing any code, present a plan and get Chad's approval

Read these files in order, then present a written plan before touching any code:

1. **`CLAUDE.md`** — especially the Build Notes (lazy var, supabaseUserId, trend=flat observation)
2. **`PRD.MD` Section 5** — Claude Context Payload JSON shape
3. **`PRD.MD` Section 7** — Claude API integration details
4. **`PRD.MD` Section 8** — Arc content generation (briefing, lookahead)
5. **`skills/swift-patterns.MD`** — data flow section
6. **`skills/testing.md`** — AthleteContext test requirements

### What Step 8 involves

**Trend threshold review (first task):**
Before wiring live UI, look at the efficiency values in the `fitness_snapshots` Supabase table. If all 97 months show `"flat"`, the ±0.05 threshold in `FitnessCalculator.trendDirection` is likely too tight or the efficiency variance is small. Adjust and re-sync if needed.

**`AthleteContext+Live.swift` (or extend `AthleteContext.swift`):**
- `AthleteContext.fromSupabase(userId:supabaseService:)` async factory — reads `fitness_snapshots` and `goals` from Supabase, assembles a live `AthleteContext`
- `contextPayload(snapshots:segments:)` already exists — verify it produces the correct JSON shape from PRD Section 5

**`AppState` updates:**
- `loadLiveContext()` async — fetches live snapshots + goal from Supabase, builds live `AthleteContext`, replaces the hardcoded `.preview` default
- Call `loadLiveContext()` after `syncPhase1()` completes
- `fitnessSnapshots` populated from Supabase (currently hardcoded preview data)

**`ArcBriefingView` / `LookaheadSuggestionView`:**
- Brief and lookahead are currently hardcoded strings from `AthleteContext.previewBriefing`
- Step 8 wires these to real Claude calls: generate briefing from live context, cache in `AppState`
- Arc opens with live Enzo copy that references real fitness data

**Testing acceptance criterion:**
Enzo references real fitness data in the Arc response — not the hardcoded "Building → up" preview.

### Key things to NOT do in Step 8
- Don't start segment scoring (Step 9) — segments tab still shows preview data
- Don't change the app launch flow — still ArcView
- Don't write raw fitness data to Supabase — still derived metrics only

---

## Bugs carried forward (do not fix in Step 8)

- `GoalSettingView` preview for "segment selected" state uses placeholder Enzo copy — fix in Step 11
- `AppState.setGoal` sets `requiredFitnessValue = segment.fitnessValueAtPR` directly, so Hawk Hill shows "Epic fitness needed" instead of "Strong" — fix in Step 9
- Swift 6 concurrency warnings in `StravaService`, `SupabaseService`, `SyncService` (from `@MainActor` Config / KeychainHelper access) — warnings only, build succeeds; fix in a dedicated cleanup pass

---

## Decisions and discoveries from this session (recorded in CLAUDE.md Build Notes)

- `lazy var` is incompatible with `@Observable` — init accessor macro conflicts. Fixed by creating local lets in `init()` and assigning to stored `let` properties.
- `supabaseUserId` was being silently discarded in Step 6 `authenticate()` — fixed: now stored in AppState and Keychain
- `SyncService.computeSnapshots()` is static and pure — key architectural choice that makes it unit-testable without mocking a network layer
- 2-month rolling window for fitness value; single-month stats for `hoursRidden`/`activityCount` — important distinction for Step 8 when populating the Arc chart
- `print()` is invisible when running via Sweetpad — use `NSLog()` for anything that needs to appear in `log stream`
- 97 fitness snapshots synced successfully; all `trend_direction = "flat"` — threshold tuning needed in Step 8

---

## First file to open

```
CLAUDE.md
```

Then open Supabase dashboard and look at the `fitness_snapshots` table — specifically the `avg_efficiency` column across months. This gives you the data you need to judge whether the trend threshold needs tuning before building the live UI.
