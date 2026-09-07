import Foundation
import Supabase

/// Best-effort, bounded reporting. Raw log text never leaves the device.
@MainActor
final class AppDiagnostics {
    static let shared = AppDiagnostics()
    private var lastAttempt: [String: Date] = [:]
    private let transport: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    nonisolated static func feature(for message: String) -> String {
        // Only these closed labels are transmitted, never interpolated messages.
        if message.contains("خبر") || message.contains("أخبار") || message.contains("الأخبار") || message.contains("التعليقات") { return "news" }
        if message.contains("إشعار") || message.contains("الإشعارات") || message.contains("الأجهزة") || message.contains("[NOTIF]") { return "notifications" }
        if message.contains("صورة") || message.contains("الصور") || message.contains("رفع") { return "media" }
        if message.contains("عضو") || message.contains("الأبناء") || message.contains("[Members]") { return "members" }
        if message.contains("الديواني") { return "diwaniyas" }
        if message.contains("المشاريع") || message.contains("مشاريعي") { return "projects" }
        if message.contains("إعدادات") { return "settings" }
        if message.contains("دخول") || message.contains("OTP") { return "auth" }
        if message.contains("طلبات") || message.contains("بلاغ") { return "admin" }
        return "app"
    }

    nonisolated static func code(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            if ns.code == NSURLErrorNotConnectedToInternet || ns.code == NSURLErrorNetworkConnectionLost { return "offline" }
            if ns.code == NSURLErrorTimedOut { return "timeout" }
        }
        if let error = error as? PostgrestError, error.code == "42501" { return "permission_denied" }
        return "fetch_failed"
    }

    func record(feature: String, code: String) async {
        // Snapshot the session: an in-flight report never switches to a new account.
        guard let session = SupabaseConfig.client.auth.currentSession else { return }
        let now = Date()
        lastAttempt = lastAttempt.filter { now.timeIntervalSince($0.value) < 3600 }
        let key = session.user.id.uuidString + ":" + feature + ":" + code
        guard lastAttempt.count < 100, now.timeIntervalSince(lastAttempt[key] ?? .distantPast) >= 120 else { return }
        lastAttempt[key] = now
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/report_app_diagnostic"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "p_feature": feature, "p_code": code, "p_app_version": "\(version)(\(build))"
        ])
        // No retry loop or Log call: a failed reporter must never report itself.
        _ = try? await transport.data(for: request)
    }
}
