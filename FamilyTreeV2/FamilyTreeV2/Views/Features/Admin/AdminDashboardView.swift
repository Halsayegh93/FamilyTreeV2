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
    @Environment(\.dismiss) var dismiss

    // Admin theme accent (purple #6C5CE7)
    private let adminAccent = DS.Color.gridTree

    // MARK: - Cached badge counts
    private var pendingCount: Int {
        memberVM.allMembers.filter { $0.role == .pending }.count
    }
    private var moderatorCount: Int {
        memberVM.allMembers.filter { $0.role == .owner || $0.role == .admin || $0.role == .monitor || $0.role == .supervisor }.count
    }
    private var totalReviewRequestsCount: Int {
        pendingCount
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
    /// عدد مشاكل الشجرة (يتائم، بدون أسماء، روابط مكسورة، مخفيين)
    private var treeIssuesCount: Int {
        let active = memberVM.allMembers.filter { $0.role != .pending && $0.status != .frozen }
        let activeIds = Set(active.map(\.id))
        let fatherIds = Set(active.compactMap(\.fatherId))
        return memberVM.allMembers.filter { m in
            guard m.status != .frozen else { return false }
            let isOrphan = m.fatherId == nil && !fatherIds.contains(m.id) && m.role != .pending
            let noName = m.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.fullName == "بدون اسم"
            let brokenParent = m.fatherId != nil && !activeIds.contains(m.fatherId!)
            let hidden = m.isHiddenFromTree
            return isOrphan || noName || brokenParent || hidden
        }.count
    }

    /// عدد الأعضاء اللي عندهم أي مشكلة (بدون تكرار)
    private var issueMembersCount: Int {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { member in
                let isNotActivated = member.status == nil || member.status == .pending
                let hasNoPhone = member.phoneNumber == nil || (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noBirth = member.birthDate == nil || (member.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noFather = member.fatherId == nil
                let noGender = member.gender == nil || (member.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return isNotActivated || hasNoPhone || noBirth || noFather || noGender
            }
            .count
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

                            // إحصائيات
                            adminStatsGrid
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)

                            // طلبات المراجعة — الكل (مالك + مدير + مشرف)
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: L10n.t("طلبات تنتظر المراجعة", "Pending Requests"),
                                    icon: "exclamationmark.shield.fill",
                                    iconColor: DS.Color.error
                                )

                                    NavigationLink(destination: AdminAllRequestsView()) {
                                        DSActionRow(
                                            title: L10n.t("طلبات المراجعة", "Review Requests"),
                                            subtitle: L10n.t("انضمام، أخبار، بلاغات، جوال، ديوانيات، وفاة، أبناء، صور، قصص، تعديل", "Join, news, reports, phone, diwaniyas, deceased, children, photos, stories, edits"),
                                            icon: "tray.full.fill",
                                            color: DS.Color.warning,
                                            badge: totalReviewRequestsCount
                                        )
                                    }
                                    // إدارة الأعضاء (موحد: إدارة + صحة الشجرة + سجل ودليل)
                                    if authVM.canModerate {
                                        DSDivider()
                                        NavigationLink(destination: AdminMembersManagementView()) {
                                            DSActionRow(
                                                title: L10n.t("إدارة الأعضاء", "Members Management"),
                                                subtitle: L10n.t("إدارة، صحة الشجرة، سجل ودليل العائلة", "Manage, tree health, registry & directory"),
                                                icon: "person.2.badge.gearshape",
                                                color: DS.Color.warning,
                                                badge: (issueMembersCount + treeIssuesCount) > 0 ? (issueMembersCount + treeIssuesCount) : nil
                                            )
                                        }
                                    }
                                }
                            .padding(.horizontal, DS.Spacing.lg)

                            // النظام — مدير + مالك فقط
                            if authVM.isAdmin {
                                DSCard(padding: 0) {
                                    DSSectionHeader(
                                        title: L10n.t("النظام", "System"),
                                        icon: "gearshape.2.fill",
                                        iconColor: DS.Color.primary
                                    )

                                        NavigationLink(destination: AdminRegisterMemberView()) {
                                            DSActionRow(title: L10n.t("تسجيل عضو جديد", "Register New Member"), subtitle: L10n.t("إضافة عضو جديد مباشرة للشجرة", "Add a new member directly to the tree"), icon: "person.badge.plus", color: DS.Color.primary)
                                        }
                                        DSDivider()
                                        NavigationLink(destination: AdminNotificationsView()) {
                                            DSActionRow(title: L10n.t("إرسال إشعارات", "Send Notifications"), subtitle: L10n.t("إرسال إشعار عام أو مخصص", "Send a general or targeted notification"), icon: "bell.badge.fill", color: DS.Color.warning)
                                        }
                                        DSDivider()
                                        NavigationLink(destination: AdminReportsView()) {
                                            DSActionRow(title: L10n.t("تقارير PDF", "PDF Reports"), subtitle: L10n.t("تقرير الأرقام والأعمار للأعضاء", "Member numbers and ages report"), icon: "doc.text.fill", color: DS.Color.info)
                                        }
                                        // الأمان والإعدادات — المالك فقط
                                        if authVM.isOwner {
                                            DSDivider()
                                            NavigationLink(destination: AdminSecuritySettingsView()) {
                                                DSActionRow(
                                                    title: L10n.t("الأمان والإعدادات", "Security & Settings"),
                                                    subtitle: L10n.t("أجهزة، أرقام محظورة، إعدادات التطبيق", "Devices, banned numbers, app settings"),
                                                    icon: "lock.shield.fill",
                                                    color: DS.Color.gridContact,
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
                                        title: L10n.t("المدراء والمشرفين والمراقبين", "Admins, Monitors & Supervisors"),
                                        icon: "shield.fill",
                                        iconColor: DS.Color.neonPurple
                                    )

                                        NavigationLink(destination: AdminModeratorsView()) {
                                            DSActionRow(
                                                title: L10n.t("المدراء والمشرفين والمراقبين", "Admins, Monitors & Supervisors"),
                                                subtitle: L10n.t("عرض قائمة المدراء والمراقبين والمشرفين", "View admins, monitors, and supervisors list"),
                                                icon: "shield.fill",
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
        }
    }




    // MARK: - إحصائيات (Colorful Stat Cards)
    private var adminStatsGrid: some View {
        VStack(spacing: DS.Spacing.sm) {
            // السطر الأول: الأعضاء + الأحياء + المتوفين
            HStack(spacing: DS.Spacing.md) {
                adminColorfulStatCard(
                    title: L10n.t("الأعضاء", "Members"),
                    value: "\(memberVM.allMembers.filter { $0.role != .pending }.count)",
                    icon: "person.2.fill",
                    color: DS.Color.primary
                )

                adminColorfulStatCard(
                    title: L10n.t("الأحياء", "Alive"),
                    value: "\(memberVM.allMembers.filter { $0.role != .pending && $0.isDeceased != true }.count)",
                    icon: "heart.fill",
                    color: DS.Color.success
                )

                adminColorfulStatCard(
                    title: L10n.t("المتوفين", "Deceased"),
                    value: "\(memberVM.allMembers.filter { $0.isDeceased == true }.count)",
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
                    color: DS.Color.accent
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

