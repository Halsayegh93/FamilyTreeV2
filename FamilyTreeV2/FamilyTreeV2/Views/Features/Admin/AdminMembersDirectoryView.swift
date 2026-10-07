import SwiftUI

// MARK: - Admin Members Registry — سجل الأعضاء
//
// تصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): قائمة واحدة تتمرّر كلها —
// صفّ أرقام حيّة (العنوان في رأس «إدارة الأعضاء» الملوّن) ← بحث ← فلاتر بالعدد ← مسار الفروع ← صفوف `.dsRowBox()`.
// بقيت `List` لأجل السحب (تجميد/تفعيل/رقم) والتحميل التدريجي.
// الضغط على الصف يفتح تفاصيل العضو، وعلى عدّاد الذرّية ينزل داخل الفرع — كما كان.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// مسار التصفّح الشجري — فارغ يعني مستوى الجذور (رؤوس الفروع)
    @State private var drillPath: [FamilyMember] = []

    /// عدد ذرّية كل عضو — يُحسب مرة واحدة بدل مسح الشجرة لكل صف عند كل رسم
    @State private var descendantCounts: [UUID: Int] = [:]

    /// لون مجال «الشجرة والأعضاء»
    private let tint = DS.Color.composerProject

    /// الرأس الملوّن الموحّد (`.dsSubPageHeader`) حين تُفتح الصفحة وحدها؛ داخل «إدارة الأعضاء» (تبويب «السجل»)
    /// رأس تلك الصفحة فوقها فلا يتكرّر — `AdminMembersManagementView` تمرّر false
    var showsHeader: Bool = true

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
            case .all:      return AppSection.admin.ink
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

    /// حركة التنقّل في الفروع — هادئة مع «تقليل الحركة»
    private var drillAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy
    }

    /// شريط المسار — يرجّعك لأي مستوى بضغطة
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                crumb(title: L10n.t("الفروع", "Branches"), icon: "house.fill",
                      isCurrent: drillPath.isEmpty) {
                    withAnimation(drillAnimation) { drillPath.removeAll() }
                }

                ForEach(Array(drillPath.enumerated()), id: \.element.id) { idx, node in
                    Image(systemName: "chevron.forward")
                        .dsGlyph(DS.Glyph.xsCompact)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    crumb(title: node.firstName.isEmpty ? node.fullName : node.firstName, icon: nil,
                          isCurrent: idx == drillPath.count - 1) {
                        withAnimation(drillAnimation) {
                            drillPath = Array(drillPath.prefix(idx + 1))
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    /// عنصر في المسار — الشريحة الموحّدة: الحالي ممتلئ بتعبئة القسم، والسابق بلون المجال
    private func crumb(title: String, icon: String?, isCurrent: Bool,
                       action: @escaping () -> Void) -> some View {
        DSChipButton(title, icon: icon, tint: isCurrent ? DS.Color.primary : tint,
                     isSelected: isCurrent, action: action)
    }

    /// صفّ فرع — الضغط على الصف يفتح التفاصيل، وعلى عدّاد الذرّية ينزل داخل الفرع
    private func branchRow(_ member: FamilyMember) -> some View {
        let kids = descendantCount(of: member)
        return ZStack {
            // الرابط مخفي: الصف كله يفتح التفاصيل بلا سهم النظام خارج الصندوق
            NavigationLink(destination: AdminMemberDetailSheet(member: member)) { EmptyView() }
                .opacity(0)

            memberRow(member: member) {
                if kids > 0 {
                    Button {
                        withAnimation(drillAnimation) { drillPath.append(member) }
                    } label: {
                        VStack(spacing: 0) {
                            Text("\(kids)")
                                .dsFont(.rowTitleCompact)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "chevron.forward")
                                .dsGlyph(DS.Glyph.micro)
                                .accessibilityHidden(true)
                        }
                        .foregroundColor(tint)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .background(tint.opacity(DS.Opacity.tintFill),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(tint.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("ذرّية \(member.firstName): \(kids)",
                                               "\(member.firstName)'s descendants: \(kids)"))
                    .accessibilityHint(L10n.t("يعرض الفرع", "Opens the branch"))
                } else {
                    DSChevron()
                }
            }
        }
    }

    /// صف نتيجة بحث — الصف كله يفتح التفاصيل (نفس الرابط، بلا سهم النظام خارج الصندوق)
    private func searchResultRow(_ member: FamilyMember) -> some View {
        ZStack {
            NavigationLink(destination: AdminMemberDetailSheet(member: member)) { EmptyView() }
                .opacity(0)
            memberRow(member: member) {
                DSChevron()
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            List {
                // 0) بطاقة الرأس — تتمرّر مع القائمة
                hero
                    .registryListRow(top: DS.Spacing.sm, bottom: DS.Spacing.sm)

                // 1) البحث
                DSSearchField(text: $searchText,
                              placeholder: L10n.t("بحث بالاسم أو رقم الهاتف...", "Search by name or phone..."),
                              tint: tint)
                    .onChange(of: searchText) { _ in displayLimit = 20 }
                    .registryListRow(top: 0, bottom: DS.Spacing.xxs)

                // 2) فلتر الحالة (الكل/أحياء/متوفون)
                filterChips
                    .registryListRow(top: 0, bottom: 0)

                if searchText.isEmpty {
                    breadcrumbBar
                        .registryListRow(top: 0, bottom: DS.Spacing.xxs, horizontal: 0)
                }

                if filteredMembers.isEmpty {
                    noResultsState
                        .registryListRow(top: DS.Spacing.sm)
                } else if searchText.isEmpty {
                    // تصفّح شجري — مستوى واحد في كل مرة
                    // نمط الأخبار والديوانيات: أول ٧ صفوف تصعد تباعاً، وما يُبنى بالتمرير يظهر مباشرة
                    ForEach(Array(currentLevelMembers.enumerated()), id: \.element.id) { index, member in
                        branchRow(member)
                            .dsCardCascade(index, appeared: appeared)
                            .registryListRow()
                    }
                    if currentLevelMembers.isEmpty {
                        DSEmptyView(L10n.t("ما فيه ذرّية مسجّلة لهذا الفرع", "No descendants recorded for this branch"),
                                    style: .compact)
                            .registryListRow(top: DS.Spacing.sm)
                    }
                } else {
                    let visible = Array(filteredMembers.prefix(displayLimit))
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, member in
                        searchResultRow(member)
                            .dsCardCascade(index, appeared: appeared)
                            .registryListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                // التجميد/التفعيل للمدير فقط (كان canEditMembers يشمل المراقب)
                                // لا تجميد للمالك ولا لنفسك (السيرفر يرفضهما أيضاً)
                                if authVM.canFreezeMembers && member.isDeceased != true
                                    && member.role != .owner && member.id != authVM.currentUser?.id {
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
                                    .tint(AppSection.admin.ink)
                                }
                            }
                    }

                    // Load more
                    if displayLimit < filteredMembers.count {
                        loadMoreButton
                            .registryListRow(top: DS.Spacing.xs)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 0)
            .onAppear {
                // دخول الصفوف مرة واحدة (نمط الأخبار والديوانيات) — الحركة نفسها في dsCardCascade؛
                // بعد أول تخطيط (خلايا `List` تُبنى فيه) حتى تبدأ أول الصفوف مخفية ثم تصعد
                DispatchQueue.main.async { appeared = true }
                if descendantCounts.isEmpty { buildDescendantCounts() }
            }
            .onChange(of: memberVM.allMembers.count) { _ in buildDescendantCounts() }
        }
        // تعديل / إضافة رقم — واجهة «رقم العضو» الموحّدة (تحفظ على السيرفر وتعتمد وتفعّل)
        .dsCenterBox(item: $memberToEditPhone) { member in
            PendingMemberPhoneSheet(member: member, activateOnSave: true)
                .environmentObject(adminRequestVM)
        }
        // Freeze confirm
        .dsTallBox(isPresented: $branchPickerOpen) {   // شجرة فروع طويلة (توصية أبل)
            BranchPickerSheet(
                allMembers: memberVM.allMembers,
                selectedId: branchRootId,
                onSelect: { id in
                    branchRootId = id
                    branchPickerOpen = false
                    displayLimit = 20
                }
            )
        }
        // تأكيد التجميد/التفعيل — المربّع الوسطي الموحّد (`dsAlert`) بدل الورقة السفلية
        .dsAlert(
            memberToFreeze.map {
                L10n.t("تجميد حساب \($0.fullName)؟", "Freeze \($0.fullName)'s account?")
            } ?? "",
            isPresented: Binding(
                get: { memberToFreeze != nil },
                set: { if !$0 { memberToFreeze = nil } }
            ),
            presenting: memberToFreeze
        ) { member in
            Button(L10n.t("تجميد الحساب", "Freeze Account"), role: .destructive) {
                Task { await memberVM.setMemberStatus(memberId: member.id, status: .frozen) }
                memberToFreeze = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { memberToFreeze = nil }
        } message: { _ in
            Text(L10n.t("لن يتمكن من الدخول للتطبيق.", "They won't be able to access the app."))
        }
        // Activate confirm
        .dsAlert(
            memberToActivate.map {
                L10n.t("تفعيل حساب \($0.fullName)؟", "Activate \($0.fullName)'s account?")
            } ?? "",
            isPresented: Binding(
                get: { memberToActivate != nil },
                set: { if !$0 { memberToActivate = nil } }
            ),
            presenting: memberToActivate
        ) { member in
            Button(L10n.t("تفعيل الحساب", "Activate Account")) {
                Task { await memberVM.setMemberStatus(memberId: member.id, status: .active) }
                memberToActivate = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { memberToActivate = nil }
        } message: { _ in
            Text(L10n.t("سيتمكن من الدخول للتطبيق مجدداً.", "They will be able to access the app again."))
        }
        // الرأس الملوّن الموحّد مثل بقية صفحات الإدارة (نفس نمط «إدارة الأعضاء»)
        .modifier(RegistryHeader(shows: showsHeader))
    }

    /// رأس «سجل الأعضاء» الملوّن — مرة واحدة فقط (لا يُرسم تحت رأس «إدارة الأعضاء»)
    private struct RegistryHeader: ViewModifier {
        let shows: Bool
        func body(content: Content) -> some View {
            if shows {
                content.dsSubPageHeader(L10n.t("سجل الأعضاء", "Members Registry"),
                                        subtitle: L10n.t("تصفّح الفروع، أو ابحث بالاسم أو الرقم",
                                                         "Browse branches, or search by name or phone"))
            } else {
                content
            }
        }
    }

    // MARK: - بطاقة الرأس

    /// أرقام حيّة بمرور واحد على الأعضاء المحمّلين (بلا فرز): الأفراد، رؤوس الفروع، من لهم رقم
    private var heroNumbers: (total: Int, branches: Int, withPhone: Int) {
        var total = 0, branches = 0, withPhone = 0
        for m in memberVM.allMembers where m.isCountable {
            total += 1
            if m.fatherId == nil { branches += 1 }
            if !(m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { withPhone += 1 }
        }
        return (total, branches, withPhone)
    }

    /// الأرقام السريعة — العنوان والوصف في رأس «إدارة الأعضاء» الملوّن
    private var hero: some View {
        let n = heroNumbers
        let ready = !memberVM.allMembers.isEmpty
        return DSStatsRow([
            DSHeroStat(value: ready ? "\(n.total)" : "—",
                       label: L10n.t("الأفراد", "Members"), icon: "person.3.fill"),
            DSHeroStat(value: ready ? "\(n.branches)" : "—",
                       label: L10n.t("الفروع", "Branches"), icon: "arrow.triangle.branch"),
            DSHeroStat(value: ready ? "\(n.withPhone)" : "—",
                       label: L10n.t("لهم رقم", "With phone"), icon: "phone.fill")
        ], tint: tint)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        DSFilterChips(
            options: RegistryFilter.allCases.map { filter in
                let n = count(for: filter)
                return DSFilterOption(id: filter, title: filter.label, icon: filter.icon,
                                      count: n > 0 ? n : nil)
            },
            selection: $selectedFilter,
            tint: tint
        )
        .onChange(of: selectedFilter) { _ in
            displayLimit = 20
            searchText = ""
        }
    }

    // MARK: - Member Row

    /// صف عضو بإطار حقول المربّعات: الصورة (وعليها الحالة) + الاسم + الدور والهاتف + طرف
    /// (دخوله بـ`dsCardCascade` في القائمة نفسها)
    private func memberRow<Trailing: View>(member: FamilyMember,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        let muted = member.isDeceased == true || member.status == .frozen
        return HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                memberAvatar(member)

                // سطران: الاسم، ثم شارة العضو والهاتف — بلا تكرار الاسم
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(member.shortFullName)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(muted ? DS.Color.textTertiary : DS.Color.fieldLabel)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.xsm) {
                        DSStatusChip(text: member.roleName, tint: member.roleColor)

                        if let phone = member.phoneNumber, !phone.isEmpty {
                            HStack(spacing: DS.Spacing.xxs) {
                                Image(systemName: "phone.fill")
                                    .dsGlyph(DS.Glyph.micro, weight: .semibold)
                                    .accessibilityHidden(true)
                                Text(KuwaitPhone.display(phone))
                                    .dsFont(.subtitle)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .foregroundColor(DS.Color.fieldValue)
                        }

                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel(member))
            .accessibilityAddTraits(.isButton)

            trailing()
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .dsRowBox()
        .contentShape(Rectangle())
    }

    /// الصورة وعليها حالة العضو — بدل شارات نصّية تزحم السطر
    private func memberAvatar(_ member: FamilyMember) -> some View {
        DSMemberAvatar(
            name: member.fullName,
            avatarUrl: member.avatarUrl,
            size: DS.Icon.avatar,
            roleColor: member.isDeceased == true ? DS.Color.textTertiary : member.roleColor
        )
        .overlay(alignment: .bottomTrailing) {
            if member.isDeceased == true {
                statusBadge("leaf.fill", DS.Color.textTertiary)
            } else if member.status == .frozen {
                statusBadge("lock.fill", DS.Color.error)
            }
        }
        .accessibilityHidden(true)
    }

    private func statusBadge(_ icon: String, _ color: Color) -> some View {
        Image(dsSymbol: icon)
            .dsGlyph(DS.Glyph.microCompact)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Icon.avatarBadge, height: DS.Icon.avatarBadge)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: DS.Border.widthBold))
            .offset(x: DS.Spacing.xxs, y: DS.Spacing.xxs)
    }

    private func rowAccessibilityLabel(_ member: FamilyMember) -> String {
        var parts = [member.shortFullName, member.roleName]
        if member.isDeceased == true { parts.append(L10n.t("متوفى", "Deceased")) }
        if member.status == .frozen { parts.append(L10n.t("مجمّد", "Frozen")) }
        if let phone = member.phoneNumber, !phone.isEmpty { parts.append(KuwaitPhone.display(phone)) }
        return parts.joined(separator: "، ")
    }

    /// «عرض المزيد» — الشريحة الموحّدة بلون المجال في وسط السطر
    private var loadMoreButton: some View {
        DSChipButton(L10n.t(
            "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
            "Show more (\(filteredMembers.count - displayLimit) remaining)"
        ), icon: "arrow.down.circle.fill", tint: tint) {
            displayLimit += 20
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty States

    private var noResultsState: some View {
        DSEmptyView(L10n.t("لا يوجد نتائج", "No results found"),
                    message: L10n.t("جرّب اسماً آخر أو غيّر الفلتر", "Try another name or change the filter"),
                    style: .compact)
    }
}

// MARK: - صف القائمة الشفاف (نمط صفحات الإدارة)

private extension View {
    /// صف بلا خلفية ولا فاصل، بهوامش الصفحة — المحتوى نفسه يرسم صندوقه
    func registryListRow(top: CGFloat = DS.Spacing.xs, bottom: CGFloat = DS.Spacing.xs,
                         horizontal: CGFloat = DS.Spacing.lg) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
    }
}
