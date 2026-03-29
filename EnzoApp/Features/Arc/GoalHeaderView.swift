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
            // Line 1: Segment name
            Text(String(goal.segmentName.prefix(24)) + " PR")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
                .lineLimit(1)

            // Line 2: Current fitness label + trend arrow
            Text(context.currentFitnessLabel + " " + trendArrow)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(fitnessLabelColor)

            // Line 3: Required fitness label
            Text(goal.requiredFitnessLabel + " fitness needed")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)

            Button("Change goal") {
                showingGoalSetting = true
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.enzoSecondary)
            .padding(.top, 4)
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingGoalSetting) {
            GoalSettingView()
                .environment(appState)
        }
    }
}

#Preview {
    GoalHeaderView(context: .preview)
        .padding()
        .background(Color.enzoBg)
        .environment(AppState())
        .preferredColorScheme(.dark)
}
