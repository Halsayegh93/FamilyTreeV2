import Foundation

// MARK: - «مسار الموافقات» (طلب المالك ٢٠٢٦-١٠-١٥)
//
// الطلب يمشي مثل الشركات: العضو يقدّم ← المختص يراجع ويرفع للمدير بتوصية (أو يطلب معلومات من العضو)
// ← المدير (المالك/المدير) يعتمد فيرجع للمختص، أو يرفض، أو يرجّعه للمختص بملاحظة ← المختص ينفّذ
// (مسار الموافقة القديم نفسه) ← مكتمل. خلف مفتاح `app_settings.approvals_workflow` — مطفأ = كما كان تماماً.
// السيرفر يقرّر الصلاحية والمرحلة (`advance_admin_request`)؛ هنا القراءة والعرض فقط.

/// مرحلة الطلب — القيم كما في عمود `admin_requests.stage` (المعلّق بلا مرحلة والمفتاح شغّال = «مراجعة»)
nonisolated enum ApprovalStage: String, Sendable, CaseIterable {
    case review, info, approve, execute

    /// ساعات في المرحلة قبل «متأخر» — معلومات العضو تُمهَل يومين
    var lateAfterHours: Double { self == .info ? 48 : 24 }

    /// موضعها في متتبّع الخطوات (٠ تقديم · ١ مراجعة المختص · ٢ اعتماد المدير · ٣ تنفيذ · ٤ مكتمل)
    var trackerStep: Int {
        switch self {
        case .review, .info: return 1
        case .approve: return 2
        case .execute: return 3
        }
    }
}

/// إجراءات `advance_admin_request` — التنفيذ والرفض النهائي يبقيان في مسارات الموافقة/الرفض القديمة
nonisolated enum ApprovalAction: String, Sendable {
    case recommendApprove = "recommend_approve"
    case recommendReject = "recommend_reject"
    case requestInfo = "request_info"
    case provideInfo = "provide_info"
    case approve
    case returnToSpecialist = "return"
    // «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦): استلام الطلب وتركه، والأولوية — خطوات إدارية لا تغيّر المرحلة
    case claim
    case release
    case markUrgent = "mark_urgent"
    case markNormal = "mark_normal"

    /// الملاحظة مطلوبة (السيرفر يرفض بدونها: note_required)
    var requiresNote: Bool {
        switch self {
        case .recommendReject, .requestInfo, .provideInfo, .returnToSpecialist: return true
        case .recommendApprove, .approve, .claim, .release, .markUrgent, .markNormal: return false
        }
    }

    /// خطوة إدارية (استلام/ترك/أولوية) — المربّع يبقى مفتوحاً بعدها
    var isHousekeeping: Bool {
        switch self {
        case .claim, .release, .markUrgent, .markNormal: return true
        default: return false
        }
    }
}

/// «طلب معلومات» منظّم (طلب المالك ٢٠٢٦-١٠-١٥ «الادارة تختار الناقص»): ما يختاره المختص من صاحب الطلب —
/// القيم كما في عمود `admin_requests.info_fields` (السيرفر يقبل هذه فقط)
nonisolated enum ApprovalInfoField: String, Sendable, CaseIterable, Identifiable {
    case phone
    case birthDate = "birth_date"
    case deathDate = "death_date"
    case fullName = "full_name"
    /// توضيح مكتوب (نص حرّ) — لا يظهر كشريحة للمختص، يُرسل مع الرد دائماً اختيارياً
    case text

    var id: String { rawValue }

    /// ما يختاره المختص بالشرائح (الترتيب = ترتيب العرض)
    static let askable: [ApprovalInfoField] = [.phone, .birthDate, .deathDate, .fullName]

    /// حقل تاريخ (yyyy-mm-dd)
    var isDate: Bool { self == .birthDate || self == .deathDate }
}

/// ردّ العضو المنظّم (`admin_requests.info_reply` jsonb) — قراءة متسامحة: النص والأرقام تُقرأ نصاً وأي شكل
/// آخر يُتجاهل، فلا يُسقط ردّ غريب (نسخة أخرى/صيانة) قائمة الطلبات كلها
nonisolated struct ApprovalInfoValues: Codable, Sendable, Equatable {
    var values: [String: String]

    init(_ values: [String: String] = [:]) { self.values = values }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        var result: [String: String] = [:]
        if let container = try? decoder.container(keyedBy: Key.self) {
            for key in container.allKeys {
                if let text = try? container.decode(String.self, forKey: key) {
                    result[key.stringValue] = text
                } else if let number = try? container.decode(Double.self, forKey: key) {
                    result[key.stringValue] = number.rounded() == number ? String(Int(number)) : String(number)
                }
            }
        }
        values = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in values { try container.encode(value, forKey: Key(stringValue: key)) }
    }

    subscript(field: ApprovalInfoField) -> String? {
        let v = values[field.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? nil : v
    }
}

