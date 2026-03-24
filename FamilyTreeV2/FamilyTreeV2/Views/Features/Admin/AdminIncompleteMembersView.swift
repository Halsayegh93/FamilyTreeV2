import SwiftUI

struct AdminIncompleteMembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: IncompleteFilter = .noBirthDate
    @State private var isSelectionMode = false
    @State private var selectedMembers: Set<UUID> = []
    @State private var memberToEdit: FamilyMember?
    @State private var memberToDelete: FamilyMember?
    @State private var showDeleteConfirm = false
    @State private var showGenderConfirm = false
    @State private var pendingGender: String = "male"
    @State private var genderUpdateResult: String?
    @State private var showGenderResult = false
    @State private var displayLimit = 20

    enum IncompleteFilter: String, CaseIterable {
        case noBirthDate, noFather, noGender

        var label: String {
            switch self {
            case .noBirthDate: return L10n.t("بدون ميلاد", "No Birth Date")
            case .noFather:    return L10n.t("بدون أب", "No Father")
            case .noGender:    return L10n.t("بدون جنس", "No Gender")
            }
        }

        var icon: String {
            switch self {
            case .noBirthDate: return "calendar.badge.exclamationmark"
            case .noFather:    return "person.line.dotted.person"
            case .noGender:    return "person.fill.questionmark"
            }
        }

        var color: Color {
            switch self {
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
        case .noBirthDate: members = members.filter { isMissingBirthDate($0) }
        case .noFather:    members = members.filter { isMissingFather($0) }
        case .noGender:    members = members.filter { isMissingGender($0) }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
            }
        }

        return members
    }

    // MARK: - Missing Data Checks

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
        isMissingBirthDate(m) || isMissingFather(m) || isMissingGender(m)
    }

    private func missingFields(for m: FamilyMember) -> [IncompleteFilter] {
        var missing: [IncompleteFilter] = []
        if isMissingBirthDate(m) { missing.append(.noBirthDate) }
        if isMissingFather(m)    { missing.append(.noFather) }
        if isMissingGender(m)    { missing.append(.noGender) }
        return missing
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if allIncompleteMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Stats summary
                    statsSummary
                        .padding(.top, DS.Spacing.sm)

                    // Filter chips
                    filterChips
                        .padding(.vertical, DS.Spacing.xs)

                    // Search bar
                    searchBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)

                    if filteredMembers.isEmpty {
                        noResultsState
                    } else {
                        List {
                            let visible = Array(filteredMembers.prefix(displayLimit))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                                if isSelectionMode {
                                    Button {
                                        withAnimation(DS.Anim.snappy) {
                                            toggleSelection(member)
                                        }
                                    } label: {
                                        HStack(spacing: DS.Spacing.md) {
                                            selectionCheckbox(for: member)
                                            memberRow(member: member, index: index)
                                        }
                                    }
                                    .buttonStyle(DSScaleButtonStyle())
                                } else {
                                    NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                                        memberRow(member: member, index: index)
                                    }
                                    .buttonStyle(DSBoldButtonStyle())
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            memberToDelete = member
                                            showDeleteConfirm = true
                                        } label: {
                                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                        }
                                        Button {
                                            memberToEdit = member
                                        } label: {
                                            Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                                        }
                                        .tint(DS.Color.primary)
                                    }
                                }
                            }

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
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }

                    // Action bar when in selection mode
                    if isSelectionMode {
                        selectionActionBar
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !allIncompleteMembers.isEmpty {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedMembers.removeAll()
                            }
                        }
                    } label: {
                        Text(isSelectionMode
                             ? L10n.t("إلغاء", "Cancel")
                             : L10n.t("تحديد", "Select"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                    }
                }
            }
        }
        .sheet(item: $memberToEdit) { member in
            NavigationStack {
                AdminMemberDetailSheet(member: member)
            }
        }
        .alert(
            L10n.t("تأكيد تحديث الجنس", "Confirm Gender Update"),
            isPresented: $showGenderConfirm
        ) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(
                pendingGender == "male"
                    ? L10n.t("تعيين ذكر", "Set Male")
                    : L10n.t("تعيين أنثى", "Set Female")
            ) {
                let ids = selectedMembers
                let gender = pendingGender
                withAnimation(DS.Anim.snappy) {
                    selectedMembers.removeAll()
                    isSelectionMode = false
                }
                Task {
                    let count = await memberVM.bulkUpdateGender(memberIds: ids, gender: gender)
                    let genderText = gender == "male" ? L10n.t("ذكر", "male") : L10n.t("أنثى", "female")
                    genderUpdateResult = L10n.t(
                        "تم تحديث \(count) عضو إلى \(genderText)",
                        "Updated \(count) members to \(genderText)"
                    )
                    showGenderResult = true
                }
            }
        } message: {
            let genderText = pendingGender == "male" ? L10n.t("ذكر", "male") : L10n.t("أنثى", "female")
            Text(L10n.t(
                "هل تريد تعيين \(selectedMembers.count) عضو كـ \(genderText)؟",
                "Set \(selectedMembers.count) members as \(genderText)?"
            ))
        }
        .alert(L10n.t("تم التحديث", "Updated"), isPresented: $showGenderResult) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(genderUpdateResult ?? "")
        }
        .alert(
            L10n.t("حذف العضو نهائياً", "Delete Member Permanently"),
            isPresented: $showDeleteConfirm,
            presenting: memberToDelete
        ) { member in
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await memberVM.deleteMember(memberId: member.id) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "هل أنت متأكد من حذف \(member.fullName)؟ هذا الإجراء لا يمكن التراجع عنه.",
                "Are you sure you want to delete \(member.fullName)? This action cannot be undone."
            ))
        }
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
                label: L10n.t("إجمالي", "Total"),
                color: DS.Color.warning
            )
            miniStat(
                count: filteredMembers.count,
                label: selectedFilter.label,
                color: selectedFilter.color
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
                .font(DS.Font.caption1)
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
                displayLimit = 20
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: filter.icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                Text(filter.label)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : filter.color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
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
                .onChange(of: searchText) { displayLimit = 20 }
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
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.03), value: appeared)
    }

    // MARK: - Selection Helpers

    private func toggleSelection(_ member: FamilyMember) {
        if selectedMembers.contains(member.id) {
            selectedMembers.remove(member.id)
        } else {
            selectedMembers.insert(member.id)
        }
    }

    private func selectionCheckbox(for member: FamilyMember) -> some View {
        let isSelected = selectedMembers.contains(member.id)
        return ZStack {
            Circle()
                .stroke(isSelected ? DS.Color.primary : DS.Color.textTertiary, lineWidth: 2)
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(DS.Color.primary)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
        }
    }

    // MARK: - Selection Action Bar
    private var selectionActionBar: some View {
        VStack(spacing: DS.Spacing.sm) {
            // الصف الأول: تحديد الكل + العدد
            HStack(spacing: DS.Spacing.md) {
                Button {
                    withAnimation(DS.Anim.snappy) {
                        if selectedMembers.count == filteredMembers.count {
                            selectedMembers.removeAll()
                        } else {
                            selectedMembers = Set(filteredMembers.map(\.id))
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: selectedMembers.count == filteredMembers.count
                              ? "checklist.unchecked" : "checklist.checked")
                            .font(DS.Font.callout)
                        Text(selectedMembers.count == filteredMembers.count
                             ? L10n.t("إلغاء الكل", "Deselect All")
                             : L10n.t("تحديد الكل", "Select All"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.primary)
                }
                .buttonStyle(DSScaleButtonStyle())

                Spacer()

                if !selectedMembers.isEmpty {
                    Text(L10n.t(
                        "محدد: \(selectedMembers.count)",
                        "Selected: \(selectedMembers.count)"
                    ))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                }
            }

            // الصف الثاني: أزرار الإجراءات
            if !selectedMembers.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    // زر ذكر
                    Button {
                        pendingGender = "male"
                        showGenderConfirm = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.fill")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(L10n.t("ذكر", "Male"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSBoldButtonStyle())

                    // زر أنثى
                    Button {
                        pendingGender = "female"
                        showGenderConfirm = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "figure.stand.dress")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(L10n.t("أنثى", "Female"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.neonPink)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSBoldButtonStyle())

                    // زر تعديل فردي
                    Button {
                        if let firstSelectedId = selectedMembers.first,
                           let member = filteredMembers.first(where: { $0.id == firstSelectedId }) {
                            memberToEdit = member
                        }
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                            .background(DS.Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(
            DS.Color.surface
                .shadow(color: DS.Color.shadowMedium, radius: 8, y: -2)
        )
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
            .font(DS.Font.title3)
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
