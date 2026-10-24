import SwiftUI

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
    /// «الوارد» مفتوحاً على طلب بعينه (مربّع تفاصيله)
    case inboxItem(UUID)
    /// «رسائل الدخول · KWT SMS» (إشعار «رصيد الرسائل منخفض»)
    case sms
    /// «طلبات رمز الدخول» كاملة فوق صفحة الرسائل (إشعار «محاولات دخول مريبة»)
    case smsAttempts
    /// بيت إشارة من لوحة «حالة النظام» (تُدفع بعد أن تُغلق اللوحة — الرابط داخل النافذة المنبثقة لا يدفع في هذا المكدس)
    case status(AdminStatusPill.Home)
    /// صفحة قسم (مربّعات «اليوم» وشريط الأقسام) — العدّاد يجعل كل انتقال من الشريط قيمة جديدة فيُستبدل المسار
    /// كله (حتى العودة لصفحة القسم الحالي من صفحة داخلية)
    case area(AdminArea, Int)
}

// MARK: - لوحة الإدارة ← «اليوم» (إعادة التصميم الكاملة — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// الاتجاه «أ» (مركز القيادة) أساساً + لمستان من «ب»: دوائر الإنجاز للمهام، وسحب «الوارد» مثل البريد.
// «في اردحام بلوحة الادارة بالبداية» → «الأقسام فوق + قائمة وحدة» (اختيار المالك ٢٠٢٦-١٠-٢٠). من الأعلى:
// الرأس الكحلي المختصر (التحية وتحتها التاريخ، ومكبّر صوت «إعلان جديد» بجانب البحث والجرس لمن يرسل للأعضاء) ← مربّع
// ثابت واحد «يحتاج انتباهك»: الأرقام الأربعة بانتظار قرارك · عاجل · متأخر · رسائل، وتحتها في المربّع نفسه سطر «حالة النظام»
// يفتح لوحة: الصيانة · الرصيد · المجدول · بلا إشعارات (الدفعة ٩؛ «إحصاء الأفراد» انتقل لأعلى «المؤشرات ← العائلة»،
// ٢٠٢٦-١٠-٢٢) ← «الأقسام» الستة ٣×٢ أيقونة واسم فقط (اختيار المالك «٦ أقسام»). بطاقة «بانتظار قرارك» حُذفت (طلب المالك
// ٢٠٢٦-١٠-٢٢): الطلبات من «الوارد» ورقم «بانتظار قرارك» في «يحتاج انتباهك» الذي يفتحه.
// بطاقة «تنبيهات» حُذفت: الأربعة صارت «حالة النظام»، والباقي (وفاة لم يُعلن عنها، مشكلات الشجرة للمراقب، خلل إعداد قاعدة
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
    @State private var treeIssuesCount = 0
    @State private var moderatorCount = 0
    @State private var inboxTotal = 0
    @State private var recentDeaths: [FamilyMember] = []
    /// المعلن عنهم — nil = تعذّر الجلب (لا تنبيه «لم يُعلن» خطأً)
    @State private var announcedIds: Set<UUID>? = nil
    /// «بلا إشعارات» في «حالة النظام» — نفس مخزن «الأجهزة ووصول الإشعارات» (رقم واحد بتعريف واحد)
    @ObservedObject private var devices = AdminDeviceReachStore.shared
    /// «ظهور موحّد» (الدفعة ١٠): البطاقات تصعد تباعاً مرة عند الظهور (`dsCardCascade`) — يُضبط في `.task` الموجودة
    @State private var appeared = false

    @Environment(\.dsLandscape) private var landscape

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
            // من الإشعار: «الوارد» نفسه (على الطلب إن عُرف)، أو طلبات الشجرة، أو صفحة رسائل الدخول (ومحاولات الدخول فوقها)
            let requestId = (note.userInfo?["request_id"] as? String).flatMap(UUID.init(uuidString:))
            let destinations: [AdminReviewDestination]
            if kind == NotificationKind.treeEdit.rawValue {
                destinations = [.treeEditRequests]
            } else if kind == AdminNotices.smsSuspicious {
                destinations = [.sms, .smsAttempts]
            } else if kind == AdminNotices.smsBalanceLow {
                destinations = [.sms]
            } else if let requestId {
                destinations = [.inboxItem(requestId)]
            } else {
                destinations = [.allRequests]
            }
            // قشّر الـ stack الحالي قبل الدفع لتجنب التراكم
            var path = NavigationPath()
            for destination in destinations { path.append(destination) }
            navigationPath = path
        }
        .task {
            // شريط الأقسام في كل صفحة من هذا المكدس ينقل عبر هذا (في `.task` الموجودة — بلا مُعدِّل إضافي على الجذر)
            AdminAreaRouter.navigate = openArea
            // «حي ✓» المحلية لهذا المستخدم — «أحياء (تقديري)» في «إحصاء الأفراد» (أعلى «المؤشرات ← العائلة»)
            AdminLivingVerifiedStore.shared.activate(user: authVM.currentUser?.id)
            appeared = true
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
        case .smsAttempts:       return AnyView(SmsAttemptsListPage().adminArea(.team))
        case .status(let home):  return AdminSystemStatusLine.page(home)
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
            if isSystem {
                group.addTask { @MainActor in await SmsBalanceStore.shared.refresh(force: force) }
            }
            if isAdmin {
                group.addTask { @MainActor in await notificationVM.fetchScheduledNotifications() }
                group.addTask { @MainActor in
                    if let ids = await AdminTodayFetch.announcedDeathIds() { announcedIds = ids }
                }
                group.addTask { @MainActor in await AdminDeviceReachStore.shared.refresh(force: force) }
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
        var moderator = 0, treeIssues = 0
        let moderatorRoles: Set<FamilyMember.UserRole> = [.owner, .admin, .monitor, .supervisor]
        var activeIds = Set<UUID>(), fatherIds = Set<UUID>()
        for m in all where m.role != .pending && m.status != .frozen {
            activeIds.insert(m.id)
            if let fid = m.fatherId { fatherIds.insert(fid) }
        }
        for m in all {
            if m.role == .pending { continue }
            if moderatorRoles.contains(m.role) && m.isDeceased != true && m.status != .frozen { moderator += 1 }
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
        withAnimation(DS.Anim.smooth) {
            moderatorCount = moderator
            treeIssuesCount = treeIssues
            inboxTotal = total
            recentDeaths = deaths
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
        // مدة التنبيه من السيرفر (تُقرأ مع المعلن عنهم) — الوفيات الحديثة نفسها ٣٠ يوماً
        return recentDeaths.filter { !announcedIds.contains($0.id) && DeathRecency.isRecent($0.deathDate, within: DeathRecency.alertDays) }
    }

    private func openTasks(_ items: [AdminDecisionItem]) -> [AdminTodayTask] {
        AdminTodayFeed.tasks(authVM: authVM, adminRequestVM: adminRequestVM, items: items,
                             sms: sms, unannounced: unannounced)
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

    private var visibleAreas: [AdminArea] { AdminArea.visible(for: authVM) }

    // MARK: - الرأس

    // كل جزء خلف AnyView: نوع الصفحة كاملاً كان عميقاً لدرجة أن حلّه في الجوال (مكدس الخيط الرئيسي ١ ميغا) يفيض
    // فينهار التطبيق عند فتح الإدارة (٢٠٢٦-١٠-٢٠؛ المحاكي مكدسه ٨ ميغا فلم يظهر). الحدود تقسم الحلّ إلى أجزاء صغيرة.
    private var todayHeader: AnyView { AnyView(todayHeaderContent) }

    /// رأس مختصر (طلب المالك ٢٠٢٦-١٠-٢٢): التحية وتحتها التاريخ في صفّ واحد مع أزرار الرأس — بلا السطر الذكي ولا «صلاحياتي»
    private var todayHeaderContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(helloLine)
                        .dsFont(.hubTitle)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: AdminTodayText.dayLine())
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Hub.greetingLine)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
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
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Hub.headerSide)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, DS.Hub.headerBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }

    /// إجراء من لوحة «حالة النظام» — يدفع بيت الإشارة في مسار «اليوم»
    private func openStatusHome(_ home: AdminStatusPill.Home) {
        navigationPath.append(AdminReviewDestination.status(home))
    }

    /// بطاقة «صلاحياتي» لكل أدوار لوحة الإدارة (طلب المالك ٢٠٢٦-١٠-٢٣ «ضيف صلاحياتي لكل في لوحة الادارة»)
    private var scopeGuide: RoleGuide? {
        authVM.currentUser.flatMap { RoleGuide.forRole($0.role) }
    }

    private var helloLine: String {
        let name = authVM.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hello = AdminTodayText.greeting()
        return name.isEmpty ? hello : L10n.t("\(hello)، \(name)", "\(hello), \(name)")
    }

    // MARK: - المحتوى

    private var todayContent: AnyView { AnyView(todayContentStack) }

    private var todayContentStack: some View {
        let items = decisionItems
        let pills = statusPills
        return VStack(spacing: DS.Hub.stackSpacing) {
            // «يحتاج انتباهك» مربّع ثابت واحد يصعد فوق حافة الرأس (طلب المالك ٢٠٢٦-١٠-٢٢: بلا سحب ولا نقاط؛ «إحصاء الأفراد»
            // انتقل لأعلى «المؤشرات ← العائلة»). سطر «حالة النظام» للمالك والمدير فقط. نوع مستقل خلف `AnyView` (حارس المكدس)،
            // وكل بطاقة تصعد تباعاً (المُعدِّل داخل `AnyView`)
            AnyView(AdminAttentionPanel(counts: counts(items), loading: isInitialLoading,
                                        status: pills.isEmpty ? nil : AdminSystemStatus(pills: pills),
                                        open: openStatusHome)
                .dsCardCascade(0, appeared: appeared))
            AnyView(areasSection().dsCardCascade(1, appeared: appeared))
            if let guide = scopeGuide {
                AnyView(AdminScopeLink(guide: guide).dsCardCascade(2, appeared: appeared))
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.xxxl)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .dsTabBarClearance()
        // أرضية اللوحة (`DS.Hub.background`) تبدأ تحت ما يصعد من المربّع فوق الرأس
        .background(alignment: .top) {
            DS.Hub.background
                .padding(.top, DS.Hub.headerOverlap)
                .accessibilityHidden(true)
        }
    }

    // MARK: «حالة النظام» (كانت بطاقة «تنبيهات» ثم سطر نقاط ثم شريحة)

    /// الصيانة · الرصيد · المجدول · بلا إشعارات — للمالك والمدير (نفس ظهور التنبيهات السابقة؛ المراقب والمشرف لا يرونها،
    /// والصيانة والرصيد لمن يرى إعدادات النظام). نفس المخازن بلا جلب جديد
    private var statusPills: [AdminStatusPill] {
        guard authVM.isAdmin else { return [] }
        let notLoaded = L10n.t("لم يُحمَّل بعد", "not loaded yet")
        let notLoadedLine = L10n.t("لم يُحمَّل بعد", "Not loaded yet")
        var list: [AdminStatusPill] = []
        if authVM.canViewSystemSettings {
            let s = appSettingsVM.settings
            if s.updatedAt == nil {
                list.append(AdminStatusPill(home: .maintenance, text: L10n.t("الصيانة: —", "Maintenance: —"),
                                            detail: notLoadedLine, level: .unknown, issue: "",
                                            spoken: L10n.t("وضع الصيانة: \(notLoaded)", "Maintenance mode: \(notLoaded)")))
            } else {
                list.append(s.maintenanceMode
                    ? AdminStatusPill(home: .maintenance, text: L10n.t("الصيانة: مفعّلة", "Maintenance: on"),
                                      detail: L10n.t("الأعضاء يرون شاشة الصيانة", "Members see the maintenance screen"),
                                      level: .urgent, issue: L10n.t("الصيانة مفعّلة", "maintenance on"),
                                      spoken: L10n.t("وضع الصيانة مفعّل", "Maintenance mode is on"))
                    : AdminStatusPill(home: .maintenance, text: L10n.t("الصيانة: مطفأة", "Maintenance: off"),
                                      detail: L10n.t("التطبيق يعمل للجميع", "The app is open to everyone"),
                                      level: .ok, issue: "",
                                      spoken: L10n.t("وضع الصيانة مطفأ", "Maintenance mode is off")))
            }
            // تحت عتبة «منخفض» كهرماني وتحت «عاجل» أحمر (العتبات من السيرفر)
            let level: AdminStatusPill.Level
            let state: String
            let issue: String
            switch sms.level {
            case .good:    level = .ok;      state = "";                                 issue = ""
            case .low:     level = .warn;    state = L10n.t("منخفض", "low");             issue = L10n.t("الرصيد منخفض", "balance low")
            case .urgent:  level = .urgent;  state = L10n.t("منخفض جداً", "very low");   issue = L10n.t("الرصيد منخفض جداً", "balance very low")
            case .unknown: level = .unknown; state = "";                                 issue = ""
            }
            if let balance = sms.status?.balance {
                let points = SmsBalanceText.points(balance)
                let enough = SmsBalanceText.enough(balance)
                list.append(AdminStatusPill(home: .sms, text: L10n.t("الرصيد: \(points) نقطة", "Balance: \(points) points"),
                                            detail: state.isEmpty ? enough : "\(state) · \(enough)", level: level, issue: issue,
                                            spoken: L10n.t("رصيد رسائل رمز الدخول: \(points) نقطة", "Sign-in SMS balance: \(points) points")
                                                + (state.isEmpty ? "" : L10n.t("، \(state)", ", \(state)"))))
            } else {
                list.append(AdminStatusPill(home: .sms, text: L10n.t("الرصيد: —", "Balance: —"), detail: notLoadedLine,
                                            level: level, issue: issue,
                                            spoken: L10n.t("رصيد رسائل رمز الدخول: \(notLoaded)", "Sign-in SMS balance: \(notLoaded)")))
            }
        }
        // الإشعارات المجدولة: اليوم كهرماني، ولاحقاً أو لا شيء أخضر
        let dates = notificationVM.scheduledNotifications.compactMap(\.scheduledDate)
        let today = dates.filter { Calendar.current.isDateInToday($0) }.count
        let later = dates.count - today
        let laterLine = later > 0 ? L10n.t("لاحقاً \(later)", "\(later) later") : nil
        list.append(today > 0
            ? AdminStatusPill(home: .scheduled, text: L10n.t("مجدول: \(today) اليوم", "Scheduled: \(today) today"),
                              detail: [L10n.t("يُرسل اليوم", "Goes out today"), laterLine].compactMap { $0 }.joined(separator: " · "),
                              level: .warn, issue: L10n.t("مجدول اليوم \(today)", "\(today) scheduled today"),
                              spoken: L10n.t("إشعارات مجدولة اليوم: \(today)", "Notifications scheduled today: \(today)"))
            : AdminStatusPill(home: .scheduled, text: L10n.t("مجدول: 0 اليوم", "Scheduled: 0 today"),
                              detail: laterLine ?? L10n.t("لا إشعارات مجدولة", "No scheduled notifications"),
                              level: .ok, issue: "",
                              spoken: later > 0
                                ? L10n.t("إشعارات مجدولة لاحقاً: \(later)", "Notifications scheduled later: \(later)")
                                : L10n.t("لا إشعارات مجدولة", "No scheduled notifications")))
        // أجهزة لا تصلها الإشعارات = التسجيلات الفاشلة فقط (الدفعة ١٤ «تم غير») — نفس رقم صفحتها. «لم يُفتح منذ 30 يوماً»
        // معلومة في صفحة الأجهزة لا تنبيه هنا
        if let reach = devices.stats {
            let n = reach.invalid
            let devicesText = L10n.isArabic
                ? (n == 0 ? "0" : AdminTodayText.arabicCount(n, one: "جهاز", two: "جهازان", few: "أجهزة", many: "جهازاً", single: "جهاز"))
                : (n == 1 ? "1 device" : "\(n) devices")
            list.append(n == 0
                ? AdminStatusPill(home: .devices, text: L10n.t("بلا إشعارات: 0", "Not reached: 0"),
                                  detail: L10n.t("كل التسجيلات سليمة", "Every registration is valid"),
                                  level: .ok, issue: "",
                                  spoken: L10n.t("كل تسجيلات الأجهزة سليمة، الإشعارات تصلها", "Every device registration is valid, notifications reach them"))
                : AdminStatusPill(home: .devices, text: L10n.t("بلا إشعارات: \(devicesText)", "Not reached: \(devicesText)"),
                                  detail: L10n.t("تسجيل فاشل — لا يُرسل لها شيء", "Failed registration — nothing is sent to them"),
                                  level: .warn, issue: L10n.t("\(devicesText) بلا إشعارات", "\(devicesText) not reached"),
                                  spoken: L10n.t("أجهزة لا تصلها الإشعارات: \(n)", "Devices not reached by notifications: \(n)")))
        } else {
            list.append(AdminStatusPill(home: .devices, text: L10n.t("بلا إشعارات: —", "Not reached: —"), detail: notLoadedLine,
                                        level: .unknown, issue: "",
                                        spoken: L10n.t("أجهزة لا تصلها الإشعارات: \(notLoaded)",
                                                       "Devices not reached by notifications: \(notLoaded)")))
        }
        return list
    }

    // MARK: الأقسام

    /// «الأقسام» (طلب المالك ٢٠٢٦-١٠-٢٤ «الايقونات بالمنتصف مع المسميات»): عنوان صغير ثم مربّعات بالمنتصف — الأيقونة بلون
    /// القسم فوق والاسم تحتها (`AdminHubTile`)، ٣ أعمدة × صفّان، وعمودان حين يرى الدور قسمين أو أربعة أو مع الخط الكبير
    /// جداً، وعمود صفوف من أحجام إمكانية الوصول (`AdminTileGrid`). شارة على أيقونة «الوارد» بما ينتظر القرار، وعلى
    /// «المناسبات» بالوفيات التي لم يُعلن عنها (المالك والمدير) — رقم حيّ يفتح بيته فقط. كل مربّع يفتح صفحة القسم بقيمة في
    /// المسار، فيستبدلها شريط الأقسام بلا تراكم
    private func areasSection() -> some View {
        let areas = visibleAreas
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("الأقسام", "Sections"))
            AdminTileGrid(count: areas.count) {
                ForEach(Array(areas.enumerated()), id: \.element) { index, area in
                    NavigationLink(value: AdminReviewDestination.area(area, 0)) {
                        AdminHubTile(icon: area.icon, fill: area.fill, title: area.title,
                                     badge: areaBadge(area), badgeFill: areaBadgeFill(area),
                                     badgeSpoken: areaBadgeSpoken(area), index: index, hint: area.subtitle)
                    }
                    .buttonStyle(AdminTilePressStyle())
                }
            }
        }
    }

    /// الشارة على أيقونة القسم: «الوارد» ما ينتظر القرار في مجال الدور، و«المناسبات» وفاة لم يُعلن عنها — وإلا لا شيء
    private func areaBadge(_ area: AdminArea) -> AdminTileBadge.Kind? {
        guard !isInitialLoading else { return nil }
        switch area {
        case .inbox:     return inboxTotal > 0 ? .count(inboxTotal) : nil
        case .occasions: return unannounced.isEmpty ? nil : .count(unannounced.count)
        default:         return nil
        }
    }

    /// العدد أحمر (بانتظار القرار)، والوفاة كهرماني هادئ (تنبيه لا خطأ)
    private func areaBadgeFill(_ area: AdminArea) -> Color {
        area == .occasions ? DS.Color.warningFill : DS.Color.errorFill
    }

    private func areaBadgeSpoken(_ area: AdminArea) -> String? {
        switch area {
        case .inbox:     return L10n.t("\(inboxTotal) بانتظار القرار", "\(inboxTotal) awaiting a decision")
        case .occasions: return L10n.t("وفاة لم يُعلن عنها: \(unannounced.count)", "Deaths not announced: \(unannounced.count)")
        default:         return nil
        }
    }
}

