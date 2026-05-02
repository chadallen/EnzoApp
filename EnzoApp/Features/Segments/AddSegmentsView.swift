import SwiftUI
import SwiftData

// MARK: - AddSegmentItem

/// A lightweight value type representing one unstarred segment row.
/// Populated once on sheet appear, then filtered/sorted in-view.
struct AddSegmentItem: Identifiable, Equatable {
    let segmentId: Int
    let name: String
    let distanceMeters: Double   // meters
    let avgGrade: Double         // percent
    let rideCount: Int           // derived from SegmentEffortModel count

    var id: Int { segmentId }

    var distanceMiles: String {
        String(format: "%.1f mi", distanceMeters * 0.000621371)
    }

    var gradeString: String {
        String(format: "%.1f%%", avgGrade)
    }
}

// MARK: - AddSegmentsView

struct AddSegmentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var items: [AddSegmentItem] = []
    @State private var searchText = ""
    @State private var sortOrder: SegmentSortOrder = .name
    @State private var selectedItem: AddSegmentItem? = nil
    @State private var starringId: Int? = nil   // segment ID currently being starred

    enum SegmentSortOrder: String, CaseIterable {
        case name = "Name A–Z"
        case distance = "Distance"
        case rideCount = "Ride Count"
    }

    // MARK: - Derived lists

    private var filteredItems: [AddSegmentItem] {
        let base: [AddSegmentItem]
        if searchText.isEmpty {
            base = items
        } else {
            base = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOrder {
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            return base.sorted { $0.distanceMeters < $1.distanceMeters }
        case .rideCount:
            return base.sorted { $0.rideCount > $1.rideCount }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                Group {
                    if items.isEmpty {
                        emptyState
                    } else if filteredItems.isEmpty {
                        noResultsState
                    } else {
                        segmentList
                    }
                }
            }
            .navigationTitle("Add Segments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.enzoAccent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !items.isEmpty {
                        sortMenu
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search segments")
            .sheet(item: $selectedItem) { item in
                SegmentStarSheet(
                    item: item,
                    isStarring: starringId == item.segmentId,
                    onStar: {
                        Task {
                            await starSegment(item)
                        }
                    }
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            loadItems()
        }
    }

    // MARK: - Subviews

    private var segmentList: some View {
        List {
            ForEach(filteredItems) { item in
                Button {
                    selectedItem = item
                } label: {
                    AddSegmentRow(item: item)
                }
                .listRowBackground(Color.enzoBg)
                .listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SegmentSortOrder.allCases, id: \.self) { order in
                Button(order.rawValue) { sortOrder = order }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(.subheadline))
                .foregroundStyle(Color.enzoAccent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.enzoSecondary)
            Text("You're all set")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoPrimary)
                .padding(.top, 4)
            Text("You have starred all your recent segments.")
                .font(.system(.subheadline))
                .foregroundStyle(Color.enzoSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Text("No segments match \"\(searchText)\"")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data loading

    private func loadItems() {
        let context = appState.modelContext

        let allSegments = (try? context.fetch(FetchDescriptor<StarredSegmentModel>())) ?? []
        let unstarred = allSegments.filter { !$0.isStarred }

        // Build a ride-count index from SegmentEffortModel
        let allEfforts = (try? context.fetch(FetchDescriptor<SegmentEffortModel>())) ?? []
        var rideCountBySegmentId: [Int: Int] = [:]
        for effort in allEfforts {
            rideCountBySegmentId[effort.segmentId, default: 0] += 1
        }

        items = unstarred.map { seg in
            AddSegmentItem(
                segmentId: seg.segmentId,
                name: seg.name,
                distanceMeters: seg.distance,
                avgGrade: seg.avgGrade,
                rideCount: rideCountBySegmentId[seg.segmentId] ?? 0
            )
        }
    }

    // MARK: - Star action

    private func starSegment(_ item: AddSegmentItem) async {
        guard starringId == nil else { return }
        starringId = item.segmentId
        selectedItem = nil   // dismiss the bottom sheet immediately

        await appState.starSegment(item.segmentId)

        // Remove from local list — starred segment disappears from this sheet
        items.removeAll { $0.segmentId == item.segmentId }
        starringId = nil
    }
}

// MARK: - AddSegmentRow

struct AddSegmentRow: View {
    let item: AddSegmentItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoPrimary)

                HStack(spacing: 8) {
                    Text(item.distanceMiles)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)

                    Text("·")
                        .font(.system(.caption2))
                        .foregroundStyle(Color.enzoSecondary.opacity(0.4))

                    let rideLabel = item.rideCount == 1 ? "1 ride" : "\(item.rideCount) rides"
                    Text(rideLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary.opacity(0.5))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - SegmentStarSheet

/// Condensed bottom sheet showing a single unstarred segment with a "Star this segment" CTA.
struct SegmentStarSheet: View {
    let item: AddSegmentItem
    let isStarring: Bool
    let onStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Segment card
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoPrimary)

                HStack(spacing: 16) {
                    statChip(label: "Distance", value: item.distanceMiles)
                    statChip(label: "Avg Grade", value: item.gradeString)
                    statChip(label: "Rides", value: "\(item.rideCount)")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

            // Star CTA
            Button {
                onStar()
            } label: {
                HStack(spacing: 8) {
                    if isStarring {
                        ProgressView()
                            .scaleEffect(0.85)
                            .tint(Color.enzoPrimary)
                    } else {
                        Image(systemName: "star.fill")
                            .font(.system(.subheadline))
                    }
                    Text(isStarring ? "Starring…" : "Star this segment")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.enzoAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.enzoPrimary)
            }
            .disabled(isStarring)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.enzoBg)
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoPrimary)
        }
    }
}

// MARK: - Previews

#Preview("Add Segments — list") {
    let items: [AddSegmentItem] = [
        AddSegmentItem(segmentId: 1, name: "Hawk Hill", distanceMeters: 2736, avgGrade: 5.4, rideCount: 12),
        AddSegmentItem(segmentId: 2, name: "Camino Alto Cutoff", distanceMeters: 980, avgGrade: 3.2, rideCount: 6),
        AddSegmentItem(segmentId: 3, name: "Paradise Loop Climb", distanceMeters: 4200, avgGrade: 7.8, rideCount: 3),
    ]
    AddSegmentsView_Preview(items: items)
}

#Preview("Add Segments — empty") {
    AddSegmentsView_Preview(items: [])
}

#Preview("Segment Star Sheet") {
    let item = AddSegmentItem(segmentId: 1, name: "Hawk Hill", distanceMeters: 2736, avgGrade: 5.4, rideCount: 12)
    SegmentStarSheet(item: item, isStarring: false, onStar: {})
        .presentationDetents([.height(280)])
        .background(Color.enzoBg)
}

/// Helper preview wrapper that drives AddSegmentsView with pre-seeded data via init injection.
private struct AddSegmentsView_Preview: View {
    let items: [AddSegmentItem]
    var body: some View {
        // Full integration previews require a real AppState+ModelContainer.
        // For layout/color previews we render the inner components directly.
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.enzoSecondary)
                        Text("You're all set")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.enzoPrimary)
                            .padding(.top, 4)
                        Text("You have starred all your recent segments.")
                            .font(.system(.subheadline))
                            .foregroundStyle(Color.enzoSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            AddSegmentRow(item: item)
                                .listRowBackground(Color.enzoBg)
                                .listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Add Segments")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
