# Session Handoff — Step 10 Chunk 1 Complete

## What was completed this session

Step 10 Chunk 1 — all 6 files, plus several bug fixes and UX improvements discovered during testing.

| Commit | What |
|---|---|
| `71f6ebc` | Add `WindowContextProvider` for ASWebAuthenticationSession anchor |
| `43919d6` | AppState: `hasCompletedOnboarding`, `disconnect()`, onboarding auto-set in `loadContext()` |
| `a890787` | GoalSettingView: `onGoalConfirmed` callback, hide Cancel in onboarding, add Path B |
| `da514ac` | Add `SettingsSheet`: sync now, reset sync history, disconnect Strava |
| `b28e669` | ArcView: replace debug sync button with gear icon opening SettingsSheet |
| `ce3e232` | EnzoAppApp: auth gating + `ConnectPlaceholderView` |
| `6205f7c` | Fix onboarding gate: add `isResolvingOnboarding` to avoid flash of GoalSettingView for existing users |
| `98becfe` | GoalSettingView: rename "Change" → "Pick different" to eliminate UX confusion |
| `f296bf6` | GoalSettingView: copy reaction text to Arc briefing, regenerate lookahead on goal confirm |
| `09b6b22` | GoalHeaderView: show weeks remaining when target date is set |
| `f25ea80` | GoalContext: add `daysRemaining`, show days/weeks label with sub-week precision |
| `2a4b59d` | GoalHeaderView: show days for <14 days, weeks for 14+ |

---

## Current app state

- **Auth gating:** live — `RootView` gates on `isAuthenticated` → `isResolvingOnboarding` → `hasCompletedOnboarding`
- **Unauthenticated:** shows `ConnectPlaceholderView` (dark screen, bike icon, "Connect Strava" — placeholder only, no working button yet)
- **Authenticated, no goal:** shows `GoalSettingView` with no Cancel button
- **Authenticated, has goal:** lands directly in `MainTabView` (existing users auto-set via `loadContext()`)
- **SettingsSheet:** gear icon in Arc header — Sync now, Reset sync history, Disconnect Strava
- **Goal confirm flow:** reaction text copied to Arc briefing; lookahead regenerates for new goal
- **Target date display:** "N days to go" for <14 days, "N weeks to go" for 14+
- **GoalSettingView Path B:** "Help me pick one" button shows top 3 segments by strike score
- **Disconnect:** clears all Keychain + UserDefaults state, restores preview data, triggers gate to ConnectPlaceholderView

---

## Step 10 Chunk 2 — next

### Files to build

| File | What |
|---|---|
| `Features/Onboarding/ConnectView.swift` | **Create** — hero screen, "Connect Strava" CTA wired to `appState.authenticate(contextProvider:)`. Uses `WindowContextProvider`. On success, transitions to `SyncProgressView`. |
| `Features/Onboarding/SyncProgressView.swift` | **Create** — shown after auth while Phase 1 + Phase 2 run. Route-drawing animation + crossfading copy phases. On completion, sets `hasCompletedOnboarding = true` and advances to `GoalSettingView`. |
| `App/AppState.swift` | **Modify** — add Claude response cache: persist `briefingText`/`lookaheadText` to UserDefaults after generation. On launch, restore cached values immediately so Arc has content before Claude responds. Invalidate cache after 24 hours or on new sync. |
| `EnzoAppApp.swift` | **Modify** — replace `ConnectPlaceholderView()` with `ConnectView()` in the unauthenticated gate branch. |

### ConnectView spec (PRD Section 8, Journey 1 Step 1)

- Clean hero screen. Dark background.
- App name "Enzo" in rounded bold at top.
- Tagline: *"Meet Enzo. Your cycling companion."*
- Single CTA: "Connect Strava" — accent blue pill button
- Tapping calls `appState.authenticate(contextProvider: WindowContextProvider())`
- On success: transition to `SyncProgressView` (not directly to goal setting — sync must run first)
- On error: show "Strava couldn't connect — tap to retry." inline below the button

### SyncProgressView spec (PRD Section 8, Journey 1 Step 2)

- Blocks progression — sync must complete before goal setting
- **Animation:** Abstract cycling route draws itself across the dark background using SwiftUI path + `trim(from:to:)` animation, looping with slight fade-out and redraw. Accent color (`#4FC3F7`) on dark background.
- **Copy phases** (crossfade between them as sync progresses):
  1. *"Reading your rides..."* — Phase 1 activity fetch
  2. *"Finding your best efforts..."* — Phase 2 segment extraction
  3. *"Sizing up your fitness..."* — metrics computation
  4. *"Scoping your opportunities..."* — strike scores calculating
  5. *"Enzo is almost ready..."* — final writes
- Secondary text below: *"[N] rides and counting"* — show actual activity count from Phase 1
- If sync takes > 60 seconds: add *"Big history — this is worth it."* below the counter
- On completion: crossfade to `GoalSettingView(onGoalConfirmed: { appState.hasCompletedOnboarding = true })`

### How SyncProgressView drives phase transitions

`AppState` needs to expose enough state for `SyncProgressView` to drive its copy phases:
- Phase 1 in progress: `isSyncing == true`
- Phase 2 in progress: `isSyncingPhase2 == true`
- Both false and no error: sync complete

The view can derive its copy phase from these two booleans. No new state needed on AppState for the basic implementation.

### Claude response cache

- After `generateBriefing()` completes: `UserDefaults.standard.set(briefingText, forKey: "cachedBriefing")` + `UserDefaults.standard.set(Date(), forKey: "briefingCachedAt")`
- Same for `generateLookahead()` → `"cachedLookahead"` / `"lookaheadCachedAt"`
- On launch (`loadContext()` completion): restore cached values if cache is < 24 hours old
- Invalidate on sync: after `syncPhase1/2` completes, clear the cache keys so next launch regenerates
- This prevents Arc from showing empty briefing/lookahead during the Claude API call on every relaunch

---

## Decisions made this session

- `isResolvingOnboarding` is set in `AppState.init()` (not lazily) so the gate never flashes GoalSettingView before loadContext runs
- `RootView` (not `EnzoAppApp.App.body`) owns the gate logic and the `.task { await appState.loadContext() }` — keeps the @main struct minimal
- `GoalSettingView` stays in `Features/Arc/` — no move needed even though it's used in onboarding
- Goal confirm: reaction text → briefingText handoff is view-level (GoalSettingView), not in AppState.setGoal() — keeps the reaction text local to the view that generated it
- `daysRemaining` added to `GoalContext` alongside `weeksRemaining` — days for display (<14), weeks for Claude context (cleaner granularity for training planning)
- "Pick different" replaces "Change" in selected segment card — unambiguous back navigation vs confirm

---

## Known issues / deferred

- `ConnectPlaceholderView` has no working button — Chunk 2 replaces it entirely
- Swift 6 concurrency warnings in `StravaService.swift` / `SupabaseService.swift` — warnings only, build succeeds, fix in Step 11 polish
- `phase2ActivityLimit = 25` — sufficient for beta, raise to 100+ in Step 11
- `recent_weeks: []` in context payload — deferred to Step 12 (webhooks)
- RLS policies on Supabase tables — deferred; anon key can read/write freely (dev only)
