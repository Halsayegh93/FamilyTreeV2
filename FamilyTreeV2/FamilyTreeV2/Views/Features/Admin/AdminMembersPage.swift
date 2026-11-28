import SwiftUI

// MARK: - «العائلة» = صفحة الأعضاء الواحدة (U11، ثم admin v2 اتجاه «أ» — V2-2، ثم F5 «مَن» داخل «تصفية»، ٢٠٢٦-١١-٢٦)
//
// الرأس الكحلي (`AdminMembersHeader.swift`): «‹ الإدارة» · «العائلة ⌄» · «＋» · «⋯» (التقارير PDF · نساء العائلة · شجرة
// النساء) ← سطر ذهبي بما تعرضه القائمة («كل العائلة»، أو «رجال · نساء»، والفرع) ← حقل البحث بالاسم أو الرقم + «تصفية (n)».
// ورقة التصفية (طقم U5، F3 اختيار متعدّد يُطبَّق فوراً، F5): «مَن» (رجال · نساء · خارج العائلة — للمالك والمدير) ←
// «الحساب» ← «الحالة» ← «الفرع» (منتقٍ، اختيار واحد) ← «القائمة» (رابط قديم)، والأعداد تتبع بقية الاختيارات
// (`AdminPeopleLogic` — المنطق الخالص، والأعداد والقائمة من النطاق نفسه). تحت الرأس على الأبيض:
//  ١) شريحة لكل اختيار بـ✕ (`AdminActiveFilterChips` — الافتراضي «رجال» شريحة عادية) وسطر «2,729 رجل · بالفروع» دائماً
//     (العدد الذي كان في مربّعات الرأس).
//  ٢) «يحتاج مراجعتك» مربّعات ثلاثة في كل صف (اختيار المالك «ب» ٢٠٢٦-١١-٢٨، `AdminReviewTiles.swift`) — كل مربّع
//     يفتح قائمته الموجودة؛ ثم عنوان «الأعضاء». (صفحة `AdminReviewHubPage` تبقى لمن يفتحها من رابط.)
//  ٣) القائمة: فئة واحدة = قائمتها؛ أكثر = أقسام «الرجال · N» · «النساء · N» · «خارج العائلة · N». الرجال بلا تصفية ولا
//     بحث بالفروع («▍فرع جاسم (214)»)، وإلا أبجدياً (والبحث بالأقرب) — صفّ العضو يفتح ورقة العضو
//     (`AdminMemberSheet(ids:start:)`، U13) بالسابق والتالي في قسمه. النساء وخارج العائلة بصفّ «نساء العائلة»
//     (`AdminWomenRow`) ويفتحان ما يفتحانه هناك: مربّع المرأة (`WomanDetailSheet`) أو ورقة ابن البنت. «عرض المزيد» كل ٤٠
//     لكل قسم.
// المعاملات القديمة `chip:`/`sub:`/`womenOutside:` تبقى (روابط «اليوم» والإشعارات و`AdminUsageDevicesKit`): كل قيمة فلتر
// أو قائمتها تُدفع فوق الجذر (`AdminMembersLogic.opening`)؛ والهبوط `AdminMembersLanding` (ومنه «مَن») من
// `AdminAreaRouter.take` حين تُفتح بلا معاملات. الصلاحيات كما كانت: التسجيل `canRegisterMembers` (× «يعدّل» في الجدول)،
// التقارير `isAdmin`، النساء وخارج العائلة للمالك والمدير (المراقب: الرجال كما كانوا، و«شجرة النساء» من «⋯»).

/// ورقة العضو مفتوحة على قائمة (السابق/التالي يتنقّلان فيها)
struct AdminMemberSheetContext: Identifiable {
    let id = UUID()
    let ids: [UUID]
    let start: Int
}

/// تصفية «العائلة» (spec C.7، F3، F5) — الحالة الخالصة نفسها التي يفحصها tests/admin-redesign/F5
typealias AdminMembersFilters = AdminPeopleLogic.Filters