/// يبني الصفحة عند ظهورها فقط (لا عند بناء اللوحة) — كانت كلها تُنسخ في مكدّس اللوحة فينغلق التطبيق (٢٠٢٦-١٠-٠٥)
struct AdminLazyPage: View {
    let make: () -> AnyView
    var body: some View { make() }
}

// MARK: - «المنجز اليوم»

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

// MARK: - «يحتاج انتباهك» (المربّع الثابت تحت الرأس)

/// مربّع «يحتاج انتباهك» (الدفعة ٩ لوحة زجاجية في الرأس؛ الدفعة ١٠ صفحة في مربّع يُسحب؛ ٢٠٢٦-١٠-٢٢ مربّع أبيض ثابت واحد
/// بلا سحب ولا نقاط — «إحصاء الأفراد» انتقل لأعلى «المؤشرات ← العائلة»): العنوان، ثم الأرقام الأربعة بأيقوناتها وأسمائها
/// (بخطوط رفيعة بينها، تعدّ من الصفر): بانتظار قرارك · عاجل · متأخر ← «الوارد» بفلتره، ورسائل ← رسائل الأعضاء؛ ثم سطر
/// «حالة النظام» (المالك والمدير فقط) بتعبئة خفيفة من لونه يفتح لوحة الإشارات الأربع. من أحجام إمكانية الوصول الأرقام ٢×٢.
/// الدفعة ١٣ («الى داخله نكبر»): الأرقام بخط رقم الرأس `hubKPI` وأسماؤها `hubLabel`، وسطر الحالة `hubRow`، وفراغات أضيق.
/// القارئ الصوتي: حاوية «يحتاج انتباهك» فيها كل رقم زرّاً ثم سطر الحالة
struct AdminAttentionPanel: View {
    let counts: AdminTodayCounts
    let loading: Bool
    /// nil = بلا سطر حالة (المراقب والمشرف)
    let status: AdminSystemStatus?
    let open: (AdminStatusPill.Home) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Item: Identifiable {
        let id: String
        let value: Int
        let label: String
        let icon: String
        let tint: Color
        /// فلتر «الوارد» — nil = رسائل الأعضاء
        let filter: ApprovalListFilter?
    }

