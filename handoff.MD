# Session Handoff — Bug Fixes Complete, Step 10 Ready to Build

## What was completed this session

This session was preparation for Step 10. No Step 10 code was written. All commits are bug fixes discovered during smoke testing.

| Commit | What |
|---|---|
| `6f891f9` | Fix goal persistence: `saveGoal()` in SupabaseService, `setGoal()` persists via background Task, `GoalHeaderView` empty state, `GoalSettingView` uses `appState.segments` |
| `f64c413` | Fix Phase 2: `StravaAthletePREffort` decoded `"pr_elapsed_time"` — correct Strava field is `"elapsed_time"`. This caused 0 segment rows on every Phase 2 run. |
| `cac49df` | Fix no-goal placeholder: `AthleteContext.build()` fallback was `"—"` (em dash) — changed to `""` so GoalHeaderView's `isEmpty` check works |
| `b5ce878` | Phase 2 incremental sync: `phase2ActivityLimit` 100→25, stores `lastPhase2SyncTimestamp` in UserDefaults, passes `after` to Strava API on re-syncs, skips entirely if no new activities |

---

## Smoke test — complete this BEFORE writing any Step 10 code

Phase 2's `elapsed_time` fix was applied but not verified end-to-end (rate limit hit during the verification run). The code is correct. Run this once to confirm:

1. Build and run via Sweetpad
2. Tap the person.circle button in ArcView
3. Watch log output (`log stream --predicate 'process == "EnzoApp"'` or Sweetpad logs)
4. Expected sequence:
   ```
   [Sync] starting Phase 1 for userId ...
   [Sync] Phase 1 complete
   [Sync] starting Phase 2 for userId ...
   [Sync P2] First run — fetching most recent 25 activities
   [Sync P2] Processing 25 activities
   [Sync P2] Upserting N segment rows       ← N must be > 0
   [Sync P2] Phase 2 complete
   [Sync] Phase 2 complete — reloading segments
   [Segments] Loaded N segments from Supabase
   ```
5. Segments tab must show real segment names (not "Hawk Hill", "Camino Alto Cutoff" etc.)
6. ArcView header shows "No goal set / Set a goal" (no goal in Supabase yet)
7. Tap "Set a goal", search and pick a real segment from your list, confirm
8. Kill and relaunch — goal header must show the segment name you picked (confirms persistence)

**If `[Sync P2] Upserting 0 segment rows`:** The `elapsed_time` fix didn't take effect. Clean build (Cmd+Shift+K) and retry.
**If rate limited (429):** Wait 15 minutes. Phase 2 is now incremental — re-running is cheap (~26 total Strava requests on first run, ~6 on subsequent runs).
**If `[Sync P2] No new activities since last sync — skipping`:** The `lastPhase2SyncTimestamp` is set from a prior run. The fix wasn't deployed before that run. Reset: temporarily add `UserDefaults.standard.removeObject(forKey: "lastPhase2SyncTimestamp")` at the top of `syncPhase2()`, run once, remove it.

---

## Current app state

- **Arc**: Live briefing + lookahead from Claude, real 97-month fitness history from Supabase
- **Goal header**: Shows "No goal set / Set a goal" until a goal is set; goal now persists to Supabase across relaunches
- **GoalSettingView**: Searches real Supabase segments (not hardcoded preview data)
- **Segments tab**: Shows preview data until Phase 2 smoke test passes; will show real segments after
- **Sync**: person.circle button in ArcView header triggers Phase 1 + Phase 2 sequentially
- **Phase 2**: Incremental — only fetches activities newer than `lastPhase2SyncTimestamp`; cap is 25 (tunable)
- **Auth**: App launches directly into ArcView — no onboarding, no auth gating (Step 10 fixes this)

---

## Step 10: Onboarding Flow — Approved Plan

Step 10 has a written plan that was reviewed and approved this session. Do not re-plan from scratch — implement this plan.

### Files to create

| File | What |
|---|---|
| `Utils/WindowContextProvider.swift` | `NSObject` + `ASWebAuthenticationPresentationContextProviding`. Needed by ConnectView to present Safari auth sheet. |
| `Features/Onboarding/ConnectView.swift` | Hero screen: app name, tagline "Meet Enzo. Your cycling companion.", "Connect Strava" CTA. Calls `appState.authenticate(contextProvider:)`. |
| `Features/Onboarding/SyncProgressView.swift` | Blocks to goal-setting while Phase 1 + Phase 2 run. Route-drawing animation + crossfading copy phases. See PRD Section 8 for exact copy. |
| `Features/Onboarding/SettingsSheet.swift` | Simple sheet: "Sync now" + "Disconnect Strava". Replaces person.circle debug button. |

