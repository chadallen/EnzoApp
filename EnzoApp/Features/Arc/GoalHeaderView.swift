import SwiftUI
import Charts

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

    private func readinessColor(for score: Double) -> Color {
        switch score {
        case 0.80...:       return .enzoGoal
        case 0.65..<0.80:   return .enzoChartPrimary
        case 0.45..<0.65:   return .enzoAmber
        default:            return .enzoSecondary
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
            if let goalSegment = appState.segments.first(where: { $0.isGoalSegment }) {
                let readColor = readinessColor(for: goalSegment.strikeScore)

                // Header: segment name + readiness tag
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current target segment")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    Text(goal.segmentName)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.enzoPrimary)
                        .lineLimit(1)
                    Text(goalSegment.strikeLabel)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(readColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(readColor.opacity(0.12), in: Capsule())
                }

                HStack(alignment: .top) {
                    // Segment stats
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

                    Spacer()

                    // Readiness donut
                    VStack(spacing: 4) {
                        ZStack {
                            Chart {
                                SectorMark(
                                    angle: .value("Readiness", goalSegment.strikeScore),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(readColor)

                                SectorMark(
                                    angle: .value("Remaining", max(0.001, 1.0 - goalSegment.strikeScore)),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(readColor.opacity(0.12))
                            }
                            .chartLegend(.hidden)
                            .frame(width: 90, height: 90)

                            Text("\(Int(goalSegment.strikeScore * 100))")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(readColor)
                        }
                        Text("Readiness")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }
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
