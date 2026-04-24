import Foundation
import Supabase
import Realtime

// MARK: - RealtimeManager
// مدير الاشتراكات الحية — يستقبل التحديثات من Supabase Realtime ويحدّث ViewModels

@MainActor
final class RealtimeManager {
    static let shared = RealtimeManager()

    // MARK: - ViewModel References

    weak var memberVM: MemberViewModel?
    weak var newsVM: NewsViewModel?
    weak var storyVM: StoryViewModel?
    weak var notificationVM: NotificationViewModel?
    weak var projectsVM: ProjectsViewModel?

    // MARK: - State

    private var subscriptionTasks: [String: Task<Void, Never>] = [:]
    private var debounceTasks: [String: Task<Void, Never>] = [:]
    private var channels: [RealtimeChannelV2] = []
    private var isSubscribed = false

    /// عدد محاولات إعادة الاتصال لكل قناة
    private var retryCounts: [String: Int] = [:]
    private static let maxRetries = 5
    private static let baseRetryDelay: TimeInterval = 2.0

    private init() {}

    // MARK: - Subscribe

    /// الاشتراك في جميع القنوات — يُستدعى عند تسجيل الدخول الكامل
    func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true
        Log.info("[Realtime] 🔌 بدء الاشتراكات الحية...")

        // الأعضاء: debounce 5 ثوانٍ + force: false يخلي الـ FetchThrottler يتحكم
        subscribeToTable("profiles", debounceKey: "members", debounceDelay: 5.0) { [weak self] in
            await self?.memberVM?.fetchAllMembers(force: false)
        }

        // الأخبار: debounce 5 ثوانٍ
        subscribeToTable("news", debounceKey: "news", debounceDelay: 5.0) { [weak self] in
            await self?.newsVM?.fetchNews(force: false)
        }

        subscribeToTable("family_stories", debounceKey: "stories") { [weak self] in
            await self?.storyVM?.fetchActiveStories(force: true)
        }

        subscribeToTable("notifications", debounceKey: "notifications") { [weak self] in
            await self?.notificationVM?.fetchNotifications(force: true)
        }

        subscribeToTable("projects", debounceKey: "projects") { [weak self] in
            await self?.projectsVM?.fetchProjects()
        }
    }

    /// إلغاء جميع الاشتراكات — يُستدعى عند تسجيل الخروج
    func unsubscribe() {
        guard isSubscribed else { return }
        isSubscribed = false

        // إلغاء جميع المهام
        for (_, task) in subscriptionTasks { task.cancel() }
        subscriptionTasks.removeAll()

        for (_, task) in debounceTasks { task.cancel() }
        debounceTasks.removeAll()

        retryCounts.removeAll()

        // إزالة القنوات
        let channelsToRemove = channels
        channels.removeAll()

        Task {
            for channel in channelsToRemove {
                await channel.unsubscribe()
            }
        }

        Log.info("[Realtime] 🔌 تم إلغاء جميع الاشتراكات")
    }

    // MARK: - Private Helpers

    private func subscribeToTable(
        _ table: String,
        debounceKey: String,
        debounceDelay: TimeInterval = 2.0,
        action: @escaping @MainActor () async -> Void
    ) {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            // الوصول للـ client على الـ MainActor عشان نتجنب unsafeForcedSync
            let client = SupabaseConfig.client
            let channel = client.realtimeV2.channel("public:\(table)")
            self.channels.append(channel)

            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: table
            )

            do {
                try await channel.subscribeWithError()
                Log.info("[Realtime] ✅ مشترك في \(table)")
                self.retryCounts[table] = 0

                for await _ in changes {
                    guard !Task.isCancelled else { break }
                    self.debounce(key: debounceKey, delay: debounceDelay) {
                        await action()
                    }
                }

                // الـ stream انتهى — نحاول نعيد الاتصال إذا ما تم الإلغاء
                if !Task.isCancelled && self.isSubscribed {
                    Log.warning("[Realtime] ⚠️ انقطع الاتصال بـ \(table) — محاولة إعادة الاتصال...")
                    await self.retrySubscription(table: table, debounceKey: debounceKey, debounceDelay: debounceDelay, action: action)
                }
            } catch {
                Log.error("[Realtime] ❌ خطأ بالاشتراك في \(table): \(error.localizedDescription)")
                if !Task.isCancelled && self.isSubscribed {
                    await self.retrySubscription(table: table, debounceKey: debounceKey, debounceDelay: debounceDelay, action: action)
                }
            }
        }

        subscriptionTasks[table] = task
    }

    /// إعادة الاتصال مع exponential backoff
    private func retrySubscription(
        table: String,
        debounceKey: String,
        debounceDelay: TimeInterval,
        action: @escaping @MainActor () async -> Void
    ) async {
        let currentRetry = (retryCounts[table] ?? 0) + 1
        retryCounts[table] = currentRetry

        guard currentRetry <= Self.maxRetries else {
            Log.error("[Realtime] ❌ تجاوز الحد الأقصى لمحاولات إعادة الاتصال بـ \(table) (\(Self.maxRetries))")
            return
        }

        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = Self.baseRetryDelay * pow(2.0, Double(currentRetry - 1))
        Log.info("[Realtime] 🔄 إعادة محاولة \(currentRetry)/\(Self.maxRetries) لـ \(table) بعد \(Int(delay))s...")

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        guard !Task.isCancelled && isSubscribed else { return }

        // إعادة الاشتراك
        subscribeToTable(table, debounceKey: debounceKey, debounceDelay: debounceDelay, action: action)
    }

    private func debounce(
        key: String,
        delay: TimeInterval,
        action: @escaping @MainActor () async -> Void
    ) {
        debounceTasks[key]?.cancel()
        debounceTasks[key] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
