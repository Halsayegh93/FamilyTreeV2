import SwiftUI

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
}

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
    @State private var appeared = false
    @State private var pendingCount: Int = 0
    @State private var moderatorCount: Int = 0
    @State private var totalReviewRequestsCount: Int = 0
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
    @Environment(\.dismiss) var dismiss
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — إحصائيات بصف واحد وبطاقات على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }

    // Admin theme accent (purple #6C5CE7)
    private let adminAccent = DS.Color.gridTree

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
            if moderatorRoles.contains(m.role) { moderator += 1 }

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
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM
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

                // Decorative background circles
                EmptyView()

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
                        VStack(spacing: 0) {
                        // مسافة بين الهيدر وأول بطاقة — نفس بقية الواجهات
                        Color.clear.frame(height: DS.Spacing.md)

                        VStack(spacing: DS.Spacing.md) {
                            // تحذير التوافق
                            if !authVM.notificationsFeatureAvailable || !authVM.newsApprovalFeatureAvailable {
                                schemaWarningCard
                                    .padding(.horizontal, DS.Spacing.lg)
                            }

                            // إحصائيات — مدير + مراقب + مالك (المشرف لا)
                            if authVM.isAdmin || authVM.currentUser?.role == .monitor {
                                adminStatsGrid
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 20)
                            }

                            // شبكة بلاطات — نفس لغة الرئيسية: كل قسم بلاطة متساوية
                            // بدل بطاقات مكدّسة متفاوتة الطول تبدو عشوائية.
                            adminBentoGrid
                                .padding(.horizontal, DS.Spacing.lg)

                            Spacer(minLength: DS.Spacing.xxxl)
                        }
                        .onAppear {
                            guard !appeared else { return }
                            withAnimation(DS.Anim.smooth.delay(0.15)) { appeared = true }
                        }
                    }
                    .refreshable { await loadAllAdminData(force: true) }
                }
            }
            .navigationDestination(for: AdminReviewDestination.self) { destination in
                switch destination {
                case .treeEditRequests: AdminTreeEditRequestsView()
                case .allRequests:      AdminAllRequestsView()
                }
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
        }
        recalculateBadges()
        withAnimation(DS.Anim.smooth) { isInitialLoading = false }
    }


    private var adminStatsGrid: some View {
        Group {
            if isInitialLoading {
                adminStatsSkeleton
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    // ═══ يحتاج إجراءك — الأولوية أولاً ═══
                    if actionableTotal > 0 {
                        HStack(spacing: DS.Spacing.sm) {
                            actionStat(
                                title: L10n.t("طلبات", "Requests"),
                                value: totalReviewRequestsCount,
                                icon: "tray.full.fill",
                                color: DS.Color.warning
                            )
                            actionStat(
                                title: L10n.t("رسائل", "Messages"),
                                value: adminRequestVM.unreadContactMessagesCount,
                                icon: "bubble.left.fill",
                                color: DS.Color.info
                            )
                            actionStat(
                                title: L10n.t("بانتظار", "Pending"),
                                value: pendingCount,
                                icon: "clock.fill",
                                color: DS.Color.error
                            )
                        }
                    } else {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(DS.Font.scaled(14, weight: .semibold))
                                .foregroundColor(DS.Color.success)
                            Text(L10n.t("ما فيه شي ينتظر مراجعتك", "Nothing awaiting your review"))
                                .font(DS.Font.scaled(12, weight: .medium))
                                .foregroundColor(DS.Color.textSecondary)
                            Spacer()
                        }
                        .padding(DS.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .background(DS.Color.success.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }

                    // ═══ أفراد العائلة — جدول واحد: صفّ لكل جنس، عمود لكل حالة ═══
                    // شريطان منفصلان كانا يجعلان المقارنة بينهما عمليةً ذهنية؛
                    // الجدول يجعلها نظرة واحدة.
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("أفراد العائلة", "Family members"))
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)

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
                    }
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
                    )
                }
                .padding(.horizontal, DS.Spacing.lg)
                .transition(.opacity)
            }
        }
    }

    // MARK: - شبكة الأقسام (Bento)

    /// بلاطة قسم — أيقونة في قرص ملوّن، عنوان، وشارة عدد اختيارية

    private var adminBentoGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: DS.Spacing.sm),
                count: 3
            ),
            spacing: DS.Spacing.sm
        ) {
            AdminTile(
                title: L10n.t("طلبات المراجعة", "Review Requests"),
                subtitle: L10n.t("انضمام، أخبار، بلاغات", "Join, news, reports"),
                icon: "tray.full.fill",
                color: DS.Color.warning,
                badge: totalReviewRequestsCount
            ) { AdminAllRequestsView() }

            AdminTile(
                title: L10n.t("الرسائل", "Messages"),
                subtitle: L10n.t("محادثاتك مع الأعضاء", "Conversations with members"),
                icon: "bubble.left.and.bubble.right.fill",
                color: DS.Color.info,
                badge: adminRequestVM.unreadContactMessagesCount
            ) { AdminInboxView() }

            if authVM.canEditMembers {
                AdminTile(
                    title: L10n.t("إدارة الأعضاء", "Members"),
                    subtitle: L10n.t("الحسابات والسجل والعوائل", "Accounts, registry, families"),
                    icon: "person.2.badge.gearshape",
                    color: DS.Color.primary,
                    badge: issueMembersCount + treeIssuesCount
                ) { AdminMembersManagementView() }
            }

            AdminTile(
                title: L10n.t("سجل النشاط", "Activity Log"),
                subtitle: L10n.t("كل حركة وتغيير", "Every change"),
                icon: "clock.arrow.circlepath",
                color: DS.Color.accent,
                badge: notificationVM.unreadActivityLogCount
            ) { AdminActivityLogView() }

            if authVM.isAdmin {
                AdminTile(
                    title: L10n.t("إحصائيات متقدمة", "Analytics"),
                    subtitle: L10n.t("الأدوار والأعمار والنمو", "Roles, ages, growth"),
                    icon: "chart.bar.xaxis",
                    color: DS.Color.accent
                ) { AdminAnalyticsView() }

                AdminTile(
                    title: L10n.t("تقارير PDF", "PDF Reports"),
                    subtitle: L10n.t("تصدير ملف للطباعة", "Export printable file"),
                    icon: "doc.text.fill",
                    color: DS.Color.info
                ) { AdminReportsView() }
            }

            if authVM.canViewSystemSettings {
                AdminTile(
                    title: L10n.t("إعدادات النظام", "System Settings"),
                    subtitle: L10n.t("الأمان وصحة النظام", "Security & health"),
                    icon: "lock.shield.fill",
                    color: DS.Color.textSecondary
                ) {
                    // الفريق والإشعارات وتحديثات التطبيق انتقلت إلى الداخل
                    AdminSecuritySettingsView()
                }
            }
        }
    }

    /// هيكل تحميل مطابق للتخطيط الجديد: صف أولويات + شريط أرقام مرجعية
    private var adminStatsSkeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    DSSkeleton(height: 64, cornerRadius: DS.Radius.lg)
                }
            }
            DSSkeleton(height: 46, cornerRadius: DS.Radius.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .transition(.opacity)
    }

    /// مجموع ما ينتظر إجراءً — يقرّر إظهار صف الأولويات أو رسالة «كل شي تمام»
    private var actionableTotal: Int {
        totalReviewRequestsCount + adminRequestVM.unreadContactMessagesCount + pendingCount
    }

    /// بطاقة أولوية — رقم بارز بلون التنبيه
    private func actionStat(title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("\(value)")
                .font(DS.Font.plex(22, weight: .bold))
                .foregroundColor(value > 0 ? color : DS.Color.textTertiary)
                .contentTransition(.numericText())
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(value > 0 ? 0.10 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(color.opacity(value > 0 ? 0.20 : 0.08), lineWidth: 1)
        )
    }

    /// رقم مرجعي — بلا لون ولا بطاقة، مجرّد معلومة
    /// عنوان عمود في جدول الأفراد
    private func censusHeader(_ t: String) -> some View {
        Text(t)
            .font(DS.Font.scaled(9.5, weight: .semibold))
            .foregroundColor(DS.Color.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)   // «المتوفون» لا يلتفّ ولا يزيح العمود
            .frame(maxWidth: .infinity)
    }

    /// اسم الصفّ — نقطة ملوّنة تميّز الجنس بلا كلمة زائدة
    private func censusLabel(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(t)
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 58, alignment: .leading)
    }

    /// رقم في الجدول — أرقام جدولية فتتراصّ الخانات عمودياً
    private func censusValue(_ v: Int) -> some View {
        Text("\(v)")
            .font(DS.Font.plex(15, weight: .bold))
            .monospacedDigit()
            .foregroundColor(DS.Color.textPrimary)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
    }

    private func refStat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .contentTransition(.numericText())
            Text(title)
                .font(DS.Font.scaled(11, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var refDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.15))
            .frame(width: 1, height: 26)
    }

    // MARK: - تحذير التوافق (Prominent Warning Card)
    private var schemaWarningCard: some View {
        HStack(spacing: 0) {
            // Prominent yellow/orange left accent bar
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(
                    LinearGradient(
                        colors: [DS.Color.warning, DS.Color.error],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: DS.Spacing.xs)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Font.scaled(15, weight: .bold))
                        .foregroundColor(DS.Color.error)
                    Text(L10n.t("تنبيه توافق قاعدة البيانات", "Database Compatibility Warning"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                }

                if !authVM.notificationsFeatureAvailable {
                    Text("• \(L10n.t("جدول notifications غير موجود، الإشعارات معطلة.", "Notifications table missing, feature disabled."))")
                        .font(DS.Font.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }
                if !authVM.newsApprovalFeatureAvailable {
                    Text("• \(L10n.t("عمود news.approval_status غير موجود، موافقات الأخبار معطلة.", "News approval_status column missing, approvals disabled."))")
                        .font(DS.Font.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .background(
            DS.Color.warning.opacity(0.08)
        )
        .cornerRadius(DS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.warning.opacity(0.2), lineWidth: 1)
        )
        .dsCardShadow()
    }
}

/// بلاطة قسم إداري — تُستعمل في لوحة الإدارة وفي إعدادات النظام.
/// كانت خاصّة داخل اللوحة، فرُفعت لمستوى الملف بدل نسخها مرة ثانية.
struct AdminTile<Destination: View>: View {
    let title: String
    let subtitle: String  // يُستخدم كوصف وصولية فقط في العرض المضغوط
    let icon: String
    let color: Color
    var badge: Int? = nil
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: DS.Spacing.sm) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(color.opacity(0.14))
                        Image(systemName: icon)
                            .font(DS.Font.scaled(17, weight: .semibold))
                            .foregroundColor(color)
                    }
                    .frame(width: 44, height: 44)

                    if let badge, badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            // الشارة حمراء دائماً — لون المربّع كان يجعل
                            // بعضها باهتاً فلا يُقرأ كتنبيه يحتاج إجراءً.
                            .background(Capsule().fill(DS.Color.error))
                            .offset(x: 8, y: -3)
                    }
                }

                Text(title)
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DS.Spacing.md)
            .padding(.horizontal, DS.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(color.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
