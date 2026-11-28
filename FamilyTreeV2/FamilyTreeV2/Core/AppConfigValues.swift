import Foundation
import Combine
import Supabase

/// قيم الإعدادات من السيرفر (`app_config()` — قاعدة المالك ٢٠٢٦-١٠-٢١: الأرقام والقواعد على السيرفر فتتغيّر بلا بناء
/// تطبيق). قارئ صغير مشترك: يجلبها مرة كل ٥ دقائق على الأكثر، ومفتاح غائب أو جلب فاشل = الافتراضي المكتوب عند
/// القارئ. القيم في `values` (أو في الجذر — نفس فكّ `DeathDatesCampaignStore`).
@MainActor
final class AppConfigValues: ObservableObject {
    static let shared = AppConfigValues()

    /// أقل مدّة بين جلبين (ثوانٍ)
    private static let refreshInterval: TimeInterval = 300

    @Published private(set) var values: [String: Any] = [:]
    private var loadedAt: Date?
    private var isLoading = false

    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.refreshInterval { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await SupabaseConfig.client.rpc("app_config").execute().data
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            values = root["values"] as? [String: Any] ?? root
            loadedAt = Date()
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[CONFIG] تعذّر جلب الإعدادات: \(error.localizedDescription)")
        }
    }

    /// نص من السيرفر (غير فارغ) — وإلا nil
    func string(_ key: String) -> String? {
        guard let s = values[key] as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// حسابات مراجعة أبل (`review_account_ids` على السيرفر) — «حساب فاضي» لا يُحسب في أي عدد (طلب المالك ٢٠٢٦-١١-٠٩)
    var reviewAccountIds: Set<UUID> {
        Set((values["review_account_ids"] as? [Any] ?? []).compactMap { ($0 as? String).flatMap(UUID.init(uuidString:)) })
    }

    /// سطر في «عن التطبيق»: الصفة (اختيارية) والاسم
    struct AboutCredit: Hashable {
        let role: String
        let name: String
    }

    /// أسماء «عن التطبيق» بالترتيب (`about_credits` على السيرفر: `[{"role": "فكرة وتنفيذ", "name": "…",
    /// "role_en": "…", "name_en": "…"}]` — الإنجليزي اختياري ويرجع للعربي) — طلب المالك ٢٠٢٦-١١-١٤ «أضيف أكثر من
    /// اسم»؛ مفتاح غائب أو فارغ = اسم المالك وحده كما كان
    var aboutCredits: [AboutCredit] {
        func text(_ row: [String: Any], _ key: String) -> String {
            let ar = (row[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !L10n.isArabic else { return ar }
            let en = (row[key + "_en"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return en.isEmpty ? ar : en
        }
        let rows = (values["about_credits"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let credits = rows.compactMap { row -> AboutCredit? in
            let name = text(row, "name")
            return name.isEmpty ? nil : AboutCredit(role: text(row, "role"), name: name)
        }
        if !credits.isEmpty { return credits }
        return [AboutCredit(role: L10n.t("فكرة وتنفيذ", "Idea and development"),
                            name: L10n.t("حسن الصايغ", "Hasan Al-Sayegh"))]
    }

    /// رقم صحيح من السيرفر — وإلا `fallback`
    func int(_ key: String, default fallback: Int) -> Int {
        if let n = values[key] as? NSNumber { return n.intValue }
        if let s = values[key] as? String, let n = Int(s) { return n }
        return fallback
    }
}
