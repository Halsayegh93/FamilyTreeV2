import SwiftUI

struct AIChatView: View {
    @StateObject private var aiVM: AIViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isInputFocused: Bool

    init(userId: String) {
        _aiVM = StateObject(wrappedValue: AIViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                VStack(spacing: 0) {
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: DS.Spacing.md) {
                                if aiVM.chatMessages.isEmpty {
                                    welcomeCard
                                }

                                ForEach(aiVM.chatMessages) { message in
                                    ChatBubbleView(message: message)
                                        .id(message.id)
                                }

                                if aiVM.isChatLoading {
                                    typingIndicator
                                        .id("typing")
                                }
                            }
                            .padding(DS.Spacing.lg)
                        }
                        .onChange(of: aiVM.chatMessages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: aiVM.isChatLoading) { _, loading in
                            if loading { scrollToBottom(proxy: proxy) }
                        }
                    }

                    // Error banner
                    if let error = aiVM.errorMessage {
                        Text(error)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(DS.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(DS.Color.error)
                            .transition(.move(edge: .bottom))
                    }

                    // Input bar
                    chatInputBar
                }
            }
            .navigationTitle(L10n.t("المساعد الذكي", "AI Assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        aiVM.clearChat()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(DS.Color.error)
                    }
                    .disabled(aiVM.chatMessages.isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 70, height: 70)
                    .dsGlowShadow()
                Image(systemName: "brain.head.profile")
                    .font(DS.Font.scaled(28, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }

            Text(L10n.t("مرحباً! أنا المساعد الذكي", "Hello! I'm the AI Assistant"))
                .font(DS.Font.title3)

            Text(L10n.t(
                "اسألني عن شجرة العائلة، مثل:\n• من هو جد فلان؟\n• كم عدد أعضاء الشجرة؟\n• من هم أبناء فلان؟",
                "Ask me about the family tree:\n• Who is X's grandfather?\n• How many members?\n• Who are X's children?"
            ))
            .font(DS.Font.callout)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)

            // Quick suggestion buttons
            VStack(spacing: DS.Spacing.sm) {
                ForEach(quickSuggestions, id: \.self) { suggestion in
                    Button {
                        aiVM.chatInput = suggestion
                        Task { await aiVM.sendChatMessage() }
                    } label: {
                        Text(suggestion)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.primary.opacity(0.08))
                            .cornerRadius(DS.Radius.full)
                    }
                }
            }
        }
        .padding(DS.Spacing.xxl)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.xl)
        .dsCardShadow()
        .padding(.top, DS.Spacing.xxxl)
    }

    private var quickSuggestions: [String] {
        [
            L10n.t("كم عدد أعضاء الشجرة؟", "How many members?"),
            L10n.t("من هم الأعضاء المتوفين؟", "Who are the deceased members?"),
            L10n.t("حلل شجرة العائلة", "Analyze the family tree")
        ]
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(DS.Color.primary.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(aiVM.isChatLoading ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                            value: aiVM.isChatLoading
                        )
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .cornerRadius(DS.Radius.lg)
            .dsSubtleShadow()

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var chatInputBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            TextField(
                L10n.t("اكتب سؤالك هنا...", "Type your question..."),
                text: $aiVM.chatInput
            )
            .font(DS.Font.body)
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .cornerRadius(DS.Radius.lg)
            .focused($isInputFocused)
            .onSubmit {
                Task { await aiVM.sendChatMessage() }
            }

            Button {
                Task { await aiVM.sendChatMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(DS.Font.scaled(36))
                    .foregroundStyle(DS.Color.gradientPrimary)
            }
            .disabled(
                aiVM.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || aiVM.isChatLoading
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surfaceElevated)
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            if aiVM.isChatLoading {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = aiVM.chatMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubbleView: View {
    let message: AIChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DS.Spacing.xs) {
                Text(message.content)
                    .font(DS.Font.body)
                    .foregroundColor(isUser ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                    .padding(DS.Spacing.md)
                    .background(
                        Group {
                            if isUser {
                                DS.Color.gradientPrimary
                            } else {
                                LinearGradient(colors: [DS.Color.surface], startPoint: .leading, endPoint: .trailing)
                            }
                        }
                    )
                    .cornerRadius(DS.Radius.lg)
                    .dsSubtleShadow()
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
