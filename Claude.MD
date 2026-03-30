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
6. **Strava OAuth** — Auth flow, token storage, athlete profile fetch.
7. **Historical sync Phase 1** — Paginated activity fetch. Run FitnessCalculator in-memory. Write fitness snapshots to Supabase.
8. **Context payload + live Enzo** — Build AthleteContext from Supabase. Feed into all Claude calls. Tune model constants against real data.
9. **Historical sync Phase 2 + segment scoring** — Background fetch of activity details. Extract segment efforts. Run SegmentScorer. Wire Segments tab and Arc PR card.
10. **Strava webhooks** — Real-time new activity handling.
11. **Onboarding flow** — Connect screen, sync animation, goal setting as front door.
12. **Polish pass** — Animations, empty states, error states, copy review, settings.
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
- Dark mode first. Background `#0A0A0F`, card surfaces `#141420`.
- Brand accent `#4FC3F7` (blue). Goal accent `#81C784` (green). Amber `#FFB74D` sparingly.
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
│   ├── EnzoAppApp.swift              ← @main entry point + MainTabView (2-tab shell)
│   ├── App/
│   │   └── AppState.swift            ← @Observable @MainActor global state; inject via .environment
│   ├── Features/
│   │   ├── Arc/                      ← main experience
│   │   │   ├── ArcView.swift         ← composes all sections; sticky header + scrollable content
│   │   │   ├── GoalHeaderView.swift  ← goal name, fitness label, trend, "Change goal" button
│   │   │   ├── GoalSettingView.swift ← Step 4 ✓ — sheet: search, Enzo reaction, date, confirm
│   │   │   ├── ArcBriefingView.swift ← left-accent-bordered Enzo briefing card
│   │   │   ├── LookaheadSuggestionView.swift
│   │   │   ├── FitnessChartView.swift ← Swift Charts; LineMark+AreaMark, two RuleMarks, tap→sheet
│   │   │   ├── MonthDetailSheet.swift ← .presentationDetents bottom sheet on chart tap
│   │   │   ├── PROpportunitiesCard.swift ← goal segment first, then top 2 by strike score
│   │   │   ├── ArcInputBar.swift     ← pill input + animated send button
│   │   │   ├── PromptChipsView.swift ← horizontal scroll chips; defaultChips static property
│   │   │   └── ArcMessageView.swift  ← Enzo/user message bubbles (Enzo has left accent border)
│   │   ├── Segments/
│   │   │   ├── SegmentsView.swift    ← full list, goal segment first, sort menu
│   │   │   └── SegmentDetailView.swift ← PR card, fitness comparison, strike assessment
│   │   └── Onboarding/               ← Step 11 only — not built yet
│   ├── Models/
│   │   ├── AthleteContext.swift      ← AthleteContext + GoalContext structs; fitnessLabel(for:);
│   │   │                                 .preview, .previewBriefing, .previewLookahead, .previewChartContext
│   │   ├── FitnessSnapshot.swift     ← Identifiable by month string; .previewSnapshots (18 months)
│   │   ├── FitnessSnapshot+Supabase.swift ← Step 5 ✓ — FitnessSnapshotRow Codable DTO; toSnapshot()
│   │   ├── SegmentScore.swift        ← Identifiable+Hashable by name; .previewSegments (5 segments)
│   │   │                                 filter(_:by:) for goal search
│   │   ├── SegmentScore+Supabase.swift ← Step 5 ✓ — SegmentScoreRow Codable DTO; toSegmentScore()
│   │   ├── Goal+Supabase.swift       ← Step 5 ✓ — GoalRow Codable DTO for goals table
│   │   └── ArcMessage.swift          ← role: .enzo / .user
│   ├── Services/
│   │   ├── ClaudeService.swift       ← Step 3 ✓ — Swift actor; stream(_:context:) → AsyncStream<String>
│   │   ├── StravaService.swift       ← Step 6
│   │   ├── SupabaseService.swift     ← Step 5 ✓ — Swift actor; fetch/upsert for fitness_snapshots,
│   │   │                                 segment_scores, goals via URLSession REST (no SDK)
│   │   └── SyncService.swift         ← Step 7
│   ├── Utils/
│   │   ├── Config.swift              ← xcconfig key accessors (Config.claudeAPIKey etc.)
│   │   ├── KeychainHelper.swift      ← Step 6
│   │   ├── FitnessCalculator.swift   ← Step 7
│   │   ├── SegmentScorer.swift       ← Step 9
│   │   └── Extensions/
│   │       ├── Color+Hex.swift       ← Color(hex: "RRGGBB") initializer
│   │       └── Color+Enzo.swift      ← semantic constants: .enzoBg .enzoCard .enzoAccent
│   │                                     .enzoGoal .enzoAmber .enzoPrimary .enzoSecondary
│   └── Config/
│       ├── Debug.xcconfig            ← gitignored — never commit
│       └── Release.xcconfig          ← gitignored — never commit
├── EnzoAppTests/                     ← unit test target (PBXFileSystemSynchronizedRootGroup)
│   ├── GoalSettingTests.swift        ← Step 4 ✓ — filter + prompt tests (10 passing)
│   └── SupabaseServiceTests.swift    ← Step 5 ✓ — Codable DTO unit tests (9 passing) +
│                                         integration test (gated on SUPABASE_INTEGRATION_TESTS=1)
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
- [ ] Step 7: Historical sync Phase 1 (activities + fitness computation)
- [ ] Step 8: Context payload + Arc content generation (live Enzo)
- [ ] Step 9: Historical sync Phase 2 + segment scoring
- [ ] Step 10: Strava webhooks
- [ ] Step 11: Onboarding flow
- [ ] Step 12: Polish pass

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
Lives in `Features/Arc/` for Steps 4–10. In Step 11 (Onboarding), it needs to be reachable from the onboarding flow — move it to a shared location then if needed. Don't pre-optimize.

