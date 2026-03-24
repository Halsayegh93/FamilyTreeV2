import SwiftUI

struct AdminMembersManagementView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    enum Tab: Int, CaseIterable {
        case management, treeHealth, directory

        var title: String {
            switch self {
            case .management: return L10n.t("إدارة", "Manage")
            case .treeHealth: return L10n.t("صحة الشجرة", "Tree Health")
            case .directory: return L10n.t("السجل", "Registry")
            }
        }
    }

    @State private var selectedTab: Tab = .management

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: 0) {
                // Segmented Picker
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                // Tab Content
                switch selectedTab {
                case .management:
                    AdminActivateAccountsView()
                        .environmentObject(authVM)
                        .environmentObject(memberVM)
                        .environmentObject(adminRequestVM)

                case .treeHealth:
                    AdminTreeHealthView()
                        .environmentObject(authVM)
                        .environmentObject(memberVM)

                case .directory:
                    AdminMembersDirectoryView()
                        .environmentObject(authVM)
                        .environmentObject(memberVM)
                }
            }
        }
        .navigationTitle(L10n.t("إدارة الأعضاء", "Members Management"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await memberVM.fetchAllMembers()
        }
    }
}
