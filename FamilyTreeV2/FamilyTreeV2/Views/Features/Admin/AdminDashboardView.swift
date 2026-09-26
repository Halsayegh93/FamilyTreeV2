import SwiftUI

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
}

// MARK: - لوحة الإدارة (تصميم المربّعات الموحّد — طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// من الأعلى: بطاقة رأس «لوحة الإدارة» بدور المشاهد ومجاله (من RoleGuides) و٣ أرقام حيّة ←
// «يحتاج انتباهك» (بطاقات قابلة للضغط لما ينتظر إجراءً) ← «مجالك» للمراقب والمشرف ←
// «أفراد العائلة» (لمن يرى الإحصائيات) ← شبكة الأقسام بعمودين بأيقونات متدرّجة بلون المجال.
// كل بلاطة تحفظ صلاحيتها ووجهتها كما كانت تماماً.

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
    /// «مجالك»: السطور المختصرة أو كل ما يقدر وما لا يقدر عليه
    @State private var showFullScope = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الوضع الأفقي — بلاطات الأقسام على ثلاثة أعمدة
    private var isLandscape: Bool { vSizeClass == .compact }

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
            pendingArchiveCount: pendingArchiveCount
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

            attentionSection
                .dsStaggerIn(1)

            // «مجالك» — يعرف كل مسؤول حدوده وقت العمل (طلب المالك).
            // المالك والمدير مجالهما كامل فلا حاجة للتذكير.
            if let guide = scopeGuide {
                scopeSection(guide)
            }

            // إحصائيات — مدير + مراقب + مالك (المشرف لا)
            if canSeeStats {
                censusSection
            }

            sectionsGrid
                .dsStaggerIn(4)
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

    // MARK: - يحتاج انتباهك

    private enum AttentionTarget { case requests, inbox }

    private struct AttentionItem: Identifiable {
        let id: String
        let title: String
        let hint: String
        let icon: String
        let tint: Color
        let count: Int
        let target: AttentionTarget
    }

    /// ما ينتظر إجراءً، بالأولوية — يظهر فقط ما عدده أكبر من صفر وما يدخل في مجال المشاهد
    private var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        if totalReviewRequestsCount > 0 {
            items.append(AttentionItem(
                id: "requests",
                title: L10n.t("طلبات المراجعة", "Review requests"),
                hint: L10n.t("بانتظار قرارك", "Awaiting your decision"),
                icon: "tray.full.fill", tint: DS.Color.warning,
                count: totalReviewRequestsCount, target: .requests))
        }
        let unread = adminRequestVM.unreadContactMessagesCount
        if unread > 0 {
            items.append(AttentionItem(
                id: "messages",
                title: L10n.t("رسائل جديدة", "New messages"),
                hint: L10n.t("لم تُقرأ بعد", "Not read yet"),
                icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.composerDiwaniya,
                count: unread, target: .inbox))
        }
        // طلبات الانضمام — مجال الشجرة والأعضاء
        if authVM.canModerateTree && pendingCount > 0 {
            items.append(AttentionItem(
                id: "join",
                title: L10n.t("طلبات انضمام", "Join requests"),
                hint: L10n.t("بانتظار القبول", "Awaiting approval"),
                icon: "person.badge.clock.fill", tint: DS.Color.composerProject,
                count: pendingCount, target: .requests))
        }
        // البلاغات — مجال المحتوى والبلاغات
        let reports = adminRequestVM.newsReportRequests.count
        if authVM.canModerateContent && reports > 0 {
            items.append(AttentionItem(
                id: "reports",
                title: L10n.t("بلاغات", "Reports"),
                hint: L10n.t("على المحتوى", "On content"),
                icon: "exclamationmark.bubble.fill", tint: DS.Color.error,
                count: reports, target: .requests))
        }
        return items
    }

    @ViewBuilder
    private func attentionDestination(_ target: AttentionTarget) -> some View {
        switch target {
        case .requests: AdminAllRequestsView()
        case .inbox:    AdminInboxView()
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SysSectionTitle(title: L10n.t("يحتاج انتباهك", "Needs your attention"),
                            icon: "bell.badge.fill", tint: DS.Color.warning)

            let items = attentionItems
            if isInitialLoading {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        DSSkeleton(height: 112, cornerRadius: DS.Radius.lg)
                    }
                }
                .transition(.opacity)
            } else if items.isEmpty {
                allClearCard
                    .transition(.opacity)
            } else if items.count <= 3 {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(items) { attentionCard($0) }
                }
                .transition(.opacity)
            } else {
                // أكثر من ثلاث: شريط أفقي يمتد لحافة الشاشة
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(items) { attentionCard($0).frame(width: 138) }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -DS.Spacing.lg)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : DS.Anim.smooth, value: isInitialLoading)
    }

    private func attentionCard(_ item: AttentionItem) -> some View {
        NavigationLink {
            attentionDestination(item.target)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 0) {
                    SysGradientIcon(name: item.icon, tint: item.tint, size: 30)
                    Spacer(minLength: 0)
                    SysChevron()
                }
                Text("\(item.count)")
                    .font(DS.Font.plex(22, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.hint)
                        .font(DS.Font.plex(10.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(item.tint.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(item.tint.opacity(0.24), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel("\(item.title): \(item.count)، \(item.hint)")
    }

    /// لا شيء ينتظر — بطاقة هادئة بدل الأرقام الصفرية
    private var allClearCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "checkmark.seal.fill", tint: DS.Color.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("ما فيه شي ينتظر مراجعتك", "Nothing awaiting your review"))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("الطلبات والرسائل كلها متابَعة", "Requests and messages are all handled"))
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(DS.Color.success.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.success.opacity(0.20), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - مجالك

    private func scopeSection(_ guide: RoleGuide) -> some View {
        DSComposerSection(title: L10n.t("مجالك", "Your scope"),
                          icon: guide.icon,
                          tint: domainTint,
                          trailing: guide.title,
                          index: 2) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(showFullScope ? guide.can : Array(guide.can.prefix(2)), id: \.self) { text in
                    scopeLine(text, allowed: true)
                }
                ForEach(showFullScope ? guide.cannot : Array(guide.cannot.prefix(1)), id: \.self) { text in
                    scopeLine(text, allowed: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()

            if guide.can.count > 2 || guide.cannot.count > 1 {
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                        showFullScope.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(showFullScope
                             ? L10n.t("عرض أقل", "Show less")
                             : L10n.t("كل ما تقدر عليه وما لا تقدر", "Everything you can and can't do"))
                            .font(DS.Font.plex(12, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10.5, weight: .bold))
                            .rotationEffect(.degrees(showFullScope ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(domainTint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -6)
            }
        }
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
                              index: 3) {
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

    // MARK: - شبكة الأقسام

    private var tileColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm, alignment: .top),
              count: isLandscape ? 3 : 2)
    }

    private var sectionsGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SysSectionTitle(title: L10n.t("الأقسام", "Sections"),
                            icon: "square.grid.2x2.fill",
                            tint: DS.Color.actionNavy)

            LazyVGrid(columns: tileColumns, spacing: DS.Spacing.sm) {
                AdminTile(
                    title: L10n.t("طلبات المراجعة", "Review Requests"),
                    subtitle: L10n.t("انضمام، أخبار، بلاغات", "Join, news, reports"),
                    icon: "tray.full.fill",
                    color: DS.Color.composerLibrary,
                    badge: totalReviewRequestsCount,
                    detail: requestsDetail
                ) { AdminAllRequestsView() }

                AdminTile(
                    title: L10n.t("الرسائل", "Messages"),
                    subtitle: L10n.t("محادثاتك مع الأعضاء", "Conversations with members"),
                    icon: "bubble.left.and.bubble.right.fill",
                    color: DS.Color.composerDiwaniya,
                    badge: adminRequestVM.unreadContactMessagesCount,
                    detail: messagesDetail
                ) { AdminInboxView() }

                if authVM.canEditMembers {
                    AdminTile(
                        title: L10n.t("إدارة الأعضاء", "Members"),
                        subtitle: L10n.t("الحسابات والسجل والعوائل", "Accounts, registry, families"),
                        icon: "person.2.badge.gearshape",
                        color: DS.Color.composerProject,
                        badge: issueMembersCount + treeIssuesCount,
                        detail: membersDetail
                    ) { AdminMembersManagementView() }
                }

                // سجل النشاط: المالك/المدير/المراقب فقط (جدول الصلاحيات — ليس المشرف)
                if authVM.isAdmin || authVM.currentUser?.role == .monitor {
                    AdminTile(
                        title: L10n.t("سجل النشاط", "Activity Log"),
                        subtitle: L10n.t("كل حركة وتغيير", "Every change"),
                        icon: "clock.arrow.circlepath",
                        color: DS.Color.actionNavy,
                        badge: notificationVM.unreadActivityLogCount,
                        detail: activityDetail
                    ) { AdminActivityLogView() }
                }

                if authVM.isAdmin {
                    AdminTile(
                        title: L10n.t("إحصائيات متقدمة", "Analytics"),
                        subtitle: L10n.t("الأدوار والأعمار والنمو", "Roles, ages, growth"),
                        icon: "chart.bar.xaxis",
                        color: DS.Color.composerProject,
                        detail: analyticsDetail
                    ) { AdminAnalyticsView() }

                    AdminTile(
                        title: L10n.t("تقارير PDF", "PDF Reports"),
                        subtitle: L10n.t("تصدير ملف للطباعة", "Export printable file"),
                        icon: "doc.text.fill",
                        color: DS.Color.composerLibrary
                    ) { AdminReportsView() }
                }

                if authVM.canViewSystemSettings {
                    // «صحة النظام» صارت داخل «إعدادات النظام» — لا تكرار هنا
                    AdminTile(
                        title: L10n.t("إعدادات النظام", "System Settings"),
                        subtitle: L10n.t("الإدارة وصحة النظام والاستخدام", "Management, health & usage"),
                        icon: "lock.shield.fill",
                        color: DS.Color.actionNavy,
                        detail: systemDetail
                    ) {
                        // الفريق والإشعارات وتحديثات التطبيق انتقلت إلى الداخل
                        AdminSecuritySettingsView()
                    }
                }
            }
        }
    }

    // أرقام حيّة صغيرة أسفل البلاطات — «—» لا يظهر أثناء التحميل الأول
    private var requestsDetail: String? {
        guard !isInitialLoading else { return nil }
        return totalReviewRequestsCount > 0
            ? L10n.t("\(totalReviewRequestsCount) بانتظار القرار", "\(totalReviewRequestsCount) awaiting")
            : L10n.t("لا شيء معلّق", "Nothing pending")
    }

    private var messagesDetail: String? {
        guard !isInitialLoading else { return nil }
        let pending = adminRequestVM.pendingContactMessagesCount
        if pending > 0 { return L10n.t("\(pending) بانتظار الرد", "\(pending) awaiting reply") }
        let n = adminRequestVM.contactMessages.count
        return L10n.t("\(n) رسالة", "\(n) messages")
    }

    private var analyticsDetail: String? {
        guard !isInitialLoading else { return nil }
        return L10n.t("\(aliveMembersCount) حي · \(deceasedMembersCount) متوفى",
                      "\(aliveMembersCount) alive · \(deceasedMembersCount) deceased")
    }

    private var membersDetail: String? {
        guard !isInitialLoading else { return nil }
        return L10n.t("\(totalMembersCount) عضو", "\(totalMembersCount) members")
    }

    private var activityDetail: String? {
        let n = notificationVM.unreadActivityLogCount
        guard n > 0 else { return nil }
        return L10n.t("\(n) جديد", "\(n) new")
    }

    private var systemDetail: String? {
        guard !isInitialLoading else { return nil }
        return L10n.t("الفريق \(moderatorCount)", "Team \(moderatorCount)")
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

// MARK: - بلاطة قسم

/// بلاطة قسم إداري — تُستعمل في لوحة الإدارة وفي إعدادات النظام.
/// الكاملة (اللوحة): أيقونة متدرّجة بلون المجال + عنوان + وصف + رقم حيّ + شارة حمراء لما ينتظر.
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
        if let badge, badge > 0 { parts.append(L10n.t("\(badge) بانتظارك", "\(badge) pending")) }
        if let detail, !compact { parts.append(detail) }
        return parts.joined(separator: "، ")
    }

    private var fullLabel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: 0) {
                SysGradientIcon(name: icon, tint: color, size: 40)
                Spacer(minLength: 4)
                if hasBadge { badgeView }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(DS.Font.plex(11.5))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.85)
            }

            HStack(spacing: 4) {
                Text(detail ?? " ")
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                SysChevron()
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(hasBadge ? color.opacity(0.28) : DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
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
