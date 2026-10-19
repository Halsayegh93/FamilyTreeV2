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

/// حدّ تعديلات الملف الشخصي (طلب المالك):
/// - أول 3 تعديلات لكل حقل: تُحفظ مباشرة
/// - بعدها: لا قفل زمني — كل تعديل يُرسَل للإدارة ولا يُطبَّق إلا بموافقتها
/// - كل حقل مستقل عن الآخر، والعدّاد لا يُصفَّر تلقائياً
final class ProfileEditCooldown {
    static let shared = ProfileEditCooldown()

    private let defaults = UserDefaults.standard
    private let useKeychain = true

    /// عدد التعديلات المسموحة قبل القفل — ٣ تعديلات ثم يُقفل الحقل (طلب المالك)
    private let maxFreeEdits = 3

    /// مفتاح إيقاف العداد
    private let disabledKey = "editCooldown_disabled"

    private init() {
        migrateMaritalCounterIfNeeded()
    }

    /// مرة واحدة: كان الضغط على «أعزب/متزوج» يُحسب تعديلاً قبل ربطها بـ«حفظ»
    /// (٢٠٢٦-٠٩-٢٣)، ثم استُهلك الحد بتجارب الحفظ (٢٠٢٦-٠٩-٢٤) — نصفّر عدّادها
    /// ليبدأ العدّ من جديد: أول ٣ حفظات مباشرة، والرابعة فما بعد للإدارة
    private func migrateMaritalCounterIfNeeded() {
        let flag = "editCooldown_isMarried_resetOnSaveV3"
        guard !defaults.bool(forKey: flag) else { return }
        resetCooldown(for: .isMarried)
        defaults.set(true, forKey: flag)
    }

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

    /// هل التعديل يُحفظ مباشرة؟ (false = تجاوز الحد → يحتاج موافقة الإدارة)
    func canEdit(_ field: EditableField) -> Bool {
        if isDisabled { return true }
        return loadCount(forKey: editCountKey(field)) < maxFreeEdits
    }

    /// لا قفل زمني بعد الآن — يبقى للتوافق مع الاستدعاءات القديمة
    func remainingTime(_ field: EditableField) -> TimeInterval { 0 }

    /// عدد التعديلات المباشرة المتبقية
    func remainingEdits(_ field: EditableField) -> Int {
        let count = loadCount(forKey: editCountKey(field))
        return max(0, maxFreeEdits - count)
    }

    /// تسجيل تعديل مباشر على حقل
    func recordEdit(_ field: EditableField) {
        if isDisabled { return }
        let count = loadCount(forKey: editCountKey(field)) + 1
        saveCount(count, forKey: editCountKey(field))
        Log.info("[EditLimit] تعديل \(count)/\(maxFreeEdits) على \(field.rawValue)")
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
}
