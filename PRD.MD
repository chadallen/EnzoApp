# Enzo — Product Spec

**Version:** 2.2 (pruned 2026-04-15 — implementation details removed, pointers to code added)
**Author:** Chad Allen

---

## 1. Product Vision

Enzo is a personal iOS cycling companion built around one question: *when should I go for that PR?* It synthesizes years of Strava segment history and fitness trends into an Enzo-narrated view of training — telling you which segments you're ready to target right now, and helping you build toward the ones you're not.

It is explicitly **not** a rigid training plan. It's an ongoing conversation. The app adapts when life happens. Missing a ride is not a failure state — it's just new information.

**The core experience:** Open the app before a ride, see your PR chances on the segments you'll encounter, ask Enzo about one.

> **Persona note:** Enzo is the user-facing name for the AI companion throughout the entire app. All UI copy, empty states, and error messages refer to "Enzo" — never "Claude", never "AI", never "assistant".

> **Scope note:** MVP is scoped to segment PR goals only. Event and race goals are deferred to v2.

---

## 2. Design Principles

1. **Goal-forward, not data-backward.** Everything is framed relative to where the user is going.
2. **Conversation, not dashboard.** Enzo speaks first. Numbers support the narrative.
3. **Flexible by design.** No streaks. No missed-workout alerts. No red states. The plan bends around life.
4. **Honest about limits.** Enzo is a training companion, not a certified coach.
5. **Relative fitness, not absolute.** You vs. your own history. No comparison to other athletes.
6. **Directionally true, not precisely predictive.** Fitness model needs to be motivating and honest about direction, not perfectly accurate.

---

## 3. Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| UI | SwiftUI | iOS 17+ features |
| Charts | Swift Charts | Native, no third-party |
| State | `@Observable` + `async/await` | No Combine |
| Networking | `URLSession` + `async/await` | No third-party HTTP library |
| Auth | Strava OAuth 2.0 | Tokens in iOS Keychain |
| Persistence | SwiftData (on-device SQLite) | No Supabase — derived metrics only |
| AI | Anthropic Claude API | `claude-sonnet-4-6`, streaming |

See `CLAUDE.md` for hard rules on each layer.

---

## 4. Data Architecture

### Core Principle

**Never store raw Strava data.** Compute in-memory, persist only derived output to SwiftData. Raw activity data is discarded after computation.

### Fitness Model

HR-based ride efficiency — more ground per heartbeat = fitter. Implemented in `Utils/FitnessCalculator.swift`.

**User-facing fitness labels** (from continuous 0.0–1.0 internal value):

| fitness_value | Label |
|---|---|
| > 0.85 | Epic |
| 0.65 – 0.85 | Strong |
| 0.45 – 0.65 | Building |
| 0.25 – 0.45 | Baseline |
| < 0.25 | Recovering |

Trend direction: rate of change over most recent 4 weeks vs prior 4 weeks. Threshold: ±0.008. See `FitnessCalculator.trendThreshold`.

### Segment Strike Score

Implemented in `Utils/SegmentScorer.swift`. Formula: `clamp(0.75 + fitnessDelta + prAgeBonus + effortGapModifier, 0, 1)`. At fitness parity → 0.75 ("Almost there").

**User-facing strike labels:**

| strike_score | Label |
|---|---|
| ≥ 0.80 | Strike now |
| 0.65 – 0.80 | Almost there |
| 0.45 – 0.65 | Worth a shot |
| 0.25 – 0.45 | Getting there |
| < 0.25 | Build first |

### SwiftData Models

Implemented in `EnzoApp/Models/SwiftDataModels.swift`. Three models:
- `FitnessSnapshotModel` — monthly fitness history, keyed on month Date
- `SegmentScoreModel` — segment PRs + strike scores, keyed on stravaSegmentId
- `GoalModel` — active/historical goals, one active at a time

---

## 5. Strava Integration

### OAuth Flow

ASWebAuthenticationSession → Strava OAuth → redirect to `enzo://oauth` → exchange code for tokens → store in Keychain. Implemented in `Services/StravaService.swift`.

Required scopes: `activity:read_all` (full history + HR), `read` (athlete profile).
Strava "Authorization Callback Domain" must be `oauth` (not `localhost`).

### Sync Strategy

**Phase 1** — Activity list + HR (fast, ~5 API calls):
1. Fetch all activities paginated at 200/page via `GET /athlete/activities`
2. Filter to cycling sport types; exclude rides < 30 min or without HR data
3. Compute monthly efficiency snapshots in-memory
4. Write to SwiftData; discard raw activity data

**Phase 2** — Segment effort extraction (background, 1 call per activity):
1. For each activity, fetch `GET /activities/{id}?include_all_efforts=true`
2. Extract segment efforts; use `pr_rank == 1` to identify PRs (`athlete_pr_effort` is not populated by the API)
3. Compute strike scores; write to SwiftData; discard raw data

**Rate limits:** 200 req/15 min, 2000/day. `phase2ActivityLimit = 25` — do not raise without Chad's instruction. Incremental sync: `lastPhase2SyncTimestamp` in UserDefaults.

