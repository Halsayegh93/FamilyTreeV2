import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
        TabView(selection: $selectedTab) {
            HomeNewsView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text(L10n.t("الرئيسية", "Home"))
                }
                .tag(0)

            TreeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "person.3.fill" : "person.3")
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
                    Image(systemName: selectedTab == 3 ? "person.fill" : "person")
                    Text(L10n.t("حسابي", "Profile"))
                }
                .tag(3)

            if authVM.canModerate {
                AdminDashboardView(selectedTab: $selectedTab)
                    .tabItem {
                        Image(systemName: selectedTab == 4 ? "shield.fill" : "shield")
                        Text(L10n.t("الإدارة", "Admin"))
                    }
                    .tag(4)
            }
        }
        .tint(DS.Color.primary)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(DS.Color.surface.opacity(0.95), for: .tabBar)
        }
    }
}
