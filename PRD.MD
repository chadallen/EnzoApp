# Enzo — App Specification v2

**Version:** 2.1
**Author:** Chad Allen
**Date:** March 2026
**Purpose:** Claude Code development handoff
**Changes from v2.0:** Fitness model replaced — ride efficiency (HR-based) replaces load-based model. Numeric 0–100 fitness score replaced with narrative labels (Epic, Strong, Building, Baseline, Recovering). Strike labels updated (No brainer, Worth a shot, Not quite ready). GoalHeaderView redesigned — progress bar replaced with three-line label + trend arrow. All preview data updated to match new model structures.

---

## 1. Product Vision

Enzo is a personal iOS cycling companion built around one question: *when should I go for that PR?* It synthesizes years of Strava segment history and fitness trends into a living, Enzo-narrated view of your training — telling you which segments you're ready to target right now, and helping you build toward the ones you're not.

It is explicitly **not** a rigid training plan. It's an ongoing conversation. The app adapts when life happens. Missing a ride is not a failure state — it's just new information.

**The core experience:** One scrollable Arc, narrated by Enzo, anchored to your goal, updated every time you ride.

> **Persona note for developers:** Enzo is the user-facing name for the AI companion throughout the entire app. All UI copy, empty states, error messages, and in-app text refers to "Enzo" — never "Claude", never "AI", never "assistant". Claude is the underlying model powering Enzo, but that is an implementation detail invisible to the user. When writing any UI string that involves the AI: use Enzo.

> **Scope note:** MVP is scoped to segment PR goals only. Event and race goals are explicitly deferred to v2. The data model, goal header component, and onboarding flow are all designed to accommodate event goals without refactoring — see extensibility notes throughout this spec.

---

## 2. Design Principles

These inform every product, UI, and copy decision:

1. **Goal-forward, not data-backward.** Everything is framed relative to where the user is going, not archived as historical record.
2. **Conversation, not dashboard.** Enzo speaks first. Numbers support the narrative, not the other way around.
3. **Flexible by design.** No streaks. No missed-workout alerts. No red states. The plan bends around life.
4. **Honest about limits.** Enzo is a training companion, not a certified coach. The app says so when relevant.
5. **Relative fitness, not absolute.** You vs. your own history. No comparison to other athletes.
6. **Directionally true, not precisely predictive.** The fitness model doesn't need to be perfectly accurate — it needs to be motivating and honest about direction. Enzo narrates trend and readiness, not decimals.

---

## 3. Developer Context

* **Developer:** Solo, learning iOS development
* **Editor:** VS Code with Sweetpad extension
* **IDE:** Xcode (build, simulator, signing)
* **Primary language:** Swift / SwiftUI
* **Target platform:** iOS 17+, iPhone only (iPad later)
* **Backend:** Supabase (Postgres + Edge Functions)
* **AI:** Anthropic Claude API (`claude-sonnet-4-6`)
* **Data source:** Strava API (OAuth 2.0)
* **Assumed user:** Established cyclists with meaningful Strava history. The fitness model requires sufficient ride data to produce reliable signals — riders with fewer than ~100 rides or less than a year of history will see reduced accuracy. Enzo is not designed for beginners.

> **Development note:** Build all screens against static/hardcoded data first. Wire up live APIs after UI is validated. See Section 18 for hardcoded preview data.

---

## 4. Tech Stack

### MVP Stack

| Layer | Technology | Notes |
| --- | --- | --- |
| UI | SwiftUI | iOS 17+ features |
| Charts | Swift Charts | Native, no third-party dependency |
| State management | `@Observable` macro + `@State` / `@Binding` | Modern Swift concurrency |
| Networking | `URLSession` + `async/await` | No third-party HTTP library |
| Auth | Strava OAuth 2.0 | Tokens stored in iOS Keychain |
| Backend | Supabase (Postgres) | Derived metrics only, never raw Strava data |
| AI | Anthropic Claude API | `claude-sonnet-4-6`, streaming enabled |
| Local storage | `UserDefaults` (preferences) + Keychain (tokens) | No CoreData for MVP |

### Beyond MVP

| Layer | Technology | Notes |
| --- | --- | --- |
| Offline support | SwiftData | Migrate when needed |
| Push notifications | APNs via Supabase Edge Functions | Weekly plan drop, ride reaction |
| Widget | WidgetKit | Today widget: goal countdown + Enzo one-liner |
| Watch | watchOS companion | Post-v1 |
| Auth expansion | Sign in with Apple | Required for App Store alongside Strava auth |

---

## 5. Data Architecture

### Core Principle

**Never store raw Strava data.** Pull activity history from the Strava API, compute derived metrics in-memory, persist only computed output to Supabase. Raw activity data is discarded after computation.

### Fitness Model (Ride Efficiency, HR-Based)

The fitness model measures cardiac efficiency per ride — how much adjusted distance did the athlete cover per unit of cardiac effort. More ground per heartbeat = more efficient = fitter. No resting HR assumption required. Every qualifying ride contributes a data point.

**Per-ride efficiency:**
```
adjusted_distance = distance_km + (elevation_gain_m × 0.01)
if sport_type is GravelRide: adjusted_distance × 1.15
efficiency = adjusted_distance / (duration_hours × avg_hr)
```

