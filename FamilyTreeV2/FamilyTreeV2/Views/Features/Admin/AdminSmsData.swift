import SwiftUI
import Supabase
import Combine

// MARK: - بيانات «رسائل الدخول · KWT SMS» (السيرفر الحي ٢٠٢٦-١٠-٢٠)
//
// القراءة: `sms_admin_overview()` (المالك والمدير، غيرهما 42501) — الرصيد وحالته، أرقام اليوم/٧/٣٠ يوماً، آخر ٣٠ يوماً
// يوماً بيوم، عدّاد الساعة، الحدود، عتبات التنبيه، آخر ٥٠ إرسالاً (بلا رقم هاتف: آخر ٤ خانات من البصمة فقط).
// إن فشلت (سيرفر أقدم، انقطاع) يبقى الرصيد من `sms_balance_status()` كما كان.
// الإجراءات: الدالة الطرفية `kwtsms-admin` بجلسة المستخدم — balance · senderid · coverage · status · validate ·
// test_send (المالك فقط، لرقم ملفه، مرة كل ١٠ دقائق). بيانات حساب KWT لا تخرج من السيرفر.
// العتبات: أعمدة `app_settings.sms_*` (المالك يعدّلها عبر `AppSettingsViewModel.updateSmsAlerts`).
// الحدود (الانتظار، لكل رقم/للجميع بالساعة، حفظ المحاولات): `updateSmsLimits` — المالك. اسم المرسل: `set_sender` فقط.

/// ما ترجعه `sms_admin_overview()` — فكّ متسامح: أي حقل ناقص يأخذ الافتراضي ولا يُفشل الصفحة
struct SmsOverview: Equatable {
    struct Totals: Equatable {
        var sends = 0, accepted = 0, failed = 0, unknown = 0, testSends = 0
        var points: Double = 0
        /// nil = لا إرسال في الفترة
        var acceptancePct: Double?
    }

    struct Day: Equatable {
        /// yyyy-MM-dd بتوقيت الكويت
        var day: String
        var sends = 0, accepted = 0, failed = 0, unknown = 0, testSends = 0
        var points: Double = 0
        /// آخر رصيد معروف في ذلك اليوم
        var balance: Double?
    }

    struct Limits: Equatable {
        /// `wait_seconds` = الانتظار بين رمزين كما يراه العضو (يعدّله المالك)؛ `phone_cooldown_seconds` = الانتظار − ١٠ (داخلي)
        var waitSeconds = 60, phoneCooldownSeconds = 50, phonePerHour = 5, allPerSecond = 5, allPerHour = 100, adminTestMinutes = 10
    }

    /// اسم المرسل المستخدم: المحفوظ في الإعدادات أو الافتراضي «KWT-SMS»
    struct Sender: Equatable {
        static let fallback = "KWT-SMS"
        var current = Sender.fallback
        var defaultName = Sender.fallback
        /// settings · default
        var source = "default"
        var isDefault: Bool { source != "settings" }
    }

    struct Alerts: Equatable {
        var lowThreshold = 50, urgentThreshold = 10, lowRepeatHours = 24, urgentRepeatHours = 12
    }

    /// إرسال واحد من آخر ٥٠
    struct Send: Equatable, Identifiable {
        var id = 0
        var at: Date?
        /// accepted · failed · unknown · pending
        var outcome = "unknown"
        var errorCode: String?
        var deliveryStatus: String?
        var deliveryCheckedAt: Date?
        var points: Double?
        var balanceAfter: Double?
        var msgid: String?
        var test = false
        var adminTest = false
        var phoneTail: String?
    }

