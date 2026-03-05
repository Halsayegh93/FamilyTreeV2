import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var isSendingWeeklyDigest = false
    @State private var edgeFunctionResult: String?
    @State private var showEdgeFunctionAlert = false
    @Environment(\.dismiss) var dismiss

    // Admin theme accent (purple #6C5CE7)
    private let adminAccent = DS.Color.gridTree

    // MARK: - Cached badge counts
    private var pendingCount: Int {
        memberVM.allMembers.filter { $0.role == .pending }.count
    }
    private var inactiveCount: Int {
        memberVM.allMembers.filter { $0.role != .pending && ($0.status == nil || $0.status == .pending) && $0.isDeceased != true }.count
    }
    private var moderatorCount: Int {
        memberVM.allMembers.filter { $0.role == .admin || $0.role == .supervisor }.count
    }
    private var incompleteMembersCount: Int {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { member in
                let noPhone = member.phoneNumber == nil || (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noBirth = member.birthDate == nil || (member.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noFather = member.fatherId == nil
                let noGender = member.gender == nil || (member.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return noPhone || noBirth || noFather || noGender
            }
            .count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                // Decorative background circles
                decorativeBackground

                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الادارة", "Admin Dashboard"),
                        icon: "shield.lefthalf.filled",
                        backgroundGradient: DS.Color.gradientAccent
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {

                        VStack(spacing: DS.Spacing.xxl) {

                            // تحذير التوافق
                            if !authVM.notificationsFeatureAvailable || !authVM.newsApprovalFeatureAvailable {
                                schemaWarningCard
                                    .padding(.horizontal, DS.Spacing.lg)
                            }

                            // إحصائيات
                            adminStatsGrid
                                .padding(.top, DS.Spacing.md)

                            // طلبات المراجعة
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: L10n.t("طلبات تنتظر المراجعة", "Pending Requests"),
                                    icon: "exclamationmark.shield.fill",
                                    iconColor: DS.Color.error
                                )

                                    NavigationLink(destination: AdminPendingRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات انضمام جديدة", "New Join Requests"), subtitle: L10n.t("مراجعة هويات المنضمين الجدد", "Review new member identities"), icon: "person.badge.plus", color: DS.Color.info, badge: pendingCount)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminActivateAccountsView()) {
                                        DSActionRow(
                                            title: L10n.t("حسابات غير مفعلة", "Inactive Accounts"),
                                            subtitle: L10n.t("تفعيل حسابات الأعضاء المعلقة", "Activate pending member accounts"),
                                            icon: "person.badge.clock",
                                            color: DS.Color.warning,
                                            badge: inactiveCount
                                        )
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminNewsRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات نشر الأخبار", "News Publish Requests"), subtitle: L10n.t("مراجعة أخبار الأعضاء قبل النشر", "Review member news before publishing"), icon: "newspaper.fill", color: DS.Color.warning, badge: newsVM.pendingNewsRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminNewsReportsView()) {
                                        DSActionRow(title: L10n.t("بلاغات الأخبار", "News Reports"), subtitle: L10n.t("مراجعة بلاغات الأعضاء على الأخبار", "Review member reports on news"), icon: "exclamationmark.bubble.fill", color: DS.Color.error, badge: adminRequestVM.newsReportRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminPhoneRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات تغيير الجوال", "Phone Change Requests"), subtitle: L10n.t("مراجعة واعتماد تحديثات الأرقام", "Review and approve phone updates"), icon: "phone.badge.checkmark", color: DS.Color.success, badge: adminRequestVM.phoneChangeRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminDiwaniyaRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات الديوانيات", "Diwaniya Requests"), subtitle: L10n.t("مراجعة واعتماد ديوانيات الأعضاء", "Review and approve member diwaniyas"), icon: "tent.fill", color: DS.Color.gridDiwaniya, badge: diwaniyaVM.pendingDiwaniyas.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminDeceasedRequestsView()) {
                                        DSActionRow(title: L10n.t("تأكيد حالات الوفاة", "Confirm Deceased"), subtitle: L10n.t("تحديثات حالة أعضاء الشجرة", "Update family tree member status"), icon: "bolt.heart.fill", color: DS.Color.error, badge: adminRequestVM.deceasedRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminChildAddRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات إضافة الأبناء", "Child Add Requests"), subtitle: L10n.t("مراجعة طلبات إضافة أبناء جدد", "Review new child addition requests"), icon: "person.badge.plus", color: DS.Color.success, badge: adminRequestVM.childAddRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminIncompleteMembersView()) {
                                        DSActionRow(
                                            title: L10n.t("بيانات أعضاء ناقصة", "Incomplete Member Data"),
                                            subtitle: L10n.t("أعضاء ينقصهم جوال أو تاريخ ميلاد أو أب أو جنس", "Members missing phone, birth date, father, or gender"),
                                            icon: "exclamationmark.triangle.fill",
                                            color: DS.Color.warning,
                                            badge: incompleteMembersCount
                                        )
                                    }
                                }
                            .padding(.horizontal, DS.Spacing.lg)

                            // النظام والشجرة
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: L10n.t("النظام والشجرة", "System & Tree"),
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
                                    NavigationLink(destination: AdminMembersListView()) {
                                        DSActionRow(title: L10n.t("سجل أعضاء الشجرة", "Member Registry"), subtitle: L10n.t("إدارة الرتب، الصلاحيات، والحذف", "Manage roles, permissions, deletion"), icon: "person.3.sequence.fill", color: adminAccent)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminReportsView()) {
                                        DSActionRow(title: L10n.t("تقارير PDF", "PDF Reports"), subtitle: L10n.t("تقرير الأرقام والأعمار للأعضاء", "Member numbers and ages report"), icon: "doc.text.fill", color: DS.Color.info)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: FamilyDirectoryView()) {
                                        DSActionRow(title: L10n.t("دليل أفراد العائلة", "Family Directory"), subtitle: L10n.t("بحث وتصفية بيانات جميع الأعضاء", "Search and filter all member data"), icon: "person.text.rectangle", color: DS.Color.success)
                                    }
                                    DSDivider()
                                    Button {
                                        isSendingWeeklyDigest = true
                                        Task {
                                            let result = await authVM.triggerWeeklyDigest()
                                            edgeFunctionResult = result.message
                                            isSendingWeeklyDigest = false
                                            showEdgeFunctionAlert = true
                                        }
                                    } label: {
                                        DSActionRow(
                                            title: L10n.t("الملخص الأسبوعي", "Weekly Digest"),
                                            subtitle: L10n.t("إرسال ملخص الأسبوع لجميع الأعضاء", "Send weekly summary to all members"),
                                            icon: "doc.text.magnifyingglass",
                                            color: DS.Color.info
                                        )
                                        .overlay(alignment: .leading) {
                                            if isSendingWeeklyDigest {
                                                ProgressView()
                                                    .padding(.leading, DS.Spacing.lg)
                                            }
                                        }
                                    }
                                    .disabled(isSendingWeeklyDigest)
                                }
                            .padding(.horizontal, DS.Spacing.lg)

                            // المدراء والمشرفين
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: L10n.t("المدراء والمشرفين", "Admins & Supervisors"),
                                    icon: "crown.fill",
                                    iconColor: DS.Color.neonPurple
                                )

                                    NavigationLink(destination: AdminModeratorsView()) {
                                        DSActionRow(
                                            title: L10n.t("المدراء والمشرفين", "Admins & Supervisors"),
                                            subtitle: L10n.t("عرض قائمة المدراء والمشرفين", "View admins and supervisors list"),
                                            icon: "crown.fill",
                                            color: DS.Color.neonPurple,
                                            badge: moderatorCount
                                        )
                                    }
                                }
                            .padding(.horizontal, DS.Spacing.lg)

                            Spacer(minLength: DS.Spacing.xxxl)
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        }
        .alert(L10n.t("نتيجة العملية", "Result"), isPresented: $showEdgeFunctionAlert) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(edgeFunctionResult ?? "")
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            // تحميل البيانات بالتوازي لتسريع الأداء
            async let members: () = memberVM.fetchAllMembers()
            async let deceased: () = adminRequestVM.fetchDeceasedRequests()
            async let pendingNews: () = newsVM.fetchPendingNewsRequests()
            async let newsReports: () = adminRequestVM.fetchNewsReportRequests()
            async let phoneChanges: () = adminRequestVM.fetchPhoneChangeRequests()
            async let childAdds: () = adminRequestVM.fetchChildAddRequests()
            async let diwaniyas: () = diwaniyaVM.fetchPendingDiwaniyas()
            _ = await (members, deceased, pendingNews, newsReports, phoneChanges, childAdds, diwaniyas)
        }
    }


    // MARK: - Decorative Background
    private var decorativeBackground: some View {
        DSDecorativeBackground()
    }



    // MARK: - إحصائيات (Colorful Stat Cards)
    private var adminStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {
            // Tree Members stat card
            adminColorfulStatCard(
                title: L10n.t("الأعضاء", "Members"),
                value: "\(memberVM.allMembers.count)",
                icon: "person.2.fill",
                color: DS.Color.info
            )

            // Pending Members
            adminColorfulStatCard(
                title: L10n.t("انتظار", "Pending"),
                value: "\(pendingCount)",
                icon: "clock.fill",
                color: DS.Color.warning
            )

            // News Requests
            adminColorfulStatCard(
                title: L10n.t("الأخبار", "News"),
                value: "\(newsVM.pendingNewsRequests.count)",
                icon: "newspaper.fill",
                color: DS.Color.accent
            )
            
            // Deceased Requests
            adminColorfulStatCard(
                title: L10n.t("الوفيات", "Deceased"),
                value: "\(adminRequestVM.deceasedRequests.count)",
                icon: "bolt.heart.fill",
                color: DS.Color.error
            )
            
            // Phone Updates
            adminColorfulStatCard(
                title: L10n.t("الجوال", "Phone"),
                value: "\(adminRequestVM.phoneChangeRequests.count)",
                icon: "phone.badge.checkmark",
                color: DS.Color.success
            )

            // Reports
            adminColorfulStatCard(
                title: L10n.t("بلاغات", "Reports"),
                value: "\(adminRequestVM.newsReportRequests.count)",
                icon: "exclamationmark.bubble.fill",
                color: DS.Color.error
            )

            // Incomplete Members
            adminColorfulStatCard(
                title: L10n.t("ناقص", "Incomplete"),
                value: "\(incompleteMembersCount)",
                icon: "exclamationmark.triangle.fill",
                color: DS.Color.warning
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
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
        .padding(.vertical, DS.Spacing.sm)
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