/// خطوة في سجل الطلب (`admin_request_steps`) — يقرؤها الطاقم وصاحب الطلب
nonisolated struct AdminRequestStep: Identifiable, Decodable, Sendable {
    let id: UUID
    let requestId: UUID
    let actorId: UUID?
    let actorRole: String?
    let action: String
    let note: String?
    let createdAt: String?
    /// «مسار ٢»: صاحب الشأن — المستلم السابق عند الأخذ/سحب الاستلام، ومن عنده الطلب في التذكير/التصعيد
    var subjectId: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, action, note
        case requestId = "request_id"
        case actorId = "actor_id"
        case actorRole = "actor_role"
        case createdAt = "created_at"
        case subjectId = "subject_id"
    }
}

/// لقطة المسار لطلب معلّق واحد — تُبنى من صفّه (`AdminRequest` أو `PhoneChangeRequest`)
nonisolated struct ApprovalSnapshot: Sendable, Equatable {
    let requestId: UUID
    let requestType: String
    let requesterId: UUID?
    let memberId: UUID
    let stage: ApprovalStage
    let stageSince: Date?
    let createdAt: Date?
    /// توصية المختص: approve | reject
    let recommendation: String?
    let recommendationNote: String?
    let recommendedBy: UUID?
    /// سؤال المختص للعضو (مرحلة «معلومات») — قد يكون فارغاً إذا اختار حقولاً فقط
    let infoRequest: String?
    let approvedBy: UUID?
    let approvalNote: String?
    /// الحقول التي طلبها المختص (فارغ = سؤال حرّ كما كان، أو السيرفر لم يُرحَّل بعد)
    var infoFields: [ApprovalInfoField] = []
    /// ردّ العضو المنظّم بعد فحص السيرفر (فارغ قبل الرد)
    var infoReply: ApprovalInfoValues = ApprovalInfoValues()

    // «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢) — أعمدة اختيارية: غيابها = كما كان
    /// الأولوية «مستعجل»
    var isUrgent: Bool = false
    /// من استلم الطلب (أو أعاده السيرفر له بعد قرار المدير)
    var assignedTo: UUID? = nil
    var assignedAt: Date? = nil
    /// تصعّد للمدير لتأخره (السيرفر يختمه بعد مهلة التصعيد)
    var escalatedAt: Date? = nil
    /// مسار سريع — بدأ عند المدير مباشرة
    var fastTrack: Bool = false
    /// السيرفر فيه أعمدة «مسار ٢» (الأولوية تصل دائماً بقيمة) — وإلا تختفي أزرار الاستلام والأولوية
    var hasV2: Bool = false
    /// المهلة من «إعدادات التطبيق» بالساعات (nil = الافتراضي) — يضعها `AdminRequestViewModel`
    var slaHours: Double? = nil
    var urgentSlaHours: Double? = nil

    /// المختص طلب حقولاً محدّدة (غير «توضيح مكتوب»)
    var asksFields: Bool { infoFields.contains { $0 != .text } }

    /// تصعّد للمدير وهو عند المختص (مراجعة/تنفيذ) — المالك/المدير يقدر يتصرف بدله
    var isEscalated: Bool { escalatedAt != nil && (stage == .review || stage == .execute) }

    /// ساعات المرحلة قبل «متأخر»: معلومات العضو يومان كما كان، والمستعجل بمهلته، والباقي بمهلة الإعدادات
    var lateAfterHours: Double {
        if stage == .info { return stage.lateAfterHours }
        if isUrgent { return urgentSlaHours ?? 6 }
        return slaHours ?? stage.lateAfterHours
    }

    /// مضى عليه في المرحلة أكثر من حدّها
    var isLate: Bool {
        guard let since = stageSince ?? createdAt else { return false }
        return Date().timeIntervalSince(since) > lateAfterHours * 3600
    }

    var recommendsApproval: Bool? {
        switch recommendation {
        case "approve": return true
        case "reject": return false
        default: return nil
        }
    }
}

