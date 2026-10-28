import SwiftUI
import Supabase
import PostgREST
import Combine

// MARK: - بيانات «الاستخدام» الجديدة (طلب المالك ٢٠٢٦-١٠-٢٢): النشطون واتجاههم + الجلسات
//
// دالتان على السيرفر (المالك والمدير فقط — غيرهما 42501)، الفترة ٧ / ٣٠ / ٩٠ يوماً:
// - `app_usage_trend(p_days)`: لقطة كل ليلة 12:00 بتوقيت الكويت (`history` — الأيام قبل اليوم) + «اليوم» حيّاً (`today`):
//   النشطون منذ منتصف الليل · خلال ٧ أيام · خلال ٣٠ يوماً، من `members` (حيّ برقم وجهاز مسجّل).
// - `app_usage_engagement(p_days)`: من جلسات التطبيق (`log_app_session` — `AppUsageTracker`): لكل يوم الجلسات والأعضاء
//   والدقائق، أكثر الشاشات (جلسة لكل شاشة أطول وقت)، وأكثر الأعضاء استخداماً (حتى ٢٠).
// فكّ متسامح كـ `SmsLoginAttempts.decode`؛ مخزن واحد يجلبهما معاً، لا يكرّر خلال دقيقة إلا بالسحب للتحديث.

/// ما ترجعه `app_usage_trend(p_days)`
struct AppUsageTrend: Equatable {
    struct Point: Equatable {
        /// yyyy-MM-dd بتوقيت الكويت
        var day = ""
        var active1d = 0, active7d = 0, active30d = 0, members = 0
        var live = false
    }

    /// يوم في الرسم — بلا لقطة = nil
    struct Slot: Identifiable, Equatable {
        let day: String
        let point: Point?
        var id: String { day }
    }

    var days = 30
    var generatedAt: Date?
    var history: [Point] = []
    var today: Point?

    static func decode(_ data: Data) throws -> AppUsageTrend {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var r = AppUsageTrend()
        r.days = SmsJSON.int(root["days"]) ?? 30
        r.generatedAt = ApprovalWorkflow.date(root["generated_at"] as? String)
        r.history = (root["history"] as? [[String: Any]] ?? []).compactMap { point($0) }.sorted { $0.day < $1.day }
        r.today = (root["today"] as? [String: Any]).flatMap { point($0) }
        return r
    }

    private static func point(_ x: [String: Any]) -> Point? {
        guard let day = x["day"] as? String, !day.isEmpty else { return nil }
        return Point(day: String(day.prefix(10)),
                     active1d: SmsJSON.int(x["active_1d"]) ?? 0, active7d: SmsJSON.int(x["active_7d"]) ?? 0,
                     active30d: SmsJSON.int(x["active_30d"]) ?? 0, members: SmsJSON.int(x["members"]) ?? 0,
                     live: x["live"] as? Bool ?? false)
    }

    /// أيام الفترة كاملة، الأقدم أولاً وآخرها اليوم (الحيّ)
    func slots(days: Int) -> [Slot] {
        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return AppUsageDays.keys(days: days, today: today?.day).map { key in
            Slot(day: key, point: key == today?.day ? today : byDay[key])
        }
    }
}

/// ما ترجعه `app_usage_engagement(p_days)`
struct AppUsageEngagement: Equatable {
    struct Day: Equatable {
        var day = ""
        var sessions = 0, members = 0, minutes = 0
    }

    struct Screen: Equatable, Identifiable {
        var screen = ""
        var opens = 0
        var id: String { screen }
    }

    struct Member: Equatable, Identifiable {
        /// ترتيبه في الرد
        var id = 0
        var memberId: UUID?
        var name: String?
        var days = 0, sessions = 0, minutes = 0
    }

    var days = 30
    var from = ""
    var generatedAt: Date?
    var daily: [Day] = []
    var screens: [Screen] = []
    var members: [Member] = []

    /// وصلت جلسات من التطبيق في الفترة (قبل تحديث التطبيق لا شيء)
    var hasData: Bool { daily.contains { $0.sessions > 0 } }
    var totalSessions: Int { daily.reduce(0) { $0 + $1.sessions } }
    var totalMinutes: Int { daily.reduce(0) { $0 + $1.minutes } }
    /// متوسط الأعضاء في اليوم — على الأيام التي فيها استخدام
    var averageMembers: Int {
        let used = daily.filter { $0.members > 0 }
        guard !used.isEmpty else { return 0 }
        return Int((Double(used.reduce(0) { $0 + $1.members }) / Double(used.count)).rounded())
    }

