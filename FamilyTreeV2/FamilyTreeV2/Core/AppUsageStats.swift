import Foundation
import Supabase

// MARK: - من يستخدم التطبيق فعلاً (طلب المالك)
//
// حالة «مفعّل» لا تعني استخدام التطبيق — أغلب الأحياء أسماء في الشجرة بلا رقم.
// هذه الأرقام من الدالة app_usage_stats() على السيرفر (لفريق الإدارة فقط).

struct AppUsageStats: Decodable, Equatable {
    /// العضو الفعّال (تعريف المالك): رقم + جهاز دخل التطبيق خلال آخر ٢١ يوماً
    let active: Int
    /// رقم + جهاز — آخر دخول قبل أكثر من ٢١ يوماً
    let idle: Int
    /// رقم + سجّل دخول بلا جهاز مسجّل
    let loginNoDevice: Int
    /// عنده رقم وما دخل ولا مرة
    let neverLogged: Int
    /// بلا رقم — أسماء في الشجرة فقط
    let noPhone: Int

    enum CodingKeys: String, CodingKey {
        case active, idle
        case loginNoDevice = "login_no_device"
        case neverLogged = "never_logged"
        case noPhone = "no_phone"
    }

    func value(for category: AppUsageCategory) -> Int {
        switch category {
        case .active:        return active
        case .idle:          return idle
        case .loginNoDevice: return loginNoDevice
        case .neverLogged:   return neverLogged
        case .noPhone:       return noPhone
        }
    }

    /// آخر قيمة — تُعرض فوراً في الشاشات ثم تتحدّث
    @MainActor static var cached: AppUsageStats?

    @MainActor
    static func fetch() async -> AppUsageStats? {
        do {
            let rows: [AppUsageStats] = try await SupabaseConfig.client
                .rpc("app_usage_stats")
                .execute()
                .value
            if let first = rows.first { cached = first }
            return rows.first
        } catch {
            Log.fetchError("تعذر جلب أرقام استخدام التطبيق", error)
            return cached
        }
    }
}
