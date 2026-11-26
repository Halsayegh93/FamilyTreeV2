import SwiftUI

// MARK: - «العائلة» = صفحة الأعضاء الواحدة (U11، ثم admin v2 اتجاه «أ» — الوحدة V2-2، ٢٠٢٦-١١-٢٦)
//
// الرأس الكحلي (`AdminMembersHeader.swift`): «‹ الإدارة» · «العائلة ⌄» · «＋» · «⋯ التقارير (PDF)» ← «كل العائلة» (أو اسم
// الفرع) ← مربّعات «2,729 رجل · 262 امرأة ‹ · 46 حياً خارج العائلة ‹» ← حقل البحث بالاسم أو الرقم + «تصفية (n)» (فلاتر
// المالك «ب»: حقل واحد + زرّ واحد). ورقة التصفية (طقم U5، F3 اختيار متعدّد يُطبَّق فوراً): «الحساب» (الكل · لهم حساب ·
// بلا حساب) ← «الحالة» (الكل · الأحياء · المتوفون) ← «الفرع» (الكل، أو صفّ يفتح قائمة الفروع داخل الورقة — اختيار واحد)،
// والأعداد تتبع بقية الاختيارات (`AdminMembersLogic.Tally`). تحت الرأس على الأبيض:
//  ١) شريحة لكل اختيار بـ✕ (`AdminActiveFilterChips` — كل شريحة تزيل اختيارها وحده، F3) وسطر «123 رجل · أبجدياً» مع
//     التصفية أو البحث فقط.
//  ٢) بطاقة «يحتاج مراجعتك» («363 تواريخ وفاة ناقصة» / «هل ما زالوا أحياء؟» · «5 قوائم») ← صفحة «يحتاج مراجعتك»
//     (`AdminReviewHubPage`، U12). تختفي حين تصل كل القوائم صفراً.
//  ٣) القائمة: بلا تصفية ولا بحث بالفروع («▍فرع جاسم (214)»)، وإلا أبجدياً (والبحث بالأقرب). الصفّ: الصورة · الاسم (أول
//     كلمتين عريضتان، سطر يُقصّ في آخره) · الحالة الرسمية («عضو مسجّل · آخر دخول اليوم»…) · ‹ — يفتح ورقة العضو
//     (`AdminMemberSheet(ids:start:)`، U13) بالسابق والتالي في القائمة نفسها. «عرض المزيد» كل ٤٠.
// مفتاح «شجرة العائلة | شجرة النساء» وبطاقة المربّعات والشرائح المسطّحة حُذفت (spec E.9–E.12).
// المعاملات القديمة `chip:`/`sub:`/`womenOutside:` تبقى (روابط «اليوم» والإشعارات و`AdminUsageDevicesKit`): كل قيمة فلتر
// أو قائمتها تُدفع فوق الجذر (`AdminMembersLogic.opening`)؛ والهبوط `AdminMembersLanding` من `AdminAreaRouter.take` حين
// تُفتح بلا معاملات. الصلاحيات كما كانت: التسجيل `canRegisterMembers` (× «يعدّل» في الجدول)، التقارير `isAdmin`.

/// ورقة العضو مفتوحة على قائمة (السابق/التالي يتنقّلان فيها)
struct AdminMemberSheetContext: Identifiable {
    let id = UUID()
    let ids: [UUID]
    let start: Int
}

/// تصفية «العائلة» (spec C.7، F3): «الحساب» و«الحالة» اختيار متعدّد (فارغة = «الكل»)، و«الفرع» اختيار واحد (منتقٍ شجري)،
/// و«القائمة» تصفية إضافية من رابط قديم وحده
struct AdminMembersFilters: Equatable {
    /// لهم حساب · بلا حساب (بلا `.all`)
    var accounts: Set<AdminAccountFilter> = []
    /// الأحياء · المتوفون (بلا `.all`)
    var lives: Set<AdminLifeFilter> = []
    /// رأس الفرع (بأي مستوى) — nil = كل الفروع
    var branch: UUID? = nil
    /// شريحة فرعية قديمة لا تقابلها قائمة مراجعة («لا تصله الإشعارات»…) — شريحة تُزال
    var sub: AdminMemberSub? = nil

    var isEmpty: Bool { self == AdminMembersFilters() }

    /// اختيار واحد لكل مجموعة — «الكل» = لا اختيار
    init(account: AdminAccountFilter = .all, life: AdminLifeFilter = .all, branch: UUID? = nil, sub: AdminMemberSub? = nil) {
        self.accounts = account == .all ? [] : [account]
        self.lives = life == .all ? [] : [life]
        self.branch = branch
        self.sub = sub
    }

    /// الروابط القديمة والهبوط: كل اختيار فيها شريحة تحت الشريط تُزال (`AdminMembersLogic.picks`)
    init(_ o: AdminMembersLogic.Opening) {
        self.accounts = Set(AdminMembersLogic.picks(o.account).map { AdminAccountFilter($0) })
        self.lives = Set(AdminMembersLogic.picks(o.life).map { AdminLifeFilter($0) })
        self.branch = o.branch
        self.sub = o.sub.flatMap(AdminMemberSub.init(rawValue:))
    }

    var accountLogic: Set<AdminMembersLanding.Account> { Set(accounts.map(\.logic)) }
    var lifeLogic: Set<AdminMembersLanding.Life> { Set(lives.map(\.logic)) }
}

/// ما يُدفع فوق جذر «العائلة» (وجهة واحدة)
enum AdminMembersPush {
    case review(AdminMemberReview)
    case deathDates
    case women(AdminWomenLanding)
    case reports(AdminReportScope?)

