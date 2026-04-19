import Foundation

struct ArcMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    // When true, the message is included in API history but not rendered in the chat UI.
    // Used for the synthetic assessment prompt sent by askEnzo() so it doesn't flash as a
    // dark user bubble before the first Enzo token arrives.
    let isHidden: Bool

    enum Role {
        case enzo, user
    }

    init(role: Role, content: String, isHidden: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.isHidden = isHidden
    }
}
