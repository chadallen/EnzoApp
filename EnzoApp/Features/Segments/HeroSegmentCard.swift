import SwiftUI

/// Dashboard-style card pinned above the segment list when the user has set a goal segment.
/// Shows segment name, key stats, a strike score donut, and two CTAs:
/// "Ask Enzo" (navigates to detail and auto-opens chat) and "View details".
struct HeroSegmentCard: View {
    let segment: SegmentScore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Goal badge
            Label("Goal segment", systemImage: "star.fill")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoAccent)

            // Name + donut
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(segment.name)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.enzoPrimary)

                    HStack(spacing: 12) {
                        if let dist = segment.distanceMeters {
                            statChip(
                                icon: "arrow.left.and.right",
                                value: String(format: "%.1f mi", dist * 0.000621371)
                            )
                        }
                        if let elev = segment.elevationDeltaMeters {
                            statChip(
                                icon: "arrow.up",
                                value: String(format: "+%.0f ft", elev * 3.28084)
                            )
                        }
                        statChip(icon: "clock", value: "PR \(segment.prFormatted)")
                    }
                }

                Spacer()

                StrikeScoreDonut(score: segment.strikeScore, label: segment.strikeLabel, size: 80)
            }

            // CTAs
            HStack(spacing: 10) {
                NavigationLink(value: SegmentNavigation.detailWithChat(segment)) {
                    Label("Ask Enzo", systemImage: "bubble.left")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.enzoAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                NavigationLink(value: SegmentNavigation.detail(segment)) {
                    Text("View details")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.enzoSecondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statChip(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(.caption2))
                .foregroundStyle(Color.enzoSecondary)
            Text(value)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
        }
    }
}

#Preview("With goal") {
    NavigationStack {
        HeroSegmentCard(segment: SegmentScore.previewSegments[0])
            .padding()
    }
    .background(Color.enzoBg)
}

#Preview("No goal — card absent") {
    NavigationStack {
        Text("Hero card does not appear")
            .foregroundStyle(Color.enzoSecondary)
            .padding()
    }
    .background(Color.enzoBg)
}