    init(_ p: AdminMembersLogic.Push) {
        switch p {
        case .review(let r):  self = .review(AdminMemberReview(rawValue: r.rawValue) ?? .problems)
        case .deathDates:     self = .deathDates
        case .women(let l):   self = .women(l)
        }
    }
}

/// القائمة بعد البحث والفرع و«القائمة» (قبل «الحساب» و«الحالة») وعدّها ٢×٢
struct AdminMembersScope {
    let rows: [Int]
    let tally: AdminMembersLogic.Tally
}

/// ذاكرة القوائم المحسوبة لكل (نسخة الفهرس، الفرع، «القائمة»، البحث) — الورقة والشرائح والملخّص يسألون عنها مراراً في الرسم
/// الواحد. مرجع لا حالة: الكتابة فيه لا تعيد الرسم
final class AdminMembersScopeMemo {
    struct Key: Hashable {
        let version: Int
        let branch: UUID?
        let sub: AdminMemberSub?
        let query: String
    }

    private var cache: [Key: AdminMembersScope] = [:]

    func value(_ key: Key, make: () -> AdminMembersScope) -> AdminMembersScope {
        if let hit = cache[key] { return hit }
        if cache.count > 12 { cache.removeAll(keepingCapacity: true) }
        let made = make()
        cache[key] = made
        return made
    }
}

