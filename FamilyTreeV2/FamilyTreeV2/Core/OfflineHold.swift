import SwiftUI
import Combine

extension Notification.Name {
    /// رجع الاتصال بعد ما غطّت شاشة البداية التطبيق — حدّث البيانات
    static let networkRestoredAfterHold = Notification.Name("networkRestoredAfterHold")
}

// MARK: - OfflineHold
// بلا اتصال بالشبكة يبقى التطبيق على شاشة البداية (طلب المالك ٢٠٢٦-١٠-٠٨) بدل شريطي
// «لا يوجد اتصال» الأحمر و«رجع الاتصال» الأخضر. نافذة مستقلّة فوق كل شيء (المربّعات والأوراق
// والتنبيهات) — تحت تبقى الشاشة كما هي بلا فقد لما كان المستخدم فيه — وتختفي وحدها عند رجوع الاتصال.

@MainActor
final class OfflineHold {
    static let shared = OfflineHold()

    /// انقطاع قصير أثناء الاستخدام (تبديل واي فاي ↔ بيانات) لا يغطّي الشاشة. عند فتح التطبيق بلا
    /// اتصال تظهر شاشة البداية فوراً.
    static let graceSeconds: Double = 2
    static let fade: TimeInterval = 0.25

    private var window: UIWindow?
    private weak var previousKey: UIWindow?
    private var pending: Task<Void, Never>?
    private var bag: AnyCancellable?
    private weak var authVM: AuthViewModel?
    /// اتصلنا مرة على الأقل في هذه الجلسة — بعدها الانقطاع ينتظر مهلة قبل التغطية
    private var everOnline = false

    private init() {}

    func install(authVM: AuthViewModel) {
        self.authVM = authVM
        guard bag == nil else { return }
        let net = NetworkMonitor.shared
        bag = net.$isConnected.combineLatest(net.$hasStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] connected, known in
                guard known else { return }
                self?.update(connected: connected)
            }
    }

    private func update(connected: Bool) {
        pending?.cancel()
        pending = nil
        if connected {
            everOnline = true
            hide()
            return
        }
        guard window == nil else { return }
        // لا تغطية قبل التأكد أن الخادم لا يرد فعلاً — مراقب الشبكة قد يخطئ فيبقى التطبيق مغطّى والإنترنت شغّال
        // (طلب المالك ٢٠٢٦-١٠-٢٤ «لا يعلق ولا يثبت بصفحة»)
        let grace = everOnline ? Self.graceSeconds : 0
        pending = Task { [weak self] in
            if grace > 0 { try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000)) }
            guard !Task.isCancelled, !NetworkMonitor.shared.isConnected else { return }
            if await NetworkMonitor.shared.confirmReachable() { return }
            guard !Task.isCancelled, !NetworkMonitor.shared.isConnected else { return }
            self?.show()
            self?.keepProbing()
        }
    }

    /// والشاشة مغطّاة: تأكيد كل لحظات — يرجع التطبيق وحده ولو لم يبلّغ مراقب الشبكة بعودة الاتصال
    private func keepProbing() {
        probing?.cancel()
        probing = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.probeEverySeconds * 1_000_000_000))
                guard !Task.isCancelled, self?.window != nil else { return }
                // النجاح يصحّح `isConnected` فيصل للمشترك أعلاه ويُخفي الشاشة
                await NetworkMonitor.shared.confirmReachable()
            }
        }
    }
    private var probing: Task<Void, Never>?
    static let probeEverySeconds: Double = 5

    private func show() {
        guard window == nil, let authVM,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        // لوحة المفاتيح نافذة فوق الكل — تُغلق (النص المكتوب يبقى في حقله)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let lang = LanguageManager.shared
        let root = SplashScreenView(waitingForNetwork: true)
            .environmentObject(authVM)
            .environment(\.locale, lang.locale)
            .environment(\.layoutDirection, lang.layoutDirection)
            .font(DS.Font.body)
        let host = UIHostingController(rootView: root)
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 2          // فوق نافذة المربّعات والتنبيهات (`DSPopupPresenter` = .alert + 1)
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.rootViewController = host
        w.alpha = everOnline ? 0 : 1        // عند الفتح: نفس شاشة البداية تحتها، فلا تلاشي
        w.makeKeyAndVisible()
        window = w
        if everOnline { UIView.animate(withDuration: Self.fade) { w.alpha = 1 } }
    }

    private func hide() {
        probing?.cancel()
        probing = nil
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: Self.fade, animations: { w.alpha = 0 }) { [weak self] _ in
            w.isHidden = true
            w.rootViewController = nil
            self?.previousKey?.makeKey()
        }
        #if DEBUG
        // تجربة المحاكي بانقطاع مصطنع (`-tmpOfflineFrom`): بيانات العرض بلا جلسة — لا تحديث من الخادم
        if UserDefaults.standard.object(forKey: "tmpOfflineFrom") != nil { return }
        #endif
        NotificationCenter.default.post(name: .networkRestoredAfterHold, object: nil)
    }
}
