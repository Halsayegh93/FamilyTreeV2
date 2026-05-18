import SwiftUI

/// شاشة "ردود الإدارة" — للعضو نفسه يشوف رسائله المرسلة سابقاً وردود الإدارة عليها.
struct MyContactRepliesView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var selectedThread: AdminRequest? = nil

    enum Filter: String, CaseIterable, Identifiable {
        case all, replied, pending
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .replied: return L10n.t("ردّت الإدارة", "Replied")
            case .pending: return L10n.t("بانتظار رد", "Awaiting")
            }
        }
    }

    @State private var filter: Filter = .all

    var filtered: [AdminRequest] {
        switch filter {
        case .all: return authVM.myContactMessages
        case .replied: return authVM.myContactMessages.filter { !($0.adminReply?.isEmpty ?? true) }
        case .pending: return authVM.myContactMessages.filter { $0.adminReply?.isEmpty ?? true }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.sm)

                if isLoading && authVM.myContactMessages.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(filtered) { msg in
                                Button {
                                    selectedThread = msg
                                } label: {
                                    threadRow(msg)
                                }
                                .buttonStyle(DSScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                    .refreshable {
                        await authVM.fetchMyContactMessages(force: true)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("ردود الإدارة", "Admin Replies"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedThread) { thread in
            MyContactReplyDetailSheet(message: thread)
        }
        .task {
            isLoading = true
            await authVM.fetchMyContactMessages()
            isLoading = false
            authVM.markAdminRepliesSeen()
        }
    }

    private var filterBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(Filter.allCases) { f in
                Button {
                    withAnimation(DS.Anim.snappy) { filter = f }
                } label: {
                    Text(f.label)
                        .font(DS.Font.calloutBold)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            Capsule()
                                .fill(filter == f ? DS.Color.primary : DS.Color.surface)
                        )
                        .foregroundColor(filter == f ? .white : DS.Color.textSecondary)
                }
                .buttonStyle(DSScaleButtonStyle())
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(emptyText)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.xxxl)
    }

    private var emptyText: String {
        switch filter {
        case .all: return L10n.t("ما أرسلت أي رسالة بعد", "You haven't sent any messages yet")
        case .replied: return L10n.t("ما عندك ردود من الإدارة", "No replies from admin yet")
        case .pending: return L10n.t("كل رسائلك ردّت الإدارة عليها", "All your messages have been replied to")
        }
    }

    private func threadRow(_ msg: AdminRequest) -> some View {
        let hasReply = !(msg.adminReply?.isEmpty ?? true)
        let parsed = ContactMessageParser.parse(msg)

        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(hasReply ? DS.Color.success.opacity(0.15) : DS.Color.warning.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: hasReply ? "envelope.open.fill" : "envelope.fill")
                    .font(DS.Font.callout)
                    .foregroundColor(hasReply ? DS.Color.success : DS.Color.warning)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DS.Spacing.xs) {
                    if let cat = parsed.category, !cat.isEmpty {
                        Text(cat)
                            .font(DS.Font.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Color.info.opacity(0.15)))
                            .foregroundColor(DS.Color.info)
                    }
                    Text(hasReply
                         ? L10n.t("رد من الإدارة", "Admin Replied")
                         : L10n.t("بانتظار رد", "Awaiting Reply"))
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(hasReply ? DS.Color.success : DS.Color.warning)
                    Spacer()
                }

                if hasReply, let reply = msg.adminReply {
                    Text(reply)
                        .font(DS.Font.subheadline)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(parsed.message ?? msg.details ?? "")
                        .font(DS.Font.subheadline)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(timeAgo(hasReply ? msg.repliedAt : msg.createdAt))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(hasReply ? DS.Color.success.opacity(0.3) : DS.Color.surface, lineWidth: 1)
        )
    }

    private func timeAgo(_ iso: String?) -> String {
        guard let iso = iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let d = date else { return "" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return L10n.t("الآن", "Now") }
        if secs < 3600 { return L10n.t("منذ \(secs/60) دقيقة", "\(secs/60)m ago") }
        if secs < 86400 { return L10n.t("منذ \(secs/3600) ساعة", "\(secs/3600)h ago") }
        return L10n.t("منذ \(secs/86400) يوم", "\(secs/86400)d ago")
    }
}

// MARK: - Detail Sheet (Thread)

struct MyContactReplyDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: AdminRequest

    var parsed: ContactMessageParser.Parsed {
        ContactMessageParser.parse(message)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // رسالتي الأصلية
                    myMessageBubble

                    // رد الإدارة (إن وُجد)
                    if let reply = message.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !reply.isEmpty {
                        adminReplyBubble(reply)
                    } else {
                        awaitingBubble
                    }

                    Spacer(minLength: DS.Spacing.lg)
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("المحادثة", "Conversation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
    }

    private var myMessageBubble: some View {
        VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Spacer()
                if let cat = parsed.category, !cat.isEmpty {
                    Text(cat)
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.Color.info.opacity(0.15)))
                        .foregroundColor(DS.Color.info)
                }
                Text(L10n.t("رسالتي", "My message"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Image(systemName: "person.fill")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Text(parsed.message ?? message.details ?? "")
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(DS.Color.surfaceElevated)
                )

            Text(dateFormatted(message.createdAt))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func adminReplyBubble(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.success)
                Text(L10n.t("الإدارة", "Admin"))
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.success)
                Spacer()
            }

            Text(reply)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(DS.Color.success.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.success.opacity(0.3), lineWidth: 1)
                )

            Text(dateFormatted(message.repliedAt))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
        }
    }

    private var awaitingBubble: some View {
        HStack(spacing: DS.Spacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(L10n.t(
                "رسالتك مع الإدارة — بنرد عليك قريباً",
                "Your message is with the admin — we'll reply soon"
            ))
            .font(DS.Font.subheadline)
            .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.warning.opacity(0.08))
        )
    }

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
