# Enzo — Project Brief for Claude Code

## What This Is

Enzo is a personal iOS cycling companion that helps athletes know when to go for a segment PR. It connects to Strava, computes a relative fitness score from heart rate history, and uses an AI companion (also named Enzo) to narrate the athlete's training trajectory and surface the best moments to target PRs.

The full product spec is at `PRD.md`. Hardcoded preview data for Steps 1–5 is in Section 18 of the spec — use those exact values, do not invent placeholder data. Read it when you need detail on any feature, data model, or user journey. This file is the short version — orientation and hard rules.

---

## Stack

- **iOS 17+, SwiftUI only.** No UIKit. No third-party UI libraries.
- **Swift Charts** for all data visualization.
- **`@Observable` + `async/await`** throughout. No Combine, no older state patterns.
- **Supabase** for backend (derived metrics only — never raw Strava data).
- **Anthropic Claude API** (`claude-sonnet-4-6`) for AI features.
- **Strava OAuth 2.0** for authentication and data access.
- **No third-party dependencies** unless the spec explicitly names one.


## Build Order

Follow this sequence. Each step produces something visible or testable before moving on.

1. ✅ **Project setup** — Xcode project, Sweetpad config, 2-tab shell, secrets infrastructure
2. ✅ **Arc UI (static)** — All Arc sections with hardcoded data. App launches directly into ArcView. No auth, no onboarding.
3. ✅ **Claude wiring (hardcoded context)** — ArcInputBar wired to Claude API. Streaming working. System prompt tuned.
4. ✅ **Goal setting UI** — GoalSettingView with Claude interpretation flow.
5. ✅ **Supabase schema + models** — Create tables, Swift models, SupabaseService read/write.
6. ✅ **Strava OAuth** — Auth flow, token storage, athlete profile fetch.
7. ✅ **Historical sync Phase 1** — Paginated activity fetch. Run FitnessCalculator in-memory. Write fitness snapshots to Supabase.
8. ✅ **Context payload + live Enzo** — Build AthleteContext from Supabase. Feed into all Claude calls. Tune model constants against real data.
9. ✅ **Historical sync Phase 2 + segment scoring** — Background fetch of activity details. Extract segment efforts. Run SegmentScorer. Wire Segments tab and Arc PR card.
10. **Onboarding flow** — Connect screen, sync animation, goal setting as front door. *(was Step 11)*
11. **Polish pass** — Animations, empty states, error states, copy review, settings. *(was Step 12)*
12. **Strava webhooks** — Real-time new activity handling. *(deferred from Step 10 — not needed for beta; manual sync is acceptable)*
---

## Hard Rules

### Naming
- The AI companion is named **Enzo** in all user-facing code, strings, and copy.
- Never use "Claude", "AI", or "assistant" anywhere the user can see.
- Claude is the underlying model. Enzo is the product. This distinction is invisible to the user.

### Secrets
- **Never hardcode API keys.** All secrets live in `Config/Debug.xcconfig`.
- Developer keys (Claude API, Supabase, Strava client ID/secret) → xcconfig → Info.plist → `Utils/Config.swift`
- User credentials (Strava access token, refresh token) → iOS Keychain via `Utils/KeychainHelper.swift`
- `Config/Debug.xcconfig` and `Config/Release.xcconfig` are in `.gitignore`. Never commit them.
- Read keys in Swift via `Config.claudeAPIKey`, `Config.supabaseURL` etc. See `Utils/Config.swift`.

### Data
- **Never store raw Strava activity data.** Pull from API, compute derived metrics in memory, write only computed output to Supabase, discard raw data.
- Fitness score is HR-only. Power meter data is ignored in MVP even if present in activities.
- All segment search runs client-side against the local `segment_scores` Supabase table — never against the global Strava segment database.

### Testing
- **Write unit tests alongside every logic file.** When you create `FitnessCalculator.swift`, create `FitnessCalculatorTests.swift` in the same step. Never defer tests.
- Test logic, not UI. Pure functions only: fitness computation, segment scoring, context payload assembly, prompt construction.
- Use **Swift Testing** (not XCTest). See `skills/testing.md` for patterns and acceptance criteria per step.
- Every view must have a `#Preview` using hardcoded data from Section 18. Use `.preferredColorScheme(.dark)` on every preview.
- Before marking any step complete, run tests and confirm they pass.

### UI & Tone
- Light mode. Background `#FAFAFA`, card surfaces `#F7F7FA`. Primary text `#000000`, secondary `#666666`.
- Brand accent `#FC5201` (orange-red). Goal accent `#81C784` (green). Amber `#FFB74D` sparingly.
- Chart colors: `#1E88E5` (primary line), `#90CAF9` (fill/secondary). All defined as `enzoChartPrimary`/`enzoChartSecondary`.
- SF Pro Rounded Bold for headers. SF Pro Text for body. SF Pro Mono for data labels.
- No red states for inactivity or missed rides. Amber at most, always with a constructive Enzo line.
- No streaks. No missed workout tracking. No guilt mechanics of any kind.
- Copy tone: warm, direct, forward-looking. See system prompt in spec Section 7.




### Commits
Commit after every discrete unit of work — not at the end of a session.
A commit should represent one thing: a new file, a bug fix, a refactored 
component. If a commit message needs "and" it should probably be two commits.
Never bundle unrelated changes. Always commit before moving to the next step.

---

## Project Structure

Files that exist today. Services, Utils helpers, and Onboarding are added in later steps.

