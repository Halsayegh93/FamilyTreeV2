import SwiftUI

/// شاشة دردشة العضو مع الإدارة — direct message style.
/// تجمع كل رسائل العضو + ردود الإدارة في thread واحد متواصل.
struct MemberChatView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var initialLoaded: Bool = false
    @FocusState private var composerFocused: Bool

    private var messages: [ChatMessage] {
        chatMessages(from: authVM.myContactMessages)
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesScroll
                .background(DS.Color.background)

            composer
                .background(
                    Rectangle()
                        .fill(DS.Color.surfaceElevated)
                        .shadow(color: .black.opacity(0.05), radius: 6, y: -2)
                )
        }
        .navigationTitle(L10n.t("الإدارة", "Admin"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                navTitle
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .alert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(authVM.contactMessageError ?? L10n.t("تعذر الإرسال. حاول مرة أخرى.", "Send failed."))
        }
        .task {
            if !initialLoaded {
                await authVM.fetchMyContactMessages()
                initialLoaded = true
            }
            authVM.markAdminRepliesSeen()
        }
    }

    // MARK: - Nav title

    private var navTitle: some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "shield.lefthalf.filled")
                    .font(DS.Font.scaled(15, weight: .semibold))
                    .foregroundColor(DS.Color.success)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("الإدارة", "Admin"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("نرد عادةً خلال يوم", "Usually replies within a day"))
                    .font(DS.Font.scaled(10))
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    // MARK: - Messages scroll

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Spacing.xs) {
                    if messages.isEmpty {
                        emptyState
                            .padding(.top, 80)
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            let prevDate = index > 0 ? messages[index - 1].createdAt : nil
                            if shouldShowDateSeparator(current: msg.createdAt, prev: prevDate) {
                                ChatDateSeparator(date: msg.createdAt)
                            }
                            ChatBubbleView(
                                message: msg,
                                isCurrentUser: msg.senderRole == .member,
                                showTimestamp: shouldShowTimestamp(at: index),
                                showSenderLabel: false
                            )
                            .id(msg.id)
                            .padding(.horizontal, DS.Spacing.md)
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.md)
            }
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .refreshable {
                await authVM.fetchMyContactMessages(force: true)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(DS.Color.primary)
            }
            VStack(spacing: 6) {
                Text(L10n.t("ابدأ محادثة مع الإدارة", "Start a conversation"))
                    .font(DS.Font.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t(
                    "اكتب رسالتك في الأسفل — استفسار، اقتراح، شكوى، أو أي شي.",
                    "Type below — questions, suggestions, complaints, anything."
                ))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
        .padding(DS.Spacing.xl)
    }

    // MARK: - Composer

    private var composer: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty && !isSending && trimmed.count <= 1000

        return HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            TextField(
                L10n.t("اكتب رسالة…", "Type a message…"),
                text: $draft,
                axis: .vertical
            )
            .font(DS.Font.body)
            .focused($composerFocused)
            .lineLimit(1...5)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(composerFocused ? DS.Color.primary.opacity(0.4) : Color.clear, lineWidth: 1)
            )

            Button {
                Task { await sendMessage() }
            } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? DS.Color.gradientPrimary : LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                    if isSending {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(!canSend)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Actions

    private func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1000 else { return }
        isSending = true
        defer { isSending = false }

        let ok = await authVM.sendContactMessage(
            category: "استفسار",
            message: text,
            preferredContact: authVM.currentUser?.phoneNumber
        )
        if ok {
            draft = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await authVM.fetchMyContactMessages(force: true)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            showErrorAlert = true
        }
    }

    // MARK: - Helpers

    private func shouldShowDateSeparator(current: Date, prev: Date?) -> Bool {
        guard let prev = prev else { return true }
        return !Calendar.current.isDate(current, inSameDayAs: prev)
    }

    private func shouldShowTimestamp(at index: Int) -> Bool {
        // أظهر الوقت تحت آخر رسالة من نفس المرسل خلال 5 دقائق
        guard index < messages.count else { return false }
        let current = messages[index]
        let next = index + 1 < messages.count ? messages[index + 1] : nil
        guard let next = next else { return true }  // آخر رسالة
        if next.senderRole != current.senderRole { return true }
        return next.createdAt.timeIntervalSince(current.createdAt) > 300
    }
}
