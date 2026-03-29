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
- **Anthropic Claude API** (`claude-sonnet-4-20250514`) for AI features.
- **Strava OAuth 2.0** for authentication and data access.
- **No third-party dependencies** unless the spec explicitly names one.

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

### Build Order
Follow Section 17 of the spec exactly. Do not skip steps. Key checkpoints:
- Steps 1–4: Hardcoded data only. App launches directly into ArcView. No auth flow, no onboarding.
- Step 3: Claude API wired with hardcoded context payload — use values from Section 18.
- Step 5: Supabase schema and models.
- Step 6: Strava OAuth — first live API. Moved earlier because bulk export is not a viable dev fixture.
- Steps 7–9: Real data sync, fitness computation, segment scoring.
- Step 11: Onboarding flow — built last, after everything behind it works.

### Commits
Commit after every discrete unit of work — not at the end of a session.
A commit should represent one thing: a new file, a bug fix, a refactored 
component. If a commit message needs "and" it should probably be two commits.
Never bundle unrelated changes. Always commit before moving to the next step.

---

## Project Structure

Files that exist today. Services, Utils helpers, and Onboarding are added in later steps.

```
EnzoApp/  
└── PRD.md                  ← full product spec — source of truth                            ← repo root / VS Code workspace
├── EnzoApp.xcodeproj/                ← Xcode project (PBXFileSystemSynchronizedRootGroup —
│                                         new files in EnzoApp/ are auto-included, no manual add)
├── EnzoApp/                          ← Xcode source root
│   ├── EnzoAppApp.swift              ← @main entry point + MainTabView (2-tab shell)
│   ├── App/
│   │   └── AppState.swift            ← @Observable @MainActor global state; inject via .environment
│   ├── Features/
│   │   ├── Arc/                      ← main experience
│   │   │   ├── ArcView.swift         ← composes all sections; sticky header + scrollable content
│   │   │   ├── GoalHeaderView.swift  ← goal name, fitness progress bar, "Change goal" button
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
│   │   ├── SegmentScore.swift        ← Identifiable+Hashable by name; .previewSegments (5 segments)
│   │   └── ArcMessage.swift          ← role: .enzo / .user
│   ├── Services/                     ← ClaudeService built in Step 3; others added later
│   │   ├── ClaudeService.swift       ← Step 3 ✓ — Swift actor; stream(_:context:) → AsyncStream<String>
│   │   ├── StravaService.swift       ← Step 6
│   │   ├── SupabaseService.swift     ← Step 5
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
├── .gitignore
├── CLAUDE.md
├── skills/
│   ├── swiftui-design.md             ← read before building any view
│   ├── enzo-voice.md                 ← read before writing any UI string or Enzo copy
│   ├── swift-patterns.md             ← read before architecture decisions or new files
│   └── testing.md                    ← read before writing any logic or service code
└── dev-data/
    
```

---

## Current Build Status

> **Update this section as steps are completed.**

- [x] Step 1: Project setup, secrets infrastructure, 2-tab shell
- [x] Step 2: Arc UI (static, hardcoded data)
- [x] Step 3: Claude API wired (hardcoded context)
- [x] Model refactor: FitnessSnapshot/SegmentScore/AthleteContext/GoalContext updated to label+value model; all preview data matches Section 18
- [x] Step 4: Goal setting UI
- [ ] Step 5: Supabase schema + models
- [ ] Step 6: Strava OAuth
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
| Building any view, component, or screen | `skills/swiftui-design.md` |
| Writing any UI string, copy, or Enzo response | `skills/enzo-voice.md` |
| Making architecture decisions or creating new files | `skills/swift-patterns.md` |
| Writing any logic, service, or data transformation code | `skills/testing.md` |

---

## How to Work on This Project

**Starting a new session:** Read this file, check the build status above to know where we are, then read the relevant section of `dev-data/enzo-spec.md` for the step you're working on.

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