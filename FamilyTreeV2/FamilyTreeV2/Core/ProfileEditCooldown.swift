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
    case avatarDelete
    case avatarAdd
    case gallery
}

/// إدارة فترة الانتظار بين تعديلات الملف الشخصي
/// - أول 3 تعديلات لكل حقل: بدون انتظار
/// - بعد 3 تعديلات: يقفل الحقل 24 ساعة
/// - كل حقل مستقل عن الآخر
final class ProfileEditCooldown {
    static let shared = ProfileEditCooldown()

    private let defaults = UserDefaults.standard
    private let useKeychain = true

    /// عدد التعديلات المسموحة قبل القفل (تعديلين حرة، الثالثة تقفل)
    private let maxFreeEdits = 2

    /// مدة الـ cooldown (24 ساعة)
    private let cooldownDuration: TimeInterval = 24 * 60 * 60

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
            defaults.removeObject(forKey: editCountKey(field))
            defaults.removeObject(forKey: lockDateKey(field))
            KeychainHelper.delete(forKey: editCountKey(field))
            KeychainHelper.delete(forKey: lockDateKey(field))
        }
        Log.info("[Cooldown] تم تصفير جميع العدادات")
    }

    /// تصفير عداد حقل معين
    func resetCooldown(for field: EditableField) {
        defaults.removeObject(forKey: editCountKey(field))
        defaults.removeObject(forKey: lockDateKey(field))
        KeychainHelper.delete(forKey: editCountKey(field))
        KeychainHelper.delete(forKey: lockDateKey(field))
        Log.info("[Cooldown] تم تصفير عداد \(field.rawValue)")
    }

    // MARK: - Keys

    private func editCountKey(_ field: EditableField) -> String {
        "editCooldown_\(field.rawValue)_count"
    }

    private func lockDateKey(_ field: EditableField) -> String {
        "editCooldown_\(field.rawValue)_lockDate"
    }

    // MARK: - Public API

    /// هل المستخدم يقدر يعدل هالحقل الآن؟
    func canEdit(_ field: EditableField) -> Bool {
        if isDisabled { return true }

        if let lockDate = loadDate(forKey: lockDateKey(field)) {
            let elapsed = Date().timeIntervalSince(lockDate)
            if elapsed >= cooldownDuration {
                resetCooldown(for: field)
                return true
            }
            return false
        }

        return true
    }

    /// الوقت المتبقي بالثواني قبل ما يقدر يعدل
    func remainingTime(_ field: EditableField) -> TimeInterval {
        guard let lockDate = loadDate(forKey: lockDateKey(field)) else { return 0 }

        let elapsed = Date().timeIntervalSince(lockDate)
        let remaining = cooldownDuration - elapsed

        if remaining <= 0 {
            resetCooldown(for: field)
            return 0
        }

        return remaining
    }

    /// عدد التعديلات المتبقية قبل القفل
    func remainingEdits(_ field: EditableField) -> Int {
        let count = loadCount(forKey: editCountKey(field))
        return max(0, maxFreeEdits - count)
    }

    /// تسجيل تعديل جديد على حقل
    func recordEdit(_ field: EditableField) {
        if isDisabled { return }

        var count = loadCount(forKey: editCountKey(field))
        count += 1
        saveCount(count, forKey: editCountKey(field))

        if count >= maxFreeEdits {
            saveDate(Date(), forKey: lockDateKey(field))
            Log.info("[Cooldown] 🔒 تم قفل \(field.rawValue) بعد \(count) تعديلات — 24 ساعة")
        } else {
            Log.info("[Cooldown] تعديل \(count)/\(maxFreeEdits) على \(field.rawValue)")
        }
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

    /// نص عدد التعديلات المتبقية
    func formattedRemainingEdits(_ field: EditableField) -> String {
        let remaining = remainingEdits(field)
        let isArabic = LanguageManager.shared.selectedLanguage == "ar"
        return isArabic
            ? "\(remaining) تعديلات متبقية"
            : "\(remaining) edits remaining"
    }

    // MARK: - Private Storage

    private func saveCount(_ count: Int, forKey key: String) {
        defaults.set(count, forKey: key)
        KeychainHelper.save(String(count), forKey: key)
    }

    private func loadCount(forKey key: String) -> Int {
        if let stored = KeychainHelper.load(forKey: key), let val = Int(stored) {
            return val
        }
        return defaults.integer(forKey: key)
    }

    private func saveDate(_ date: Date, forKey key: String) {
        defaults.set(date, forKey: key)
        KeychainHelper.save(String(date.timeIntervalSince1970), forKey: key)
    }

    private func loadDate(forKey key: String) -> Date? {
        if let stored = KeychainHelper.load(forKey: key),
           let interval = Double(stored) {
            return Date(timeIntervalSince1970: interval)
        }
        return defaults.object(forKey: key) as? Date
    }
}
