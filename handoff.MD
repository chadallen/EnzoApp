# Session Handoff — Step 10 Chunks 2a + 2b Complete

## What was completed this session

| Commit | What |
|---|---|
| `9df7a88` | Session close: update docs for Step 10 Chunk 1 completion, Chunk 2 handoff |
| `69a1d07` | Step 10 Chunk 2a: AppState cache + sync state, SyncService activity count |
| `04cc892` | Docs: split Step 10 Chunk 2 into 2a/2b/2c in CLAUDE.md and handoff.MD |
| `3255677` | Step 10 Chunk 2b: ConnectView + wire into RootView |

---

## Current app state

- **Unauthenticated:** shows `ConnectView` — "Enzo" hero screen with working "Connect Strava" CTA
- **Auth flow:** `ConnectView` calls `authenticate()` then `startOnboardingSync()`. After auth, `isOnboardingSyncing = true` and `isSyncing` kicks in. The `isOnboardingSyncing` gate branch in RootView is wired in Chunk 2c alongside `SyncProgressView`.
- **After onboarding sync (existing flow):** still routes through `isResolvingOnboarding` → `GoalSettingView` → `MainTabView`
- **Claude response cache:** live — briefing + lookahead persist to UserDefaults after generation; restored on relaunch if < 24h old; invalidated on sync and disconnect. Brief flash of preview text before restore is a known artifact, deferred to Step 11.
- **SettingsSheet:** unchanged — Sync now, Reset sync history, Disconnect Strava
- **`syncedActivityCount`:** populated after Phase 1 — ready for SyncProgressView to display

---

## Step 10 Chunk 2c — next

### What to build

| File | What |
|---|---|
| `Features/Onboarding/SyncProgressView.swift` | **Create** — route animation, 5 copy phases, activity counter, completion detection |
| `EnzoAppApp.swift` | **Modify** — add `isOnboardingSyncing` gate branch |

### SyncProgressView spec (PRD Section 8, Journey 1 Step 2)

**Route animation:**
- `GeometryReader` + custom `Path` with bezier curves suggesting a cycling route: rolling terrain, a switchback section, a climb. Not a circle or simple squiggle — think a Strava GPS trace.
- Full path drawn faintly: `Color.enzoAccent.opacity(0.15)` stroke
- Animated portion: `trim(from: max(0, progress - 0.25), to: progress)` in full `enzoAccent`, using `.linear(duration: 3.0).repeatForever(autoreverses: false)` on `progress` from 0 → 1
- This creates a "drawing point moving through landscape" effect with a trailing fade

**Copy phases (enum, 5 cases):**
```
1. "Reading your rides..."         — Phase 1 active
2. "Finding your best efforts..."  — Phase 1 active
3. "Sizing up your fitness..."     — Phase 2 active
4. "Scoping your opportunities..." — Phase 2 active
5. "Enzo is almost ready..."       — Phase 2 active / wrapping up
```
- Crossfade between phases using `.transition(.opacity)` + `withAnimation`
- Phase 1 (`isSyncing == true`) cycles phases 1–2 on a timer (~8s each)
- Phase 2 (`isSyncingPhase2 == true`) cycles phases 3–5 on a timer (~8s each)

**Activity counter:**
- `"\(appState.syncedActivityCount) rides and counting"` in `enzoTextSecondary`, monospaced
- Only shown once `syncedActivityCount > 0`

**Long sync message:**
- `@State var elapsed: TimeInterval = 0` tracked by a 1-second `Timer`
- Show `"Big history — this is worth it."` below counter after 60 seconds

**Completion detection:**
- `@State var syncHasStarted = false` — set `true` when either `isSyncing || isSyncingPhase2` first becomes true
- When both return to false after `syncHasStarted == true`: show phase 5 copy, wait 0.8s, call `onComplete()`
- `onComplete: () -> Void` — passed in from RootView

**Signature:**
```swift
struct SyncProgressView: View {
    let onComplete: () -> Void
    ...
}
```

### EnzoAppApp.swift change

Add one gate branch between `isResolvingOnboarding` and `!hasCompletedOnboarding`:

```swift
} else if appState.isOnboardingSyncing {
    SyncProgressView(onComplete: { appState.isOnboardingSyncing = false })
}
```

Full gate order after Chunk 2c:
```
!isAuthenticated            → ConnectView
isResolvingOnboarding       → Color.enzoBg (blank hold)
isOnboardingSyncing         → SyncProgressView(onComplete:)
!hasCompletedOnboarding     → GoalSettingView(onGoalConfirmed:)
else                        → MainTabView
```

### Complete onboarding flow after Chunk 2c

```
ConnectView: "Connect Strava" tapped
  → authenticate() → isAuthenticated = true
  → startOnboardingSync() → isOnboardingSyncing = true
  → RootView routes to SyncProgressView
  → syncPhase1: isSyncing = true, syncedActivityCount populated, isSyncing = false
  → syncPhase2: isSyncingPhase2 = true → false
  → SyncProgressView detects completion → final copy beat → onComplete fires
  → isOnboardingSyncing = false
  → RootView routes to GoalSettingView
  → user confirms goal → hasCompletedOnboarding = true
  → RootView routes to MainTabView
```

---

## Known issues / deferred

- Brief flash of preview text before cached content restores on relaunch — Step 11 polish
- `phase2ActivityLimit = 25` — sufficient for beta, raise to 100+ in Step 11
- Swift 6 concurrency warnings in `StravaService.swift` / `SupabaseService.swift` — warnings only, build succeeds, fix in Step 11
- `recent_weeks: []` in context payload — deferred to Step 12
- RLS policies on Supabase tables — deferred, anon key reads/writes freely (dev only)

---

## Decisions made this session

- Chunk 2 split into 2a/2b/2c to preserve context window — each chunk independently testable
- `isOnboardingSyncing` gate branch deferred to Chunk 2c (added alongside `SyncProgressView` so the build always compiles)
- `SyncService.syncPhase1` return type changed from `Void` to `Int` (activity count) — no test changes needed as `syncPhase1` itself isn't unit tested (requires network)
- Cache restore happens inside `loadContext()` after context is built — not at init time — to avoid showing stale data before the context is fresh
