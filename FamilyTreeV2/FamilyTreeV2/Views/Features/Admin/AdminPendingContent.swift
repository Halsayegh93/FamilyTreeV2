import Foundation
import Combine
import Supabase

// MARK: - ما ينتظر الاعتماد من المحتوى خارج «الوارد» (F4، V34 — مراجعة الكود ٢٠٢٦-١١-٢٦)
//
// الجرس و«يحتاج إجراء N» في «إشعارات الإدارة» يعدّان الإشعار ما دام طلبه معلّقاً (`AdminTodayBandLogic.needsAction`:
// معرّف الطلب في مجموعة المفتوح). إشعارات «ديوانية جديدة» و«إضافة للمكتبة» و«صورة معرض» تحمل معرّف العنصر نفسه
// (`request_id`) — ولم تكن عناصرها في المجموعة، فلم تُعدّ أبداً ولو بقيت تنتظر. هنا معرّفات الثلاثة المعلّقة
// (`approval_status = pending`) تُضاف للمجموعة في المكانين (`AdminTodayFeed.openRequestIds` و`AdminNotificationsPage`).
// جلب معرّفات فقط (عمود واحد)، والفشل يُبقي آخر قيمة (الإشعار يرجع لقاعدة غير المقروء لا يختفي).

@MainActor
final class AdminPendingContentStore: ObservableObject {
    static let shared = AdminPendingContentStore()

    /// معرّفات الديوانيات وعناصر المكتبة وصور المعرض المعلّقة
    @Published private(set) var ids: Set<UUID> = []
    private var lastFetch: Date?

    private struct Row: Decodable { let id: UUID }

    func refresh(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 30 { return }
        guard NetworkMonitor.shared.isConnected else { return }
        async let diwaniyas = Self.pending("diwaniyas")
        async let archive = Self.pending("family_archive")
        async let gallery = Self.pending("member_gallery_photos")
        let lists = await [diwaniyas, archive, gallery]
        // جدول تعذّر جلبه يُبقي ما عُرف منه — لا يُمسح ما لم يُعرف
        guard lists.contains(where: { $0 != nil }) else { return }
        var next = Set<UUID>()
        for list in lists { next.formUnion(list ?? []) }
        if lists.contains(where: { $0 == nil }) { next.formUnion(ids) }
        lastFetch = Date()
        if next != ids { ids = next }
    }

    private static func pending(_ table: String) async -> Set<UUID>? {
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from(table)
                .select("id")
                .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                .execute()
                .value
            return Set(rows.map(\.id))
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[AdminPendingContent] \(table): \(ErrorHelper.description(error))")
            }
            return nil
        }
    }
}
