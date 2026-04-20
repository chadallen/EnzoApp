---
date: 2026-04-20
status: accepted
---

# ADR-0008: Effort history stored as JSON string in SwiftData, not as a relationship

## Context

`SegmentScoreModel` (SwiftData `@Model`) needed to store the last 20 effort timestamps and durations per segment to power the effort history list in `SegmentDetailView`. Two approaches were considered:

**Option A: Separate `@Model` entity with `@Relationship`**
Add an `EffortHistoryModel` `@Model` class, with a `@Relationship(deleteRule: .cascade)` on `SegmentScoreModel`. Each effort becomes a row. Querying, sorting, and deleting are all handled by SwiftData.

**Option B: JSON-encoded `String` field (chosen)**
Add `var effortsJSON: String = "[]"` to `SegmentScoreModel`. `EffortRecord` is a plain `Codable` struct. Encode/decode at the callsite. Cap at 20 records during sync.

## Decision

Option B — JSON string field.

## Rationale

- **Read-only child data.** Efforts are written once during Phase 2 sync and read by the UI. They are never queried independently, filtered by date on the DB side, or updated in place. The cost of a relationship buys nothing.
- **Lightweight migration.** Adding a `String` field with a default value (`"[]"`) requires no schema version bump — SwiftData handles it automatically. A new `@Model` entity would require explicit migration or version management.
- **Simpler sync code.** `SyncService` builds efforts in-memory as `[EffortRecord]`, encodes to JSON, and writes one field. No SwiftData inserts, no cascade-delete logic, no actor-boundary issues with relationship traversal.
- **Bounded size.** Capped at 20 records per segment (~600 bytes worst case). Not a concern for SQLite storage.

## Consequences

- The `EffortRecord` struct must remain `Codable`. Schema changes to `EffortRecord` require a data migration strategy (re-sync clears old data, so this is acceptable).
- This pattern should be followed for any future read-only, bounded child data on `SegmentScoreModel` (e.g., pace history, weather snapshots).
- Do NOT use this pattern for data that needs to be queried, sorted, or related across model types — use a proper `@Model` entity for those.
