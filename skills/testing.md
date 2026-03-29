# Enzo Testing Skill

Read this when writing any logic code, services, or data transformation functions.

---

## Philosophy

Test logic, not UI. SwiftUI previews handle visual validation. Unit tests handle correctness of pure functions. Don't build test infrastructure that becomes a project in itself.

**Test these:**
- `FitnessCalculator.swift` — all computation functions
- `SegmentScorer.swift` — strike score and label logic
- `SyncService.swift` — data transformation pipeline
- `AthleteContext.swift` — context payload assembly
- `ClaudeService.swift` — prompt construction, not API calls

**Don't test these in MVP:**
- SwiftUI views
- Supabase read/write (integration test territory)
- Strava API calls
- Claude API responses

---

## Unit Test Rules

**Always write tests alongside logic code.** When you create a logic file, create its test file in the same step. Never defer tests to later.

File naming: `FitnessCalculator.swift` → `FitnessCalculatorTests.swift` in the `EnzoAppTests` target.

**Test structure — use Swift Testing (not XCTest):**
```swift
import Testing
@testable import EnzoApp

@Suite("FitnessCalculator")
struct FitnessCalculatorTests {

    @Test("activity load increases with higher HR")
    func activityLoadScalesWithHR() {
        let lowHR = FitnessCalculator.activityLoad(
            durationHours: 1.0, avgHR: 110, restingHR: 60
        )
        let highHR = FitnessCalculator.activityLoad(
            durationHours: 1.0, avgHR: 155, restingHR: 60
        )
        #expect(highHR > lowHR)
    }

    @Test("fitness score normalizes to 0-100 range")
    func fitnessScoreInRange() {
        let loads = [10.0, 25.0, 40.0, 15.0, 35.0]
        let score = FitnessCalculator.fitnessScore(
            currentLoad: 25.0,
            historicalLoads: loads
        )
        #expect(score >= 0)
        #expect(score <= 100)
    }

    @Test("missing HR data falls back to duration-only")
    func missingHRFallback() {
        let load = FitnessCalculator.activityLoad(
            durationHours: 1.0, avgHR: nil, restingHR: 60
        )
        #expect(load > 0)
    }
}
```

**What to test per module:**

`FitnessCalculator`:
- Activity load scales with HR intensity
- Fitness score stays within 0-100
- Missing HR (nil) falls back gracefully to duration-only
- Score correctly identifies peak month from history
- Fitness label returns correct string for each score band

`SegmentScorer`:
- Strike score of 1.0 when fitter than PR by large margin
- Strike score of 0.0 when significantly less fit than PR
- "Strike now" label for score ≥ 0.7
- "Getting close" label for score 0.4–0.7
- "Not yet" label for score < 0.4
- Recency multiplier reduces score for recent PRs

`AthleteContext`:
- toJSON() produces valid JSON
- Goal context included when goal is set
- days_since_last_ride calculated correctly
- Fitness history sorted chronologically

---

## Running Tests

**From VS Code / Sweetpad:**
- `Cmd+U` in Xcode runs all tests
- Or use Sweetpad's test runner if available

**Ask Claude Code to run tests** after writing them:
*"Run the unit tests and show me the results before we move on."*

Claude Code can execute tests via the `xcodebuild test` command and report pass/fail in the terminal.

---

## SwiftUI Previews

Every view and component must have a `#Preview` using hardcoded data from Section 18 of the spec.

```swift
#Preview("Arc View — hardcoded data") {
    ArcView()
        .environment(AppState.preview)
        .preferredColorScheme(.dark)
}

#Preview("Segment row — strike now") {
    SegmentStrikeRow(segment: SegmentScore.previewStrikeNow)
        .padding()
        .background(Color.enzoBG)
}

#Preview("Segment row — not yet") {
    SegmentStrikeRow(segment: SegmentScore.previewNotYet)
        .padding()
        .background(Color.enzoBG)
}
```

Rules:
- Always use `.preferredColorScheme(.dark)` — Enzo is dark mode first
- Preview edge cases: empty states, long text, missing data
- Use static preview helpers on model types (`.preview`, `.previewStrikeNow` etc.)
- Never use `@State` in previews — use static data only

---

## Claude API Testing

When wiring `ClaudeService.swift`, verify the integration with a manual debug call before marking the step complete. Add a temporary test function:

```swift
// Temporary — remove before Step 4
func debugEnzoResponse() async {
    let context = AthleteContext.preview
    let question = "When was I at my peak fitness and what was I doing?"
    
    for await token in claudeService.stream(
        question: question, 
        context: context
    ) {
        print(token, terminator: "")
    }
}
```

The response must reference August 2025 and a fitness score of 100. If it gives generic advice not grounded in the hardcoded data, the context payload or system prompt is wrong — fix before proceeding.

---

## Acceptance Criteria by Step

Claude Code should not mark a step complete until these pass:

| Step | Test requirement |
|---|---|
| 5 (Supabase) | Can write a fitness snapshot and read it back |
| 6 (OAuth) | Access token stored in Keychain, athlete profile fetched |
| 7 (Sync Phase 1) | Fitness snapshots in Supabase match expected values from known activities |
| 8 (Arc live) | Enzo references real fitness data in response, not hardcoded preview |
| 9 (Segments) | At least one segment scores above 0.5, strike labels display correctly |