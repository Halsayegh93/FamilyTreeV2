import Foundation

nonisolated struct BannedPhone: Identifiable, Codable, Sendable {
    let id: UUID
    var phoneNumber: String
    let reason: String?
    let bannedBy: UUID
    let createdAt: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, reason
        case phoneNumber = "phone_number"
        case bannedBy = "banned_by"
        case createdAt = "created_at"
        case isActive = "is_active"
    }
}
