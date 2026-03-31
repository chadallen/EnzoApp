import SwiftUI

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
            Color.enzoCard,
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
        VStack(alignment: .leading, spacing: 8) {
            // Line 1: Current target
            Text("Current target: \(goal.segmentName).")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.enzoPrimary)
                .lineLimit(1)

            // Line 2: Current fitness
            let currentPct = Int(context.currentFitnessValue * 100)
            HStack(spacing: 0) {
                Text("Current fitness: ")
                    .foregroundStyle(Color.enzoPrimary)
                Text(context.currentFitnessLabel)
                    .foregroundStyle(fitnessLabelColor)
                Text(" | \(currentPct)%")
                    .foregroundStyle(Color.enzoPrimary)
            }
            .font(.system(.subheadline, design: .rounded))

            // Line 3: PR fitness (from goal segment)
            if let goalSegment = appState.segments.first(where: { $0.isGoalSegment }) {
                let prLabel = AthleteContext.fitnessLabel(for: goalSegment.fitnessValueAtPR)
                let prPct = Int(goalSegment.fitnessValueAtPR * 100)
                Text("PR fitness: \(prLabel) | \(prPct)%")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
            }

            Button("Change goal") {
                showingGoalSetting = true
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.enzoSecondary)
            .padding(.top, 2)
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
