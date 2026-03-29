import SwiftUI

struct PromptChipsView: View {
    let chips: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        onTap(chip)
                    } label: {
                        Text(chip)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.enzoAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.enzoAccent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.enzoAccent.opacity(0.25), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    static let defaultChips = [
        "Am I on track for Hawk Hill?",
        "What should I do this weekend?",
        "When was I last this fit?",
        "What if I only have 4 weeks left?",
    ]
}

#Preview {
    PromptChipsView(chips: PromptChipsView.defaultChips, onTap: { _ in })
        .background(Color.enzoBg)
}
