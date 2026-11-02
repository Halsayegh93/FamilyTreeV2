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
    /// بأكملها (الإشعارات والمستجدات و«إشعارات الإدارة» تظهر فارغة).
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

    /// إعلان وفاة من دالة السيرفر `announce_death` (بثّ لكل الأعضاء)
    var isDeathAnnouncement: Bool {
        details?.type == "death_announcement"
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
        /// نوع خاص للإشعار (مثل «death_announcement») — بلا v/changes في تلك الحمولة
        let type: String?
        let memberId: String?
        let newsId: String?
        /// «مسار الموافقات» (`type = approval_workflow`): الطلب ومرحلته — عمودا الطلب في الإشعار فارغان عمداً
        /// (حتى لا تُظهر النسخ القديمة «قبول» سريعاً)
        let workflowRequestId: String?
        let workflowStage: String?
        /// مرسل الإشعار من السيرفر لكل صف جديد: «الإدارة» أو عضو — قد يغيب في الصفوف القديمة
        let sender: Sender?
        /// تغييرات الأعضاء (v2، `member_change` و`my_profile_change`): edit/add/delete
        let action: String?
        /// الشجرة: main أو women
        let tree: String?
        /// العضو المعني بالتغيير
        let subject: Person?
        /// من نفّذ التغيير (للإدارة فقط — لا يصل العضو)
        let actor: Person?

        enum CodingKeys: String, CodingKey {
            case v, changes, type, sender, action, tree, subject, actor
            case memberId = "member_id"
            case newsId = "news_id"
            case workflowRequestId = "request_id"
            case workflowStage = "stage"
        }

        /// `details.sender` — type = admin | member، والاسم المختصر (قد يكون null)
        nonisolated struct Sender: Codable, Sendable, Equatable {
            let type: String?
            let name: String?
            let id: String?

            var isAdmin: Bool { type != "member" }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                type = try? c.decodeIfPresent(String.self, forKey: .type)
                name = try? c.decodeIfPresent(String.self, forKey: .name)
                id = try? c.decodeIfPresent(String.self, forKey: .id)
            }
        }

        /// عضو مذكور في الحمولة (المعني أو المنفّذ)
        nonisolated struct Person: Codable, Sendable, Equatable {
            let id: String?
            let name: String?
            let isAdmin: Bool?

            enum CodingKeys: String, CodingKey {
                case id, name
                case isAdmin = "is_admin"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try? c.decodeIfPresent(String.self, forKey: .id)
                name = try? c.decodeIfPresent(String.self, forKey: .name)
                isAdmin = try? c.decodeIfPresent(Bool.self, forKey: .isAdmin)
            }
        }

        nonisolated struct ChangeEntry: Codable, Sendable, Equatable, Identifiable {
            let field: String
            let before: String?
            let after: String?
            /// اسم الحقل جاهزاً من السيرفر (v2) — بدونه نترجم المفتاح محلياً
            let label: String?
            /// text | image
            let kind: String?
            let beforeUrl: String?
            let afterUrl: String?

            var id: String { field }

            enum CodingKeys: String, CodingKey {
                case field, before, after, label, kind
                case beforeUrl = "before_url"
                case afterUrl = "after_url"
            }

            init(field: String, before: String?, after: String?,
                 label: String? = nil, kind: String? = nil,
                 beforeUrl: String? = nil, afterUrl: String? = nil) {
                self.field = field
                self.before = before
                self.after = after
                self.label = label
                self.kind = kind
                self.beforeUrl = beforeUrl
                self.afterUrl = afterUrl
            }

            /// فكّ متسامح: القيم قد تصل أرقاماً أو منطقية (v2) — تتحوّل نصّاً بدل أن يفشل الصف
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                field = (try? c.decodeIfPresent(String.self, forKey: .field)) ?? ""
                before = Self.looseString(c, .before)
                after = Self.looseString(c, .after)
                label = try? c.decodeIfPresent(String.self, forKey: .label)
                kind = try? c.decodeIfPresent(String.self, forKey: .kind)
                beforeUrl = try? c.decodeIfPresent(String.self, forKey: .beforeUrl)
                afterUrl = try? c.decodeIfPresent(String.self, forKey: .afterUrl)
            }

            private static func looseString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
                if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
                if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
                if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return String(d) }
                if let b = try? c.decodeIfPresent(Bool.self, forKey: key) {
                    return b ? L10n.t("نعم", "Yes") : L10n.t("لا", "No")
                }
                return nil
            }

            /// اسم الحقل للعرض: من السيرفر أولاً
            var displayLabel: String {
                if let label, !label.isEmpty { return label }
                return NotificationDetails.localizedFieldName(field)
            }

            /// تغيير صورة — يُعرض بالصورتين لا بالنص
            var isImage: Bool { kind == "image" || field == "avatar_url" }

            /// رابط الصورة قبل/بعد (v2 في `*_url`، والقديم في القيمة نفسها)
            var beforeImageURL: String? { beforeUrl ?? (field == "avatar_url" ? before : nil) }
            var afterImageURL: String? { afterUrl ?? (field == "avatar_url" ? after : nil) }
        }

        init(changes: [ChangeEntry], v: Int = 1) {
            self.v = v
            self.changes = changes
            self.type = nil
            self.memberId = nil
            self.newsId = nil
            self.workflowRequestId = nil
            self.workflowStage = nil
            self.sender = nil
            self.action = nil
            self.tree = nil
            self.subject = nil
            self.actor = nil
        }

        /// حمولة «ما الذي تغيّر» أو حمولة نوع خاص (إعلان وفاة) — الغائب يأخذ قيمة فارغة
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            memberId = try? c.decodeIfPresent(String.self, forKey: .memberId)
            newsId = try? c.decodeIfPresent(String.self, forKey: .newsId)
            workflowRequestId = try? c.decodeIfPresent(String.self, forKey: .workflowRequestId)
            workflowStage = try? c.decodeIfPresent(String.self, forKey: .workflowStage)
            changes = (try? c.decodeIfPresent([ChangeEntry].self, forKey: .changes)) ?? []
            sender = try? c.decodeIfPresent(Sender.self, forKey: .sender)
            action = try? c.decodeIfPresent(String.self, forKey: .action)
            tree = try? c.decodeIfPresent(String.self, forKey: .tree)
            subject = try? c.decodeIfPresent(Person.self, forKey: .subject)
            actor = try? c.decodeIfPresent(Person.self, forKey: .actor)
            if let version = try? c.decodeIfPresent(Int.self, forKey: .v) {
                v = version
            } else if type != nil || sender != nil || !changes.isEmpty {
                // كل صف جديد يحمل `sender` وحده (بلا v ولا نوع) — حمولة صالحة
                v = 1
            } else {
                // لا v ولا نوع — شكل غير متوقّع (يبقى السلوك القديم: details = nil)
                throw DecodingError.dataCorruptedError(forKey: .v, in: c,
                                                       debugDescription: "unknown details payload")
            }
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