```
EnzoApp/                              ← repo root / VS Code workspace
├── EnzoApp.xcodeproj/                ← Xcode project (PBXFileSystemSynchronizedRootGroup —
│                                         new files in EnzoApp/ are auto-included, no manual add)
├── EnzoApp/                          ← Xcode source root
│   ├── EnzoAppApp.swift              ← @main entry point; RootView (auth gate), MainTabView
│   ├── App/
│   │   └── AppState.swift            ← @Observable @MainActor global state; inject via .environment
│   │                                     Step 8: loadContext(), generateBriefing(), generateLookahead(),
│   │                                     briefingText, lookaheadText, isGeneratingBriefing/Lookahead
│   │                                     Step 9: loadSegments(), syncPhase2(), isSyncingPhase2
│   │                                     Step 10 Chunk 1: hasCompletedOnboarding, isResolvingOnboarding,
│   │                                     disconnect(), resetSyncHistory()
│   │                                     Step 10 Chunk 2a ✓: isOnboardingSyncing, syncedActivityCount,
│   │                                     startOnboardingSync(), Claude response cache (UserDefaults)
│   │                                     Step 11: syncErrorMessage, lastSyncedAt (UserDefaults-persisted)
│   ├── Features/
│   │   ├── Arc/                      ← main experience
│   │   │   ├── ArcView.swift         ← composes all sections; .task triggers loadContext+generate on launch
│   │   │   │                             gear icon button → SettingsSheet (Step 10 Chunk 1)
│   │   │   ├── GoalHeaderView.swift  ← goal name, fitness label, trend, "Change goal" button
│   │   │   ├── GoalSettingView.swift ← Step 4 ✓ — sheet: search, Enzo reaction, date, confirm
│   │   │   │                             Step 10 Chunk 1: onGoalConfirmed callback, Path B "Help me pick one"
│   │   │   ├── ArcBriefingView.swift ← left-accent-bordered Enzo briefing card; isLoading spinner
│   │   │   ├── LookaheadSuggestionView.swift ← isLoading + empty state placeholder
│   │   │   ├── FitnessChartView.swift ← Swift Charts; LineMark+AreaMark, two RuleMarks, tap→sheet
│   │   │   ├── MonthDetailSheet.swift ← .presentationDetents bottom sheet on chart tap
│   │   │   ├── PROpportunitiesCard.swift ← goal segment first, then top 2 by strike score
│   │   │   ├── ArcInputBar.swift     ← pill input + animated send button
│   │   │   ├── PromptChipsView.swift ← horizontal scroll chips; defaultChips static property
│   │   │   └── ArcMessageView.swift  ← Enzo/user message bubbles (Enzo has left accent border)
│   │   ├── Segments/
│   │   │   ├── SegmentsView.swift    ← full list, goal segment first, sort menu
│   │   │   └── SegmentDetailView.swift ← PR card, fitness comparison, strike assessment
│   │   └── Onboarding/               ← Step 10 Chunk 1 ✓
│   │       ├── SettingsSheet.swift   ← Sync now, Reset sync history, Disconnect Strava
│   │       ├── ConnectView.swift     ← Step 10 Chunk 2b ✓ — hero screen, "Connect Strava" CTA
│   │       └── SyncProgressView.swift ← Step 10 Chunk 2c ✓ — route animation, copy phases, completion
│   ├── Models/
│   │   ├── AthleteContext.swift      ← AthleteContext + GoalContext structs; fitnessLabel(for:);
│   │   │                                 .preview, .previewBriefing, .previewLookahead, .previewChartContext
│   │   │                                 Step 8: build(name:snapshots:goalRow:lastActivityDate:) factory
│   │   ├── FitnessSnapshot.swift     ← Identifiable by month string; .previewSnapshots (18 months)
│   │   ├── FitnessSnapshot+Supabase.swift ← Step 5 ✓ — FitnessSnapshotRow Codable DTO; toSnapshot()
│   │   ├── SegmentScore.swift        ← Identifiable+Hashable by name; .previewSegments (5 segments)
│   │   │                                 filter(_:by:) for goal search
│   │   ├── SegmentScore+Supabase.swift ← Step 5 ✓ — SegmentScoreRow Codable DTO; toSegmentScore()
│   │   ├── Goal+Supabase.swift       ← Step 5 ✓ — GoalRow Codable DTO for goals table
│   │   └── ArcMessage.swift          ← role: .enzo / .user
│   ├── Services/
│   │   ├── ClaudeService.swift       ← Step 3 ✓ — Swift actor; stream(_:context:) → AsyncStream<String>
│   │   ├── StravaService.swift       ← Step 6 ✓ — Swift actor; OAuth URL builder, ASWebAuthenticationSession,
│   │   │                                 token exchange + storage, refreshTokenIfNeeded(), fetchAthlete()
│   │   ├── SupabaseService.swift     ← Step 5 ✓ — Swift actor; fetch/upsert for fitness_snapshots,
│   │   │                                 segment_scores, goals, createUser, fetchUserId
│   │   │                                 Step 8: fetchUserProfile(userId:), updateLastActivityDate(userId:date:)
│   │   └── SyncService.swift         ← Step 7 ✓ — Swift actor; syncPhase1(userId:), isQualifying(_:),
│   │                                     computeSnapshots(from:userId:) [static, pure, testable]
│   │                                     Step 8: writes last_activity_date to users after sync
│   │                                     Step 9: syncPhase2(userId:) — detail fetch, segment extraction, upsert
│   ├── Utils/
│   │   ├── Config.swift              ← xcconfig key accessors (Config.claudeAPIKey etc.)
│   │   ├── WindowContextProvider.swift ← Step 10 Chunk 1 ✓ — ASWebAuthenticationPresentationContextProviding
│   │   ├── KeychainHelper.swift      ← Step 6 ✓ — save/load/delete kSecClassGenericPassword; Strava key constants
│   │   │                                 + supabaseUserId constant (Step 7)
│   │   ├── FitnessCalculator.swift   ← Step 7 ✓ — pure static enum; efficiency, fitnessValue,
│   │   │                                 trendDirection (trendThreshold=0.008), fitnessLabel, cyclingTypes
│   │   ├── SegmentScorer.swift       ← Step 9 ✓ — pure static enum; strikeScore, strikeLabel, requiredFitnessLabel
│   │   └── Extensions/
│   │       ├── Color+Hex.swift       ← Color(hex: "RRGGBB") initializer
│   │       └── Color+Enzo.swift      ← semantic constants: .enzoBg .enzoCard .enzoAccent
│   │                                     .enzoGoal .enzoAmber .enzoPrimary .enzoSecondary
│   └── Config/
│       ├── Debug.xcconfig            ← gitignored — never commit
│       └── Release.xcconfig          ← gitignored — never commit
├── EnzoAppTests/                     ← unit test target (PBXFileSystemSynchronizedRootGroup)
│   ├── GoalSettingTests.swift        ← Step 4 ✓ — filter + prompt tests (10 passing)
│   ├── SupabaseServiceTests.swift    ← Step 5 ✓ — Codable DTO unit tests (9 passing) +
│   │                                     integration test (gated on SUPABASE_INTEGRATION_TESTS=1)
│   ├── KeychainHelperTests.swift     ← Step 6 ✓ — save/load/delete/overwrite round-trip (7 passing)
│   ├── StravaServiceTests.swift      ← Step 6 ✓ — URL construction + token/athlete JSON decoding (8 passing)
│   ├── FitnessCalculatorTests.swift  ← Step 7 ✓ — efficiency, fitnessValue, trend, label (18 passing)
│   ├── SyncServiceTests.swift        ← Step 7 ✓ — qualifying filter, computeSnapshots pipeline (23 passing)
│   ├── AthleteContextTests.swift     ← Step 8 ✓ — build factory, contextPayload, fitnessLabel (13 passing)
│   └── SegmentScorerTests.swift      ← Step 9 ✓ — strikeScore, strikeLabel, requiredFitnessLabel (13 passing)
├── .gitignore
├── CLAUDE.md
├── PRD.MD                            ← full product spec — source of truth
├── handoff.MD                        ← session handoff prompt for next Claude Code session
├── Info.plist                        ← explicit plist with $(VARIABLE) substitution
├── skills/
│   ├── swift-design.MD               ← read before building any view
│   ├── enzo-voice.MD                 ← read before writing any UI string or Enzo copy
│   ├── swift-patterns.MD             ← read before architecture decisions or new files
│   └── testing.md                    ← read before writing any logic or service code
└── Config/
    ├── Debug.xcconfig                ← gitignored — never commit
    └── Release.xcconfig              ← gitignored — never commit
```

