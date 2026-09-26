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
                // تفاصيل الدور — مربّع عرض بمنتصف الشاشة (يُغلق أيضاً بالضغط خارجه)
                .dsCenterBox(item: $selectedRoleGuide, onBackgroundTap: { selectedRoleGuide = nil }) { guide in
                    roleDetailBox(guide)
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
        .dsTallBox(isPresented: $showAddSheet, onDismiss: {   // قائمة أعضاء طويلة (توصية أبل)
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
        .dsCenterBox(item: $roleChangeTarget) { member in
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

    /// تفاصيل الدور — مربّع عرض بمنتصف الشاشة بتصميم المربّعات الموحّد:
    /// الرأس يحمل رمز الدور واسمه ومجاله، ثم قسما «يقدر» و«ما يقدر»، و«إغلاق» أسفله
    private func roleDetailBox(_ guide: RoleGuide) -> some View {
        DSComposer(
            title: guide.title,
            subtitle: guide.mandate,
            icon: guide.icon,
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { selectedRoleGuide = nil }
        ) {
            guideSection(title: L10n.t("يقدر", "Can"), lines: guide.can, allowed: true, index: 0)

            if !guide.cannot.isEmpty {
                guideSection(title: L10n.t("ما يقدر", "Cannot"), lines: guide.cannot, allowed: false, index: 1)
            }
        }
    }

    /// قسم «يقدر» أو «ما يقدر» — الأسطر داخل صندوق صف المربّعات
    private func guideSection(title: String, lines: [String], allowed: Bool, index: Int) -> some View {
        DSComposerSection(title: title,
                          icon: allowed ? "checkmark.circle.fill" : "xmark.circle.fill",
                          tint: allowed ? DS.Color.success : DS.Color.textTertiary,
                          index: index) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    RoleScopeLineRow(text: line, allowed: allowed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()
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
//
// مربّع بمنتصف الشاشة بتصميم مربّعات الإضافة (طلب المالك): قسم «الدور» (مبدّل
// مشرف/مراقب/مدير + مجال الدور المختار) ثم قسم «العضو» (بحث + صفوف بعلامة اختيار)،
// و«إضافة» كحلي يمين / «إلغاء» رمادي يسار.
struct AddModeratorSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    /// «تقليل الحركة» (توصية أبل): مؤشّر الدور ينتقل مباشرة بلا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedRole: FamilyMember.UserRole = .supervisor
    /// العضو المختار — يُعيَّن بالدور عند الضغط على «إضافة»
    @State private var selectedMember: FamilyMember?
    @State private var isSaving = false
    @State private var filterCache = RegularMembersCache()
    @Namespace private var roleNS

    /// نفس ترتيب المبدّل السابق: مشرف، مراقب، مدير
    private let roleOptions: [FamilyMember.UserRole] = [.supervisor, .monitor, .admin]

    /// نفس التصفية والترتيب — مع حفظ النتيجة حتى يتغيّر الأعضاء أو نص البحث:
    /// القائمة ~٢٤٠٠ عضو، والمربّع يُعاد رسمه كلما تغيّر ارتفاع القائمة الكسولة أثناء التمرير
    private var regularMembers: [FamilyMember] {
        let all = memberVM.allMembers
        if let cached = filterCache.result(for: all, query: searchText) { return cached }
        let result = all
            .filter { $0.role == .member && $0.isDeceased != true && $0.status != .frozen }
            .filter { member in
                searchText.isEmpty || member.fullName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.fullName < $1.fullName }
        filterCache.store(result, for: all, query: searchText)
        return result
    }

    var body: some View {
        DSComposer(
            title: L10n.t("إضافة مدير/مشرف", "Add Admin/Supervisor"),
            subtitle: L10n.t("اختر الدور ثم العضو", "Choose a role, then a member"),
            icon: "person.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            actionIcon: "plus",
            canSubmit: selectedMember != nil,
            isBusy: isSaving,
            // من سيُمنح الدور — ظاهر دائماً فوق الزر حتى لو خرج العضو من نتائج البحث
            note: selectedMember.map { "\($0.displayFullName) ← \(roleLabel(selectedRole))" },
            // عضو مختار ولم يُعيَّن بعد → «إلغاء» يسأل قبل التجاهل، ولا يُسحب المربّع الطويل
            hasUnsavedChanges: selectedMember != nil,
            onSubmit: assignRole,
            onCancel: { dismiss() }
        ) {
            roleSection
            memberSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: الدور

    private var roleSection: some View {
        DSComposerSection(title: L10n.t("الدور", "Role"), icon: "person.badge.key.fill",
                          tint: DS.Color.primary, index: 0) {
            // اختيار مستوى الحساب
            HStack(spacing: 4) {
                ForEach(roleOptions, id: \.self) { role in
                    roleOption(role)
                }
            }
            // الخيار ٤٤ ضغطاً و٤٠ شكلاً — الهامش العمودي ٢ + نقطتا الضغط = نفس الإطار السابق (٤)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.14), lineWidth: 1))

            // مجال الدور المختار — ليعرف من يمنح الدور ما الذي يمنحه بالضبط
            // (ZStack: القديم والجديد يتداخلان أثناء التلاشي بدل أن يتكدّسا)
            if let guide = RoleGuide.forRole(selectedRole) {
                ZStack(alignment: .top) {
                    RoleScopeRowBox(guide: guide)
                        .id(selectedRole)
                        .transition(.opacity)
                }
            }
        }
    }

    private func roleOption(_ role: FamilyMember.UserRole) -> some View {
        let isSelected = selectedRole == role
        let guide = RoleGuide.forRole(role)
        return Button {
            guard selectedRole != role else { return }
            if reduceMotion {
                selectedRole = role   // «تقليل الحركة»: المؤشّر يظهر في مكانه مباشرة
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selectedRole = role }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: guide?.icon ?? "person.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(isSelected ? .white : (guide?.color ?? DS.Color.primary))
                    .accessibilityHidden(true)
                Text(roleLabel(role))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DSActionFill.style())
                        .matchedGeometryEffect(id: "role-pill", in: roleNS)
                }
            }
            // مساحة ضغط ٤٤ (توصية أبل) — المؤشّر الظاهر ٤٠ كما هو
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// نفس أسماء المبدّل السابق
    private func roleLabel(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .admin: return L10n.t("مدير", "Admin")
        case .monitor: return L10n.t("مراقب", "Monitor")
        default: return L10n.t("مشرف", "Supervisor")
        }
    }

    // MARK: العضو

    private var memberSection: some View {
        let members = regularMembers
        return DSComposerSection(title: L10n.t("العضو", "Member"), icon: "person.fill",
                                 tint: DS.Color.primary, trailing: selectedMember?.firstName, index: 1) {
            // البحث
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("بحث عن عضو...", "Search member..."),
                            text: $searchText)

            if members.isEmpty {
                emptyMembers
            } else {
                // كسولة — قائمة الأعضاء قد تكون طويلة
                LazyVStack(spacing: DS.Spacing.sm) {
                    ForEach(members) { member in
                        memberRow(member)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        let isSelected = selectedMember?.id == member.id
        return Button {
            selectedMember = member
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill", tint: DS.Color.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayFullName)
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.plex(12))
                            .foregroundColor(DS.Color.fieldValue)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 0)

                // للعين فقط — «محدّد» يُعلن من صفة isSelected
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textTertiary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyMembers: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "person.slash")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.t("لا يوجد أعضاء", "No members found"))
                .font(DS.Font.plex(13, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .dsRowBox()
    }

    // MARK: التعيين — نفس الاستدعاء ثم الإغلاق

    private func assignRole() {
        guard let member = selectedMember, !isSaving else { return }
        isSaving = true
        Task {
            await memberVM.updateMemberRole(memberId: member.id, newRole: selectedRole)
            isSaving = false
            dismiss()
        }
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
        // نفس هيكل المربّعات الموحّد (طلب المالك): العضو، ثم بطاقات الأدوار كصفوف
        // بعلامة اختيار — المختارة تعرض كل «يقدر» و«ما يقدر» — ثم «حفظ» يطلب التأكيد
        DSComposer(
            title: L10n.t("تغيير الدور", "Change Role"),
            subtitle: member.displayFullName,
            icon: "person.badge.key.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: selected != member.role,
            // دور مختار غير دوره الحالي ولم يُحفظ → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: selected != member.role,
            onSubmit: { showConfirm = true },
            onCancel: { dismiss() }
        ) {
            memberSection
            rolesSection
        }
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

    // MARK: العضو ودوره الحالي

    private var memberSection: some View {
        DSComposerSection(title: L10n.t("العضو", "Member"), icon: "person.fill",
                          tint: DS.Color.primary, index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                memberAvatar
                    .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayFullName)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                    Text(L10n.t("دوره الحالي: ", "Current role: ") + roleTitle(member.role))
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    private var memberAvatar: some View {
        Group {
            if let avatar = member.avatarUrl, let url = URL(string: avatar) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { DS.Color.mutedBackground }
            } else {
                ZStack {
                    DS.Color.primary.opacity(0.14)
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // MARK: بطاقات الأدوار

    private var rolesSection: some View {
        DSComposerSection(title: L10n.t("اختر الدور", "Choose a role"), icon: "person.badge.key.fill",
                          tint: DS.Color.primary, index: 1) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(options, id: \.self) { role in
                    if let guide = RoleGuide.forRole(role) {
                        Button { selected = role } label: {
                            roleOption(role: role, guide: guide)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == role ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// بطاقة دور بشكل صفوف المربّعات: رمز الدور + اسمه + مجاله + علامة اختيار،
    /// والمختارة تتوسّع بكل ما يقدر عليه وما لا يقدر
    private func roleOption(role: FamilyMember.UserRole, guide: RoleGuide) -> some View {
        let isSelected = selected == role
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: guide.icon, tint: guide.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.title)
                        .font(DS.Font.plex(13.5, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(guide.mandate)
                        .font(DS.Font.plex(12.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                // للعين فقط — «محدّد» يُعلن من صفة isSelected على البطاقة
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? guide.color : DS.Color.textTertiary.opacity(0.5))
                    .accessibilityHidden(true)
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 5) {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(0.12))
                        .frame(height: 1)
                        .padding(.bottom, 3)
                    scopeCaption(L10n.t("يقدر", "Can"), color: DS.Color.success)
                    ForEach(guide.can, id: \.self) { text in
                        RoleScopeLineRow(text: text, allowed: true)
                    }
                    if !guide.cannot.isEmpty {
                        scopeCaption(L10n.t("ما يقدر", "Cannot"), color: DS.Color.textTertiary)
                            .padding(.top, 2)
                        ForEach(guide.cannot, id: \.self) { text in
                            RoleScopeLineRow(text: text, allowed: false)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(guide.color.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .animation(DS.Anim.snappy, value: selected)
    }

    private func scopeCaption(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DS.Font.plex(12, weight: .heavy))
            .foregroundColor(color)
    }

    private func roleTitle(_ role: FamilyMember.UserRole) -> String {
        RoleGuide.forRole(role)?.title ?? L10n.t("عضو", "Member")
    }
}

// MARK: - ذاكرة تصفية الأعضاء (خاصة بهذا الملف)

/// آخر نتيجة لتصفية «الأعضاء العاديين» — تُعاد فقط إذا تغيّرت مصفوفة الأعضاء أو نص البحث.
/// مقارنة المصفوفة فورية ما دامت لم تتغيّر (نفس التخزين)، وعنصراً بعنصر عند أي تعديل.
private final class RegularMembersCache {
    private var source: [FamilyMember] = []
    private var query: String?
    private var cached: [FamilyMember] = []

    func result(for members: [FamilyMember], query: String) -> [FamilyMember]? {
        guard self.query == query, source == members else { return nil }
        return cached
    }

    func store(_ result: [FamilyMember], for members: [FamilyMember], query: String) {
        source = members
        self.query = query
        cached = result
    }
}

// MARK: - أسطر مجال الدور بخط المربّعات (خاصة بهذا الملف)

/// سطر «يقدر» / «ما يقدر» — نصوص `RoleGuide` نفسها
private struct RoleScopeLineRow: View {
    let text: String
    let allowed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary.opacity(0.8))
                .padding(.top, 2)
            Text(text)
                .font(DS.Font.plex(12.5))
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // القارئ الصوتي: العلامة (✓/✗) تحمل المعنى — تُقرأ «يقدر: …» أو «ما يقدر: …» سطراً واحداً
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((allowed ? L10n.t("يقدر", "Can") : L10n.t("ما يقدر", "Cannot")) + ": " + text)
    }
}

/// مجال الدور المختار في صندوق صف — المختصر نفسه الذي كان في `RoleScopeCard(compact:)`:
/// المجال، وأول سطرين «يقدر»، وأول «ما يقدر»
private struct RoleScopeRowBox: View {
    let guide: RoleGuide

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: guide.icon, tint: guide.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.title)
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(guide.mandate)
                        .font(DS.Font.plex(13.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(guide.can.prefix(2)), id: \.self) { text in
                    RoleScopeLineRow(text: text, allowed: true)
                }
                ForEach(Array(guide.cannot.prefix(1)), id: \.self) { text in
                    RoleScopeLineRow(text: text, allowed: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }
}
