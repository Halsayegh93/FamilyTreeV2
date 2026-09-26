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

    /// تغييرات المحتوى (أخبار، صور، ديوانيات، مشاريع)
    private static let contentKinds: Set<String> = [
        NotificationKind.newsPublished.rawValue,
        "news_deleted",
        NotificationKind.galleryApproved.rawValue,
        NotificationKind.galleryRejected.rawValue,
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
        // تفاصيل الحركة — مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك ٢٠٢٦-٠٩-٢٦)
        .dsCenterBox(item: $detailItem) { item in
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

// MARK: - مربّع تفاصيل الحركة

/// تفاصيل سجل واحد: من نفّذها، على مَن، متى بالضبط، وكل ما تغيّر.
/// مربّع عرض بنفس تصميم المربّعات (طلب المالك ٢٠٢٦-٠٩-٢٦): رأس بلون نوع الحركة،
/// أقسام تدخل تباعاً، و«إغلاق» أسفل المربّع.
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

    private var changes: [AppNotification.NotificationDetails.ChangeEntry] {
        item.details?.changes ?? []
    }

    /// لون الرأس — درجة داكنة من لون نوع الحركة حتى يُقرأ النص الأبيض (مثل بقية المربّعات)
    private var headerTint: Color {
        let c = style.color
        if c == DS.Color.error { return DS.Color.error }
        if c == DS.Color.textSecondary { return DS.Color.textSecondary }
        if c == DS.Color.success { return DS.Color.composerProject }
        if c == DS.Color.warning || c == DS.Color.accent { return DS.Color.composerLibrary }
        return DS.Color.actionNavy
    }

    /// تصنيف الحركة — بأيقونة قائمة التصفية ولونها نفسهما
    private var category: AdminActivityLogView.ActivityFilter? {
        AdminActivityLogView.ActivityFilter.allCases.first { $0.title == categoryTitle }
    }

    /// ترتيب دخول الأقسام تباعاً — حسب الأقسام الظاهرة فعلاً
    private var bodyIndex: Int { changes.isEmpty ? 0 : 1 }
    private var infoIndex: Int { bodyIndex + (item.body.isEmpty ? 0 : 1) }

    var body: some View {
        DSComposer(
            title: item.title,
            subtitle: categoryTitle,
            icon: style.icon,
            tint: headerTint,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            // «ما تغيّر» — سبب فتح السجل، فيتصدّر
            if !changes.isEmpty { changesSection }
            if !item.body.isEmpty { bodySection }
            infoSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var changesSection: some View {
        DSComposerSection(title: L10n.t("ما تغيّر", "What changed"), icon: "arrow.left.arrow.right",
                          tint: DS.Color.accent, trailing: "\(changes.count)", index: 0) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(changes) { ch in changeLine(ch) }
            }
        }
    }

    private var bodySection: some View {
        DSComposerSection(title: L10n.t("التفاصيل", "Details"), icon: "text.alignright",
                          tint: DS.Color.primary, index: bodyIndex) {
            Text(item.body)
                .font(DS.Font.plex(14))
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsRowBox()
        }
    }

    /// معلومات السجل — كل الحقول ظاهرة بصفوف موحّدة
    private var infoSection: some View {
        DSComposerSection(title: L10n.t("معلومات السجل", "Record info"), icon: "info.circle.fill",
                          tint: DS.Color.textSecondary, index: infoIndex) {
            VStack(spacing: DS.Spacing.sm) {
                infoRow(icon: category?.icon ?? "square.grid.2x2.fill",
                        tint: category?.color ?? DS.Color.accent,
                        L10n.t("التصنيف", "Category"), categoryTitle)
                infoRow(icon: "calendar.badge.clock", tint: DS.Color.warning,
                        L10n.t("الوقت", "Time"), fullDate)
                if let subject {
                    infoRow(icon: "person.fill", tint: DS.Color.primary,
                            L10n.t("تخصّ", "About"), subject.shortFullName)
                }
                if let actor {
                    infoRow(icon: "person.fill.checkmark", tint: DS.Color.success,
                            L10n.t("نفّذها", "By"), actor.shortFullName)
                }
            }
        }
    }

    /// صف معلومة: أيقونة الحقل + العنوان الغامق + القيمة — نفس صفوف المربّعات
    private func infoRow(icon: String, tint: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(value)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «العنوان، القيمة» عنصراً واحداً
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
            .accessibilityHidden(true)   // المصغّرة للعين — «قبل/بعد» يُقرأ من النص تحتها

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
        // صف بنفس صفوف المربّعات: أيقونة الحقل + اسم الحقل + القيمة قبل ← بعد
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: isPhoto ? "photo.fill" : "pencil", tint: DS.Color.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(AppNotification.NotificationDetails.localizedFieldName(ch.field))
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)

                if isPhoto {
                    // الصور تُعرض فعلاً — النص «صورة ← صورة» كان بلا فائدة
                    HStack(spacing: DS.Spacing.md) {
                        photoThumb(ch.before, label: L10n.t("قبل", "Before"), faded: true)
                        Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .accessibilityHidden(true)
                        photoThumb(ch.after, label: L10n.t("بعد", "After"), faded: false)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(display(ch.before))
                            .font(DS.Font.plex(13))
                            .foregroundColor(DS.Color.textTertiary)
                            .strikethrough(true, color: DS.Color.textTertiary.opacity(0.6))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .accessibilityHidden(true)
                        Text(display(ch.after))
                            .font(DS.Font.plex(13, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    // الشطب والسهم لا يُسمعان — القارئ الصوتي يقرأ «قبل: … بعد: …»
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.t("قبل: \(display(ch.before))، بعد: \(display(ch.after))",
                                               "Before: \(display(ch.before)), after: \(display(ch.after))"))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }
}
