import SwiftUI

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
            DSDecorativeBackground()

            VStack(spacing: 0) {
                // شريط الأدوات الموحد
                actionBar

                if filteredNotifications.isEmpty {
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
                        fg: .white,
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
                            fg: .white,
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
                            .foregroundColor(.white)
                            .frame(minWidth: 22, minHeight: 22)
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

    private var filteredNotifications: [AppNotification] {
        let base: [AppNotification]
        if authVM.canModerate {
            base = notificationVM.notifications
        } else {
            base = notificationVM.notifications.filter { $0.targetMemberId != nil }
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
                        let iconInfo = notificationIcon(for: item.kind)
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

    private func notificationRow(item: AppNotification, iconInfo: (icon: String, gradient: LinearGradient, color: Color), isUnread: Bool) -> some View {
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
                        .frame(width: 44, height: 44)

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
                        Text(kindLabel(for: item.kind))
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(isUnread ? iconInfo.color : DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background((isUnread ? iconInfo.color : DS.Color.textTertiary).opacity(0.08))
                            .clipShape(Capsule())

                        // اسم المرسل الثلاثي — يظهر فقط للمدراء والمشرفين
                        if authVM.canModerate, let creatorId = item.createdBy {
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
            .shadow(color: isUnread ? iconInfo.color.opacity(0.08) : Color.clear, radius: 8, x: 0, y: 3)
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
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.06))
                    .frame(width: 130, height: 130)
                    .scaleEffect(appeared ? 1 : 0.5)

                Circle()
                    .fill(DS.Color.primary.opacity(0.10))
                    .frame(width: 95, height: 95)
                    .scaleEffect(appeared ? 1 : 0.6)

                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 64, height: 64)
                    .scaleEffect(appeared ? 1 : 0.7)

                Image(systemName: "bell.slash.fill")
                    .font(DS.Font.scaled(28, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            .opacity(appeared ? 1 : 0)

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("لا توجد إشعارات", "No Notifications"))
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textPrimary)

                Text(L10n.t("ستظهر الإشعارات هنا عند وصولها", "Notifications will appear here when received"))
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 15)
        }
        .padding(.horizontal, DS.Spacing.xxxl)
    }

    // MARK: - Detail Sheet

    private func notificationDetailSheet(_ notification: AppNotification) -> some View {
        let iconInfo = notificationIcon(for: notification.kind)
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
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Image(systemName: iconInfo.icon)
                                            .font(DS.Font.scaled(13, weight: .bold))
                                            .foregroundColor(DS.Color.textOnPrimary)
                                    )

                                Text(kindLabel(for: notification.kind))
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
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
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
                            if authVM.canModerate, let creatorId = notification.createdBy {
                                let creator = memberVM.member(byId: creatorId)
                                let creatorName = creator?.shortFullName ?? L10n.t("مدير", "Admin")
                                let roleColor: Color = creator?.roleColor ?? DS.Color.accent

                                detailDivider
                                HStack(spacing: DS.Spacing.md) {
                                    Circle()
                                        .fill(roleColor)
                                        .frame(width: 10, height: 10)
                                        .frame(width: 28, alignment: .center)

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

                            if authVM.canModerate {
                                detailDivider
                                detailInfoRow(
                                    icon: "tag.fill",
                                    label: L10n.t("التصنيف", "Category"),
                                    value: kindLabel(for: notification.kind),
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
                .frame(width: 28, alignment: .center)

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
            .padding(.leading, DS.Spacing.lg + 28 + DS.Spacing.md)
    }

    // MARK: - Helpers

    private func cleanBody(_ body: String) -> String {
        body.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("بواسطة:") }
            .joined(separator: "\n")
    }

    /// يحلل النص ويبني عرض يحتوي على كبسولات للأسماء المحاطة بـ «»
    @ViewBuilder
    private func richBodyView(_ body: String, font: Font, color: Color, lineLimit: Int? = nil) -> some View {
        let cleaned = cleanBody(body)
        let segments = parseNameSegments(cleaned)

        if segments.contains(where: { $0.isCapsule }) {
            // فيه أسماء — نعرضها كـ Flow layout
            WrappingHStack(segments: segments, font: font, color: color, lineLimit: lineLimit)
        } else {
            // نص عادي بدون كبسولات
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
    }

    private func parseNameSegments(_ text: String) -> [BodySegment] {
        var segments: [BodySegment] = []
        var remaining = text[...]

        while let openRange = remaining.range(of: "«") {
            // نص قبل «
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            if !before.isEmpty {
                segments.append(BodySegment(text: before, isCapsule: false))
            }

            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "»") {
                let name = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                if !name.isEmpty {
                    segments.append(BodySegment(text: name, isCapsule: true))
                }
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                // لا يوجد إغلاق — نكمل كنص عادي
                let rest = String(remaining[openRange.lowerBound...])
                segments.append(BodySegment(text: rest, isCapsule: false))
                remaining = remaining[remaining.endIndex...]
            }
        }

        // النص المتبقي
        if !remaining.isEmpty {
            segments.append(BodySegment(text: String(remaining), isCapsule: false))
        }

        return segments
    }

    private func createdByName(for notification: AppNotification) -> String? {
        guard authVM.canModerate else { return nil }
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

    // MARK: - Notification Icon

    private func notificationIcon(for kind: String) -> (icon: String, gradient: LinearGradient, color: Color) {
        switch kind {
        case "approval", "join_approved":
            return ("checkmark.circle.fill", DS.Color.gradientCool, DS.Color.success)
        case "news", "news_add":
            return ("newspaper.fill", DS.Color.gradientPrimary, DS.Color.primary)
        case "admin", "admin_request":
            return ("shield.fill", DS.Color.gradientAccent, DS.Color.accent)
        case "deceased_report":
            return ("heart.fill", DS.Color.gradientWarm, DS.Color.neonPink)
        case "child_add":
            return ("person.badge.plus", DS.Color.gradientCool, DS.Color.info)
        case "phone_change":
            return ("phone.arrow.right", DS.Color.gradientNeon, DS.Color.neonBlue)
        case "news_report":
            return ("exclamationmark.triangle.fill", DS.Color.gradientFire, DS.Color.warning)
        case "contact_message":
            return ("envelope.fill", DS.Color.gradientOcean, DS.Color.primary)
        case "link_request":
            return ("link.circle.fill", DS.Color.gradientCool, DS.Color.info)
        case "gallery_add":
            return ("photo.fill", DS.Color.gradientNeon, DS.Color.neonCyan)
        case "news_comment":
            return ("bubble.left.fill", DS.Color.gradientCool, DS.Color.info)
        case "news_like":
            return ("heart.fill", DS.Color.gradientFire, DS.Color.error)
        case "news_published":
            return ("megaphone.fill", DS.Color.gradientPrimary, DS.Color.primary)
        case "profile_update":
            return ("person.crop.circle.badge.checkmark", DS.Color.gradientAccent, DS.Color.accent)
        case "account_activated":
            return ("checkmark.seal.fill", DS.Color.gradientCool, DS.Color.success)
        case "role_change":
            return ("shield.lefthalf.filled", DS.Color.gradientAccent, DS.Color.warning)
        case "weekly_digest":
            return ("list.clipboard.fill", DS.Color.gradientOcean, DS.Color.primaryDark)
        case "tree_edit":
            return ("pencil.circle.fill", DS.Color.gradientAccent, DS.Color.accent)
        case "story_pending":
            return ("circle.dashed", DS.Color.gradientNeon, DS.Color.neonCyan)
        case "story_approved", "story_rejected":
            return ("circle.fill", DS.Color.gradientCool, DS.Color.info)
        default:
            return ("bell.fill", DS.Color.gradientPrimary, DS.Color.primary)
        }
    }

    // MARK: - Kind Label

    private func kindLabel(for kind: String) -> String {
        switch kind {
        case "approval", "join_approved": return L10n.t("عضوية", "Membership")
        case "news", "news_add": return L10n.t("أخبار", "News")
        case "admin", "admin_request": return L10n.t("إدارة", "Admin")
        case "deceased_report": return L10n.t("وفاة", "Deceased")
        case "child_add": return L10n.t("إضافة ابن", "Child Add")
        case "phone_change": return L10n.t("تغيير رقم", "Phone Change")
        case "news_report": return L10n.t("بلاغ خبر", "News Report")
        case "contact_message": return L10n.t("تواصل", "Contact")
        case "link_request": return L10n.t("طلب ربط", "Link Request")
        case "gallery_add": return L10n.t("معرض صور", "Gallery")
        case "news_comment": return L10n.t("تعليق", "Comment")
        case "news_like": return L10n.t("إعجاب", "Like")
        case "news_published": return L10n.t("خبر جديد", "New Post")
        case "profile_update": return L10n.t("تحديث بيانات", "Profile Update")
        case "account_activated": return L10n.t("تفعيل حساب", "Activated")
        case "role_change": return L10n.t("تغيير الصلاحية", "Role Change")
        case "weekly_digest": return L10n.t("ملخص أسبوعي", "Weekly Digest")
        case "tree_edit": return L10n.t("تعديل شجرة", "Tree Edit")
        case "story_pending": return L10n.t("قصة معلقة", "Pending Story")
        case "story_approved": return L10n.t("قصة معتمدة", "Story Approved")
        case "story_rejected": return L10n.t("قصة مرفوضة", "Story Rejected")
        default: return L10n.t("عام", "General")
        }
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
