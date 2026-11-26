import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - «نساء العائلة» (طلب المالك ٢٠٢٦-١١-٠٨، عينة samples/admin-women؛ صفحةً في إعادة التصميم U12 ٢٠٢٦-١١-٢٦ — spec C.9)
//
// صفحة تُدفع من رقم «262 امرأة ‹» في رأس «العائلة» (U11) — كانت لوحة تحت مفتاح «شجرة العائلة | شجرة النساء» (حُذف، E.9).
// كل ما يخص النساء في مكان واحد. الرأس: ‹ العائلة · «نساء العائلة» · زرّ «شجرة النساء» (← تبويب الشجرة على شجرة النساء) ·
// سطر الأرقام «127 حية ‹» «135 متوفاة ‹» (كل رقم يضبط «الحالة»). تحته شريط الفلاتر (spec A.13): البحث باسمها أو اسم أبيها +
// «الفلاتر» — «الحالة» (الكل · الحيّات · مسجّلات · متزوجات · متوفيات؛ الافتراضي «الحيّات» شريحةً مفعّلة)، «الفرع» (كل الفروع ·
// فرع خارج العائلة)، «الترتيب» (أبجدياً · الأحدث = المضافات أو المربوطات بحساب، الأحدث أولاً، وكم منهن خلال ٣٠ يوماً).
// الضغط على امرأة يفتح مربّع تفاصيلها نفسه في شجرة النساء (`WomanDetailSheet`)، وابن البنت ورقة حسابه (`AdminMemberSheet`).
// «فرع خارج العائلة» = أبناء البنات (`DaughterSonsIndex`) وأزواج البنات من خارج العائلة والنساء من خارجها
// (`WomenStore.outsideFamilyIds`) — بقاعدة `AdminFamilyCensus.make` نفسها (المسمّون فقط، بلا حساب مراجعة أبل)، فعدد القائمة
// = رقم «خارج العائلة» (T2). الأحياء في القائمة، والمتوفون في قسم مطويّ بروحهم تحتها (طلب المالك ٢٠٢٦-١١-٢٦).
// «نساء العائلة» = إناث شجرة النساء المسمّيات بلا «خارج العائلة» — نفس حلقة «النساء».
// للمالك والمدير (طلب المالك ٢٠٢٦-١١-٠٨)؛ المراقب يذهب لشجرة النساء.
// الهبوط: `AdminWomenLanding` (معامل `init` صريح، أو `AdminAreaRouter.take(.women, hop:)`) — الرابط من مجموع يضبط «الحالة» =
// الكل، والفتح المباشر «الحيّات».

// MARK: - المنطق الخالص

