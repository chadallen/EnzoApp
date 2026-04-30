import SwiftUI
import Charts

/// Navigation value used by SegmentsView and HeroSegmentCard.
enum SegmentNavigation: Hashable {
    case detail(SegmentScore)
    case detailWithChat(SegmentScore)
}

struct SegmentsView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: SortOrder = .prProbability
    @State private var searchText = ""
    @State private var showStarredOnly: Bool = false
    @AppStorage("hasSeenSegmentHint") private var hasSeenSegmentHint = false

    enum SortOrder: String, CaseIterable {
        case prProbability = "PR Probability"
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
    // When showStarredOnly is true, further narrow to starred segments.
    private var sortedSegments: [SegmentScore] {
        let base = appState.segments.filter { !$0.isGoalSegment }
        let source = showStarredOnly ? base.filter { $0.isStarred } : base
        switch sortOrder {
        case .prProbability: return source.sorted { ($0.prProbability ?? $0.strikeScore) > ($1.prProbability ?? $1.strikeScore) }
        case .alphabetical: return source.sorted { $0.name < $1.name }
        case .prDate:       return source.sorted { $0.prDate > $1.prDate }
        }
    }

    private static let tierOrder = ["Strike now", "Almost there", "Worth a shot", "Getting there", "Build first"]

    private var tieredSegments: [(tier: String, segments: [SegmentScore])] {
        let grouped = Dictionary(grouping: sortedSegments, by: \.strikeLabel)
        return Self.tierOrder.compactMap { tier in
            guard let segs = grouped[tier], !segs.isEmpty else { return nil }
            return (tier: tier, segments: segs)
        }
    }

    private var isSyncing: Bool { appState.isSyncing }

    private var isSearching: Bool { !searchText.isEmpty }

    /// All segments (including goal) filtered by searchText and starred filter. Used only when isSearching.
    private var filteredSegments: [SegmentScore] {
        let candidates = showStarredOnly
            ? appState.segments.filter { $0.isStarred || $0.isGoalSegment }
            : appState.segments
        return SegmentScore.filter(candidates, by: searchText)
            .sorted { ($0.prProbability ?? $0.strikeScore) > ($1.prProbability ?? $1.strikeScore) }
    }

    /// Whether any segments exist that can be starred-filtered (used to show the filter control).
    private var hasStarredSegments: Bool {
        appState.segments.contains { $0.isStarred || $0.isGoalSegment }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSearching && appState.hasRealSegmentData {
                if hasStarredSegments {
                    starFilterBar
                }
                if !sortedSegments.isEmpty {
                    sortBar
                }
            }

            // Full-screen spinner only on first load (no data yet).
            // During re-sync with existing segments, keep the list visible.
            if isSyncing && appState.segments.isEmpty {
                loadingState
            } else if !appState.hasRealSegmentData {
                emptyState
            } else if isSearching {
                searchResultsList
            } else if showStarredOnly && sortedSegments.isEmpty {
                starredEmptyState
            } else {
                if isSyncing {
                    syncBanner
                }
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
                    ForEach(tieredSegments, id: \.tier) { group in
                        Section {
                            ForEach(group.segments) { segment in
                                NavigationLink(value: SegmentNavigation.detail(segment)) {
                                    SegmentStrikeRow(segment: segment)
                                }
                                .listRowBackground(Color.enzoBg)
                                .listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
                            }
                        } header: {
                            Text(group.tier.uppercased())
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoSecondary)
                                .tracking(0.5)
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $searchText, prompt: "Search segments")
        .navigationDestination(for: SegmentNavigation.self) { nav in
            switch nav {
            case .detail(let seg):
                SegmentDetailView(segment: seg)
            case .detailWithChat(let seg):
                SegmentDetailView(segment: seg, autoStartChat: true)
            }
        }
    }

    private var searchResultsList: some View {
        Group {
            if filteredSegments.isEmpty {
                VStack(spacing: 8) {
                    Text("No segments match \"\(searchText)\"")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredSegments) { segment in
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
    }

    private var starFilterBar: some View {
        HStack(spacing: 0) {
            Button {
                showStarredOnly = false
            } label: {
                Text("All")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(showStarredOnly ? Color.enzoSecondary : Color.enzoPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(showStarredOnly ? Color.clear : Color.enzoAccent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                showStarredOnly = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text("Starred")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(showStarredOnly ? Color.enzoPrimary : Color.enzoSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(showStarredOnly ? Color.enzoAccent.opacity(0.12) : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.enzoBg)
    }

    private var starredEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundStyle(Color.enzoSecondary)
            Text("No starred segments")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoPrimary)
                .padding(.top, 2)
            Text("Star a segment from its detail page to find it here.")
                .font(.system(.subheadline))
                .foregroundStyle(Color.enzoSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var syncBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
                .tint(Color.enzoSecondary)
            Text("Syncing…")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.enzoBg)
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
                    if segment.isGoalSegment || segment.isStarred {
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

            StrikeScoreDonut(score: segment.prProbability ?? segment.strikeScore, label: segment.strikeLabel, size: 44)
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
