# Enzo Swift Patterns Skill

Read this before making any architecture decisions, creating new files, or establishing patterns that will be used across the codebase.

---

## State Management

Use `@Observable` (Swift 5.9+) throughout. Do not use `ObservableObject`, `@Published`, or Combine.

```swift
// ✅ Correct
@Observable
class AppState {
    var currentGoal: Goal?
    var fitnessSnapshots: [FitnessSnapshot] = []
    var issyncing: Bool = false
}

// ❌ Never use
class AppState: ObservableObject {
    @Published var currentGoal: Goal?
}
```

**State ownership:**
- `AppState` — global singleton, injected via `.environment`. Owns: current user, active goal, sync status.
- Feature-level `@State` — local to a view, not shared.
- `@Binding` — for passing state down to child views that need to mutate it.
- Never duplicate state. If two views need the same data, it lives in `AppState` or a shared service.

---

## Async/Await

All async work uses Swift concurrency. No completion handlers, no Combine publishers.

```swift
// ✅ Correct
func fetchFitnessHistory() async throws -> [FitnessSnapshot] {
    let data = try await supabaseService.query("fitness_snapshots")
    return data.map { FitnessSnapshot(from: $0) }
}

// Call sites
Task {
    do {
        snapshots = try await fetchFitnessHistory()
    } catch {
        // handle error
    }
}

// ❌ Never use
func fetchFitnessHistory(completion: @escaping ([FitnessSnapshot]) -> Void) { }
```

**Main actor:**
Any update to `@Observable` state that drives UI must happen on the main actor:

```swift
await MainActor.run {
    self.fitnessSnapshots = snapshots
}
// or annotate the class: @MainActor @Observable class AppState { }
```

---

## Service Layer

Each service owns one domain. Services are classes, not structs. Inject via `@Environment` or pass directly.

```swift
// One responsibility per service
ClaudeService    // Claude API calls and streaming only
StravaService    // OAuth, activity fetch, webhooks only
SupabaseService  // DB reads and writes only
SyncService      // Orchestrates the Strava → metrics pipeline
```

Services do not own UI state. They return data or throw errors. Views decide what to do with results.

```swift
// ✅ Service returns data, view owns state
class ClaudeService {
    func ask(question: String, context: AthleteContext) async throws -> AsyncStream<String> { }
}

// ❌ Service should not own @Observable state
@Observable class ClaudeService {
    var lastResponse: String = ""
}
```

---

## Claude API Streaming

All Claude responses stream. Use `AsyncStream<String>` to pipe tokens into the UI.

```swift
// ClaudeService.swift
func stream(prompt: String, context: AthleteContext) -> AsyncStream<String> {
    AsyncStream { continuation in
        Task {
            // URLSession streaming request
            // For each token received:
            continuation.yield(token)
            // On complete:
            continuation.finish()
        }
    }
}

// In view:
var displayText = ""

Task {
    for await token in claudeService.stream(prompt: question, context: context) {
        displayText += token  // @Observable triggers re-render automatically
    }
}
```

Never buffer the full response before displaying. First token should appear on screen within ~300ms.

---

## Error Handling

All errors are caught at the view layer and translated to user-facing copy using the Enzo voice (see `skills/enzo-voice.md`). Services throw typed errors.

```swift
// Define typed errors per service
enum ClaudeError: Error {
    case timeout
    case invalidResponse
    case rateLimited
}

// Views catch and display
do {
    response = try await claudeService.ask(...)
} catch ClaudeError.timeout {
    errorMessage = "Enzo couldn't connect — tap to retry."
} catch {
    errorMessage = "Something went wrong — tap to retry."
}
```

Never show raw error messages or system error descriptions to the user.

---

## Config & Secrets

```swift
// Utils/Config.swift — read-only accessors, never set values here
enum Config {
    static var claudeAPIKey: String {
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
    }
    static var supabaseURL: String {
        Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
    }
    static var supabaseAnonKey: String {
        Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
    }
    static var stravaClientID: String {
        Bundle.main.infoDictionary?["STRAVA_CLIENT_ID"] as? String ?? ""
    }
    static var stravaClientSecret: String {
        Bundle.main.infoDictionary?["STRAVA_CLIENT_SECRET"] as? String ?? ""
    }
}
```

User credentials (Strava tokens) go in Keychain, not Config:

```swift
// Utils/KeychainHelper.swift
class KeychainHelper {
    static func save(_ value: String, for key: String) { }
    static func load(for key: String) -> String? { }
    static func delete(for key: String) { }
}

// Usage
KeychainHelper.save(accessToken, for: "strava_access_token")
let token = KeychainHelper.load(for: "strava_access_token")
```

---

## Data Flow: Strava → Supabase

This pipeline is the core of the app. Follow it exactly.

```
Phase 1: GET /athlete/activities (paginated, 200/page)
    → SummaryActivity includes average_heartrate directly
    → FitnessCalculator.swift (in-memory)
    → Supabase: fitness_snapshots, personal_bests

Phase 2: GET /activities/{id}?include_all_efforts=true (1 per activity, background)
    → segment_efforts[].segment.athlete_pr_effort has PR data
    → SegmentScorer.swift (in-memory)
    → Supabase: segment_scores

AthleteContext.swift (assembled at query time from Supabase)
    ↓
ClaudeService (context payload, never persisted)
```

**Raw Strava data never touches Supabase.** Compute first, write only the output.

**Never use `GET /segment_efforts`** — requires paid Strava subscription. All segment data comes from activity detail calls.

**Always use `sport_type` not `type`** — `type` is deprecated. Filter cycling activities by: `Ride`, `VirtualRide`, `MountainBikeRide`, `GravelRide`, `EMountainBikeRide`.

---

## File Naming & Organization

- One view per file. File name matches view name exactly.
- One model per file.
- Extensions in `Utils/Extensions/` named `Type+Purpose.swift` e.g. `Color+Enzo.swift`, `Date+Formatting.swift`
- No massive files. If a view file exceeds ~150 lines, extract subviews.

```swift
// ✅ Extract subviews
struct ArcView: View {
    var body: some View {
        ScrollView {
            GoalHeaderView()
            ArcBriefingView()
            FitnessChartView()
        }
    }
}

// ❌ Don't build everything in one body
struct ArcView: View {
    var body: some View {
        ScrollView {
            // 400 lines of inline view code
        }
    }
}
```

---

## What Not To Use

| Avoid | Use instead |
|---|---|
| `ObservableObject` / `@Published` | `@Observable` |
| Combine | `async/await` + `AsyncStream` |
| `UIKit` directly | SwiftUI only |
| Third-party HTTP libraries | `URLSession` + `async/await` |
| Third-party chart libraries | Swift Charts |
| `CoreData` | Supabase (remote) or `UserDefaults` (local prefs) |
| Completion handlers | `async throws` |
| Hardcoded color hex values in views | `Color.enzoAccent` etc. |
| Hardcoded API key strings | `Config.claudeAPIKey` |