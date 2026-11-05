import SwiftUI
import UIKit

// MARK: - صفحة تصفية التقرير («منضدة التصفية» — الاتجاه «أ»، طلب المالك ٢٠٢٦-١١-٠٢)
//
// لكل تقرير صفحته، وفيها ما يناسبه فقط، من الأعلى:
//   • «النطاق»: الفرع بأي مستوى بمسار «العائلة ‹ فرع ‹ فرع» (الضغط على مستوى أعلى يصعد إليه، و«تغيير» يفتح
//     `BranchPickerSheet(allLevels:)` من `BranchPickerSheet.familyRoot`)، وشريحة «من صفحة الأعضاء» ✕ إن جاءت منها.
//   • «التصفية»: الحالة (الكل · أحياء · متوفون) · التسجيل (مسجّل · مقيّد · موقوف) · مدى العمر الحرّ بشريط (غير المعروف
//     يُستثنى متى حُدّد) · الفترة · الناقص · الهواتف · الراحلون — كل ما يخص النوع فقط.
//   • «التجميع»: الفرع · الأب · عقد الميلاد · أبجدياً · الدولة (أدوات صفحة الأعضاء `AdminGrouping`).
//   • «الأعمدة»: ✓ يُطبع · + لا · قفل دائماً، و«ترتيب» يفتح مربّع التحريك بالسهمين، و«الافتراضي» — يُحفظ لكل مستخدم ولكل
//     تقرير (`AdminReportFieldsStore`). في «الملخّص»: «الأقسام».
//   • «المعاينة»: الغلاف وأول صفحة داخلية (الضغط يفتح الملف كاملاً).
// في الرأس العدد الحيّ «سيطبع 184 فرداً»، وأسفل الصفحة زرّ «مشاركة / حفظ · 6 صفحات».
// الملف يُبنى بعد مهلة قصيرة من آخر تغيير (والسابق يُلغى) خارج الخيط الرئيسي: البناء أولاً (فيظهر العدد) ثم الرسم.
// خطّة التجميع وشجرة الآباء تُحسبان مرة لكل تغيّر في الأعضاء أو التجميع أو الفرع — لا في الجسم.

