import SwiftUI

/// واجهة مجمّعة: الأجهزة + الأرقام المحظورة + إعدادات التطبيق
struct AdminSecuritySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {

                    DSCard(padding: 0) {
                        NavigationLink(destination: AdminDevicesView()) {
                            DSActionRow(
                                title: L10n.t("إدارة الأجهزة", "Device Management"),
                                subtitle: L10n.t("عرض وإزالة أجهزة الأعضاء المرتبطة", "View and remove members' linked devices"),
                                icon: "iphone.gen3",
                                color: DS.Color.neonBlue
                            )
                        }
                        DSDivider()
                        NavigationLink(destination: AdminBannedPhonesView()) {
                            DSActionRow(
                                title: L10n.t("الأرقام المحظورة", "Banned Numbers"),
                                subtitle: L10n.t("حظر أرقام من تسجيل الدخول", "Block numbers from logging in"),
                                icon: "phone.down.fill",
                                color: DS.Color.error,
                                badge: authVM.bannedPhones.count > 0 ? authVM.bannedPhones.count : nil
                            )
                        }
                        DSDivider()
                        NavigationLink(destination: AdminAppSettingsView()) {
                            DSActionRow(
                                title: L10n.t("إعدادات التطبيق", "App Settings"),
                                subtitle: L10n.t("تحكم بإعدادات التسجيل والأمان", "Manage registration and security settings"),
                                icon: "gearshape.fill",
                                color: DS.Color.gridContact
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }
                .padding(.top, DS.Spacing.md)
            }
        }
        .navigationTitle(L10n.t("الأمان والإعدادات", "Security & Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
