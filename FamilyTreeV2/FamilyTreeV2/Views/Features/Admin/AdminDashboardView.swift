import SwiftUI

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
    /// «الوارد» مفتوحاً على طلب بعينه (مربّع تفاصيله)
    case inboxItem(UUID)
    /// «رسائل الدخول · KWT SMS» (إشعار «رصيد الرسائل منخفض»)
    case sms
    /// صفحة قسم (مربّعات «اليوم» وشريط الأقسام) — العدّاد يجعل كل انتقال من الشريط قيمة جديدة فيُستبدل المسار
    /// كله (حتى العودة لصفحة القسم الحالي من صفحة داخلية)
    case area(AdminArea, Int)
}

// MARK: - لوحة الإدارة ← «اليوم» (إعادة التصميم الكاملة — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// الاتجاه «أ» (مركز القيادة) أساساً + لمستان من «ب»: دوائر الإنجاز للمهام، وسحب «الوارد» مثل البريد.
// «في اردحام بلوحة الادارة بالبداية» → «الأقسام فوق + قائمة وحدة» (اختيار المالك ٢٠٢٦-١٠-٢٠). من الأعلى:
// الرأس الكحلي (التحية، الدور، التاريخ، وأربعة أرقام: بانتظارك · مستعجل · متأخر · رسائل؛ ومكبّر صوت «إعلان جديد» بجانب
// البحث والجرس لمن يرسل للأعضاء؛ وتحتها سطر حالة مختصر: الصيانة · الرصيد · المجدول · بلا إشعارات — طلب المالك «ابى تختصر
// لوحة التنبيهات وتكون عند اللوحة العلوية») ← «أعداد الأعضاء» جدولاً صغيراً (المالك والمدير والمراقب) ← «الأقسام» الستة
// ٣×٢ بتلميح حيّ (اختيار المالك «٦ أقسام») ← «بانتظار قرارك» قائمة واحدة (القرارات والمهام معاً، أول ٣ و«عرض الكل»).
// بطاقة «تنبيهات» حُذفت: الأربعة صارت سطر الحالة، والباقي (وفاة لم يُعلن عنها، مشكلات الشجرة للمراقب، خلل إعداد قاعدة
// البيانات) «يحتاج إجراء» في «إشعارات الإدارة» التي يفتحها الجرس (`AdminNotificationsPage`). «اليوم في العائلة» انتقل لأعلى «المناسبات»،
// و«نبض العائلة» لأعلى «المؤشرات»، وكل إجراء سريع لأعلى قسمه. كل دور يرى مجاله فقط والقسم الفارغ لا يُرسم (IA.md).
// صفحات الأقسام تُفتح بقيمة في المسار (`.area`) ليستبدلها شريط الأقسام (`AdminAreaRouter`) بلا تراكم.
// الصلاحيات والوجهات والروابط العميقة كما كانت، والصفحات القديمة تُفتح كما هي.

