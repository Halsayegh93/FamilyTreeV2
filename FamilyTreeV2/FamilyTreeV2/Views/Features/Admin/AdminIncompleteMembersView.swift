import SwiftUI

struct AdminIncompleteMembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: IncompleteFilter = .all

    enum IncompleteFilter: String, CaseIterable {
        case all, noPhone, noBirthDate, noFather, noGender

        var label: String {
            switch self {
            case .all:         return L10n.t("الكل", "All")
            case .noPhone:     return L10n.t("بدون جوال", "No Phone")
            case .noBirthDate: return L10n.t("بدون ميلاد", "No Birth Date")
            case .noFather:    return L10n.t("بدون أب", "No Father")
            case .noGender:    return L10n.t("بدون جنس", "No Gender")
            }
        }

        var icon: String {
            switch self {
            case .all:         return "checklist"
            case .noPhone:     return "phone.badge.plus"
            case .noBirthDate: return "calendar.badge.exclamationmark"
            case .noFather:    return "person.line.dotted.person"
            case .noGender:    return "person.fill.questionmark"
            }
        }

        var color: Color {
            switch self {
            case .all:         return DS.Color.primary
            case .noPhone:     return DS.Color.error
            case .noBirthDate: return DS.Color.warning
            case .noFather:    return DS.Color.info
            case .noGender:    return DS.Color.neonPurple
            }
        }
    }

    // MARK: - Incomplete Members Logic

    /// Returns members (non-pending, non-deceased) with at least one missing field
    private var allIncompleteMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { memberHasIncompleteData($0) }
            .sorted { $0.fullName < $1.fullName }
    }

    private var filteredMembers: [FamilyMember] {
        var members = allIncompleteMembers

        // Apply category filter
        switch selectedFilter {
        case .all:         break
        case .noPhone:     members = members.filter { isMissingPhone($0) }
        case .noBirthDate: members = members.filter { isMissingBirthDate($0) }
        case .noFather:    members = members.filter { isMissingFather($0) }
        case .noGender:    members = members.filter { isMissingGender($0) }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }

        return members
    }

    // MARK: - Missing Data Checks

    private func isMissingPhone(_ m: FamilyMember) -> Bool {
        m.phoneNumber == nil || (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMissingBirthDate(_ m: FamilyMember) -> Bool {
        m.birthDate == nil || (m.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMissingFather(_ m: FamilyMember) -> Bool {
        m.fatherId == nil
    }

    private func isMissingGender(_ m: FamilyMember) -> Bool {
        m.gender == nil || (m.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func memberHasIncompleteData(_ m: FamilyMember) -> Bool {
        isMissingPhone(m) || isMissingBirthDate(m) || isMissingFather(m) || isMissingGender(m)
    }

    private func missingFields(for m: FamilyMember) -> [IncompleteFilter] {
        var missing: [IncompleteFilter] = []
        if isMissingPhone(m)     { missing.append(.noPhone) }
        if isMissingBirthDate(m) { missing.append(.noBirthDate) }
        if isMissingFather(m)    { missing.append(.noFather) }
        if isMissingGender(m)    { missing.append(.noGender) }
        return missing
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if allIncompleteMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Stats summary
                    statsSummary
                        .padding(.top, DS.Spacing.sm)

                    // Filter chips
                    filterChips
                        .padding(.vertical, DS.Spacing.sm)

                    // Search bar
                    searchBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)

                    if filteredMembers.isEmpty {
                        noResultsState
                    } else {
                        List {
                            ForEach(Array(filteredMembers.enumerated()), id: \.element.id) { index, member in
                                NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                                    memberRow(member: member, index: index)
                                }
                                .buttonStyle(DSBoldButtonStyle())
                                .listRowBackground(DS.Color.surface)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("بيانات ناقصة", "Incomplete Data"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await memberVM.fetchAllMembers() }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Stats Summary
    private var statsSummary: some View {
        HStack(spacing: DS.Spacing.sm) {
            miniStat(
                count: allIncompleteMembers.count,
                label: L10n.t("عضو ناقص", "Incomplete"),
                color: DS.Color.warning
            )
            miniStat(
                count: allIncompleteMembers.filter { isMissingPhone($0) }.count,
                label: L10n.t("بدون جوال", "No Phone"),
                color: DS.Color.error
            )
            miniStat(
                count: allIncompleteMembers.filter { isMissingFather($0) }.count,
                label: L10n.t("بدون أب", "No Father"),
                color: DS.Color.info
            )
            miniStat(
                count: allIncompleteMembers.filter { isMissingGender($0) }.count,
                label: L10n.t("بدون جنس", "No Gender"),
                color: DS.Color.neonPurple
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func miniStat(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Text("\(count)")
                .font(DS.Font.headline)
                .fontWeight(.black)
                .foregroundColor(color)
            Text(label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .glassCard(radius: DS.Radius.md)
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(IncompleteFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private func filterChip(_ filter: IncompleteFilter) -> some View {
        let isSelected = selectedFilter == filter
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
            }
            .foregroundColor(isSelected ? .white : filter.color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(isSelected ? filter.color : filter.color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(filter.color.opacity(0.3), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Search Bar
    private var searchBar: some View {
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
    }

    // MARK: - Member Row
    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar
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

                Text(String(member.fullName.prefix(1)))
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.warning)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)

                // Role badge
                DSRoleBadge(title: member.roleName, color: member.roleColor)

                // Missing fields tags
                let missing = missingFields(for: member)
                if !missing.isEmpty {
                    FlowLayout(spacing: DS.Spacing.xs) {
                        ForEach(missing, id: \.self) { field in
                            HStack(spacing: 2) {
                                Image(systemName: field.icon)
                                    .font(DS.Font.scaled(9, weight: .bold))
                                Text(field.label)
                                    .font(DS.Font.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(field.color)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(field.color.opacity(0.1))
                            .clipShape(Capsule())
                        }
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
        .padding(.vertical, DS.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.03), value: appeared)
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
            Text(L10n.t("جميع بيانات الأعضاء مكتملة", "All member data is complete"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    // MARK: - No Results State
    private var noResultsState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(DS.Font.scaled(36, weight: .bold))
                .foregroundColor(DS.Color.textTertiary.opacity(0.5))
            Text(L10n.t(
                "لا توجد نتائج",
                "No results found"
            ))
            .font(DS.Font.callout)
            .foregroundColor(DS.Color.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Flow Layout for Tags
/// A simple horizontal flow layout that wraps items to the next line
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