struct AdminMembersPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// أبناء البنات — بيتهم «نساء العائلة» (يُستبعدون من القائمة)
    @ObservedObject private var sons = DaughterSonsIndex.shared
    /// «حي ✓» المحلية لهذا المستخدم (عدد «هل ما زالوا أحياء؟»)
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adminBackTitle) private var outerBack
    /// عدّاد الانتقال (`.area(.family, hop)`) — مفتاح الهبوط
    @Environment(\.adminAreaHop) private var hop

    // أرقام الرأس
    @State private var census = AdminFamilyCensus()
    @State private var womenRows: [FamilyMember] = WomenStore.cache
    @State private var womenHealth: AdminStoreHealth = WomenStore.cache.isEmpty ? .idle : .loaded(at: Date())

    // الرأس المطويّ
    @State private var collapsed = false
    @State private var compactLine: CGFloat = DS.Hub.compactBar
    /// زرّ البحث في السطر المطويّ: يمرّر إلى الحقل ثم يضع المؤشر فيه
    @State private var searchToken = 0
    @State private var searchFocus = 0

    // القائمة
    @State private var filters: AdminMembersFilters
    @State private var query = ""
    @State private var limit = Self.pageSize
    @State private var index = AdminMembersIndex.empty
    @State private var tree = AdminFamilyTree.empty
    @State private var version = 0
    @State private var memo = AdminMembersScopeMemo()
    /// أعداد قوائم «يحتاج مراجعتك» (المفتاح الغائب = لم يصل) — نفس صفحتها (U12)
    @State private var reviewCounts: [AdminReviewHubLogic.List: Int] = [:]
    @State private var showFilters = false

    // ما يُفتح
    @State private var sheet: AdminMemberSheetContext?
    /// صورة العضو مكبّرة بالضغط عليها في الصفّ (طلب المالك ٢٠٢٦-١١-١١)
    @State private var photoURL: AdminPhotoURL?
    @State private var push: AdminMembersPush?
    @State private var showPush = false
    /// قائمة تُدفع عند الظهور (رابط قديم أو هبوط)
    @State private var pendingPush: AdminMembersLogic.Push?
    @State private var landed = false

    /// المعاملات على افتراضها — الهبوط المخزَّن يُطبَّق
    private let usesDefaults: Bool
    private let explicitLanding: AdminMembersLanding?

    static let pageSize = 40
    private static let searchAnchor = "adminMembersSearch"

    /// - chip/sub: روابط قديمة («اليوم»، الإشعارات، `AdminUsageDevicesKit`) — كل قيمة فلتر أو قائمة تُدفع فوق الجذر
    /// - womenOutside: «نساء العائلة» على «فرع خارج العائلة» فوق الجذر
    /// - landing: هبوط صريح (يغلب المخزَّن في `AdminAreaRouter`) — يُطبَّق حين تكون المعاملات القديمة على افتراضها
    init(chip: AdminMemberChip = .all, sub: AdminMemberSub = .all, womenOutside: Bool = false,
         landing: AdminMembersLanding? = nil) {
        let defaults = AdminMembersLogic.isDefault(chip: chip.rawValue, sub: sub.rawValue, womenOutside: womenOutside)
        let opening: AdminMembersLogic.Opening
        if defaults, let landing {
            opening = AdminMembersLogic.opening(landing: landing)
        } else {
            opening = AdminMembersLogic.opening(chip: chip.rawValue, sub: sub.rawValue, womenOutside: womenOutside)
        }
        usesDefaults = defaults
        explicitLanding = landing
        _filters = State(initialValue: AdminMembersFilters(opening))
        _pendingPush = State(initialValue: opening.push)
    }

    // حارس المكدس: الرأس والمحتوى والطبقة المثبّتة خلف `AnyView`
    var body: some View {
        let model = makeModel()
        return ScrollViewReader { proxy in
            AdminHubPage(pinned: collapsed && index.built ? AnyView(compactBar(model).transition(.opacity)) : nil) {
                AdminBandHeader(title: AdminArea.family.title,
                                subtitle: AdminMembersLogic.caption(branch: filters.branch.map(branchTitle)),
                                badge: authVM.adminCanEdit(.family) ? nil : AdminPageHeader.readOnlyText,
                                bottomPadding: DS.Spacing.md, isAreaRoot: true) {
                    AnyView(headerButtons(model))
                } accessory: {
                    // حارس المكدس: المربّعات والحقل نوعان مستقلان خلف `AnyView`
                    AnyView(bandAccessory(model))
                }
            } content: {
                AnyView(content(model))
            }
            .refreshable { await reload(force: true) }
            .onChange(of: searchToken) { _ in
                if reduceMotion {
                    proxy.scrollTo(Self.searchAnchor, anchor: .center)
                } else {
                    withAnimation(DS.Anim.smooth) { proxy.scrollTo(Self.searchAnchor, anchor: .center) }
                }
            }
        }
        .adminFilterSheet(isPresented: $showFilters, set: model.set, selection: $filters)
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
        .fullScreenCover(item: $photoURL) { p in
            ProjectPhotoViewer(urls: [p.url], startIndex: 0, section: .admin)
        }
        .navigationDestination(isPresented: $showPush) {
            AdminLazyPage { [push] in Self.destination(push) }
        }
        .task { await start() }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: accounts.accounts) { _ in rebuild() }
        .onChange(of: accounts.loaded) { _ in rebuild() }
        .onChange(of: sons.ids) { _ in rebuild() }
        .onChange(of: verified.ids) { _ in refreshReviews() }
        .onChange(of: query) { _ in limit = Self.pageSize }
        .onChange(of: filters) { _ in limit = Self.pageSize }
        .debugStackProbe("AdminMembersPage", limitKB: DebugStackLimit.page)
    }

    // MARK: التحميل

    private func start() async {
        if !landed {
            landed = true
            // الهبوط يُقرأ مرة ويُمسح دائماً؛ يُطبَّق حين تُفتح الصفحة بلا معاملات قديمة (الصريح يغلب)
            let stored = AdminAreaRouter.take(.members, hop: hop)
            if usesDefaults, let stored {
                let merged = explicitLanding.map { stored.overridden(by: $0) } ?? stored
                let o = AdminMembersLogic.opening(landing: merged)
                filters = AdminMembersFilters(o)
                if let p = o.push { pendingPush = p }
            }
            if let p = pendingPush {
                pendingPush = nil
                // فوق الجذر بعد ظهوره — الرجوع يعود للجذر
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(AdminMembersPush(p)) }
            }
        }
        verified.activate(user: authVM.currentUser?.id)
        if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        rebuild()
        await sons.refresh()
        await accounts.refresh()
        await loadWomen(force: false)
    }

    private func reload(force: Bool) async {
        await memberVM.fetchAllMembers(force: force)
        rebuild()
        await sons.refresh()
        await accounts.refresh(force: force)
        await loadWomen(force: force)
    }

    /// شجرة النساء لأرقام «امرأة» و«خارج العائلة» — الكاش أولاً، وجلب للقراءة إن لم تُحمَّل
    private func loadWomen(force: Bool) async {
        if !force, !womenRows.isEmpty {
            refreshCensus()
            return
        }
        let before = womenHealth
        womenHealth = womenHealth.beginning()
        do {
            let fresh = try await WomenStore.fetch()
            womenRows = fresh
            womenHealth = womenHealth.ending(success: true)
            refreshCensus()
        } catch {
            if Log.isCancellation(error) {
                womenHealth = before
                return
            }
            Log.fetchError("[AdminMembersPage] women tree load failed", error)
            womenHealth = womenHealth.ending(success: false)
        }
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
        tree = AdminFamilyTree(memberVM.allMembers)
        version += 1
        refreshReviews()
        refreshCensus()
    }

    /// أرقام الرأس — مع كل بناء للفهرس، وبعد وصول شجرة النساء
    private func refreshCensus() {
        census = AdminFamilyCensus.make(members: memberVM.allMembers, women: womenRows)
    }

    /// أعداد قوائم «يحتاج مراجعتك» — المصدر الواحد مع صفحتها (`AdminReviewHubCounts`)
    private func refreshReviews() {
        reviewCounts = AdminReviewHubCounts.make(index: index, verified: verified.ids, members: memberVM.allMembers,
                                                 photos: .init(authVM: authVM))
    }

    private func open(_ p: AdminMembersPush) {
        push = p
        showPush = true
    }

    /// الصفحة فوق الجذر — رجوعها «العائلة» وقسمها هنا (الصفحة المدفوعة لا ترث البيئة)
    private static func destination(_ p: AdminMembersPush?) -> AnyView {
        let page: AnyView
        switch p {
        case .review(let r)?:     page = AnyView(AdminReviewListPage(review: r, branchSet: nil))
        case .deathDates?:        page = AnyView(DeathDatesCampaignPage())
        case .women(let l)?:      page = AnyView(AdminWomenPanel(landing: l))
        case .reports(let s)?:    page = AnyView(AdminReportsView(scope: s))
        case nil:                 page = AnyView(EmptyView())
        }
        return AnyView(page.adminBackTitle(AdminArea.family.title).adminArea(.family))
    }

    // MARK: الرأس

    private var headerItems: [AdminHeaderItem] {
        let men: AdminStoreHealth? = memberVM.membersLoadFailed && memberVM.allMembers.isEmpty ? .failed(lastGood: nil) : nil
        let admin = authVM.isAdmin
        return AdminMembersHeaderItems.make(
            census: census, menHealth: men, womenHealth: womenHealth,
            retryMen: { Task { await reload(force: true) } },
            retryWomen: { Task { await loadWomen(force: true) } },
            // «نساء العائلة» للمالك والمدير (طلب المالك ٢٠٢٦-١١-٠٨)؛ المراقب ← شجرة النساء في تبويب الشجرة
            openWomen: admin ? { open(.women(AdminWomenLanding(status: .all))) } : { Self.openWomenTree() },
            openOutside: admin ? { open(.women(AdminWomenLanding(status: .all, branch: .outside))) } : nil)
    }

    private static func openWomenTree() {
        TreeTabContainer.openWomenOnAppear = true
        NotificationCenter.default.post(name: .openWomenTree, object: nil)
    }

    /// ما تحت العنوان في الكحلي: مربّعات الأرقام ثم الحقل و«تصفية». الحقل مرساة زرّ البحث في السطر المطويّ، ومنه يُقاس الطيّ
    private func bandAccessory(_ model: AdminMembersListModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminMembersKPIRow(kpis: AdminMembersHeaderItems.kpis(headerItems))
                .padding(.top, DS.Spacing.xsm)
            AdminMembersFilterBar(query: $query, focusToken: searchFocus, activeCount: model.snapshot.items.count) {
                showFilters = true
            }
            .id(Self.searchAnchor)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(AdminHubScroll.space)).minY } action: { barMoved($0) }
            .padding(.top, DS.Spacing.md)
        }
    }

    private func headerButtons(_ model: AdminMembersListModel) -> some View {
        let canRegister = authVM.canRegisterMembers && authVM.adminCanEdit(.family)
        return AdminMembersHeaderButtons(
            register: canRegister ? { Self.registerPage } : nil,
            // التقارير بالفلاتر والفرع والبحث الحاليين — الصفّ نفسه الذي في القائمة
            reports: authVM.isAdmin ? { open(.reports(exportScope(model))) } : nil)
    }

    private static var registerPage: AnyView {
        AnyView(AdminRegisterMemberView().adminBackTitle(AdminArea.family.title).adminArea(.family))
    }

    /// التصدير: الفلاتر والفرع والبحث — بلا شيء = كل العائلة
    private func exportScope(_ model: AdminMembersListModel) -> AdminReportScope? {
        let q = trimmedQuery
        guard !filters.isEmpty || !q.isEmpty else { return nil }
        var parts: [String] = []
        parts += AdminAccountFilter.allCases.filter(filters.accounts.contains).map(\.title)
        parts += AdminLifeFilter.allCases.filter(filters.lives.contains).map(\.title)
        if let sub = filters.sub { parts.append(sub.title) }
        if let b = filters.branch { parts.append(branchTitle(b)) }
        if !q.isEmpty { parts.append("«\(q)»") }
        return AdminReportScope(ids: Set(model.rows.map { index.entries[$0].id }), title: parts.joined(separator: " · "))
    }

    // MARK: الطيّ عند التمرير

    /// شريط البحث وصل تحت سطر الرأس المطويّ ← يُثبَّت السطر (بحث + «تصفية») والشرائح تحته؛ وتعود الصفحة لرأسها حين ينزل
    private func barMoved(_ top: CGFloat) {
        let shouldCollapse = top < compactLine
        guard shouldCollapse != collapsed else { return }
        if reduceMotion {
            collapsed = shouldCollapse
        } else {
            withAnimation(DS.Anim.quick) { collapsed = shouldCollapse }
        }
    }

    private func compactBar(_ model: AdminMembersListModel) -> some View {
        AdminMembersCompactBar(
            total: census.counts.men,
            backTitle: outerBack ?? AdminArea.homeTitle,
            back: { dismiss() },
            search: {
                searchToken += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : DS.Hub.compactSearchDelay)) {
                    searchFocus += 1
                }
            },
            filterCount: model.snapshot.items.count,
            openFilters: { showFilters = true },
            chips: model.snapshot.items.isEmpty ? nil
                : AnyView(AdminActiveFilterChips(set: model.set, selection: $filters, snapshot: model.snapshot)),
            lineHeight: $compactLine)
    }

    // MARK: النموذج (يُحسب مرة لكل رسم)

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func makeModel() -> AdminMembersListModel {
        let base = scope(branch: filters.branch, sub: filters.sub)
        let accounts = filters.accounts, lives = filters.lives
        let rows = base.rows.filter { index.matches($0, accounts: accounts, lives: lives) }
        let set = filterSet(base: base)
        let searching = !trimmedQuery.isEmpty
        let order = AdminMembersLogic.Order.make(filtered: !filters.isEmpty, searching: searching)
        return AdminMembersListModel(rows: rows, set: set, snapshot: set.snapshot(filters), order: order,
                                     searching: searching)
    }

    /// القائمة بعد «القائمة» الإضافية والفرع والبحث، وعدّها ٢×٢ — من الذاكرة إن حُسبت لهذه القيم
    private func scope(branch: UUID?, sub: AdminMemberSub?) -> AdminMembersScope {
        let q = trimmedQuery
        let key = AdminMembersScopeMemo.Key(version: version, branch: branch, sub: sub, query: q)
        return memo.value(key) {
            var rows = index.rows(.all, .all)
            if let sub {
                let members = Set(index.rows(sub.homeChip, sub))
                rows = rows.filter { members.contains($0) }
            }
            if let branch {
                let members = tree.subtree(of: branch)
                rows = rows.filter { members.contains(index.entries[$0].id) }
            }
            rows = searched(rows, q)
            var tally = AdminMembersLogic.Tally()
            for i in rows {
                let e = index.entries[i]
                tally.add(deceased: e.member.isDeceased == true, hasLogin: AdminMembersIndex.hasLogin(e))
            }
            return AdminMembersScope(rows: rows, tally: tally)
        }
    }

    /// البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب، والرقم أرقاماً فقط — النتائج بالأقرب
    private func searched(_ base: [Int], _ q: String) -> [Int] {
        guard !q.isEmpty else { return base }
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

    /// العدد لحالة تصفية (يشمل البحث — نفس ما يُرى) — nil قبل وصول الحسابات لخيار «الحساب»
    private func resultCount(_ s: AdminMembersFilters) -> Int? {
        guard index.built else { return nil }
        return scope(branch: s.branch, sub: s.sub).tally
            .shown(accounts: s.accountLogic, lives: s.lifeLogic, accountsReady: index.accountsReady)
    }

    /// اسم الفرع في صفّ «الفرع» وشريحته: الاسم المخصّص من «أسماء العوائل والفروع» إن وُجد، وإلا الاسم المختصر لرأسه
    /// (كصفحة تواريخ الوفاة — U12)
    private func branchTitle(_ id: UUID) -> String {
        if let custom = appSettingsVM.branchName(for: id) { return custom }
        let m = tree.byId[id] ?? memberVM.member(byId: id)
        return m.map { $0.shortFullName.isEmpty ? $0.fullName : $0.shortFullName } ?? L10n.t("فرع", "Branch")
    }

    /// ورقة التصفية (spec C.7، mock 5، F3): الحساب ← الحالة (اختيار متعدّد) ← الفرع (منتقٍ، اختيار واحد) — و«القائمة» حين
    /// جاءت من رابط. عدد كل خيار = النتيجة لو اختير وحده في مجموعته مع بقية الاختيارات
    private func filterSet(base: AdminMembersScope) -> AdminFilterSet<AdminMembersFilters> {
        let ready = index.accountsReady
        let members = memberVM.allMembers
        return AdminFilterSet(
            noun: { _ in L10n.t("رجل", "men") },
            resultCount: { s in resultCount(s) },
            groups: { s in
                let tally = index.built ? scope(branch: s.branch, sub: s.sub).tally : AdminMembersLogic.Tally()
                func count(_ a: Set<AdminAccountFilter>, _ l: Set<AdminLifeFilter>) -> Int? {
                    index.built ? tally.shown(accounts: Set(a.map(\.logic)), lives: Set(l.map(\.logic)),
                                              accountsReady: ready) : nil
                }
                let accounts = AdminAccountFilter.allCases.filter { $0 != .all }
                let lives = AdminLifeFilter.allCases.filter { $0 != .all }
                var groups: [AdminFilterGroup<AdminMembersFilters>] = [
                    .choices("account", title: L10n.t("الحساب", "Account"), values: \.accounts,
                             options: accounts.map { AdminFilterOption($0, $0.title, count: count([$0], s.lives)) }),
                    .choices("life", title: L10n.t("الحالة", "Status"), values: \.lives,
                             options: lives.map { AdminFilterOption($0, $0.title, count: count(s.accounts, [$0])) }),
                    .picker("branch", title: L10n.t("الفرع", "Branch"), value: \.branch, all: nil,
                            allTitle: L10n.t("كل الفروع", "All branches"), valueTitle: s.branch.map(branchTitle),
                            chooseTitle: L10n.t("اختر فرعاً", "Pick a branch"),
                            count: s.branch == nil ? nil : count(s.accounts, s.lives), ownsHeader: true) { current, pick in
                        AnyView(BranchPickerSheet(allMembers: members, selectedId: current, allLevels: true,
                                                  onSelect: { pick($0) }))
                    },
                ]
                if let sub = s.sub {
                    groups.append(.single("list", title: L10n.t("القائمة", "List"), value: \.sub, neutral: nil, options: [
                        AdminFilterOption<AdminMemberSub?>(nil, AdminFilterText.all, count: resultCount(cleared(s))),
                        AdminFilterOption<AdminMemberSub?>(sub, sub.title, count: count(s.accounts, s.lives)),
                    ]))
                }
                return groups
            })
    }

    private func cleared(_ s: AdminMembersFilters) -> AdminMembersFilters {
        var next = s
        next.sub = nil
        return next
    }

    // MARK: المحتوى

    private func content(_ model: AdminMembersListModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !index.built {
                if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                              message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                              retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
                } else {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…"), rows: 8))
                }
            } else {
                if AdminMembersLogic.showsResultLine(filtered: !model.snapshot.items.isEmpty, searching: model.searching) {
                    AnyView(filterStatus(model))
                        .padding(.bottom, DS.Spacing.md)
                }
                if let row = reviewRow {
                    row.padding(.bottom, DS.Spacing.lg)
                }
                AnyView(listSection(model))
                AnyView(footer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: «يحتاج مراجعتك»

    /// البطاقة بسطريها، أو هيكلها قبل وصول الأرقام — nil حين لا أحد في أي قائمة (أو فشلت قوائم الحسابات والباقي صفر).
    /// الأعداد من المصدر الواحد مع صفحتها (`AdminReviewHubCounts`) بترتيب قوائمها
    private var reviewRow: AnyView? {
        // «تواريخ وفاة ناقصة» تتصدّر (حملة المالك — رقمها خرج من مربّع «المناسبات» إلى هنا)
        let lists = AdminReviewHubLogic.List.allCases.map {
            AdminMembersLogic.ReviewList($0.title, reviewCounts[$0], leads: $0 == .death, forms: $0.forms)
        }
        switch AdminMembersLogic.reviewState(lists, accountsFailed: accounts.health.look == .unknown) {
        case .hidden:          return nil
        case .loading:         return AnyView(AdminMembersReviewRow(card: nil))
        case .card(let card):  return AnyView(AdminMembersReviewRow(card: card))
        }
    }

    // MARK: التصفية المفعّلة

    /// شرائح التصفية المفعّلة (طقم U5 — كل ✕ تلغي فلترها وحده) ثم «123 رجل · أبجدياً». مع التصفية أو البحث فقط
    private func filterStatus(_ model: AdminMembersListModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            AdminActiveFilterChips(set: model.set, selection: $filters, snapshot: model.snapshot)
            AdminMembersResultLine(result: model.snapshot.result, set: model.set, order: model.order.title)
        }
    }

    // MARK: القائمة

    @ViewBuilder
    private func listSection(_ model: AdminMembersListModel) -> some View {
        if !filters.accounts.isEmpty && !index.accountsReady {
            // «لهم حساب/بلا حساب» قبل وصول قوائم الحسابات: لا قائمة فارغة مضلِّلة
            if accounts.health.look == .unknown {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الحسابات", "Couldn't load the accounts"),
                                          message: L10n.t("تصفية «الحساب» تحتاجها", "The «Account» filter needs them"),
                                          retry: { Task { await accounts.refresh(force: true) } }))
            } else {
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الحسابات…", "Loading accounts…"), rows: 4))
            }
        } else if model.rows.isEmpty {
            if model.searching {
                AdminPageStateCard(.empty(L10n.t("لا أحد بهذا الاسم أو الرقم", "Nobody with this name or number"),
                                          actionTitle: L10n.t("مسح البحث", "Clear search"), action: { query = "" }))
            } else if !filters.isEmpty {
                AdminFilterEmptyCard(title: AdminMembersText.noResults, editFilters: { showFilters = true })
            } else {
                AdminPageStateCard(.empty(L10n.t("لا أحد هنا الآن", "Nobody here right now")))
            }
        } else if model.order == .branches {
            AnyView(groupedList(model.rows))
        } else {
            AnyView(flatList(model.rows))
        }
    }

    /// أبجدياً (أو بالأقرب للبحث): صفوف مسطّحة بخط رفيع يبدأ من النص (mock 4)
    private func flatList(_ rows: [Int]) -> some View {
        let ids = rows.map { index.entries[$0].id }
        let visible = Array(rows.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            AdminMembersListTopRule()
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element) { pos, i in
                    row(i, ids: ids, position: pos, divider: pos > 0)
                }
            }
            moreButton(total: rows.count)
        }
    }

    /// بالفروع («فرع جاسم · 214»، `BranchPickerSheet.familyRoot` والأسماء المخصّصة) — «عرض المزيد» يمرّ على الفروع بالترتيب
    private func groupedList(_ rows: [Int]) -> some View {
        let groups = index.branches
        let ids = groups.flatMap { $0.rows.map { index.entries[$0].id } }
        var sections: [(branch: AdminMembersIndex.Branch, shown: [Int], offset: Int)] = []
        var offset = 0
        var budget = limit
        for g in groups where budget > 0 {
            let shown = Array(g.rows.prefix(budget))
            sections.append((g, shown, offset))
            offset += g.rows.count
            budget -= shown.count
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { n, section in
                AdminMembersBranchHeader(title: section.branch.title, count: section.branch.rows.count)
                    .padding(.top, n == 0 ? 0 : DS.Spacing.lg)
                AdminMembersListTopRule()
                LazyVStack(spacing: 0) {
                    ForEach(Array(section.shown.enumerated()), id: \.element) { pos, i in
                        row(i, ids: ids, position: section.offset + pos, divider: pos > 0)
                    }
                }
            }
            moreButton(total: ids.count)
        }
    }

    @ViewBuilder
    private func moreButton(total: Int) -> some View {
        if total > limit {
            AdminPillButton(title: L10n.t("عرض المزيد (\(DSNumber.grouped(total - limit)))",
                                          "Show more (\(DSNumber.grouped(total - limit)))"),
                            icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                limit += Self.pageSize
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.md)
        }
    }

    private func row(_ i: Int, ids: [UUID], position: Int, divider: Bool) -> some View {
        let entry = index.entries[i]
        return Button {
            sheet = AdminMemberSheetContext(ids: ids, start: position)
        } label: {
            AdminMemberListRow(entry: entry, subline: statusLine(entry), onPhotoTap: { photoURL = AdminPhotoURL(url: $0) },
                               boldLead: true)
        }
        .buttonStyle(AdminRowPressStyle(bleed: DS.Spacing.lg))
        .overlay(alignment: .top) {
            if divider { AdminRowDivider(inset: DS.Icon.avatar + DS.Spacing.md) }
        }
    }

    /// سطر الحالة الرسمية (spec C.6): «عضو مسجّل · آخر دخول اليوم» · «بدون حساب · بلا تاريخ ميلاد» · «متوفى» · «حساب موقوف»
    /// — فارغ قبل وصول قوائم الحسابات
    private func statusLine(_ e: AdminMembersIndex.Entry) -> String {
        guard let status = e.status else { return "" }
        switch status {
        case .registered:
            return "\(status.title) · \(lastSeenText(e))"
        case .treeOnly where e.gaps.contains(.noBirth):
            return "\(status.title) · \(AdminMemberGap.noBirth.tag)"
        default:
            return status.title
        }
    }

    private func lastSeenText(_ e: AdminMembersIndex.Entry) -> String {
        guard let seen = accounts.info(e.id)?.lastSeen else {
            return L10n.t("لم يفتح التطبيق بعد", "Hasn't opened the app yet")
        }
        return AdminMembersLogic.lastSeen(days: AdminMembersLogic.daysSince(seen))
            ?? L10n.t("آخر دخول \(DSDateText.display(seen))", "Last seen \(DSDateText.display(seen))")
    }

    // MARK: آخر سطر

    /// «آخر تحديث 9:41» للحسابات (spec A.2) — وبعد فشل تحديث لاحق «أعد المحاولة» بجانبه، والأرقام القديمة باقية
    @ViewBuilder
    private var footer: some View {
        if let stamp = accounts.health.lastGood {
            HStack(spacing: DS.Spacing.sm) {
                Text(AdminStoreHealthText.updated(stamp))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                if accounts.health.canRetry {
                    Button(AdminStoreHealthText.retry) { Task { await accounts.refresh(force: true) } }
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.primary)
                        .frame(minHeight: DS.Icon.tapTarget)
                }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
            .padding(.top, DS.Spacing.lg)
        }
    }
}