struct AdminDashboardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @StateObject private var taskStore = AdminTodayTaskStore()
    @ObservedObject private var sms = SmsBalanceStore.shared
    @Binding var selectedTab: Int
    @State private var navigationPath = NavigationPath()
    /// عدّاد انتقالات شريط الأقسام (قيمة جديدة في المسار كل مرة)
    @State private var areaHops = 0

    // أرقام محسوبة من البيانات المحمّلة
    @State private var isInitialLoading = true
    @State private var pendingArchiveCount = 0
    @State private var usageStats: AppUsageStats? = AppUsageStats.cached
    @State private var issueMembersCount = 0
    @State private var treeIssuesCount = 0
    @State private var moderatorCount = 0
    @State private var inboxTotal = 0
    @State private var memorial = DeceasedMemorialBoard.empty
    @State private var recentDeaths: [FamilyMember] = []
    /// المعلن عنهم — nil = تعذّر الجلب (لا تنبيه «لم يُعلن» خطأً)
    @State private var announcedIds: Set<UUID>? = nil
    @State private var activeNow: Int? = nil
    /// «بلا إشعارات» في سطر الحالة — نفس مخزن «الأجهزة ووصول الإشعارات» (رقم واحد بتعريف واحد)
    @ObservedObject private var devices = AdminDeviceReachStore.shared
    /// «أعداد الأعضاء» — تبدأ من آخر ما حُمّل وتتحدّث مع التحميل
    @State private var memberCounts = AdminMemberCounts.seeded(members: [])

    @Environment(\.dsLandscape) private var landscape
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                DS.Hub.background.ignoresSafeArea()
                // السحب للأسفل فوق الرأس يكشف كحلياً لا رملياً
                DS.Hub.bandTop
                    .frame(height: DS.Hub.ringSide)
                    .ignoresSafeArea(edges: .top)
                    .accessibilityHidden(true)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        todayHeader
                        todayContent
                            .padding(.top, -DS.Hub.headerOverlap)
                    }
                }
                .refreshable { await loadAllAdminData(force: true) }
                .adminHideTopEdgeEffect()
            }
            // منطقة شريط الحالة كحلية دائماً (الرأس يتمرّر، ونص الساعة أبيض)
            .adminStatusBarCover()
            .navigationDestination(for: AdminReviewDestination.self) { destination in
                AdminLazyPage { Self.page(for: destination) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onReceive(NotificationCenter.default.publisher(for: .openAdminReviewForKind)) { note in
            guard let kind = note.userInfo?["kind"] as? String else { return }
            // من الإشعار: «الوارد» نفسه (على الطلب إن عُرف)، أو طلبات الشجرة، أو صفحة رسائل الدخول
            let requestId = (note.userInfo?["request_id"] as? String).flatMap(UUID.init(uuidString:))
            let destination: AdminReviewDestination
            if kind == NotificationKind.treeEdit.rawValue {
                destination = .treeEditRequests
            } else if kind == "sms_balance_low" {
                destination = .sms
            } else if let requestId {
                destination = .inboxItem(requestId)
            } else {
                destination = .allRequests
            }
            // قشّر الـ stack الحالي قبل الدفع لتجنب التراكم
            navigationPath = NavigationPath()
            navigationPath.append(destination)
        }
        .task {
            // شريط الأقسام في كل صفحة من هذا المكدس ينقل عبر هذا (في `.task` الموجودة — بلا مُعدِّل إضافي على الجذر)
            AdminAreaRouter.navigate = openArea
            await loadAllAdminData()
        }
        .onChange(of: memberVM.membersVersion) { _ in recalculate() }
        .onChange(of: pendingRequestsSum) { _ in recalculate() }
        .onChange(of: pendingArchiveCount) { _ in recalculate() }
        .onChange(of: todaySnapshot) { _ in syncTasks() }
    }

    // MARK: - المسار

    /// وجهات المسار — كل وجهة بقسمها في شريط الأقسام
    static func page(for destination: AdminReviewDestination) -> AnyView {
        switch destination {
        case .treeEditRequests:  return AnyView(AdminTreeEditRequestsView().adminArea(.inbox))
        case .allRequests:       return AnyView(AdminAllRequestsView().adminArea(.inbox))
        case .inboxItem(let id): return AnyView(AdminAllRequestsView(focusId: id).adminArea(.inbox))
        case .sms:               return AnyView(AdminSmsView(backTitle: L10n.t("اليوم", "Today")).adminArea(.team))
        case .area(let area, _): return AnyView(AdminAreaView(area: area))
        }
    }

    /// شريط الأقسام: المسار كله يصير صفحة القسم المطلوب (لا تكدّس صفحات فوق بعض)
    private func openArea(_ area: AdminArea) {
        areaHops += 1
        var path = NavigationPath()
        path.append(AdminReviewDestination.area(area, areaHops))
        navigationPath = path
    }

    // MARK: - التحميل

    /// مجموع كل الطلبات المعلّقة — يعيد الحساب لحظياً عند أي تغيير
    private var pendingRequestsSum: Int {
        newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.treeEditRequests.count
            + projectsVM.pendingProjects.count
    }

    /// كل بيانات «اليوم» بالتوازي — في `.task` وفي السحب للتحديث
    private func loadAllAdminData(force: Bool = false) async {
        diwaniyaVM.canModerate = authVM.canModerate
        diwaniyaVM.authVM = authVM
        await memberVM.fetchAllMembers(force: force)
        await adminRequestVM.refreshApprovalsFlag()

        let isAdmin = authVM.isAdmin
        let isSystem = authVM.canViewSystemSettings
        let seesCounts = seesMemberCounts
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await adminRequestVM.fetchDeceasedRequests() }
            group.addTask { @MainActor in await newsVM.fetchPendingNewsRequests() }
            group.addTask { @MainActor in await adminRequestVM.fetchChildAddRequests() }
            group.addTask { @MainActor in await adminRequestVM.fetchNewsReportRequests() }
            group.addTask { @MainActor in await adminRequestVM.fetchPhoneChangeRequests() }
            group.addTask { @MainActor in await adminRequestVM.fetchPhotoSuggestionRequests() }
            group.addTask { @MainActor in await diwaniyaVM.fetchPendingDiwaniyas() }
            group.addTask { @MainActor in await adminRequestVM.fetchTreeEditRequests() }
            group.addTask { @MainActor in await adminRequestVM.fetchNameChangeRequests() }
            group.addTask { @MainActor in await adminRequestVM.fetchContactMessages() }
            group.addTask { @MainActor in await adminRequestVM.fetchJoinApprovalRequests() }
            group.addTask { @MainActor in await projectsVM.fetchPendingProjects() }
            group.addTask { @MainActor in await authVM.fetchBannedPhones() }
            group.addTask { @MainActor in pendingArchiveCount = await FamilyArchiveViewModel.pendingCount() }
            // فشل الجلب يُبقي آخر قيمة محفوظة (لا يمسح البطاقة)
            group.addTask { @MainActor in if let u = await AppUsageStats.fetch() { usageStats = u } }
            if isSystem {
                group.addTask { @MainActor in await SmsBalanceStore.shared.refresh(force: force) }
            }
            if isAdmin {
                group.addTask { @MainActor in await notificationVM.fetchScheduledNotifications() }
                group.addTask { @MainActor in
                    if let ids = await AdminTodayFetch.announcedDeathIds() { announcedIds = ids }
                }
                group.addTask { @MainActor in activeNow = await AdminTodayFetch.activeNowCount() }
                group.addTask { @MainActor in await AdminDeviceReachStore.shared.refresh(force: force) }
            }
            if seesCounts {
                // «النساء» في «أعداد الأعضاء» — فشل الجلب يُبقي آخر قيمة (كاش شجرة النساء)
                group.addTask { @MainActor in
                    if let rows = try? await WomenStore.fetch() { memberCounts.setWomen(rows) }
                }
            }
        }
        recalculate()
        withAnimation(DS.Anim.smooth) { isInitialLoading = false }
        syncTasks()
    }

    /// الحالات المشتقة لـ«إشعارات الإدارة» (وفاة لم يُعلن عنها، مشكلات الشجرة للمراقب، خلل قاعدة البيانات)
    private var derivedNotices: [AdminNoticeItem] {
        AdminNoticeStore.derive(authVM: authVM, unannounced: unannounced,
                                treeIssues: isInitialLoading ? nil : treeIssuesCount)
    }

    private func publishNotices() {
        AdminNoticeStore.shared.publish(derivedNotices)
    }

    /// الأرقام المحسوبة من الأعضاء والطلبات — مرور واحد على الأعضاء
    private func recalculate() {
        let all = memberVM.allMembers
        var moderator = 0, issues = 0, treeIssues = 0
        let moderatorRoles: Set<FamilyMember.UserRole> = [.owner, .admin, .monitor, .supervisor]
        var activeIds = Set<UUID>(), fatherIds = Set<UUID>()
        for m in all where m.role != .pending && m.status != .frozen {
            activeIds.insert(m.id)
            if let fid = m.fatherId { fatherIds.insert(fid) }
        }
        for m in all {
            if m.role == .pending { continue }
            if moderatorRoles.contains(m.role) && m.isDeceased != true && m.status != .frozen { moderator += 1 }
            // «بيانات ناقصة» = نفس شريحة «العائلة» (الميلاد والجنس للأحياء، والصورة للعضو المسجّل) — بلا «مفعّل/بانتظار»
            if m.isDeceased != true
                && !AdminMemberFacts.gaps(m, registered: AdminAccountsStore.shared.info(m.id) != nil).isEmpty { issues += 1 }
            if m.status != .frozen {
                let isOrphan = m.fatherId == nil && !fatherIds.contains(m.id)
                let noName = m.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.fullName == "بدون اسم"
                let brokenParent = m.fatherId != nil && !activeIds.contains(m.fatherId ?? UUID())
                if isOrphan || noName || brokenParent || m.isHiddenFromTree { treeIssues += 1 }
            }
        }
        let total = AdminAllRequestsView.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveCount,
            scope: AdminAllRequestsView.reviewScope(for: authVM))
        let deaths = all.filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate) }
            .sorted { ($0.deathDate ?? "") > ($1.deathDate ?? "") }
        var countsNow = memberCounts
        countsNow.setMen(from: all)
        countsNow.setUsage(usageStats)
        // شجرة النساء فتحت في تبويب آخر قبل أن يصل جلبنا — خذ كاشها
        if countsNow.women == nil { countsNow.setWomen(WomenStore.cache) }
        withAnimation(DS.Anim.smooth) {
            moderatorCount = moderator
            issueMembersCount = issues
            treeIssuesCount = treeIssues
            inboxTotal = total
            recentDeaths = deaths
            memorial = DeceasedMemorialBoard(all)
            if countsNow != memberCounts { memberCounts = countsNow }
        }
        publishNotices()
    }

    // MARK: - مشتقات

    private var decisionItems: [AdminDecisionItem] {
        AdminTodayFeed.decisionItems(authVM: authVM, memberVM: memberVM, newsVM: newsVM,
                                     adminRequestVM: adminRequestVM, diwaniyaVM: diwaniyaVM, projectsVM: projectsVM)
    }

    private func counts(_ items: [AdminDecisionItem]) -> AdminTodayCounts {
        AdminTodayFeed.counts(authVM: authVM, adminRequestVM: adminRequestVM, items: items, inboxTotal: inboxTotal)
    }

    /// المتوفون حديثاً ولم يُعلن عنهم (المالك والمدير) — فارغة إن لم يُعرف المعلن عنهم
    private var unannounced: [FamilyMember] {
        guard authVM.isAdmin, let announcedIds else { return [] }
        return recentDeaths.filter { !announcedIds.contains($0.id) }
    }

    private func openTasks(_ items: [AdminDecisionItem]) -> [AdminTodayTask] {
        AdminTodayFeed.tasks(authVM: authVM, adminRequestVM: adminRequestVM, items: items,
                             sms: sms, unannounced: unannounced)
    }

    private func todayEntries(_ items: [AdminDecisionItem]) -> [AdminTodayEntry] {
        AdminTodayFeed.entries(items: items, tasks: openTasks(items))
    }

    /// ما يتغيّر في القائمة والمهام — لمزامنة «المنجز» وصفحة «عرض الكل»
    private struct TodaySnapshot: Equatable {
        var tasks: [String] = []
        var entries: [AdminTodayEntry] = []
        var inbox = 0
    }

    private var todaySnapshot: TodaySnapshot {
        guard !isInitialLoading else { return TodaySnapshot() }
        let items = decisionItems
        let tasks = openTasks(items)
        return TodaySnapshot(tasks: tasks.map(\.id), entries: AdminTodayFeed.entries(items: items, tasks: tasks),
                             inbox: inboxTotal)
    }

    private func syncTasks() {
        guard !isInitialLoading else { return }
        let items = decisionItems
        let tasks = openTasks(items)
        taskStore.sync(open: tasks, user: authVM.currentUser?.id, role: authVM.currentUser?.role.rawValue ?? "")
        taskStore.publish(entries: AdminTodayFeed.entries(items: items, tasks: tasks), inboxTotal: inboxTotal)
        publishNotices()
    }

    /// «أعداد الأعضاء» لمن يرى الإحصائيات (كبطاقة «أفراد العائلة» القديمة): المالك والمدير والمراقب
    private var seesMemberCounts: Bool { authVM.isAdmin || authVM.currentUser?.role == .monitor }

    private var roleGuide: RoleGuide? {
        authVM.currentUser.flatMap { RoleGuide.forRole($0.role) }
    }

    /// مجال المراقب والمشرف (سطر «نطاقي» في الرأس)
    private var scopeGuide: RoleGuide? { authVM.isAdmin ? nil : roleGuide }

    private var visibleAreas: [AdminArea] { AdminArea.visible(for: authVM) }

    // MARK: - الرأس

    // كل جزء خلف AnyView: نوع الصفحة كاملاً كان عميقاً لدرجة أن حلّه في الجوال (مكدس الخيط الرئيسي ١ ميغا) يفيض
    // فينهار التطبيق عند فتح الإدارة (٢٠٢٦-١٠-٢٠؛ المحاكي مكدسه ٨ ميغا فلم يظهر). الحدود تقسم الحلّ إلى أجزاء صغيرة.
    private var todayHeader: AnyView { AnyView(todayHeaderContent) }

    private var todayHeaderContent: some View {
        let items = decisionItems
        let c = counts(items)
        let loading = isInitialLoading
        func value(_ n: Int) -> String { loading ? "—" : "\(n)" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xsm) {
                    Image(systemName: "checkmark.shield")
                        .dsGlyph(DS.Glyph.md, weight: .semibold)
                    Text(L10n.t("لوحة الإدارة · اليوم", "Admin · Today"))
                        .dsFont(.sectionTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(DS.Color.accentLight)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Spacing.sm)
                // «إعلان جديد» السريع (طلب المالك ٢٠٢٦-١٠-٢٠ «زر سريع و خارجي») — نوع مستقل خلف `AnyView` (حارس المكدس)
                if authVM.canSendNotifications {
                    AnyView(AdminAnnounceLauncher())
                }
                NavigationLink { AdminLazyPage { AnyView(AdminSearchView()) } } label: {
                    AdminGlassCircle(symbol: "magnifyingglass")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("بحث في اللوحة", "Search the dashboard"))
                // «إشعارات الإدارة» (صفحة واحدة: الطلبات ونشاط الفريق والنظام) — العدد = غير المقروء + ما يحتاج إجراء الآن
                let bell = notificationVM.unreadAdminNoticesCount + derivedNotices.count
                NavigationLink {
                    AdminLazyPage { AnyView(AdminNotificationsPage().adminBackTitle(L10n.t("اليوم", "Today"))) }
                } label: {
                    AdminGlassCircle(symbol: "bell", count: bell)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(bell > 0
                    ? L10n.t("إشعارات الإدارة، \(bell) جديد", "Admin notifications, \(bell) new")
                    : L10n.t("إشعارات الإدارة", "Admin notifications"))
            }
            .frame(minHeight: DS.Hub.glassButton)

            Text(helloLine)
                .dsFont(.hubTitle)
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.sm + 2)

            HStack(spacing: DS.Spacing.sm) {
                if let guide = roleGuide {
                    AdminBandChip(text: guide.title)
                }
                Text(AdminTodayText.dayLine())
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.onBandMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, DS.Spacing.xs)

            if let guide = scopeGuide {
                NavigationLink { AdminMyScopeView(guide: guide) } label: {
                    HStack(spacing: DS.Spacing.xsm) {
                        Image(dsSymbol: guide.icon).dsGlyph(DS.Glyph.sm)
                        Text(L10n.t("صلاحياتي: \(guide.mandate)", "My permissions: \(guide.mandate)"))
                            .dsFont(.footnote)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        DSChevron()
                    }
                    .foregroundColor(DS.Hub.onBandMuted)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Hub.glass))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
                }
                .buttonStyle(DSPressStyle())
                .padding(.top, DS.Spacing.md)
            }

            HStack(spacing: DS.Spacing.sm) {
                kpiLink(AdminKPITile(value: value(c.waiting), label: L10n.t("بانتظار قرارك", "Awaiting you"),
                                     icon: "tray", tint: DS.Hub.kpiMine), filter: .waiting)
                kpiLink(AdminKPITile(value: value(c.urgent), label: L10n.t("عاجل", "Urgent"),
                                     icon: "flame", tint: DS.Hub.kpiHot), filter: .urgent)
                kpiLink(AdminKPITile(value: value(c.late), label: L10n.t("متأخر", "Late"),
                                     icon: "clock", tint: DS.Hub.kpiLate), filter: .late)
                NavigationLink { AdminLazyPage { AnyView(AdminAllRequestsView(startsWithMessages: true).adminArea(.inbox)) } } label: {
                    AdminKPITile(value: value(c.unreadMessages), label: L10n.t("رسائل", "Messages"),
                                 icon: "bubble.left")
                }
                .buttonStyle(DSPressStyle())
            }
            .padding(.top, DS.Spacing.lg + 2)

            // سطر الحالة (كان بطاقة «تنبيهات») — كل إشارة تفتح بيتها الوحيد
            let pills = statusPills
            if !pills.isEmpty {
                AnyView(AdminTodayStatusRow(pills: pills))
                    .padding(.top, DS.Spacing.sm)
            }
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Hub.headerSide)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, DS.Hub.headerBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }

    private func kpiLink(_ tile: AdminKPITile, filter: ApprovalListFilter) -> some View {
        NavigationLink { AdminLazyPage { AnyView(AdminAllRequestsView(initialFilter: filter).adminArea(.inbox)) } } label: { tile }
            .buttonStyle(DSPressStyle())
    }

    private var helloLine: String {
        let name = authVM.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hello = AdminTodayText.greeting()
        return name.isEmpty ? hello : L10n.t("\(hello)، \(name)", "\(hello), \(name)")
    }

    // MARK: - المحتوى

    private var todayContent: AnyView { AnyView(todayContentStack) }

    private var todayContentStack: some View {
        let entries = todayEntries(decisionItems)
        let seesCounts = seesMemberCounts
        return VStack(spacing: DS.Hub.stackSpacing) {
            if seesCounts {
                AnyView(AdminMemberCountsCard(counts: memberCounts))
            }
            // بلا «أعداد الأعضاء» (المشرف) تصعد المربّعات نفسها فوق الرأس — عنوان «الأقسام» لا يقع على الكحلي
            AnyView(areasSection(labeled: seesCounts))
            AnyView(decisionCard(entries))
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.xxxl)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .dsTabBarClearance()
        // الأرضية الرملية تبدأ تحت ما يصعد من البطاقة فوق الرأس
        .background(alignment: .top) {
            DS.Hub.background
                .padding(.top, DS.Hub.headerOverlap)
                .accessibilityHidden(true)
        }
    }

    // MARK: سطر الحالة (كان بطاقة «تنبيهات»)

    /// الصيانة · الرصيد · المجدول · بلا إشعارات — للمالك والمدير (نفس ظهور التنبيهات السابقة؛ المراقب والمشرف لا يرونها)
    private var statusPills: [AdminStatusPill] {
        guard authVM.isAdmin else { return [] }
        var list: [AdminStatusPill] = []
        if authVM.canViewSystemSettings {
            let s = appSettingsVM.settings
            if s.updatedAt == nil {
                list.append(AdminStatusPill(home: .maintenance, label: L10n.t("الصيانة", "Maintenance"), value: "—", level: .unknown))
            } else {
                list.append(s.maintenanceMode
                    ? AdminStatusPill(home: .maintenance, label: L10n.t("الصيانة", "Maintenance"),
                                      value: L10n.t("شغّالة", "On"), level: .urgent)
                    : AdminStatusPill(home: .maintenance, label: L10n.t("الصيانة", "Maintenance"),
                                      value: L10n.t("مطفأة", "Off"), level: .ok))
            }
            // تحت عتبة «منخفض» كهرماني وتحت «عاجل» أحمر (العتبات من السيرفر)
            let level: AdminStatusPill.Level
            switch sms.level {
            case .good:    level = .ok
            case .low:     level = .warn
            case .urgent:  level = .urgent
            case .unknown: level = .unknown
            }
            list.append(AdminStatusPill(home: .sms, label: L10n.t("الرصيد", "Balance"),
                                        value: sms.status?.balance.map { L10n.t("\(SmsBalanceText.points($0)) نقطة",
                                                                                "\(SmsBalanceText.points($0)) pts") } ?? "—",
                                        level: level))
        }
        // الإشعارات المجدولة: اليوم كهرماني، ولاحقاً أو لا شيء أخضر
        let dates = notificationVM.scheduledNotifications.compactMap(\.scheduledDate)
        let today = dates.filter { Calendar.current.isDateInToday($0) }.count
        list.append(today > 0
            ? AdminStatusPill(home: .scheduled, label: L10n.t("مجدول", "Scheduled"),
                              value: L10n.t("\(today) اليوم", "\(today) today"), level: .warn)
            : dates.isEmpty
                ? AdminStatusPill(home: .scheduled, label: L10n.t("مجدول", "Scheduled"),
                                  value: L10n.t("لا شيء", "None"), level: .ok,
                                  spoken: L10n.t("لا شيء مجدول", "Nothing scheduled"))
                : AdminStatusPill(home: .scheduled, label: L10n.t("مجدول", "Scheduled"),
                                  value: L10n.t("\(dates.count) لاحقاً", "\(dates.count) later"), level: .ok))
        // أجهزة لا تصلها الإشعارات (غير مسجّلة أو لم تُحدَّث منذ 30 يوماً) — نفس رقم صفحتها
        if let reach = devices.stats {
            let n = reach.total - reach.reach
            list.append(AdminStatusPill(home: .devices, label: L10n.t("بلا إشعارات", "Not reached"),
                                        value: n == 0 ? L10n.t("لا يوجد", "None")
                                                      : n == 1 ? L10n.t("جهاز واحد", "1 device")
                                                               : L10n.t("\(n) أجهزة", "\(n) devices"),
                                        level: n > 0 ? .warn : .ok))
        } else {
            list.append(AdminStatusPill(home: .devices, label: L10n.t("بلا إشعارات", "Not reached"), value: "—", level: .unknown))
        }
        return list
    }

    // MARK: يحتاج قرارك — قائمة واحدة (القرارات والمهام معاً)

    private static let visibleEntryLimit = 3

    private func decisionCard(_ entries: [AdminTodayEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("بانتظار قرارك", "Awaiting your decision"),
                            badge: isInitialLoading ? nil : entries.count) {
                if !isInitialLoading {
                    // «عرض الكل» = «الوارد» على «بانتظار قرارك» (صفحة «عرض الكل» حُذفت — D21؛ «المنجز اليوم» آخر الوارد)
                    NavigationLink {
                        AdminLazyPage { AnyView(AdminAllRequestsView(initialFilter: .waiting).adminArea(.inbox)) }
                    } label: {
                        AdminCardLinkLabel(title: L10n.t("عرض الكل", "View all"))
                    }
                    .buttonStyle(.plain)
                }
            }
            if isInitialLoading {
                DSPageLoader(L10n.t("جارٍ التحميل…", "Loading…"), fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
            } else if entries.isEmpty {
                AdminTodayCaughtUpRow()
            } else {
                ForEach(Array(entries.prefix(Self.visibleEntryLimit).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { AdminRowDivider() }
                    AdminTodayEntryLink(entry: entry)
                }
            }
        }
        .adminCard()
    }

    // MARK: الأقسام

    /// الأقسام الستة: ٣ أعمدة × صفّان — وعمودان مع الخط الكبير جداً، أو حين يرى الدور قسمين أو أربعة (المشرف ٢،
    /// المراقب ٤: صفوف كاملة بلا خانة فارغة). كل مربّع يحجز سطري الاسم وسطري التلميح فتتساوى المربّعات بلا قياس إضافي
    /// (حارس المكدس). كل مربّع يفتح صفحة القسم بقيمة في المسار، فيستبدلها شريط الأقسام بلا تراكم
    private func areasSection(labeled: Bool) -> some View {
        let shown = visibleAreas.count
        let narrow = (typeSize >= .xxxLarge && !landscape) || shown <= 2 || shown == 4
        let count = narrow ? DS.Hub.areaColumnsLargeText : DS.Hub.areaColumns
        let columns = Array(repeating: GridItem(.flexible(), spacing: AdminGrid.spacing), count: count)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if labeled {
                AdminSectionLabel(title: L10n.t("الأقسام", "Sections"))
            }
            LazyVGrid(columns: columns, spacing: AdminGrid.spacing) {
                ForEach(visibleAreas) { area in
                    NavigationLink(value: AdminReviewDestination.area(area, 0)) {
                        areaTile(area)
                    }
                    .buttonStyle(DSPressStyle())
                }
            }
        }
    }

    private func areaTile(_ area: AdminArea) -> some View {
        let hint = areaHint(area)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminIconSquare(symbol: area.icon, tint: area.fill, side: DS.Hub.tileIcon,
                            radius: DS.Hub.tileIconRadius, filled: true, glyph: DS.Glyph.lg)
            Spacer(minLength: 0)
            Text(area.title)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
            Text(hint.text)
                .dsFont(.caption)
                .foregroundColor(hint.warn ? DS.Color.warning : DS.Color.textTertiary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Hub.tileMinHeight, alignment: .topLeading)
        .dsCard(padding: DS.Spacing.md, radius: DS.Hub.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint.text)
    }

    /// تلميح حيّ واحد لكل قسم
    private func areaHint(_ area: AdminArea) -> (text: String, warn: Bool) {
        if isInitialLoading { return (area.subtitle, false) }
        switch area {
        case .inbox:
            let msgs = adminRequestVM.pendingContactMessagesCount
            return (L10n.t("\(inboxTotal) طلباً · \(msgs) رسائل", "\(inboxTotal) requests · \(msgs) messages"), false)
        case .family:
            if issueMembersCount > 0 {
                return (L10n.t("\(issueMembersCount) بيانات ناقصة", "\(issueMembersCount) with missing data"), false)
            }
            return treeIssuesCount > 0 ? (L10n.t("\(treeIssuesCount) مشكلات الشجرة", "\(treeIssuesCount) tree problems"), false)
                                       : (area.subtitle, false)
        case .occasions:
            // إشعار مجدول (للمرسلين) أولاً، وإلا الذكرى القريبة
            let n = authVM.canSendNotifications ? notificationVM.scheduledNotifications.count : 0
            return n > 0 ? (L10n.t("\(n) إشعار مجدول", "\(n) scheduled"), false) : (memorial.dashboardCaption, false)
        case .metrics:
            if let now = activeNow { return (L10n.t("المستخدمون الآن \(now)", "\(now) using now"), false) }
            return (area.subtitle, false)
        case .team:
            // رصيد رسائل الدخول حين يحتاج شحناً (تحذير)، وإلا عدد الفريق
            if authVM.canViewSystemSettings, sms.needsTopUp, let balance = sms.status?.balance {
                return (L10n.t("رصيد الرسائل \(SmsBalanceText.points(balance))", "SMS balance \(SmsBalanceText.points(balance))"),
                        true)
            }
            return (L10n.t("\(moderatorCount) في الفريق", "\(moderatorCount) on the team"), false)
        case .app:
            return appSettingsVM.settings.maintenanceMode
                ? (L10n.t("وضع الصيانة يعمل", "Maintenance on"), true)
                : (L10n.t("وضع الصيانة مطفأ", "Maintenance off"), false)
        }
    }
}

