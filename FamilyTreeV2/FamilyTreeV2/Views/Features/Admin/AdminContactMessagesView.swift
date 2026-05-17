import SwiftUI

struct AdminContactMessagesView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    enum Filter: String, CaseIterable, Identifiable {
        case all, unread, handled
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .unread: return L10n.t("غير مُعالَجة", "Unread")
            case .handled: return L10n.t("مُعالَجة", "Handled")
            }
        }
    }

    @State private var filter: Filter = .unread
    @State private var selectedMessage: AdminRequest? = nil
    @State private var isLoading = false

    var filteredMessages: [AdminRequest] {
        switch filter {
        case .all: return adminRequestVM.contactMessages
        case .unread: return adminRequestVM.contactMessages.filter { $0.status == ApprovalStatus.pending.rawValue }
        case .handled: return adminRequestVM.contactMessages.filter { $0.status != ApprovalStatus.pending.rawValue }
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

                if isLoading && adminRequestVM.contactMessages.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredMessages.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(filteredMessages) { msg in
                                Button {
                                    selectedMessage = msg
                                } label: {
                                    messageRow(msg)
                                }
                                .buttonStyle(DSScaleButtonStyle())
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
        .navigationTitle(L10n.t("رسائل التواصل", "Contact Messages"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMessage) { msg in
            AdminContactMessageDetailSheet(message: msg)
                .environmentObject(adminRequestVM)
        }
        .task {
            isLoading = true
            await adminRequestVM.fetchContactMessages(force: false)
            isLoading = false
        }
    }

    private var filterBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(Filter.allCases) { f in
                Button {
                    withAnimation(DS.Anim.snappy) { filter = f }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(f.label)
                            .font(DS.Font.calloutBold)
                        if f == .unread && adminRequestVM.unreadContactMessagesCount > 0 {
                            Text("\(adminRequestVM.unreadContactMessagesCount)")
                                .font(DS.Font.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DS.Color.error))
                        }
                    }
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
            Text(emptyStateText)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.xxxl)
    }

    private var emptyStateText: String {
        switch filter {
        case .all: return L10n.t("لا توجد رسائل تواصل", "No contact messages yet")
        case .unread: return L10n.t("لا توجد رسائل غير مُعالَجة", "No unread messages")
        case .handled: return L10n.t("لا توجد رسائل مُعالَجة", "No handled messages yet")
        }
    }

    private func messageRow(_ msg: AdminRequest) -> some View {
        let parsed = ContactMessageParser.parse(msg)
        let isUnread = msg.status == ApprovalStatus.pending.rawValue
        let senderName = msg.member?.fourPartName ?? L10n.t("عضو", "Member")

        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            // Avatar / initial
            ZStack {
                Circle()
                    .fill(isUnread ? DS.Color.primary.opacity(0.15) : DS.Color.surface)
                    .frame(width: 44, height: 44)
                Text(String(senderName.prefix(1)))
                    .font(DS.Font.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(isUnread ? DS.Color.primary : DS.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(senderName)
                        .font(isUnread ? DS.Font.calloutBold : DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    if let category = parsed.category, !category.isEmpty {
                        Text(category)
                            .font(DS.Font.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DS.Color.info.opacity(0.15))
                            )
                            .foregroundColor(DS.Color.info)
                    }

                    Spacer()

                    if isUnread {
                        Circle()
                            .fill(DS.Color.primary)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(parsed.message ?? msg.details ?? "")
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(timeAgo(msg.createdAt))
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
                .stroke(DS.Color.surface, lineWidth: 0.5)
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

// MARK: - Parser

enum ContactMessageParser {
    struct Parsed {
        var category: String?
        var message: String?
        var preferredContact: String?
    }

    /// يستخرج الحقول من details المكوّن نصياً:
    ///   التصنيف: ...
    ///   الرسالة: ...
    ///   وسيلة التواصل: ...
    /// يستفيد من new_value كقيمة category مفضّلة (مخزّنة مستقلاً).
    static func parse(_ msg: AdminRequest) -> Parsed {
        var p = Parsed()
        p.category = msg.newValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let details = msg.details else { return p }
        let lines = details.split(separator: "\n").map { String($0) }
        for line in lines {
            if line.hasPrefix("التصنيف:") {
                if p.category == nil || p.category?.isEmpty == true {
                    p.category = line.replacingOccurrences(of: "التصنيف:", with: "").trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasPrefix("الرسالة:") {
                p.message = line.replacingOccurrences(of: "الرسالة:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("وسيلة التواصل:") {
                p.preferredContact = line.replacingOccurrences(of: "وسيلة التواصل:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return p
    }
}