    private var items: [Item] {
        [
            Item(id: "waiting", value: counts.waiting, label: L10n.t("بانتظار قرارك", "Awaiting you"), icon: "tray",
                 tint: DS.Color.accent, filter: .waiting),
            Item(id: "urgent", value: counts.urgent, label: L10n.t("عاجل", "Urgent"), icon: "flame",
                 tint: DS.Color.error.dsReadableGlyph, filter: .urgent),
            Item(id: "late", value: counts.late, label: L10n.t("متأخر", "Late"), icon: "clock",
                 tint: DS.Color.warning.dsReadableGlyph, filter: .late),
            Item(id: "messages", value: counts.unreadMessages, label: L10n.t("رسائل", "Messages"), icon: "bubble.left",
                 tint: DS.Color.textPrimary, filter: nil)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.swipeGap) {
            AdminCardHeader(title: L10n.t("يحتاج انتباهك", "Needs your attention"))
            numbers
            if let status {
                AnyView(AdminSystemStatusLine(status: status, open: open))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous))
            }
        }
        .padding(DS.Hub.swipePadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
        .adminCard(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("يحتاج انتباهك", "Needs your attention"))
    }

    @ViewBuilder
    private var numbers: some View {
        let list = items
        if typeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                HStack(spacing: 0) { cell(list[0], divided: false); cell(list[1], divided: true) }
                hairline(horizontal: true)
                HStack(spacing: 0) { cell(list[2], divided: false); cell(list[3], divided: true) }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    cell(item, divided: index > 0)
                }
            }
        }
    }

    /// رقم يفتح «الوارد» بفلتره (أو الرسائل)، وخطّ رفيع على طرفه الأول بينه وبين ما قبله
    private func cell(_ item: Item, divided: Bool) -> some View {
        let filter = item.filter
        return NavigationLink {
            AdminLazyPage {
                filter.map { AnyView(AdminAllRequestsView(initialFilter: $0).adminArea(.inbox)) }
                    ?? AnyView(AdminAllRequestsView(startsWithMessages: true).adminArea(.inbox))
            }
        } label: {
            AdminAttentionNumber(value: loading ? nil : item.value, label: item.label, icon: item.icon, tint: item.tint)
        }
        .buttonStyle(DSPressStyle())
        .overlay(alignment: .leading) {
            if divided {
                hairline(horizontal: false).padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    private func hairline(horizontal: Bool) -> some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke))
            .frame(width: horizontal ? nil : DS.Border.width, height: horizontal ? DS.Border.width : nil)
            .accessibilityHidden(true)
    }
}

