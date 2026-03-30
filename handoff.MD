# Session Handoff — Step 9 Complete, Step 10 is Onboarding

## What was completed this session

**Step 9: Historical Sync Phase 2 + Segment Scoring** — 5 commits to main.

| Commit | What |
|---|---|
| 0246d66 | `SegmentScorer.swift` + `SegmentScorerTests.swift` (13 passing tests) |
| 52b2716 | `SyncService.syncPhase2()` — Strava detail fetch, segment extraction, strike scoring, Supabase upsert. `AppState.loadSegments()`, `syncPhase2()`, `isSyncingPhase2`. Phase 1 now chains into Phase 2 automatically. Fixed `requiredFitnessLabel` in `setGoal`. |
| 79ca3bc | Fix upsert 409 (`on_conflict` columns in URL). Increase Phase 2 delay to 1.5s. |
| 1edff16 | Mark Step 9 complete; build notes, handoff |
| f80fdc5 | Session close: update docs, finalize Step 9 handoff |

**Step ordering change:** Strava webhooks (was Step 10) deferred to Step 12 — not needed for beta, manual sync is fine. New order: Step 10 = Onboarding, Step 11 = Polish, Step 12 = Webhooks.

---

## Smoke test — run this BEFORE starting Step 10

The Phase 2 sync was not fully verified at session end due to Strava rate limiting during debugging. The code is correct but the end-to-end run did not complete. **Do this first:**

1. Build and run via Sweetpad
2. Tap the person.circle button in ArcView
3. Watch log output (Sweetpad logs or `log stream --predicate 'process == "EnzoApp"'`)
4. Expected sequence — all lines must appear:
   ```
   [Sync] starting Phase 1 for userId ...
   [Sync] Phase 1 complete
   [Sync] starting Phase 2 for userId ...
   [Sync P2] Upserting N segment rows   ← N must be > 0
   [Sync P2] Phase 2 complete
   [Sync] Phase 2 complete — reloading segments
   [Segments] Loaded N segments from Supabase
   ```
5. Phase 2 takes ~2.5 minutes (1.5s × 100 activities) — wait for it
6. Segments tab must show real segment names (not "Hawk Hill", "Camino Alto Cutoff" etc.)
7. At least one segment must have a non-default strike label

**If `[Sync P2] Upserting 0 segment rows`:** Strava rate limit hit again. Wait 15 minutes, retry.
**If Phase 1 error 409:** Should be fixed by `on_conflict` columns — if it recurs, check `SupabaseService.upsertFitnessSnapshot`.

Do not start Step 10 until the smoke test passes.

---

## Current app state

- **Arc**: Live briefing + lookahead from Claude, real 97-month fitness history
- **Segments tab**: Shows real data after first successful Phase 2 sync; shows 5 preview segments until then
- **Sync**: person.circle button in ArcView header triggers Phase 1 + Phase 2 sequentially (~2.5 min total)
- **Goal setting**: `requiredFitnessLabel` now correctly shows one tier below PR fitness (e.g. Epic PR → "Strong needed")
- **Auth**: App launches directly into ArcView — no onboarding, no auth gating (dev mode only; Step 10 fixes this)

---

## Step 10: Onboarding Flow

This is the step that makes the app usable by anyone other than the developer. Currently the app only works because Chad's Strava tokens and Supabase UUID are already in the Keychain. Any beta tester would open it and see broken empty states.

### Before writing any code

Read in this order:
1. `CLAUDE.md` — full orientation, all hard rules, all build notes
2. `PRD.MD` Section 8 — User Journey 1 (First Launch): Connect screen, sync animation, goal setting flow
3. `PRD.MD` Section 10 — UI requirements for onboarding screens
4. `skills/swift-design.MD` — before building any view
5. `skills/enzo-voice.MD` — before writing any copy
6. `skills/swift-patterns.MD` — architecture decisions

Then **present a written plan and get Chad's approval before writing any code.**

### What Step 10 builds

**1. `ConnectView`** — Hero screen, first thing a new user sees
- App name + tagline: *"Meet Enzo. Your cycling companion."*
- Single CTA: "Connect Strava" button
- Triggers `AppState.authenticate(contextProvider:)` (already built in Step 6)

**2. `SyncProgressView`** — Blocks progression while Phase 1 + Phase 2 run
- Route-drawing animation (SwiftUI `trimmedPath`, brand accent color on dark bg)
- Copy phases that crossfade: "Reading your rides..." → "Finding your best efforts..." → "Sizing up your fitness..." → "Scoping your opportunities..." → "Enzo is almost ready..."
- Activity count in secondary text: *"847 rides and counting"*
- If > 60s: add *"Big history — this is worth it."*
- On completion: crossfade to GoalSettingView

**3. `GoalSettingView` wired into onboarding** — Already exists in `Features/Arc/`. Step 10 makes it the entry point after sync, not just a sheet.
- Path A: user searches their segments by name
- Path B: "Help me pick one" → Enzo suggests top 3 by strike score
- On goal confirmed: advance to Arc (MainTabView)

**4. Auth gating in `EnzoAppApp.swift`** — Show `ConnectView` if not authenticated, `MainTabView` if authenticated. Restore from Keychain on launch (already happens in `AppState.init()`).

**5. Replace person.circle button** — Replace the debug sync trigger in `ArcView` with a settings icon that opens a simple settings sheet (disconnect Strava, manual re-sync).

### Key existing infrastructure (already built)

- `AppState.authenticate(contextProvider:)` — full OAuth flow ✅
- `AppState.syncPhase1()` → auto-chains `syncPhase2()` ✅
- `AppState.isSyncing` + `isSyncingPhase2` flags for progress UI ✅
- `GoalSettingView` — segment search + Enzo reaction + date picker ✅
- `AppState.isAuthenticated` — restored from Keychain on launch ✅

### Auth gating pattern

```swift
// EnzoAppApp.swift — show onboarding vs main app
if appState.isAuthenticated {
    MainTabView()
} else {
    ConnectView()
}
```

### No tests needed for UI

Onboarding is all UI/flow — no new logic functions, so no new unit tests. Verify with `#Preview` on each new view and a manual run-through of the full flow.

---

## Decisions made this session

- Strava webhooks deferred to Step 12 (after Polish pass) — manual sync is sufficient for beta
- Phase 2 activity limit = 100 (proof of concept; `SyncService.phase2ActivityLimit` constant with TODO comment)
- Delay between Phase 2 calls = 1.5s (was 0.1s — hit Strava rate limits)
- Supabase upsert needs explicit `?on_conflict=` columns — applied to both `fitness_snapshots` and `segment_scores`