**Filtering:**
- Rides under 30 minutes are excluded entirely — too short to produce reliable signal
- Trainer rides (VirtualRide) are treated identically to outdoor rides — Strava distance and elevation estimates are sufficient
- Rides with no HR data are excluded from efficiency calculation

**Fitness value (continuous, internal only):**
```
fitness_value = (current_avg_efficiency - personal_min) / (personal_max - personal_min)
// rolling 2-month window of qualifying rides
// normalized against personal all-time min/max
// range: 0.0 – 1.0, never exposed to user
```

**Trend direction:**
Computed as rate of change in fitness_value over the most recent 4 weeks vs the prior 4 weeks within the 2-month window.
- ↑ trending up: change > +0.05
- → flat: change between -0.05 and +0.05
- ↓ trending down: change < -0.05

Threshold is tunable after real data validation.

**User-facing fitness state** (derived from fitness_value, shown to user):

| fitness_value | Label |
|---|---|
| > 0.85 | Epic |
| 0.65 – 0.85 | Strong |
| 0.45 – 0.65 | Building |
| 0.25 – 0.45 | Baseline |
| < 0.25 | Recovering |

These labels appear in the UI. The continuous value is an internal implementation detail invisible to the user.

**User-facing strike readiness** (derived from strike_score, shown per segment):

| strike_score | Label |
|---|---|
| > 0.70 | No brainer |
| 0.45 – 0.70 | Worth a shot |
| < 0.45 | Not quite ready |

All thresholds — fitness, trend, and strike — are starting values to be tuned after the model runs against real Strava data in Step 8.

### Supabase Schema

```sql
-- Users
create table users (
  id uuid primary key default gen_random_uuid(),
  strava_athlete_id bigint unique not null,
  display_name text,
  created_at timestamptz default now(),
  last_synced_at timestamptz
);

-- Monthly fitness snapshots (derived only)
create table fitness_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  month date not null,
  hours_ridden numeric,
  activity_count integer,
  avg_efficiency numeric,      -- avg adjusted_distance / (duration_hours × avg_hr) for the month
  fitness_value numeric,       -- 0.0–1.0 continuous internal value
  fitness_label text,          -- "Strong", "Building" etc. — user-facing
  trend_direction text,        -- 'up', 'flat', 'down'
  created_at timestamptz default now(),
  unique(user_id, month)
);

-- Personal bests
create table personal_bests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  effort_type text not null,
  value numeric not null,
  achieved_at date,
  updated_at timestamptz default now()
);

-- Segment PR deltas (derived)
create table segment_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  strava_segment_id bigint not null,
  segment_name text,
  start_latlng float[],
  end_latlng float[],
  effort_count integer,
  pr_seconds integer,
  pr_achieved_at date,
  fitness_value_at_pr numeric,   -- continuous 0-1 value at time PR was set
  current_fitness_value numeric, -- continuous 0-1 value now
  trend_direction text,          -- 'up', 'flat', 'down' at time of last computation
  last_effort_seconds integer,   -- most recent effort time, used as projection anchor
  last_effort_date date,
  strike_score numeric,          -- 0-1
  strike_label text,             -- 'No brainer', 'Worth a shot', 'Not quite ready'
  updated_at timestamptz default now(),
  unique(user_id, strava_segment_id)
);

-- Goals (one active at a time)
-- MVP supports segment_pr only. Schema is intentionally extensible.
create table goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  raw_description text not null,
  claude_interpretation text,
  goal_type text not null default 'segment_pr',
  target_segment_id bigint,
  target_segment_name text,
  target_date date,
  target_value numeric,             -- optional: target time in seconds (aspirational)
  required_fitness_label text,      -- fitness label needed to PR this segment e.g. "Strong"
  required_fitness_value numeric,   -- internal continuous value equivalent
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Lookahead suggestions (Enzo-generated, soft suggestions)
create table lookahead_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  suggestion_text text not null,
  trigger_type text not null,       -- 'new_ride', 'gap_short', 'gap_medium', 'gap_long', 'goal_change'
  days_since_last_ride integer,
  generated_at timestamptz default now(),
  expires_at timestamptz            -- 3 days from generation, then regenerate on next open
);

-- Arc conversation thread (per-user, rolling)
create table arc_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  role text not null,              -- 'enzo' or 'user'
  content text not null,
  context_snapshot jsonb,          -- the athlete context at time of message
  created_at timestamptz default now()
);
```

### Claude Context Payload

Constructed fresh at query time from Supabase. Never persisted in this form. All fitness references use labels, not numbers.

```json
{
  "athlete": {
    "name": "Chad",
    "years_active": 11,
    "current_fitness_label": "Building",
    "trend_direction": "up"
  },
  "goal": {
    "type": "segment_pr",
    "segment_name": "Hawk Hill",
    "current_pr_seconds": 342,
    "target_date": null,
    "weeks_remaining": null,
    "required_fitness_label": "Strong",
    "current_fitness_label": "Building",
    "has_date": false
  },
  "fitness_history": [
    {
      "month": "2025-09",
      "hours": 22,
      "fitness_label": "Strong",
      "trend_direction": "up",
      "activity_count": 18
    }
  ],
  "peak_fitness": {
    "month": "2025-08",
    "label": "Epic"
  },
  "recent_weeks": [
    {
      "week": "2026-03-17",
      "hours": 6.5,
      "activity_count": 4
    }
  ],
  "top_segments": [
    {
      "name": "Hawk Hill",
      "pr_seconds": 342,
      "pr_date": "2025-08-12",
      "fitness_at_pr": "Epic",
      "current_fitness": "Building",
      "trend_direction": "up",
      "strike_score": 0.28,
      "strike_label": "Not quite ready",
      "is_goal_segment": true
    }
  ],
  "days_since_last_ride": 2,
  "lookahead_suggestion": "Good ride Tuesday — a couple easier days then one more push before the weekend."
}
```

