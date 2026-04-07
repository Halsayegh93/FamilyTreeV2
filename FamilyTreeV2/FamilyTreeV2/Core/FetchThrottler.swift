import Foundation

/// مُتحكم بتكرار الطلبات — يمنع إعادة التحميل خلال فترة محددة
class FetchThrottler {
    private var lastFetchDates: [String: Date] = [:]

    /// هل نقدر نسوي fetch؟
    /// - Parameters:
    ///   - key: معرف الطلب (مثل "members", "news")
    ///   - interval: الفترة بالثواني بين كل طلب
    ///   - force: تجاوز الحد
    /// - Returns: true إذا مسموح بالطلب
    func canFetch(key: String, interval: TimeInterval, force: Bool = false) -> Bool {
        if force { return true }
        guard let last = lastFetchDates[key] else { return true }
        return Date().timeIntervalSince(last) >= interval
    }

    /// تسجيل وقت الطلب
    func didFetch(key: String) {
        lastFetchDates[key] = Date()
    }

    /// مسح
    func reset(key: String? = nil) {
        if let key { lastFetchDates.removeValue(forKey: key) }
        else { lastFetchDates.removeAll() }
    }
}
