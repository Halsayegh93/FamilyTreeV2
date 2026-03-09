import SwiftUI

struct AdminMembersManagementView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            AdminActivateAccountsView()
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environmentObject(adminRequestVM)
        }
        .navigationTitle(L10n.t("إدارة الأعضاء", "Members Management"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await memberVM.fetchAllMembers()
        }
    }
}
