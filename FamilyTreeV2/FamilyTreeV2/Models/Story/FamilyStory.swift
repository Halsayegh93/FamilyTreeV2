import Foundation

nonisolated struct FamilyStory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let memberId: UUID
    let imageUrl: String
    let caption: String?
    var approvalStatus: String
    var approvedBy: UUID?
    var approvedAt: String?
    let createdBy: UUID
    let createdAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case memberId = "member_id"
        case imageUrl = "image_url"
        case caption
        case approvalStatus = "approval_status"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    // MARK: - Computed

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var createdDate: Date {
        Self.iso8601.date(from: createdAt)
            ?? Self.iso8601NoFrac.date(from: createdAt)
            ?? Date()
    }

    var expiresDate: Date {
        Self.iso8601.date(from: expiresAt)
            ?? Self.iso8601NoFrac.date(from: expiresAt)
            ?? Date()
    }

    var isExpired: Bool {
        expiresDate <= Date()
    }

    var isApproved: Bool {
        approvalStatus == "approved"
    }

    var isPending: Bool {
        approvalStatus == "pending"
    }
}
