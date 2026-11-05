import SwiftUI

// MARK: - «العائلة» = صفحة الأعضاء الواحدة (النموذج الأول — طلب المالك ٢٠٢٦-١٠-٢٠ «نفّذ كل المقترح»؛ مبسّطة ٢٠٢٦-١١-٠٢)
//
// التبسيط (اختيار المالك ٢٠٢٦-١١-٠٢، `samples/simplify`): رأس كحلي بالحلقات (`AdminMembersHeader.swift` — مفتوح ومطويّ)،
// «＋ تسجيل عضو» للمالك والمدير، PDF بالشريحة والفرع والبحث الحاليين، العنوان قائمة الأقسام، حقل بحث واحد (الاسم أو الرقم)،
// وأربع شرائح فقط: الكل · مسجّلون · متوفون · ناقصة («ناقصة» = البيانات الناقصة + مشكلات الشجرة + «تحقق من الأحياء»)
// ← «الفرع: الكل ⌄» (فرع بأي مستوى) وفي الطرف «2,719 عضو · أبجدياً» ← قائمة واحدة أبجدياً (الصورة · الاسم · «فرع X» أو
// سبب النقص · شارة الحالة) بـ«عرض المزيد». الضغط على عضو يفتح ورقته (`AdminMemberSheet`) بالسابق/التالي في القائمة نفسها،
// وأزرار الإصلاح فيها كما كانت؛ مرشّح «تحقق من الأحياء» يبقى صفّه بزرّي «متوفى» و«حي ✓».
// حُذف: السطر الذهبي، «طلبا انضمام قيد المراجعة»، سطر «اكتمال البيانات / سلامة الشجرة»، بطاقات الفروع و«التقسيم»،
// والشرائح الفرعية. الحالات والإشارات في `AdminMembersModel.swift`. الصلاحيات كما كانت: الصفحة لـ`canEditMembers`، التسجيل
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
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// «حي ✓» المحلية لهذا المستخدم
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adminBackTitle) private var outerBack

    /// رأس الحلقات (`AdminMembersHeader.swift`): أرقامها، شجرة النساء (لعدد النساء)، والطيّ عند التمرير
    @State private var census = AdminFamilyCensus()
    @State private var womenRows: [FamilyMember] = WomenStore.cache
    @State private var collapsed = false
    @State private var compactLine: CGFloat = DS.Hub.compactBar
    /// زرّ البحث في السطر المطويّ: يرجع لأعلى ثم يضع المؤشر في الحقل
    @State private var topToken = 0
    @State private var searchFocus = 0

    @State private var chip: AdminMemberChip
    @State private var query = ""
    @State private var limit = Self.pageSize
    @State private var index = AdminMembersIndex.empty
    /// الآباء والأبناء (للفرع المختار) — مرة لكل تغيّر في الأعضاء
    @State private var tree = AdminFamilyTree.empty
    /// «الفرع: …» — رأس فرع بأي مستوى (nil = الكل) وذرّيته
    @State private var branchFilter: UUID?
    @State private var branchSet: Set<UUID>?
    /// أعداد الشرائح داخل الفرع المختار
    @State private var branchCounts: [AdminMembersIndex.Key: Int] = [:]
    @State private var showBranchPicker = false
    /// «ناقصة» محسوبة مرة لكل تغيّر (الفهرس أو «حي ✓») — مواضع الفهرس بالترتيب الأبجدي
    @State private var incomplete: [Int] = []
    @State private var sheet: AdminMemberSheetContext?
    @State private var showExport = false
    /// «زر التقارير» بالفلتر الحالي: الشريحة والفرع والبحث — nil = كل العائلة
    @State private var exportScope: AdminReportScope?
    /// «متوفى» من مرشّح «تحقق من الأحياء» — مربّع تسجيل الوفاة الموجود (`AdminMemberDetailSheet(deathOnly:)`)
    @State private var deathTarget: FamilyMember?

    static let pageSize = 40

    /// `sub` باقٍ لمن يفتح الصفحة به (الشرائح الفرعية حُذفت في التبسيط) — يُتجاهل
    init(chip: AdminMemberChip = .all, sub: AdminMemberSub = .all) {
        _chip = State(initialValue: chip.shownChip)
    }

    var body: some View {
        AdminHubPage(pinned: collapsed ? AnyView(compactBar.transition(.opacity)) : nil, topToken: topToken) {
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
        .modifier(AdminBranchPickerBox(isPresented: $showBranchPicker, members: memberVM.allMembers,
                                       selected: branchFilter, onSelect: { pickBranch($0) }))
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
            // عدد النساء في الحلقة — من كاش شجرة النساء، أو جلب للقراءة مرة إن لم تُحمَّل
            if womenRows.isEmpty, let fetched = try? await WomenStore.fetch() {
                womenRows = fetched
                refreshCensus()
            }
        }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: accounts.accounts) { _ in rebuild() }
        .onChange(of: accounts.loaded) { _ in rebuild() }
        .onChange(of: verified.ids) { _ in refreshIncomplete() }
        .onChange(of: query) { _ in limit = Self.pageSize }
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded,
                                        branchName: { names.branchName(for: $0) })
        tree = AdminFamilyTree(memberVM.allMembers)
        applyBranchFilter()
        refreshIncomplete()
        refreshCensus()
    }

    /// أرقام الحلقات — مع كل بناء للفهرس، وبعد وصول شجرة النساء
    private func refreshCensus() {
        census = AdminFamilyCensus.make(members: memberVM.allMembers, women: womenRows)
    }

    /// «ناقصة» = اتحاد «بيانات ناقصة» و«مشكلات الشجرة» ومرشّحي «تحقق من الأحياء» بلا من راجعه المستخدم («حي ✓»)
    private func refreshIncomplete() {
        var set = Set(index.rows(.gaps, .all))
        set.formUnion(index.rows(.problems, .all))
        set.formUnion(index.rows(.verifyLiving, .all).filter { !verified.ids.contains(index.entries[$0].id) })
        incomplete = set.sorted()
    }

    // MARK: الطيّ عند التمرير

    /// الشرائح وصلت تحت سطر الرأس المطويّ ← يُثبَّت السطر والشرائح فوقها في الموضع نفسه؛ وتعود الصفحة لرأسها الكامل حين تنزل
    private func chipsMoved(_ top: CGFloat) {
        let shouldCollapse = top < compactLine
        guard shouldCollapse != collapsed else { return }
        if reduceMotion {
            collapsed = shouldCollapse
        } else {
            withAnimation(DS.Anim.quick) { collapsed = shouldCollapse }
        }
    }

    private var compactBar: some View {
        AdminMembersCompactBar(total: census.counts.total,
                               backTitle: outerBack ?? L10n.t("اليوم", "Today"),
                               back: { dismiss() },
                               search: {
                                   topToken += 1
                                   DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : DS.Hub.compactSearchDelay)) {
                                       searchFocus += 1
                                   }
                               },
                               register: authVM.canRegisterMembers ? { Self.registerPage } : nil,
                               chips: AnyView(chipsRow),
                               lineHeight: $compactLine)
    }

    private static var registerPage: AnyView {
        AnyView(AdminRegisterMemberView().adminBackTitle(AdminArea.family.title).adminArea(.family))
    }

    // MARK: الفرع المختار

    private func pickBranch(_ id: UUID?) {
        guard id != branchFilter else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        branchFilter = id
        applyBranchFilter()
        limit = Self.pageSize
    }

    /// ذرّية الفرع المختار وأعداد الشرائح داخله
    private func applyBranchFilter() {
        guard let head = branchFilter else {
            branchSet = nil
            branchCounts = [:]
            return
        }
        let set = tree.subtree(of: head)
        branchSet = set
        var counts: [AdminMembersIndex.Key: Int] = [:]
        for (key, rows) in index.lists where key.sub == .all {
            counts[key] = rows.reduce(0) { $0 + (set.contains(index.entries[$1].id) ? 1 : 0) }
        }
        branchCounts = counts
    }

    /// عدد الشريحة — داخل الفرع المختار إن وُجد («ناقصة» من اتحادها)
    private func chipCount(_ c: AdminMemberChip) -> Int? {
        if c == .gaps {
            guard index.built else { return nil }
            guard let set = branchSet else { return incomplete.count }
            return incomplete.reduce(0) { $0 + (set.contains(index.entries[$1].id) ? 1 : 0) }
        }
        guard let base = index.shownCount(c) else { return nil }
        guard branchSet != nil else { return base }
        return branchCounts[AdminMembersIndex.Key(chip: c, sub: .all)] ?? 0
    }

    /// اسم الفرع المختار في الشريحة (الاسم المختصر للرأس — الأسماء المخصّصة لصفوف قائمة الفروع فقط)
    private var branchFilterTitle: String? {
        guard let id = branchFilter else { return nil }
        let m = tree.byId[id] ?? memberVM.member(byId: id)
        return m.map { $0.shortFullName.isEmpty ? $0.fullName : $0.shortFullName } ?? L10n.t("فرع", "Branch")
    }

    // MARK: الرأس

    private var headerButtons: some View {
        HStack(spacing: DS.Spacing.sm) {
            // «تسجيل عضو جديد» — بيته الوحيد (المالك والمدير)
            if authVM.canRegisterMembers {
                NavigationLink {
                    AdminLazyPage { Self.registerPage }
                } label: {
                    // رمز عارٍ كأزرار رأس «اليوم» (طلب المالك ٢٠٢٦-١١-٠٢ — كانت كبسولة «＋ تسجيل عضو» تُقصّ)
                    AdminGlassCircle(symbol: "person.badge.plus")
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register a new member"))
            }
            if authVM.isAdmin { reportsButton }
        }
    }

    /// زر «التقارير» المباشر للمالك والمدير — يفتح التقارير بالشريحة والفرع والبحث الحاليين
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

    /// تحت العنوان: الحلقات، ثم البحث والشرائح — موضع الشرائح يقرّر طيّ الرأس
    private var headerAccessory: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AnyView(AdminFamilyCensusBand(census: census, openMen: { select(.all) }))
            AdminBandSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم أو رقم الهاتف", "Search by name or phone"),
                                 focusToken: searchFocus)
            chipsRow
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(AdminHubScroll.space)).minY } action: { chipsMoved($0) }
        }
        .padding(.top, DS.Spacing.xsm)
    }

    private var chipsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(AdminMemberChip.shown) { c in
                        AdminBandFilterChip(title: c.title, count: c == .all ? nil : chipCount(c), selected: c == chip) {
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

    private func select(_ c: AdminMemberChip) {
        guard c != chip else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) {
            chip = c
            limit = Self.pageSize
        }
    }

    /// الفلتر الحالي للتصدير: الشريحة · الفرع · «البحث» — بلا فلتر = كل العائلة
    private var currentExportScope: AdminReportScope? {
        let q = trimmedQuery
        guard chip != .all || !q.isEmpty || branchFilter != nil else { return nil }
        var parts = [chip.title]
        if let b = branchFilterTitle { parts.append(L10n.t("الفرع: \(b)", "Branch: \(b)")) }
        if !q.isEmpty { parts.append("«\(q)»") }
        return AdminReportScope(ids: Set(currentRows.map { index.entries[$0].id }), title: parts.joined(separator: " · "))
    }

    // MARK: المحتوى

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !trimmedQuery.isEmpty }

    private var content: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            if !index.built {
                if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                              message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                              retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
                } else {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
                }
            } else {
                AnyView(listSection)
            }
        }
    }

    // MARK: القائمة

    /// الصفوف المعروضة الآن: الشريحة، ثم الفرع المختار، ثم البحث (الاسم أو الرقم)
    private var currentRows: [Int] {
        var base = chip == .gaps ? incomplete : index.rows(chip, .all)
        if let set = branchSet { base = base.filter { set.contains(index.entries[$0].id) } }
        let q = trimmedQuery
        guard !q.isEmpty else { return base }
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب (والرقم أرقاماً فقط)
        if NameSearch.isPhoneQuery(q) {
            let digits = NameSearch.digits(q)
            return digits.count >= 3 ? base.filter { index.entries[$0].digits.contains(digits) } : []
        }
        let words = NameSearch.words(q)
        var hits: [(order: Int, score: Int, row: Int)] = []
        for (n, i) in base.enumerated() {
            if let score = NameSearch.score(queryWords: words, candidateWords: NameSearch.words(index.entries[i].needle)) {
                hits.append((order: n, score: score, row: i))
            }
        }
        hits.sort { $0.score != $1.score ? $0.score < $1.score : $0.order < $1.order }
        return hits.map(\.row)
    }

    @ViewBuilder
    private var listSection: some View {
        let rows = currentRows
        AnyView(AdminMembersFilterBar(branchTitle: branchFilterTitle,
                                      countText: countText(rows.count),
                                      pickBranch: { showBranchPicker = true },
                                      clearBranch: { pickBranch(nil) }))
        if rows.isEmpty {
            AdminPageStateCard(emptyState)
        } else {
            AnyView(listCard(rows))
        }
    }

    /// «2,719 عضو · أبجدياً» — والبحث «12 نتيجة» (النتائج بالأقرب لا أبجدياً)
    private func countText(_ n: Int) -> String {
        let number = AdminMembersFilterBar.grouped(n)
        if searching { return L10n.t("\(number) نتيجة", "\(number) results") }
        return L10n.t("\(number) عضو · أبجدياً", "\(number) members · A–Z")
    }

    private var emptyState: AdminPageStateCard.Kind {
        if searching {
            return .empty(L10n.t("لا نتائج", "No results"), message: L10n.t("جرّب اسماً آخر أو رقماً", "Try another name or number"))
        }
        switch chip {
        case .gaps: return .empty(L10n.t("لا شيء ناقص", "Nothing incomplete"),
                                  message: L10n.t("البيانات مكتملة والشجرة سليمة", "The data is complete and the tree is healthy"),
                                  tint: DS.Color.success)
        default:    return .empty(L10n.t("لا أحد هنا الآن", "Nobody here right now"))
        }
    }

    private func listCard(_ rows: [Int]) -> some View {
        let visible = Array(rows.prefix(limit))
        let ids = rows.map { index.entries[$0].id }
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element) { pos, i in
                    if pos > 0 { AdminRowDivider() }
                    row(i, ids: ids, position: pos)
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

    private func branchTitle(_ entry: AdminMembersIndex.Entry) -> String? {
        entry.branch.flatMap { b in index.branches.first { $0.id == b }?.title }
    }

    /// مرشّح «تحقق من الأحياء» لم يُراجَع بعد على هذا الجهاز
    private func needsLivingCheck(_ entry: AdminMembersIndex.Entry) -> Bool {
        entry.living != nil && !verified.ids.contains(entry.id)
    }

    /// سبب الظهور في «ناقصة»: «بلا تاريخ ميلاد» / «مشكلة في الشجرة» / «تحقق: هل ما زال حياً؟» (+N حين يتعدّد)
    private func reason(_ entry: AdminMembersIndex.Entry) -> String {
        var reasons = entry.gaps.filter { $0 != .deathIncomplete }.map(\.tag)
        if !entry.problems.isEmpty { reasons.append(L10n.t("مشكلة في الشجرة", "Tree problem")) }
        if needsLivingCheck(entry) { reasons.append(L10n.t("تحقق: هل ما زال حياً؟", "Check: still alive?")) }
        guard let first = reasons.first else { return "" }
        return reasons.count > 1 ? "\(first) · +\(reasons.count - 1)" : first
    }

    @ViewBuilder
    private func row(_ i: Int, ids: [UUID], position: Int) -> some View {
        let entry = index.entries[i]
        if chip == .gaps && needsLivingCheck(entry) {
            // «متوفى» و«حي ✓» في الصفّ نفسه (لا مكان لهما في ورقة العضو)
            AnyView(livingRow(entry, ids: ids, position: position))
        } else {
            Button {
                sheet = AdminMemberSheetContext(ids: ids, start: position)
            } label: {
                AdminMemberListRow(entry: entry, subline: chip == .gaps ? reason(entry) : (branchTitle(entry) ?? ""),
                                   warns: chip == .gaps)
            }
            .buttonStyle(.plain)
        }
    }

    private func livingRow(_ entry: AdminMembersIndex.Entry, ids: [UUID], position: Int) -> some View {
        AdminLivingCheckRow(entry: entry,
                            reason: L10n.t("تحقق: هل ما زال حياً؟", "Check: still alive?"),
                            canEdit: authVM.canEditMembers,
                            open: { sheet = AdminMemberSheetContext(ids: ids, start: position) },
                            deceased: { deathTarget = entry.member },
                            alive: {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation(DS.Anim.snappy) { verified.markAlive(entry.id) }
                            })
    }
}

