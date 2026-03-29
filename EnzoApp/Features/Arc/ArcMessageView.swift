import SwiftUI

struct ArcMessageView: View {
    let message: ArcMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.system(.body))
                    .foregroundStyle(Color.enzoPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "1C1C2E"), in: RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.enzoAccent)
                        .frame(width: 3)

                    Text(message.content)
                        .font(.system(.body))
                        .foregroundStyle(Color.enzoPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
                .padding(.trailing, 10)
                .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 60)
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ArcMessageView(message: ArcMessage(role: .enzo, content: "You peaked last August. You're building back — that's good."))
        ArcMessageView(message: ArcMessage(role: .user, content: "Am I on track for Hawk Hill?"))
    }
    .padding()
    .background(Color.enzoBg)
}
