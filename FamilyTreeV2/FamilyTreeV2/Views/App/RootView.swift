import SwiftUI

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var network = NetworkMonitor.shared
    /// شاشة «جاري التحقق» تبقى ١٫٢ ث على الأقل عند الفتح (طلب المالك ٢٠٢٦-١٠-٢٥ «وين راحت؟») — نسخة الإصدار
    /// تتحقق من الجلسة في لحظة فكانت الشاشة تومض وتختفي
    @State private var splashMinDone = false

    var body: some View {
        Group {
            // كل شاشة خلف AnyView — حدّ نوع يقصّر مكدس البناء الأول (iOS 16 يستهلك مكدساً أكثر لكل طبقة؛
            // جوال الوالدة آيفون X بقي على «جاري التحقق» لأن «التسجيل» لم تُبنَ — ٢٠٢٦-١٠-٢٤)
            if !splashMinDone {
                AnyView(SplashScreenView())
            } else {
            switch authVM.status {
            case .unauthenticated:
                AnyView(LoginView())

            case .checking:
                AnyView(SplashScreenView())

            case .authenticatedNoProfile:
                AnyView(RegistrationView())

            case .pendingApproval:
                AnyView(WaitingForApprovalView())

            case .accountFrozen:
                AnyView(FrozenAccountView())

            case .deviceLimitExceeded:
                AnyView(DeviceLimitView()
                    .environmentObject(appSettingsVM))

            case .deviceRevoked:
                AnyView(DeviceRevokedView()
                    .environmentObject(notificationVM)
                    .environmentObject(appSettingsVM))

            case .deviceOverLimit:
                AnyView(DeviceOverLimitView()
                    .environmentObject(notificationVM)
                    .environmentObject(appSettingsVM))

            case .fullyAuthenticated:
                // التحديث الإجباري — النسخة أقل من الحد الأدنى. المالك مستثنى حتى
                // لا يقفل نفسه خارج التطبيق لو رفع الحد قبل ما يحدّث جهازه.
                if AppBuild.current < (appSettingsVM.settings.iosMinBuild ?? 0)
                    && authVM.currentUser?.role != .owner {
                    AnyView(ForceUpdateView())
                } else if appSettingsVM.settings.maintenanceMode && !authVM.canModerate {
                    AnyView(MaintenanceModeView())
                } else {
                    AnyView(MainTabView())
                }
            }
            }
        }
        .animation(.default, value: authVM.status)
        .animation(.easeOut(duration: 0.3), value: splashMinDone)
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            splashMinDone = true
        }
        // Alert مركزي لأي عملية كتابة بدون اتصال — ViewModels تستدعي
        // NetworkMonitor.shared.requireOnline() اللي يضبط هذا الفلاج.
        .dsAlert(
            L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"),
            isPresented: $network.showOfflineAlert
        ) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t(
                "لا يمكن تنفيذ هذا الإجراء بدون اتصال بالإنترنت. تأكّد من الاتصال ثم حاول مجدّداً.",
                "This action requires an internet connection. Please check your connection and try again."
            ))
        }
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
                    await CategoryStore.shared.fetch()
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
                        .dsFont(.emptyTitle)
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
        .dsCenterBox(isPresented: $showDevicesSheet) {
            LinkedDevicesSheet()
                .environmentObject(appSettingsVM)
        }
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }
}
