import Foundation
import Supabase
import Combine

// MARK: - «تقرير الموافقات» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)
//
// يقرأ `approvals_report(p_from, p_to)` للفترة المختارة — للمالك والمدير والمراقب (السيرفر يقرّر).
// الدالة غير موجودة بعد = حالة «يحتاج تحديث السيرفر» بدل خطأ تقني.

@MainActor
final class ApprovalsReportViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String), unavailable
    }

    @Published var period: ApprovalsReportPeriod = .thisMonth
    @Published var report = ApprovalsReport()
    @Published var state: LoadState = .idle

    private let supabase = SupabaseConfig.client
    /// آخر طلب — نتيجة طلب أقدم (تبديل سريع للفترة) لا تغطّي الأحدث
    private var generation = 0

    func load() async {
        generation += 1
        let current = generation
        state = .loading
        let range = period.range()
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let iso = ISO8601DateFormatter()
        do {
            let result: ApprovalsReport = try await supabase
                .rpc("approvals_report", params: Params(p_from: iso.string(from: range.from), p_to: iso.string(from: range.to)))
                .execute()
                .value
            guard current == generation else { return }
            report = result
            state = .loaded
        } catch {
            guard current == generation, !ErrorHelper.isCancellation(error) else { return }
            Log.warning("[Approvals] تعذّر جلب تقرير الموافقات: \(error)")
            let pg = error as? PostgrestError
            let raw = ErrorHelper.description(error)
            if pg?.code == "PGRST202" || raw.contains("could not find the function") {
                state = .unavailable
            } else if pg?.hint == "bad_range" {
                state = .failed(L10n.t("الفترة غير صحيحة — اختر فترة أخرى.", "Invalid period — pick another one."))
            } else if pg?.code == "42501" || pg?.hint == "not_allowed" {
                state = .failed(L10n.t("التقرير للمالك والمدير والمراقب فقط.", "The report is for the owner, admins and monitors only."))
            } else {
                state = .failed(L10n.t("تعذّر تحميل التقرير — تحقّق من الاتصال وحاول مرة أخرى.",
                                       "Couldn't load the report — check the connection and try again."))
            }
        }
    }

}
