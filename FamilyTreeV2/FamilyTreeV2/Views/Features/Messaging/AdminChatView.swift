import SwiftUI

/// شاشة دردشة الإدارة مع عضو محدد — direct message style.
/// الإدارة ترد على آخر رسالة معلّقة من العضو، أو ترسل رسالة جديدة (تُحفظ كـ admin reply لآخر row).
struct AdminChatView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    /// عضو المحادثة
    let memberId: UUID

    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var loaded: Bool = false
    @FocusState private var composerFocused: Bool

    private var memberThreads: [AdminRequest] {
        adminRequestVM.contactMessages.filter { $0.memberId == memberId }
    }

    private var messages: [ChatMessage] {
        chatMessages(from: memberThreads)
    }

    private var member: FamilyMember? {
        memberThreads.first?.member ?? memberVM.allMembers.first(where: { $0.id == memberId })
    }

    /// آخر رسالة من العضو لم يُرد عليها — هدف الرد الجديد.
    private var latestUnrepliedRow: AdminRequest? {
        memberThreads
            .filter { $0.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .first
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
        .navigationTitle(member?.fullName ?? L10n.t("عضو", "Member"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                navTitle
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .task {
            if !loaded {
                await adminRequestVM.fetchContactMessages()
                loaded = true
            }
        }
    }

    // MARK: - Nav title

    private var navTitle: some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.18))
                    .frame(width: 32, height: 32)
                Text(String((member?.fullName ?? "?").prefix(1)))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(member?.fourPartName ?? member?.fullName ?? "—")
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let phone = member?.phoneNumber, !phone.isEmpty {
                    Text(KuwaitPhone.display(phone))
                        .font(DS.Font.scaled(10))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Spacing.xs) {
                    if messages.isEmpty {
                        Text(L10n.t("لا توجد رسائل من هذا العضو", "No messages from this member"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, 80)
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            let prevDate = index > 0 ? messages[index - 1].createdAt : nil
                            if shouldShowDateSeparator(current: msg.createdAt, prev: prevDate) {
                                ChatDateSeparator(date: msg.createdAt)
                            }
                            ChatBubbleView(
                                message: msg,
                                isCurrentUser: msg.senderRole == .admin,
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
        }
    }

    // MARK: - Composer

    private var composer: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let canReply = latestUnrepliedRow != nil
        let canSend = !trimmed.isEmpty && !isSending && trimmed.count <= 2000 && canReply

        return VStack(spacing: 4) {
            if !canReply {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(DS.Font.caption2)
                    Text(L10n.t(
                        "كل الرسائل ردّت عليها — انتظر العضو يرسل رسالة جديدة",
                        "All messages replied — wait for the member to message"
                    ))
                    .font(DS.Font.caption2)
                    Spacer()
                }
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.md)
            }

            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                TextField(
                    L10n.t("اكتب رد…", "Type a reply…"),
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
                .disabled(!canReply)
                .opacity(canReply ? 1 : 0.5)

                Button {
                    Task { await sendReply() }
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
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Actions

    private func sendReply() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { return }
        guard let targetRow = latestUnrepliedRow else { return }
        isSending = true
        defer { isSending = false }
        let ok = await adminRequestVM.replyToContactMessage(targetRow, replyText: text)
        if ok {
            draft = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await adminRequestVM.fetchContactMessages(force: true)
        }
    }

    // MARK: - Helpers

    private func shouldShowDateSeparator(current: Date, prev: Date?) -> Bool {
        guard let prev = prev else { return true }
        return !Calendar.current.isDate(current, inSameDayAs: prev)
    }

    private func shouldShowTimestamp(at index: Int) -> Bool {
        guard index < messages.count else { return false }
        let current = messages[index]
        let next = index + 1 < messages.count ? messages[index + 1] : nil
        guard let next = next else { return true }
        if next.senderRole != current.senderRole { return true }
        return next.createdAt.timeIntervalSince(current.createdAt) > 300
    }
}
