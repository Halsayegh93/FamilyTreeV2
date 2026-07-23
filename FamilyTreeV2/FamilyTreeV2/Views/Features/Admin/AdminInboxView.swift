import SwiftUI
import Supabase

/// قائمة رسائل التواصل من الأعضاء — نموذج بسيط (لا دردشة).
/// كل صف = رسالة واحدة. الضغط يفتح تفاصيلها مع خيارات الرد بالاتصال/واتساب.
struct AdminInboxView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var selectedMessage: AdminRequest? = nil
    @State private var filter: InboxFilter = .pending
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    private enum InboxFilter: String, CaseIterable {
        case pending, handled
        var title: String {
            switch self {
            case .pending: return L10n.t("لم يتم التعامل", "Pending")
            case .handled: return L10n.t("تم التعامل", "Handled")
            }
        }
    }

    private var filteredMessages: [AdminRequest] {
        let all = adminRequestVM.contactMessages
        let byStatus: [AdminRequest]
        switch filter {
        case .pending: byStatus = all.filter { $0.status == ApprovalStatus.pending.rawValue }
        case .handled: byStatus = all.filter { $0.status == ApprovalStatus.approved.rawValue }
        }
        let sorted = byStatus.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { msg in
            let name = msg.member?.fullName.lowercased() ?? ""
            let preview = ContactParser.message(from: msg).lowercased()
            return name.contains(q) || preview.contains(q)
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)

                searchBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                if isLoading && adminRequestVM.contactMessages.isEmpty {
                    Spacer()
                    ProgressView().tint(DS.Color.primary)
                    Spacer()
                } else if filteredMessages.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    if adminRequestVM.unreadContactMessagesCount > 0 {
                        markAllReadBar
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.sm)
                    }

                    ScrollView {
                        AdaptiveLazyStack(spacing: DS.Spacing.sm, landscapeMinimum: 340) {
                            ForEach(filteredMessages) { msg in
                                Button {
                                    if isSelectMode {
                                        toggleSelection(msg.id)
                                    } else {
                                        adminRequestVM.markContactMessageRead(msg.id)
                                        selectedMessage = msg
                                    }
                                } label: {
                                    HStack(spacing: DS.Spacing.sm) {
                                        if isSelectMode {
                                            Image(systemName: selectedIDs.contains(msg.id) ? "checkmark.circle.fill" : "circle")
                                                .font(DS.Font.scaled(20, weight: .semibold))
                                                .foregroundColor(selectedIDs.contains(msg.id) ? DS.Color.primary : DS.Color.textTertiary)
                                        }
                                        messageRow(msg)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                    .refreshable { await adminRequestVM.fetchContactMessages(force: true) }
                }
            }

            // شريط الحذف السفلي في وضع التحديد
            if isSelectMode {
                VStack {
                    Spacer()
                    deleteBar
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !filteredMessages.isEmpty {
                    Button(isSelectMode ? L10n.t("تم", "Done") : L10n.t("تحديد", "Select")) {
                        withAnimation(DS.Anim.quick) {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedIDs.removeAll() }
                        }
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                }
            }
        }
        .alert(L10n.t("حذف الرسائل", "Delete Messages"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await deleteSelected() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد حذف \(selectedIDs.count) رسالة؟ لا يمكن التراجع.",
                        "Delete \(selectedIDs.count) message(s)? This can't be undone."))
        }
        .navigationTitle(L10n.t("رسائل التواصل", "Contact Messages"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            await adminRequestVM.fetchContactMessages()
            isLoading = false
        }
        .sheet(item: $selectedMessage) { msg in
            NavigationStack {
                MessageDetailSheet(message: msg) {
                    selectedMessage = nil
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Spacer(minLength: 0)
            ForEach(InboxFilter.allCases, id: \.self) { f in
                let selected = filter == f
                let count = f == .pending
                    ? adminRequestVM.contactMessages.filter { $0.status == ApprovalStatus.pending.rawValue }.count
                    : adminRequestVM.contactMessages.filter { $0.status == ApprovalStatus.approved.rawValue }.count
                Button {
                    withAnimation(DS.Anim.quick) { filter = f }
                } label: {
                    HStack(spacing: 5) {
                        Text(f.title)
                            .font(DS.Font.scaled(13, weight: selected ? .bold : .semibold))
                            .lineLimit(1)
                        if count > 0 {
                            Text("\(count)")
                                .font(DS.Font.scaled(9, weight: .black))
                                .foregroundColor(selected ? .white : .white)
                                .frame(minWidth: 16, minHeight: 16)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(selected ? Color.white.opacity(0.28) : DS.Color.primary))
                        }
                    }
                    .foregroundColor(selected ? .white : DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if selected {
                                Capsule(style: .continuous).fill(DS.Color.gradientPrimary)
                            } else {
                                Capsule(style: .continuous).fill(DS.Color.primary.opacity(0.10))
                            }
                        }
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(selected ? Color.white.opacity(0.20) : DS.Color.primary.opacity(0.22), lineWidth: selected ? 0.5 : 1)
                    )
                    .shadow(color: selected ? DS.Color.primary.opacity(0.35) : .clear, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Select / Delete

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func deleteSelected() async {
        isDeleting = true
        await adminRequestVM.deleteContactMessages(ids: Array(selectedIDs))
        selectedIDs.removeAll()
        isDeleting = false
        withAnimation(DS.Anim.quick) { isSelectMode = false }
    }

    private var deleteBar: some View {
        HStack(spacing: DS.Spacing.md) {
            Text(L10n.t("\(selectedIDs.count) محدّدة", "\(selectedIDs.count) selected"))
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textSecondary)
            Spacer()
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 5) {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "trash.fill").font(DS.Font.scaled(13, weight: .bold))
                    }
                    Text(L10n.t("حذف", "Delete")).font(DS.Font.scaled(14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, 12)
                .background(Capsule().fill(DS.Color.error))
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty || isDeleting)
            .opacity(selectedIDs.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
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
                Image(systemName: "tray")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(DS.Color.primary)
            }
            VStack(spacing: 6) {
                Text(L10n.t("ما فيه رسائل", "No messages"))
                    .font(DS.Font.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(filter == .pending
                     ? L10n.t("كل الرسائل تم التعامل معها", "All messages handled")
                     : L10n.t("لا توجد رسائل متعامل معها بعد", "No handled messages yet"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .padding(DS.Spacing.xxxl)
    }

    // MARK: - Row

    private func messageRow(_ msg: AdminRequest) -> some View {
        let category = ContactParser.category(of: msg)
        let preview = ContactParser.message(from: msg)
        let date = ContactParser.date(msg.createdAt)
        let isPending = msg.status == ApprovalStatus.pending.rawValue
        let isUnread = !adminRequestVM.readContactMessageIds.contains(msg.id)

        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            // نقطة "غير مقروء" — تظهر فقط للرسائل اللي ما ضغط عليها المدير بعد
            ZStack {
                if isUnread {
                    Circle()
                        .fill(DS.Color.primary)
                        .frame(width: 9, height: 9)
                        .transition(.opacity)
                }
            }
            .frame(width: 9)
            .padding(.top, 6)
            .animation(DS.Anim.quick, value: isUnread)

            // الصف معكوس مثل شاشة التفاصيل: النص أولاً والصورة في الطرف المقابل
            VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    if let d = date {
                        Text(relativeShort(d))
                            .font(DS.Font.caption2)
                            .fontWeight(isUnread ? .bold : .regular)
                            .foregroundColor(isUnread ? DS.Color.primary : DS.Color.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text(msg.member?.fullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.calloutBold)
                        .fontWeight(isUnread ? .black : .bold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: DS.Spacing.xs) {
                    Spacer(minLength: 0)
                    if isPending {
                        Image(systemName: "clock.fill")
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.warning)
                    }
                    categoryChip(category)
                }

                Text(preview)
                    .font(DS.Font.subheadline)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            avatar(for: msg.member)
        }
        .padding(DS.Spacing.md)
        .background(isUnread ? DS.Color.primary.opacity(0.04) : DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(
                    isUnread
                        ? DS.Color.primary.opacity(0.25)
                        : (isPending ? DS.Color.warning.opacity(0.18) : Color.clear),
                    lineWidth: isUnread ? 1.2 : 1
                )
        )
    }

    // MARK: - Mark all read bar

    private var markAllReadBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "envelope.badge.fill")
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(DS.Color.primary)
            Text(L10n.t(
                "\(adminRequestVM.unreadContactMessagesCount) رسالة جديدة",
                "\(adminRequestVM.unreadContactMessagesCount) new messages"
            ))
            .font(DS.Font.caption1)
            .fontWeight(.semibold)
            .foregroundColor(DS.Color.textPrimary)
            Spacer()
            Button {
                withAnimation(DS.Anim.quick) {
                    adminRequestVM.markAllContactMessagesRead()
                }
            } label: {
                Text(L10n.t("تحديد الكل كمقروء", "Mark all read"))
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, 6)
                    .background(DS.Color.primary.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private func avatar(for member: FamilyMember?) -> some View {
        DSMemberAvatar(
            name: member?.firstName ?? "?",
            avatarUrl: member?.avatarUrl,
            size: 44,
            roleColor: member?.roleColor ?? DS.Color.primary
        )
    }

    private func categoryChip(_ raw: String) -> some View {
        let info = ContactCategoryInfo.from(raw: raw)
        return HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(DS.Font.scaled(9, weight: .bold))
            Text(info.title)
                .font(DS.Font.scaled(10, weight: .bold))
        }
        .foregroundColor(info.color)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 3)
        .background(info.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func relativeShort(_ d: Date) -> String {
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

// MARK: - Message Detail Sheet

private struct MessageDetailSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    let message: AdminRequest
    let onDismiss: () -> Void

    @State private var isMarking = false
    /// شيت كتابة الرد الرسمي (يُرسل من بريد العائلة)
    @State private var showEmailComposer = false

    var body: some View {
        let category = ContactParser.category(of: message)
        let body = ContactParser.message(from: message)
        let phone = message.member?.phoneNumber ?? ""

        ScrollView {
            VStack(alignment: .trailing, spacing: DS.Spacing.lg) {
                // Sender
                // صف المرسل معكوس: التصنيف أولاً · الاسم والهاتف في الوسط ·
                // الصورة في الطرف المقابل (طلب المالك)
                HStack(spacing: DS.Spacing.md) {
                    let info = ContactCategoryInfo.from(raw: category)
                    VStack(spacing: 2) {
                        Image(systemName: info.icon)
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(info.color)
                            .frame(width: 34, height: 34)
                            .background(info.color.opacity(0.14))
                            .clipShape(Circle())
                        Text(info.title)
                            .font(DS.Font.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(message.member?.fullName ?? L10n.t("عضو", "Member"))
                            .font(DS.Font.headline)
                            .foregroundColor(DS.Color.textPrimary)
                        if !phone.isEmpty {
                            Text(phone)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    DSMemberAvatar(
                        name: message.member?.firstName ?? "?",
                        avatarUrl: message.member?.avatarUrl,
                        size: 52,
                        roleColor: message.member?.roleColor ?? DS.Color.primary
                    )
                }

                Divider()

                // Message body
                VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                    Text(L10n.t("الرسالة", "Message"))
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(body)
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(DS.Spacing.md)
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                // Reply actions — الوسيلة التي طلبها العضو أوّلاً، ثم رقمه المسجّل
                let preferred = ContactParser.preferredContact(from: message)
                let isEmail = (preferred ?? "").contains("@")
                let replyPhone = isEmail ? phone : (preferred ?? phone)

                if isEmail || !replyPhone.isEmpty {
                    VStack(alignment: .trailing, spacing: DS.Spacing.sm) {
                        Text(L10n.t("الرد على العضو", "Reply to member"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        // وسيلة التواصل التي كتبها العضو — تُعرض وتُنسخ بالضغط
                        if let preferred {
                            Button {
                                UIPasteboard.general.string = preferred
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isEmail ? "envelope.fill" : "phone.fill")
                                        .font(DS.Font.scaled(11, weight: .semibold))
                                    Text(preferred)
                                        .font(DS.Font.caption1)
                                        .lineLimit(1)
                                        .environment(\.layoutDirection, .leftToRight)
                                    Image(systemName: "doc.on.doc")
                                        .font(DS.Font.scaled(9, weight: .semibold))
                                        .opacity(0.6)
                                }
                                .foregroundColor(DS.Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: DS.Spacing.sm) {
                            if !replyPhone.isEmpty {
                                replyButton(
                                    title: L10n.t("واتساب", "WhatsApp"),
                                    icon: "message.fill",
                                    color: Color(hex: "#25D366")
                                ) { openURL("https://wa.me/\(sanitize(replyPhone))") }
                                replyButton(
                                    title: L10n.t("اتصال", "Call"),
                                    icon: "phone.fill",
                                    color: DS.Color.success
                                ) { openURL("tel:\(sanitize(replyPhone))") }
                            }
                            if isEmail {
                                replyButton(
                                    title: L10n.t("إيميل", "Email"),
                                    icon: "envelope.fill",
                                    color: DS.Color.info
                                ) { showEmailComposer = true }
                            }
                        }
                    }
                }

                // Mark handled
                if message.status == ApprovalStatus.pending.rawValue {
                    Button {
                        Task { await markHandled() }
                    } label: {
                        HStack {
                            if isMarking {
                                ProgressView().tint(.white).scaleEffect(0.9)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(15, weight: .bold))
                            }
                            Text(isMarking ? L10n.t("جارٍ…", "Working…") : L10n.t("تم التعامل", "Mark as Handled"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md + 2)
                        .background(DS.Color.gradientPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }
                    .disabled(isMarking)
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(DS.Color.success)
                        Text(L10n.t("تم التعامل مع هذه الرسالة", "This message was handled"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.success.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                Spacer(minLength: DS.Spacing.lg)
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Color.background)
        .navigationTitle(L10n.t("تفاصيل الرسالة", "Message Detail"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // defensive: تأكد أن الرسالة معلّمة كمقروءة حتى لو فُتحت من مسار آخر
            adminRequestVM.markContactMessageRead(message.id)
        }
        .sheet(isPresented: $showEmailComposer) {
            OfficialReplySheet(
                to: ContactParser.preferredContact(from: message) ?? "",
                memberName: message.member?.fullName ?? "",
                category: ContactParser.category(of: message),
                originalMessage: ContactParser.message(from: message)
            )
        }
    }

    private func replyButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                Text(title)
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sanitize(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }

    private func openURL(_ str: String) {
        guard let url = URL(string: str) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func markHandled() async {
        isMarking = true
        adminRequestVM.markContactMessageRead(message.id)
        await adminRequestVM.markContactMessageHandled(message)
        isMarking = false
        onDismiss()
    }
}

// MARK: - Helpers

enum ContactParser {
    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// تحويل ISO string لـ Date (يدعم بكسر ثواني أو بدونها).
    static func date(_ str: String?) -> Date? {
        guard let s = str, !s.isEmpty else { return nil }
        return isoFull.date(from: s) ?? isoBasic.date(from: s)
    }

    /// التصنيف: من new_value مباشرة، fallback لتحليل details.
    static func category(of msg: AdminRequest) -> String {
        if let nv = msg.newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !nv.isEmpty {
            return nv
        }
        guard let details = msg.details else { return "—" }
        for line in details.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("التصنيف:") {
                return String(trimmed.dropFirst("التصنيف:".count)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.lowercased().hasPrefix("category:") {
                return String(trimmed.dropFirst("category:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "—"
    }

    /// وسيلة التواصل التي كتبها العضو للرد (إيميل أو رقم) — إن وُجدت.
    static func preferredContact(from msg: AdminRequest) -> String? {
        guard let details = msg.details else { return nil }
        for line in details.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("وسيلة التواصل:") {
                let v = String(t.dropFirst("وسيلة التواصل:".count)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            if t.lowercased().hasPrefix("preferred contact:") {
                let v = String(t.dropFirst("preferred contact:".count)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    /// نص الرسالة: من سطر "الرسالة:" أو "Message:" — fallback للنص الكامل.
    static func message(from msg: AdminRequest) -> String {
        guard let details = msg.details else { return "" }
        let lines = details.components(separatedBy: .newlines)
        var capturing = false
        var collected: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("الرسالة:") {
                capturing = true
                let rest = String(trimmed.dropFirst("الرسالة:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { collected.append(rest) }
                continue
            }
            if trimmed.lowercased().hasPrefix("message:") {
                capturing = true
                let rest = String(trimmed.dropFirst("message:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { collected.append(rest) }
                continue
            }
            if trimmed.hasPrefix("التصنيف:") || trimmed.lowercased().hasPrefix("category:") {
                continue
            }
            if trimmed.hasPrefix("وسيلة التواصل:") || trimmed.lowercased().hasPrefix("preferred contact:") {
                capturing = false
                continue
            }
            if capturing && !trimmed.isEmpty { collected.append(trimmed) }
        }
        if collected.isEmpty {
            return details
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("التصنيف:") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        return collected.joined(separator: "\n")
    }
}

/// عرض موحّد للتصنيف (لون/أيقونة/ترجمة) بناءً على نص خام من قاعدة البيانات.
struct ContactCategoryInfo {
    let title: String
    let icon: String
    let color: Color

    static func from(raw: String) -> ContactCategoryInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "شكوى", "complaint", "Complaint":
            return .init(title: L10n.t("شكوى", "Complaint"), icon: "exclamationmark.bubble.fill", color: DS.Color.error)
        case "اقتراح", "suggestion", "Suggestion":
            return .init(title: L10n.t("اقتراح", "Suggestion"), icon: "lightbulb.fill", color: DS.Color.success)
        case "استفسار", "inquiry", "Inquiry":
            return .init(title: L10n.t("استفسار", "Inquiry"), icon: "questionmark.bubble.fill", color: DS.Color.primary)
        case "أخرى", "other", "Other":
            return .init(title: L10n.t("أخرى", "Other"), icon: "ellipsis.message.fill", color: DS.Color.accent)
        default:
            return .init(title: trimmed.isEmpty ? "—" : trimmed, icon: "envelope.fill", color: DS.Color.textSecondary)
        }
    }
}


// MARK: - شيت الرد الرسمي (يُرسل من بريد العائلة عبر الخادم)

private struct OfficialReplySheet: View {
    let to: String
    let memberName: String
    let category: String
    let originalMessage: String

    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var didSend = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        // المستلم
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundColor(DS.Color.info)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memberName.isEmpty ? L10n.t("العضو", "Member") : memberName)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                                Text(to)
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            Spacer()
                        }
                        .padding(DS.Spacing.md)
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                        // نص الرد
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(L10n.t("نص الرد", "Reply"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            ZStack(alignment: .topLeading) {
                                if replyText.isEmpty {
                                    Text(L10n.t("اكتب ردّك هنا…", "Write your reply…"))
                                        .font(DS.Font.body)
                                        .foregroundColor(DS.Color.textTertiary)
                                        .padding(.horizontal, DS.Spacing.md)
                                        .padding(.vertical, DS.Spacing.md + 4)
                                }
                                TextEditor(text: $replyText)
                                    .focused($focused)
                                    .font(DS.Font.body)
                                    .scrollContentBackground(.hidden)
                                    .padding(DS.Spacing.sm)
                                    .frame(minHeight: 150, maxHeight: 240)
                            }
                            .background(DS.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        }

                        if let errorText {
                            Text(errorText)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.error)
                        }

                        DSPrimaryButton(didSend ? L10n.t("تم الإرسال", "Sent")
                                                : L10n.t("إرسال الرد", "Send reply"),
                                        icon: didSend ? "checkmark.circle.fill" : "paperplane.fill",
                                        isLoading: isSending) {
                            Task { await send() }
                        }
                        .disabled(isSending || didSend || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle(L10n.t("الرد بالإيميل", "Email reply"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
    }

    @MainActor
    private func send() async {
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            struct Payload: Encodable {
                let to: String, reply: String, member_name: String
                let original_message: String, category: String
            }
            _ = try await SupabaseConfig.client.functions.invoke(
                "admin-reply-email",
                options: .init(body: Payload(
                    to: to,
                    reply: replyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    member_name: memberName,
                    original_message: originalMessage,
                    category: category
                ))
            )
            didSend = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            Log.error("[AdminReply] فشل إرسال الرد: \(error.localizedDescription)")
            errorText = L10n.t("تعذّر إرسال الرد. حاول مرة أخرى.", "Could not send the reply. Try again.")
        }
    }
}