/// ما يرسمه المحتوى في الرسم الواحد
struct AdminMembersListModel {
    /// صفوف القائمة الظاهرة (مواضع الفهرس) بترتيبها
    let rows: [Int]
    let set: AdminFilterSet<AdminMembersFilters>
    let snapshot: AdminFilterSnapshot<AdminMembersFilters>
    let order: AdminMembersLogic.Order
    let searching: Bool
}

// MARK: - الحقل + «تصفية» في الرأس الكحلي (فلاتر المالك «ب»، بحقل يقبل المؤشر من الرأس المطويّ)

/// سطر واحد على الكحلي: حقل البحث الأبيض (يأخذ الباقي) + «تصفية» الكريمي بعدده (`AdminMembersFilterPill`). من أحجام
/// إمكانية الوصول الزرّ تحت الحقل
struct AdminMembersFilterBar: View {
    @Binding var query: String
    var focusToken: Int = 0
    let activeCount: Int
    let openFilters: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// «2,719» — فاصل الآلاف بأرقام لاتينية (كأرقام اللوحة)
    static func grouped(_ n: Int) -> String { DSNumber.grouped(n) }

    var body: some View {
        // أبيض في الفاتح (سطح البطاقة في الداكن) بلا إطار يُرى على الكحلي — وإطار المؤشر حين يُكتب فيه
        let field = AdminMembersSearchField(text: $query, placeholder: AdminFilterText.searchPlaceholder, focusToken: focusToken,
                                            radius: DS.Hub.familyControlRadius, idleStroke: DS.Hub.glassLine)
        let button = AdminMembersFilterPill(count: activeCount, action: openFilters)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                field
                button
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                field
                button.fixedSize()
            }
        }
    }
}

