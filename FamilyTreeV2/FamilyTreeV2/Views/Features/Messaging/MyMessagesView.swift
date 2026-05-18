import SwiftUI

/// "مراسلاتي" — صندوق العضو لكل محادثاته مع الإدارة.
/// قائمة email-style + FAB لرسالة جديدة.
struct MyMessagesView: View {
    @EnvironmentObject var authVM: AuthViewModel

    enum Filter: String, CaseIterable, Identifiable {
        case all, awaiting, replied
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .awaiting: return L10n.t("بانتظار رد", "Awaiting")
            case .replied: return L10n.t("تم الرد", "Replied")
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var isLoading = false
    @State private var showCompose = false

    private var threads: [AdminRequest] {
        switch filter {
        case .all: return authVM.myContactMessages
        case .awaiting: return authVM.myContactMessages.filter { $0.adminReply?.isEmpty ?? true }
        case .replied: return authVM.myContactMessages.filter { !($0.adminReply?.isEmpty ?? true) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                if isLoading && authVM.myContactMessages.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if threads.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(threads) { thread in
                                NavigationLink {
                                    MessageThreadView(thread: thread, isAdminView: false)
                                } label: {
                                    threadRow(thread)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, 100)  // مساحة للـ FAB
                    }
                    .refreshable {
                        await authVM.fetchMyContactMessages(force: true)
                    }
                }
            }

            // FAB لرسالة جديدة
            composeFAB
                .padding(.trailing, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
        }
        .navigationTitle(L10n.t("مراسلاتي", "My Messages"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCompose) {
            ComposeMessageSheet()
        }
        .task {
            isLoading = true
            await authVM.fetchMyContactMessages()
            isLoading = false
            authVM.markAdminRepliesSeen()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(Filter.allCases) { f in
                Button {
                    withAnimation(DS.Anim.snappy) { filter = f }
                } label: {
                    Text(f.label)
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, 7)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: filter == .all ? "envelope" : "tray")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(DS.Color.primary)
            }
            VStack(spacing: 6) {
                Text(emptyTitle)
                    .font(DS.Font.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(emptySubtitle)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if filter == .all {
                Button {
                    showCompose = true
                } label: {
                    Label(L10n.t("ابدأ محادثة جديدة", "Start New Message"), systemImage: "plus.circle.fill")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.vertical, DS.Spacing.md)
                        .background(
                            Capsule().fill(DS.Color.gradientPrimary)
                        )
                        .shadow(color: DS.Color.primary.opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(DSScaleButtonStyle())
                .padding(.top, DS.Spacing.sm)
            }
        }
        .padding(DS.Spacing.xxxl)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return L10n.t("ما عندك مراسلات بعد", "No messages yet")
        case .awaiting: return L10n.t("ما عندك رسائل بانتظار رد", "No awaiting replies")
        case .replied: return L10n.t("ما عندك ردود من الإدارة", "No admin replies yet")
        }
    }

    private var emptySubtitle: String {
        switch filter {
        case .all: return L10n.t("تواصل مع الإدارة بسؤال أو اقتراح", "Reach out to admin with a question or suggestion")
        case .awaiting: return L10n.t("كل رسائلك ردّت الإدارة عليها", "All messages have been replied to")
        case .replied: return L10n.t("الردود رح تظهر هنا لما تجي", "Replies will appear here")
        }
    }

    // MARK: - Thread Row

    private func threadRow(_ thread: AdminRequest) -> some View {
        let parsed = ContactMessageParser.parse(thread)
        let hasReply = !(thread.adminReply?.isEmpty ?? true)
        let isUnread = hasReply && (thread.repliedAt ?? "") > (UserDefaults.standard.string(forKey: "lastSeenAdminRepliesAt") ?? "")

        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // Status indicator
            Circle()
                .fill(hasReply ? (isUnread ? DS.Color.info : DS.Color.success) : DS.Color.warning)
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(subjectFor(thread, parsed: parsed))
                        .font(isUnread ? DS.Font.calloutBold : DS.Font.callout)
                        .fontWeight(isUnread ? .bold : .semibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeAgo(hasReply ? thread.repliedAt : thread.createdAt))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }

                // Preview line
                Text(previewFor(thread, hasReply: hasReply))
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Meta row: category badge + status text
                HStack(spacing: DS.Spacing.xs) {
                    if let cat = parsed.category, !cat.isEmpty {
                        Text(cat)
                            .font(DS.Font.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(DS.Color.info.opacity(0.12)))
                            .foregroundColor(DS.Color.info)
                    }
                    Text(hasReply
                         ? (isUnread ? L10n.t("رد جديد", "New reply") : L10n.t("تم الرد", "Replied"))
                         : L10n.t("بانتظار رد", "Awaiting reply"))
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(hasReply ? (isUnread ? DS.Color.info : DS.Color.success) : DS.Color.warning)
                    Spacer()
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(isUnread ? DS.Color.info.opacity(0.4) : DS.Color.surface, lineWidth: isUnread ? 1.2 : 0.5)
        )
    }

    // MARK: - FAB

    private var composeFAB: some View {
        Button {
            showCompose = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(DS.Font.scaled(15, weight: .bold))
                Text(L10n.t("رسالة جديدة", "New"))
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                Capsule()
                    .fill(DS.Color.gradientPrimary)
            )
            .shadow(color: DS.Color.primary.opacity(0.35), radius: 10, y: 5)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Helpers

    private func subjectFor(_ t: AdminRequest, parsed: ContactMessageParser.Parsed) -> String {
        let body = parsed.message ?? t.details ?? ""
        for line in body.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("الموضوع:") {
                let stripped = s.replacingOccurrences(of: "الموضوع:", with: "").trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { return stripped }
            }
        }
        return parsed.category ?? L10n.t("بدون عنوان", "Untitled")
    }

    private func previewFor(_ t: AdminRequest, hasReply: Bool) -> String {
        if hasReply, let reply = t.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            return reply
        }
        let body = ContactMessageParser.parse(t).message ?? t.details ?? ""
        // Strip "الموضوع:" line
        let lines = body.split(separator: "\n")
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("الموضوع:") }
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
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
        if secs < 3600 { return L10n.t("\(secs/60)د", "\(secs/60)m") }
        if secs < 86400 { return L10n.t("\(secs/3600)س", "\(secs/3600)h") }
        return L10n.t("\(secs/86400)ي", "\(secs/86400)d")
    }
}
