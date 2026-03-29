import SwiftUI

struct SegmentsView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: SortOrder = .strikeScore

    enum SortOrder: String, CaseIterable {
        case strikeScore = "Strike Score"
        case alphabetical = "Alphabetical"
        case prDate = "PR Date"
    }

    private var sortedSegments: [SegmentScore] {
        let goal = appState.segments.filter { $0.isGoalSegment }
        let rest: [SegmentScore]
        switch sortOrder {
        case .strikeScore:
            rest = appState.segments.filter { !$0.isGoalSegment }.sorted { $0.strikeScore > $1.strikeScore }
        case .alphabetical:
            rest = appState.segments.filter { !$0.isGoalSegment }.sorted { $0.name < $1.name }
        case .prDate:
            rest = appState.segments.filter { !$0.isGoalSegment }.sorted { $0.prDate > $1.prDate }
        }
        return goal + rest
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                List {
                    ForEach(sortedSegments) { segment in
                        NavigationLink(value: segment) {
                            SegmentStrikeRow(segment: segment)
                        }
                        .listRowBackground(Color.enzoCard)
                        .listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Segments")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.enzoBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button(order.rawValue) { sortOrder = order }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(Color.enzoAccent)
                    }
                }
            }
            .navigationDestination(for: SegmentScore.self) { segment in
                SegmentDetailView(segment: segment)
            }
        }
    }
}

struct SegmentStrikeRow: View {
    let segment: SegmentScore

    private var pillColor: Color {
        switch segment.strikeScore {
        case 0.70...: return .enzoGoal
        case 0.45..<0.70: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(segment.name)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoPrimary)
                    if segment.isGoalSegment {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.enzoAccent)
                    }
                }

                HStack(spacing: 8) {
                    Text("PR \(segment.prFormatted)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.enzoSecondary)

                    let arrow = segment.trendDirection == "up" ? "↑" : segment.trendDirection == "down" ? "↓" : "→"
                    Text(arrow)
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(segment.trendDirection == "up" ? Color.enzoGoal : Color.enzoSecondary)
                }
            }

            Spacer()

            Text(segment.strikeLabel)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(pillColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(pillColor.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    SegmentsView()
        .environment(AppState())
}
