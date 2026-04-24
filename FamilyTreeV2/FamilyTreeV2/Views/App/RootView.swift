import SwiftUI

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    var body: some View {
        Group {
            switch authVM.status {
            case .unauthenticated:
                LoginView()

            case .checking:
                SplashScreenView()

            case .authenticatedNoProfile:
                RegistrationView()

            case .pendingApproval:
                WaitingForApprovalView()

            case .accountFrozen:
                FrozenAccountView()

            case .deviceLimitExceeded:
                DeviceLimitView()
                    .environmentObject(appSettingsVM)

            case .deviceRevoked:
                DeviceRevokedView()
                    .environmentObject(notificationVM)
                    .environmentObject(appSettingsVM)

            case .deviceOverLimit:
                DeviceOverLimitView()
                    .environmentObject(notificationVM)
                    .environmentObject(appSettingsVM)

            case .fullyAuthenticated:
                if appSettingsVM.settings.maintenanceMode && !authVM.canModerate {
                    MaintenanceModeView()
                } else {
                    MainTabView()
                }
            }
        }
        .animation(.default, value: authVM.status)
    }
}

// MARK: - Maintenance Mode View

struct MaintenanceModeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver")
                .font(DS.Font.scaled(80, weight: .regular))
                .foregroundStyle(DS.Color.primary)

            Text(L10n.t("التطبيق تحت الصيانة", "App Under Maintenance"))
                .font(DS.Font.title1)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(L10n.t(
                "نقوم حالياً بتحديث التطبيق. يرجى المحاولة لاحقاً.",
                "We're currently updating the app. Please try again later."
            ))
            .font(DS.Font.body)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Spacing.xxxl)

            Spacer()

            DSSecondaryButton(
                L10n.t("تحديث", "Refresh"),
                icon: "arrow.clockwise"
            ) {
                Task {
                    await appSettingsVM.fetchSettings()
                }
            }

            DSSecondaryButton(
                L10n.t("تسجيل الخروج", "Sign Out"),
                icon: "rectangle.portrait.and.arrow.right"
            ) {
                Task {
                    await authVM.signOut()
                }
            }
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.background)
    }
}

// MARK: - Device Revoked View
struct DeviceRevokedView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    @State private var showDevicesSheet = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DS.Color.warning.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "iphone.slash")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                }

                VStack(spacing: DS.Spacing.md) {
                    Text(L10n.t("تم إزالة هذا الجهاز", "Device Removed"))
                        .font(DS.Font.title2)
                        .fontWeight(.black)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(L10n.t(
                        "تم حذف هذا الجهاز من الأجهزة المرتبطة.\nيمكنك إدارة الأجهزة وإزالة جهاز آخر للمتابعة.",
                        "This device was removed from linked devices.\nManage your devices to continue."
                    ))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
                }

                Spacer()

                DSPrimaryButton(
                    L10n.t("إدارة الأجهزة", "Manage Devices"),
                    icon: "iphone.gen3"
                ) {
                    showDevicesSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)

                DSSecondaryButton(
                    L10n.t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right",
                    color: DS.Color.error
                ) {
                    Task { await authVM.signOut() }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .sheet(isPresented: $showDevicesSheet) {
            LinkedDevicesSheet()
                .environmentObject(appSettingsVM)
        }
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }
}
