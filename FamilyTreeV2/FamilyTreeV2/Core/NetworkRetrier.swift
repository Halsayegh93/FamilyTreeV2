import Foundation

/// إعادة محاولة الطلبات الفاشلة مع exponential backoff
enum NetworkRetrier {

    /// إعادة محاولة عملية async مع backoff
    /// - Parameters:
    ///   - maxAttempts: عدد المحاولات القصوى (default: 3)
    ///   - initialDelay: التأخير الأول بالثواني (default: 1)
    ///   - operation: العملية المطلوبة
    /// - Returns: النتيجة أو يرمي آخر خطأ
    static func retry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                CrashReporter.log(error, context: "retry attempt \(attempt)/\(maxAttempts)")

                if attempt < maxAttempts {
                    let jitter = Double.random(in: 0...0.3)
                    let sleepDuration = UInt64((delay + jitter) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: sleepDuration)
                    delay *= 2 // exponential backoff
                }
            }
        }

        throw lastError ?? NSError(domain: "NetworkRetrier", code: -1)
    }

    /// إعادة محاولة بدون throw — يرجع nil إذا فشل
    static func retryOptional<T>(
        maxAttempts: Int = 2,
        initialDelay: TimeInterval = 0.5,
        operation: @Sendable () async throws -> T
    ) async -> T? {
        try? await retry(maxAttempts: maxAttempts, initialDelay: initialDelay, operation: operation)
    }
}
