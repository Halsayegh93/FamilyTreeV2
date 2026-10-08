import SwiftUI

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
}

// MARK: - لوحة الإدارة — فكرة «المطلوب مني» (أبسط وأسهل — طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// من الأعلى: بطاقة رأس «لوحة الإدارة» (الدور ومجاله + ٣ أرقام حيّة) ← «ابحث عن أداة…»
// (أي نص يجمع كل أدوات المشاهد المسموحة في قائمة واحدة، والفارغ يرجع للعرض العادي) ←
// مبدّل كبير بثلاثة أقسام يتذكّر آخر اختيار طوال الجلسة:
//   ١. «المطلوب مني» (الافتراضي): ما ينتظر المشاهد فقط — صف كبير لكل نوع بعدده الأحمر،
//      أو «لا توجد مهام معلّقة» — ثم «أفراد العائلة» (لمن يرى الإحصائيات) و«نطاق الصلاحيات» (المراقب والمشرف).
//   ٢. «الأعضاء والشجرة»: أدوات الشجرة والأعضاء المتاحة للمشاهد.
//   ٣. «النظام»: مربّعات الإعدادات نفسها بمجموعات — الفريق والأمان · الإشعارات · التطبيق ·
//      التقارير؛ كل مربّع يفتح صفحته مباشرة، بلا صفحة وسطية وبلا رقم مكرّر (طلب المالك ٢٠٢٦-١٠-٠٢).
// كل أداة في قسم واحد، وكل صف بشكل واحد (أيقونة بمربّع فاتح، عنوان، تلميح، عدد، سهم) داخل
// بطاقة واحدة بفواصل — بلا تدرّج ولا ظل. الصلاحيات والوجهات والروابط العميقة كما كانت تماماً.

