import SwiftUI

struct RootView: View {
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
                WaitingForApprovalView()

            case .trialExpired:
                TrialExpiredView()

            case .fullyAuthenticated:
                MainTabView()
            }
        }
        .animation(.default, value: authVM.status)
    }
}
