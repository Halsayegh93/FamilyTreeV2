import Foundation
import Supabase
import PostgREST

/// تتبع نشاط العضو الحالي ومكان وجوده في التطبيق
/// يحدّث `current_screen` و `last_active_at` في profiles
enum MemberActivityTracker {
    /// آخر شاشة أُرسلت — لتجنب تحديثات متكررة لنفس الشاشة
    private static var lastReportedScreen: String?
    private static var lastReportTime: Date = .distantPast
    private static var heartbeatTimer: Timer?

    /// أبلغ القاعدة بمكان وجود العضو حالياً
    /// - Parameter screen: مفتاح الشاشة (home, tree, diwaniyas, profile, admin, news, ...)
    /// - Parameter force: تجاوز الـ throttle (للـ heartbeat)
    static func report(_ screen: String, force: Bool = false) {
        // throttle: لا ترسل نفس الشاشة أكثر من مرة كل 30 ثانية
        let now = Date()
        if !force, lastReportedScreen == screen, now.timeIntervalSince(lastReportTime) < 30 {
            return
        }
        lastReportedScreen = screen
        lastReportTime = now

        Task {
            do {
                let payload: [String: AnyEncodable] = [
                    "p_screen": AnyEncodable(screen),
                    "p_source": AnyEncodable("app")
                ]
                _ = try await SupabaseConfig.client.rpc(
                    "update_my_current_screen",
                    params: payload
                ).execute()
            } catch {
                Log.warning("[Activity] فشل تحديث الشاشة الحالية: \(error.localizedDescription)")
            }
        }

        // ابدأ/جدد الـ heartbeat
        startHeartbeat()
    }

    /// Heartbeat: يحدث آخر شاشة كل ٦٠ ثانية عشان العضو يبقى "نشط الآن"
    private static func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            guard let screen = lastReportedScreen else { return }
            report(screen, force: true)
        }
    }

    /// مسح الشاشة الحالية (عند الخروج من التطبيق)
    static func clear() {
        lastReportedScreen = nil
        Task {
            let payload: [String: AnyEncodable] = [
                "p_screen": AnyEncodable(Optional<String>.none),
                "p_source": AnyEncodable("app")
            ]
            _ = try? await SupabaseConfig.client.rpc(
                "update_my_current_screen",
                params: payload
            ).execute()
        }
    }
}
