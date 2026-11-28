import Foundation
import Supabase
import Combine

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

/// حدّ تعديلات الملف الشخصي (طلب المالك) — **على السيرفر** منذ ٢٠٢٦-١١-٢٨ (ترحيل 20261128160000):
/// - أول N تعديلات لكل حقل (`app_config.profile_free_edits`، ٣) تُحفظ مباشرة، وبعدها كل تعديل يُرسل للإدارة
/// - كل حقل مستقل، والعدّاد لا يُصفَّر تلقائياً — لكل عضو في `profile_edit_counts` يعدّه المشغّل `trg_profiles_self_edit_limit`
/// - المفتاح (`profile_edit_limit_enabled`) وإعادة الضبط من «الإدارة ← التطبيق» تصل كل الأعضاء (كانا على جهاز المالك فقط)
/// - العضو والمشرف فقط؛ المالك والمدير والمراقب معفون (`exempt`)
/// هذه الطبقة تجلب `profile_edit_limits()` وتقرّر في الشاشة (`ProfileEditLimitState`).
@MainActor
final class ProfileEditCooldown: ObservableObject {
    static let shared = ProfileEditCooldown()

    @Published private(set) var state = ProfileEditLimitState()

    private init() {
        clearOldDeviceCounters()
    }

    /// مرة واحدة: عدّادات الجهاز القديمة (UserDefaults/Keychain) لم تعد تُقرأ
    private func clearOldDeviceCounters() {
        let defaults = UserDefaults.standard
        let flag = "editCooldown_serverV1"
        guard !defaults.bool(forKey: flag) else { return }
        for field in EditableField.allCases {
            for key in ["editCooldown_\(field.rawValue)_count", "editCooldown_\(field.rawValue)_lockDate"] {
                defaults.removeObject(forKey: key)
                KeychainHelper.delete(forKey: key)
            }
        }
        defaults.removeObject(forKey: "editCooldown_disabled")
        defaults.set(true, forKey: flag)
    }

    // MARK: - السيرفر

    /// يجلب حالة المتصل (`profile_edit_limits()`) — يبقي آخر حالة إن فشل؛ true = وصل ردّ مفهوم
    @discardableResult
    func refresh() async -> Bool {
        do {
            let data = try await SupabaseConfig.client.rpc("profile_edit_limits").execute().data
            guard let fresh = ProfileEditLimitState.parse(data) else { return false }
            state = fresh
            return true
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[EditLimit] profile_edit_limits: \(error.localizedDescription)")
            }
            return false
        }
    }

    /// هل الحدّ مطفأ؟ (`profile_edit_limit_enabled`)
    var isDisabled: Bool { !state.enabled }

    /// المالك: يشغّل/يطفئ الحدّ لكل الأعضاء (`set_app_config`)
    func setLimitEnabled(_ on: Bool) async -> Bool {
        struct Params: Encodable { let p_key: String; let p_value: Bool }
        do {
            _ = try await SupabaseConfig.client
                .rpc("set_app_config", params: Params(p_key: "profile_edit_limit_enabled", p_value: on)).execute()
            state.enabled = on
            await refresh()
            return state.enabled == on
        } catch {
            if !ErrorHelper.isCancellation(error) { Log.warning("[EditLimit] set_app_config: \(error.localizedDescription)") }
            return false
        }
    }

    /// المالك: يصفّر عدّاد كل الأعضاء (`reset_profile_edit_counts()`) — يرجع عدد الصفوف المحذوفة، nil عند الفشل
    func resetAllMembers() async -> Int? {
        do {
            let data = try await SupabaseConfig.client.rpc("reset_profile_edit_counts").execute().data
            let n = Int(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            Log.info("[EditLimit] صُفّر عدّاد كل الأعضاء (\(n) صف)")
            await refresh()
            return n
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[EditLimit] reset_profile_edit_counts: \(error.localizedDescription)")
            }
            return nil
        }
    }

    // MARK: - Public API

    /// هل التعديل يُحفظ مباشرة؟ (false = تجاوز الحد → يحتاج موافقة الإدارة)
    func canEdit(_ field: EditableField) -> Bool { state.canEdit(field.rawValue) }

    /// لا قفل زمني بعد الآن — يبقى للتوافق مع الاستدعاءات القديمة
    func remainingTime(_ field: EditableField) -> TimeInterval { 0 }

    /// عدد التعديلات المباشرة المتبقية
    func remainingEdits(_ field: EditableField) -> Int { state.remaining(field.rawValue) }

    /// بعد حفظ مباشر ناجح — السيرفر عدّه بالمشغّل، والنسخة المحلية تتبعه حتى الجلب التالي
    func recordEdit(_ field: EditableField) {
        state.record(field.rawValue)
        Log.info("[EditLimit] تعديل على \(field.rawValue) — متبقٍ \(state.remaining(field.rawValue))")
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
}