extension AdminPeopleLogic.Filters {
    /// «القائمة» من رابط قديم بنوعها
    var subList: AdminMemberSub? { sub.flatMap(AdminMemberSub.init(rawValue:)) }
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

/// ذاكرة النطاقات المحسوبة لكل (نسخة البيانات، الفرع، «القائمة»، البحث) — الورقة والشرائح والملخّص يسألون عنها مراراً في
/// الرسم الواحد. مرجع لا حالة: الكتابة فيه لا تعيد الرسم
final class AdminMembersScopeMemo {
    struct Key: Hashable {
        let version: Int
        let branch: UUID?
        let sub: String?
        let query: String
    }

    private var cache: [Key: AdminPeopleLogic.Scope] = [:]

    func value(_ key: Key, make: () -> AdminPeopleLogic.Scope) -> AdminPeopleLogic.Scope {
        if let hit = cache[key] { return hit }
        if cache.count > 12 { cache.removeAll(keepingCapacity: true) }
        let made = make()
        cache[key] = made
        return made
    }
}

struct AdminMembersPage: View {
    private typealias P = AdminPeopleLogic
    private typealias Population = AdminMembersLanding.Population

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// أبناء البنات — فئة «خارج العائلة» (يُستبعدون من الرجال)
    @ObservedObject private var sons = DaughterSonsIndex.shared
    /// «حي ✓» المحلية لهذا المستخدم (عدد «هل ما زالوا أحياء؟»)
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    /// «ليسا مكرّرين» المحلية لهذا المستخدم (عدد «المكرر والأخطاء»)
    @ObservedObject private var dupDismissed = AdminDuplicateDismissStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adminBackTitle) private var outerBack
    /// عدّاد الانتقال (`.area(.family, hop)`) — مفتاح الهبوط
    @Environment(\.adminAreaHop) private var hop

    // «نساء» و«خارج العائلة» (F5): شجرة النساء وصفوفها — بناء «نساء العائلة» نفسه (`AdminWomenRows`)
    @State private var womenRows: [FamilyMember] = WomenStore.cache
    @State private var womenHealth: AdminStoreHealth = WomenStore.cache.isEmpty ? .idle : .loaded(at: Date())
    @State private var people: [AdminWomenEntry] = []
    @State private var peopleBuilt = false

    // الرأس المطويّ
    @State private var collapsed = false
    @State private var compactLine: CGFloat = DS.Hub.compactBar
    /// زرّ البحث في السطر المطويّ: يمرّر إلى الحقل ثم يضع المؤشر فيه
    @State private var searchToken = 0
    @State private var searchFocus = 0

    // القائمة
    @State private var filters: AdminMembersFilters
    @State private var query = ""
    /// «عرض المزيد» لكل قسم (الغائب = `pageSize`)
    @State private var limits: [Population: Int] = [:]
    @State private var index = AdminMembersIndex.empty
    /// مدخلات آخر بناء للفهرس — نداء بلا تغيير لا يعيد البناء (تغيّر الحسابات يطلق `onChange` اثنين معاً، و«المكرر
    /// والأخطاء» فوق الصفحة يطلق `reload` — Sentry FAMILYTREE-B)
    @State private var builtKey: IndexKey?
    @State private var tree = AdminFamilyTree.empty
    /// صفوف الفلتر: الرجال بمواضع الفهرس، ثم النساء وخارج العائلة بعدها (`people` بإزاحة `index.entries.count`)
    @State private var persons: [AdminPeopleLogic.Person] = []
    @State private var version = 0
    @State private var memo = AdminMembersScopeMemo()
    /// أعداد قوائم «يحتاج مراجعتك» (المفتاح الغائب = لم يصل) — نفس صفحتها (U12)
    @State private var reviewCounts: [AdminReviewHubLogic.List: Int] = [:]
    /// «المكرر والأخطاء»: الأسماء المكررة والأرقام بدون أسماء (`AdminIssuesData` — نفس صفحتها)
    @State private var issues = AdminIssuesData()
    @State private var showFilters = false

    // ما يُفتح
    @State private var sheet: AdminMemberSheetContext?
    /// مربّع المرأة (أو الزوج من خارج العائلة) كما في «نساء العائلة»
    @State private var selectedWoman: FamilyMember?
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
    /// - womenOutside: «العائلة» على {خارج العائلة} (F5)
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

    /// النساء وخارج العائلة («مَن») للمالك والمدير — نفس صفحة «نساء العائلة» (طلب المالك ٢٠٢٦-١١-٠٨)
    private var seesOthers: Bool { authVM.isAdmin }

