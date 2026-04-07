import Foundation

/// تحديث البيانات بالخلفية — يمنع بطء عند فتح التطبيق
@MainActor
class BackgroundRefresher {
    static let shared = BackgroundRefresher()
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false

    private init() {}

    /// بدء التحديث الدوري — كل 5 دقائق
    func startPeriodicRefresh(
        memberVM: MemberViewModel?,
        newsVM: NewsViewModel?,
        notificationVM: NotificationViewModel?
    ) {
        stopRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 دقائق
                guard !Task.isCancelled, NetworkMonitor.shared.isConnected else { continue }

                isRefreshing = true
                Log.info("[BGRefresh] بدء التحديث الدوري...")

                async let m: () = memberVM?.fetchAllMembers(force: false) ?? ()
                async let n: () = newsVM?.fetchNews(force: false) ?? ()
                async let notif: () = notificationVM?.fetchNotifications(force: false) ?? ()
                _ = await (m, n, notif)

                isRefreshing = false
                Log.info("[BGRefresh] اكتمل التحديث الدوري")
            }
        }
    }

    /// إيقاف التحديث
    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }
}
