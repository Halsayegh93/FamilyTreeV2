import Foundation

// MARK: - «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)
//
// الردود الجاهزة (`approval_templates`)، ملاحظات الإدارة الداخلية (`admin_request_notes` — لا يراها العضو)،
// وتقرير الموافقات (`approvals_report`). كل القراءات متسامحة: جدول/دالة غير موجودة بعد = تختفي الواجهة.

/// نوع الرد الجاهز — يظهر فوق حقل الملاحظة بحسب القرار الحالي
nonisolated enum ApprovalTemplateKind: String, Sendable, CaseIterable, Identifiable {
    case recommend
    case reject
    case info
    case returnBack = "return"
    case note

    var id: String { rawValue }
}

/// رد جاهز — يقرؤه الطاقم ويكتبه المالك/المدير
nonisolated struct ApprovalTemplate: Identifiable, Decodable, Sendable, Equatable {
    let id: UUID
    let kind: String
    let body: String
    let sort: Int?

    var templateKind: ApprovalTemplateKind? { ApprovalTemplateKind(rawValue: kind) }
}

/// ملاحظة داخلية على طلب — للطاقم فقط (الكاتب = أنا، ويحذف ملاحظته)
nonisolated struct AdminRequestNote: Identifiable, Decodable, Sendable, Equatable {
    let id: UUID
    let requestId: UUID
    let authorId: UUID?
    let body: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case requestId = "request_id"
        case authorId = "author_id"
        case createdAt = "created_at"
    }
}

// MARK: تقرير الموافقات

/// فترة التقرير — هذا الشهر · الشهر الماضي · ٣ شهور (بتقويم الجهاز)
nonisolated enum ApprovalsReportPeriod: String, Sendable, CaseIterable, Identifiable, Hashable {
    case thisMonth, lastMonth, threeMonths

    var id: String { rawValue }

    /// [من، إلى) — «إلى» = الآن لهذا الشهر وللثلاثة
    func range(now: Date = Date(), calendar: Calendar = .current) -> (from: Date, to: Date) {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        switch self {
        case .thisMonth:
            return (startOfMonth, now)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
            return (start, startOfMonth)
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -2, to: startOfMonth) ?? startOfMonth
            return (start, now)
        }
    }
}

/// نتيجة `approvals_report(p_from, p_to)` — الأرقام تُقرأ بتسامح (عدد صحيح أو عشري أو نص أو null)
nonisolated struct ApprovalsReport: Decodable, Sendable, Equatable {
    struct Totals: Decodable, Sendable, Equatable {
        var submitted = 0, executed = 0, rejected = 0, pending = 0
        var urgent = 0, escalated = 0, fastTrack = 0, overdueNow = 0

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: LenientKey.self)
            submitted = c.int("submitted"); executed = c.int("executed"); rejected = c.int("rejected")
            pending = c.int("pending"); urgent = c.int("urgent"); escalated = c.int("escalated")
            fastTrack = c.int("fast_track"); overdueNow = c.int("overdue_now")
        }
    }

    struct Stages: Decodable, Sendable, Equatable {
        var reviewHours: Double?, approveHours: Double?, executeHours: Double?, infoHours: Double?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: LenientKey.self)
            reviewHours = c.double("review_hours"); approveHours = c.double("approve_hours")
            executeHours = c.double("execute_hours"); infoHours = c.double("info_hours")
        }
    }

    struct TypeRow: Decodable, Sendable, Equatable, Identifiable {
        var type: String
        var label: String?
        var count: Int, executed: Int, rejected: Int
        var id: String { type }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: LenientKey.self)
            type = c.string("type") ?? "—"
            label = c.string("label")
            count = c.int("count"); executed = c.int("executed"); rejected = c.int("rejected")
        }
    }

    struct StaffRow: Decodable, Sendable, Equatable, Identifiable {
        var memberId: UUID?
        var name: String?
        var role: String?
        var actions: Int
        var avgResponseHours: Double?
        var escalations: Int
        var id: String { memberId?.uuidString ?? (name ?? "—") }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: LenientKey.self)
            memberId = c.string("member_id").flatMap(UUID.init(uuidString:))
            name = c.string("name"); role = c.string("role")
            actions = c.int("actions"); avgResponseHours = c.double("avg_response_hours")
            escalations = c.int("escalations")
        }
    }

    var totals = Totals()
    var stages = Stages()
    var types: [TypeRow] = []
    var staff: [StaffRow] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LenientKey.self)
        totals = (try? c.decodeIfPresent(Totals.self, forKey: LenientKey("totals"))) ?? Totals()
        stages = (try? c.decodeIfPresent(Stages.self, forKey: LenientKey("stages"))) ?? Stages()
        types = (try? c.decodeIfPresent([TypeRow].self, forKey: LenientKey("types"))) ?? []
        staff = (try? c.decodeIfPresent([StaffRow].self, forKey: LenientKey("staff"))) ?? []
    }
}

/// مفتاح بالاسم لقراءة متسامحة
nonisolated struct LenientKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

nonisolated extension KeyedDecodingContainer where K == LenientKey {
    /// رقم بأي شكل (صحيح/عشري/نص) — غيابه أو null = nil
    func double(_ key: String) -> Double? {
        let k = LenientKey(key)
        if let v = try? decodeIfPresent(Double.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return Double(v) }
        if let v = try? decodeIfPresent(String.self, forKey: k) { return Double(v) }
        return nil
    }

    func int(_ key: String) -> Int { double(key).map { Int($0.rounded()) } ?? 0 }

    func string(_ key: String) -> String? {
        let k = LenientKey(key)
        if let v = try? decodeIfPresent(String.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: k) { return String(v) }
        return nil
    }
}
