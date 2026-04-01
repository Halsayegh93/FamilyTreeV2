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

    private init() {}

    // MARK: - Subscribe

    /// الاشتراك في جميع القنوات — يُستدعى عند تسجيل الدخول الكامل
    func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true
        Log.info("[Realtime] 🔌 بدء الاشتراكات الحية...")

        subscribeToTable("profiles", debounceKey: "members") { [weak self] in
            await self?.memberVM?.fetchAllMembers(force: true)
        }

        subscribeToTable("news", debounceKey: "news") { [weak self] in
            await self?.newsVM?.fetchNews(force: true)
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
        action: @escaping @MainActor () async -> Void
    ) {
        let task = Task { [weak self] in
            guard let self else { return }

            let channel = SupabaseConfig.client.realtimeV2.channel("public:\(table)")
            await MainActor.run { self.channels.append(channel) }

            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: table
            )

            await channel.subscribe()
            Log.info("[Realtime] ✅ مشترك في \(table)")

            for await _ in changes {
                guard !Task.isCancelled else { break }
                // Debounce: ثانيتين عشان ما نرسل طلبات كثيرة
                self.debounce(key: debounceKey, delay: 2.0) {
                    await action()
                }
            }
        }

        subscriptionTasks[table] = task
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
