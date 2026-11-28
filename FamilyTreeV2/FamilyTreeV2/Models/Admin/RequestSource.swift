import Foundation

// MARK: - «من أرسل الطلب ومن أين» (طلب المالك ٢٠٢٦-١١-١١)
//
// `admin_requests.sent_from` — مسار الإرسال كما مرّ به العضو حتى زرّ الإرسال: ٢–٤ خطوات {icon, title}
// (رمز SF Symbol + عنوان عربي رسمي). الشاشة التي تُرسل الطلب تمرّره صراحةً، وكل دالة إرسال لها مسار افتراضي.
// `admin_requests.sent_via` — يكتبه السيرفر وحده من ترويسات `SupabaseConfig.appHeaders` (المنصة والنسخة والبناء).
// السيرفر (20261111150000) ينظّف المسار ويحفظ الفاسد NULL ولا يغيّر العمودين بعد الإدراج. قبل تطبيقه يُعاد
// الإدراج بلا المسار (`AdminRequestSource.insert`) فلا يتعطّل إرسال أي طلب.

/// خطوة واحدة في مسار الإرسال
nonisolated struct RequestSourceStep: Codable, Hashable, Sendable {
    let icon: String
    let title: String

    init(_ icon: String, _ title: String) {
        self.icon = icon
        self.title = title
    }

    // ── خطوات البداية المشتركة (العناوين بالعربية دائماً: بيانات تقرؤها الإدارة لا واجهة المرسل) ──
    static let tree = RequestSourceStep("tree.fill", "الشجرة")
    static let womenTree = RequestSourceStep("tree.fill", "شجرة النساء")
    static let profile = RequestSourceStep("person.crop.circle", "الملف الشخصي")
    static let profileFamily = RequestSourceStep("figure.2.and.child.holdinghands", "الأسرة")
    static let home = RequestSourceStep("house.fill", "الرئيسية")
    static let contact = RequestSourceStep("envelope.fill", "التواصل")
    static let registration = RequestSourceStep("person.badge.plus", "التسجيل")
    static let notifications = RequestSourceStep("bell.fill", "الإشعارات")
    static let admin = RequestSourceStep("shield.lefthalf.filled", "لوحة الإدارة")

    /// خطوة باسم عضو (تفاصيله في الشجرة)
    static func member(_ name: String?) -> RequestSourceStep? {
        let clean = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : RequestSourceStep("person.fill", clean)
    }
}

/// مسار الإرسال كاملاً — يُرسل مصفوفة JSON ويُقرأ بتسامح (أي شكل غير متوقّع = بلا مسار)
nonisolated struct RequestSource: Codable, Hashable, Sendable {
    /// حدود السيرفر: ١–٥ خطوات، الرمز ≤٤٠ والعنوان ≤١٢٠
    static let maxSteps = 5
    static let maxTitle = 120
    static let maxIcon = 40

    let steps: [RequestSourceStep]

    init(_ steps: [RequestSourceStep?]) {
        self.steps = steps.compactMap { step -> RequestSourceStep? in
            guard let step else { return nil }
            let title = step.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !title.isEmpty else { return nil }
            let icon = step.icon.count <= Self.maxIcon ? step.icon : ""
            return RequestSourceStep(icon, String(title.prefix(Self.maxTitle)))
        }
        .prefix(Self.maxSteps)
        .map { $0 }
    }

    init(_ steps: RequestSourceStep?...) {
        self.init(steps)
    }

    var isEmpty: Bool { steps.isEmpty }

    // ── مسارات مشتركة لأكثر من شاشة ──
    /// «الملف الشخصي ← تعديل البيانات»
    static let profileEdit = RequestSource(.profile, RequestSourceStep("pencil", "تعديل البيانات"))
    /// «الملف الشخصي ← الأسرة ← تعديل ابن»
    static let profileChildEdit = RequestSource(.profile, .profileFamily, RequestSourceStep("pencil", "تعديل بيانات ابن"))
    /// تذكير الصورة الشخصية (النافذة المنبثقة)
    static let photoReminder = RequestSource(.home, RequestSourceStep("camera.fill", "تذكير الصورة الشخصية"),
                                             RequestSourceStep("photo.badge.plus", "إضافة صورة"))

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        steps = ((try? container.decode([LossyStep].self)) ?? []).compactMap(\.step)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(steps)
    }

    /// خطوة تُقرأ بتسامح — العنصر الفاسد يُسقط وحده
    private struct LossyStep: Decodable {
        let step: RequestSourceStep?
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            let title = (try? c?.decodeIfPresent(String.self, forKey: .title)) ?? nil
            let icon = (try? c?.decodeIfPresent(String.self, forKey: .icon)) ?? nil
            if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                step = RequestSourceStep(icon ?? "", title)
            } else {
                step = nil
            }
        }
        enum CodingKeys: String, CodingKey { case icon, title }
    }
}

