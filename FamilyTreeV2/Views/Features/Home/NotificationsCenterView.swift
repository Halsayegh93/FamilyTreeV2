import SwiftUI

struct NotificationsCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var appeared = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var selectedNotification: AppNotification? = nil
    @State private var filterKind: String? = nil

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                VStack(spacing: 0) {
                    if authVM.notifications.isEmpty {
                        emptyState
                            .frame(maxHeight: .infinity)
                    } else {
                        // فلاتر نوع الإشعار
                        notificationFilterChips

                        // ملخص سريع
                        notificationSummaryBar

                        notificationsList
                    }

                    // شريط أسفل وضع التحديد
                    if isSelecting {
                        selectionBar
                    }
                }
            }
            .navigationTitle(L10n.t("الإشعارات", "Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                isSelecting = false
                                selectedIds.removeAll()
                            }
                        } label: {
                            Text(L10n.t("إلغاء", "Cancel"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.error)
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(22, weight: .medium))
                                .foregroundStyle(DS.Color.textTertiary)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }

                if !authVM.notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                if isSelecting {
                                    let allIds = Set(filteredNotifications.map(\.id))
                                    if selectedIds == allIds {
                                        selectedIds.removeAll()
                                    } else {
                                        selectedIds = allIds
                                    }
                                } else {
                                    isSelecting = true
                                    selectedIds.removeAll()
                                }
                            }
                        } label: {
                            if isSelecting {
                                let allIds = Set(filteredNotifications.map(\.id))
                                let allSelected = !allIds.isEmpty && selectedIds == allIds
                                Image(systemName: allSelected ? "checkmark.circle.fill" : "checklist")
                                    .font(DS.Font.scaled(20, weight: .medium))
                                    .foregroundStyle(DS.Color.primary)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(DS.Font.scaled(20, weight: .medium))
                                    .foregroundStyle(DS.Color.primary)
                            }
                        }
                    }
                }
            }
            .task { await authVM.fetchNotifications() }
            .onAppear {
                withAnimation(DS.Anim.smooth.delay(0.15)) {
                    appeared = true
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $selectedNotification) { notification in
            notificationDetailSheet(notification)
        }
    }

    // MARK: - Notification Detail Sheet
    private func notificationDetailSheet(_ notification: AppNotification) -> some View {
        let iconInfo = notificationIcon(for: notification.kind)

        return NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(iconInfo.color.opacity(0.08))
                                .frame(width: 100, height: 100)
                            Circle()
                                .fill(iconInfo.color.opacity(0.12))
                                .frame(width: 76, height: 76)
                            Circle()
                                .fill(iconInfo.gradient)
                                .frame(width: 56, height: 56)
                            Image(systemName: iconInfo.icon)
                                .font(DS.Font.scaled(24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, DS.Spacing.xl)

                        // Kind badge
                        Text(kindLabel(for: notification.kind))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(iconInfo.color)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(iconInfo.color.opacity(0.12))
                            .clipShape(Capsule())

                        // Title
                        Text(notification.title)
                            .font(DS.Font.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.lg)

                        // Body
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                Text(cleanBody(notification.body))
                                    .font(DS.Font.body)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DS.Spacing.lg)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Info rows
                        VStack(spacing: DS.Spacing.md) {
                            // Created by
                            if let creatorName = createdByName(for: notification) {
                                DSCard {
                                    HStack(spacing: DS.Spacing.md) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [DS.Color.warning.opacity(0.2), DS.Color.warning.opacity(0.08)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "person.fill")
                                                .font(DS.Font.scaled(16, weight: .semibold))
                                                .foregroundColor(DS.Color.warning)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(L10n.t("بواسطة", "By"))
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textSecondary)
                                            Text(creatorName)
                                                .font(DS.Font.calloutBold)
                                                .foregroundColor(DS.Color.textPrimary)
                                        }
                                        Spacer()
                                    }
                                    .padding(DS.Spacing.lg)
                                }
                            }

                            // Time
                            DSCard {
                                HStack(spacing: DS.Spacing.md) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [DS.Color.textTertiary.opacity(0.2), DS.Color.textTertiary.opacity(0.08)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "clock")
                                            .font(DS.Font.scaled(16, weight: .semibold))
                                            .foregroundColor(DS.Color.textTertiary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.t("الوقت", "Time"))
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textSecondary)
                                        Text(relativeTime(notification.createdDate))
                                            .font(DS.Font.calloutBold)
                                            .foregroundColor(DS.Color.textPrimary)
                                    }
                                    Spacer()
                                }
                                .padding(DS.Spacing.lg)
                            }
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        let id = notification.id
                        selectedNotification = nil
                        Task { await authVM.deleteNotification(id: id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(DS.Font.scaled(16, weight: .medium))
                            .foregroundStyle(DS.Color.error)
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Selection Bar
    private var selectionBar: some View {
        HStack(spacing: DS.Spacing.md) {
            // عدد المحدد
            Text(L10n.t("محدد: \(selectedIds.count)", "Selected: \(selectedIds.count)"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)

            Spacer()

            // زر حذف المحدد
            Button {
                let ids = selectedIds
                withAnimation(DS.Anim.snappy) {
                    selectedIds.removeAll()
                    isSelecting = false
                }
                Task { await authVM.deleteNotifications(ids: ids) }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "trash.fill")
                        .font(DS.Font.scaled(13, weight: .semibold))
                    Text(L10n.t("حذف", "Delete"))
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(selectedIds.isEmpty ? Color.gray : DS.Color.error)
                .clipShape(Capsule())
            }
            .disabled(selectedIds.isEmpty)

            // زر جعل المحدد مقروء
            Button {
                let ids = selectedIds
                withAnimation(DS.Anim.snappy) {
                    selectedIds.removeAll()
                    isSelecting = false
                }
                Task { await authVM.markNotificationsAsRead(ids: ids) }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "envelope.open.fill")
                        .font(DS.Font.scaled(13, weight: .semibold))
                    Text(L10n.t("مقروء", "Read"))
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(selectedIds.isEmpty ? Color.gray : DS.Color.primary)
                .clipShape(Capsule())
            }
            .disabled(selectedIds.isEmpty)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.15))
                .frame(height: 0.5)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Kind Grouping (دمج الأنواع المتشابهة)
    private func kindGroup(for kind: String) -> String {
        switch kind {
        case "news", "news_add": return "news"
        case "admin", "admin_request": return "admin"
        case "approval", "join_approved": return "approval"
        default: return kind
        }
    }

    // MARK: - Filtered Notifications
    private var filteredNotifications: [AppNotification] {
        guard let kind = filterKind else { return authVM.notifications }
        return authVM.notifications.filter { kindGroup(for: $0.kind) == kind }
    }

    // MARK: - إحصائية سريعة
    private var notificationSummaryBar: some View {
        let unreadCount = filteredNotifications.filter { !$0.read }.count
        return Group {
            if unreadCount > 0 {
                HStack(spacing: DS.Spacing.sm) {
                    Circle()
                        .fill(DS.Color.error)
                        .frame(width: 8, height: 8)
                    Text("\(unreadCount) " + L10n.t("غير مقروء", "unread"))
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)

                    Spacer()

                    // زر جعل الكل مقروء
                    Button {
                        Task { await authVM.markAllNotificationsAsRead() }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "envelope.open.fill")
                                .font(DS.Font.scaled(11, weight: .semibold))
                            Text(L10n.t("قراءة الكل", "Read All"))
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs + 2)
                        .background(DS.Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    // MARK: - فلاتر الإشعارات
    private var notificationFilterChips: some View {
        let groupedKinds = Array(Set(authVM.notifications.map { kindGroup(for: $0.kind) })).sorted()
        return Group {
            if groupedKinds.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        // زر الكل
                        filterChip(label: L10n.t("الكل", "All"), kind: nil, count: authVM.notifications.count)

                        ForEach(groupedKinds, id: \.self) { group in
                            let count = authVM.notifications.filter { kindGroup(for: $0.kind) == group }.count
                            filterChip(label: kindLabel(for: group), kind: group, count: count)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                }
            }
        }
    }

    private func filterChip(label: String, kind: String?, count: Int) -> some View {
        let isActive = filterKind == kind
        let iconInfo: (icon: String, gradient: LinearGradient, color: Color) = kind.map { notificationIcon(for: $0) } ?? ("bell.fill", DS.Color.gradientPrimary, DS.Color.primary)

        return Button {
            withAnimation(DS.Anim.snappy) { filterKind = kind }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: iconInfo.icon)
                    .font(DS.Font.scaled(10, weight: .semibold))
                Text(label)
                    .font(DS.Font.scaled(11, weight: .semibold))
                Text("\(count)")
                    .font(DS.Font.scaled(10, weight: .black))
                    .foregroundColor(isActive ? .white.opacity(0.8) : DS.Color.textTertiary)
            }
            .foregroundColor(isActive ? .white : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(isActive ? iconInfo.color : DS.Color.surface)
            )
            .overlay(Capsule().stroke(isActive ? iconInfo.color : Color.gray.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(DS.Color.primary.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 60, height: 60)
                Image(systemName: "bell.slash.fill")
                    .font(DS.Font.scaled(26, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
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

    // MARK: - Notification Icon Helper
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
        case "weekly_digest":
            return ("list.clipboard.fill", DS.Color.gradientOcean, DS.Color.primaryDark)
        default:
            return ("bell.fill", DS.Color.gradientPrimary, DS.Color.primary)
        }
    }

    // MARK: - Clean Body (إزالة سطر "بواسطة:" من النص)
    private func cleanBody(_ body: String) -> String {
        body.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("بواسطة:") }
            .joined(separator: "\n")
    }

    // MARK: - Created By Name (للمدراء والمشرفين فقط)
    private func createdByName(for notification: AppNotification) -> String? {
        guard authVM.canModerate else { return nil }
        if let creatorId = notification.createdBy {
            if let member = authVM.member(byId: creatorId) {
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
        case "weekly_digest": return L10n.t("ملخص أسبوعي", "Weekly Digest")
        default: return L10n.t("عام", "General")
        }
    }

    // MARK: - Date Section Helper
    private func dateSection(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.t("اليوم", "Today")
        } else if calendar.isDateInYesterday(date) {
            return L10n.t("أمس", "Yesterday")
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()),
                  date >= weekAgo {
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await authVM.deleteNotification(id: item.id) }
                                } label: {
                                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if isUnread {
                                    Button {
                                        Task { await authVM.markNotificationAsRead(id: item.id) }
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
            await authVM.fetchNotifications()
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
                        selectedIds.insert(item.id)
                    }
                }
            } else {
                selectedNotification = item
                if isUnread {
                    Task { await authVM.markNotificationAsRead(id: item.id) }
                }
            }
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // Checkbox في وضع التحديد
                if isSelecting {
                    let isSelected = selectedIds.contains(item.id)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(DS.Font.scaled(22, weight: .medium))
                        .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.textTertiary)
                        .padding(.top, 12)
                        .animation(DS.Anim.snappy, value: isSelected)
                }

                // Icon
                ZStack {
                    Circle()
                        .fill(isUnread ? iconInfo.gradient : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)

                    Image(systemName: iconInfo.icon)
                        .font(DS.Font.scaled(18, weight: .bold))
                        .foregroundColor(isUnread ? .white : DS.Color.textTertiary)

                    // Unread indicator
                    if isUnread {
                        Circle()
                            .fill(DS.Color.error)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(DS.Color.surface, lineWidth: 2.5))
                            .offset(x: 16, y: -16)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    // Title + Kind badge
                    HStack(alignment: .center, spacing: DS.Spacing.sm) {
                        Text(item.title)
                            .font(isUnread ? DS.Font.headline : DS.Font.callout)
                            .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        // Kind badge
                        Text(kindLabel(for: item.kind))
                            .font(DS.Font.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(isUnread ? iconInfo.color : DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 3)
                            .background((isUnread ? iconInfo.color : Color.gray).opacity(0.10))
                            .clipShape(Capsule())
                    }

                    // Body — محدود السطور مع cleanBody
                    Text(cleanBody(item.body))
                        .font(DS.Font.subheadline)
                        .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Created by (للمدراء والمشرفين فقط)
                    if let creatorName = createdByName(for: item) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.fill")
                                .font(DS.Font.scaled(10))
                            Text(L10n.t("بواسطة: \(creatorName)", "By: \(creatorName)"))
                                .font(DS.Font.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(DS.Color.warning)
                        .padding(.top, 1)
                    }

                    // Time
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(DS.Font.scaled(10))
                        Text(relativeTime(item.createdDate))
                            .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.top, 2)
                }
            }
            .padding(DS.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(isUnread ? DS.Color.surface : DS.Color.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(isUnread ? iconInfo.color.opacity(0.15) : Color.gray.opacity(0.08), lineWidth: isUnread ? 1.2 : 0.8)
            )
            .shadow(color: isUnread ? iconInfo.color.opacity(0.08) : .clear, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(DSScaleButtonStyle())
        .contextMenu {
            if isUnread {
                Button {
                    Task { await authVM.markNotificationAsRead(id: item.id) }
                } label: {
                    Label(L10n.t("تعليم كمقروء", "Mark as Read"), systemImage: "envelope.open")
                }
            }

            Button(role: .destructive) {
                Task { await authVM.deleteNotification(id: item.id) }
            } label: {
                Label(L10n.t("حذف", "Delete"), systemImage: "trash")
            }
        }
    }
}
