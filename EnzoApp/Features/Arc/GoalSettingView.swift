import SwiftUI

struct GoalSettingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedSegment: SegmentScore? = nil
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()
    @State private var reactionText = ""
    @State private var isStreamingReaction = false
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var showPathB = false

    /// Called instead of dismiss() when GoalSettingView is used in the onboarding flow.
    /// When nil, the view behaves as a sheet with a Cancel button.
    var onGoalConfirmed: (() -> Void)?

    // For previews only — allows pre-selecting a segment without @State in #Preview
    init(onGoalConfirmed: (() -> Void)? = nil, previewSegment: SegmentScore? = nil) {
        self.onGoalConfirmed = onGoalConfirmed
        _selectedSegment = State(initialValue: previewSegment)
        if let seg = previewSegment {
            _reactionText = State(initialValue: "Hawk Hill. Solid choice. You set that PR at Epic fitness last August — you're Recovering right now but trending up. There's real ground to cover, but your history shows you can move fast when you're consistent. A target date isn't required, but if you have one in mind it helps me calibrate.")
            _ = seg
        }
    }

    private var filteredSegments: [SegmentScore] {
        SegmentScore.filter(appState.segments, by: searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.top, 8)

                    if !appState.segments.isEmpty && !showPathB && selectedSegment == nil {
                        Button {
                            showPathB = true
                            searchText = ""
                        } label: {
                            Text("Help me pick one")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal)
                    }

                    Spacer().frame(height: 12)

                    if let segment = selectedSegment {
                        selectedFlow(segment: segment)
                    } else if showPathB {
                        pathBList
                    } else {
                        segmentList
                    }
                }
            }
            .navigationTitle("Which segment?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onGoalConfirmed == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color.enzoSecondary)
                    }
                }
            }
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.enzoSecondary)
            TextField("Search your segments", text: $searchText)
                .foregroundStyle(Color.enzoPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Segment list (search phase)

    private var segmentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredSegments.isEmpty {
                    Text("No segments match that search.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(filteredSegments) { segment in
                        segmentRow(segment)
                            .onTapGesture { selectSegment(segment) }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Path B (top segments by strike score)

    private var pathBList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top opportunities right now")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoSecondary)
                    Spacer()
                    Button("Search instead") {
                        showPathB = false
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoAccent)
                }
                .padding(.horizontal)

                ForEach(appState.segments.prefix(3)) { segment in
                    segmentRow(segment)
                        .onTapGesture { selectSegment(segment) }
                        .padding(.horizontal)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    private func segmentRow(_ segment: SegmentScore) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(segment.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoPrimary)
                HStack(spacing: 8) {
                    Text("PR \(segment.prFormatted)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.enzoSecondary)
                    Circle()
                        .fill(Color.enzoSecondary.opacity(0.3))
                        .frame(width: 3, height: 3)
                    Text(segment.strikeLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(strikeLabelColor(segment.strikeLabel))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary.opacity(0.4))
        }
        .padding(14)
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Selected state (confirmation phase)

    private func selectedFlow(segment: SegmentScore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                selectedSegmentCard(segment)

                if !reactionText.isEmpty || isStreamingReaction {
                    enzoReactionCard
                }

                if !reactionText.isEmpty && !isStreamingReaction {
                    targetDateSection
                    confirmButton(segment)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    private func selectedSegmentCard(_ segment: SegmentScore) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(segment.name)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoPrimary)
                Text("PR \(segment.prFormatted)  ·  \(segment.strikeLabel)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.enzoSecondary)
            }
            Spacer()
            Button("Pick different") {
                streamTask?.cancel()
                streamTask = nil
                selectedSegment = nil
                reactionText = ""
                isStreamingReaction = false
                showPathB = false
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.enzoAccent)
        }
        .padding(14)
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var enzoReactionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(Color.enzoAccent)
                .frame(width: 3)
                .frame(minHeight: 20)
            Text(reactionText.isEmpty ? "..." : reactionText)
                .font(.system(.body))
                .foregroundStyle(Color.enzoPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.1), value: reactionText)
        }
        .padding(14)
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var targetDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasTargetDate) {
                Text("Set a target date")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoPrimary)
            }
            .tint(Color.enzoAccent)

            if hasTargetDate {
                DatePicker(
                    "Target date",
                    selection: $targetDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .colorScheme(.dark)
                .foregroundStyle(Color.enzoPrimary)
            }
        }
        .padding(14)
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func confirmButton(_ segment: SegmentScore) -> some View {
        Button {
            appState.setGoal(segment, targetDate: hasTargetDate ? targetDate : nil)
            if let onGoalConfirmed {
                onGoalConfirmed()
            } else {
                dismiss()
            }
        } label: {
            Text("Set this goal")
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoBg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.enzoAccent, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Helpers

    private func strikeLabelColor(_ label: String) -> Color {
        switch label {
        case "No brainer": return .enzoGoal
        case "Worth a shot": return .enzoAccent
        default: return .enzoAmber
        }
    }

    private func selectSegment(_ segment: SegmentScore) {
        selectedSegment = segment
        reactionText = ""
        isStreamingReaction = true

        streamTask = Task {
            let stream = await appState.goalReactionStream(for: segment)
            for await token in stream {
                reactionText += token
            }
            isStreamingReaction = false
        }
    }
}

// MARK: - Previews

#Preview("Search state") {
    GoalSettingView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Segment selected — reaction complete") {
    GoalSettingView(previewSegment: SegmentScore.previewSegments[0])
        .environment(AppState())
        .preferredColorScheme(.dark)
}