/// حقل البحث بشكل شريط الفلاتر (`DSSearchField(style: .admin)`: ٤٤، إطار `frameStroke`) — وزرّ البحث في الرأس المطويّ
/// يضع المؤشر فيه (`focusToken`). `fill`/`radius`/`idleStroke` لشكله فوق الكحلي في رأس «العائلة»
struct AdminMembersSearchField: View {
    @Binding var text: String
    let placeholder: String
    var focusToken: Int = 0
    var fill: Color = DS.Color.surface
    var radius: CGFloat = DS.Radius.md
    var idleStroke: Color = DS.Hub.frameStroke
    @FocusState private var focused: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        let tint = DS.Color.primary.dsChrome(in: section).dsReadableGlyph
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(focused ? tint : DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .dsFieldFont(.fieldValue)
                .foregroundColor(DS.Color.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lgCompact, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -DS.Spacing.sm)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DS.Icon.tapTarget)
        .dsFocusFieldBox(focused: focused, tint: tint, fill: fill, radius: radius, idleStroke: idleStroke)
        .onChange(of: focusToken) { _ in focused = true }
    }
}

// MARK: - القائمة

/// خطّ رفيع أعلى القائمة المسطّحة (mock 4)
struct AdminMembersListTopRule: View {
    var body: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke * 2))
            .frame(height: DS.Border.width / 2)
            .accessibilityHidden(true)
    }
}