/// الجهاز الذي أُرسل منه الطلب (`admin_requests.sent_via`) — يكتبه السيرفر، ويُقرأ بتسامح
nonisolated struct RequestSentVia: Codable, Hashable, Sendable {
    var platform: String?
    var appVersion: String?
    var appBuild: String?
    var at: String?

    enum CodingKeys: String, CodingKey {
        case platform, at
        case appVersion = "app_version"
        case appBuild = "app_build"
    }

    init(platform: String?, appVersion: String? = nil, appBuild: String? = nil, at: String? = nil) {
        self.platform = platform
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        platform = (try? c?.decodeIfPresent(String.self, forKey: .platform)) ?? nil
        appVersion = (try? c?.decodeIfPresent(String.self, forKey: .appVersion)) ?? nil
        appBuild = (try? c?.decodeIfPresent(String.self, forKey: .appBuild)) ?? nil
        at = (try? c?.decodeIfPresent(String.self, forKey: .at)) ?? nil
    }

    /// اسم المنصة بالعربية الرسمية
    var platformName: String {
        switch platform?.lowercased() {
        case "ios": return L10n.t("آيفون", "iPhone")
        case "android": return L10n.t("أندرويد", "Android")
        case "web": return L10n.t("الموقع", "Website")
        case "server": return L10n.t("السيرفر", "Server")
        default: return L10n.t("غير معروف", "Unknown")
        }
    }

    /// «آيفون 1.0.2 (51)» — النسخة والبناء إن سُجّلا
    var deviceLine: String {
        var line = platformName
        if let v = appVersion, !v.isEmpty {
            line += " \u{2066}\(v)\u{2069}"
            if let b = appBuild, !b.isEmpty { line += " \u{2066}(\(b))\u{2069}" }
        }
        return line
    }
}

// MARK: - الإدراج بالمسار، والرجوع بلا مسار على سيرفر أقدم

enum AdminRequestSource {
    /// يضيف `sent_from` إلى حمولة الإدراج (إن وُجد مسار)
    static func payload(_ base: [String: AnyEncodable], _ source: RequestSource?) -> [String: AnyEncodable] {
        guard let source, !source.isEmpty else { return base }
        var payload = base
        payload["sent_from"] = AnyEncodable(source)
        return payload
    }

    /// يجرّب الإدراج بالمسار؛ إن رفضه سيرفر بلا العمود (قبل 20261111150000) يُعاد بلا المسار —
    /// إرسال الطلب لا يتعطّل أبداً بسبب المسار
    @MainActor @discardableResult
    static func send<T>(_ source: RequestSource?, _ operation: (RequestSource?) async throws -> T) async throws -> T {
        guard let source, !source.isEmpty else { return try await operation(nil) }
        do {
            return try await operation(source)
        } catch where ErrorHelper.isMissingColumn(error, column: "sent_from") {
            Log.warning("[RequestSource] السيرفر بلا sent_from — يُعاد الإدراج بلا المسار")
            return try await operation(nil)
        }
    }
}
