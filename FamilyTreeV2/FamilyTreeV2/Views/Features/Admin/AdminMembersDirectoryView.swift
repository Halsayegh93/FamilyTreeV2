import SwiftUI

// MARK: - Admin Members Registry — سجل الأعضاء
struct AdminMembersDirectoryView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    @State private var searchText = ""
    @State private var displayLimit = 20
    @State private var appeared = false
    @State private var selectedFilter: RegistryFilter = .all
    @State private var memberToFreeze: FamilyMember?
    @State private var memberToActivate: FamilyMember?
    @State private var memberToEditPhone: FamilyMember?
    @State private var branchRootId: UUID? = nil
    @State private var branchPickerOpen = false

    /// مسار التصفّح الشجري — فارغ يعني مستوى الجذور (رؤوس الفروع)
    @State private var drillPath: [FamilyMember] = []

    /// عدد ذرّية كل عضو — يُحسب مرة واحدة بدل مسح الشجرة لكل صف عند كل رسم
    @State private var descendantCounts: [UUID: Int] = [:]

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
        // المعيار القانوني: يطابق الشجرة + الويب + كل العدّادات
        // الفرز على الاسم الأول ثم الكامل — الفرز على سلسلة النسب الطويلة
        // كان يجعل القائمة تبدو عشوائية لأن التشابه في أوائل السلسلة كبير.
        memberVM.allMembers
            .filter(\.isCountable)
            .sorted {
                let a = $0.firstName.trimmingCharacters(in: .whitespaces)
                let b = $1.firstName.trimmingCharacters(in: .whitespaces)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
                return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }
    }

    /// أبناء كل أب — لحساب الذرّية بسرعة
    private var childrenByFather: [UUID: [FamilyMember]] {
        var map: [UUID: [FamilyMember]] = [:]
        for m in memberVM.allMembers {
            if let f = m.fatherId {
                map[f, default: []].append(m)
            }
        }
        return map
    }

    /// كل ذرّية عضو معيّن (يشمل العضو نفسه)
    private func descendantIds(of rootId: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [rootId]
        var stack = [rootId]
        let kidsMap = childrenByFather
        while let cur = stack.popLast() {
            for c in kidsMap[cur] ?? [] {
                if !ids.contains(c.id) {
                    ids.insert(c.id)
                    stack.append(c.id)
                }
            }
        }
        return ids
    }

    private var branchRootMember: FamilyMember? {
        guard let id = branchRootId else { return nil }
        return memberVM.allMembers.first { $0.id == id }
    }

    private func count(for filter: RegistryFilter) -> Int {
        // إذا في فرع محدّد، نعدّ من ذرّيته فقط
        var pool = baseMembers
        if let rootId = branchRootId {
            let ids = descendantIds(of: rootId)
            pool = pool.filter { ids.contains($0.id) }
        }
        switch filter {
        case .all:      return pool.count
        case .living:   return pool.filter { $0.isDeceased != true }.count
        case .deceased: return pool.filter { $0.isDeceased == true }.count
        }
    }

    private var filteredMembers: [FamilyMember] {
        var members: [FamilyMember]
        switch selectedFilter {
        case .all:      members = baseMembers
        case .living:   members = baseMembers.filter { $0.isDeceased != true }
        case .deceased: members = baseMembers.filter { $0.isDeceased == true }
        }
        // حصر على فرع معيّن (إذا اختار)
        if let rootId = branchRootId {
            let ids = descendantIds(of: rootId)
            members = members.filter { ids.contains($0.id) }
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

    // MARK: - التصفّح الشجري

    /// رؤوس الفروع — من ليس له أب مسجّل
    private var rootMembers: [FamilyMember] {
        baseMembers.filter { $0.fatherId == nil }
    }

    /// أعضاء المستوى الحالي حسب المسار
    private var currentLevelMembers: [FamilyMember] {
        guard let last = drillPath.last else { return rootMembers }
        let kids = childrenByFather[last.id] ?? []
        return kids.sorted {
            let a = $0.firstName.trimmingCharacters(in: .whitespaces)
            let b = $1.firstName.trimmingCharacters(in: .whitespaces)
            if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
            return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
    }

    /// عدد ذرّية عضو (بلا نفسه) — من الخريطة المحسوبة مسبقاً
    private func descendantCount(of m: FamilyMember) -> Int {
        descendantCounts[m.id] ?? 0
    }

    /// يبني خريطة الذرّية بمرور واحد من الأسفل للأعلى — O(n) بدل O(n²)
    private func buildDescendantCounts() {
        let kidsMap = childrenByFather
        var memo: [UUID: Int] = [:]

        func count(_ id: UUID) -> Int {
            if let cached = memo[id] { return cached }
            var total = 0
            for child in kidsMap[id] ?? [] {
                total += 1 + count(child.id)
            }
            memo[id] = total
            return total
        }

        for m in memberVM.allMembers { _ = count(m.id) }
        descendantCounts = memo
    }

    /// شريط المسار — يرجّعك لأي مستوى بضغطة
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(DS.Anim.snappy) { drillPath.removeAll() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(DS.Font.scaled(11, weight: .semibold))
                        Text(L10n.t("الفروع", "Branches"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                    .foregroundColor(drillPath.isEmpty ? DS.Color.textOnPrimary : DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.sm + 2)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(drillPath.isEmpty ? DS.Color.primary : DS.Color.primary.opacity(0.10)))
                }

                ForEach(Array(drillPath.enumerated()), id: \.element.id) { idx, node in
                    Image(systemName: "chevron.forward")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            drillPath = Array(drillPath.prefix(idx + 1))
                        }
                    } label: {
                        let isLast = idx == drillPath.count - 1
                        Text(node.firstName.isEmpty ? node.fullName : node.firstName)
                            .font(DS.Font.scaled(11, weight: .semibold))
                            .foregroundColor(isLast ? DS.Color.textOnPrimary : DS.Color.primary)
                            .lineLimit(1)
                            .padding(.horizontal, DS.Spacing.sm + 2)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(isLast ? DS.Color.primary : DS.Color.primary.opacity(0.10)))
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// صفّ فرع — الضغط على الاسم يفتح التفاصيل، وعلى شارة الذرّية ينزل داخل الفرع
    private func branchRow(_ member: FamilyMember) -> some View {
        let kids = descendantCount(of: member)
        return HStack(spacing: DS.Spacing.sm) {
            NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                memberRow(member: member, index: 0)
            }
            .buttonStyle(PlainButtonStyle())

            if kids > 0 {
                Button {
                    withAnimation(DS.Anim.snappy) { drillPath.append(member) }
                } label: {
                    VStack(spacing: 1) {
                        Text("\(kids)")
                            .font(DS.Font.plex(13, weight: .bold))
                        Image(systemName: "chevron.forward")
                            .font(DS.Font.scaled(11, weight: .bold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 42, height: 42)
                    .background(DS.Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.sm) {
                // 1) البحث — أعلى شي
                searchBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)

                // 2) فلتر الحالة (الكل/أحياء/متوفون)
                filterChips

                if searchText.isEmpty {
                    breadcrumbBar
                }

                if filteredMembers.isEmpty {
                    noResultsState
                } else if searchText.isEmpty {
                    // تصفّح شجري — مستوى واحد في كل مرة
                    List {
                        ForEach(currentLevelMembers, id: \.id) { member in
                            branchRow(member)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 3, leading: DS.Spacing.lg,
                                    bottom: 3, trailing: DS.Spacing.lg
                                ))
                        }
                        if currentLevelMembers.isEmpty {
                            Text(L10n.t("ما فيه ذرّية مسجّلة لهذا الفرع", "No descendants recorded for this branch"))
                                .font(DS.Font.scaled(12))
                                .foregroundColor(DS.Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, DS.Spacing.xxl)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 0)
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
                                top: 3,
                                leading: DS.Spacing.lg,
                                bottom: 3,
                                trailing: DS.Spacing.lg
                            ))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                // التجميد/التفعيل للمدير فقط (كان canEditMembers يشمل المراقب)
                                if authVM.canFreezeMembers && member.isDeceased != true {
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
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if authVM.canEditMembers && member.isDeceased != true {
                                    Button {
                                        memberToEditPhone = member
                                    } label: {
                                        Label(L10n.t("رقم", "Number"), systemImage: "phone.badge.plus")
                                    }
                                    .tint(DS.Color.primary)
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
                    .environment(\.defaultMinListRowHeight, 0)
                }
            }
            .onAppear {
                withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
                if descendantCounts.isEmpty { buildDescendantCounts() }
            }
            .onChange(of: memberVM.allMembers.count) { _ in buildDescendantCounts() }
        }
        // تعديل / إضافة رقم — واجهة «رقم العضو» الموحّدة (تحفظ على السيرفر وتعتمد وتفعّل)
        .sheet(item: $memberToEditPhone) { member in
            PendingMemberPhoneSheet(member: member, activateOnSave: true)
                .environmentObject(adminRequestVM)
        }
        // Freeze confirm
        .sheet(isPresented: $branchPickerOpen) {
            BranchPickerSheet(
                allMembers: memberVM.allMembers,
                onSelect: { id in
                    branchRootId = id
                    branchPickerOpen = false
                    displayLimit = 20
                }
            )
        }
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

    /// شارة حالة صغيرة موحّدة (متوفي / مجمّد)
    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DS.Font.caption2)
            .fontWeight(.bold)
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func memberRow(member: FamilyMember, index: Int) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(
                name: member.fullName,
                avatarUrl: member.avatarUrl,
                size: 40,
                roleColor: member.isDeceased == true ? DS.Color.textTertiary : member.roleColor
            )
            .overlay(alignment: .bottomTrailing) {
                // حالة العضو على الصورة نفسها — بدل شارات نصّية تزحم السطر
                if member.isDeceased == true {
                    Image(systemName: "leaf.fill")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(DS.Color.textTertiary)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 1.5))
                } else if member.status == .frozen {
                    Image(systemName: "lock.fill")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(DS.Color.error)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 1.5))
                }
            }

            // سطران: الاسم، ثم شارة العضو والهاتف — بلا تكرار الاسم
            VStack(alignment: .leading, spacing: 3) {
                Text(member.shortFullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(
                        member.isDeceased == true ? DS.Color.textTertiary :
                        member.status == .frozen ? DS.Color.textTertiary :
                        DS.Color.textPrimary
                    )
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.sm) {
                    DSRoleBadge(title: member.roleName, color: member.roleColor)

                    if let phone = member.phoneNumber, !phone.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "phone.fill")
                                .font(DS.Font.scaled(11))
                            Text(KuwaitPhone.display(phone))
                                .font(DS.Font.caption2)
                                .monospacedDigit()
                        }
                        .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(minHeight: 50)
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(DS.Anim.smooth.delay(Double(index) * 0.03), value: appeared)
    }

    // MARK: - Branch Filter Row

    private var branchFilterRow: some View {
        Group {
            if let m = branchRootMember {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "tree.fill")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("فرع: \(m.fullName)", "Branch: \(m.fullName)"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.accent)
                            .lineLimit(1)
                        Text(L10n.t(
                            "\(descendantIds(of: m.id).count) عضو في الفرع",
                            "\(descendantIds(of: m.id).count) members in branch"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                    Spacer()
                    Button {
                        branchPickerOpen = true
                    } label: {
                        Text(L10n.t("تغيير", "Change"))
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.accent)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(DS.Color.accent.opacity(0.12)))
                    }
                    Button {
                        branchRootId = nil
                        displayLimit = 20
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DS.Color.error)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.accent.opacity(0.2), lineWidth: 1)
                )
            } else {
                Button {
                    branchPickerOpen = true
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "tree")
                            .font(DS.Font.scaled(12, weight: .semibold))
                        Text(L10n.t("حصر على فرع معيّن", "Filter by branch"))
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .opacity(0.5)
                    }
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
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

