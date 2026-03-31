import SwiftUI
import Charts

struct FitnessRingView: View {
    let context: AthleteContext
    var fullWidth: Bool = false
    var goalSegment: SegmentScore? = nil

    private var ringColor: Color { .enzoChartPrimary }

    private func readinessColor(for score: Double) -> Color {
        switch score {
        case 0.70...: return .enzoGoal
        case 0.45..<0.70: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    private var greeting: String { context.name }

    private var trendArrow: String {
        switch context.trendDirection {
        case "up": return "↑"
        case "down": return "↓"
        default: return "→"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Greeting
            Text(greeting)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)

            // Ring + stats row
            HStack(spacing: 20) {
                // Fitness donut
                VStack(spacing: 4) {
                    ZStack {
                        Chart {
                            SectorMark(
                                angle: .value("Fitness", context.currentFitnessValue),
                                innerRadius: .ratio(0.65),
                                angularInset: 2
                            )
                            .foregroundStyle(ringColor)

                            SectorMark(
                                angle: .value("Remaining", max(0.001, 1.0 - context.currentFitnessValue)),
                                innerRadius: .ratio(0.65),
                                angularInset: 2
                            )
                            .foregroundStyle(ringColor.opacity(0.12))
                        }
                        .chartLegend(.hidden)
                        .frame(width: 120, height: 120)

                        Text("\(Int(context.currentFitnessValue * 100))")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(ringColor)
                    }
                    Text("Fitness")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                // Readiness donut (only when goal segment is set)
                if let seg = goalSegment, !context.goal.segmentName.isEmpty {
                    let readColor = readinessColor(for: seg.strikeScore)
                    VStack(spacing: 4) {
                        ZStack {
                            Chart {
                                SectorMark(
                                    angle: .value("Readiness", seg.strikeScore),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(readColor)

                                SectorMark(
                                    angle: .value("Remaining", max(0.001, 1.0 - seg.strikeScore)),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(readColor.opacity(0.12))
                            }
                            .chartLegend(.hidden)
                            .frame(width: 120, height: 120)

                            Text("\(Int(seg.strikeScore * 100))")
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

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(context.currentFitnessLabel + " " + trendArrow)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(ringColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last ride")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(lastRideText)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.enzoPrimary)
                    }
                }

                Spacer()
            }

            // Segment name below both donuts
            if let seg = goalSegment, !context.goal.segmentName.isEmpty {
                Text(seg.name)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(
            fullWidth ? Color.enzoAccent.opacity(0.08) : Color.enzoCard,
            in: fullWidth
                ? AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
                : AnyShape(RoundedRectangle(cornerRadius: 16))
        )
    }

    private var lastRideText: String {
        switch context.daysSinceLastRide {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(context.daysSinceLastRide) days ago"
        }
    }
}

#Preview {
    FitnessRingView(
        context: .preview,
        fullWidth: true,
        goalSegment: SegmentScore.previewSegments[0]
    )
    .background(Color.enzoBg)
}
