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
//   ٣. «المحتوى والنظام»: الرسائل والإحصائيات والتقارير وإعدادات النظام.
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
                        backgroundGradient: DS.Color.gradientPrimary,
                        hasDropShadow: false
                    )

                    ScrollView(showsIndicators: false) {
                        dashboardContent
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.md)
                            .padding(.bottom, DS.Spacing.xxxl)
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
    private var domainTint: Color {
        switch authVM.currentUser?.role {
        case .monitor:    return DS.Color.composerProject
        case .supervisor: return DS.Color.composerLibrary
        default:          return DS.Color.actionNavy
        }
    }

    // MARK: - مربّع «أفراد العائلة»

    private var familyHero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .accessibilityHidden(true)
                Text(L10n.t("أفراد العائلة", "Family members"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                // الدور للمالك والمدير (المراقب يراه في «مجالك» — بلا تكرار)
                if authVM.isAdmin, let guide = viewerGuide {
                    Text(guide.title)
                        .font(DS.Font.plex(11.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                }
            }

            HStack(spacing: DS.Spacing.sm) {
                GenderRingPanel(title: L10n.t("الرجال", "Men"), dot: DS.Color.primaryLight,
                                total: totalMembersCount, alive: aliveMembersCount,
                                deceased: deceasedMembersCount, loading: isInitialLoading)
                GenderRingPanel(title: L10n.t("النساء", "Women"), dot: DS.Color.female,
                                total: womenTotalCount, alive: womenAliveCount,
                                deceased: womenDeceasedCount, loading: isInitialLoading)
            }
        }
        .padding(DS.Spacing.lg)
        .background(
            ZStack {
                LinearGradient(colors: [domainTint, domainTint.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // دائرتان ناعمتان للعمق (ثابتتان — بلا حركة)
                Circle().fill(Color.white.opacity(0.07))
                    .frame(width: 190, height: 190)
                    .offset(x: 130, y: -70)
                Circle().fill(Color.white.opacity(0.05))
                    .frame(width: 140, height: 140)
                    .offset(x: -140, y: 80)
                if colorScheme == .dark { Color.black.opacity(0.3) }
            }
            .accessibilityHidden(true)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .shadow(color: domainTint.opacity(colorScheme == .dark ? 0 : 0.16), radius: 10, x: 0, y: 5)
    }

    // MARK: - الأقسام

    private enum DashSection: Hashable { case pending, members, system }

    /// وجهة كل بطاقة
    private enum DashTarget {
        case requests, inbox, members, activity, analytics, pdfReports, system, deaths
        case usage(AppUsageCategory)
    }

    @ViewBuilder
    private func destinationView(_ target: DashTarget) -> some View {
        switch target {
        case .requests:            AdminAllRequestsView()
        case .inbox:               AdminInboxView()
        case .members:             AdminMembersManagementView()
        case .activity:            AdminActivityLogView()
        case .analytics:           AdminAnalyticsView()
        case .pdfReports:          AdminReportsView()
        // الفريق والإشعارات وتحديثات التطبيق و«صحة النظام» كلها بالداخل
        case .system:              AdminSecuritySettingsView()
        case .usage(let category): AppUsageMembersView(category: category)
        case .deaths:              DeathAnnouncementsPage()
        }
    }

    /// الأقسام الظاهرة — قسم بلا محتوى لهذا الدور لا يظهر
    private var visibleSections: [DashSection] {
        var sections: [DashSection] = [.pending]
        if !memberTiles.isEmpty || canSeeStats { sections.append(.members) }
        if !systemTiles.isEmpty || authVM.canViewSystemSettings { sections.append(.system) }
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
                VStack(spacing: DS.Spacing.md) {
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
                VStack(spacing: DS.Spacing.md) {
                    if authVM.canViewSystemSettings {
                        settingsCard
                            .dsCardCascade(0, appeared: tilesAppeared)
                    }
                    tilesGrid(systemTiles, columns: 2, startIndex: 1)
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
                    SysGradientIcon(name: "tray.full.fill", tint: tint, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("طلبات المراجعة", "Review requests"))
                            .font(DS.Font.plex(16, weight: .bold))
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(reviews > 0 ? L10n.t("بانتظار قرارك", "Awaiting your decision")
                                         : L10n.t("لا شيء بانتظارك", "Nothing waiting"))
                            .dsFieldFont(12)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                    Spacer(minLength: DS.Spacing.sm)
                    statusBadge(alert: reviews, loading: isInitialLoading)
                    SysChevron()
                }
                let chips = reviewChips
                if !chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)],
                              alignment: .leading, spacing: 6) {
                        ForEach(chips) { chip in reviewChipView(chip) }
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(tint))
            .overlay(cardBorder(highlight: reviews > 0))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(reviews > 0
            ? L10n.t("طلبات المراجعة، \(reviews) بانتظار قرارك", "Review requests, \(reviews) waiting")
            : L10n.t("طلبات المراجعة، لا شيء بانتظارك", "Review requests, nothing waiting"))
    }

    private func reviewChipView(_ chip: ReviewChip) -> some View {
        let color = chip.tint.dsReadableGlyph
        return HStack(spacing: 5) {
            Image(systemName: chip.icon)
                .font(.system(size: 10.5, weight: .bold))
                .accessibilityHidden(true)
            Text(chip.label)
                .font(DS.Font.plex(11.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Text("\(chip.count)")
                .font(DS.Font.plex(12, weight: .bold))
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Capsule().fill(color.opacity(0.12)))
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
                SysGradientIcon(name: "bubble.left.and.bubble.right.fill", tint: tint, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("الرسائل", "Messages"))
                        .font(DS.Font.plex(16, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(caption)
                        .dsFieldFont(12)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: DS.Spacing.sm)
                statusBadge(alert: unread, loading: false)
                SysChevron()
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(tint))
            .overlay(cardBorder(highlight: unread > 0))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("الرسائل، \(caption)", "Messages, \(caption)"))
    }

    /// العدد الأحمر لما ينتظرك، أو ✓ خضراء حين لا شيء
    @ViewBuilder
    private func statusBadge(alert: Int, loading: Bool) -> some View {
        if loading {
            ProgressView().scaleEffect(0.8)
        } else if alert > 0 {
            Text(Self.countText(alert))
                .font(DS.Font.plex(15, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(minWidth: 34, minHeight: 28)
                .background(Capsule().fill(DS.Color.error))
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
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
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                SysGradientIcon(name: "iphone.gen3", tint: DS.Color.success, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("استخدام التطبيق", "App usage"))
                        .font(DS.Font.plex(16, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(total > 0 ? L10n.t("من \(total) من الأحياء", "Of \(total) living members")
                         : isInitialLoading ? L10n.t("جارٍ التحميل…", "Loading…")
                         : L10n.t("غير متاح الآن — اسحب للتحديث", "Unavailable — pull to refresh"))
                        .dsFieldFont(12)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }

            UsageBar(segments: segments.map { ($0.value, $0.color) }, total: total)
                .frame(height: 12)
                .accessibilityHidden(true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.sm),
                                GridItem(.flexible(), spacing: DS.Spacing.sm)],
                      spacing: DS.Spacing.sm) {
                ForEach(segments) { seg in
                    NavigationLink { destinationView(.usage(seg.category)) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(seg.color).frame(width: 9, height: 9)
                                .accessibilityHidden(true)
                            Text(seg.label)
                                .dsFieldFont(12.5, weight: .semibold)
                                .foregroundColor(DS.Color.fieldLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 2)
                            Text("\(seg.value)")
                                .font(DS.Font.plex(14, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(seg.color.dsReadableGlyph)
                                .contentTransition(.numericText())
                            SysChevron()
                        }
                        .padding(.horizontal, DS.Spacing.sm + 2)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.background))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel("\(seg.label): \(seg.value)")
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(DS.Color.success))
        .overlay(cardBorder(highlight: false))
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
        // إعلان وفاة — مكان ثابت: نفس من يعتمد الوفيات
        if authVM.canApproveTreeRequests {
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
                                 icon: "clock.arrow.circlepath", tint: DS.Color.actionNavy,
                                 alert: notificationVM.unreadActivityLogCount,
                                 target: .activity))
        }
        return list
    }

    // MARK: - «النظام»: الإعدادات + الإحصائيات والتقارير

    private var settingsCard: some View {
        let tint = DS.Color.actionNavy
        let parts: [(String, String)] = [
            ("person.badge.shield.checkmark.fill",
             isInitialLoading ? L10n.t("الفريق", "Team") : L10n.t("الفريق \(moderatorCount)", "Team \(moderatorCount)")),
            ("iphone.gen3", L10n.t("الأجهزة", "Devices")),
            ("bell.badge.fill", L10n.t("الإشعارات", "Notifications")),
            ("arrow.down.app.fill", L10n.t("التحديث الإجباري", "Force update"))
        ]
        return NavigationLink { destinationView(.system) } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.md) {
                    SysGradientIcon(name: "lock.shield.fill", tint: tint, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("الإعدادات", "Settings"))
                            .font(DS.Font.plex(16, weight: .bold))
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(L10n.t("التطبيق والأمان", "App & security"))
                            .dsFieldFont(12)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                    Spacer(minLength: 0)
                    SysChevron()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
                          alignment: .leading, spacing: 6) {
                    ForEach(parts, id: \.1) { icon, label in
                        HStack(spacing: 5) {
                            Image(systemName: icon)
                                .font(.system(size: 10.5, weight: .bold))
                                .accessibilityHidden(true)
                            Text(label)
                                .font(DS.Font.plex(11.5, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(tint.dsReadableGlyph)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(Capsule().fill(tint.dsReadableGlyph.opacity(0.10)))
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(tint))
            .overlay(cardBorder(highlight: false))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("الإعدادات: الفريق والأجهزة والإشعارات والتحديث الإجباري",
                                   "Settings: team, devices, notifications, force update"))
    }

    private var systemTiles: [DashTile] {
        var list: [DashTile] = []
        if authVM.isAdmin {
            list.append(DashTile(id: "system.analytics",
                                 title: L10n.t("الإحصائيات", "Analytics"),
                                 caption: L10n.t("الأعمار والنمو", "Ages & growth"),
                                 icon: "chart.bar.xaxis", tint: DS.Color.composerProject,
                                 target: .analytics))
            list.append(DashTile(id: "system.reports",
                                 title: L10n.t("التقارير", "Reports"),
                                 caption: L10n.t("ملفات للطباعة", "Printable files"),
                                 icon: "doc.text.fill", tint: DS.Color.composerLibrary,
                                 target: .pdfReports))
        }
        return list
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: columns),
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
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    SysGradientIcon(name: tile.icon, tint: tile.tint, size: compact ? 38 : 42)
                    Spacer(minLength: 2)
                    if tile.alert > 0 {
                        Text(Self.countText(tile.alert))
                            .font(DS.Font.plex(12, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 24, minHeight: 21)
                            .background(Capsule().fill(DS.Color.error))
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                Text(tile.title)
                    .font(DS.Font.plex(compact ? 13 : 14.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(rowTextLines)
                    .minimumScaleFactor(0.75)
                Text(tile.caption)
                    .font(DS.Font.plex(compact ? 10.5 : 11.5))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(rowTextLines)
                    .minimumScaleFactor(0.75)
            }
            .padding(compact ? DS.Spacing.sm + 2 : DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: compact ? 108 : 116, alignment: .topLeading)
            .background(cardBackground(tile.tint))
            .overlay(cardBorder(highlight: tile.alert > 0))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(tile.alert > 0
            ? L10n.t("\(tile.title)، \(tile.alert) جديد", "\(tile.title), \(tile.alert) new")
            : tile.title)
        .accessibilityHint(tile.caption)
    }

    // MARK: - خلفية وإطار البطاقات (لمسة لون القسم من الأعلى)

    private func cardBackground(_ tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [tint.dsReadableGlyph.opacity(0.12), .clear],
                                     startPoint: .top, endPoint: .bottom))
        }
    }

    private func cardBorder(highlight: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .strokeBorder(highlight ? DS.Color.error.opacity(0.30) : DS.Color.textTertiary.opacity(0.12),
                          lineWidth: 1)
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
                    SysGradientIcon(name: guide.icon, tint: domainTint, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("نطاق الصلاحيات · \(guide.title)", "Your scope · \(guide.title)"))
                            .dsFieldFont(13, weight: .bold)
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(rowTextLines)
                        Text(guide.mandate)
                            .dsFieldFont(11.5)
                            .foregroundColor(DS.Color.fieldValue)
                            .lineLimit(rowTextLines)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                        .rotationEffect(.degrees(showFullScope ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
                VStack(alignment: .leading, spacing: 6) {
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
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private func scopeLine(_ text: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .dsFieldFont(12, weight: .medium)
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
                SysRow(icon: "bell.slash.fill", tint: DS.Color.error,
                       title: L10n.t("جدول notifications غير موجود، الإشعارات معطلة.",
                                     "Notifications table missing, feature disabled."))
            }
            if !authVM.newsApprovalFeatureAvailable {
                SysRow(icon: "newspaper.fill", tint: DS.Color.warning,
                       title: L10n.t("عمود news.approval_status غير موجود، موافقات الأخبار معطلة.",
                                     "News approval_status column missing, approvals disabled."))
            }
        }
    }
}

/// ضغط الصف: تظليل خفيف لكامل الصف (بدل التصغير) — مثل صفوف قوائم أبل، بلا حركة
/// حلقة جنس في مربّع «أفراد العائلة»: نسبة الأحياء حلقةً بيضاء والعدد في وسطها،
/// والأحياء والمتوفون بجانبها — تمتلئ الحلقة بهدوء عند التحميل (بلا حركة مع «تقليل الحركة»)
private struct GenderRingPanel: View {
    let title: String
    let dot: Color
    let total: Int
    let alive: Int
    let deceased: Int
    let loading: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var share: Double { total > 0 ? Double(alive) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.20), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: shown && !loading ? share : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // تمتلئ بهدوء حين تصل الأرقام — «تقليل الحركة»: مباشرة
                    .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85).delay(0.1),
                               value: shown && !loading)
                Text(loading ? "—" : "\(total)")
                    .font(DS.Font.plex(15, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 6)
                    .contentTransition(.numericText())
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(title)
                        .font(DS.Font.plex(13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                line(L10n.t("أحياء", "Alive"), alive)
                line(L10n.t("متوفون", "Deceased"), deceased)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .onAppear { DispatchQueue.main.async { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(title): \(total)، أحياء \(alive)، متوفون \(deceased)",
                                   "\(title): \(total), alive \(alive), deceased \(deceased)"))
    }

    private func line(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DS.Font.plex(11, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
            Text(loading ? "—" : "\(value)")
                .font(DS.Font.plex(12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

}

/// شريط «استخدام التطبيق»: قطعة لكل فئة بعرض نسبتها — يمتدّ بهدوء عند الظهور
private struct UsageBar: View {
    let segments: [(Int, Color)]
    let total: Int
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let visible = segments.filter { $0.0 > 0 }
            let gaps = CGFloat(max(visible.count - 1, 0)) * 3
            let width = max(geo.size.width - gaps, 0)
            HStack(spacing: 3) {
                if total > 0 {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, seg in
                        Capsule()
                            .fill(seg.1)
                            .frame(width: max(6, width * CGFloat(seg.0) / CGFloat(total)) * (grown ? 1 : 0))
                    }
                } else {
                    Capsule().fill(DS.Color.textTertiary.opacity(0.15))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if reduceMotion { grown = true; return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.2)) { grown = true }
        }
    }
}

private struct DashRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(DS.Color.textTertiary.opacity(configuration.isPressed ? 0.12 : 0))
    }
}

// MARK: - بلاطة قسم

/// بلاطة قسم إداري — تُستعمل في «إعدادات النظام» (وكانت في لوحة الإدارة قبل فكرة الأقسام).
/// الكاملة: أيقونة متدرّجة بلون المجال + عنوان + وصف + رقم حيّ + شارة حمراء لما ينتظر.
/// المضغوطة (إعدادات النظام، ثلاثة أعمدة — طلب المالك): أيقونة + عنوان فقط.
struct AdminTile<Destination: View>: View {
    let title: String
    let subtitle: String  // يُستخدم كوصف وصولية فقط في العرض المضغوط
    let icon: String
    let color: Color
    var badge: Int? = nil
    /// سطر رقم حيّ صغير أسفل البلاطة (مثل «١٢٣ عضو») — nil = بلا
    var detail: String? = nil
    /// أصغر — لشبكة «إعدادات النظام» بثلاثة أعمدة (طلب المالك)
    var compact: Bool = false
    /// ما يقوله القارئ الصوتي عن الشارة — nil = «N بانتظارك» (للشارات التي ليست طلبات، مثل عدد الفريق)
    var badgeSpoken: String? = nil
    @ViewBuilder let destination: () -> Destination

    private var hasBadge: Bool { (badge ?? 0) > 0 }

    var body: some View {
        NavigationLink(destination: destination()) {
            if compact { compactLabel } else { fullLabel }
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [title, subtitle]
        if let badge, badge > 0 { parts.append(badgeSpoken ?? L10n.t("\(badge) بانتظار الإجراء", "\(badge) pending")) }
        if let detail, !compact { parts.append(detail) }
        return parts.joined(separator: "، ")
    }

    /// بلاطة أبسط (طلب المالك): أيقونة + العنوان + رقم صغير، والشارة الحمراء إن وُجدت — سطر واحد
    private var fullLabel: some View {
        HStack(spacing: DS.Spacing.sm) {
            SysGradientIcon(name: icon, tint: color, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .dsFieldFont(13.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .dsFieldFont(11, weight: .semibold)
                        .foregroundColor(DS.Color.fieldValue)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if hasBadge { badgeView }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var compactLabel: some View {
        VStack(spacing: DS.Spacing.xs + 2) {
            SysGradientIcon(name: icon, tint: color, size: 38)
                .overlay(alignment: .topTrailing) {
                    if hasBadge {
                        badgeView
                            .fixedSize()
                            .offset(x: L10n.isArabic ? -12 : 12, y: -7)
                    }
                }
            Text(title)
                .dsFieldFont(11.5, weight: .bold)
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .padding(.horizontal, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    /// الشارة حمراء دائماً — لون المربّع كان يجعل بعضها باهتاً فلا يُقرأ كتنبيه يحتاج إجراءً
    private var badgeView: some View {
        let value = badge ?? 0
        return Text(value > 99 ? "99+" : "\(value)")
            .font(DS.Font.plex(11, weight: .bold))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(DS.Color.error))
            .accessibilityHidden(true)
    }
}
