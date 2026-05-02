import SwiftUI

struct AddSegmentsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.enzoBg.ignoresSafeArea()
            }
            .navigationTitle("Add Segments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.enzoAccent)
                }
            }
        }
    }
}

#Preview {
    AddSegmentsView()
}
