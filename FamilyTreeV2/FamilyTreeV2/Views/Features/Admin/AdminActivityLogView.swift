import SwiftUI

/// سجل النشاط — قسم إداري مستقل يعرض **كل حركة أو تغيير** في التطبيق:
/// تعديلات الأعضاء، الموافقات والرفض، نشر/حذف المحتوى، وتغيّرات النظام.
/// انتقل هنا من تبويب «المستجدات» في مركز الإشعارات (طلب المالك)، فصار
/// مركز الإشعارات مخصّصاً لإشعارات العضو نفسه، وهذا السجل للإدارة فقط.
struct AdminActivityLogView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var filter: ActivityFilter = .all
    @State private var searchText = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    /// وضع التحديد المتعدد + الحذف
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    // MARK: - التصنيفات

    enum ActivityFilter: String, CaseIterable, Identifiable {
        case all, members, content, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:     return L10n.t("الكل", "All")
            case .members: return L10n.t("الأعضاء", "Members")
            case .content: return L10n.t("المحتوى", "Content")
            case .system:  return L10n.t("النظام", "System")
            }
        }
        var icon: String {
            switch self {
            case .all:     return "square.grid.2x2.fill"
            case .members: return "person.2.fill"
            case .content: return "photo.stack.fill"
            case .system:  return "gearshape.fill"
            }
        }
        var color: Color {
            switch self {
            case .all:     return DS.Color.primary
            case .members: return DS.Color.warning
            case .content: return DS.Color.info
            case .system:  return DS.Color.accent
            }
        }
    }

    /// تغييرات تخصّ الأعضاء (تعديل بيانات، حذف، أدوار، تفعيل)
    private static let memberKinds: Set<String> = [
        NotificationKind.adminEdit.rawValue,
        NotificationKind.adminEditName.rawValue,
        NotificationKind.adminEditDates.rawValue,
        NotificationKind.adminEditPhone.rawValue,
        NotificationKind.adminEditPhoneRemove.rawValue,
        NotificationKind.adminEditRole.rawValue,
        NotificationKind.adminEditFather.rawValue,
        NotificationKind.adminEditAvatar.rawValue,
        NotificationKind.adminEditAvatarRemove.rawValue,
        NotificationKind.adminEditChildAdd.rawValue,
        NotificationKind.adminEditChildRemove.rawValue,
        NotificationKind.memberDelete.rawValue,
        NotificationKind.joinApproved.rawValue,
        NotificationKind.accountActivated.rawValue,
        NotificationKind.roleChange.rawValue,
    ]

    /// تغييرات المحتوى (أخبار، صور، قصص، ديوانيات، مشاريع)
    private static let contentKinds: Set<String> = [
        NotificationKind.newsPublished.rawValue,
        "news_deleted",
        NotificationKind.galleryApproved.rawValue,
        NotificationKind.galleryRejected.rawValue,
        NotificationKind.storyApproved.rawValue,
        NotificationKind.storyRejected.rawValue,
        NotificationKind.diwaniyaApproved.rawValue,
        NotificationKind.diwaniyaRejected.rawValue,
        NotificationKind.projectApproved.rawValue,
        NotificationKind.projectRejected.rawValue,
    ]

    /// كل ما يُعدّ «حركة منفّذة» — لا طلبات معلّقة
    private var activityItems: [AppNotification] {
        notificationVM.notifications.filter { n in
            let isMember  = Self.memberKinds.contains(n.kind)
            let isContent = Self.contentKinds.contains(n.kind)
            let titleDone = n.title.hasPrefix("تم قبول") || n.title.hasPrefix("تم رفض")
                || n.title.contains("Approved") || n.title.contains("Rejected")
            return isMember || isContent || titleDone
        }
    }

    private func matchesFilter(_ n: AppNotification) -> Bool {
        switch filter {
        case .all:     return true
        case .members: return Self.memberKinds.contains(n.kind)
        case .content: return Self.contentKinds.contains(n.kind)
        case .system:  return !Self.memberKinds.contains(n.kind) && !Self.contentKinds.contains(n.kind)
        }
    }

    private var filteredItems: [AppNotification] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return activityItems
            .filter(matchesFilter)
            .filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) }
            .sorted { $0.createdDate > $1.createdDate }
    }

    /// تجميع حسب اليوم — نفس تقسيم مركز الإشعارات
    private func dateSection(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.t("اليوم", "Today") }
        if cal.isDateInYesterday(date) { return L10n.t("أمس", "Yesterday") }
        if let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start, date >= weekStart {
            return L10n.t("هذا الأسبوع", "This Week")
        }
        return L10n.t("أقدم", "Older")
    }

    private var grouped: [(String, [AppNotification])] {
        let dict = Dictionary(grouping: filteredItems) { dateSection(for: $0.createdDate) }
        let order = [L10n.t("اليوم", "Today"), L10n.t("أمس", "Yesterday"),
                     L10n.t("هذا الأسبوع", "This Week"), L10n.t("أقدم", "Older")]
        return order.compactMap { key in
            guard let v = dict[key], !v.isEmpty else { return nil }
            return (key, v)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar

                if showSearch {
                    searchField
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)
                }

                if isSelecting {
                    selectionBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)
                }

                if filteredItems.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    // List — ليعمل السحب للحذف (لا يعمل داخل LazyVStack)
                    List {
                        ForEach(grouped, id: \.0) { section, items in
                            Section {
                                ForEach(items) { item in
                                    activityRow(item)
                                        .listRowInsets(EdgeInsets(top: 3, leading: DS.Spacing.lg,
                                                                  bottom: 3, trailing: DS.Spacing.lg))
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                Task { await notificationVM.deleteNotification(id: item.id) }
                                            } label: {
                                                Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                                            }
                                        }
                                }
                            } header: {
                                sectionHeader(section, count: items.count)
                                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.lg,
                                                              bottom: 0, trailing: DS.Spacing.lg))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(L10n.t("سجل النشاط", "Activity Log"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: DS.Spacing.md) {
                    Button {
                        withAnimation(DS.Anim.quick) {
                            isSelecting.toggle()
                            if !isSelecting { selectedIds.removeAll() }
                        }
                    } label: {
                        Text(isSelecting ? L10n.t("إلغاء", "Cancel") : L10n.t("تحديد", "Select"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                    }

                    Button {
                        withAnimation(DS.Anim.quick) { showSearch.toggle() }
                        if showSearch { searchFocused = true } else { searchText = "" }
                    } label: {
                        Image(systemName: showSearch ? "xmark.circle.fill" : "magnifyingglass")
                            .foregroundColor(DS.Color.primary)
                    }
                    .accessibilityLabel(L10n.t("بحث", "Search"))
                }
            }
        }
        .confirmationDialog(
            L10n.t("حذف \(selectedIds.count) من السجل؟", "Delete \(selectedIds.count) entries?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await deleteSelected() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
        .task { await notificationVM.fetchNotifications(force: true) }
        .refreshable { await notificationVM.fetchNotifications(force: true) }
    }

    // MARK: - شريط التصنيفات

    private var filterBar: some View {
        // الأربعة في صف واحد بلا سحب — طلب المالك
        HStack(spacing: 5) {
            ForEach(ActivityFilter.allCases) { f in
                let active = filter == f
                let count = activityItems.filter { n in
                    switch f {
                    case .all:     return true
                    case .members: return Self.memberKinds.contains(n.kind)
                    case .content: return Self.contentKinds.contains(n.kind)
                    case .system:  return !Self.memberKinds.contains(n.kind) && !Self.contentKinds.contains(n.kind)
                    }
                }.count

                Button {
                    withAnimation(DS.Anim.quick) { filter = f }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: f.icon)
                            .font(DS.Font.scaled(8.5, weight: .bold))
                        Text(f.title)
                            .font(DS.Font.scaled(10.5, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if count > 0 {
                            Text("\(count)")
                                .font(DS.Font.scaled(9.5, weight: .heavy))
                                .opacity(0.75)
                        }
                    }
                    .foregroundColor(active ? .white : DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Capsule().fill(active ? f.color : DS.Color.surface))
                    .overlay(Capsule().stroke(DS.Color.mutedBackground, lineWidth: active ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DS.Font.scaled(13, weight: .medium))
                .foregroundColor(DS.Color.textTertiary)
            TextField(L10n.t("ابحث في السجل…", "Search the log…"), text: $searchText)
                .font(DS.Font.callout)
                .focused($searchFocused)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    /// شريط التحديد: تحديد الكل · العدد · حذف
    private var selectionBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.Anim.quick) {
                    let all = Set(filteredItems.map(\.id))
                    selectedIds = (selectedIds == all) ? [] : all
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(11, weight: .bold))
                    Text(L10n.t("تحديد الكل", "Select all"))
                        .font(DS.Font.scaled(12, weight: .bold))
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 30)
                .background(Capsule().fill(DS.Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Text(L10n.t("\(selectedIds.count) محدّد", "\(selectedIds.count) selected"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)

            Spacer(minLength: 0)

            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 4) {
                    if isDeleting {
                        ProgressView().tint(DS.Color.error).scaleEffect(0.7)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(DS.Font.scaled(11, weight: .bold))
                    }
                    Text(L10n.t("حذف", "Delete"))
                        .font(DS.Font.scaled(12, weight: .bold))
                }
                .foregroundColor(DS.Color.error)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 30)
                .background(Capsule().fill(DS.Color.error.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(selectedIds.isEmpty || isDeleting)
            .opacity(selectedIds.isEmpty ? 0.45 : 1)
        }
    }

    @MainActor
    private func deleteSelected() async {
        guard !selectedIds.isEmpty else { return }
        isDeleting = true
        await notificationVM.deleteNotifications(ids: selectedIds)
        isDeleting = false
        withAnimation(DS.Anim.quick) {
            selectedIds.removeAll()
            isSelecting = false
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
            Text("\(count)")
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.background)
    }

    // MARK: - صف الحركة

    private func activityRow(_ item: AppNotification) -> some View {
        let style = rowStyle(for: item.kind)
        let isNew = !item.read
        let picked = selectedIds.contains(item.id)
        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            if isSelecting {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.scaled(18))
                    .foregroundColor(picked ? DS.Color.primary : DS.Color.textTertiary)
                    .padding(.top, 4)
            }

            Image(systemName: style.icon)
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(style.color)
                .frame(width: 32, height: 32)
                .background(style.color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(item.title)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)

                    // شارة «جديد» — حركة لم تُقرأ بعد
                    if isNew {
                        Text(L10n.t("جديد", "New"))
                            .font(DS.Font.scaled(9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Color.primary))
                    }
                    Spacer(minLength: 0)
                }

                if !item.body.isEmpty {
                    Text(item.body)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(3)
                }

                Text(relativeTime(item.createdDate))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isNew ? DS.Color.primary.opacity(0.05) : DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(picked ? DS.Color.primary.opacity(0.5)
                                     : (isNew ? DS.Color.primary.opacity(0.18) : Color.clear),
                              lineWidth: picked ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                withAnimation(DS.Anim.quick) {
                    if picked { selectedIds.remove(item.id) } else { selectedIds.insert(item.id) }
                }
            } else if isNew {
                Task { await notificationVM.markNotificationAsRead(id: item.id) }
            }
        }
    }

    /// أيقونة ولون الصف حسب نوع الحركة (محلي — لا يعتمد على مركز الإشعارات)
    private func rowStyle(for kind: String) -> (icon: String, color: Color) {
        if Self.memberKinds.contains(kind) {
            switch kind {
            case NotificationKind.memberDelete.rawValue:
                return ("person.crop.circle.badge.minus", DS.Color.error)
            case NotificationKind.roleChange.rawValue, NotificationKind.adminEditRole.rawValue:
                return ("shield.lefthalf.filled", DS.Color.accent)
            case NotificationKind.joinApproved.rawValue, NotificationKind.accountActivated.rawValue:
                return ("person.crop.circle.badge.checkmark", DS.Color.success)
            case NotificationKind.adminEditAvatar.rawValue, NotificationKind.adminEditAvatarRemove.rawValue:
                return ("photo.circle.fill", DS.Color.info)
            default:
                return ("pencil.circle.fill", DS.Color.warning)
            }
        }
        if Self.contentKinds.contains(kind) {
            if kind.contains("news") { return ("newspaper.fill", DS.Color.info) }
            if kind.contains("gallery") { return ("photo.stack.fill", DS.Color.info) }
            if kind.contains("story") { return ("book.fill", DS.Color.accent) }
            if kind.contains("diwaniya") { return ("map.fill", DS.Color.primary) }
            if kind.contains("project") { return ("briefcase.fill", DS.Color.warning) }
            return ("doc.fill", DS.Color.info)
        }
        return ("gearshape.fill", DS.Color.textSecondary)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(DS.Font.scaled(38, weight: .regular))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد حركة بعد", "No activity yet"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
        }
    }
}