// MARK: - «الفرع: الكل ⌄» والعدد فوق القائمة

struct AdminMembersFilterBar: View {
    /// اسم الفرع المختار — nil = «الكل»
    let branchTitle: String?
    let countText: String
    let pickBranch: () -> Void
    let clearBranch: () -> Void

    /// «2,719» — فاصل الآلاف بأرقام لاتينية (كأرقام اللوحة)
    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Button(action: pickBranch) {
                AdminChoiceChip(title: L10n.t("الفرع: \(branchTitle ?? "الكل")", "Branch: \(branchTitle ?? "All")"),
                                isSelected: branchTitle != nil, expands: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("يفتح قائمة الفروع", "Opens the branch list"))
            if branchTitle != nil {
                Button(action: clearBranch) {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lg, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("كل الفروع", "All branches"))
            }
            Spacer(minLength: DS.Spacing.sm)
            Text(verbatim: countText)
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
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

/// صفّ عضو: الصورة · الاسم · سطر صغير («فرع X» أو سبب النقص) · شارة حالة واحدة (مسجّل · مقيّد · موقوف · متوفى)
struct AdminMemberListRow: View {
    let entry: AdminMembersIndex.Entry
    let subline: String
    /// السطر سبب نقص («ناقصة») — بلون التنبيه
    var warns: Bool = false
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
                            .foregroundColor(warns ? DS.Color.warning.dsReadableGlyph : DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                if !stacked { Spacer(minLength: DS.Spacing.xs) }
                if let status = entry.status {
                    DSStatusChip(text: status.shortTitle, tint: status == .treeOnly ? DS.Color.textTertiary : status.tint)
                        .fixedSize()
                        .accessibilityLabel(status.title)
                }
            }
            if stacked { Spacer(minLength: 0) }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))
    }
}

