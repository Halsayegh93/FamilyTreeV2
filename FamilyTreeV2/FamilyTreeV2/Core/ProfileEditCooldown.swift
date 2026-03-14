import Foundation

/// الحقول القابلة للتعديل في الملف الشخصي
enum EditableField: String, CaseIterable {
    case fullName
    case birthDate
    case isMarried
    case isPhoneHidden
    case bio
    case avatar
    case phoneNumber
}

/// إدارة فترة الانتظار بين تعديلات الملف الشخصي
/// - أول تعديل: يقفل الحقل 24 ساعة
/// - تعديل ثاني خلال 48 ساعة: يقفل 48 ساعة
/// - كل حقل مستقل عن الآخر
final class ProfileEditCooldown {
    static let shared = ProfileEditCooldown()

    private let defaults = UserDefaults.standard

    /// مدة الـ cooldown العادي (24 ساعة)
    private let baseCooldown: TimeInterval = 24 * 60 * 60

    /// مدة الـ cooldown الممتد (48 ساعة)
    private let extendedCooldown: TimeInterval = 48 * 60 * 60

    /// مفتاح إيقاف العداد
    private let disabledKey = "editCooldown_disabled"

    private init() {}

    // MARK: - Admin Controls

    /// هل العداد متوقف؟
    var isDisabled: Bool {
        get { defaults.bool(forKey: disabledKey) }
        set { defaults.set(newValue, forKey: disabledKey) }
    }

    /// تصفير جميع العدادات
    func resetAllCooldowns() {
        for field in EditableField.allCases {
            defaults.removeObject(forKey: lastEditKey(field))
            defaults.removeObject(forKey: prevEditKey(field))
        }
        Log.info("[Cooldown] تم تصفير جميع العدادات")
    }

    // MARK: - Keys

    private func lastEditKey(_ field: EditableField) -> String {
        "editCooldown_\(field.rawValue)_lastEdit"
    }

    private func prevEditKey(_ field: EditableField) -> String {
        "editCooldown_\(field.rawValue)_prevEdit"
    }

    // MARK: - Public API

    /// هل المستخدم يقدر يعدل هالحقل الآن؟
    func canEdit(_ field: EditableField) -> Bool {
        if isDisabled { return true }
        return remainingTime(field) <= 0
    }

    /// الوقت المتبقي بالثواني قبل ما يقدر يعدل
    func remainingTime(_ field: EditableField) -> TimeInterval {
        guard let lastEdit = defaults.object(forKey: lastEditKey(field)) as? Date else {
            return 0
        }

        let cooldown = currentCooldown(for: field)
        let elapsed = Date().timeIntervalSince(lastEdit)
        let remaining = cooldown - elapsed

        return max(remaining, 0)
    }

    /// تسجيل تعديل جديد على حقل
    func recordEdit(_ field: EditableField) {
        let now = Date()

        // نقل آخر تعديل للسابق
        if let lastEdit = defaults.object(forKey: lastEditKey(field)) as? Date {
            defaults.set(lastEdit, forKey: prevEditKey(field))
        }

        defaults.set(now, forKey: lastEditKey(field))
    }

    /// نص الوقت المتبقي مثل "٣ ساعات و ١٥ دقيقة"
    func formattedRemaining(_ field: EditableField) -> String {
        let remaining = remainingTime(field)
        guard remaining > 0 else { return "" }

        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        let isArabic = LanguageManager.shared.selectedLanguage == "ar"

        if hours > 0 && minutes > 0 {
            return isArabic
                ? "\(hours) ساعة و \(minutes) دقيقة"
                : "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return isArabic
                ? "\(hours) ساعة"
                : "\(hours)h"
        } else {
            return isArabic
                ? "\(minutes) دقيقة"
                : "\(minutes)m"
        }
    }

    // MARK: - Private

    /// حساب مدة الـ cooldown — 24 أو 48 ساعة
    private func currentCooldown(for field: EditableField) -> TimeInterval {
        guard let lastEdit = defaults.object(forKey: lastEditKey(field)) as? Date,
              let prevEdit = defaults.object(forKey: prevEditKey(field)) as? Date else {
            return baseCooldown
        }

        // إذا التعديلين خلال 48 ساعة من بعض → cooldown ممتد
        let gap = lastEdit.timeIntervalSince(prevEdit)
        if gap <= extendedCooldown {
            return extendedCooldown
        }

        return baseCooldown
    }
}