/// يبني الصفحة عند ظهورها فقط (لا عند بناء اللوحة) — كانت كلها تُنسخ في مكدّس اللوحة فينغلق التطبيق (٢٠٢٦-١٠-٠٥)
struct AdminLazyPage: View {
    let make: () -> AnyView
    var body: some View { make() }
}

// MARK: - «بانتظار قرارك»: الصفّ، والرابط، و«المنجز اليوم»

/// صفّ في «يحتاج قرارك»: دائرة الإنجاز لما عليك أنت (لمسة «ب» — تصير ✓ في «المنجز» حين يُحلّ ما خلفها)، أو مربّع
/// النوع لما في مجالك عند غيرك؛ ثم العنوان وسطر الحالة وشارة المهلة
struct AdminTodayEntryRow: View {
    let entry: AdminTodayEntry

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if entry.isTask {
                Circle()
                    .strokeBorder(DS.Color.textTertiary, lineWidth: DS.Border.widthBold)
                    .frame(width: DS.Hub.taskRing, height: DS.Hub.taskRing)
                    .frame(width: DS.Hub.iconSquare)
                    .accessibilityHidden(true)
            } else {
                AdminIconSquare(symbol: entry.icon, tint: entry.tint)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // نصّ عادي (لا مفتاح ترجمة): مفتاح بمتغيّرين يعزل كلاً منهما فيقلب ترتيبهما في العربية
                Text(verbatim: entry.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                if !entry.subtitle.isEmpty {
                    Text(verbatim: entry.subtitle)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let chip = entry.chip {
                DSStatusChip(text: chip.text, icon: chip.icon, tint: chip.tint)
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.isTask ? L10n.t("عليك", "Yours to do") : L10n.t("بانتظار غيرك", "With someone else"))
    }
}

/// الصفّ رابطاً: الطلب يفتح «الوارد» على مربّع تفاصيله، والرسالة تفتح «رسائل الأعضاء»
struct AdminTodayEntryLink: View {
    let entry: AdminTodayEntry

    var body: some View {
        NavigationLink { AdminLazyPage { Self.page(entry.target) } } label: {
            AdminTodayEntryRow(entry: entry)
        }
        .buttonStyle(.plain)
    }

    private static func page(_ target: AdminTodayEntry.Target) -> AnyView {
        switch target {
        case .inbox(let id): return AnyView(AdminAllRequestsView(focusId: id).adminArea(.inbox))
        case .messages:      return AnyView(AdminAllRequestsView(startsWithMessages: true).adminArea(.inbox))
        }
    }
}

/// «كل شيء متابَع» — حين لا شيء ينتظر
struct AdminTodayCaughtUpRow: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "checkmark.seal.fill", tint: DS.Color.success)
            Text(L10n.t("لا توجد طلبات بانتظار قرارك", "No requests await your decision"))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
    }
}

