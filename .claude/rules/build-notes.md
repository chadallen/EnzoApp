# Enzo — Build Notes

Gotchas and decisions that could trip you up. Check before making changes in these areas.

---

## Architecture

**Xcode auto-sync** — `PBXFileSystemSynchronizedRootGroup` is active. Any `.swift` file dropped into `EnzoApp/` or `EnzoAppTests/` is automatically included in the build target. No manual `.xcodeproj` registration needed.

**AppState injection** — Created in `EnzoAppApp` with `@State private var appState = AppState()`, injected via `.environment(appState)`. Views use `@Environment(AppState.self) private var appState`. Never pass as a regular parameter.

**Cross-actor calls** — `ClaudeService` is a Swift `actor`. Any `AppState` method calling it must be `async`. `lazy var` is incompatible with `@Observable` — initialize services in `init()` with local `let` bindings instead.

**Color constants** — Never use raw hex in view files. All colors are `Color.enzoXxx` in `Color+Enzo.swift`. `Color(hex:)` is an internal primitive only.

---

## Secrets & Config

**xcconfig `//` stripping** — `//` in xcconfig values is treated as a comment. URLs break. Fix:
```
SUPABASE_HOST = hizswbzxwfxddocryvci.supabase.co
SUPABASE_URL = https:/$()/$(SUPABASE_HOST)
```
`$()` expands to empty string. Already applied to both xcconfig files.

**Info.plist** — Explicit plist at repo root with `$(VARIABLE)` substitution. `GENERATE_INFOPLIST_FILE = NO`. Custom keys only work here — `INFOPLIST_KEY_*` in xcconfig silently drops them.

---

## Supabase

**REST API, no SDK** — `SupabaseService` uses `URLSession` directly. Every request needs `apikey` + `Authorization: Bearer <anon key>` headers.

**Upserts** — All upserts use `POST` with `Prefer: resolution=merge-duplicates,return=representation` AND `?on_conflict=<col>` in the URL. Without `on_conflict`, Supabase ignores the hint and returns 409. Without `return=representation`, upserts return 204 with no body and decoding fails.

**RLS** — Disabled on all tables (dev). Add policies before App Store submission.

**Integration test** — Gated on `export SUPABASE_INTEGRATION_TESTS=1` before running xcodebuild. The `VAR=value xcodebuild` prefix doesn't reach the simulator.

---

## Strava

**OAuth** — `STRAVA_CLIENT_ID = 217529`. Redirect URI: `enzo://oauth`. Strava "Authorization Callback Domain" must be `oauth` (not `localhost` — Strava strips the scheme). `pr_rank == 1` is the reliable PR signal — `athlete_pr_effort` is never populated in activity detail responses.

**Rate limits** — 200 req/15 min, 2000/day. Phase 2 uses ~26 requests per run. `phase2ActivityLimit = 25` — do not raise without explicit instruction from Chad.

**Phase 2 incremental sync** — Saves `lastPhase2SyncTimestamp` to UserDefaults after each successful run. Next run passes `after=<timestamp>` to Strava. Reset via Settings → Reset sync history (wired to `appState.resetSyncHistory()`).

---

## Fitness & Scoring

**Fitness model** — `value: Double` (0.0–1.0, internal). Labels: Epic / Strong / Building / Baseline / Recovering. Percentile normalization (5th/95th) in `SyncService.computeSnapshots`. Trend threshold: 0.008.

**Strike score formula** — `clamp(0.75 + fitnessDelta + prAgeBonus + effortGapModifier, 0, 1)`. At parity → 0.75 ("Almost there"). 5-tier labels: Strike now (≥0.80) / Almost there (0.65) / Worth a shot (0.45) / Getting there (0.25) / Build first (<0.25).

**Demo jitter** — `SyncService.syncPhase2` applies ±0.25 deterministic jitter seeded from `segId`. Tagged "DEMO — Remove before shipping." Remove this before any real user testing or App Store submission.

**lastEffortSeconds** — Correctly populated via `latestEffortMap` (first occurrence in newest-first activity loop). Was always equal to `prSeconds` before the readiness differentiation session fix.

---

## UI

**Dark mode** — App is forced light mode via `.preferredColorScheme(.light)` on `WindowGroup` in `EnzoAppApp.swift`. Only one place now — `ArcView` (which had a second `.colorScheme(.light)` on the `safeAreaInset` input area) was deleted in the Segment-Focused Redesign.

**Navigation** — `MainTabView` owns the `NavigationStack`. `SegmentsView` does not wrap itself. `navigationDestination(for: SegmentScore.self)` in SegmentsView works because it's inside the ancestor NavigationStack. Tabs were removed in the Segment-Focused Redesign — `SegmentsView` is now the single content view inside the stack.

**loadContext() placement** — Only called from `RootView.task` (once per launch). `generateLookahead()` and `generateBriefing()` were removed in the Segment-Focused Redesign — Claude responses are now scoped to individual segments via `sendSegmentMessage()`.

---

## Prompts

**Playground first** — Use `scripts/enzo_playground.py` to test prompt changes before touching `ClaudeService.swift` or `AppState.swift`. Streams in ~2 seconds. See `scripts/README.md`.

**Stale labels in enzo-voice.MD** — System prompt section still has old fitness labels (Peak shape, Strong base...) and old readiness labels (No brainer, Worth a shot, Not quite ready). Fix before any prompt work.

**segmentAssessmentPrompt in AppState** — The static func that generates the opening Enzo prompt when "Ask Enzo" is tapped on a segment. Needs tuning via playground (`scripts/enzo_playground.py`) before shipping. `GoalSettingView` and its `strikeLabelColor()` were deleted in the Segment-Focused Redesign.

**NSLog not print()** — When running via Sweetpad, `print()` doesn't appear in the iOS log stream. Use `NSLog()` for anything you need to see via `log stream --predicate 'process == "EnzoApp"'`.
