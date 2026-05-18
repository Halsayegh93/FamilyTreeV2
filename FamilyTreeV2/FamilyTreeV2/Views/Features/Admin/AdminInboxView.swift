import SwiftUI

/// "صندوق التواصل" — للإدارة: عرض كل رسائل الأعضاء بنمط email/threads.
/// يستخدم MessageThreadView نفسه (مع isAdminView=true) لعرض التفاصيل والرد.
struct AdminInboxView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    enum Filter: String, CaseIterable, Identifiable {
        case awaiting, all, replied
        var id: String { rawValue }
        var label: String {
            switch self {
            case .awaiting: return L10n.t("بانتظار", "Awaiting")
            case .all: return L10n.t("الكل", "All")
            case .replied: return L10n.t("تم الرد", "Replied")
            }
        }
    }

    @State private var filter: Filter = .awaiting
    @State private var searchText: String = ""
    @State private var isLoading = false

    private var threads: [AdminRequest] {
        let base: [AdminRequest] = {
            switch filter {
            case .all: return adminRequestVM.contactMessages
            case .awaiting: return adminRequestVM.contactMessages.filter { $0.adminReply?.isEmpty ?? true }
            case .replied: return adminRequestVM.contactMessages.filter { !($0.adminReply?.isEmpty ?? true) }
            }
        }()
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { thread in
            let parsed = ContactMessageParser.parse(thread)
            let memberName = thread.member?.fullName.lowercased() ?? ""
            let body = (parsed.message ?? thread.details ?? "").lowercased()
            let cat = (parsed.category ?? "").lowercased()
            return memberName.contains(q) || body.contains(q) || cat.contains(q)
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchAndFilter
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                if isLoading && adminRequestVM.contactMessages.isEmpty {
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
                                    MessageThreadView(thread: thread, isAdminView: true)
                                } label: {
                                    threadRow(thread)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                    .refreshable {
                        await adminRequestVM.fetchContactMessages(force: true)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("صندوق التواصل", "Contact Inbox"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            await adminRequestVM.fetchContactMessages()
            isLoading = false
        }
    }

    // MARK: - Search + Filter

    private var searchAndFilter: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textTertiary)
                TextField(L10n.t("ابحث في الرسائل…", "Search messages…"), text: $searchText)
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

            HStack(spacing: DS.Spacing.xs) {
                ForEach(Filter.allCases) { f in
                    Button {
                        withAnimation(DS.Anim.snappy) { filter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Text(f.label)
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                            if f == .awaiting, adminRequestVM.unreadContactMessagesCount > 0 {
                                Text("\(adminRequestVM.unreadContactMessagesCount)")
                                    .font(DS.Font.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(DS.Color.error))
                            }
                        }
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: filter == .awaiting ? "tray" : "envelope.open")
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
        }
        .padding(DS.Spacing.xxxl)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return L10n.t("لا توجد نتائج", "No results") }
        switch filter {
        case .awaiting: return L10n.t("الصندوق فاضي 🎉", "Inbox clear 🎉")
        case .all: return L10n.t("ما فيه رسائل بعد", "No messages yet")
        case .replied: return L10n.t("ما فيه رسائل مرّدت", "No replied messages")
        }
    }

    private var emptySubtitle: String {
        if !searchText.isEmpty { return L10n.t("جرّب كلمة بحث مختلفة", "Try a different search term") }
        switch filter {
        case .awaiting: return L10n.t("كل الرسائل ردّيت عليها — شغل ممتاز", "All messages replied — great work")
        case .all: return L10n.t("لما يرسل عضو رسالة بتشوفها هنا", "Member messages will appear here")
        case .replied: return L10n.t("الرسائل المردّ عليها بتظهر هنا", "Replied messages appear here")
        }
    }

    // MARK: - Row

    private func threadRow(_ thread: AdminRequest) -> some View {
        let parsed = ContactMessageParser.parse(thread)
        let hasReply = !(thread.adminReply?.isEmpty ?? true)
        let senderName = thread.member?.fourPartName ?? thread.member?.fullName ?? L10n.t("عضو", "Member")

        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // Status indicator
            Circle()
                .fill(hasReply ? DS.Color.success : DS.Color.warning)
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(senderName)
                        .font(hasReply ? DS.Font.callout : DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeAgo(thread.createdAt))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                }

                Text(subjectFor(thread, parsed: parsed))
                    .font(DS.Font.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                Text(previewFor(thread, parsed: parsed))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

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
                         ? L10n.t("تم الرد", "Replied")
                         : L10n.t("بانتظار", "Awaiting"))
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(hasReply ? DS.Color.success : DS.Color.warning)
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
                .stroke(!hasReply ? DS.Color.warning.opacity(0.35) : DS.Color.surface, lineWidth: !hasReply ? 1.2 : 0.5)
        )
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

    private func previewFor(_ t: AdminRequest, parsed: ContactMessageParser.Parsed) -> String {
        let body = parsed.message ?? t.details ?? ""
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
