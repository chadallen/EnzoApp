import SwiftUI

struct PROpportunitiesCard: View {
    let segments: [SegmentScore]

    // Goal segment first, then top 2 by strike score (excluding goal)
    private var displaySegments: [SegmentScore] {
        let goal = segments.filter { $0.isGoalSegment }
        let others = segments
            .filter { !$0.isGoalSegment }
            .sorted { $0.strikeScore > $1.strikeScore }
            .prefix(2)
        return Array((goal + others).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Strike while you're hot")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.enzoSecondary)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(displaySegments.enumerated()), id: \.element.id) { index, segment in
                    if index > 0 {
                        Divider()
                            .background(Color.enzoSecondary.opacity(0.15))
                            .padding(.vertical, 2)
                    }
                    SegmentOpportunityRow(segment: segment, rank: index + 1)
                }
            }

            NavigationLink(destination: Text("Segments")) {
                HStack(spacing: 4) {
                    Text("See all opportunities")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoAccent)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.enzoAccent)
                }
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SegmentOpportunityRow: View {
    let segment: SegmentScore
    let rank: Int
    @State private var isPulsing = false

    private var strikePillColor: Color {
        switch segment.strikeScore {
        case 0.70...: return .enzoGoal
        case 0.45..<0.70: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    private var description: String {
        if segment.isGoalSegment {
            return "Your goal — \(segment.strikeLabel.lowercased())"
        }
        switch segment.strikeScore {
        case 0.7...:
            return "Fitter now than when you set this PR"
        case 0.45..<0.7:
            return "Getting close — timing is right soon"
        default:
            return "Build more fitness before targeting this"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("⑦".replacingOccurrences(of: "⑦", with: circledNumber(rank)))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(segment.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoPrimary)
                    if segment.isGoalSegment {
                        Label("Goal", systemImage: "star.fill")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(Color.enzoAccent)
                            .labelStyle(.iconOnly)
                    }
                }

                HStack(spacing: 6) {
                    Text("PR \(segment.prFormatted)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.enzoSecondary)
                    Text("·")
                        .foregroundStyle(Color.enzoSecondary.opacity(0.5))
                    Text(description)
                        .font(.system(.caption))
                        .foregroundStyle(Color.enzoSecondary)
                }
            }

            Spacer()

            Text(segment.strikeLabel)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(strikePillColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(strikePillColor.opacity(0.15), in: Capsule())
                .scaleEffect(isPulsing ? 1.06 : 1.0)
                .animation(
                    segment.strikeLabel == "No brainer"
                        ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .onAppear { isPulsing = segment.strikeLabel == "No brainer" }
        }
        .padding(.vertical, 6)
    }

    private func circledNumber(_ n: Int) -> String {
        let circled = ["①", "②", "③", "④", "⑤"]
        return circled[max(0, min(n - 1, circled.count - 1))]
    }
}

#Preview {
    PROpportunitiesCard(segments: SegmentScore.previewSegments)
        .padding()
        .background(Color.enzoBg)
}
