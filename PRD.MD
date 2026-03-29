# Enzo — App Specification v2
**Version:** 2.0  
**Author:** Chad Allen  
**Date:** March 2026  
**Purpose:** Claude Code development handoff  
**Changes from v1:** Arc-based single-screen experience, goal-first onboarding, inline conversational AI, HR-only fitness model (power data ignored for consistency), Enzo as explicit user-facing persona (Claude is implementation detail), flexible non-prescriptive tone throughout.

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
6. **HR-only.** The fitness model uses heart rate exclusively. Power meter data is ignored in MVP. This ensures a consistent, comparable fitness score across the full activity history.

---

## 3. Developer Context

- **Developer:** Solo, learning iOS development
- **Editor:** VS Code with Sweetpad extension
- **IDE:** Xcode (build, simulator, signing)
- **Primary language:** Swift / SwiftUI
- **Target platform:** iOS 17+, iPhone only (iPad later)
- **Backend:** Supabase (Postgres + Edge Functions)
- **AI:** Anthropic Claude API (`claude-sonnet-4-20250514`)
- **Data source:** Strava API (OAuth 2.0) + local Strava data export for development

> **Development note:** Build all screens against static/hardcoded data first. Wire up live APIs after UI is validated. The `/dev-data/` folder contains a sample Strava export to use during development.

---

## 4. Tech Stack

### MVP Stack

| Layer | Technology | Notes |
|---|---|---|
| UI | SwiftUI | iOS 17+ features |
| Charts | Swift Charts | Native, no third-party dependency |
| State management | `@Observable` macro + `@State` / `@Binding` | Modern Swift concurrency |
| Networking | `URLSession` + `async/await` | No third-party HTTP library |
| Auth | Strava OAuth 2.0 | Tokens stored in iOS Keychain |
| Backend | Supabase (Postgres) | Derived metrics only, never raw Strava data |
| AI | Anthropic Claude API | `claude-sonnet-4-20250514`, streaming enabled |
| Local storage | `UserDefaults` (preferences) + Keychain (tokens) | No CoreData for MVP |

### Beyond MVP

| Layer | Technology | Notes |
|---|---|---|
| Offline support | SwiftData | Migrate when needed |
| Push notifications | APNs via Supabase Edge Functions | Weekly plan drop, ride reaction |
| Widget | WidgetKit | Today widget: goal countdown + Claude one-liner |
| Watch | watchOS companion | Post-v1 |
| Auth expansion | Sign in with Apple | Required for App Store alongside Strava auth |

---

## 5. Data Architecture

### Core Principle
**Never store raw Strava data.** Pull activity history from the Strava API, compute derived metrics in-memory, persist only computed output to Supabase. Raw activity data is discarded after computation.

### Fitness Model (HR-Only)

The fitness score is a normalized 0–100 relative score. It measures the user against their own history — not against other athletes or absolute benchmarks.

Power meter data is intentionally ignored in MVP. Mixed power data (some rides with power, some without) produces inconsistent scores that make the fitness timeline misleading. HR data exists across all rides and provides a clean, comparable signal across the full history. Power can be added as an enhancement in a future version.

```
per_activity_load = duration_hours × hr_intensity_factor
hr_intensity_factor = avg_hr / resting_hr (capped at 2.0)

monthly_load = sum of per_activity_load for all rides that month
fitness_score = normalize(8_week_rolling_load, personal_min, personal_max) × 100
```

**Key behavior:** The fitness score is always a personal relative score — you vs. your own history. It is never compared to other athletes or absolute benchmarks. If an activity has no HR data, use duration only (lower confidence, not surfaced to user explicitly).

**Fitness score language:**
- 80–100: "Peak shape"
- 60–79: "Strong base"
- 40–59: "Building"
- 20–39: "Coming back"
- 0–19: "Early days"

These labels appear in the UI. The raw number is secondary.

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
  avg_hr integer,
  fitness_score numeric,       -- 0-100, relative to personal history
  fitness_label text,          -- "Strong base" etc.
  created_at timestamptz default now(),
  unique(user_id, month)
);

-- Personal bests
create table personal_bests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  effort_type text not null,   -- 'longest_ride_km', 'best_hr_efficiency', 'most_hours_in_month'
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
  start_latlng float[],        -- from segment.start_latlng, for MapKit display
  end_latlng float[],          -- from segment.end_latlng
  effort_count integer,        -- from athlete_pr_effort.effort_count
  pr_seconds integer,          -- from athlete_pr_effort.pr_elapsed_time
  pr_achieved_at date,         -- from athlete_pr_effort.pr_date
  fitness_score_at_pr numeric,
  current_fitness_score numeric,
  delta numeric,               -- positive = fitter now than when PR was set
  strike_score numeric,        -- 0-1, higher = better time to target
  updated_at timestamptz default now(),
  unique(user_id, strava_segment_id)
);