    var balance: Double?
    var balanceAt: Date?
    /// ok · low · urgent · nil (لا قراءة)
    var balanceState: String?
    var avgDailyPoints7d: Double = 0
    var today = Totals(), days7 = Totals(), days30 = Totals()
    var days: [Day] = []
    var hourCount = 0, hourCap = 100
    var limits = Limits()
    /// السيرفر يرجع `wait_seconds` = أعمدة الحدود القابلة للتعديل موجودة (المالك يعدّلها من «إعدادات الإرسال»)
    var limitsEditable = false
    var alerts = Alerts()
    /// آخر رمز دخول: وضع تجريبي (لا رسالة فعلية) أو تشغيل فعلي — nil = لا إرسال محفوظ
    var lastTestMode: Bool?
    var retentionDays = 2
    /// مدة حفظ «محاولات الدخول» (إعداد المالك) — nil = السيرفر أقدم
    var loginAttemptsDays: Int?
    var sender = Sender()
    var recent: [Send] = []

    /// من رد الدالة (jsonb)
    static func decode(_ data: Data) throws -> SmsOverview {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var o = SmsOverview()
        o.balance = SmsJSON.double(root["balance"])
        o.balanceAt = ApprovalWorkflow.date(root["balance_at"] as? String)
        o.balanceState = root["balance_state"] as? String
        o.avgDailyPoints7d = SmsJSON.double(root["avg_daily_points_7d"]) ?? 0
        if let totals = root["totals"] as? [String: Any] {
            o.today = totalsFrom(totals["today"])
            o.days7 = totalsFrom(totals["days_7"])
            o.days30 = totalsFrom(totals["days_30"])
        }
        o.days = (root["days"] as? [[String: Any]] ?? []).compactMap { d in
            guard let day = d["day"] as? String else { return nil }
            return Day(day: String(day.prefix(10)),
                       sends: SmsJSON.int(d["sends"]) ?? 0, accepted: SmsJSON.int(d["accepted"]) ?? 0,
                       failed: SmsJSON.int(d["failed"]) ?? 0, unknown: SmsJSON.int(d["unknown"]) ?? 0,
                       testSends: SmsJSON.int(d["test_sends"]) ?? 0, points: SmsJSON.double(d["points"]) ?? 0,
                       balance: SmsJSON.double(d["balance"]))
        }
        if let hour = root["hour"] as? [String: Any] {
            o.hourCount = SmsJSON.int(hour["count"]) ?? 0
            o.hourCap = SmsJSON.int(hour["cap"]) ?? 100
        }
        if let l = root["limits"] as? [String: Any] {
            let d = Limits()
            let cooldown = SmsJSON.int(l["phone_cooldown_seconds"])
            o.limitsEditable = SmsJSON.int(l["wait_seconds"]) != nil
            // سيرفر أقدم بلا `wait_seconds`: الانتظار = المهلة الداخلية + ١٠
            o.limits = Limits(waitSeconds: SmsJSON.int(l["wait_seconds"]) ?? cooldown.map { $0 + 10 } ?? d.waitSeconds,
                              phoneCooldownSeconds: cooldown ?? d.phoneCooldownSeconds,
                              phonePerHour: SmsJSON.int(l["phone_per_hour"]) ?? d.phonePerHour,
                              allPerSecond: SmsJSON.int(l["all_per_second"]) ?? d.allPerSecond,
                              allPerHour: SmsJSON.int(l["all_per_hour"]) ?? d.allPerHour,
                              adminTestMinutes: SmsJSON.int(l["admin_test_minutes"]) ?? d.adminTestMinutes)
        }
        if let a = root["alerts"] as? [String: Any] {
            let d = Alerts()
            o.alerts = Alerts(lowThreshold: SmsJSON.int(a["low_threshold"]) ?? d.lowThreshold,
                              urgentThreshold: SmsJSON.int(a["urgent_threshold"]) ?? d.urgentThreshold,
                              lowRepeatHours: SmsJSON.int(a["low_repeat_hours"]) ?? d.lowRepeatHours,
                              urgentRepeatHours: SmsJSON.int(a["urgent_repeat_hours"]) ?? d.urgentRepeatHours)
        }
        o.lastTestMode = root["last_test_mode"] as? Bool
        o.retentionDays = SmsJSON.int(root["retention_days"]) ?? 2
        if let r = root["retention"] as? [String: Any] {
            o.retentionDays = SmsJSON.int(r["deliveries_days"]) ?? o.retentionDays
            o.loginAttemptsDays = SmsJSON.int(r["login_attempts_days"])
        }
        if let s = root["sender"] as? [String: Any] {
            let d = Sender()
            o.sender = Sender(current: (s["current"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? d.current,
                              defaultName: (s["default"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? d.defaultName,
                              source: s["source"] as? String ?? d.source)
        }
        o.recent = (root["recent"] as? [[String: Any]] ?? []).enumerated().map { i, r in
            Send(id: i,
                 at: ApprovalWorkflow.date(r["at"] as? String),
                 outcome: r["outcome"] as? String ?? "unknown",
                 errorCode: r["error_code"] as? String,
                 deliveryStatus: r["delivery_status"] as? String,
                 deliveryCheckedAt: ApprovalWorkflow.date(r["delivery_checked_at"] as? String),
                 points: SmsJSON.double(r["points"]),
                 balanceAfter: SmsJSON.double(r["balance_after"]),
                 msgid: r["msgid"] as? String,
                 test: r["test"] as? Bool ?? false,
                 adminTest: r["admin_test"] as? Bool ?? false,
                 phoneTail: r["phone_tail"] as? String)
        }
        return o
    }

    private static func totalsFrom(_ raw: Any?) -> Totals {
        guard let t = raw as? [String: Any] else { return Totals() }
        return Totals(sends: SmsJSON.int(t["sends"]) ?? 0, accepted: SmsJSON.int(t["accepted"]) ?? 0,
                      failed: SmsJSON.int(t["failed"]) ?? 0, unknown: SmsJSON.int(t["unknown"]) ?? 0,
                      testSends: SmsJSON.int(t["test_sends"]) ?? 0, points: SmsJSON.double(t["points"]) ?? 0,
                      acceptancePct: SmsJSON.double(t["acceptance_pct"]))
    }

    /// الأيام المتوقعة قبل نفاد الرصيد بمعدّل آخر ٧ أيام — nil بلا معدّل أو بلا رصيد
    var daysLeft: Int? {
        guard let balance, avgDailyPoints7d > 0 else { return nil }
        return Int((balance / avgDailyPoints7d).rounded(.down))
    }

    /// آخر ٣٠ يوماً متصلة (الأقدم أولاً) — اليوم بلا صفّ = صفر إرسال وبلا رصيد
    func series(today: Date = Date()) -> [Day] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SmsJSON.kuwait
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return (0..<30).reversed().map { back in
            let date = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let key = SmsJSON.dayKey.string(from: date)
            return byDay[key] ?? Day(day: key)
        }
    }
}

/// قراءة الأرقام من jsonb (عدد صحيح أو عشري أو نص رقمي)
enum SmsJSON {
    static func double(_ raw: Any?) -> Double? {
        switch raw {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func int(_ raw: Any?) -> Int? {
        double(raw).map { Int($0.rounded()) }
    }

    static let kuwait = TimeZone(identifier: "Asia/Kuwait") ?? .current

    /// مفتاح اليوم بتوقيت الكويت (نفس `day` في السيرفر)
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = kuwait
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - أخطاء الدالة الطرفية

/// خطأ من `kwtsms-admin` (`{ok:false, error:{code, provider_code?}}`) أو من الشبكة — برسالة عربية واضحة
struct SmsAdminError: Error, Equatable {
    let code: String
    var providerCode: String? = nil

    static func from(status: Int, data: Data) -> SmsAdminError {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = root?["error"] as? [String: Any]
        if let code = error?["code"] as? String {
            return SmsAdminError(code: code, providerCode: error?["provider_code"] as? String)
        }
        return SmsAdminError(code: status == 401 ? "unauthorized" : "http_\(status)")
    }

    var title: String {
        switch code {
        case "wait_10_minutes": return L10n.t("انتظر قليلاً", "Please wait")
        case "owner_only", "forbidden": return L10n.t("غير مسموح", "Not allowed")
        default: return L10n.t("لم تكتمل العملية", "Couldn't complete")
        }
    }

    var message: String {
        switch code {
        case "unauthorized":
            return L10n.t("انتهت جلستك — سجّل الدخول من جديد ثم حاول.", "Your session ended — sign in again and retry.")
        case "forbidden":
            return L10n.t("هذه الأداة للمالك والمدير فقط.", "This tool is for the owner and admins only.")
        case "owner_only":
            return L10n.t("اختبار الإرسال للمالك فقط.", "Test sending is for the owner only.")
        case "kuwait_only":
            return L10n.t("الرقم ليس جوالاً كويتياً — 8 أرقام تبدأ بـ 4 أو 5 أو 6 أو 9 (+965).",
                          "Not a Kuwaiti mobile — 8 digits starting with 4, 5, 6 or 9 (+965).")
        case "no_phone":
            return L10n.t("لا يوجد رقم جوال كويتي في ملفك — أضف رقمك أولاً.",
                          "Your profile has no Kuwaiti mobile number — add yours first.")
        case "wait_10_minutes":
            return L10n.t("أُرسل اختبار قبل أقل من 10 دقائق — اختبار واحد كل 10 دقائق حفاظاً على الرصيد. جرّب بعد قليل.",
                          "A test went out less than 10 minutes ago — one test every 10 minutes to protect the balance. Try again shortly.")
        case "rate_limited":
            return L10n.t("الإرسال مزدحم الآن، أو وصل رقمك رمز قبل قليل، أو بلغ حدّ الساعة — جرّب بعد قليل.",
                          "Sending is busy right now, your number just got a code, or the hourly limit was hit — try again shortly.")
        case "provider_error":
            let hint = providerCode.flatMap { SmsText.providerHint($0) }
            let codeText = SmsText.isolate(providerCode ?? "—")
            return hint.map { L10n.t("رفض المزوّد الطلب (\(codeText): \($0)).", "The provider refused (\(codeText): \($0)).") }
                ?? L10n.t("رفض المزوّد الطلب (\(codeText)).", "The provider refused the request (\(codeText)).")
        case "provider_unavailable":
            return L10n.t("موقع KWT SMS لم يردّ في الوقت — جرّب بعد قليل.", "KWT SMS didn't answer in time — try again shortly.")
        case "storage_unavailable", "auth_unavailable":
            return L10n.t("السيرفر مشغول الآن — جرّب بعد قليل.", "The server is busy right now — try again shortly.")
        case "not_configured":
            return L10n.t("حساب KWT SMS غير مضبوط على السيرفر.", "The KWT SMS account isn't set up on the server.")
        case "bad_msgid":
            return L10n.t("رقم الرسالة غير صالح.", "Invalid message ID.")
        case "network":
            return L10n.t("تعذّر الاتصال — تأكد من الإنترنت وجرّب مرة ثانية.", "Couldn't connect — check the internet and retry.")
        default:
            return L10n.t("حدث خطأ غير متوقع — حدّث التطبيق أو جرّب لاحقاً.", "Something went wrong — update the app or try later.")
        }
    }

    /// رسالة «تغيير اسم المرسل» (`set_sender`) — في كل الأخطاء لا يُحفظ شيء
    var senderMessage: String {
        switch code {
        case "sender_not_approved":
            return L10n.t("هذا الاسم ليس في قائمة المرسلين المعتمدين في حسابك على KWT (الحروف الكبيرة والصغيرة والمسافات تفرق) — لم يُحفظ شيء.",
                          "That name isn't on your KWT account's approved sender list (case and spaces matter) — nothing was saved.")
        case "owner_only":
            return L10n.t("تغيير اسم المرسل للمالك فقط.", "Only the owner can change the sender name.")
        case "bad_sender":
            return L10n.t("اسم المرسل غير مقبول — حروف إنجليزية وأرقام ومسافة وشرطة فقط، حتى 11 خانة.",
                          "Sender name not accepted — English letters, digits, space and dash only, up to 11 characters.")
        case "provider_unavailable":
            return L10n.t("موقع KWT SMS لم يردّ في الوقت — لم يُحفظ شيء، جرّب بعد قليل.",
                          "KWT SMS didn't answer in time — nothing was saved, try again shortly.")
        case "provider_error":
            return message + " " + L10n.t("لم يُحفظ شيء.", "Nothing was saved.")
        default:
            return message
        }
    }
}

// MARK: - المخزن المشترك

/// آخر رصيد معروف + نظرة الإدارة — مشترك بين «اليوم» وصفحة KWT SMS والأقسام
@MainActor
final class SmsBalanceStore: ObservableObject {
    static let shared = SmsBalanceStore()

    /// الرصيد وحده (من النظرة، أو من `sms_balance_status()` احتياطاً)
    struct Status: Equatable {
        /// nil = لا قراءة معروفة
        var balance: Double?
        var at: Date?
    }

    enum LoadState: Equatable { case idle, loading, loaded, denied, failed }

    /// عتبات السيرفر الافتراضية (`app_settings.sms_*`) قبل وصول النظرة
    static let defaultLowThreshold: Double = 50
    static let defaultUrgentThreshold: Double = 10
    /// مرجع مقياس الرصيد في رأس الصفحة («من ١٠٠»)
    static let gaugeReference: Double = 100
    /// صفحة شراء الرصيد في حساب KWT SMS (تحوّل لتسجيل الدخول عند المزوّد إن لم يكن مسجّلاً) — الرابط الوحيد للشحن
    static let rechargeURL = URL(string: "https://www.kwtsms.com/cportal/buy/")!

    @Published var status: Status?
    @Published var overview: SmsOverview?
    @Published private(set) var state: LoadState = .idle
    /// آخر جلب للنظرة فشل (السيرفر أقدم أو انقطاع) — الرصيد قد يكون من الدالة القديمة
    @Published private(set) var overviewFailed = false
    private var lastFetch: Date?

    enum Level { case unknown, good, low, urgent }

    /// عتبة «منخفض» (٠ = التنبيه مطفأ)
    var lowThreshold: Double { overview.map { Double($0.alerts.lowThreshold) } ?? Self.defaultLowThreshold }
    var urgentThreshold: Double { overview.map { Double($0.alerts.urgentThreshold) } ?? Self.defaultUrgentThreshold }

    var level: Level {
        guard let balance = status?.balance else { return .unknown }
        if balance < urgentThreshold { return .urgent }
        if balance < lowThreshold { return .low }
        return .good
    }

    /// تحت عتبة «منخفض» — تنبيه «اليوم» ومهمته وشارة القسم
    var needsTopUp: Bool { level == .low || level == .urgent }

    /// المالك والمدير فقط — ولا يُكرَّر الطلب خلال دقيقة إلا بالسحب للتحديث أو بعد إجراء
    func refresh(force: Bool = false) async {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < 60 { return }
        lastFetch = Date()
        state = .loading
        do {
            let data = try await SupabaseConfig.client.rpc("sms_admin_overview").execute().data
            let o = try SmsOverview.decode(data)
            overview = o
            status = Status(balance: o.balance, at: o.balanceAt)
            overviewFailed = false
            state = .loaded
            return
        } catch {
            if ErrorHelper.isCancellation(error) { state = .idle; return }
            if (error as? PostgrestError)?.code == "42501" { state = .denied; return }
            overviewFailed = true
            Log.warning("[KWT SMS] تعذّر جلب النظرة — نجرب الرصيد وحده: \(error.localizedDescription)")
        }
        await refreshBalanceOnly()
    }

    /// الاحتياط: `sms_balance_status()` (موجودة قبل النظرة)
    private func refreshBalanceOnly() async {
        nonisolated struct Row: Decodable {
            let balance: Double?
            let at: String?
        }
        do {
            let row: Row = try await SupabaseConfig.client.rpc("sms_balance_status").execute().value
            status = Status(balance: row.balance, at: ApprovalWorkflow.date(row.at))
            state = .loaded
        } catch {
            guard !ErrorHelper.isCancellation(error) else { state = .idle; return }
            state = (error as? PostgrestError)?.code == "42501" ? .denied : .failed
            Log.warning("[KWT SMS] تعذّر جلب الرصيد: \(error.localizedDescription)")
        }
    }

    // MARK: إجراءات `kwtsms-admin`

    nonisolated struct BalanceReply: Decodable {
        let balance: Double
        let testMode: Bool?
        let stored: Bool?
        enum CodingKeys: String, CodingKey { case balance, stored; case testMode = "test_mode" }
    }

    nonisolated struct SendersReply: Decodable {
        let senders: [String]
        let inUse: String?
        let inUseListed: Bool?
        enum CodingKeys: String, CodingKey { case senders; case inUse = "in_use"; case inUseListed = "in_use_listed" }
    }

    nonisolated struct CoverageReply: Decodable {
        let prefixes: [String]
        let kuwait: Bool
    }

    nonisolated struct StatusReply: Decodable {
        let status: String
        let stored: Bool?
    }

    nonisolated struct ValidateReply: Decodable {
        /// valid · no_route · invalid · unknown
        let verdict: String
    }

    nonisolated struct TestSendReply: Decodable {
        let testMode: Bool?
        let points: Double?
        let balance: Double?
        enum CodingKeys: String, CodingKey { case points, balance; case testMode = "test_mode" }
    }

    /// رد `set_sender`: المحفوظ (nil = الافتراضي) والمستخدم فعلاً
    nonisolated struct SetSenderReply: Decodable {
        let sender: String?
        let inUse: String?
        let defaultName: String?
        let source: String?
        enum CodingKeys: String, CodingKey { case sender, source; case inUse = "in_use"; case defaultName = "default" }
    }

    nonisolated struct Body: Encodable {
        let action: String
        let msgid: String?
        let phone: String?
    }

    /// جسم `set_sender` — `sender` يُرسل دائماً (null صريح = الرجوع للافتراضي؛ غيابه يرفضه السيرفر)
    nonisolated struct SenderBody: Encodable {
        let action = "set_sender"
        let sender: String?
        enum CodingKeys: String, CodingKey { case action, sender }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(action, forKey: .action)
            if let sender { try c.encode(sender, forKey: .sender) } else { try c.encodeNil(forKey: .sender) }
        }
    }

    /// نداء واحد للدالة الطرفية بجلسة المستخدم — يرمي `SmsAdminError` بسبب مفهوم
    func call<T: Decodable>(_ action: String, msgid: String? = nil, phone: String? = nil,
                            as type: T.Type = T.self) async throws -> T {
        try await call(action, body: Body(action: action, msgid: msgid, phone: phone), as: type)
    }

    private func call<B: Encodable, T: Decodable>(_ action: String, body: B, as type: T.Type) async throws -> T {
        do {
            let data: Data = try await SupabaseConfig.client.functions.invoke(
                "kwtsms-admin",
                options: FunctionInvokeOptions(method: .post, body: body)
            ) { data, _ in data }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let FunctionsError.httpError(code, data) {
            Log.warning("[KWT SMS] \(action) رُفض: \(code)")
            throw SmsAdminError.from(status: code, data: data)
        } catch let error as SmsAdminError {
            throw error
        } catch is DecodingError {
            throw SmsAdminError(code: "bad_response")
        } catch {
            if ErrorHelper.isCancellation(error) { throw error }
            throw SmsAdminError(code: "network")
        }
    }

    /// «اسم المرسل» (المالك): اسم من قائمة KWT المعتمدة، أو nil للرجوع إلى «KWT-SMS» — ثم تُعاد النظرة
    func setSender(_ sender: String?) async throws -> SetSenderReply {
        let reply = try await call("set_sender", body: SenderBody(sender: sender), as: SetSenderReply.self)
        if var o = overview {
            let d = SmsOverview.Sender()
            o.sender = SmsOverview.Sender(current: reply.inUse ?? reply.sender ?? d.current,
                                          defaultName: reply.defaultName ?? d.defaultName,
                                          source: reply.source ?? (reply.sender == nil ? "default" : "settings"))
            overview = o
        }
        await refresh(force: true)
        return reply
    }

    /// بعد حفظ المالك للحدود (تأكّد السيرفر بعدد الصفوف): تظهر القيم الجديدة فوراً قبل إعادة النظرة
    func applyLimits(_ l: SmsSendingLimits) {
        guard var o = overview else { return }
        o.limits.waitSeconds = l.waitSeconds
        o.limits.phoneCooldownSeconds = l.waitSeconds - 10
        o.limits.phonePerHour = l.perNumberHour
        o.limits.allPerHour = l.allHour
        o.hourCap = l.allHour
        o.loginAttemptsDays = l.retentionDays
        overview = o
    }

    /// «تحديث الرصيد الآن»: رصيد حي من KWT (يُحفظ في السجل اليومي) ثم تُعاد النظرة
    func refreshLiveBalance() async throws {
        let reply = try await call("balance", as: BalanceReply.self)
        status = Status(balance: reply.balance, at: Date())
        await refresh(force: true)
        // النظرة فشلت أو لم تحفظ القراءة بعد: يبقى الرصيد الحي ظاهراً
        if status?.balance == nil || reply.stored == false { status = Status(balance: reply.balance, at: Date()) }
    }
}

extension SmsBalanceStore.Level {
    var title: String {
        switch self {
        case .unknown: return L10n.t("لا قراءة", "No reading")
        case .good:    return L10n.t("جيد", "Good")
        case .low:     return L10n.t("منخفض", "Low")
        case .urgent:  return L10n.t("عاجل", "Urgent")
        }
    }

    /// لون المعنى: جيد أخضر، منخفض تحذير، عاجل خطأ
    var tint: Color {
        switch self {
        case .unknown: return DS.Color.textTertiary
        case .good:    return DS.Color.success
        case .low:     return DS.Color.warning
        case .urgent:  return DS.Color.error
        }
    }

    /// لون الرقم الكبير فوق الكحلي
    var bandTint: Color {
        switch self {
        case .unknown: return DS.Color.textOnPrimary
        case .good:    return DS.Hub.kpiMine
        case .low:     return DS.Hub.kpiLate
        case .urgent:  return DS.Hub.kpiHot
        }
    }
}

// MARK: - النصوص المشتركة

/// نصوص الرصيد المشتركة (اليوم + الصفحة)
enum SmsBalanceText {
    static func points(_ balance: Double) -> String { "\(Int(balance.rounded(.down)))" }

    /// «يكفي نحو ١٧ رمز دخول» — كل رسالة دخول بنقطة واحدة (٥٣ حرفاً)
    static func enough(_ balance: Double) -> String {
        let n = Int(balance.rounded(.down))
        return L10n.t("يكفي نحو \(n) رمز دخول", "Enough for about \(n) sign-in codes")
    }

    /// «آخر تحديث قبل ساعتين»
    static func updated(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.unitsStyle = .full
        return L10n.t("آخر تحديث \(f.localizedString(for: date, relativeTo: Date()))",
                      "Updated \(f.localizedString(for: date, relativeTo: Date()))")
    }

    static let noReading = L10n.t("لا توجد قراءة بعد — اضغط «تحديث الرصيد الآن»",
                                  "No reading yet — tap “Refresh balance now”")
}

/// نصوص الصفحة: النتائج، رموز الأخطاء، حالة المزوّد، الوقت
enum SmsText {
    /// تلميح قصير لرموز KWT الشائعة — غيرها يظهر برمزه فقط
    static func providerHint(_ code: String) -> String? {
        switch code {
        case "ERR001": return L10n.t("الربط البرمجي مطفأ في الحساب", "API disabled on the account")
        case "ERR003": return L10n.t("بيانات حساب KWT خاطئة", "Wrong KWT account credentials")
        case "ERR005": return L10n.t("الحساب موقوف", "Account blocked")
        case "ERR010": return L10n.t("الرصيد صفر", "Zero balance")
        case "ERR011": return L10n.t("الرصيد لا يكفي", "Insufficient balance")
        case "ERR013": return L10n.t("طابور الإرسال ممتلئ", "Send queue full")
        case "ERR024": return L10n.t("عنوان السيرفر غير مسموح في الحساب", "Server IP not allowed")
        case "ERR025": return L10n.t("رقم غير صالح", "Invalid number")
        case "ERR026": return L10n.t("الدولة غير مفعّلة في الحساب", "Country not activated")
        case "ERR028": return L10n.t("إرسال متكرر لنفس الرقم — انتظر قليلاً", "Repeat send to the same number — wait")
        case "ERR029": return L10n.t("الرسالة غير موجودة عند المزوّد", "Message not found at the provider")
        case "ERR030": return L10n.t("عالقة في الطابور بخطأ", "Stuck in the queue with an error")
        case "TIMEOUT": return L10n.t("انتهت المهلة", "Timed out")
        case "NETWORK": return L10n.t("انقطاع", "Connection dropped")
        case "BAD_RESPONSE": return L10n.t("رد غير مفهوم", "Unreadable reply")
        default:
            return code.hasPrefix("HTTP_") ? L10n.t("خطأ من المزوّد", "Provider error") : nil
        }
    }

    /// «ERR010 · الرصيد صفر» أو الرمز وحده
    static func errorLine(_ code: String) -> String {
        providerHint(code).map { "\(isolate(code)) · \($0)" } ?? code
    }

    /// يعزل نصاً لاتينياً (رمز، بصمة) داخل سطر عربي — لا يقلب ترتيب ما حوله
    static func isolate(_ text: String) -> String { "\u{2068}\(text)\u{2069}" }

    /// حالة الرسالة من فحص «status» بكلام مفهوم
    static func deliveryStatus(_ raw: String) -> String {
        let s = raw.lowercased()
        if raw == "ERR029" { return L10n.t("غير موجودة عند المزوّد", "Not found at the provider") }
        if raw == "ERR030" { return L10n.t("عالقة في الطابور بخطأ", "Stuck in the queue with an error") }
        if s.contains("deliver") { return L10n.t("وصلت", "Delivered") }
        if s.contains("fail") || s.contains("reject") || s.contains("error") { return L10n.t("فشلت", "Failed") }
        if s.contains("queue") || s.contains("pending") { return L10n.t("في الطابور", "Queued") }
        if s.contains("sent") { return L10n.t("خرجت من المزوّد", "Sent by the provider") }
        return raw
    }

    /// «10:42» اليوم، «أمس 10:42»، وإلا «18 أكتوبر 10:42» — أرقام لاتينية كبقية اللوحة
    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let cal = Calendar.current
        clock.locale = locale
        clock.setLocalizedDateFormatFromTemplate("jjmm")
        if cal.isDateInToday(date) { return clock.string(from: date) }
        if cal.isDateInYesterday(date) { return L10n.t("أمس \(clock.string(from: date))", "Yesterday \(clock.string(from: date))") }
        dayClock.locale = locale
        dayClock.setLocalizedDateFormatFromTemplate("dMMMjjmm")
        return dayClock.string(from: date)
    }

    /// «18 أكتوبر» لمحور الرسم
    static func shortDay(_ key: String) -> String {
        guard let date = SmsJSON.dayKey.date(from: key) else { return key }
        dayOnly.locale = locale
        dayOnly.timeZone = SmsJSON.kuwait
        dayOnly.setLocalizedDateFormatFromTemplate("dMMM")
        return dayOnly.string(from: date)
    }

    /// نسبة بلا كسور إن كانت صحيحة («98%» أو «97.5%»)
    static func percent(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    /// «يوم واحد» · «يومين» · «5 أيام» · «12 يوماً»
    static func days(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 day" : "\(n) days" }
        switch n {
        case 0: return "أقل من يوم"
        case 1: return "يوم واحد"
        case 2: return "يومين"
        case 3...10: return "\(n) أيام"
        default: return "\(n) يوماً"
        }
    }

    /// نقاط بلا كسور إن كانت صحيحة
    static func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private static var locale: Locale { Locale(identifier: L10n.isArabic ? "ar@numbers=latn" : "en") }
    private static let clock = DateFormatter()
    private static let dayClock = DateFormatter()
    private static let dayOnly = DateFormatter()
}
