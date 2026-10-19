import Foundation
import Supabase

// MARK: - هوية الحساب الحالي

/// معرّفا المستخدم الحالي: معرّف الملف في الشجرة (`currentUser.id`) ومعرّف الدخول
/// (auth). يختلفان للعضو المربوط بسجل قديم في الشجرة — والتعليقات تُحفظ بمعرّف الدخول.
enum AccountIdentity {
    static var authUserId: UUID? { SupabaseConfig.client.auth.currentUser?.id }

    /// هل هذا المعرّف للمستخدم الحالي (بأي من معرّفيه)؟
    static func isMine(_ id: UUID?, currentUser: FamilyMember?) -> Bool {
        guard let id else { return false }
        return id == currentUser?.id || id == authUserId
    }
}

// MARK: - الموافقة على شروط الاستخدام (EULA — Guideline 1.2)
//
// يوافق العضو مرة واحدة: عند التسجيل (قبل إرسال طلب الانضمام)، والأعضاء الحاليون
// بمربّع لمرة واحدة عند أول دخول بعد التحديث. تُحفظ على الجهاز لكل عضو
// (UserDefaults) — بلا أي تغيير في السيرفر.

enum TermsAgreement {
    /// ارفع الرقم إذا تغيّرت الشروط جوهرياً — فيُطلب من الجميع الموافقة مرة أخرى
    static let version = 1

    private static func key(_ id: UUID) -> String {
        "termsAccepted.v\(version).\(id.uuidString.lowercased())"
    }

    /// هل وافق هذا العضو (بمعرّف ملفه أو بمعرّف دخوله) على النسخة الحالية؟
    static func hasAccepted(_ ids: [UUID?]) -> Bool {
        ids.contains { id in
            guard let id else { return false }
            return UserDefaults.standard.object(forKey: key(id)) != nil
        }
    }

    /// يسجّل الموافقة (مع وقتها) لكل المعرّفات المعروفة للعضو
    static func accept(_ ids: [UUID?]) {
        let now = Date()
        for case let id? in ids {
            UserDefaults.standard.set(now, forKey: key(id))
        }
    }
}