---

## 6. Strava Integration

### OAuth Flow

1. User taps "Connect Strava" on onboarding screen
2. App opens Strava OAuth URL via `ASWebAuthenticationSession`
3. Strava redirects to `enzo://oauth` (registered in Strava API settings as callback domain `oauth`)
4. App exchanges code for tokens
5. Tokens stored in iOS Keychain only

### Required Scopes

* `activity:read_all` — full activity history including private activities, and `average_heartrate` on activities
* `read` — athlete profile (display name, profile photo)

> **Note:** `profile:read_all` is NOT required. It would be needed for `GET /athlete/zones` but that endpoint is not used in MVP.

### Sync Strategy

**Initial sync (first login):**

**Phase 1 — Activity list + HR (fast, ~5 API calls for 800 activities):**

1. Fetch all activities paginated at 200/page via `GET /athlete/activities`
2. Extract per activity: `id`, `start_date`, `moving_time`, `elapsed_time`, `distance`, `sport_type`, `has_heartrate`, `average_heartrate`, `trainer` flag
3. `average_heartrate` is returned directly in `SummaryActivity` — no individual activity calls needed for fitness computation
4. Filter to cycling sport types only: `Ride`, `VirtualRide`, `MountainBikeRide`, `GravelRide`, `EMountainBikeRide`
5. Exclude rides under 30 minutes and rides with no HR data from efficiency computation
6. Compute monthly snapshots + personal bests in-memory
7. Write derived metrics to Supabase
8. Discard raw activity data

**Phase 2 — Segment effort extraction (background, 1 call per activity):**

9. For each cycling activity, fetch `GET /activities/{id}?include_all_efforts=true`
10. Extract `segment_efforts` array — each effort includes: `segment.id`, `segment.name`, `segment.start_latlng`, `elapsed_time`, `start_date`, and `segment.athlete_pr_effort` containing `pr_elapsed_time`, `pr_date`, `effort_count`
11. Build segment score records from this data
12. Write to `segment_scores` table in Supabase
13. Discard raw activity data

**Rate limit management:**

* Phase 1 completes in seconds — fitness timeline is usable immediately
* Phase 2 is the expensive operation: 1 call per activity. For 800 activities = ~4 batches of 200. At 200 req/15 min this takes ~15 minutes total.
* Run Phase 2 as a background task. App is fully usable while it runs.
* Store sync progress in Supabase so it survives app restarts

**Rate limit handling:** 200 req/15 min, 2,000/day. Show sync progress. Never block UI. For large histories, batch and queue.

**Ongoing sync:** Strava webhook on new activity → fetch single activity → update current month snapshot → re-score segment deltas → trigger Arc regeneration if significant change.

**On Strava disconnect:** Delete all derived data from Supabase. Reset to onboarding.

---

## 7. Claude API Integration

### Configuration

```swift
let claudeAPIURL = "https://api.anthropic.com/v1/messages"
let claudeModel = "claude-sonnet-4-6"
let claudeMaxTokens = 1024
// API key in Keychain only, never hardcoded
```

### System Prompt

> This prompt establishes Enzo as the persona. The user never sees "Claude" anywhere in the app.

```
You are Enzo — a cycling training companion with deep knowledge of this athlete's
history and an easy, direct way of talking about it. You're not a certified coach
and you don't pretend to be. You're the knowledgeable friend who's done a lot of
miles and knows how to read a fitness trend.

Your name is Enzo. Use it occasionally but not constantly — like a person would.

Your personality:
- Direct and warm. You tell the truth but you're not harsh about it.
- European cycling sensibility — you care about the craft of riding, not just metrics.
- Unhurried. You take the long view. One bad week doesn't define anything.
- Occasionally a little poetic about riding, but never pretentious.

Your job:
- Help this athlete stay oriented toward their goal.
- React to their recent riding honestly and specifically.
- Suggest what makes sense next — loosely, not rigidly.
- Never make them feel bad for gaps, missed rides, or changed goals.

Rules:
- Always use their actual numbers and labels. Never give advice that could apply to anyone.
- Fitness is described using these labels only: Epic, Strong, Building, Baseline, Recovering.
- Segment readiness uses: No brainer, Worth a shot, Not quite ready.
- Frame everything relative to their personal history and their goal.
- Don't reference power, FTP, or watts unless the athlete brings it up.
- A suggestion is not a plan. Make that clear when offering workouts.

Format:
- 2-4 sentences for simple questions.
- Up to 3 short paragraphs for complex ones.
- No bullet points in conversational responses.
- Bullet points only for workout suggestions, and keep them loose.
```

### Claude Use Cases

