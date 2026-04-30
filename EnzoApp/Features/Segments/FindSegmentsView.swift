import SwiftUI

/// Sheet that surfaces frequently-ridden unstarred segments.
/// Shown when the user taps "Find more segments" in SegmentsView.
///
/// Read-only discovery only — no in-app starring via Strava API.
struct FindSegmentsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [AppState.SuggestedSegment] = []
    @State private var selectedSegment: AppState.SuggestedSegment? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                if suggestions.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(suggestions) { suggestion in
                                Button {
                                    selectedSegment = suggestion
                                } label: {
                                    SuggestedSegmentRow(suggestion: suggestion)
                                }
                                .listRowBackground(Color.enzoBg)
                                .listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
                            }
                        } header: {
                            headerText
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Segments to Consider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.enzoBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.enzoAccent)
                }
            }
            .sheet(item: $selectedSegment) { suggestion in
                SuggestedSegmentDetailView(suggestion: suggestion)
            }
            .onAppear {
                suggestions = appState.findSegmentsToConsider()
            }
        }
    }

    private var headerText: some View {
        Text("Ridden 3 or more times but not yet starred")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.enzoSecondary)
            .textCase(nil)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(Color.enzoSecondary)
            Text("No new candidates yet")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoPrimary)
                .padding(.top, 4)
            Text("Segments you ride 3 or more times without starring will appear here after the next sync.")
                .font(.system(.subheadline))
                .foregroundStyle(Color.enzoSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct SuggestedSegmentRow: View {
    let suggestion: AppState.SuggestedSegment

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(suggestion.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoPrimary)

                HStack(spacing: 8) {
                    Text(formattedTime(suggestion.bestTimeSeconds))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.enzoSecondary)

                    Text("·")
                        .font(.system(.caption2))
                        .foregroundStyle(Color.enzoSecondary.opacity(0.4))

                    Text("\(suggestion.effortCount) rides")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary.opacity(0.4))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Detail sheet

/// Detail view shown when the user taps a suggested segment.
/// Shows name, effort count, best time, and instructions for starring on Strava.
struct SuggestedSegmentDetailView: View {
    let suggestion: AppState.SuggestedSegment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        statsCard
                        howToStarCard
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.enzoBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.enzoAccent)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statBlock(
                value: formattedTime(suggestion.bestTimeSeconds),
                label: "Best time",
                mono: true,
                color: Color.enzoAccent
            )
            statBlock(
                value: "\(suggestion.effortCount)",
                label: "Times ridden",
                mono: true,
                color: Color.enzoPrimary
            )
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var howToStarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.enzoAccent)
                Text("How to add this segment")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                instructionStep(
                    number: "1",
                    text: "Open Strava and find this segment by searching for \"\(suggestion.name)\"."
                )
                instructionStep(
                    number: "2",
                    text: "Tap the star icon on the segment page to add it to your starred segments."
                )
                instructionStep(
                    number: "3",
                    text: "Sync Enzo — it will appear here with full PR readiness data."
                )
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func instructionStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoAccent)
                .frame(width: 18, height: 18)
                .background(Color.enzoAccent.opacity(0.12), in: Circle())

            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statBlock(value: String, label: String, mono: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(mono
                    ? .system(.title2, design: .monospaced, weight: .bold)
                    : .system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Previews

#Preview("With suggestions") {
    let suggestions: [AppState.SuggestedSegment] = [
        AppState.SuggestedSegment(segmentId: 1, name: "Marincello Trail", effortCount: 7, bestTimeSeconds: 412),
        AppState.SuggestedSegment(segmentId: 2, name: "Tennessee Valley Road", effortCount: 5, bestTimeSeconds: 683),
        AppState.SuggestedSegment(segmentId: 3, name: "Coastal Trail climb", effortCount: 3, bestTimeSeconds: 187),
    ]
    FindSegmentsViewPreviewWrapper(suggestions: suggestions)
}

#Preview("Empty state") {
    FindSegmentsViewPreviewWrapper(suggestions: [])
}

#Preview("Detail") {
    SuggestedSegmentDetailView(
        suggestion: AppState.SuggestedSegment(
            segmentId: 1,
            name: "Marincello Trail",
            effortCount: 7,
            bestTimeSeconds: 412
        )
    )
    .environment(AppState())
}

/// Preview helper — injects a fixed list of suggestions without needing SwiftData.
private struct FindSegmentsViewPreviewWrapper: View {
    let suggestions: [AppState.SuggestedSegment]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                if suggestions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.enzoSecondary)
                        Text("No new candidates yet")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.enzoPrimary)
                            .padding(.top, 4)
                        Text("Segments you ride 3 or more times without starring will appear here after the next sync.")
                            .font(.system(.subheadline))
                            .foregroundStyle(Color.enzoSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(suggestions) { suggestion in
                                SuggestedSegmentRow(suggestion: suggestion)
                                    .listRowBackground(Color.enzoBg)
                                    .listRowSeparatorTint(Color.enzoSecondary.opacity(0.15))
                            }
                        } header: {
                            Text("Ridden 3 or more times but not yet starred")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.enzoSecondary)
                                .textCase(nil)
                                .padding(.bottom, 4)
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Segments to Consider")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
