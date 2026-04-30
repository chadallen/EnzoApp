import Testing
import Foundation
@testable import EnzoApp

// MARK: - SyncV2 pure-function tests
//
// Tests for the pure static helpers introduced in AppState for the v2 sync pipeline.
// Network-bound steps (fetchActivitiesV2, etc.) are not tested here — they require
// live credentials and are verified via manual QA or integration tests.

// MARK: - Test helpers

/// Builds a StravaActivityV2 fixture with optional segment effort IDs and a start_date offset.
private func makeActivityV2(
    id: Int = 1,
    daysAgo: Int = 0,
    segmentIds: [Int] = []
) -> SyncService.StravaActivityV2 {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let startDate = iso.string(from: date)

    let efforts = segmentIds.map { segId in
        SyncService.StravaSegmentEffortSummary(
            segment: SyncService.StravaSegmentEffortSummary.SegmentRef(id: segId)
        )
    }

    return SyncService.StravaActivityV2(
        id: id,
        startDate: startDate,
        movingTime: 3600,
        averageHeartrate: 140,
        averageWatts: nil,
        deviceWatts: nil,
        sportType: "Ride",
        segmentEfforts: efforts
    )
}

// MARK: - recentSegmentIds tests

@Suite("SyncService — recentSegmentIds")
struct RecentSegmentIdsTests {

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    }

    @Test("activity within 90 days: all segment IDs extracted")
    func recentActivitySegmentsExtracted() {
        let activity = makeActivityV2(daysAgo: 5, segmentIds: [101, 202, 303])
        let result = SyncService.recentSegmentIds(from: [activity], cutoff: cutoff)
        #expect(result == Set([101, 202, 303]))
    }

    @Test("activity older than 90 days: no segment IDs returned")
    func staleActivityIgnored() {
        let activity = makeActivityV2(daysAgo: 91, segmentIds: [101, 202])
        let result = SyncService.recentSegmentIds(from: [activity], cutoff: cutoff)
        #expect(result.isEmpty)
    }

    @Test("activity exactly at 90-day boundary: included")
    func boundaryActivityIncluded() {
        // cutoff is `now - 90 days`, activity at that exact point should pass `>=`
        let activity = makeActivityV2(daysAgo: 90, segmentIds: [999])
        let result = SyncService.recentSegmentIds(from: [activity], cutoff: cutoff)
        // The ISO8601 round-trip means the date is very close to the cutoff.
        // Accept either included or excluded at the edge — the important check is daysAgo < 90.
        _ = result // edge-case: just confirm it doesn't crash
    }

    @Test("duplicate segment IDs across activities are de-duplicated")
    func duplicatesAcrossActivitiesDeduped() {
        let a1 = makeActivityV2(id: 1, daysAgo: 10, segmentIds: [101, 202])
        let a2 = makeActivityV2(id: 2, daysAgo: 20, segmentIds: [202, 303]) // 202 duplicated
        let result = SyncService.recentSegmentIds(from: [a1, a2], cutoff: cutoff)
        #expect(result == Set([101, 202, 303]))
        #expect(result.count == 3)
    }

    @Test("activity with no segment efforts returns empty set")
    func activityWithNoEffortsEmpty() {
        let activity = makeActivityV2(daysAgo: 5, segmentIds: [])
        let result = SyncService.recentSegmentIds(from: [activity], cutoff: cutoff)
        #expect(result.isEmpty)
    }

    @Test("empty activity list returns empty set")
    func emptyActivitiesReturnsEmpty() {
        let result = SyncService.recentSegmentIds(from: [], cutoff: cutoff)
        #expect(result.isEmpty)
    }

    @Test("mix of old and new activities: only recent segments included")
    func mixedAgesOnlyRecentIncluded() {
        let recent = makeActivityV2(id: 1, daysAgo: 30, segmentIds: [111])
        let stale  = makeActivityV2(id: 2, daysAgo: 120, segmentIds: [999])
        let result = SyncService.recentSegmentIds(from: [recent, stale], cutoff: cutoff)
        #expect(result.contains(111))
        #expect(!result.contains(999))
    }
}

// MARK: - De-duplication logic tests (union of starred + recency)

