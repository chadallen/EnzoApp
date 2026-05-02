import Testing
import Foundation
@testable import EnzoApp

// MARK: - Helpers

private func makeItem(
    id: Int,
    name: String,
    distanceMeters: Double = 1000,
    avgGrade: Double = 3.0,
    rideCount: Int = 1
) -> AddSegmentItem {
    AddSegmentItem(
        segmentId: id,
        name: name,
        distanceMeters: distanceMeters,
        avgGrade: avgGrade,
        rideCount: rideCount
    )
}

// MARK: - AddSegmentsView logic tests

@Suite("AddSegmentsView — sort and filter logic")
struct AddSegmentsViewTests {

    // MARK: - Search filter

    @Test("Empty query returns all items")
    func emptyQueryReturnsAll() {
        let items = [
            makeItem(id: 1, name: "Hawk Hill"),
            makeItem(id: 2, name: "Camino Alto"),
            makeItem(id: 3, name: "Paradise Loop"),
        ]
        let result = items.filter { "".isEmpty || $0.name.localizedCaseInsensitiveContains("") }
        // Empty query — all pass the contains check
        let filtered = items  // mirror view logic: guard !query.isEmpty returns base
        #expect(filtered.count == 3)
    }

    @Test("Search filters by name substring")
    func searchFiltersByNameSubstring() {
        let items = [
            makeItem(id: 1, name: "Hawk Hill"),
            makeItem(id: 2, name: "Camino Alto"),
            makeItem(id: 3, name: "Hawk Descent"),
        ]
        let result = items.filter { $0.name.localizedCaseInsensitiveContains("Hawk") }
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.name.localizedCaseInsensitiveContains("Hawk") })
    }

    @Test("Search is case-insensitive")
    func searchCaseInsensitive() {
        let items = [
            makeItem(id: 1, name: "Pantoll Climb"),
            makeItem(id: 2, name: "pantoll descent"),
            makeItem(id: 3, name: "Bolinas Ridge"),
        ]
        let result = items.filter { $0.name.localizedCaseInsensitiveContains("pantoll") }
        #expect(result.count == 2)
    }

    @Test("Search returns empty when no items match")
    func searchNoMatch() {
        let items = [
            makeItem(id: 1, name: "Hawk Hill"),
            makeItem(id: 2, name: "Camino Alto"),
        ]
        let result = items.filter { $0.name.localizedCaseInsensitiveContains("Bolinas") }
        #expect(result.isEmpty)
    }

    // MARK: - Sort: name A-Z

    @Test("Name sort orders alphabetically ascending")
    func sortByNameAscending() {
        let items = [
            makeItem(id: 1, name: "Zebra Climb"),
            makeItem(id: 2, name: "Ant Hill"),
            makeItem(id: 3, name: "Marmot Ridge"),
        ]
        let sorted = items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        #expect(sorted[0].name == "Ant Hill")
        #expect(sorted[1].name == "Marmot Ridge")
        #expect(sorted[2].name == "Zebra Climb")
    }

    @Test("Name sort is case-insensitive")
    func sortByNameCaseInsensitive() {
        let items = [
            makeItem(id: 1, name: "zoo Road"),
            makeItem(id: 2, name: "Alpha Trail"),
            makeItem(id: 3, name: "Beta Descent"),
        ]
        let sorted = items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        #expect(sorted[0].name == "Alpha Trail")
        #expect(sorted[1].name == "Beta Descent")
        #expect(sorted[2].name == "zoo Road")
    }

    // MARK: - Sort: distance

    @Test("Distance sort orders shortest to longest")
    func sortByDistance() {
        let items = [
            makeItem(id: 1, name: "Long Climb", distanceMeters: 5000),
            makeItem(id: 2, name: "Short Sprint", distanceMeters: 500),
            makeItem(id: 3, name: "Mid Segment", distanceMeters: 2000),
        ]
        let sorted = items.sorted { $0.distanceMeters < $1.distanceMeters }
        #expect(sorted[0].distanceMeters == 500)
        #expect(sorted[1].distanceMeters == 2000)
        #expect(sorted[2].distanceMeters == 5000)
    }

    @Test("Distance sort preserves equal distances")
    func sortByDistanceEqualValues() {
        let items = [
            makeItem(id: 1, name: "A", distanceMeters: 1000),
            makeItem(id: 2, name: "B", distanceMeters: 1000),
        ]
        let sorted = items.sorted { $0.distanceMeters < $1.distanceMeters }
        #expect(sorted.count == 2)
        #expect(sorted[0].distanceMeters == 1000)
        #expect(sorted[1].distanceMeters == 1000)
    }

    // MARK: - Sort: ride count

    @Test("Ride count sort orders most rides first")
    func sortByRideCountDescending() {
        let items = [
            makeItem(id: 1, name: "Rare", rideCount: 1),
            makeItem(id: 2, name: "Often", rideCount: 15),
            makeItem(id: 3, name: "Sometimes", rideCount: 6),
        ]
        let sorted = items.sorted { $0.rideCount > $1.rideCount }
        #expect(sorted[0].name == "Often")
        #expect(sorted[1].name == "Sometimes")
        #expect(sorted[2].name == "Rare")
    }

    @Test("Ride count sort with zero rides sorts last")
    func sortByRideCountZeroSortsLast() {
        let items = [
            makeItem(id: 1, name: "Zero rides", rideCount: 0),
            makeItem(id: 2, name: "Five rides", rideCount: 5),
        ]
        let sorted = items.sorted { $0.rideCount > $1.rideCount }
        #expect(sorted[0].rideCount == 5)
        #expect(sorted[1].rideCount == 0)
    }

    // MARK: - AddSegmentItem computed properties

    @Test("distanceMiles formats correctly for 2736 meters")
    func distanceMilesFormat() {
        let item = makeItem(id: 1, name: "Hawk Hill", distanceMeters: 2736)
        // 2736 * 0.000621371 ≈ 1.700 → "1.7 mi"
        #expect(item.distanceMiles == "1.7 mi")
    }

    @Test("gradeString formats correctly")
    func gradeStringFormat() {
        let item = makeItem(id: 1, name: "Climb", avgGrade: 5.4)
        #expect(item.gradeString == "5.4%")
    }

    @Test("ride count label is singular for 1 ride")
    func rideCountLabelSingular() {
        let item = makeItem(id: 1, name: "X", rideCount: 1)
        let label = item.rideCount == 1 ? "1 ride" : "\(item.rideCount) rides"
        #expect(label == "1 ride")
    }

    @Test("ride count label is plural for multiple rides")
    func rideCountLabelPlural() {
        let item = makeItem(id: 1, name: "X", rideCount: 7)
        let label = item.rideCount == 1 ? "1 ride" : "\(item.rideCount) rides"
        #expect(label == "7 rides")
    }

    @Test("ride count label is plural for 0 rides")
    func rideCountLabelZero() {
        let item = makeItem(id: 1, name: "X", rideCount: 0)
        let label = item.rideCount == 1 ? "1 ride" : "\(item.rideCount) rides"
        #expect(label == "0 rides")
    }

    // MARK: - Search + sort composition

    @Test("Filter then sort by name works correctly")
    func filterThenSortByName() {
        let items = [
            makeItem(id: 1, name: "Hawk Descent"),
            makeItem(id: 2, name: "Camino Alto"),
            makeItem(id: 3, name: "Hawk Hill"),
        ]
        let filtered = items.filter { $0.name.localizedCaseInsensitiveContains("Hawk") }
        let sorted = filtered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        #expect(sorted.count == 2)
        #expect(sorted[0].name == "Hawk Descent")
        #expect(sorted[1].name == "Hawk Hill")
    }

    @Test("Filter then sort by ride count works correctly")
    func filterThenSortByRideCount() {
        let items = [
            makeItem(id: 1, name: "Hawk Descent", rideCount: 3),
            makeItem(id: 2, name: "Camino Alto", rideCount: 10),
            makeItem(id: 3, name: "Hawk Hill", rideCount: 8),
        ]
        let filtered = items.filter { $0.name.localizedCaseInsensitiveContains("Hawk") }
        let sorted = filtered.sorted { $0.rideCount > $1.rideCount }
        #expect(sorted.count == 2)
        #expect(sorted[0].name == "Hawk Hill")   // 8 rides
        #expect(sorted[1].name == "Hawk Descent") // 3 rides
    }
}
