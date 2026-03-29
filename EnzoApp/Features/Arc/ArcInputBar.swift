import SwiftUI

struct ArcInputBar: View {
    @Binding var text: String
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

            if !text.isEmpty {
                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSend(trimmed)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.enzoAccent)
                }
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}

#Preview {
    @Previewable @State var text = ""
    ArcInputBar(text: $text, onSend: { _ in })
        .background(Color.enzoBg)
}