-- Goals (one active at a time)
-- MVP supports segment_pr only. Schema is intentionally extensible:
-- add goal_type values ('event', 'distance', 'fitness_level') in future 
-- without migration. target_date and target_value are nullable to support
-- open-ended segment goals with no deadline.
create table goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  raw_description text not null,    -- user's own words e.g. "Hawk Hill PR"
  claude_interpretation text,       -- Enzo's structured read of the goal
  goal_type text not null default 'segment_pr', -- MVP: always segment_pr
  target_segment_id bigint,         -- required for segment_pr goals
  target_segment_name text,         -- denormalized for display without join
  target_date date,                 -- optional: user can set a "by when" or leave open
  target_value numeric,             -- optional: target time in seconds (aspirational)
  required_fitness_score numeric,   -- estimated fitness score needed to PR this segment
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Weekly plans (Claude-generated, soft suggestions)
create table lookahead_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  suggestion_text text not null,       -- Enzo's forward-looking suggestion
  trigger_type text not null,          -- 'new_ride', 'gap_short', 'gap_medium', 'gap_long', 'goal_change'
  days_since_last_ride integer,
  generated_at timestamptz default now(),
  expires_at timestamptz               -- 3 days from generation, then regenerate on next open
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

Constructed fresh at query time from Supabase. Never persisted in this form.

```json
{
  "athlete": {
    "name": "Chad",
    "years_active": 4,
    "current_fitness_score": 71,
    "current_fitness_label": "Strong base"
  },
  "goal": {
    "type": "segment_pr",
    "segment_name": "Hawk Hill",
    "current_pr_seconds": 342,
    "target_date": "2026-05-15",   
    "weeks_remaining": 7,            
    "required_fitness_score": 82,
    "current_fitness_score": 71,
    "gap": 11,
    "has_date": true
    // has_date: false when no target date set — Enzo drops countdown language
  },
  "fitness_history": [
    {
      "month": "2025-09",
      "hours": 22,
      "fitness_score": 88,
      "fitness_label": "Peak shape",
      "activity_count": 18
    }
  ],
  "peak_fitness": {
    "month": "2025-09",
    "score": 88,
    "label": "Peak shape"
  },
  "recent_weeks": [
    {
      "week": "2026-03-17",
      "hours": 6.5,
      "activity_count": 4,
      "note": "Solid week"
    }
  ],
  "top_segments": [
    {
      "name": "Hawk Hill",
      "pr_seconds": 342,
      "pr_date": "2025-08-12",
      "fitness_at_pr": 85,
      "current_fitness": 71,
      "delta": -14,
      "strike_score": 0.71,
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
3. Strava redirects to `enzo://oauth`
4. App exchanges code for tokens
5. Tokens stored in iOS Keychain only

### Required Scopes
- `activity:read_all` — full activity history including private activities, and `average_heartrate` on activities
- `read` — athlete profile (display name, profile photo)

> **Note:** `profile:read_all` is NOT required. It would be needed for `GET /athlete/zones` but that endpoint is not used in MVP.

### Sync Strategy

**Initial sync (first login):**

**Phase 1 — Activity list + HR (fast, ~5 API calls for 800 activities):**
1. Fetch all activities paginated at 200/page via `GET /athlete/activities`
2. Extract per activity: `id`, `start_date`, `moving_time`, `elapsed_time`, `distance`, `sport_type`, `has_heartrate`, `average_heartrate`, `trainer` flag
3. `average_heartrate` is returned directly in `SummaryActivity` — no individual activity calls needed for fitness computation
4. Filter to cycling sport types only: `Ride`, `VirtualRide`, `MountainBikeRide`, `GravelRide`, `EMountainBikeRide`
5. Compute monthly snapshots + personal bests in-memory
6. Write derived metrics to Supabase
7. Discard raw activity data

**Phase 2 — Segment effort extraction (background, 1 call per activity):**
8. For each cycling activity, fetch `GET /activities/{id}?include_all_efforts=true`
9. Extract `segment_efforts` array — each effort includes: `segment.id`, `segment.name`, `segment.start_latlng`, `elapsed_time`, `start_date`, and crucially `segment.athlete_pr_effort` containing `pr_elapsed_time`, `pr_date`, `effort_count`
10. Build segment score records from this data
11. Write to `segment_scores` table in Supabase
12. Discard raw activity data

**Rate limit management:**
- Phase 1 completes in seconds — fitness timeline is usable immediately
- Phase 2 is the expensive operation: 1 call per activity. For 800 activities = ~4 batches of 200. At 200 req/15 min this takes ~15 minutes total.
- Run Phase 2 as a background task. App is fully usable while it runs.
- Store sync progress in Supabase so it survives app restarts
- For activities with no HR data (`has_heartrate = false`), use duration-only load calculation (lower confidence, not surfaced to user)

**Rate limit handling:** 200 req/15 min, 2,000/day. Show sync progress. Never block UI. For large histories, batch and queue.

**Ongoing sync:** Strava webhook on new activity → fetch single activity → update current month snapshot → re-score segment deltas → trigger Arc regeneration if significant change.

**On Strava disconnect:** Delete all derived data from Supabase. Reset to onboarding.

---

## 7. Claude API Integration

