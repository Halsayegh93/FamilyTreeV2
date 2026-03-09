import SwiftUI

// MARK: - Admin Members & Directory — سجل الأعضاء ودليل العائلة
struct AdminMembersDirectoryView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    enum Tab: String, CaseIterable {
        case registry, directory

        var label: String {
            switch self {
            case .registry: return L10n.t("سجل الأعضاء", "Registry")
            case .directory: return L10n.t("دليل العائلة", "Directory")
            }
        }
        var icon: String {
            switch self {
            case .registry: return "person.3.sequence.fill"
            case .directory: return "person.text.rectangle"
            }
        }
    }

    @State private var selectedTab: Tab = .registry
    @State private var searchText = ""

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: 0) {
                // شريط التابات
                tabBar

                // محتوى التاب
                switch selectedTab {
                case .registry:
                    RegistryTabContent(searchText: $searchText)
                case .directory:
                    DirectoryTabContent(searchText: $searchText)
                }
            }
        }
        .navigationTitle(L10n.t("الأعضاء", "Members"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(DS.Anim.snappy) { selectedTab = tab }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: tab.icon)
                            .font(DS.Font.scaled(12, weight: .bold))

                        Text(tab.label)
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        Capsule().fill(isSelected ? DS.Color.primary : DS.Color.surface)
                    )
                    .overlay(
                        Capsule().stroke(
                            isSelected ? DS.Color.primary : DS.Color.textTertiary.opacity(0.2),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }
}