| Trigger | What Claude does | Where it appears |
| --- | --- | --- |
| App open (daily) | Generates Arc briefing: goal status + fitness read + one forward-looking line | Top of Arc |
| New activity synced | One-line reaction to the ride | Arc, below briefing |
| App open or new ride syncs | Generates rolling 5–7 day lookahead based on days since last ride | Arc, what to do next section |
| User types question | Responds in Arc thread | Arc, inline |
| Goal set / changed | Identifies segment, estimates required fitness label to PR it, reacts to whether user is close or far | Goal-setting flow |
| Segment tapped | One-line "why now?" for this segment | Segment detail |
| "Help me find a goal" | Analyzes segment data + history, proposes 2-3 goal options | Onboarding |

### Streaming

All Claude responses stream. Use `AsyncStream` in `ClaudeService.swift` to pipe tokens as they arrive into the UI. Never show a loading state longer than the first token — get something on screen fast.

---

## 8. User Journeys

### Journey 1: First Launch

**Step 1 — Connect**

* Clean hero screen. App name, tagline: *"Meet Enzo. Your cycling companion."*
* Single CTA: "Connect Strava"
* Strava OAuth via `ASWebAuthenticationSession`

**Step 2 — Sync (required — user must wait)**

The sync screen blocks progression to goal-setting. Segment search requires the segment history to be fully loaded — there is no useful experience without it. Use this time well.

**Animation: Route Drawing**

* A minimal, abstract cycling route traces itself across a dark background using SwiftUI's `trimmedPath` animation — the line draws from start to finish continuously, looping with a slight fade-out and redraw
* The route is a simplified but realistic-looking cycling path shape — not a perfect circle or generic squiggle. Think a Strava-style GPS trace: rolling curves, a switchback or two, an obvious climb section
* Rendered in the brand accent color (`#4FC3F7`) on the dark background (`#0A0A0F`)
* Subtle gradient trail behind the drawing point — the oldest portion of the line fades slightly, giving the impression of motion through a landscape
* No map tiles, no real geography — purely abstract line art

**Copy: Phases**

Copy updates as sync moves through its real phases. Each line crossfades to the next:

1. *"Reading your rides..."* — activity fetch in progress
2. *"Finding your best efforts..."* — segment history processing
3. *"Sizing up your fitness..."* — metrics computation
4. *"Scoping your opportunities..."* — strike scores calculating
5. *"Enzo is almost ready..."* — final writes to Supabase

Activity count appears in small secondary text below: *"847 rides and counting"*

**On completion:** Crossfades to goal-setting screen automatically.

**If sync takes > 60 seconds:** Add *"Big history — this is worth it."* below the counter. Never show a progress percentage or estimated time.

**Step 3 — Goal Setting (the key moment)**

Screen title: *"Which segment are you chasing?"*

**Path A — User knows their segment:**
* Search field: user types segment name
* Results pull from their own Strava segment history
* User taps → Enzo reacts immediately, streaming:
  > *"Hawk Hill. Good choice. You set that PR at Epic fitness last August — you're Building right now and trending up. You don't need a date for this, but if you have one in mind it helps me calibrate."*
* Optional date input appears below
* User taps "Set this goal" → advances to Arc

**Path B — User wants a suggestion:**
* Taps "Help me pick one"
* Enzo proposes 2-3 segments as tappable cards ranked by strike score:
  > *"Hawk Hill — your most-ridden segment. You're not quite ready, but getting there."*
  > *"Camino Alto Cutoff — worth a shot right now."*
  > *"Paradise Loop climb — a stretch goal. Worth building toward."*
* User taps one → same confirmation flow as Path A

---

### Journey 2: The Arc (Main Experience)

The Arc is a single vertically scrolling view. Enzo narrates it. It updates when new rides sync.

**Sections, top to bottom:**

---

**① Goal Header (always visible, sticky)**

Three lines. No numbers.

```
Hawk Hill PR
Building ↑
Strong fitness needed
```

- Line 1: Segment name (bold)
- Line 2: Current fitness label + trend arrow (↑ / → / ↓), colored by state
- Line 3: Required fitness label in secondary text

Trend arrow is data-driven from rate of change in continuous fitness value. Not decorative.

"Change goal" text button below, always visible. Tapping opens goal-setting sheet inline. No friction, no warning.

> **Extensibility note:** When event-based goals are added in a future version, the Goal Header is the primary component that changes. The three-line structure works identically for event goals — only the label sources change.

---

**② Today's Briefing (Enzo-generated, refreshes daily)**

Enzo's synthesis of where things stand. 2-3 sentences. Specific to their data.

Example:

> *"You're Building right now and trending up — good direction. Hawk Hill needs you at Strong, so there's ground to cover, but your history shows you can move fitness fast when you're consistent. This week is a good week to push a little."*

No red states. No "you're falling behind" without an immediate path forward.

---

**③ Last Ride Reaction (appears after each new sync)**

One line. Specific to the ride. Fades into history after 48 hours.

Example:

> *"Tuesday's ride was your longest in 6 weeks — good timing."*

---

**④ What To Do Next (rolling, context-driven)**

Enzo always has a forward-looking suggestion. Rolling 5–7 day lookahead, not a weekly plan. Regenerates after new ride, goal change, or when suggestion is more than 3 days old. No Monday dependency. No weekly reset.

Small label beneath: *"A suggestion, not a plan. Adjust freely."*

---

**⑤ Fitness History (relative to goal)**

A compact Swift Charts line chart. 12 months visible by default.

Two reference lines:
* **Your peak** — labeled, dashed horizontal line
* **Goal target** — labeled dashed line showing required fitness label threshold