---

## Current Build Status

> **Update this section as steps are completed.**

- [x] Step 1: Project setup, secrets infrastructure, 2-tab shell
- [x] Step 2: Arc UI (static, hardcoded data)
- [x] Step 3: Claude API wired (hardcoded context)
- [x] Model refactor: FitnessSnapshot/SegmentScore/AthleteContext/GoalContext updated to label+value model; all preview data matches Section 18
- [x] Step 4: Goal setting UI
- [x] Step 5: Supabase schema + models
- [x] Step 6: Strava OAuth
- [x] Step 7: Historical sync Phase 1 (activities + fitness computation)

- [x] Step 8: Context payload + Arc content generation (live Enzo)
- [x] Step 9: Historical sync Phase 2 + segment scoring
- [x] Step 10: Onboarding flow — Chunk 1 complete (auth gating, SettingsSheet, GoalSettingView Path B)
- [x] Step 10: Onboarding flow — Chunk 2a (AppState cache + sync state, SyncService count)
- [x] Step 10: Onboarding flow — Chunk 2b (ConnectView + EnzoAppApp routing)
- [x] Step 10: Onboarding flow — Chunk 2c (SyncProgressView + final gate wiring)
- [x] Step 11: Polish pass — core items complete (see build notes for what was deferred)
- [x] UI Refactor session: light mode color scheme, top-tab navigation (Today/Targets), tab caching fix
- [x] Today tab UI session: FitnessRingView (donut), chart at top, GoalHeader/PROpportunities removed from Today, timeframe picker on chart, dynamic Y scale
- [x] Targets tab UI session: GoalHeaderView pinned full-width header with accent tint; segment name hero + fitness comparison + segment stats columns; distance/elevation wired through Strava API → SegmentScore → UI; SegmentDetailView consolidated as single goal-setting entry point; alternating row shading; "Explore more segments" section header
- [x] Today tab header session: FitnessRingView pinned as accent-tint full-width header; ring color → chart blue; athlete name greeting; goal progress bar (current vs PR fitness)
- [ ] Step 11b: Enzo voice/prompt tuning pass (dedicated session — deferred from Step 11)
- [ ] Step 12: Strava webhooks (deferred — not needed for beta)

---

## Deferred Items

Small things noted during sessions but not worth stopping for. Pick these up in a future polish pass.

- **Dark header on Targets tab** — tried Option A (black `enzoPrimary` header background with white text) as a high-contrast alternative to the accent tint. No other screen uses that level of contrast yet, so deferred. Revisit when more of the app's visual language is settled.
- **Sync progress indicator during manual sync** — when sync is triggered from SettingsSheet and the sheet is dismissed, there's no visible indicator in the main UI. Could be a subtle activity indicator in the top bar while `isSyncingPhase2` is true.
- **FitnessChartView axis polish** — x-axis label overlap at some timeframes, Y-axis labels hidden. Attempted in the Today tab UI session, reverted due to alignment issues on device. Needs dedicated time.
- **`phase2ActivityLimit` still at 25** — raise to 100+ once smoke tests on distance/elevation data look clean.
- **`enzo-voice.MD` has stale fitness labels** — still uses old names (`Peak shape, Strong base, Building, Coming back`). Fix before any prompt work in Step 11b.

---

## Prompt Playground

`scripts/enzo_playground.py` — iterate on Enzo's system prompt, briefing/lookahead/goal prompts, and model without building the app. Responses stream to terminal in ~2 seconds.

```bash
# one-liner examples
python3 scripts/enzo_playground.py --mode briefing --fitness recovering --trend up
python3 scripts/enzo_playground.py --mode chat --message "Am I close to Hawk Hill?"
```

Full usage: `scripts/README.md`. Requires `ANTHROPIC_API_KEY` in environment and `pip3 install anthropic`.

When prompt changes are finalized, paste back into Swift source:
- System prompt → `EnzoApp/Services/ClaudeService.swift` → `systemPrompt`
- Briefing/lookahead/goal prompts → `EnzoApp/App/AppState.swift` → static prompt functions

---

## Skills

Reusable guidelines for specific types of work. Read the relevant skill before starting that type of work — don't rely on memory or defaults.

| When you're... | Read... |
|---|---|
| Building any view, component, or screen | `skills/swift-design.MD` |
| Writing any UI string, copy, or Enzo response | `skills/enzo-voice.MD` |
| Making architecture decisions or creating new files | `skills/swift-patterns.MD` |
| Writing any logic, service, or data transformation code | `skills/testing.md` |

---

## How to Work on This Project

**Starting a new session:** Read this file, check the build status above to know where we are, then read the relevant section of `PRD.MD` for the step you're working on.

**If a requirement is unclear:** The spec is the source of truth. If the spec doesn't cover it, ask before building — don't infer.

**If something in the spec conflicts with what's already built:** Flag it. Don't silently pick one over the other.

**When a step is complete:** Mark it done in the build status above and commit.

**Committing:** Commit after each discrete change with a descriptive message. Do not wait until the end of a step or session to commit.

**At the end of every session:** Write a prompt for the 
next Claude Code session. Include:
- What was completed this session (with commit refs if possible)
- What step comes next and exactly where to start
- Any bugs observed but not fixed
- Any decisions made that aren't yet reflected in CLAUDE.md or PRD.MD
- The first command or file to open
- Write it as something that can be pasted directly into a 
new Claude Code session without modification.
- Save this the prompt to Handoff.MD
- Commit and push

---

## Build Notes

Key decisions and gotchas discovered during development. Check this before making changes in these areas.
**Fitness model (completed refactor)**
The fitness model uses continuous `value: Double` (0.0–1.0, internal only) and user-facing `label: String` ("Epic", "Strong", "Building", "Baseline", "Recovering"). Numeric 0–100 scores are gone. `FitnessSnapshot` has `label`, `value`, `trend`. `SegmentScore` has `fitnessValueAtPR`, `currentFitnessValue`, `trendDirection`, `lastEffortSeconds`, `strikeLabel` (stored, not computed). `GoalContext` has `requiredFitnessLabel` and `requiredFitnessValue`. `AthleteContext.fitnessLabel(for:)` takes a 0.0–1.0 Double. Strike thresholds: ≥0.70 "No brainer", 0.45–0.70 "Worth a shot", <0.45 "Not quite ready".

