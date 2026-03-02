import SwiftUI

struct NotificationsCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var appeared = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var selectedNotification: AppNotification? = nil

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
                                    // تحديد الكل / إلغاء تحديد الكل
                                    let allIds = Set(authVM.notifications.map(\.id))
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
                                let allIds = Set(authVM.notifications.map(\.id))
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
            .onAppear {
                Task { await authVM.fetchNotifications() }
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

                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(iconInfo.gradient)
                                .frame(width: 72, height: 72)

                            Image(systemName: iconInfo.icon)
                                .font(DS.Font.scaled(28, weight: .bold))
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

                        // Body — full text
                        DSCard(padding: 0) {
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                Text(notification.body)
                                    .font(DS.Font.body)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DS.Spacing.lg)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Created by
                        if let creatorName = createdByName(for: notification) {
                            HStack(spacing: DS.Spacing.sm) {
                                DSIcon("person.fill", color: DS.Color.warning)
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
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Time
                        HStack(spacing: DS.Spacing.sm) {
                            DSIcon("clock", color: DS.Color.textTertiary)
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
                        .padding(.horizontal, DS.Spacing.lg)

                        Spacer()
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
                Task {
                    for id in selectedIds {
                        await authVM.deleteNotification(id: id)
                    }
                    withAnimation(DS.Anim.snappy) {
                        selectedIds.removeAll()
                        isSelecting = false
                    }
                }
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
                Task {
                    for id in selectedIds {
                        await authVM.markNotificationAsRead(id: id)
                    }
                    withAnimation(DS.Anim.snappy) {
                        selectedIds.removeAll()
                        isSelecting = false
                    }
                }
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
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 120, height: 120)
                    .opacity(0.08)

                Circle()
                    .fill(DS.Color.gradientAccent)
                    .frame(width: 88, height: 88)
                    .opacity(0.12)

                Image(systemName: "bell.slash.fill")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundStyle(DS.Color.gradientPrimary)
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
        case "news":
            return ("newspaper.fill", DS.Color.gradientPrimary, DS.Color.primary)
        case "admin":
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
        // البحث عبر created_by أولاً
        if let creatorId = notification.createdBy {
            if let member = authVM.allMembers.first(where: { $0.id == creatorId }) {
                return member.fullName
            }
            if creatorId == authVM.currentUser?.id {
                return authVM.currentUser?.fullName
            }
        }
        // استخراج الاسم من نص الإشعار إذا يحتوي سطر "بواسطة:"
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
        case "news": return L10n.t("أخبار", "News")
        case "admin": return L10n.t("إدارة", "Admin")
        case "deceased_report": return L10n.t("وفاة", "Deceased")
        case "child_add": return L10n.t("إضافة", "Addition")
        case "phone_change": return L10n.t("تغيير رقم", "Phone Change")
        case "news_report": return L10n.t("بلاغ", "Report")
        case "contact_message": return L10n.t("تواصل", "Contact")
        default: return L10n.t("عام", "General")
        }
    }

    // MARK: - Notifications List
    private var notificationsList: some View {
        List {
            ForEach(Array(authVM.notifications.enumerated()), id: \.element.id) { index, item in
                let iconInfo = notificationIcon(for: item.kind)
                let isUnread = !item.read

                notificationRow(item: item, iconInfo: iconInfo, isUnread: isUnread)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(DS.Anim.smooth.delay(Double(index) * 0.04), value: appeared)
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                    
                    // Body — كل التفاصيل
                    Text(item.body)
                        .font(DS.Font.subheadline)
                        .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textTertiary)
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
