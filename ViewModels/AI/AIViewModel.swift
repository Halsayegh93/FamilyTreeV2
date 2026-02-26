import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class AIViewModel: ObservableObject {
    let supabase = SupabaseConfig.client

    // MARK: - Chat State
    @Published var chatMessages: [AIChatMessage] = []
    @Published var chatInput: String = ""
    @Published var isChatLoading: Bool = false

    // MARK: - News Generation State
    @Published var generatedNewsContent: String = ""
    @Published var generatedNewsType: String = "خبر"
    @Published var isNewsLoading: Bool = false
    @Published var newsError: String?

    // MARK: - Admin Summary State
    @Published var adminSummary: String = ""
    @Published var adminStats: AIAdminResponse.AdminStats?
    @Published var isAdminLoading: Bool = false
    @Published var adminError: String?

    // MARK: - Tree Analysis State
    @Published var treeAnalysis: String = ""
    @Published var isTreeAnalysisLoading: Bool = false
    @Published var treeAnalysisError: String?

    // MARK: - Generic Error
    @Published var errorMessage: String?

    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Type-erased Encodable wrapper

    private struct AnyEncodable: Encodable {
        private let _encode: (Encoder) throws -> Void
        init<T: Encodable>(_ wrapped: T) {
            _encode = wrapped.encode
        }
        func encode(to encoder: Encoder) throws {
            try _encode(encoder)
        }
    }

    // MARK: - Helper: Call Edge Function

    private func invokeAI(payload: [String: AnyEncodable]) async throws -> Data {
        try await supabase.functions.invoke(
            "claude-ai",
            options: FunctionInvokeOptions(body: payload)
        ) { data, _ in data }
    }

    // MARK: - Chat

    func sendChatMessage() async {
        let trimmed = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = AIChatMessage(role: "user", content: trimmed, timestamp: Date())
        chatMessages.append(userMsg)
        chatInput = ""
        isChatLoading = true
        errorMessage = nil

        // Build conversation history (last 10 messages, exclude latest user msg)
        let historyMessages = Array(chatMessages.dropLast().suffix(10))
        let history = historyMessages.map { msg in
            ["role": msg.role, "content": msg.content]
        }

        let payload: [String: AnyEncodable] = [
            "action": AnyEncodable("chat"),
            "user_id": AnyEncodable(userId),
            "message": AnyEncodable(trimmed),
            "conversation_history": AnyEncodable(history)
        ]

        do {
            let data = try await invokeAI(payload: payload)
            let result = try JSONDecoder().decode(AIResponse.self, from: data)
            if result.ok, let reply = result.reply {
                let assistantMsg = AIChatMessage(role: "assistant", content: reply, timestamp: Date())
                chatMessages.append(assistantMsg)
            } else {
                errorMessage = result.message ?? L10n.t("حدث خطأ غير متوقع", "An unexpected error occurred")
            }
        } catch {
            errorMessage = L10n.t(
                "تعذر الاتصال بالمساعد الذكي",
                "Could not connect to AI assistant"
            )
            Log.error("Chat error: \(error.localizedDescription)")
        }

        isChatLoading = false
    }

    // MARK: - Generate News

    func generateNews(topic: String, newsType: String) async {
        isNewsLoading = true
        newsError = nil
        generatedNewsContent = ""

        let payload: [String: AnyEncodable] = [
            "action": AnyEncodable("generate_news"),
            "user_id": AnyEncodable(userId),
            "topic": AnyEncodable(topic),
            "news_type": AnyEncodable(newsType)
        ]

        do {
            let data = try await invokeAI(payload: payload)
            let result = try JSONDecoder().decode(AINewsResponse.self, from: data)
            if result.ok, let newsData = result.news_data {
                generatedNewsContent = newsData.content ?? ""
                generatedNewsType = newsData.type ?? "خبر"
            } else {
                newsError = result.message ?? L10n.t("تعذر إنشاء الخبر", "Could not generate news")
            }
        } catch {
            newsError = L10n.t("خطأ في إنشاء الخبر", "Error generating news")
            Log.error("News generation error: \(error.localizedDescription)")
        }

        isNewsLoading = false
    }

    // MARK: - Admin Summary

    func fetchAdminSummary() async {
        isAdminLoading = true
        adminError = nil
        adminSummary = ""

        let payload: [String: AnyEncodable] = [
            "action": AnyEncodable("admin_summary"),
            "user_id": AnyEncodable(userId)
        ]

        do {
            let data = try await invokeAI(payload: payload)
            let result = try JSONDecoder().decode(AIAdminResponse.self, from: data)
            if result.ok {
                adminSummary = result.reply ?? ""
                adminStats = result.stats
            } else {
                adminError = result.message ?? L10n.t("تعذر جلب الملخص", "Could not fetch summary")
            }
        } catch {
            adminError = L10n.t("خطأ في جلب الملخص الإداري", "Error fetching admin summary")
            Log.error("Admin summary error: \(error.localizedDescription)")
        }

        isAdminLoading = false
    }

    // MARK: - Tree Analysis

    func analyzeTree() async {
        isTreeAnalysisLoading = true
        treeAnalysisError = nil
        treeAnalysis = ""

        let payload: [String: AnyEncodable] = [
            "action": AnyEncodable("analyze_tree"),
            "user_id": AnyEncodable(userId)
        ]

        do {
            let data = try await invokeAI(payload: payload)
            let result = try JSONDecoder().decode(AIResponse.self, from: data)
            if result.ok {
                treeAnalysis = result.reply ?? ""
            } else {
                treeAnalysisError = result.message ?? L10n.t("تعذر تحليل الشجرة", "Could not analyze tree")
            }
        } catch {
            treeAnalysisError = L10n.t("خطأ في تحليل الشجرة", "Error analyzing tree")
            Log.error("Tree analysis error: \(error.localizedDescription)")
        }

        isTreeAnalysisLoading = false
    }

    // MARK: - Clear Chat

    func clearChat() {
        chatMessages = []
        errorMessage = nil
    }
}
