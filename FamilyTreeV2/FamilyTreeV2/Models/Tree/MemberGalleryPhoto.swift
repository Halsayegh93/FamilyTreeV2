import Foundation

struct MemberGalleryPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    let memberId: UUID
    let photoURL: String
    let caption: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case memberId = "member_id"
        case photoURL = "photo_url"
        case caption
        case createdAt = "created_at"
    }
}
