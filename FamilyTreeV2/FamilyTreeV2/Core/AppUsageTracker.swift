import SwiftUI
import UIKit
import Supabase
import PostgREST

// MARK: - جلسات الاستخدام من التطبيق (طلب المالك ٢٠٢٦-١٠-٢٢ — «الاستخدام» في «المؤشرات»)
//
// جلسة = من دخول التطبيق للواجهة إلى خروجه للخلفية. عند الخروج نداء واحد `log_app_session(p_seconds, p_screen)`:
// مدة الجلسة بالثواني (السيرفر يقصّها عند ٣٦٠٠) والشاشة التي أخذت أطول وقت فيها. للحساب المفعّل الكامل فقط (`MainTabView`
// ظاهر)، والسيرفر يتجاهل المعلّق والموقوف. أقل من ٥ ثوانٍ لا تُرسل. بلا إعادة محاولة ولا تخزين — المؤقّت في الذاكرة فقط،
// والخطأ (دالة غير موجودة، بلا اتصال) سطر تحذير.
// الشاشة الحالية: تبويب `MainTabView` المختار، وفوقه آخر صفحة ظاهرة فيه بـ `.appUsageScreen(_:)` (المكتبة، المشاريع،
// الأخبار، الإشعارات، صفحة العضو) — كل صفحة تزيل نفسها بمعرّفها عند اختفائها (نفس آلية `AppSection.current`).

/// معرّفات الشاشات الثابتة (السيرفر يقبل `^[a-z][a-z0-9_]*$` ≤ ٤٠ حرفاً) وأسماؤها في لوحة الإدارة
enum AppUsageScreen: String, CaseIterable {
    case home, news, tree, diwaniyas, profile, admin, library, projects, notifications
    case memberDetails = "member_details"

    /// تبويب `MainTabView` (٠ الرئيسية … ٤ الإدارة — نفس ترتيب `AppSection`)
    init?(tab: Int) {
        switch tab {
        case 0: self = .home
        case 1: self = .tree
        case 2: self = .diwaniyas
        case 3: self = .profile
        case 4: self = .admin
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .home:          return L10n.t("الرئيسية", "Home")
        case .news:          return L10n.t("الأخبار", "News")
        case .tree:          return L10n.t("الشجرة", "Tree")
        case .diwaniyas:     return L10n.t("الديوانيات", "Diwaniyas")
        case .profile:       return L10n.t("حسابي", "Profile")
        case .admin:         return L10n.t("الإدارة", "Admin")
        case .library:       return L10n.t("المكتبة", "Library")
        case .projects:      return L10n.t("المشاريع", "Projects")
        case .notifications: return L10n.t("الإشعارات", "Notifications")
        case .memberDetails: return L10n.t("صفحة العضو", "Member page")
        }
    }

    var icon: String {
        switch self {
        case .home:          return AppSection.home.symbol
        case .news:          return AppSection.news.symbol
        case .tree:          return AppSection.tree.symbol
        case .diwaniyas:     return AppSection.diwaniyas.symbol
        case .profile:       return AppSection.profile.symbol
        case .admin:         return AppSection.admin.symbol
        case .library:       return AppSection.library.symbol
        case .projects:      return AppSection.projects.symbol
        case .notifications: return "bell.fill"
        case .memberDetails: return "person.text.rectangle.fill"
        }
    }

    /// اسم معرّف من السيرفر — غير المعروف يُعرض كما هو
    static func title(_ id: String) -> String { AppUsageScreen(rawValue: id)?.title ?? id }
    static func icon(_ id: String) -> String { AppUsageScreen(rawValue: id)?.icon ?? "square.grid.2x2.fill" }
}

/// مؤقّت الجلسة الواحد — في الذاكرة فقط
@MainActor
final class AppUsageTracker {
    static let shared = AppUsageTracker()

    /// أقصر جلسة تُرسل، وأطولها (السيرفر يقصّ عندها أيضاً)
    static let minimumSeconds: TimeInterval = 5
    static let maximumSeconds = 3600
    /// حدّ أمان لقائمة الصفحات المفتوحة (لا تنمو إن فات اختفاء)
    private static let pageCap = 16

    /// `MainTabView` ظاهر لحساب مفعّل
    private var enabled = false
    private var tab: AppUsageScreen = .home
    private var pages: [(id: UUID, screen: AppUsageScreen, tab: AppUsageScreen)] = []
    private var sessionStart: Date?
    private var timed: AppUsageScreen?
    private var timedSince: Date?
    private var totals: [AppUsageScreen: TimeInterval] = [:]
    private var observing = false

