# Handoff — Session ending 2026-03-29

## What was completed this session

Step 5: Supabase schema + models (commits 26126da → c64f6e9)

- `26126da` — Added `FitnessSnapshotRow` Codable DTO (`Models/FitnessSnapshot+Supabase.swift`)
- `92a86e3` — Added `SegmentScoreRow` Codable DTO (`Models/SegmentScore+Supabase.swift`)
- `7656a4a` — Added `GoalRow` Codable DTO (`Models/Goal+Supabase.swift`)
- `d4acf7e` — Created `SupabaseService` actor with REST read/write for fitness_snapshots, segment_scores, goals
- `2e32e16` — `SupabaseServiceTests.swift`: 9 Codable unit tests + integration test (gated behind env var)
- `c64f6e9` — Marked Step 5 complete in CLAUDE.md

Build succeeds. 19 tests pass (was 10, now 19). Supabase tables exist and are accessible. Integration test confirmed working after exporting `SUPABASE_INTEGRATION_TESTS=1` then running xcodebuild.

---

## What comes next: Step 6 — Strava OAuth

### Before writing any code, read these in order

1. **`CLAUDE.md`** — full orientation, build notes (especially the Strava client ID note at the bottom), hard rules
2. **`PRD.MD` Section 6** — Strava OAuth flow details, redirect URI, token storage, athlete profile fetch
3. **`PRD.MD` Section 17** — build order, Step 6 definition
4. **`skills/swift-patterns.MD`** — service layer patterns
5. **`skills/testing.md`** — acceptance criteria: Step 6 requires access token stored in Keychain + athlete profile fetched

### What Step 6 involves

**Before writing any code — confirm with Chad:**
- `STRAVA_CLIENT_ID` is currently empty in `Config/Debug.xcconfig`. Chad needs to add it. Find it in the Strava API settings for the app (developers.strava.com → My API Application).
- The Strava app must have a redirect URI registered. The standard iOS pattern is a custom URL scheme like `enzo://strava-oauth`. Confirm Chad's registered redirect URI.

**Swift side:**
- `StravaService.swift` — already a placeholder in `Services/`. Fill it in as a Swift `actor`, same pattern as `ClaudeService` and `SupabaseService`.
- `KeychainHelper.swift` — already a placeholder in `Utils/`. Implement `save(_:for:)`, `load(for:)`, `delete(for:)` using `Security` framework (`kSecClassGenericPassword`).
- OAuth flow:
  1. Build the Strava authorization URL with `client_id`, `redirect_uri`, `response_type=code`, `scope=read,activity:read_all`
  2. Open it via `ASWebAuthenticationSession` (no SFSafariViewController — ASWebAuth is the correct iOS pattern for OAuth)
  3. Capture the `code` from the redirect URI callback
  4. Exchange `code` for `access_token` + `refresh_token` via POST to `https://www.strava.com/oauth/token`
  5. Store both tokens in Keychain via `KeychainHelper`
  6. Fetch athlete profile: `GET https://www.strava.com/api/v3/athlete` with `Authorization: Bearer <access_token>`
  7. Create a `users` row in Supabase with `strava_athlete_id` and `display_name`
- Token refresh: implement `refreshTokenIfNeeded()` — check expiry before every Strava API call, refresh if expired using the refresh token

**AppState wiring:**
- Add `isAuthenticated: Bool` and `stravaAthleteId: Int?` to `AppState`
- The app still launches into ArcView (no auth gating yet — that's Step 11 Onboarding)
- Step 6 just establishes that auth works; the UI doesn't change

**Testing:**
- `KeychainHelperTests.swift` — unit test save/load/delete round-trip
- `StravaServiceTests.swift` — unit test URL construction, token parsing

### Key things to NOT do in Step 6
- Don't build an onboarding screen yet — that's Step 11
- Don't start syncing activities yet — that's Step 7
- Don't change the app's launch flow — still goes directly to ArcView

### Acceptance criteria (from skills/testing.md)
- Access token stored in Keychain after OAuth flow completes
- Athlete profile fetched and `display_name` + `strava_athlete_id` accessible
- `users` row created in Supabase

---

## Bugs carried forward (do not fix in Step 6)

- `GoalSettingView` preview for the "segment selected" state uses placeholder Enzo copy — fix in Step 11 Enzo voice review
- `AppState.setGoal` sets `requiredFitnessValue = segment.fitnessValueAtPR` directly, so Hawk Hill shows "Epic fitness needed" instead of "Strong" — fix in Step 9 when `SegmentScorer` is built

---

## Decisions from this session (recorded in CLAUDE.md Build Notes)

- `SupabaseService` uses URLSession REST directly (no SDK) — same pattern as ClaudeService
- Codable row DTOs live in `+Supabase.swift` extension files alongside domain models
- `FitnessSnapshot.month` stored as "YYYY-MM-01" in Postgres (date type), trimmed back to "YYYY-MM" on read
- RLS is disabled on all Supabase tables (dev-only) — will add policies in Step 6 scoped to authenticated users
- Integration test env var must be `export`ed in shell before xcodebuild; `VAR=value xcodebuild` prefix doesn't reach the simulator process; `-testenv` flag is not valid on this Xcode version

---

## First file to open

```
CLAUDE.md
```

Then ask Chad for `STRAVA_CLIENT_ID` and the registered redirect URI before opening any Swift files.
