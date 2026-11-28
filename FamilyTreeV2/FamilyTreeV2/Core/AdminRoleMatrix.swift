import Foundation

// MARK: - مين يشوف وش في لوحة الإدارة — من السيرفر (مقترح «أدوار الإدارة» بموافقة المالك ٢٠٢٦-١١-٠٧)
//
// قاعدة المالك: «كل شي يكون على قاعدة البيانات، ما نبي التطبيق كل شوي». الجدول (الدور ← الأقسام الستة وبطاقات «اليوم»
// وصفوف الأقسام، وكل خانة «يشوف ويعدّل» أو «يشوف بس» أو «ما يشوف») مفتاح واحد في `app_config`:
// `admin_role_matrix` (نوع json) يُقرأ عبر `app_config()` (`AppConfigValues`) ويغيّره المالك بـ`set_app_config` بلا بناء.
// شكله: {"admin": {"areas": {"team": "read", …}, "items": {"today.census": "read", …}, "attention_fourth": "messages"},
//        "monitor": {…}, "supervisor": {…}}
// • مفتاح غائب، أو دور غائب، أو خانة غائبة أو قيمتها غير معروفة = الافتراضي المكتوب هنا (= المقترح المعتمد) — خانةً خانة.
// • المالكان (الاثنين) دائماً كل شي — لا يدخلان الجدول، فلا يقفل إعداد خاطئ أحداً منهما خارج اللوحة.
// • السقف: ما يحرسه السيرفر للمالك وحده (قسم «التطبيق»، رسائل الدخول، التسجيل والمنع، الأجهزة) لا يفتحه الجدول لغيره —
//   يرفضه فحص السيرفر عند الحفظ (`trg_app_config_role_matrix_guard`) ويقصّه التطبيق هنا أيضاً.
// • الجدول للظهور فقط: الصلاحيات الفعلية (`canApproveContent`، `canRegisterMembers`… وحرّاس السيرفر) كما هي؛
//   «يشوف ويعدّل» لا يمنح دوراً ما لا يملكه، و«يشوف بس» يُخفي أزرار التعديل حتى لو كان يملكها.

/// مستوى الوصول في خانة
enum AdminAccess: String {
    case edit, read, none

    var canSee: Bool { self != .none }
    var canEdit: Bool { self == .edit }
}

/// الرقم الرابع في «يحتاج انتباهك» — من مجال الدور
enum AdminAttentionFourth: String {
    /// رسائل الأعضاء غير المقروءة (المالك والمدير)
    case messages
    /// «مشكلات الشجرة» (المراقب)
    case treeIssues = "tree_issues"
    /// البلاغات (المشرف)
    case reports
}

/// خانات الجدول غير الأقسام — بطاقات «اليوم» وصفوف داخل الأقسام. المفتاح = الاسم في JSON
enum AdminRoleItem: String, CaseIterable {
    // «اليوم»
    case todayAttention    = "today.attention"
    case todayCensus       = "today.census"
    case todaySystemStatus = "today.system_status"
    case todayMegaphone    = "today.megaphone"
    // الوارد
    case inboxMessages         = "inbox.messages"
    case inboxPhotos           = "inbox.photos"
    case inboxApprovalSettings = "inbox.approval_settings"
    // المناسبات والإعلانات
    case occasionsUpcoming  = "occasions.upcoming"
    case occasionsAnnounce  = "occasions.announce"
    case occasionsCards     = "occasions.cards"
    case occasionsPublished = "occasions.published"
    // المؤشرات
    case metricsFamily    = "metrics.family"
    case metricsApprovals = "metrics.approvals"
    // الفريق والأمان (المفاتيح ثابتة — جدول السيرفر). منذ ٢٠٢٦-١١-٢٨ القسم اسمه «الفريق والصلاحيات»، و`team.usage` بيته
    // «الإحصاءات ← في التطبيق»، و`team.sms`/`team.devices` بيتهما «التطبيق والنظام ← النظام» — الخانات وقيمها كما هي
    case teamMembers      = "team.members"
    case teamUsage        = "team.usage"
    case teamSms          = "team.sms"
    case teamRegistration = "team.registration"
    case teamDevices      = "team.devices"
    // التطبيق
    case appSettings = "app.settings"

    /// يحرسه السيرفر للمالك وحده — لا يفتحه الجدول لغيره
    var isOwnerOnly: Bool {
        switch self {
        case .teamSms, .teamRegistration, .teamDevices, .appSettings: return true
        default: return false
        }
    }
}

@MainActor
enum AdminRoleMatrix {
    /// مفتاح `app_config`
    static let configKey = "admin_role_matrix"

    // MARK: الافتراضي (= المقترح المعتمد — نفس قيمة المفتاح في الترحيل 20261107200000)

    private struct Row {
        let areas: [AdminArea: AdminAccess]
        let items: [AdminRoleItem: AdminAccess]
        let fourth: AdminAttentionFourth
    }

