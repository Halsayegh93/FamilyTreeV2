import SwiftUI
import Combine
import Supabase

// MARK: - «إعلانات عند فتح التطبيق» (موافقة المالك ٢٠٢٦-١١-١٢، العينة launch-announcements)
//
// صورة يرفعها المالك/المدير من «إنشاء ← إعلان» تظهر للعضو كل ما يفتح التطبيق (تشغيل جديد، أو رجوع من الخلفية بعد
// ٣٠ دقيقة — `app_config.launch_announcements_resume_minutes`) لين تخلص مدّتها. أكثر من إعلان: واحد ورا الثاني.
// الترتيب عند الفتح: الإعلانات ← «ما الجديد» ← «كمّل ملفك بصورة». شاشة التحديث الإجباري لا تتأثر (لا تبويبات تحتها).
// الجدول `public.launch_announcements` (الترحيل 20261112170000) — العضو يقرأ الشغّالة الموجّهة له فقط (RLS)،
// والمالك والمدير يقرؤون الكل، فالتطبيق يصفّي أيضاً. الصورة في مستودع `news` تحت `launch/`، وتُعرض موقّعة
// (`CachedImageLoader` ← `StorageURLResolver`) مثل صور الأخبار.

/// صفّ من `launch_announcements`
struct LaunchAnnouncement: Codable, Identifiable, Equatable {
    let id: UUID
    /// مسار داخل مستودع `news` — `launch/<uuid>.jpg`
    let imagePath: String
    /// none · update · news · link
    let buttonKind: String
    let buttonTitle: String?
    let buttonUrl: String?
    /// nil = الكل
    let memberIds: [UUID]?
    let startsAt: String
    let endsAt: String
    let stoppedAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imagePath = "image_path"
        case buttonKind = "button_kind"
        case buttonTitle = "button_title"
        case buttonUrl = "button_url"
        case memberIds = "member_ids"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case stoppedAt = "stopped_at"
        case createdAt = "created_at"
    }

    enum Kind: String, CaseIterable { case none, update, news, link }

    var kind: Kind { Kind(rawValue: buttonKind) ?? .none }
    var starts: Date? { AppUpdateDates.parse(startsAt) }
    var ends: Date? { AppUpdateDates.parse(endsAt) }
    var stopped: Date? { AppUpdateDates.parse(stoppedAt) }

    /// شغّال الآن: غير موقوف، بدأ، ولم ينتهِ
    func isActive(at now: Date = Date()) -> Bool {
        guard stopped == nil, let s = starts, let e = ends else { return false }
        return s <= now && now < e
    }

    /// انتهى (وقته أو أُوقف)
    func isOver(at now: Date = Date()) -> Bool {
        if stopped != nil { return true }
        guard let e = ends else { return true }
        return now >= e
    }

    func targets(_ memberId: UUID?) -> Bool {
        guard let ids = memberIds, !ids.isEmpty else { return true }
        guard let memberId else { return false }
        return ids.contains(memberId)
    }

    /// نصّ الزرّ: المكتوب على السيرفر، وإلا الافتراضي لنوعه
    var buttonText: String? {
        let custom = (buttonTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty, kind != .none { return custom }
        return Self.defaultTitle(kind)
    }

    static func defaultTitle(_ kind: Kind) -> String? {
        switch kind {
        case .none:   return nil
        case .update: return L10n.t("حدّث الحين", "Update now")
        case .news:   return L10n.t("افتح الأخبار", "Open News")
        case .link:   return L10n.t("فتح الرابط", "Open link")
        }
    }

    /// الرابط العام للصورة — `CachedImageLoader` يوقّعه عند التحميل (المستودع قد يصير خاصاً)
    var imageURL: URL? { Self.imageURL(path: imagePath) }

    static func imageURL(path: String) -> URL? {
        try? SupabaseConfig.client.storage.from(LaunchAnnouncementsService.bucket).getPublicURL(path: path)
    }
}

// MARK: - السيرفر: قراءة · إنشاء · إيقاف (الرفع في مستودع الأخبار)

enum LaunchAnnouncementsService {
    static let table = "launch_announcements"
    static let bucket = "news"
    static let folder = "launch"