/// سطر النتيجة تحت شرائح التصفية: «783 رجل · أبجدياً» (الرقم شبه عريض بحبر النص، الباقي رمادي ١٣)
struct AdminMembersResultLine: View {
    let result: Int?
    let set: AdminFilterSet<AdminMembersFilters>
    let order: String

    var body: some View {
        let number = Text(verbatim: result.map { DSNumber.grouped($0) } ?? AdminStoreHealthText.placeholder)
            .font(DS.Font.role(.sectionTitle))
            .foregroundColor(DS.Color.textPrimary)
        let noun = result.map { " \(set.noun($0))" } ?? ""
        return (number + Text(verbatim: "\(noun) · \(order)"))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

/// عنوان فرع فوق صفوفه (V2-2): شريط أخضر في البداية · «فرع جاسم» ١٧ شبه عريض · العدد في حبّة خضراء خافتة. الأخضر لمسة —
/// لون العائلة (`DS.Color.palm`، يفتح في الداكن)
struct AdminMembersBranchHeader: View {
    let title: String
    let count: Int

    var body: some View {
        let number = DSNumber.grouped(count)
        HStack(alignment: .center, spacing: DS.Spacing.smd) {
            RoundedRectangle(cornerRadius: DS.Hub.stripeWidth / 2, style: .continuous)
                .fill(DS.Color.palm)
                .frame(width: DS.Hub.stripeWidth, height: DS.Hub.familyBranchBar)
            Text(verbatim: title)
                .dsFont(DS.Hub.familyBranchTitle)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: number)
                .dsFont(.sectionTitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.palm)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.smd)
                .frame(minHeight: DS.Hub.familyBranchCount)
                .background(Capsule().fill(DS.Color.palm.opacity(DS.Opacity.tintFill)))
                .fixedSize()
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title)\(L10n.isArabic ? "،" : ",") \(number)"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// صفّ عضو (spec C.6، mock 4): الصورة ٤٠ · الاسم ١٥ متوسط · سطر ١٣ (الحالة الرسمية، أو سبب الظهور في قوائم المراجعة) · ‹.
/// الاسم سطر واحد يصغر ليتّسع بالحجم الافتراضي (طلب المالك ٢٠٢٦-١١-٠٨: ارتفاع ثابت فلا تتعثّر القائمة الكسولة)، وسطران مع
/// الخط الأكبر
struct AdminMemberListRow: View {
    let entry: AdminMembersIndex.Entry
    let subline: String
    /// السطر سبب نقص — بلون التنبيه
    var warns: Bool = false
    /// الضغط على الصورة يكبّرها (بدل فتح ورقة العضو) — nil = الصورة جزء من الصفّ
    var onPhotoTap: ((String) -> Void)? = nil
    /// السهم في الطرف (الصفّ يفتح ورقة العضو) — صفحات «يحتاج مراجعتك» تخفيه وتضع إجراءها مكانه
    var showsStatus: Bool = true
    /// جذر «العائلة» (V2-2): الاسم ١٥ بأول كلمتين شبه عريضتين والباقي عادي رمادي، سطر واحد يُقصّ في آخره (لا يصغر) —
    /// false = شكل الصفّ السابق (قوائم «يحتاج مراجعتك»)
    var boldLead: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var hasPhotoTap: Bool { onPhotoTap != nil && !AdminMemberFacts.isBlank(entry.member.avatarUrl) }

    private var member: FamilyMember { entry.member }

    var body: some View {
        let large = typeSize > .large
        HStack(spacing: DS.Spacing.md) {
            // الرمادي للمتوفى فقط — `grayscale(0)` على كل صفّ كان مرور رسم زائداً أثناء التمرير
            Group {
                if member.isDeceased == true {
                    DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar,
                                   roleColor: DS.Color.slate)
                        .grayscale(1)
                } else {
                    DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar,
                                   roleColor: DS.Color.slate)
                }
            }
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded {
                if let url = member.avatarUrl, !AdminMemberFacts.isBlank(url) { onPhotoTap?(url) }
            }, including: hasPhotoTap ? .all : .none)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                if boldLead {
                    leadName
                        .lineLimit(large ? DSBox.nameLinesLargeText : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: large)
                } else {
                    Text(member.fullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.fullName)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(large ? DSBox.nameLinesLargeText : 1)
                        .minimumScaleFactor(large ? 1 : 0.7)
                        .fixedSize(horizontal: false, vertical: large)
                }
                if !subline.isEmpty {
                    Text(verbatim: subline)
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(warns ? DS.Color.warning.dsReadableGlyph : DS.Color.textSecondary)
                        .lineLimit(large ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: large)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsStatus {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DS.Spacing.smd)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeightTwoLines, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))
    }

    /// «**ابراهيم احمد** ابراهيم حسين حسن…» — نصّ واحد فيُقصّ في آخره كله (`AdminMembersLogic.nameParts`)
    private var leadName: Text {
        let parts = AdminMembersLogic.nameParts(member.fullName)
        guard !parts.lead.isEmpty else {
            return Text(L10n.t("بلا اسم", "No name"))
                .font(DS.Font.role(.body))
                .foregroundColor(DS.Color.textSecondary)
        }
        let lead = Text(verbatim: parts.lead)
            .font(DS.Font.role(.hubSection))
            .foregroundColor(DS.Color.textPrimary)
        guard !parts.rest.isEmpty else { return lead }
        return lead + Text(verbatim: " \(parts.rest)")
            .font(DS.Font.role(.body))
            .foregroundColor(DS.Color.textSecondary)
    }
}

