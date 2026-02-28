import SwiftUI

struct AdminModeratorsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var appeared = false
    @State private var showAddSheet = false
    @State private var memberToChange: FamilyMember?
    @State private var showRoleConfirm = false
    @State private var pendingRole: FamilyMember.UserRole = .member
    @State private var showRemoveConfirm = false

    private var isAdmin: Bool {
        authVM.currentUser?.role == .admin
    }

    private var moderators: [FamilyMember] {
        authVM.allMembers
            .filter { $0.role == .admin || $0.role == .supervisor }
            .sorted { a, b in
                if a.role == .admin && b.role != .admin { return true }
                if a.role != .admin && b.role == .admin { return false }
                return a.fullName < b.fullName
            }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 80)
                .offset(x: 120, y: -180)

            Circle()
                .fill(Color.orange.opacity(0.06))
                .frame(width: 160, height: 160)
                .blur(radius: 60)
                .offset(x: -100, y: 120)

            if moderators.isEmpty {
                emptyState
            } else {
                List {
                    let admins = moderators.filter { $0.role == .admin }
                    if !admins.isEmpty {
                        Section {
                            ForEach(Array(admins.enumerated()), id: \.element.id) { index, member in
                                moderatorRow(member: member, index: index)
                            }
                        } header: {
                            sectionHeader(title: L10n.t("المدراء", "Admins"), icon: "shield.fill", color: .purple, count: admins.count)
                        }
                    }

                    let supervisors = moderators.filter { $0.role == .supervisor }
                    if !supervisors.isEmpty {
                        Section {
                            ForEach(Array(supervisors.enumerated()), id: \.element.id) { index, member in
                                moderatorRow(member: member, index: admins.count + index)
                            }
                        } header: {
                            sectionHeader(title: L10n.t("المشرفين", "Supervisors"), icon: "star.fill", color: .orange, count: supervisors.count)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(L10n.t("المدراء والمشرفين", "Admins & Supervisors"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddModeratorSheet()
                .environmentObject(authVM)
        }
        .alert(
            L10n.t("تغيير الرتبة", "Change Role"),
            isPresented: $showRoleConfirm,
            presenting: memberToChange
        ) { member in
            Button(L10n.t("تأكيد", "Confirm"), role: .destructive) {
                Task {
                    await authVM.updateMemberRole(memberId: member.id, newRole: pendingRole)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            let roleName = pendingRole == .admin ? L10n.t("مدير", "Admin") : (pendingRole == .supervisor ? L10n.t("مشرف", "Supervisor") : L10n.t("عضو", "Member"))
            Text(L10n.t(
                "تغيير رتبة \(member.firstName) إلى \(roleName)؟",
                "Change \(member.firstName)'s role to \(roleName)?"
            ))
        }
        .alert(
            L10n.t("إزالة الصلاحية", "Remove Permission"),
            isPresented: $showRemoveConfirm,
            presenting: memberToChange
        ) { member in
            Button(L10n.t("إزالة", "Remove"), role: .destructive) {
                Task {
                    await authVM.updateMemberRole(memberId: member.id, newRole: .member)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "إزالة صلاحية \(member.firstName) وتحويله لعضو عادي؟",
                "Remove \(member.firstName)'s permission and set as regular member?"
            ))
        }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Section Header
    private func sectionHeader(title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Text("(\(count))")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
        }
        .textCase(nil)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Moderator Row
    private func moderatorRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: member.role == .admin
                                ? [Color.purple.opacity(0.3), Color.purple.opacity(0.1)]
                                : [Color.orange.opacity(0.3), Color.orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: member.role == .admin ? "shield.fill" : "star.fill")
                    .font(DS.Font.scaled(20, weight: .bold))
                    .foregroundColor(member.role == .admin ? .purple : .orange)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: DS.Spacing.xs) {
                    Text(member.role == .admin ? L10n.t("مدير", "Admin") : L10n.t("مشرف", "Supervisor"))
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(member.role == .admin ? Color.purple : Color.orange)
                        .clipShape(Capsule())

                    if member.id == authVM.currentUser?.id {
                        Text(L10n.t("أنت", "You"))
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(DS.Color.info)
                            .clipShape(Capsule())
                    }
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
            }

            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.05), value: appeared)
        .listRowBackground(DS.Color.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // لا يمكن تعديل نفسك + فقط المدير يقدر يتحكم
            if isAdmin && member.id != authVM.currentUser?.id {
                // إزالة الصلاحية
                Button(role: .destructive) {
                    memberToChange = member
                    showRemoveConfirm = true
                } label: {
                    Label(L10n.t("إزالة", "Remove"), systemImage: "person.badge.minus")
                }

                // تبديل الرتبة
                if member.role == .supervisor {
                    Button {
                        memberToChange = member
                        pendingRole = .admin
                        showRoleConfirm = true
                    } label: {
                        Label(L10n.t("ترقية لمدير", "Promote"), systemImage: "arrow.up.circle.fill")
                    }
                    .tint(.purple)
                } else if member.role == .admin {
                    Button {
                        memberToChange = member
                        pendingRole = .supervisor
                        showRoleConfirm = true
                    } label: {
                        Label(L10n.t("تنزيل لمشرف", "Demote"), systemImage: "arrow.down.circle.fill")
                    }
                    .tint(.orange)
                }
            }
        }
        .contextMenu {
            if isAdmin && member.id != authVM.currentUser?.id {
                if member.role == .supervisor {
                    Button {
                        memberToChange = member
                        pendingRole = .admin
                        showRoleConfirm = true
                    } label: {
                        Label(L10n.t("ترقية لمدير", "Promote to Admin"), systemImage: "shield.fill")
                    }
                } else if member.role == .admin {
                    Button {
                        memberToChange = member
                        pendingRole = .supervisor
                        showRoleConfirm = true
                    } label: {
                        Label(L10n.t("تنزيل لمشرف", "Demote to Supervisor"), systemImage: "star.fill")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    memberToChange = member
                    showRemoveConfirm = true
                } label: {
                    Label(L10n.t("إزالة الصلاحية", "Remove Permission"), systemImage: "person.badge.minus")
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "crown.fill")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(.purple.opacity(0.5))
            }
            Text(L10n.t("لا يوجد مدراء أو مشرفين", "No admins or supervisors"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)

            if isAdmin {
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                        Text(L10n.t("إضافة", "Add"))
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.primary)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Add Moderator Sheet
struct AddModeratorSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedRole: FamilyMember.UserRole = .supervisor

    private var regularMembers: [FamilyMember] {
        authVM.allMembers
            .filter { $0.role == .member && $0.status == .active }
            .filter { member in
                searchText.isEmpty || member.fullName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.fullName < $1.fullName }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // اختيار الرتبة
                    Picker("", selection: $selectedRole) {
                        Text(L10n.t("مشرف", "Supervisor")).tag(FamilyMember.UserRole.supervisor)
                        Text(L10n.t("مدير", "Admin")).tag(FamilyMember.UserRole.admin)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

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
                    .padding(.bottom, DS.Spacing.sm)

                    if regularMembers.isEmpty {
                        Spacer()
                        VStack(spacing: DS.Spacing.md) {
                            Image(systemName: "person.slash")
                                .font(DS.Font.scaled(36, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                            Text(L10n.t("لا يوجد أعضاء", "No members found"))
                                .font(DS.Font.subheadline)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(regularMembers) { member in
                                Button {
                                    Task {
                                        await authVM.updateMemberRole(memberId: member.id, newRole: selectedRole)
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: DS.Spacing.md) {
                                        ZStack {
                                            Circle()
                                                .fill(DS.Color.primary.opacity(0.1))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "person.fill")
                                                .font(DS.Font.scaled(16, weight: .semibold))
                                                .foregroundColor(DS.Color.primary)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.fullName)
                                                .font(DS.Font.calloutBold)
                                                .foregroundColor(DS.Color.textPrimary)
                                                .lineLimit(1)

                                            if let phone = member.phoneNumber, !phone.isEmpty {
                                                Text(phone)
                                                    .font(DS.Font.caption1)
                                                    .foregroundColor(DS.Color.textTertiary)
                                                    .monospacedDigit()
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "plus.circle.fill")
                                            .font(DS.Font.scaled(22))
                                            .foregroundColor(selectedRole == .admin ? .purple : .orange)
                                    }
                                }
                                .listRowBackground(DS.Color.surface)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(L10n.t("إضافة مدير/مشرف", "Add Admin/Supervisor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.textTertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