    /// الشغّالة الآن الموجّهة لهذا العضو (السيرفر يصفّي بالسياسة، والتطبيق يعيد التصفية — المالك والمدير يقرؤون الكل)
    static func fetchActive(for memberId: UUID?) async -> [LaunchAnnouncement] {
        let now = Date()
        do {
            let rows: [LaunchAnnouncement] = try await SupabaseConfig.client
                .from(table)
                .select()
                .is("stopped_at", value: nil)
                .gt("ends_at", value: AppUpdateDates.iso(now))
                .order("starts_at", ascending: true)
                .execute()
                .value
            return rows.filter { $0.isActive(at: now) && $0.targets(memberId) }
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[LAUNCH] تعذّر جلب إعلانات الفتح: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// كل الإعلانات للإدارة (الأحدث أولاً) — nil = تعذّر الجلب
    static func fetchAll(limit: Int = 60) async -> [LaunchAnnouncement]? {
        do {
            return try await SupabaseConfig.client
                .from(table)
                .select()
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[LAUNCH] تعذّر جلب قائمة إعلانات الفتح: \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// يضغط الصورة مثل صور الأخبار ويرفعها إلى `news/launch/<uuid>.jpg` — يرجع المسار داخل المستودع
    static func uploadImage(_ image: UIImage) async -> String? {
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            ImageProcessor.process(image, for: .news)
        }).value else { return nil }
        let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
        do {
            try await SupabaseConfig.client.storage
                .from(bucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            return path
        } catch {
            Log.error("[LAUNCH] خطأ رفع صورة إعلان الفتح: \(error.localizedDescription)")
            return nil
        }
    }

    private struct NewRow: Encodable {
        let image_path: String
        let button_kind: String
        let button_url: String?
        let member_ids: [UUID]?
        let starts_at: String
        let ends_at: String
    }

    static func create(imagePath: String, kind: LaunchAnnouncement.Kind, url: String?, memberIds: [UUID]?,
                       startsAt: Date, endsAt: Date) async -> Bool {
        let row = NewRow(image_path: imagePath, button_kind: kind.rawValue,
                         button_url: kind == .link ? url : nil, member_ids: memberIds,
                         starts_at: AppUpdateDates.iso(startsAt), ends_at: AppUpdateDates.iso(endsAt))
        do {
            try await SupabaseConfig.client.from(table).insert(row).execute()
            NotificationCenter.default.post(name: .launchAnnouncementsChanged, object: nil)
            return true
        } catch {
            Log.error("[LAUNCH] تعذّر حفظ إعلان الفتح: \(error.localizedDescription)")
            return false
        }
    }

    private struct StopRow: Encodable { let stopped_at: String }

    /// «إيقاف» قبل وقته
    static func stop(_ id: UUID) async -> Bool {
        do {
            try await SupabaseConfig.client.from(table)
                .update(StopRow(stopped_at: AppUpdateDates.iso(Date())))
                .eq("id", value: id.uuidString)
                .execute()
            NotificationCenter.default.post(name: .launchAnnouncementsChanged, object: nil)
            return true
        } catch {
            Log.error("[LAUNCH] تعذّر إيقاف إعلان الفتح: \(error.localizedDescription)")
            return false
        }
    }
}

extension Notification.Name {
    /// أُنشئ إعلان فتح أو أُوقف — بطاقة «الإعلانات عند الفتح» تعيد الجلب
    static let launchAnnouncementsChanged = Notification.Name("launchAnnouncementsChanged")
    /// زرّ «افتح الأخبار» في إعلان الفتح — التبويبات تنتقل للرئيسية ثم ترسل `showNewsList`
    static let openNewsList = Notification.Name("openNewsList")
    /// الرئيسية تفتح صفحة الأخبار (بعد أن تُبنى إن لم تكن مبنية)
    static let showNewsList = Notification.Name("showNewsList")
}

// MARK: - الحالة: متى تظهر، و«ما الجديد» ينتظرها

@MainActor
final class LaunchAnnouncementsStore: ObservableObject {
    static let shared = LaunchAnnouncementsStore()

    /// الإعلانات قيد الفحص أو معروضة — «ما الجديد» ومربّع الإشعارات و«كمّل ملفك بصورة» تنتظر
    @Published private(set) var busy = true

    /// آخر عضو فُحص له في هذا التشغيل — فتح التبويبات من جديد (تبديل اللغة…) لا يعيد العرض
    private var checkedMember: UUID?
    private var running = false
    private var backgroundedAt: Date?

    /// الرجوع من الخلفية بعد هذه المدّة يعيد العرض (من السيرفر، والافتراضي ٣٠ دقيقة)
    private var resumeSeconds: TimeInterval {
        TimeInterval(max(1, AppConfigValues.shared.int("launch_announcements_resume_minutes", default: 30)) * 60)
    }

    /// أول ظهور للتبويبات (تشغيل جديد أو دخول)
    func appeared(memberId: UUID?, storeURL: @escaping () -> URL?) async {
        guard memberId != checkedMember else { busy = running; return }
        checkedMember = memberId
        await run(memberId: memberId, storeURL: storeURL)
    }

    func wentToBackground() { backgroundedAt = Date() }

    func becameActive(memberId: UUID?, storeURL: @escaping () -> URL?) async {
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        guard Date().timeIntervalSince(since) >= resumeSeconds else { return }
        await run(memberId: memberId, storeURL: storeURL)
    }

    private func run(memberId: UUID?, storeURL: @escaping () -> URL?) async {
        guard !running else { return }
        running = true
        busy = true
        defer {
            running = false
            busy = false
        }
        let rows = await LaunchAnnouncementsService.fetchActive(for: memberId)
        guard !rows.isEmpty else { return }
        // الصور محمّلة قبل الظهور — لا مربّع فارغ؛ ما تعذّر تحميله يُتخطّى هذه المرة
        var slides: [LaunchAnnouncementSlide] = []
        for row in rows {
            guard let url = row.imageURL,
                  let image = (try? await CachedImageLoader.load(url)) ?? nil else { continue }
            slides.append(LaunchAnnouncementSlide(item: row, image: image))
        }
        guard !slides.isEmpty, !Task.isCancelled else { return }
        // «الخصوصية والاستخدام» تُقبل أولاً
        while TermsAcceptanceStore.shared.needsAcceptance {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
        }
        let action = await LaunchAnnouncementWindow.present(slides, storeURL: storeURL())
        if action == .openNews {
            NotificationCenter.default.post(name: .openNewsList, object: nil)
        }
    }
}

struct LaunchAnnouncementSlide: Identifiable {
    let item: LaunchAnnouncement
    let image: UIImage
    var id: UUID { item.id }
}

/// يراقب الرجوع من الخلفية ويبدأ الفحص مع ظهور التبويبات — على `MainTabView`
struct LaunchAnnouncementsGate: ViewModifier {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: authVM.currentUser?.id) {
                await LaunchAnnouncementsStore.shared.appeared(memberId: authVM.currentUser?.id, storeURL: storeURL)
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .background:
                    LaunchAnnouncementsStore.shared.wentToBackground()
                case .active:
                    Task {
                        await LaunchAnnouncementsStore.shared.becameActive(memberId: authVM.currentUser?.id,
                                                                           storeURL: storeURL)
                    }
                default:
                    break
                }
            }
            // الخروج من الحساب (التبويبات تختفي) والمربّع ظاهر — لا يبقى فوق شاشة الدخول
            .onDisappear {
                if authVM.status != .fullyAuthenticated { LaunchAnnouncementWindow.dismiss() }
            }
    }

