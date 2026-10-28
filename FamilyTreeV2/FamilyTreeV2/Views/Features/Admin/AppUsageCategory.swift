import SwiftUI
import Supabase

// MARK: - فئات «استخدام التطبيق» (من `app_usage_members` على السيرفر)
//
// صفحات القوائم القديمة حُذفت (٢٠٢٦-١٠-٢٠): الفئات صارت شرائح «العائلة ← مسجّلون/مقيّدون في الشجرة»
// (`AdminAccountsStore` يقرأ القوائم الثلاث التي لها حساب دخول). الأسماء بالمسميات الرسمية.

enum AppUsageCategory: String, CaseIterable, Identifiable {
    case active
    case idle
    case loginNoDevice = "login_no_device"
    case neverLogged = "never_logged"
    case noPhone = "no_phone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:        return L10n.t("يستخدم التطبيق", "Using the app")
        case .idle:          return L10n.t("غير نشط", "Inactive")
        case .loginNoDevice: return L10n.t("لا تصله الإشعارات", "No notifications")
        case .neverLogged:   return L10n.t("لم يسجّل الدخول بعد", "Not signed in yet")
        case .noPhone:       return L10n.t("بلا رقم هاتف", "No phone")
        }
    }

    var icon: String {
        switch self {
        case .active:        return "checkmark.seal.fill"
        case .idle:          return "moon.zzz.fill"
        case .loginNoDevice: return "iphone.slash"
        case .neverLogged:   return "phone.fill.arrow.up.right"
        case .noPhone:       return "phone.down.fill"
        }
    }

    var color: Color {
        switch self {
        case .active:        return DS.Color.success
        case .idle:          return DS.Color.warning
        case .loginNoDevice: return DS.Color.info
        case .neverLogged:   return DS.Color.textSecondary
        case .noPhone:       return DS.Color.textTertiary
        }
    }
}

/// صف عضو من نتيجة app_usage_members
struct AppUsageMember: Decodable, Identifiable {
    let memberId: UUID
    let fullName: String?
    let phone: String?
    let lastSeen: Date?
    let accountCreated: Date?
    let hasLogin: Bool

    var id: UUID { memberId }

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case fullName = "full_name"
        case phone
        case lastSeen = "last_seen"
        case accountCreated = "account_created"
        case hasLogin = "has_login"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try c.decode(UUID.self, forKey: .memberId)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        hasLogin = try c.decodeIfPresent(Bool.self, forKey: .hasLogin) ?? false
        lastSeen = Self.parse(try c.decodeIfPresent(String.self, forKey: .lastSeen))
        accountCreated = Self.parse(try c.decodeIfPresent(String.self, forKey: .accountCreated))
    }

    private static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}
