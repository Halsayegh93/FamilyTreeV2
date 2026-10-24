import SwiftUI

// MARK: - «العائلة» = صفحة الأعضاء الواحدة (النموذج الأول — طلب المالك ٢٠٢٦-١٠-٢٠ «نفّذ كل المقترح»)
//
// بدل ٧ صفحات (سجل الأعضاء، جودة البيانات، الحسابات والاستخدام/محطة التفعيل، قوائم استخدام التطبيق، صحة الشجرة،
// أسماء العوائل، تسجيل عضو): رأس كحلي (‹ اليوم، «＋ تسجيل عضو جديد» للمالك والمدير، «⋯» تصدير/شجرة النساء، العنوان
// قائمة الأقسام، حقل بحث واحد، شرائح بالأعداد الحقيقية) ← «طلبا انضمام قيد المراجعة» رقم يفتح الوارد ← شرائح فرعية
// ← سطر ملخّص (اكتمال البيانات، سلامة الشجرة، توزيع المسجّلين) ← القائمة (بالفروع في «الكل» بلا بحث) ← الضغط على
// عضو يفتح ورقته الواحدة (`AdminMemberSheet`) بالسابق/التالي داخل القائمة نفسها. لا تبويبات علوية.
// الحالات والإشارات في `AdminMembersModel.swift`. الصلاحيات كما كانت: الصفحة لـ`canEditMembers`، التسجيل
// `canRegisterMembers`، التصدير `isAdmin`.

/// ورقة العضو مفتوحة على قائمة (السابق/التالي يتنقّلان فيها)
struct AdminMemberSheetContext: Identifiable {
    let id = UUID()
    let ids: [UUID]
    let start: Int
}

