import SwiftUI

// MARK: - Admin Members Registry — سجل الأعضاء
struct AdminMembersDirectoryView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var searchText = ""
    @State private var displayLimit = 20
    @State private var appeared = false
    @State private var selectedFilter: RegistryFilter = .all
    @State private var memberToFreeze: FamilyMember?
    @State private var memberToActivate: FamilyMember?

    // MARK: - Filter

    enum RegistryFilter: String, CaseIterable {
        case all, living, deceased

        var label: String {
            switch self {
            case .all:      return L10n.t("الكل", "All")
            case .living:   return L10n.t("الأحياء", "Living")
            case .deceased: return L10n.t("المتوفين", "Deceased")
            }
        }

        var icon: String {
            switch self {
            case .all:      return "person.3.sequence.fill"
            case .living:   return "person.fill.checkmark"
            case .deceased: return "leaf.fill"
            }
        }

        var color: Color {
            switch self {
            case .all:      return DS.Color.primary
            case .living:   return DS.Color.success
            case .deceased: return DS.Color.textTertiary
            }
        }
    }

    // MARK: - Data

    private var baseMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending }
            .sorted { $0.fullName < $1.fullName }
    }

    private func count(for filter: RegistryFilter) -> Int {
        switch filter {
        case .all:      return baseMembers.count
        case .living:   return baseMembers.filter { $0.isDeceased != true }.count
        case .deceased: return baseMembers.filter { $0.isDeceased == true }.count
        }
    }

    private var filteredMembers: [FamilyMember] {
        var members: [FamilyMember]
        switch selectedFilter {
        case .all:      members = baseMembers
        case .living:   members = baseMembers.filter { $0.isDeceased != true }
        case .deceased: members = baseMembers.filter { $0.isDeceased == true }
        }
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }
        return members
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Filter chips
                filterChips
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                // Swipe hint
                if authVM.canEditMembers && selectedFilter != .deceased {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "hand.draw")
                            .font(DS.Font.scaled(10, weight: .medium))
                        Text(L10n.t(
                            "سحب يسار: تجميد / تفعيل الحساب",
                            "Swipe left: Freeze / Activate account"
                        ))
                        .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xs)
                }

                // Search bar
                searchBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xs)

                if filteredMembers.isEmpty {
                    noResultsState
                } else {
                    List {
                        let visible = Array(filteredMembers.prefix(displayLimit))
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                            NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                                memberRow(member: member, index: index)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: DS.Spacing.xs,
                                leading: DS.Spacing.lg,
                                bottom: DS.Spacing.xs,
                                trailing: DS.Spacing.lg
                            ))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if authVM.canEditMembers && member.isDeceased != true {
                                    if member.status == .frozen {
                                        Button {
                                            memberToActivate = member
                                        } label: {
                                            Label(L10n.t("تفعيل", "Activate"), systemImage: "lock.open.fill")
                                        }
                                        .tint(DS.Color.success)
                                    } else {
                                        Button {
                                            memberToFreeze = member
                                        } label: {
                                            Label(L10n.t("تجميد", "Freeze"), systemImage: "lock.fill")
                                        }
                                        .tint(DS.Color.error)
                                    }
                                }
                            }
                        }

                        // Load more
                        if displayLimit < filteredMembers.count {
                            Button {
                                displayLimit += 20
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(L10n.t(
                                        "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
                                        "Show more (\(filteredMembers.count - displayLimit) remaining)"
                                    ))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.primary)
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.sm)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .onAppear {
                withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
            }
        }
        // Freeze confirm
        .confirmationDialog(
            memberToFreeze.map {
                L10n.t("تجميد حساب \($0.fullName)؟", "Freeze \($0.fullName)'s account?")
            } ?? "",
            isPresented: Binding(
                get: { memberToFreeze != nil },
                set: { if !$0 { memberToFreeze = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let member = memberToFreeze {
                Button(L10n.t("تجميد الحساب", "Freeze Account"), role: .destructive) {
                    Task { await memberVM.setMemberStatus(memberId: member.id, status: .frozen) }
                    memberToFreeze = nil
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { memberToFreeze = nil }
        } message: {
            Text(L10n.t("لن يتمكن من الدخول للتطبيق.", "They won't be able to access the app."))
        }
        // Activate confirm
        .confirmationDialog(
            memberToActivate.map {
                L10n.t("تفعيل حساب \($0.fullName)؟", "Activate \($0.fullName)'s account?")
            } ?? "",
            isPresented: Binding(
                get: { memberToActivate != nil },
                set: { if !$0 { memberToActivate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let member = memberToActivate {
                Button(L10n.t("تفعيل الحساب", "Activate Account")) {
                    Task { await memberVM.setMemberStatus(memberId: member.id, status: .active) }
                    memberToActivate = nil
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { memberToActivate = nil }
        } message: {
            Text(L10n.t("سيتمكن من الدخول للتطبيق مجدداً.", "They will be able to access the app again."))
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(RegistryFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .onChange(of: selectedFilter) { _ in
            displayLimit = 20
            searchText = ""
        }
    }

    private func filterChip(_ filter: RegistryFilter) -> some View {
        let isSelected = selectedFilter == filter
        let chipCount = count(for: filter)
        return Button {
            withAnimation(DS.Anim.snappy) { selectedFilter = filter }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: filter.icon)
                    .font(DS.Font.scaled(11, weight: .semibold))
                Text(filter.label)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                if chipCount > 0 {
                    Text("\(chipCount)")
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? filter.color : DS.Color.textOnPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.28) : filter.color)
                        )
                }
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : filter.color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Capsule().fill(isSelected ? filter.color : filter.color.opacity(0.1)))
            .overlay(Capsule().stroke(isSelected ? Color.clear : filter.color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Member Row

    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(
                name: member.fullName,
                avatarUrl: member.avatarUrl,
                size: 50,
                roleColor: member.isDeceased == true ? DS.Color.textTertiary : member.roleColor
            )
            .overlay(alignment: .bottomTrailing) {
                if member.status == .frozen {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(DS.Color.error)
                        .clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                // Name + status badges
                HStack(spacing: DS.Spacing.xs) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(
                            member.isDeceased == true ? DS.Color.textTertiary :
                            member.status == .frozen ? DS.Color.textTertiary :
                            DS.Color.textPrimary
                        )
                        .lineLimit(2)

                    if member.isDeceased == true {
                        Text(L10n.t("متوفي", "Deceased"))
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.textTertiary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if member.status == .frozen {
                        Text(L10n.t("مجمّد", "Frozen"))
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.error)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.error.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Role badge
                DSRoleBadge(title: member.roleName, color: member.roleColor)

                // Phone
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
        .padding(.horizontal, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.03), value: appeared)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.Color.textTertiary)
            TextField(L10n.t("بحث بالاسم أو رقم الهاتف...", "Search by name or phone..."), text: $searchText)
                .font(DS.Font.callout)
                .onChange(of: searchText) { _ in displayLimit = 20 }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.lg)
    }

    // MARK: - Empty States

    private var noResultsState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "person.fill.questionmark")
                .font(DS.Font.scaled(32))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا يوجد نتائج", "No results found"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxxl)
    }
}
