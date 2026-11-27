import SwiftUI

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var network = NetworkMonitor.shared
    /// حالة التحديث من السيرفر («فرض التحديث»)
    @ObservedObject private var updateStore = AppUpdateStore.shared
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
                // «التسجيل»: «من العائلة» (RegistrationView كما هو) أو «من خارج العائلة» (R1)
                AnyView(SignupOriginFlow())

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
                // التحديث الإجباري — السيرفر يقرّر (`app_update_policy`: بعد الموعد، «إجباري الحين»، تحت الحد)،
                // وقبل الترحيل الحد الأدنى من app_settings كما كان. المالك مستثنى حتى لا يقفل نفسه خارج التطبيق.
                if updateStore.isForced(minBuildSetting: appSettingsVM.settings.iosMinBuild ?? 0,
                                        isOwner: authVM.currentUser?.role == .owner) {
                    AnyView(ForceUpdateView())
                } else if appSettingsVM.settings.maintenanceMode && !authVM.canModerate {
                    AnyView(MaintenanceModeView())
                } else {
                    // قبول «الخصوصية والاستخدام» مرة لكل إصدار (app_config.terms_version)
                    AnyView(MainTabView().termsAcceptanceGate().lineageGate().appUpdateGate())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshing = false

    /// بهوية الشعار (طلب المالك ٢٠٢٦-١١-٢٧ «باللون الأزرق ثيمة الشعار»): أرضية كحلية (`gradientBand`)، الشعار الكريمي،
    /// العنوان أبيض، الفاصل والسطر ذهبيان، «تحديث» ذهبي ممتلئ و«تسجيل الخروج» نصّ فاتح هادئ. الظهور مرة (`dsEntrance`).
    var body: some View {
        ZStack {
            Rectangle().fill(DS.Color.gradientBand).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("FamilyLogoCream")
                    .resizable()
                    .scaledToFit()
                    .frame(height: DS.Icon.splashLogo)
                    .padding(DS.Icon.appLogo / 4)
                    .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))
                    .dsEntrance(delay: 0, scale: DSMotion.panelScale, animation: DSMotion.panel, anchor: .center)

                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("التطبيق تحت الصيانة", "App Under Maintenance"))
                        .dsFont(.heroTitle)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: DS.Spacing.xsm) {
                        Rectangle()
                            .fill(LinearGradient(colors: [DS.Color.accentLight.opacity(0), DS.Color.accentLight.opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: DS.Spacing.xxxxl, height: DS.Border.width)
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .dsGlyph(DS.Glyph.sm)
                            .foregroundColor(DS.Color.accentLight)
                            .accessibilityHidden(true)
                        Rectangle()
                            .fill(LinearGradient(colors: [DS.Color.accentLight.opacity(0.7), DS.Color.accentLight.opacity(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: DS.Spacing.xxxxl, height: DS.Border.width)
                    }

                    Text(L10n.t("نقوم حالياً بتحديث التطبيق. يرجى المحاولة لاحقاً.",
                                "We're currently updating the app. Please try again later."))
                        .dsFont(.callout)
                        .foregroundColor(DS.Color.accentLight)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .dsEntrance(delay: DSMotion.iconDelay, scale: 1, animation: DSMotion.panel, anchor: .center)

                DSButton(L10n.t("تحديث", "Refresh"), icon: "arrow.clockwise", tint: DS.Color.goldFill,
                         isLoading: refreshing, fullWidth: false) {
                    guard !refreshing else { return }
                    refreshing = true
                    Task {
                        await appSettingsVM.fetchSettings()
                        await CategoryStore.shared.fetch()
                        refreshing = false
                    }
                }
                .padding(.top, DS.Spacing.xl)

                Spacer()

                Button {
                    Task { await authVM.signOut() }
                } label: {
                    Label(L10n.t("تسجيل الخروج", "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                        .dsFont(.button)
                        .foregroundColor(DS.Color.textOnPrimary.opacity(0.8))
                        .frame(minHeight: DS.Icon.tapTarget)
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dsLightStatusBar()
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
                        .frame(width: DS.Icon.appLogo, height: DS.Icon.appLogo)
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
