import Foundation

// MARK: - CacheManager
// مدير الكاش — تخزين واسترجاع البيانات محلياً كملفات JSON مع TTL

@MainActor
final class CacheManager {
    static let shared = CacheManager()

    // MARK: - Cache Keys

    enum CacheKey: String, CaseIterable {
        case members
        case news
        case stories
        case diwaniyas
        case projects
        case currentUser
        case notifications
        // Widget keys
        case widgetStats
        case widgetNews

        var ttlSeconds: TimeInterval {
            switch self {
            case .members, .diwaniyas, .projects: return 3600     // ساعة
            case .news, .stories:                  return 900      // 15 دقيقة
            case .notifications:                   return 300      // 5 دقائق
            case .currentUser:                     return 3600     // ساعة
            case .widgetStats, .widgetNews:         return 1800    // 30 دقيقة
            }
        }
    }

    // MARK: - Paths

    private let cacheDirectory: URL
    private let appGroupId = "group.Hasan.FamilyTreeV2"

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = caches.appendingPathComponent("offline_cache", isDirectory: true)

        // إنشاء المجلد إذا مو موجود
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save / Load

    /// حفظ بيانات في الكاش المحلي
    func save<T: Encodable>(_ data: T, for key: CacheKey) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(data) else {
            Log.warning("[Cache] فشل ترميز البيانات: \(key.rawValue)")
            return
        }

        let fileURL = cacheDirectory.appendingPathComponent("\(key.rawValue).json")
        let metaURL = cacheDirectory.appendingPathComponent("\(key.rawValue)_meta.json")

        // كتابة البيانات في background thread
        let meta = CacheMeta(savedAt: Date())
        let metaData = try? encoder.encode(meta)

        // حفظ ملف البيانات والميتاداتا
        try? jsonData.write(to: fileURL, options: .atomic)
        if let metaData {
            try? metaData.write(to: metaURL, options: .atomic)
        }

        Log.info("[Cache] 💾 حفظ \(key.rawValue) (\(formatBytes(jsonData.count)))")
    }

    /// تحميل بيانات من الكاش المحلي
    func load<T: Decodable>(_ type: T.Type, for key: CacheKey) -> T? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key.rawValue).json")

        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let decoded = try? decoder.decode(type, from: data) else {
            Log.warning("[Cache] فشل فك ترميز: \(key.rawValue)")
            return nil
        }

        return decoded
    }

    /// هل الكاش منتهي الصلاحية؟
    func isExpired(for key: CacheKey) -> Bool {
        let metaURL = cacheDirectory.appendingPathComponent("\(key.rawValue)_meta.json")

        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(CacheMeta.self, from: metaData) else {
            return true // لا يوجد كاش
        }

        return Date().timeIntervalSince(meta.savedAt) > key.ttlSeconds
    }

    /// مسح كل الكاش (عند تسجيل الخروج)
    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Log.info("[Cache] 🗑️ تم مسح جميع البيانات المخزنة مؤقتاً")
    }

    // MARK: - App Group (Widget)

    /// حفظ بيانات في حاوية App Group المشتركة (للويدجت)
    func saveToSharedContainer<T: Encodable>(_ data: T, for key: CacheKey) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            // App Group مو مهيأ بعد — طبيعي قبل إعداد الويدجت
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(data) else { return }

        let fileURL = containerURL.appendingPathComponent("\(key.rawValue).json")
        try? jsonData.write(to: fileURL, options: .atomic)
    }

    /// تحميل من حاوية App Group المشتركة
    func loadFromSharedContainer<T: Decodable>(_ type: T.Type, for key: CacheKey) -> T? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return nil }

        let fileURL = containerURL.appendingPathComponent("\(key.rawValue).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Private

    private struct CacheMeta: Codable {
        let savedAt: Date
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}
