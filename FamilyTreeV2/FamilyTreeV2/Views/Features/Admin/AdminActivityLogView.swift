import SwiftUI

/// سجل النشاط — قسم إداري مستقل يعرض **كل حركة أو تغيير** في التطبيق:
/// تعديلات الأعضاء، الموافقات والرفض، نشر/حذف المحتوى، وتغيّرات النظام.
/// انتقل هنا من تبويب «المستجدات» في مركز الإشعارات (طلب المالك)، فصار
/// مركز الإشعارات مخصّصاً لإشعارات العضو نفسه، وهذا السجل للإدارة فقط.
///
/// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بلون بلاطة «سجل النشاط»
/// في لوحة الإدارة وأرقامها الحيّة ← بحث + فلاتر التصنيفات بعددها ← قائمة واحدة بلا تقسيم
/// حسب اليوم (طلب المالك) بصفوف `.dsRowBox()` داخل `List` (بقيت لأجل السحب للحذف والسحب
/// للتحديث). التحديد المتعدد والحذف وتأكيده ومربّع التفاصيل كما كانت تماماً.
struct AdminActivityLogView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var filter: ActivityFilter = .all
    @State private var searchText = ""
    /// وضع التحديد المتعدد + الحذف
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    /// السجل المفتوح في شيت التفاصيل
    @State private var detailItem: AppNotification?
    /// اكتمل أول جلب — قبله «—» في الأرقام وبطاقة تحميل (إن لم يكن هناك سجل محمّل أصلاً)
    @State private var hasLoaded = false
    /// آخر جلب انتهى والجهاز غير متصل — لبطاقة «تعذّر التحميل» بدل «لا توجد حركة» المضلِّلة
    /// (تبقى حتى جلب ناجح: السحب للتحديث أو «إعادة المحاولة»)
    @State private var lastFetchOffline = false
    /// دخول الصفوف مرة واحدة عند فتح الصفحة
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// لون بلاطة «سجل النشاط» في لوحة الإدارة — رأس الصفحة يطابق البلاطة التي ضُغطت
    private let pageTint = DS.Color.actionNavy

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

    /// عدد الحركات في كل تصنيف (نفس أعداد قائمة التصفية السابقة) — مرور واحد على السجل
    private var filterCounts: [ActivityFilter: Int] {
        var counts: [ActivityFilter: Int] = [:]
        for n in activityItems {
            for f in ActivityFilter.allCases where matches(n, f) {
                counts[f, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - حالة التحميل

    /// أول تحميل ولا سجل محمّل بعد
    private var isInitialLoading: Bool {
        !hasLoaded && activityItems.isEmpty
    }

    /// الجلب انتهى بلا سجل والجهاز غير متصل — القائمة الفارغة هنا ليست «لا توجد حركة»
    private var loadFailed: Bool {
        hasLoaded && activityItems.isEmpty && lastFetchOffline
    }

    /// نفس الجلب السابق تماماً (`fetchNotifications(force: true)`) — ويحفظ هل انتهى بلا اتصال
    private func fetchLog() async {
        await notificationVM.fetchNotifications(force: true)
        lastFetchOffline = !NetworkMonitor.shared.isConnected
    }

    // MARK: - Body

    // قائمة واحدة بلا تقسيم «اليوم / هذا الأسبوع / أقدم» (طلب المالك)، وصف واحد لكل حركة
    // (أيقونة · عنوان · سطر · وقت). التفاصيل (قبل ← بعد) في المربّع عند الضغط.
    var body: some View {
        let counts = filterCounts

        return ZStack {
            DS.Color.background.ignoresSafeArea()

            // بطاقة الرأس ← البحث والفلاتر ← الحركات: قائمة واحدة تتمرّر معاً
            // (بقيت `List` لأجل السحب للحذف والسحب للتحديث — والسحب للتحديث يعمل حتى والسجل فارغ)
            List {
                heroSection(counts: counts)
                    .activityListRow(top: DS.Spacing.sm, bottom: DS.Spacing.sm)

                listContent(counts: counts)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .navigationTitle(L10n.t("سجل النشاط", "Activity Log"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .toolbar {
            // البحث والتصفية صارا تحت بطاقة الرأس (حقل بحث + فلاتر بعددها) — والتحديد باقٍ هنا
            ToolbarItem(placement: .topBarTrailing) {
                // لا تحديد والسجل فارغ (يبقى ظاهراً أثناء التحديد ليُلغى)
                if isSelecting || !activityItems.isEmpty {
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
        .task {
            await fetchLog()
            withAnimation(reduceMotion ? nil : DS.Anim.smooth) { hasLoaded = true }
        }
        .refreshable { await fetchLog() }
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

    /// الصفوف تدخل بعد أقسام الصفحة فوقها (البحث والفلاتر ← العنوان = ٢)، فيبقى التسلسل:
    /// الرأس ← الأقسام ← الصفوف. مرة واحدة؛ «تقليل الحركة»: تلاشٍ فوري بلا انتظار.
    private func startRowsCascade() {
        guard !appeared else { return }
        guard !reduceMotion else { appeared = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.staggerDelay(3, base: DSMotion.sectionsOnPage)) {
            appeared = true
        }
    }

    // MARK: - محتوى القائمة

    @ViewBuilder
    private func listContent(counts: [ActivityFilter: Int]) -> some View {
        if isInitialLoading {
            SysStateCard(icon: "clock.arrow.circlepath",
                         title: L10n.t("جارٍ تحميل السجل…", "Loading the log…"),
                         tint: pageTint,
                         isLoading: true)
                .padding(.top, DS.Spacing.xs)
                .dsStaggerIn(1)
                .activityListRow()
        } else if loadFailed {
            SysStateCard(icon: "wifi.exclamationmark",
                         title: L10n.t("تعذّر تحميل السجل", "Couldn't load the log"),
                         hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                         action: { Task { await fetchLog() } })
                .padding(.top, DS.Spacing.xs)
                .dsStaggerIn(1)
                .activityListRow()
        } else if activityItems.isEmpty {
            SysStateCard(icon: "clock.arrow.circlepath",
                         title: L10n.t("لا توجد حركة بعد", "No activity yet"),
                         hint: L10n.t("كل حركة أو تغيير في التطبيق يظهر هنا", "Every change in the app shows up here"),
                         tint: pageTint)
                .padding(.top, DS.Spacing.xs)
                .dsStaggerIn(1)
                .activityListRow()
        } else {
            let items = filteredItems

            DSSearchField(text: $searchText,
                          placeholder: L10n.t("ابحث في السجل…", "Search the log…"),
                          tint: pageTint)
                .dsStaggerIn(1)
                .activityListRow(top: DS.Spacing.xs, bottom: 2)

            filterChips(counts)
                .dsStaggerIn(1)
                .activityListRow(top: 0, bottom: 0)

            if isSelecting {
                selectionBar
                    .activityListRow(top: DS.Spacing.xs, bottom: 2)
            }

            // عنوان التصفية المختارة + عدد ما يظهر منها
            SysSectionTitle(title: filter == .all ? L10n.t("كل الحركات", "All activity") : filter.title,
                            icon: filter.icon,
                            tint: filter.color,
                            trailing: items.isEmpty ? nil : L10n.t("\(items.count) حركة", "\(items.count) entries"))
                .dsStaggerIn(2)
                // العنوان يظهر مع الصفوف (بعد التحميل) — فتبدأ الصفوف بعده
                .onAppear(perform: startRowsCascade)
                .activityListRow(top: DS.Spacing.xs, bottom: 2)

            if items.isEmpty {
                noResultsState
                    .padding(.top, DS.Spacing.xs)
                    .activityListRow()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    activityRow(item)
                        // نمط الأخبار والديوانيات: أول ٧ تصعد تباعاً، وما يُبنى بالتمرير يظهر مباشرة
                        .dsCardCascade(index, appeared: appeared)
                        .activityListRow()
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
    }

    // MARK: - بطاقة الرأس

    private func heroSection(counts: [ActivityFilter: Int]) -> some View {
        DSPageHero(
            title: L10n.t("سجل النشاط", "Activity Log"),
            subtitle: L10n.t("كل حركة وتغيير في التطبيق — اضغط أي حركة لتفاصيلها",
                             "Every change in the app — tap an entry for its details"),
            icon: "clock.arrow.circlepath",
            tint: pageTint,
            stats: heroStats(counts: counts)
        )
    }

    /// ٣ أرقام حيّة من السجل المحمّل أصلاً (بلا طلبات جديدة للسيرفر): حركة اليوم، من نفّذ حركات
    /// هذا الأسبوع (بلا تكرار)، والتصنيف الأكثر حركة — «—» قبل اكتمال أول تحميل.
    private func heroStats(counts: [ActivityFilter: Int]) -> [DSHeroStat] {
        let todayLabel = L10n.t("حركة اليوم", "Today")
        let weekLabel = L10n.t("نشطون هذا الأسبوع", "Active this week")
        let topLabel = L10n.t("الأكثر", "Most common")

        guard !isInitialLoading, !loadFailed else {
            return [
                DSHeroStat(value: "—", label: todayLabel, icon: "clock.fill"),
                DSHeroStat(value: "—", label: weekLabel, icon: "person.2.fill"),
                DSHeroStat(value: "—", label: topLabel, icon: "chart.bar.fill")
            ]
        }

        let calendar = Calendar.current
        let now = Date()
        var today = 0
        var actors = Set<UUID>()
        for n in activityItems {
            let date = n.createdDate
            if calendar.isDateInToday(date) { today += 1 }
            if let by = n.createdBy, calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                actors.insert(by)
            }
        }

        // الأكثر حركة — عند التساوي يبقى الأسبق بترتيب الفلاتر
        var top: ActivityFilter? = nil
        var topCount = 0
        for f in ActivityFilter.allCases where f != .all && (counts[f] ?? 0) > topCount {
            top = f
            topCount = counts[f] ?? 0
        }

        let topStat: DSHeroStat
        if let top {
            topStat = DSHeroStat(value: "\(topCount)",
                                 label: L10n.t("الأكثر: \(top.title)", "Top: \(top.title)"),
                                 icon: top.icon)
        } else {
            topStat = DSHeroStat(value: "—", label: topLabel, icon: "chart.bar.fill")
        }

        return [
            DSHeroStat(value: "\(today)", label: todayLabel, icon: "clock.fill"),
            DSHeroStat(value: "\(actors.count)", label: weekLabel, icon: "person.2.fill"),
            topStat
        ]
    }

    // MARK: - الفلاتر

    /// نفس تصنيفات قائمة التصفية السابقة — العدد يظهر فقط إذا أكبر من صفر
    private func filterChips(_ counts: [ActivityFilter: Int]) -> some View {
        DSFilterChips(
            options: ActivityFilter.allCases.map { f in
                let n = counts[f] ?? 0
                return DSFilterOption(id: f, title: f.title, icon: f.icon, count: n > 0 ? n : nil)
            },
            selection: $filter,
            tint: pageTint
        )
    }

    /// لا نتيجة للبحث أو للتصنيف — زر يرجع لـ«الكل» (مثل شارة التصفية السابقة)
    private var noResultsState: some View {
        let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return SysStateCard(
            icon: searching ? "magnifyingglass" : filter.icon,
            title: searching ? L10n.t("لا توجد نتائج", "No results")
                             : L10n.t("لا توجد حركة بعد", "No activity yet"),
            hint: searching ? L10n.t("جرّب كلمة أخرى", "Try another word")
                            : L10n.t("لا حركة في «\(filter.title)» الآن", "Nothing in \(filter.title) right now"),
            tint: DS.Color.textTertiary,
            actionTitle: filter == .all ? nil : L10n.t("عرض الكل", "Show all"),
            actionIcon: ActivityFilter.all.icon,
            action: showAllAction
        )
    }

    private var showAllAction: (() -> Void)? {
        guard filter != .all else { return nil }
        return {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { filter = .all }
        }
    }

    // MARK: - شريط التحديد

    /// شريط التحديد: تحديد الكل · العدد · حذف
    private var selectionBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.Anim.quick) {
                    let all = Set(filteredItems.map(\.id))
                    selectedIds = (selectedIds == all) ? [] : all
                }
            } label: {
                selectionCapsule(icon: "checkmark.circle.fill",
                                 title: L10n.t("تحديد الكل", "Select all"),
                                 tint: DS.Color.primary)
            }
            .buttonStyle(.plain)

            Text(L10n.t("\(selectedIds.count) محدّد", "\(selectedIds.count) selected"))
                .font(DS.Font.plex(12, weight: .semibold))
                .foregroundColor(DS.Color.fieldValue)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Button {
                showDeleteConfirm = true
            } label: {
                selectionCapsule(icon: "trash.fill",
                                 title: L10n.t("حذف", "Delete"),
                                 tint: DS.Color.error,
                                 busy: isDeleting)
            }
            .buttonStyle(.plain)
            .disabled(selectedIds.isEmpty || isDeleting)
            .opacity(selectedIds.isEmpty ? 0.45 : 1)
        }
        .dsRowBox()
    }

    /// كبسولة شريط التحديد — مساحة ضغط ٤٤ نقطة والشكل كما هو
    private func selectionCapsule(icon: String, title: String, tint: Color, busy: Bool = false) -> some View {
        HStack(spacing: 4) {
            if busy {
                ProgressView().tint(tint).scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(DS.Font.plex(12, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 30)
        .background(tint.opacity(0.10), in: Capsule())
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .padding(.vertical, -7)
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

    /// صف بإطار صفوف المربّعات: أيقونة نوع الحركة (ونقطة «جديد» على ركنها) + العنوان
    /// (Plex 13.5 عريض) + سطر التفاصيل (Plex 12) + شارة الوقت. التفاصيل (قبل ← بعد) في المربّع.
    private func activityRow(_ item: AppNotification) -> some View {
        let style = rowStyle(for: item.kind)
        let isNew = !item.read
        let picked = selectedIds.contains(item.id)
        return HStack(spacing: DS.Spacing.sm) {
            if isSelecting {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.scaled(20))
                    .foregroundColor(picked ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }

            rowIcon(style: style, isNew: isNew)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // الوقت — كحلي للحركة الجديدة، رمادي لما قُرئ
            SysStatusChip(text: relativeTime(item.createdDate),
                          tint: isNew ? DS.Color.primary : DS.Color.textTertiary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .overlay {
            if isSelecting && picked {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(0.55), lineWidth: 1.5)
            }
        }
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
        .accessibilityElement(children: .combine)
        .accessibilityValue(isNew ? L10n.t("جديد", "New") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelecting && picked ? .isSelected : [])
    }

    /// أيقونة نوع الحركة — نقطة «جديد» صغيرة على ركنها بدل الكبسولة
    private func rowIcon(style: (icon: String, color: Color), isNew: Bool) -> some View {
        DSFieldIcon(name: style.icon, tint: style.color)
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Circle()
                        .fill(DS.Color.primary)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 1.5))
                        .offset(x: L10n.isArabic ? -3 : 3, y: -3)
                }
            }
            .accessibilityHidden(true)
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
}

// MARK: - صف القائمة الشفاف (نمط صفحات الإدارة)

private extension View {
    /// صف بلا خلفية ولا فاصل، بهوامش الصفحة — المحتوى نفسه يرسم صندوقه
    func activityListRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: DS.Spacing.lg, bottom: bottom, trailing: DS.Spacing.lg))
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
