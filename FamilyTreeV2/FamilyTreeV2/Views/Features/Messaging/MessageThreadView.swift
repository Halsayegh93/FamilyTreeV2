import SwiftUI

/// عرض موحّد لمحادثة (Thread) — يستخدمه العضو والإدارة.
/// يعرض الرسائل كبطاقات مرتّبة بالوقت + خيار رد للإدارة.
struct MessageThreadView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss

    let thread: AdminRequest
    /// true لعرض من جهة الإدارة (يظهر composer للرد)
    let isAdminView: Bool

    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var showSuccessToast: Bool = false
    @FocusState private var isReplyFocused: Bool

    // MARK: - Derived

    private var parsed: ContactMessageParser.Parsed {
        ContactMessageParser.parse(thread)
    }

    private var adminReply: String? {
        let r = thread.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r?.isEmpty ?? true) ? nil : r
    }

    private var status: ThreadStatus {
        if adminReply != nil { return .replied }
        return .open
    }

    private var subjectLine: String {
        // محاولة استخراج "الموضوع: …" من نص الرسالة
        let body = parsed.message ?? thread.details ?? ""
        for line in body.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("الموضوع:") {
                return t.replacingOccurrences(of: "الموضوع:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return parsed.category ?? L10n.t("بدون عنوان", "Untitled")
    }

    private var memberName: String {
        thread.member?.fullName ?? L10n.t("عضو", "Member")
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    threadHeader

                    memberMessageCard

                    if let reply = adminReply {
                        adminReplyCard(reply)
                    } else if !isAdminView {
                        awaitingReplyCard
                    }

                    Spacer(minLength: isAdminView && adminReply == nil ? 200 : 80)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }

            // Reply composer للإدارة فقط لو ما رد بعد
            if isAdminView && adminReply == nil {
                replyComposer
                    .background(
                        Rectangle()
                            .fill(DS.Color.background)
                            .ignoresSafeArea(edges: .bottom)
                    )
            }

            // Success toast
            if showSuccessToast {
                successToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .navigationTitle(L10n.t("المحادثة", "Conversation"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var threadHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(subjectLine)
                .font(DS.Font.title3)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            HStack(spacing: DS.Spacing.xs) {
                if let cat = parsed.category, !cat.isEmpty {
                    categoryPill(cat)
                }
                statusPill
                Spacer()
                Text(dateFormatted(thread.createdAt))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.bottom, DS.Spacing.xs)
    }

    private func categoryPill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(DS.Font.scaled(10))
            Text(text)
                .font(DS.Font.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(DS.Color.info)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(DS.Color.info.opacity(0.12)))
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(DS.Font.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(status.color)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(status.color.opacity(0.12)))
    }

    // MARK: - Message cards

    private var memberMessageCard: some View {
        MessageCard(
            authorIcon: "person.fill",
            authorColor: DS.Color.primary,
            authorName: isAdminView ? memberName : L10n.t("أنت", "You"),
            timestamp: thread.createdAt,
            text: parsed.message?.replacingOccurrences(of: "الموضوع:[^\n]*\n+", with: "", options: .regularExpression) ?? thread.details ?? "",
            tint: nil
        )
    }

    private func adminReplyCard(_ reply: String) -> some View {
        MessageCard(
            authorIcon: "shield.lefthalf.filled",
            authorColor: DS.Color.success,
            authorName: L10n.t("الإدارة", "Admin"),
            timestamp: thread.repliedAt,
            text: reply,
            tint: DS.Color.success
        )
    }

    private var awaitingReplyCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "clock.fill")
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("بانتظار رد الإدارة", "Awaiting admin reply"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("سنرد عليك في أقرب وقت", "We'll reply soon"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.warning.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Reply Composer (Admin)

    private var replyComposer: some View {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty && !isSending && trimmed.count <= 2000

        return VStack(spacing: DS.Spacing.sm) {
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                TextField(
                    L10n.t("اكتب ردك…", "Write your reply…"),
                    text: $replyText,
                    axis: .vertical
                )
                .font(DS.Font.body)
                .focused($isReplyFocused)
                .lineLimit(1...5)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(DS.Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(isReplyFocused ? DS.Color.primary.opacity(0.5) : DS.Color.surface, lineWidth: 1)
                )

                Button {
                    Task { await sendReply() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(canSend ? DS.Color.gradientPrimary : LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 42, height: 42)
                        if isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(DS.Font.scaled(15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(!canSend)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)

            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(DS.Font.caption2)
                Text(L10n.t(
                    "ردك يوصل العضو عبر الإشعار\((thread.member?.email ?? "").isEmpty ? "" : " + إيميل")",
                    "Reply via notification\((thread.member?.email ?? "").isEmpty ? "" : " + email")"
                ))
                .font(DS.Font.caption2)
                Spacer()
                Text("\(trimmed.count)/2000")
                    .font(DS.Font.caption2)
                    .foregroundColor(trimmed.count > 2000 ? DS.Color.error : DS.Color.textTertiary)
            }
            .foregroundColor(DS.Color.textTertiary)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)
        }
    }

    private var successToast: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DS.Color.success)
            Text(L10n.t("تم إرسال الرد", "Reply sent"))
                .font(DS.Font.callout)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.full)
                .fill(DS.Color.surfaceElevated)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .padding(.top, DS.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Actions

    private func sendReply() async {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return }
        isSending = true
        defer { isSending = false }
        let ok = await adminRequestVM.replyToContactMessage(thread, replyText: trimmed)
        if ok {
            replyText = ""
            isReplyFocused = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(DS.Anim.snappy) { showSuccessToast = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(DS.Anim.medium) { showSuccessToast = false }
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }

    // MARK: - Date

    private func dateFormatted(_ iso: String?) -> String {
        guard let iso = iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let d = date else { return "" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: d)
    }
}

// MARK: - Thread Status

enum ThreadStatus {
    case open       // ما رد بعد
    case replied    // الإدارة ردّت

    var label: String {
        switch self {
        case .open: return L10n.t("بانتظار رد", "Awaiting Reply")
        case .replied: return L10n.t("تم الرد", "Replied")
        }
    }

    var color: Color {
        switch self {
        case .open: return DS.Color.warning
        case .replied: return DS.Color.success
        }
    }
}

// MARK: - Message Card (Reusable)

private struct MessageCard: View {
    let authorIcon: String
    let authorColor: Color
    let authorName: String
    let timestamp: String?
    let text: String
    /// لون tint اختياري لإطار البطاقة (لتمييز رد الإدارة مثلاً)
    let tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(authorColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: authorIcon)
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(authorColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(authorName)
                        .font(DS.Font.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)
                    if let ts = timestamp {
                        Text(formatted(ts))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                Spacer()
            }

            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(tint != nil ? tint!.opacity(0.06) : DS.Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(tint != nil ? tint!.opacity(0.25) : DS.Color.surface, lineWidth: 1)
        )
    }

    private func formatted(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let d = date else { return "" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: d)
    }
}
