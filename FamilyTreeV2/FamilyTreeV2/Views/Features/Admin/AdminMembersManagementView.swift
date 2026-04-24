import SwiftUI

struct AdminMembersManagementView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    enum Tab: Int, CaseIterable {
        case management, treeHealth, directory

        var title: String {
            switch self {
            case .management:  return L10n.t("إدارة", "Manage")
            case .treeHealth:  return L10n.t("الشجرة", "Tree")
            case .directory:   return L10n.t("السجل", "Registry")
            }
        }

        var icon: String {
            switch self {
            case .management:  return "person.badge.exclamationmark"
            case .treeHealth:  return "tree.fill"
            case .directory:   return "person.3.sequence.fill"
            }
        }

        var color: Color {
            switch self {
            case .management:  return DS.Color.warning
            case .treeHealth:  return DS.Color.success
            case .directory:   return DS.Color.primary
            }
        }
    }

    @State private var selectedTab: Tab = .management

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // شريط التابات
                tabBar
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                // المحتوى
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
        .task { await memberVM.fetchAllMembers() }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(DS.Anim.snappy) { selectedTab = tab }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(DS.Font.scaled(13, weight: .semibold))
                Text(tab.title)
                    .font(DS.Font.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : tab.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(
                Capsule()
                    .fill(isSelected ? tab.color : tab.color.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : tab.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
