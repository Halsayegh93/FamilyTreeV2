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
}
