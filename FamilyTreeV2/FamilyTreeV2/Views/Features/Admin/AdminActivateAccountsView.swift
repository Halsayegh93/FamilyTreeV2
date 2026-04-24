import SwiftUI

struct AdminActivateAccountsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @State private var appeared = false
    @State private var searchText = ""
    @State private var selectedFilter: MemberFilter = .notActivated
    @State private var memberToActivate: FamilyMember?
    @State private var showActivateConfirm = false
    @State private var memberToEditPhone: FamilyMember?
    @State private var memberToEditBirthDate: FamilyMember?

    // Selection mode for bulk gender update
    @State private var isSelectionMode = false
    @State private var selectedMembers: Set<UUID> = []
    @State private var memberToEdit: FamilyMember?
    @State private var showGenderConfirm = false
    @State private var pendingGender: String = "male"
    @State private var genderUpdateResult: String?
    @State private var showGenderResult = false
    @State private var displayLimit = 20

    // MARK: - Combined Filter

    enum MemberFilter: String, CaseIterable {
        case notActivated, noBirthDate, noFather, noGender

        /// الفلاتر الظاهرة حالياً — لتفعيل noGender أضفها هنا
        static let visible: [MemberFilter] = [.notActivated, .noBirthDate, .noFather]

        var label: String {
            switch self {
            case .notActivated: return L10n.t("بدون هاتف", "No Phone")
            case .noBirthDate:  return L10n.t("بدون ميلاد", "No Birth Date")
            case .noFather:     return L10n.t("بدون أب", "No Father")
            case .noGender:     return L10n.t("بدون جنس", "No Gender")
            }
        }

        var icon: String {
            switch self {
            case .notActivated: return "phone.badge.exclamationmark"
            case .noBirthDate:  return "calendar.badge.exclamationmark"
            case .noFather:     return "person.line.dotted.person"
            case .noGender:     return "person.fill.questionmark"
            }
        }

        var color: Color {
            switch self {
            case .notActivated: return DS.Color.error
            case .noBirthDate:  return DS.Color.warning
            case .noFather:     return DS.Color.info
            case .noGender:     return DS.Color.accent
            }
        }
    }

    // MARK: - Data

    /// All living non-pending members that have at least one issue
    private var allIssueMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending && $0.isDeceased != true }
            .filter { memberHasAnyIssue($0) }
            .sorted { $0.fullName < $1.fullName }
    }

    private func memberHasAnyIssue(_ m: FamilyMember) -> Bool {
        isNotActivated(m) || isMissingBirthDate(m) || isMissingFather(m) || isMissingGender(m)
    }

    // Individual checks
    private func isNotActivated(_ m: FamilyMember) -> Bool {
        // غير مفعّل = حالة pending، أو بدون رقم هاتف (ما يقدر يسجل دخول)
        m.status == nil || m.status == .pending || hasNoPhone(m)
    }

    private func hasNoPhone(_ m: FamilyMember) -> Bool {
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

    // Counts per filter
    private func count(for filter: MemberFilter) -> Int {
        allIssueMembers.filter { matches(member: $0, filter: filter) }.count
    }

    private func matches(member: FamilyMember, filter: MemberFilter) -> Bool {
        switch filter {
        case .notActivated: return isNotActivated(member)
        case .noBirthDate:  return isMissingBirthDate(member)
        case .noFather:     return isMissingFather(member)
        case .noGender:     return isMissingGender(member)
        }
    }

    private var filteredMembers: [FamilyMember] {
        var members = allIssueMembers.filter { matches(member: $0, filter: selectedFilter) }
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            members = members.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
        }
        return members
    }

    /// نوع المشكلة التفصيلية (لعرض التاقات على كل عضو)
    enum IssueTag: Hashable {
        case notActivated
        case noPhone
        case noBirthDate
        case noFather

        var label: String {
            switch self {
            case .notActivated: return L10n.t("بدون هاتف", "No Phone")
            case .noPhone:      return L10n.t("بدون هاتف", "No Phone")
            case .noBirthDate:  return L10n.t("بدون ميلاد", "No Birth Date")
            case .noFather:     return L10n.t("بدون أب", "No Father")
            }
        }

        var icon: String {
            switch self {
            case .notActivated: return "person.badge.minus"
            case .noPhone:      return "phone.badge.plus"
            case .noBirthDate:  return "calendar.badge.exclamationmark"
            case .noFather:     return "person.line.dotted.person"
            }
        }

        var color: Color {
            switch self {
            case .notActivated: return DS.Color.error
            case .noPhone:      return DS.Color.error
            case .noBirthDate:  return DS.Color.warning
            case .noFather:     return DS.Color.info
            }
        }
    }

    /// Returns all issue tags for a given member
    private func issueLabels(for m: FamilyMember) -> [IssueTag] {
        var issues: [IssueTag] = []
        // إذا pending وعنده هاتف → tag "غير مفعل" فقط
        // إذا بدون هاتف → tag "بدون هاتف" (يغني عن "غير مفعل")
        if hasNoPhone(m) {
            issues.append(.noPhone)
        } else if isNotActivated(m) {
            issues.append(.notActivated)
        }
        if isMissingBirthDate(m) { issues.append(.noBirthDate) }
        if isMissingFather(m)    { issues.append(.noFather) }
        return issues
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if memberVM.isLoading && memberVM.allMembers.isEmpty {
                VStack(spacing: DS.Spacing.lg) {
                    ProgressView()
                        .tint(DS.Color.warning)
                        .scaleEffect(1.3)
                    Text(L10n.t("جاري فحص البيانات...", "Checking data..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allIssueMembers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Filter chips
                    filterChips
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)

                    // Swipe hint
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "hand.draw")
                            .font(DS.Font.scaled(10, weight: .medium))
                        Text(L10n.t(
                            "← سحب يمين: هاتف / ميلاد  •  سحب يسار: ربط أب / تفعيل →",
                            "← Swipe right: Phone / Birth  •  Swipe left: Father / Activate →"
                        ))
                        .font(DS.Font.caption2)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.lg)

                    // Search
                    searchBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)

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
                                    memberRow(member: member, index: index)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            if hasNoPhone(member) {
                                                Button {
                                                    memberToEditPhone = member
                                                } label: {
                                                    Label(L10n.t("هاتف", "Phone"), systemImage: "phone.badge.plus")
                                                }
                                                .tint(DS.Color.primary)
                                            }
                                            if isMissingBirthDate(member) {
                                                Button {
                                                    memberToEditBirthDate = member
                                                } label: {
                                                    Label(L10n.t("ميلاد", "Birth"), systemImage: "calendar.badge.plus")
                                                }
                                                .tint(DS.Color.warning)
                                            }
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            if isMissingFather(member) {
                                                Button {
                                                    memberToEdit = member
                                                } label: {
                                                    Label(L10n.t("ربط أب", "Link Father"), systemImage: "person.line.dotted.person")
                                                }
                                                .tint(DS.Color.info)
                                            }
                                            if isNotActivated(member) {
                                                Button {
                                                    memberToActivate = member
                                                    showActivateConfirm = true
                                                } label: {
                                                    Label(L10n.t("تفعيل", "Activate"), systemImage: "checkmark.circle.fill")
                                                }
                                                .tint(DS.Color.success)
                                            }
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

                    // Selection action bar
                    if isSelectionMode {
                        selectionActionBar
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedFilter == .noGender && !filteredMembers.isEmpty {
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
        .alert(
            L10n.t("تفعيل الحساب", "Activate Account"),
            isPresented: $showActivateConfirm,
            presenting: memberToActivate
        ) { member in
            Button(L10n.t("تفعيل", "Activate")) {
                Task { await activateMember(member) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "تفعيل حساب \(member.fullName)؟",
                "Activate \(member.fullName)'s account?"
            ))
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
        .sheet(item: $memberToEditPhone) { member in
            EditPhoneSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEditBirthDate) { member in
            EditBirthDateSheet(member: member, memberVM: memberVM)
        }
        .sheet(item: $memberToEdit) { member in
            LinkFatherSheet(member: member, memberVM: memberVM)
        }
        .onChange(of: selectedFilter) { _ in
            displayLimit = 20
            // Exit selection mode when switching filters
            if isSelectionMode {
                isSelectionMode = false
                selectedMembers.removeAll()
            }
        }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
            // اختر أول فلتر متاح إذا الفلتر الافتراضي فارغ
            if count(for: selectedFilter) == 0, let first = availableFilters.first {
                selectedFilter = first
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Member Row
    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [selectedFilter.color.opacity(0.3), selectedFilter.color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Text(String(member.fullName.prefix(1)))
                    .font(DS.Font.headline)
                    .foregroundColor(selectedFilter.color)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)

                // Role badge
                DSRoleBadge(title: roleLabel(member.role), color: member.roleColor)

                // Issue tags
                let issues = issueLabels(for: member)
                if !issues.isEmpty {
                    FlowLayout(spacing: DS.Spacing.xs) {
                        ForEach(issues, id: \.self) { issue in
                            HStack(spacing: 2) {
                                Image(systemName: issue.icon)
                                    .font(DS.Font.scaled(9, weight: .bold))
                                Text(issue.label)
                                    .font(DS.Font.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(issue.color)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(issue.color.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Phone info
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
        .animation(DS.Anim.smooth.delay(Double(index) * 0.04), value: appeared)
    }

    // MARK: - Filter Chips
    /// الفلاتر التي تحتوي على أعضاء فقط
    private var availableFilters: [MemberFilter] {
        MemberFilter.visible.filter { count(for: $0) > 0 }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(availableFilters, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .onChange(of: availableFilters) { newFilters in
            // إذا الفلتر المحدد صار فارغ، انقل تلقائياً لأول فلتر متاح
            if !newFilters.contains(selectedFilter), let first = newFilters.first {
                withAnimation(DS.Anim.snappy) { selectedFilter = first }
            }
        }
    }

    private func filterChip(_ filter: MemberFilter) -> some View {
        let isSelected = selectedFilter == filter
        let chipCount = count(for: filter)
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedFilter = filter
            }
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
            .background(
                Capsule()
                    .fill(isSelected ? filter.color : filter.color.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : filter.color.opacity(0.3), lineWidth: 1)
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
                .onChange(of: searchText) { _ in displayLimit = 20 }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.Color.textTertiary)
                }
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.lg)
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

            if !selectedMembers.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
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
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(
            DS.Color.surface
                .dsSubtleShadow()
        )
    }

    // MARK: - Empty State
    private var emptyState: some View {
        DSEmptyState(
            icon: "checkmark.shield.fill",
            title: L10n.t("جميع الحسابات مفعلة والبيانات مكتملة", "All accounts activated and data complete"),
            tint: DS.Color.success
        )
    }

    // MARK: - No Results
    private var noResultsState: some View {
        DSEmptyState(
            icon: "magnifyingglass",
            title: L10n.t("لا توجد نتائج", "No results found")
        )
    }

    // MARK: - Helpers
    private func roleLabel(_ role: FamilyMember.UserRole) -> String {
        switch role {
        case .owner: return L10n.t("مدير", "Admin")
        case .admin: return L10n.t("مدير", "Admin")
        case .monitor: return L10n.t("مراقب", "Monitor")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلق", "Pending")
        }
    }

    private func activateMember(_ member: FamilyMember) async {
        await adminRequestVM.activateAccount(memberId: member.id)
    }
}

// MARK: - Flow Layout for Tags
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
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

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

// MARK: - Edit Phone Sheet
struct EditPhoneSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var phoneInput: String
    @State private var isSaving = false

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
                    // Icon
                    ZStack {
                        Circle()
                            .fill(DS.Color.info.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "phone.badge.plus")
                            .font(DS.Font.scaled(30, weight: .bold))
                            .foregroundColor(DS.Color.info)
                    }
                    .padding(.top, DS.Spacing.xl)

                    // Member name
                    Text(member.fullName)
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    // Phone field
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

                            PhoneNumberTextField(
                                text: $phoneInput,
                                placeholder: L10n.t("أدخل رقم الجوال", "Enter phone number"),
                                font: .monospacedDigitSystemFont(ofSize: 17, weight: .regular),
                                keyboardType: .phonePad,
                                maxLength: 15
                            )
                            .frame(height: 30)
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

                    // Save button
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
                                    .tint(DS.Color.textOnPrimary)
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
                        .background(phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.Color.textTertiary : DS.Color.primary)
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
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - Link Father Sheet

struct LinkFatherSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var selectedFather: FamilyMember?

    /// All potential fathers (non-pending, non-deceased, excluding self)
    private var potentialFathers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.id != member.id && $0.role != .pending }
            .sorted { $0.fullName < $1.fullName }
    }

    private var filteredFathers: [FamilyMember] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return potentialFathers
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return potentialFathers.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Icon + member name
                    VStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.info.opacity(0.1))
                                .frame(width: 70, height: 70)
                            Image(systemName: "person.line.dotted.person")
                                .font(DS.Font.scaled(28, weight: .bold))
                                .foregroundColor(DS.Color.info)
                        }

                        Text(member.fullName)
                            .font(DS.Font.headline)
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)

                    // Search field
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("ابحث عن الأب...", "Search for father..."), text: $searchText)
                            .font(DS.Font.body)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(DS.Color.info.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.sm)

                    // Results count
                    HStack {
                        Text(L10n.t(
                            "\(filteredFathers.count) عضو",
                            "\(filteredFathers.count) members"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xs)

                    // Members list
                    List {
                        ForEach(filteredFathers) { father in
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    selectedFather = (selectedFather?.id == father.id) ? nil : father
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    // Selection indicator
                                    Image(systemName: selectedFather?.id == father.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFather?.id == father.id ? DS.Color.info : DS.Color.textTertiary)
                                        .font(DS.Font.scaled(20))

                                    // Avatar
                                    ZStack {
                                        Circle()
                                            .fill(DS.Color.info.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                        Text(String(father.firstName.prefix(1)))
                                            .font(DS.Font.calloutBold)
                                            .foregroundColor(DS.Color.info)
                                    }

                                    // Name
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(father.fullName)
                                            .font(DS.Font.callout)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .lineLimit(1)
                                        if father.isDeceased == true {
                                            Text(L10n.t("متوفى", "Deceased"))
                                                .font(DS.Font.caption2)
                                                .foregroundColor(DS.Color.textTertiary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .listRowBackground(
                                selectedFather?.id == father.id
                                    ? DS.Color.info.opacity(0.08)
                                    : Color.clear
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)

                    // Save button
                    Button {
                        guard let father = selectedFather else { return }
                        isSaving = true
                        Task {
                            await memberVM.updateMemberFather(memberId: member.id, fatherId: father.id)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(DS.Color.textOnPrimary)
                            } else {
                                Image(systemName: "link.circle.fill")
                            }
                            Text(L10n.t("ربط الأب", "Link Father"))
                                .fontWeight(.bold)
                        }
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(selectedFather != nil ? DS.Color.info : DS.Color.textTertiary)
                        .cornerRadius(DS.Radius.lg)
                    }
                    .disabled(selectedFather == nil || isSaving)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
            .navigationTitle(L10n.t("ربط الأب", "Link Father"))
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
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - Edit Birth Date Sheet
struct EditBirthDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date
    @State private var isSaving = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        // Parse existing date or default to 1990-01-01
        if let existing = member.birthDate,
           let parsed = Self.formatter.date(from: existing) {
            _selectedDate = State(initialValue: parsed)
        } else {
            var comps = DateComponents()
            comps.year = 1990; comps.month = 1; comps.day = 1
            _selectedDate = State(initialValue: Calendar.current.date(from: comps) ?? Date())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.xl) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(DS.Color.warning.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "calendar.badge.plus")
                            .font(DS.Font.scaled(30, weight: .bold))
                            .foregroundColor(DS.Color.warning)
                    }
                    .padding(.top, DS.Spacing.xl)

                    // Member name
                    Text(member.fullName)
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    // Date picker
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        StableWheelDatePicker(selection: $selectedDate, in: ...Date())
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // Save button
                    Button {
                        isSaving = true
                        Task {
                            let dateString = Self.formatter.string(from: selectedDate)
                            await memberVM.updateMemberBirthDate(
                                memberId: member.id,
                                birthDate: dateString
                            )
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(DS.Color.textOnPrimary)
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
                        .background(DS.Color.primary)
                        .cornerRadius(DS.Radius.lg)
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, DS.Spacing.lg)

                    Spacer()
                }
            }
            .navigationTitle(L10n.t("تعديل تاريخ الميلاد", "Edit Birth Date"))
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
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
