import SwiftUI
import Charts

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
            if appState.hasRealSegmentData && !sortedSegments.isEmpty {
                sortBar
            }

            if appState.isSyncing || appState.isSyncingPhase2 {
                loadingState
            } else if !appState.hasRealSegmentData {
                emptyState
            } else {
                List {
                    ForEach(sortedSegments) { segment in
                        NavigationLink(value: segment) {
                            SegmentStrikeRow(segment: segment)
                        }
                        .listRowBackground(Color.enzoBg)
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
            Text("Explore more segments")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .kerning(0.4)
                .padding(.leading)

            Spacer()

            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(order.rawValue) { sortOrder = order }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(.subheadline))
                    .foregroundStyle(Color.enzoAccent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal)
        }
        .background(Color.enzoBg)
    }

    private var loadingState: some View {
        SegmentLoadingView()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 48))
                .foregroundStyle(Color.enzoSecondary)
            Text("Sync to see your segments")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoPrimary)
                .padding(.top, 4)
            Text("Enzo will rank your PR opportunities once your ride history loads.")
                .font(.system(.subheadline))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func readinessColor(for score: Double) -> Color {
        switch score {
        case 0.80...:       return .enzoGoal
        case 0.65..<0.80:   return .enzoChartPrimary
        case 0.45..<0.65:   return .enzoAmber
        default:            return .enzoSecondary
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

                    if let dist = segment.distanceMeters {
                        Text("·")
                            .font(.system(.caption2))
                            .foregroundStyle(Color.enzoSecondary.opacity(0.4))
                        Text(String(format: "%.1f mi", dist * 0.000621371))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                    }

                    if let elev = segment.elevationDeltaMeters {
                        Text("·")
                            .font(.system(.caption2))
                            .foregroundStyle(Color.enzoSecondary.opacity(0.4))
                        Text(String(format: "+%.0f ft", elev * 3.28084))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                    }
                }
            }

            Spacer()

            ZStack {
                Chart {
                    SectorMark(
                        angle: .value("Readiness", segment.strikeScore),
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .foregroundStyle(readinessColor(for: segment.strikeScore))

                    SectorMark(
                        angle: .value("Remaining", max(0.001, 1.0 - segment.strikeScore)),
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .foregroundStyle(readinessColor(for: segment.strikeScore).opacity(0.12))
                }
                .chartLegend(.hidden)
                .frame(width: 44, height: 44)

                Text("\(Int(segment.strikeScore * 100))")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(readinessColor(for: segment.strikeScore))
            }
            .scaleEffect(isPulsing ? 1.06 : 1.0)
            .animation(
                segment.strikeLabel == "Strike now" && !reduceMotion
                    ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = segment.strikeLabel == "Strike now" && !reduceMotion }
        }
        .padding(.vertical, 6)
    }
}

struct SegmentLoadingView: View {
    @State private var phraseIndex: Int = 0

    private let phrases = [
        "Getting your segments…",
        "Analyzing your PR history…",
        "Calculating your strike scores…",
        "Ranking your best opportunities…",
        "Almost there…"
    ]

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.enzoSecondary)
            Text(phrases[phraseIndex])
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
                .id(phraseIndex)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeInOut(duration: 0.4)) {
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
    }
}

#Preview("Segments") {
    NavigationStack {
        SegmentsView()
            .environment(AppState())
    }
}

#Preview("Loading") {
    SegmentLoadingView()
        .background(Color.enzoBg)
}
