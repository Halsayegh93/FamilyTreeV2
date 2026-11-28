import Foundation
import Supabase

// MARK: - «الوارد»: عدّ الناجح فعلاً (ملاحظة «المنتقد» ٢٠٢٦-١١-٢٨، البندان ٧ و٨)
//
// قبول/رفض المحتوى (أخبار، ديوانيات، مشاريع، مكتبة) متفائل في نماذج العرض: الصفّ يختفي فوراً والنداء في الخلفية بلا نتيجة
// تُرجع. فالعدد في «موافقة/رفض المحدّد» و«لحظة النجاح» بعد الموافقة المفردة يُؤكَّدان من السيرفر نفسه بعد انتهاء النداء.
// طلبات `admin_requests` لها نتيجتها في `AdminRequestViewModel.awaitDecision` (لا تمرّ من هنا).

enum AdminContentDecisionCheck {
    enum Table: String {
        case news
        case diwaniyas
        case projects
        case archive = "family_archive"
    }

    private struct Row: Decodable {
        let id: UUID
        let approvalStatus: String?
        enum CodingKeys: String, CodingKey { case id, approvalStatus = "approval_status" }
    }

    /// ما ثبت على السيرفر من `ids`: القبول = `approval_status = approved`، والرفض = `rejected` أو حُذف الصفّ (الأخبار
    /// والديوانيات تُحذف عند الرفض). يعيد المحاولة قليلاً لأن النداء التفاؤلي قد لا يكون انتهى بعد.
    static func confirmed(_ table: Table, ids: [UUID], approve: Bool,
                          attempts: Int = 5, interval: UInt64 = 600_000_000) async -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        var done: Set<UUID> = []
        for attempt in 0..<max(attempts, 1) {
            if attempt > 0 { try? await Task.sleep(nanoseconds: interval) }
            let left = ids.filter { !done.contains($0) }
            guard !left.isEmpty else { break }
            do {
                let rows: [Row] = try await SupabaseConfig.client
                    .from(table.rawValue)
                    .select("id, approval_status")
                    .in("id", values: left.map(\.uuidString))
                    .execute()
                    .value
                done.formUnion(settled(left, rows: rows, approve: approve))
            } catch {
                if ErrorHelper.isCancellation(error) { break }
                Log.warning("[Inbox] تأكيد القرار من \(table.rawValue) فشل: \(error.localizedDescription)")
            }
        }
        return done
    }

    /// منطق خالص (يُفحص بلا سيرفر): أيّ المعرّفات ثبت قرارها في الصفوف المقروءة
    static func settled(_ ids: [UUID], rows: [(id: UUID, status: String?)], approve: Bool) -> Set<UUID> {
        let byId: [UUID: String] = Dictionary(rows.map { ($0.id, ($0.status ?? "").lowercased()) },
                                              uniquingKeysWith: { a, _ in a })
        return Set(ids.filter { id in
            if approve { return byId[id] == "approved" }
            guard let status = byId[id] else { return true }   // حُذف الصفّ = رُفض
            return status == "rejected"
        })
    }

    private static func settled(_ ids: [UUID], rows: [Row], approve: Bool) -> Set<UUID> {
        settled(ids, rows: rows.map { (id: $0.id, status: $0.approvalStatus) }, approve: approve)
    }
}
