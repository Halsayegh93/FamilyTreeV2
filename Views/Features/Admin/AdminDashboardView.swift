import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @Environment(\.dismiss) var dismiss

    // Admin theme accent (purple #6C5CE7)
    private let adminAccent = DS.Color.gridTree

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
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                adminSectionHeader(
                                    title: L10n.t("طلبات تنتظر المراجعة", "Pending Requests"),
                                    icon: "exclamationmark.shield.fill"
                                )

                                DSCard {
                                    NavigationLink(destination: AdminPendingRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات انضمام جديدة", "New Join Requests"), subtitle: L10n.t("مراجعة هويات المنضمين الجدد", "Review new member identities"), icon: "person.badge.plus", color: DS.Color.info, badge: authVM.allMembers.filter { $0.role == .pending }.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminNewsRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات نشر الأخبار", "News Publish Requests"), subtitle: L10n.t("مراجعة أخبار الأعضاء قبل النشر", "Review member news before publishing"), icon: "newspaper.fill", color: DS.Color.warning, badge: authVM.pendingNewsRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminNewsReportsView()) {
                                        DSActionRow(title: L10n.t("بلاغات الأخبار", "News Reports"), subtitle: L10n.t("مراجعة بلاغات الأعضاء على الأخبار", "Review member reports on news"), icon: "exclamationmark.bubble.fill", color: DS.Color.error, badge: authVM.newsReportRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminPhoneRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات تغيير الجوال", "Phone Change Requests"), subtitle: L10n.t("مراجعة واعتماد تحديثات الأرقام", "Review and approve phone updates"), icon: "phone.badge.checkmark", color: DS.Color.success, badge: authVM.phoneChangeRequests.count)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminDiwaniyaRequestsView()) {
                                        DSActionRow(title: L10n.t("طلبات الديوانيات", "Diwaniya Requests"), subtitle: L10n.t("مراجعة واعتماد ديوانيات الأعضاء", "Review and approve member diwaniyas"), icon: "tent.fill", color: DS.Color.gridDiwaniya)
                                    }
                                    DSDivider()
                                    NavigationLink(destination: AdminDeceasedRequestsView()) {
                                        DSActionRow(title: L10n.t("تأكيد حالات الوفاة", "Confirm Deceased"), subtitle: L10n.t("تحديثات حالة أعضاء الشجرة", "Update family tree member status"), icon: "bolt.heart.fill", color: DS.Color.error, badge: authVM.deceasedRequests.count)
                                    }
                                }
                                .dsCardShadow()
                                .padding(.horizontal, DS.Spacing.lg)
                            }

                            // النظام والشجرة
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                adminSectionHeader(
                                    title: L10n.t("النظام والشجرة", "System & Tree"),
                                    icon: "gearshape.2.fill"
                                )

                                DSCard {
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
                                }
                                .dsCardShadow()
                                .padding(.horizontal, DS.Spacing.lg)
                            }

                            Spacer(minLength: DS.Spacing.xxxl)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            Task {
                await authVM.fetchAllMembers()
                await authVM.fetchDeceasedRequests()
                await authVM.fetchPendingNewsRequests()
                await authVM.fetchNewsReportRequests()
                await authVM.fetchPhoneChangeRequests()
            }
        }
    }


    // MARK: - Decorative Background
    private var decorativeBackground: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [adminAccent.opacity(0.08), adminAccent.opacity(0.01)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 160
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(x: geo.size.width * 0.6, y: geo.size.height * 0.15)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DS.Color.info.opacity(0.07), DS.Color.info.opacity(0.01)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )
                    .frame(width: 220, height: 220)
                    .offset(x: -geo.size.width * 0.3, y: geo.size.height * 0.5)

                Circle()
                    .fill(DS.Color.accent.opacity(0.05))
                    .frame(width: 160, height: 160)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.75)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Bold Section Header
    private func adminSectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(adminAccent)

            Text(title)
                .font(DS.Font.headline)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Spacer()

            // Decorative accent line
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [adminAccent.opacity(0.5), adminAccent.opacity(0.0)],
                        startPoint: L10n.isArabic ? .trailing : .leading,
                        endPoint: .leading
                    )
                )
                .frame(height: 2)
                .frame(maxWidth: 60)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - إحصائيات (Colorful Stat Cards)
    private var adminStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {
            // Tree Members stat card
            adminColorfulStatCard(
                title: L10n.t("الأعضاء", "Members"),
                value: "\(authVM.allMembers.count)",
                icon: "person.2.fill",
                color: DS.Color.info
            )

            // Pending Members
            adminColorfulStatCard(
                title: L10n.t("انتظار", "Pending"),
                value: "\(authVM.allMembers.filter { $0.role == .pending }.count)",
                icon: "clock.fill",
                color: DS.Color.warning
            )

            // News Requests
            adminColorfulStatCard(
                title: L10n.t("الأخبار", "News"),
                value: "\(authVM.pendingNewsRequests.count)",
                icon: "newspaper.fill",
                color: DS.Color.accent
            )
            
            // Deceased Requests
            adminColorfulStatCard(
                title: L10n.t("الوفيات", "Deceased"),
                value: "\(authVM.deceasedRequests.count)",
                icon: "bolt.heart.fill",
                color: DS.Color.error
            )
            
            // Phone Updates
            adminColorfulStatCard(
                title: L10n.t("الجوال", "Phone"),
                value: "\(authVM.phoneChangeRequests.count)",
                icon: "phone.badge.checkmark",
                color: DS.Color.success
            )

            // Reports
            adminColorfulStatCard(
                title: L10n.t("بلاغات", "Reports"),
                value: "\(authVM.newsReportRequests.count)",
                icon: "exclamationmark.bubble.fill",
                color: DS.Color.error
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
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(color)
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
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: color.opacity(0.15), radius: 12, x: 0, y: 4)
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
                        .font(.system(size: 15, weight: .bold))
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

// MARK: - Rounded Shape Helper
private struct RoundedShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - AdminStatCard & AdminMenuRow (Backwards compatibility)
struct AdminStatCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View {
        DSStatCard(title: title, value: value, icon: icon, color: color)
    }
}

struct AdminMenuRow: View {
    let title: String; let subtitle: String; let icon: String; let color: Color
    var count: Int = 0

    var body: some View {
        DSActionRow(title: title, subtitle: subtitle, icon: icon, color: color, badge: count > 0 ? count : nil)
    }
}