    private init() {}

    // MARK: التبويبات

    /// `MainTabView` ظهر — يبدأ الجلسة إن كان التطبيق في الواجهة (جلسة جارية تبقى كما هي)
    func start(tab index: Int) {
        enabled = true
        if let screen = AppUsageScreen(tab: index) { tab = screen }
        observeApp()
        if sessionStart == nil, UIApplication.shared.applicationState != .background {
            begin()
        } else {
            retime()
        }
    }

    /// خرج من التبويبات (تسجيل الخروج، الانتظار، الإيقاف) — الجلسة الجارية تُترك بلا إرسال
    func stop() {
        enabled = false
        pages.removeAll()
        reset()
    }

    func setTab(_ index: Int) {
        guard let screen = AppUsageScreen(tab: index), screen != tab else { return }
        tab = screen
        retime()
    }

    // MARK: الصفحات

    func pageAppeared(_ id: UUID, _ screen: AppUsageScreen) {
        pages.removeAll { $0.id == id }
        pages.append((id, screen, tab))
        if pages.count > Self.pageCap { pages.removeFirst(pages.count - Self.pageCap) }
        retime()
    }

    func pageDisappeared(_ id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        pages.removeAll { $0.id == id }
        retime()
    }

    /// آخر صفحة ظاهرة في التبويب المختار، وإلا التبويب نفسه
    private var current: AppUsageScreen {
        pages.last(where: { $0.tab == tab })?.screen ?? tab
    }

    // MARK: الجلسة

    private func observeApp() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppUsageTracker.shared.finish() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppUsageTracker.shared.resume() }
        }
    }

    private func resume() {
        guard enabled, sessionStart == nil else { return }
        begin()
    }

    private func begin(at now: Date = Date()) {
        sessionStart = now
        totals = [:]
        timed = current
        timedSince = now
    }

    /// يضيف وقت الشاشة السابقة ويبدأ عدّ الحالية
    private func retime(at now: Date = Date()) {
        guard sessionStart != nil else { return }
        let screen = current
        guard screen != timed else { return }
        addTimed(until: now)
        timed = screen
        timedSince = now
    }

    private func addTimed(until now: Date) {
        if let timed, let since = timedSince {
            totals[timed, default: 0] += max(0, now.timeIntervalSince(since))
        }
    }

    /// الخروج للخلفية: يرسل الجلسة مرة واحدة (إن طالت ٥ ثوانٍ فأكثر)
    private func finish(at now: Date = Date()) {
        guard let start = sessionStart else { return }
        addTimed(until: now)
        let seconds = now.timeIntervalSince(start)
        let top = totals.max { $0.value < $1.value }?.key
        reset()
        guard enabled, seconds >= Self.minimumSeconds else { return }
        send(seconds: min(Int(seconds.rounded()), Self.maximumSeconds), screen: top)
    }

    private func reset() {
        sessionStart = nil
        timed = nil
        timedSince = nil
        totals = [:]
    }

    /// نداء واحد بلا إعادة — مهلة خلفية قصيرة كي يكتمل بعد الخروج، والخطأ سطر تحذير فقط
    private func send(seconds: Int, screen: AppUsageScreen?) {
        nonisolated struct Params: Encodable {
            let p_seconds: Int
            let p_screen: String?
        }
        let params = Params(p_seconds: seconds, p_screen: screen?.rawValue)
        let background = AppUsageBackgroundTask()
        background.begin()
        Task {
            defer { background.end() }
            do {
                _ = try await SupabaseConfig.client.rpc("log_app_session", params: params).execute()
            } catch {
                guard !ErrorHelper.isCancellation(error) else { return }
                Log.warning("[Usage] تعذّر تسجيل الجلسة: \(error.localizedDescription)")
            }
        }
    }
}

/// مهلة الخلفية لنداء الجلسة — تنتهي بانتهائه أو بانتهاء وقت النظام
@MainActor
private final class AppUsageBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: "app-usage-session") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

// MARK: - تعليم الصفحة

private struct AppUsageScreenModifier: ViewModifier {
    let screen: AppUsageScreen?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let screen { AppUsageTracker.shared.pageAppeared(id, screen) }
            }
            .onDisappear { AppUsageTracker.shared.pageDisappeared(id) }
    }
}

extension View {
    /// صفحة تُحسب باسمها في جلسات الاستخدام ما دامت ظاهرة (nil = تُحسب للتبويب)
    func appUsageScreen(_ screen: AppUsageScreen?) -> some View {
        modifier(AppUsageScreenModifier(screen: screen))
    }
}