/// رقم في «يحتاج انتباهك»: الرقم بلون معناه على البطاقة (ذهبي، أحمر، كهرماني، أساسي) وتحته الأيقونة والاسم بالثانوي،
/// في وسط عموده. الرقم يعدّ من الصفر حين يصل (`DSCountText`، الدفعة ١٠ «الأرقام تعدّ»). خط الجهاز أكبر من الافتراضي: الاسم
/// على سطرين محجوزين فتبقى الأعمدة بطول واحد (بلا `fixedSize`). الدفعة ١٣: الرقم `hubKPI` (كان `hubPulse`) والاسم
/// `hubLabel` (كان `caption`)
struct AdminAttentionNumber: View {
    /// nil = لم يُحمَّل («—»)
    let value: Int?
    let label: String
    let icon: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let wraps = typeSize > .large
        VStack(spacing: DS.Spacing.xxs) {
            DSCountText(value: value)
                .dsFont(.hubKPI)
                .monospacedDigit()
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold)
                Text(label)
                    .dsFont(.hubLabel)
                    .lineLimit(wraps ? 2 : 1, reservesSpace: wraps)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value.map { "\($0)" } ?? "—")")
    }
}

/// سطر «حالة النظام» أسفل «يحتاج انتباهك» (كان شريحة تحت المربّعات — الدفعة ٨): «✓ النظام سليم» أخضر، «⚠︎ تنبيه /
/// تنبيهان / 3 تنبيهات للنظام» كهرماني وأحمر إن كان فيها عاجل (الصيانة مفعّلة، الرصيد تحت «عاجل»)، و«حالة النظام» محايدة
/// ما دام شيء لم يُحمَّل؛ ثم «⌄» في الطرف. الضغط يفتح لوحة صغيرة منه (`AdminSystemStatusPanel`) بالإشارات وإجراء صغير
/// لكلٍّ؛ البيت يُدفع في مسار «اليوم» بعد أن تختفي اللوحة (الرابط داخل النافذة المنبثقة لا يدفع في هذا المكدس). لمس ٤٤
/// بعرض اللوحة، والقارئ الصوتي يقرأ الملخّص كاملاً («حالة النظام: تنبيهان — الرصيد منخفض، 3 أجهزة بلا إشعارات»)
struct AdminSystemStatusLine: View {
    let status: AdminSystemStatus
    let open: (AdminStatusPill.Home) -> Void
    @State private var showsPanel = false
    /// بيت اختير من اللوحة — يُفتح حين تختفي
    @State private var pending: AdminStatusPill.Home?

