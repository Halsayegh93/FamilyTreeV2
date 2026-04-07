import Foundation

/// أدوات معالجة الأخطاء الموحدة — بدل تكرار نفس الكود بكل ViewModel
enum ErrorHelper {
    /// تحويل خطأ لوصف نصي
    static func description(_ error: Error) -> String {
        "\(error) \(error.localizedDescription)".lowercased()
    }

    /// هل الخطأ بسبب إلغاء المهمة؟
    static func isCancellation(_ error: Error) -> Bool {
        let raw = description(error)
        return raw.contains("cancelled") || raw.contains("canceled") || error is CancellationError
    }

    /// هل الخطأ بسبب عمود مفقود بالداتابيس؟
    static func isMissingColumn(_ error: Error, column: String) -> Bool {
        let raw = description(error)
        return raw.contains("column") && raw.contains(column) && (raw.contains("does not exist") || raw.contains("42703"))
    }

    /// هل الخطأ بسبب جدول مفقود؟
    static func isMissingTable(_ error: Error, table: String) -> Bool {
        let raw = description(error)
        return raw.contains(table) && (raw.contains("does not exist") || raw.contains("42P01") || raw.contains("relation"))
    }

    /// هل الخطأ بسبب rate limiting؟
    static func isRateLimited(_ error: Error) -> Bool {
        let raw = description(error)
        return raw.contains("429") || raw.contains("rate")
    }

    /// هل الخطأ بسبب عدم وجود جلسة؟
    static func isNoSession(_ error: Error) -> Bool {
        let raw = description(error)
        return raw.contains("session not found") || raw.contains("no session") || raw.contains("not authenticated") || raw.contains("refresh_token")
    }
}
