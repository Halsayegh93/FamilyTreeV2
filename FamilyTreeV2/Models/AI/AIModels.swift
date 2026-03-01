import Foundation

// MARK: - Chat Message
struct AIChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String   // "user" or "assistant"
    let content: String
    let timestamp: Date

    static func == (lhs: AIChatMessage, rhs: AIChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - API Response Models

struct AIResponse: Decodable {
    let ok: Bool
    let reply: String?
    let message: String?
    let action: String?
}

struct AINewsResponse: Decodable {
    let ok: Bool
    let reply: String?
    let news_data: NewsDataDTO?
    let message: String?

    struct NewsDataDTO: Decodable {
        let content: String?
        let type: String?
    }
}

struct AIAdminResponse: Decodable {
    let ok: Bool
    let reply: String?
    let stats: AdminStats?
    let message: String?

    struct AdminStats: Decodable {
        let total_members: Int?
        let active: Int?
        let pending_members: Int?
        let pending_requests: Int?
        let pending_news: Int?
    }
}