    var body: some View {
        Button { showsPanel = true } label: {
            AdminSystemStatusLineLabel(status: status)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spoken)
        .accessibilityHint(L10n.t("يعرض الحالة والإجراءات", "Shows the status and actions"))
        .accessibilityAddTraits(.isButton)
        .modifier(AdminStatusPanelPresenter(isPresented: $showsPanel) {
            AdminSystemStatusPanel(pills: status.pills) { home in
                pending = home
                showsPanel = false
            }
            .onDisappear {
                guard let home = pending else { return }
                pending = nil
                open(home)
            }
        })
    }

    /// بيت كل إشارة: الصيانة ← «التطبيق» (فيها مجموعة «التشغيل»)، الرصيد ← «رسائل رمز الدخول»، المجدول ← «المناسبات»
    /// (القادم)، الأجهزة ← «الأجهزة ووصول الإشعارات»
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

/// شكل السطر على البطاقة: رمز الحالة + النص بلون الحالة على تعبئة خفيفة منه (زوايا مدوّرة أسفل الصفحة)، و«⌄» في الطرف
/// (تعبئة رمادية والنص ثانوي ما دام شيء لم يُحمَّل)
struct AdminSystemStatusLineLabel: View {
    let status: AdminSystemStatus

    var body: some View {
        let tone = status.tone
        HStack(spacing: DS.Spacing.xsm) {
            if let icon = Self.icon(tone) {
                Image(systemName: icon).dsGlyph(DS.Glyph.md, weight: .bold)
                    // «نبضة للعاجل» (الدفعة ١٠): هالة حمراء هادئة على الساعة المشتركة — تقف خارج الشاشة ومع «تقليل الحركة»
                    .dsUrgentPulse(DS.Color.error, active: tone == .urgent)
            }
            // الدفعة ١٣: درجة أكبر (كان `hubButton` Footnote ١٣)
            Text(verbatim: status.title)
                .dsFont(.hubRow)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.sm)
            Image(systemName: "chevron.down").dsGlyph(DS.Glyph.sm, weight: .bold)
        }
        .foregroundColor(Self.ink(tone))
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
        .background(Self.fill(tone))
        .contentShape(Rectangle())
    }

    private static func icon(_ tone: AdminSystemStatus.Tone) -> String? {
        switch tone {
        case .ok:            return "checkmark"
        case .warn, .urgent: return "exclamationmark.triangle.fill"
        case .loading:       return nil
        }
    }

    /// لون الحالة على البطاقة (ألوان المعنى، الدفعة ١٠): سليم `success`، تنبيه `warning`، عاجل `error`
    private static func base(_ tone: AdminSystemStatus.Tone) -> Color? {
        switch tone {
        case .ok:      return DS.Color.success
        case .warn:    return DS.Color.warning
        case .urgent:  return DS.Color.error
        case .loading: return nil
        }
    }

    private static func ink(_ tone: AdminSystemStatus.Tone) -> Color {
        base(tone)?.dsReadableGlyph ?? DS.Color.textSecondary
    }

    private static func fill(_ tone: AdminSystemStatus.Tone) -> Color {
        base(tone).map { $0.opacity(DS.Hub.statusLineFill) } ?? DS.Color.cardBackgroundSoft
    }
}

/// اللوحة: نافذة منبثقة من سطر «حالة النظام» نفسه من iOS 16.4 (`presentationCompactAdaptation(.popover)` — لا ورقة في الآيفون)
/// على سطح التطبيق المصمت (لا زجاج يشفّ الكحلي خلفه)، وتحتها من iOS 18 (السهم في أعلى اللوحة)؛ وقبل 16.4 مربّع صغير بالمنتصف (`dsCenterBox`)
private struct AdminStatusPanelPresenter<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let panel: () -> Panel

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                panel()
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(DS.Color.surface)
            }
        } else if #available(iOS 16.4, *) {
            content.popover(isPresented: $isPresented) {
                panel()
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(DS.Color.surface)
            }
        } else {
            content.dsCenterBox(isPresented: $isPresented, onBackgroundTap: { isPresented = false }) {
                ScrollView { panel().dsPanelContentHeight(extra: 0) }
            }
        }
    }
}

