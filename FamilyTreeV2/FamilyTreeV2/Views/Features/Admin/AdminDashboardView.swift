import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var storyVM: StoryViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @Binding var selectedTab: Int
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
    @Environment(\.dismiss) var dismiss

    // Admin theme accent (purple #6C5CE7)
    private let adminAccent = DS.Color.gridTree

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

        pendingCount = pending
        moderatorCount = moderator
        totalMembersCount = total
        aliveMembersCount = alive
        deceasedMembersCount = deceased
        issueMembersCount = issues
        treeIssuesCount = treeIssues
        totalReviewRequestsCount = pending
            + newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + adminRequestVM.treeEditRequests.count
            + adminRequestVM.nameChangeRequests.count
            + memberVM.pendingGalleryPhotos.count
            + storyVM.pendingStories.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                // Decorative background circles
                EmptyView()

                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الادارة", "Admin Dashboard"),
                        icon: "shield.lefthalf.filled",
                        backgroundGradient: DS.Color.gradientPrimary,
                        hasDropShadow: false
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {

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

                            // طلبات المراجعة — الكل (مالك + مدير + مشرف)
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: L10n.t("طلبات تنتظر المراجعة", "Pending Requests"),
                                    icon: "exclamationmark.shield.fill",
                                    iconColor: DS.Color.warning
                                )

                                    NavigationLink(destination: AdminAllRequestsView()) {
                                        DSActionRow(
                                            title: L10n.t("طلبات المراجعة", "Review Requests"),
                                            subtitle: L10n.t("انضمام، أخبار، بلاغات والمزيد", "Join, news, reports & more"),
                                            icon: "tray.full.fill",
                                            color: DS.Color.warning,
                                            badge: totalReviewRequestsCount
                                        )
                                    }
                                    // إدارة الأعضاء — مدير + مراقب + مالك (المشرف لا)
                                    if authVM.canEditMembers {
                                        DSDivider()
                                        NavigationLink(destination: AdminMembersManagementView()) {
                                            DSActionRow(
                                                title: L10n.t("إدارة الأعضاء", "Members Management"),
                                                subtitle: L10n.t("إدارة الشجرة والسجلات", "Tree management & records"),
                                                icon: "person.2.badge.gearshape",
                                                color: DS.Color.warning,
                                                badge: (issueMembersCount + treeIssuesCount) > 0 ? (issueMembersCount + treeIssuesCount) : nil
                                            )
                                        }
                                    }
                                }
                            .padding(.horizontal, DS.Spacing.lg)

                            // تسجيل عضو جديد — مدير + مشرف + مالك
                            if authVM.canModerate {
                                DSCard(padding: 0) {
                                    DSSectionHeader(
                                        title: L10n.t("النظام", "System"),
                                        icon: "gearshape.2.fill",
                                        iconColor: DS.Color.primary
                                    )

                                        NavigationLink(destination: AdminRegisterMemberView()) {
                                            DSActionRow(title: L10n.t("تسجيل عضو جديد", "Register New Member"), subtitle: L10n.t("إضافة عضو جديد للشجرة", "Add new member to tree"), icon: "person.badge.plus", color: DS.Color.primary)
                                        }

                                        // إشعارات وتقارير — مدير + مالك فقط
                                        if authVM.isAdmin {
                                            DSDivider()
                                            NavigationLink(destination: AdminNotificationsView()) {
                                                DSActionRow(title: L10n.t("إرسال إشعارات", "Send Notifications"), subtitle: L10n.t("إرسال إشعار للأعضاء", "Send notification"), icon: "bell.badge.fill", color: DS.Color.primary)
                                            }
                                            DSDivider()
                                            NavigationLink(destination: AdminReportsView()) {
                                                DSActionRow(title: L10n.t("تقارير PDF", "PDF Reports"), subtitle: L10n.t("تقرير إحصائيات الأعضاء", "Member stats report"), icon: "doc.text.fill", color: DS.Color.primary)
                                            }
                                        }

                                        // الأمان والإعدادات — المالك فقط
                                        if authVM.isOwner {
                                            DSDivider()
                                            NavigationLink(destination: AdminSecuritySettingsView()) {
                                                DSActionRow(
                                                    title: L10n.t("الأمان والإعدادات", "Security & Settings"),
                                                    subtitle: L10n.t("الأجهزة والأمان والإعدادات", "Devices & security"),
                                                    icon: "lock.shield.fill",
                                                    color: DS.Color.primary,
                                                    badge: authVM.bannedPhones.count > 0 ? authVM.bannedPhones.count : nil
                                                )
                                            }
                                        }
                                    }
                                .padding(.horizontal, DS.Spacing.lg)
                            }

                            // المدراء والمشرفين — المدير + المالك
                            if authVM.isAdmin {
                                DSCard(padding: 0) {
                                    DSSectionHeader(
                                        title: L10n.t("فريق الإدارة", "Admin Team"),
                                        icon: "person.3.fill",
                                        iconColor: DS.Color.neonPurple
                                    )

                                        NavigationLink(destination: AdminModeratorsView()) {
                                            DSActionRow(
                                                title: L10n.t("فريق الإدارة", "Admin Team"),
                                                subtitle: L10n.t("أعضاء الفريق والصلاحيات", "Team & permissions"),
                                                icon: "person.3.fill",
                                                color: DS.Color.neonPurple,
                                                badge: moderatorCount
                                            )
                                        }
                                    }
                                .padding(.horizontal, DS.Spacing.lg)
                            }

                            Spacer(minLength: DS.Spacing.xxxl)
                        }
                        .onAppear {
                            guard !appeared else { return }
                            withAnimation(DS.Anim.smooth.delay(0.15)) { appeared = true }
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            diwaniyaVM.canModerate = authVM.canModerate
            diwaniyaVM.authVM = authVM
            // تحميل كل البيانات بالتوازي — بدون تأخير
            await memberVM.fetchAllMembers()

            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in await adminRequestVM.fetchDeceasedRequests() }
                group.addTask { @MainActor in await newsVM.fetchPendingNewsRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchChildAddRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNewsReportRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhoneChangeRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhotoSuggestionRequests() }
                group.addTask { @MainActor in await diwaniyaVM.fetchPendingDiwaniyas() }
                group.addTask { @MainActor in await adminRequestVM.fetchTreeEditRequests() }
                group.addTask { @MainActor in await memberVM.fetchPendingGalleryPhotos() }
                group.addTask { @MainActor in await adminRequestVM.fetchNameChangeRequests() }
                group.addTask { @MainActor in await authVM.fetchBannedPhones() }
            }
            recalculateBadges()
        }
        .onChange(of: memberVM.membersVersion) { _, _ in recalculateBadges() }
    }


    // MARK: - إحصائيات (Colorful Stat Cards)
    private var adminStatsGrid: some View {
        VStack(spacing: DS.Spacing.sm) {
            // السطر الأول: الأعضاء + الأحياء + المتوفين
            HStack(spacing: DS.Spacing.md) {
                adminColorfulStatCard(
                    title: L10n.t("الأعضاء", "Members"),
                    value: "\(totalMembersCount)",
                    icon: "person.2.fill",
                    color: DS.Color.primary
                )

                adminColorfulStatCard(
                    title: L10n.t("الأحياء", "Alive"),
                    value: "\(aliveMembersCount)",
                    icon: "heart.fill",
                    color: DS.Color.success
                )

                adminColorfulStatCard(
                    title: L10n.t("المتوفين", "Deceased"),
                    value: "\(deceasedMembersCount)",
                    icon: "heart.slash.fill",
                    color: DS.Color.deceased
                )
            }

            // السطر الثاني: انتظار + طلبات
            HStack(spacing: DS.Spacing.md) {
                adminColorfulStatCard(
                    title: L10n.t("انتظار", "Pending"),
                    value: "\(pendingCount)",
                    icon: "clock.fill",
                    color: DS.Color.secondary
                )

                adminColorfulStatCard(
                    title: L10n.t("طلبات", "Requests"),
                    value: "\(totalReviewRequestsCount)",
                    icon: "tray.full.fill",
                    color: DS.Color.warning
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
    }

    /// Colorful stat card with gradient top border
    private func adminColorfulStatCard(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 32, height: 32)
                Image(systemName: icon).font(DS.Font.scaled(14, weight: .bold)).foregroundColor(color)
            }

            Text(value)
                .font(DS.Font.headline)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Text(title)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.textTertiary.opacity(DS.Opacity.divider), lineWidth: 0.5)
        )
        .dsCardShadow()
    }

    // MARK: - تحذير التوافق (Prominent Warning Card)
    private var schemaWarningCard: some View {
        HStack(spacing: 0) {
            // Prominent yellow/orange left accent bar
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [DS.Color.warning, DS.Color.error],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5)

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

