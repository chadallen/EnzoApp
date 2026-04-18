# ADR-0001: SwiftData over Supabase for persistence

**Date:** 2026-04-17
**Status:** Accepted

## Context

Enzo needs to persist derived fitness metrics and segment scores between sessions. Early development used Supabase (remote PostgreSQL via REST API) as the persistence layer. This required a network connection to read/write data, introduced latency on app launch, added complexity around RLS policies, and stored user-derived data on a remote server.

The alternative was on-device SQLite via SwiftData, Apple's first-party persistence framework introduced in iOS 17.

## Decision

Replace Supabase with SwiftData for all persistence. Derived metrics are written to the local device only. Raw Strava data is never persisted anywhere — computed in-memory and discarded.

## Consequences

- No remote backend required; app works fully offline after initial Strava sync
- User data stays on-device; simpler privacy posture
- No RLS policies, no API keys for persistence layer
- Migration was completed as a dedicated step (see `docs/migration-supabase-to-swiftdata.md`)
- Data is not synced across devices (acceptable for MVP cycling companion)
- Identity is Strava athlete ID in Keychain only — no remote user table
