import SwiftUI
import Charts

/// Navigation value used by SegmentsView and HeroSegmentCard.
enum SegmentNavigation: Hashable {
    case detail(SegmentScore)
    case detailWithChat(SegmentScore)
}

struct SegmentsView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: SortOrder = .strikeScore
    @AppStorage("hasSeenSegmentHint") private var hasSeenSegmentHint = false

    enum SortOrder: String, CaseIterable {
        case strikeScore = "Strike Score"
        case alphabetical = "Alphabetical"
        case prDate = "PR Date"
    }

    private var heroSegment: SegmentScore? {
        appState.segments.first(where: { $0.isGoalSegment })
    }

    private var showHintCard: Bool {
        !hasSeenSegmentHint &&
        appState.hasRealSegmentData &&
        heroSegment == nil
    }

    // Goal segment is shown in the hero card — exclude it from the list below.
    private var sortedSegments: [SegmentScore] {
        let source = appState.segments.filter { !$0.isGoalSegment }
        switch sortOrder {
        case .strikeScore:  return source.sorted { $0.strikeScore > $1.strikeScore }
        case .alphabetical: return source.sorted { $0.name < $1.name }
        case .prDate:       return source.sorted { $0.prDate > $1.prDate }
        }
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
                    if let goal = heroSegment {
                        HeroSegmentCard(segment: goal)
                            .listRowBackground(Color.enzoBg)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    if showHintCard {
                        segmentHintCard
                            .listRowBackground(Color.enzoBg)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
                    }
                    ForEach(sortedSegments) { segment in
                        NavigationLink(value: SegmentNavigation.detail(segment)) {
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
        .navigationDestination(for: SegmentNavigation.self) { nav in
            switch nav {
            case .detail(let seg):
                SegmentDetailView(segment: seg)
            case .detailWithChat(let seg):
                SegmentDetailView(segment: seg, autoStartChat: true)
            }
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

    private var segmentHintCard: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tap a segment to see your readiness.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.enzoPrimary)
                Text("Star one to make it your target.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
            }
            Spacer()
            Button {
                hasSeenSegmentHint = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.enzoSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.enzoAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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

            StrikeScoreDonut(score: segment.strikeScore, label: segment.strikeLabel, size: 44)
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
