# ADR-0006: Strava as sole authentication and data source

**Date:** 2026-04-17
**Status:** Accepted

## Context

Enzo needs both authentication (who is the user?) and training data (what have they ridden?). Options: build a custom auth system + manual data entry, integrate multiple fitness platforms, or use Strava OAuth as both auth and data source.

Nearly all serious cyclists already have Strava accounts with years of activity history, including HR data and segment efforts. Strava's OAuth token serves as both user identity and data access credential.

## Decision

Strava OAuth 2.0 is the sole authentication mechanism and data source. No other login methods. No power meter data (deliberately excluded for model consistency — HR-based efficiency is the fitness signal). Identity is stored as `strava_athlete_id` in the iOS Keychain.

## Consequences

- Users must have a Strava account — this is acceptable for the cycling companion target audience
- No custom user management, no remote user table
- Required scopes: `activity:read_all` (full history + HR), `read` (athlete profile)
- Redirect URI is `enzo://oauth`; Strava callback domain must be `oauth`
- Power meter data is intentionally excluded to keep the fitness model consistent across users who do and don't have power meters
