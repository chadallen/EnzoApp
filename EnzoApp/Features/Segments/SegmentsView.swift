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
        VStack(spacing: 0) {
            GoalHeaderView(context: appState.athleteContext, fullWidth: true)
                .environment(appState)

            if !sortedSegments.isEmpty {
                sortBar
            }

            if sortedSegments.isEmpty {
                emptyState
            } else {
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
        }
        .navigationDestination(for: SegmentScore.self) { segment in
            SegmentDetailView(segment: segment)
        }
    }

    private var sortBar: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(order.rawValue) { sortOrder = order }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(.subheadline))
                    .foregroundStyle(Color.enzoAccent)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.enzoBg)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 48))
                .foregroundStyle(Color.enzoSecondary)
            Text("No segments yet")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoPrimary)
            Text("Enzo will find your best opportunities once your rides sync.")
                .font(.system(.body))
                .foregroundStyle(Color.enzoSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SegmentStrikeRow: View {
    let segment: SegmentScore
    @State private var isPulsing = false

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
                .scaleEffect(isPulsing ? 1.06 : 1.0)
                .animation(
                    segment.strikeLabel == "No brainer"
                        ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .onAppear { isPulsing = segment.strikeLabel == "No brainer" }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        SegmentsView()
            .environment(AppState())
    }
}