/// مهمة أُنجزت اليوم (سطر «المنجز اليوم» آخر «الوارد»)
struct AdminTodayDoneRow: View {
    let record: AdminTodayTaskStore.Record

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: "checkmark")
                .dsGlyph(DS.Glyph.sm, weight: .heavy)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Hub.taskRing, height: DS.Hub.taskRing)
                .background(Circle().fill(DS.Color.accentLight))
                .frame(width: DS.Hub.iconSquare)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: record.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .strikethrough(true, color: DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: [L10n.t("تمّ", "Done"), record.doneAt.map(Self.time)].compactMap { $0 }
                        .joined(separator: " · ") + " · " + record.source)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .opacity(DS.Opacity.disabled + 0.1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("منجزة: \(record.title)", "Done: \(record.title)"))
    }

    private static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - سطر الحالة في الرأس

/// إشارات الحالة الأربع تحت أرقام «اليوم» (كانت بطاقة «تنبيهات»): صفّ واحد بأربع إشارات زجاجية متساوية، وصفّان
/// (٢×٢) حين يكبر خط الجهاز — كل إشارة تفتح بيتها الوحيد
struct AdminTodayStatusRow: View {
    let pills: [AdminStatusPill]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    private var rows: [[AdminStatusPill]] {
        guard typeSize > .large && !landscape && pills.count > 2 else { return [pills] }
        return stride(from: 0, to: pills.count, by: 2).map { Array(pills[$0..<min($0 + 2, pills.count)]) }
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xsm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(row) { pill in
                        NavigationLink { AdminLazyPage { Self.page(pill.home) } } label: {
                            AdminStatusPillView(pill: pill)
                        }
                        .buttonStyle(DSPressStyle())
                    }
                }
            }
        }
    }

    /// بيت كل إشارة: الصيانة ← «التطبيق»، الرصيد ← «رسائل رمز الدخول»، المجدول ← «المناسبات» (القادم)، الأجهزة ←
    /// «الأجهزة ووصول الإشعارات»
    static func page(_ home: AdminStatusPill.Home) -> AnyView {
        let today = L10n.t("اليوم", "Today")
        switch home {
        case .maintenance: return AnyView(AdminAppAreaPage().adminArea(.app))
        case .sms:         return AnyView(AdminSmsView(backTitle: today).adminArea(.team))
        case .scheduled:   return AnyView(AdminOccasionsPage().adminArea(.occasions).adminBackTitle(today))
        case .devices:     return AnyView(AdminPushHealthView().adminArea(.team).adminBackTitle(today))
        }
    }
}

