Good instinct. Let me write a tight summary now while we still have headroom.

---

## Enzo — Project Summary & Decision Log
**As of March 28, 2026**

### What We Built
A full product spec, technical architecture, and Claude Code development scaffold for **Enzo** — a personal iOS cycling app that uses your Strava history to tell you when to go for segment PRs, narrated by an AI companion also named Enzo (powered by Claude on the backend).

---

### Key Product Decisions

**Core concept:** Goal-first, segment-PR focused. You set a target segment, Enzo tracks your fitness relative to that goal and tells you when conditions are right to go for it. Event/race goals are explicitly deferred to v2 but the architecture supports them.

**The Arc:** Single scrollable screen — not a tab-per-feature. Everything lives in one vertical flow: sticky goal header → daily briefing → last ride reaction → lookahead suggestion → fitness chart → PR opportunities → inline conversation with Enzo.

**No Chat tab:** Conversation is inline at the bottom of the Arc, always context-aware of what you're looking at. Not a separate experience.

**Enzo persona:** European cycling companion. Warm, direct, never guilty, never prescriptive. "A suggestion, not a plan" appears beneath every workout recommendation. No streaks, no red states, no missed workout tracking.

**Fitness model:** HR-only, deliberately. Mixed power data (some rides with, some without) produces inconsistent scores across history. HR gives a clean comparable signal across all 654 cycling rides.

**No bulk export:** Strava's bulk export segment data is essentially empty (4 rows). Went direct to API instead. Rate limit math: 659 total API calls for full initial sync, fits in 33% of daily budget.

**Onboarding last:** Built in Step 11, not Step 1. Front door goes on after the house is built.

---

### Technical Architecture

**Stack:** SwiftUI iOS 17+, Swift Charts, @Observable, async/await, Supabase, Claude API (claude-sonnet-4-20250514), Strava OAuth 2.0.

**Secrets:** xcconfig → Info.plist → Config.swift for developer keys. Keychain for user Strava tokens. Never hardcoded, never committed.

**Data pipeline:**
- Phase 1: `GET /athlete/activities` paginated — HR is in the summary response, no individual calls needed
- Phase 2: `GET /activities/{id}?include_all_efforts=true` — segment efforts with `athlete_pr_effort` embedded. Background, non-blocking.
- Never store raw Strava data. Compute in memory, write only derived metrics to Supabase.

**Key API facts confirmed from official docs:**
- `average_heartrate` IS in `SummaryActivity` (list endpoint) — no individual calls needed for fitness
- `GET /segment_efforts` requires paid Strava subscription — not used
- `sport_type` not `type` (deprecated) — cycling filter: Ride, Virtual Ride, E-Bike Ride, Gravel Ride, Mountain Bike Ride
- Rate limits: 200 req/15min, 2,000/day

**Segment scoring:** `athlete_pr_effort` embedded in activity detail gives PR time, date, effort count. Strike score = fitness delta × recency multiplier. Labels: Strike now (≥0.7), Getting close (0.4–0.7), Not yet (<0.4).

---

### Hardcoded Dev Data (real numbers from Chad's Strava)
- 654 cycling activities, 11 years
- Peak: August 2025, score 100, 30.4 hours
- Current: March 2026, score 20, "Coming back"
- Goal: Hawk Hill PR, required fitness ~72, gap of 52 points
- 5 Bay Area segments with realistic PR history in preview data

---

### Build Order (revised)
1. ✅ Project setup + secrets
2. ✅ Arc UI (static hardcoded data)
3. ✅ Claude API wired (hardcoded context, streaming working)
4. Goal setting UI
5. Supabase schema + models
6. Strava OAuth
7. Historical sync Phase 1 (fitness)
8. Context payload + live Enzo
9. Historical sync Phase 2 + segment scoring
10. Strava webhooks
11. Onboarding flow
12. Polish pass

---

### Files Created
- `strava-iq-spec-v2.md` — full product spec (18 sections)
- `CLAUDE.md` — project brief for Claude Code sessions
- `enzo-handoff-prompt.md` — initial Claude Code prompt template
- `skills/swiftui-design.md` — UI design rules
- `skills/enzo-voice.md` — copy tone + verbatim system prompt
- `skills/swift-patterns.md` — architecture rules, data flow
- `skills/testing.md` — Swift Testing patterns, acceptance criteria per step

---

### Strava API Policy Note
Data retention policy: 7-day cache limit on raw Strava data. Enzo's "store derived metrics only" architecture is the legal path. Sent clarification email to developers@strava.com — no response yet. Building on derived-metrics-only architecture regardless.

---

Save this somewhere accessible. When you start a new claude.ai conversation for product/requirements questions, paste the relevant section rather than re-explaining from scratch.