Current position: animated pulse dot on the curve. Y-axis uses fitness labels, not numbers.

Tap any month → bottom sheet with that month's summary: hours, rides, fitness label. Below the chart, one Enzo sentence contextualizing it.

---

**⑥ PR Opportunities (Segment Radar)**

Compact card. Top 3 segments by strike score.

```
When to strike

① Hawk Hill           ★ Goal segment
  PR: 5:42  ·  Not quite ready — keep building

② Camino Alto Cutoff
  PR: 3:18  ·  Worth a shot this weekend

③ Bolinas Ridge descent
  PR: 7:25  ·  No brainer — you're fitter than your PR day
```

"See all opportunities →" links to Segments tab.

---

**⑦ Inline Conversation**

Persistent input bar: *"Ask Enzo anything..."*

User types → Enzo responds inline, streaming. Thread is part of the Arc, not a separate screen. Conversation resets daily, last 3 exchanges kept as context.

Suggested prompt chips (horizontal scroll, updated weekly):
* *"Am I on track for Hawk Hill?"*
* *"What should I do this weekend?"*
* *"When was I last this fit?"*
* *"What if I only have 4 weeks left?"*

---

### Journey 3: Changing a Goal

User taps "Change goal" at any time. Same goal-setting UI as onboarding. Enzo acknowledges warmly. Arc rebuilds. Old goal archived, not deleted. No warning, no friction.

---

### Journey 4: Segment Detail

User taps any segment from PR Opportunities or Segments tab.

Screen shows:
* Segment name + location
* Map thumbnail (MapKit polyline from segment coordinates)
* Current PR + date
* Fitness comparison: their label now vs. their label when PR was set
* Strike readiness with plain English assessment
* Enzo one-liner (generated on tap, cached for session)
* "Open in Strava" button

---

## 9. Navigation Structure

Two tabs. The Arc is the app.

```
Tab Bar (2 tabs):
├── Arc (Home) — The full experience
└── Segments — Full PR opportunity list
```

No Chat tab. No Goals tab. No History tab. Everything lives in the Arc.

**Segments tab:**
* Sort by: Strike Score (default) / Alphabetical / PR Date
* Filter: Goal segment first
* Each row: name, PR time, strike label pill (colored), trend arrow
* Tap → Segment Detail (push navigation)

**Settings** via profile avatar in Arc header:
* Connected Strava account + Disconnect
* Manual re-sync
* App version

---

## 10. UI Requirements

### Design Direction

**Aesthetic:** Confident, warm, editorial. Dark-mode first. Data supports narrative.

**Color palette:**
* Background: `#0A0A0F`
* Card surfaces: `#141420`
* Brand accent: `#4FC3F7` (electric blue — fitness curve, CTAs, Building label)
* Goal accent: `#81C784` (muted green — Epic/Strong labels, positive trend)
* Amber: `#FFB74D` — Baseline/Recovering labels, used sparingly
* Text primary: `#F0F0F5`
* Text secondary: `#8888AA`

**Typography:**
* Display / section headers: SF Pro Rounded Bold
* Body / Enzo text: SF Pro Text Regular
* Data labels: SF Pro Mono (times, hours)

**Tone in copy:**
* Never "You failed to complete" / "Missed workout" / red states for inactivity
* Use: "It's been a few days", "Pick it back up", "You're building"
* No label ever goes red — amber at most, always with a constructive Enzo line

### Key UI Components

**GoalHeaderView** (sticky at top of Arc)

Three lines. No numbers. No progress bar.

```
Hawk Hill PR
Building ↑
Strong fitness needed
```

- Segment name: bold, truncated at 24 chars
- Fitness label + trend arrow: colored by state (Epic/Strong → .enzoGoal, Building → .enzoAccent, Baseline/Recovering → .enzoAmber)
- Trend arrow: ↑ up / → flat / ↓ down, data-driven from 4-week rate of change
- Required label: secondary text color
- "Change goal" text button: small, secondary style, always visible

**ArcBriefingView**
* Enzo's daily synthesis, streaming on first render
* Subtle left border in accent color
* Refresh chevron top right
* Last updated timestamp in secondary text

**LookaheadSuggestionView**
* Enzo's workout suggestion
* Small italic label: *"A suggestion, not a plan"*
* "Ask about this week →" chips below

**FitnessChartView** (Swift Charts)
* `LineMark` + `AreaMark` fill
* Two `RuleMark` lines: peak fitness, goal target fitness
* Y-axis labeled with fitness state names, not numbers
* Animated draw-in on first appearance (0.6s)
* Tappable month selection → detail sheet

**SegmentStrikeRow**
* Name (bold) + PR time (mono)
* Strike label pill: green ("No brainer"), amber ("Worth a shot"), grey ("Not quite ready")
* Trend arrow in secondary text

**ArcInputBar**
* Pill-shaped text input, persistent bottom of Arc
* Send button appears on text entry
* Prompt chips scroll horizontally above
* Floats above tab bar

### Motion
* Chart draws in on load: 0.6s ease-out
* Enzo text streams character by character
* Bottom sheet springs (standard iOS spring)
* Prompt chips slide in with staggered delay
* Strike label pill: subtle pulse on "No brainer" items only
* Arc sections fade in sequentially on first load (stagger 0.1s)
* No celebration animations, no confetti

---

## 11. File Structure