    /// رابط المتجر: سياسة التحديث من السيرفر، وإلا `app_settings.ios_update_url` (نفس شاشة التحديث)
    private func storeURL() -> URL? {
        AppUpdateStore.shared.storeURL(fallback: appSettingsVM.settings.iosUpdateUrl)
    }
}

// MARK: - النافذة: فوق التطبيق وتحت الرسائل (`DSPopupPresenter` = `.alert + 1`)

@MainActor
enum LaunchAnnouncementWindow {
    enum Outcome { case finished, openNews }

    private static var window: UIWindow?
    /// يُغلق المعروض الآن (الخروج من الحساب والمربّع ظاهر)
    private static var finishCurrent: ((Outcome) -> Void)?

    static func dismiss() { finishCurrent?(.finished) }

    /// يعرض الإعلانات واحداً ورا الثاني ويرجع حين تُغلق كلها
    static func present(_ slides: [LaunchAnnouncementSlide], storeURL: URL?) async -> Outcome {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return .finished }
        return await withCheckedContinuation { continuation in
            var resumed = false
            let previousKey = scene.windows.first(where: \.isKeyWindow)
            let finish: (Outcome) -> Void = { outcome in
                guard !resumed else { return }
                resumed = true
                finishCurrent = nil
                hide(restoring: previousKey)
                continuation.resume(returning: outcome)
            }
            finishCurrent = finish
            let root = LaunchAnnouncementOverlay(slides: slides, storeURL: storeURL, onFinish: finish)
                .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
                .environment(\.locale, LanguageManager.shared.locale)
                .font(DS.Font.body)
                .dsSection(AppSection.current)
            let host = UIHostingController(rootView: AnyView(root))
            host.view.backgroundColor = .clear
            host.view.accessibilityViewIsModal = true
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert
            w.backgroundColor = .clear
            w.rootViewController = host
            w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
            w.makeKeyAndVisible()
            window = w
        }
    }

    private static func hide(restoring previousKey: UIWindow?) {
        guard let w = window else { return }
        window = nil
        previousKey?.makeKey()
        w.isUserInteractionEnabled = false
        UIView.animate(withDuration: DSMotion.popupOutDuration, delay: 0, options: [.curveEaseIn]) {
            w.alpha = 0
        } completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
        }
    }
}
