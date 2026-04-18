# ADR-0002: @Observable + async/await over Combine

**Date:** 2026-04-17
**Status:** Accepted

## Context

iOS state management and async work can be handled via Combine (reactive streams, publishers/subscribers) or the newer `@Observable` macro + Swift concurrency (`async/await`, `AsyncStream`). Combine is more established but more complex; `@Observable` + async/await is simpler, more readable, and the direction Apple is pushing for iOS 17+.

## Decision

Use `@Observable` for all state management and `async/await` / `AsyncStream` for all async work. Combine is explicitly prohibited in this codebase.

## Consequences

- Code is more readable and linear; easier to reason about
- Requires iOS 17+ (acceptable — this is the project minimum)
- Claude API streaming is handled via `AsyncStream` in `ClaudeService`
- No Combine knowledge required for contributors
- Cannot use Combine-based third-party libraries (not an issue — no third-party UI libraries are used)