    private static let defaults: [FamilyMember.UserRole: Row] = [
        .admin: Row(
            areas: [.inbox: .edit, .family: .edit, .occasions: .edit, .metrics: .read, .team: .read, .app: .none],
            items: [.todayAttention: .read, .todayCensus: .read, .todaySystemStatus: .none, .todayMegaphone: .edit,
                    .inboxMessages: .edit, .inboxPhotos: .edit, .inboxApprovalSettings: .read,
                    .occasionsUpcoming: .edit, .occasionsAnnounce: .edit, .occasionsCards: .edit, .occasionsPublished: .read,
                    .metricsFamily: .read, .metricsApprovals: .read,
                    .teamMembers: .read, .teamUsage: .read, .teamSms: .none, .teamRegistration: .none, .teamDevices: .none,
                    .appSettings: .none],
            fourth: .messages),
        .monitor: Row(
            areas: [.inbox: .edit, .family: .edit, .occasions: .read, .metrics: .read, .team: .none, .app: .none],
            items: [.todayAttention: .read, .todayCensus: .read, .todaySystemStatus: .none, .todayMegaphone: .none,
                    .inboxMessages: .none, .inboxPhotos: .edit, .inboxApprovalSettings: .none,
                    .occasionsUpcoming: .read, .occasionsAnnounce: .none, .occasionsCards: .none, .occasionsPublished: .none,
                    .metricsFamily: .read, .metricsApprovals: .none,
                    .teamMembers: .none, .teamUsage: .none, .teamSms: .none, .teamRegistration: .none, .teamDevices: .none,
                    .appSettings: .none],
            fourth: .treeIssues),
        .supervisor: Row(
            areas: [.inbox: .edit, .family: .none, .occasions: .edit, .metrics: .none, .team: .none, .app: .none],
            items: [.todayAttention: .read, .todayCensus: .none, .todaySystemStatus: .none, .todayMegaphone: .none,
                    .inboxMessages: .none, .inboxPhotos: .none, .inboxApprovalSettings: .none,
                    .occasionsUpcoming: .read, .occasionsAnnounce: .none, .occasionsCards: .edit, .occasionsPublished: .none,
                    .metricsFamily: .none, .metricsApprovals: .none,
                    .teamMembers: .none, .teamUsage: .none, .teamSms: .none, .teamRegistration: .none, .teamDevices: .none,
                    .appSettings: .none],
            fourth: .reports)
    ]

    // MARK: القراءة

    /// وصول الدور لقسم
    static func access(_ area: AdminArea, for role: FamilyMember.UserRole?) -> AdminAccess {
        guard let role else { return .none }
        if role == .owner { return .edit }
        guard let row = defaults[role] else { return .none }
        if area == .app { return .none }   // السقف: «التطبيق» للمالك وحده
        return serverValue(role: role, group: "areas", key: area.rawValue) ?? row.areas[area] ?? .none
    }

    /// وصول الدور لخانة
    static func access(_ item: AdminRoleItem, for role: FamilyMember.UserRole?) -> AdminAccess {
        guard let role else { return .none }
        if role == .owner { return .edit }
        guard let row = defaults[role] else { return .none }
        if item.isOwnerOnly { return .none }   // السقف
        return serverValue(role: role, group: "items", key: item.rawValue) ?? row.items[item] ?? .none
    }

    /// الرقم الرابع في «يحتاج انتباهك»
    static func attentionFourth(for role: FamilyMember.UserRole?) -> AdminAttentionFourth {
        guard let role, role != .owner, let row = defaults[role] else { return .messages }
        if let raw = roleObject(role)?["attention_fourth"] as? String, let v = AdminAttentionFourth(rawValue: raw) {
            return v
        }
        return row.fourth
    }

    // MARK: من السيرفر

    private static func roleObject(_ role: FamilyMember.UserRole) -> [String: Any]? {
        #if DEBUG
        // أداة الفحص T0 (`-tmpRoleMatrix`): جدول تجريبي يحلّ محلّ جدول السيرفر في النسخة التجريبية فقط
        if let o = DebugAdminProbe.roleMatrixOverride(role.rawValue) { return o }
        #endif
        return (AppConfigValues.shared.values[configKey] as? [String: Any])?[role.rawValue] as? [String: Any]
    }

    private static func serverValue(role: FamilyMember.UserRole, group: String, key: String) -> AdminAccess? {
        guard let raw = (roleObject(role)?[group] as? [String: Any])?[key] as? String else { return nil }
        return AdminAccess(rawValue: raw)
    }
}

// MARK: - اختصارات على المستخدم الحالي

extension AuthViewModel {
    /// وصول دورك لقسم من أقسام اللوحة (الجدول من السيرفر) — `canModerate` شرط أول
    func adminAccess(_ area: AdminArea) -> AdminAccess {
        guard canModerate else { return .none }
        return AdminRoleMatrix.access(area, for: currentUser?.role)
    }

    /// وصول دورك لخانة من خانات اللوحة (الجدول من السيرفر)
    func adminAccess(_ item: AdminRoleItem) -> AdminAccess {
        guard canModerate else { return .none }
        return AdminRoleMatrix.access(item, for: currentUser?.role)
    }

    /// يشوف الخانة (اختصار)
    func adminSees(_ item: AdminRoleItem) -> Bool { adminAccess(item).canSee }
}
