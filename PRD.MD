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

CTL/ATL/TSB Performance Management Chart. TSS computed per activity from power (when `device_watts == true`) with HR fallback using LTHR (95th percentile of avg HR across 20–90 min rides). CTL = 42-day EMA of daily TSS (fitness). ATL = 7-day EMA (fatigue). TSB = CTL_yesterday − ATL_yesterday (form/readiness). Implemented in `Utils/FitnessV2Calculator.swift` and `Utils/DailyFitnessBuilder.swift`.

**User-facing fitness labels** (used in Enzo conversation only — not shown as standalone UI):

| Label | Meaning |
|---|---|
| Epic | Peak CTL relative to athlete's history |
| Strong | High CTL, positive form |
| Building | CTL trending up |
| Baseline | Typical CTL for this athlete |
| Recovering | CTL below baseline or declining |

### Segment PR Probability

Per-segment OLS regression: `elapsed_time = β₀ + β₁·CTL + β₂·TSB`. Fit from athlete's own effort history via normal equations (`simd_double3x3`). Output: `P(PR) = Φ((prTime − ŷ) / σ)` — a 0–100% probability displayed directly in the UI. Implemented in `Utils/SegmentRegression.swift` and `Utils/PRPredictor.swift`.

**User-facing strike labels** (derived from PR probability):

| probability | Label |
|---|---|
| ≥ 0.80 | Strike now |
| 0.65 – 0.80 | Almost there |
| 0.45 – 0.65 | Worth a shot |
| 0.25 – 0.45 | Getting there |
| < 0.25 | Build first |

When a segment has insufficient effort history for a valid model, Enzo shows a plain-language fallback: "PR set when CTL was X. Your current CTL is Y."

### SwiftData Models

Implemented in `EnzoApp/Models/SwiftDataModels.swift`. Six models:
- `ActivityModel` — one Strava cycling activity, TSS computed on ingest
- `DailyFitnessModel` — CTL/ATL/TSB per calendar day (one row per day, no gaps)
- `StarredSegmentModel` — segments starred on Strava or ridden within 90 days
- `SegmentEffortModel` — one effort per segment ride, with CTL/TSB at effort time
- `SegmentFitnessModel` — per-segment OLS regression state (coefficients, σ, bounds)
- `GoalModel` — active/historical goals, one active at a time

---

## 5. Strava Integration

### OAuth Flow

ASWebAuthenticationSession → Strava OAuth → redirect to `enzo://oauth` → exchange code for tokens → store in Keychain. Implemented in `Services/StravaService.swift`.

Required scopes: `activity:read_all` (full history + HR), `read` (athlete profile).
Strava "Authorization Callback Domain" must be `oauth` (not `localhost`).

### Sync Strategy

**Phase 1** — Activity list + fitness timeline:
1. Fetch activities paginated at 100/page via `GET /athlete/activities` (3-year lookback, max 300 rides)
2. Filter to cycling sport types (Ride, VirtualRide, GravelRide, MountainBikeRide, EMountainBikeRide)
3. Compute TSS per activity (power if available, else HR); estimate LTHR from 95th percentile of qualifying rides
4. Build CTL/ATL/TSB timeline day-by-day; write to SwiftData; discard raw activity data

**Phase 2** — Segment effort fetch (per starred segment):
1. Fetch starred segments via `GET /segments/starred`
2. For each starred segment, fetch all efforts via `GET /segments/{id}/all_efforts` (3-year window)
3. Join efforts to fitness timeline (CTL/TSB on effort date − 1 day)
4. Fit OLS regression; write `SegmentFitnessModel` to SwiftData; discard raw effort data

**Rate limits:** 200 req/15 min, 2000/day. Incremental sync: `lastV2SyncDate` in UserDefaults.

**Ongoing sync:** Manual only for beta. Strava webhooks deferred to Step 12.

---

## 6. Claude API Integration

Implemented in `Services/ClaudeService.swift`. Streaming via `AsyncStream`. System prompt establishes the Enzo persona — see `ClaudeService.systemPrompt`.

**Current readiness labels in system prompt:** Strike now, Almost there, Worth a shot, Getting there, Build first. Fitness labels: Epic, Strong, Building, Baseline, Recovering. (Note: fitness labels in the system prompt are v1 holdovers — updating them to reflect CTL/TSB context is EnzoApp-55p.6.)

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

Single `NavigationStack` at the app root. No tabs.

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

Implemented — see `Utils/FitnessV2Calculator.swift`, `Utils/DailyFitnessBuilder.swift`, `Utils/SegmentRegression.swift`, `Utils/PRPredictor.swift`.

**Key constants:**
- CTL time constant: 42 days
- ATL time constant: 7 days
- LTHR estimation: 95th percentile of avg HR across 20–90 min rides (requires ≥10 qualifying rides)
- TSS cap: 400 per activity (above = sensor error)
- Extrapolation guard: warn when today's CTL/TSB is outside `[ctlMin × 0.9, ctlMax × 1.1]` or `[tsbMin − 20, tsbMax + 20]`
- Minimum efforts for valid regression: 1 (models with <3 efforts have σ = 0, deterministic result)

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