    // حارس المكدس: الرأس والمحتوى والطبقة المثبّتة خلف `AnyView`
    var body: some View {
        let model = makeModel()
        return ScrollViewReader { proxy in
            AdminHubPage(pinned: collapsed && index.built ? AnyView(compactBar(model).transition(.opacity)) : nil) {
                AdminBandHeader(title: AdminArea.family.title,
                                subtitle: P.caption(filters, seesOthers: seesOthers, branch: filters.branch.map(branchTitle)),
                                badge: authVM.adminCanEdit(.family) ? nil : AdminPageHeader.readOnlyText,
                                bottomPadding: DS.Spacing.md, isAreaRoot: true) {
                    AnyView(headerButtons(model))
                } accessory: {
                    // حارس المكدس: الحقل نوع مستقل خلف `AnyView`
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
        .modifier(AdminWomanDetailCover(woman: $selectedWoman, women: womenRows, me: authVM.currentUser,
                                        canEdit: authVM.canEditMembers && authVM.adminCanEdit(.family),
                                        canDelete: authVM.canDeleteMembers && authVM.adminCanEdit(.family),
                                        canAnnounceDeath: authVM.isAdmin, canModerate: authVM.canModerate,
                                        onChanged: { await loadWomen(force: true) }))
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
        .onChange(of: accounts.outsideSeen) { _ in refreshReviews() }
        .onChange(of: sons.ids) { _ in rebuild() }
        .onChange(of: verified.ids) { _ in refreshReviews() }
        .onChange(of: dupDismissed.signatures) { _ in refreshIssues() }
        .onChange(of: query) { _ in limits = [:] }
        .onChange(of: filters) { _ in limits = [:] }
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
            // مجموعة لا تنطبق على الفئات المفتوح عليها لا تُبقي اختياراً (لا شريحة بلا مجموعة تزيلها)
            var fixed = filters
            P.normalize(&fixed, seesOthers: seesOthers)
            if fixed != filters { filters = fixed }
            if let p = pendingPush {
                pendingPush = nil
                // فوق الجذر بعد ظهوره — الرجوع يعود للجذر
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(AdminMembersPush(p)) }
            }
        }
        verified.activate(user: authVM.currentUser?.id)
        dupDismissed.activate(user: authVM.currentUser?.id, shared: authVM.isAdmin)
        if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        rebuild()
        await sons.refresh()
        await accounts.refresh()
        if seesOthers { await loadWomen(force: false) }
    }

    private func reload(force: Bool) async {
        await memberVM.fetchAllMembers(force: force)
        rebuild()
        await sons.refresh()
        await accounts.refresh(force: force)
        if seesOthers { await loadWomen(force: force) }
    }

    /// شجرة النساء لفئتي «نساء» و«خارج العائلة» — الكاش أولاً، وجلب للقراءة إن لم تُحمَّل
    private func loadWomen(force: Bool) async {
        if !force, !womenRows.isEmpty {
            if !peopleBuilt { refreshPeople() }
            return
        }
        let before = womenHealth
        womenHealth = womenHealth.beginning()
        do {
            let fresh = try await WomenStore.fetch()
            womenRows = fresh
            womenHealth = womenHealth.ending(success: true)
            refreshPeople()
        } catch {
            if Log.isCancellation(error) {
                womenHealth = before
                return
            }
            Log.fetchError("[AdminMembersPage] women tree load failed", error)
            womenHealth = womenHealth.ending(success: false)
        }
    }

    struct IndexKey: Equatable {
        let membersVersion: Int
        let members: Int
        let accountsLoaded: Bool
        let accounts: [UUID: AdminAccountInfo]
        let sons: Set<UUID>
        let branchNames: [String: String]?
    }

    private func rebuild() {
        let key = IndexKey(membersVersion: memberVM.membersVersion, members: memberVM.allMembers.count,
                           accountsLoaded: accounts.loaded, accounts: accounts.accounts, sons: sons.ids,
                           branchNames: appSettingsVM.settings.branchNames)
        guard key != builtKey || memberVM.allMembers.isEmpty else { return }
        builtKey = key
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
        tree = AdminFamilyTree(memberVM.allMembers)
        buildPeople()
        buildPersons()
        version += 1
        refreshReviews()
    }

    /// بعد وصول شجرة النساء: صفوف الفئتين، ثم صفوف الفلتر
    private func refreshPeople() {
        buildPeople()
        buildPersons()
        version += 1
        refreshIssues()
    }

    /// صفوف «نساء» و«خارج العائلة» — بناء صفحة «نساء العائلة» نفسه (أعدادها = أرقامها، T2)
    private func buildPeople() {
        guard seesOthers, !womenRows.isEmpty || womenHealth.hasData else { return }
        let members = memberVM
        people = AdminWomenRows.build(women: womenRows, members: members.allMembers, sons: sons.ids,
                                      member: { members.member(byId: $0) })
        peopleBuilt = true
    }

    /// ما يحتاجه الفلتر من كل صفّ: الرجال (حساب الدخول، المرساة نفسه)، ثم النساء وخارج العائلة (الربط بحساب، مرساة الفرع)
    private func buildPersons() {
        var list = index.entries.map { e in
            P.Person(population: .men, deceased: e.member.isDeceased == true, hasAccount: AdminMembersIndex.hasLogin(e),
                     anchor: e.id)
        }
        if peopleBuilt {
            list += people.map { e in
                P.Person(population: e.fact.outside ? .outside : .women, deceased: e.fact.deceased,
                         hasAccount: e.fact.registered, anchor: e.anchor)
            }
        }
        persons = list
    }

    /// أعداد قوائم «يحتاج مراجعتك» — المصدر الواحد مع صفحتها (`AdminReviewHubCounts`)
    private func refreshReviews() {
        reviewCounts = AdminReviewHubCounts.make(index: index, verified: verified.ids, members: memberVM.allMembers,
                                                 photos: .init(authVM: authVM), outside: Set(accounts.outsideSeen.keys))
        refreshIssues()
    }

    /// أعداد «المكرر والأخطاء» — شجرة النساء حين وصلت (لمن يراها)
    private func refreshIssues() {
        issues = AdminIssuesData.make(members: memberVM.allMembers, women: seesOthers ? womenRows : [],
                                      accounts: accounts, dismissed: dupDismissed.signatures, seesAll: seesOthers)
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

    /// ما تحت العنوان في الكحلي: الحقل و«تصفية». الحقل مرساة زرّ البحث في السطر المطويّ، ومنه يُقاس الطيّ
    private func bandAccessory(_ model: AdminMembersListModel) -> some View {
        AdminMembersFilterBar(query: $query, focusToken: searchFocus, activeCount: model.snapshot.items.count) {
            showFilters = true
        }
        .id(Self.searchAnchor)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(AdminHubScroll.space)).minY } action: { barMoved($0) }
        .padding(.top, DS.Spacing.md)
    }

