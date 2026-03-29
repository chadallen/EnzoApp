import SwiftUI

struct ArcInputBar: View {
    @Binding var text: String
    var isSending: Bool = false
    let onSend: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask Enzo anything...", text: $text, axis: .vertical)
                .font(.system(.body))
                .foregroundStyle(Color.enzoPrimary)
                .tint(Color.enzoAccent)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.enzoCard, in: Capsule())
                .disabled(isSending)

            if !text.isEmpty || isSending {
                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !isSending else { return }
                    onSend(trimmed)
                    text = ""
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(Color.enzoAccent)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.enzoAccent)
                    }
                }
                .disabled(isSending)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        .animation(.easeInOut(duration: 0.15), value: isSending)
    }
}

#Preview {
    @Previewable @State var text = ""
    ArcInputBar(text: $text, onSend: { _ in })
        .background(Color.enzoBg)
}
