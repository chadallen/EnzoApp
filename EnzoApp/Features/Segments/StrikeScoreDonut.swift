import SwiftUI
import Charts

/// Returns the tier color for a given strike score.
/// Used by StrikeScoreDonut and SegmentStrikeRow.
func strikeColor(for score: Double) -> Color {
    switch score {
    case 0.80...:       return .enzoGoal
    case 0.65..<0.80:   return .enzoChartPrimary
    case 0.45..<0.65:   return .enzoAmber
    default:            return .enzoSecondary
    }
}

/// Donut chart visualizing a strike score (0.0–1.0).
///
/// Compact (size ≤ 56): center shows the score number. Used in list rows.
/// Hero (size > 56): center shows score + label. Used in SegmentDetailView.
struct StrikeScoreDonut: View {
    let score: Double
    let label: String
    let size: CGFloat

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(score: Double, label: String, size: CGFloat = 120) {
        self.score = score
        self.label = label
        self.size = size
    }

    private var color: Color { strikeColor(for: score) }
    // < 90: score number only (list rows at 44pt, hero card at 80pt)
    // ≥ 90: score + label (detail view at 120pt)
    private var isCompact: Bool { size < 90 }

    var body: some View {
        ZStack {
            Chart {
                SectorMark(
                    angle: .value("Readiness", score),
                    innerRadius: .ratio(0.62),
                    angularInset: 2
                )
                .foregroundStyle(color)

                SectorMark(
                    angle: .value("Remaining", max(0.001, 1.0 - score)),
                    innerRadius: .ratio(0.62),
                    angularInset: 2
                )
                .foregroundStyle(color.opacity(0.12))
            }
            .chartLegend(.hidden)
            .frame(width: size, height: size)

            if isCompact {
                Text("\(Int(score * 100))")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(color)
            } else {
                VStack(spacing: 2) {
                    Text("\(Int(score * 100))")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(color)
                    Text(label)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(color)
                        .frame(maxWidth: size * 0.55)
                }
            }
        }
        .scaleEffect(isPulsing ? 1.06 : 1.0)
        .animation(
            label == "Strike now" && !reduceMotion
                ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                : .default,
            value: isPulsing
        )
        .onAppear { isPulsing = label == "Strike now" && !reduceMotion }
    }
}

#Preview("Hero — all tiers") {
    let segments = SegmentScore.previewSegments
    return ScrollView(.horizontal) {
        HStack(spacing: 24) {
            ForEach(segments.prefix(5)) { seg in
                VStack(spacing: 8) {
                    StrikeScoreDonut(score: seg.strikeScore, label: seg.strikeLabel)
                    Text(seg.strikeLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                }
            }
        }
        .padding()
    }
    .background(Color.enzoBg)
}

#Preview("Compact — list row size") {
    HStack(spacing: 16) {
        StrikeScoreDonut(score: 0.85, label: "Strike now", size: 44)
        StrikeScoreDonut(score: 0.70, label: "Almost there", size: 44)
        StrikeScoreDonut(score: 0.55, label: "Worth a shot", size: 44)
        StrikeScoreDonut(score: 0.30, label: "Getting there", size: 44)
        StrikeScoreDonut(score: 0.10, label: "Build first", size: 44)
    }
    .padding()
    .background(Color.enzoBg)
}
