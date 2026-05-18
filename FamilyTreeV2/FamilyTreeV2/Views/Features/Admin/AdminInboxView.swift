import SwiftUI

/// قائمة محادثات الإدارة — مجموعة حسب العضو (مثل WhatsApp/iMessage).
/// كل صف = محادثة مع عضو واحد. الضغط يفتح AdminChatView.
struct AdminInboxView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    @State private var searchText: String = ""
    @State private var isLoading = false

    /// تجميع admin_requests حسب member_id إلى محادثات.
    private var conversations: [Conversation] {
        let groups = Dictionary(grouping: adminRequestVM.contactMessages, by: { $0.memberId })
        let convs: [Conversation] = groups.compactMap { (memberId, rows) in
            guard let any = rows.first else { return nil }
            let sorted = rows.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            let latestRow = sorted.first!
            let unreadCount = rows.filter { $0.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }.count
            return Conversation(
                memberId: memberId,
                memberName: any.member?.fullName ?? L10n.t("عضو", "Member"),
                memberFourPart: any.member?.fourPartName ?? any.member?.fullName ?? "—",
                lastMessagePreview: lastPreview(of: latestRow),
                lastMessageDate: AdminRequest.parseDate(latestRow.repliedAt ?? latestRow.createdAt),
                unreadCount: unreadCount
            )
        }
        let sorted = convs.sorted { ($0.lastMessageDate ?? Date.distantPast) > ($1.lastMessageDate ?? Date.distantPast) }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.memberName.lowercased().contains(q) || $0.lastMessagePreview.lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                if isLoading && adminRequestVM.contactMessages.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if conversations.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(conversations) { conv in
                                NavigationLink {
                                    AdminChatView(memberId: conv.memberId)
                                } label: {
                                    conversationRow(conv)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 72)
                            }
                        }
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                    .refreshable {
                        await adminRequestVM.fetchContactMessages(force: true)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("الرسائل", "Messages"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            await adminRequestVM.fetchContactMessages()
            isLoading = false
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textTertiary)
            TextField(L10n.t("ابحث…", "Search…"), text: $searchText)
                .font(DS.Font.callout)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surface)
        )
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(DS.Color.primary)
            }
            VStack(spacing: 6) {
                Text(searchText.isEmpty
                     ? L10n.t("ما فيه محادثات بعد", "No conversations yet")
                     : L10n.t("لا توجد نتائج", "No results"))
                    .font(DS.Font.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(searchText.isEmpty
                     ? L10n.t("لما يرسل عضو رسالة بتشوفها هنا", "Member messages will appear here")
                     : L10n.t("جرّب كلمة بحث مختلفة", "Try a different search"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .padding(DS.Spacing.xxxl)
    }

    // MARK: - Row

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(String(conv.memberName.prefix(1)))
                    .font(DS.Font.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(conv.memberFourPart)
                        .font(conv.unreadCount > 0 ? DS.Font.calloutBold : DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let d = conv.lastMessageDate {
                        Text(timeAgo(d))
                            .font(DS.Font.caption2)
                            .foregroundColor(conv.unreadCount > 0 ? DS.Color.primary : DS.Color.textTertiary)
                            .fontWeight(conv.unreadCount > 0 ? .semibold : .regular)
                    }
                }

                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    Text(conv.lastMessagePreview)
                        .font(DS.Font.subheadline)
                        .foregroundColor(conv.unreadCount > 0 ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if conv.unreadCount > 0 {
                        Text("\(conv.unreadCount)")
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(DS.Color.primary))
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func lastPreview(of row: AdminRequest) -> String {
        if let reply = row.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            return L10n.t("أنت: ", "You: ") + reply
        }
        let parsed = ContactMessageParser.parse(row)
        let text = parsed.message ?? row.details ?? ""
        return text
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("الموضوع:") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func timeAgo(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return L10n.t("الآن", "Now") }
        if secs < 3600 { return L10n.t("\(secs/60) د", "\(secs/60)m") }
        if secs < 86400 { return L10n.t("\(secs/3600) س", "\(secs/3600)h") }
        if secs < 604800 { return L10n.t("\(secs/86400) ي", "\(secs/86400)d") }
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: d)
    }
}

// MARK: - Conversation Model

private struct Conversation: Identifiable {
    let memberId: UUID
    let memberName: String
    let memberFourPart: String
    let lastMessagePreview: String
    let lastMessageDate: Date?
    let unreadCount: Int
    var id: UUID { memberId }
}
