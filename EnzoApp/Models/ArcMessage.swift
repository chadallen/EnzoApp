import Foundation

struct ArcMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    enum Role {
        case enzo, user
    }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}
