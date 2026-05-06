import Foundation

/// ثوابت التطبيق — بدل أرقام سحرية بالكود
enum AppConstants {

    // MARK: - Fetch Throttle (ثواني)
    enum Throttle {
        static let members: TimeInterval = 15
        static let news: TimeInterval = 10
        static let pendingNews: TimeInterval = 20
        static let stories: TimeInterval = 15
        static let adminRequests: TimeInterval = 20
        static let notifications: TimeInterval = 10
    }

    // MARK: - Limits
    enum Limit {
        static let fetchMax = 10000
        static let maxDevices = 3
        static let maxSearchResults = 50
        static let maxCrashLogs = 50
        static let maxAnalyticsEvents = 200
    }

    // MARK: - Delays (نانو ثانية)
    enum Delay {
        static let optimisticRevert: UInt64 = 800_000_000  // 0.8 ثانية
        static let optimisticRefresh: UInt64 = 500_000_000 // 0.5 ثانية
        static let shortDelay: UInt64 = 200_000_000        // 0.2 ثانية
        static let retryDelay: UInt64 = 300_000_000        // 0.3 ثانية
    }
}

/// أنواع الطلبات الإدارية — بدل strings سحرية
enum RequestType: String {
    case joinRequest = "join_request"
    case linkRequest = "link_request"
    case treeEdit = "tree_edit"
    case newsReport = "news_report"
    case phoneChange = "phone_change"
    case nameChange = "name_change"
    case childAdd = "child_add"
    case deceasedReport = "deceased_report"
    case photoSuggestion = "photo_suggestion"
}

/// أنواع الإشعارات — بدل strings سحرية
enum NotificationKind: String {
    case general = "general"
    case admin = "admin"
    case adminRequest = "admin_request"
    // تعديلات المدراء المباشرة
    case adminEdit = "admin_edit"
    case adminEditName = "admin_edit_name"
    case adminEditDates = "admin_edit_dates"
    case adminEditPhone = "admin_edit_phone"
    case adminEditRole = "admin_edit_role"
    case adminEditFather = "admin_edit_father"
    case adminEditAvatar = "admin_edit_avatar"
    case adminEditChildAdd = "admin_edit_child_add"
    case adminEditChildRemove = "admin_edit_child_remove"
    // شجرة وعضوية
    case treeEdit = "tree_edit"
    case linkRequest = "link_request"
    case joinApproved = "join_approved"
    case accountActivated = "account_activated"
    // أخبار وقصص
    case newsAdd = "news_add"
    case newsPublished = "news_published"
    case newsComment = "news_comment"
    case newsLike = "news_like"
    case newsReport = "news_report"
    case storyPending = "story_pending"
    case test = "test"
}

/// حالات الموافقة — بدل strings
enum ApprovalStatus: String {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
}

/// ألوان الأدوار كـ string — للـ API
extension FamilyMember.UserRole {
    var colorString: String {
        switch self {
        case .owner: return "gold"
        case .admin: return "purple"
        case .monitor: return "green"
        case .supervisor: return "orange"
        case .member: return "blue"
        case .pending: return "gray"
        }
    }
}
