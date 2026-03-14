import SwiftUI

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

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

            case .deviceLimitExceeded:
                DeviceLimitView()

            case .accountFrozen:
                FrozenAccountView()

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
                .font(.system(size: 80))
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
