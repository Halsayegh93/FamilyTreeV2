import Foundation

struct AppNotification: Identifiable, Codable {
    let id: UUID
    let targetMemberId: UUID?
    let title: String
    let body: String
    let kind: String
    let createdBy: UUID?
    let createdAt: String
    let isRead: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, title, body, kind
        case targetMemberId = "target_member_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case isRead = "is_read"
    }
    
    var read: Bool {
        isRead ?? false
    }
    
    func withRead(_ value: Bool) -> AppNotification {
        AppNotification(id: id, targetMemberId: targetMemberId, title: title, body: body, kind: kind, createdBy: createdBy, createdAt: createdAt, isRead: value)
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var createdDate: Date {
        Self.isoFormatter.date(from: createdAt) ?? Date()
    }
}
