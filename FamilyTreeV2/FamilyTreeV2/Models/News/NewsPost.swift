import Foundation

struct NewsPost: Identifiable, Codable {
    let id: UUID
    let created_at: String // التاريخ كنص كما يأتي من قاعدة البيانات
    let author_name: String
    let author_role: String
    let role_color: String
    let author_id: UUID?
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
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoWithout: ISO8601DateFormatter = {
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
        case approval_status = "approval_status"
        case approved_by = "approved_by"
        case approved_at = "approved_at"
    }
    
    var isApproved: Bool {
        approval_status == nil || approval_status == "approved"
    }

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

struct NewsPollVote: Identifiable, Codable {
    let id: UUID
    let news_id: UUID
    let member_id: UUID
    let option_index: Int
    let created_at: String
}

struct NewsLikeRecord: Identifiable, Codable {
    let id: UUID
    let news_id: UUID
    let member_id: UUID
    let created_at: String?
}

struct NewsCommentRecord: Identifiable, Codable {
    let id: UUID
    let news_id: UUID
    let author_id: UUID?
    let author_name: String
    let content: String
    let created_at: String
}