// MARK: - صفّ «تحقق من الأحياء» (داخل «ناقصة»)

/// الصورة · الاسم · السبب و«مواليد 1935 · 91 سنة»، وتحتها «متوفى» و«حي ✓» (الرمز SF بعد النص — علامة ✓ النصية تُرسم
/// بخط Plex كأنها «٧») — تحت النص دائماً حتى يبقى الاسم كاملاً. الضغط على الاسم يفتح ورقة العضو
struct AdminLivingCheckRow: View {
    let entry: AdminMembersIndex.Entry
    /// سبب الظهور في «ناقصة» («تحقق: هل ما زال حياً؟» …)
    let reason: String
    let canEdit: Bool
    let open: () -> Void
    let deceased: () -> Void
    let alive: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var member: FamilyMember { entry.member }

    /// السبب و«مواليد 1935 · 91 سنة» إن عُرف الميلاد — سطر واحد
    private var subline: String {
        guard let y = entry.living?.birthYear else { return reason }
        let age = Calendar(identifier: .gregorian).component(.year, from: Date()) - y
        return [reason, L10n.t("مواليد \(y) · \(age) سنة", "Born \(y) · \(age) yrs")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
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
                        .foregroundColor(DS.Color.warning.dsReadableGlyph)
                        .lineLimit(typeSize >= .xxxLarge ? nil : 1)
                        .fixedSize(horizontal: false, vertical: typeSize >= .xxxLarge)
                }
                Spacer(minLength: 0)
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

        // الزرّان تحت النص بمحاذاته (بعد الصورة)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            person
            if canEdit {
                buttons.padding(.leading, typeSize.isAccessibilitySize ? 0 : DS.Icon.avatar + DS.Spacing.md)
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
    /// كل تغيّر فيه يضع المؤشر في الحقل (زرّ البحث في الرأس المطويّ)
    var focusToken: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(DS.Hub.onBandMuted)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(DS.Hub.onBandMuted))
                .dsFieldFont(.fieldValue)
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
        .onChange(of: focusToken) { _ in focused = true }
    }
}