**Xcode project auto-sync**
The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16 feature). Any Swift file created in the `EnzoApp/` directory tree is automatically included in the build — no need to manually add files to the `.xcodeproj`. Just create the file in the right folder.

**Color constants**
Never use raw hex strings in view files. All colors are defined as `Color.enzoXxx` in `Utils/Extensions/Color+Enzo.swift`. The `Color(hex:)` initializer in `Color+Hex.swift` is an internal primitive — views should only ever call the named constants.

**Preview data location**
All hardcoded preview data (Section 18 of spec) lives in the model files as static properties:
- `AthleteContext.preview` — athlete context struct
- `AthleteContext.previewBriefing` — hardcoded Enzo briefing text
- `AthleteContext.previewLookahead` — hardcoded lookahead suggestion
- `AthleteContext.previewChartContext` — hardcoded chart context sentence
- `FitnessSnapshot.previewSnapshots` — 18 months of fitness history
- `SegmentScore.previewSegments` — 5 Bay Area segments

**AppState injection**
`AppState` is created in `EnzoAppApp` with `@State private var appState = AppState()` and injected via `.environment(appState)` on `MainTabView`. Views read it with `@Environment(AppState.self) private var appState`. Do not pass AppState as a regular parameter.

**FitnessChartView tap detection**
Uses `chartOverlay` + `proxy.plotFrame` + `GeometryReader` to convert tap location to a `Date` x-axis value, then finds the nearest `FitnessSnapshot`. Sheet is triggered via `@State var showingDetail: Bool` + `sheet(isPresented:)`.

**ClaudeService streaming**
`ClaudeService` is a Swift `actor`. `AppState.sendMessage(_:)` calls it with `await`, iterates the returned `AsyncStream<String>`, and updates `streamingText` token by token. `ArcView` renders an in-progress Enzo bubble from `streamingText` while `isStreaming` is true; on completion the final text is appended to `arcMessages` as a permanent `ArcMessage`. The athlete context JSON (from `AthleteContext.contextPayload`) is prepended to every user message.

**Info.plist and secret key loading**
The project uses an explicit `Info.plist` at the repo root (`SRCROOT/Info.plist`) with `$(VARIABLE)` substitution, not Xcode's auto-generated one. `GENERATE_INFOPLIST_FILE = NO` and `INFOPLIST_FILE = Info.plist` in project build settings. `INFOPLIST_KEY_*` in xcconfig/pbxproj only works for Apple-recognized keys — custom keys silently disappear unless they're in an explicit Info.plist. The Info.plist itself is safe to commit (contains only variable references). xcconfig files with actual values remain gitignored.

**GitHub repo**
https://github.com/chadallen/EnzoApp — private. Push all work here. xcconfig files are gitignored.

**Unit test target**
`EnzoAppTests` target was added manually by editing `project.pbxproj` (UUIDs prefixed `ENZO2000...`). It uses `PBXFileSystemSynchronizedRootGroup` pointing at `/EnzoAppTests/` — any `.swift` file placed in that directory is automatically included in the test target. No manual file registration needed.

**Cross-actor calls from @MainActor to actor services**
`ClaudeService` is a Swift `actor`. Any `AppState` method that calls into it must be marked `async` so the call can be `await`ed. `sendMessage` and `goalReactionStream` both follow this pattern. All future AppState methods that call actor-isolated services need the same treatment.

**GoalSettingView location**
Lives in `Features/Arc/` for Steps 4–9. In Step 10 (Onboarding), it needs to be reachable from the onboarding flow — move it to a shared location then if needed. Don't pre-optimize.

**requiredFitnessLabel in setGoal — fixed in Step 9**
`AppState.setGoal` now calls `SegmentScorer.requiredFitnessLabel(fitnessValueAtPR:)`, which returns one tier below the PR fitness label (Epic→Strong, Strong→Building, etc.). Hawk Hill (Epic PR) now correctly shows "Strong fitness needed".
**Supabase REST API (no SDK)**
`SupabaseService` is a Swift `actor` using `URLSession` directly — no Supabase Swift SDK. Auth headers on every request: `apikey: <anon key>` and `Authorization: Bearer <anon key>`. Upserts use `POST` with `Prefer: resolution=merge-duplicates,return=representation` — this resolves unique constraint conflicts and returns the full inserted/updated row including its server-assigned UUID. The `return=representation` header is critical; without it, upserts return 204 with no body and decoding fails.

**Codable row DTOs**
`FitnessSnapshotRow`, `SegmentScoreRow`, `GoalRow` live in `Models/+Supabase.swift` files alongside their domain model counterparts. These are wire-format DTOs, not domain models — they map to DB column names (snake_case) via `CodingKeys`. `FitnessSnapshot.month` ("YYYY-MM") is stored as "YYYY-MM-01" (PostgreSQL `date` type); `toSnapshot()` trims the suffix back. `SegmentScoreRow.stravaSegmentId` is non-optional (required by DB) — SyncService provides it from Strava in Step 9.

**Supabase RLS**
All 7 tables were created with RLS disabled (dev-only). The anon key can read/write freely. RLS policies were not added through Step 11 — defer to before App Store submission.

**Integration test env var**
The Supabase round-trip test in `SupabaseServiceTests.swift` is gated on `SUPABASE_INTEGRATION_TESTS=1`. To run it: `export SUPABASE_INTEGRATION_TESTS=1` in Terminal, then run xcodebuild. The `VAR=value xcodebuild` prefix syntax does NOT reach the simulator process — the var must be exported first. `-testenv` is not a valid xcodebuild flag on this Xcode version.

**Strava OAuth (Step 6)**
`STRAVA_CLIENT_ID = 217529` — added to `Config/Debug.xcconfig` (gitignored). Redirect URI is `enzo://oauth`; registered in `Info.plist` as `CFBundleURLTypes` with scheme `enzo`. In Strava API settings, the "Authorization Callback Domain" must be set to `oauth` (not `localhost`) — Strava strips the scheme. `StravaService` is a Swift `actor` using `ASWebAuthenticationSession` with `callbackURLScheme: "enzo"`. Tokens stored in Keychain via `KeychainHelper`. Auth state (`isAuthenticated`, `stravaAthleteId`) lives on `AppState` and is restored from Keychain on launch. Auth gating is live in `RootView` since Step 10. `ASWebAuthenticationSession` with `prefersEphemeralWebBrowserSession = false` uses the shared Safari session — returning users who previously authorized the app will not be prompted for credentials again (Strava auto-completes the redirect).

