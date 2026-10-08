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
                self.isConnected = self.debugForced ?? (path.status == .satisfied)
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