### Configuration
```swift
let claudeAPIURL = "https://api.anthropic.com/v1/messages"
let claudeModel = "claude-sonnet-4-20250514"
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
- Always use their actual numbers. Never give advice that could apply to anyone.
- Fitness is HR-based. Don't reference power, FTP, or watts unless the athlete brings it up.
- Frame everything relative to their personal history and their goal.
- Use fitness labels (Peak shape, Strong base, Building, Coming back) naturally in conversation.
- A suggestion is not a plan. Make that clear when offering workouts.

Format:
- 2-4 sentences for simple questions.
- Up to 3 short paragraphs for complex ones.
- No bullet points in conversational responses.
- Bullet points only for workout suggestions, and keep them loose.
```

### Claude Use Cases

| Trigger | What Claude does | Where it appears |
|---|---|---|
| App open (daily) | Generates Arc briefing: goal status + fitness read + one forward-looking line | Top of Arc |
| New activity synced | One-line reaction to the ride | Arc, below briefing |
| App open or new ride syncs | Generates rolling 5–7 day lookahead based on days since last ride | Arc, what to do next section |
| User types question | Responds in Arc thread | Arc, inline |
| Goal set / changed | Identifies segment, estimates required fitness score to PR it, reacts to whether user is close or far | Goal-setting flow |
| Segment tapped | One-line "why now?" for this segment | Segment detail |
| "Help me find a goal" | Analyzes segment data + history, proposes 2-3 goal options | Onboarding |

### Streaming
All Claude responses stream. Use `AsyncStream` in `ClaudeService.swift` to pipe tokens as they arrive into the UI. Never show a loading state longer than the first token — get something on screen fast.

---

## 8. User Journeys

### Journey 1: First Launch

**Step 1 — Connect**
- Clean hero screen. App name, tagline: *"Meet Enzo. Your cycling companion."*
- Single CTA: "Connect Strava"
- Strava OAuth via `ASWebAuthenticationSession`

**Step 2 — Sync (required — user must wait)**

The sync screen blocks progression to goal-setting. Segment search requires the segment history to be fully loaded — there is no useful experience without it. Use this time well.

**Animation: Route Drawing**
- A minimal, abstract cycling route traces itself across a dark background using SwiftUI's `trimmedPath` animation — the line draws from start to finish continuously, looping with a slight fade-out and redraw
- The route is a simplified but realistic-looking cycling path shape — not a perfect circle or generic squiggle. Think a Strava-style GPS trace: rolling curves, a switchback or two, an obvious climb section
- Rendered in the brand accent color (`#4FC3F7`) on the dark background (`#0A0A0F`)
- Subtle gradient trail behind the drawing point — the oldest portion of the line fades slightly, giving the impression of motion through a landscape
- No map tiles, no real geography — purely abstract line art. Keeps it fast and avoids any mapping API dependency at this stage

**Copy: Phases**
Copy updates as sync moves through its real phases. Each line crossfades to the next:
1. *"Reading your rides..."* — activity fetch in progress
2. *"Finding your best efforts..."* — segment history processing  
3. *"Sizing up your fitness..."* — metrics computation
4. *"Scoping your opportunities..."* — strike scores calculating
5. *"Enzo is almost ready..."* — final writes to Supabase

Activity count appears in small secondary text below the copy, incrementing as activities are processed: *"847 rides and counting"*

**On completion:**
- Route drawing animation completes one final full loop
- Crossfades to goal-setting screen
- No "tap to continue" — transition is automatic when sync finishes

**If sync takes > 60 seconds:**
- Add a single line of secondary copy below the counter: *"Big history — this is worth it."*
- Never show a progress percentage or estimated time — these create anxiety when they stall

> **Implementation note:** Use SwiftUI `trim(from:to:)` on a `Path` with an `@State` variable animated via `withAnimation(.linear(duration:).repeatForever())`. The route shape is a hardcoded `Path` defined as a series of curves — not MapKit, not any external data. Design the path shape in Figma or directly in SwiftUI coordinates before coding.

**Step 3 — Goal Setting (the key moment)**

Screen title: *"Which segment are you chasing?"*

