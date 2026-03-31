import SwiftUI
import Charts

struct FitnessRingView: View {
    let context: AthleteContext
    var fullWidth: Bool = false
    var goalSegment: SegmentScore? = nil

    private var ringColor: Color { .enzoChartPrimary }

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

            // Goal progress bar
            if let seg = goalSegment, !context.goal.segmentName.isEmpty {
                goalProgressBar(segment: seg)
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

    private func goalProgressBar(segment: SegmentScore) -> some View {
        let current = context.currentFitnessValue
        let pr = segment.fitnessValueAtPR

        return VStack(alignment: .leading, spacing: 6) {
            Text("For \(context.goal.segmentName) PR")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .kerning(0.3)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.enzoSecondary.opacity(0.15))
                        .frame(height: 6)

                    // Fill to current fitness
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ringColor)
                        .frame(width: width * min(current, pr), height: 6)

                    // PR marker tick
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.enzoAccent)
                        .frame(width: 3, height: 12)
                        .offset(x: width * pr - 1.5, y: -3)
                }
            }
            .frame(height: 12)

            HStack {
                Text("You · \(Int(current * 100))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(ringColor)
                Spacer()
                Text("PR · \(Int(pr * 100))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.enzoAccent)
            }
        }
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
