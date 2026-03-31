import SwiftUI

struct AdminModeratorsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
    @State private var showAddSheet = false
    @State private var memberToChange: FamilyMember?
    @State private var showRoleConfirm = false
    @State private var pendingRole: FamilyMember.UserRole = .member
    @State private var showRemoveConfirm = false

    private var isOwner: Bool {
        authVM.isOwner
    }

    private var moderators: [FamilyMember] {
        let roleOrder: [FamilyMember.UserRole] = [.owner, .admin, .supervisor]
        return memberVM.allMembers
            .filter { $0.role == .owner || $0.role == .admin || $0.role == .supervisor }
            .sorted { a, b in
                let aIdx = roleOrder.firstIndex(of: a.role) ?? 99
                let bIdx = roleOrder.firstIndex(of: b.role) ?? 99
                if aIdx != bIdx { return aIdx < bIdx }
                return a.fullName < b.fullName
            }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()


            if moderators.isEmpty {
                emptyState
            } else {
                List {
                    // المالك يظهر ضمن المدراء — بدون قسم خاص
                    let admins = moderators.filter { $0.role == .admin || $0.role == .owner }
                    if !admins.isEmpty {
                        Section {
                            ForEach(Array(admins.enumerated()), id: \.element.id) { index, member in
                                moderatorRow(member: member, index: index)
                            }
                        } header: {
                            sectionHeader(title: L10n.t("المدراء", "Admins"), icon: "shield.fill", color: DS.Color.neonPurple, count: admins.count)
                        }
                    }

                    let supervisors = moderators.filter { $0.role == .supervisor }
                    if !supervisors.isEmpty {
                        Section {
                            ForEach(Array(supervisors.enumerated()), id: \.element.id) { index, member in
                                moderatorRow(member: member, index: admins.count + index)
                            }
                        } header: {
                            sectionHeader(title: L10n.t("المشرفين", "Supervisors"), icon: "star.fill", color: DS.Color.warning, count: supervisors.count)
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
            if isOwner {
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
        .sheet(isPresented: $showAddSheet, onDismiss: {
            Task { await memberVM.fetchAllMembers(force: true) }
        }) {
            AddModeratorSheet()
                .environmentObject(authVM)
                .environmentObject(memberVM)
        }
        .alert(
            L10n.t("تغيير مستوى الحساب", "Change Account Level"),
            isPresented: $showRoleConfirm,
            presenting: memberToChange
        ) { member in
            Button(L10n.t("تأكيد", "Confirm"), role: .destructive) {
                Task {
                    await memberVM.updateMemberRole(memberId: member.id, newRole: pendingRole)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            let roleName = pendingRole == .admin ? L10n.t("مدير", "Admin") : (pendingRole == .supervisor ? L10n.t("مشرف", "Supervisor") : L10n.t("عضو", "Member"))
            Text(L10n.t(
                "تغيير مستوى حساب \(member.firstName) إلى \(roleName)؟",
                "Change \(member.firstName)'s account level to \(roleName)?"
            ))
        }
        .alert(
            L10n.t("إزالة الصلاحية", "Remove Permission"),
            isPresented: $showRemoveConfirm,
            presenting: memberToChange
        ) { member in
            Button(L10n.t("إزالة", "Remove"), role: .destructive) {
                Task {
                    await memberVM.updateMemberRole(memberId: member.id, newRole: .member)
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
            Task { await memberVM.fetchAllMembers(force: true) }
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
                let roleColor = (member.role == .owner || member.role == .admin) ? DS.Color.neonPurple : DS.Color.warning
                let roleIcon = (member.role == .owner || member.role == .admin) ? "shield.fill" : "star.fill"

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [roleColor.opacity(0.3), roleColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: roleIcon)
                    .font(DS.Font.scaled(20, weight: .bold))
                    .foregroundColor(roleColor)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: DS.Spacing.xs) {
                    Text(member.roleName)
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(member.role.color)
                        .clipShape(Capsule())

                    if member.id == authVM.currentUser?.id {
                        Text(L10n.t("أنت", "You"))
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textOnPrimary)
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
                        Text(KuwaitPhone.display(phone))
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
            if isOwner && member.id != authVM.currentUser?.id && member.role != .owner {
                // إزالة الصلاحية
                Button(role: .destructive) {
                    memberToChange = member
                    showRemoveConfirm = true
                } label: {
                    Label(L10n.t("إزالة", "Remove"), systemImage: "person.badge.minus")
                }

                // تبديل مستوى الحساب
                if member.role == .supervisor {
                    Button {
                        memberToChange = member
                        pendingRole = .admin
                        showRoleConfirm = true
                    } label: {
                        Label(L10n.t("ترقية لمدير", "Promote"), systemImage: "arrow.up.circle.fill")
                    }
                    .tint(DS.Color.neonPurple)
                } else if member.role == .admin {
                    Button {
                        memberToChange = member
                        pendingRole = .supervisor
                        showRoleConfirm = true
                    } label: {
                        Label(L10n.t("تنزيل لمشرف", "Demote"), systemImage: "arrow.down.circle.fill")
                    }
                    .tint(DS.Color.warning)
                }
            }
        }
        .contextMenu {
            if isOwner && member.id != authVM.currentUser?.id && member.role != .owner {
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
                    .fill(DS.Color.neonPurple.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "shield.fill")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(DS.Color.neonPurple.opacity(0.5))
            }
            Text(L10n.t("لا يوجد مدراء أو مشرفين", "No admins or supervisors"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)

            if isOwner {
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                        Text(L10n.t("إضافة", "Add"))
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.xs)
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
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedRole: FamilyMember.UserRole = .supervisor

    private var regularMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role == .member }
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
                    // اختيار مستوى الحساب
                    Picker("", selection: $selectedRole) {
                        Text(L10n.t("مشرف", "Supervisor")).tag(FamilyMember.UserRole.supervisor)
                        Text(L10n.t("مدير", "Admin")).tag(FamilyMember.UserRole.admin)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

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
                                        await memberVM.updateMemberRole(memberId: member.id, newRole: selectedRole)
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
                                                Text(KuwaitPhone.display(phone))
                                                    .font(DS.Font.caption1)
                                                    .foregroundColor(DS.Color.textTertiary)
                                                    .monospacedDigit()
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "plus.circle.fill")
                                            .font(DS.Font.scaled(22))
                                            .foregroundColor(selectedRole == .admin ? DS.Color.neonPurple : DS.Color.warning)
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
