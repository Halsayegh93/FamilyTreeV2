import Foundation

/// مسجّل الأخطاء — يحفظ الأخطاء محلياً ويرسلها للمدراء
enum CrashReporter {
    private static let key = "saved_crash_logs"
    private static let maxLogs = 50

    struct CrashLog: Codable {
        let date: String
        let error: String
        let context: String
    }

    /// تسجيل خطأ
    static func log(_ error: Error, context: String = "") {
        let formatter = ISO8601DateFormatter()
        let entry = CrashLog(
            date: formatter.string(from: Date()),
            error: "\(error) — \(error.localizedDescription)",
            context: context
        )

        var logs = loadLogs()
        logs.insert(entry, at: 0)
        if logs.count > maxLogs { logs = Array(logs.prefix(maxLogs)) }

        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: key)
        }

        Log.error("[CRASH] \(context): \(error.localizedDescription)")
    }

    /// تحميل السجلات
    static func loadLogs() -> [CrashLog] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CrashLog].self, from: data)) ?? []
    }

    /// مسح السجلات
    static func clearLogs() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// عدد الأخطاء
    static var count: Int { loadLogs().count }
}
