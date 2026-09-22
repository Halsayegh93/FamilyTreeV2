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
    /// الدور المعروضة تفاصيله في ورقة «يقدر / ما يقدر»
    @State private var selectedRoleGuide: RoleGuide? = nil
    /// المسؤول المطلوب تغيير دوره — يفتح ورقة اختيار المجال
    @State private var roleChangeTarget: FamilyMember? = nil
    /// من يستخدم التطبيق فعلاً — يظهر تحت صف «العضو»
    @State private var usageStats: AppUsageStats? = AppUsageStats.cached

    private var isOwner: Bool {
        authVM.isOwner
    }

    private var moderators: [FamilyMember] {
        let roleOrder: [FamilyMember.UserRole] = [.owner, .admin, .monitor, .supervisor]
        return memberVM.allMembers
            .filter { $0.role == .owner || $0.role == .admin || $0.role == .monitor || $0.role == .supervisor }
            .filter { $0.isDeceased != true } // المتوفون لا يظهرون في الفريق (طلب المالك)
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

                    let monitors = moderators.filter { $0.role == .monitor }
                    if !monitors.isEmpty {
                        Section {
                            ForEach(Array(monitors.enumerated()), id: \.element.id) { index, member in
                                moderatorRow(member: member, index: admins.count + index)
                            }
                        } header: {
                            sectionHeader(title: L10n.t("المراقبين", "Monitors"), icon: "eye.fill", color: DS.Color.monitorRole, count: monitors.count)
                        }
                    }

                    let supervisors = moderators.filter { $0.role == .supervisor }
                    if !supervisors.isEmpty {
                        Section {
                            ForEach(Array(supervisors.enumerated()), id: \.element.id) { index, member in
                                moderatorRow(member: member, index: admins.count + monitors.count + index)
                            }
                        } header: {
                            sectionHeader(title: L10n.t("المشرفين", "Supervisors"), icon: "star.fill", color: DS.Color.warning, count: supervisors.count)
                        }
                    }
                    // قسم الصلاحيات
                    Section {
                        permissionsGuide
                    } header: {
                        sectionHeader(title: L10n.t("الأدوار وما يقدر عليه كل دور", "Roles and what each can do"), icon: "person.badge.key.fill", color: DS.Color.info, count: nil)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .sheet(item: $selectedRoleGuide) { guide in
                    roleDetailSheet(guide)
                }
            }
        }
        .navigationTitle(L10n.t("فريق الإدارة", "Admin Team"))
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
                    .accessibilityLabel(L10n.t("إضافة", "Add"))
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
        .dsAlert(
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
            let roleName: String = {
                switch pendingRole {
                case .admin: return L10n.t("مدير", "Admin")
                case .monitor: return L10n.t("مراقب", "Monitor")
                case .supervisor: return L10n.t("مشرف", "Supervisor")
                default: return L10n.t("عضو", "Member")
                }
            }()
            Text(L10n.t(
                "تغيير مستوى حساب \(member.firstName) إلى \(roleName)؟",
                "Change \(member.firstName)'s account level to \(roleName)?"
            ))
        }
        .dsAlert(
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
        .sheet(item: $roleChangeTarget) { member in
            ChangeRoleSheet(member: member) { newRole in
                Task { await memberVM.updateMemberRole(memberId: member.id, newRole: newRole) }
            }
            .environmentObject(authVM)
            .environmentObject(memberVM)
        }
        .task { usageStats = await AppUsageStats.fetch() }
        .onAppear {
            Task { await memberVM.fetchAllMembers(force: true) }
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Section Header
    private func sectionHeader(title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            if let count {
                Text("(\(count))")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .textCase(nil)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Moderator Row
    private func moderatorRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                let roleColor = (member.role == .owner || member.role == .admin) ? DS.Color.neonPurple : (member.role == .monitor ? DS.Color.monitorRole : DS.Color.warning)
                let roleIcon = (member.role == .owner || member.role == .admin) ? "shield.fill" : (member.role == .monitor ? "eye.fill" : "star.fill")

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
                Text(member.displayFullName)
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
                        // المالك يظهر بنفس لون المدير — لا يتميّز عنه بصرياً
                        .background(member.role == .owner ? FamilyMember.UserRole.admin.color : member.role.color)
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
                            .font(DS.Font.scaled(11))
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
        .contentShape(Rectangle())
        .onTapGesture {
            // تغيير الدور: اختيار مجال من ورقة واحدة — بدل ترقية/تنزيل بالسحب
            guard isOwner, member.id != authVM.currentUser?.id, member.role != .owner else { return }
            roleChangeTarget = member
        }
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
                    Label(L10n.t("إزالة", "Remove"), systemImage: "minus.circle.fill")
                }

                // تغيير الدور صار من ورقة «تغيير الدور» بالضغط على الصف
            }
        }
        .contextMenu {
            if isOwner && member.id != authVM.currentUser?.id && member.role != .owner {
                Button {
                    roleChangeTarget = member
                } label: {
                    Label(L10n.t("تغيير الدور", "Change role"), systemImage: "person.badge.key.fill")
                }
                Button(role: .destructive) {
                    memberToChange = member
                    showRemoveConfirm = true
                } label: {
                    Label(L10n.t("إزالة الصلاحية", "Remove role"), systemImage: "minus.circle.fill")
                }
            }
        }
    }


    // MARK: - دليل الأدوار — بطاقة لكل دور (تحديث الأدوار 2026-09-21)
    //
    // بدل جدول ✓/✕ طويل: لكل دور بطاقة فيها رمزه ولونه ومجاله، وقائمة
    // «يقدر» و«ما يقدر» بكلام واضح — ليعرف المالك ما الذي يمنحه بالضبط.

    private var permissionsGuide: some View {
        VStack(spacing: DS.Spacing.sm) {
            // ١) خريطة المجالات
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(RoleDomain.all.enumerated()), id: \.offset) { _, domain in
                    domainTile(domain)
                }
            }

            // ٢) صف مضغوط لكل دور — الضغط يفتح تفاصيله
            VStack(spacing: 0) {
                ForEach(Array(RoleGuide.all.enumerated()), id: \.offset) { index, guide in
                    Button { selectedRoleGuide = guide } label: {
                        roleCompactRow(guide)
                    }
                    .buttonStyle(.plain)

                    if index < RoleGuide.all.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .dsSubtleShadow()
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private func domainTile(_ domain: RoleDomain) -> some View {
        VStack(spacing: 5) {
            Image(systemName: domain.icon)
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(domain.color)
            Text(domain.title)
                .font(DS.Font.plex(11, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(domain.roles.joined(separator: " · "))
                .font(DS.Font.plex(10, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, 4)
        .background(domain.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(domain.color.opacity(0.25), lineWidth: 1)
        )
    }

    /// صف الدور: شارة + اسم + مجاله + عدد من يحملونه
    private func roleCompactRow(_ guide: RoleGuide) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(guide.color.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: guide.icon)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(guide.color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(guide.title)
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(guide.mandate)
                    .font(DS.Font.plex(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // العضو: عدد الأحياء في الشجرة لا يعني أنهم يستخدمون التطبيق
                if guide.title == L10n.t("العضو", "Member"), let usage = usageStats {
                    Text(L10n.t("فعّالون (رقم + جهاز): \(usage.active)",
                                "Active (phone + device): \(usage.active)"))
                        .font(DS.Font.plex(10, weight: .semibold))
                        .foregroundColor(DS.Color.success)
                }
            }
            Spacer(minLength: 0)
            if let count = holdersCount(for: guide.title), count > 0 {
                Text("\(count)")
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(guide.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(guide.color.opacity(0.14)))
            }
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
    }

    /// عدد من يحملون هذا الدور
    private func holdersCount(for title: String) -> Int? {
        let all = memberVM.allMembers.filter { $0.isDeceased != true }
        switch title {
        case L10n.t("المالك", "Owner"):      return all.filter { $0.role == .owner }.count
        case L10n.t("المدير", "Admin"):      return all.filter { $0.role == .admin }.count
        case L10n.t("المراقب", "Monitor"):   return all.filter { $0.role == .monitor }.count
        case L10n.t("المشرف", "Supervisor"): return all.filter { $0.role == .supervisor }.count
        // الأعضاء العاديون الأحياء فقط (طلب المالك) — كل من في الشجرة،
        // سواء فعّل حسابه أو لا. الأحياء كلهم = هذا العدد + فريق الإدارة.
        case L10n.t("العضو", "Member"):      return all.filter { $0.role == .member && $0.isDeceased != true }.count
        default: return nil
        }
    }

    /// ورقة تفاصيل الدور — عمودان قصيران: يقدر / ما يقدر
    private func roleDetailSheet(_ guide: RoleGuide) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    HStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle().fill(guide.color.opacity(0.18)).frame(width: 52, height: 52)
                            Image(systemName: guide.icon)
                                .font(DS.Font.scaled(22, weight: .bold))
                                .foregroundColor(guide.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guide.title)
                                .font(DS.Font.plex(19, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)
                            Text(guide.mandate)
                                .font(DS.Font.plex(12, weight: .medium))
                                .foregroundColor(DS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }

                    guideGroup(title: L10n.t("يقدر", "Can"), lines: guide.can,
                               icon: "checkmark.circle.fill", color: DS.Color.success)

                    if !guide.cannot.isEmpty {
                        guideGroup(title: L10n.t("ما يقدر", "Cannot"), lines: guide.cannot,
                                   icon: "xmark.circle.fill", color: DS.Color.textTertiary)
                    }
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(guide.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    DSToolbarCancelButton(title: L10n.t("إغلاق", "Close")) { selectedRoleGuide = nil }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func guideGroup(title: String, lines: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Font.plex(13, weight: .bold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    guideLine(line, icon: icon, color: color)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .dsSubtleShadow()
    }

    private func guideLine(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(DS.Font.plex(12, weight: .medium))
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        DSEmptyState(
            icon: "shield.fill",
            title: L10n.t("لا يوجد أعضاء في فريق الإدارة", "No admin team members"),
            buttonTitle: isOwner ? L10n.t("إضافة", "Add") : nil,
            buttonAction: isOwner ? { showAddSheet = true } : nil,
            style: .halo
        )
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
            .filter { $0.role == .member && $0.isDeceased != true && $0.status != .frozen }
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
                        Text(L10n.t("مراقب", "Monitor")).tag(FamilyMember.UserRole.monitor)
                        Text(L10n.t("مدير", "Admin")).tag(FamilyMember.UserRole.admin)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    // مجال الدور المختار — ليعرف من يمنح الدور ما الذي يمنحه بالضبط
                    if let guide = RoleGuide.forRole(selectedRole) {
                        RoleScopeCard(guide: guide, compact: true)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.sm)
                    }

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
                                            Text(member.displayFullName)
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
                                            .foregroundColor(selectedRole == .admin ? DS.Color.neonPurple : (selectedRole == .monitor ? DS.Color.monitorRole : DS.Color.warning))
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
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(22, weight: .medium))
                            .foregroundStyle(DS.Color.textTertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - ورقة تغيير الدور (طلب المالك)
//
// الدور صار مجال عمل لا درجة، فالتغيير صار اختيار مجال من بطاقات واضحة
// بدل أسهم «ترقية/تنزيل». كل خيار يعرض مجاله وأهم ما يقدر عليه.

struct ChangeRoleSheet: View {
    let member: FamilyMember
    /// يُستدعى عند التأكيد بالدور الجديد
    let onSelect: (FamilyMember.UserRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: FamilyMember.UserRole
    @State private var showConfirm = false

    private let options: [FamilyMember.UserRole] = [.admin, .monitor, .supervisor, .member]

    init(member: FamilyMember, onSelect: @escaping (FamilyMember.UserRole) -> Void) {
        self.member = member
        self.onSelect = onSelect
        _selected = State(initialValue: member.role)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        memberHeader

                        ForEach(options, id: \.self) { role in
                            if let guide = RoleGuide.forRole(role) {
                                Button { selected = role } label: {
                                    roleOption(role: role, guide: guide)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationTitle(L10n.t("تغيير الدور", "Change Role"))
            .navigationBarTitleDisplayMode(.inline)
            .dsSheetToolbar(
                confirm: L10n.t("حفظ", "Save"),
                disabled: selected == member.role,
                onConfirm: { showConfirm = true },
                onCancel: { dismiss() }
            )
            .dsAlert(L10n.t("تأكيد تغيير الدور", "Confirm Role Change"), isPresented: $showConfirm) {
                Button(L10n.t("تأكيد", "Confirm")) {
                    onSelect(selected)
                    dismiss()
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "\(member.firstName) يصير «\(roleTitle(selected))» — \(RoleGuide.forRole(selected)?.mandate ?? "")",
                    "\(member.firstName) becomes «\(roleTitle(selected))» — \(RoleGuide.forRole(selected)?.mandate ?? "")"
                ))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .presentationDragIndicator(.visible)
    }

    private var memberHeader: some View {
        HStack(spacing: DS.Spacing.md) {
            Group {
                if let avatar = member.avatarUrl, let url = URL(string: avatar) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { DS.Color.mutedBackground }
                } else {
                    ZStack {
                        DS.Color.primary.opacity(0.14)
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(18, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                    }
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayFullName)
                    .font(DS.Font.plex(15, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(L10n.t("دوره الحالي: ", "Current role: ") + roleTitle(member.role))
                    .font(DS.Font.plex(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .dsSubtleShadow()
    }

    private func roleOption(role: FamilyMember.UserRole, guide: RoleGuide) -> some View {
        let isSelected = selected == role
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle().fill(guide.color.opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: guide.icon)
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(guide.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(guide.title)
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(guide.mandate)
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(isSelected ? guide.color : DS.Color.textTertiary.opacity(0.5))
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("يقدر", "Can"))
                        .font(DS.Font.plex(11, weight: .bold))
                        .foregroundColor(DS.Color.success)
                    ForEach(guide.can, id: \.self) { text in
                        optionLine(text, icon: "checkmark.circle.fill", color: DS.Color.success)
                    }
                    if !guide.cannot.isEmpty {
                        Text(L10n.t("ما يقدر", "Cannot"))
                            .font(DS.Font.plex(11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, 2)
                        ForEach(guide.cannot, id: \.self) { text in
                            optionLine(text, icon: "xmark.circle.fill", color: DS.Color.textTertiary.opacity(0.8))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? guide.color.opacity(0.08) : DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? guide.color.opacity(0.45) : DS.Color.textTertiary.opacity(0.15),
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .animation(DS.Anim.snappy, value: selected)
    }

    private func optionLine(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(DS.Font.plex(11.5, weight: .medium))
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func roleTitle(_ role: FamilyMember.UserRole) -> String {
        RoleGuide.forRole(role)?.title ?? L10n.t("عضو", "Member")
    }
}
