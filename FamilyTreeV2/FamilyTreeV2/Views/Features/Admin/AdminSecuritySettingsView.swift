import SwiftUI

/// واجهة مجمّعة: إعدادات النظام
struct AdminSecuritySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {

                    // MARK: - الإعدادات العامة
                    sectionCard(
                        title: L10n.t("الإعدادات العامة", "General Settings"),
                        icon: "gearshape.2.fill",
                        color: DS.Color.primary
                    ) {
                        NavigationLink(destination: AdminAppSettingsView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                            .environmentObject(appSettingsVM)
                            .environmentObject(notificationVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("إعدادات التطبيق", "App Settings"),
                                subtitle: L10n.t("التسجيل · الأخبار · الصيانة · الأجهزة", "Registration · News · Maintenance · Devices"),
                                icon: "gearshape.fill",
                                color: DS.Color.primary
                            )
                        }
                    }

                    // MARK: - إدارة الأدوار
                    sectionCard(
                        title: L10n.t("إدارة الأدوار", "Role Management"),
                        icon: "person.badge.key.fill",
                        color: DS.Color.accent
                    ) {
                        NavigationLink(destination: AdminModeratorsView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("المدراء والمشرفون", "Moderators & Supervisors"),
                                subtitle: L10n.t("تعيين الأدوار وإدارة صلاحيات الفريق", "Assign roles and manage team permissions"),
                                icon: "person.3.fill",
                                color: DS.Color.accent
                            )
                        }
                    }

                    // MARK: - الأمان والوصول
                    sectionCard(
                        title: L10n.t("الأمان والوصول", "Security & Access"),
                        icon: "lock.shield.fill",
                        color: DS.Color.error
                    ) {
                        NavigationLink(destination: AdminBannedPhonesView()
                            .environmentObject(authVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("الأرقام المحظورة", "Banned Numbers"),
                                subtitle: L10n.t("حظر أرقام من تسجيل الدخول", "Block numbers from logging in"),
                                icon: "phone.down.fill",
                                color: DS.Color.error,
                                badge: authVM.bannedPhones.count > 0 ? authVM.bannedPhones.count : nil
                            )
                        }

                        DSDivider()

                        NavigationLink(destination: AdminDevicesView()
                            .environmentObject(notificationVM)
                            .environmentObject(memberVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("إدارة الأجهزة", "Device Management"),
                                subtitle: L10n.t("عرض وإزالة أجهزة الأعضاء المرتبطة", "View and remove members' linked devices"),
                                icon: "iphone.gen3",
                                color: DS.Color.warning
                            )
                        }
                    }

                    // MARK: - الإشعارات
                    sectionCard(
                        title: L10n.t("الإشعارات", "Notifications"),
                        icon: "bell.badge.fill",
                        color: DS.Color.info
                    ) {
                        NavigationLink(destination: AdminPushHealthView()
                            .environmentObject(authVM)
                            .environmentObject(notificationVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("فحص حالة الإشعارات", "Push Health Check"),
                                subtitle: L10n.t("إحصائيات رموز التسجيل واختبار الإرسال", "Token stats & delivery test"),
                                icon: "waveform.path.ecg",
                                color: DS.Color.info
                            )
                        }
                    }

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
        }
        .navigationTitle(L10n.t("إعدادات النظام", "System Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Section Card Helper

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Section Header
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xs)

            DSCard(padding: 0) {
                content()
            }
        }
    }
}
