import Foundation

/// «حدّ التعديلات الذاتية» كما يرجعه السيرفر (`profile_edit_limits()`، ترحيل 20261128160000) — منطق خالص بلا شبكة.
///
/// السيرفر هو الحارس: `trg_profiles_self_edit_limit` يعدّ كل تعديل مباشر على ملف العضو نفسه (العضو والمشرف فقط) في
/// `profile_edit_counts`، وبعد الحدّ يرفض (`hint = edit_limit_reached`). هذه النسخة تقرّر في الشاشة قبل الحفظ: يُحفظ
/// مباشرة أو يُرسل للإدارة — فلا يصل التطبيق رفض المشغّل إلا في سباق (تعديل من جهاز آخر في اللحظة نفسها).
/// فحصه بلا محاكي: tests/admin-redesign/PE1.
nonisolated struct ProfileEditLimitState: Equatable, Sendable {
    /// الحقول التي يعدّها السيرفر (`EditableField.rawValue`) — «إظهار الرقم» خيار خصوصية خارج الحدّ (20261128161000)
    static let serverFields: Set<String> = ["birthDate", "isMarried", "bio", "avatar", "phoneNumber"]

    /// وصل ردّ السيرفر مرة على الأقل
    var loaded = false
    /// `app_config.profile_edit_limit_enabled` — المفتاح الذي يغيّره المالك
    var enabled = true
    /// `app_config.profile_free_edits`
    var freeEdits = 3
    /// المالك والمدير والمراقب (ومن ليس مفعّلاً) معفون
    var exempt = false
    /// المستهلك لكل حقل
    var used: [String: Int] = [:]

    private var limits: Bool { loaded && enabled && !exempt }

    /// يُحفظ مباشرة؟ (false = بلغ الحدّ ← يُرسل للإدارة). قبل وصول الردّ: مباشرة، والمشغّل يبقى الحارس
    func canEdit(_ field: String) -> Bool {
        guard Self.serverFields.contains(field), limits else { return true }
        return (used[field] ?? 0) < freeEdits
    }

    func remaining(_ field: String) -> Int {
        guard Self.serverFields.contains(field), limits else { return freeEdits }
        return max(0, freeEdits - (used[field] ?? 0))
    }

    /// بعد حفظ مباشر ناجح — السيرفر عدّه، والنسخة تتبعه حتى الجلب التالي
    mutating func record(_ field: String) {
        guard Self.serverFields.contains(field), limits else { return }
        used[field, default: 0] += 1
    }

    static func parse(_ data: Data) -> ProfileEditLimitState? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = obj["enabled"] as? Bool else { return nil }
        var s = ProfileEditLimitState()
        s.loaded = true
        s.enabled = enabled
        s.freeEdits = max(0, (obj["free_edits"] as? NSNumber)?.intValue ?? 3)
        s.exempt = obj["exempt"] as? Bool ?? false
        if let fields = obj["fields"] as? [String: Any] {
            for (k, v) in fields {
                if let n = ((v as? [String: Any])?["used"] as? NSNumber)?.intValue { s.used[k] = n }
            }
        }
        return s
    }

    /// رفض المشغّل بعد الحدّ
    static func isLimitError(hint: String?) -> Bool { hint == "edit_limit_reached" }
}
