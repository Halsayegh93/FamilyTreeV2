import SwiftUI

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
    /// «الوارد» مفتوحاً على طلب بعينه (مربّع تفاصيله)
    case inboxItem(UUID)
    /// «رسائل الدخول · KWT SMS» (إشعار «رصيد الرسائل منخفض»)
    case sms
}

// MARK: - لوحة الإدارة ← «اليوم» (إعادة التصميم الكاملة — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// الاتجاه «أ» (مركز القيادة) أساساً + لمستان من «ب»: دوائر الإنجاز للمهام، وسحب «الوارد» مثل البريد.
// «في اردحام بلوحة الادارة بالبداية» → «الأقسام فوق + قائمة وحدة» (اختيار المالك ٢٠٢٦-١٠-٢٠). من الأعلى:
// الرأس الكحلي (التحية، الدور، التاريخ، وأربعة أرقام: بانتظارك · مستعجل · متأخر · رسائل) ← «أعداد الأعضاء» (المالك
// والمدير والمراقب — «ابى اعداد الاعضاء بالتطبيق») ← «الأقسام» الثمانية بتلميح حيّ ← «تنبيهات» (عند المشكلة فقط) ←
// «يحتاج قرارك» قائمة واحدة (القرارات والمهام معاً، أول ٣ و«عرض الكل»). «اليوم في العائلة» انتقل لأعلى «المناسبات»،
// و«نبض العائلة» لأعلى «المؤشرات»، وكل إجراء سريع لأعلى قسمه. كل دور يرى مجاله فقط والقسم الفارغ لا يُرسم (IA.md).
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
    @State private var staleTokens: Int? = nil
    /// «أعداد الأعضاء» — تبدأ من آخر ما حُمّل وتتحدّث مع التحميل
    @State private var memberCounts = AdminMemberCounts.seeded(members: [])

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
                switch destination {
                case .treeEditRequests: AdminTreeEditRequestsView()
                case .allRequests:      AdminAllRequestsView()
                case .inboxItem(let id): AdminAllRequestsView(focusId: id)
                case .sms:              AdminSmsView(backTitle: L10n.t("اليوم", "Today"))
                }
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
        .task { await loadAllAdminData() }
        .onChange(of: memberVM.membersVersion) { _ in recalculate() }
        .onChange(of: pendingRequestsSum) { _ in recalculate() }
        .onChange(of: pendingArchiveCount) { _ in recalculate() }
        .onChange(of: todaySnapshot) { _ in syncTasks() }
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
                group.addTask { @MainActor in staleTokens = await AdminTodayFetch.staleTokenCount() }
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
            if m.isDeceased != true {
                let noPhone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noBirth = (m.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noGender = (m.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let notActivated = m.status == nil || m.status == .pending
                if notActivated || noPhone || noBirth || m.fatherId == nil || noGender { issues += 1 }
            }
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
    }

    /// «أعداد الأعضاء» لمن يرى الإحصائيات (كبطاقة «أفراد العائلة» القديمة): المالك والمدير والمراقب
    private var seesMemberCounts: Bool { authVM.isAdmin || authVM.currentUser?.role == .monitor }

    private var roleGuide: RoleGuide? {
        authVM.currentUser.flatMap { RoleGuide.forRole($0.role) }
    }

    /// مجال المراقب والمشرف (سطر «نطاقي» في الرأس)
    private var scopeGuide: RoleGuide? { authVM.isAdmin ? nil : roleGuide }

    private var visibleAreas: [AdminArea] { AdminArea.allCases.filter { $0.isVisible(for: authVM) } }

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
                NavigationLink { AdminLazyPage { AnyView(AdminSearchView()) } } label: {
                    AdminGlassCircle(symbol: "magnifyingglass")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("بحث في اللوحة", "Search the dashboard"))
                NavigationLink { NotificationsCenterView() } label: {
                    AdminGlassCircle(symbol: "bell", dot: notificationVM.unreadNotificationsCount > 0)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(notificationVM.unreadNotificationsCount > 0
                    ? L10n.t("\(notificationVM.unreadNotificationsCount) إشعار غير مقروء",
                             "\(notificationVM.unreadNotificationsCount) unread notifications")
                    : L10n.t("الإشعارات", "Notifications"))
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
                        Text(L10n.t("نطاقي: \(guide.mandate)", "My scope: \(guide.mandate)"))
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
                kpiLink(AdminKPITile(value: value(c.waiting), label: L10n.t("بانتظارك", "For you"),
                                     icon: "tray", tint: DS.Hub.kpiMine), filter: .waiting)
                kpiLink(AdminKPITile(value: value(c.urgent), label: L10n.t("مستعجل", "Urgent"),
                                     icon: "flame", tint: DS.Hub.kpiHot), filter: .urgent)
                kpiLink(AdminKPITile(value: value(c.late), label: L10n.t("متأخر", "Late"),
                                     icon: "clock", tint: DS.Hub.kpiLate), filter: .late)
                NavigationLink { AdminAllRequestsView(startsWithMessages: true) } label: {
                    AdminKPITile(value: value(c.unreadMessages), label: L10n.t("رسائل", "Messages"),
                                 icon: "bubble.left")
                }
                .buttonStyle(DSPressStyle())
            }
            .padding(.top, DS.Spacing.lg + 2)
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
        NavigationLink { AdminAllRequestsView(initialFilter: filter) } label: { tile }
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
        let alerts = todayAlerts
        let seesCounts = seesMemberCounts
        return VStack(spacing: DS.Hub.stackSpacing) {
            if seesCounts {
                AnyView(AdminMemberCountsCard(counts: memberCounts))
            }
            // بلا «أعداد الأعضاء» (المشرف) تصعد المربّعات نفسها فوق الرأس — عنوان «الأقسام» لا يقع على الكحلي
            AnyView(areasSection(labeled: seesCounts))
            if !alerts.isEmpty {
                AnyView(alertsCard(alerts))
            }
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

    // MARK: تنبيهات

    private var todayAlerts: [AdminTodayAlert] {
        var list: [AdminTodayAlert] = []
        // رصيد رسائل الدخول — تحت عتبة «منخفض» تحذير وتحت «عاجل» خطأ (العتبات من السيرفر، افتراضياً ٥٠/١٠)
        if authVM.canViewSystemSettings, let balance = sms.status?.balance, sms.needsTopUp {
            let urgent = sms.level == .urgent
            list.append(AdminTodayAlert(
                id: "sms", icon: "ellipsis.message.fill", tint: urgent ? DS.Color.error : DS.Color.warning,
                title: urgent ? L10n.t("عاجل: رصيد رسائل الدخول قارب يخلص", "Urgent: sign-in SMS balance nearly out")
                              : L10n.t("رصيد رسائل الدخول منخفض", "Sign-in SMS balance is low"),
                subtitle: L10n.t("\(SmsBalanceText.points(balance)) نقطة · \(SmsBalanceText.enough(balance))",
                                 "\(SmsBalanceText.points(balance)) points · \(SmsBalanceText.enough(balance))"),
                meter: sms.lowThreshold > 0 ? balance / sms.lowThreshold : 0,
                buttonTitle: L10n.t("اشحن", "Top up"), buttonStyle: .navy, action: .sms))
        }
        // تحذير توافق قاعدة البيانات (للكل عند الخلل)
        if !authVM.notificationsFeatureAvailable || !authVM.newsApprovalFeatureAvailable {
            var lines: [String] = []
            if !authVM.notificationsFeatureAvailable {
                lines.append(L10n.t("جدول الإشعارات غير موجود — الإشعارات معطلة", "Notifications table missing"))
            }
            if !authVM.newsApprovalFeatureAvailable {
                lines.append(L10n.t("عمود موافقة الأخبار غير موجود — موافقات الأخبار معطلة", "News approval column missing"))
            }
            list.append(AdminTodayAlert(id: "schema", icon: "exclamationmark.triangle.fill", tint: DS.Color.error,
                                        title: L10n.t("توافق قاعدة البيانات", "Database compatibility"),
                                        subtitle: lines.joined(separator: "\n")))
        }
        // وضع الصيانة مفعّل
        if authVM.canViewSystemSettings && appSettingsVM.settings.maintenanceMode {
            list.append(AdminTodayAlert(id: "maintenance", icon: "wrench.and.screwdriver.fill", tint: DS.Color.warning,
                                        title: L10n.t("وضع الصيانة مفعّل", "Maintenance mode is on"),
                                        subtitle: L10n.t("الأعضاء لا يقدرون يستخدمون التطبيق الآن", "Members can't use the app now"),
                                        buttonTitle: L10n.t("راجع", "Review"), action: .maintenance))
        }
        // وفاة لم يُعلن عنها (المالك والمدير)
        let waiting = unannounced
        if let first = waiting.first {
            let one = waiting.count == 1
            list.append(AdminTodayAlert(
                id: "deaths", icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                title: one ? L10n.t("وفاة لم يُعلن عنها", "Death not announced")
                           : L10n.t("\(waiting.count) وفيات لم يُعلن عنها", "\(waiting.count) deaths not announced"),
                subtitle: one ? first.shortFullName : waiting.prefix(2).map(\.shortFullName).joined(separator: "، "),
                buttonTitle: L10n.t("أعلن", "Announce"),
                action: one ? .announce(DeathAnnouncementTarget(id: first.id, name: first.fullName,
                                                                 isFemale: first.gender == "female",
                                                                 deathDate: first.deathDate))
                            : .deaths))
        }
        // رموز إشعارات قديمة (المالك والمدير)
        if authVM.isAdmin, let stale = staleTokens, stale > 0 {
            list.append(AdminTodayAlert(
                id: "push", icon: "bell.slash.fill", tint: DS.Color.info,
                title: L10n.t("\(stale) أجهزة قد لا تصلها الإشعارات", "\(stale) devices may miss notifications"),
                subtitle: L10n.t("رموز أقدم من 30 يوماً", "Tokens older than 30 days"),
                buttonTitle: L10n.t("راجع", "Review"), action: .pushHealth))
        }
        // إشعار مجدول اليوم
        if authVM.isAdmin, let next = notificationVM.scheduledNotifications
            .compactMap({ n in n.scheduledDate.map { (n, $0) } })
            .filter({ Calendar.current.isDateInToday($0.1) })
            .sorted(by: { $0.1 < $1.1 }).first {
            let f = DateFormatter()
            f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
            f.dateFormat = "h:mm a"
            list.append(AdminTodayAlert(
                id: "scheduled", icon: "clock.badge.checkmark.fill", tint: DS.Color.info,
                title: L10n.t("إشعار مجدول اليوم \(f.string(from: next.1))", "Notification scheduled today \(f.string(from: next.1))"),
                subtitle: next.0.title, buttonTitle: L10n.t("عرض", "View"), action: .scheduled))
        }
        // المراقب: تنبيهات الشجرة فقط
        if authVM.currentUser?.role == .monitor, !isInitialLoading, treeIssuesCount > 0 {
            list.append(AdminTodayAlert(
                id: "tree", icon: "stethoscope", tint: DS.Color.warning,
                title: L10n.t("صحة الشجرة: \(treeIssuesCount) تحتاج مراجعة", "Tree health: \(treeIssuesCount) to review"),
                subtitle: L10n.t("أعضاء بلا أب أو بلا اسم أو برابط مكسور", "Unlinked, unnamed or broken links"),
                buttonTitle: L10n.t("راجع", "Review"), action: .treeHealth))
        }
        return list
    }

    private func alertsCard(_ alerts: [AdminTodayAlert]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("تنبيهات", "Alerts"), badge: alerts.count)
            ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                if index > 0 { AdminRowDivider() }
                alertRow(alert)
            }
        }
        .adminCard()
    }

    private func alertRow(_ alert: AdminTodayAlert) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: alert.icon, tint: alert.tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(alert.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = alert.subtitle {
                    Text(sub)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let meter = alert.meter {
                    AdminMeter(progress: meter, tint: alert.tint.dsReadableGlyph)
                        .padding(.top, DS.Spacing.xs)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let title = alert.buttonTitle, let action = alert.action {
                alertButton(title, style: alert.buttonStyle, action: action)
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func alertButton(_ title: String, style: AdminPillStyle, action: AdminTodayAlert.Action) -> some View {
        switch action {
        case .announce(let target):
            AdminPillButton(title: title, style: style) { DeathAnnouncementPresenter.open(target) }
        default:
            NavigationLink { alertDestination(action) } label: {
                AdminPillLabel(title: title, style: style)
            }
            .buttonStyle(DSPressStyle())
        }
    }

    @ViewBuilder
    private func alertDestination(_ action: AdminTodayAlert.Action) -> some View {
        switch action {
        case .sms:           AdminSmsView(backTitle: L10n.t("اليوم", "Today"))
        case .deaths:        DeathAnnouncementsPage()
        case .announce:      DeathAnnouncementsPage()
        case .pushHealth:    AdminLazyPage { AnyView(AdminPushHealthView()) }
        case .maintenance:   AdminLazyPage { AnyView(AdminAppSettingsView(scope: .maintenance)) }
        case .scheduled:     AdminLazyPage { AnyView(AdminMessagingHubView()) }
        case .treeHealth:    AdminLazyPage { AnyView(AdminTreeHealthView()) }
        }
    }

    // MARK: يحتاج قرارك — قائمة واحدة (القرارات والمهام معاً)

    private static let visibleEntryLimit = 3

    private func decisionCard(_ entries: [AdminTodayEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("يحتاج قرارك", "Needs your decision"),
                            badge: isInitialLoading ? nil : entries.count) {
                if !isInitialLoading {
                    NavigationLink { AdminTodayListView(store: taskStore) } label: {
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

    private func areasSection(labeled: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if labeled {
                AdminSectionLabel(title: L10n.t("الأقسام", "Sections"))
            }
            LazyVGrid(columns: AdminGrid.columns(landscape: landscape), spacing: AdminGrid.spacing) {
                ForEach(visibleAreas) { area in
                    NavigationLink { AdminLazyPage { AnyView(AdminAreaView(area: area)) } } label: {
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
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text(hint.text)
                .dsFont(.caption)
                .foregroundColor(hint.warn ? DS.Color.warning : DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
            let gaps = issueMembersCount + treeIssuesCount
            return gaps > 0 ? (L10n.t("\(gaps) بيانات ناقصة", "\(gaps) data gaps"), false) : (area.subtitle, false)
        case .occasions:
            return (memorial.dashboardCaption, false)
        case .announcements:
            let n = notificationVM.scheduledNotifications.count
            return n > 0 ? (L10n.t("\(n) إشعار مجدول", "\(n) scheduled"), false)
                         : (L10n.t("إشعار أو تحديث للأعضاء", "Notify members or announce"), false)
        case .metrics:
            if let now = activeNow { return (L10n.t("\(now) نشطون الآن", "\(now) active now"), false) }
            let unread = notificationVM.unreadActivityLogCount
            return unread > 0 ? (L10n.t("سجل النشاط · \(unread) جديد", "Activity · \(unread) new"), false)
                              : (area.subtitle, false)
        case .team:
            return (L10n.t("\(moderatorCount) في الفريق", "\(moderatorCount) on the team"), false)
        case .access:
            if let balance = sms.status?.balance {
                return (L10n.t("رصيد الرسائل \(SmsBalanceText.points(balance))", "SMS balance \(SmsBalanceText.points(balance))"),
                        sms.needsTopUp)
            }
            return (area.subtitle, false)
        case .app:
            return appSettingsVM.settings.maintenanceMode
                ? (L10n.t("الصيانة مفعّلة", "Maintenance on"), true)
                : (L10n.t("الصيانة مطفأة", "Maintenance off"), false)
        }
    }
}

/// يبني الصفحة عند ظهورها فقط (لا عند بناء اللوحة) — كانت كلها تُنسخ في مكدّس اللوحة فينغلق التطبيق (٢٠٢٦-١٠-٠٥)
struct AdminLazyPage: View {
    let make: () -> AnyView
    var body: some View { make() }
}

// MARK: - «يحتاج قرارك»: الصفّ، والرابط، و«عرض الكل»

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
        case .inbox(let id): return AnyView(AdminAllRequestsView(focusId: id))
        case .messages:      return AnyView(AdminAllRequestsView(startsWithMessages: true))
        }
    }
}

/// «كل شيء متابَع» — حين لا شيء ينتظر
struct AdminTodayCaughtUpRow: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "checkmark.seal.fill", tint: DS.Color.success)
            Text(L10n.t("كل شيء متابَع — لا شيء ينتظر قرارك", "All caught up — nothing awaits your decision"))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
    }
}

/// مهمة أُنجزت اليوم (في «عرض المنجز»)
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

/// «عرض الكل»: القائمة الموحّدة كاملة + «عرض المنجز» + «الوارد». تقرأ من ذاكرة «اليوم» فتتحدّث وهي مفتوحة
struct AdminTodayListView: View {
    @ObservedObject var store: AdminTodayTaskStore
    @State private var showDone = false

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: L10n.t("يحتاج قرارك", "Needs your decision"),
                            subtitle: L10n.t("الطلبات ورسائل الأعضاء — ما عليك بدائرة، وما عند غيرك بنوعه",
                                             "Requests and member messages — yours with a circle, others' by type"))
        } content: {
            AnyView(listCard)
            AnyView(inboxCard)
        }
    }

    private var listCard: some View {
        let entries = store.entries
        let done = store.done
        return VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("المفتوحة", "Open"), badge: store.loaded ? entries.count : nil) {
                if !done.isEmpty {
                    Button {
                        withAnimation(DS.Anim.snappy) { showDone.toggle() }
                    } label: {
                        AdminCardLinkLabel(title: showDone ? L10n.t("إخفاء المنجز", "Hide done")
                                                           : L10n.t("عرض المنجز (\(done.count))", "Show done (\(done.count))"),
                                           showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !store.loaded {
                DSPageLoader(L10n.t("جارٍ التحميل…", "Loading…"), fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
            } else if entries.isEmpty {
                AdminTodayCaughtUpRow()
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { AdminRowDivider() }
                AdminTodayEntryLink(entry: entry)
            }
            if showDone {
                ForEach(done) { record in
                    AdminRowDivider()
                    AdminTodayDoneRow(record: record)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var inboxCard: some View {
        NavigationLink { AdminLazyPage { AnyView(AdminAllRequestsView()) } } label: {
            AdminListRow(icon: AdminArea.inbox.icon, tint: DS.Color.primary, title: AdminArea.inbox.title,
                         subtitle: L10n.t("كل الطلبات بالنوع والمهلة، ورسائل الأعضاء", "Every request by type and SLA, and messages")) {
                if store.loaded {
                    Text(verbatim: "\(store.inboxTotal)")
                        .dsFont(.chip)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

// MARK: - «أعداد الأعضاء»

/// بطاقة «أ» مدمجة تحت الرأس: الأفراد · الرجال · النساء · الحسابات المفعّلة — كل رقم يفتح قائمته الموجودة
/// (نظرة الأعضاء، السجل، شجرة النساء، «فعّال» في استخدام التطبيق). أربعة أعمدة، ومربّعان×مربّعين مع النص الكبير.
struct AdminMemberCountsCard: View {
    let counts: AdminMemberCounts
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsLandscape) private var landscape

    fileprivate enum Target { case overview, directory, women, accounts }

    fileprivate struct Cell: Identifiable {
        let id: String
        let label: String
        let value: Int?
        let note: String?
        let tint: Color
        let target: Target
    }

    private var cells: [Cell] {
        func alive(_ n: Int?) -> String? { n.map { L10n.t("\($0) أحياء", "\($0) alive") } }
        return [
            Cell(id: "total", label: L10n.t("الأفراد", "Members"), value: counts.total,
                 note: alive(counts.totalAlive), tint: DS.Color.textPrimary, target: .overview),
            Cell(id: "men", label: L10n.t("الرجال", "Men"), value: counts.men,
                 note: alive(counts.menAlive), tint: DS.Color.male, target: .directory),
            Cell(id: "women", label: L10n.t("النساء", "Women"), value: counts.women,
                 note: alive(counts.womenAlive), tint: DS.Color.female, target: .women),
            Cell(id: "accounts", label: L10n.t("الحسابات المفعّلة", "Active accounts"), value: counts.accounts,
                 note: counts.living.map { L10n.t("من \($0) حيّاً", "of \($0) living") },
                 tint: DS.Color.success, target: .accounts)
        ]
    }

    /// صفّ واحد بأربعة أعمدة، أو صفّان بعمودين مع النص الكبير (عمودياً)
    private var rows: [[Cell]] {
        let all = cells
        guard typeSize >= .xxLarge && !landscape else { return [all] }
        return [Array(all.prefix(2)), Array(all.suffix(2))]
    }

    var body: some View {
        let rows = self.rows
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            AdminCardHeader(title: L10n.t("أعداد الأعضاء", "Member counts"))
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    if r > 0 { AdminRowDivider() }
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { i, cell in
                            if i > 0 { AdminColumnDivider() }
                            link(cell)
                                .padding(.leading, i == 0 ? 0 : DS.Spacing.sm)
                                .padding(.trailing, i == row.count - 1 ? 0 : DS.Spacing.sm)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    @ViewBuilder
    private func link(_ cell: Cell) -> some View {
        switch cell.target {
        case .women:
            // شجرة النساء تُدار من تبويب الشجرة (كصفّ «شجرة النساء» في «العائلة»)
            Button {
                TreeTabContainer.openWomenOnAppear = true
                NotificationCenter.default.post(name: .openWomenTree, object: nil)
            } label: { cellView(cell) }
            .buttonStyle(DSPressStyle())
        default:
            NavigationLink { AdminLazyPage { Self.page(cell.target) } } label: { cellView(cell) }
                .buttonStyle(DSPressStyle())
        }
    }

    private func cellView(_ cell: Cell) -> some View {
        let value = cell.value.map { "\($0)" } ?? "—"
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: value)
                .dsFont(.hubPulse)
                .monospacedDigit()
                .foregroundColor(cell.tint.dsReadableGlyph)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(cell.label)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let note = cell.note {
                Text(verbatim: note)
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([cell.label + ": " + value, cell.note].compactMap { $0 }.joined(separator: "، "))
    }

    private static func page(_ target: Target) -> AnyView {
        switch target {
        case .overview:  return AnyView(AdminMembersManagementView(initialTab: .overview))
        case .directory: return AnyView(AdminMembersManagementView(initialTab: .directory))
        case .accounts:  return AnyView(AppUsageMembersView(category: .active))
        case .women:     return AnyView(EmptyView())
        }
    }
}
