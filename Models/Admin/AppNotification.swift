import Foundation

struct AppNotification: Identifiable, Codable {
    let id: UUID
    let targetMemberId: UUID?
    let title: String
    let body: String
    let kind: String
    let createdBy: UUID?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, title, body, kind
        case targetMemberId = "target_member_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
    
    var createdDate: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: createdAt) ?? Date()
    }
}