    private func headerButtons(_ model: AdminMembersListModel) -> some View {
        let canRegister = authVM.canRegisterMembers && authVM.adminCanEdit(.family)
        let admin = authVM.isAdmin
        return AdminMembersHeaderButtons(
            register: canRegister ? { Self.registerPage } : nil,
            // التقارير بالفلاتر والفرع والبحث الحاليين — رجال القائمة نفسها
            reports: admin ? { open(.reports(exportScope(model))) } : nil,
            // «نساء العائلة» و«شجرة النساء» خارج «⋯» (المالك ٢٠٢٦-١١-٢٧ «ابي اشيل منه شجرة النساء و نساء العائلة») —
            // النساء من «تصفية ← مَن ← نساء»، وشجرة النساء من تبويب «الشجرة»
            womenPage: nil,
            womenTree: nil)
    }

    private static var registerPage: AnyView {
        AnyView(AdminRegisterMemberView().adminBackTitle(AdminArea.family.title).adminArea(.family))
    }

    /// التصدير (تقرير الأعضاء = رجال الشجرة): الفلاتر والفرع والبحث على رجال القائمة — بلا شيء، أو بلا «رجال» في القائمة،
    /// = كل العائلة
    private func exportScope(_ model: AdminMembersListModel) -> AdminReportScope? {
        let q = trimmedQuery
        let s = filters
        guard let men = model.sections.first(where: { $0.population == .men }) else { return nil }
        let filtered = !s.accounts.isEmpty || !s.lives.isEmpty || s.branch != nil || s.sub != nil
        guard filtered || !q.isEmpty else { return nil }
        var parts: [String] = []
        parts += AdminMembersLanding.Account.allCases.filter(s.accounts.contains).map { P.title($0) }
        parts += AdminMembersLanding.Life.allCases.filter(s.lives.contains).map { P.title($0) }
        if let sub = s.subList { parts.append(sub.title) }
        if let b = s.branch { parts.append(branchTitle(b)) }
        if !q.isEmpty { parts.append("«\(q)»") }
        return AdminReportScope(ids: Set(men.rows.map { index.entries[$0].id }), title: parts.joined(separator: " · "))
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
            // «العائلة ⌄ · N» = عدد النتيجة الحالية (F5)
            total: model.snapshot.result,
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

    /// الفئات التي وصلت بياناتها — غيرها «—» لا صفر
    private var ready: Set<Population> {
        var out: Set<Population> = []
        if index.built { out.insert(.men) }
        if peopleBuilt { out.formUnion([.women, .outside]) }
        return out
    }

    private func makeModel() -> AdminMembersListModel {
        let s = filters
        let sees = seesOthers
        let searching = !trimmedQuery.isEmpty
        let sections = index.built
            ? P.sections(scope(branch: s.branch, sub: s.sub), persons: persons, s, seesOthers: sees,
                         accountsReady: index.accountsReady)
            : []
        let set = filterSet(current: s)
        return AdminMembersListModel(sections: sections, set: set, snapshot: set.snapshot(s),
                                     order: P.order(s, seesOthers: sees, searching: searching), searching: searching,
                                     showsHeaders: P.showsSections(s.people, seesOthers: sees))
    }

    /// النطاق بعد «القائمة» (للرجال) والبحث والفرع لكل فئة، وعدّها ٢×٢ — من الذاكرة إن حُسب لهذه القيم
    private func scope(branch: UUID?, sub: String?) -> AdminPeopleLogic.Scope {
        let q = trimmedQuery
        let key = AdminMembersScopeMemo.Key(version: version, branch: branch, sub: sub, query: q)
        return memo.value(key) {
            var men = index.rows(.all, .all)
            if let list = sub.flatMap(AdminMemberSub.init(rawValue:)) {
                let members = Set(index.rows(list.homeChip, list))
                men = men.filter { members.contains($0) }
            }
            var candidates = searched(men, q)
            if peopleBuilt {
                let offset = index.entries.count
                candidates += searchedPeople(q).map { $0 + offset }
            }
            return P.scope(persons, candidates: candidates, branch: branch.map { tree.subtree(of: $0) })
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

    /// النساء وخارج العائلة بالبحث نفسه (الاسم فقط — لا أرقام هاتف في شجرة النساء) — مواضع `people`
    private func searchedPeople(_ q: String) -> [Int] {
        guard !q.isEmpty else { return Array(people.indices) }
        guard !NameSearch.isPhoneQuery(q) else { return [] }
        let words = NameSearch.words(q)
        var hits: [(score: Int, row: Int)] = []
        for (i, e) in people.enumerated() {
            if let score = NameSearch.score(queryWords: words, candidateWords: e.words) { hits.append((score, i)) }
        }
        hits.sort { $0.score != $1.score ? $0.score < $1.score : $0.row < $1.row }
        return hits.map(\.row)
    }

    /// العدد لحالة تصفية (يشمل البحث — نفس ما يُرى) — nil قبل وصول ما يلزمه
    private func resultCount(_ s: AdminMembersFilters) -> Int? {
        guard index.built else { return nil }
        return P.count(scope(branch: s.branch, sub: s.sub), s, seesOthers: seesOthers, ready: ready,
                       accountsReady: index.accountsReady)
    }

    /// اسم الفرع في صفّ «الفرع» وشريحته: الاسم المخصّص من «أسماء العوائل والفروع» إن وُجد، وإلا الاسم المختصر لرأسه
    /// (كصفحة تواريخ الوفاة — U12)
    private func branchTitle(_ id: UUID) -> String {
        if let custom = appSettingsVM.branchName(for: id) { return custom }
        let m = tree.byId[id] ?? memberVM.member(byId: id)
        return m.map { $0.shortFullName.isEmpty ? $0.fullName : $0.shortFullName } ?? L10n.t("فرع", "Branch")
    }

    /// ورقة التصفية (spec C.7، mock 5، F3، F5): مَن ← الحساب ← الحالة ← الفرع ← «القائمة» حين جاءت من رابط. عدد كل
    /// خيار = النتيجة لو اختير وحده في مجموعته مع بقية الاختيارات (`AdminPeopleLogic.filterSet`)
    private func filterSet(current: AdminMembersFilters) -> AdminFilterSet<AdminMembersFilters> {
        let members = memberVM.allMembers
        return P.filterSet(current: current, seesOthers: seesOthers, result: { resultCount($0) },
                           branchTitle: { branchTitle($0) },
                           subTitle: { AdminMemberSub(rawValue: $0)?.title ?? $0 },
                           branchPicker: { current, pick in
                               AnyView(BranchPickerSheet(allMembers: members, selectedId: current, allLevels: true,
                                                         onSelect: { pick($0) }))
                           })
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
                // ترتيب المالك ٢٠٢٦-١١-٢٨: «يحتاج مراجعتك» مربّعات ثلاثة في كل صف (اختيار «ب») ثم «الأعضاء». المربّعات
                // تغيب أثناء البحث — النتائج تبقى تحت الحقل مباشرة
                if trimmedQuery.isEmpty {
                    AnyView(AdminReviewTilesSection(counts: reviewTileCounts,
                                                    kinds: AdminReviewTilesLogic.kinds(seesWomen: seesOthers)))
                        .padding(.bottom, DS.Spacing.lg)
                }
                AdminSectionLabel(title: AdminAreaGroup.members.title)
                    .padding(.bottom, DS.Spacing.xsm)
                // العدد دائماً هنا (كان في مربّعات الرأس — F5)، والشرائح فوقه حين تكون
                AnyView(filterStatus(model))
                    .padding(.bottom, DS.Spacing.md)
                AnyView(listSection(model))
                AnyView(footer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: «يحتاج مراجعتك»

    /// أعداد المربّعات — من المصادر نفسها (`AdminReviewHubCounts` لقوائم «يحتاج مراجعتك»، و`AdminIssuesData` للمكرر
    /// والمتزوجات). الغائب = لم يصل («—»)
    private var reviewTileCounts: [AdminReviewTileKind: Int] {
        var out: [AdminReviewTileKind: Int] = [:]
        for kind in AdminReviewTileKind.allCases {
            if let list = kind.hubList {
                out[kind] = reviewCounts[list]
            }
        }
        if index.built {
            out[.issues] = AdminReviewTilesLogic.issuesCount(duplicates: issues.duplicates, nameless: issues.nameless.count)
        }
        if seesOthers && !womenRows.isEmpty {
            out[.married] = issues.marriedNoHusband.count
        }
        return out
    }

    // MARK: التصفية المفعّلة

    /// شرائح التصفية المفعّلة (طقم U5 — كل ✕ تلغي فلترها وحده؛ «رجال» الافتراضية شريحة) ثم «2,729 رجل · بالفروع»
    private func filterStatus(_ model: AdminMembersListModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if !model.snapshot.items.isEmpty {
                AdminActiveFilterChips(set: model.set, selection: $filters, snapshot: model.snapshot)
            }
            AdminMembersResultLine(result: model.snapshot.result, set: model.set, order: model.order.title)
        }
    }

    // MARK: القائمة

    /// قسم ينتظر بياناته: الرجال بفلتر «الحساب» قبل قوائم الحسابات، والنساء وخارج العائلة قبل شجرة النساء
    private func waiting(_ p: Population) -> Bool {
        p == .men ? !filters.accounts.isEmpty && !index.accountsReady : !peopleBuilt
    }

    private func limit(_ p: Population) -> Int { limits[p] ?? Self.pageSize }

    @ViewBuilder
    private func listSection(_ model: AdminMembersListModel) -> some View {
        let shown = model.sections.filter { !$0.rows.isEmpty || waiting($0.population) }
        if shown.isEmpty {
            if model.searching {
                AdminPageStateCard(.empty(L10n.t("لا أحد بهذا الاسم أو الرقم", "Nobody with this name or number"),
                                          actionTitle: L10n.t("مسح البحث", "Clear search"), action: { query = "" }))
            } else if !model.snapshot.items.isEmpty {
                AdminFilterEmptyCard(title: AdminMembersText.noResults, editFilters: { showFilters = true })
            } else {
                AdminPageStateCard(.empty(L10n.t("لا أحد هنا الآن", "Nobody here right now")))
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.population) { n, section in
                    if model.showsHeaders {
                        AdminMembersPopulationHeader(population: section.population,
                                                     count: waiting(section.population) ? nil : section.rows.count)
                            .padding(.top, n == 0 ? 0 : DS.Spacing.xxl)
                            .padding(.bottom, DS.Spacing.xs)
                    }
                    AnyView(sectionBody(section, order: model.order))
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: AdminPeopleLogic.Section, order: AdminMembersLogic.Order) -> some View {
        switch section.population {
        case .men:
            if waiting(.men) {
                // «لهم حساب/بلا حساب» قبل وصول قوائم الحسابات: لا قائمة فارغة مضلِّلة
                if accounts.health.look == .unknown {
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الحسابات", "Couldn't load the accounts"),
                                              message: L10n.t("تصفية «الحساب» تحتاجها", "The «Account» filter needs them"),
                                              retry: { Task { await accounts.refresh(force: true) } }))
                } else {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الحسابات…", "Loading accounts…"), rows: 4))
                }
            } else if order == .branches {
                AnyView(groupedList(section.rows))
            } else {
                AnyView(flatList(section.rows))
            }
        case .women, .outside:
            if !peopleBuilt {
                if womenHealth.canRetry {
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل شجرة النساء", "Couldn't load the women's tree"),
                                              message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                              retry: { Task { await loadWomen(force: true) } }))
                } else {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل شجرة النساء…", "Loading the women's tree…"), rows: 4))
                }
            } else {
                AnyView(peopleList(section.rows, population: section.population))
            }
        }
    }

    /// أبجدياً (أو بالأقرب للبحث): صفوف مسطّحة بخط رفيع يبدأ من النص (mock 4)
    private func flatList(_ rows: [Int]) -> some View {
        let ids = rows.map { index.entries[$0].id }
        let visible = Array(rows.prefix(limit(.men)))
        return VStack(alignment: .leading, spacing: 0) {
            AdminMembersListTopRule()
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element) { pos, i in
                    row(i, ids: ids, position: pos, divider: pos > 0)
                }
            }
            moreButton(total: rows.count, population: .men)
        }
    }