**xcconfig `//` comment stripping**
In Xcode xcconfig files, `//` is treated as a comment even mid-value. `SUPABASE_URL = https://...` stores as `https:/` (second `/` and everything after is stripped). Fix: use an empty variable substitution to break up the `//`:
```
SUPABASE_HOST = hizswbzxwfxddocryvci.supabase.co
SUPABASE_URL = https:/$()/$(SUPABASE_HOST)
```
Apply this pattern to ANY URL stored in xcconfig. `$()` expands to empty string at build time, so the final value is `https://hizswbzxwfxddocryvci.supabase.co`. Already applied in `Debug.xcconfig` and `Release.xcconfig`.

**Step 7: lazy var incompatible with @Observable**
`lazy var` in a `@MainActor @Observable` class causes a compiler error because `@Observable` generates init accessors that can't reference lazy properties. Pattern: initialize services that depend on other services inside `init()` by creating local `let` bindings first, then assigning to stored `let` properties. `SyncService` follows this pattern in `AppState.init()`.

**SyncService fitness computation**
`SyncService.computeSnapshots(from:userId:)` is a static, pure function — testable without network. Each month's `FitnessSnapshotRow` uses a 2-month rolling window for `fitnessValue`/`avgEfficiency`, and that month's rides only for `hoursRidden`/`activityCount`. Trend direction compares rides in the 4 weeks before month-end vs the prior 4 weeks. Months with no prior-window rides default to `"flat"`.

**supabaseUserId storage**
Step 6 discarded the UUID returned by `supabaseService.createUser()`. Fixed in Step 7: stored in `AppState.supabaseUserId` and persisted to Keychain under `KeychainHelper.supabaseUserId = "supabase_user_id"`. Restored from Keychain in `AppState.init()`. Required for `syncPhase1()` to know which user row to write snapshots under.

**NSLog vs print() for Sweetpad/device log**
When running via Sweetpad (not Xcode), `print()` goes to stdout and does NOT appear in the iOS unified log stream. Use `NSLog()` for any logging that needs to be visible via `log stream --predicate 'process == "EnzoApp"'`. All sync logging in `AppState.syncPhase1()` uses `NSLog` for this reason.

**Step 7 smoke test results**
First sync wrote 97 rows to `fitness_snapshots`. All rows had `trend_direction = "flat"` due to the ±0.05 threshold being too large for the actual efficiency range (~0.10–0.28). Fixed in Step 8: threshold lowered to ±0.008. Re-run sync to rewrite rows with corrected trends.

**Step 8: Supabase migration required before re-syncing**
Before running syncPhase1 again (to get corrected trend directions), run this migration in Supabase:
```sql
alter table users add column last_activity_date date;
```
After running it, trigger a sync from the app. `SyncService.syncPhase1()` will now write the most recent qualifying ride date to `users.last_activity_date`, enabling accurate `days_since_last_ride` in the context payload.

**Step 8: Trend threshold lowered to 0.008**
`FitnessCalculator.trendThreshold` changed from 0.05 to 0.008. Calibrated against real Supabase data (efficiency range ~0.10–0.28). The 97 existing rows in `fitness_snapshots` were computed with the old threshold — re-running sync will rewrite them with corrected trend directions (upsert overwrites).

**Step 8: loadContext() + generateBriefing/Lookahead pattern**
`AppState.loadContext()` fetches snapshots, user profile, and active goal concurrently from Supabase, then calls `AthleteContext.build()`. `generateBriefing()` and `generateLookahead()` stream Claude responses into `briefingText`/`lookaheadText`. All three are triggered by `.task` in `ArcView` on every launch. Falls back to empty string (placeholder copy in view) until authenticated. Caching (daily refresh, UserDefaults) is complete — added Step 11.

**Step 8: fitness data is mostly Baseline/Recovering**
Real Supabase data shows 97 months almost entirely in "Recovering" or "Baseline" with one "Building" month. This is the actual fitness state vs. the illustrative hardcoded preview. Enzo will narrate the real state. The fitness model normalization (all-time min/max) may need tuning in Step 9 once segment data gives more context.

**Step 8: recent_weeks is empty in contextPayload**
`contextPayload()` includes `recent_weeks: []` as a placeholder. Per-activity weekly breakdown is deferred to Step 12 (webhooks), when individual ride data will be available.

**Supabase upsert requires on_conflict columns (all tables)**
Every POST with `Prefer: resolution=merge-duplicates` must include `?on_conflict=<column>` in the URL or Supabase ignores the hint and returns 409. Applied to all three upsert endpoints: `upsertFitnessSnapshot` (`?on_conflict=user_id,month`), `upsertSegmentScore` (`?on_conflict=user_id,strava_segment_id`), and `createUser` (`?on_conflict=strava_athlete_id`). If you add a new upsert, follow this pattern.

**Phase 2 rate limit and incremental sync (updated this session)**
Strava limits: 200 requests/15 min, 2000/day. Phase 1 uses ~4–5 requests (paginated list). Phase 2 first run uses ~26 requests (1 list page + 25 detail calls). Two full syncs in one 15-minute window exceeded the limit during development.

Fix: Phase 2 is now **incremental**. After each successful run, a `lastPhase2SyncTimestamp` is saved to `UserDefaults`. The next run passes `after=<unix timestamp>` to the Strava activities API, fetching only activities newer than that date. If no new activities → Phase 2 logs "No new activities — skipping" and returns immediately without any Strava API calls.

`phase2ActivityLimit = 25`. This is a tunable constant — raise toward 200 once smoke tests consistently pass. Production full-history import will need batch pausing (200 req/15 min). Deliberately held at 25 through Step 11 at Chad's request — do not raise without explicit instruction.

**To reset Phase 2 and re-fetch from scratch:** call `appState.resetSyncHistory()` — this is wired to a "Reset sync history" button in `SettingsSheet` (built in Step 10 Chunk 1). It clears `lastPhase2SyncTimestamp` from UserDefaults. `SyncService.lastPhase2SyncKey` is `static` (not private) so AppState can reference it. Do not add temp reset code — use the SettingsSheet button.

**Step 9: Phase 2 triggered automatically after Phase 1**
`AppState.syncPhase1()` calls `syncPhase2()` on completion. The person.circle button in ArcView triggers both phases sequentially. `isSyncingPhase2` flag is available for a future progress indicator.

**Step 9: loadSegments() falls back to preview data if Supabase is empty**
`AppState.loadSegments()` is a no-op (keeps `SegmentScore.previewSegments`) if the `segment_scores` table returns zero rows. This means the first launch before any sync shows preview data — correct behavior.

**Step 9: SegmentScorer strike score formula**
`base = clamp(0.5 + (currentFitness - fitnessAtPR) × 0.8, 0, 1)`. Trend adds ±0.05. PRs set within 30 days get ×0.85 recency discount. Thresholds: ≥0.70 "No brainer", 0.45–0.70 "Worth a shot", <0.45 "Not quite ready". `requiredFitnessLabel` returns one tier below the PR fitness label.

