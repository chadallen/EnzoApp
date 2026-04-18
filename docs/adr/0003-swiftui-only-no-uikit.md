# ADR-0003: SwiftUI-only, no UIKit

**Date:** 2026-04-17
**Status:** Accepted

## Context

iOS apps can be built with UIKit (imperative, long-established), SwiftUI (declarative, iOS 13+), or a mix. SwiftUI requires less boilerplate, integrates naturally with `@Observable`, and is Apple's stated direction. UIKit provides more fine-grained control but at significant complexity cost. Mixing the two layers adds cognitive overhead.

## Decision

SwiftUI only. No UIKit. No third-party UI libraries. iOS 17+ minimum target.

## Consequences

- All views use SwiftUI primitives; no `UIViewRepresentable` wrappers needed
- Swift Charts (also SwiftUI-native) is the only data visualization library
- iOS 17+ minimum target is required and acceptable for the cycling companion use case
- Some advanced UIKit behaviors (e.g., fine-grained scroll control) require workarounds, but none have been needed so far
