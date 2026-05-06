import SwiftUI

// MARK: - Notification Kind Style (data-driven icon/color/label mapping)

private struct NotificationKindStyle {
    let icon: String
    let gradient: LinearGradient
    let color: Color
    let labelAr: String
    let labelEn: String

    var label: String { L10n.t(labelAr, labelEn) }

    private static let styles: [String: NotificationKindStyle] = [
        "approval":          .init(icon: "checkmark.circle.fill",                    gradient: DS.Color.gradientCool,    color: DS.Color.success,     labelAr: "عضوية",           labelEn: "Membership"),
        "join_approved":     .init(icon: "checkmark.circle.fill",                    gradient: DS.Color.gradientCool,    color: DS.Color.success,     labelAr: "عضوية",           labelEn: "Membership"),
        "join_request":      .init(icon: "link.circle.fill",                         gradient: DS.Color.gradientCool,    color: DS.Color.info,        labelAr: "طلب انضمام",      labelEn: "Join Request"),
        "news":              .init(icon: "newspaper.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "أخبار",           labelEn: "News"),
        "news_add":          .init(icon: "newspaper.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "أخبار",           labelEn: "News"),
        "admin":             .init(icon: "shield.fill",                              gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "إدارة",           labelEn: "Admin"),
        "admin_request":     .init(icon: "shield.fill",                              gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "إدارة",           labelEn: "Admin"),
        "deceased_report":   .init(icon: "heart.fill",                               gradient: DS.Color.gradientWarm,    color: DS.Color.neonPink,    labelAr: "وفاة",            labelEn: "Deceased"),
        "child_add":         .init(icon: "person.badge.plus",                        gradient: DS.Color.gradientCool,    color: DS.Color.info,        labelAr: "إضافة ابن",       labelEn: "Child Add"),
        "phone_change":      .init(icon: "phone.arrow.right",                        gradient: DS.Color.gradientNeon,    color: DS.Color.neonBlue,    labelAr: "تغيير رقم",       labelEn: "Phone Change"),
        "news_report":       .init(icon: "exclamationmark.triangle.fill",            gradient: DS.Color.gradientFire,    color: DS.Color.warning,     labelAr: "بلاغ خبر",        labelEn: "News Report"),
        "contact_message":   .init(icon: "envelope.fill",                            gradient: DS.Color.gradientOcean,   color: DS.Color.primary,     labelAr: "تواصل",           labelEn: "Contact"),
        "link_request":      .init(icon: "link.circle.fill",                         gradient: DS.Color.gradientCool,    color: DS.Color.info,        labelAr: "طلب ربط",         labelEn: "Link Request"),
        "gallery_add":       .init(icon: "photo.fill",                               gradient: DS.Color.gradientNeon,    color: DS.Color.neonCyan,    labelAr: "معرض صور",        labelEn: "Gallery"),
        "news_comment":      .init(icon: "bubble.left.fill",                         gradient: DS.Color.gradientCool,    color: DS.Color.info,        labelAr: "تعليق",           labelEn: "Comment"),
        "news_like":         .init(icon: "heart.fill",                               gradient: DS.Color.gradientFire,    color: DS.Color.error,       labelAr: "إعجاب",           labelEn: "Like"),
        "news_published":    .init(icon: "megaphone.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "خبر جديد",        labelEn: "New Post"),
        "profile_update":    .init(icon: "person.crop.circle.badge.checkmark",       gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تحديث بيانات",    labelEn: "Profile Update"),
        "account_activated": .init(icon: "checkmark.seal.fill",                      gradient: DS.Color.gradientCool,    color: DS.Color.success,     labelAr: "تفعيل حساب",      labelEn: "Activated"),
        "role_change":       .init(icon: "shield.lefthalf.filled",                   gradient: DS.Color.gradientAccent,  color: DS.Color.warning,     labelAr: "تغيير الصلاحية",  labelEn: "Role Change"),
        "weekly_digest":     .init(icon: "list.clipboard.fill",                      gradient: DS.Color.gradientOcean,   color: DS.Color.primaryDark, labelAr: "ملخص أسبوعي",     labelEn: "Weekly Digest"),
        "tree_edit":         .init(icon: "pencil.circle.fill",                       gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل شجرة",      labelEn: "Tree Edit"),
        "story_pending":     .init(icon: "circle.dashed",                            gradient: DS.Color.gradientNeon,    color: DS.Color.neonCyan,    labelAr: "قصة معلقة",        labelEn: "Pending Story"),
        "story_approved":    .init(icon: "circle.fill",                              gradient: DS.Color.gradientCool,    color: DS.Color.info,        labelAr: "قصة معتمدة",      labelEn: "Story Approved"),
        "story_rejected":    .init(icon: "circle.fill",                              gradient: DS.Color.gradientCool,    color: DS.Color.info,        labelAr: "قصة مرفوضة",      labelEn: "Story Rejected"),
    ]

    private static let fallback = NotificationKindStyle(
        icon: "bell.fill", gradient: DS.Color.gradientPrimary, color: DS.Color.primary,
        labelAr: "عام", labelEn: "General"
    )

    static func style(for kind: String) -> NotificationKindStyle {
        styles[kind] ?? fallback
    }
}

// MARK: - Layout Constants

private enum NotifLayout {
    /// Detail info row icon column width (also used by detailDivider leading inset)
    static let infoIconWidth: CGFloat = 28
    /// Notification row icon circle size
    static let rowIconSize: CGFloat = 44
    /// Selection badge min dimension
    static let badgeSize: CGFloat = 22
}

struct NotificationsCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    @AppStorage("notif_comments") private var notifComments: Bool = true
    @AppStorage("notif_likes") private var notifLikes: Bool = true
    @AppStorage("notif_profile_updates") private var notifProfileUpdates: Bool = true

    @State private var appeared = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var selectedNotification: AppNotification? = nil

    // MARK: - Date Formatters

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func fullDateTime(_ date: Date) -> String {
        Self.fullDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.fullDateFormatter.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // شريط الأدوات الموحد
                actionBar

                if notificationVM.isLoading && filteredNotifications.isEmpty {
                    Spacer()
                    ProgressView(L10n.t("جاري التحميل...", "Loading..."))
                        .tint(DS.Color.primary)
                    Spacer()
                } else if filteredNotifications.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    notificationsList
                }
            }
        }
        .navigationTitle(L10n.t("الإشعارات", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .task { await notificationVM.fetchNotifications() }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $selectedNotification) { notification in
            notificationDetailSheet(notification)
        }
    }

    // MARK: - Action Bar (Unified)

    private var actionBar: some View {
        let unreadCount = filteredNotifications.filter { !$0.read }.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {

                if isSelecting {
                    // ── وضع التحديد ──

                    // إلغاء
                    pillButton(
                        icon: "xmark",
                        label: L10n.t("إلغاء", "Cancel"),
                        fg: DS.Color.error,
                        bg: DS.Color.error.opacity(0.10)
                    ) {
                        withAnimation(DS.Anim.snappy) {
                            isSelecting = false
                            selectedIds.removeAll()
                        }
                    }

                    // تحديد الكل / إلغاء الكل
                    let allIds = Set(filteredNotifications.map(\.id))
                    let allSelected = !allIds.isEmpty && selectedIds == allIds
                    pillButton(
                        icon: allSelected ? "checkmark.square.fill" : "square.dashed",
                        label: allSelected ? L10n.t("إلغاء الكل", "Deselect") : L10n.t("الكل", "All"),
                        fg: DS.Color.accent,
                        bg: DS.Color.accent.opacity(0.10)
                    ) {
                        withAnimation(DS.Anim.snappy) {
                            selectedIds = allSelected ? [] : allIds
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }

                    // مقروء
                    pillButton(
                        icon: "envelope.open.fill",
                        label: L10n.t("مقروء", "Read"),
                        fg: DS.Color.textOnPrimary,
                        bg: selectedIds.isEmpty ? DS.Color.inactive : DS.Color.primary,
                        disabled: selectedIds.isEmpty
                    ) {
                        let ids = selectedIds
                        withAnimation(DS.Anim.snappy) { selectedIds.removeAll(); isSelecting = false }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await notificationVM.markNotificationsAsRead(ids: ids) }
                    }

                    // حذف — المدير والمالك فقط
                    if authVM.isAdmin {
                        pillButton(
                            icon: "trash.fill",
                            label: L10n.t("حذف", "Delete"),
                            fg: DS.Color.textOnPrimary,
                            bg: selectedIds.isEmpty ? DS.Color.inactive : DS.Color.error,
                            disabled: selectedIds.isEmpty
                        ) {
                            let ids = selectedIds
                            withAnimation(DS.Anim.snappy) { selectedIds.removeAll(); isSelecting = false }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { await notificationVM.deleteNotifications(ids: ids) }
                        }
                    }

                    // عداد المحدد
                    if !selectedIds.isEmpty {
                        Text("\(selectedIds.count)")
                            .font(DS.Font.scaled(11, weight: .black))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(minWidth: NotifLayout.badgeSize, minHeight: NotifLayout.badgeSize)
                            .background(DS.Color.primary)
                            .clipShape(Circle())
                    }

                } else {
                    // ── الوضع العادي ──

                    // تحديث
                    pillButton(
                        icon: "arrow.clockwise",
                        label: L10n.t("تحديث", "Refresh"),
                        fg: DS.Color.primary,
                        bg: DS.Color.primary.opacity(0.10),
                        disabled: notificationVM.isLoading
                    ) {
                        Task { await notificationVM.fetchNotifications(force: true) }
                    }

                    // تحديد
                    if !filteredNotifications.isEmpty {
                        pillButton(
                            icon: "checklist.unchecked",
                            label: L10n.t("تحديد", "Select"),
                            fg: DS.Color.accent,
                            bg: DS.Color.accent.opacity(0.10)
                        ) {
                            withAnimation(DS.Anim.snappy) { isSelecting = true; selectedIds.removeAll() }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }

                    // قراءة الكل
                    if unreadCount > 0 {
                        pillButton(
                            icon: "envelope.open.fill",
                            label: L10n.t("قراءة الكل", "Read All"),
                            fg: DS.Color.primary,
                            bg: DS.Color.primary.opacity(0.10)
                        ) {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            Task { await notificationVM.markAllNotificationsAsRead() }
                        }
                    }

                    // عداد غير المقروء
                    if unreadCount > 0 {
                        HStack(spacing: DS.Spacing.xs) {
                            Circle()
                                .fill(DS.Color.error)
                                .frame(width: 7, height: 7)
                            Text("\(unreadCount) " + L10n.t("غير مقروء", "unread"))
                                .font(DS.Font.scaled(11, weight: .semibold))
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surfaceElevated.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.textTertiary.opacity(0.1)).frame(height: 0.5)
        }
        .animation(DS.Anim.snappy, value: isSelecting)
        .animation(DS.Anim.snappy, value: selectedIds.count)
    }

    // MARK: - Pill Button

    private func pillButton(
        icon: String,
        label: String,
        fg: Color,
        bg: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .semibold))
                Text(label)
                    .font(DS.Font.scaled(12, weight: .bold))
            }
            .foregroundColor(fg)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(bg)
            .clipShape(Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Filtered Notifications

    private var hiddenKinds: Set<String> {
        var kinds = Set<String>()
        if !notifComments { kinds.insert("news_comment") }
        if !notifLikes { kinds.insert("news_like") }
        if !notifProfileUpdates { kinds.insert("profile_update") }
        return kinds
    }

    /// أنواع الإشعارات الإدارية — المدير والمالك فقط يشوفونها
    private let adminOnlyKinds: Set<String> = [
        NotificationKind.adminEdit.rawValue,
        NotificationKind.adminRequest.rawValue,
        NotificationKind.treeEdit.rawValue,
        NotificationKind.linkRequest.rawValue,
        NotificationKind.adminEditName.rawValue,
        NotificationKind.adminEditDates.rawValue,
        NotificationKind.adminEditPhone.rawValue,
        NotificationKind.adminEditRole.rawValue,
        NotificationKind.adminEditFather.rawValue,
        NotificationKind.adminEditAvatar.rawValue,
        NotificationKind.adminEditChildAdd.rawValue,
        NotificationKind.adminEditChildRemove.rawValue,
    ]

    private var filteredNotifications: [AppNotification] {
        let base: [AppNotification]
        if authVM.isAdmin {
            // المدير يشوف كل شي
            base = notificationVM.notifications
        } else {
            // الباقي يشوفون: الموجهة لهم + العامة (بدون الإدارية)
            base = notificationVM.notifications.filter { notif in
                notif.targetMemberId != nil || !adminOnlyKinds.contains(notif.kind)
            }
        }
        if hiddenKinds.isEmpty { return base }
        return base.filter { !hiddenKinds.contains($0.kind) }
    }

    // MARK: - Date Grouping

    private func dateSection(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.t("اليوم", "Today")
        } else if calendar.isDateInYesterday(date) {
            return L10n.t("أمس", "Yesterday")
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return L10n.t("هذا الأسبوع", "This Week")
        } else {
            return L10n.t("أقدم", "Older")
        }
    }

    private var groupedNotifications: [(String, [AppNotification])] {
        let sorted = filteredNotifications.sorted { $0.createdDate > $1.createdDate }
        let grouped = Dictionary(grouping: sorted) { dateSection(for: $0.createdDate) }
        let order = [
            L10n.t("اليوم", "Today"),
            L10n.t("أمس", "Yesterday"),
            L10n.t("هذا الأسبوع", "This Week"),
            L10n.t("أقدم", "Older")
        ]
        return order.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        List {
            ForEach(groupedNotifications, id: \.0) { section, items in
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let iconInfo = NotificationKindStyle.style(for: item.kind)
                        let isUnread = !item.read

                        notificationRow(item: item, iconInfo: iconInfo, isUnread: isUnread)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(DS.Anim.smooth.delay(Double(min(index, 5)) * 0.04), value: appeared)
                            .listRowInsets(EdgeInsets(top: DS.Spacing.xs, leading: DS.Spacing.lg, bottom: DS.Spacing.xs, trailing: DS.Spacing.lg))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: authVM.isAdmin) {
                                if authVM.isAdmin {
                                    Button(role: .destructive) {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        Task { await notificationVM.deleteNotification(id: item.id) }
                                    } label: {
                                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if isUnread {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        Task { await notificationVM.markNotificationAsRead(id: item.id) }
                                    } label: {
                                        Label(L10n.t("مقروء", "Read"), systemImage: "envelope.open")
                                    }
                                    .tint(DS.Color.primary)
                                }
                            }
                    }
                } header: {
                    HStack(spacing: DS.Spacing.sm) {
                        Text(section)
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)
                        Rectangle()
                            .fill(DS.Color.textTertiary.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.lg, bottom: 0, trailing: DS.Spacing.lg))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await notificationVM.fetchNotifications(force: true)
        }
    }

    // MARK: - Notification Row

    private func notificationRow(item: AppNotification, iconInfo: NotificationKindStyle, isUnread: Bool) -> some View {
        Button {
            if isSelecting {
                withAnimation(DS.Anim.snappy) {
                    if selectedIds.contains(item.id) {
                        selectedIds.remove(item.id)
                    } else {
                        _ = selectedIds.insert(item.id)
                    }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } else {
                selectedNotification = item
                if isUnread {
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                // Checkbox في وضع التحديد
                if isSelecting {
                    let isSelected = selectedIds.contains(item.id)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(DS.Font.scaled(22, weight: .medium))
                        .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.textTertiary)
                        .animation(DS.Anim.snappy, value: isSelected)
                }

                // أيقونة النوع — دائرة كبيرة
                ZStack {
                    Circle()
                        .fill(isUnread ? iconInfo.color.opacity(0.12) : DS.Color.textTertiary.opacity(0.08))
                        .frame(width: NotifLayout.rowIconSize, height: NotifLayout.rowIconSize)

                    Image(systemName: iconInfo.icon)
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(isUnread ? iconInfo.color : DS.Color.textTertiary)
                }

                // المحتوى
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    // العنوان + الوقت
                    HStack(alignment: .top) {
                        Text(item.title)
                            .font(DS.Font.scaled(15, weight: isUnread ? .bold : .medium))
                            .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textTertiary)
                            .lineLimit(2)

                        Spacer(minLength: DS.Spacing.sm)

                        Text(relativeTime(item.createdDate))
                            .font(DS.Font.scaled(11, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                    }

                    // النص الكامل
                    richBodyView(
                        item.body,
                        font: DS.Font.scaled(13, weight: .regular),
                        color: isUnread ? DS.Color.textSecondary : DS.Color.textTertiary,
                        lineLimit: 3
                    )

                    // شريط سفلي: التصنيف + بادج المدير
                    HStack(spacing: DS.Spacing.sm) {
                        // التصنيف
                        Text(iconInfo.label)
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(isUnread ? iconInfo.color : DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background((isUnread ? iconInfo.color : DS.Color.textTertiary).opacity(0.08))
                            .clipShape(Capsule())

                        // اسم المرسل الثلاثي — يظهر فقط للمدراء والمشرفين
                        if authVM.isAdmin, let creatorId = item.createdBy {
                            let creator = memberVM.member(byId: creatorId)
                            let creatorName = creator?.shortFullName ?? L10n.t("مدير", "Admin")
                            let roleColor: Color = creator?.roleColor ?? DS.Color.accent

                            HStack(spacing: 3) {
                                Circle()
                                    .fill(roleColor)
                                    .frame(width: 6, height: 6)
                                Text(creatorName)
                                    .font(DS.Font.scaled(10, weight: .bold))
                            }
                            .foregroundColor(roleColor)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(roleColor.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(roleColor.opacity(0.2), lineWidth: 0.5))
                        }

                        Spacer(minLength: 0)
                    }
                }

                // نقطة غير مقروء
                if isUnread && !isSelecting {
                    Circle()
                        .fill(DS.Color.primary)
                        .frame(width: 9, height: 9)
                }
            }
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(
                        isUnread ? iconInfo.color.opacity(0.15) : DS.Color.textTertiary.opacity(0.08),
                        lineWidth: isUnread ? 1 : 0.5
                    )
            )
            .dsSubtleShadow()
            .opacity(isUnread ? 1 : 0.55)
        }
        .buttonStyle(DSScaleButtonStyle())
        .contextMenu {
            if isUnread {
                Button {
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
                } label: {
                    Label(L10n.t("تعليم كمقروء", "Mark as Read"), systemImage: "envelope.open")
                }
            }
            if authVM.isAdmin {
                Button(role: .destructive) {
                    Task { await notificationVM.deleteNotification(id: item.id) }
                } label: {
                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DSEmptyState(
            icon: "bell.slash.fill",
            title: L10n.t("لا توجد إشعارات", "No Notifications"),
            subtitle: L10n.t("الإشعارات تظهر هنا", "Notifications appear here"),
            style: .halo
        )
    }

    // MARK: - Detail Sheet

    private func notificationDetailSheet(_ notification: AppNotification) -> some View {
        let iconInfo = NotificationKindStyle.style(for: notification.kind)
        let date = notification.createdDate

        return NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {

                        // ── Push-notification style card ──
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: DS.Spacing.sm) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(iconInfo.gradient)
                                    .frame(width: NotifLayout.infoIconWidth, height: NotifLayout.infoIconWidth)
                                    .overlay(
                                        Image(systemName: iconInfo.icon)
                                            .font(DS.Font.scaled(13, weight: .bold))
                                            .foregroundColor(DS.Color.textOnPrimary)
                                    )

                                Text(iconInfo.label)
                                    .font(DS.Font.scaled(14, weight: .semibold))
                                    .foregroundColor(DS.Color.textSecondary)

                                Spacer(minLength: 0)

                                Text(relativeTime(date))
                                    .font(DS.Font.scaled(13, weight: .regular))
                                    .foregroundColor(DS.Color.textTertiary)
                            }

                            Spacer().frame(height: DS.Spacing.md)

                            Text(notification.title)
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)

                            Spacer().frame(height: DS.Spacing.sm)

                            richBodyView(
                                notification.body,
                                font: DS.Font.scaled(15, weight: .regular),
                                color: DS.Color.textPrimary
                            )
                        }
                        .padding(DS.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .fill(DS.Color.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 0.5)
                        )
                        .dsSubtleShadow()
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.xl)

                        // ── Info rows ──
                        VStack(spacing: 0) {
                            detailInfoRow(
                                icon: notification.read ? "envelope.open.fill" : "envelope.badge.fill",
                                label: L10n.t("الحالة", "Status"),
                                value: notification.read ? L10n.t("مقروء", "Read") : L10n.t("غير مقروء", "Unread"),
                                color: notification.read ? DS.Color.success : DS.Color.error
                            )

                            detailDivider

                            detailInfoRow(
                                icon: "calendar.badge.clock",
                                label: L10n.t("التاريخ", "Date"),
                                value: fullDateTime(date),
                                color: DS.Color.primary
                            )

                            // اسم المرسل الثلاثي — يظهر فقط للمدراء والمشرفين
                            if authVM.isAdmin, let creatorId = notification.createdBy {
                                let creator = memberVM.member(byId: creatorId)
                                let creatorName = creator?.shortFullName ?? L10n.t("مدير", "Admin")
                                let roleColor: Color = creator?.roleColor ?? DS.Color.accent

                                detailDivider
                                HStack(spacing: DS.Spacing.md) {
                                    Circle()
                                        .fill(roleColor)
                                        .frame(width: 10, height: 10)
                                        .frame(width: NotifLayout.infoIconWidth, alignment: .center)

                                    Text(L10n.t("بواسطة", "By"))
                                        .font(DS.Font.caption1)
                                        .foregroundColor(DS.Color.textTertiary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(creatorName)
                                        .font(DS.Font.scaled(12, weight: .bold))
                                        .foregroundColor(roleColor)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)
                            }

                            if authVM.isAdmin {
                                detailDivider
                                detailInfoRow(
                                    icon: "tag.fill",
                                    label: L10n.t("التصنيف", "Category"),
                                    value: iconInfo.label,
                                    color: DS.Color.accent
                                )
                            }
                        }
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 0.5)
                        )
                        .padding(.horizontal, DS.Spacing.lg)

                        // ── Actions ──
                        VStack(spacing: DS.Spacing.md) {
                            if !notification.read {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let id = notification.id
                                    selectedNotification = nil
                                    Task { await notificationVM.markNotificationAsRead(id: id) }
                                } label: {
                                    HStack(spacing: DS.Spacing.sm) {
                                        Image(systemName: "envelope.open.fill")
                                            .font(DS.Font.scaled(14, weight: .semibold))
                                        Text(L10n.t("تعليم كمقروء", "Mark as Read"))
                                            .font(DS.Font.calloutBold)
                                    }
                                    .foregroundColor(DS.Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DS.Spacing.md)
                                    .background(DS.Color.primary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                                }
                                .buttonStyle(DSScaleButtonStyle())
                            }

                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                let id = notification.id
                                selectedNotification = nil
                                Task { await notificationVM.deleteNotification(id: id) }
                            } label: {
                                HStack(spacing: DS.Spacing.sm) {
                                    Image(systemName: "trash.fill")
                                        .font(DS.Font.scaled(14, weight: .semibold))
                                    Text(L10n.t("حذف الإشعار", "Delete Notification"))
                                        .font(DS.Font.calloutBold)
                                }
                                .foregroundColor(DS.Color.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.md)
                                .background(DS.Color.error.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                            }
                            .buttonStyle(DSScaleButtonStyle())
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        Spacer(minLength: DS.Spacing.xxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("تفاصيل الإشعار", "Notification Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedNotification = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.textTertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Detail Info Row

    private func detailInfoRow(icon: String, label: String, value: some StringProtocol, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: NotifLayout.infoIconWidth, alignment: .center)

            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.leading, DS.Spacing.lg + NotifLayout.infoIconWidth + DS.Spacing.md)
    }

    // MARK: - Helpers

    private func cleanBody(_ body: String) -> String {
        body.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("بواسطة:") }
            .joined(separator: "\n")
    }

    /// Renders body text, wrapping «name» delimiters in styled capsules.
    @ViewBuilder
    private func richBodyView(_ body: String, font: Font, color: Color, lineLimit: Int? = nil) -> some View {
        let cleaned = cleanBody(body)
        let segments = BodySegment.parse(cleaned)

        if segments.contains(where: \.isCapsule) {
            WrappingHStack(segments: segments, font: font, color: color, lineLimit: lineLimit)
        } else {
            Text(cleaned)
                .font(font)
                .foregroundColor(color)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
        }
    }

    struct BodySegment: Identifiable {
        let id = UUID()
        let text: String
        let isCapsule: Bool

        /// Splits text on «name» delimiters into plain and capsule segments.
        static func parse(_ text: String) -> [BodySegment] {
            var segments: [BodySegment] = []
            var remaining = text[...]

            while let open = remaining.range(of: "«") {
                let before = remaining[remaining.startIndex..<open.lowerBound]
                if !before.isEmpty { segments.append(.init(text: String(before), isCapsule: false)) }

                let afterOpen = remaining[open.upperBound...]
                guard let close = afterOpen.range(of: "»") else {
                    // No closing delimiter -- treat the rest as plain text
                    segments.append(.init(text: String(remaining[open.lowerBound...]), isCapsule: false))
                    return segments
                }
                let name = afterOpen[afterOpen.startIndex..<close.lowerBound]
                if !name.isEmpty { segments.append(.init(text: String(name), isCapsule: true)) }
                remaining = afterOpen[close.upperBound...]
            }

            if !remaining.isEmpty { segments.append(.init(text: String(remaining), isCapsule: false)) }
            return segments
        }
    }

    private func createdByName(for notification: AppNotification) -> String? {
        guard authVM.isAdmin else { return nil }
        if let creatorId = notification.createdBy {
            if let member = memberVM.member(byId: creatorId) {
                return member.fullName
            }
            if creatorId == authVM.currentUser?.id {
                return authVM.currentUser?.fullName
            }
        }
        for line in notification.body.components(separatedBy: "\n") {
            if line.hasPrefix("بواسطة: ") {
                let name = String(line.dropFirst("بواسطة: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

}

// MARK: - Wrapping HStack for capsule names

private struct WrappingHStack: View {
    let segments: [NotificationsCenterView.BodySegment]
    let font: Font
    let color: Color
    let lineLimit: Int?

    /// يحدد لون الكبسولة حسب محتواها — إذا كانت صلاحية يستخدم لونها، وإلا اللون الأساسي
    private func capsuleColor(for text: String) -> Color {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "مدير", "Admin":       return FamilyMember.UserRole.admin.color
        case "مشرف", "Supervisor":  return FamilyMember.UserRole.supervisor.color
        case "عضو", "Member":       return FamilyMember.UserRole.member.color
        default:                     return DS.Color.primary
        }
    }

    var body: some View {
        // عرض النصوص مع كبسولات الأسماء
        FlowLayout(spacing: 4) {
            ForEach(segments) { segment in
                if segment.isCapsule {
                    let capColor = capsuleColor(for: segment.text)
                    Text(segment.text)
                        .font(font).bold()
                        .foregroundColor(capColor)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(capColor.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(capColor.opacity(0.25), lineWidth: 0.5))
                } else {
                    Text(segment.text)
                        .font(font)
                        .foregroundColor(color)
                        .padding(.vertical, 3)
                }
            }
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentY += lineHeight + spacing
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentY += lineHeight + spacing
                currentX = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
