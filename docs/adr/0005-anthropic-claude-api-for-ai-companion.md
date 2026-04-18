# ADR-0005: Anthropic Claude API for AI companion

**Date:** 2026-04-17
**Status:** Accepted

## Context

The app's AI companion ("Enzo") needs to generate natural-language training assessments and respond to follow-up questions about specific segments. Options considered: on-device models (Core ML), OpenAI API, Anthropic Claude API.

On-device models lack the reasoning quality needed for nuanced coaching language. OpenAI is a viable alternative but requires different SDK/streaming patterns. Anthropic Claude was selected for response quality and streaming API support.

## Decision

Use the Anthropic Claude API (`claude-sonnet-4-6`) for all AI companion features. Streaming via `AsyncStream`. The user-facing persona is always "Enzo" — never "Claude", "AI", or "assistant" in any UI copy or error messages.

## Consequences

- Requires `ANTHROPIC_API_KEY` in xcconfig (never hardcoded)
- Streaming handled in `Services/ClaudeService.swift` as a Swift actor
- Prompt iteration via `scripts/enzo_playground.py` before touching code
- API costs are per-token; usage is bounded by segment chat sessions (not background polling)
- Model upgrades (`claude-sonnet-4-6` → future versions) are a single constant change in `ClaudeService`
