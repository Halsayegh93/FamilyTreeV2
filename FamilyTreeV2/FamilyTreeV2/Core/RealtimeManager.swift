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
    weak var notificationVM: NotificationViewModel?
    weak var projectsVM: ProjectsViewModel?

    // MARK: - State

    private var subscriptionTasks: [String: Task<Void, Never>] = [:]
    private var debounceTasks: [String: Task<Void, Never>] = [:]
    /// قناة واحدة لكل جدول — نتجنّب تكدّس القنوات اللي يصير لما الاشتراك يفشل ويعيد المحاولة
    private var channelsByTable: [String: RealtimeChannelV2] = [:]
    private var isSubscribed = false

    /// أعضاء تغيّروا منذ آخر دفعة (من رسالة التغيير نفسها) — يُجلبون وحدهم بدل القائمة كلها
    private var changedMemberIds: Set<UUID> = []
    private var deletedMemberIds: Set<UUID> = []

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

        // الأعضاء (طلب المالك ٢٠٢٦-١١-١٢ «سرّع السيرفر»): كل تنقّل لأي عضو بين الشاشات يحدّث «آخر نشاط» في سجلّه،
        // فكانت كل الأجهزة تعيد جلب كل الأعضاء (~٣٠٠٠) بعد ٥ ثوانٍ — آلاف المرات يومياً. الآن تُجمع معرّفات من تغيّروا
        // خلال ٥ ثوانٍ ويُجلبون وحدهم، ويُدمج ما تغيّر فعلاً فقط («آخر نشاط» وحده لا يحرّك الشجرة)
        subscribeToTable("profiles", debounceKey: "members", debounceDelay: 5.0, collect: { [weak self] change in
            self?.collectMemberChange(change)
        }) { [weak self] in
            guard let self else { return }
            let updated = self.changedMemberIds
            let deleted = self.deletedMemberIds
            self.changedMemberIds.removeAll()
            self.deletedMemberIds.removeAll()
            await self.memberVM?.applyLiveMemberChanges(updated: updated, deleted: deleted)
        }

        // الأخبار: debounce 5 ثوانٍ
        subscribeToTable("news", debounceKey: "news", debounceDelay: 5.0) { [weak self] in
            await self?.newsVM?.fetchNews(force: false)
        }

        subscribeToTable("notifications", debounceKey: "notifications") { [weak self] in
            await self?.notificationVM?.fetchNotifications(force: true)
        }

        subscribeToTable("projects", debounceKey: "projects") { [weak self] in
            await self?.projectsVM?.fetchProjects()
        }

        // شجرة النساء: أي تغيير (زوجة/بنت/إخفاء/متزوجة) ينبّه الشاشات المفتوحة
        // عبر إشعار داخلي — الشجرة و«عائلتي» يعيدان الجلب فوراً.
        subscribeToTable("women_members", debounceKey: "women", debounceDelay: 3.0) { [weak self] in
            await MainActor.run { NotificationCenter.default.post(name: .womenMembersChanged, object: nil) }
            if let uid = SupabaseConfig.client.auth.currentUser?.id {
                await self?.memberVM?.fetchWomenFamily(for: uid)
            }
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
        let channelsToRemove = Array(channelsByTable.values)
        channelsByTable.removeAll()

        Task {
            for channel in channelsToRemove {
                await channel.unsubscribe()
            }
        }

        Log.info("[Realtime] 🔌 تم إلغاء جميع الاشتراكات")
    }

    // MARK: - Private Helpers

    /// معرّف العضو من رسالة التغيير (إضافة/تعديل/حذف)
    private func collectMemberChange(_ change: AnyAction) {
        switch change {
        case let .insert(a):
            if let id = a.record["id"]?.stringValue.flatMap(UUID.init) { changedMemberIds.insert(id) }
        case let .update(a):
            if let id = a.record["id"]?.stringValue.flatMap(UUID.init) { changedMemberIds.insert(id) }
        case let .delete(a):
            if let id = a.oldRecord["id"]?.stringValue.flatMap(UUID.init) { deletedMemberIds.insert(id) }
        }
    }

    private func subscribeToTable(
        _ table: String,
        debounceKey: String,
        debounceDelay: TimeInterval = 2.0,
        collect: (@MainActor (AnyAction) -> Void)? = nil,
        action: @escaping @MainActor () async -> Void
    ) {
        // إلغاء أي task سابق لنفس الجدول (يحدث عند إعادة المحاولة بعد فشل)
        subscriptionTasks[table]?.cancel()
        // فصل القناة القديمة لو موجودة
        if let oldChannel = channelsByTable.removeValue(forKey: table) {
            Task { await oldChannel.unsubscribe() }
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            // الوصول للـ client على الـ MainActor عشان نتجنب unsafeForcedSync
            let client = SupabaseConfig.client
            let channel = client.realtimeV2.channel("public:\(table)")
            self.channelsByTable[table] = channel

            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: table
            )

            do {
                try await channel.subscribeWithError()
                Log.info("[Realtime] ✅ مشترك في \(table)")
                self.retryCounts[table] = 0

                for await change in changes {
                    guard !Task.isCancelled else { break }
                    collect?(change)
                    self.debounce(key: debounceKey, delay: debounceDelay) {
                        await action()
                    }
                }

                // الـ stream انتهى — نحاول نعيد الاتصال إذا ما تم الإلغاء
                if !Task.isCancelled && self.isSubscribed {
                    Log.warning("[Realtime] ⚠️ انقطع الاتصال بـ \(table) — محاولة إعادة الاتصال...")
                    await self.retrySubscription(table: table, debounceKey: debounceKey, debounceDelay: debounceDelay, collect: collect, action: action)
                }
            } catch {
                Log.error("[Realtime] ❌ خطأ بالاشتراك في \(table): \(error.localizedDescription)")
                if !Task.isCancelled && self.isSubscribed {
                    await self.retrySubscription(table: table, debounceKey: debounceKey, debounceDelay: debounceDelay, collect: collect, action: action)
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
        collect: (@MainActor (AnyAction) -> Void)? = nil,
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
        subscribeToTable(table, debounceKey: debounceKey, debounceDelay: debounceDelay, collect: collect, action: action)
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
