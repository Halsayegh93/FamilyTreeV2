import SwiftUI

struct AdminActivateAccountsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: InactiveFilter = .pending
    @State private var memberToActivate: FamilyMember?
    @State private var showActivateConfirm = false
    @State private var memberToEditPhone: FamilyMember?

    enum InactiveFilter: String, CaseIterable {
        case pending, notActivated

        var label: String {
            switch self {
            case .pending:      return L10n.t("معلق", "Pending")
            case .notActivated: return L10n.t("غير مفعل", "Not Activated")
            }
        }

        var icon: String {
            switch self {
            case .pending:      return "clock.badge.exclamationmark"
            case .notActivated: return "person.badge.minus"
            }
        }

        var color: Color {
            switch self {
            case .pending:      return DS.Color.warning
            case .notActivated: return DS.Color.textTertiary
            }
        }
    }

    // أعضاء بحالة nil أو pending (غير مفعلين) أو بدون رقم جوال - ليسوا بـ role pending - أحياء فقط
    private var allInactiveMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { member in
                let isNotActivated = member.status == nil || member.status == .pending
                let hasNoPhone = member.phoneNumber == nil || (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return isNotActivated || hasNoPhone
            }
            .sorted { $0.fullName < $1.fullName }
    }

    private var pendingMembers: [FamilyMember] {
        allInactiveMembers.filter { $0.status == .pending }
    }

    private var notActivatedMembers: [FamilyMember] {
        allInactiveMembers.filter { member in
            let statusNil = member.status == nil
            let hasNoPhone = member.phoneNumber == nil || (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return statusNil || hasNoPhone
        }
    }

    private var filteredMembers: [FamilyMember] {
        var members: [FamilyMember]
        switch selectedFilter {
        case .pending:      members = pendingMembers
        case .notActivated: members = notActivatedMembers
        }
        if searchText.isEmpty { return members }
        return members.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            if allInactiveMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // فلتر التصنيف
                    filterChips
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)

                    // عدد الأعضاء
                    HStack {
                        Text(L10n.t(
                            "\(filteredMembers.count) عضو",
                            "\(filteredMembers.count) members"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // البحث
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("بحث عن عضو...", "Search member..."), text: $searchText)
                            .font(DS.Font.callout)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xs)

                    if filteredMembers.isEmpty {
                        // لا توجد نتائج بحث
                        VStack(spacing: DS.Spacing.lg) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(DS.Font.scaled(36, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary.opacity(0.5))
                            Text(L10n.t(
                                "لا توجد نتائج لـ \"\(searchText)\"",
                                "No results for \"\(searchText)\""
                            ))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(Array(filteredMembers.enumerated()), id: \.element.id) { index, member in
                                memberRow(member: member, index: index)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
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
        .sheet(item: $memberToEditPhone) { member in
            EditPhoneSheet(member: member, memberVM: memberVM)
        }
        .onAppear {
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
                            colors: [DS.Color.warning.opacity(0.3), DS.Color.warning.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Text(member.fullName.prefix(1))
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.warning)
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
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(member.status == .pending ? DS.Color.warning : DS.Color.textTertiary)
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
                } else {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "phone.badge.plus")
                            .font(DS.Font.scaled(10))
                        Text(L10n.t("لا يوجد رقم جوال", "No phone number"))
                            .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.error.opacity(0.7))
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                memberToActivate = member
                showActivateConfirm = true
            } label: {
                Label(L10n.t("تفعيل", "Activate"), systemImage: "checkmark.circle.fill")
            }
            .tint(DS.Color.success)

            Button {
                memberToEditPhone = member
            } label: {
                Label(L10n.t("رقم الجوال", "Phone"), systemImage: "phone.badge.plus")
            }
            .tint(DS.Color.info)
        }
        .contextMenu {
            Button {
                memberToEditPhone = member
            } label: {
                Label(
                    (member.phoneNumber ?? "").isEmpty
                        ? L10n.t("إضافة رقم جوال", "Add Phone Number")
                        : L10n.t("تعديل رقم الجوال", "Edit Phone Number"),
                    systemImage: "phone.badge.plus"
                )
            }

            Divider()

            Button {
                memberToActivate = member
                showActivateConfirm = true
            } label: {
                Label(L10n.t("تفعيل الحساب", "Activate Account"), systemImage: "checkmark.circle.fill")
            }
        }
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(InactiveFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private func filterChip(_ filter: InactiveFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count: Int = {
            switch filter {
            case .pending:      return pendingMembers.count
            case .notActivated: return notActivatedMembers.count
            }
        }()
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: filter.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                Text(filter.label)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                Text("\(count)")
                    .font(DS.Font.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? filter.color : DS.Color.textOnPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? DS.Color.textOnPrimary.opacity(0.3) : filter.color.opacity(0.8))
                    .clipShape(Capsule())
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : filter.color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(isSelected ? filter.color : filter.color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : filter.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(DS.Color.success.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.shield.fill")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(DS.Color.success.opacity(0.5))
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
        await adminRequestVM.activateAccount(memberId: member.id)
    }
}

// MARK: - Edit Phone Sheet
struct EditPhoneSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var phoneInput: String
    @State private var isSaving = false
    @State private var showSuccess = false

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        _phoneInput = State(initialValue: member.phoneNumber ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.xl) {
                    // أيقونة
                    ZStack {
                        Circle()
                            .fill(DS.Color.info.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "phone.badge.plus")
                            .font(DS.Font.scaled(30, weight: .bold))
                            .foregroundColor(DS.Color.info)
                    }
                    .padding(.top, DS.Spacing.xl)

                    // اسم العضو
                    Text(member.fullName)
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    // حقل الرقم
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("رقم الجوال", "Phone Number"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        HStack(spacing: DS.Spacing.md) {
                            Image(systemName: "phone.fill")
                                .foregroundColor(DS.Color.textOnPrimary)
                                .font(DS.Font.scaled(14))
                                .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                .background(DS.Color.info)
                                .cornerRadius(DS.Radius.sm)

                            TextField(L10n.t("أدخل رقم الجوال", "Enter phone number"), text: $phoneInput)
                                .font(DS.Font.body)
                                .keyboardType(.phonePad)
                                .multilineTextAlignment(.leading)
                                .monospacedDigit()
                        }
                        .padding(DS.Spacing.md)
                        .background(DS.Color.surface)
                        .cornerRadius(DS.Radius.lg)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                .stroke(DS.Color.info.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // زر الحفظ
                    Button {
                        isSaving = true
                        Task {
                            await memberVM.updateMemberPhone(memberId: member.id, newPhone: phoneInput.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(L10n.t("حفظ", "Save"))
                                .fontWeight(.bold)
                        }
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.Color.inactive : DS.Color.primary)
                        .cornerRadius(DS.Radius.lg)
                    }
                    .disabled(phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer()
                }
            }
            .navigationTitle(L10n.t("تعديل رقم الجوال", "Edit Phone Number"))
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
