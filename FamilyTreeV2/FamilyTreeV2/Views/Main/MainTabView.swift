import SwiftUI
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab = 0
    @State private var showNotificationAlert = false
    @AppStorage("notificationAlertDismissCount") private var dismissCount = 0

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    NotificationCenter.default.post(name: .didReselectTab, object: nil, userInfo: ["tab": newValue])
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedTab = newValue
            }
        )
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
        TabView(selection: tabSelection) {
            HomeNewsView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "newspaper.fill" : "newspaper")
                    Text(L10n.t("الرئيسية", "Home"))
                }
                .tag(0)

            TreeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "tree.fill" : "tree")
                    Text(L10n.t("الشجرة", "Tree"))
                }
                .tag(1)

            DiwaniyasView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "map.fill" : "map")
                    Text(L10n.t("الديوانيات", "Diwaniyas"))
                }
                .tag(2)

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
        }
        .task {
            // تحقق من إذن الإشعارات — أقصى 3 تنبيهات
            guard dismissCount < 3 else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied || settings.authorizationStatus == .notDetermined {
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
    }
}

extension Notification.Name {
    static let didReselectTab = Notification.Name("didReselectTab")
}
