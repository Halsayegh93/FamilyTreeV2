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
                self.isConnected = path.status == .satisfied

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
    }

    deinit {
        monitor.cancel()
    }
}
