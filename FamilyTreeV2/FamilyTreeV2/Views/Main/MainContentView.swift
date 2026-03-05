import SwiftUI
struct MainContentView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        Group {
            switch authVM.status {
            case .unauthenticated:
                LoginView()
            case .checking:
                ProgressView(L10n.t("جاري التحقق...", "Checking..."))
                    .tint(DS.Color.primary)
            case .authenticatedNoProfile:
                RegistrationView()
            case .pendingApproval:
                // يمنع المستخدم من الدخول حتى يوافق المدير
                WaitingForApprovalView()
            case .trialExpired:
                TrialExpiredView()
            case .deviceLimitExceeded:
                DeviceLimitView()
            case .fullyAuthenticated:
                // الدخول الكامل للتطبيق
                MainTabView()
            }
        }
        .tint(DS.Color.primary)
    }
}
