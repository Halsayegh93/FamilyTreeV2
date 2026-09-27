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
//      أو «كل شي تمام ✓» — ثم «أفراد العائلة» (لمن يرى الإحصائيات) و«مجالك» (المراقب والمشرف).
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
    @State private var toolQuery = ""
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

        withAnimation(DS.Anim.smooth) {
            pendingCount = pending
            moderatorCount = moderator
            totalMembersCount = total
            aliveMembersCount = alive
            deceasedMembersCount = deceased
            issueMembersCount = issues
            treeIssuesCount = treeIssues
            totalReviewRequestsCount = reviewTotal
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
                        title: L10n.t("الادارة", "Admin Dashboard"),
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

    // MARK: - هيكل الصفحة

    private var dashboardContent: some View {
        VStack(spacing: DS.Spacing.lg) {
            dashboardHero

            // تحذير التوافق
            if !authVM.notificationsFeatureAvailable || !authVM.newsApprovalFeatureAvailable {
                schemaWarningCard
            }

            VStack(spacing: DS.Spacing.md) {
                DSSearchField(text: $toolQuery,
                              placeholder: L10n.t("ابحث عن أداة…", "Find a tool…"),
                              tint: domainTint.dsReadableGlyph)

                if isSearching {
                    searchResults
                        .transition(.opacity)
                } else {
                    DSSegmentedSwitch(options: sectionOptions, selection: sectionBinding)
                        .transition(.opacity)
                    sectionContent
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSearching)
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

    // MARK: - بطاقة الرأس

    private var dashboardHero: some View {
        DSPageHero(
            title: L10n.t("لوحة الإدارة", "Admin Dashboard"),
            subtitle: heroSubtitle,
            icon: viewerGuide?.icon ?? "shield.lefthalf.filled",
            tint: domainTint,
            stats: heroStats
        )
    }

    /// «المالك · صاحب النظام — كل الصلاحيات» — الدور ومجاله من RoleGuides
    private var heroSubtitle: String {
        guard let guide = viewerGuide else {
            return L10n.t("المراجعة والإعدادات والتقارير", "Review, settings and reports")
        }
        return "\(guide.title) · \(guide.mandate)"
    }

    private func heroValue(_ n: Int) -> String { isInitialLoading ? "—" : "\(n)" }

    /// ٣ أرقام حيّة من بيانات اللوحة نفسها — ومن لا يرى الإحصائيات (المشرف) يرى أرقام مجاله
    private var heroStats: [DSHeroStat] {
        if canSeeStats {
            // الفعّال = رقم + جهاز (فعّال + خامل) — نفس تعريف «أفراد العائلة» أدناه
            let active = usageStats.map { "\($0.active + $0.idle)" } ?? "—"
            return [
                DSHeroStat(value: heroValue(totalMembersCount),
                           label: L10n.t("الأعضاء", "Members"), icon: "person.3.fill"),
                DSHeroStat(value: active,
                           label: L10n.t("فعّال", "Active"), icon: "checkmark.seal.fill"),
                DSHeroStat(value: heroValue(moderatorCount),
                           label: L10n.t("فريق الإدارة", "Admin team"), icon: "person.badge.shield.checkmark.fill")
            ]
        }
        // المشرف: مجاله المحتوى — المحتوى المنتظر بدل إحصائيات الأعضاء
        return [
            DSHeroStat(value: heroValue(newsVM.pendingNewsRequests.count),
                       label: L10n.t("أخبار منتظرة", "Pending news"), icon: "newspaper.fill"),
            DSHeroStat(value: heroValue(diwaniyaVM.pendingDiwaniyas.count),
                       label: L10n.t("ديوانيات", "Diwaniyas"), icon: "tent.fill"),
            DSHeroStat(value: heroValue(projectsVM.pendingProjects.count),
                       label: L10n.t("مشاريع", "Projects"), icon: "briefcase.fill")
        ]
    }

    // MARK: - نموذج الأقسام والصفوف

    private enum DashSection: Hashable { case pending, members, content }

    /// وجهة كل صف — نفس الشاشات التي كانت تفتحها البلاطات وبنود «يحتاج انتباهك»
    private enum DashTarget {
        case requests, treeEdits, inbox, members, activity, analytics, pdfReports, system
        case usage(AppUsageCategory)
    }

    /// صف واحد في أي قسم أو في نتائج البحث
    private struct DashItem: Identifiable {
        let id: String
        let title: String
        var hint: String
        let icon: String
        let tint: Color
        /// عدد أحمر = ينتظرك (طلبات، غير مقروء) — ٠ = بلا
        var alert: Int = 0
        /// رقم حيّ هادئ بلون الأداة (مثل عدد الأعضاء) — يظهر فقط إن لم يكن هناك عدد أحمر
        var info: Int? = nil
        /// ما يقوله القارئ الصوتي عن العدد الأحمر — nil = «N بانتظارك»
        var alertSpoken: String? = nil
        var infoSpoken: String? = nil
        /// قسم الأداة — روابط «أفراد العائلة» مكانها «المطلوب مني» وتظهر في البحث أيضاً
        var section: DashSection = .pending
        /// كلمات يجدها البحث (عربي وإنجليزي) — منها أسماء ما بداخل الأداة
        var keywords: [String] = []
        let target: DashTarget
    }

    @ViewBuilder
    private func destinationView(_ target: DashTarget) -> some View {
        switch target {
        case .requests:            AdminAllRequestsView()
        case .treeEdits:           AdminTreeEditRequestsView()
        case .inbox:               AdminInboxView()
        case .members:             AdminMembersManagementView()
        case .activity:            AdminActivityLogView()
        case .analytics:           AdminAnalyticsView()
        case .pdfReports:          AdminReportsView()
        // الفريق والإشعارات وتحديثات التطبيق و«صحة النظام» كلها بالداخل
        case .system:              AdminSecuritySettingsView()
        case .usage(let category): AppUsageMembersView(category: category)
        }
    }

    // MARK: - ١. المطلوب مني

    /// ما ينتظر المشاهد، بالأولوية — بنود «يحتاج انتباهك» وشروطها تماماً، ومعها طلبات تعديل
    /// الشجرة (عددها محمّل أصلاً) لمجال الشجرة. يظهر فقط ما عدده أكبر من صفر.
    private var attentionItems: [DashItem] {
        var items: [DashItem] = []
        if totalReviewRequestsCount > 0 {
            items.append(DashItem(
                id: "attention.requests",
                title: L10n.t("طلبات المراجعة", "Review requests"),
                hint: L10n.t("بانتظار قرارك", "Awaiting your decision"),
                icon: "tray.full.fill", tint: DS.Color.warning,
                alert: totalReviewRequestsCount,
                target: .requests))
        }
        let unread = adminRequestVM.unreadContactMessagesCount
        if unread > 0 {
            items.append(DashItem(
                id: "attention.messages",
                title: L10n.t("رسائل جديدة", "New messages"),
                hint: L10n.t("لم تُقرأ بعد", "Not read yet"),
                icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.composerDiwaniya,
                alert: unread,
                alertSpoken: L10n.t("\(unread) لم تُقرأ", "\(unread) unread"),
                target: .inbox))
        }
        // طلبات الانضمام — مجال الشجرة والأعضاء
        if authVM.canModerateTree && pendingCount > 0 {
            items.append(DashItem(
                id: "attention.join",
                title: L10n.t("طلبات انضمام", "Join requests"),
                hint: L10n.t("بانتظار القبول", "Awaiting approval"),
                icon: "person.badge.clock.fill", tint: DS.Color.composerProject,
                alert: pendingCount,
                target: .requests))
        }
        // طلبات تعديل الشجرة — مجال الشجرة والأعضاء (نفس شاشة إشعار «تعديل الشجرة»)
        let treeEdits = adminRequestVM.treeEditRequests.count
        if authVM.canModerateTree && treeEdits > 0 {
            items.append(DashItem(
                id: "attention.treeEdits",
                title: L10n.t("طلبات تعديل الشجرة", "Tree edit requests"),
                hint: L10n.t("إضافة وتعديل في الشجرة", "Additions and edits in the tree"),
                icon: "arrow.triangle.branch", tint: DS.Color.composerProject,
                alert: treeEdits,
                target: .treeEdits))
        }
        // البلاغات — مجال المحتوى والبلاغات
        let reports = adminRequestVM.newsReportRequests.count
        if authVM.canModerateContent && reports > 0 {
            items.append(DashItem(
                id: "attention.reports",
                title: L10n.t("بلاغات", "Reports"),
                hint: L10n.t("على المحتوى", "On content"),
                icon: "exclamationmark.bubble.fill", tint: DS.Color.error,
                alert: reports,
                target: .requests))
        }
        return items
    }

    private var pendingSection: some View {
        VStack(spacing: DS.Spacing.md) {
            VStack(spacing: 0) {
                if isInitialLoading {
                    DSSkeleton(height: 62, cornerRadius: DS.Radius.lg)
                        .transition(.opacity)
                } else if attentionItems.isEmpty {
                    allClearCard
                        .transition(.opacity)
                } else {
                    rowsCard(attentionItems)
                        .transition(.opacity)
                }
            }
            .dsStaggerIn(0)

            // «أفراد العائلة» — ملخّص لمن يرى الإحصائيات (المالك والمدير والمراقب؛ المشرف لا)
            if canSeeStats {
                censusSection
            }

            // «مجالك» — صف معلومات صغير يتوسّع. المالك والمدير مجالهما كامل فلا حاجة للتذكير.
            if let guide = scopeGuide {
                scopeRow(guide)
                    .dsStaggerIn(2)
            }
        }
        .animation(reduceMotion ? nil : DS.Anim.smooth, value: isInitialLoading)
    }

    /// لا شيء ينتظر — بطاقة هادئة بدل الأرقام الصفرية
    private var allClearCard: some View {
        HStack(spacing: DS.Spacing.md) {
            SysGradientIcon(name: "checkmark.seal.fill", tint: DS.Color.success, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("كل شي تمام ✓", "All clear ✓"))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("ما فيه طلبات ولا رسائل تنتظرك", "No requests or messages are waiting for you"))
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: 62)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(DS.Color.success.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.success.opacity(0.20), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("كل شي تمام، ما فيه طلبات ولا رسائل تنتظرك",
                                   "All clear, no requests or messages are waiting for you"))
    }

    // MARK: - ٢ و٣. الأدوات

    /// كل أدوات المشاهد — بنفس شروط بلاطات «الأقسام» السابقة تماماً، وكل أداة في قسم واحد.
    private var tools: [DashItem] {
        let loaded = !isInitialLoading
        let scope = AdminAllRequestsView.reviewScope(for: authVM)
        var list: [DashItem] = []

        // طلبات المراجعة — لكل مسؤول (بلا شرط كما كانت). قسمها بمجال المشاهد:
        // المشرف (المحتوى والبلاغات) في «المحتوى والنظام»، والباقون في «الأعضاء والشجرة».
        list.append(DashItem(
            id: "tool.requests",
            title: L10n.t("طلبات المراجعة", "Review requests"),
            hint: requestsHint(scope),
            icon: "tray.full.fill", tint: DS.Color.composerLibrary,
            alert: loaded ? totalReviewRequestsCount : 0,
            section: scope == .content ? .content : .members,
            keywords: requestsKeywords(scope),
            target: .requests))

        if authVM.canEditMembers {
            // النواقص (البيانات + مشاكل الشجرة) — كانت شارة البلاطة؛ صارت سطراً هادئاً
            let gaps = issueMembersCount + treeIssuesCount
            list.append(DashItem(
                id: "tool.members",
                title: L10n.t("إدارة الأعضاء", "Members"),
                hint: loaded && gaps > 0
                    ? L10n.t("\(gaps) نقص في البيانات", "\(gaps) data gaps")
                    : L10n.t("الحسابات والسجل والعوائل", "Accounts, registry, families"),
                icon: "person.2.badge.gearshape", tint: DS.Color.composerProject,
                info: loaded ? totalMembersCount : nil,
                infoSpoken: L10n.t("\(totalMembersCount) عضو", "\(totalMembersCount) members"),
                section: .members,
                keywords: [
                    "الحسابات", "تفعيل الحسابات", "بانتظار التفعيل", "الحسابات المجمدة", "السجل",
                    "الفروع", "العوائل", "أسماء العوائل", "جودة البيانات", "بيانات ناقصة",
                    "تعديل بيانات عضو",
                    "members", "accounts", "activation", "registry", "families", "data quality"
                ] + (authVM.canRegisterMembers ? ["تسجيل عضو جديد", "register member"] : []),
                target: .members))
        }

        // سجل النشاط: المالك/المدير/المراقب فقط (جدول الصلاحيات — ليس المشرف)
        if authVM.isAdmin || authVM.currentUser?.role == .monitor {
            let activityUnread = notificationVM.unreadActivityLogCount
            list.append(DashItem(
                id: "tool.activity",
                title: L10n.t("سجل النشاط", "Activity Log"),
                hint: L10n.t("كل حركة وتغيير", "Every change"),
                icon: "clock.arrow.circlepath", tint: DS.Color.actionNavy,
                alert: activityUnread,
                alertSpoken: L10n.t("\(activityUnread) جديد", "\(activityUnread) new"),
                section: .members,
                keywords: ["النشاط", "الحركات", "التغييرات", "التعديلات", "من عدّل",
                           "activity", "log", "changes", "history"],
                target: .activity))
        }

        // الرسائل — لكل مسؤول (بلا شرط كما كانت)
        let messagesUnread = adminRequestVM.unreadContactMessagesCount
        let awaitingReply = adminRequestVM.pendingContactMessagesCount
        list.append(DashItem(
            id: "tool.messages",
            title: L10n.t("الرسائل", "Messages"),
            hint: loaded && awaitingReply > 0
                ? L10n.t("\(awaitingReply) بانتظار الرد", "\(awaitingReply) awaiting reply")
                : L10n.t("محادثاتك مع الأعضاء", "Conversations with members"),
            icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.composerDiwaniya,
            alert: messagesUnread,
            alertSpoken: L10n.t("\(messagesUnread) لم تُقرأ", "\(messagesUnread) unread"),
            section: .content,
            keywords: ["رسائل", "المحادثات", "التواصل", "الرد", "صندوق الوارد",
                       "messages", "inbox", "contact", "chat", "reply"],
            target: .inbox))

        if authVM.isAdmin {
            list.append(DashItem(
                id: "tool.analytics",
                title: L10n.t("إحصائيات متقدمة", "Analytics"),
                hint: L10n.t("الأدوار والأعمار والنمو", "Roles, ages, growth"),
                icon: "chart.bar.xaxis", tint: DS.Color.composerProject,
                section: .content,
                keywords: ["الإحصائيات", "الأعمار", "الأدوار", "النمو", "الرسوم",
                           "analytics", "statistics", "charts", "growth"],
                target: .analytics))

            list.append(DashItem(
                id: "tool.pdf",
                title: L10n.t("تقارير PDF", "PDF Reports"),
                hint: L10n.t("تصدير ملف للطباعة", "Export printable file"),
                icon: "doc.text.fill", tint: DS.Color.composerLibrary,
                section: .content,
                keywords: ["تقرير", "طباعة", "تصدير", "ملف",
                           "reports", "export", "print"],
                target: .pdfReports))
        }

        if authVM.canViewSystemSettings {
            // «صحة النظام» صارت داخل «إعدادات النظام» — والكلمات تجد ما بداخلها
            list.append(DashItem(
                id: "tool.system",
                title: L10n.t("إعدادات النظام", "System Settings"),
                hint: L10n.t("الفريق والأجهزة والإشعارات والأمان", "Team, devices, notifications & security"),
                icon: "lock.shield.fill", tint: DS.Color.actionNavy,
                section: .content,
                keywords: [
                    "الإعدادات", "الأمان", "إعدادات التطبيق", "فريق الإدارة", "الأدوار", "الصلاحيات",
                    "الأجهزة", "النشاط الآن", "التحديث الإجباري", "إرسال إشعار", "الإشعارات",
                    "تحديثات التطبيق", "الأرقام المحظورة", "حظر رقم", "حالة الإشعارات", "استخدام التطبيق",
                    "settings", "system", "security", "team", "roles", "devices", "force update",
                    "notifications", "banned numbers", "push"
                ],
                target: .system))
        }

        // روابط «أفراد العائلة» (الفعّالون / بلا رقم) — مكانها «المطلوب مني»، وتظهر في البحث أيضاً
        if canSeeStats {
            let active = usageStats.map { $0.active + $0.idle }
            list.append(DashItem(
                id: "tool.usage.active",
                title: L10n.t("الأعضاء الفعّالون", "Active members"),
                hint: L10n.t("رقم + جهاز دخل التطبيق", "Phone + device that used the app"),
                icon: "checkmark.seal.fill", tint: DS.Color.success,
                info: active,
                infoSpoken: active.map { L10n.t("\($0) عضو", "\($0) members") },
                keywords: ["فعّال", "الفعّالون", "استخدام التطبيق", "دخلوا التطبيق", "active", "usage"],
                target: .usage(.active)))

            let noPhone = usageStats?.noPhone
            list.append(DashItem(
                id: "tool.usage.noPhone",
                title: L10n.t("أعضاء بلا رقم", "Members without a phone"),
                hint: L10n.t("أحياء بلا رقم جوال", "Living members with no phone"),
                icon: "phone.down.fill", tint: DS.Color.textTertiary,
                info: noPhone,
                infoSpoken: noPhone.map { L10n.t("\($0) عضو", "\($0) members") },
                keywords: ["بلا رقم", "بدون رقم", "بدون جوال", "no phone"],
                target: .usage(.noPhone)))
        }

        return list
    }

    /// وصف «طلبات المراجعة» بما يراه هذا الدور فيها
    private func requestsHint(_ scope: AdminAllRequestsView.ReviewScope) -> String {
        switch scope {
        case .all:     return L10n.t("انضمام، شجرة، أخبار، بلاغات", "Join, tree, news, reports")
        case .tree:    return L10n.t("الانضمام وتعديلات الشجرة", "Join and tree edits")
        case .content: return L10n.t("الأخبار والمحتوى والبلاغات", "News, content and reports")
        }
    }

    /// كلمات بحث «طلبات المراجعة» — تبويبات مجال المشاهد فقط
    private func requestsKeywords(_ scope: AdminAllRequestsView.ReviewScope) -> [String] {
        let common = ["المراجعة", "موافقة", "رفض", "اعتماد", "review", "requests", "approve", "reject"]
        let tree = ["الانضمام", "طلبات الانضمام", "تعديل الشجرة", "إضافة ابن", "وفاة", "تغيير الرقم",
                    "تعديل الاسم", "تاريخ الميلاد", "صحة الشجرة", "بدون أب", "أرقام مكررة",
                    "join", "tree", "child", "deceased", "phone change", "name change", "tree health"]
        let content = ["الأخبار", "خبر", "البلاغات", "بلاغ", "الديوانيات", "المشاريع", "المكتبة",
                       "الأرشيف", "الصور", "news", "reports", "diwaniyas", "projects", "library",
                       "archive", "photos"]
        switch scope {
        case .all:     return common + tree + content
        case .tree:    return common + tree
        case .content: return common + content
        }
    }

    // MARK: - المبدّل

    /// الأقسام الظاهرة — قسم بلا أدوات لهذا الدور لا يظهر (المشرف: لا أدوات للشجرة)
    private var visibleSections: [DashSection] {
        let used = Set(tools.map(\.section))
        return [.pending] + [DashSection.members, .content].filter { used.contains($0) }
    }

    /// القسم المعروض — إن لم يعد المختار ظاهراً نرجع لـ«المطلوب مني»
    private var effectiveSection: DashSection {
        visibleSections.contains(selectedSection) ? selectedSection : .pending
    }

    private var sectionBinding: Binding<DashSection> {
        Binding(get: { effectiveSection }, set: { selectedSection = $0 })
    }

    /// بلا أعداد على الأزرار: الأعداد الحمراء على الصفوف نفسها (وفي صفوف الأدوات أيضاً)، وبثلاثة
    /// أزرار لا يتّسع عدد بجانب «المطلوب مني» في الشاشات الصغيرة. أيقونات ضيّقة (قياس خط Plex):
    /// العناوين الثلاثة تبقى بنفس الحجم تقريباً (٩٦–١٠٠٪ على ٣٩٣ نقطة، ٨٩٪ فأكثر على ٣٧٥).
    private var sectionOptions: [DSSegmentOption<DashSection>] {
        visibleSections.map { section -> DSSegmentOption<DashSection> in
            switch section {
            case .pending:
                return DSSegmentOption(id: .pending,
                                       title: L10n.t("المطلوب مني", "For me"),
                                       icon: "checklist")
            case .members:
                return DSSegmentOption(id: .members,
                                       title: L10n.t("الأعضاء والشجرة", "Members"),
                                       icon: "person.fill")
            case .content:
                return DSSegmentOption(id: .content,
                                       title: L10n.t("المحتوى والنظام", "Content"),
                                       icon: "gearshape.fill")
            }
        }
    }

    /// التبديل: القديم يتلاشى بسرعة والجديد يدخل بـ dsStaggerIn (يحترم «تقليل الحركة») —
    /// داخل ZStack حتى لا تقفز الصفحة لحظة التبديل
    private var sectionSwap: AnyTransition {
        .asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.1)))
    }

    private var sectionContent: some View {
        ZStack(alignment: .top) {
            switch effectiveSection {
            case .pending:
                pendingSection
                    .transition(sectionSwap)
            case .members:
                rowsCard(tools.filter { $0.section == .members })
                    .dsStaggerIn(0)
                    .transition(sectionSwap)
            case .content:
                rowsCard(tools.filter { $0.section == .content })
                    .dsStaggerIn(0)
                    .transition(sectionSwap)
            }
        }
    }

    // MARK: - البحث عن أداة

    private var isSearching: Bool {
        !toolQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// كل أدوات المشاهد المسموحة المطابقة — بالعنوان أولاً ثم بكلمات ما بداخلها
    /// (وحينها التلميح يقول أين: «فيها: الأجهزة»)
    private var searchMatches: [DashItem] {
        let tokens = Self.searchTokens(toolQuery)
        guard !tokens.isEmpty else { return [] }
        var byTitle: [DashItem] = []
        var byKeyword: [DashItem] = []
        for tool in tools {
            let title = Self.fold(tool.title)
            let words = tool.keywords.map { (original: $0, folded: Self.fold($0)) }
            var via: String? = nil
            var matched = true
            for token in tokens where !title.contains(token) {
                guard let hit = words.first(where: { $0.folded.contains(token) }) else {
                    matched = false
                    break
                }
                if via == nil { via = hit.original }
            }
            guard matched else { continue }
            if let via {
                var item = tool
                item.hint = L10n.t("فيها: \(via)", "Includes: \(via)")
                byKeyword.append(item)
            } else {
                byTitle.append(tool)
            }
        }
        return byTitle + byKeyword
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = searchMatches
        if matches.isEmpty {
            let examples = tools.filter { $0.section != .pending }
                .prefix(3).map(\.title).joined(separator: L10n.t("، ", ", "))
            SysStateCard(icon: "magnifyingglass",
                         title: L10n.t("ما لقينا أداة بهذا الاسم", "No tool matches that"),
                         hint: L10n.t("جرّب كلمة ثانية، مثل: \(examples)", "Try another word, like: \(examples)"),
                         tint: DS.Color.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                SysSectionTitle(title: L10n.t("نتائج البحث", "Search results"),
                                icon: "magnifyingglass",
                                tint: domainTint,
                                trailing: "\(matches.count)")
                rowsCard(matches)
            }
        }
    }

    /// توحيد النص للبحث: بلا تشكيل ولا همزات ولا تطويل، والتاء المربوطة هاء والألف المقصورة ياء.
    /// على مستوى الحروف المفردة — `diacriticInsensitive` لا يحذف التشكيل العربي (الشدّة، الضمّة…).
    private static func fold(_ text: String) -> String {
        let base = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                locale: nil)
        var out = String.UnicodeScalarView()
        for scalar in base.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640:
                continue                                        // تشكيل وهمزة مركّبة وتطويل
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")   // آ أ إ ٱ
            case 0x0629: out.append("ه")                           // ة
            case 0x0649, 0x0626: out.append("ي")                   // ى ئ
            case 0x0624: out.append("و")                           // ؤ
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// كلمات البحث — «ال» في أول الكلمة لا تمنع المطابقة («الأجهزة» = «أجهزة»)
    private static func searchTokens(_ query: String) -> [String] {
        fold(query)
            .split(whereSeparator: { $0.isWhitespace || $0 == "،" || $0 == "," })
            .map { word -> String in
                var w = String(word)
                if w.count >= 4, w.hasPrefix("ال") { w.removeFirst(2) }
                return w
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - الصفوف (شكل واحد في كل مكان)

    /// بداية الفاصل بعد الأيقونة: حاشية الصف + الأيقونة + المسافة
    private static let dividerInset: CGFloat = DS.Spacing.md + 40 + DS.Spacing.md

    /// بطاقة واحدة فيها صفوف بفواصل — نفسها في الأقسام وفي نتائج البحث
    private func rowsCard(_ items: [DashItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                dashRow(item)
                if index < items.count - 1 {
                    Divider().padding(.leading, Self.dividerInset)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    /// سطر واحد عادةً — ويلتفّ مع أحجام الخط الكبيرة جداً حتى لا يُقصّ
    private var rowTextLines: Int { dynamicTypeSize.isAccessibilitySize ? 3 : 1 }

    /// صف كبير: أيقونة بمربّع فاتح بلون الأداة، العنوان والتلميح، العدد، ثم السهم
    private func dashRow(_ item: DashItem) -> some View {
        NavigationLink {
            destinationView(item.target)
        } label: {
            HStack(spacing: DS.Spacing.md) {
                SysGradientIcon(name: item.icon, tint: item.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(rowTextLines)
                        .minimumScaleFactor(0.85)
                    Text(item.hint)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(rowTextLines)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: DS.Spacing.sm)
                rowCount(item)
                SysChevron()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DashRowPressStyle())
        .accessibilityLabel(spokenLabel(item))
        .accessibilityHint(item.hint)
    }

    /// العدد: أحمر لما ينتظرك، أو رقم هادئ بلون الأداة
    @ViewBuilder
    private func rowCount(_ item: DashItem) -> some View {
        if item.alert > 0 {
            Text(Self.countText(item.alert))
                .font(DS.Font.plex(12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .frame(minWidth: 26, minHeight: 22)
                .background(Capsule().fill(DS.Color.error))
                .accessibilityHidden(true)
        } else if let info = item.info {
            Text(Self.countText(info))
                .font(DS.Font.plex(12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(item.tint.dsReadableGlyph)
                .padding(.horizontal, 8)
                .frame(minWidth: 26, minHeight: 22)
                .background(Capsule().fill(item.tint.dsReadableGlyph.opacity(0.13)))
                .accessibilityHidden(true)
        }
    }

    private static func countText(_ n: Int) -> String { n > 999 ? "999+" : "\(n)" }

    /// «طلبات المراجعة، ٥ بانتظارك» — العنوان ثم العدد بمعناه
    private func spokenLabel(_ item: DashItem) -> String {
        var parts = [item.title]
        if item.alert > 0 {
            parts.append(item.alertSpoken ?? L10n.t("\(item.alert) بانتظارك", "\(item.alert) pending"))
        } else if let info = item.info {
            parts.append(item.infoSpoken ?? "\(info)")
        }
        return parts.joined(separator: L10n.t("، ", ", "))
    }

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
                        Text(L10n.t("مجالك · \(guide.title)", "Your scope · \(guide.title)"))
                            .font(DS.Font.plex(13, weight: .bold))
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(rowTextLines)
                        Text(guide.mandate)
                            .font(DS.Font.plex(11.5))
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
            .accessibilityLabel(L10n.t("مجالك: \(guide.title)، \(guide.mandate)",
                                       "Your scope: \(guide.title), \(guide.mandate)"))
            .accessibilityHint(showFullScope
                               ? L10n.t("يخفي التفاصيل", "Hides the details")
                               : L10n.t("يعرض كل ما تقدر عليه وما لا تقدر", "Shows everything you can and can't do"))

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
                .font(DS.Font.plex(12, weight: .medium))
                .foregroundColor(allowed ? DS.Color.fieldLabel : DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(allowed ? text : L10n.t("لا: \(text)", "Can't: \(text)"))
    }

    // MARK: - أفراد العائلة

    @ViewBuilder
    private var censusSection: some View {
        if isInitialLoading {
            DSSkeleton(height: 190, cornerRadius: DS.Radius.lg)
                .transition(.opacity)
        } else {
            DSComposerSection(title: L10n.t("أفراد العائلة", "Family members"),
                              icon: "person.3.fill",
                              tint: DS.Color.composerProject,
                              trailing: L10n.t("الرجال والنساء", "Men & women"),
                              index: 1) {
                censusTable
                    .dsRowBox()

                // استخدام التطبيق — العضو الفعّال = رقم + جهاز دخل التطبيق
                // (تعريف المالك). أرقام الشجرة وحدها لا تعني استخدام التطبيق.
                if let usage = usageStats {
                    // لوحة الإدارة: الفعّال وبلا رقم فقط — التقسيم الكامل في «إعدادات النظام»
                    HStack(spacing: DS.Spacing.sm) {
                        // كل من عنده رقم وجهاز — بدون فصل الخامل (طلب المالك)
                        usagePill(category: .active, icon: "checkmark.seal.fill", value: usage.active + usage.idle,
                                  label: L10n.t("فعّال (رقم + جهاز)", "Active (phone + device)"),
                                  color: DS.Color.success)
                        usagePill(category: .noPhone, icon: "phone.down.fill", value: usage.noPhone,
                                  label: L10n.t("بلا رقم", "No phone"),
                                  color: DS.Color.textTertiary)
                    }
                }
            }
        }
    }

    /// جدول واحد: صفّ لكل جنس، عمود لكل حالة — المقارنة نظرة واحدة
    private var censusTable: some View {
        // أعمدة ثابتة العرض: الاسم يسار، والأرقام الثلاثة
        // تتقاسم الباقي بالتساوي — فتتراصّ الخانات تحت عناوينها.
        Grid(alignment: .center,
             horizontalSpacing: DS.Spacing.xs,
             verticalSpacing: 10) {
            GridRow {
                Text("")
                    .frame(width: 58, alignment: .leading)
                censusHeader(L10n.t("الكل", "Total"))
                censusHeader(L10n.t("الأحياء", "Alive"))
                censusHeader(L10n.t("المتوفون", "Deceased"))
            }

            GridRow {
                censusLabel(L10n.t("الرجال", "Men"), DS.Color.primary)
                censusValue(totalMembersCount)
                censusValue(aliveMembersCount)
                censusValue(deceasedMembersCount)
            }

            // خطّ يفصل الجنسين — يمتدّ على الأعمدة الأربعة
            Divider()
                .overlay(DS.Color.textTertiary.opacity(0.22))
                .gridCellColumns(4)

            GridRow {
                censusLabel(L10n.t("النساء", "Women"), DS.Color.female)
                censusValue(womenTotalCount)
                censusValue(womenAliveCount)
                censusValue(womenDeceasedCount)
            }
        }
        .padding(.vertical, 2)
    }

    /// عنوان عمود في جدول الأفراد
    private func censusHeader(_ t: String) -> some View {
        Text(t)
            .font(DS.Font.plex(10.5, weight: .semibold))
            .foregroundColor(DS.Color.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)   // «المتوفون» لا يلتفّ ولا يزيح العمود
            .frame(maxWidth: .infinity)
    }

    /// اسم الصفّ — نقطة ملوّنة تميّز الجنس بلا كلمة زائدة
    private func censusLabel(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(t)
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
        }
        .frame(width: 58, alignment: .leading)
    }

    /// رقم في الجدول — أرقام جدولية فتتراصّ الخانات عمودياً
    private func censusValue(_ v: Int) -> some View {
        Text("\(v)")
            .font(DS.Font.plex(16, weight: .bold))
            .monospacedDigit()
            .foregroundColor(DS.Color.fieldLabel)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
    }

    /// رقم «استخدام التطبيق» — يفتح أعضاء الفئة
    private func usagePill(category: AppUsageCategory, icon: String, value: Int, label: String, color: Color) -> some View {
        NavigationLink {
            AppUsageMembersView(category: category)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)")
                        .font(DS.Font.plex(16, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(label)
                        .font(DS.Font.plex(10.5, weight: .semibold))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                SysChevron()
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel("\(label): \(value)")
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
        if let badge, badge > 0 { parts.append(badgeSpoken ?? L10n.t("\(badge) بانتظارك", "\(badge) pending")) }
        if let detail, !compact { parts.append(detail) }
        return parts.joined(separator: "، ")
    }

    /// بلاطة أبسط (طلب المالك): أيقونة + العنوان + رقم صغير، والشارة الحمراء إن وُجدت — سطر واحد
    private var fullLabel: some View {
        HStack(spacing: DS.Spacing.sm) {
            SysGradientIcon(name: icon, tint: color, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(DS.Font.plex(11, weight: .semibold))
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
                .font(DS.Font.plex(11.5, weight: .bold))
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
