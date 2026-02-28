import SwiftUI

struct AdminActivateAccountsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var memberToActivate: FamilyMember?
    @State private var showActivateConfirm = false

    // أعضاء بحالة nil أو pending (غير مفعلين) - ليسوا بـ role pending
    private var inactiveMembers: [FamilyMember] {
        authVM.allMembers
            .filter { $0.role != .pending && ($0.status == nil || $0.status == .pending) }
            .filter { member in
                searchText.isEmpty || member.fullName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.fullName < $1.fullName }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            Circle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 80)
                .offset(x: 120, y: -180)

            Circle()
                .fill(Color.blue.opacity(0.06))
                .frame(width: 160, height: 160)
                .blur(radius: 60)
                .offset(x: -100, y: 120)

            if inactiveMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // البحث
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("بحث عن عضو...", "Search member..."), text: $searchText)
                            .font(DS.Font.callout)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)

                    List {
                        ForEach(Array(inactiveMembers.enumerated()), id: \.element.id) { index, member in
                            memberRow(member: member, index: index)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(L10n.t("حسابات غير مفعلة", "Inactive Accounts"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L10n.t("تفعيل الحساب", "Activate Account"),
            isPresented: $showActivateConfirm,
            presenting: memberToActivate
        ) { member in
            Button(L10n.t("تفعيل", "Activate")) {
                Task {
                    await activateMember(member)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "تفعيل حساب \(member.fullName)؟",
                "Activate \(member.fullName)'s account?"
            ))
        }
        .onAppear {
            Task { await authVM.fetchAllMembers() }
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Member Row
    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Text(member.fullName.prefix(1))
                    .font(DS.Font.headline)
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: DS.Spacing.xs) {
                    // حالة الحساب
                    let statusText = member.status == .pending
                        ? L10n.t("معلق", "Pending")
                        : L10n.t("غير مفعل", "Not Activated")
                    Text(statusText)
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(member.status == .pending ? Color.orange : Color.gray)
                        .clipShape(Capsule())

                    // الرتبة
                    Text(roleLabel(member.role))
                        .font(DS.Font.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Color.textTertiary)
                }

                if let phone = member.phoneNumber, !phone.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(10))
                        Text(phone)
                            .font(DS.Font.caption1)
                            .monospacedDigit()
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }

                if let date = member.createdAt?.prefix(10) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(DS.Font.scaled(10))
                        Text(String(date))
                            .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.04), value: appeared)
        .listRowBackground(DS.Color.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                memberToActivate = member
                showActivateConfirm = true
            } label: {
                Label(L10n.t("تفعيل", "Activate"), systemImage: "checkmark.circle.fill")
            }
            .tint(DS.Color.success)
        }
        .contextMenu {
            Button {
                memberToActivate = member
                showActivateConfirm = true
            } label: {
                Label(L10n.t("تفعيل الحساب", "Activate Account"), systemImage: "checkmark.circle.fill")
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.shield.fill")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(.green.opacity(0.5))
            }
            Text(L10n.t("جميع الحسابات مفعلة", "All accounts are activated"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - Helpers
    private func roleLabel(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .admin: return L10n.t("مدير", "Admin")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلق", "Pending")
        }
    }

    private func activateMember(_ member: FamilyMember) async {
        do {
            try await authVM.supabase
                .from("profiles")
                .update(["status": AnyEncodable("active")])
                .eq("id", value: member.id.uuidString)
                .execute()

            if let index = authVM.allMembers.firstIndex(where: { $0.id == member.id }) {
                await MainActor.run {
                    authVM.allMembers[index].status = .active
                    authVM.objectWillChange.send()
                }
            }
        } catch {
            Log.error("فشل تفعيل الحساب: \(error.localizedDescription)")
        }
    }
}