/// لوحة «حالة النظام»: عنوان صغير ثم صفّ لكل إشارة — نقطة اللون (معاني التطبيق: نجاح/تحذير/خطأ)، الحالة («الرصيد: 17
/// نقطة») وسطر ثانٍ، وإجراء صغير في الطرف («الإعدادات»، «اشحن»، «القادم»، «الأجهزة»). الصفّ كله زرّ بلمس ٤٤، ويقرؤه
/// القارئ الصوتي بالحالة كاملة والإجراء تلميحاً. من أحجام إمكانية الوصول: أعرض، والإجراء تحت النص، واللوحة تتمرّر
struct AdminSystemStatusPanel: View {
    let pills: [AdminStatusPill]
    let choose: (AdminStatusPill.Home) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView(showsIndicators: false) { list }
            } else {
                // بارتفاعها كاملاً (لا تنضغط الصفوف إن ضاق المكان — النافذة تختار جهة تتّسع لها)
                list.fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("حالة النظام", "System status"))
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, DS.Spacing.xxs)
            // الحالات السليمة لا تُعرض (الصيانة مطفأة، لا مجدول، لا أجهزة فاشلة): تبقى الأرقام المهمة فقط.
            // الرصيد يبقى ظاهراً دائماً (حتى وهو سليم)
            let shown = pills.filter { $0.level != .ok || $0.home == .sms }
            if shown.allSatisfy({ $0.level == .ok }) {
                Text(verbatim: "✓ " + L10n.t("النظام سليم", "All systems OK"))
                    .dsFont(.hubRow)
                    .foregroundColor(Self.dot(.ok))
                    .padding(.vertical, DS.Spacing.sm)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, pill in
                if index > 0 { AdminRowDivider() }
                row(pill)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .frame(width: typeSize.isAccessibilitySize ? DS.Hub.statusPanelWidthLarge : DS.Hub.statusPanelWidth,
               alignment: .leading)
    }

    private func row(_ pill: AdminStatusPill) -> some View {
        let large = typeSize.isAccessibilitySize
        let action = AdminPillLabel(title: pill.actionTitle, style: pill.isFlagged ? .navy : .soft)
        return Button { choose(pill.home) } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                AdminBaselineDot(color: Self.dot(pill.level))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: pill.text)
                        .dsFont(.hubRow)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: pill.detail)
                        .dsFont(.footnote)
                        .foregroundColor(pill.isFlagged ? Self.dot(pill.level) : DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if large { action.padding(.top, DS.Spacing.xs) }
                }
                Spacer(minLength: DS.Spacing.sm)
                if !large { action }
            }
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.spoken)
        .accessibilityHint(pill.actionTitle)
        .accessibilityAddTraits(.isButton)
    }

    private static func dot(_ level: AdminStatusPill.Level) -> Color {
        switch level {
        case .ok:      return DS.Color.success
        case .warn:    return DS.Color.warning
        case .urgent:  return DS.Color.error
        case .unknown: return DS.Color.textTertiary
        }
    }
}

/// نقطة لون على وسط السطر الأول من النص بجانبها (في `HStack` بمحاذاة `.firstTextBaseline`) — تكبر قليلاً مع خط الجهاز
struct AdminBaselineDot: View {
    let color: Color
    var size: CGFloat = DS.Hub.statusDot
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    var body: some View {
        // تكبر مع خط الجهاز حتى ١٫٦ مرة
        let side = size * min(max(scale, 1), 1.6)
        Circle()
            .fill(color)
            .frame(width: side, height: side)
            // مركزها فوق خطّ الكتابة بنصف ارتفاع الحروف تقريباً (٣٫٥ نقطة بالخط الافتراضي)
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 3.5 * scale }
            .accessibilityHidden(true)
    }
}

// MARK: - «إحصاء الأفراد»

/// بطاقة «إحصاء الأفراد» (كانت «أعداد الأعضاء»؛ تصميم «ثلاث دوائر» اختيار المالك ٢٠٢٦-١٠-٢٠، الدفعة ٩): ثلاث حلقات
/// متجاورة — الإجمالي · الرجال · النساء. في وسط كل حلقة عددها الكلي، والحلقة نسبة الأحياء إلى المتوفين: الأحياء بلون الحلقة
/// (الإجمالي ذهبي «اليوم» `DS.Color.accent` — حبر قسم الإدارة هو كحلي الرجال نفسه فلا تتميّز به — والرجال `male` والنساء
/// `female`)، والمتوفون رمادي المتوفين الخافت `DS.Color.deceased` (لا أحمر). تحت الحلقة اسمها و«54 حياً · 14 متوفى»
/// (`AdminTodayText.arabicCount`؛ سطران إن ضاق). ثم شريحة «✓ الأعضاء المسجّلون N ›». بيتها أعلى «المؤشرات ← العائلة»
/// (`AdminAnalyticsView`، ٢٠٢٦-١٠-٢٢ — كانت الصفحة الثانية من مربّع «اليوم» المسحوب). كل رقم يفتح صفحته:
/// الإجمالي بلا رابط (الصفحة نفسها)، الرجال ← صفحة الأعضاء (و«متوفى» الرجال ← شريحة «متوفون»)، النساء ← شجرة النساء،
/// المسجّلون ← شريحة «مسجّلون». الحلقات `DS.Ring.census` (الدفعة ١٣: درجة فوق المتوسطة والرقم `hubKPI`، والسطر `hubLabel`،
/// والشريحة بارتفاعها المرئي ولمس ٤٤ بلا إزاحة). مع XXXL تصغر الحلقات قليلاً وتلتفّ الأسماء؛ من أحجام إمكانية الوصول كل حلقة كتلة (حلقة
/// صغيرة بجانب الاسم والعدد، ثم الأحياء والمتوفون صفّين بلمس ٤٤). الحلقات من المكوّن الموحّد (`DSRingGauge`، الدفعة ١٠ — مرجع كل مؤشرات اللوحة)، بلا Charts.
/// نفس التعريفات: الرجال = الشجرة بلا طلبات الانضمام، النساء = إناث شجرة النساء، المسجّلون = لهم حساب دخول.
/// «أحياء (تقديري)» (الدفعة ١٢): ما دام في كبار السن من بلا وفاة مسجّلة ولم يُراجَع («تحقق من الأحياء» ناقص «حي ✓»
/// المحلية) فأحياء الرجال والإجمالي «≈» وفي رأس البطاقة شارة «أحياء (تقديري)» تشرح العدد وتفتح الشريحة؛ و«≈ أحياء» نفسها
/// تفتح الشريحة. المقاس والتخطيط كما هما (الشارة في سطر العنوان).
struct AdminMemberCountsCard: View {
    let counts: AdminMemberCounts
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @State private var showEstimate = false
    @State private var openVerify = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    fileprivate enum Target { case overview, directory, deceased, women, accounts, verify }

    /// مرشّحو «تحقق من الأحياء» الذين لم يراجعهم المستخدم بعد
    private var unverified: Int { counts.oldLiving.map { $0.subtracting(verified.ids).count } ?? 0 }
    private var estimated: Bool { unverified > 0 }