**requiredFitnessLabel in setGoal — known placeholder**
`AppState.setGoal` sets `requiredFitnessValue = segment.fitnessValueAtPR` directly. For Hawk Hill (0.98 → "Epic"), the header shows "Epic fitness needed" rather than the spec's "Strong". The correct derivation belongs in `SegmentScorer` (Step 9) and will be fixed then.
**Supabase REST API (no SDK)**
`SupabaseService` is a Swift `actor` using `URLSession` directly — no Supabase Swift SDK. Auth headers on every request: `apikey: <anon key>` and `Authorization: Bearer <anon key>`. Upserts use `POST` with `Prefer: resolution=merge-duplicates,return=representation` — this resolves unique constraint conflicts and returns the full inserted/updated row including its server-assigned UUID. The `return=representation` header is critical; without it, upserts return 204 with no body and decoding fails.

**Codable row DTOs**
`FitnessSnapshotRow`, `SegmentScoreRow`, `GoalRow` live in `Models/+Supabase.swift` files alongside their domain model counterparts. These are wire-format DTOs, not domain models — they map to DB column names (snake_case) via `CodingKeys`. `FitnessSnapshot.month` ("YYYY-MM") is stored as "YYYY-MM-01" (PostgreSQL `date` type); `toSnapshot()` trims the suffix back. `SegmentScoreRow.stravaSegmentId` is non-optional (required by DB) — SyncService provides it from Strava in Step 9.

**Supabase RLS**
All 7 tables were created with RLS disabled (dev-only). The anon key can read/write freely. RLS policies will be scoped to authenticated users in Step 6 when Strava OAuth is wired.

**Integration test env var**
The Supabase round-trip test in `SupabaseServiceTests.swift` is gated on `SUPABASE_INTEGRATION_TESTS=1`. To run it: `export SUPABASE_INTEGRATION_TESTS=1` in Terminal, then run xcodebuild. The `VAR=value xcodebuild` prefix syntax does NOT reach the simulator process — the var must be exported first. `-testenv` is not a valid xcodebuild flag on this Xcode version.

**Strava OAuth (Step 6)**
`STRAVA_CLIENT_ID = 217529` — added to `Config/Debug.xcconfig` (gitignored). Redirect URI is `enzo://oauth`; registered in `Info.plist` as `CFBundleURLTypes` with scheme `enzo`. In Strava API settings, the "Authorization Callback Domain" must be set to `oauth` (not `localhost`) — Strava strips the scheme. `StravaService` is a Swift `actor` using `ASWebAuthenticationSession` with `callbackURLScheme: "enzo"`. Tokens stored in Keychain via `KeychainHelper`. Auth state (`isAuthenticated`, `stravaAthleteId`) lives on `AppState` and is restored from Keychain on launch. The app still launches into ArcView — no auth gating until Step 11.

**xcconfig `//` comment stripping**
In Xcode xcconfig files, `//` is treated as a comment even mid-value. `SUPABASE_URL = https://...` stores as `https:/` (second `/` and everything after is stripped). Fix: use an empty variable substitution to break up the `//`:
```
SUPABASE_HOST = hizswbzxwfxddocryvci.supabase.co
SUPABASE_URL = https:/$()/$(SUPABASE_HOST)
```
Apply this pattern to ANY URL stored in xcconfig. `$()` expands to empty string at build time, so the final value is `https://hizswbzxwfxddocryvci.supabase.co`. This is already applied in `Debug.xcconfig` — apply the same to `Release.xcconfig` before Step 8.

**Swift 6 concurrency warnings**
Several warnings of the form `main actor-isolated ... cannot be used in actor-isolated context` exist in `StravaService.swift` and pre-existing in `SupabaseService.swift`. Root cause: `Config` computed vars access `Bundle.main` (a `@MainActor` API), making them `@MainActor`-isolated; `KeychainHelper` static methods are similarly inferred as `@MainActor`. All are warnings only — build succeeds. Fix in a Swift 6 cleanup pass, not in feature steps.
