import SwiftUI

struct SegmentDetailView: View {
    let segment: SegmentScore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()

    private var pillColor: Color {
        switch segment.strikeScore {
        case 0.70...: return .enzoGoal
        case 0.45..<0.70: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    private var deltaLine: String {
        let labelAtPR = AthleteContext.fitnessLabel(for: segment.fitnessValueAtPR)
        let labelNow = AthleteContext.fitnessLabel(for: segment.currentFitnessValue)
        if segment.fitnessDelta > 0.05 {
            return "You're at \(labelNow) — fitter than when you set this PR at \(labelAtPR). A good window to go after it."
        } else if segment.fitnessDelta >= -0.05 {
            return "You're at \(labelNow) — roughly the same fitness as when you set this PR."
        } else {
            return "You were at \(labelAtPR) when you set this PR. You're at \(labelNow) now. Close the gap and come back to this one."
        }
    }

    private var strikeLine: String {
        switch segment.strikeScore {
        case 0.70...:
            return "You're in better shape now than when you set this PR. A good window to go after it."
        case 0.45..<0.70:
            return "Getting close — a few more weeks of consistent riding and the timing will be right."
        default:
            return "Not quite there yet. Worth targeting once you've built more fitness."
        }
    }

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        if segment.isGoalSegment {
                            Label("Goal segment", systemImage: "star.fill")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoAccent)
                        }
                        Text(segment.name)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.enzoPrimary)
                    }

                    // PR card
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.prFormatted)
                                .font(.system(.title, design: .monospaced, weight: .bold))
                                .foregroundStyle(Color.enzoAccent)
                            Text("Current PR")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.enzoSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.prDate)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.enzoPrimary)
                            Text("Date set")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.enzoSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

                    // Fitness comparison
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Fitness comparison")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .tracking(1)

                        HStack(spacing: 0) {
                            fitnessBlock(
                                label: AthleteContext.fitnessLabel(for: segment.fitnessValueAtPR),
                                sublabel: "When PR set"
                            )

                            Image(systemName: "arrow.right")
                                .foregroundStyle(Color.enzoSecondary.opacity(0.5))

                            fitnessBlock(
                                label: AthleteContext.fitnessLabel(for: segment.currentFitnessValue),
                                sublabel: "Today",
                                labelColor: segment.fitnessDelta >= 0 ? Color.enzoGoal : Color.enzoPrimary
                            )
                        }

                        Text(deltaLine)
                            .font(.system(.subheadline))
                            .foregroundStyle(Color.enzoPrimary)
                            .lineSpacing(3)
                    }
                    .padding()
                    .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

                    // Strike assessment
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(segment.strikeLabel)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(pillColor)
                            Spacer()
                            Text(String(format: "%.0f%%", segment.strikeScore * 100))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(pillColor)
                        }
                        Text(strikeLine)
                            .font(.system(.subheadline))
                            .foregroundStyle(Color.enzoSecondary)
                            .lineSpacing(3)
                    }
                    .padding()
                    .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

                    // Goal card
                    if segment.isGoalSegment {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.enzoAccent)
                            Text("This is your current goal")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoAccent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.enzoAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    } else {
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
                                .foregroundStyle(Color.enzoPrimary)
                            }

                            Button {
                                appState.setGoal(segment, targetDate: hasTargetDate ? targetDate : nil)
                                Task {
                                    await appState.generateBriefing(forceRefresh: true)
                                    await appState.generateLookahead(forceRefresh: true)
                                }
                                dismiss()
                            } label: {
                                Text("Set this goal")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.enzoBg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.enzoAccent, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding()
                        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
        }
        .navigationTitle(segment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.enzoBg, for: .navigationBar)
    }

    private func fitnessBlock(
        label: String,
        sublabel: String,
        labelColor: Color = Color.enzoPrimary
    ) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(labelColor)
            Text(sublabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.enzoSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        SegmentDetailView(segment: SegmentScore.previewSegments[0])
    }
    .environment(AppState())
}
