import Foundation

/// جسر الجلسة بين التطبيق وامتداد المشاركة.
///
/// امتداد المشاركة عملية منفصلة لا ترث تسجيل دخولك ولا تصل إلى تخزين
/// Supabase الداخلي. فنكتب هنا رمز الوصول ومعرّف العضو في حاوية
/// App Group المشتركة، ويقرأها الامتداد ليرفع باسمك.
///
/// يُخزَّن رمز الوصول فقط (قصير العمر وقابل للتجديد) — لا رمز التحديث،
/// حتى لا يبقى مفتاح دائم في مخزن مشترك.
enum SharedSessionStore {
    static let appGroupId = "group.Hasan.FamilyTreeV2"

    private enum Keys {
        static let accessToken = "shared.accessToken"
        static let expiresAt   = "shared.expiresAt"
        static let memberId    = "shared.memberId"
        static let isAdmin     = "shared.isAdmin"
        static let memberName  = "shared.memberName"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// يحفظ ما يحتاجه الامتداد للرفع. يُستدعى عند الدخول وعند تجديد الجلسة.
    static func save(accessToken: String,
                     expiresAt: TimeInterval,
                     memberId: UUID?,
                     memberName: String?,
                     isAdmin: Bool) {
        guard let defaults else { return }
        defaults.set(accessToken, forKey: Keys.accessToken)
        defaults.set(expiresAt, forKey: Keys.expiresAt)
        defaults.set(memberId?.uuidString, forKey: Keys.memberId)
        defaults.set(memberName, forKey: Keys.memberName)
        defaults.set(isAdmin, forKey: Keys.isAdmin)
    }

    /// يمسح الجسر عند تسجيل الخروج — الامتداد يفقد صلاحيته فوراً.
    static func clear() {
        guard let defaults else { return }
        for key in [Keys.accessToken, Keys.expiresAt, Keys.memberId,
                    Keys.memberName, Keys.isAdmin] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - القراءة (يستخدمها الامتداد)

    struct Snapshot {
        let accessToken: String
        let memberId: String
        let memberName: String
        let isAdmin: Bool
    }

    /// يعيد الجلسة المشتركة إن كانت موجودة وصالحة (لم تنتهِ).
    static func current() -> Snapshot? {
        guard let defaults,
              let token = defaults.string(forKey: Keys.accessToken),
              let memberId = defaults.string(forKey: Keys.memberId),
              !token.isEmpty, !memberId.isEmpty
        else { return nil }

        let expiresAt = defaults.double(forKey: Keys.expiresAt)
        // هامش دقيقة: رمز على وشك الانتهاء لا ينفع لرفع قد يطول
        guard expiresAt > Date().timeIntervalSince1970 + 60 else { return nil }

        return Snapshot(
            accessToken: token,
            memberId: memberId,
            memberName: defaults.string(forKey: Keys.memberName) ?? "",
            isAdmin: defaults.bool(forKey: Keys.isAdmin)
        )
    }
}