**Step 10 Chunk 1 — complete (this session)**
Auth gating live. `RootView` in `EnzoAppApp.swift` is the new root — it calls `loadContext()` before the gate resolves and shows: `ConnectPlaceholderView` (unauthenticated) → blank dark hold screen while `isResolvingOnboarding` is true → `GoalSettingView` (authenticated, no goal) → `MainTabView`. `hasCompletedOnboarding` auto-sets in `loadContext()` when `activeGoal != nil`. `disconnect()` wipes all Keychain/UserDefaults auth state and restores preview data. `SettingsSheet` (gear icon in Arc header) exposes Sync now, Reset sync history, Disconnect Strava. `GoalSettingView` now takes `onGoalConfirmed: (() -> Void)?` — used by the onboarding gate to advance without dismiss. Path B "Help me pick one" shows top 3 segments by strike score. On goal confirm, reaction text is copied to `appState.briefingText` and `generateLookahead()` fires for the new goal.

**Step 10 Chunk 2 — split into 2a/2b/2c to preserve context**

**Chunk 2a — AppState + SyncService (backend only, no new views)**
- `AppState.swift`: add `isOnboardingSyncing: Bool`, `syncedActivityCount: Int`, `startOnboardingSync()` async method
- `AppState.swift`: Claude response cache — persist `briefingText`/`lookaheadText` to UserDefaults after generation; restore on launch if < 24h old; invalidate on sync and on `disconnect()`
- `SyncService.swift`: change `syncPhase1(userId:)` return type from `Void` to `Int` (total activities fetched); `AppState.syncPhase1()` sets `syncedActivityCount` from this

**Chunk 2b — ConnectView + EnzoAppApp routing**
- `Features/Onboarding/ConnectView.swift`: hero screen ("Enzo" header, tagline, cycling SF Symbol, "Connect Strava" accent pill); calls `authenticate()` then `startOnboardingSync()`; inline error state
- `EnzoAppApp.swift`: replace `ConnectPlaceholderView` with `ConnectView`; remove `ConnectPlaceholderView` struct. Note: `isOnboardingSyncing` gate branch deferred to Chunk 2c (added alongside `SyncProgressView` so build always compiles)

**Chunk 2c — SyncProgressView**
- `Features/Onboarding/SyncProgressView.swift`: bezier-curve route animation (`trim(from:to:)` + repeat); 5 copy phases crossfading (driven by `isSyncing`/`isSyncingPhase2`); activity counter; 60s long-sync message; completion detection → `onComplete` clears `isOnboardingSyncing`

**isOnboardingSyncing flow**
`ConnectView` auth success → calls `appState.startOnboardingSync()` (sets `isOnboardingSyncing = true`, calls `syncPhase1`) → RootView routes to `SyncProgressView` → sync flags drop to false → SyncProgressView plays final beat → `onComplete: { appState.isOnboardingSyncing = false }` → gate advances to `GoalSettingView`.

**GoalContext.daysRemaining (added this session)**
`GoalContext` now has `daysRemaining: Int?` alongside `weeksRemaining: Int?`. Both computed from `targetDate` at the same time. `GoalHeaderView` uses `daysRemaining` for the display label: today / 1 day to go / N days to go (2–13) / N weeks to go (14+). `weeksRemaining` is still sent to Claude in the context payload.

**onGoalConfirmed → Arc briefing handoff (this session)**
When the user confirms a goal in `GoalSettingView`, `reactionText` is copied into `appState.briefingText` immediately. `generateLookahead()` fires in a background Task. No need to regenerate the briefing — the reaction IS the relevant briefing for the new goal.

**isResolvingOnboarding bootstrapping fix (this session)**
On first launch after Step 10 update, existing authenticated users had `hasCompletedOnboarding = false` (new UserDefaults key) but `loadContext()` was only called from `ArcView.task` — which never ran because the gate showed `GoalSettingView`. Fix: `RootView` calls `loadContext()` via `.task`. `isResolvingOnboarding` is set `true` in `AppState.init()` when `isAuthenticated && !hasCompletedOnboarding`, then set `false` at the end of `loadContext()`. The gate shows a blank dark screen while resolving — avoids flash of `GoalSettingView` for existing users.

**Strava webhooks deferred to Step 12**
Webhooks were originally Step 10. Decision: not needed for beta — testers can tap to sync manually after a ride. Deferred to after the Polish pass (Step 11). The manual sync button (person.circle → settings in Step 10) stays as the primary sync mechanism through beta.

**Smoke test — PASSED (pre-Step 10 gate complete)**
Phase 2 confirmed end-to-end: `[Sync P2] Upserting 109 segment rows`, `[Segments] Loaded 109 segments from Supabase`. Segments tab shows real segments. Goal persistence confirmed across relaunches. Step 10 code may proceed.

**Goal persistence via saveGoal() (fixed this session)**
`AppState.setGoal()` previously only updated in-memory state — goals were lost on relaunch. Fixed: `setGoal()` now fires a background Task calling `supabaseService.saveGoal()`. `saveGoal()` first PATCHes all existing active goals for the user to `is_active=false`, then POSTs a new goal row **without an `id` field** (using a private `GoalInsert` struct). Sending `"id": null` would conflict with PostgreSQL's NOT NULL + DEFAULT constraint on the auto-generated PK — the separate insert struct avoids this.

**GoalHeaderView empty state (fixed this session)**
`GoalHeaderView` now shows "No goal set / Set a goal" when `goal.segmentName.isEmpty`. The no-goal placeholder in `AthleteContext.build()` was `"—"` (em dash, non-empty) — changed to `""` so the `isEmpty` check works. If you see `"— PR"` in the header again, check the `AthleteContext.build()` fallback GoalContext.

**GoalSettingView used hardcoded preview segments (fixed this session)**
`filteredSegments` was referencing `SegmentScore.previewSegments` instead of `appState.segments`. Fixed. Goal search now shows real Supabase segments after sync.

**Phase 2 PR detection uses pr_rank, not athlete_pr_effort (fixed, commit 93dee1f)**
`athlete_pr_effort` is defined in Strava's `SummarySegment` schema but is **not populated** in activity detail API responses — it's always nil. The reliable signal is `pr_rank == 1` on `DetailedSegmentEffort`: if this effort is the athlete's all-time PR on this segment, `pr_rank` is 1. `StravaSegmentEffort` now has `prRank: Int?` and `startDateLocal: String`. The loop records a `SegmentScoreRow` only when `effort.prRank == 1`, using `effort.elapsedTime` as `prSeconds` and `effort.startDateLocal` as `prAchievedAt`. `StravaSegmentSummary` no longer has `athletePrEffort` — it only needs `id` and `name`. **Limitation:** only segments with a PR in the fetched activity window are captured. Raise `phase2ActivityLimit` in Step 11 to expand coverage.

