import SwiftUI

/// إعدادات النظام — مربّعات بنفس لغة لوحة الإدارة (AdminTile) بدل صفوف داخل
/// بطاقات. ضُمّ إليها ما كان مبعثراً في اللوحة: فريق الإدارة · إرسال الإشعارات
/// · تحديثات التطبيق — فصارت اللوحة للعمل اليومي وهذه لضبط النظام.
struct AdminSecuritySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    /// عدد فريق الإدارة — شارة على مربّع الفريق، كما كانت في اللوحة.
    private var moderatorCount: Int {
        memberVM.allMembers.filter {
            $0.role == .owner || $0.role == .admin || $0.role == .monitor || $0.role == .supervisor
        }.count
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {

                    // شبكة واحدة متجاورة — العناوين الثلاثة كانت تقطع الصفوف
                    // فتظهر المربّعات مبعثرة بدل أن تصطفّ جنب بعضها.
                    LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
                        AdminTile(
                            title: L10n.t("إعدادات التطبيق", "App Settings"),
                            subtitle: L10n.t("التسجيل · الأخبار · الميزات · الصيانة",
                                             "Registration · News · Features · Maintenance"),
                            icon: "gearshape.fill",
                            color: DS.Color.primary
                        ) {
                            AdminAppSettingsView()
                                .environmentObject(authVM)
                                .environmentObject(memberVM)
                                .environmentObject(appSettingsVM)
                                .environmentObject(notificationVM)
                        }

                        if authVM.canModerate {
                            AdminTile(
                                title: L10n.t("فريق الإدارة", "Admin Team"),
                                subtitle: L10n.t("الأعضاء والصلاحيات", "Members & permissions"),
                                icon: "person.3.fill",
                                color: DS.Color.neonPurple,
                                badge: moderatorCount
                            ) {
                                AdminModeratorsView()
                                    .environmentObject(authVM)
                                    .environmentObject(memberVM)
                            }
                        }

                        if authVM.isAdmin {
                            AdminTile(
                                title: L10n.t("إرسال إشعارات", "Notifications"),
                                subtitle: L10n.t("إشعار موجّه أو بثّ", "Targeted or broadcast"),
                                icon: "bell.badge.fill",
                                color: DS.Color.secondary
                            ) {
                                AdminNotificationsView()
                                    .environmentObject(authVM)
                                    .environmentObject(memberVM)
                                    .environmentObject(notificationVM)
                            }

                            AdminTile(
                                title: L10n.t("تحديثات التطبيق", "App Updates"),
                                subtitle: L10n.t("رسالة نظام في المستجدات", "System message in Updates"),
                                icon: "megaphone.fill",
                                color: DS.Color.success
                            ) {
                                AdminAppUpdateView()
                                    .environmentObject(authVM)
                                    .environmentObject(notificationVM)
                            }
                        }

                        AdminTile(
                            title: L10n.t("صحة النظام", "System Health"),
                            subtitle: L10n.t("النشاط والأجهزة والإشعارات", "Activity, devices & push"),
                            icon: "waveform.path.ecg",
                            color: DS.Color.info
                        ) {
                            AdminSystemHealthView()
                                .environmentObject(authVM)
                                .environmentObject(notificationVM)
                                .environmentObject(memberVM)
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

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3)
    }

}
