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

**xcconfig `//` stripping** — `//` in xcconfig values is treated as a comment. Any URL value will break. Fix: split the URL using `$()` which expands to an empty string:
```
MY_HOST = example.com
MY_URL = https:/$()/$(MY_HOST)
```

**Info.plist** — Explicit plist at repo root with `$(VARIABLE)` substitution. `GENERATE_INFOPLIST_FILE = NO`. Custom keys only work here — `INFOPLIST_KEY_*` in xcconfig silently drops them.

---

## Strava

**OAuth** — `STRAVA_CLIENT_ID = 217529`. Redirect URI: `enzo://oauth`. Strava "Authorization Callback Domain" must be `oauth` (not `localhost` — Strava strips the scheme). `pr_rank == 1` is the reliable PR signal — `athlete_pr_effort` is never populated in activity detail responses.

**Rate limits** — 200 req/15 min, 2000/day. Phase 2 uses ~26 requests per run. `phase2ActivityLimit = 25` — do not raise without explicit instruction from Chad.

**Phase 2 incremental sync** — Saves `lastPhase2SyncTimestamp` to UserDefaults after each successful run. Next run passes `after=<timestamp>` to Strava. Reset via Settings → Reset sync history (wired to `appState.resetSyncHistory()`).

---

## Fitness & Scoring

**Fitness model** — CTL/ATL/TSB (Performance Management Chart). TSS computed per activity from power (`avgWatts`, only when `device_watts == true`) with HR fallback (`avgHeartRate / LTHR`)². LTHR = 95th percentile of average HR across 20–90 min rides (requires ≥10 qualifying rides; stored in UserDefaults `athleteLTHR`). FTP stored in UserDefaults `athleteFTP` (user-entered). CTL = 42-day EMA of daily TSS. ATL = 7-day EMA. TSB = CTL_yesterday − ATL_yesterday. One `DailyFitnessModel` row per calendar day — never skip rest days.

**PR probability** — Per-segment OLS regression: `elapsed_time = β₀ + β₁·CTL + β₂·TSB`. Fit via normal equations using `simd_double3x3.inverse` (no LAPACK). `P(PR) = Φ((prTime − ŷ) / σ)`. Implemented in `SegmentRegression.swift` + `PRPredictor.swift`. `isValid = false` when β₁ > 0 (wrong sign), matrix is singular, or no efforts. Shows naive fallback when invalid: "PR set when CTL was X. Your current CTL is Y."

**Strike labels** — Derived from `prProbability` in `AppState.strikeLabelV2()`: Strike now (≥0.80) / Almost there (0.65) / Worth a shot (0.45) / Getting there (0.25) / Build first (<0.25).

**lastEffortSeconds** — Populated from the most recent `SegmentEffortModel` for the segment (newest effortDate). Distinct from `prSeconds` — the PR may not be the most recent effort.

---

## UI

**Dark mode** — Fully supported as of Phase J (commit 62e1d1f). `Color+Enzo.swift` uses `UIColor { traits in }` adaptive closures for bg/card/primary/secondary. Fixed tokens (accent, goal, amber, chart colors) are identical in both modes. `enzoUserBubble` is always a dark surface — always pair with `.white` text, never `Color.enzoPrimary`. The forced `.preferredColorScheme(.light)` was removed from `EnzoAppApp.swift`.

**Navigation** — Single `NavigationStack` at the app root. `SegmentsView` is the sole content view — no tabs. Uses typed navigation values: `navigationDestination(for: SegmentNavigation.self)` where `SegmentNavigation` is an enum (`detail(SegmentScore)` / `detailWithChat(SegmentScore)`). Supplementary flows (Find Segments, Settings) use `.sheet`.

**loadContext() placement** — Only called from `RootView.task` (once per launch). `generateLookahead()` and `generateBriefing()` were removed in the Segment-Focused Redesign — Claude responses are now scoped to individual segments via `sendSegmentMessage()`.

---

## Visual UI Verification

**How to capture a screenshot** — Run `bash scripts/screenshot.sh` from the repo root. It saves to `scripts/screenshots/latest.png` and prints the path.

**How to read it** — Use `Read scripts/screenshots/latest.png` (absolute path: `/Users/chadallen/projects/EnzoApp/scripts/screenshots/latest.png`). The Read tool renders the image inline.

**Manual prerequisite** — Simulator must be booted and the app running before taking a screenshot. Boot once per session: `xcrun simctl boot "iPhone 17"`, then launch via Sweetpad or Xcode. The screenshot script does not launch the app.

**When to use** — After any view change, run the script and read the result to verify layout, colors, and content before committing.

---

## UI Interaction (idb)

idb lets Claude drive the simulator — tap, swipe, type — without manual input. Combined with screenshots, this enables end-to-end flow verification.

**Prerequisites** — idb-companion and fb-idb must be installed (one-time, done by Chad). idb binary: `~/.venv/idb312/bin/idb` (Python 3.12 venv — 3.14 is incompatible). Simulator must be booted.

**tap.sh wrapper** — `scripts/tap.sh` resolves the booted simulator UDID automatically and delegates to idb:

```bash
bash scripts/tap.sh tap <x> <y>                             # tap a point
bash scripts/tap.sh swipe <x1> <y1> <x2> <y2> [duration]   # swipe between points
bash scripts/tap.sh type <text>                              # type into focused field
```

**Coordinate reference** — iPhone 17 simulator logical resolution is 393×852 pt. Center of screen: `196 426`. Common targets: status bar `196 60`, bottom safe area edge `196 820`.

**Flow verification pattern** — Screenshot → tap → screenshot → verify. Always screenshot after each interaction to confirm the result before the next action:

```bash
bash scripts/screenshot.sh   # capture state
# Read scripts/screenshots/latest.png to verify
bash scripts/tap.sh tap 196 426
bash scripts/screenshot.sh   # capture result
```

**Error: no booted simulator** — `tap.sh` exits with a clear message if no simulator is booted. Boot with `xcrun simctl boot "iPhone 17"` then launch the app before using idb.

---

## Prompts

**Playground first** — Use `scripts/enzo_playground.py` to test prompt changes before touching `ClaudeService.swift` or `AppState.swift`. Streams in ~2 seconds. See `scripts/README.md`.

**Fitness labels in system prompt** — `ClaudeService.swift` system prompt still uses v1 fitness labels (Epic, Strong, Building, Baseline, Recovering). ADR-0009 retired these in favour of PR probability %. Updating the prompt is EnzoApp-55p.6 — use playground (`scripts/enzo_playground.py`) before touching `ClaudeService.swift`.

**segmentAssessmentPrompt in AppState** — Static func that generates the opening Enzo prompt when "Ask Enzo" is tapped. Needs tuning via playground before shipping.

**NSLog not print()** — When running via Sweetpad, `print()` doesn't appear in the iOS log stream. Use `NSLog()` for anything you need to see via `log stream --predicate 'process == "EnzoApp"'`.
