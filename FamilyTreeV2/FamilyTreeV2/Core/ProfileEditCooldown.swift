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
    // Cooldown timestamps also stored in Keychain for tamper resistance
    private let useKeychain = true

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
            KeychainHelper.delete(forKey: lastEditKey(field))
            KeychainHelper.delete(forKey: prevEditKey(field))
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
        // محاولة من Keychain أولاً (أصعب بالتلاعب)، ثم UserDefaults كـ fallback
        let lastEdit: Date? = loadDate(forKey: lastEditKey(field))
        guard let lastEdit else { return 0 }

        let cooldown = currentCooldown(for: field)
        let elapsed = Date().timeIntervalSince(lastEdit)
        let remaining = cooldown - elapsed

        return max(remaining, 0)
    }

    /// تسجيل تعديل جديد على حقل
    func recordEdit(_ field: EditableField) {
        let now = Date()

        // نقل آخر تعديل للسابق
        if let lastEdit = loadDate(forKey: lastEditKey(field)) {
            saveDate(lastEdit, forKey: prevEditKey(field))
        }

        saveDate(now, forKey: lastEditKey(field))
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
        guard let lastEdit = loadDate(forKey: lastEditKey(field)),
              let prevEdit = loadDate(forKey: prevEditKey(field)) else {
            return baseCooldown
        }

        // إذا التعديلين خلال 48 ساعة من بعض → cooldown ممتد
        let gap = lastEdit.timeIntervalSince(prevEdit)
        if gap <= extendedCooldown {
            return extendedCooldown
        }

        return baseCooldown
    }

    // MARK: - Secure Storage Helpers

    private func saveDate(_ date: Date, forKey key: String) {
        defaults.set(date, forKey: key)
        KeychainHelper.save(String(date.timeIntervalSince1970), forKey: key)
    }

    private func loadDate(forKey key: String) -> Date? {
        // Keychain أولاً (أصعب بالتلاعب)
        if let stored = KeychainHelper.load(forKey: key),
           let interval = Double(stored) {
            return Date(timeIntervalSince1970: interval)
        }
        // Fallback إلى UserDefaults
        return defaults.object(forKey: key) as? Date
    }
}
