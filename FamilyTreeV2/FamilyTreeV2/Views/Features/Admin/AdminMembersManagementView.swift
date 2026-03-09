import SwiftUI

struct AdminMembersManagementView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    enum ManagementTab: String, CaseIterable, Identifiable {
        case inactive, incomplete

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inactive:   return L10n.t("غير مفعلة", "Inactive")
            case .incomplete: return L10n.t("بيانات ناقصة", "Incomplete")
            }
        }

        var icon: String {
            switch self {
            case .inactive:   return "person.badge.clock"
            case .incomplete: return "exclamationmark.triangle.fill"
            }
        }
    }

    @State private var selectedTab: ManagementTab = .inactive

    // MARK: - Counts

    private var inactiveCount: Int {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { member in
                let isNotActivated = member.status == nil || member.status == .pending
                let hasNoPhone = member.phoneNumber == nil || (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return isNotActivated || hasNoPhone
            }
            .count
    }

    private var incompleteCount: Int {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { member in
                let noBirth = member.birthDate == nil || (member.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let noFather = member.fatherId == nil
                let noGender = member.gender == nil || (member.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return noBirth || noFather || noGender
            }
            .count
    }

    private func badgeCount(for tab: ManagementTab) -> Int {
        switch tab {
        case .inactive:   return inactiveCount
        case .incomplete: return incompleteCount
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: 0) {
                // شريط التابات
                tabBar
                    .padding(.top, DS.Spacing.sm)

                // المحتوى
                switch selectedTab {
                case .inactive:
                    AdminActivateAccountsView()
                        .environmentObject(authVM)
                        .environmentObject(memberVM)
                        .environmentObject(adminRequestVM)
                case .incomplete:
                    AdminIncompleteMembersView()
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
            // اختيار أول تاب فيه عناصر
            if inactiveCount == 0 && incompleteCount > 0 {
                selectedTab = .incomplete
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(ManagementTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .padding(.bottom, DS.Spacing.xs)
    }

    private func tabButton(_ tab: ManagementTab) -> some View {
        let isSelected = selectedTab == tab
        let count = badgeCount(for: tab)

        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                Text(tab.title)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)

                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.scaled(10, weight: .black))
                        .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textOnPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? DS.Color.textOnPrimary.opacity(0.9) : DS.Color.warning)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(isSelected ? DS.Color.primary : DS.Color.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.clear : DS.Color.primary.opacity(0.15),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
