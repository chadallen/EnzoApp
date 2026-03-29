import SwiftUI

struct GoalHeaderView: View {
    let context: AthleteContext

    private var goal: GoalContext { context.goal }

    private var progressFraction: Double {
        min(context.currentFitnessScore / goal.requiredFitnessScore, 1.0)
    }

    private var requiredLabel: String {
        AthleteContext.fitnessLabel(for: goal.requiredFitnessScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row
            HStack(alignment: .firstTextBaseline) {
                Text(goal.segmentName + " PR")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoPrimary)
                    .lineLimit(1)

                Spacer()

                if let weeks = goal.weeksRemaining {
                    Text("\(weeks) weeks to go")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoAccent)
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.enzoSecondary.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.enzoAccent.opacity(0.6))
                            .frame(width: geo.size.width * progressFraction, height: 8)

                        Circle()
                            .fill(Color.enzoAccent)
                            .frame(width: 14, height: 14)
                            .offset(x: max(0, geo.size.width * progressFraction - 7))
                    }
                }
                .frame(height: 14)

                HStack {
                    Text(context.currentFitnessLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                    Spacer()
                    Text(requiredLabel + " needed")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                }

                HStack(spacing: 4) {
                    Text(String(format: "%.0f", context.currentFitnessScore))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.enzoAccent)
                    Text("→ \(String(format: "%.0f", goal.requiredFitnessScore))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.enzoSecondary)

                    Spacer()

                    Button("Change goal") { }
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                }
            }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    GoalHeaderView(context: .preview)
        .padding()
        .background(Color.enzoBg)
}
