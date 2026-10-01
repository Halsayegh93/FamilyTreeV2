import SwiftUI

// MARK: - الملفات الناقصة — بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// ملاحظة: الشاشة غير مربوطة حالياً بأي مكان (حلّت محلّها محطة «الحسابات» في
// «إدارة الأعضاء»)، ووُحّد شكلها لو أُعيدت: بطاقة رأس بأرقام حيّة ← فلاتر بالعدد ←
// بحث ← صفوف `.dsRowBox()` في `List` (لأجل السحب: تعديل/حذف) ← شريط التحديد الجماعي.
struct AdminIncompleteMembersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var appeared = false
    @State private var searchText = ""
    var initialFilter: IncompleteFilter = .noBirthDate
    @State private var selectedFilter: IncompleteFilter = .noBirthDate
    @State private var isSelectionMode = false
    @State private var selectedMembers: Set<UUID> = []
    @State private var memberToEdit: FamilyMember?
    @State private var memberToDelete: FamilyMember?
    @State private var showDeleteConfirm = false
    @State private var deleteFailureText: String?
    @State private var showDeleteFailure = false
    @State private var showGenderConfirm = false
    @State private var pendingGender: String = "male"
    @State private var genderUpdateResult: String?
    @State private var showGenderResult = false
    @State private var displayLimit = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// لون مجال «الشجرة والأعضاء»
    private let tint = DS.Color.composerProject

    enum IncompleteFilter: String, CaseIterable {
        case noBirthDate, noFather, noGender

        /// الفلاتر الظاهرة حالياً — لتفعيل noGender أضفها هنا
        static let visible: [IncompleteFilter] = [.noBirthDate, .noFather]

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

    /// Returns countable family members (non-deceased) with at least one missing field
    private var allIncompleteMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.isCountable && $0.isDeceased != true }
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

    /// أرقام حيّة بمرور واحد (بلا فرز) على نفس المجموعة
    private var counts: (total: Int, noBirth: Int, noFather: Int, noGender: Int) {
        var t = 0, b = 0, f = 0, g = 0
        for m in memberVM.allMembers where m.isCountable && m.isDeceased != true && memberHasIncompleteData(m) {
            t += 1
            if isMissingBirthDate(m) { b += 1 }
            if isMissingFather(m) { f += 1 }
            if isMissingGender(m) { g += 1 }
        }
        return (t, b, f, g)
    }

    private func count(for filter: IncompleteFilter) -> Int {
        let c = counts
        switch filter {
        case .noBirthDate: return c.noBirth
        case .noFather:    return c.noFather
        case .noGender:    return c.noGender
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if memberVM.isLoading && memberVM.allMembers.isEmpty {
                // حالة التحميل — البيانات لم تصل بعد
                stateScroll {
                    SysStateCard(icon: "person.text.rectangle",
                                 title: L10n.t("جاري فحص البيانات...", "Checking data..."),
                                 tint: DS.Color.warning,
                                 isLoading: true)
                }
            } else if allIncompleteMembers.isEmpty {
                stateScroll { emptyState }
            } else {
                VStack(spacing: 0) {
                    List {
                        hero
                            .incompleteListRow(top: DS.Spacing.md, bottom: DS.Spacing.sm)

                        // Filter chips
                        DSFilterChips(
                            options: IncompleteFilter.visible.map { filter in
                                DSFilterOption(id: filter, title: filter.label, icon: filter.icon,
                                               count: count(for: filter))
                            },
                            selection: $selectedFilter,
                            tint: tint
                        )
                        .onChange(of: selectedFilter) { _ in displayLimit = 20 }
                        .incompleteListRow(top: 0, bottom: 0)

                        // Search bar
                        DSSearchField(text: $searchText,
                                      placeholder: L10n.t("بحث عن عضو...", "Search member..."),
                                      tint: tint)
                            .onChange(of: searchText) { _ in displayLimit = 20 }
                            .incompleteListRow(top: 2, bottom: DS.Spacing.xs)

                        if filteredMembers.isEmpty {
                            noResultsState
                                .incompleteListRow(top: DS.Spacing.sm)
                        } else {
                            let visible = Array(filteredMembers.prefix(displayLimit))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                                if isSelectionMode {
                                    Button {
                                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                                            toggleSelection(member)
                                        }
                                    } label: {
                                        memberRow(member: member, index: index) {
                                            selectionCheckbox(for: member)
                                        }
                                    }
                                    .buttonStyle(DSScaleButtonStyle())
                                    .accessibilityAddTraits(selectedMembers.contains(member.id) ? .isSelected : [])
                                    .incompleteListRow()
                                } else {
                                    ZStack {
                                        // الرابط مخفي — الصف كله يفتح التفاصيل بلا سهم النظام خارج الصندوق
                                        NavigationLink(destination: AdminMemberDetailSheet(member: member)) { EmptyView() }
                                            .opacity(0)
                                        memberRow(member: member, index: index) {
                                            SysChevron()
                                        }
                                    }
                                    .incompleteListRow()
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
                                loadMoreButton
                                    .incompleteListRow(top: DS.Spacing.xs)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .environment(\.defaultMinListRowHeight, 0)

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
        // «تعديل» من السحب — مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك)
        .dsTallBox(item: $memberToEdit) { member in   // نموذج طويل — مربّع طويل (توصية أبل)
            AdminMemberDetailSheet(member: member)
        }
        .dsAlert(
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
        .dsAlert(L10n.t("تم التحديث", "Updated"), isPresented: $showGenderResult) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(genderUpdateResult ?? "")
        }
        .dsAlert(
            L10n.t("حذف العضو نهائياً", "Delete Member Permanently"),
            isPresented: $showDeleteConfirm,
            presenting: memberToDelete
        ) { member in
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task {
                    if await !memberVM.deleteMember(memberId: member.id) {
                        deleteFailureText = memberVM.errorMessage
                        showDeleteFailure = true
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: { member in
            Text(L10n.t(
                "هل أنت متأكد من حذف \(member.fullName)؟ هذا الإجراء لا يمكن التراجع عنه.",
                "Are you sure you want to delete \(member.fullName)? This action cannot be undone."
            ))
        }
        .dsAlert(L10n.t("لم يُحذف العضو", "Member Not Deleted"), isPresented: $showDeleteFailure) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(deleteFailureText ?? "")
        }
        .onAppear {
            selectedFilter = initialFilter
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// الرأس + بطاقة حالة (تحميل / لا نواقص) في صفحة تتمرّر
    private func stateScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                hero
                content()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
    }

    // MARK: - بطاقة الرأس

    private var hero: some View {
        let c = counts
        let loading = memberVM.isLoading && memberVM.allMembers.isEmpty
        return DSPageHero(
            title: L10n.t("الملفات الناقصة", "Incomplete Profiles"),
            subtitle: L10n.t("أحياء ينقصهم تاريخ ميلاد أو أب مرتبط أو جنس",
                             "Living members missing a birth date, father or gender"),
            icon: "person.text.rectangle",
            tint: tint,
            stats: [
                DSHeroStat(value: loading ? "—" : "\(c.total)",
                           label: L10n.t("إجمالي", "Total"), icon: "person.3.fill"),
                DSHeroStat(value: loading ? "—" : "\(c.noBirth)",
                           label: IncompleteFilter.noBirthDate.label, icon: IncompleteFilter.noBirthDate.icon),
                DSHeroStat(value: loading ? "—" : "\(c.noFather)",
                           label: IncompleteFilter.noFather.label, icon: IncompleteFilter.noFather.icon)
            ]
        )
    }

    // MARK: - Member Row

    private func memberRow<Trailing: View>(member: FamilyMember, index: Int,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // الحرف الأول
            Text(String(member.fullName.prefix(1)))
                .font(DS.Font.plex(15, weight: .bold))
                .foregroundColor(DS.Color.warning)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.Color.warning.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(member.displayFullName)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(2)

                // الدور + الحقول الناقصة
                FlowLayout(spacing: DS.Spacing.xs) {
                    SysStatusChip(text: member.roleName, tint: member.roleColor)
                    ForEach(missingFields(for: member), id: \.self) { field in
                        SysStatusChip(text: field.label, icon: field.icon, tint: field.color)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            trailing()
        }
        .dsRowBox()
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 15)
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : DS.Anim.smooth.delay(Double(min(index, 15)) * 0.03),
                   value: appeared)
    }

    private var loadMoreButton: some View {
        Button {
            displayLimit += 20
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .accessibilityHidden(true)
                Text(L10n.t(
                    "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
                    "Show more (\(filteredMembers.count - displayLimit) remaining)"
                ))
                .font(DS.Font.plex(12.5, weight: .bold))
            }
            .foregroundColor(tint)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(minHeight: 40)
            .background(Capsule().fill(tint.opacity(0.10)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
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
                .strokeBorder(isSelected ? tint : DS.Color.textTertiary, lineWidth: 2)
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(tint)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
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
                            .font(.system(size: 14, weight: .semibold))
                        Text(selectedMembers.count == filteredMembers.count
                             ? L10n.t("إلغاء الكل", "Deselect All")
                             : L10n.t("تحديد الكل", "Select All"))
                            .font(DS.Font.plex(13.5, weight: .bold))
                    }
                    .foregroundColor(tint)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())

                Spacer()

                if !selectedMembers.isEmpty {
                    SysStatusChip(text: L10n.t(
                        "محدد: \(selectedMembers.count)",
                        "Selected: \(selectedMembers.count)"
                    ), tint: tint)
                }
            }

            // الصف الثاني: أزرار الإجراءات
            if !selectedMembers.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    // TODO: gender buttons — re-enable when needed
                    // زر تعديل فردي
                    Button {
                        if let firstSelectedId = selectedMembers.first,
                           let member = filteredMembers.first(where: { $0.id == firstSelectedId }) {
                            memberToEdit = member
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(tint)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(tint.opacity(0.12)))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("تعديل", "Edit"))
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            DS.Color.surface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(0.12))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Empty State
    private var emptyState: some View {
        SysStateCard(
            icon: "checkmark.shield.fill",
            title: L10n.t("جميع بيانات الأعضاء مكتملة", "All member data is complete"),
            tint: DS.Color.success
        )
    }

    // MARK: - No Results State
    private var noResultsState: some View {
        SysStateCard(
            icon: "magnifyingglass",
            title: L10n.t("لا توجد نتائج", "No results found"),
            tint: DS.Color.textTertiary
        )
    }
}

// MARK: - صف القائمة الشفاف (نمط صفحات الإدارة)

private extension View {
    /// صف بلا خلفية ولا فاصل، بهوامش الصفحة — المحتوى نفسه يرسم صندوقه
    func incompleteListRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: DS.Spacing.lg, bottom: bottom, trailing: DS.Spacing.lg))
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
