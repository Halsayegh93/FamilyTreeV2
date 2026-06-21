import SwiftUI

// MARK: - SwiftUI-dependent extensions for FamilyMember
// تم فصل هذه الأشياء عن الـ struct الأصلي لمنع main-actor isolation
// من ينشر إلى Decodable conformance ويكسر loadAsync<T: Decodable & Sendable>

extension FamilyMember.UserRole {
    /// اللون العلني — المالك يظهر بنفس لون المدير
    var color: Color {
        switch self {
        case .owner:      return DS.Color.primary
        case .admin:      return DS.Color.adminRole
        case .monitor:    return DS.Color.monitorRole
        case .supervisor: return DS.Color.supervisorRole
        case .member:     return DS.Color.memberRole
        case .pending:    return DS.Color.pendingRole
        }
    }
}

extension FamilyMember {
    /// لون دور العضو — يسهّل الوصول: member.roleColor ✅
    var roleColor: Color {
        return role.color
    }

    /// العضو داخل المنظومة (نشط فعلياً):
    /// - حي (ليس متوفى)
    /// - ليس قيد المراجعة (role != .pending)
    /// - حسابه غير مجمّد (status != .frozen)
    /// - **عنده رقم هاتف موثّق** (إشارة حقيقية للنشاط في التطبيق/الإدارة)
    /// لإزالة النشاط: المدير يجمّد الحساب أو يحذف الرقم
    var isInSystem: Bool {
        guard isDeceased != true else { return false }
        guard role != .pending else { return false }
        guard status != .frozen else { return false }
        let phone = (phoneNumber ?? "").trimmingCharacters(in: .whitespaces)
        return !phone.isEmpty
    }

    /// أنثى — التخزين: gender == "female" (الافتراضي ذكر).
    var isFemale: Bool { (gender ?? "").lowercased() == "female" }

    /// أيقونة بديلة محايدة (للذكور عند غياب الصورة). الإناث يُعرض لهنّ
    /// `FemaleAvatarView` بدلاً من أي صورة/أيقونة.
    var fallbackSymbol: String { "person.fill" }

    /// قاعدة التطبيق: الأنثى لا تُعرض لها صورة شخصية إطلاقاً — دائماً البديل.
    var displayAvatarUrl: String? { isFemale ? nil : avatarUrl }
}