// MARK: - صفّ «هل ما زالوا أحياء؟» (صفحة القائمة — U12)

/// الصورة · الاسم · السبب و«مواليد 1935 · 91 سنة»، وتحتها «متوفى» و«حي ✓» (الرمز SF بعد النص — علامة ✓ النصية تُرسم
/// بخط Plex كأنها «٧») — تحت النص دائماً حتى يبقى الاسم كاملاً. الضغط على الاسم يفتح ورقة العضو
struct AdminLivingCheckRow: View {
    let entry: AdminMembersIndex.Entry
    /// سبب الظهور في القائمة («تحقق: هل ما زال حياً؟» …)
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
        // صفحة القائمة تمرّر السبب نفسه «مواليد …» — لا يتكرّر
        if reason.contains("\(y)") { return reason }
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
                        .dsFont(.subtitle)
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

        let buttons = HStack(spacing: DS.Hub.actingPillGap) {
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
struct AdminLivingDeathBox: ViewModifier {
    @Binding var member: FamilyMember?

    func body(content: Content) -> some View {
        content.dsCenterBox(item: $member) { m in
            AdminMemberDetailSheet(member: m, showsAccount: false, deathOnly: true)
        }
    }
}

/// رابط صورة للعارض المكبّر (`fullScreenCover(item:)`)
struct AdminPhotoURL: Identifiable {
    let url: String
    var id: String { url }
}