**Step 10 Chunk 2a — complete**
`AppState` now has `isOnboardingSyncing: Bool` (set by `startOnboardingSync()`, cleared by SyncProgressView's `onComplete`), `syncedActivityCount: Int` (set after Phase 1), and `startOnboardingSync()` which sets the flag then calls `syncPhase1()`. Claude response cache: `generateBriefing/Lookahead()` persist to UserDefaults after streaming; `loadContext()` restores if < 24h old via `restoreCachedContent()`; `invalidateCachedContent()` clears on sync completion and disconnect. `SyncService.syncPhase1` now returns `Int` (total activities fetched).

**Step 10 Chunk 2b — complete**
`ConnectView.swift` is the new unauthenticated hero screen — "Enzo" header, tagline, `figure.outdoor.cycle` SF Symbol, "Connect Strava" accent pill button. On tap: `authenticate()` then `startOnboardingSync()`. Inline amber error state on auth failure. `ConnectPlaceholderView` removed. `EnzoAppApp.swift` now routes to `ConnectView` for unauthenticated state. `isOnboardingSyncing` gate branch (→ `SyncProgressView`) is added in Chunk 2c alongside the view itself.

**Step 10 Chunk 2c — complete**
`SyncProgressView.swift`: bezier-curve route animation (`CyclingRoutePath: Shape`, cubic bezier path suggesting terrain → switchback → climb), 5 crossfading copy phases driven by `isSyncing`/`isSyncingPhase2`, activity counter (`syncedActivityCount`), 60s long-sync message ("Big history — this is worth it."), completion detection → `onComplete`. `EnzoAppApp.swift`: `isOnboardingSyncing` gate branch added between `isResolvingOnboarding` and `!hasCompletedOnboarding`. Requires `import Combine` for `Timer.publish`. Color constants are `enzoPrimary`/`enzoSecondary` (not `enzoTextPrimary`/`enzoTextSecondary` — check Color+Enzo.swift before referencing).

**Partial auth guard (Step 10 fix)**
If `exchangeCode` succeeds but `createUser` (or `fetchAthlete`) fails, `stravaAthleteId` lands in Keychain without `supabaseUserId`. On relaunch `AppState.init()` would set `isAuthenticated = true` and `isResolvingOnboarding = true`, but `loadContext()` returned early (no `supabaseUserId`) without clearing `isResolvingOnboarding` — app stuck on blank screen forever. Two fixes applied: (1) `AppState.init()` requires both `stravaAthleteId` AND `supabaseUserId` in Keychain to set `isAuthenticated = true` — partial state is treated as unauthenticated. (2) `loadContext()` always sets `isResolvingOnboarding = false` even on early return.

**Preview text flash on relaunch (fixed Step 11)**
`briefingText` and `lookaheadText` now initialize to `""` in `AppState` instead of the preview strings. Both `ArcBriefingView` and `LookaheadSuggestionView` already had `isEmpty` checks showing placeholder copy — the fix was purely the initial value. No flash on relaunch.

**ConnectView NSLog removed (Step 11)**
The dev-only `NSLog("[ConnectView] authenticate error: \(error)")` has been removed.

**Swift 6 concurrency warnings (fixed Step 11)**
`Config` computed vars changed to `nonisolated(unsafe) static let` stored properties — values cached at startup, no longer `@MainActor`-inferred. `WindowContextProvider` marked `@MainActor` — also fixes the Main Thread Checker warning (`isKeyWindow` called off main thread). Remaining warnings in `StravaService`/`SupabaseService` are minor and build succeeds.

**syncErrorMessage in AppState (added Step 11)**
`AppState.syncErrorMessage: String?` is set in `syncPhase1()` on failure and cleared on sync start. `StravaError.notAuthenticated` and `.tokenExchangeFailed` → "Strava needs you to reconnect — takes 10 seconds." Generic errors → "Sync didn't complete — tap to try again." Displayed as an amber inline banner in `ArcView` between the goal header divider and scroll content, with a "Retry" button that re-runs `syncPhase1()`.

**lastSyncedAt in AppState (added Step 11)**
`AppState.lastSyncedAt: Date?` is set after a successful Phase 1 sync and persisted to `UserDefaults` under key `"lastSyncedAt"`. Restored on launch. Cleared on `disconnect()`. Displayed in `SettingsSheet` as a sublabel on the "Sync now" row: "Last synced [date, time]". During active sync shows "Fetching rides..." / "Scoring segments..." instead.

**Empty states (added Step 11)**
`SegmentsView` shows `figure.outdoor.cycle` + "No segments yet" + Enzo copy when `sortedSegments` is empty. `PROpportunitiesCard` shows Enzo copy when `segments` is empty (no broken "See all" link). `ArcBriefingView` and `LookaheadSuggestionView` already handled `isEmpty` — no changes needed there.

**No brainer pill pulse (added Step 11)**
`SegmentOpportunityRow` (in `PROpportunitiesCard`) and `SegmentStrikeRow` (in `SegmentsView`) both animate the strike pill with a 1.06× scale, 1.4s `easeInOut` repeating animation when `strikeLabel == "No brainer"`. The animation only activates on `onAppear` when the condition is true — other labels are unaffected.

**SettingsSheet sync status copy (fixed Step 11)**
`syncStatusText` previously exposed "Phase 1 running..." / "Phase 2 running..." to users. Changed to "Fetching rides..." / "Scoring segments..." — user-facing language that matches Enzo's voice.

**Enzo prompt/voice tuning deferred**
The system prompt in `ClaudeService`, and the `briefingPrompt`, `lookaheadPrompt`, and `goalReactionPrompt` in `AppState` were not reviewed or changed in Step 11. Chad wants a dedicated session focused entirely on Enzo's generated voice — prompts, output quality, and tuning against real ride data. This is Step 11b.

**phase2ActivityLimit still at 25**
Deliberately not raised during Step 11 at Chad's request. Raise to 100+ in Step 11b or Step 12 once smoke tests confirm no rate limit issues.

**Color scheme changed to light mode (UI Refactor session)**
All semantic color constants updated in `Color+Enzo.swift`: `enzoBg` → `#FAFAFA`, `enzoCard` → `#F7F7FA`, `enzoAccent` → `#FC5201` (orange-red), `enzoPrimary` → `#000000`, `enzoSecondary` → `#666666`. Added `enzoChartPrimary` (`#1E88E5`) and `enzoChartSecondary` (`#90CAF9`) for chart-specific colors. All `.preferredColorScheme(.dark)`, `.colorScheme(.dark)`, and `.toolbarColorScheme(.dark)` removed from all view files. `FitnessChartView` now uses `enzoChartPrimary` for line/dot/area fill.

**Navigation structure changed to top tabs (UI Refactor session)**
`MainTabView` now uses a custom top bar ("Enzo" left + gear right → SettingsSheet) and a tab picker row ("Today" / "Targets") with `enzoAccent` underline on active tab. Wraps everything in a `NavigationStack`. Content uses a `ZStack` with opacity toggle + `allowsHitTesting` to keep both views alive (avoids re-running `.task` on tab switch). Tab names: "Today" (was "Arc"), "Targets" (was "Segments"). When drilling into a segment from Targets, the full screen pushes (custom top bar disappears, system nav bar with back button appears) — identical to Strava behavior.

**ArcView no longer has a sticky header (UI Refactor session)**
`ArcView` header ("Enzo" + gear) and sticky `GoalHeaderView` removed. Both now live in `MainTabView` (gear) and `ArcView`'s scroll content `LazyVStack` (GoalHeaderView as first item). Sync error banner also moved into scroll content, styled as a card with `RoundedRectangle` background. `showSettings` state removed from `ArcView`.

**SegmentsView NavigationStack removed (UI Refactor session)**
`SegmentsView` no longer wraps itself in a `NavigationStack`. Push navigation to `SegmentDetailView` is handled by the outer `NavigationStack` in `MainTabView`. `navigationDestination(for: SegmentScore.self)` stays on `SegmentsView`'s content — this works from any view inside a `NavigationStack` ancestor. Sort button moved from toolbar to an inline bar above the list.

**generateBriefing/Lookahead caching guard (UI Refactor session)**
`generateBriefing(forceRefresh: Bool = false)` and `generateLookahead(forceRefresh: Bool = false)` skip generation if content already exists unless `forceRefresh: true`. Prevents regeneration when switching back to the Today tab. The `.task` in `ArcView` uses default `false`. The briefing refresh button and goal-confirm path pass `forceRefresh: true`.

**enzo-voice.MD has stale fitness labels**
The system prompt copy in `skills/enzo-voice.MD` still uses old fitness label names (`Peak shape, Strong base, Building, Coming back`) instead of current labels (`Epic, Strong, Building, Baseline, Recovering`). The actual implementation in `ClaudeService.swift` is correct. Fix `enzo-voice.MD` before doing any prompt work in Step 11b.

**Today tab restructured (Today tab UI session)**
`ArcView` no longer shows `GoalHeaderView` or `PROpportunitiesCard`. New layout: `FitnessRingView` (top), `FitnessChartView`, sync error banner, `ArcBriefingView`, `LookaheadSuggestionView`, message thread. Both removed components still exist in the codebase — they'll be reconsidered for the Targets tab.

**FitnessRingView — donut fitness score card (Today tab UI session)**
New file at `Features/Arc/FitnessRingView.swift`. Uses `SectorMark` (iOS 17+). Ring color: `enzoRingHigh` (#27AE60) for Epic/Strong, `enzoAccent` for Building, `enzoRingLow` (#E67E22) for Baseline/Recovering. Center shows `Int(currentFitnessValue × 100)%`. Right side shows STATUS (label + trend arrow) and LAST RIDE. New color constants `enzoRingHigh` and `enzoRingLow` added to `Color+Enzo.swift`.

**FitnessChartView timeframe picker + dynamic Y scale (Today tab UI session)**
`ChartTimeframe` enum (YTD / 1Y / 5Y / All) lives in `FitnessChartView.swift`. `filteredSnapshots` computed property filters the snapshot array per selection. `yDomain` is dynamic: fits to visible data min/max + 30% padding (minimum range 0.05). X-axis uses `@AxisContentBuilder` switching: YTD + 1Y → monthly abbreviations, 5Y + All → abbreviated years (`'24`). `contextText` parameter removed from this view.

**PromptChipsView trimmed (Today tab UI session)**
Removed "Am I on track for Hawk Hill?" (goal-specific hardcoded) and "What if I only have 4 weeks left?" (date-specific). Remaining chips: "What should I do this weekend?" and "When was I last this fit?"

**PromptChipsView removed from Today tab (Targets/Today session)**
`PromptChipsView` is no longer rendered in `ArcView`. The file still exists — not deleted. Input area is now just `ArcInputBar`.

**GoalHeaderView on Targets tab (Targets/Today session)**
`GoalHeaderView` is now pinned above the segment list in `SegmentsView` as a full-width header with `enzoAccent.opacity(0.08)` background and `UnevenRoundedRectangle` (flat top, rounded bottom). Layout: "CURRENT TARGET SEGMENT" caption → segment name (title2 bold) → three columns: Segment stats (distance, PR time, PR date, elevation) | Current fitness (label + %) | PR fitness (label + %). The "Change goal" button was removed from the header — goal changes happen via `SegmentDetailView`. `GoalHeaderView` still has `emptyGoalState` with "Set a goal" button.

**Distance and elevation in SegmentScore (Targets/Today session)**
`SegmentScore` has two new optional fields: `distanceMeters: Double? = nil` and `elevationDeltaMeters: Double? = nil`. `SegmentScoreRow` has matching `distanceMeters`/`elevationDeltaMeters` Codable fields mapped to `distance_meters`/`elevation_delta_meters` DB columns. `StravaSegmentSummary` now decodes `distance`, `elevationHigh`, `elevationLow`. `SyncService.syncPhase2` passes these through when writing PR rows. **Supabase migration already applied:** `alter table segment_scores add column distance_meters float8; alter table segment_scores add column elevation_delta_meters float8;` Existing rows have nulls until re-sync. To populate: Settings → Reset sync history → Sync.

**SegmentDetailView is now the single goal-setting entry point (Targets/Today session)**
`SegmentDetailView` now has `@Environment(AppState.self)`, target date state, and a goal card at the bottom. Non-goal segments show: target date toggle + date picker + "Set this goal" accent button. Goal segments show: "This is your current goal" accent tint badge. Setting goal fires `generateBriefing(forceRefresh: true)` + `generateLookahead(forceRefresh: true)` in background. `GoalSettingView` is still used for onboarding only. `SegmentDetailView` also gained: expanded stats card (PR time, formatted date, distance, elevation), fitness percentages in comparison blocks, "READINESS SCORE" section header distinguishing readiness from fitness scores.

**FitnessRingView pinned as Today tab header (Targets/Today session)**
`FitnessRingView` is no longer inside `ArcView`'s `ScrollView`. It's pinned above the scroll content as a full-width header (`fullWidth: true`) matching the Targets tab header style. Ring color changed from tier-based (green/orange/amber) to always `enzoChartPrimary` (#1E88E5 blue) for contrast against the orange tint background. Added: athlete name greeting above the ring row; goal progress bar below the ring row (shows current fitness fill vs PR fitness tick marker, "You · X%" / "PR · Y%" labels). Progress bar only renders when a goal segment exists. `enzoRingHigh` and `enzoRingLow` color constants remain in `Color+Enzo.swift` but are no longer used by `FitnessRingView`.
