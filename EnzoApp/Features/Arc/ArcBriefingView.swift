import SwiftUI

struct ArcBriefingView: View {
    let text: String
    var isLoading: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left accent border
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.enzoAccent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("What to do next")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.enzoSecondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Color.enzoSecondary)
                    } else {
                        Button {
                            onRefresh?()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(Color.enzoSecondary)
                        }
                    }
                }

                if text.isEmpty {
                    Text("Checking in on your training...")
                        .font(.system(.body))
                        .foregroundStyle(Color.enzoSecondary)
                        .italic()
                } else {
                    Text(text)
                        .font(.system(.body))
                        .foregroundStyle(Color.enzoPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .padding(.trailing, 14)
        }
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ArcBriefingView(text: AthleteContext.previewBriefing)
        .padding()
        .background(Color.enzoBg)
}
