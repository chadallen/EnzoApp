import SwiftUI

struct GoalHeaderView: View {
    let context: AthleteContext
    var fullWidth: Bool = false
    @Environment(AppState.self) private var appState
    @State private var showingGoalSetting = false

    private var goal: GoalContext { context.goal }

    private var trendArrow: String {
        switch context.trendDirection {
        case "up": return "↑"
        case "down": return "↓"
        default: return "→"
        }
    }

    private var fitnessLabelColor: Color {
        switch context.currentFitnessLabel {
        case "Epic", "Strong": return .enzoGoal
        case "Building": return .enzoAccent
        default: return .enzoAmber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if goal.segmentName.isEmpty {
                emptyGoalState
            } else {
                goalContent
            }
        }
        .padding()
        .background(
            fullWidth ? Color.enzoAccent.opacity(0.08) : Color.enzoCard,
            in: fullWidth
                ? AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
                : AnyShape(RoundedRectangle(cornerRadius: 16))
        )
        .sheet(isPresented: $showingGoalSetting) {
            GoalSettingView()
                .environment(appState)
        }
    }

    private var goalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: label + segment name
            VStack(alignment: .leading, spacing: 2) {
                Text("Current target segment")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text(goal.segmentName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoPrimary)
                    .lineLimit(1)
            }

            // Stat comparison row
            let currentPct = Int(context.currentFitnessValue * 100)
            if let goalSegment = appState.segments.first(where: { $0.isGoalSegment }) {
                let prLabel = AthleteContext.fitnessLabel(for: goalSegment.fitnessValueAtPR)
                let prPct = Int(goalSegment.fitnessValueAtPR * 100)
                HStack(alignment: .top, spacing: 0) {
                    // Segment stats column (only when data is available)
                    if goalSegment.distanceMeters != nil || goalSegment.elevationDeltaMeters != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Segment")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.enzoSecondary)
                                .textCase(.uppercase)
                                .kerning(0.3)
                            if let dist = goalSegment.distanceMeters {
                                Text(String(format: "%.1f mi", dist * 0.000621371))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.enzoSecondary)
                            }
                            Text(goalSegment.prFormatted)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoSecondary)
                            Text(formattedPRDate(goalSegment.prDate))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoSecondary)
                            if let elev = goalSegment.elevationDeltaMeters {
                                Text(String(format: "+%.0f ft", elev * 3.28084))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.enzoSecondary)
                            }
                        }

                        Rectangle()
                            .fill(Color.enzoSecondary.opacity(0.2))
                            .frame(width: 1, height: 110)
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                    }

                    // Current fitness column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current fitness")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .kerning(0.3)
                        Text(context.currentFitnessLabel)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(fitnessLabelColor)
                        Text("\(currentPct)%")
                            .font(.system(.title2, design: .monospaced))
                            .foregroundStyle(Color.enzoPrimary)
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.enzoSecondary.opacity(0.2))
                        .frame(width: 1, height: 110)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)

                    // PR fitness column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PR fitness")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .kerning(0.3)
                        Text(prLabel)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.enzoSecondary)
                        Text("\(prPct)%")
                            .font(.system(.title2, design: .monospaced))
                            .foregroundStyle(Color.enzoSecondary)
                    }

                    Spacer()
                }
            } else {
                // Fallback: no goal segment synced yet — show current fitness only
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current fitness")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .textCase(.uppercase)
                        .kerning(0.3)
                    Text(context.currentFitnessLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(fitnessLabelColor)
                    Text("\(currentPct)%")
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(Color.enzoPrimary)
                }
            }

            Button("Change goal") {
                showingGoalSetting = true
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.enzoSecondary)
        }
    }

    private func formattedPRDate(_ dateString: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = TimeZone(identifier: "UTC")
        guard let date = input.date(from: dateString) else { return dateString }
        let output = DateFormatter()
        output.dateFormat = "MMM yyyy"
        return output.string(from: date)
    }

    private var emptyGoalState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No goal set")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)

            Text(context.currentFitnessLabel + " " + trendArrow)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(fitnessLabelColor)

            Text("Pick a segment to chase.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)

            Button("Set a goal") {
                showingGoalSetting = true
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.enzoAccent)
            .padding(.top, 4)
        }
    }
}

#Preview {
    GoalHeaderView(context: .preview)
        .padding()
        .background(Color.enzoBg)
        .environment(AppState())
}