/// مكان واحد لقواعد المسار التي لا تحتاج حالة (نصوص الأنواع حرفية: النوع خارج عزل الواجهة)
nonisolated enum ApprovalWorkflow {
    /// مختص النوع: المشرف للبلاغات، والمراقب لكل نوع آخر — رسائل التواصل خارج المسار (nil)
    static func specialistRole(for requestType: String) -> FamilyMember.UserRole? {
        switch requestType {
        case "contact_message": return nil
        case "news_report", "content_report": return .supervisor
        default: return .monitor
        }
    }

    /// طلب الانضمام/الربط: صاحبه معلّق بلا شاشة «طلباتي» فلا يقدر يرد — لا «طلب معلومات» له
    static func canAskRequester(_ requestType: String) -> Bool {
        requestType != "join_request" && requestType != "link_request"
    }

    /// تاريخ ISO من السيرفر (بكسور الثواني أو بدونها)
    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return isoFraction.date(from: raw) ?? isoPlain.date(from: raw)
    }

    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// اللقطة من حقول الصف — nil للمغلق ولما هو خارج المسار
    static func snapshot(id: UUID, requestType: String, status: String, requesterId: UUID?, memberId: UUID,
                         createdAt: String?, stage: String?, stageSince: String?,
                         recommendation: String?, recommendationNote: String?, recommendedBy: UUID?,
                         infoRequest: String?, approvedBy: UUID?, approvalNote: String?,
                         infoFields: [String]? = nil, infoReply: ApprovalInfoValues? = nil,
                         priority: String? = nil, assignedTo: UUID? = nil, assignedAt: String? = nil,
                         escalatedAt: String? = nil, fastTrack: Bool? = nil) -> ApprovalSnapshot? {
        guard status == "pending", specialistRole(for: requestType) != nil else { return nil }
        // معلّق بلا مرحلة (قبل تشغيل المفتاح أو قبل أول خطوة) = «عند المختص للمراجعة»
        let resolved = stage.flatMap(ApprovalStage.init(rawValue:)) ?? .review
        // حقل لا يعرفه هذا الإصدار يُتجاهل (لا يُسقط الصف)
        var fields: [ApprovalInfoField] = []
        for raw in infoFields ?? [] {
            if let field = ApprovalInfoField(rawValue: raw), !fields.contains(field) { fields.append(field) }
        }
        var snapshot = ApprovalSnapshot(requestId: id, requestType: requestType, requesterId: requesterId, memberId: memberId,
                                        stage: resolved, stageSince: date(stageSince), createdAt: date(createdAt),
                                        recommendation: recommendation, recommendationNote: recommendationNote,
                                        recommendedBy: recommendedBy, infoRequest: infoRequest,
                                        approvedBy: approvedBy, approvalNote: approvalNote,
                                        infoFields: fields, infoReply: infoReply ?? ApprovalInfoValues())
        // «مسار ٢»: الأولوية تصل دائماً بقيمة (normal افتراضياً) إذا رُحِّل السيرفر — هي علامة وجود الأعمدة
        snapshot.hasV2 = priority != nil || fastTrack != nil
        snapshot.isUrgent = priority == "urgent"
        snapshot.assignedTo = assignedTo
        snapshot.assignedAt = date(assignedAt)
        snapshot.escalatedAt = date(escalatedAt)
        snapshot.fastTrack = fastTrack == true
        return snapshot
    }
}

nonisolated extension AdminRequest {
    /// لقطة المسار (بلا اعتبار للمفتاح — `AdminRequestViewModel.approvalSnapshot` يتحقّق منه)
    var approvalSnapshot: ApprovalSnapshot? {
        ApprovalWorkflow.snapshot(id: id, requestType: requestType, status: status, requesterId: requesterId,
                                  memberId: memberId, createdAt: createdAt, stage: stage, stageSince: stageSince,
                                  recommendation: recommendation, recommendationNote: recommendationNote,
                                  recommendedBy: recommendedBy, infoRequest: infoRequest,
                                  approvedBy: approvedBy, approvalNote: approvalNote,
                                  infoFields: infoFields, infoReply: infoReply,
                                  priority: priority, assignedTo: assignedTo, assignedAt: assignedAt,
                                  escalatedAt: escalatedAt, fastTrack: fastTrack)
    }
}

nonisolated extension PhoneChangeRequest {
    var approvalSnapshot: ApprovalSnapshot? {
        ApprovalWorkflow.snapshot(id: id, requestType: requestType, status: status, requesterId: requesterId,
                                  memberId: memberId, createdAt: createdAt, stage: stage, stageSince: stageSince,
                                  recommendation: recommendation, recommendationNote: recommendationNote,
                                  recommendedBy: recommendedBy, infoRequest: infoRequest,
                                  approvedBy: approvedBy, approvalNote: approvalNote,
                                  infoFields: infoFields, infoReply: infoReply,
                                  priority: priority, assignedTo: assignedTo, assignedAt: assignedAt,
                                  escalatedAt: escalatedAt, fastTrack: fastTrack)
    }
}