nonisolated enum AdminWomenLogic {
    /// نافذة «جديدة» في ترتيب «الأحدث» بالأيام
    static let recentDays = 30

    enum Status: String, CaseIterable, Hashable {
        case all, living, registered, married, deceased

        var title: String {
            switch self {
            case .all:        return L10n.t("الكل", "All")
            case .living:     return L10n.t("الحيّات", "Living")
            // بلا «ال» كشرائح «العائلة» — طلب المالك ٢٠٢٦-١١-١١ «الفلاتر مو مضبوطة»
            case .registered: return L10n.t("مسجّلات", "Registered")
            case .married:    return L10n.t("متزوجات", "Married")
            case .deceased:   return L10n.t("متوفيات", "Deceased")
            }
        }

        init(landing: AdminWomenLanding.Status) {
            switch landing {
            case .all:        self = .all
            case .living:     self = .living
            case .registered: self = .registered
            case .married:    self = .married
            case .deceased:   self = .deceased
            }
        }
    }

    enum Branch: String, CaseIterable, Hashable {
        case family, outside

        var title: String {
            switch self {
            case .family:  return L10n.t("كل الفروع", "All branches")
            case .outside: return L10n.t("فرع خارج العائلة", "Outside branch")
            }
        }
    }

    enum Order: String, CaseIterable, Hashable {
        case alphabetical, newest

        var title: String {
            switch self {
            case .alphabetical: return L10n.t("أبجدياً", "A–Z")
            // «الأحدث» (طلب المالك ٢٠٢٦-١١-١٣ «فلتر اخر الاسماء المضافة او المربوطة بالتطبيق»)
            case .newest:       return L10n.t("الأحدث", "Newest")
            }
        }
    }

    struct Filters: Equatable {
        var status: Status = .living
        var branch: Branch = .family
        var order: Order = .alphabetical
    }

    /// ما تُفتح عليه الصفحة مباشرة (spec C.9: «الحيّات»)، وما يرجع إليه «إعادة ضبط الفلاتر»
    static let pageDefault = Filters()

    /// ما يُعرف عن صفّ — يُحسب مرة لكل تغيّر في البيانات
    struct Fact: Equatable {
        var deceased = false
        /// مربوطة بحساب (ابن البنت: حسابه نفسه)
        var registered = false
        var married = false
        /// في «فرع خارج العائلة»
        var outside = false

        init(deceased: Bool = false, registered: Bool = false, married: Bool = false, outside: Bool = false) {
            self.deceased = deceased
            self.registered = registered
            self.married = married
            self.outside = outside
        }
    }

    /// في القائمة: الفرع ثم «الحالة». متوفو «فرع خارج العائلة» في قسمهم المطويّ — إلا حين تُختار «متوفيات»
    static func inList(_ f: Fact, _ s: Filters) -> Bool {
        guard f.outside == (s.branch == .outside) else { return false }
        if f.outside && f.deceased && s.status != .deceased { return false }
        switch s.status {
        case .all:        return true
        case .living:     return !f.deceased
        case .registered: return f.registered
        case .married:    return f.married
        case .deceased:   return f.deceased
        }
    }

    /// القسم المطويّ «المتوفون من خارج العائلة» تحت قائمة «فرع خارج العائلة» (مع «الكل» و«الحيّات»)
    static func inOutsideDeceased(_ f: Fact, _ s: Filters) -> Bool {
        s.branch == .outside && (s.status == .all || s.status == .living) && f.outside && f.deceased
    }

    static func count(_ facts: [Fact], _ s: Filters) -> Int {
        facts.reduce(0) { $0 + (inList($1, s) ? 1 : 0) }
    }

    /// الهبوط ← الفلاتر: الحقل الغائب = افتراض الصفحة («الحيّات»، «كل الفروع»)
    static func filters(landing: AdminWomenLanding?) -> Filters {
        var s = pageDefault
        guard let landing else { return s }
        if let status = landing.status { s.status = Status(landing: status) }
        if let branch = landing.branch { s.branch = branch == .outside ? .outside : .family }
        return s
    }

    /// «الأحدث»: مواضع الصفوف بالتاريخ الأحدث أولاً، وما بلا تاريخ آخراً بترتيبه (ثابت)
    static func newestOrder(_ dates: [Date?]) -> [Int] {
        dates.indices.sorted { a, b in
            switch (dates[a], dates[b]) {
            case let (x?, y?): return x != y ? x > y : a < b
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a < b
            }
        }
    }

    /// كم تاريخاً خلال آخر `days` يوماً
    static func recentCount(_ dates: [Date?], now: Date = Date(), days: Int = recentDays) -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return dates.reduce(0) { $0 + (($1 ?? .distantPast) >= cutoff ? 1 : 0) }
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - الصفّ

/// صفّ في القائمة: امرأة (أو زوج من خارج العائلة) من شجرة النساء، أو حساب ابن بنت
struct AdminWomenEntry: Identifiable {
    enum Kind { case woman(FamilyMember), outsideHusband(FamilyMember), son(FamilyMember) }
    let kind: Kind
    let title: String
    let subtitle: String?
    let status: (text: String, tint: Color)?
    let needle: String
    /// كلمات البحث محسوبة مرة (لا مع كل حرف)
    let words: [String]
    /// ما يُعرف عنه للفلاتر
    let fact: AdminWomenLogic.Fact
    /// أُضيفت عقدتها أو رُبطت بحساب (الأحدث منهما) — ترتيب «الأحدث»
    let date: Date?
    /// «أُضيفت 12 نوفمبر» / «رُبطت بحساب 12 نوفمبر» — السطر الثاني في ترتيب «الأحدث»
    let dateLine: String?

    init(kind: Kind, title: String, subtitle: String?, status: (text: String, tint: Color)?, needle: String,
         fact: AdminWomenLogic.Fact = AdminWomenLogic.Fact(), date: Date? = nil, dateLine: String? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.needle = needle
        self.words = NameSearch.words(needle)
        self.fact = fact
        self.date = date
        self.dateLine = dateLine
    }

    var id: UUID { member.id }

    var member: FamilyMember {
        switch kind {
        case .woman(let m), .outsideHusband(let m), .son(let m): return m
        }
    }
}

// MARK: - الصفحة

/// صفحة مدفوعة (spec C.9) — تجلب بياناتها وتفتح ورقة العضو بنفسها
struct AdminWomenPanel: View {
    private typealias L = AdminWomenLogic

    private let landing: AdminWomenLanding?

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @Environment(\.adminAreaHop) private var hop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filters: L.Filters
    @State private var query = ""
    @State private var limit = Self.pageSize
    /// الصفوف مبنية مرة لكل تغيّر في البيانات (كانت تُبنى مع كل ضغطة وحرف — بلاغ المالك ٢٠٢٦-١١-٠٨ «القسم شوي يعلق»)
    @State private var rows: [AdminWomenEntry] = []
    @State private var built = false
    @State private var selectedWoman: FamilyMember?
    /// قسم متوفي «فرع خارج العائلة» مفتوح؟ (مطويّ بالبداية)
    @State private var showsOutsideDeceased = false
    // الصفحة:
    @State private var pageWomen: [FamilyMember]
    @State private var health: AdminStoreHealth
    @State private var memberSheet: AdminMemberSheetContext?
    @State private var started = false

    static let pageSize = 40

    /// الصفحة «نساء العائلة» — `landing` (من رقم أو إشعار) يغلب الهبوط المخزَّن؛ بلا شيء = «الحيّات»
    init(landing: AdminWomenLanding? = nil) {
        self.landing = landing
        _filters = State(initialValue: L.filters(landing: landing))
        let cache = WomenStore.cache
        _pageWomen = State(initialValue: cache)
        _health = State(initialValue: cache.isEmpty ? .idle : .loaded(at: Date()))
    }

    static var title: String { L10n.t("نساء العائلة", "Family women") }

    private var women: [FamilyMember] { pageWomen }

    /// تعديل وحذف من مربّع التفاصيل: صلاحية الدور مضروبة بـ«يعدّل» في جدول السيرفر (Autoplan note 7)
    private var canEdit: Bool { authVM.canEditMembers && authVM.adminCanEdit(.family) }
    private var canDelete: Bool { authVM.canDeleteMembers && authVM.adminCanEdit(.family) }

    // حارس المكدس: الصفحة واللوحة طبقات خلف `AnyView`
    var body: some View {
        AnyView(pageBody)
            .debugStackProbe("AdminWomenPanel")
    }

    // MARK: الصفحة

    private var pageBody: some View {
        AdminPage(header: header, content: AnyView(pageContent))
            .adminArea(.family)
            .dsTallBox(item: $memberSheet) { context in
                AdminMemberSheet(ids: context.ids, start: context.start)
            }
            .refreshable { await load(force: true) }
            .task {
                guard !started else { return }
                started = true
                applyStoredLanding()
                await load(force: false)
            }
    }

    /// هبوط «اليوم» (`AdminAreaRouter.landings`) — معامل `init` الصريح يغلبه
    private func applyStoredLanding() {
        guard let stored = AdminAreaRouter.take(.women, hop: hop) else { return }
        let merged = landing.map { stored.overridden(by: $0) } ?? stored
        filters = L.filters(landing: merged)
    }

    private func load(force: Bool) async {
        if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        await sons.refresh(force: force)
        // البيانات الحاضرة (الكاش) تُعرض فوراً، والجلب يحدّثها
        health = health.beginning()
        do {
            let fresh = try await WomenStore.fetch()
            pageWomen = fresh
            health = health.ending(success: true)
        } catch {
            health = health.ending(success: false)
            Log.fetchError("[AdminWomenPanel] تعذّر جلب شجرة النساء", error)
        }
        rebuild(pageWomen)
    }

    private var header: AdminPageHeader {
        let facts = rows.map(\.fact)
        let ready = built && !women.isEmpty
        let living = ready ? L.count(facts, L.Filters(status: .living, branch: .family)) : nil
        let deceased = ready ? L.count(facts, L.Filters(status: .deceased, branch: .family)) : nil
        // الأرقام من البيانات الحاضرة ولو فشل التحديث (بـ«آخر تحديث»)؛ «—» وإعادة المحاولة حين لا شيء في اليد
        let itemHealth: AdminStoreHealth? = women.isEmpty || health.canRetry ? health : nil
        let retry: () -> Void = { Task { await load(force: true) } }
        let items: [AdminHeaderItem] = authVM.isAdmin ? [
            AdminHeaderItem(id: "living", value: living, label: L10n.t("حية", "living"), health: itemHealth,
                            tap: .action { land(.living) }, retry: retry,
                            spoken: living.map { L10n.t("\($0) حية، يفتح القائمة", "\($0) living, opens the list") }),
            AdminHeaderItem(id: "deceased", value: deceased, label: L10n.t("متوفاة", "deceased"), health: itemHealth,
                            tap: .action { land(.deceased) }, retry: retry,
                            spoken: deceased.map { L10n.t("\($0) متوفاة، يفتح القائمة", "\($0) deceased, opens the list") }),
        ] : []
        return AdminPageHeader(title: Self.title,
                               readOnly: authVM.isAdmin && !authVM.adminCanEdit(.family),
                               items: items,
                               actions: [AdminPageAction(symbol: "tree", label: L10n.t("شجرة النساء", "Women's tree"),
                                                         tap: .action { openWomenTree() })])
    }

    /// رقم الرأس يفتح قائمته: «الحالة» وحدها في نساء العائلة، بلا بحث — فأول رقم تحت الشريط = الرقم المضغوط (T2)
    private func land(_ status: L.Status) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
            filters = L.Filters(status: status, branch: .family, order: filters.order)
            query = ""
            limit = Self.pageSize
        }
    }

    /// تبويب الشجرة على شجرة النساء (نفس «اليوم» وورقة العضو)
    private func openWomenTree() {
        TreeTabContainer.openWomenOnAppear = true
        NotificationCenter.default.post(name: .openWomenTree, object: nil)
    }

    @ViewBuilder
    private var pageContent: some View {
        if !authVM.isAdmin {
            // للمالك والمدير (طلب المالك ٢٠٢٦-١١-٠٨) — غيرهما يذهب لشجرة النساء
            AdminPageStateCard(.empty(L10n.t("هذه الصفحة للمالك والمدير", "This page is for the owner and admins"),
                                      message: L10n.t("تصفّح النساء من شجرة النساء", "Browse the women from the women's tree"),
                                      actionTitle: L10n.t("شجرة النساء", "Women's tree"),
                                      action: { openWomenTree() }))
        } else if women.isEmpty && health.canRetry {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل شجرة النساء", "Couldn't load the women's tree"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await load(force: true) } }))
        } else {
            panel
        }
    }

    // MARK: اللوحة

    private var panel: some View {
        AnyView(panelContent)
            .onAppear { rebuild() }
            // أي تبدّل في بيانات النساء (تعديل بنفس العدد: وفاة، زوج، حالة) — لا العدد وحده
            .onChange(of: women) { rebuild($0) }
            .onChange(of: sons.ids) { _ in rebuild() }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: filters) { _ in limit = Self.pageSize }
            .onChange(of: query) { _ in limit = Self.pageSize }
            .fullScreenCover(item: $selectedWoman) { w in
                WomanDetailSheet(
                    woman: w,
                    allWomen: women,
                    me: authVM.currentUser,
                    canEdit: canEdit,
                    canDelete: canDelete,
                    canAnnounceDeath: authVM.isAdmin,
                    canModerate: authVM.canModerate,
                    onChanged: { await load(force: true) },
                    onOpenMember: { id in
                        selectedWoman = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selectedWoman = women.first { $0.id == id } }
                    }
                )
                .background(ClearPresentationBackground())
            }
            .transaction { t in if selectedWoman != nil { t.disablesAnimations = true } }
    }

    private func openMember(_ ids: [UUID], _ start: Int) {
        memberSheet = AdminMemberSheetContext(ids: ids, start: start)
    }

    /// كل ما يرسمه الرسم الواحد — يُحسب مرة
    private struct Model {
        /// القائمة بعد البحث والفلاتر والترتيب
        let visible: [AdminWomenEntry]
        /// «المتوفون من خارج العائلة» (بعد البحث)
        let outsideDeceased: [AdminWomenEntry]
        let set: AdminFilterSet<AdminWomenLogic.Filters>
        /// «12 جديدة خلال 30 يوماً» في ترتيب «الأحدث»
        let note: String?
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func makeModel() -> Model {
        let searched = search(rows, trimmedQuery)
        let facts = searched.map(\.fact)
        let ready = built
        let count: (L.Filters) -> Int? = { s in ready ? L.count(facts, s) : nil }
        let current = filters
        var visible = searched.filter { L.inList($0.fact, current) }
        if current.order == .newest && trimmedQuery.isEmpty {
            let dated = visible
            visible = L.newestOrder(dated.map(\.date)).map { dated[$0] }
        }
        let outsideDeceased = searched.filter { L.inOutsideDeceased($0.fact, current) }
        let outside = current.branch == .outside
        let set = AdminFilterSet<L.Filters>(reset: L.pageDefault,
                                            noun: { n in outside ? Self.peopleNoun(n) : Self.womenNoun(n) },
                                            resultCount: count) { s in
            let statuses = L.Status.allCases.map { status -> AdminFilterOption<L.Status> in
                var probe = s
                probe.status = status
                return AdminFilterOption(status, status.title, count: count(probe))
            }
            let branches = L.Branch.allCases.map { branch -> AdminFilterOption<L.Branch> in
                var probe = s
                probe.branch = branch
                return AdminFilterOption(branch, branch.title, count: count(probe))
            }
            let groups: [AdminFilterGroup<L.Filters>] = [
                .choices("status", title: L10n.t("الحالة", "Status"), value: \.status, all: .all, options: statuses),
                .choices("branch", title: L10n.t("الفرع", "Branch"), value: \.branch, all: .family, options: branches),
                .order("order", title: L10n.t("الترتيب", "Order"), value: \.order, standard: .alphabetical,
                       options: L.Order.allCases.map { AdminFilterOption($0, $0.title) }),
            ]
            return groups
        }
        var note: String?
        if current.order == .newest {
            let recent = L.recentCount(visible.map(\.date))
            note = L10n.t("\(recent) جديدة خلال \(L.recentDays) يوماً", "\(recent) new in \(L.recentDays) days")
        }
        return Model(visible: visible, outsideDeceased: outsideDeceased, set: set, note: note)
    }

    /// «امرأة» · «امرأتان» · «نساء» · «امرأةً»
    static func womenNoun(_ n: Int) -> String {
        L10n.t(AdminFilterText.noun(n, one: "امرأة", two: "امرأتان", few: "نساء", many: "امرأةً"), n == 1 ? "woman" : "women")
    }

    /// «فرد» · «فردان» · «أفراد» · «فرداً» — «فرع خارج العائلة» فيه رجال ونساء
    static func peopleNoun(_ n: Int) -> String {
        L10n.t(AdminFilterText.noun(n, one: "فرد", two: "فردان", few: "أفراد", many: "فرداً"), n == 1 ? "person" : "people")
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if women.isEmpty || !built {
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل شجرة النساء…", "Loading the women's tree…"), rows: 6))
            } else {
                AnyView(loadedPanel(makeModel()))
            }
        }
    }

    private func loadedPanel(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminFilterPanel(set: m.set, selection: $filters, search: $query,
                             placeholder: L10n.t("ابحث باسمها أو اسم أبيها", "Search by her or her father's name"),
                             note: m.note)
            // مساحة القائمة لا تقصر فجأة عند تغيير الفلتر — كانت الصفحة تقفز للأعلى (بلاغ المالك ٢٠٢٦-١١-٠٨)
            VStack(spacing: 0) {
                if m.visible.isEmpty {
                    emptyCard(m)
                } else {
                    AnyView(list(m.visible))
                }
            }
            .frame(minHeight: DS.Hub.filterListMinHeight, alignment: .top)
            if !m.outsideDeceased.isEmpty {
                AnyView(outsideDeceasedSection(m.outsideDeceased))
            }
        }
    }

    /// فارغة: بالبحث «لا أحد بهذا الاسم» + «مسح البحث»؛ بالفلاتر «لا نساء بهذه الفلاتر» + «إعادة ضبط الفلاتر» (spec C.9)
    @ViewBuilder
    private func emptyCard(_ m: Model) -> some View {
        if !trimmedQuery.isEmpty {
            AdminPageStateCard(.empty(L10n.t("لا أحد بهذا الاسم", "Nobody with this name"),
                                      actionTitle: L10n.t("مسح البحث", "Clear search"),
                                      action: { query = "" }))
        } else if filters.order == .newest && filters.status == .all && filters.branch == .family {
            AdminPageStateCard(.empty(L10n.t("لا أسماء مضافة أو مربوطة بعد", "No names added or linked yet")))
        } else {
            AdminFilterEmptyCard(title: L10n.t("لا نساء بهذه الفلاتر", "No women with these filters"),
                                 clearTitle: m.set.resetTitle) {
                withAnimation(reduceMotion ? nil : DS.Anim.snappy) { filters = L.pageDefault }
            }
        }
    }

    /// صفوف بخط رفيع يبدأ من النص (بعد الصورة) — بلا بطاقة (القائمة تضعها في بطاقة، والقسم المطويّ في بطاقته)
    private func rowsStack(_ shown: [AdminWomenEntry], all: [AdminWomenEntry]) -> some View {
        let sonIds = all.compactMap { e -> UUID? in if case .son(let m) = e.kind { return m.id } else { return nil } }
        let showsDate = filters.order == .newest
        return LazyVStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { pos, e in
                if pos > 0 { AdminRowDivider(inset: DS.Icon.avatar + DS.Spacing.md) }
                Button { open(e, sonIds: sonIds) } label: { AdminWomenRow(entry: e, showsDate: showsDate) }
                    .buttonStyle(AdminRowPressStyle())
            }
        }
    }

    private func list(_ shown: [AdminWomenEntry]) -> some View {
        let visible = Array(shown.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            rowsStack(visible, all: shown)
            if shown.count > limit {
                AdminPillButton(title: L10n.t("عرض المزيد (\(shown.count - limit))", "Show more (\(shown.count - limit))"),
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

    /// «المتوفون من خارج العائلة · N» — بطاقة مطويّة تحت قائمة الأحياء، تنفتح بصفوفهم (نفس الصفوف والضغط)
    private func outsideDeceasedSection(_ entries: [AdminWomenEntry]) -> some View {
        AdminSectionCard(title: L10n.t("المتوفون من خارج العائلة", "Deceased outside the family"),
                         tag: DSNumber.grouped(entries.count),
                         isOpen: $showsOutsideDeceased,
                         summary: L10n.t("لا يُعدّون في أي رقم — اضغط لعرضهم", "Not counted anywhere — tap to show")) {
            rowsStack(entries, all: entries)
        }
    }

    private func open(_ e: AdminWomenEntry, sonIds: [UUID]) {
        switch e.kind {
        case .woman(let m), .outsideHusband(let m): selectedWoman = m
        case .son(let m): openMember(sonIds, sonIds.firstIndex(of: m.id) ?? 0)
        }
    }

    // MARK: البيانات

    /// `fresh`: القيمة الجديدة من `onChange(of: women)` أو الجلب؛ غيرها يبني من بيانات الصفحة الحاضرة
    private func rebuild(_ fresh: [FamilyMember]? = nil) {
        let source = fresh ?? women
        guard !source.isEmpty else { return }
        rows = buildRows(source)
        built = true
    }

    private func name(_ m: FamilyMember) -> String { m.fullName.isEmpty ? m.firstName : m.fullName }

    /// نساء العائلة أبجدياً، ثم «فرع خارج العائلة»: أبناء البنات · أزواج البنات من خارجها · النساء من خارجها — المسمّون فقط
    /// (`hasName`)، كقاعدة `AdminFamilyCensus.make` (T2)
    private func buildRows(_ women: [FamilyMember]) -> [AdminWomenEntry] {
        let map = Dictionary(women.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let linked = WomenStore.linkedUserByWoman
        let outside = WomenStore.outsideFamilyIds
        var out: [AdminWomenEntry] = []

        /// «الأحدث»: تاريخ إضافة العقدة أو إنشاء حسابها المربوط (الأحدث منهما)
        func dated(_ w: FamilyMember) -> (date: Date?, line: String?) {
            let added = ApprovalWorkflow.date(w.createdAt)
            let linkedAt = linked[w.id].flatMap { memberVM.member(byId: $0) }.flatMap { ApprovalWorkflow.date($0.createdAt) }
            let byLink = linkedAt.map { l in added.map { l > $0 } ?? true } ?? false
            guard let latest = byLink ? linkedAt : added else { return (nil, nil) }
            let day = AdminOccasionsText.shortDate(latest)
            return (latest, byLink ? L10n.t("رُبطت بحساب \(day)", "Linked to an account \(day)")
                                   : L10n.t("أُضيفت \(day)", "Added \(day)"))
        }

        func womanStatus(_ w: FamilyMember) -> (String, Color)? {
            w.isDeceased == true
                ? (L10n.t("متوفاة", "Deceased"), DS.Color.textTertiary)
                : (linked[w.id] != nil ? (L10n.t("مسجّلة", "Registered"), DS.Color.success) : nil)
        }

        // نساء العائلة — نفس حلقة «النساء» (`AdminMemberCounts.setWomen`)
        for w in AdminGrouping.alphabetical(women.filter { $0.isFemale && $0.hasName && !outside.contains($0.id) }) {
            let husband = w.husbandId.flatMap { map[$0] }
            let sub: String = {
                // تحت اسمها (طلب المالك ٢٠٢٦-١١-٠٨): اسم الزوج · «متزوجة: غير مسجّل الزوج» · «غير متزوجة» — بلا «بنت فلان»
                if let husband {
                    let tag = outside.contains(husband.id) ? L10n.t(" (من خارج العائلة)", " (outside the family)") : ""
                    return L10n.t("الزوج: \(name(husband))\(tag)", "Husband: \(name(husband))\(tag)")
                }
                if w.isMarried == true { return L10n.t("متزوجة: غير مسجّل الزوج", "Married: husband not recorded") }
                return L10n.t("غير متزوجة", "Not married")
            }()
            let when = dated(w)
            out.append(AdminWomenEntry(kind: .woman(w), title: name(w), subtitle: sub, status: womanStatus(w),
                                       needle: ArabicTextNormalizer.normalizeForSearch(name(w)),
                                       fact: L.Fact(deceased: w.isDeceased == true, registered: linked[w.id] != nil,
                                                    married: w.husbandId != nil || w.isMarried == true),
                                       date: when.date, dateLine: when.line))
        }

        // فرع خارج العائلة ١: أبناء البنات (حساباتهم) — حساب مراجعة أبل ليس فرداً
        let review = AppConfigValues.shared.reviewAccountIds
        let sonMembers = AdminGrouping.alphabetical(memberVM.allMembers.filter {
            sons.contains($0.id) && $0.hasName && !review.contains($0.id)
        })
        for s in sonMembers {
            let node = WomenStore.womanByLinkedUser[s.id].flatMap { map[$0] }
            let mother = node?.motherId.flatMap { map[$0] }
            let sub = mother.map { L10n.t("أمّه: \(name($0)) · ابن بنت", "Mother: \(name($0)) · daughter's son") }
                ?? L10n.t("ابن بنت · لم يكمل حسابه", "Daughter's son · account not completed")
            let status: (String, Color) = s.isDeceased == true
                ? (L10n.t("متوفى", "Deceased"), DS.Color.textTertiary)
                : (node == nil ? (L10n.t("أكمل حسابه؟", "Not completed"), DS.Color.warning)
                               : (L10n.t("في الشجرة", "In the tree"), DS.Color.success))
            out.append(AdminWomenEntry(kind: .son(s), title: s.fullName, subtitle: sub, status: status,
                                       needle: ArabicTextNormalizer.normalizeForSearch(s.fullName),
                                       fact: L.Fact(deceased: s.isDeceased == true, registered: true, outside: true)))
        }

        // فرع خارج العائلة ٢: أزواج البنات من خارج العائلة
        for h in AdminGrouping.alphabetical(women.filter { outside.contains($0.id) && !$0.isFemale && $0.hasName }) {
            let wife = women.first { $0.husbandId == h.id }
            out.append(AdminWomenEntry(kind: .outsideHusband(h), title: name(h),
                                       subtitle: wife.map { L10n.t("زوج: \(name($0))", "Husband of \(name($0))") },
                                       status: h.isDeceased == true ? (L10n.t("متوفى", "Deceased"), DS.Color.textTertiary) : nil,
                                       needle: ArabicTextNormalizer.normalizeForSearch(name(h)),
                                       fact: L.Fact(deceased: h.isDeceased == true, registered: linked[h.id] != nil,
                                                    married: true, outside: true)))
        }

        // فرع خارج العائلة ٣: النساء من خارج العائلة (`is_outside_family`، طلب المالك ٢٠٢٦-١١-٢٦): زوجات من عوائل ثانية
        // وبنات البنات — هنا وحده، لا في نساء العائلة (مثل حلقة «النساء» التي لا تعدّهن)
        for w in AdminGrouping.alphabetical(women.filter { $0.isFemale && $0.hasName && outside.contains($0.id) }) {
            let sub: String? = {
                if let hid = w.husbandId, let h = map[hid] ?? memberVM.member(byId: hid) {
                    return L10n.t("زوجة: \(name(h))", "Wife of \(name(h))")
                }
                if let mom = w.motherId.flatMap({ map[$0] }) {
                    return L10n.t("بنت بنت · أمّها: \(name(mom))", "Daughter's daughter · mother: \(name(mom))")
                }
                return nil
            }()
            let when = dated(w)
            out.append(AdminWomenEntry(kind: .woman(w), title: name(w), subtitle: sub, status: womanStatus(w),
                                       needle: ArabicTextNormalizer.normalizeForSearch(name(w)),
                                       fact: L.Fact(deceased: w.isDeceased == true, registered: linked[w.id] != nil,
                                                    married: w.husbandId != nil || w.isMarried == true, outside: true),
                                       date: when.date, dateLine: when.line))
        }
        return out
    }

    /// البحث الدقيق الواحد (`NameSearch`) — الأقرب أولاً، وبترتيب القائمة عند التساوي
    private func search(_ base: [AdminWomenEntry], _ q: String) -> [AdminWomenEntry] {
        guard !q.isEmpty else { return base }
        let words = NameSearch.words(q)
        var hits: [(order: Int, score: Int, entry: AdminWomenEntry)] = []
        for (n, e) in base.enumerated() {
            if let score = NameSearch.score(queryWords: words, candidateWords: e.words) {
                hits.append((order: n, score: score, entry: e))
            }
        }
        hits.sort { $0.score != $1.score ? $0.score < $1.score : $0.order < $1.order }
        return hits.map(\.entry)
    }
}

/// الصورة · الاسم كاملاً · سطر الزوج/الأب (أو تاريخ الإضافة في «الأحدث») · الحالة كلمة · السهم
struct AdminWomenRow: View {
    let entry: AdminWomenEntry
    /// ترتيب «الأحدث»: «أُضيفت 12 نوفمبر» مكان سطر الزوج
    var showsDate: Bool = false

    private var member: FamilyMember {
        switch entry.kind { case .woman(let m), .outsideHusband(let m), .son(let m): return m }
    }

    private var tint: Color {
        switch entry.kind {
        case .woman: return member.isDeceased == true ? DS.Color.deceased : DS.Color.female
        case .outsideHusband, .son: return DS.Color.slate
        }
    }

    private var subtitle: String? {
        (showsDate ? entry.dateLine : nil) ?? entry.subtitle
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Group {
                if member.isDeceased == true {
                    DSMemberAvatar(name: entry.title, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: tint)
                        .grayscale(1)
                } else {
                    DSMemberAvatar(name: entry.title, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: tint)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // الاسم كاملاً بحجمه — سطران إن طال (طلب المالك ٢٠٢٦-١١-٠٨ «ليش الاسم صغر»)
                Text(entry.title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subtitle {
                    Text(verbatim: sub)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let s = entry.status {
                Text(verbatim: s.text)
                    .dsFont(.chip)
                    .foregroundColor(s.tint.dsReadableGlyph)
                    .fixedSize()
            }
            DSChevron()
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.t("يفتح التفاصيل", "Opens the details"))
    }
}

#endif