/// إشارة واحدة: العنوان صغيراً، ثم نقطة اللون والقيمة
struct AdminStatusPillView: View {
    let pill: AdminStatusPill

    private var dot: Color {
        switch pill.level {
        case .ok:      return DS.Hub.statusOk
        case .warn:    return DS.Hub.kpiLate
        case .urgent:  return DS.Hub.bellDot
        case .unknown: return DS.Hub.onBandMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(pill.label)
                .dsFont(.micro)
                .foregroundColor(DS.Hub.onBandMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(dot)
                    .frame(width: DS.Hub.statusDot, height: DS.Hub.statusDot)
                Text(verbatim: pill.value)
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(pill.level == .urgent ? DS.Hub.kpiHot : DS.Color.textOnPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xsm)
        .background(RoundedRectangle(cornerRadius: DS.Hub.statusRadius, style: .continuous).fill(DS.Hub.glass))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.statusRadius, style: .continuous)
            .strokeBorder(pill.level == .urgent ? DS.Hub.bellDot.opacity(DS.Opacity.selectedStroke) : DS.Hub.glassLine,
                          lineWidth: DS.Border.width))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.spoken ?? "\(pill.label): \(pill.value)")
    }
}

// MARK: - «أعداد الأعضاء»

/// جدول صغير (طلب المالك ٢٠٢٦-١٠-٢٠): الرجال · النساء · الإجمالي × العدد الكلي · الأحياء · المتوفون، وتحته
/// «الأعضاء المسجّلون: N». كل رقم يفتح صفحته: الرجال ← صفحة الأعضاء (والمتوفون ← شريحة «متوفون»)، النساء ← شجرة النساء،
/// الإجمالي ← «المؤشرات ← العائلة»، والمسجّلون ← شريحة «مسجّلون». نفس التعريفات: الرجال = الشجرة بلا طلبات الانضمام،
/// النساء = إناث شجرة النساء، المسجّلون = لهم حساب دخول. مع الخط الكبير جداً يتحوّل كل صفّ إلى كتلة (العنوان ثم الأرقام).
struct AdminMemberCountsCard: View {
    let counts: AdminMemberCounts
    @Environment(\.dynamicTypeSize) private var typeSize

