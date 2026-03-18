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

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: 0) {
                if notificationVM.notifications.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    // شريط العمليات (تحديد أو ملخص)
                    if isSelecting {
                        selectionBar
                    } else {
                        notificationSummaryBar
                    }

                    notificationsList
                }
            }
        }
        .navigationTitle(L10n.t("الإشعارات", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
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
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await notificationVM.fetchNotifications(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DS.Font.scaled(16, weight: .medium))
                        .foregroundStyle(DS.Color.primary)
                }
            }

            if !notificationVM.notifications.isEmpty {
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

    // MARK: - Notification Detail Sheet (Push-notification style)
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
                            // Header: icon + kind + time
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

                            // Title
                            Text(notification.title)
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)

                            Spacer().frame(height: DS.Spacing.sm)

                            // Body
                            Text(cleanBody(notification.body))
                                .font(DS.Font.scaled(15, weight: .regular))
                                .foregroundColor(DS.Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DS.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
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

                            if let creatorName = createdByName(for: notification) {
                                detailDivider
                                detailInfoRow(
                                    icon: "person.fill",
                                    label: L10n.t("بواسطة", "By"),
                                    value: creatorName,
                                    color: DS.Color.warning
                                )
                            }

                            if authVM.canModerate {
                                detailDivider
                                detailInfoRow(
                                    icon: "tag.fill",
                                    label: L10n.t("التصنيف", "Category"),
                                    value: kindLabel(for: notification.kind) + " (\(notification.kind))",
                                    color: DS.Color.accent
                                )

                                detailDivider
                                detailInfoRow(
                                    icon: "number",
                                    label: L10n.t("رقم الإشعار", "Notification #"),
                                    value: notification.id.uuidString.lowercased(),
                                    color: DS.Color.textTertiary
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
                                    Task { await notificationVM.markNotificationAsRead(id: notification.id) }
                                    selectedNotification = nil
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

    // MARK: - Selection Bar
    private var selectionBar: some View {
        VStack(spacing: DS.Spacing.xs) {
            // الأزرار على اليمين
            HStack(spacing: DS.Spacing.sm) {
                // زر قراءة الكل
                Button {
                    Task { await notificationVM.markAllNotificationsAsRead() }
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

                // زر جعل المحدد مقروء
                Button {
                    let ids = selectedIds
                    withAnimation(DS.Anim.snappy) {
                        selectedIds.removeAll()
                        isSelecting = false
                    }
                    Task { await notificationVM.markNotificationsAsRead(ids: ids) }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                        Text(L10n.t("مقروء", "Read"))
                            .font(DS.Font.scaled(11, weight: .bold))
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs + 2)
                    .background(selectedIds.isEmpty ? DS.Color.inactive : DS.Color.primary)
                    .clipShape(Capsule())
                }
                .disabled(selectedIds.isEmpty)

                // زر حذف المحدد
                Button {
                    let ids = selectedIds
                    withAnimation(DS.Anim.snappy) {
                        selectedIds.removeAll()
                        isSelecting = false
                    }
                    Task { await notificationVM.deleteNotifications(ids: ids) }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "trash.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                        Text(L10n.t("حذف", "Delete"))
                            .font(DS.Font.scaled(11, weight: .bold))
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs + 2)
                    .background(selectedIds.isEmpty ? DS.Color.inactive : DS.Color.error)
                    .clipShape(Capsule())
                }
                .disabled(selectedIds.isEmpty)

                Spacer()
            }

            // عدد المحدد تحت الأزرار
            HStack {
                Text(L10n.t("محدد: \(selectedIds.count)", "Selected: \(selectedIds.count)"))
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                Spacer()
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.15))
                .frame(height: 0.5)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Filtered Notifications
    /// المدراء والمشرفون يشوفون كل الإشعارات، الأعضاء العاديون يشوفون فقط الموجهة لهم
    /// أنواع الإشعارات المخفية حسب إعدادات المستخدم
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
        // تطبيق إعدادات الخصوصية
        if hiddenKinds.isEmpty { return base }
        return base.filter { !hiddenKinds.contains($0.kind) }
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
                        Task { await notificationVM.markAllNotificationsAsRead() }
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
                .padding(.vertical, DS.Spacing.xs)
            }
        }
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
                    .foregroundColor(DS.Color.textOnPrimary)
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
        case "role_change": return L10n.t("تغيير رتبة", "Role Change")
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
                                    Task { await notificationVM.deleteNotification(id: item.id) }
                                } label: {
                                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if isUnread {
                                    Button {
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

    // MARK: - Notification Row (Push-notification style)
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
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
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
                        .padding(.top, DS.Spacing.md)
                        .animation(DS.Anim.snappy, value: isSelected)
                }

                VStack(alignment: .leading, spacing: 0) {
                    // ── Header row: icon + app name + kind + time ──
                    HStack(spacing: DS.Spacing.sm) {
                        // App-style small icon (like iOS push notifications)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isUnread ? iconInfo.gradient : LinearGradient(colors: [DS.Color.textTertiary.opacity(0.3), DS.Color.textTertiary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: iconInfo.icon)
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(isUnread ? .white : DS.Color.textTertiary)
                            )

                        Text(kindLabel(for: item.kind))
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(isUnread ? DS.Color.textSecondary : DS.Color.textTertiary)

                        Spacer(minLength: 0)

                        Text(relativeTime(item.createdDate))
                            .font(DS.Font.scaled(12, weight: .regular))
                            .foregroundColor(DS.Color.textTertiary)

                        if isUnread {
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Spacer().frame(height: DS.Spacing.sm)

                    // ── Title ──
                    Text(item.title)
                        .font(DS.Font.scaled(15, weight: isUnread ? .semibold : .medium))
                        .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textTertiary)
                        .lineLimit(1)

                    Spacer().frame(height: 3)

                    // ── Body ──
                    Text(cleanBody(item.body))
                        .font(DS.Font.scaled(14, weight: .regular))
                        .foregroundColor(isUnread ? DS.Color.textSecondary : DS.Color.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(isUnread ? DS.Color.surface : DS.Color.surface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.textTertiary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: isUnread ? Color.black.opacity(0.06) : Color.clear, radius: 6, x: 0, y: 2)
            .opacity(isUnread ? 1 : 0.6)
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

            Button(role: .destructive) {
                Task { await notificationVM.deleteNotification(id: item.id) }
            } label: {
                Label(L10n.t("حذف", "Delete"), systemImage: "trash")
            }
        }
    }
}
