import SwiftUI

struct SegmentDetailView: View {
    let segment: SegmentScore

    private var pillColor: Color {
        switch segment.strikeScore {
        case 0.7...: return .enzoGoal
        case 0.4..<0.7: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    private var deltaLine: String {
        let delta = Int(segment.fitnessDelta)
        if delta > 0 {
            return "You're \(delta) points fitter now than when you set this PR — a good window to go after it."
        } else if delta == 0 {
            return "You're at the same fitness level as when you set this PR."
        } else {
            return "You're \(abs(delta)) points below your PR fitness. Close the gap and come back to this one."
        }
    }

    private var strikeLine: String {
        switch segment.strikeScore {
        case 0.7...:
            return "You're in better shape now than when you set this PR. A good window to go after it."
        case 0.4..<0.7:
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
                                value: "\(Int(segment.fitnessAtPR))",
                                label: AthleteContext.fitnessLabel(for: segment.fitnessAtPR),
                                sublabel: "When PR set"
                            )

                            Image(systemName: "arrow.right")
                                .foregroundStyle(Color.enzoSecondary.opacity(0.5))

                            fitnessBlock(
                                value: "\(Int(segment.currentFitness))",
                                label: AthleteContext.fitnessLabel(for: segment.currentFitness),
                                sublabel: "Today",
                                valueColor: segment.fitnessDelta >= 0 ? Color.enzoGoal : Color.enzoPrimary
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
                }
                .padding()
            }
        }
        .navigationTitle(segment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.enzoBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func fitnessBlock(
        value: String,
        label: String,
        sublabel: String,
        valueColor: Color = Color.enzoPrimary
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
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