    static func decode(_ data: Data) throws -> AppUsageEngagement {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var r = AppUsageEngagement()
        r.days = SmsJSON.int(root["days"]) ?? 30
        r.from = (root["from"] as? String).map { String($0.prefix(10)) } ?? ""
        r.generatedAt = ApprovalWorkflow.date(root["generated_at"] as? String)
        r.daily = (root["daily"] as? [[String: Any]] ?? []).compactMap { x in
            guard let day = x["day"] as? String, !day.isEmpty else { return nil }
            return Day(day: String(day.prefix(10)), sessions: SmsJSON.int(x["sessions"]) ?? 0,
                       members: SmsJSON.int(x["members"]) ?? 0, minutes: SmsJSON.int(x["minutes"]) ?? 0)
        }
        .sorted { $0.day < $1.day }
        r.screens = (root["screens"] as? [[String: Any]] ?? []).compactMap { x in
            guard let screen = x["screen"] as? String, !screen.isEmpty else { return nil }
            return Screen(screen: screen, opens: SmsJSON.int(x["opens"]) ?? 0)
        }
        .sorted { $0.opens > $1.opens }
        r.members = (root["members"] as? [[String: Any]] ?? []).enumerated().map { i, x in
            Member(id: i,
                   memberId: (x["member_id"] as? String).flatMap(UUID.init(uuidString:)),
                   name: (x["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                   days: SmsJSON.int(x["days"]) ?? 0, sessions: SmsJSON.int(x["sessions"]) ?? 0,
                   minutes: SmsJSON.int(x["minutes"]) ?? 0)
        }
        return r
    }

    /// الجلسات لكل يوم من أيام الفترة (الأقدم أولاً، آخرها اليوم) — اليوم بلا جلسات = ٠
    func sessionsPerDay(days: Int, today: String?) -> [(day: String, sessions: Int)] {
        let byDay = Dictionary(daily.map { ($0.day, $0.sessions) }, uniquingKeysWith: { a, _ in a })
        return AppUsageDays.keys(days: days, today: today).map { ($0, byDay[$0] ?? 0) }
    }
}

/// مفاتيح الأيام بتوقيت الكويت (نفس `day` في السيرفر)
enum AppUsageDays {
    /// آخر `days` يوماً، الأقدم أولاً وآخرها اليوم (من السيرفر إن عُرف)
    static func keys(days: Int, today: String?) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SmsJSON.kuwait
        let todayKey = today ?? SmsJSON.dayKey.string(from: Date())
        guard let base = SmsJSON.dayKey.date(from: todayKey), days > 0 else { return [] }
        return (0..<days).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: base).map { SmsJSON.dayKey.string(from: $0) }
        }
    }
}

// MARK: - المخزن

@MainActor
final class AdminUsageStore: ObservableObject {
    static let shared = AdminUsageStore()
    /// فترات المبدّل بالأيام
    static let periods = [7, 30, 90]

    @Published private(set) var days = 30
    @Published private(set) var trends: [Int: AppUsageTrend] = [:]
    @Published private(set) var engagements: [Int: AppUsageEngagement] = [:]
    /// «اليوم» الحيّ من آخر جلب (الحلقات — لا تتبع الفترة)
    @Published private(set) var today: AppUsageTrend.Point?
    @Published private(set) var loading: Set<Int> = []
    @Published private(set) var failed: Set<Int> = []
    @Published private(set) var denied = false
    private var fetchedAt: [Int: Date] = [:]

    var trend: AppUsageTrend? { trends[days] }
    var engagement: AppUsageEngagement? { engagements[days] }
    var isLoading: Bool { loading.contains(days) }
    var isFailed: Bool { failed.contains(days) }

    func select(_ period: Int) {
        guard period != days, Self.periods.contains(period) else { return }
        days = period
        Task { await refresh() }
    }

    /// يجلب الفترة المختارة (الدالتان معاً) — لا يُكرَّر خلال دقيقة إلا بالسحب للتحديث
    func refresh(force: Bool = false) async {
        let period = days
        if !force, let at = fetchedAt[period], Date().timeIntervalSince(at) < 60 { return }
        guard !loading.contains(period) else { return }
        fetchedAt[period] = Date()
        loading.insert(period)
        defer { loading.remove(period) }
        async let trendOK = loadTrend(period)
        async let engagementOK = loadEngagement(period)
        let (t, e) = await (trendOK, engagementOK)
        if t && e { failed.remove(period) } else if !denied { failed.insert(period) }
    }

    private func loadTrend(_ period: Int) async -> Bool {
        do {
            let data = try await SupabaseConfig.client
                .rpc("app_usage_trend", params: ["p_days": period])
                .execute().data
            let trend = try AppUsageTrend.decode(data)
            trends[period] = trend
            if let live = trend.today { today = live }
            denied = false
            return true
        } catch {
            return handle(error, period, "اتجاه الاستخدام")
        }
    }

    private func loadEngagement(_ period: Int) async -> Bool {
        do {
            let data = try await SupabaseConfig.client
                .rpc("app_usage_engagement", params: ["p_days": period])
                .execute().data
            engagements[period] = try AppUsageEngagement.decode(data)
            return true
        } catch {
            return handle(error, period, "جلسات الاستخدام")
        }
    }

    /// إلغاء = يُجلب في المرة القادمة، 42501 = ليس للمستخدم، غيره تحذير
    private func handle(_ error: Error, _ period: Int, _ what: String) -> Bool {
        if ErrorHelper.isCancellation(error) { fetchedAt[period] = nil; return true }
        if (error as? PostgrestError)?.code == "42501" { denied = true; return false }
        Log.warning("[Usage] تعذّر جلب \(what): \(error.localizedDescription)")
        return false
    }
}

// MARK: - النصوص

enum AdminUsageText {
    /// «7 أيام» · «30 يوماً» · «90 يوماً»
    static func period(_ days: Int) -> String {
        days <= 10 ? L10n.t("\(days) أيام", "\(days) days") : L10n.t("\(days) يوماً", "\(days) days")
    }

    /// «آخر 30 يوماً»
    static func last(_ days: Int) -> String { L10n.t("آخر \(period(days))", "Last \(period(days))") }

    /// «جلسة واحدة» · «جلستان» · «5 جلسات» · «12 جلسة»
    static func sessions(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 session" : "\(n) sessions" }
        switch n {
        case 1: return "جلسة واحدة"
        case 2: return "جلستان"
        case 3...10: return "\(n) جلسات"
        default: return "\(n) جلسة"
        }
    }

    /// «دقيقة واحدة» · «دقيقتان» · «5 دقائق» · «12 دقيقة»
    static func minutes(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 min" : "\(n) min" }
        switch n {
        case 1: return "دقيقة واحدة"
        case 2: return "دقيقتان"
        case 3...10: return "\(n) دقائق"
        default: return "\(n) دقيقة"
        }
    }
}