struct AdminMembersPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// «حي ✓» المحلية لهذا المستخدم
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var chip: AdminMemberChip
    @State private var sub: AdminMemberSub = .all
    @State private var query = ""
    @State private var limit = Self.pageSize
    @State private var index = AdminMembersIndex.empty
    /// الفرع المفتوح في «الكل» (مفتاحه، «» = لا شيء؛ nil قبل أول بناء — يُفتح أولها)
    @State private var openBranch: String? = nil
    @State private var branchLimit = Self.branchPreview
    @State private var sheet: AdminMemberSheetContext?
    @State private var showExport = false
    /// «زر التقارير» بالفلتر الحالي (الدفعة ج): الشريحة والبحث المختاران — nil = كل العائلة
    @State private var exportScope: AdminReportScope?
    /// «متوفى» من «تحقق من الأحياء» — مربّع تسجيل الوفاة الموجود (`AdminMemberDetailSheet(deathOnly:)`)
    @State private var deathTarget: FamilyMember?
    /// «عرض المزيد» لكل قسم في «تحقق من الأحياء»
    @State private var groupLimits: [AdminLivingCheck.Group: Int] = [:]

    static let pageSize = 30
    static let branchPreview = 8

    init(chip: AdminMemberChip = .all, sub: AdminMemberSub = .all) {
        _chip = State(initialValue: chip)
        _sub = State(initialValue: sub)
    }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: AdminArea.family.title, isAreaRoot: true) {
                AnyView(headerButtons)
            } accessory: {
                AnyView(headerAccessory)
            }
        } content: {
            AnyView(content)
        }
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
        .modifier(AdminLivingDeathBox(member: $deathTarget))
        .navigationDestination(isPresented: $showExport) {
            AdminLazyPage { [exportScope] in
                AnyView(AdminReportsView(scope: exportScope).adminBackTitle(AdminArea.family.title).adminArea(.family))
            }
        }
        .task {
            verified.activate(user: authVM.currentUser?.id)
            if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
            rebuild()
            await accounts.refresh()
        }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: accounts.accounts) { _ in rebuild() }
        .onChange(of: accounts.loaded) { _ in rebuild() }
        .onChange(of: query) { _ in limit = Self.pageSize }
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded,
                                        branchName: { names.branchName(for: $0) })
        if openBranch == nil, let first = index.branches.first { openBranch = Self.key(first) }
    }

    // MARK: الرأس

    private var headerButtons: some View {
        HStack(spacing: DS.Spacing.sm) {
            // «تسجيل عضو جديد» — بيته الوحيد (المالك والمدير)
            if authVM.canRegisterMembers {
                NavigationLink {
                    AdminLazyPage { AnyView(AdminRegisterMemberView().adminBackTitle(AdminArea.family.title).adminArea(.family)) }
                } label: {
                    if typeSize >= .accessibility1 {
                        AdminGlassCircle(symbol: "person.badge.plus")
                    } else {
                        AdminPillLabel(title: L10n.t("تسجيل عضو جديد", "Register member"), icon: "person.badge.plus",
                                       style: .gold, height: DS.Hub.glassButton)
                    }
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register a new member"))
            }
            if authVM.isAdmin { reportsButton }
        }
    }

    /// زر «التقارير» المباشر للمالك والمدير (طلب المالك ٢٠٢٦-١٠-٢٠: «الاختصار الثاني يدش على التقارير دايركت»)
    /// — بدل قائمة «⋯»؛ يفتح التقارير بالشريحة المختارة. اختصار «شجرة النساء» أُزيل: بيتها الواحد تبويب الشجرة.
    private var reportsButton: some View {
        Button {
            exportScope = currentExportScope
            showExport = true
        } label: {
            AdminGlassCircle(symbol: "doc.text")
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("التقارير (PDF)", "Reports (PDF)"))
    }

    private var headerAccessory: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminBandSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم أو رقم الهاتف", "Search by name or phone"))
            chipsRow
        }
        .padding(.top, DS.Spacing.md)
    }

    private var chipsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(visibleChips) { c in
                        AdminBandFilterChip(title: c.title, count: c == .verifyLiving ? (index.built ? verifyCount : nil)
                                                                                      : index.shownCount(c),
                                            selected: c == chip) {
                            select(c)
                        }
                        .id(c)
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
            .onAppear {
                // بعد أول تخطيط — الشريحة المختارة (من «اليوم» أو التنبيه) ظاهرة كاملة
                guard chip != .all else { return }
                DispatchQueue.main.async { proxy.scrollTo(chip, anchor: .center) }
            }
        }
    }

    /// «تحقق من الأحياء» تختفي حين تفرغ قائمتها (وتبقى ما دامت مختارة — حتى لا تقفز الصفحة بعد آخر مراجعة)
    private var visibleChips: [AdminMemberChip] {
        AdminMemberChip.allCases.filter { $0 != .verifyLiving || chip == .verifyLiving || verifyCount > 0 }
    }

    /// مرشّحو «تحقق من الأحياء» بلا من راجعه هذا المستخدم («حي ✓»)
    private var verifyRows: [Int] {
        index.rows(.verifyLiving, .all).filter { !verified.ids.contains(index.entries[$0].id) }
    }

    private var verifyCount: Int { verifyRows.count }

    private func select(_ c: AdminMemberChip) {
        guard c != chip else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) {
            chip = c
            sub = .all
            limit = Self.pageSize
        }
    }

    /// الفلتر الحالي للتصدير: الشريحة · الشريحة الفرعية · «البحث» — بلا فلتر = كل العائلة
    private var currentExportScope: AdminReportScope? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chip != .all || sub != .all || !q.isEmpty else { return nil }
        var parts = [chip.title]
        if sub != .all { parts.append(sub.title) }
        if !q.isEmpty { parts.append("«\(q)»") }
        return AdminReportScope(ids: Set(currentRows.map { index.entries[$0].id }), title: parts.joined(separator: " · "))
    }

    // MARK: المحتوى

    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var content: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            if joinCount > 0 {
                AnyView(joinBanner)
            }
            if !index.built {
                if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                              message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                              retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
                } else {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
                }
            } else {
                // «الكل»: شريحة «قُيّدوا هذا الأسبوع» حين يوجد جدد فقط (بلا شرائح فرعية غيرها — القائمة بالفروع)
                if !chip.subs.isEmpty && (chip != .all || sub != .all || index.count(.all, .newThisWeek) > 0) {
                    AnyView(subChips)
                }
                AnyView(AdminMembersSummary(chip: chip, sub: sub, index: index,
                                            start: { startWalk() },
                                            verifiedCount: chip == .verifyLiving ? index.count(.verifyLiving) - verifyCount : 0,
                                            resetVerified: { withAnimation(DS.Anim.snappy) { verified.reset() } }))
                AnyView(listSection)
            }
        }
    }

    // MARK: طلبات الانضمام — رقم فقط، القرار في «الوارد»

    private var joinCount: Int { max(index.pendingJoin, adminRequestVM.joinApprovalRequests.count) }

    private var joinTitle: String {
        switch joinCount {
        case 1:  return L10n.t("طلب انضمام قيد المراجعة", "1 join request under review")
        case 2:  return L10n.t("طلبا انضمام قيد المراجعة", "2 join requests under review")
        default: return L10n.t("\(joinCount) طلبات انضمام قيد المراجعة", "\(joinCount) join requests under review")
        }
    }

    private var joinBanner: some View {
        let single = adminRequestVM.joinApprovalRequests.count == 1 ? adminRequestVM.joinApprovalRequests.first?.id : nil
        return NavigationLink {
            AdminLazyPage {
                AnyView(AdminAllRequestsView(focusId: single).adminArea(.inbox).adminBackTitle(AdminArea.family.title))
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: "person.badge.plus", tint: DS.Color.warning)
                Text(joinTitle)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.warning.dsReadableGlyph)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.xs)
                AdminCardLinkLabel(title: L10n.t("في الوارد", "In the inbox"))
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
        .accessibilityHint(L10n.t("يفتح الوارد — القرار هناك", "Opens the inbox — decide there"))
    }

    // MARK: الشرائح الفرعية

    private var subChips: some View {
        let options = chip.subs.map { s in
            DSFilterOption(id: s, title: s.title, count: index.shownCount(chip, s))
        }
        return DSFilterChips(options: options, selection: Binding(get: { sub }, set: { new in
            sub = new
            limit = Self.pageSize
        }))
    }

    // MARK: القائمة

    /// الصفوف المعروضة الآن: الشريحة (والفرعية)، ثم البحث
    private var currentRows: [Int] {
        let base = chip == .verifyLiving ? verifyRows : index.rows(chip, sub)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        let digits = AdminMemberFacts.asciiDigits(q)
        return base.filter { i in
            let e = index.entries[i]
            return e.needle.contains(needle) || (digits.count >= 3 && e.digits.contains(digits))
        }
    }

    @ViewBuilder
    private var listSection: some View {
        let rows = currentRows
        if chip == .all && sub == .all && !searching {
            AdminSectionLabel(title: L10n.t("حسب الفرع", "By branch"),
                              trailing: L10n.t("\(index.branches.count) فروع", "\(index.branches.count) branches"))
            ForEach(index.branches) { branch in
                AnyView(branchCard(branch))
            }
        } else if rows.isEmpty {
            AdminPageStateCard(emptyState)
        } else if chip == .verifyLiving {
            if searching {
                AdminSectionLabel(title: L10n.t("النتائج", "Results"), trailing: "\(rows.count)")
            }
            ForEach(Self.livingGroups(rows, index: index)) { group in
                AdminSectionLabel(title: "\(group.group.title) · \(group.positions.count)")
                AnyView(livingCard(group, rows: rows))
            }
        } else {
            if searching {
                AdminSectionLabel(title: L10n.t("النتائج", "Results"), trailing: "\(rows.count)")
            }
            AnyView(listCard(rows))
        }
    }

    private var emptyState: AdminPageStateCard.Kind {
        if searching {
            return .empty(L10n.t("لا نتائج", "No results"), message: L10n.t("جرّب اسماً آخر أو رقماً", "Try another name or number"))
        }
        switch chip {
        case .gaps:     return .empty(L10n.t("البيانات مكتملة", "Data is complete"), tint: DS.Color.success)
        case .problems: return .empty(L10n.t("الشجرة سليمة", "The tree is healthy"),
                                      message: L10n.t("لا مشكلات الآن", "No problems right now"), tint: DS.Color.success)
        case .verifyLiving: return .empty(L10n.t("تمت المراجعة", "All reviewed"),
                                          message: L10n.t("لا أسماء من كبار السن بانتظار المراجعة", "No elderly names left to review"),
                                          tint: DS.Color.success)
        default:        return .empty(L10n.t("لا أحد هنا الآن", "Nobody here right now"))
        }
    }

    private func listCard(_ rows: [Int]) -> some View {
        let visible = Array(rows.prefix(limit))
        let ids = rows.map { index.entries[$0].id }
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element) { pos, i in
                    if pos > 0 { AdminRowDivider() }
                    rowButton(i, ids: ids, position: pos)
                }
            }
            if rows.count > limit {
                AdminPillButton(title: L10n.t("عرض المزيد (\(rows.count - limit))", "Show more (\(rows.count - limit))"),
                                icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                    limit += Self.pageSize
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func branchCard(_ branch: AdminMembersIndex.Branch) -> some View {
        let isOpen = openBranch == Self.key(branch)
        let ids = branch.rows.map { index.entries[$0].id }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DS.Anim.snappy) {
                    openBranch = isOpen ? "" : Self.key(branch)
                    branchLimit = Self.branchPreview
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Text(branch.title)
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    AdminCountChip(count: branch.rows.count)
                    Spacer(minLength: DS.Spacing.xs)
                    Image(systemName: "chevron.down")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                        .foregroundColor(DS.Color.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? L10n.t("يطوي الفرع", "Collapses the branch") : L10n.t("يعرض أعضاء الفرع", "Shows the branch"))
            if isOpen {
                AdminRowDivider()
                LazyVStack(spacing: 0) {
                    ForEach(Array(branch.rows.prefix(branchLimit).enumerated()), id: \.element) { pos, i in
                        if pos > 0 { AdminRowDivider() }
                        rowButton(i, ids: ids, position: pos)
                    }
                }
                if branch.rows.count > branchLimit {
                    AdminPillButton(title: L10n.t("عرض المزيد (\(branch.rows.count - branchLimit))",
                                                  "Show more (\(branch.rows.count - branchLimit))"),
                                    icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                        branchLimit += Self.pageSize
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private static func key(_ branch: AdminMembersIndex.Branch) -> String { branch.id?.uuidString ?? "outside" }

    // MARK: «تحقق من الأحياء» — بأقسام الميلاد («بلا تاريخ ميلاد» ← «قبل 1940» ← الباقون)، الأقدم أولاً

    struct LivingGroup: Identifiable {
        let group: AdminLivingCheck.Group
        /// مواضع الصفوف في القائمة الحالية (السابق/التالي في الورقة يمشي فيها كلها)
        let positions: [Int]
        var id: Int { group.rawValue }
    }

    /// صفّ في بطاقة القسم — هويته العضو نفسه (لا موضعه: «حي ✓» يزيح المواضع)
    struct LivingSlot: Identifiable {
        let pos: Int
        let id: UUID
    }

    /// القائمة مرتّبة بالقسم (`AdminLivingCheck.ordered`) — تُقسم حيث يتغيّر القسم (البحث يبقي الترتيب نفسه)
    static func livingGroups(_ rows: [Int], index: AdminMembersIndex) -> [LivingGroup] {
        var groups: [(AdminLivingCheck.Group, [Int])] = []
        for (pos, i) in rows.enumerated() {
            let g = index.entries[i].living?.group ?? .rest
            if groups.last?.0 == g { groups[groups.count - 1].1.append(pos) } else { groups.append((g, [pos])) }
        }
        return groups.map { LivingGroup(group: $0.0, positions: $0.1) }
    }

    private func livingCard(_ group: LivingGroup, rows: [Int]) -> some View {
        let limit = groupLimits[group.group] ?? Self.branchPreview
        let ids = rows.map { index.entries[$0].id }
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(group.positions.prefix(limit).map { LivingSlot(pos: $0, id: ids[$0]) }) { slot in
                    if slot.pos != group.positions.first { AdminRowDivider() }
                    livingRow(rows[slot.pos], ids: ids, position: slot.pos)
                }
            }
            if group.positions.count > limit {
                AdminPillButton(title: L10n.t("عرض المزيد (\(group.positions.count - limit))",
                                              "Show more (\(group.positions.count - limit))"),
                                icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                    groupLimits[group.group] = limit + Self.pageSize
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func livingRow(_ i: Int, ids: [UUID], position: Int) -> some View {
        let entry = index.entries[i]
        let canEdit = authVM.canEditMembers
        return AdminLivingCheckRow(entry: entry,
                                   branchTitle: entry.branch.flatMap { b in index.branches.first { $0.id == b }?.title },
                                   canEdit: canEdit,
                                   open: { sheet = AdminMemberSheetContext(ids: ids, start: position) },
                                   deceased: { deathTarget = entry.member },
                                   alive: {
                                       UINotificationFeedbackGenerator().notificationOccurred(.success)
                                       withAnimation(DS.Anim.snappy) { verified.markAlive(entry.id) }
                                   })
    }

    private func rowButton(_ i: Int, ids: [UUID], position: Int) -> some View {
        let entry = index.entries[i]
        return Button {
            sheet = AdminMemberSheetContext(ids: ids, start: position)
        } label: {
            AdminMemberListRow(entry: entry, chip: chip,
                               branchTitle: entry.branch.flatMap { b in index.branches.first { $0.id == b }?.title })
        }
        .buttonStyle(.plain)
    }

    /// «ابدأ الاستكمال» / «ابدأ المراجعة»: ورقة العضو على أول القائمة الحالية، و«التالي» يمشي فيها عضواً عضواً
    private func startWalk() {
        let rows = currentRows
        guard !rows.isEmpty else { return }
        sheet = AdminMemberSheetContext(ids: rows.map { index.entries[$0].id }, start: 0)
    }
}

// MARK: - سطر الملخّص تحت الشرائح

struct AdminMembersSummary: View {
    let chip: AdminMemberChip
    let sub: AdminMemberSub
    let index: AdminMembersIndex
    let start: () -> Void
    /// «تحقق من الأحياء»: من راجعهم المستخدم «حي ✓» على جهازه، وإعادة إظهارهم
    var verifiedCount: Int = 0
    var resetVerified: () -> Void = {}
    @State private var showsLivingHow = false

    var body: some View {
        switch chip {
        case .verifyLiving: AnyView(livingCard)
        case .gaps:       AnyView(gapsCard)
        case .problems:   AnyView(problemsCard)
        case .registered: AnyView(EmptyView()) // توزيعها في الشرائح الفرعية فوق القائمة
        case .treeOnly:   AnyView(note(L10n.t("أسماء في الشجرة بلا حساب في التطبيق. من له رقم يمكن دعوته، ويصير «عضواً مسجّلاً» حين يسجّل الدخول.",
                                              "Names in the tree with no app account. Anyone with a number can be invited; they become registered once they sign in."),
                                       icon: "person.crop.circle.badge.questionmark"))
        case .deceased:
            let n = index.count(.deceased, .deathIncomplete)
            if n > 0 {
                AnyView(note(L10n.t("\(n) متوفى تاريخ وفاته غير مكتمل — لا تظهر ذكراهم في «ذكرى الراحلين».",
                                    "\(n) have an incomplete death date — their anniversary doesn't show."),
                             icon: "calendar.badge.clock"))
            } else {
                AnyView(EmptyView())
            }
        case .all:
            AnyView(EmptyView())
        }
    }

    /// شرح «تحقق من الأحياء» + «إعادة إظهار من راجعتهم» (المراجعة محلية على هذا الجهاز)
    private var livingCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: "person.fill.questionmark", tint: DS.Color.info)
                Text(L10n.t("كبار السن بلا وفاة مسجّلة — راجعهم", "Elderly with no death recorded — review them"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: DS.Spacing.xs)
                Button { showsLivingHow.toggle() } label: {
                    Text(L10n.t("كيف يُحسب", "How it's counted"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.info.dsReadableGlyph)
                }
                .buttonStyle(.plain)
            }
            if showsLivingHow {
                Text(L10n.t("بلا تاريخ ميلاد، ثم مواليد قبل \(AdminLivingCheck.oldBirthYear)، ثم الباقون — الأقدم أولاً. «متوفى» يسجّل الوفاة (التاريخ اختياري)، و«حي» يخفي الاسم من هذه القائمة على جهازك فقط.",
                            "No birth date, then born before \(AdminLivingCheck.oldBirthYear), then the rest — oldest first. “Deceased” records the death (date optional); “Alive” hides the name from this list on this device only."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if verifiedCount > 0 {
                HStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("راجعتَ \(verifiedCount) كأحياء", "You marked \(verifiedCount) as alive"))
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                    Spacer(minLength: DS.Spacing.xs)
                    AdminPillButton(title: L10n.t("إعادة إظهارهم", "Show them again"), icon: "arrow.uturn.backward",
                                    style: .soft, height: DS.Hub.pillHeightCard, action: resetVerified)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func note(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: DS.Color.info)
            Text(text)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    /// «اكتمال البيانات» + «ابدأ الاستكمال» (يحلّ محلّ «جودة البيانات» و«محطة التفعيل») — صفّ الحلقة الموحّد (الدفعة ١٠)
    /// بذهبي «اليوم» كما كان
    private var gapsCard: some View {
        let empty = index.rows(.gaps, sub).isEmpty
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminScoreRow(progress: index.completeness,
                          title: L10n.t("اكتمال البيانات", "Data completeness"),
                          subtitle: L10n.t("عضو واحد في كل مرة — أكمل ثم «التالي»", "One member at a time — fill in, then “Next”"),
                          tint: DS.Color.accent)
            if !empty {
                HStack {
                    Spacer(minLength: 0)
                    AdminPillButton(title: L10n.t("ابدأ الاستكمال", "Start"), icon: L10n.isArabic ? "chevron.left" : "chevron.right",
                                    style: .navy, height: DS.Hub.pillHeightCard, action: start)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
        .accessibilityElement(children: .contain)
    }

    /// «سلامة الشجرة» (يحلّ محلّ صفحة «صحة الشجرة») — لا تعرض ١٠٠٪ ما دامت هناك ملاحظة
    private var problemsCard: some View {
        let any = index.count(.problems) > 0
        let score = index.checked > 0 ? Double(index.clean) / Double(index.checked) : 1
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminScoreRow(progress: any ? min(0.99, score) : 1,
                          title: L10n.t("سلامة الشجرة", "Tree integrity"),
                          subtitle: L10n.t("بلا ملاحظات: \(index.clean) من \(index.checked)",
                                           "No issues: \(index.clean) of \(index.checked)"))
            if !index.rows(.problems, sub).isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    AdminPillButton(title: L10n.t("ابدأ المراجعة", "Start reviewing"), icon: L10n.isArabic ? "chevron.left" : "chevron.right",
                                    style: .navy, height: DS.Hub.pillHeightCard, action: start)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

}

/// شارة عدد رمادية بجانب اسم الفرع
struct AdminCountChip: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .dsFont(.chip)
            .monospacedDigit()
            .foregroundColor(DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(minHeight: DS.Icon.section)
            .background(Capsule().fill(DS.Color.cardBackgroundSoft))
    }
}

// MARK: - صفّ العضو

/// صفّ عضو: الصورة · الاسم · سطر (الفرع/الرقم/النقص) · شارة الحالة الرسمية (أو النواقص/المشكلات في شريحتها)
struct AdminMemberListRow: View {
    let entry: AdminMembersIndex.Entry
    let chip: AdminMemberChip
    let branchTitle: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var member: FamilyMember { entry.member }

    private var avatarTint: Color {
        switch entry.status {
        case .registered: return DS.Color.palm
        case .frozen:     return DS.Color.error
        case .deceased:   return DS.Color.deceased
        default:          return DS.Color.slate
        }
    }

    private var subline: String {
        let phone = AdminMemberFacts.isBlank(member.phoneNumber) ? nil : KuwaitPhone.display(member.phoneNumber)
        switch chip {
        case .gaps:
            return [branchTitle, entry.status == .registered ? AdminMemberStatus.registered.title : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .deceased:
            if AdminMemberFacts.deathIncomplete(member) { return AdminMemberGap.deathIncomplete.title }
            return AdminMemberSheetFacts.dayText(member.deathDate).map { L10n.t("الوفاة: \($0)", "Died: \($0)") } ?? (branchTitle ?? "")
        default:
            if member.isDeceased == true { return branchTitle ?? "" }
            return phone ?? L10n.t("بلا رقم هاتف", "No phone")
        }
    }

    private var tags: [(String, Color)] {
        switch chip {
        case .gaps:
            return entry.gaps.filter { $0 != .deathIncomplete }.map { ($0.tag, DS.Color.warning) }
        case .problems:
            return entry.problems.map { ($0.title, DS.Color.warning) }
        case .deceased:
            return []
        default:
            var list: [(String, Color)] = []
            // حساب امرأة (دخول النساء) — «أنثى» أولاً (الشارة الظاهرة)، فليست من شجرة الرجال
            if member.isWomanAccount { list.append((L10n.t("أنثى", "Female"), DS.Color.female)) }
            if let status = entry.status { list.append((status.title, status.tint)) }
            return list
        }
    }

    var body: some View {
        let stacked = typeSize >= .accessibility1
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xs))
                             : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
        HStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: avatarTint)
                .grayscale(member.isDeceased == true ? 1 : 0)
                .accessibilityHidden(true)
            layout {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(member.shortFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.shortFullName)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()
                    if !subline.isEmpty {
                        Text(verbatim: subline)
                            .dsFont(.footnote)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                if !stacked { Spacer(minLength: DS.Spacing.xs) }
                tagsView
            }
            if stacked { Spacer(minLength: 0) }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var tagsView: some View {
        let list = tags
        if !list.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                DSStatusChip(text: list[0].0, tint: list[0].1)
                if list.count > 1 {
                    DSStatusChip(text: "+\(list.count - 1)", tint: list[0].1)
                }
            }
            .fixedSize()
        }
    }
}

// MARK: - صفّ «تحقق من الأحياء»

/// الصورة · الاسم · «الفرع · مواليد 1935 · 91 سنة» (أو «بلا تاريخ ميلاد») ثم «متوفى» و«حي ✓» (الرمز SF بعد النص —
/// علامة ✓ النصية تُرسم بخط Plex كأنها «٧»). الضغط على الاسم يفتح ورقة العضو.
/// من أحجام الخط الكبيرة الزرّان تحت الاسم
struct AdminLivingCheckRow: View {
    let entry: AdminMembersIndex.Entry
    let branchTitle: String?
    let canEdit: Bool
    let open: () -> Void
    let deceased: () -> Void
    let alive: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var member: FamilyMember { entry.member }

    private var subline: String {
        let birth: String
        if let y = entry.living?.birthYear {
            let age = Calendar(identifier: .gregorian).component(.year, from: Date()) - y
            birth = L10n.t("مواليد \(y) · \(age) سنة", "Born \(y) · \(age) yrs")
        } else {
            birth = L10n.t("بلا تاريخ ميلاد", "No birth date")
        }
        return [branchTitle, birth].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let stacked = typeSize >= .xxxLarge
        let name = member.shortFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.shortFullName
        let person = Button(action: open) {
            HStack(spacing: DS.Spacing.md) {
                DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: DS.Color.slate)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(name)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()
                    Text(verbatim: subline)
                        .dsFont(.footnote)
                        .monospacedDigit()
                        .foregroundColor(entry.living?.birthYear.map { $0 < AdminLivingCheck.oldBirthYear } == true
                                         ? DS.Color.warning.dsReadableGlyph : DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !stacked { Spacer(minLength: 0) }
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))

        let buttons = HStack(spacing: DS.Spacing.sm) {
            AdminPillButton(title: L10n.t("متوفى", "Deceased"), style: .soft, height: DS.Hub.pillHeightCard, action: deceased)
                .accessibilityLabel(L10n.t("تسجيل وفاة \(name)", "Record \(name)'s death"))
            AdminPillButton(title: L10n.t("حي", "Alive"), icon: "checkmark", style: .navy, height: DS.Hub.pillHeightCard,
                            iconTrailing: true, action: alive)
                .accessibilityLabel(L10n.t("\(name) حي — تمت المراجعة", "\(name) is alive — reviewed"))
        }
        .fixedSize()

        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    person
                    if canEdit { buttons }
                }
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    person
                    if canEdit { buttons }
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// مربّع «تسجيل الوفاة» — نفس `AdminMemberDetailSheet` (حفظه ونداءاته وإعلان الوفاة) مفتوحاً على التواريخ فقط
/// (في نوعه المستقل — حارس المكدس)
private struct AdminLivingDeathBox: ViewModifier {
    @Binding var member: FamilyMember?

    func body(content: Content) -> some View {
        content.dsCenterBox(item: $member) { m in
            AdminMemberDetailSheet(member: m, showsAccount: false, deathOnly: true)
        }
    }
}

// MARK: - حقل البحث فوق الكحلي

/// حقل بحث زجاجي فوق الرأس الكحلي (النص أبيض، والعدسة والتلميح فاتحان)
struct AdminBandSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(DS.Hub.onBandMuted)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(DS.Hub.onBandMuted))
                .dsFieldFont(.body)
                .foregroundColor(DS.Color.textOnPrimary)
                .tint(DS.Color.accentLight)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lgCompact, weight: .regular)
                        .foregroundColor(DS.Hub.onBandMuted)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -DS.Spacing.sm)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DSBox.searchHeight)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Hub.glass))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
            .strokeBorder(focused ? DS.Color.accentLight : DS.Hub.glassLine, lineWidth: DS.Border.width))
    }
}