    fileprivate enum Target { case overview, directory, deceased, women, accounts }

    fileprivate struct Line: Identifiable {
        let id: String
        let title: String
        let tint: Color
        let values: [Int?]
        let targets: [Target]
    }

    private static var columns: [String] {
        [L10n.t("العدد الكلي", "Total"), L10n.t("الأحياء", "Living"), L10n.t("المتوفون", "Deceased")]
    }

    private var lines: [Line] {
        [
            Line(id: "men", title: L10n.t("الرجال", "Men"), tint: DS.Color.male,
                 values: [counts.men, counts.menAlive, counts.menDeceased], targets: [.directory, .directory, .deceased]),
            Line(id: "women", title: L10n.t("النساء", "Women"), tint: DS.Color.female,
                 values: [counts.women, counts.womenAlive, counts.womenDeceased], targets: [.women, .women, .women]),
            Line(id: "total", title: L10n.t("الإجمالي", "Total"), tint: DS.Color.textPrimary,
                 values: [counts.total, counts.totalAlive, counts.totalDeceased], targets: [.overview, .overview, .overview])
        ]
    }

    /// الكتل بدل الجدول من أحجام إمكانية الوصول
    private var stacked: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("أعداد الأعضاء", "Member counts"))
            if stacked { AnyView(blocks) } else { AnyView(table) }
            AdminRowDivider()
            registeredLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Spacing.sm, verticalSpacing: DS.Spacing.sm) {
            GridRow {
                Color.clear.frame(width: 0, height: 0).gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Self.columns, id: \.self) { title in
                    Text(title)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(lines) { line in
                if line.id == "total" {
                    AdminRowDivider()
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text(line.title)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    ForEach(0..<3, id: \.self) { i in
                        cell(line, i, labelled: false)
                    }
                }
            }
        }
    }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(line.title)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                    ForEach(0..<3, id: \.self) { i in
                        cell(line, i, labelled: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ line: Line, _ i: Int, labelled: Bool) -> some View {
        let value = line.values[i].map { "\($0)" } ?? "—"
        let label = Self.columns[i]
        let face = HStack(spacing: DS.Spacing.xs) {
            if labelled {
                Text(label)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: DS.Spacing.sm)
            }
            Text(verbatim: value)
                .dsFont(.statValue)
                .monospacedDigit()
                .foregroundColor(line.tint.dsReadableGlyph)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: labelled ? DS.Icon.tapTarget : nil, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.title)، \(label): \(value)")
        link(line.targets[i], face: AnyView(face))
    }

    private var registeredLine: some View {
        let value = counts.accounts.map { "\($0)" } ?? "—"
        return link(.accounts, face: AnyView(
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.success.dsReadableGlyph)
                    .accessibilityHidden(true)
                Text(verbatim: L10n.t("الأعضاء المسجّلون: \(value)", "Registered members: \(value)"))
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.sm)
                DSChevron()
            }
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)))
    }

    @ViewBuilder
    private func link(_ target: Target, face: AnyView) -> some View {
        switch target {
        case .women:
            // شجرة النساء تُدار من تبويب الشجرة (كصفّ «شجرة النساء» في «العائلة»)
            Button {
                TreeTabContainer.openWomenOnAppear = true
                NotificationCenter.default.post(name: .openWomenTree, object: nil)
            } label: { face }
            .buttonStyle(DSPressStyle())
        default:
            NavigationLink { AdminLazyPage { Self.page(target) } } label: { face }
                .buttonStyle(DSPressStyle())
        }
    }

    private static func page(_ target: Target) -> AnyView {
        switch target {
        // «الإجمالي» ← بيت الأعداد «المؤشرات ← العائلة» (الدفعة ج)
        case .overview:  return AnyView(AdminAnalyticsView().adminArea(.metrics))
        case .directory: return AnyView(AdminMembersPage().adminArea(.family))
        case .deceased:  return AnyView(AdminMembersPage(chip: .deceased).adminArea(.family))
        case .accounts:  return AnyView(AdminMembersPage(chip: .registered).adminArea(.family))
        case .women:     return AnyView(EmptyView())
        }
    }
}
