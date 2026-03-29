# Enzo — Project Brief for Claude Code

## What This Is

Enzo is a personal iOS cycling companion that helps athletes know when to go for a segment PR. It connects to Strava, computes a relative fitness score from heart rate history, and uses an AI companion (also named Enzo) to narrate the athlete's training trajectory and surface the best moments to target PRs.

The full product spec is at `dev-data/enzo-spec.md`. Hardcoded preview data for Steps 1–5 is in Section 18 of the spec — use those exact values, do not invent placeholder data. Read it when you need detail on any feature, data model, or user journey. This file is the short version — orientation and hard rules.

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

---

## Project Structure

```
EnzoApp/                        ← repo root (open VS Code here)
├── EnzoApp.xcodeproj
├── EnzoApp/                    ← Xcode source files
│   ├── App/
│   │   ├── EnzoAppApp.swift
│   │   └── AppState.swift
│   ├── Features/
│   │   ├── Onboarding/         # Step 11 only — built last
│   │   ├── Arc/                # Main experience — built first
│   │   └── Segments/           # Full segment list tab
│   ├── Services/
│   │   ├── StravaService.swift
│   │   ├── ClaudeService.swift
│   │   ├── SupabaseService.swift
│   │   └── SyncService.swift
│   ├── Models/
│   ├── Utils/
│   │   ├── Config.swift        # xcconfig key accessors
│   │   ├── KeychainHelper.swift
│   │   ├── FitnessCalculator.swift
│   │   └── SegmentScorer.swift
│   └── Config/
│       ├── Debug.xcconfig      # gitignored — never commit
│       └── Release.xcconfig    # gitignored — never commit
├── CLAUDE.md
├── skills/
└── dev-data/
    └── enzo-spec.md            # Full product spec — read this for detail
```

---

## Current Build Status

> **Update this section as steps are completed.**

- [x] Step 1: Project setup, secrets infrastructure, 2-tab shell
- [x] Step 2: Arc UI (static, hardcoded data)
- [ ] Step 3: Claude API wired (hardcoded context)
- [ ] Step 4: Goal setting UI
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

---

## How to Work on This Project

**Starting a new session:** Read this file, check the build status above to know where we are, then read the relevant section of `dev-data/enzo-spec.md` for the step you're working on.

**If a requirement is unclear:** The spec is the source of truth. If the spec doesn't cover it, ask before building — don't infer.

**If something in the spec conflicts with what's already built:** Flag it. Don't silently pick one over the other.

**When a step is complete:** Mark it done in the build status above and commit.