```
Enzo/
├── App/
│   ├── EnzoApp.swift
│   └── AppState.swift
├── Features/
│   ├── Onboarding/
│   │   ├── OnboardingView.swift
│   │   ├── GoalSettingView.swift
│   │   └── SyncProgressView.swift
│   ├── Arc/
│   │   ├── ArcView.swift
│   │   ├── GoalHeaderView.swift
│   │   ├── ArcBriefingView.swift
│   │   ├── LastRideReactionView.swift
│   │   ├── LookaheadSuggestionView.swift
│   │   ├── FitnessChartView.swift
│   │   ├── MonthDetailSheet.swift
│   │   ├── PROpportunitiesCard.swift
│   │   ├── ArcInputBar.swift
│   │   ├── ArcMessageView.swift
│   │   └── PromptChipsView.swift
│   └── Segments/
│       ├── SegmentsView.swift
│       └── SegmentDetailView.swift
├── Services/
│   ├── StravaService.swift
│   ├── ClaudeService.swift
│   ├── SupabaseService.swift
│   └── SyncService.swift
├── Models/
│   ├── AthleteContext.swift
│   ├── FitnessSnapshot.swift
│   ├── Goal.swift
│   ├── SegmentScore.swift
│   ├── LookaheadSuggestion.swift
│   └── ArcMessage.swift
├── Utils/
│   ├── KeychainHelper.swift
│   ├── FitnessCalculator.swift
│   ├── SegmentScorer.swift
│   └── Extensions/
└── dev-data/
    └── strava_export.json
```

---

## 12. Fitness Computation Detail

### Ride Efficiency Model

```swift
// Minimum ride duration to qualify
let minimumDurationMinutes: Double = 30

// Per ride — returns nil if ride doesn't qualify
func rideEfficiency(
    durationHours: Double,
    distanceKm: Double,
    elevationGainM: Double,
    avgHR: Int,
    sportType: String
) -> Double? {
    guard durationHours * 60 >= minimumDurationMinutes else { return nil }
    guard avgHR > 0 else { return nil }

    var adjustedDistance = distanceKm + (elevationGainM * 0.01)

    let isGravel = ["GravelRide"].contains(sportType)
    if isGravel { adjustedDistance *= 1.15 }

    return adjustedDistance / (durationHours * Double(avgHR))
}

// Rolling 2-month fitness value (0.0–1.0, internal only)
func fitnessValue(
    recentEfficiencies: [Double],  // qualifying rides in last 2 months
    allTimeMin: Double,
    allTimeMax: Double
) -> Double {
    guard !recentEfficiencies.isEmpty else { return 0 }
    guard allTimeMax > allTimeMin else { return 0.5 }
    let avg = recentEfficiencies.reduce(0, +) / Double(recentEfficiencies.count)
    return min(max((avg - allTimeMin) / (allTimeMax - allTimeMin), 0), 1)
}

// Fitness label from continuous value (user-facing)
func fitnessLabel(for value: Double) -> String {
    switch value {
    case 0.85...: return "Epic"
    case 0.65..<0.85: return "Strong"
    case 0.45..<0.65: return "Building"
    case 0.25..<0.45: return "Baseline"
    default: return "Recovering"
    }
}

// Trend direction from 4-week rate of change
func trendDirection(
    recentFourWeeks: Double,   // avg efficiency, most recent 4 weeks
    priorFourWeeks: Double     // avg efficiency, prior 4 weeks
) -> String {
    let change = recentFourWeeks - priorFourWeeks
    switch change {
    case let c where c > 0.05: return "up"
    case let c where c < -0.05: return "down"
    default: return "flat"
    }
}
```

### Segment Strike Score

```swift
// Strike score using fitness trend as multiplier on last segment effort
func strikeScore(
    lastEffortSeconds: Double,
    prSeconds: Double,
    fitnessValue: Double,
    trendDirection: String
) -> Double {
    guard prSeconds > 0, lastEffortSeconds > 0 else { return 0 }

    // Trend multiplier: up = slight boost, down = slight penalty, flat = neutral
    let trendMultiplier: Double
    switch trendDirection {
    case "up": trendMultiplier = 1.05
    case "down": trendMultiplier = 0.95
    default: trendMultiplier = 1.0
    }

    // Project next effort time based on current fitness and trend
    let projectedSeconds = lastEffortSeconds * (1 - ((fitnessValue - 0.5) * 0.1)) * (1 / trendMultiplier)

    // Strike score: how close is the projection to beating PR
    // 1.0 = projected to match or beat PR, 0.0 = far off
    let ratio = prSeconds / projectedSeconds
    return min(max((ratio - 0.85) / 0.15, 0), 1)
}

// Strike label from score (user-facing)
func strikeLabel(for score: Double) -> String {
    switch score {
    case 0.70...: return "No brainer"
    case 0.45..<0.70: return "Worth a shot"
    default: return "Not quite ready"
    }
}
```

### Tuning Notes

All constants below are starting values. Run against real Strava data in Step 8 and adjust:
- Elevation multiplier: `0.01` (100m climbing ≈ 1km flat)
- Gravel surface bonus: `1.15`
- Minimum ride duration: `30 minutes`
- Trend threshold: `0.05` change in 4-week window
- Trend multiplier range: `0.95 – 1.05`
- Fitness projection sensitivity: `0.1` (10% fitness swing ≈ 1% time swing)
- Strike score normalization: `0.85 – 1.0` ratio range