    fileprivate struct Gauge: Identifiable {
        let id: String
        let title: String
        let tint: Color
        let total: Int?
        let alive: Int?
        let deceased: Int?
        /// الحلقة والاسم والأحياء
        let main: Target
        /// «N متوفى»
        let deceasedTarget: Target
        /// الأحياء تقديريون (الرجال والإجمالي ما دام في «تحقق من الأحياء» من لم يُراجَع)
        var estimated = false
        var split: Bool { deceasedTarget != main }
        /// «≈ N حياً» تفتح «تحقق من الأحياء»
        var aliveTarget: Target { estimated ? .verify : main }
    }

    private var gauges: [Gauge] {
        [
            Gauge(id: "total", title: L10n.t("الإجمالي", "Total"), tint: DS.Color.accent,
                  total: counts.total, alive: counts.totalAlive, deceased: counts.totalDeceased,
                  main: .overview, deceasedTarget: .overview, estimated: estimated),
            Gauge(id: "men", title: L10n.t("الرجال", "Men"), tint: DS.Color.male,
                  total: counts.men, alive: counts.menAlive, deceased: counts.menDeceased,
                  main: .directory, deceasedTarget: .deceased, estimated: estimated),
            Gauge(id: "women", title: L10n.t("النساء", "Women"), tint: DS.Color.female,
                  total: counts.women, alive: counts.womenAlive, deceased: counts.womenDeceased,
                  main: .women, deceasedTarget: .women)
        ]
    }

    /// كتل عمودية من أحجام إمكانية الوصول
    private var stacked: Bool { typeSize.isAccessibilitySize }

