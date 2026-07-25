import Foundation

nonisolated struct NewsPost: Identifiable, Codable, Sendable {
    let id: UUID
    let created_at: String // التاريخ كنص كما يأتي من قاعدة البيانات
    let author_name: String
    let author_role: String
    let role_color: String
    let author_id: UUID?
    /// المالك الحقيقي — يُملأ دائماً، حتى حين يكون author_id فارغاً
    /// (منشور بهوية الإدارة). يُستخدم للصلاحيات لا للعرض.
    var posted_by: UUID?
    let content: String
    let type: String
    var image_url: String?
    var image_urls: [String]?
    var poll_question: String?
    var poll_options: [String]?
    var approval_status: String?
    var approved_by: UUID?
    var approved_at: String?
    
    // ✅ الإضافة السحرية: متغير يحول النص إلى تاريخ تلقائياً ليقرأه كود الواجهة
    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoWithout: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var timestamp: Date {
        Self.isoWithFraction.date(from: created_at)
            ?? Self.isoWithout.date(from: created_at)
            ?? Date()
    }

    // ربط مسميات سويفت بمسميات قاعدة البيانات (Snake Case)
    enum CodingKeys: String, CodingKey {
        case id, content, type
        case created_at = "created_at"
        case author_name = "author_name"
        case author_role = "author_role"
        case role_color = "role_color"
        case image_url = "image_url"
        case image_urls = "image_urls"
        case poll_question = "poll_question"
        case poll_options = "poll_options"
        case author_id = "author_id"
        case posted_by = "posted_by"
        case approval_status = "approval_status"
        case approved_by = "approved_by"
        case approved_at = "approved_at"
    }
    
    var isApproved: Bool {
        approval_status == nil || approval_status == "approved"
    }

    /// مالك المنشور لأغراض الصلاحيات — يتجاوز فراغ author_id في منشورات الإدارة
    var ownerId: UUID? { author_id ?? posted_by }

    var mediaURLs: [String] {
        if let image_urls, !image_urls.isEmpty {
            return image_urls
        }
        if let image_url, !image_url.isEmpty {
            return [image_url]
        }
        return []
    }

    var hasPoll: Bool {
        (poll_options?.isEmpty == false)
    }
}

nonisolated struct NewsPollVote: Identifiable, Codable, Sendable {
    let id: UUID
    let news_id: UUID
    let member_id: UUID
    let option_index: Int
    let created_at: String
}

nonisolated struct NewsLikeRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let news_id: UUID
    let member_id: UUID
    let created_at: String?
}

nonisolated struct NewsCommentRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let news_id: UUID
    let author_id: UUID?
    let author_name: String
    let content: String
    let created_at: String
}
