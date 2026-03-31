import SwiftUI
import Charts

struct FitnessRingView: View {
    let context: AthleteContext

    private var ringColor: Color {
        switch context.currentFitnessLabel {
        case "Epic", "Strong": return .enzoRingHigh
        case "Building": return .enzoAccent
        default: return .enzoRingLow
        }
    }

    private var trendArrow: String {
        switch context.trendDirection {
        case "up": return "↑"
        case "down": return "↓"
        default: return "→"
        }
    }

    var body: some View {
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

                Text("\(Int(context.currentFitnessValue * 100))%")
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
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
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
    FitnessRingView(context: .preview)
        .padding()
        .background(Color.enzoBg)
}
