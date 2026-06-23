import SwiftUI
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var selectedTab = 0
    @State private var showNotificationAlert = false
    @AppStorage("notificationAlertDismissCount") private var dismissCount = 0

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    NotificationCenter.default.post(name: .didReselectTab, object: nil, userInfo: ["tab": newValue])
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                selectedTab = newValue
                NotificationCenter.default.post(name: Notification.Name("TabChanged"), object: nil)
                let tabs = ["home", "tree", "diwaniyas", "profile", "admin"]
                if newValue < tabs.count {
                    AppAnalytics.trackTabSwitch(tab: tabs[newValue])
                    MemberActivityTracker.report(tabs[newValue])
                }
            }
        )
    }
    
    var body: some View {
        // تحديث إجباري (server-driven) — يحجب التطبيق حتى التحديث.
        if (appSettingsVM.settings.forceUpdate ?? false),
           (appSettingsVM.settings.latestBuild ?? 0) > kAppBuild {
            ForceUpdateView(message: appSettingsVM.settings.updateMessage,
                            urlString: appSettingsVM.settings.updateUrl)
        } else {
        ZStack(alignment: .bottomLeading) {
        TabView(selection: tabSelection) {
            HomeNewsView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text(L10n.t("الرئيسية", "Home"))
                }
                .tag(0)

            // مغلّف يسمح بالتبديل بين الواجهة الكلاسيكية والتجربة الجديدة
            TreeTabContainer(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "tree.fill" : "tree")
                    Text(L10n.t("الشجرة", "Tree"))
                }
                .tag(1)

            if appSettingsVM.settings.diwaniyasEnabled ?? true {
                DiwaniyasView(selectedTab: $selectedTab)
                    .tabItem {
                        Image(systemName: selectedTab == 2 ? "map.fill" : "map")
                        Text(L10n.t("الديوانيات", "Diwaniyas"))
                    }
                    .tag(2)
            }

            ProfileView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "person.crop.circle.fill" : "person.crop.circle")
                    Text(L10n.t("حسابي", "Profile"))
                }
                .tag(3)

            if authVM.canModerate {
                AdminDashboardView(selectedTab: $selectedTab)
                    .tabItem {
                        Image(systemName: selectedTab == 4 ? "gearshape.2.fill" : "gearshape.2")
                        Text(L10n.t("الإدارة", "Admin"))
                    }
                    .tag(4)
            }
        }
        .tint(DS.Color.primary)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .overlay(alignment: .top) {
            OfflineBanner()
                .padding(.top, DS.Spacing.xs)
                .zIndex(999)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAdminRequests)) { _ in
            guard authVM.canModerate else { return }
            withAnimation { selectedTab = 4 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAdminReviewForKind)) { _ in
            guard authVM.canModerate else { return }
            withAnimation { selectedTab = 4 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHomeNotificationsCenter)) { _ in
            withAnimation { selectedTab = 0 }
        }
        }
        .task {
            // تتبع أول شاشة عند الفتح
            MemberActivityTracker.report("home")
            // أول مرة: النظام يطلب تلقائي من PushNotificationDelegate
            // ننتظر 3 ثواني عشان المستخدم يرد على طلب النظام أول
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // تحقق إذا رفض — أقصى مرتين بعد طلب النظام
            guard dismissCount < 2 else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied {
                showNotificationAlert = true
            }
        }
        .alert(
            L10n.t("تفعيل الإشعارات", "Enable Notifications"),
            isPresented: $showNotificationAlert
        ) {
            Button(L10n.t("فتح الإعدادات", "Open Settings")) {
                dismissCount += 1
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.t("لاحقاً", "Later"), role: .cancel) {
                dismissCount += 1
            }
        } message: {
            Text(L10n.t(
                "فعّل الإشعارات عشان توصلك أخبار العائلة والتحديثات المهمة",
                "Enable notifications to receive family news and important updates"
            ))
        }
        } // نهاية else لحارس التحديث الإجباري
    }
}

extension Notification.Name {
    static let didReselectTab       = Notification.Name("didReselectTab")
    static let openAdminRequests    = Notification.Name("openAdminRequests")
    /// userInfo: ["kind": String] — يفتح تاب الإدارة + يدفع شاشة المراجعة المناسبة
    static let openAdminReviewForKind = Notification.Name("openAdminReviewForKind")
    /// يفتح تاب الرئيسية ويدفع مركز الإشعارات + يفتح شيت تفاصيل الطلب لو فيه deep-link
    static let openHomeNotificationsCenter = Notification.Name("openHomeNotificationsCenter")
}

// MARK: - شاشة التحديث الإجباري (server-driven)
struct ForceUpdateView: View {
    let message: String?
    let urlString: String?

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(DS.Color.primary)
                Text(L10n.t("تحديث مطلوب", "Update Required"))
                    .font(DS.Font.title2)
                    .foregroundColor(DS.Color.textPrimary)
                Text((message?.isEmpty == false)
                     ? message!
                     : L10n.t("يتوفّر إصدار جديد. حدّث التطبيق للمتابعة.",
                              "A new version is available. Update to continue."))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
                if let urlStr = urlString, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    Button { UIApplication.shared.open(url) } label: {
                        Label(L10n.t("تحديث الآن", "Update Now"), systemImage: "square.and.arrow.down")
                            .font(DS.Font.bodyBold)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.vertical, DS.Spacing.md)
                            .background(DS.Color.primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(DS.Spacing.xl)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