    /// مقاس الحلقة: حلقة «إحصاء الأفراد»، وأصغر قليلاً مع XXXL (الأسماء والأعداد أكبر)
    private var ringSize: DS.Ring.Size { typeSize >= .xxxLarge ? DS.Ring.censusCompact : DS.Ring.census }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.swipeGap) {
            AdminCardHeader(title: L10n.t("إحصاء الأفراد", "Family census")) {
                if estimated { estimatePill }
            }
            if stacked {
                AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(gauges) { block($0) }
                })
            } else {
                // صفّ واحد دائماً — في الوضع الأفقي بعرض عمود القراءة في الوسط (لا تتباعد الحلقات على عرض البطاقة كله)
                AnyView(HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(gauges) { column($0) }
                }
                .frame(maxWidth: landscape ? DS.Landscape.maxContentWidth : .infinity)
                .frame(maxWidth: .infinity))
            }
            registeredChip
                .frame(maxWidth: .infinity, alignment: stacked ? .leading : .center)
        }
        // أعلى «المؤشرات ← العائلة» (٢٠٢٦-١٠-٢٢؛ كان الصفحة الثانية من مربّع «اليوم» المسحوب) — بحشوة مربّع «يحتاج انتباهك»
        .padding(DS.Hub.swipePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
        .adminCard(padding: 0)
        .modifier(AdminEstimateInfo(unverified: unverified, show: $showEstimate, open: $openVerify))
    }

    // MARK: «أحياء (تقديري)»

    /// شارة صغيرة في سطر العنوان (بلا تغيير في ارتفاعه — منطقة اللمس ٤٤ بلا إزاحة)
    private var estimatePill: some View {
        Button { showEstimate = true } label: {
            HStack(spacing: DS.Spacing.xxs + 1) {
                Image(systemName: "info.circle")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    .accessibilityHidden(true)
                Text(L10n.t("أحياء (تقديري)", "Living (estimate)"))
                    .dsFont(.badge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(DS.Color.warning.dsReadableGlyph)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs + 1)
            .background(Capsule().fill(DS.Color.warning.opacity(DS.Opacity.tintFill)))
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.section)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("أحياء (تقديري)", "Living (estimate)"))
        .accessibilityHint(Self.estimateText(unverified))
    }

    /// «يشمل N من كبار السن بدون تاريخ وفاة — راجعهم من «تحقق من الأحياء»»
    static func estimateText(_ n: Int) -> String {
        L10n.t("يشمل \(n) من كبار السن بدون تاريخ وفاة — راجعهم من «تحقق من الأحياء»",
               "Includes \(n) elderly members with no death date — review them in “Check the living”")
    }

    // MARK: الحلقات

    /// عمود: الحلقة وعددها في الوسط، ثم الاسم بلونها (رابط واحد)، ثم «54 حياً · 14 متوفى»
    private func column(_ g: Gauge) -> some View {
        let face = VStack(spacing: DS.Spacing.xs) {
            ring(g, size: ringSize)
            Text(g.title)
                .dsFont(.hubRow)
                .foregroundColor(g.tint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(g))
        return VStack(spacing: DS.Spacing.xxs) {
            link(g.main, face: AnyView(face))
            legend(g)
        }
        .frame(maxWidth: .infinity)
    }

    /// «54 حياً · 14 متوفى» في سطر، وسطرين إن ضاق العمود. الأحياء رابط الحلقة نفسها، و«متوفى» الرجال رابط شريحة «متوفون».
    /// القارئ الصوتي قرأ السطر مع الحلقة — يبقى منه «متوفى» الرجال وحده (وجهته مختلفة)
    private func legend(_ g: Gauge) -> some View {
        let alive = link(g.aliveTarget, face: AnyView(legendText(Self.aliveText(g.alive, estimated: g.estimated), color: g.tint)))
            .accessibilityHidden(true)
        let dead = link(g.deceasedTarget, face: AnyView(
            legendText(Self.deceasedText(g.deceased), color: DS.Color.textSecondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("\(g.title)، المتوفون: \(Self.number(g.deceased))",
                                           "\(g.title), deceased: \(Self.number(g.deceased))"))))
            .accessibilityHidden(!g.split)
        let dot = Text(verbatim: "·")
            .dsFont(.hubLabel)
            .foregroundColor(DS.Color.textTertiary)
            .accessibilityHidden(true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) { alive; dot; dead }
            VStack(spacing: 0) { alive; dead }
        }
    }

    private func legendText(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .dsFont(.hubLabel)
            .monospacedDigit()
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, DS.Spacing.xxs)
            .contentShape(Rectangle())
    }

    /// كتلة (أحجام إمكانية الوصول): حلقة صغيرة بجانب الاسم والعدد، ثم الأحياء والمتوفون صفّين بمنطقة لمس كاملة تحت الاسم
    private func block(_ g: Gauge) -> some View {
        let total = Self.number(g.total)
        return VStack(alignment: .leading, spacing: 0) {
            link(g.main, face: AnyView(
                HStack(spacing: DS.Spacing.md) {
                    ring(g, size: DS.Ring.mediumStacked)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(g.title).dsFont(.hubRow).foregroundColor(g.tint)
                        Text(verbatim: total).dsFont(.hubPulse).monospacedDigit().foregroundColor(DS.Color.textPrimary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(g.title): \(total)")))
            link(g.aliveTarget, face: AnyView(blockLine(Self.aliveText(g.alive, estimated: g.estimated), color: g.tint, title: g.title)))
            link(g.deceasedTarget, face: AnyView(blockLine(Self.deceasedText(g.deceased), color: DS.Color.textSecondary,
                                                           title: g.title)))
        }
    }

    private func blockLine(_ text: String, color: Color, title: String) -> some View {
        Text(verbatim: text)
            .dsFont(.hubLabel)
            .monospacedDigit()
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .padding(.leading, DS.Ring.mediumStacked.side + DS.Spacing.md)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)، \(text)")
    }

    /// الحلقة الموحّدة (`DSRingGauge`، مرجع الدفعة ١٠): الأحياء بلونها فوق مسار رمادي المتوفين (الباقي من الدائرة)
    /// والعدد في وسطها يعدّ من الصفر؛ مسار باهت فارغ و«—» قبل وصول الأعداد
    private func ring(_ g: Gauge, size: DS.Ring.Size) -> DSRingGauge {
        let total = g.total ?? 0
        let known = g.alive != nil && total > 0
        return DSRingGauge(progress: known ? Double(g.alive ?? 0) / Double(total) : nil, tint: g.tint, size: size,
                           track: DS.Ring.restTrack, center: .count(g.total))
    }

    // MARK: المسجّلون

    private var registeredChip: some View {
        let value = counts.accounts.map { "\($0)" } ?? "—"
        let shape = RoundedRectangle(cornerRadius: DS.Hub.pillHeightCard / 2, style: .continuous)
        return link(.accounts, face: AnyView(
            HStack(spacing: DS.Spacing.xsm) {
                Image(systemName: "checkmark.seal.fill")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.success.dsReadableGlyph)
                    .accessibilityHidden(true)
                Text(L10n.t("الأعضاء المسجّلون", "Registered members"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: value)
                    .dsFont(.hubButton)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.success.dsReadableGlyph)
                    .contentTransition(.numericText())
                DSChevron(size: DS.Glyph.xs)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xsm)
            .frame(minHeight: DS.Hub.pillHeight)
            .background(shape.fill(DS.Color.success.opacity(DS.Opacity.tintFillSoft)))
            .overlay(shape.strokeBorder(DS.Color.success.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            // لمس ٤٤ بلا فراغ في التخطيط (الدفعة ١٣ — المربّع أقصر)
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.pillHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("الأعضاء المسجّلون: \(value)", "Registered members: \(value)"))))
    }

    // MARK: الروابط

    @ViewBuilder
    private func link(_ target: Target, face: AnyView) -> some View {
        switch target {
        case .overview:
            // «الإجمالي» على بيت الأعداد نفسه («المؤشرات ← العائلة») — لا رابط لصفحته
            face
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
        case .directory: return AnyView(AdminMembersPage().adminArea(.family))
        case .deceased:  return AnyView(AdminMembersPage(chip: .deceased).adminArea(.family))
        case .accounts:  return AnyView(AdminMembersPage(chip: .registered).adminArea(.family))
        case .verify:    return AnyView(AdminMembersPage(chip: .verifyLiving).adminArea(.family))
        case .overview, .women: return AnyView(EmptyView())
        }
    }

    // MARK: النصوص

    private static func number(_ n: Int?) -> String { n.map { "\($0)" } ?? "—" }

    /// «الرجال: 56، 44 حياً، 12 متوفى»
    private static func spoken(_ g: Gauge) -> String {
        [L10n.t("\(g.title): \(number(g.total))", "\(g.title): \(number(g.total))"),
         aliveText(g.alive) + (g.estimated ? L10n.t(" (تقديري)", " (estimate)") : ""),
         deceasedText(g.deceased)].joined(separator: L10n.t("، ", ", "))
    }

    /// «54 حياً» (المعدود بالعربية الصحيحة: حيّ واحد، حيّان، 3 أحياء، 54 حياً)
    /// `estimated`: «≈ 54 حياً» (أحياء تقديريون — «تحقق من الأحياء»)
    private static func aliveText(_ n: Int?, estimated: Bool = false) -> String {
        guard let n else { return L10n.t("— أحياء", "— living") }
        let text = L10n.isArabic ? AdminTodayText.arabicCount(n, one: "حيّ واحد", two: "حيّان", few: "أحياء", many: "حياً", single: "حيّ")
                                 : "\(n) living"
        return estimated ? "≈ " + text : text
    }

    /// «14 متوفى» (متوفى واحد، متوفيان، 3 متوفين، 14 متوفى)
    private static func deceasedText(_ n: Int?) -> String {
        guard let n else { return L10n.t("— متوفون", "— deceased") }
        return L10n.isArabic ? AdminTodayText.arabicCount(n, one: "متوفى واحد", two: "متوفيان", few: "متوفين", many: "متوفى", single: "متوفى")
                             : "\(n) deceased"
    }
}

/// «أحياء (تقديري)»: شرح العدد ثم «تحقق من الأحياء» تفتح صفحة الأعضاء على الشريحة (في نوعه المستقل — حارس المكدس)
private struct AdminEstimateInfo: ViewModifier {
    let unverified: Int
    @Binding var show: Bool
    @Binding var open: Bool

    func body(content: Content) -> some View {
        content
            .dsAlert(L10n.t("أحياء (تقديري)", "Living (estimate)"), isPresented: $show) {
                Button(L10n.t("تحقق من الأحياء", "Check the living")) { open = true }
                Button(L10n.t("إغلاق", "Close"), role: .cancel) {}
            } message: {
                Text(AdminMemberCountsCard.estimateText(unverified))
            }
            .navigationDestination(isPresented: $open) {
                AdminLazyPage { AnyView(AdminMembersPage(chip: .verifyLiving).adminArea(.family)) }
            }
    }
}

/// «صلاحياتي» لكل أدوار الإدارة: ما يقدر عليه دورك وما لا يقدر — يفتح `AdminMyScopeView`
private struct AdminScopeLink: View {
    let guide: RoleGuide

    var body: some View {
        NavigationLink { AdminMyScopeView(guide: guide) } label: {
            HStack(spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: guide.icon, tint: guide.color)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("صلاحياتي", "My permissions"))
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(guide.mandate)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                DSChevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
        .buttonStyle(DSPressStyle())
    }
}