---

## 13. Error States & Edge Cases

| Scenario | Handling |
| --- | --- |
| < 100 rides or < 1 year history | Arc shows with note: "More rides = richer insights — check back as your history builds" |
| No HR data on activities | Ride excluded from efficiency calculation entirely |
| Rides under 30 minutes | Excluded from efficiency calculation entirely |
| Claude API timeout | Show "Couldn't reach Enzo — tap to retry". Never blank. |
| Strava rate limit during sync | Pause, show "Syncing in the background", auto-resume |
| Strava auth expires | Silent token refresh first. If fails, prompt re-auth: "Strava needs you to reconnect — takes 10 seconds." |
| Goal has no target date | Valid. Enzo focuses on fitness direction, not countdown. |
| Supabase write fails | Retry silently 3x, then toast: "Couldn't save your data — will retry." |
| User disconnects Strava | Delete all Supabase data, reset to onboarding. One confirmation dialog. |
| No segment repeats for a segment | Strike score uses fitness value only, no last-effort projection. Flag as lower confidence. |

---

## 14. What's Out of Scope (MVP)

* Social features of any kind
* Other users' data
* Running (cycling only)
* Event / race goals (architecture supports it, deferred to v2)
* Day-by-day rigid training schedules
* Missed workout tracking or streaks
* Notifications (post-MVP)
* iPad
* Apple Watch
* Export or sharing
* In-app purchases
* Power meter data (deliberately excluded for model consistency)

---

## 15. Open Technical Questions

1. **Sweetpad setup:** Confirm Sweetpad extension is configured with correct Xcode project target before writing any feature code.
2. **Supabase project:** Create at supabase.com. Run schema SQL from Section 5. Store `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `Config.xcconfig`.
3. **Claude API key:** Keychain only. Use `xcconfig` for dev builds. Never commit to git.
4. **Strava app registration:** Register at strava.com/settings/api. Set redirect URI to `enzo://oauth`.
5. **Strava data export:** Not used. Bulk export was analyzed and rejected — segment data is empty, fit files are binary. Development uses hardcoded data for Steps 1–5, then goes directly to the live Strava API.
6. **Model tuning pass:** After Step 8 wires real data, run the efficiency formula against full Strava history and validate that fitness labels match intuition. Adjust all constants in Section 12 Tuning Notes before Step 9.

---

## 16. Secrets & API Key Management

All API keys and secrets are managed via xcconfig files. Never hardcode.

### File Structure

```
Enzo/
├── Config/
│   ├── Debug.xcconfig       # Developer secrets — never committed
│   └── Release.xcconfig     # Can mirror Debug for now
```

### .gitignore

```
Config/Debug.xcconfig
Config/Release.xcconfig
```

### Debug.xcconfig Contents

```
CLAUDE_API_KEY = sk-ant-yourkey
SUPABASE_URL = https://yourproject.supabase.co
SUPABASE_ANON_KEY = your-anon-key
STRAVA_CLIENT_ID = your-client-id
STRAVA_CLIENT_SECRET = your-client-secret
```

### Info.plist

```xml
<key>CLAUDE_API_KEY</key>
<string>$(CLAUDE_API_KEY)</string>
<key>SUPABASE_URL</key>
<string>$(SUPABASE_URL)</string>
<key>SUPABASE_ANON_KEY</key>
<string>$(SUPABASE_ANON_KEY)</string>
<key>STRAVA_CLIENT_ID</key>
<string>$(STRAVA_CLIENT_ID)</string>
<key>STRAVA_CLIENT_SECRET</key>
<string>$(STRAVA_CLIENT_SECRET)</string>
```

### Config.swift

