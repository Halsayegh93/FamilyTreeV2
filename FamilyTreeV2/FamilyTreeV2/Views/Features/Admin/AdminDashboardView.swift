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
// الاتجاه «أ» (مركز القيادة) أساساً + لمستان من «ب»: «مهام اليوم» بدوائر الإنجاز، وسحب «الوارد» مثل البريد.
// من الأعلى: الرأس الكحلي (التحية، الدور، التاريخ، وأربعة أرقام: بانتظارك · مستعجل · متأخر · رسائل — «اللوحة العلوي
// ب أ ممتازه») ← «تنبيهات» (تظهر عند المشكلة فقط) ← «يحتاج قرارك» (أول ٣ بأولوية المهلة) ← «مهام اليوم» ← «اليوم في
// العائلة» ← إجراءات سريعة ← «نبض العائلة» ← «الأقسام» الثمانية بتلميح حيّ. كل دور يرى مجاله فقط والقسم الفارغ
// لا يُرسم (IA.md). الصلاحيات والوجهات والروابط العميقة كما كانت، والصفحات القديمة تُفتح كما هي.

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
    @State private var joinedThisWeek = 0
    /// المعلن عنهم — nil = تعذّر الجلب (لا تنبيه «لم يُعلن» خطأً)
    @State private var announcedIds: Set<UUID>? = nil
    @State private var activeNow: Int? = nil
    @State private var staleTokens: Int? = nil
    @State private var weekly: (executed: Int, rejected: Int)? = nil
    /// «عرض المنجز» في «مهام اليوم»
    @State private var showDoneTasks = false

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
        .onChange(of: taskSignature) { _ in syncTasks() }
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
        let seesReport = isAdmin || authVM.currentUser?.role == .monitor
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
            if seesReport {
                group.addTask { @MainActor in
                    if adminRequestVM.approvalsWorkflowOn {
                        weekly = await AdminTodayFetch.weeklyDone()
                    }
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
        var moderator = 0, issues = 0, treeIssues = 0, joined = 0
        let moderatorRoles: Set<FamilyMember.UserRole> = [.owner, .admin, .monitor, .supervisor]
        var activeIds = Set<UUID>(), fatherIds = Set<UUID>()
        for m in all where m.role != .pending && m.status != .frozen {
            activeIds.insert(m.id)
            if let fid = m.fatherId { fatherIds.insert(fid) }
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        for m in all {
            if m.role == .pending { continue }
            if moderatorRoles.contains(m.role) && m.isDeceased != true && m.status != .frozen { moderator += 1 }
            if m.isDeceased != true {
                let noPhone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noBirth = (m.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noGender = (m.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let notActivated = m.status == nil || m.status == .pending
                if notActivated || noPhone || noBirth || m.fatherId == nil || noGender { issues += 1 }
                if m.isCountable, let created = ApprovalWorkflow.date(m.createdAt), created >= weekAgo { joined += 1 }
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
        withAnimation(DS.Anim.smooth) {
            moderatorCount = moderator
            issueMembersCount = issues
            treeIssuesCount = treeIssues
            joinedThisWeek = joined
            inboxTotal = total
            recentDeaths = deaths
            memorial = DeceasedMemorialBoard(all)
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

    private var openTasks: [AdminTodayTask] {
        AdminTodayFeed.tasks(authVM: authVM, adminRequestVM: adminRequestVM, items: decisionItems,
                             sms: sms, unannounced: unannounced)
    }

    /// يتغيّر مع المهام المفتوحة — لمزامنة «المنجز»
    private var taskSignature: [String] { isInitialLoading ? [] : openTasks.map(\.id) }

    private func syncTasks() {
        guard !isInitialLoading else { return }
        taskStore.sync(open: openTasks, user: authVM.currentUser?.id, role: authVM.currentUser?.role.rawValue ?? "")
    }

    private var roleGuide: RoleGuide? {
        authVM.currentUser.flatMap { RoleGuide.forRole($0.role) }
    }

    /// مجال المراقب والمشرف (سطر «نطاقي» في الرأس)
    private var scopeGuide: RoleGuide? { authVM.isAdmin ? nil : roleGuide }

    private var visibleAreas: [AdminArea] { AdminArea.allCases.filter { $0.isVisible(for: authVM) } }

    // MARK: - الرأس

    private var todayHeader: some View {
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

    private var todayContent: some View {
        let items = decisionItems
        let tasks = openTasks
        return VStack(spacing: DS.Hub.stackSpacing) {
            let alerts = todayAlerts
            if !alerts.isEmpty {
                alertsCard(alerts)
            }
            decisionCard(items)
            tasksCard(tasks)
            familyTodayCard
            quickActions
            pulseSection
            areasSection
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
        // رصيد رسائل الدخول — تحت ٥٠ تحذير، تحت ١٠ عاجل (نفس عتبات السيرفر)
        if authVM.canViewSystemSettings, let balance = sms.status?.balance,
           balance < SmsBalanceStore.lowThreshold {
            let urgent = balance < SmsBalanceStore.urgentThreshold
            list.append(AdminTodayAlert(
                id: "sms", icon: "ellipsis.message.fill", tint: urgent ? DS.Color.error : DS.Color.warning,
                title: urgent ? L10n.t("عاجل: رصيد رسائل الدخول قارب يخلص", "Urgent: sign-in SMS balance nearly out")
                              : L10n.t("رصيد رسائل الدخول منخفض", "Sign-in SMS balance is low"),
                subtitle: L10n.t("\(SmsBalanceText.points(balance)) نقطة · \(SmsBalanceText.enough(balance))",
                                 "\(SmsBalanceText.points(balance)) points · \(SmsBalanceText.enough(balance))"),
                meter: balance / SmsBalanceStore.lowThreshold,
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

    // MARK: يحتاج قرارك

    private func decisionCard(_ items: [AdminDecisionItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("يحتاج قرارك", "Needs your decision")) {
                NavigationLink { AdminAllRequestsView() } label: {
                    AdminCardLinkLabel(title: isInitialLoading ? L10n.t("الوارد", "Inbox")
                                                                : L10n.t("الوارد \(inboxTotal)", "Inbox \(inboxTotal)"))
                }
                .buttonStyle(.plain)
            }
            if isInitialLoading {
                DSPageLoader(L10n.t("جارٍ التحميل…", "Loading…"), fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
            } else if items.isEmpty {
                HStack(spacing: DS.Spacing.md) {
                    AdminIconSquare(symbol: "checkmark.seal.fill", tint: DS.Color.success)
                    Text(L10n.t("كل شيء متابَع — لا شيء ينتظر قرارك", "All caught up — nothing awaits your decision"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.sm)
            } else {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { AdminRowDivider() }
                    NavigationLink { AdminAllRequestsView(focusId: item.id) } label: {
                        decisionRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .adminCard()
    }

    private func decisionRow(_ item: AdminDecisionItem) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: item.icon, tint: item.tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // نصّ عادي (لا مفتاح ترجمة): مفتاح بمتغيّرين فقط يعزل كلاً منهما فيقلب ترتيبهما في العربية
                Text(verbatim: item.typeTitle + " · " + item.name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                Text(item.subtitle)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            if item.isUrgent {
                DSStatusChip(text: L10n.t("مستعجل", "Urgent"), icon: "flame.fill", tint: DS.Color.warning)
            } else if item.isLate {
                DSStatusChip(text: AdminTodayText.late(item.snapshot), icon: "clock", tint: DS.Color.error)
            } else if let since = AdminTodayText.since(item.date) {
                DSStatusChip(text: since, tint: DS.Color.textTertiary)
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: مهام اليوم (لمسة «ب»)

    private static let visibleTaskLimit = 6

    private func tasksCard(_ tasks: [AdminTodayTask]) -> some View {
        let done = taskStore.done
        return VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("مهام اليوم", "Today's tasks"), badge: isInitialLoading ? nil : tasks.count) {
                if !done.isEmpty {
                    Button {
                        withAnimation(DS.Anim.snappy) { showDoneTasks.toggle() }
                    } label: {
                        AdminCardLinkLabel(title: showDoneTasks ? L10n.t("إخفاء المنجز", "Hide done")
                                                                : L10n.t("عرض المنجز (\(done.count))", "Show done (\(done.count))"),
                                           showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isInitialLoading {
                DSPageLoader(nil, fillsSpace: false)
                    .frame(maxWidth: .infinity)
            } else if tasks.isEmpty && (done.isEmpty || !showDoneTasks) {
                Text(L10n.t("لا مهام مفتوحة اليوم — كل شيء متابَع", "No open tasks today — all caught up"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.vertical, DS.Spacing.sm)
            }
            if !isInitialLoading {
                let shown = Array(tasks.prefix(Self.visibleTaskLimit))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { AdminRowDivider() }
                    NavigationLink { taskDestination(task.target) } label: { taskRow(task) }
                        .buttonStyle(.plain)
                }
                if tasks.count > Self.visibleTaskLimit {
                    AdminRowDivider()
                    NavigationLink { AdminAllRequestsView(initialFilter: .waiting) } label: {
                        AdminCardLinkLabel(title: L10n.t("+\(tasks.count - Self.visibleTaskLimit) مهام أخرى في الوارد",
                                                         "+\(tasks.count - Self.visibleTaskLimit) more in the inbox"))
                    }
                    .buttonStyle(.plain)
                }
                if showDoneTasks {
                    ForEach(done) { record in
                        AdminRowDivider()
                        doneRow(record)
                    }
                }
            }
        }
        .adminCard()
    }

    private func taskRow(_ task: AdminTodayTask) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Circle()
                .strokeBorder(DS.Color.textTertiary, lineWidth: DS.Border.widthBold)
                .frame(width: DS.Hub.taskRing, height: DS.Hub.taskRing)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                (Text(task.marks > 0 ? String(repeating: "!", count: task.marks) + " " : "")
                    .foregroundColor(task.marks >= 3 ? DS.Color.error : DS.Color.warning)
                 + Text(task.title).foregroundColor(DS.Color.textPrimary))
                    .dsFont(.hubRow)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: DS.Spacing.md) {
                    if let flag = task.flag {
                        Label { Text(flag) } icon: { Image(systemName: task.flagIcon).dsGlyph(DS.Glyph.xs) }
                            .foregroundColor(task.flagTint.dsReadableGlyph)
                    }
                    Label { Text(task.source) } icon: { Image(dsSymbol: task.sourceIcon).dsGlyph(DS.Glyph.xs) }
                        .foregroundColor(DS.Color.accent)
                }
                .dsFont(.caption)
                .labelStyle(AdminTightLabelStyle())
                .padding(.top, DS.Spacing.xxs)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func doneRow(_ record: AdminTodayTaskStore.Record) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: "checkmark")
                .dsGlyph(DS.Glyph.sm, weight: .heavy)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Hub.taskRing, height: DS.Hub.taskRing)
                .background(Circle().fill(DS.Color.accentLight))
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(record.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .strikethrough(true, color: DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text([L10n.t("تمّ", "Done"), record.doneAt.map(timeText)].compactMap { $0 }.joined(separator: " · ")
                     + " · " + record.source)
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

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    @ViewBuilder
    private func taskDestination(_ target: AdminTodayTask.Target) -> some View {
        switch target {
        case .inbox(let id):  AdminAllRequestsView(focusId: id)
        case .sms:            AdminSmsView(backTitle: L10n.t("اليوم", "Today"))
        case .deaths:         DeathAnnouncementsPage()
        case .announce:       DeathAnnouncementsPage()
        case .messages:       AdminAllRequestsView(startsWithMessages: true)
        }
    }

    // MARK: اليوم في العائلة

    private var familyRows: [AdminFamilyTodayRow] {
        var rows: [AdminFamilyTodayRow] = []
        let arabic = L10n.isArabic
        if let next = memorial.upcoming.first {
            rows.append(AdminFamilyTodayRow(
                id: "memorial", icon: "moon.stars.fill", tint: DS.Color.sadu,
                title: L10n.t("ذكرى \(next.member.shortFullName)", "\(next.member.shortFullName)'s anniversary"),
                value: DeceasedMemorial.whenLabel(next.anniversary.daysUntil, arabic: arabic),
                target: .memorial))
        }
        let seesNumbers = authVM.isAdmin || authVM.currentUser?.role == .monitor
        if seesNumbers && !recentDeaths.isEmpty {
            rows.append(AdminFamilyTodayRow(
                id: "deaths", icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                title: L10n.t("وفيات آخر 30 يوماً", "Deaths in the last 30 days"),
                value: "\(recentDeaths.count)", target: authVM.isAdmin ? .deaths : .memorial))
        }
        if seesNumbers && joinedThisWeek > 0 {
            rows.append(AdminFamilyTodayRow(
                id: "joined", icon: "person.crop.circle.badge.plus", tint: DS.Color.palm,
                title: L10n.t("أُضيفوا للشجرة هذا الأسبوع", "Added to the tree this week"),
                value: "\(joinedThisWeek)", target: .directory))
        }
        return rows
    }

    @ViewBuilder
    private var familyTodayCard: some View {
        let rows = familyRows
        if !isInitialLoading && !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AdminCardHeader(title: L10n.t("اليوم في العائلة", "Today in the family"))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { AdminRowDivider() }
                    NavigationLink { familyDestination(row.target) } label: {
                        AdminListRow(icon: row.icon, tint: row.tint, title: row.title) {
                            Text(row.value)
                                .dsFont(.chip)
                                .monospacedDigit()
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .adminCard()
        }
    }

    @ViewBuilder
    private func familyDestination(_ target: AdminFamilyTodayRow.Target) -> some View {
        switch target {
        case .memorial:  DeceasedMemorialView()
        case .deaths:    DeathAnnouncementsPage()
        case .directory: AdminLazyPage { AnyView(AdminMembersManagementView(initialTab: .directory)) }
        }
    }

    // MARK: إجراءات سريعة

    private struct QuickAction: Identifiable {
        let id: String
        let icon: String
        let title: String
        let page: () -> AnyView
    }

    private var quickActionItems: [QuickAction] {
        var list: [QuickAction] = []
        if authVM.canSendNotifications {
            list.append(QuickAction(id: "notify", icon: "megaphone", title: L10n.t("إشعار", "Notify")) {
                AnyView(AdminMessagingHubView())
            })
        }
        list.append(QuickAction(id: "occasion", icon: "photo.on.rectangle", title: L10n.t("مناسبة", "Occasion")) {
            AnyView(OccasionComposerView())
        })
        if authVM.canRegisterMembers {
            list.append(QuickAction(id: "register", icon: "person.badge.plus", title: L10n.t("تسجيل عضو", "Register")) {
                AnyView(AdminRegisterMemberView())
            })
        }
        if authVM.isAdmin {
            list.append(QuickAction(id: "death", icon: NewsTypeHelper.icon(for: "وفاة"), title: L10n.t("إعلان وفاة", "Obituary")) {
                AnyView(DeathAnnouncementsPage())
            })
        }
        if authVM.canEditMembers {
            list.append(QuickAction(id: "find", icon: "magnifyingglass", title: L10n.t("بحث عضو", "Find member")) {
                AnyView(AdminMembersManagementView(initialTab: .directory))
            })
        }
        return list
    }

    private var quickActions: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(quickActionItems) { action in
                NavigationLink { AdminLazyPage(make: action.page) } label: {
                    VStack(spacing: DS.Spacing.xsm) {
                        Image(dsSymbol: action.icon)
                            .dsGlyph(DS.Glyph.xxl, weight: .medium)
                            .foregroundColor(DS.Color.primary)
                            .frame(width: DS.Hub.quickCircle, height: DS.Hub.quickCircle)
                            .background(Circle().fill(DS.Color.surface))
                            .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke),
                                                           lineWidth: DS.Border.width))
                            .dsSubtleShadow()
                        Text(action.title)
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(action.title)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    // MARK: نبض العائلة

    private struct PulseTile: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: String
        var unit: String? = nil
        var valueTint: Color = DS.Color.textPrimary
        let note: String
        var meter: Double? = nil
        var meterTint: Color = DS.Color.primaryFill
        let page: () -> AnyView
    }

    private var pulseTiles: [PulseTile] {
        var tiles: [PulseTile] = []
        if authVM.isAdmin, let now = activeNow {
            tiles.append(PulseTile(id: "active", icon: "bolt.fill", label: L10n.t("النشطون الآن", "Active now"),
                                   value: "\(now)", note: L10n.t("يستخدمون التطبيق الآن", "Using the app now")) {
                AnyView(AdminActiveMembersView())
            })
        }
        if authVM.isAdmin || authVM.currentUser?.role == .monitor, let u = usageStats {
            let living = u.active + u.idle + u.loginNoDevice + u.neverLogged + u.noPhone
            let activeAccounts = u.active + u.idle
            let share = living > 0 ? Double(activeAccounts) / Double(living) : 0
            tiles.append(PulseTile(id: "accounts", icon: "iphone", label: L10n.t("حسابات فعّالة", "Active accounts"),
                                   value: "\(Int((share * 100).rounded()))%",
                                   note: L10n.t("\(activeAccounts) من \(living) حيّاً", "\(activeAccounts) of \(living) living"),
                                   meter: share) {
                AnyView(AppUsageMembersView(category: .active))
            })
        }
        if authVM.canViewSystemSettings, let balance = sms.status?.balance {
            let level = sms.level
            tiles.append(PulseTile(id: "sms", icon: "ellipsis.message", label: L10n.t("رسائل الدخول", "Sign-in SMS"),
                                   value: SmsBalanceText.points(balance), unit: L10n.t("نقطة", "pts"),
                                   valueTint: level == .good ? DS.Color.textPrimary : level.tint,
                                   note: SmsBalanceText.enough(balance)) {
                AnyView(AdminSmsView(backTitle: L10n.t("اليوم", "Today")))
            })
        }
        if let w = weekly {
            tiles.append(PulseTile(id: "done", icon: "checkmark.circle", label: L10n.t("منجز هذا الأسبوع", "Done this week"),
                                   value: "\(w.executed + w.rejected)",
                                   note: L10n.t("نُفّذ \(w.executed) · رُفض \(w.rejected)", "\(w.executed) done · \(w.rejected) rejected")) {
                AnyView(ApprovalsReportView())
            })
        }
        return tiles
    }

    @ViewBuilder
    private var pulseSection: some View {
        let tiles = pulseTiles
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                AdminSectionLabel(title: L10n.t("نبض العائلة", "Family pulse"))
                LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm + 2) {
                    ForEach(tiles) { tile in
                        NavigationLink { AdminLazyPage(make: tile.page) } label: { pulseTile(tile) }
                            .buttonStyle(DSPressStyle())
                    }
                }
            }
        }
    }

    private func pulseTile(_ tile: PulseTile) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(dsSymbol: tile.icon).dsGlyph(DS.Glyph.sm)
                Text(tile.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .dsFont(.caption)
            .foregroundColor(DS.Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(tile.value)
                    .dsFont(.hubPulse)
                    .monospacedDigit()
                    .foregroundColor(tile.valueTint.dsReadableGlyph)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = tile.unit {
                    Text(unit)
                        .dsFont(.caption)
                        .foregroundColor(tile.valueTint.dsReadableGlyph)
                }
            }
            Text(tile.note)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let meter = tile.meter {
                AdminMeter(progress: meter, tint: tile.meterTint)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Hub.tileMinHeight, alignment: .topLeading)
        .dsCard(padding: DS.Spacing.md, radius: DS.Hub.tileRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: الأقسام

    private var gridColumns: [GridItem] {
        landscape
            ? [GridItem(.adaptive(minimum: DS.Landscape.tileMinWidth), spacing: DS.Spacing.sm + 2)]
            : [GridItem(.flexible(), spacing: DS.Spacing.sm + 2), GridItem(.flexible(), spacing: DS.Spacing.sm + 2)]
    }

    private var areasSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminSectionLabel(title: L10n.t("الأقسام", "Sections"))
            LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm + 2) {
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
                        balance < SmsBalanceStore.lowThreshold)
            }
            return (area.subtitle, false)
        case .app:
            return appSettingsVM.settings.maintenanceMode
                ? (L10n.t("الصيانة مفعّلة", "Maintenance on"), true)
                : (L10n.t("الصيانة مطفأة", "Maintenance off"), false)
        }
    }
}

/// رمز ونص متقاربان (مصدر المهمة وشارتها)
struct AdminTightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Spacing.xxs + 1) {
            configuration.icon
            configuration.title
        }
    }
}

/// يبني الصفحة عند ظهورها فقط (لا عند بناء اللوحة) — كانت كلها تُنسخ في مكدّس اللوحة فينغلق التطبيق (٢٠٢٦-١٠-٠٥)
struct AdminLazyPage: View {
    let make: () -> AnyView
    var body: some View { make() }
}
