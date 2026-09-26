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
    /// رسالة طُلب حذفها بالسحب — تأكيد قبل الحذف
    @State private var messageToDelete: AdminRequest? = nil

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
                    .padding(.top, DS.Spacing.md)

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
                                // ضغطة فعلية فقط تفتح التفاصيل — السحب لا يفتحها (طلب المالك).
                                // (زر Button كان يعدّ رفع الإصبع بعد السحب ضغطة)
                                HStack(spacing: DS.Spacing.sm) {
                                    if isSelectMode {
                                        Image(systemName: selectedIDs.contains(msg.id) ? "checkmark.circle.fill" : "circle")
                                            .font(DS.Font.scaled(20, weight: .semibold))
                                            .foregroundColor(selectedIDs.contains(msg.id) ? DS.Color.primary : DS.Color.textTertiary)
                                    }
                                    messageRow(msg)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelectMode {
                                        toggleSelection(msg.id)
                                    } else {
                                        adminRequestVM.markContactMessageRead(msg.id)
                                        selectedMessage = msg
                                    }
                                }
                                .accessibilityAddTraits(.isButton)
                                // نفس سحب الأخبار: صوب اليمين يكشف «حذف» و«تم التعامل» (طلب المالك)
                                .dsSwipeActions(id: msg.id, actions: isSelectMode ? [] : swipeActions(for: msg))
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
                    Button {
                        withAnimation(DS.Anim.quick) {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedIDs.removeAll() }
                        }
                    } label: {
                        Image(systemName: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(DS.Color.primary)
                    }
                    .accessibilityLabel(isSelectMode ? L10n.t("تم", "Done") : L10n.t("تحديد", "Select"))
                }
            }
        }
        .dsAlert(L10n.t("حذف الرسائل", "Delete Messages"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await deleteSelected() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد حذف \(selectedIDs.count) رسالة؟ لا يمكن التراجع.",
                        "Delete \(selectedIDs.count) message(s)? This can't be undone."))
        }
        .dsAlert(L10n.t("حذف الرسالة", "Delete Message"), isPresented: Binding(
            get: { messageToDelete != nil },
            set: { if !$0 { messageToDelete = nil } }
        )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let m = messageToDelete {
                    Task { await adminRequestVM.deleteContactMessages(ids: [m.id]) }
                }
                messageToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { messageToDelete = nil }
        } message: {
            Text(L10n.t("هل تريد حذف هذه الرسالة؟ لا يمكن التراجع.", "Delete this message? This can't be undone."))
        }
        .navigationTitle(L10n.t("رسائل التواصل", "Contact Messages"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            await adminRequestVM.fetchContactMessages()
            isLoading = false
        }
        .dsCenterBox(item: $selectedMessage) { msg in
            MessageDetailSheet(message: msg) {
                selectedMessage = nil
            }
        }
    }

    // MARK: - Filter Bar

    /// تبويبان بعرض متساوٍ داخل حاوية واحدة (نمط segmented) — مرتّب وثابت الحجم
    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(InboxFilter.allCases, id: \.self) { f in
                let selected = filter == f
                let count = f == .pending
                    ? adminRequestVM.contactMessages.filter { $0.status == ApprovalStatus.pending.rawValue }.count
                    : adminRequestVM.contactMessages.filter { $0.status == ApprovalStatus.approved.rawValue }.count
                Button {
                    withAnimation(DS.Anim.quick) { filter = f }
                } label: {
                    HStack(spacing: 6) {
                        Text(f.title)
                            .font(DS.Font.plex(13, weight: selected ? .bold : .medium))
                            .lineLimit(1)
                        if count > 0 {
                            Text("\(count)")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(selected ? DS.Color.primary : DS.Color.textSecondary)
                                .frame(minWidth: 18, minHeight: 18)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(selected ? DS.Color.primary.opacity(0.12) : DS.Color.mutedBackground))
                        }
                    }
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(selected ? DS.Color.background : Color.clear)
                            .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 3, x: 0, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
    }

    // MARK: - Swipe actions

    private func swipeActions(for msg: AdminRequest) -> [DSSwipeAction] {
        var actions = [
            DSSwipeAction(icon: "trash.fill", title: L10n.t("حذف", "Delete"), color: DS.Color.error) {
                messageToDelete = msg
            }
        ]
        if msg.status == ApprovalStatus.pending.rawValue {
            actions.append(DSSwipeAction(icon: "checkmark.circle.fill", title: L10n.t("تم التعامل", "Handled"),
                                         color: DS.Color.success) {
                adminRequestVM.markContactMessageRead(msg.id)
                Task { await adminRequestVM.markContactMessageHandled(msg) }
            })
        }
        return actions
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
        .dsGlass(Rectangle())
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
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
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

        // صندوق موحّد الحجم: صورة · (الاسم + الوقت) · (التصنيف) · مقتطف من سطرين
        return HStack(alignment: .top, spacing: DS.Spacing.sm + 2) {
            avatar(for: msg.member)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    // الاسم أصغر بخط IBM Plex وعلى سطرين (طلب المالك)
                    Text(msg.member?.displayFullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.plex(13, weight: isUnread ? .bold : .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Spacing.xs)
                    HStack(spacing: 4) {
                        if isUnread {
                            Circle().fill(DS.Color.primary).frame(width: 7, height: 7)
                        }
                        if let d = date {
                            Text(relativeShort(d))
                                .font(DS.Font.plex(11, weight: isUnread ? .bold : .regular))
                                .foregroundColor(isUnread ? DS.Color.primary : DS.Color.textTertiary)
                        }
                    }
                }

                HStack(spacing: DS.Spacing.xs) {
                    categoryChip(category)
                    if isPending {
                        Image(systemName: "clock.fill")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.warning)
                    }
                    Spacer(minLength: 0)
                }

                Text(preview)
                    .font(DS.Font.plex(12, weight: .regular))
                    .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(isUnread ? DS.Color.primary.opacity(0.30) : DS.Color.cardBorder,
                              lineWidth: isUnread ? 1.2 : 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    // MARK: - Mark all read bar

    private var markAllReadBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(L10n.t(
                "\(adminRequestVM.unreadContactMessagesCount) رسالة جديدة",
                "\(adminRequestVM.unreadContactMessagesCount) new messages"
            ))
            .font(DS.Font.plex(12, weight: .semibold))
            .foregroundColor(DS.Color.textSecondary)
            Spacer()
            Button {
                withAnimation(DS.Anim.quick) {
                    adminRequestVM.markAllContactMessagesRead()
                }
            } label: {
                Text(L10n.t("تحديد الكل كمقروء", "Mark all read"))
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    private func avatar(for member: FamilyMember?) -> some View {
        DSMemberAvatar(
            name: member?.firstName ?? "?",
            avatarUrl: member?.avatarUrl,
            size: 36,
            roleColor: member?.roleColor ?? DS.Color.primary
        )
    }

    private func categoryChip(_ raw: String) -> some View {
        let info = ContactCategoryInfo.from(raw: raw)
        return HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(DS.Font.scaled(11, weight: .bold))
            Text(info.title)
                .font(DS.Font.scaled(11, weight: .bold))
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

/// تفاصيل الرسالة — مربّع عرض بنفس التصميم الموحّد (طلب المالك): المرسل، الرسالة،
/// الرد على العضو، و«تم التعامل» (للرسالة المعلّقة) / «إغلاق» أسفل المربّع
private struct MessageDetailSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    let message: AdminRequest
    let onDismiss: () -> Void

    @State private var isMarking = false
    /// مربّع كتابة الرد الرسمي (يُرسل من بريد العائلة)
    @State private var showEmailComposer = false

    private var isPending: Bool { message.status == ApprovalStatus.pending.rawValue }

    var body: some View {
        DSComposer(
            title: L10n.t("تفاصيل الرسالة", "Message Detail"),
            subtitle: message.member?.displayFullName ?? L10n.t("عضو", "Member"),
            icon: "envelope.open.fill",
            tint: DS.Color.actionNavy,
            actionTitle: isMarking ? L10n.t("جارٍ…", "Working…") : L10n.t("تم التعامل", "Mark as Handled"),
            actionIcon: "checkmark.circle.fill",
            showsAction: isPending,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: true,
            isBusy: isMarking,
            isBehindExtra: showEmailComposer,
            onSubmit: { Task { await markHandled() } },
            onCancel: onDismiss
        ) {
            senderSection
            messageSection
            replySection
        }
        .onAppear {
            // defensive: تأكد أن الرسالة معلّمة كمقروءة حتى لو فُتحت من مسار آخر
            adminRequestVM.markContactMessageRead(message.id)
        }
        .dsCenterBox(isPresented: $showEmailComposer) {
            OfficialReplySheet(
                to: ContactParser.preferredContact(from: message) ?? "",
                memberName: message.member?.fullName ?? "",
                category: ContactParser.category(of: message),
                originalMessage: ContactParser.message(from: message)
            )
        }
    }

    // MARK: المرسل — الصورة · الاسم والهاتف · التصنيف في الطرف المقابل

    private var senderSection: some View {
        let info = ContactCategoryInfo.from(raw: ContactParser.category(of: message))
        let phone = message.member?.phoneNumber ?? ""
        return DSComposerSection(title: L10n.t("المرسل", "Sender"),
                                 icon: "person.fill",
                                 tint: DS.Color.primary,
                                 index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(
                    name: message.member?.firstName ?? "?",
                    avatarUrl: message.member?.avatarUrl,
                    size: 44,
                    roleColor: message.member?.roleColor ?? DS.Color.primary
                )
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.member?.displayFullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !phone.isEmpty {
                        Text(phone)
                            .font(DS.Font.plex(12))
                            .foregroundColor(DS.Color.fieldValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Image(systemName: info.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(info.color)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(info.color.opacity(0.14)))
                        .accessibilityHidden(true)   // التصنيف يُقرأ من النص تحته
                    Text(info.title)
                        .font(DS.Font.plex(10.5, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)   // المرسل ورقمه وتصنيف الرسالة معاً
        }
    }

    // MARK: نص الرسالة (+ حالة التعامل)

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الرسالة", "Message"),
                          icon: "text.bubble.fill",
                          tint: DS.Color.info,
                          index: 1) {
            Text(ContactParser.message(from: message))
                .font(DS.Font.plex(15))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsRowBox()

            if !isPending {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "checkmark.seal.fill", tint: DS.Color.success)
                        .accessibilityHidden(true)
                    Text(L10n.t("تم التعامل مع هذه الرسالة", "This message was handled"))
                        .font(DS.Font.plex(13.5, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                    Spacer(minLength: 0)
                }
                .dsRowBox()
            }
        }
    }

    // MARK: الرد على العضو — الوسيلة التي طلبها العضو أوّلاً، ثم رقمه المسجّل

    @ViewBuilder
    private var replySection: some View {
        let phone = message.member?.phoneNumber ?? ""
        let preferred = ContactParser.preferredContact(from: message)
        let isEmail = (preferred ?? "").contains("@")
        let replyPhone = isEmail ? phone : (preferred ?? phone)

        if isEmail || !replyPhone.isEmpty {
            DSComposerSection(title: L10n.t("الرد على العضو", "Reply to member"),
                              icon: "arrowshape.turn.up.left.fill",
                              tint: DS.Color.success,
                              index: 2) {
                // وسيلة التواصل التي كتبها العضو — تُعرض وتُنسخ بالضغط
                if let preferred {
                    preferredContactRow(preferred, isEmail: isEmail)
                }

                HStack(spacing: DS.Spacing.sm) {
                    if !replyPhone.isEmpty {
                        replyButton(
                            title: L10n.t("واتساب", "WhatsApp"),
                            icon: "message.fill",
                            // أخضر واتساب الثابت (#25D366) كان باهتاً جداً على خلفيته في الوضع الفاتح
                            // (~1.8:1) — لون أخضر من ألوان التطبيق يُقرأ في الوضعين
                            color: DS.Color.secondary
                        ) { openURL("https://wa.me/\(sanitize(replyPhone))") }
                        replyButton(
                            title: L10n.t("اتصال", "Call"),
                            icon: "phone.fill",
                            color: DS.Color.success
                        ) { openURL("tel:\(sanitize(replyPhone))") }
                    }
                    if isEmail {
                        replyButton(
                            title: L10n.t("بريد", "Email"),
                            icon: "envelope.fill",
                            color: DS.Color.info
                        ) { showEmailComposer = true }
                    }
                }
            }
        }
    }

    private func preferredContactRow(_ preferred: String, isEmail: Bool) -> some View {
        Button {
            UIPasteboard.general.string = preferred
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isEmail ? "envelope.fill" : "phone.fill", tint: DS.Color.info)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("وسيلة التواصل", "Preferred contact"))
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(preferred)
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        // رمز النسخ للعين فقط — القارئ الصوتي يعرف أن الضغط ينسخ
        .accessibilityHint(L10n.t("ينسخ وسيلة التواصل", "Copies the contact"))
    }

    private func replyButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(color.opacity(0.12)))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
            // مساحة ضغط ٤٤ (توصية أبل) — الشكل والارتفاع في الصف كما هما
            .frame(height: 44)
            .contentShape(Rectangle())
            .padding(.vertical, -1)
        }
        .buttonStyle(DSScaleButtonStyle())
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

/// «الرد بالبريد» — مربّع كتابة بنفس التصميم الموحّد (طلب المالك): المستلم ثم نص الرد،
/// و«إرسال الرد» / «إغلاق» أسفل المربّع
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

    private var canSend: Bool {
        !(isSending || didSend || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("الرد بالبريد", "Email reply"),
            subtitle: memberName.isEmpty ? L10n.t("العضو", "Member") : memberName,
            icon: "envelope.badge.fill",
            tint: DS.Color.actionNavy,
            actionTitle: didSend ? L10n.t("تم الإرسال", "Sent") : L10n.t("إرسال الرد", "Send reply"),
            actionIcon: didSend ? "checkmark.circle.fill" : "paperplane.fill",
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: canSend,
            isBusy: isSending,
            // ردّ مكتوب لم يُرسل → «إغلاق» يسأل قبل التجاهل (توصية أبل)؛ بعد الإرسال لا سؤال
            hasUnsavedChanges: !didSend && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSubmit: { Task { await send() } },
            onCancel: { dismiss() }
        ) {
            recipientSection
            replySection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: المستلم

    private var recipientSection: some View {
        DSComposerSection(title: L10n.t("المستلم", "Recipient"),
                          icon: "person.fill",
                          tint: DS.Color.info,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "envelope.badge.fill", tint: DS.Color.info)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(memberName.isEmpty ? L10n.t("العضو", "Member") : memberName)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    Text(to)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: نص الرد

    private var replySection: some View {
        DSComposerSection(title: L10n.t("الرد على العضو", "Reply to member"),
                          icon: "arrowshape.turn.up.left.fill",
                          tint: DS.Color.primary,
                          index: 1) {
            ReplyComposerField(label: L10n.t("نص الرد", "Reply"),
                               placeholder: L10n.t("اكتب ردّك هنا…", "Write your reply…"),
                               text: $replyText)

            if let errorText {
                Text(errorText)
                    .font(DS.Font.plex(12, weight: .semibold))
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
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

/// حقل نص الرد — بنفس شكل `DSComposerField` لكنه أطول (يبدأ بستة أسطر)،
/// فالرد البريدي يحتاج مساحة كتابة مثل محرّر النص السابق
private struct ReplyComposerField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var tint: Color = DS.Color.primary
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(focused ? .white : tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(focused ? tint : tint.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(focused ? tint : DS.Color.fieldLabel)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(6...12)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($focused)
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: focused ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}
