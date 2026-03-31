# Session Handoff — Smoke Test Complete, Step 10 Chunk 1 Ready

## What was completed this session

Smoke test debugging and Phase 2 PR detection fix. No Step 10 code written.

| Commit | What |
|---|---|
| `93dee1f` | Fix Phase 2: switch from `athlete_pr_effort` (not populated by Strava in activity detail responses) to `pr_rank == 1` (reliable all-time PR signal). Also exposes `SyncService.lastPhase2SyncKey` as `static` and adds `AppState.resetSyncHistory()` for SettingsSheet reset button. |

---

## Smoke test — PASSED

- Phase 2 processed 25 activities, upserted **109 segment rows**
- `[Segments] Loaded 109 segments from Supabase` confirmed
- Segments tab shows real segments (not preview data)

**Why `athlete_pr_effort` was always nil:** Strava does not populate this field in activity detail responses despite it being in the `SummarySegment` schema. `pr_rank == 1` on the `DetailedSegmentEffort` is the correct signal — it means that effort is the athlete's all-time PR on that segment.

**Limitation:** Phase 2 only captures PRs that appear as `pr_rank == 1` in the fetched activity window (currently 25 activities). Segments where the PR is older than the window won't appear. Raising `phase2ActivityLimit` in a later session will expand coverage.

---

## Current app state

- **Smoke test:** passed — 109 real segment rows in Supabase
- **Segments tab:** shows real segments sorted by strike score
- **Goal header:** shows "No goal set / Set a goal" until a goal is set; goal persists to Supabase across relaunches
- **GoalSettingView:** searches real Supabase segments
- **Sync:** person.circle button in ArcView header triggers Phase 1 + Phase 2
- **Phase 2:** incremental — `resetSyncHistory()` on AppState clears `lastPhase2SyncTimestamp`
- **Auth gating:** none — app still launches directly into ArcView

---

## Step 10: Onboarding Flow — Chunk 1 Ready to Implement

All open questions are answered. Plan is approved. Do not re-plan — implement this.

### Approved answers to open questions

1. **Existing user bootstrapping:** Auto-set `hasCompletedOnboarding = true` at end of `loadContext()` if `activeGoal != nil`. Prevents forcing existing users through onboarding after app update. ✅ Approved.

2. **GoalSettingView location:** Stays in `Features/Arc/` — just adding a callback parameter. ✅ Confirmed.

### Chunk 1 files (implement all of these)

| File | Change |
|---|---|
| `Utils/WindowContextProvider.swift` | **Create** — `NSObject` + `ASWebAuthenticationPresentationContextProviding`. Needed by ConnectView (Chunk 2) to present Safari auth sheet. |
| `App/AppState.swift` | **Modify** — add `hasCompletedOnboarding: Bool` (UserDefaults-backed, restored in `init()`), `disconnect()` method, auto-set in `loadContext()` when `activeGoal != nil` |
| `Features/Arc/GoalSettingView.swift` | **Modify** — add `onGoalConfirmed: (() -> Void)?` callback (called instead of `dismiss()` when set), hide Cancel button when callback is present, add "Help me pick one" Path B |
| `Features/Onboarding/SettingsSheet.swift` | **Create** — sheet with three actions: "Sync now", "Reset sync history" (calls `appState.resetSyncHistory()` then `syncPhase1()`), "Disconnect Strava" (calls `appState.disconnect()`) |
| `Features/Arc/ArcView.swift` | **Modify** — replace person.circle debug button with gear icon that opens SettingsSheet as a sheet |
| `EnzoAppApp.swift` | **Modify** — auth gating logic (see below) |

### Auth gating pattern (approved)

```swift
// EnzoAppApp.swift — WindowGroup body
if !appState.isAuthenticated {
    // ConnectView comes in Chunk 2 — use a placeholder for now
    ConnectPlaceholderView()
} else if !appState.hasCompletedOnboarding {
    GoalSettingView(onGoalConfirmed: { appState.hasCompletedOnboarding = true })
} else {
    MainTabView()
}
```

`ConnectPlaceholderView` is a minimal dark screen with "Connect Strava" text — enough to test the gate. Real ConnectView with OAuth + animation is Chunk 2.

### hasCompletedOnboarding implementation

```swift
// In AppState — stored property so @Observable tracks it; didSet persists to UserDefaults
var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
    didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
}
```

**Why stored, not computed:** `@Observable` only tracks stored properties. A computed property backed purely by UserDefaults won't trigger SwiftUI re-renders. The stored property + `didSet` pattern initializes from UserDefaults on launch and persists every change.

Auto-set in `loadContext()`:
```swift
// After building context, before returning:
if activeGoal != nil && !hasCompletedOnboarding {
    hasCompletedOnboarding = true
}
```

### disconnect() implementation

```swift
func disconnect() {
    KeychainHelper.delete(for: KeychainHelper.stravaAccessToken)
    KeychainHelper.delete(for: KeychainHelper.stravaRefreshToken)
    KeychainHelper.delete(for: KeychainHelper.stravaAthleteId)
    KeychainHelper.delete(for: KeychainHelper.supabaseUserId)
    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    UserDefaults.standard.removeObject(forKey: SyncService.lastPhase2SyncKey)
    isAuthenticated = false
    stravaAthleteId = nil
    supabaseUserId = nil
    athleteContext = .preview
    fitnessSnapshots = FitnessSnapshot.previewSnapshots
    segments = SegmentScore.previewSegments
}
```

### GoalSettingView — Path B "Help me pick one"

Secondary button below search bar. Shows top 3 segments by `strikeScore` from `appState.segments`. Each card shows segment name + strike label (static copy — no Claude call). Tapping a card calls `selectSegment(_:)` — same flow as Path A.

Only show Path B when `appState.segments` has real data (not preview). Check: `!appState.segments.isEmpty`.

### SettingsSheet — "Reset sync history" behavior

Calls `appState.resetSyncHistory()` then immediately triggers `appState.syncPhase1()`. Dismisses the sheet before triggering sync. User sees normal sync progress in logs.

---

## Chunk 2 (next session after Chunk 1)

- `Features/Onboarding/ConnectView.swift` — hero screen, "Connect Strava" CTA, real OAuth
- `Features/Onboarding/SyncProgressView.swift` — route-drawing animation, crossfading copy phases
- Claude response cache — briefing/lookahead in UserDefaults for demo resilience

---

## Decisions made this session

- `athlete_pr_effort` is NOT populated by Strava in activity detail API responses — use `pr_rank == 1` instead
- `phase2ActivityLimit = 25` is sufficient for finding recent PRs; raise to 100+ in Step 11 polish for broader history coverage
- `SegmentsView` sort default (strike score desc) is correct per spec; date-based sort is a polish-pass addition
- `resetSyncHistory()` exposed on AppState (not buried in SyncService) so SettingsSheet can call it directly
- Segment sort by date is deferred to polish list (Step 11)
