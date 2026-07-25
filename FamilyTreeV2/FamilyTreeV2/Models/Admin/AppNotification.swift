import Foundation

nonisolated struct AppNotification: Identifiable, Codable, Sendable {
    let id: UUID
    let targetMemberId: UUID?
    let title: String
    let body: String
    let kind: String
    let createdBy: UUID?
    let createdAt: String
    let isRead: Bool?
    let requestId: UUID?
    let requestType: String?
    let details: NotificationDetails?
    /// العضو الذي تخصّه الحركة (لا مستلم الإشعار — ذاك `targetMemberId`)
    let subjectMemberId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, body, kind, details
        case targetMemberId = "target_member_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case isRead = "is_read"
        case requestId = "request_id"
        case requestType = "request_type"
        case subjectMemberId = "subject_member_id"
    }

    init(id: UUID, targetMemberId: UUID?, title: String, body: String, kind: String,
         createdBy: UUID?, createdAt: String, isRead: Bool?,
         requestId: UUID?, requestType: String?, details: NotificationDetails?,
         subjectMemberId: UUID? = nil) {
        self.id = id
        self.targetMemberId = targetMemberId
        self.title = title
        self.body = body
        self.kind = kind
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.isRead = isRead
        self.requestId = requestId
        self.requestType = requestType
        self.details = details
        self.subjectMemberId = subjectMemberId
    }

    /// فكّ ترميز متسامح: أي عطب في `details` (شكل غير متوقّع) يجعلها nil
    /// بدل أن يُفشل الصف كله — ففشل صف واحد كان يُسقط قائمة الإشعارات
    /// بأكملها (الإشعارات والمستجدات وسجل النشاط تظهر فارغة).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        title         = try c.decode(String.self, forKey: .title)
        body          = try c.decode(String.self, forKey: .body)
        kind          = try c.decode(String.self, forKey: .kind)
        createdAt     = try c.decode(String.self, forKey: .createdAt)
        targetMemberId = try? c.decodeIfPresent(UUID.self, forKey: .targetMemberId)
        createdBy     = try? c.decodeIfPresent(UUID.self, forKey: .createdBy)
        isRead        = try? c.decodeIfPresent(Bool.self, forKey: .isRead)
        requestId     = try? c.decodeIfPresent(UUID.self, forKey: .requestId)
        requestType   = try? c.decodeIfPresent(String.self, forKey: .requestType)
        details       = try? c.decodeIfPresent(NotificationDetails.self, forKey: .details)
        subjectMemberId = try? c.decodeIfPresent(UUID.self, forKey: .subjectMemberId)
    }

    var read: Bool {
        isRead ?? false
    }

    /// Whether this notification carries an actionable request the admin can approve
    var isActionableRequest: Bool {
        requestId != nil && requestType != nil
    }

    func withRead(_ value: Bool) -> AppNotification {
        AppNotification(
            id: id, targetMemberId: targetMemberId,
            title: title, body: body, kind: kind,
            createdBy: createdBy, createdAt: createdAt, isRead: value,
            requestId: requestId, requestType: requestType,
            details: details, subjectMemberId: subjectMemberId
        )
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

// MARK: - Change Details Payload

extension AppNotification {
    /// Structured "what changed" payload attached to admin-edit notifications.
    /// Stored as JSONB in `notifications.details` column.
    nonisolated struct NotificationDetails: Codable, Sendable, Equatable {
        let v: Int
        let changes: [ChangeEntry]

        nonisolated struct ChangeEntry: Codable, Sendable, Equatable, Identifiable {
            let field: String
            let before: String?
            let after: String?

            var id: String { field }
        }

        init(changes: [ChangeEntry], v: Int = 1) {
            self.v = v
            self.changes = changes
        }

        /// Localized label for a field key (e.g., "birth_date" → "تاريخ الميلاد").
        static func localizedFieldName(_ field: String) -> String {
            switch field {
            case "full_name":      return L10n.t("الاسم", "Name")
            case "first_name":     return L10n.t("الاسم الأول", "First Name")
            case "phone_number":   return L10n.t("رقم الهاتف", "Phone")
            case "birth_date":     return L10n.t("تاريخ الميلاد", "Birth Date")
            case "death_date":     return L10n.t("تاريخ الوفاة", "Death Date")
            case "is_deceased":    return L10n.t("الحالة", "Status")
            case "is_married":     return L10n.t("الحالة الاجتماعية", "Marital Status")
            case "is_phone_hidden":return L10n.t("إخفاء الهاتف", "Phone Visibility")
            case "avatar_url":     return L10n.t("الصورة الشخصية", "Profile Photo")
            case "father_id":      return L10n.t("الأب", "Father")
            case "role":           return L10n.t("الدور", "Role")
            case "gender":         return L10n.t("الجنس", "Gender")
            default:               return field
            }
        }

        /// Whether the field stores a URL/opaque identifier whose raw value
        /// shouldn't be rendered (we show a friendly summary instead).
        static func isOpaqueField(_ field: String) -> Bool {
            field == "avatar_url" || field == "father_id"
        }
    }
}