**Ongoing sync:** Manual only for beta. Strava webhooks deferred to Step 12.

---

## 6. Claude API Integration

Implemented in `Services/ClaudeService.swift`. Streaming via `AsyncStream`. System prompt establishes the Enzo persona — see `ClaudeService.systemPrompt`.

**Current readiness labels in system prompt:** Strike now, Almost there, Worth a shot, Getting there, Build first. (Note: `skills/enzo-voice.MD` still has old labels — fix before Step 11b.)

**Segment chat flow:** User taps "Ask Enzo" on a segment → `AppState.segmentAssessmentPrompt()` generates the opening message → `AppState.sendSegmentMessage()` streams response with multi-turn history support. Chat is session-scoped (cleared on view disappear).

**Prompt playground:** `python3 scripts/enzo_playground.py` — use before editing prompts in code.

---

## 7. User Journeys

### Journey 1: First Launch

1. **Connect** — ConnectView: "Connect Strava" button → ASWebAuthenticationSession OAuth flow
2. **Sync** — SyncProgressView: phase labels cycle while Phase 1 + Phase 2 run. `hasCompletedOnboarding` set true on completion. No goal-setting gate.
3. **Segment list** — User lands directly on SegmentsView, sorted by strike score.

### Journey 2: Daily Use (Pre-ride)

1. Open app → SegmentsView shows segments sorted by opportunity. Goal segment starred at top.
2. Tap a segment → SegmentDetailView: stats card, readiness score + label, "Ask Enzo" button.
3. Tap "Ask Enzo" → Enzo's assessment streams in. Input bar appears for follow-ups.
4. Follow-up questions → multi-turn conversation, scoped to that segment.

### Journey 3: Setting a Goal

From SegmentDetailView: toggle "Set a target date" (optional), tap "Set this goal". Goal persists in SwiftData. Goal segment is starred in the list. Only one active goal at a time; previous goal is archived.

### Journey 4: Changing a Goal

Tap any non-goal segment's "Set this goal" button. Previous goal deactivated. No friction, no warning.

---

## 8. Navigation Structure

Single NavigationStack in `MainTabView`. No tabs.

```
MainTabView (NavigationStack)
└── SegmentsView (root)
    └── SegmentDetailView (push on row tap)

Settings via gear icon → SettingsSheet (modal)
```

---

## 9. UI Tone & Copy Rules

- Never "You failed" / "Missed workout" / red states for inactivity
- Use: "It's been a few days", "Pick it back up", "You're building"
- No label ever goes red — amber at most, always with a constructive Enzo line
- Enzo one-liners: direct, warm, specific to the athlete's actual data
- Never give advice that applies to anyone — always reference their labels, their history, their goal

---

## 10. Fitness Computation Detail

Implemented — see `Utils/FitnessCalculator.swift` and `Utils/SegmentScorer.swift`.

**Confirmed tuning constants:**
- Elevation multiplier: `0.01` (100m climbing ≈ 1km flat)
- Gravel surface bonus: `1.15`
- Minimum ride duration: `30 minutes`
- Trend threshold: `±0.008`
- Strike score base at fitness parity: `0.75`

---

## 11. Error States & Edge Cases

| Scenario | Handling |
|---|---|
| < 100 rides or < 1 year history | Show with note: "More rides = richer insights — check back as your history builds" |
| No HR data on activities | Ride excluded from efficiency calculation entirely |
| Rides under 30 minutes | Excluded from efficiency calculation entirely |
| Claude API timeout | "Couldn't reach Enzo — tap to retry." Never blank. |
| Strava rate limit during sync | Pause, show "Syncing in the background", auto-resume |
| Strava auth expires | Silent token refresh first. If fails: "Strava needs you to reconnect — takes 10 seconds." |
| Goal has no target date | Valid. Enzo focuses on fitness direction, not countdown. |
| No segment repeats for a segment | Strike score uses fitness value only. |
| User disconnects Strava | Delete all SwiftData rows, reset to onboarding. One confirmation dialog. |

---

## 12. What's Out of Scope (MVP)

- Social features
- Running (cycling only)
- Event / race goals (architecture supports it, deferred to v2)
- Day-by-day training schedules
- Missed workout tracking or streaks
- Push notifications (post-MVP)
- iPad, Apple Watch
- Export or sharing
- Power meter data (deliberately excluded for model consistency)

---

## 13. Secrets Management

Pattern: xcconfig → Info.plist → `Utils/Config.swift`. See `CLAUDE.md` for the hard rule. See `.claude/rules/build-notes.md` for the `//` URL escaping gotcha in xcconfig.

Secrets by type:
- Claude API key, Strava client ID/secret: xcconfig → Info.plist → Config.swift
- Strava user access/refresh tokens: iOS Keychain (`KeychainHelper.swift`)

---

## 14. Preview Data

All preview data lives in `.preview` / `.previewSegments` / `.previewSnapshots` static properties in the relevant model files (`AthleteContext.swift`, `FitnessSnapshot.swift`, `SegmentScore.swift`). The hardcoded values are derived from Chad's real Strava history and must not be changed arbitrarily.
