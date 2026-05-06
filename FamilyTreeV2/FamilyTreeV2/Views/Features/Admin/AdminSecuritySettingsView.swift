import SwiftUI

/// إعدادات النظام — بنفس تصميم التطبيق (DSCard + DSSectionHeader + DSActionRow)
struct AdminSecuritySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {

                    // ── الإعدادات العامة ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("الإعدادات العامة", "General Settings"),
                            icon: "gearshape.2.fill",
                            iconColor: DS.Color.primary
                        )

                        NavigationLink(
                            destination: AdminAppSettingsView()
                                .environmentObject(authVM)
                                .environmentObject(memberVM)
                                .environmentObject(appSettingsVM)
                                .environmentObject(notificationVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("إعدادات التطبيق", "App Settings"),
                                subtitle: L10n.t("التسجيل · الأخبار · الميزات · الصيانة", "Registration · News · Features · Maintenance"),
                                icon: "gearshape.fill",
                                color: DS.Color.primary
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // ── الفريق ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("الفريق", "Team"),
                            icon: "person.3.fill",
                            iconColor: DS.Color.accent
                        )

                        NavigationLink(
                            destination: AdminModeratorsView()
                                .environmentObject(authVM)
                                .environmentObject(memberVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("المدراء والمشرفون", "Moderators & Supervisors"),
                                subtitle: L10n.t("تعيين الأدوار وإدارة الصلاحيات", "Assign roles and manage permissions"),
                                icon: "person.badge.key.fill",
                                color: DS.Color.accent
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // ── الأمان ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("الأمان", "Security"),
                            icon: "lock.shield.fill",
                            iconColor: DS.Color.error
                        )

                        NavigationLink(
                            destination: AdminBannedPhonesView()
                                .environmentObject(authVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("الأرقام المحظورة", "Banned Numbers"),
                                subtitle: L10n.t("منع أرقام معينة من التسجيل", "Block numbers from registering"),
                                icon: "phone.down.fill",
                                color: DS.Color.error,
                                badge: authVM.bannedPhones.count > 0 ? authVM.bannedPhones.count : nil
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // ── المراقبة ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("المراقبة", "Monitoring"),
                            icon: "waveform.path.ecg.rectangle.fill",
                            iconColor: DS.Color.info
                        )

                        NavigationLink(
                            destination: AdminSystemHealthView()
                                .environmentObject(authVM)
                                .environmentObject(notificationVM)
                                .environmentObject(memberVM)
                        ) {
                            DSActionRow(
                                title: L10n.t("صحة النظام", "System Health"),
                                subtitle: L10n.t("النشاط والأجهزة والإشعارات", "Activity, Devices & Push"),
                                icon: "waveform.path.ecg",
                                color: DS.Color.info
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.top, DS.Spacing.md)
            }
        }
        .navigationTitle(L10n.t("إعدادات النظام", "System Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
