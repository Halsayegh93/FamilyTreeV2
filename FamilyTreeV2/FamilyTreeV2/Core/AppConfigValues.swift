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

    /// رقم صحيح من السيرفر — وإلا `fallback`
    func int(_ key: String, default fallback: Int) -> Int {
        if let n = values[key] as? NSNumber { return n.intValue }
        if let s = values[key] as? String, let n = Int(s) { return n }
        return fallback
    }
}