struct AdminReportFilterPage: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: AdminReportKind

    @State private var filter: AdminReportFilter
    @State private var result: AdminReportResult?
    @State private var liveCount: Int?
    @State private var generating = false
    @State private var failed = false
    @State private var women: [FamilyMember]? = WomenStore.cache.isEmpty ? nil : WomenStore.cache
    @State private var branchPickerOpen = false
    @State private var orderBoxOpen = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var viewerURL: AdminReportViewerItem?
    /// شجرة الآباء — مرة لكل تغيّر في الأعضاء
    @State private var familyTree: AdminFamilyTree = .empty
    /// خطّة التجميع الأخيرة ومفتاحها
    @State private var planCache: (key: String, plan: AdminReportGroupPlan)?
    @AppStorage(AdminReportFieldsStore.key) private var fieldsRaw = ""
    @AppStorage(AdminReportRecentStore.key) private var recentRaw = ""

    init(kind: AdminReportKind, scope: AdminReportScope? = nil) {
        self.kind = kind
        var f = AdminReportFilter()
        if let scope, kind == .register { f.scope = .init(ids: scope.ids, title: scope.title) }
        if kind == .book || kind == .branchReport { f.grouping = .father }
        _filter = State(initialValue: f)
    }

    // MARK: - Body

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let allowed = authVM.isAdmin
        return AdminPage(header: header,
                         lead: AnyView(!allowed ? AnyView(notAllowedCard)
                                       : loaded ? AnyView(leadCard) : AnyView(membersStateCard)),
                         content: AnyView(allowed && loaded ? AnyView(cards) : AnyView(Color.clear.frame(height: 0))))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if allowed && loaded { shareBar }
            }
            .task(id: genKey) { await regenerate() }
            .task(id: treeKey) { familyTree = AdminFamilyTree(memberVM.allMembers) }
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                await accounts.refresh()
                if women == nil, let fetched = try? await WomenStore.fetch() { women = fetched }
            }
            .modifier(AdminBranchPickerBox(isPresented: $branchPickerOpen, members: memberVM.allMembers,
                                           selected: filter.branch, onSelect: { filter.branch = $0 }))
            .dsTallBox(isPresented: $orderBoxOpen) { orderBox }
            .sheet(isPresented: $showShare, onDismiss: { shareItems.removeAll() }) {
                AdminReportShareSheet(items: shareItems) { showShare = false }
            }
            .sheet(item: $viewerURL) { item in
                AdminReportViewer(item: item, onShare: recordRecent)
            }
    }

    private var header: AdminPageHeader {
        AdminPageHeader(title: AdminReportKindUI.title(kind), subtitle: countLine, glyph: AdminReportKindUI.icon(kind))
    }

    /// «سيطبع 184 فرداً ضمن التصفية الحالية»
    private var countLine: String {
        guard let n = liveCount else { return L10n.t("جارٍ العدّ…", "Counting…") }
        return L10n.t("سيطبع \(AdminReportText.people(n)) ضمن التصفية الحالية",
                      n == 1 ? "1 person in the current filter" : "\(n) people in the current filter")
    }

    @ViewBuilder
    private var leadCard: some View {
        if kind.usesBranch {
            AnyView(scopeCard)
        } else {
            AnyView(fieldsCard)
        }
    }

    private var cards: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            if hasFilters { AnyView(filtersCard) }
            if kind.usesGrouping { AnyView(groupingCard) }
            if kind.usesBranch && !kind.fields.isEmpty { AnyView(fieldsCard) }
            AnyView(previewCard)
        }
    }

    // MARK: - المفاتيح

    private var treeKey: String { "\(memberVM.membersVersion)-\(memberVM.allMembers.count)" }

    private struct GenKey: Equatable {
        let filter: AdminReportFilter
        let members: Int
        let version: Int
        let accounts: Int
        let accountsLoaded: Bool
        let women: Int?
        let names: [String: String]?
        let allowed: Bool
        let fields: [AdminReportField]
    }

    private var genKey: GenKey {
        GenKey(filter: filter, members: memberVM.allMembers.count, version: memberVM.membersVersion,
               accounts: accounts.accounts.count, accountsLoaded: accounts.loaded, women: women?.count,
               names: appSettingsVM.settings.branchNames, allowed: authVM.isAdmin, fields: fields)
    }

    // MARK: - الإنشاء

    private func groupPlan() -> AdminReportGroupPlan {
        guard kind.usesGrouping else { return .empty }
        let key = "\(filter.grouping.rawValue)|\(filter.branch?.uuidString ?? "-")|\(treeKey)|\(appSettingsVM.settings.branchNames?.count ?? 0)"
        if let c = planCache, c.key == key { return c.plan }
        let tree = familyTree.byId.isEmpty ? AdminFamilyTree(memberVM.allMembers) : familyTree
        let names = appSettingsVM
        let plan = AdminReportGroupPlan.make(filter.grouping, members: memberVM.allMembers, tree: tree,
                                             root: filter.branch, names: { names.branchName(for: $0) })
        planCache = (key, plan)
        return plan
    }

    private func regenerate() async {
        guard authVM.isAdmin, !memberVM.allMembers.isEmpty else { return }
        // مهلة قصيرة: ضغطات وسحبات متتالية تُنشئ ملفاً واحداً
        if result != nil || liveCount != nil {
            try? await Task.sleep(nanoseconds: AdminReportsLayout.debounce)
            guard !Task.isCancelled else { return }
        }
        generating = true
        failed = false
        let names = appSettingsVM
        let input = AdminReportInput.make(
            members: memberVM.allMembers,
            women: women ?? (WomenStore.cache.isEmpty ? nil : WomenStore.cache),
            registered: accounts.loaded ? Set(accounts.accounts.keys) : nil,
            branchName: { names.branchName(for: $0) },
            generatedBy: authVM.currentUser?.displayFullName ?? "")
        var f = filter
        if kind != .register { f.scope = nil }
        let request = AdminReportRequest(kind: kind, filter: f, fields: fields, plan: groupPlan(),
                                         book: kind == .branchReport ? AdminReportBookSection.branchReport : [])
        let flag = AdminReportCancelFlag()
        let built = Task.detached(priority: .userInitiated) { AdminReportJob.build(request, input: input) }
        let doc = await withTaskCancellationHandler { await built.value } onCancel: { flag.cancel() }
        guard !Task.isCancelled else { return }
        liveCount = doc.count
        let thumbs = AdminReportsLayout.previewPages
        let job = Task.detached(priority: .userInitiated) {
            try? AdminReportJob.render(doc, thumbnails: thumbs, flag: flag)
        }
        let out = await withTaskCancellationHandler { await job.value } onCancel: { flag.cancel() }
        guard !Task.isCancelled else { return }
        generating = false
        if let out {
            if let old = result?.url, old != out.url { try? FileManager.default.removeItem(at: old) }
            result = out
        } else {
            failed = true
        }
    }

    // MARK: - «النطاق»

    private var scopeCard: some View {
        AdminSectionCard(title: L10n.t("النطاق", "Scope"), spacing: DS.Spacing.md) {
            if let s = filter.scope {
                // من صفحة الأعضاء — ✕ يرجع لكل العائلة
                DSChipButton(s.title, icon: "xmark.circle.fill", tint: DS.Color.palm, isSelected: true) {
                    filter.scope = nil
                }
                .accessibilityHint(L10n.t("يزيل تصفية صفحة الأعضاء", "Removes the members-page filter"))
            }
            AdminReportBreadcrumb(path: breadcrumb, onPick: { id in
                UISelectionFeedbackGenerator().selectionChanged()
                filter.branch = id
            })
            HStack(spacing: DS.Spacing.sm) {
                DSChipButton(L10n.t("اختر فرعاً", "Pick a branch"), icon: "point.3.connected.trianglepath.dotted",
                             tint: DS.Color.palm, isSelected: false, size: .small) { branchPickerOpen = true }
                    .accessibilityHint(L10n.t("يفتح قائمة الفروع بكل المستويات", "Opens the branch list at every level"))
                if kind == .tree || kind == .branchReport {
                    Text(L10n.t("الشجرة تُرسم من رأس هذا الفرع", "The tree is drawn from this branch's head"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// «العائلة ‹ فرع محمد ‹ فرع عبدالله» — (معرّف أو nil للعائلة، الاسم)
    private var breadcrumb: [(id: UUID?, title: String)] {
        var out: [(id: UUID?, title: String)] = [(nil, L10n.t("العائلة", "Family"))]
        guard let b = filter.branch else { return out }
        let names = appSettingsVM
        let chain = familyTree.chain(to: b) ?? []
        for id in chain + [b] {
            out.append((id, familyTree.branchTitle(id, names: { names.branchName(for: $0) })))
        }
        return out
    }

    // MARK: - «التصفية»

    private var hasFilters: Bool {
        kind.usesLife || kind.usesRegistration || kind.usesAge || kind.usesPeriod || kind.usesMissing
            || kind.usesPhonesFilter || kind.usesMemorialFilter
    }

    private var filtersCard: some View {
        AdminSectionCard(title: L10n.t("التصفية", "Filter"), spacing: DS.Spacing.md) {
            if kind.usesLife {
                chipRow(L10n.t("الحالة", "Status"), AdminReportFilter.Life.allCases, selected: filter.life, title: lifeTitle) {
                    filter.life = $0
                }
            }
            if kind.usesRegistration {
                chipRow(L10n.t("التسجيل", "Registration"), AdminReportFilter.Registration.allCases,
                        selected: filter.registration, title: registrationTitle) { filter.registration = $0 }
            }
            if kind.usesPhonesFilter {
                chipRow(L10n.t("الأرقام", "Numbers"), AdminReportFilter.Phones.allCases, selected: filter.phones,
                        title: phonesTitle) { filter.phones = $0 }
            }
            if kind.usesMemorialFilter {
                chipRow(L10n.t("التواريخ", "Dates"), AdminReportFilter.Memorial.allCases, selected: filter.memorial,
                        title: memorialTitle) { filter.memorial = $0 }
            }
            if kind.usesPeriod {
                chipRow(L10n.t("الفترة", "Period"), AdminReportFilter.Period.allCases, selected: filter.period,
                        title: periodTitle) { filter.period = $0 }
            }
            if kind.usesMissing {
                chipRow(L10n.t("الناقص", "Missing"), AdminReportFilter.Missing.allCases, selected: filter.missing,
                        title: missingTitle) { filter.missing = $0 }
            }
            if kind.usesAge { ageRow }
        }
    }

    private func chipRow<T: Hashable>(_ label: String, _ options: [T], selected: T, title: @escaping (T) -> String,
                                      set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(label)
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textSecondary)
                .accessibilityAddTraits(.isHeader)
            AdminChoiceRow {
                ForEach(options, id: \.self) { o in
                    Button {
                        guard o != selected else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        set(o)
                    } label: {
                        AdminChoiceChip(title: title(o), isSelected: o == selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label): \(title(o))")
                    .accessibilityAddTraits(o == selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private func lifeTitle(_ v: AdminReportFilter.Life) -> String {
        switch v {
        case .all: return L10n.t("الكل", "All")
        case .living: return L10n.t("أحياء", "Living")
        case .deceased: return L10n.t("متوفون", "Deceased")
        }
    }

    private func registrationTitle(_ v: AdminReportFilter.Registration) -> String {
        switch v {
        case .all: return L10n.t("كل الحالات", "All")
        case .registered: return L10n.t("مسجّل", "Registered")
        case .treeOnly: return L10n.t("مقيّد", "Listed only")
        case .frozen: return L10n.t("موقوف", "Suspended")
        }
    }

    private func phonesTitle(_ v: AdminReportFilter.Phones) -> String {
        switch v {
        case .all: return L10n.t("الكل", "All")
        case .registered: return L10n.t("مسجّلون", "Registered")
        case .noPhone: return L10n.t("بلا رقم هاتف", "No phone")
        }
    }

    private func memorialTitle(_ v: AdminReportFilter.Memorial) -> String {
        switch v {
        case .all: return L10n.t("الكل", "All")
        case .incomplete: return L10n.t("لا يوجد تاريخ كامل للوفاة", "No full death date")
        }
    }

    private func periodTitle(_ v: AdminReportFilter.Period) -> String {
        switch v {
        case .thisMonth: return L10n.t("هذا الشهر", "This month")
        case .lastMonth: return L10n.t("الشهر الماضي", "Last month")
        case .last90: return L10n.t("آخر 90 يوماً", "Last 90 days")
        }
    }

    private func missingTitle(_ v: AdminReportFilter.Missing) -> String {
        switch v {
        case .any: return L10n.t("كل الناقص", "Anything")
        case .birth: return L10n.t("الميلاد", "Birth")
        case .death: return L10n.t("الوفاة", "Death")
        case .photo: return L10n.t("الصورة", "Photo")
        case .father: return L10n.t("الأب", "Father")
        }
    }

    /// «العمر» + المدى المختار + الشريط
    private var ageRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text(L10n.t("العمر", "Age"))
                    .dsFont(.sectionTitle)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: DS.Spacing.sm)
                Text(ageSummary)
                    .dsFont(.chip)
                    .foregroundColor(filter.ageLimited ? DS.Color.textPrimary : DS.Color.textTertiary)
                    .monospacedDigit()
                if filter.ageLimited {
                    Button {
                        filter.ageMin = 0
                        filter.ageMax = AdminReportFilter.ageCap
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dsGlyph(DS.Glyph.lg)
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -DS.Spacing.sm)
                    .accessibilityLabel(L10n.t("كل الأعمار", "All ages"))
                }
            }
            AdminReportAgeRange(lower: $filter.ageMin, upper: $filter.ageMax)
            if filter.ageLimited {
                Text(L10n.t("من لا يُعرف عمره (بلا ميلاد أو مخفي) لا يدخل متى حُدّد المدى",
                            "People with an unknown age are left out when a range is set"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ageSummary: String {
        guard filter.ageLimited else { return L10n.t("كل الأعمار", "All ages") }
        let maxText = filter.ageMax >= AdminReportFilter.ageCap ? "\(AdminReportFilter.ageCap)+" : "\(filter.ageMax)"
        return L10n.t("من \(filter.ageMin) إلى \(maxText) سنة", "\(filter.ageMin) to \(maxText) years")
    }

    // MARK: - «التجميع»

    private var groupingCard: some View {
        AdminSectionCard(title: L10n.t("التجميع", "Group by")) {
            AdminChoiceRow {
                ForEach(AdminReportGrouping.allCases) { g in
                    Button {
                        guard g != filter.grouping else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        filter.grouping = g
                    } label: {
                        AdminChoiceChip(title: Self.groupingTitle(g), icon: Self.groupingIcon(g), isSelected: g == filter.grouping)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("التجميع: \(Self.groupingTitle(g))", "Group by: \(Self.groupingTitle(g))"))
                    .accessibilityAddTraits(g == filter.grouping ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// نفس أسماء «التقسيم» في صفحة الأعضاء
    static func groupingTitle(_ g: AdminReportGrouping) -> String {
        member(g).title
    }

    static func groupingIcon(_ g: AdminReportGrouping) -> String { member(g).icon }

    private static func member(_ g: AdminReportGrouping) -> AdminMemberGrouping {
        AdminMemberGrouping(rawValue: g.rawValue) ?? .branch
    }

    // MARK: - «الأعمدة» / «الأقسام»

    private var fieldsKey: String {
        "\(authVM.currentUser?.id.uuidString.lowercased() ?? "-")|\(kind.rawValue)"
    }

    /// المحفوظ لهذا النوع بترتيبه — nil = الافتراضي
    private var savedFields: [AdminReportField]? { AdminReportFieldsStore.fields(fieldsRaw, key: fieldsKey) }

    /// ما يُطبع الآن بترتيبه (المقفل أولاً)
    private var fields: [AdminReportField] { kind.orderedFields(savedFields) }

    private func saveFields(_ chosen: [AdminReportField]?) {
        var all = AdminReportFieldsStore.decode(fieldsRaw)
        let resolved = chosen.map { kind.orderedFields($0) }
        if let resolved, resolved != kind.orderedFields(nil) {
            all[fieldsKey] = resolved.map(\.rawValue).joined(separator: ",")
        } else {
            all[fieldsKey] = nil
        }
        fieldsRaw = AdminReportFieldsStore.encode(all)
    }

    private var fieldsCard: some View {
        let current = fields
        let changed = current != kind.orderedFields(nil)
        let isSections = kind == .stats
        return AdminSectionCard(title: isSections ? L10n.t("الأقسام", "Sections") : L10n.t("الأعمدة", "Columns"),
                                spacing: DS.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(current + kind.fields.filter { !current.contains($0) }) { f in
                        fieldChip(f, on: current.contains(f), locked: kind.lockedFields.contains(f), current: current)
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
            HStack(spacing: DS.Spacing.md) {
                if !isSections {
                    Button { orderBoxOpen = true } label: {
                        Label(L10n.t("ترتيب الأعمدة", "Reorder columns"), systemImage: "arrow.up.arrow.down")
                            .dsFont(.chip)
                            .foregroundColor(DS.Color.primary)
                            .frame(minHeight: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if changed {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { saveFields(nil) }
                    } label: {
                        Text(L10n.t("الافتراضي", "Default"))
                            .dsFont(.chip)
                            .foregroundColor(DS.Color.primary)
                            .frame(minHeight: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("إرجاع الأعمدة الافتراضية", "Restore the default columns"))
                }
            }
        }
    }

    private func fieldChip(_ f: AdminReportField, on: Bool, locked: Bool, current: [AdminReportField]) -> some View {
        let title = Self.fieldTitle(f)
        return DSChipButton(title, icon: locked ? "lock.fill" : on ? "checkmark" : "plus",
                            tint: AdminReportKindUI.tint(kind), isSelected: on, size: .small) {
            guard !locked else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            var next = current
            if on { next.removeAll { $0 == f } } else { next.append(f) }
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { saveFields(next) }
        }
        .accessibilityLabel(title)
        .accessibilityValue(on ? L10n.t("في التقرير", "In the report") : L10n.t("ليس في التقرير", "Not in the report"))
        .accessibilityHint(locked ? L10n.t("دائماً في التقرير", "Always in the report")
                           : on ? L10n.t("يزيله من التقرير", "Removes it from the report")
                           : L10n.t("يضيفه للتقرير", "Adds it to the report"))
    }

    static func fieldTitle(_ f: AdminReportField) -> String {
        switch f {
        case .name: return L10n.t("الاسم الكامل", "Full name")
        case .branch: return L10n.t("الفرع", "Branch")
        case .father: return L10n.t("الأب", "Father")
        case .birth: return L10n.t("الميلاد", "Birth")
        case .age: return L10n.t("العمر", "Age")
        case .status: return L10n.t("الحالة", "Status")
        case .death: return L10n.t("تاريخ الوفاة", "Death date")
        case .phone: return L10n.t("الهاتف", "Phone")
        case .registration: return L10n.t("التسجيل", "Registration")
        case .country: return L10n.t("الدولة", "Country")
        case .created: return L10n.t("تاريخ القيد", "Added on")
        case .missing: return L10n.t("الناقص", "Missing")
        case .anniversary: return L10n.t("الذكرى القادمة", "Next anniversary")
        case .ageAtDeath: return L10n.t("العمر عند الوفاة", "Age at death")
        case .people: return L10n.t("إحصاء الأفراد", "Head count")
        case .ages: return L10n.t("الأعمار", "Ages")
        case .branches: return L10n.t("الفروع", "Branches")
        case .registered: return L10n.t("المسجّلون", "Registered")
        }
    }

    /// مربّع الترتيب: الأعمدة المختارة بالسهمين (المقفل ثابت أولاً)
    private var orderBox: some View {
        let current = fields
        let movable = current.filter { !kind.lockedFields.contains($0) }
        let locked = current.filter { kind.lockedFields.contains($0) }
        return DSComposer(title: L10n.t("ترتيب الأعمدة", "Column order"),
                          subtitle: L10n.t("من اليمين إلى اليسار في الملف — حرّك بالسهمين", "Right to left in the file — move with the arrows"),
                          icon: "arrow.up.arrow.down", tint: DS.Color.actionNavy, actionTitle: "", showsAction: false,
                          cancelTitle: L10n.t("تم", "Done"), canSubmit: false, onSubmit: {}, onCancel: { orderBoxOpen = false }) {
            VStack(spacing: DS.Spacing.xs) {
                ForEach(locked) { f in
                    orderRow(f, index: nil, count: movable.count, movable: movable, locked: locked)
                }
                ForEach(Array(movable.enumerated()), id: \.element) { i, f in
                    orderRow(f, index: i, count: movable.count, movable: movable, locked: locked)
                }
            }
        }
    }

    private func orderRow(_ f: AdminReportField, index: Int?, count: Int, movable: [AdminReportField],
                          locked: [AdminReportField]) -> some View {
        func move(_ by: Int) {
            guard let index else { return }
            let to = index + by
            guard movable.indices.contains(to) else { return }
            var next = movable
            next.swapAt(index, to)
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { saveFields(locked + next) }
        }
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: index == nil ? "lock.fill" : "line.3.horizontal")
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(Self.fieldTitle(f))
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
            Spacer(minLength: DS.Spacing.sm)
            if let index {
                arrow("chevron.up", enabled: index > 0, label: L10n.t("تحريك لأعلى", "Move up")) { move(-1) }
                arrow("chevron.down", enabled: index < count - 1, label: L10n.t("تحريك لأسفل", "Move down")) { move(1) }
            } else {
                Text(L10n.t("ثابت", "Fixed"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DS.Icon.tapTarget)
        .dsRowBox()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(index.map { L10n.t("\(Self.fieldTitle(f))، العمود \($0 + 1 + locked.count)",
                                               "\(Self.fieldTitle(f)), column \($0 + 1 + locked.count)") }
                            ?? L10n.t("\(Self.fieldTitle(f))، ثابت", "\(Self.fieldTitle(f)), fixed"))
        .accessibilityActions {
            if let index, index > 0 { Button(L10n.t("تحريك لأعلى", "Move up")) { move(-1) } }
            if let index, index < count - 1 { Button(L10n.t("تحريك لأسفل", "Move down")) { move(1) } }
        }
    }

    private func arrow(_ icon: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(enabled ? DS.Color.primary : DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - «المعاينة»

    private var previewCard: some View {
        AdminSectionCard(title: L10n.t("المعاينة", "Preview"), tag: result == nil ? nil : "PDF · A4") {
            if let result, result.kind == kind {
                AnyView(previewBody(result))
            } else if failed {
                AnyView(DSEmptyView(L10n.t("تعذّر إنشاء التقرير", "Couldn't create the report"),
                                    message: L10n.t("حاول مرة أخرى", "Try again"),
                                    actionTitle: L10n.t("إعادة المحاولة", "Retry"), actionIcon: "arrow.clockwise",
                                    style: .compact, action: { Task { await regenerate() } }))
            } else {
                AnyView(DSPageLoader(L10n.t("جارٍ إعداد التقرير…", "Preparing the report…"),
                                     size: DS.Icon.loaderArtInline, fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.lg))
            }
        }
    }

    private func previewBody(_ r: AdminReportResult) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(verbatim: r.summary)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if generating {
                    ProgressView().scaleEffect(DS.Spinner.chipScale)
                }
            }
            .opacity(generating ? 0.55 : 1)
            AdminReportThumbs(result: r) {
                viewerURL = AdminReportViewerItem(url: r.url, title: AdminReportKindUI.title(kind))
            }
            Text(L10n.t("اضغط على الصفحة لعرض الملف كاملاً", "Tap a page to view the whole file"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - المشاركة

    private var shareBar: some View {
        let ready = result?.kind == kind && !generating
        let pages = result.map { L10n.t(" · \(AdminReportText.pages($0.pages))", " · \($0.pages) pages") } ?? ""
        return DSActionButton(title: L10n.t("مشاركة / حفظ", "Share / Save") + (ready ? pages : ""),
                              icon: "square.and.arrow.up",
                              isBusy: generating && result?.kind != kind,
                              enabled: ready) {
            share()
        }
        .dsSubtleShadow()
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [DS.Hub.background.opacity(0), DS.Hub.background],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func share() {
        guard let url = result?.url else { return }
        recordRecent()
        shareItems = [url]
        showShare = true
    }

    /// «أعددتها مؤخراً» — التقرير ونطاقه
    private func recordRecent() {
        guard let r = result else { return }
        var title = AdminReportKindUI.title(kind)
        if let b = filter.branch {
            let names = appSettingsVM
            title += " · " + familyTree.branchTitle(b, names: { names.branchName(for: $0) })
        }
        let user = authVM.currentUser?.id.uuidString.lowercased() ?? "-"
        recentRaw = AdminReportRecentStore.add(.init(kind: kind.rawValue, title: title, date: Date(), pages: r.pages),
                                               raw: recentRaw, user: user)
    }

    // MARK: - الحالات

    @ViewBuilder
    private var membersStateCard: some View {
        if memberVM.membersLoadFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
        } else {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
        }
    }

    private var notAllowedCard: some View {
        AdminPageStateCard(.empty(L10n.t("التقارير للمالك والمدير", "Reports are for the owner and admins"),
                                  message: L10n.t("تحتوي أرقام هواتف وبيانات الأعضاء", "They include members' phones and data")))
    }
}

// MARK: - مسار الفرع «العائلة ‹ فرع ‹ فرع»

struct AdminReportBreadcrumb: View {
    let path: [(id: UUID?, title: String)]
    let onPick: (UUID?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(Array(path.enumerated()), id: \.offset) { i, step in
                        if i > 0 {
                            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                                .foregroundColor(DS.Color.textTertiary)
                                .accessibilityHidden(true)
                        }
                        let last = i == path.count - 1
                        Button {
                            guard !last else { return }
                            onPick(step.id)
                        } label: {
                            AdminChoiceChip(title: step.title, isSelected: last)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityLabel(step.title)
                        .accessibilityHint(last ? "" : L10n.t("يصعد إلى هذا المستوى", "Goes up to this level"))
                        .accessibilityAddTraits(last ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
            .onAppear { proxy.scrollTo(path.count - 1, anchor: .trailing) }
            .onChange(of: path.count) { n in proxy.scrollTo(n - 1, anchor: .trailing) }
        }
    }
}

// MARK: - شريط مدى العمر (مقبضان)

/// مدى حرّ ٠…١٠٠+ بمقبضين؛ القارئ الصوتي: عنصران قابلان للتعديل («أقل عمر» و«أكبر عمر») بخطوة سنة
struct AdminReportAgeRange: View {
    @Binding var lower: Int
    @Binding var upper: Int
    @State private var dragLower: Int?
    @State private var dragUpper: Int?

    private let cap = AdminReportFilter.ageCap
    private static let space = "adminReportAgeRange"

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width - AdminReportsLayout.ageThumb, 1)
            let lo = CGFloat(dragLower ?? lower) / CGFloat(cap) * w
            let hi = CGFloat(dragUpper ?? upper) / CGFloat(cap) * w
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                    .frame(height: AdminReportsLayout.ageTrack)
                    .padding(.horizontal, AdminReportsLayout.ageThumb / 2)
                Capsule().fill(DS.Color.primary)
                    .frame(width: max(hi - lo, 0), height: AdminReportsLayout.ageTrack)
                    .offset(x: lo + AdminReportsLayout.ageThumb / 2)
                thumb(value: dragLower ?? lower, label: L10n.t("أقل عمر", "Minimum age"))
                    .offset(x: lo)
                    .gesture(drag(width: w, isLower: true))
                    .accessibilityAdjustableAction { dir in
                        lower = dir == .increment ? min(lower + 1, upper) : max(lower - 1, 0)
                    }
                thumb(value: dragUpper ?? upper, label: L10n.t("أكبر عمر", "Maximum age"))
                    .offset(x: hi)
                    .gesture(drag(width: w, isLower: false))
                    .accessibilityAdjustableAction { dir in
                        upper = dir == .increment ? min(upper + 1, cap) : max(upper - 1, lower)
                    }
            }
            .frame(height: DS.Icon.tapTarget)
            .coordinateSpace(name: Self.space)
        }
        .frame(height: DS.Icon.tapTarget)
        // الشريط من اليسار لليمين (الأعمار تكبر يميناً) في الاتجاهين
        .environment(\.layoutDirection, .leftToRight)
    }

    private func thumb(value: Int, label: String) -> some View {
        Circle()
            .fill(DS.Color.surface)
            .overlay(Circle().strokeBorder(DS.Color.primary, lineWidth: DS.Border.widthBold))
            .frame(width: AdminReportsLayout.ageThumb, height: AdminReportsLayout.ageThumb)
            .dsSubtleShadow()
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .contentShape(Rectangle())
            .padding(.horizontal, -(DS.Icon.tapTarget - AdminReportsLayout.ageThumb) / 2)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value >= cap ? L10n.t("\(cap) سنة فأكثر", "\(cap)+ years") : L10n.t("\(value) سنة", "\(value) years"))
    }

    private func drag(width: CGFloat, isLower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { g in
                let v = Int(((g.location.x - AdminReportsLayout.ageThumb / 2) / width * CGFloat(cap)).rounded())
                if isLower {
                    dragLower = min(max(v, 0), dragUpper ?? upper)
                } else {
                    dragUpper = max(min(v, cap), dragLower ?? lower)
                }
            }
            .onEnded { _ in
                if let v = dragLower { lower = v }
                if let v = dragUpper { upper = v }
                if dragLower != nil || dragUpper != nil { UISelectionFeedbackGenerator().selectionChanged() }
                dragLower = nil
                dragUpper = nil
            }
    }
}
