import Foundation

// MARK: - Tree Edit Payload (v2 structured JSON in details column)
struct TreeEditPayload: Codable {
    let v: Int                    // version = 2
    let action: String            // "تعديل اسم" / "حذف" / "إضافة"
    let targetMemberId: String?
    let targetMemberName: String?
    let newName: String?          // for name edit
    let parentMemberId: String?   // for add
    let parentMemberName: String? // for add
    let newMemberName: String?    // for add
    let reason: String?           // for delete
    let notes: String?            // optional free text
}

struct AdminRequest: Identifiable, Codable {
    let id: UUID
    let memberId: UUID
    let requesterId: UUID
    let requestType: String
    var newValue: String?
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

    /// Parses structured v2 JSON from details column for tree_edit requests.
    /// Returns nil for old format (backward compatible).
    var treeEditPayload: TreeEditPayload? {
        guard requestType == "tree_edit",
              let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TreeEditPayload.self, from: data)
    }
}
