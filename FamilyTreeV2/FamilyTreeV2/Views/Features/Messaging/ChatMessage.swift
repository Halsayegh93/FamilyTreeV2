import Foundation

/// رسالة واحدة في chat — مشتقّة من admin_requests rows.
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderRole: ChatSenderRole
    let text: String
    let createdAt: Date
    /// مرجع الـ admin_request الأصلي (للرد عليه من جهة الإدارة)
    let sourceRequestId: UUID
}

enum ChatSenderRole {
    case member
    case admin
}

/// تحويل admin_requests إلى chat messages (member msg + optional admin reply).
extension AdminRequest {
    func toChatMessages() -> [ChatMessage] {
        var result: [ChatMessage] = []
        let parsed = ContactMessageParser.parse(self)

        // Member message — استخرج النص بدون "الموضوع:" prefix
        let rawText = parsed.message ?? details ?? ""
        let cleanText = rawText
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("الموضوع:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanText.isEmpty {
            result.append(ChatMessage(
                id: "\(id)-m",
                senderRole: .member,
                text: cleanText,
                createdAt: Self.parseDate(createdAt) ?? Date.distantPast,
                sourceRequestId: id
            ))
        }

        // Admin reply
        if let reply = adminReply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            result.append(ChatMessage(
                id: "\(id)-a",
                senderRole: .admin,
                text: reply,
                createdAt: Self.parseDate(repliedAt) ?? Self.parseDate(createdAt) ?? Date.distantPast,
                sourceRequestId: id
            ))
        }
        return result
    }

    static func parseDate(_ iso: String?) -> Date? {
        guard let iso = iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}

/// تحويل array من admin_requests إلى chat messages مرتّبة زمنياً.
func chatMessages(from requests: [AdminRequest]) -> [ChatMessage] {
    requests.flatMap { $0.toChatMessages() }
        .sorted { $0.createdAt < $1.createdAt }
}
