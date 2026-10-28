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