    /// بالفروع («فرع جاسم · 214»، `BranchPickerSheet.familyRoot` والأسماء المخصّصة) — «عرض المزيد» يمرّ على الفروع بالترتيب.
    /// بلا تصفية ولا بحث فقط: صفوف القسم = كل الرجال
    private func groupedList(_ rows: [Int]) -> some View {
        let groups = index.branches
        let ids = groups.flatMap { $0.rows.map { index.entries[$0].id } }
        var sections: [(branch: AdminMembersIndex.Branch, shown: [Int], offset: Int)] = []
        var offset = 0
        var budget = limit(.men)
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
            moreButton(total: ids.count, population: .men)
        }
    }

    /// النساء أو خارج العائلة: صفّ «نساء العائلة» نفسه (`AdminWomenRow`)، ويفتح ما يفتحه هناك
    private func peopleList(_ rows: [Int], population: Population) -> some View {
        let offset = index.entries.count
        let valid = rows.filter { people.indices.contains($0 - offset) }
        let sonIds = valid.compactMap { i -> UUID? in
            if case .son(let m) = people[i - offset].kind { return m.id } else { return nil }
        }
        let visible = Array(valid.prefix(limit(population)))
        return VStack(alignment: .leading, spacing: 0) {
            AdminMembersListTopRule()
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element) { pos, i in
                    let entry = people[i - offset]
                    Button { openPerson(entry, sonIds: sonIds) } label: { AdminWomenRow(entry: entry) }
                        .buttonStyle(AdminRowPressStyle(bleed: DS.Spacing.lg))
                        .overlay(alignment: .top) {
                            if pos > 0 { AdminRowDivider(inset: DS.Icon.avatar + DS.Spacing.md) }
                        }
                }
            }
            moreButton(total: valid.count, population: population)
        }
    }

    /// كما في «نساء العائلة»: المرأة والزوج من خارج العائلة ← مربّع شجرة النساء، وابن البنت ← ورقة حسابه بين أبناء القسم
    private func openPerson(_ e: AdminWomenEntry, sonIds: [UUID]) {
        switch e.kind {
        case .woman(let m), .outsideHusband(let m):
            selectedWoman = m
        case .son(let m):
            sheet = AdminMemberSheetContext(ids: sonIds, start: sonIds.firstIndex(of: m.id) ?? 0)
        }
    }

    @ViewBuilder
    private func moreButton(total: Int, population: Population) -> some View {
        let shown = limit(population)
        if total > shown {
            AdminPillButton(title: L10n.t("عرض المزيد (\(DSNumber.grouped(total - shown)))",
                                          "Show more (\(DSNumber.grouped(total - shown)))"),
                            icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                limits[population] = shown + Self.pageSize
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
    /// الأقسام بترتيبها («الرجال» · «النساء» · «خارج العائلة») وصفوف كلٍّ (مواضع `persons`) — فئة واحدة = قسم واحد
    let sections: [AdminPeopleLogic.Section]
    let set: AdminFilterSet<AdminMembersFilters>
    let snapshot: AdminFilterSnapshot<AdminMembersFilters>
    let order: AdminMembersLogic.Order
    let searching: Bool
    /// أكثر من فئة: عنوان لكل قسم
    let showsHeaders: Bool
}

/// مربّع المرأة (أو الزوج من خارج العائلة) — نفسه في «نساء العائلة» بصلاحياته (في نوعه المستقل — حارس المكدس)
struct AdminWomanDetailCover: ViewModifier {
    @Binding var woman: FamilyMember?
    let women: [FamilyMember]
    let me: FamilyMember?
    let canEdit: Bool
    let canDelete: Bool
    let canAnnounceDeath: Bool
    let canModerate: Bool
    let onChanged: () async -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $woman) { w in
                AnyView(WomanDetailSheet(
                    woman: w,
                    allWomen: women,
                    me: me,
                    canEdit: canEdit,
                    canDelete: canDelete,
                    canAnnounceDeath: canAnnounceDeath,
                    canModerate: canModerate,
                    onChanged: onChanged,
                    onOpenMember: { id in
                        woman = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { woman = women.first { $0.id == id } }
                    }
                )
                .background(ClearPresentationBackground()))
            }
            .transaction { t in if woman != nil { t.disablesAnimations = true } }
    }
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

/// عنوان قسم فئة (F5) فوق صفوفها حين تُختار أكثر من فئة: مربّع رمز بلون سلسلتها في «اليوم» (`DS.Chart.men/women/outside`
/// — اللون نفسه بجانب الاسم نفسه في الحلقات) · «الرجال» ١٧ شبه عريض · العدد رمادياً («—» قبل وصول بياناته). فوق عناوين
/// الفروع داخل «الرجال»، فشكله غير شكلها (مربّع الرمز لا الشريط الأخضر، والعدد بلا كبسولة)
struct AdminMembersPopulationHeader: View {
    let population: AdminMembersLanding.Population
    /// nil = لم تصل بيانات الفئة
    let count: Int?

    private var symbol: String {
        switch population {
        case .men:     return "figure.stand"
        case .women:   return "figure.stand.dress"
        case .outside: return "person.2.fill"
        }
    }

    private var tint: Color {
        switch population {
        case .men:     return DS.Chart.men
        case .women:   return DS.Chart.women
        case .outside: return DS.Chart.outside
        }
    }

    var body: some View {
        let title = AdminPeopleLogic.sectionTitle(population)
        let number = count.map { DSNumber.grouped($0) } ?? AdminStoreHealthText.placeholder
        HStack(alignment: .center, spacing: DS.Spacing.smd) {
            AdminIconSquare(symbol: symbol, tint: tint, glyph: DS.Glyph.lg)
            Text(verbatim: title)
                .dsFont(DS.Hub.familyBranchTitle)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: number)
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title)\(L10n.isArabic ? "،" : ",") \(count == nil ? AdminStoreHealthText.loading : number)"))
        .accessibilityAddTraits(.isHeader)
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