struct AdminDashboardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @Binding var selectedTab: Int
    @State private var navigationPath = NavigationPath()
    @State private var showingNotifications = false
    @State private var pendingCount: Int = 0
    @State private var moderatorCount: Int = 0
    @State private var totalReviewRequestsCount: Int = 0
    /// عناصر الأرشيف المنتظرة — تدخل في عدّاد «طلبات المراجعة» مثل بقية الطلبات
    @State private var pendingArchiveCount: Int = 0
    /// من يستخدم التطبيق فعلاً — حساب دخول / جهاز / رقم
    @State private var usageStats: AppUsageStats? = AppUsageStats.cached
    @State private var treeIssuesCount: Int = 0
    @State private var issueMembersCount: Int = 0
    @State private var totalMembersCount: Int = 0
    @State private var aliveMembersCount: Int = 0
    @State private var deceasedMembersCount: Int = 0
    // أعداد شجرة النساء — الإناث وحدهن (الجدول يضمّ مرايا الرجال أيضاً)
    @State private var womenTotalCount: Int = 0
    @State private var womenAliveCount: Int = 0
    @State private var womenDeceasedCount: Int = 0
    @State private var isInitialLoading = true
    /// «مجالك»: سطر مختصر، أو كل ما يقدر وما لا يقدر عليه
    @State private var showFullScope = false
    /// القسم المختار — يبقى طوال الجلسة (تاب الإدارة لا يُعاد بناؤه عند التنقّل بين التابات)
    @State private var selectedSection: DashSection = .pending
    /// «ابحث عن أداة…» — أي نص يعرض كل الأدوات المطابقة في قائمة واحدة
    /// دخول المربّعات تباعاً (dsCardCascade) — يُعاد عند تبديل القسم
    @State private var tilesAppeared = false
    /// بنود «صحة الشجرة» داخل طلبات المراجعة (الباقي من مجموع مجال الشجرة)
    @State private var reviewHealthCount = 0
    /// وفيات آخر ٣٠ يوماً (لمربّع «إعلان وفاة»)
    @State private var recentDeathsCount = 0
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    /// وضع العرض: «المعلّقة» بطاقتان جنباً إلى جنب، والأدوات بشبكة أعرض (`DS.Landscape`)
    @Environment(\.dsLandscape) private var landscape

    /// مجموع كل الطلبات المعلّقة من مصادر مختلفة — يُستخدم لتشغيل إعادة الحساب لحظياً عند أي تغيير
    private var pendingRequestsSum: Int {
        newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + adminRequestVM.nameChangeRequests.count
    }

    private func recalculateBadges() {
        let all = memberVM.allMembers

        // مرور واحد لحساب كل الأعداد بدل 11 filter
        var pending = 0, moderator = 0, total = 0, alive = 0, deceased = 0, issues = 0, treeIssues = 0
        let moderatorRoles: Set<FamilyMember.UserRole> = [.owner, .admin, .monitor, .supervisor]

        // بناء مجموعات الأعضاء النشطين وآبائهم (لفحص مشاكل الشجرة)
        var activeIds = Set<UUID>()
        var fatherIds = Set<UUID>()
        for m in all where m.role != .pending && m.status != .frozen {
            activeIds.insert(m.id)
            if let fid = m.fatherId { fatherIds.insert(fid) }
        }

        for m in all {
            if m.role == .pending { pending += 1; continue }
            total += 1
            // الفريق: الأحياء غير المجمّدين فقط
            if moderatorRoles.contains(m.role) && m.isDeceased != true && m.status != .frozen { moderator += 1 }

            if m.isDeceased == true {
                deceased += 1
            } else {
                alive += 1
                // فحص النواقص (أحياء فقط)
                let noPhone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noBirth = (m.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noFather = m.fatherId == nil
                let noGender = (m.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let notActivated = m.status == nil || m.status == .pending
                if notActivated || noPhone || noBirth || noFather || noGender {
                    issues += 1
                }
            }

            // مشاكل الشجرة
            if m.status != .frozen {
                let isOrphan = m.fatherId == nil && !fatherIds.contains(m.id) && m.role != .pending
                let noName = m.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.fullName == "بدون اسم"
                let brokenParent = m.fatherId != nil && !activeIds.contains(m.fatherId ?? UUID())
                if isOrphan || noName || brokenParent || m.isHiddenFromTree {
                    treeIssues += 1
                }
            }
        }

        // مصدر واحد للحقيقة — مطابق تماماً لعدّاد «الكل» داخل «طلبات المراجعة»
        let reviewTotal = AdminAllRequestsView.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveCount,
            scope: AdminAllRequestsView.reviewScope(for: authVM)
        )

        // «صحة الشجرة» = مجموع مجال الشجرة ناقص بنوده المعروفة (نفس مصدر عدّاد المراجعة)
        let treeScopeTotal = AdminAllRequestsView.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveCount, scope: .tree)
        let treeKnown = pending
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.treeEditRequests.count
        let healthInReview = max(0, treeScopeTotal - treeKnown)
        let recentDeaths = all.filter {
            $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate)
        }.count

        withAnimation(DS.Anim.smooth) {
            pendingCount = pending
            moderatorCount = moderator
            totalMembersCount = total
            aliveMembersCount = alive
            deceasedMembersCount = deceased
            issueMembersCount = issues
            treeIssuesCount = treeIssues
            totalReviewRequestsCount = reviewTotal
            reviewHealthCount = healthInReview
            recentDeathsCount = recentDeaths
        }
    }

    /// أعداد شجرة النساء — الإناث فقط، فالجدول يضمّ مرايا الذكور كذلك.
    @MainActor
    private func loadWomenStats() async {
        guard let rows = try? await WomenStore.fetch() else { return }
        let females = rows.filter { $0.isFemale }
        let deceased = females.filter { $0.isDeceased == true }.count
        withAnimation(DS.Anim.smooth) {
            womenTotalCount = females.count
            womenDeceasedCount = deceased
            womenAliveCount = females.count - deceased
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الإدارة", "Admin Dashboard"),
                        subtitle: L10n.t("المراجعة والإعدادات والتقارير", "Review, settings and reports"),
                        icon: "shield.lefthalf.filled",
                        backgroundGradient: AppSection.admin.gradient,
                        hasDropShadow: false
                    )

                    ScrollView(showsIndicators: false) {
                        dashboardContent
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.md)
                            .padding(.bottom, DS.Spacing.xxxl)
                            .dsTabBarClearance()   // أفقياً: آخر صفّ لا يختفي تحت شريط التبويبات العائم
                    }
                    // السحب للتحديث على الـ ScrollView نفسه (كان على المحتوى الداخلي فلا يعمل)
                    .refreshable { await loadAllAdminData(force: true) }
                    // سحب الصفحة يُنزل لوحة المفاتيح أثناء البحث عن أداة
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationDestination(for: AdminReviewDestination.self) { destination in
                switch destination {
                case .treeEditRequests: AdminTreeEditRequestsView()
                case .allRequests:      AdminAllRequestsView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onReceive(NotificationCenter.default.publisher(for: .openAdminReviewForKind)) { note in
            guard let kind = note.userInfo?["kind"] as? String else { return }
            // عبد عند الفتح: انتقل لتاب الإدارة، ثم ادفع الشاشة المناسبة
            let destination: AdminReviewDestination = (kind == NotificationKind.treeEdit.rawValue)
                ? .treeEditRequests
                : .allRequests
            // قشّر الـ stack الحالي قبل الدفع لتجنب التراكم
            navigationPath = NavigationPath()
            navigationPath.append(destination)
        }
        .task {
            await loadAllAdminData()
        }
        .onChange(of: memberVM.membersVersion) { _ in recalculateBadges() }
        .onChange(of: pendingRequestsSum) { _ in recalculateBadges() }
        .onChange(of: pendingArchiveCount) { _ in recalculateBadges() }
    }

    /// تحميل كل بيانات لوحة الإدارة بالتوازي — يُستخدم في .task وفي السحب للتحديث
    private func loadAllAdminData(force: Bool = false) async {
        diwaniyaVM.canModerate = authVM.canModerate
        diwaniyaVM.authVM = authVM
        await memberVM.fetchAllMembers(force: force)

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
            group.addTask { @MainActor in await projectsVM.fetchPendingProjects() }
            group.addTask { @MainActor in await authVM.fetchBannedPhones() }
            group.addTask { @MainActor in await loadWomenStats() }
            group.addTask { @MainActor in pendingArchiveCount = await FamilyArchiveViewModel.pendingCount() }
            group.addTask { @MainActor in usageStats = await AppUsageStats.fetch() }
        }
        recalculateBadges()
        withAnimation(DS.Anim.smooth) { isInitialLoading = false }
    }

    // MARK: - هيكل الصفحة (إبداعي وبلا تكرار — طلب المالك ٢٠٢٦-١٠-٠١)
    //
    // كل رقم في مكان واحد فقط:
    //   • مربّع «أفراد العائلة» بالأعلى: حلقة لكل جنس (نسبة الأحياء) والعدد في وسطها.
    //   • «المعلّقة»: بطاقة «طلبات المراجعة» بعددها وتفصيله (انضمام، شجرة، أخبار…)، وبطاقة «الرسائل».
    //   • «الأعضاء»: «استخدام التطبيق» شريطاً ملوّناً (فعّال، بلا جهاز، ما دخل، دون رقم)،
    //     ثم الأعضاء وإعلان وفاة وسجل النشاط.
    //   • «النظام»: الإعدادات بطاقةً عريضة، ثم الإحصائيات والتقارير.

    private var dashboardContent: some View {
        VStack(spacing: DS.Spacing.lg) {
            if canSeeStats {
                familyHero
                    .dsStaggerIn(0)
            }

            // تحذير التوافق
            if !authVM.notificationsFeatureAvailable || !authVM.newsApprovalFeatureAvailable {
                schemaWarningCard
            }

            VStack(spacing: DS.Spacing.md) {
                DSSegmentedSwitch(options: sectionOptions, selection: sectionBinding)
                    .dsStaggerIn(1)
                sectionContent
            }
        }
        .onAppear {
            guard !tilesAppeared else { return }
            DispatchQueue.main.async { tilesAppeared = true }
        }
        // تبديل القسم: بطاقاته تدخل تباعاً من جديد (نمط الأخبار والديوانيات)
        .onChange(of: effectiveSection) { _ in
            tilesAppeared = false
            DispatchQueue.main.async { tilesAppeared = true }
        }
    }

    // MARK: - المشاهد ودوره

    /// من يرى الإحصائيات (جدول الصلاحيات): المالك والمدير والمراقب
    private var canSeeStats: Bool { authVM.isAdmin || authVM.currentUser?.role == .monitor }

    private var viewerGuide: RoleGuide? {
        guard let role = authVM.currentUser?.role else { return nil }
        return RoleGuide.forRole(role)
    }

    /// «مجالك» للمراقب والمشرف فقط
    private var scopeGuide: RoleGuide? {
        guard !authVM.isAdmin else { return nil }
        return viewerGuide
    }

    /// لون مجال المشاهد: المراقب = الشجرة والأعضاء، المشرف = المحتوى والبلاغات، والإدارة = النظام
    /// (بلون تبويب الإدارة — «كل قسم بلونه»)
    private var domainTint: Color {
        switch authVM.currentUser?.role {
        case .monitor:    return DS.Color.composerProject
        case .supervisor: return DS.Color.composerLibrary
        default:          return AppSection.admin.fill
        }
    }

    // MARK: - مربّع «أفراد العائلة»

    /// «أسلوب واحد» (دفعة 3-B): البطاقة الواحدة `.dsCard()` بعنوان قسم مجسّم — كانت بطاقة تدرّج يدوية
    /// (قرص SF أبيض، دائرتان زخرفيتان، ظلّ ملوّن) بجانب بطاقات العُدّة
    private var familyHero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                DSSectionTitle(title: L10n.t("أفراد العائلة", "Family members"), icon: "person.3.fill",
                               tint: domainTint)
                // الدور للمالك والمدير (المراقب يراه في «مجالك» — بلا تكرار)
                if authVM.isAdmin, let guide = viewerGuide {
                    DSStatusChip(text: guide.title, tint: domainTint)
                }
            }

            HStack(spacing: DS.Spacing.sm) {
                GenderRingPanel(title: L10n.t("الرجال", "Men"), dot: DS.Color.male,
                                total: totalMembersCount, alive: aliveMembersCount,
                                deceased: deceasedMembersCount, loading: isInitialLoading)
                GenderRingPanel(title: L10n.t("النساء", "Women"), dot: DS.Color.female,
                                total: womenTotalCount, alive: womenAliveCount,
                                deceased: womenDeceasedCount, loading: isInitialLoading)
            }
        }
        .dsCard(padding: DS.Spacing.md)
    }

    // MARK: - الأقسام

    private enum DashSection: Hashable { case pending, members, system }

    /// وجهة كل بطاقة
    private enum DashTarget {
        case requests, inbox, members, activity, analytics, pdfReports, deaths
        case usage(AppUsageCategory)
        // «النظام» — كل مربّع يفتح صفحته مباشرة (كانت داخل صفحة «إعدادات النظام» الوسطية)
        case team, liveActivity, devices, bannedPhones, messaging, pushHealth, appSettings, forceUpdate
    }

    /// وجهات اللوحة — كل صفحة في صندوق (AnyView) وتُبنى عند فتحها فقط (LazyAdminPage):
    /// كانت كلها تُنسخ في مكدّس اللوحة فيطفح في نسخة التطوير وينغلق التطبيق عند فتح «الإدارة» (٢٠٢٦-١٠-٠٥)
    private func destinationView(_ target: DashTarget) -> some View {
        LazyAdminPage { Self.page(for: target) }
    }

    private static func page(for target: DashTarget) -> AnyView {
        switch target {
        case .requests: return AnyView(AdminAllRequestsView())
        case .inbox: return AnyView(AdminInboxView())
        case .members: return AnyView(AdminMembersManagementView())
        case .activity: return AnyView(AdminActivityLogView())
        case .analytics: return AnyView(AdminAnalyticsView())
        case .pdfReports: return AnyView(AdminReportsView())
        case .usage(let category): return AnyView(AppUsageMembersView(category: category))
        case .deaths: return AnyView(DeathAnnouncementsPage())
        case .team: return AnyView(AdminModeratorsView())
        case .liveActivity: return AnyView(AdminActiveMembersView())
        case .devices: return AnyView(AdminDevicesView())
        case .bannedPhones: return AnyView(AdminBannedPhonesView())
        case .messaging: return AnyView(AdminMessagingHubView())
        case .pushHealth: return AnyView(AdminPushHealthView())
        case .appSettings: return AnyView(AdminAppSettingsView())
        case .forceUpdate: return AnyView(AdminForceUpdateView())
        }
    }


    /// الأقسام الظاهرة — قسم بلا محتوى لهذا الدور لا يظهر
    private var visibleSections: [DashSection] {
        var sections: [DashSection] = [.pending]
        if !memberTiles.isEmpty || canSeeStats { sections.append(.members) }
        if !systemGroups.isEmpty { sections.append(.system) }
        return sections
    }

    /// القسم المعروض — إن لم يعد المختار ظاهراً نرجع لـ«المعلّقة»
    private var effectiveSection: DashSection {
        visibleSections.contains(selectedSection) ? selectedSection : .pending
    }

    private var sectionBinding: Binding<DashSection> {
        Binding(get: { effectiveSection }, set: { selectedSection = $0 })
    }

    /// أسماء قصيرة وبلا أعداد (الأعداد في البطاقات وحدها — بلا تكرار)
    private var sectionOptions: [DSSegmentOption<DashSection>] {
        visibleSections.map { section -> DSSegmentOption<DashSection> in
            switch section {
            case .pending:
                return DSSegmentOption(id: .pending, title: L10n.t("المعلّقة", "Pending"), icon: "checklist")
            case .members:
                return DSSegmentOption(id: .members, title: L10n.t("الأعضاء", "Members"), icon: "person.2.fill")
            case .system:
                return DSSegmentOption(id: .system, title: L10n.t("النظام", "System"), icon: "gearshape.fill")
            }
        }
    }

    /// التبديل: القديم يتلاشى بسرعة والجديد يدخل تباعاً — داخل ZStack حتى لا تقفز الصفحة
    private var sectionSwap: AnyTransition {
        .asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.1)))
    }

    private var sectionContent: some View {
        ZStack(alignment: .top) {
            switch effectiveSection {
            case .pending:
                AdaptiveCardStack(spacing: DS.Spacing.md) {
                    reviewCard
                        .dsCardCascade(0, appeared: tilesAppeared)
                    messagesCard
                        .dsCardCascade(1, appeared: tilesAppeared)
                    // «مجالك» — للمراقب والمشرف فقط (المالك والمدير مجالهما كامل)
                    if let guide = scopeGuide {
                        scopeRow(guide)
                            .dsCardCascade(2, appeared: tilesAppeared)
                    }
                }
                .transition(sectionSwap)
            case .members:
                VStack(spacing: DS.Spacing.md) {
                    if canSeeStats {
                        usageCard
                            .dsCardCascade(0, appeared: tilesAppeared)
                    }
                    tilesGrid(memberTiles, columns: 3, startIndex: 1)
                }
                .transition(sectionSwap)
            case .system:
                // المربّعات نفسها بمجموعات — كل مربّع يفتح صفحته (بلا صفحة وسطية)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(systemGroups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            DSSectionTitle(title: group.title, icon: group.icon, tint: group.tint,
                                           trailing: group.trailing)
                                .padding(.top, DS.Spacing.md)
                                .padding(.bottom, DS.Spacing.sm)
                                .dsCardCascade(group.start, appeared: tilesAppeared)
                            tilesGrid(group.tiles, columns: 2, startIndex: group.start + 1)
                        }
                    }
                }
                .transition(sectionSwap)
            }
        }
    }

    // MARK: - «المعلّقة»: طلبات المراجعة (بتفصيلها) + الرسائل

    private struct ReviewChip: Identifiable {
        let id: String
        let label: String
        let icon: String
        let tint: Color
        let count: Int
    }

    /// تفصيل «طلبات المراجعة» — بنود مجال المشاهد غير الصفرية فقط (العدد الكلّي على البطاقة)
    private var reviewChips: [ReviewChip] {
        guard !isInitialLoading else { return [] }
        let scope = AdminAllRequestsView.reviewScope(for: authVM)
        var chips: [ReviewChip] = []
        func add(_ id: String, _ label: String, _ icon: String, _ tint: Color, _ count: Int) {
            if count > 0 { chips.append(ReviewChip(id: id, label: label, icon: icon, tint: tint, count: count)) }
        }
        if scope != .content {
            add("join", L10n.t("انضمام", "Join"), "person.badge.clock.fill", DS.Color.composerProject, pendingCount)
            add("tree", L10n.t("تعديل الشجرة", "Tree edits"), "arrow.triangle.branch", DS.Color.composerProject,
                adminRequestVM.treeEditRequests.count)
            add("death", L10n.t("وفاة", "Deceased"), "heart.slash.fill", DS.Color.newsDeath,
                adminRequestVM.deceasedRequests.count)
            add("child", L10n.t("إضافة ابن", "Add child"), "person.badge.plus", DS.Color.composerProject,
                adminRequestVM.childAddRequests.count)
            add("phone", L10n.t("تغيير رقم", "Phone"), "phone.arrow.right", DS.Color.info,
                adminRequestVM.phoneChangeRequests.count)
            add("name", L10n.t("تغيير اسم", "Name"), "character.cursor.ibeam", DS.Color.info,
                adminRequestVM.nameChangeRequests.count)
            add("health", L10n.t("صحة الشجرة", "Tree health"), "stethoscope", DS.Color.warning, reviewHealthCount)
        }
        if scope != .tree {
            add("news", L10n.t("أخبار", "News"), "newspaper.fill", DS.Color.primary, newsVM.pendingNewsRequests.count)
            add("reports", L10n.t("بلاغات", "Reports"), "exclamationmark.bubble.fill", DS.Color.error,
                adminRequestVM.newsReportRequests.count)
            add("diwaniyas", L10n.t("ديوانيات", "Diwaniyas"), "tent.fill", DS.Color.composerDiwaniya,
                diwaniyaVM.pendingDiwaniyas.count)
            add("projects", L10n.t("مشاريع", "Projects"), "briefcase.fill", DS.Color.tileProjects,
                projectsVM.pendingProjects.count)
            add("archive", L10n.t("المكتبة", "Library"), "books.vertical.fill", DS.Color.tileLibrary,
                pendingArchiveCount)
            add("photos", L10n.t("صور", "Photos"), "photo.fill", DS.Color.primary,
                adminRequestVM.photoSuggestionRequests.count)
        }
        return chips
    }

    private var reviewCard: some View {
        let reviews = isInitialLoading ? 0 : totalReviewRequestsCount
        let tint = DS.Color.warning
        return NavigationLink { destinationView(.requests) } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.md) {
                    DSStateIcon("tray.full.fill", tint: tint, size: DS.Icon.tile)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("طلبات المراجعة", "Review requests"))
                            .dsFont(.headline)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(reviews > 0 ? L10n.t("بانتظار قرارك", "Awaiting your decision")
                                         : L10n.t("لا شيء بانتظارك", "Nothing waiting"))
                            .dsFieldFont(.subtitle)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                    Spacer(minLength: DS.Spacing.sm)
                    statusBadge(alert: reviews, loading: isInitialLoading)
                    DSChevron()
                }
                let chips = reviewChips
                if !chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: DS.Spacing.xsm)],
                              alignment: .leading, spacing: DS.Spacing.xsm) {
                        ForEach(chips) { chip in reviewChipView(chip) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(padding: DS.Spacing.md)
            .overlay(cardBorder(highlight: reviews > 0))
            .contentShape(DSBox.sectionShape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(reviews > 0
            ? L10n.t("طلبات المراجعة، \(reviews) بانتظار قرارك", "Review requests, \(reviews) waiting")
            : L10n.t("طلبات المراجعة، لا شيء بانتظارك", "Review requests, nothing waiting"))
    }

    private func reviewChipView(_ chip: ReviewChip) -> some View {
        let color = chip.tint.dsReadableGlyph
        return HStack(spacing: DS.Spacing.xs) {
            Image(systemName: chip.icon)
                .dsGlyph(DS.Glyph.xs)
                .accessibilityHidden(true)
            Text(chip.label)
                .dsFont(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Spacing.xxs)
            Text("\(chip.count)")
                .dsFont(.chip)
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(minHeight: DSBox.chipHeightCompact)
        .background(Capsule().fill(color.opacity(DS.Opacity.tintFill)))
        .accessibilityElement(children: .combine)
    }

    private var messagesCard: some View {
        let unread = adminRequestVM.unreadContactMessagesCount
        let awaiting = adminRequestVM.pendingContactMessagesCount
        let tint = DS.Color.composerDiwaniya
        let caption: String = unread > 0 ? L10n.t("غير مقروءة", "Unread")
            : awaiting > 0 ? L10n.t("\(awaiting) بانتظار الرد", "\(awaiting) awaiting reply")
            : L10n.t("لا جديد", "All caught up")
        return NavigationLink { destinationView(.inbox) } label: {
            HStack(spacing: DS.Spacing.md) {
                DSStateIcon("bubble.left.and.bubble.right.fill", tint: tint, size: DS.Icon.tile)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("الرسائل", "Messages"))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(caption)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: DS.Spacing.sm)
                statusBadge(alert: unread, loading: false)
                DSChevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(padding: DS.Spacing.md)
            .overlay(cardBorder(highlight: unread > 0))
            .contentShape(DSBox.sectionShape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("الرسائل، \(caption)", "Messages, \(caption)"))
    }

    /// العدد الأحمر لما ينتظرك، أو ✓ خضراء حين لا شيء
    @ViewBuilder
    private func statusBadge(alert: Int, loading: Bool) -> some View {
        if loading {
            // قبل وصول الأرقام «—» هادئة (كصفّ الأرقام) بدل دوّارة
            Text("—")
                .dsFont(.chip)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
        } else if alert > 0 {
            // أصغر (طلب المالك ٢٠٢٦-١٠-٠٥ «الرقم الأحمر اصغر»)
            Text(Self.countText(alert))
                .dsFont(.chip)
                .monospacedDigit()
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.xsm)
                .frame(minWidth: DS.Spacing.xxl, minHeight: DS.Icon.countBadge)
                .background(Capsule().fill(DS.Color.error))
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .dsGlyph(DS.Glyph.xxl, weight: .semibold)
                .foregroundColor(DS.Color.success)
                .accessibilityHidden(true)
        }
    }

    // MARK: - «الأعضاء»: استخدام التطبيق + الأعضاء وإعلان وفاة وسجل النشاط

    private struct UsageSegment: Identifiable {
        let id: String
        let label: String
        let value: Int
        let color: Color
        let category: AppUsageCategory
    }

    /// فئات استخدام التطبيق — «فعّال» = رقم وجهاز (فعّال + خامل، تعريف المالك)
    private var usageSegments: [UsageSegment] {
        guard let u = usageStats else { return [] }
        return [
            UsageSegment(id: "active", label: L10n.t("فعّال", "Active"), value: u.active + u.idle,
                         color: DS.Color.success, category: .active),
            UsageSegment(id: "noDevice", label: L10n.t("بلا جهاز", "No device"), value: u.loginNoDevice,
                         color: DS.Color.info, category: .loginNoDevice),
            UsageSegment(id: "never", label: L10n.t("ما دخل", "Never in"), value: u.neverLogged,
                         color: DS.Color.warning, category: .neverLogged),
            UsageSegment(id: "noPhone", label: L10n.t("دون رقم", "No phone"), value: u.noPhone,
                         color: DS.Color.textTertiary, category: .noPhone)
        ]
    }

    private var usageCard: some View {
        let segments = usageSegments
        let total = segments.reduce(0) { $0 + $1.value }
        // كل من دخل التطبيق: فعّال + خامل + دخل بلا جهاز
        let totalUsers = usageStats.map { $0.active + $0.idle + $0.loginNoDevice } ?? 0
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                DSStateIcon("iphone.gen3", tint: DS.Color.success, size: DS.Icon.tile)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("استخدام التطبيق", "App usage"))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.fieldLabel)
                    // «إجمالي المستخدمين» هنا وحده (كان في صفحة «إعدادات النظام» الوسطية)
                    Text(total > 0
                         ? L10n.t("إجمالي المستخدمين \(totalUsers) · من \(total) من الأحياء",
                                  "\(totalUsers) users · of \(total) living members")
                         : isInitialLoading ? L10n.t("جارٍ التحميل…", "Loading…")
                         : L10n.t("غير متاح الآن — اسحب للتحديث", "Unavailable — pull to refresh"))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            DSDistributionBar(segments: segments.map { .init(id: $0.id, value: $0.value, tint: $0.color) },
                              height: DS.Spacing.md)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.sm),
                                GridItem(.flexible(), spacing: DS.Spacing.sm)],
                      spacing: DS.Spacing.sm) {
                ForEach(segments) { seg in
                    NavigationLink { destinationView(.usage(seg.category)) } label: {
                        HStack(spacing: DS.Spacing.xsm) {
                            Circle().fill(seg.color).frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                                .accessibilityHidden(true)
                            Text(seg.label)
                                .dsFieldFont(.sectionTitle)
                                .foregroundColor(DS.Color.fieldLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: DS.Spacing.xxs)
                            Text("\(seg.value)")
                                .dsFont(.button)
                                .monospacedDigit()
                                .foregroundColor(seg.color.dsReadableGlyph)
                                .contentTransition(.numericText())
                            DSChevron()
                        }
                        .frame(minHeight: DSBox.fieldMinHeight)
                        .dsRowBox()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel("\(seg.label): \(seg.value)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: DS.Spacing.md)
    }

    /// مربّعات صغيرة تحت «استخدام التطبيق» — بلا أرقام مكررة (عدد الأعضاء في المربّع العلوي)
    private var memberTiles: [DashTile] {
        let loaded = !isInitialLoading
        var list: [DashTile] = []
        if authVM.canEditMembers {
            let gaps = issueMembersCount + treeIssuesCount
            list.append(DashTile(id: "members.manage",
                                 title: L10n.t("الأعضاء", "Members"),
                                 caption: loaded && gaps > 0
                                     ? L10n.t("\(gaps) ناقصة", "\(gaps) gaps")
                                     : L10n.t("الحسابات", "Accounts"),
                                 icon: "person.2.badge.gearshape", tint: DS.Color.composerProject,
                                 target: .members))
        }
        // إعلان وفاة — للمالك والمدير (نشر المحتوى والإشعارات، والسيرفر يفرضه)
        if authVM.isAdmin {
            list.append(DashTile(id: "members.deaths",
                                 title: L10n.t("إعلان وفاة", "Obituary"),
                                 caption: loaded && recentDeathsCount > 0
                                     ? L10n.t("\(recentDeathsCount) حديثة", "\(recentDeathsCount) recent")
                                     : L10n.t("لا وفيات حديثة", "None recent"),
                                 icon: NewsTypeHelper.icon(for: "وفاة"), tint: NewsTypeHelper.color(for: "وفاة"),
                                 target: .deaths))
        }
        // سجل النشاط: المالك/المدير/المراقب فقط (جدول الصلاحيات — ليس المشرف)
        if authVM.isAdmin || authVM.currentUser?.role == .monitor {
            list.append(DashTile(id: "members.activity",
                                 title: L10n.t("سجل النشاط", "Activity"),
                                 caption: L10n.t("التعديلات", "Changes"),
                                 icon: "clock.arrow.circlepath", tint: AppSection.admin.fill,
                                 alert: notificationVM.unreadActivityLogCount,
                                 target: .activity))
        }
        return list
    }

    // MARK: - «النظام»: مربّعات الإعدادات بمجموعات (طلب المالك ٢٠٢٦-١٠-٠٢)
    //
    // «الفريق والأمان · الإشعارات · التطبيق · التقارير» — كل مربّع يفتح صفحته مباشرة (كانت
    // داخل صفحة «إعدادات النظام» الوسطية)، وبلا رقم مكرّر: عدد الفريق في مربّعه وحده،
    // و«استخدام التطبيق» في «الأعضاء» وحده. الصلاحيات كما كانت: الإعدادات للمالك والمدير
    // (المدير للقراءة فيما يعدّله المالك وحده)، والإحصائيات والتقارير لهما.

    private struct SystemGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        /// تلميح بطرف العنوان — «للقراءة» للمدير فيما يعدّله المالك وحده
        var trailing: String? = nil
        let tiles: [DashTile]
        /// ترتيب أول عنصر في دخول المربّعات تباعاً عبر التبويب كله
        var start = 0
    }

    private var systemGroups: [SystemGroup] {
        var groups: [SystemGroup] = []
        let readOnly = authVM.canManageSettings ? nil : L10n.t("للقراءة", "Read-only")
        if authVM.canViewSystemSettings {
            groups.append(SystemGroup(
                id: "group.team", title: L10n.t("الفريق والأمان", "Team & security"),
                icon: "person.badge.shield.checkmark.fill", tint: AppSection.admin.fill, trailing: readOnly,
                tiles: [
                    // عدد الفريق هنا وحده — نص هادئ لا شارة حمراء (ليس شيئاً ينتظرك)
                    DashTile(id: "system.team",
                             title: L10n.t("فريق الإدارة", "Admin team"),
                             caption: isInitialLoading
                                 ? L10n.t("الأدوار والصلاحيات", "Roles & permissions")
                                 : L10n.t("\(moderatorCount) في الفريق", "\(moderatorCount) on the team"),
                             icon: "person.3.fill", tint: AppSection.admin.fill, target: .team),
                    // «النشاط الآن» جنب «فريق الإدارة» (طلب المالك)
                    DashTile(id: "system.live",
                             title: L10n.t("النشاط الآن", "Live activity"),
                             caption: L10n.t("الدخول وآخر نشاط", "Sign-ins & activity"),
                             icon: "person.2.fill", tint: DS.Color.composerProject, target: .liveActivity),
                    DashTile(id: "system.devices",
                             title: L10n.t("الأجهزة", "Devices"),
                             caption: L10n.t("المرتبطة بالحسابات", "Linked to accounts"),
                             icon: "iphone.gen3", tint: AppSection.admin.fill, target: .devices),
                    DashTile(id: "system.banned",
                             title: L10n.t("الأرقام المحظورة", "Banned numbers"),
                             caption: L10n.t("منع التسجيل برقم", "Block sign-up by number"),
                             icon: "phone.down.fill", tint: DS.Color.error, target: .bannedPhones)
                ]))
            groups.append(SystemGroup(
                id: "group.notify", title: L10n.t("الإشعارات", "Notifications"),
                icon: "bell.badge.fill", tint: DS.Color.composerDiwaniya,
                tiles: [
                    // «إرسال إشعارات» + «تحديثات التطبيق» صفحة واحدة
                    DashTile(id: "system.messaging",
                             title: L10n.t("الإشعارات والتحديثات", "Notifications & updates"),
                             caption: L10n.t("إشعار للأعضاء أو تحديث", "Notify members or announce"),
                             icon: "bell.badge.fill", tint: DS.Color.composerDiwaniya, target: .messaging),
                    DashTile(id: "system.push",
                             title: L10n.t("حالة الإشعارات", "Push status"),
                             caption: L10n.t("جاهزية الإرسال والاختبار", "Readiness & testing"),
                             icon: "bell.and.waves.left.and.right.fill", tint: DS.Color.composerDiwaniya,
                             target: .pushHealth)
                ]))
            groups.append(SystemGroup(
                id: "group.app", title: L10n.t("التطبيق", "App"),
                icon: "gearshape.fill", tint: AppSection.admin.fill, trailing: readOnly,
                tiles: [
                    DashTile(id: "system.settings",
                             title: L10n.t("إعدادات التطبيق", "App settings"),
                             caption: L10n.t("اللغة · التسجيل · الميزات", "Language · sign-up · features"),
                             icon: "gearshape.fill", tint: AppSection.admin.fill, target: .appSettings),
                    DashTile(id: "system.forceUpdate",
                             title: L10n.t("التحديث الإجباري", "Force update"),
                             caption: L10n.t("إيقاف النسخ القديمة", "Block old versions"),
                             icon: "arrow.down.app.fill", tint: AppSection.admin.fill, target: .forceUpdate)
                ]))
        }
        if authVM.isAdmin {
            groups.append(SystemGroup(
                id: "group.reports", title: L10n.t("التقارير", "Reports"),
                icon: "doc.text.fill", tint: DS.Color.composerLibrary,
                tiles: [
                    DashTile(id: "system.analytics",
                             title: L10n.t("الإحصائيات", "Analytics"),
                             caption: L10n.t("الأعمار والنمو", "Ages & growth"),
                             icon: "chart.bar.xaxis", tint: DS.Color.composerProject,
                             target: .analytics),
                    DashTile(id: "system.reports",
                             title: L10n.t("مركز التقارير", "Reports center"),
                             caption: L10n.t("ملفات للطباعة", "Printable files"),
                             icon: "doc.text.fill", tint: DS.Color.composerLibrary,
                             target: .pdfReports)
                ]))
        }
        var next = 0
        for i in groups.indices {
            groups[i].start = next
            next += groups[i].tiles.count + 1
        }
        return groups
    }

    // MARK: - مربّعات صغيرة (شكل واحد)

    /// مربّع صغير في أي قسم
    private struct DashTile: Identifiable {
        let id: String
        let title: String
        let caption: String
        let icon: String
        let tint: Color
        /// عدد أحمر = ينتظرك — ٠ = بلا
        var alert: Int = 0
        let target: DashTarget
    }

    private func tilesGrid(_ tiles: [DashTile], columns: Int, startIndex: Int) -> some View {
        LazyVGrid(columns: landscape
                    ? [GridItem(.adaptive(minimum: DS.Landscape.tileMinWidth), spacing: DS.Spacing.sm)]
                    : Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: columns),
                  spacing: DS.Spacing.sm) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                dashTile(tile, compact: columns > 2)
                    .dsCardCascade(startIndex + index, appeared: tilesAppeared)
            }
        }
    }

    /// سطر واحد عادةً — ويلتفّ مع أحجام الخط الكبيرة جداً حتى لا يُقصّ
    private var rowTextLines: Int { dynamicTypeSize.isAccessibilitySize ? 3 : 1 }

    private func dashTile(_ tile: DashTile, compact: Bool) -> some View {
        NavigationLink {
            destinationView(tile.target)
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(alignment: .top) {
                    FT5STrial.dashTileArt(icon: tile.icon, tint: tile.tint)
                    .frame(width: compact ? DS.Icon.sizeSm : DS.Icon.tile, height: compact ? DS.Icon.sizeSm : DS.Icon.tile)
                    Spacer(minLength: DS.Spacing.xxs)
                    if tile.alert > 0 {
                        Text(Self.countText(tile.alert))
                            .dsFont(.chip)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.xsm)
                            .frame(minWidth: DS.Spacing.xxl, minHeight: DS.Icon.countBadge)
                            .background(Capsule().fill(DS.Color.error))
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                Text(tile.title)
                    .dsFont(compact ? .rowTitle : .headline)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(rowTextLines)
                    .minimumScaleFactor(0.75)
                Text(tile.caption)
                    .dsFont(compact ? .footnote : .subtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(rowTextLines)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity,
                   minHeight: (compact ? DSBox.dashTileHeightCompact : DSBox.dashTileHeight)
                       - 2 * (compact ? DS.Spacing.sm : DS.Spacing.md),
                   alignment: .topLeading)
            .dsCard(padding: compact ? DS.Spacing.sm : DS.Spacing.md)
            .overlay(cardBorder(highlight: tile.alert > 0))
            .contentShape(DSBox.sectionShape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(tile.alert > 0
            ? L10n.t("\(tile.title)، \(tile.alert) جديد", "\(tile.title), \(tile.alert) new")
            : tile.title)
        .accessibilityHint(tile.caption)
    }

    // MARK: - إطار التنبيه فوق البطاقة الواحدة

    /// البطاقة نفسها `.dsCard()`؛ وما ينتظرك يُحاط بإطار أحمر خفيف (نفس زوايا البطاقة)
    @ViewBuilder
    private func cardBorder(highlight: Bool) -> some View {
        if highlight {
            DSBox.sectionShape
                .strokeBorder(DS.Color.error.opacity(DS.Opacity.tintStroke), lineWidth: DS.Card.strokeWidth)
        }
    }

    private static func countText(_ n: Int) -> String { n > 9999 ? "9999+" : "\(n)" }

    // MARK: - مجالك

    /// صف معلومات صغير: الدور ومجاله — الضغط يعرض كل ما يقدر عليه وما لا يقدر
    private func scopeRow(_ guide: RoleGuide) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                    showFullScope.toggle()
                }
            } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSStateIcon(guide.icon, tint: domainTint, size: DS.Icon.rowCompact)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("نطاق الصلاحيات · \(guide.title)", "Your scope · \(guide.title)"))
                            .dsFieldFont(.rowTitleCompact)
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(rowTextLines)
                        Text(guide.mandate)
                            .dsFieldFont(.footnote)
                            .foregroundColor(DS.Color.fieldValue)
                            .lineLimit(rowTextLines)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .dsGlyph(DS.Glyph.xs)
                        .foregroundColor(DS.Color.textTertiary)
                        .rotationEffect(.degrees(showFullScope ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget + DS.Spacing.sm, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(DashRowPressStyle())
            .accessibilityLabel(L10n.t("نطاق الصلاحيات: \(guide.title)، \(guide.mandate)",
                                       "Your scope: \(guide.title), \(guide.mandate)"))
            .accessibilityHint(showFullScope
                               ? L10n.t("يخفي التفاصيل", "Hides the details")
                               : L10n.t("يعرض الصلاحيات المتاحة وغير المتاحة", "Shows everything you can and can't do"))

            if showFullScope {
                Divider().padding(.horizontal, DS.Spacing.md)
                VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                    ForEach(guide.can, id: \.self) { text in
                        scopeLine(text, allowed: true)
                    }
                    ForEach(guide.cannot, id: \.self) { text in
                        scopeLine(text, allowed: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.md)
                .transition(.opacity)
            }
        }
        // ظلّ الضغط داخل الزوايا، ثم البطاقة الواحدة
        .clipShape(DSBox.sectionShape)
        .dsCard(padding: nil)
    }

    private func scopeLine(_ text: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.xsm) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .dsGlyph(DS.Glyph.smCompact)
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            Text(text)
                .dsFieldFont(.subtitle)
                .foregroundColor(allowed ? DS.Color.fieldLabel : DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(allowed ? text : L10n.t("غير مسموح: \(text)", "Can't: \(text)"))
    }

    // MARK: - تحذير التوافق

    private var schemaWarningCard: some View {
        DSComposerSection(title: L10n.t("تنبيه توافق قاعدة البيانات", "Database Compatibility Warning"),
                          icon: "exclamationmark.triangle.fill",
                          tint: DS.Color.error,
                          index: 1) {
            if !authVM.notificationsFeatureAvailable {
                DSRow(icon: "bell.slash.fill", tint: DS.Color.error,
                       title: L10n.t("جدول notifications غير موجود، الإشعارات معطلة.",
                                     "Notifications table missing, feature disabled."))
            }
            if !authVM.newsApprovalFeatureAvailable {
                DSRow(icon: "newspaper.fill", tint: DS.Color.warning,
                       title: L10n.t("عمود news.approval_status غير موجود، موافقات الأخبار معطلة.",
                                     "News approval_status column missing, approvals disabled."))
            }
        }
    }
}