**Path A — User knows their segment:**
- Search field: user types a segment name
- Results pull from their own Strava segment history (segments they've actually ridden)
- User taps a segment → Enzo reacts immediately, streaming:
  > *"Hawk Hill. Good choice. You set that PR at peak fitness last August — you're about 80% of the way back. You don't need a date for this, but if you have one in mind it helps me calibrate."*
- Optional date input appears below (clearly optional, easily skipped)
- User taps "Set this goal" → advances to Arc

**Path B — User wants a suggestion:**
- Taps "Help me pick one"
- Enzo analyzes segment history + fitness delta
- Proposes 2-3 segments as tappable cards, ranked by strike score + meaningfulness:
  > *"Hawk Hill — your most-ridden segment. You're close to beating it."*  
  > *"Camino Alto Cutoff — you're actually fitter now than when you set this one."*  
  > *"Paradise Loop climb — a stretch goal. Worth building toward."*
- User taps one → same confirmation flow as Path A

**Goal change note (shown once, subtly below the goal header on first Arc view):**
*"This is your focus for now. Change it any time — no commitment required."*

> **Extensibility note:** When event goals are added, this screen gets a second option at the top: "A segment PR" / "An event or race". The segment PR path is unchanged. The event path is a new flow. Nothing about the current segment flow needs to change to accommodate this.

---

### Journey 2: The Arc (Main Experience)

The Arc is a single vertically scrolling view. Claude narrates it. It updates when new rides sync.

**Sections, top to bottom:**

---

**① Goal Header (always visible, sticky)**

The goal is always a segment PR. Date is optional — if set, show a countdown. If not, show fitness gap only. Both are fully supported states.

```
[Segment name]                 [X weeks to go — IF date set]
Hawk Hill PR                   7 weeks

  — or, if no date —

[Segment name]
Hawk Hill PR

[Progress bar: current fitness → required fitness]
Strong base ————————●————————— Peak shape needed
                   71              82

                        [Change goal]
```

Tapping "Change goal" opens the goal-setting flow inline. No guilt. No warning. Just a sheet.

> **Extensibility note:** When event-based goals are added in a future version, the Goal Header is the primary component that changes. The progress bar logic (current fitness → required fitness) works identically for event goals — only the label and optional date source change. Design this component to accept a goal type prop, not hardcode segment-specific copy.

---

**② Today's Briefing (Enzo-generated, refreshes daily)**

Enzo's synthesis of where things stand. 2-3 sentences. Specific to their data.

Example:
> *"You're in a good window. Seven weeks is plenty of time to get from where you are to where you need to be for Hawk Hill — your history shows you can move fitness scores 15+ points in that timeframe when you're consistent. This week is a good week to push a little."*

If they haven't ridden in a while:
> *"It's been 10 days since your last ride. That's fine — you haven't lost much. Pick it back up this week and you'll be right back on track."*

No red states. No "you're falling behind" without an immediate path forward.

---

**③ Last Ride Reaction (appears after each new sync)**

One line. Specific to the ride.

Example:
> *"Tuesday's ride was your longest in 6 weeks — good timing."*

Or:
> *"Short one yesterday, but sometimes that's the ride you needed."*

Fades into history after 48 hours.

---

**④ What To Do Next (rolling, context-driven)**

Enzo always has a forward-looking suggestion. It's a rolling 5–7 day lookahead, not a weekly plan. It regenerates when context changes meaningfully: after a new ride syncs, after a goal change, or when the existing suggestion is more than 3 days old.

There is no Monday dependency. There is no weekly reset. Enzo just always knows what makes sense given what you've done recently and how much time is left toward your goal.

**Trigger: new ride synced**
> *"Good ride yesterday — that's exactly the kind of effort that moves the needle. For the next few days, something easier would serve you well. Then if you can get one more solid effort in before the weekend, you're in great shape."*

**Trigger: opened app, no new rides since last open (< 5 days)**
> *"You've had a couple of days off. That's fine — your fitness doesn't evaporate that fast. When you're ready to ride again, pick up where you left off. Nothing heroic needed."*

**Trigger: opened app, no new rides since last open (5–7 days)**
> *"It's been about five days. You've got 6 weeks until your goal — still plenty of time, but this week is worth showing up for. Even one solid ride gets things moving again."*

**Trigger: long gap (7+ days)**
> *"Let's reset. A week off happens. Your fitness has dipped a little but it comes back fast — your body remembers. Here's what the next few days should look like to get back on track."*

No day-by-day prescription. No "rest day Tuesday." User can always ask Enzo follow-up questions inline.

Small label beneath: *"A suggestion, not a plan. Adjust freely."*

---

**⑤ Fitness History (relative to goal)**

A compact Swift Charts line chart. 12 months visible by default.

Two reference lines:
- **Your peak** — labeled, dashed horizontal line
- **Goal target** — labeled, dashed horizontal line (the required fitness score)

Current position: animated pulse dot on the curve.

Tap any month → bottom sheet with that month's summary: hours, rides, notable efforts. No drill-down beyond this in MVP.

Below the chart, one Claude sentence contextualizing it:
> *"Your peak was last September. You've been building back since January — this is normal."*

---

**⑥ PR Opportunities (Segment Radar)**

Compact card, not a full section. Top 3 segments by strike score.

```
Strike while you're hot

① Hawk Hill           ★ Goal segment
  PR: 5:42  ·  You're close — best window in 6 months

② Camino Alto Cutoff
  PR: 3:18  ·  Slightly fitter than your PR day

③ Paradise Loop climb
  PR: 8:54  ·  Worth a shot this weekend
```

"See all opportunities →" links to the full Segments tab (one of two tabs, see nav below).

---

**⑦ Inline Conversation**

Below all sections, a persistent input bar:
*"Ask Enzo anything..."*

User types → Claude responds inline, streaming, in a chat-style thread below the input. The thread is part of the Arc, not a separate screen. It scrolls with everything else.

Conversation is maintained within the session. A new day starts a fresh thread, but the last 3 exchanges are kept as context for Claude.

Suggested prompt chips above the input (horizontally scrollable, updated weekly):
- *"Am I on track for Hawk Hill?"*
- *"What should I do this weekend?"*
- *"When was I last this fit?"*
- *"What if I only have 4 weeks left?"*

---

### Journey 3: Changing a Goal

User taps "Change goal" in the Goal Header at any time.

- Same goal-setting UI as onboarding
- Enzo acknowledges the change warmly: *"Got it, switching to Camino Alto. Good call — you're actually already fitter than when you set that one."*
- Arc rebuilds around the new goal
- Old goal is archived in Supabase (not deleted)
- No warning, no "are you sure," no friction

---

### Journey 4: Segment Detail

User taps any segment from PR Opportunities or the full Segments tab.

Screen shows:
- Segment name + location
- Map thumbnail (MapKit polyline from segment coordinates)
- Current PR + date
- Fitness delta: their score now vs. their score when PR was set
- Strike score with plain English: *"You're in better shape now than when you set this PR."* or *"You're not quite there yet — worth targeting in a few weeks."*
- Claude one-liner (generated on tap, cached for session): *"Your legs should feel different on this one than last August — trust that."*
- "Open in Strava" button

---

## 9. Navigation Structure

Simplified to two tabs. The Arc is the app.

```
Tab Bar (2 tabs):
├── Arc (Home) — The full experience described above
└── Segments — Full PR opportunity list with sorting + filters
```

No Chat tab. No Goals tab. No History tab. Everything lives in the Arc.

**Segments tab** (simple list):
- Sort by: Strike Score (default) / Alphabetical / PR Date
- Filter: Goal segment first
- Each row: name, PR time, strike score badge (colored pill), fitness delta arrow
- Tap → Segment Detail screen (push navigation)

**Settings** accessible via profile avatar in Arc header (top right):
- Connected Strava account + Disconnect
- Manual re-sync
- App version

---

## 10. UI Requirements

### Design Direction

**Aesthetic:** Confident, warm, editorial. Like a well-designed training journal — not a sports analytics dashboard. Dark-mode first. Data supports narrative, not the other way around.

**Color palette:**
- Background: `#0A0A0F`
- Card surfaces: `#141420`
- Brand accent: `#4FC3F7` (electric blue — used for the fitness curve, CTAs)
- Goal accent: `#81C784` (muted green — goal progress, positive deltas)
- Amber: `#FFB74D` — used sparingly for "worth noting" signals only
- Text primary: `#F0F0F5`
- Text secondary: `#8888AA`

**Typography:**
- Display / section headers: SF Pro Rounded Bold (warmer than default SF Pro)
- Body / Claude text: SF Pro Text Regular
- Data labels: SF Pro Mono (for numbers — times, scores, hours)
- Never use custom fonts in MVP — SF system fonts only for performance and legibility

**Tone in copy:**
- Never "You failed to complete"
- Never "Missed workout"
- Never red states for inactivity
- Use: "It's been a few days", "Pick it back up", "You're building"
- Goal progress bar never goes red — it goes amber at most, with a constructive Claude line

### Key UI Components

**GoalHeaderView** (sticky at top of Arc)
- Goal name (bold, truncated at 24 chars)
- Weeks remaining (right-aligned, accent color)
- Progress bar: two labeled endpoints, filled to current fitness position
- "Change goal" text button (small, secondary style) — always visible, never hidden

**ArcBriefingView**
- Claude's daily synthesis text, streaming on first render
- Subtle left border in accent color to visually distinguish Enzo's voice
- Refresh chevron (top right) to manually regenerate
- Last updated timestamp in secondary text below

**LookaheadSuggestionView**
- Claude's workout suggestion
- Small italic label: *"A suggestion, not a plan"*
- "Ask about this week →" chips below that pre-populate the input

**FitnessChartView** (Swift Charts)
- `LineMark` + `AreaMark` fill below curve
- Two `RuleMark` horizontal lines: peak fitness, goal target fitness
- Animated draw-in on first appearance (0.6s, left to right)
- Tappable month selection — selected month highlighted, detail sheet slides up
- Axis labels: abbreviated month names, no year unless >12 months shown

**SegmentStrikeRow**
- Name (bold) + PR time (mono)
- Strike score pill: green ("Strike now"), amber ("Getting close"), grey ("Not yet")
- Fitness delta: small arrow + percentage in secondary text

**ArcInputBar** (persistent bottom of Arc)
- Pill-shaped text input
- Send button appears on text entry
- Prompt chips scroll horizontally above input
- Input bar floats above tab bar, not inside it

### Motion
- Chart draws in on load: 0.6s ease-out
- Claude text streams character by character (not word — character feels more alive)
- Bottom sheet springs (standard iOS spring, don't override)
- Prompt chips slide in on load with staggered delay
- Strike score pill: subtle pulse animation on "Strike now" items only
- Arc sections fade in sequentially on first load (stagger 0.1s each)
- No celebration animations, no confetti — this isn't that kind of app

---

## 11. File Structure

```
Enzo/
├── App/
│   ├── EnzoApp.swift
│   └── AppState.swift               # Global @Observable: user, goal, sync status
├── Features/
│   ├── Onboarding/
│   │   ├── OnboardingView.swift      # Connect + sync screens
│   │   ├── GoalSettingView.swift     # Goal input + Claude interpretation
│   │   └── SyncProgressView.swift
│   ├── Arc/
│   │   ├── ArcView.swift             # Main scrollable Arc, composes all sections
│   │   ├── GoalHeaderView.swift      # Sticky goal + progress bar
│   │   ├── ArcBriefingView.swift     # Claude daily synthesis
│   │   ├── LastRideReactionView.swift
│   │   ├── LookaheadSuggestionView.swift
│   │   ├── FitnessChartView.swift    # Swift Charts fitness curve
│   │   ├── MonthDetailSheet.swift    # Bottom sheet on chart tap
│   │   ├── PROpportunitiesCard.swift # Top 3 segments, compact
│   │   ├── ArcInputBar.swift         # Inline conversation input
│   │   ├── ArcMessageView.swift      # Claude/user message bubble
│   │   └── PromptChipsView.swift
│   └── Segments/
│       ├── SegmentsView.swift        # Full segment list tab
│       └── SegmentDetailView.swift
├── Services/
│   ├── StravaService.swift           # OAuth, activity fetch, webhooks
│   ├── ClaudeService.swift           # API calls, streaming, prompt assembly
│   ├── SupabaseService.swift         # Read/write derived metrics
│   └── SyncService.swift             # Strava → metrics pipeline orchestration
├── Models/
│   ├── AthleteContext.swift          # Claude context payload, toJSON()
│   ├── FitnessSnapshot.swift
│   ├── Goal.swift
│   ├── SegmentScore.swift
│   ├── LookaheadSuggestion.swift
│   └── ArcMessage.swift
├── Utils/
│   ├── KeychainHelper.swift
│   ├── FitnessCalculator.swift       # HR-first fitness model, power enhancement
│   ├── SegmentScorer.swift           # Strike score computation
│   └── Extensions/
└── dev-data/
    └── strava_export.json            # Developer's real Strava export for static dev
```

---

## 12. Fitness Computation Detail

### HR-Only Model

```swift
// Per activity
func activityLoad(durationHours: Double, avgHR: Int, restingHR: Int) -> Double {
    let intensity = min(Double(avgHR) / Double(restingHR), 2.0)
    return durationHours * intensity
}

// Per month
func monthlyFitnessLoad(activities: [Activity]) -> Double {
    activities.reduce(0) { $0 + activityLoad($1.durationHours, $1.avgHR, restingHR) }
}

// Score: normalize against personal history (rolling 24-month min/max)
func fitnessScore(currentLoad: Double, historicalLoads: [Double]) -> Double {
    let min = historicalLoads.min() ?? 0
    let max = historicalLoads.max() ?? 1
    return ((currentLoad - min) / (max - min)) * 100
}
```

### Power Data
Power meter data is not used in the MVP fitness model. If present in activity records, ignore it during computation. This keeps the fitness score consistent across the full history regardless of when the athlete started using a power meter.

### Segment Strike Score

```swift
func strikeScore(currentFitness: Double, fitnessAtPR: Double, prDate: Date) -> Double {
    let delta = currentFitness - fitnessAtPR
    let recencyMultiplier = prDate < Date().addingTimeInterval(-180*86400) ? 1.0 : 0.7
    let normalizedDelta = (delta + 20) / 40  // center around 0 delta, cap at ±20
    return min(max(normalizedDelta * recencyMultiplier, 0), 1)
}

// Strike label
func strikeLabel(score: Double) -> String {
    switch score {
    case 0.7...: return "Strike now"
    case 0.4..<0.7: return "Getting close"
    default: return "Not yet"
    }
}
```

---

## 13. Error States & Edge Cases

| Scenario | Handling |
|---|---|
| < 2 months of Strava data | Arc shows with note: "More rides = richer insights — check back as your history builds" |
| No HR data on activities | Fitness model uses duration only, lower confidence, noted in Arc |
| Claude API timeout | Show "Couldn't reach Enzo — tap to retry" in place of briefing. Never blank. |
| Strava rate limit during sync | Pause, show "Syncing in the background", auto-resume. No user action needed. |
| Strava auth expires | Silent token refresh first. If fails, prompt re-auth with warm copy: "Strava needs you to reconnect — takes 10 seconds." |
| Goal has no target date | Valid. Claude treats it as open-ended and focuses on fitness direction, not countdown. |
| Supabase write fails | Retry silently 3x, then toast: "Couldn't save your data — will retry." |
| User disconnects Strava | Delete all Supabase data, reset to onboarding. Confirmed with one dialog: "This will clear all your synced data." |

---

## 14. What's Out of Scope (MVP)

- Social features of any kind
- Other users' data
- Running (cycling only for now)
- Event / race goals (architecture supports it, intentionally deferred to v2)
- Day-by-day rigid training schedules
- Missed workout tracking or streaks
- Notifications (post-MVP)
- iPad
- Apple Watch
- Export or sharing
- In-app purchases

---

## 15. Open Technical Questions

1. **Sweetpad setup:** Confirm Sweetpad extension is configured with correct Xcode project target. Build + run from VS Code to iOS Simulator should work before writing any feature code.
2. **Supabase project:** Create at supabase.com. Run schema SQL from Section 5 in the SQL editor. Store `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `Config.xcconfig` excluded from git.
3. **Claude API key:** Keychain only. Use `xcconfig` for dev builds. Never commit to git.
4. **Strava app registration:** Register at strava.com/settings/api. Set redirect URI to `enzo://oauth`. Store `client_id` and `client_secret` in Keychain.
5. **Strava data export:** Not used. The bulk export was analyzed and rejected as a dev fixture — segment data is empty, fit files are binary requiring a separate parsing library, and CSV activity type values don't match API field names. Development uses hardcoded data for UI steps (1–4), then goes directly to the live Strava API. See revised build order in Section 17.
6. **Resting HR:** Strava does not expose resting HR via the API. Use 60bpm as a fixed fallback for all users in MVP. Post-MVP: add a resting HR input to Settings so the user can calibrate their own baseline.

---


## 16. Secrets & API Key Management

All API keys and secrets are managed via xcconfig files. Never use global config, hardcoded strings, or environment variables for secrets in this project.

### File Structure

```
Enzo/
├── Config/
│   ├── Debug.xcconfig       # Developer secrets — never committed to git
│   └── Release.xcconfig     # Can mirror Debug for now
```

### .gitignore — Add Before First Commit

```
Config/Debug.xcconfig
Config/Release.xcconfig
```

This must be done before the first commit. Not after.

### Debug.xcconfig Contents

```
CLAUDE_API_KEY = sk-ant-yourkey
SUPABASE_URL = https://yourproject.supabase.co
SUPABASE_ANON_KEY = your-anon-key
STRAVA_CLIENT_ID = your-client-id
STRAVA_CLIENT_SECRET = your-client-secret
```

### Wire xcconfig to Xcode Project

In Xcode: select the project in the navigator → Info tab → expand Configurations → set Debug and Release to point to their respective xcconfig files.

### Expose Keys via Info.plist

Add to `Info.plist`:

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

### Read in Swift via Config Helper

```swift
// Utils/Config.swift
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

Use `Config.claudeAPIKey` anywhere in the app. No hardcoding. No global config.

### Secret Storage by Type

| Secret | Storage | Reason |
|---|---|---|
| Claude API key | xcconfig → Info.plist → Config.swift | Developer-owned, build-time constant |
| Supabase URL + anon key | xcconfig → Info.plist → Config.swift | Developer-owned, build-time constant |
| Strava client ID + secret | xcconfig → Info.plist → Config.swift | Developer-owned, build-time constant |
| Strava user access token | iOS Keychain | User credential, must survive app restarts |
| Strava user refresh token | iOS Keychain | User credential, must survive app restarts |

The rule: your keys go in xcconfig. The user's tokens go in Keychain.

## 17. Build Order

Follow this sequence. Each step produces something visible or testable before moving on.

1. **Project setup** — Xcode project named "Enzo", Sweetpad config, 2-tab shell (Arc + Segments), placeholder views. Immediately after project creation: create `Config/Debug.xcconfig`, add to `.gitignore`, wire to Xcode project configurations, add keys to `Info.plist`, create `Utils/Config.swift`. Confirm `Config.claudeAPIKey` resolves before writing any feature code. Confirm Sweetpad can build and run to iOS Simulator.
2. **Arc UI (static)** — Build all Arc sections with hardcoded data. Goal header, briefing card, fitness chart, segment card, input bar. Make it look right. **The app launches directly into ArcView at this stage — no login screen, no OAuth flow, no onboarding. Do not scaffold any authentication screens yet. Right now we're building the interior.**
3. **Claude wiring (hardcoded context)** — Wire ArcInputBar to real Claude API with a hardcoded `AthleteContext` JSON. Get streaming working. Tune system prompt.
4. **Goal setting UI** — GoalSettingView with Claude interpretation flow. Wire to Claude API.
5. **Supabase schema + models** — Create tables, Swift models, SupabaseService read/write.
6. **Strava OAuth** — Auth flow, token storage, athlete profile fetch. Moved up because the bulk export is not a viable dev fixture — segment data is empty and fit files are binary. Going direct to the real API is simpler than building a mock pipeline.
7. **Historical sync (Phase 1)** — Paginated activity fetch via `GET /athlete/activities`. Extract HR, duration, distance per activity. Run FitnessCalculator.swift in-memory. Write fitness snapshots to Supabase.
8. **Context payload** — Build `AthleteContext` from Supabase data. Feed into all Claude calls. Enzo is now talking about your real rides.
9. **Arc content generation** — Wire briefing, last ride reaction, lookahead suggestion to Claude with real context.
10. **Historical sync (Phase 2) + Segment scoring** — Background fetch of `GET /activities/{id}?include_all_efforts=true` for each activity. Extract segment efforts. Run SegmentScorer.swift. Write to `segment_scores` table. Wire full Segments tab and Arc PR card.
11. **Strava webhooks** — Real-time new activity handling.
12. **Onboarding flow** — Now that OAuth and sync work, build the front door: connect screen, sync animation, goal setting.
13. **Polish pass** — Animations, empty states, error states, copy review, settings screen.

---

## 18. Hardcoded Data for Static UI Development (Steps 2–5)

Before Strava OAuth is wired in Step 6, all views are built against this hardcoded data. This data is derived from Chad's real Strava history so Enzo's responses feel meaningful even in the static phase.

**Do not invent placeholder data. Use the values below exactly.**

### Athlete Context (hardcode in `AthleteContext.swift`)

```swift
static let preview = AthleteContext(
    name: "Chad",
    yearsActive: 11,
    totalActivities: 654,
    currentFitnessScore: 20,
    currentFitnessLabel: "Coming back",
    peakFitnessScore: 100,
    peakFitnessMonth: "August 2025",
    daysSinceLastRide: 3,
    goal: GoalContext(
        segmentName: "Hawk Hill",
        requiredFitnessScore: 72,
        targetDate: nil,
        weeksRemaining: nil,
        gap: 52
    )
)
```

### Fitness History (last 18 months — hardcode in `FitnessChartView`)

```swift
static let previewSnapshots: [FitnessSnapshot] = [
    FitnessSnapshot(month: "2024-10", score: 24, hours: 7.6, rides: 7),
    FitnessSnapshot(month: "2024-11", score: 12, hours: 4.1, rides: 4),
    FitnessSnapshot(month: "2024-12", score: 13, hours: 4.3, rides: 4),
    FitnessSnapshot(month: "2025-01", score: 21, hours: 6.7, rides: 5),
    FitnessSnapshot(month: "2025-02", score: 14, hours: 4.7, rides: 3),
    FitnessSnapshot(month: "2025-03", score: 69, hours: 21.2, rides: 10),
    FitnessSnapshot(month: "2025-04", score: 72, hours: 22.1, rides: 8),
    FitnessSnapshot(month: "2025-05", score: 36, hours: 11.1, rides: 8),
    FitnessSnapshot(month: "2025-06", score: 39, hours: 12.1, rides: 9),
    FitnessSnapshot(month: "2025-07", score: 45, hours: 13.9, rides: 7),
    FitnessSnapshot(month: "2025-08", score: 100, hours: 30.4, rides: 13), // peak
    FitnessSnapshot(month: "2025-09", score: 4,  hours: 1.6,  rides: 2),  // sharp drop
    FitnessSnapshot(month: "2025-10", score: 58, hours: 17.6, rides: 18),
    FitnessSnapshot(month: "2025-11", score: 37, hours: 11.6, rides: 8),
    FitnessSnapshot(month: "2025-12", score: 26, hours: 8.1,  rides: 8),
    FitnessSnapshot(month: "2026-01", score: 26, hours: 8.2,  rides: 6),
    FitnessSnapshot(month: "2026-02", score: 26, hours: 8.3,  rides: 5),
    FitnessSnapshot(month: "2026-03", score: 20, hours: 6.4,  rides: 6),  // current
]
```

### Segment PR Opportunities (hardcode in `PROpportunitiesCard` and `SegmentsView`)

Real Bay Area segments with plausible PR data:

```swift
static let previewSegments: [SegmentScore] = [
    SegmentScore(
        name: "Hawk Hill",
        prSeconds: 342,    // 5:42
        prDate: "2025-08-10",
        fitnessAtPR: 98,
        currentFitness: 20,
        strikeScore: 0.18,
        isGoalSegment: true
    ),
    SegmentScore(
        name: "Camino Alto Cutoff",
        prSeconds: 198,    // 3:18
        prDate: "2024-04-02",
        fitnessAtPR: 31,
        currentFitness: 20,
        strikeScore: 0.44
    ),
    SegmentScore(
        name: "Paradise Loop Climb",
        prSeconds: 534,    // 8:54
        prDate: "2025-04-15",
        fitnessAtPR: 72,
        currentFitness: 20,
        strikeScore: 0.22
    ),
    SegmentScore(
        name: "Pantoll to Rock Spring",
        prSeconds: 1147,   // 19:07
        prDate: "2024-10-05",
        fitnessAtPR: 24,
        currentFitness: 20,
        strikeScore: 0.48
    ),
    SegmentScore(
        name: "Bolinas Ridge descent",
        prSeconds: 445,    // 7:25
        prDate: "2023-09-20",
        fitnessAtPR: 18,
        currentFitness: 20,
        strikeScore: 0.71  // strike now — fitter than PR day
    ),
]
```

### Hardcoded Enzo Briefing (for ArcBriefingView before Claude is wired)

```swift
static let previewBriefing = """
You peaked last August — 30 hours in a month, your best in years. September dropped off sharply, which happens. You've been in the 20s since the new year. Hawk Hill will need you closer to where you were in spring 2025, so there's real ground to cover. The good news is your history shows you can move fitness quickly when you're consistent.
"""
```

### Hardcoded Lookahead Suggestion

```swift
static let previewLookahead = """
It's been a few days. Nothing lost yet — your fitness doesn't move that fast. When you're ready, aim for two or three rides this week. Nothing heroic. Just get back on the bike.
"""
```

> **Note:** These hardcoded values are replaced by real data the moment Strava OAuth is wired in Step 6. They exist only to make the UI feel real during development. The fitness chart will show Chad's actual training narrative — peak in August, sharp September drop, slow rebuild — which makes Enzo's responses feel meaningful even against static data.