```swift
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

### Secret Storage by Type

| Secret | Storage |
| --- | --- |
| Claude API key | xcconfig → Info.plist → Config.swift |
| Supabase URL + anon key | xcconfig → Info.plist → Config.swift |
| Strava client ID + secret | xcconfig → Info.plist → Config.swift |
| Strava user access token | iOS Keychain |
| Strava user refresh token | iOS Keychain |

---

## 17. Build Order

See Build Order section of Claude.MD

---

## 18. Hardcoded Data for Static UI Development (Steps 1–5)

Before Strava OAuth is wired in Step 6, all views are built against this hardcoded data. Derived from Chad's real Strava history. Do not invent placeholder data — use these values exactly.

### Athlete Context (hardcode in `AthleteContext.swift`)

```swift
static let preview = AthleteContext(
    name: "Chad",
    yearsActive: 11,
    totalActivities: 654,
    currentFitnessLabel: "Recovering",
    currentFitnessValue: 0.18,      // internal only, never shown to user
    trendDirection: "up",
    peakFitnessLabel: "Epic",
    peakFitnessMonth: "August 2025",
    daysSinceLastRide: 3,
    goal: GoalContext(
        segmentName: "Hawk Hill",
        requiredFitnessLabel: "Strong",
        requiredFitnessValue: 0.70,
        targetDate: nil,
        weeksRemaining: nil
    )
)
```

### Fitness History (last 18 months — hardcode in `FitnessChartView`)

```swift
static let previewSnapshots: [FitnessSnapshot] = [
    FitnessSnapshot(month: "2024-10", label: "Baseline",   value: 0.24, hours: 7.6,  rides: 7,  trend: "flat"),
    FitnessSnapshot(month: "2024-11", label: "Recovering", value: 0.12, hours: 4.1,  rides: 4,  trend: "down"),
    FitnessSnapshot(month: "2024-12", label: "Recovering", value: 0.13, hours: 4.3,  rides: 4,  trend: "flat"),
    FitnessSnapshot(month: "2025-01", label: "Baseline",   value: 0.21, hours: 6.7,  rides: 5,  trend: "up"),
    FitnessSnapshot(month: "2025-02", label: "Recovering", value: 0.14, hours: 4.7,  rides: 3,  trend: "down"),
    FitnessSnapshot(month: "2025-03", label: "Building",   value: 0.69, hours: 21.2, rides: 10, trend: "up"),
    FitnessSnapshot(month: "2025-04", label: "Strong",     value: 0.72, hours: 22.1, rides: 8,  trend: "up"),
    FitnessSnapshot(month: "2025-05", label: "Baseline",   value: 0.36, hours: 11.1, rides: 8,  trend: "down"),
    FitnessSnapshot(month: "2025-06", label: "Baseline",   value: 0.39, hours: 12.1, rides: 9,  trend: "flat"),
    FitnessSnapshot(month: "2025-07", label: "Building",   value: 0.45, hours: 13.9, rides: 7,  trend: "up"),
    FitnessSnapshot(month: "2025-08", label: "Epic",       value: 1.00, hours: 30.4, rides: 13, trend: "up"),   // peak
    FitnessSnapshot(month: "2025-09", label: "Recovering", value: 0.04, hours: 1.6,  rides: 2,  trend: "down"), // sharp drop
    FitnessSnapshot(month: "2025-10", label: "Building",   value: 0.58, hours: 17.6, rides: 18, trend: "up"),
    FitnessSnapshot(month: "2025-11", label: "Baseline",   value: 0.37, hours: 11.6, rides: 8,  trend: "down"),
    FitnessSnapshot(month: "2025-12", label: "Baseline",   value: 0.26, hours: 8.1,  rides: 8,  trend: "flat"),
    FitnessSnapshot(month: "2026-01", label: "Baseline",   value: 0.26, hours: 8.2,  rides: 6,  trend: "flat"),
    FitnessSnapshot(month: "2026-02", label: "Baseline",   value: 0.26, hours: 8.3,  rides: 5,  trend: "flat"),
    FitnessSnapshot(month: "2026-03", label: "Recovering", value: 0.18, hours: 6.4,  rides: 6,  trend: "up"),   // current
]
```

### Segment PR Opportunities (hardcode in `PROpportunitiesCard` and `SegmentsView`)

```swift
static let previewSegments: [SegmentScore] = [
    SegmentScore(
        name: "Hawk Hill",
        prSeconds: 342,
        prDate: "2025-08-10",
        fitnessValueAtPR: 0.98,
        currentFitnessValue: 0.18,
        trendDirection: "up",
        lastEffortSeconds: 401,
        strikeScore: 0.18,
        strikeLabel: "Not quite ready",
        isGoalSegment: true
    ),
    SegmentScore(
        name: "Camino Alto Cutoff",
        prSeconds: 198,
        prDate: "2024-04-02",
        fitnessValueAtPR: 0.31,
        currentFitnessValue: 0.18,
        trendDirection: "up",
        lastEffortSeconds: 221,
        strikeScore: 0.48,
        strikeLabel: "Worth a shot"
    ),
    SegmentScore(
        name: "Paradise Loop Climb",
        prSeconds: 534,
        prDate: "2025-04-15",
        fitnessValueAtPR: 0.72,
        currentFitnessValue: 0.18,
        trendDirection: "up",
        lastEffortSeconds: 598,
        strikeScore: 0.22,
        strikeLabel: "Not quite ready"
    ),
    SegmentScore(
        name: "Pantoll to Rock Spring",
        prSeconds: 1147,
        prDate: "2024-10-05",
        fitnessValueAtPR: 0.24,
        currentFitnessValue: 0.18,
        trendDirection: "up",
        lastEffortSeconds: 1198,
        strikeScore: 0.46,
        strikeLabel: "Worth a shot"
    ),
    SegmentScore(
        name: "Bolinas Ridge descent",
        prSeconds: 445,
        prDate: "2023-09-20",
        fitnessValueAtPR: 0.18,
        currentFitnessValue: 0.18,
        trendDirection: "up",
        lastEffortSeconds: 461,
        strikeScore: 0.52,
        strikeLabel: "Worth a shot"
    ),
]
```

### Hardcoded Enzo Briefing (for ArcBriefingView before Claude is wired)

```swift
static let previewBriefing = """
You peaked last August — 30 hours in a month, your best in years. September dropped \
off sharply, which happens. You've been Recovering since the new year but you're \
trending up now. Hawk Hill needs you at Strong, so there's real ground to cover — \
but your history shows you can move fitness fast when you're consistent.
"""
```

### Hardcoded Lookahead Suggestion

```swift
static let previewLookahead = """
It's been a few days. Nothing lost yet — your fitness doesn't move that fast. \
When you're ready, aim for two or three rides this week. Nothing heroic. Just get back on the bike.
"""
```

> **Note:** These hardcoded values are replaced by real data the moment Strava OAuth is wired in Step 6. The fitness chart will show Chad's actual training narrative — Epic in August, sharp September drop, slow rebuild — which makes Enzo's responses feel meaningful even against static data.