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

## Step 10 Chunk 2 — split into 2a / 2b / 2c

Chunk 2 was split to preserve context window across sessions. Each chunk is independently testable before moving to the next.

---

### Chunk 2a — AppState + SyncService (backend only, no new views)

**Files:**

| File | What |
|---|---|
| `App/AppState.swift` | Add `isOnboardingSyncing`, `syncedActivityCount`, `startOnboardingSync()`; add Claude response cache |
| `Services/SyncService.swift` | Change `syncPhase1(userId:)` return type from `Void` to `Int` (total activities fetched) |

**AppState changes:**
- `var isOnboardingSyncing: Bool = false` — set true by `startOnboardingSync()`, cleared by SyncProgressView's `onComplete`. Distinct from `isSyncing` so manual syncs (SettingsSheet) don't re-trigger the onboarding screen.
- `var syncedActivityCount: Int = 0` — set after Phase 1 returns; shown in SyncProgressView as "N rides and counting"
- `func startOnboardingSync() async` — sets `isOnboardingSyncing = true`, then calls `syncPhase1()`. Does NOT clear `isOnboardingSyncing` — SyncProgressView clears it after completion animation.
- **Claude response cache**: after `generateBriefing/Lookahead()` loop completes, write to UserDefaults with timestamp. In `loadContext()` after building context, restore cached values if < 24h old (skip Claude call). Invalidate in `syncPhase1()` after sync completes and in `disconnect()`. Keys: `"cachedBriefing"`, `"briefingCachedAt"`, `"cachedLookahead"`, `"lookaheadCachedAt"`.

**SyncService change:**
- `func syncPhase1(userId:) async throws -> Int` — return `activities.count` (total fetched, not just qualifying)
- `AppState.syncPhase1()` captures return value and sets `syncedActivityCount`

**Testability:** verify via NSLog — `[Sync] activity count: N` and UserDefaults cache keys populated after generateBriefing/Lookahead.

---

### Chunk 2b — ConnectView + EnzoAppApp routing

**Files:**

| File | What |
|---|---|
| `Features/Onboarding/ConnectView.swift` | **Create** — hero screen, "Connect Strava" CTA |
| `EnzoAppApp.swift` | Replace `ConnectPlaceholderView` with `ConnectView`; add `isOnboardingSyncing` gate branch |

**ConnectView spec (PRD Section 8, Journey 1 Step 1):**
- `.enzoBg` background, "Enzo" SF Pro Rounded Bold header, tagline *"Meet Enzo. Your cycling companion."*, cycling SF Symbol (`figure.outdoor.cycle`, large, `enzoAccent`)
- "Connect Strava" accent pill button
- `@State var isConnecting: Bool`, `@State var errorMessage: String?`
- On tap: `isConnecting = true`, `await appState.authenticate(contextProvider: WindowContextProvider())`, then `Task { await appState.startOnboardingSync() }`
- Error: inline *"Strava couldn't connect — tap to retry."* below button; reset `isConnecting = false`

**EnzoAppApp changes:**
- Replace `ConnectPlaceholderView()` with `ConnectView()` in the `!isAuthenticated` branch
- Add gate branch: `else if appState.isOnboardingSyncing { SyncProgressView(onComplete: { appState.isOnboardingSyncing = false }) }` — between `isResolvingOnboarding` and `!hasCompletedOnboarding`
- Remove `ConnectPlaceholderView` struct entirely

**Full gate order after Chunk 2b:**
```
!isAuthenticated            → ConnectView
isResolvingOnboarding       → Color.enzoBg (blank hold)
isOnboardingSyncing         → SyncProgressView(onComplete:)   ← new
!hasCompletedOnboarding     → GoalSettingView(onGoalConfirmed:)
else                        → MainTabView
```

---

### Chunk 2c — SyncProgressView

**Files:**

| File | What |
|---|---|
| `Features/Onboarding/SyncProgressView.swift` | **Create** — route animation + copy phases + completion |

**Spec (PRD Section 8, Journey 1 Step 2):**
- **Route animation:** `GeometryReader` + custom `Path` with bezier curves (rolling terrain, switchback, climb). Full path drawn faintly in `enzoAccent.opacity(0.15)`. Animated `trim(from:to:)` segment at full `enzoAccent`, repeating with `.linear(duration: 3).repeatForever(autoreverses: false)`. Gives "drawing through landscape" effect.
- **Copy phases** (enum, 5 cases): crossfade between them. `@State var currentPhase` advances on timer within each sync stage — P1 (`isSyncing`) cycles phases 1–2; P2 (`isSyncingPhase2`) cycles phases 3–5.
- **Activity counter:** `"\(appState.syncedActivityCount) rides and counting"` in `enzoTextSecondary` monospaced; appears once count > 0.
- **Long sync:** `@State var elapsed: TimeInterval` tracked by 1s timer; shows *"Big history — this is worth it."* after 60s.
- **Completion detection:** `@State var syncHasStarted = false` — set when either flag goes true. When both return to false after `syncHasStarted`, plays final copy phase, waits 0.8s, calls `onComplete`.
- `onComplete: () -> Void` — passed in from RootView; sets `appState.isOnboardingSyncing = false`

---

### Full flow after all chunks complete

```
ConnectView taps "Connect Strava"
  → authenticate() → isAuthenticated = true
  → startOnboardingSync() → isOnboardingSyncing = true
  → RootView routes to SyncProgressView
  → isSyncing = true → false, isSyncingPhase2 = true → false
  → SyncProgressView final beat → onComplete → isOnboardingSyncing = false
  → RootView routes to GoalSettingView
  → goal confirmed → hasCompletedOnboarding = true
  → RootView routes to MainTabView
```

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
