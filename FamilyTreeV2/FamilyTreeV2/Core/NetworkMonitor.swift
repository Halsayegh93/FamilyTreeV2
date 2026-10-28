import Foundation
import Network
import SwiftUI
import Combine

// MARK: - NetworkMonitor
// مراقب الشبكة — يتتبع حالة الاتصال بالإنترنت

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    /// وصلت أول قراءة للشبكة — قبلها `isConnected` افتراضي (true) لا حقيقي
    @Published private(set) var hasStatus: Bool = false

    /// فلاج عام لإظهار alert "لا يوجد اتصال" — أي ViewModel يستدعي
    /// `requireOnline()` يضبط هذا الفلاج، وRootView يعرض الـalert.
    @Published var showOfflineAlert: Bool = false

    /// تحقّق سريع قبل أي عملية كتابة. لو offline: يضبط alert + يرجع false.
    /// مثال:
    /// ```swift
    /// guard NetworkMonitor.shared.requireOnline() else { return }
    /// ```
    @discardableResult
    func requireOnline() -> Bool {
        guard isConnected else {
            showOfflineAlert = true
            return false
        }
        return true
    }

    /// تأكيد حقيقي قبل اعتبار الجهاز «بلا اتصال»: `NWPathMonitor` قد يتأخر أو يخطئ (بعد الرجوع من الخلفية،
    /// تبديل الشبكة) فيبقى التطبيق على شاشة البداية بلا مخرج. طلب صغير لخادم المشروع بمهلة قصيرة — إن ردّ
    /// (بأي رمز HTTP) فالاتصال موجود ويُصحَّح `isConnected`.
    @discardableResult
    func confirmReachable() async -> Bool {
        #if DEBUG
        if debugForced == false { return false }
        #endif
        if let probe = probeTask { return await probe.value }
        let task = Task<Bool, Never> { @MainActor in
            var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/health"))
            request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let response = try? await Self.probeSession.data(for: request).1
            let ok = response is HTTPURLResponse
            if ok, !self.isConnected {
                Log.info("[Network] ✅ الخادم يرد رغم أن مراقب الشبكة قال «بلا اتصال» — تصحيح")
                self.isConnected = true
                self.hasStatus = true
            }
            return ok
        }
        probeTask = task
        let ok = await task.value
        probeTask = nil
        return ok
    }
    private var probeTask: Task<Bool, Never>?
    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.familytree.networkmonitor")

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                // `.requiresConnection` (VPN عند الطلب، اتصال يُفتح بأول طلب) ليس انقطاعاً — كان يُعدّ «بلا اتصال» فتغطّي
                // شاشة البداية التطبيق وفحص الدخول يتوقف والإنترنت شغّال (طلب المالك ٢٠٢٦-١٠-٢٤ «لا يعلق عند الدخول»)
                self.isConnected = self.debugForced ?? (path.status != .unsatisfied)
                self.hasStatus = true

                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else {
                    self.connectionType = nil
                }

                // لوق فقط عند تغيير الحالة
                if wasConnected != self.isConnected {
                    if self.isConnected {
                        Log.info("[Network] ✅ الاتصال بالإنترنت متاح")
                    } else {
                        Log.warning("[Network] ⚠️ لا يوجد اتصال بالإنترنت")
                    }
                }
            }
        }
        monitor.start(queue: queue)
        #if DEBUG
        scheduleDebugOffline()
        #endif
    }

    /// تجربة المحاكي فقط: `-tmpOfflineFrom <ث> -tmpOfflineTo <ث>` — انقطاع مصطنع بين الثانيتين
    private var debugForced: Bool?

    #if DEBUG
    private func scheduleDebugOffline() {
        let d = UserDefaults.standard
        guard d.object(forKey: "tmpOfflineFrom") != nil else { return }
        let from = d.double(forKey: "tmpOfflineFrom"), to = d.double(forKey: "tmpOfflineTo")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(from * 1e9))
            debugForced = false; isConnected = false; hasStatus = true
            guard to > from else { return }
            try? await Task.sleep(nanoseconds: UInt64((to - from) * 1e9))
            debugForced = nil; isConnected = true
        }
    }
    #endif

    deinit {
        monitor.cancel()
    }
}
