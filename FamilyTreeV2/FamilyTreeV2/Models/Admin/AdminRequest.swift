import Foundation

// MARK: - Tree Edit Action (v3)
nonisolated enum TreeEditAction: String, Codable, CaseIterable, Identifiable {
    case add = "add"
    case editName = "edit_name"
    case editPhone = "edit_phone"
    case editBirth = "edit_birth"
    case deceased = "deceased"
    case addDeathDate = "add_death_date"
    case addPhoto = "add_photo"
    case delete = "delete"
    case other = "other"

    var id: String { rawValue }

    var arabicLabel: String {
        switch self {
        case .add: return "إضافة"
        case .editName: return "تعديل اسم"
        case .editPhone: return "تعديل رقم"
        case .editBirth: return "تعديل ميلاد"
        case .deceased: return "تسجيل وفاة"
        case .addDeathDate: return "إضافة تاريخ وفاة"
        case .addPhoto: return "إضافة صورة"
        case .delete: return "حذف"
        case .other: return "طلب آخر"
        }
    }

    var englishLabel: String {
        switch self {
        case .add: return "Add"
        case .editName: return "Edit Name"
        case .editPhone: return "Edit Phone"
        case .editBirth: return "Edit Birth Date"
        case .deceased: return "Mark Deceased"
        case .addDeathDate: return "Add Death Date"
        case .addPhoto: return "Add Photo"
        case .delete: return "Delete"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .add: return "person.badge.plus"
        case .editName: return "pencil.line"
        case .editPhone: return "phone.arrow.up.right"
        case .editBirth: return "birthday.cake"
        case .deceased: return "heart.slash"
        case .addDeathDate: return "calendar.badge.exclamationmark"
        case .addPhoto: return "photo.badge.plus"
        case .delete: return "person.badge.minus"
        case .other: return "square.and.pencil"
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
    let newBirthDate: String?
    let deathDate: String?
    let newPhotoUrl: String?

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
        newBirthDate: String? = nil,
        deathDate: String? = nil,
        newPhotoUrl: String? = nil,
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
            newBirthDate: newBirthDate,
            deathDate: deathDate,
            newPhotoUrl: newPhotoUrl,
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
