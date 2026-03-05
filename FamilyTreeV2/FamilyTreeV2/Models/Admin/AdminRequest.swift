import Foundation

struct AdminRequest: Identifiable, Codable {
    let id: UUID
    let memberId: UUID
    let requesterId: UUID
    let requestType: String
    let newValue: String?
    var status: String
    let details: String?
    let createdAt: String? // نخليه String ليتوافق مع نظام السيرفر عندك
    let member: FamilyMember? // هذا المجلد الذي سيجلب بيانات الابن كاملة ✅

    enum CodingKeys: String, CodingKey {
        case id, status, details, member
        case memberId = "member_id"
        case requesterId = "requester_id"
        case requestType = "request_type"
        case createdAt = "created_at"
        case newValue = "new_value"
    }
}
