import Foundation

// MARK: - «جديد» في «الوارد» (عينة «ب»، المالك ٢٠٢٦-١١-٢٥ «ترتب وضع الطلبات»)
//
// الطلب «جديد» = وصل خلال آخر ٢٤ ساعة ولم يُفتح على هذا الجهاز. الفتح يُسجَّل محلياً (UserDefaults) — لا عمود سيرفر،
// مثل «حي ✓» في «تحقق من الأحياء». يُنظَّف ما مضى عليه أسبوع.

@MainActor
final class InboxSeenStore {
    static let shared = InboxSeenStore()
    private let key = "admin.inbox.seen"
    private let freshWindow: TimeInterval = 24 * 3600
    private var seen: [String: Double]

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        seen = stored.filter { $0.value > cutoff }
    }

    /// وصل خلال يوم ولم يُفتح
    func isNew(_ id: String, created: Date) -> Bool {
        created > Date().addingTimeInterval(-freshWindow) && seen[id] == nil
    }

    func markSeen(_ id: String) {
        guard seen[id] == nil else { return }
        seen[id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(seen, forKey: key)
    }
}