### Files to modify

| File | Change |
|---|---|
| `EnzoAppApp.swift` | Auth gating: `ConnectView` if not authenticated, onboarding gate if not completed, `MainTabView` if done |
| `App/AppState.swift` | Add `hasCompletedOnboarding: Bool` (UserDefaults), `disconnect()` method |
| `Features/Arc/ArcView.swift` | Replace person.circle button with settings icon that opens `SettingsSheet` |
| `Features/Arc/GoalSettingView.swift` | Add `onGoalConfirmed: (() -> Void)?` callback; hide Cancel in onboarding context; add "Help me pick one" Path B |

### Auth gating pattern (approved)

```swift
// EnzoAppApp.swift
if !appState.isAuthenticated {
    ConnectView()
} else if !appState.hasCompletedOnboarding {
    if appState.isSyncing || appState.isSyncingPhase2 {
        SyncProgressView()
    } else {
        GoalSettingView(onGoalConfirmed: { appState.hasCompletedOnboarding = true })
    }
} else {
    MainTabView()
}
```

`hasCompletedOnboarding` stored in `UserDefaults`, read back in `AppState.init()`. Set to `true` when user confirms first goal.

### SyncProgressView copy phases (from PRD Section 8)

| Phase | Copy | When |
|---|---|---|
| 1 | "Reading your rides..." | Phase 1 running (`isSyncing == true`) |
| 2 | "Sizing up your fitness..." | ~20s into Phase 1 |
| 3 | "Finding your best efforts..." | Phase 2 running (`isSyncingPhase2 == true`) |
| 4 | "Scoping your opportunities..." | ~30s into Phase 2 |
| 5 | "Enzo is almost ready..." | Both flags false |

Secondary text: activity count from `appState.athleteContext.totalActivities`. If > 60s: add "Big history — this is worth it." Route animation: abstract cycling path, `trimmedPath` in `enzoAccent`, loops with fade trail.

### GoalSettingView — Path B "Help me pick one"

Secondary button below search bar. Shows top 3 segments by `strikeScore` as tappable cards. Each card shows segment name + strike label (static copy — no Claude call for the pitch, too many concurrent API calls). Tapping goes into the same `selectSegment()` flow as Path A.

### Open questions for Chad before coding

1. **Existing user bootstrapping:** On first run after Step 10 ships, you (already authenticated) will see `SyncProgressView` → `GoalSettingView` because `hasCompletedOnboarding` is false. Should the code auto-set `hasCompletedOnboarding = true` if Supabase already has an active goal (detected in `loadContext()`)? Or is one manual pass through goal-setting acceptable?

2. **GoalSettingView location:** Stays in `Features/Arc/` — just adding a callback parameter. Confirmed. Don't move it.

### Chunk 1 / Chunk 2 split (agreed this session)

**Chunk 1 (next session):** WindowContextProvider, AppState changes, GoalSettingView callback + Path B, EnzoAppApp auth gating, SettingsSheet, replace person.circle. Foundation — everything compiles and auth gate works.

**Chunk 2 (following session):** ConnectView, SyncProgressView (animation), Claude response cache in UserDefaults (demo resilience).

---

## Decisions made this session

- Goal persistence is required, not optional — `setGoal()` must write to Supabase immediately
- `saveGoal()` uses a private insert-only struct (no `id` field) to avoid PostgreSQL NOT NULL conflict; also deactivates prior active goals before inserting
- Phase 2 incremental sync is the right long-term architecture, not just a workaround — `lastPhase2SyncTimestamp` in UserDefaults is the source of truth for "what's been processed"
- `phase2ActivityLimit = 25` for now; raise to 100–200 once smoke tests confirm segment data is correct
- Path B "Help me pick one" uses static copy, not Claude-generated pitches (avoids 3 concurrent API calls on goal-setting screen)
- Claude response cache (briefing/lookahead in UserDefaults) deferred to Chunk 2 for demo resilience
- Strava fallback for demo: no extra work needed — Arc and Segments run entirely off Supabase; Strava only needed for sync
