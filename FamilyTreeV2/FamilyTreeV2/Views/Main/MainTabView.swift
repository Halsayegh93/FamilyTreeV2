import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab = 0

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    // Tapped the same tab — post notification to reset sub-pages
                    NotificationCenter.default.post(name: .didReselectTab, object: nil, userInfo: ["tab": newValue])
                }
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
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(DS.Color.surface.opacity(0.95), for: .tabBar)

        // Tree tab glow overlay
        treeTabGlow
        }
    }

    // MARK: - Tree Tab Glow Effect
    private var treeTabGlow: some View {
        GeometryReader { geo in
            let tabCount = CGFloat(authVM.canModerate ? 5 : 4)
            let tabWidth = geo.size.width / tabCount
            let treeIndex: CGFloat = 1
            let centerX = tabWidth * treeIndex + tabWidth / 2

            Circle()
                .fill(DS.Color.primary.opacity(selectedTab == 1 ? 0.25 : 0))
                .frame(width: 44, height: 44)
                .blur(radius: 12)
                .position(x: centerX, y: geo.size.height - 30)
                .allowsHitTesting(false)
                .animation(DS.Anim.smooth, value: selectedTab)
        }
        .ignoresSafeArea()
    }
}

extension Notification.Name {
    static let didReselectTab = Notification.Name("didReselectTab")
}
