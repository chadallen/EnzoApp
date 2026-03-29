import SwiftUI

struct LookaheadSuggestionView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What to do next")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .tracking(1)

            Text(text)
                .font(.system(.body))
                .foregroundStyle(Color.enzoPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text("A suggestion, not a plan. Adjust freely.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
                .italic()
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    LookaheadSuggestionView(text: AthleteContext.previewLookahead)
        .padding()
        .background(Color.enzoBg)
}
