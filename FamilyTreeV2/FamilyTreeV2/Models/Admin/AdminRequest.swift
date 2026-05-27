import Foundation

// MARK: - Tree Edit Action (v3)
enum TreeEditAction: String, Codable, CaseIterable, Identifiable {
    case add = "add"
    case editName = "edit_name"
    case editPhone = "edit_phone"
    case deceased = "deceased"
    case delete = "delete"

    var id: String { rawValue }

    var arabicLabel: String {
        switch self {
        case .add: return "إضافة"
        case .editName: return "تعديل اسم"
        case .editPhone: return "تعديل رقم"
        case .deceased: return "تسجيل وفاة"
        case .delete: return "حذف"
        }
    }

    var englishLabel: String {
        switch self {
        case .add: return "Add"
        case .editName: return "Edit Name"
        case .editPhone: return "Edit Phone"
        case .deceased: return "Mark Deceased"
        case .delete: return "Delete"
        }
    }

    var iconName: String {
        switch self {
        case .add: return "person.badge.plus"
        case .editName: return "pencil.line"
        case .editPhone: return "phone.arrow.up.right"
        case .deceased: return "heart.slash"
        case .delete: return "person.badge.minus"
        }
    }

    static func from(rawValue: String) -> TreeEditAction? {
        if let direct = TreeEditAction(rawValue: rawValue) { return direct }
        switch rawValue {
        case "إضافة": return .add
        case "تعديل اسم": return .editName
        case "حذف": return .delete
        default: return nil
        }
    }
}

// MARK: - Tree Edit Payload (v3 structured JSON in details column)
nonisolated struct TreeEditPayload: Codable {
    let v: Int
    let action: String
    let targetMemberId: String?
    let targetMemberName: String?

    let newName: String?
    let newPhone: String?
    let deathDate: String?

    let parentMemberId: String?
    let parentMemberName: String?
    let newMemberName: String?

    let reason: String?
    let notes: String?
    let isAdminDirectEdit: Bool?

    var resolvedAction: TreeEditAction? {
        TreeEditAction.from(rawValue: action)
    }

    static func make(
        action: TreeEditAction,
        targetMemberId: String? = nil,
        targetMemberName: String? = nil,
        newName: String? = nil,
        newPhone: String? = nil,
        deathDate: String? = nil,
        parentMemberId: String? = nil,
        parentMemberName: String? = nil,
        newMemberName: String? = nil,
        reason: String? = nil,
        notes: String? = nil,
        isAdminDirectEdit: Bool? = nil
    ) -> TreeEditPayload {
        TreeEditPayload(
            v: 3,
            action: action.rawValue,
            targetMemberId: targetMemberId,
            targetMemberName: targetMemberName,
            newName: newName,
            newPhone: newPhone,
            deathDate: deathDate,
            parentMemberId: parentMemberId,
            parentMemberName: parentMemberName,
            newMemberName: newMemberName,
            reason: reason,
            notes: notes,
            isAdminDirectEdit: isAdminDirectEdit
        )
    }
}

nonisolated struct AdminRequest: Identifiable, Codable, Sendable {
    let id: UUID
    let memberId: UUID
    let requesterId: UUID
    let requestType: String
    var newValue: String?
    var status: String
    let details: String?
    let createdAt: String?
    let member: FamilyMember?
    var adminReply: String?
    var repliedAt: String?
    var repliedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, status, details, member
        case memberId = "member_id"
        case requesterId = "requester_id"
        case requestType = "request_type"
        case createdAt = "created_at"
        case newValue = "new_value"
        case adminReply = "admin_reply"
        case repliedAt = "replied_at"
        case repliedBy = "replied_by"
    }

    /// Parses structured JSON payload (v2 or v3) from details column for tree_edit requests.
    /// Returns nil for legacy/free-form text.
    var treeEditPayload: TreeEditPayload? {
        guard requestType == "tree_edit",
              let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TreeEditPayload.self, from: data)
    }
}