/// حلقة جنس في مربّع «أفراد العائلة»: نسبة الأحياء حلقةً بلون المعنى (`DSRing`) والعدد في وسطها،
/// والأحياء والمتوفون بجانبها، في صندوق صفّ (`.dsRowBox()`) — تمتلئ بهدوء حين تصل الأرقام
private struct GenderRingPanel: View {
    let title: String
    let dot: Color
    let total: Int
    let alive: Int
    let deceased: Int
    let loading: Bool

    private var share: Double { total > 0 && !loading ? Double(alive) / Double(total) : 0 }

    var body: some View {
        let ink = dot.dsReadableGlyph
        HStack(spacing: DS.Spacing.sm) {
            DSRing(progress: share, tint: ink, lineWidth: DS.Spacing.xs + 1, size: DS.Icon.sizeLg) {
                Text(loading ? "—" : "\(total)")
                    .dsFont(.headline)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, DS.Spacing.xsm)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(ink)
                    .lineLimit(1)
                line(L10n.t("أحياء", "Alive"), alive)
                line(L10n.t("متوفون", "Deceased"), deceased)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(title): \(total)، أحياء \(alive)، متوفون \(deceased)",
                                   "\(title): \(total), alive \(alive), deceased \(deceased)"))
    }

    private func line(_ label: String, _ value: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
            Text(loading ? "—" : "\(value)")
                .dsFont(.chip)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// ضغط الصف: تظليل خفيف لكامل الصف (بدل التصغير) — مثل صفوف قوائم أبل، بلا حركة
private struct DashRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(DS.Color.textTertiary.opacity(configuration.isPressed ? DS.Opacity.tintFill : 0))
    }
}

/// يبني الصفحة عند ظهورها فقط (لا عند بناء اللوحة)
private struct LazyAdminPage: View {
    let make: () -> AnyView
    var body: some View { make() }
}