// MARK: - Registry Tab (سجل الأعضاء — إدارة)
private struct RegistryTabContent: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Binding var searchText: String

    private var filteredMembers: [FamilyMember] {
        let members = memberVM.allMembers.filter { $0.role != .pending }
        if searchText.isEmpty {
            return members.sorted { $0.fullName < $1.fullName }
        } else {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                // إحصائيات
                statsSection
                    .padding(.top, DS.Spacing.md)

                // قائمة الأعضاء
                membersSection
            }
            .padding(.bottom, DS.Spacing.xxxl)
        }
    }

    // MARK: - Stats
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("إحصائيات", "Statistics"),
                    icon: "chart.bar.fill",
                    iconColor: DS.Color.primary
                )

                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    statCell(
                        icon: "person.2.fill",
                        color: DS.Color.primary,
                        title: L10n.t("إجمالي الأعضاء", "Total Members"),
                        value: "\(memberVM.allMembers.filter { $0.role != .pending }.count)"
                    )
                    statCell(
                        icon: "line.3.horizontal.decrease.circle.fill",
                        color: DS.Color.info,
                        title: L10n.t("نتائج البحث", "Search Results"),
                        value: "\(filteredMembers.count)"
                    )
                    statCell(
                        icon: "shield.fill",
                        color: DS.Color.warning,
                        title: L10n.t("مدراء ومشرفين", "Admins & Supervisors"),
                        value: "\(memberVM.allMembers.filter { $0.role == .admin || $0.role == .supervisor }.count)"
                    )
                    statCell(
                        icon: "person.fill.checkmark",
                        color: DS.Color.success,
                        title: L10n.t("أعضاء فعالين", "Active Members"),
                        value: "\(memberVM.allMembers.filter { $0.status == .active }.count)"
                    )
                }
                .padding(DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func statCell(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)

                Text(value)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Members List
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("الأعضاء", "Members"),
                    icon: "person.3.sequence.fill",
                    trailing: "\(filteredMembers.count)",
                    iconColor: DS.Color.success
                )

                // Search bar
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("magnifyingglass", color: DS.Color.primary)

                    TextField(L10n.t("ابحث بالاسم أو رقم الهاتف...", "Search by name or phone..."), text: $searchText)
                        .font(DS.Font.body)
                        .multilineTextAlignment(.leading)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)

                DSDivider()

                // Members list
                if filteredMembers.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.fill.questionmark")
                            .font(DS.Font.scaled(32))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أعضاء بهذا البحث", "No members found"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xl)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMembers) { member in
                            NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                                registryMemberRow(member: member)
                            }
                            .buttonStyle(DSBoldButtonStyle())

                            if member.id != filteredMembers.last?.id {
                                DSDivider()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func registryMemberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(member.roleColor.opacity(0.12))
                    .frame(width: 42, height: 42)

                Text(String(member.fullName.prefix(1)))
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(member.roleColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                HStack(spacing: DS.Spacing.sm) {
                    DSRoleBadge(title: member.roleName, color: member.roleColor)

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        Text(KuwaitPhone.display(phone))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 26, height: 26)
                .background(DS.Color.textTertiary.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: - Directory Tab (دليل العائلة — تصفح)
private struct DirectoryTabContent: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Binding var searchText: String

    @State private var sortOption: SortOption = .name
    @State private var filterRole: FamilyMember.UserRole? = nil
    @State private var showDeceasedOnly = false
    @State private var selectedMember: FamilyMember? = nil

    @State private var cachedFilteredMembers: [FamilyMember] = []
    @State private var cachedMembersByLetter: [(String, [FamilyMember])] = []

    enum SortOption: String, CaseIterable {
        case name, role, newest
        var label: String {
            switch self {
            case .name: return L10n.t("الاسم", "Name")
            case .role: return L10n.t("الدور", "Role")
            case .newest: return L10n.t("الأحدث", "Newest")
            }
        }
        var icon: String {
            switch self {
            case .name: return "textformat"
            case .role: return "shield.fill"
            case .newest: return "clock.fill"
            }
        }
    }

    private func rebuildFilteredMembers() {
        var members = memberVM.allMembers.filter {
            $0.role != .pending && !$0.isHiddenFromTree
        }

        // فلتر البحث
        if !searchText.isEmpty {
            let folded = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            members = members.filter {
                $0.fullName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(folded) ||
                $0.firstName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(folded)
            }
        }

        // فلتر الدور
        if let role = filterRole {
            members = members.filter { $0.role == role }
        }

        // فلتر المتوفين
        if showDeceasedOnly {
            members = members.filter { $0.isDeceased ?? false }
        }

        // الترتيب
        switch sortOption {
        case .name:
            members.sort { $0.firstName < $1.firstName }
        case .role:
            members.sort { $0.role.rawValue < $1.role.rawValue }
        case .newest:
            members.sort { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        }

        cachedFilteredMembers = members

        // تجميع حسب الحرف
        if sortOption == .name {
            let grouped = Dictionary(grouping: members) { member -> String in
                let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(first.prefix(1)).uppercased()
            }
            cachedMembersByLetter = grouped.sorted { $0.key < $1.key }
        } else {
            cachedMembersByLetter = [("", members)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // شريط البحث
            directorySearchBar

            // الفلاتر
            filterBar

            // عدد النتائج
            HStack {
                Text("\(cachedFilteredMembers.count) " + L10n.t("عضو", "members"))
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)

            // قائمة الأعضاء
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(cachedMembersByLetter, id: \.0) { letter, members in
                        if sortOption == .name && !letter.isEmpty {
                            Section {
                                ForEach(members) { member in
                                    directoryMemberRow(member)
                                }
                            } header: {
                                sectionHeader(letter)
                            }
                        } else {
                            ForEach(members) { member in
                                directoryMemberRow(member)
                            }
                        }
                    }
                }
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .sheet(item: $selectedMember) { member in
            MemberDetailsView(member: member)
                .presentationDetents([.medium, .large])
        }
        .onAppear { rebuildFilteredMembers() }
        .onChange(of: searchText) { _, _ in rebuildFilteredMembers() }
        .onChange(of: sortOption) { _, _ in rebuildFilteredMembers() }
        .onChange(of: filterRole) { _, _ in rebuildFilteredMembers() }
        .onChange(of: showDeceasedOnly) { _, _ in rebuildFilteredMembers() }
        .onChange(of: memberVM.allMembers.count) { _, _ in rebuildFilteredMembers() }
    }

    // MARK: - Search Bar
    private var directorySearchBar: some View {
        HStack(spacing: DS.Spacing.md - 2) {
            Image(systemName: "magnifyingglass")
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(DS.Color.primary)

            TextField(L10n.t("ابحث بالاسم...", "Search by name..."), text: $searchText)
                .font(DS.Font.body)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(16))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(DS.Opacity.border), lineWidth: 1)
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: - Filter Bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                // ترتيب
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            withAnimation { sortOption = option }
                        } label: {
                            Label(option.label, systemImage: option.icon)
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(DS.Font.scaled(10, weight: .semibold))
                        Text(sortOption.label)
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Color.primary.opacity(0.2), lineWidth: 1))
                }

                // فلتر الأدوار
                ForEach([FamilyMember.UserRole.admin, .supervisor, .member], id: \.self) { role in
                    let isActive = filterRole == role
                    Button {
                        withAnimation { filterRole = isActive ? nil : role }
                    } label: {
                        Text(roleName(role))
                            .font(DS.Font.scaled(11, weight: .semibold))
                            .foregroundColor(isActive ? .white : DS.Color.textSecondary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(Capsule().fill(isActive ? role.color : DS.Color.surface))
                            .overlay(Capsule().stroke(isActive ? role.color : DS.Color.textTertiary.opacity(DS.Opacity.border), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // فلتر المتوفين
                Button {
                    withAnimation { showDeceasedOnly.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: showDeceasedOnly ? "checkmark.circle.fill" : "circle")
                            .font(DS.Font.scaled(10))
                        Text(L10n.t("المتوفين", "Deceased"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                    .foregroundColor(showDeceasedOnly ? .white : DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(Capsule().fill(showDeceasedOnly ? DS.Color.deceased : DS.Color.surface))
                    .overlay(Capsule().stroke(showDeceasedOnly ? DS.Color.deceased : DS.Color.textTertiary.opacity(DS.Opacity.border), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    // MARK: - Section Header
    private func sectionHeader(_ letter: String) -> some View {
        HStack {
            Text(letter)
                .font(DS.Font.scaled(13, weight: .black))
                .foregroundColor(DS.Color.primary)
                .frame(width: 28, height: 28)
                .background(DS.Color.primary.opacity(0.1))
                .clipShape(Circle())

            Rectangle()
                .fill(DS.Color.primary.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.background.opacity(0.95))
    }

    // MARK: - Member Row
    private func directoryMemberRow(_ member: FamilyMember) -> some View {
        Button {
            selectedMember = member
        } label: {
            HStack(spacing: DS.Spacing.md) {
                // صورة
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [member.roleColor, member.roleColor.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Text(String(member.firstName.prefix(1)))
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(DS.Color.textOnPrimary)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Text(String(member.firstName.prefix(1)))
                            .font(DS.Font.scaled(18, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }

                    if member.isDeceased ?? false {
                        VStack {
                            Spacer()
                            HStack { Spacer()
                                Circle()
                                    .fill(DS.Color.deceased)
                                    .frame(width: 13, height: 13)
                                    .overlay(
                                        Image(systemName: "heart.slash.fill")
                                            .font(DS.Font.scaled(7, weight: .bold))
                                            .foregroundColor(DS.Color.textOnPrimary)
                                    )
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.sm) {
                        // شارة الدور
                        HStack(spacing: 3) {
                            Circle()
                                .fill(member.roleColor)
                                .frame(width: 6, height: 6)
                            Text(member.roleName)
                                .font(DS.Font.scaled(10, weight: .semibold))
                                .foregroundColor(member.roleColor)
                        }

                        if let phone = member.phoneNumber, !phone.isEmpty, !(member.isPhoneHidden ?? false) {
                            Text("•")
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary)
                            Text(KuwaitPhone.display(phone))
                                .font(DS.Font.scaled(10))
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // زر اتصال
                if let phone = member.phoneNumber, !phone.isEmpty,
                   !(member.isPhoneHidden ?? false),
                   let callURL = KuwaitPhone.telURL(phone) {
                    Button {
                        UIApplication.shared.open(callURL)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.success)
                            .frame(width: 34, height: 34)
                            .background(DS.Color.success.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func roleName(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .admin: return L10n.t("مدير", "Admin")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلق", "Pending")
        }
    }
}
