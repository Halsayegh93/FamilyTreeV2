import Foundation

struct PhoneChangeRequest: Identifiable, Codable {
    let id: UUID
    let memberId: UUID
    let requesterId: UUID?
    let requestType: String
    var newValue: String?
    var status: String
    let details: String?
    let createdAt: String?
    let member: FamilyMember?
    
    enum CodingKeys: String, CodingKey {
        case id, status, details, member
        case memberId = "member_id"
        case requesterId = "requester_id"
        case requestType = "request_type"
        case newValue = "new_value"
        case createdAt = "created_at"
    }
}
