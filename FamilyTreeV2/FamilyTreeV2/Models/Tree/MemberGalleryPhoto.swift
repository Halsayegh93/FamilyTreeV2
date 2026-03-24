import Foundation

struct MemberGalleryPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    let memberId: UUID
    let photoURL: String
    let caption: String?
    let createdAt: String?
    let createdBy: UUID?
    let approvalStatus: String?

    /// هل الصورة معتمدة
    var isApproved: Bool { approvalStatus == "approved" || approvalStatus == nil }
    /// هل الصورة معلقة
    var isPending: Bool { approvalStatus == "pending" }

    enum CodingKeys: String, CodingKey {
        case id
        case memberId = "member_id"
        case photoURL = "photo_url"
        case caption
        case createdAt = "created_at"
        case createdBy = "created_by"
        case approvalStatus = "approval_status"
    }
}
