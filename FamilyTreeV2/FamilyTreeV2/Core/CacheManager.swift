import Foundation

// MARK: - CacheManager
// مدير الكاش — تخزين واسترجاع البيانات محلياً كملفات JSON مع TTL
// ملاحظة: غير @MainActor عمداً — حتى يقدر يكتب الملفات في background.
// كل المتغيرات immutable بعد init، فالـ class آمن متعدد الـ threads.

final class CacheManager: @unchecked Sendable {
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

    /// طابور الـ I/O الخاص بالكاش — serial queue يكتب الملفات بدون تنافس.
    private static let ioQueue = DispatchQueue(label: "com.familytree.cache.io", qos: .utility)

    /// مهام الحفظ المعلّقة — debounce يمنع حفظات متتالية سريعة لنفس المفتاح
    private var pendingSaves: [String: DispatchWorkItem] = [:]

    /// debounce delay لكل مفتاح — البيانات الكبيرة تنتظر أطول لتجميع التعديلات
    private func saveDelay(for key: CacheKey) -> TimeInterval {
        switch key {
        case .members: return 1.5   // ١.٤ MB — نجمّع التعديلات قدر الإمكان
        default:       return 0.3   // بيانات صغيرة — تأخير قصير يكفي
        }
    }

    /// حفظ بيانات في الكاش المحلي.
    /// الترميز والكتابة يحدثان كلاهما في background مع debounce.
    func save<T: Encodable & Sendable>(_ data: T, for key: CacheKey) {
        // إلغاء أي حفظة معلّقة لنفس المفتاح
        pendingSaves[key.rawValue]?.cancel()

        let directory = cacheDirectory
        let keyName = key.rawValue
        let delay = saveDelay(for: key)

        let workItem = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            guard let jsonData = try? encoder.encode(data) else {
                Log.warning("[Cache] فشل ترميز البيانات: \(keyName)")
                return
            }

            let metaData = try? encoder.encode(CacheMeta(savedAt: Date()))
            let fileURL = directory.appendingPathComponent("\(keyName).json")
            let metaURL = directory.appendingPathComponent("\(keyName)_meta.json")
            try? jsonData.write(to: fileURL, options: .atomic)
            if let metaData {
                try? metaData.write(to: metaURL, options: .atomic)
            }
            Log.info("[Cache] 💾 حفظ \(keyName) (\(Self.formatBytes(jsonData.count)))")
        }

        pendingSaves[key.rawValue] = workItem
        Self.ioQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// تحميل بيانات من الكاش المحلي (synchronous — للبيانات الصغيرة)
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

    /// تحميل غير متزامن للبيانات الكبيرة — يقرأ ويفك الترميز في background.
    /// استخدمه للبيانات الكبيرة (مثل allMembers) لتجنب تجميد الواجهة.
    func loadAsync<T: Decodable & Sendable>(_ type: T.Type, for key: CacheKey) async -> T? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key.rawValue).json")

        return await withCheckedContinuation { continuation in
            Self.ioQueue.async {
                guard let data = try? Data(contentsOf: fileURL) else {
                    continuation.resume(returning: nil)
                    return
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let decoded = try? decoder.decode(type, from: data)
                if decoded == nil {
                    Log.warning("[Cache] فشل فك ترميز: \(key.rawValue)")
                }
                continuation.resume(returning: decoded)
            }
        }
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

    /// حفظ بيانات في حاوية App Group المشتركة (للويدجت) — الكتابة في background.
    func saveToSharedContainer<T: Encodable>(_ data: T, for key: CacheKey) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(data) else { return }

        let groupId = appGroupId
        let keyName = key.rawValue

        Self.ioQueue.async {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupId
            ) else { return }

            let fileURL = containerURL.appendingPathComponent("\(keyName).json")
            try? jsonData.write(to: fileURL, options: .atomic)
        }
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

    private struct CacheMeta: Codable, Sendable {
        let savedAt: Date
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}