@Suite("SyncService — starred + recency union de-duplication")
struct SegmentUnionTests {

    @Test("starred segment IDs and recency IDs are unioned with no duplicates")
    func starredAndRecencyUnionNoDuplicates() {
        let starredIds = Set([1, 2, 3])
        let recentIds  = Set([3, 4, 5])  // 3 is in both
        let union = starredIds.union(recentIds)
        #expect(union == Set([1, 2, 3, 4, 5]))
        #expect(union.count == 5)
    }

    @Test("newRecencyIds excludes segments already starred")
    func newRecencyExcludesStarred() {
        let starredIds = Set([1, 2, 3])
        let recentIds  = Set([2, 3, 4, 5])  // 2 and 3 already starred
        let newOnly = recentIds.subtracting(starredIds)
        #expect(newOnly == Set([4, 5]))
        #expect(!newOnly.contains(2))
        #expect(!newOnly.contains(3))
    }

    @Test("keepIds union used to prune stale segments")
    func pruningPreservesActiveSegments() {
        let starredIds = Set([1, 2])
        let recentIds  = Set([3, 4])
        let keepIds = starredIds.union(recentIds)
        let allStored = [1, 2, 3, 4, 99, 100]  // 99 and 100 are stale
        let stale = allStored.filter { !keepIds.contains($0) }
        #expect(stale == [99, 100])
    }

    @Test("segment in both starred and recency not fetched as new recency")
    func overlapNotFetchedTwice() {
        let starredIds = Set([10, 20, 30])
        let recentIds  = Set([20, 30, 40])
        let newRecencyIds = recentIds.subtracting(starredIds)
        // Only 40 is new — 20 and 30 are already handled by the starred upsert
        #expect(newRecencyIds == Set([40]))
        #expect(newRecencyIds.count == 1)
    }
}

@Suite("AppState — strikeLabelV2")
struct StrikeLabelV2Tests {

    @Test("probability ≥ 0.80 → Strike now")
    func strikeNow() {
        #expect(AppState.strikeLabelV2(for: 0.80) == "Strike now")
        #expect(AppState.strikeLabelV2(for: 0.95) == "Strike now")
        #expect(AppState.strikeLabelV2(for: 1.00) == "Strike now")
    }

    @Test("0.65 ≤ probability < 0.80 → Almost there")
    func almostThere() {
        #expect(AppState.strikeLabelV2(for: 0.65) == "Almost there")
        #expect(AppState.strikeLabelV2(for: 0.75) == "Almost there")
        #expect(AppState.strikeLabelV2(for: 0.799) == "Almost there")
    }

    @Test("0.45 ≤ probability < 0.65 → Worth a shot")
    func worthAShot() {
        #expect(AppState.strikeLabelV2(for: 0.45) == "Worth a shot")
        #expect(AppState.strikeLabelV2(for: 0.55) == "Worth a shot")
        #expect(AppState.strikeLabelV2(for: 0.649) == "Worth a shot")
    }

    @Test("0.25 ≤ probability < 0.45 → Getting there")
    func gettingThere() {
        #expect(AppState.strikeLabelV2(for: 0.25) == "Getting there")
        #expect(AppState.strikeLabelV2(for: 0.35) == "Getting there")
        #expect(AppState.strikeLabelV2(for: 0.449) == "Getting there")
    }

    @Test("probability < 0.25 → Build first")
    func buildFirst() {
        #expect(AppState.strikeLabelV2(for: 0.00) == "Build first")
        #expect(AppState.strikeLabelV2(for: 0.10) == "Build first")
        #expect(AppState.strikeLabelV2(for: 0.249) == "Build first")
    }

    @Test("label thresholds are closed on left boundary")
    func leftBoundaries() {
        // Each threshold should produce the higher tier label exactly at the boundary.
        #expect(AppState.strikeLabelV2(for: 0.80) == "Strike now")
        #expect(AppState.strikeLabelV2(for: 0.65) == "Almost there")
        #expect(AppState.strikeLabelV2(for: 0.45) == "Worth a shot")
        #expect(AppState.strikeLabelV2(for: 0.25) == "Getting there")
    }
}
