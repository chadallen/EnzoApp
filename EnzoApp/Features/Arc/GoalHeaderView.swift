import SwiftUI

struct GoalHeaderView: View {
    let context: AthleteContext
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
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingGoalSetting) {
            GoalSettingView()
                .environment(appState)
        }
    }

    private var goalContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Line 1: Segment name
            Text(String(goal.segmentName.prefix(24)) + " PR")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
                .lineLimit(1)

            // Line 2: Current fitness label + trend arrow
            Text(context.currentFitnessLabel + " " + trendArrow)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(fitnessLabelColor)

            // Line 3: Required fitness label + optional weeks remaining
            HStack(spacing: 6) {
                Text(goal.requiredFitnessLabel + " fitness needed")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
                if let days = goal.daysRemaining {
                    Text("·")
                        .foregroundStyle(Color.enzoSecondary.opacity(0.4))
                    Text(timeRemainingLabel(days: days))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                }
            }

            Button("Change goal") {
                showingGoalSetting = true
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.enzoSecondary)
            .padding(.top, 4)
        }
    }

    private func timeRemainingLabel(days: Int) -> String {
        switch days {
        case 0: return "today"
        case 1: return "1 day to go"
        case 2...13: return "\(days) days to go"
        default: return "\(days / 7) weeks to go"
        }
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
