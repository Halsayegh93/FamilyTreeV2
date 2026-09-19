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
    /// السجل المفتوح في شيت التفاصيل
    @State private var detailItem: AppNotification?

    // MARK: - التصنيفات

    enum ActivityFilter: String, CaseIterable, Identifiable {
        case all, members, women, content, requests, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:     return L10n.t("الكل", "All")
            case .members: return L10n.t("الأعضاء", "Members")
            case .women:   return L10n.t("النساء", "Women")
            case .content: return L10n.t("المحتوى", "Content")
            case .requests: return L10n.t("الطلبات", "Requests")
            case .system:  return L10n.t("النظام", "System")
            }
        }
        var icon: String {
            switch self {
            case .all:     return "square.grid.2x2.fill"
            case .members: return "person.2.fill"
            case .women:   return "figure.dress.line.vertical.figure"
            case .content: return "photo.stack.fill"
            case .requests: return "tray.full.fill"
            case .system:  return "gearshape.fill"
            }
        }
        var color: Color {
            switch self {
            case .all:     return DS.Color.primary
            case .members: return DS.Color.warning
            case .women:   return DS.Color.female
            case .content: return DS.Color.info
            case .requests: return DS.Color.warning
            case .system:  return DS.Color.accent
            }
        }
    }

    /// تغييرات تخصّ الأعضاء (تعديل بيانات، حذف، أدوار، تفعيل)
    /// حركة شجرة النساء — قسم مستقلّ لا ضمن «الأعضاء»، فمصدرها جدول آخر
    /// وطبيعتها مختلفة (زوجات وبنات لا حسابات).
    private static let womenKinds: Set<String> = [
        NotificationKind.womenAdd.rawValue,
        NotificationKind.womenEdit.rawValue,
        NotificationKind.womenDelete.rawValue,
    ]

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
        NotificationKind.womenAdd.rawValue,
        NotificationKind.womenEdit.rawValue,
        NotificationKind.womenDelete.rawValue,
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

    /// طلبات الأعضاء (انضمام، ربط، تعديل شجرة…)
    private static let requestKinds: Set<String> = [
        "join_request",
        NotificationKind.linkRequest.rawValue,
        NotificationKind.treeEdit.rawValue,
        NotificationKind.childAdd.rawValue,
        NotificationKind.phoneChange.rawValue,
        NotificationKind.nameChange.rawValue,
        NotificationKind.deceasedReport.rawValue,
        NotificationKind.photoSuggestion.rawValue,
        NotificationKind.contentReport.rawValue,
        NotificationKind.newsReport.rawValue,
        NotificationKind.newsAdd.rawValue,
        NotificationKind.contactMessage.rawValue,
        NotificationKind.adminRequest.rawValue,
        NotificationKind.galleryPending.rawValue,
        NotificationKind.storyPending.rawValue,
        NotificationKind.diwaniyaPending.rawValue,
        NotificationKind.projectPending.rawValue,
    ]

    /// السجل شامل: كل حركة في التطبيق بلا استثناء (طلب المالك)
    private var activityItems: [AppNotification] {
        notificationVM.notifications
    }

    private func matchesFilter(_ n: AppNotification) -> Bool { matches(n, filter) }

    private func matches(_ n: AppNotification, _ f: ActivityFilter) -> Bool {
        switch f {
        case .all:     return true
        case .members: return Self.memberKinds.contains(n.kind)
        case .women:   return Self.womenKinds.contains(n.kind)
        case .content: return Self.contentKinds.contains(n.kind)
        case .requests: return Self.requestKinds.contains(n.kind)
        case .system:
            return !Self.memberKinds.contains(n.kind)
                && !Self.womenKinds.contains(n.kind)
                && !Self.contentKinds.contains(n.kind)
                && !Self.requestKinds.contains(n.kind)
        }
    }

    private var filteredItems: [AppNotification] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return activityItems
            .filter(matchesFilter)
            .filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) }
            .sorted { $0.createdDate > $1.createdDate }
    }

    // MARK: - Body

    // تصميم مبسّط بنفس تنسيق «صحة النظام» (طلب المالك): بطاقة واحدة بفواصل رفيعة
    // بلا تقسيم حسب اليوم، وصف واحد لكل حركة (أيقونة · عنوان · سطر · وقت). التصفية والبحث
    // والتحديد في الشريط العلوي بدل صف الكبسولات.
    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if showSearch {
                    searchField
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                }

                if isSelecting {
                    selectionBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                }

                if filteredItems.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    // List مجمّعة — بطاقات بفواصل، والسحب للحذف يعمل
                    List {
                        if filter != .all {
                            Section {
                                EmptyView()
                            } header: {
                                activeFilterChip
                            }
                        }
                        // قائمة واحدة بلا تقسيم «اليوم / هذا الأسبوع / أقدم» (طلب المالك)
                        Section {
                            ForEach(filteredItems) { item in
                                activityRow(item)
                                    .listRowBackground(DS.Color.surface)
                                    .listRowInsets(EdgeInsets(top: 10, leading: DS.Spacing.md,
                                                              bottom: 10, trailing: DS.Spacing.md))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            Task { await notificationVM.deleteNotification(id: item.id) }
                                        } label: {
                                            Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
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
                    // التصفية — قائمة بدل صف الكبسولات
                    Menu {
                        Picker(L10n.t("تصفية", "Filter"), selection: $filter) {
                            ForEach(ActivityFilter.allCases) { f in
                                let count = activityItems.filter { matches($0, f) }.count
                                Label("\(f.title) (\(count))", systemImage: f.icon).tag(f)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(DS.Color.primary)
                    }
                    .accessibilityLabel(L10n.t("تصفية", "Filter"))

                    Button {
                        withAnimation(DS.Anim.quick) { showSearch.toggle() }
                        if showSearch { searchFocused = true } else { searchText = "" }
                    } label: {
                        Image(systemName: showSearch ? "xmark.circle.fill" : "magnifyingglass")
                            .foregroundColor(DS.Color.primary)
                    }
                    .accessibilityLabel(L10n.t("بحث", "Search"))

                    Button {
                        withAnimation(DS.Anim.quick) {
                            isSelecting.toggle()
                            if !isSelecting { selectedIds.removeAll() }
                        }
                    } label: {
                        // التحديد علامة بدل النص (طلب المالك)
                        Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(DS.Color.primary)
                    }
                    .accessibilityLabel(isSelecting ? L10n.t("إلغاء التحديد", "Cancel selection")
                                                    : L10n.t("تحديد", "Select"))
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
        .sheet(item: $detailItem) { item in
            ActivityDetailSheet(
                item: item,
                style: rowStyle(for: item.kind),
                categoryTitle: categoryTitle(for: item.kind)
            )
            .environmentObject(memberVM)
        }
    }

    // MARK: - التصفية الحالية

    /// شارة التصفية الفعّالة — تظهر فقط عند اختيار غير «الكل»، والضغط يرجع للكل
    private var activeFilterChip: some View {
        Button {
            withAnimation(DS.Anim.quick) { filter = .all }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                Text(filter.title)
                    .font(DS.Font.scaled(12, weight: .bold))
                Image(systemName: "xmark")
                    .font(DS.Font.scaled(9, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 28)
            .background(Capsule().fill(filter.color))
        }
        .buttonStyle(.plain)
        .textCase(nil)
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

    // MARK: - صف الحركة

    /// صف واحد بسيط — التفاصيل (قبل ← بعد) في الشيت عند الضغط
    private func activityRow(_ item: AppNotification) -> some View {
        let style = rowStyle(for: item.kind)
        let isNew = !item.read
        let picked = selectedIds.contains(item.id)
        return HStack(spacing: DS.Spacing.md) {
            if isSelecting {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.scaled(20))
                    .foregroundColor(picked ? DS.Color.primary : DS.Color.textTertiary)
            }

            Image(systemName: style.icon)
                .font(DS.Font.scaled(15, weight: .semibold))
                .foregroundColor(style.color)
                .frame(width: 36, height: 36)
                .background(style.color.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DS.Font.plex(15, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(DS.Font.plex(12.5, weight: .regular))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.xs)

            VStack(alignment: .trailing, spacing: 4) {
                Text(relativeTime(item.createdDate))
                    .font(DS.Font.plex(11, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                // نقطة «جديد» بدل الكبسولة
                if isNew {
                    Circle().fill(DS.Color.primary).frame(width: 8, height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                withAnimation(DS.Anim.quick) {
                    if picked { selectedIds.remove(item.id) } else { selectedIds.insert(item.id) }
                }
            } else {
                detailItem = item                       // الضغط يفتح التفاصيل
                if isNew {
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
                }
            }
        }
    }

    /// اسم تصنيف الحركة (للعرض في التفاصيل)
    private func categoryTitle(for kind: String) -> String {
        if Self.memberKinds.contains(kind)   { return ActivityFilter.members.title }
        if Self.contentKinds.contains(kind)  { return ActivityFilter.content.title }
        if Self.requestKinds.contains(kind)  { return ActivityFilter.requests.title }
        return ActivityFilter.system.title
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

// MARK: - شيت تفاصيل الحركة

private struct ActivitySheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 260
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// تفاصيل سجل واحد: من نفّذها، على مَن، متى بالضبط، وكل ما تغيّر.
private struct ActivityDetailSheet: View {
    let item: AppNotification
    let style: (icon: String, color: Color)
    let categoryTitle: String

    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    /// العضو الذي تخصّه الحركة — عمود مستقل عن مستلم الإشعار
    private var subject: FamilyMember? {
        guard let id = item.subjectMemberId else { return nil }
        return memberVM.member(byId: id)
    }
    private var actor: FamilyMember? {
        guard let id = item.createdBy else { return nil }
        return memberVM.member(byId: id)
    }

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()
    private var fullDate: String {
        Self.fullFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.fullFormatter.string(from: item.createdDate)
    }

    /// ارتفاع المحتوى الفعلي — الشيت يفصّل نفسه عليه
    @State private var contentHeight: CGFloat = 260
    /// لا بدّ من ربط الاختيار: بدونه يعلق الشيت على أول ارتفاع ولا يتكيّف
    @State private var detent: PresentationDetent = .height(260)

    var body: some View {
        VStack(spacing: 0) {
            // ═══ شريط علوي ثابت بهوية نوع الحركة ═══
            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle().fill(SwiftUI.Color.white.opacity(0.20))
                        Image(systemName: style.icon)
                            .font(DS.Font.scaled(17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(DS.Font.plex(16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(categoryTitle)
                            .font(DS.Font.caption2)
                            .foregroundColor(SwiftUI.Color.white.opacity(0.85))
                    }

                    Spacer(minLength: 0)

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(SwiftUI.Color.white.opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(style.color)

            // ═══ المحتوى ═══
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {

                    // «ما تغيّر» — سبب فتح السجل، فيتصدّر
                    if let changes = item.details?.changes, !changes.isEmpty {
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("ما تغيّر", "What changed"),
                                icon: "arrow.left.arrow.right",
                                trailing: "\(changes.count)",
                                iconColor: DS.Color.accent
                            )
                            VStack(spacing: DS.Spacing.xs) {
                                ForEach(changes) { ch in changeLine(ch) }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.md)
                        }
                    }

                    if !item.body.isEmpty {
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("التفاصيل", "Details"),
                                icon: "text.alignright",
                                iconColor: DS.Color.primary
                            )
                            Text(item.body)
                                .font(DS.Font.subheadline)
                                .foregroundColor(DS.Color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.bottom, DS.Spacing.md)
                        }
                    }

                    // معلومات السجل — كل الحقول ظاهرة بصفوف موحّدة
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("معلومات السجل", "Record info"),
                            icon: "info.circle.fill",
                            iconColor: DS.Color.textSecondary
                        )
                        VStack(spacing: 0) {
                            infoRow(L10n.t("التصنيف", "Category"), categoryTitle)
                            DSDivider()
                            infoRow(L10n.t("الوقت", "Time"), fullDate)
                            if let subject {
                                DSDivider()
                                infoRow(L10n.t("تخصّ", "About"), subject.shortFullName)
                            }
                            if let actor {
                                DSDivider()
                                infoRow(L10n.t("نفّذها", "By"), actor.shortFullName)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)
                    }
                }
                .padding(DS.Spacing.lg)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: ActivitySheetHeightKey.self, value: g.size.height)
                    }
                )
            }
            .background(DS.Color.background)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onPreferenceChange(ActivitySheetHeightKey.self) { h in
            let safeBottom = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first(where: { $0.isKeyWindow })?
                .safeAreaInsets.bottom ?? 0
            // المحتوى + الشريط العلوي (76) + منطقة الأمان
            let newHeight = min(max(h + 76 + safeBottom, 240),
                                UIScreen.main.bounds.height * 0.92)
            guard abs(newHeight - contentHeight) > 1 else { return }
            contentHeight = newHeight
            withAnimation(DS.Anim.quick) { detent = .height(newHeight) }
        }
        .presentationDetents([.height(contentHeight), .large], selection: $detent)
        .presentationDragIndicator(.hidden)
    }

    /// صف معلومة داخل بطاقة «معلومات السجل»
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.sm)
            Text(value)
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(L10n.isArabic ? .leading : .trailing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.Spacing.xs + 1)
    }

    /// مصغّرة صورة داخل تفاصيل التغيير — تُظهر الصورة الفعلية قبل/بعد
    private func photoThumb(_ urlString: String?, label: String, faded: Bool) -> some View {
        let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 3) {
            Group {
                if let url = URL(string: trimmed), !trimmed.isEmpty {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(DS.Color.surface)
                    }
                } else {
                    ZStack {
                        Rectangle().fill(DS.Color.surface)
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(DS.Font.scaled(14))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
            )
            .opacity(faded ? 0.55 : 1)

            Text(label)
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
        }
    }

    private func changeLine(_ ch: AppNotification.NotificationDetails.ChangeEntry) -> some View {
        let isPhoto = ch.field == "avatar_url" || ch.field == "cover_url" || ch.field == "photo_url"
        func display(_ v: String?) -> String {
            let t = (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return L10n.t("بلا", "None") }
            return t
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text(AppNotification.NotificationDetails.localizedFieldName(ch.field))
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)

            if isPhoto {
                // الصور تُعرض فعلاً — النص «صورة ← صورة» كان بلا فائدة
                HStack(spacing: DS.Spacing.md) {
                    photoThumb(ch.before, label: L10n.t("قبل", "Before"), faded: true)
                    Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                    photoThumb(ch.after, label: L10n.t("بعد", "After"), faded: false)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    Text(display(ch.before))
                        .font(DS.Font.scaled(12))
                        .foregroundColor(DS.Color.textTertiary)
                        .strikethrough(true, color: DS.Color.textTertiary.opacity(0.6))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(display(ch.after))
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, DS.Spacing.sm)
        .background(DS.Color.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
