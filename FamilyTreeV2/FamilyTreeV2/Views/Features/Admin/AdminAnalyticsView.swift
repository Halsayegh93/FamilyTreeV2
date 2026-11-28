import SwiftUI
import Combine

// MARK: - «الإحصاءات» = «إحصاءات العائلة» (اتجاه المالك «أ»؛ إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.12، الوحدة U15)
//
// صفحة واحدة تتمرّر بعناوين صغيرة، رقم الصفحة في كل قسم جملة تبدأ به، والرسم تحته (Yr، Nuxt Dashboard، Tide Guide):
//  ١ «العائلة» — حُذفت ٢٠٢٦-١١-٢٨ (تكرّر رأس «اليوم»؛ تبقى مكان خطأ جلب الأعضاء وحده، والهبوط عليها = أول الصفحة). كانت: بطاقة حلقات U6 (`AdminCensusRings`، `rows: .livingAndDeceased`): الإجمالي (بيته هنا، بلا سهم) · الرجال ‹ ·
//    النساء ‹، ثم «أحياء» و«متوفون» بلا سهم (رجال ونساء مختلطون).
//  ٢ «الراحلون» — متوسط العمر عند الوفاة وأطول عمر (من الرجال ونساء العائلة الذين لهم تاريخا ميلاد ووفاة؛ «—» و«لا تواريخ
//    كافية» بلا بيانات) · «بلا تاريخ وفاة كامل» = عدد صفحة «تواريخ الوفاة» ‹ (لمن يعدّل الأعضاء).
//  ٣ «في التطبيق» — «170 لهم حساب» (= «في التطبيق» في «اليوم»، `setFamilyAccounts`) + شريط ٧٪ + رجال ‹ · نساء ‹ · بلا حساب.
//  ٤ «جديد في الشجرة» — «121 أُضيفوا» + أعمدة ٦ أشهر، و«أغلبه استيراد دفعة واحدة» حين يكون الشهر الشاذّ يوماً واحداً.
//  ٥ «الأعمار» — «نعرف عمر 185 فقط» + شريط المعروف + أشرطة الفئات + «أكمل البيانات الناقصة» ‹ (عدد قائمة «بيانات ناقصة»).
//  ٦ «الأدوار» — مالك · مدير · عضو · مراقب ومشرف (الرجال الأحياء) + «فريق الإدارة» ‹ (بابه، لمن يرى «الفريق والأمان»).
//  ٧ «الشجرة» — رقمان في بطاقة واحدة.  ٨ «خارج العائلة» — «50 حياً من خارج العائلة» ‹ + أجزاؤه — الأحياء وحدهم (طلب المالك، F1) (بمساعد U6).
//  ٩ «الموافقات» (AdminInsightsReport.swift) ثم «آخر تحديث 9:41».
// كل رقم بسهم يفتح قائمة أول عدد فيها يساويه (T2، `AdminStatsLogic.destination` في AdminInsightsArea.swift) — تُدفع فوق الصفحة
// والرجوع يعود إليها. الحالات لكل قسم: هيكل قبل الوصول، خطأ بإعادة المحاولة مكانه، والأرقام القديمة بوقتها.
// حارس المكدس: الصفحة والأقسام طبقات خلف `AnyView`، والوجهات خلف `AdminLazyPage`.

struct AdminAnalyticsView: View {
    /// قسم يُفتح عليه — يغلب هبوط «اليوم» المخزَّن (`AdminAreaRouter.take(.stats, hop:)`)
    private let anchor: AdminStatsAnchor?
    /// جذر القسم: العنوان قائمة الأقسام والرجوع «الإدارة» — وإلا صفحة مدفوعة برجوع إلى ما فتحها
    private let isAreaRoot: Bool

    init(anchor: AdminStatsAnchor? = nil, isAreaRoot: Bool = false) {
        self.anchor = anchor
        self.isAreaRoot = isAreaRoot
    }

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @ObservedObject private var sons = DaughterSonsIndex.shared
    @StateObject private var approvals = AdminInsightsApprovalsStore()
    @Environment(\.adminAreaHop) private var hop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// كل أرقام الصفحة — تُحسب مرة لكل تغيّر في البيانات، لا مع كل رسم
    @State private var snapshot = AdminStatsSnapshot()
    /// شجرة النساء (الكاش فوراً ثم الجلب) وحالها
    @State private var women: [FamilyMember] = WomenStore.cache
    @State private var womenHealth: AdminStoreHealth = WomenStore.cache.isEmpty ? .idle : .loaded(at: Date())
    /// قوائم الحسابات (`AdminAccountsStore`) وحالها
    @State private var accountsHealth: AdminStoreHealth = AdminAccountsStore.shared.loaded ? .loaded(at: Date()) : .idle
    /// جلب الأعضاء من هذه الصفحة (`AdminTodayLogic.membersFetchEnded`): علامة الفشل في نموذج الأعضاء تبقى من جلب سابق
    /// حتى ينجح جلب، فلا تُقرأ وحدها أثناء «أعد المحاولة» (F2، كما في «اليوم» F1)
    @State private var membersFetch: AdminStoreHealth = .idle
    /// مفتاح مسار الموافقات قُرئ طازجاً (قبله لا تُعرض «لا إحصاءات» لمن له «الموافقات» وحدها)
    @State private var flagReady = false
    @State private var updatedAt: Date?
    @State private var started = false
    /// الهبوط ينتظر وصول الأرقام، ثم تُمرَّر الصفحة إليه
    @State private var pendingAnchor: AdminStatsAnchor?
    @State private var scrollTarget: AdminStatsAnchor?
    @State private var pushed: AdminStatsPushedPage?
    @State private var isPushed = false

    // MARK: الظهور

    private var access: AdminStatsLogic.Access {
        .make(familyItem: authVM.adminSees(.metricsFamily), approvalsItem: authVM.adminSees(.metricsApprovals),
              workflowOn: adminRequestVM.approvalsWorkflowOn)
    }

    private var viewer: AdminStatsLogic.Viewer {
        let family = AdminArea.family.isVisible(for: authVM)
        return AdminStatsLogic.Viewer(family: family, womenPage: family && authVM.isAdmin, editMembers: authVM.canEditMembers)
    }

    /// الأعضاء: وصلوا = كلمة؛ وإلا حال جلب هذه الصفحة — هيكل أثناء التحميل، و«تعذّر التحميل» بعد أن ينتهي بفشل فقط (F2)
    private var membersHealth: AdminStoreHealth {
        AdminTodayLogic.membersHealth(hasMembers: !memberVM.allMembers.isEmpty, loadedAt: updatedAt ?? Date(),
                                      fetch: membersFetch)
    }

    /// «الاستخدام» — خانة `team.usage` كما كانت في «الفريق والأمان» (المالك والمدير)
    private var seesUsage: Bool { authVM.adminSees(.teamUsage) }

    private var shown: [AdminStatsAnchor] {
        AdminStatsLogic.sections(access, membersFailed: membersHealth == .failed(lastGood: nil))
    }

    // MARK: الصفحة

    // حارس المكدس: الصفحة طبقة خلف `AnyView`
    var body: some View {
        AnyView(page)
            .debugStackProbe(isAreaRoot ? "AdminMetricsAreaView" : "AdminAnalyticsView")
    }

    private var page: some View {
        ScrollViewReader { proxy in
            AdminHubPage {
                AdminBandHeader(backTitle: isAreaRoot ? AdminArea.homeTitle : L10n.t("رجوع", "Back"),
                                title: AdminArea.metrics.title, subtitle: AdminStatsText.subtitle(access),
                                isAreaRoot: isAreaRoot)
            } content: {
                // «الاستخدام» (`team.usage`) لمن لا يرى أقسام العائلة — أول الصفحة (وإلا تحت «في التطبيق»)
                if seesUsage && !shown.contains(.inApp) {
                    AnyView(AdminUsageSection())
                }
                ForEach(shown, id: \.self) { anchor in
                    if AdminStatsLogic.startsDetails(anchor, in: shown) {
                        AnyView(AdminGroupHeader(title: AdminAreaGroup.details.title))
                    }
                    section(anchor).id(anchor)
                    // «الاستخدام» في «في التطبيق» (انتقل من «الفريق والأمان» ٢٠٢٦-١١-٢٨ — بخانته نفسها)
                    if anchor == .inApp && seesUsage {
                        AnyView(AdminUsageSection())
                    }
                }
                if shown.isEmpty && !seesUsage {
                    emptyState
                } else if let updatedAt {
                    AdminStatsFooter(date: updatedAt)
                }
            }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                scrollTarget = nil
                if reduceMotion {
                    proxy.scrollTo(target, anchor: .top)
                } else {
                    withAnimation(DS.Anim.smooth) { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .navigationDestination(isPresented: $isPushed) { pushedPage }
        .refreshable { await load(force: true) }
        .task {
            guard !started else {
                // جلب أعضاء أُلغي قبل انتهائه (`membersFetch` رجع هيكلاً): الظهور التالي يعيده (F2)
                if memberVM.allMembers.isEmpty && membersFetch == .idle { await load(force: false) }
                return
            }
            started = true
            // الهبوط مرة واحدة — الصريح يغلب المخزَّن؛ «الموافقات» تُقبل قبل قراءة مفتاح المسار
            let possible = AdminStatsLogic.sections(.make(familyItem: authVM.adminSees(.metricsFamily),
                                                          approvalsItem: authVM.adminSees(.metricsApprovals),
                                                          workflowOn: true))
            pendingAnchor = AdminStatsLogic.scrollTarget(explicit: anchor, stored: AdminAreaRouter.take(.stats, hop: hop),
                                                         shown: possible)
            rebuild()
            await load(force: false)
        }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: accounts.accounts.count) { _ in rebuild() }
        .onReceive(sons.$ids.dropFirst()) { _ in rebuild() }
    }

    /// قسم واحد بعنوانه — كلٌّ طبقة خلف `AnyView`
    private func section(_ anchor: AdminStatsAnchor) -> AnyView {
        let s = snapshot
        switch anchor {
        case .family:
            return AnyView(AdminStatsSection(anchor: .family) {
                AdminCensusRings(figures: s.figures, rows: .livingAndDeceased,
                                 health: AdminStoreHealth.combined([membersHealth, womenHealth]), actions: ringActions)
            })
        case .approvals:
            return AnyView(AdminInsightsApprovalsCard(store: approvals, openReport: {
                push(.metrics) { AnyView(ApprovalsReportView()) }
            }))
        default:
            guard s.built else { return AnyView(AdminStatsLoadingSection(anchor: anchor)) }
            return memberSection(anchor, s)
        }
    }

    private func memberSection(_ anchor: AdminStatsAnchor, _ s: AdminStatsSnapshot) -> AnyView {
        switch anchor {
        case .departed:
            return AnyView(AdminStatsDepartedSection(lifespans: s.lifespans, deathDates: s.deathDates,
                                                     tap: tap(.deathIncomplete, value: s.deathDates.incomplete)))
        case .inApp:
            return AnyView(AdminStatsInAppSection(
                figures: s.figures, health: AdminStoreHealth.combined([membersHealth, womenHealth, accountsHealth]),
                menTap: tap(.menAccounts, value: s.figures.menAccounts),
                womenTap: tap(.womenAccounts, value: s.figures.womenAccounts),
                retry: { Task { await reloadAccountsAndWomen() } }))
        case .growth:
            return AnyView(AdminStatsGrowthSection(growth: s.growth))
        case .ages:
            return AnyView(AdminStatsAgesSection(livingMen: s.livingMen, known: s.knownAges, bands: s.bands,
                                                 missingData: s.missingData, noBirth: s.noBirth,
                                                 gapsTap: tap(.missingData, value: s.missingData)))
        case .roles:
            return AnyView(AdminStatsRolesSection(roles: s.roles, teamTap: teamTap))
        case .tree:
            return AnyView(AdminStatsTreeSection(fathers: s.fathers, largestFamily: s.largestFamily))
        case .outside:
            return AnyView(AdminStatsOutsideSection(
                figures: s.figures, outsideWomen: s.outsideWomen, husbands: s.husbands, daughtersSons: s.daughtersSons,
                health: AdminStoreHealth.combined([membersHealth, womenHealth]),
                livingTap: tap(.outsideLiving, value: s.figures.outsideLiving),
                retry: { Task { await reloadAccountsAndWomen() } }))
        case .family, .approvals:
            return AnyView(EmptyView())
        }
    }

    /// لا «العائلة» ولا «الموافقات» لهذا الدور (أو «الموافقات» والمسار مطفأ) — بطاقة تقول لماذا، لا صفحة بيضاء
    @ViewBuilder
    private var emptyState: some View {
        let reason = AdminStatsLogic.empty(familyItem: authVM.adminSees(.metricsFamily),
                                           approvalsItem: authVM.adminSees(.metricsApprovals),
                                           workflowOn: adminRequestVM.approvalsWorkflowOn)
        if reason == .workflowOff && !flagReady {
            AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…"), rows: 2))
        } else if reason == .workflowOff {
            AdminPageStateCard(.empty(L10n.t("مسار الموافقات مطفأ", "The approvals workflow is off"),
                                      message: L10n.t("تظهر أرقام الموافقات هنا حين يُفعَّل المسار",
                                                      "Approval numbers appear here once the workflow is on")))
        } else {
            AdminPageStateCard(.empty(L10n.t("لا إحصاءات لدورك هنا", "No statistics for your role here"),
                                      message: L10n.t("يضيفها المالك لدورك من «صلاحيات الأدوار»",
                                                      "The owner can add them to your role in Role permissions")))
        }
    }

    // MARK: الضغطات (T2)

    private var ringActions: AdminCensusRingsActions {
        AdminCensusRingsActions(total: nil, men: action(.ringMen), women: action(.ringWomen),
                                estimate: action(.estimate), retry: { Task { await load(force: true) } })
    }

    private func action(_ number: AdminStatsLogic.Number) -> (() -> Void)? {
        let destination = AdminStatsLogic.destination(number, viewer: viewer)
        return destination == .none ? nil : { open(destination) }
    }

    /// الرقم يفتح قائمته حين له وجهة ووصل وليس صفراً — وإلا بلا سهم
    private func tap(_ number: AdminStatsLogic.Number, value: Int?) -> AdminPageTap {
        guard AdminStatsLogic.opens(number, value: value, viewer: viewer) else { return .none }
        let destination = AdminStatsLogic.destination(number, viewer: viewer)
        return .action { open(destination) }
    }

    /// «فريق الإدارة» — باب بلا رقم لمن يرى «الفريق والأمان» (المالك يعدّل، المدير يطّلع)
    private var teamTap: AdminPageTap {
        guard AdminArea.team.isVisible(for: authVM) else { return .none }
        return .action { push(.team) { AnyView(AdminModeratorsView()) } }
    }

    private func open(_ destination: AdminStatsLogic.Destination) {
        switch destination {
        case .none:
            return
        case .members(let landing) where landing.population != nil:
            // F5: الحلقات و«خارج العائلة» تفتح «العائلة» على فئتها («مَن») — الهبوط الصريح يحملها كاملة
            push(.family) { AnyView(AdminMembersPage(landing: landing)) }
        case .members(let landing):
            let chip = Self.chip(for: landing)
            push(.family) { AnyView(AdminMembersPage(chip: chip)) }
        case .women(let landing):
            push(.family) { AnyView(AdminWomenPanel(landing: landing)) }
        case .womenTree:
            // تبويب الشجرة على شجرة النساء (نفس «اليوم» وورقة العضو)
            TreeTabContainer.openWomenOnAppear = true
            NotificationCenter.default.post(name: .openWomenTree, object: nil)
        case .deathDates:
            push(.family) { AnyView(DeathDatesCampaignPage()) }
        case .missingData:
            push(.family) { AnyView(AdminReviewListPage(review: .gaps, branchSet: nil)) }
        }
    }

    /// هبوط «العائلة» ← شريحة `AdminMembersPage` (معاملها الصريح): «لهم حساب + الأحياء» = مسجّلون، والمراجعة قائمتها
    private static func chip(for landing: AdminMembersLanding) -> AdminMemberChip {
        switch landing.review {
        case .living?:   return .verifyLiving
        case .gaps?:     return .gaps
        case .problems?: return .problems
        default:         break
        }
        switch (landing.account ?? .all, landing.life ?? .all) {
        case (.with, .alive):    return .registered
        case (.without, .alive): return .treeOnly
        case (.all, .deceased):  return .deceased
        default:                 return .all
        }
    }

    private func push(_ area: AdminArea, _ make: @escaping () -> AnyView) {
        pushed = AdminStatsPushedPage(area: area, make: make)
        isPushed = true
    }

    /// الوجهة ترجع باسم هذه الصفحة وتتبع قسمها
    private var pushedPage: AnyView {
        guard let pushed else { return AnyView(EmptyView()) }
        return AnyView(AdminLazyPage(make: pushed.make)
            .adminBackTitle(AdminArea.metrics.title)
            .adminArea(pushed.area))
    }

    // MARK: التحميل

    private func load(force: Bool) async {
        if memberVM.allMembers.isEmpty || force {
            membersFetch = membersFetch.beginning()
            await memberVM.fetchAllMembers(force: force)
            membersFetch = AdminTodayLogic.membersFetchEnded(hasMembers: !memberVM.allMembers.isEmpty,
                                                             loadFailed: memberVM.membersLoadFailed && !Task.isCancelled)
        }
        rebuild()
        async let womenDone: Void = loadWomen(force: force)
        async let sonsDone: Void = sons.refresh(force: force)
        async let accountsDone: Void = loadAccounts(force: force)
        async let flagDone: Void = adminRequestVM.refreshApprovalsFlag()
        _ = await (womenDone, sonsDone, accountsDone, flagDone)
        flagReady = true
        rebuild()
        updatedAt = Date()
        if access.approvals { await approvals.load() }
    }

    private func reloadAccountsAndWomen() async {
        async let womenDone: Void = loadWomen(force: true)
        async let accountsDone: Void = loadAccounts(force: true)
        _ = await (womenDone, accountsDone)
        rebuild()
    }

    /// شجرة النساء: الكاش يكفي حتى «سحب للتحديث». `-tmpFailStores census` يُفشلها (الحلقات و«خارج العائلة»)
    private func loadWomen(force: Bool) async {
        if DebugAdminProbe.shouldFail(.census, hasLoaded: womenHealth.hasData) {
            womenHealth = womenHealth.ending(success: false)
            return
        }
        if !force && womenHealth.hasData && !women.isEmpty { return }
        womenHealth = womenHealth.beginning()
        do {
            women = try await WomenStore.fetch()
            womenHealth = womenHealth.ending(success: true)
        } catch {
            guard !ErrorHelper.isCancellation(error) else {
                if womenHealth == .loading { womenHealth = .idle }
                return
            }
            Log.warning("[Stats] تعذّر جلب شجرة النساء: \(error)")
            womenHealth = womenHealth.ending(success: false)
        }
    }

    /// قوائم الحسابات (`AdminAccountsStore`، مهلة ٦٠ ث بين جلبين). `-tmpFailStores accounts` يُفشلها («في التطبيق»)
    private func loadAccounts(force: Bool) async {
        accountsHealth = accountsHealth.beginning()
        if DebugAdminProbe.shouldFail(.accounts, hasLoaded: accounts.loaded) {
            accountsHealth = .failed(lastGood: accountsHealth.lastGood)
            return
        }
        await accounts.refresh(force: force)
        accountsHealth = accountsHealth.ending(success: accounts.loaded)
    }

    private func rebuild() {
        snapshot = AdminStatsSnapshot.make(members: memberVM.allMembers, women: women)
        guard snapshot.built, let target = pendingAnchor else { return }
        pendingAnchor = nil
        // بعد رسم الأقسام بأرقامها — وإلا تقفز الصفحة تحت القسم
        DispatchQueue.main.async { scrollTarget = target }
    }
}

/// صفحة تُدفع فوق «الإحصاءات» وقسمها
private struct AdminStatsPushedPage {
    let area: AdminArea
    let make: () -> AnyView
}

// MARK: - الأرقام

/// أعداد الأدوار بين الرجال الأحياء
struct AdminStatsRoles: Equatable {
    var owners = 0
    var admins = 0
    var monitors = 0
    var supervisors = 0
    var members = 0
}

/// كل أرقام الصفحة من البيانات المحمّلة — بتعريفات «العائلة» الواحدة: الرجال = رجال الشجرة بلا طلبات الانضمام ولا حسابات
/// النساء ولا أبناء البنات (`AdminMemberCounts.setMen`)، ونساء العائلة بلا «خارج العائلة»
struct AdminStatsSnapshot {
    /// وصل الأعضاء
    var built = false
    var figures = AdminCensusFigures()
    var lifespans = AdminStatsLogic.Lifespans()
    /// نفس أرقام صفحة «تواريخ الوفاة» (`DeathDatesCampaign.stats`)
    var deathDates = DeathDatesStats()
    var growth = AdminStatsLogic.Growth(months: [], spike: nil)
    var livingMen = 0
    var knownAges = 0
    var bands: [Int] = []
    /// عدد قائمة «بيانات ناقصة» كاملة ومنهم بلا تاريخ ميلاد (`AdminMembersIndex` — نفس فهرس القائمة)
    var missingData: Int? = nil
    var noBirth: Int? = nil
    var roles = AdminStatsRoles()
    var fathers = 0
    var largestFamily = 0
    /// أجزاء «خارج العائلة» الأحياء — nil قبل وصول شجرة النساء
    var outsideWomen: Int? = nil
    var husbands: Int? = nil
    var daughtersSons: Int? = nil

    @MainActor
    static func make(members all: [FamilyMember], women: [FamilyMember], now: Date = Date()) -> AdminStatsSnapshot {
        var s = AdminStatsSnapshot()
        guard !all.isEmpty else { return s }
        s.built = true
        let census = AdminFamilyCensus.make(members: all, women: women)
        s.figures = AdminCensusFigures.make(census: census, members: all, women: women)

        let sons = DaughterSonsIndex.shared.ids
        let review = AppConfigValues.shared.reviewAccountIds
        let outside = WomenStore.outsideFamilyIds
        let men = all.filter { $0.role != .pending && $0.hasName && !$0.isWomanAccount && !sons.contains($0.id) }
        let livingMen = men.filter { $0.isDeceased != true }
        let familyWomen = women.filter { $0.isFemale && $0.hasName && !outside.contains($0.id) }

        // الراحلون: رجال الشجرة ونساء العائلة
        let departed = men.filter { $0.isDeceased == true } + familyWomen.filter { $0.isDeceased == true }
        s.lifespans = AdminStatsLogic.lifespans(departed.compactMap {
            AdminStatsLogic.lifespan(birth: $0.birthDate, death: $0.deathDate)
        })
        s.deathDates = DeathDatesCampaign.stats(all)

        // جديد في الشجرة: أعضاء الشجرة المسمَّون بتاريخ إضافتهم
        // اليوم ويوم الإضافة بتوقيت الكويت (لا غرينتش ولا منطقة الجهاز)
        let today = AdminStatsLogic.kuwaitToday(now)
        s.growth = AdminStatsLogic.growth(created: all.filter { $0.hasName && $0.role != .pending }
                                                      .compactMap { AdminStatsLogic.kuwaitDay($0.createdAt) },
                                          today: today)

        // الأعمار: الرجال الأحياء
        let ages = livingMen.compactMap { m in AdminStatsLogic.day(m.birthDate).flatMap { AdminStatsLogic.years(from: $0, to: today) } }
        s.livingMen = livingMen.count
        s.knownAges = ages.count
        s.bands = AdminStatsLogic.bands(ages)
        let accounts = AdminAccountsStore.shared
        let index = AdminMembersIndex.build(members: all, accounts: accounts.accounts, accountsReady: accounts.loaded,
                                            daughterSons: sons, branchName: { _ in nil })
        s.missingData = index.rows(.gaps, .all).count
        s.noBirth = index.rows(.gaps, .noBirth).count

        // الأدوار: الرجال الأحياء
        for m in livingMen {
            switch m.role {
            case .owner:      s.roles.owners += 1
            case .admin:      s.roles.admins += 1
            case .monitor:    s.roles.monitors += 1
            case .supervisor: s.roles.supervisors += 1
            case .member:     s.roles.members += 1
            case .pending:    break
            }
        }

        // الشجرة: الآباء وأبناؤهم من رجال الشجرة
        var sonsByFather: [UUID: Int] = [:]
        for m in men { if let f = m.fatherId { sonsByFather[f, default: 0] += 1 } }
        s.fathers = sonsByFather.count
        s.largestFamily = sonsByFather.values.max() ?? 0

        // خارج العائلة (الأحياء) — بقاعدة `AdminFamilyCensus.make` نفسها، فمجموعها = «50»
        if !women.isEmpty {
            let rows = women.filter { outside.contains($0.id) && $0.hasName && $0.isDeceased != true }
            s.outsideWomen = rows.filter(\.isFemale).count
            s.husbands = rows.filter { !$0.isFemale }.count
            s.daughtersSons = all.filter {
                sons.contains($0.id) && $0.hasName && !review.contains($0.id) && $0.isDeceased != true
            }.count
        }
        return s
    }
}

// MARK: - الأقسام

/// قسم ينتظر الأعضاء: هيكل بشكل صفوفه (spec A.12)
private struct AdminStatsLoadingSection: View {
    let anchor: AdminStatsAnchor

    var body: some View {
        AdminStatsSection(anchor: anchor) {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأرقام…", "Loading the numbers…"), rows: 2))
        }
    }
}

/// «الراحلون»: متوسط العمر عند الوفاة · أطول عمر · «بلا تاريخ وفاة كامل» ‹
private struct AdminStatsDepartedSection: View {
    let lifespans: AdminStatsLogic.Lifespans
    let deathDates: DeathDatesStats
    let tap: AdminPageTap

    var body: some View {
        let incomplete = deathDates.incomplete
        AdminStatsSection(anchor: .departed) {
            AdminStatsCard {
                AdminStatsRow(title: L10n.t("متوسط العمر عند الوفاة", "Average age at death"),
                              subtitle: lifespans.count > 0 ? AdminStatsText.lifespanBase(lifespans.count)
                                                            : AdminStatsText.notEnoughDates,
                              value: lifespans.average.map { AdminStatsText.years($0) } ?? AdminStatsText.number(nil),
                              dim: lifespans.average == nil)
                AdminRowDivider()
                AdminStatsRow(title: L10n.t("أطول عمر", "Longest life"),
                              value: lifespans.longest.map { AdminStatsText.years($0) } ?? AdminStatsText.number(nil),
                              dim: lifespans.longest == nil)
                // «بلا تاريخ وفاة كامل» حُذف (قاعدة المالك ٢٠٢٦-١١-٢٨ «لا تكرر من الرئيسية»): بطاقة «تواريخ الوفاة» في «اليوم»
            }
        }
    }
}

/// «في التطبيق»: «170 لهم حساب» + شريط + رجال ‹ · نساء ‹ · بلا حساب (spec C.12 البند ٣)
private struct AdminStatsInAppSection: View {
    let figures: AdminCensusFigures
    let health: AdminStoreHealth
    let menTap: AdminPageTap
    let womenTap: AdminPageTap
    let retry: () -> Void

    var body: some View {
        AdminStatsSection(anchor: .inApp) {
            switch health.look {
            case .hidden:
                EmptyView()
            case .unknown:
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الحسابات", "Couldn't load the accounts"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: retry))
            case .skeleton where figures.inApp == nil:
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الحسابات…", "Loading accounts…"), rows: 3))
            case .staleWord(let since):
                AnyView(content(staleSince: since))
            default:
                AnyView(content(staleSince: nil))
            }
        }
    }

    private func content(staleSince: Date?) -> some View {
        let inApp = figures.inApp
        let without = figures.totalAlive.flatMap { l in inApp.map { max(0, l - $0) } }
        let menWithout = figures.menAlive.flatMap { a in figures.menAccounts.map { max(0, a - $0) } }
        let womenWithout = figures.womenAlive.flatMap { a in figures.womenAccounts.map { max(0, a - $0) } }
        return AdminStatsCard {
            // «170 لهم حساب» وشريط النسبة حُذفا («لا تكرر من الرئيسية»: «في التطبيق 170» في رأس «اليوم») — التفصيل وحده
            AdminStatsRow(title: L10n.t("رجال لهم حساب", "Men with an account"),
                          subtitle: figures.menAlive.map { AdminStatsText.of($0) },
                          value: AdminStatsText.number(figures.menAccounts), dim: (figures.menAccounts ?? 0) == 0,
                          tap: menTap)
            AdminRowDivider()
            AdminStatsRow(title: L10n.t("نساء لهن حساب", "Women with an account"),
                          subtitle: figures.womenAlive.map { AdminStatsText.of($0) },
                          value: AdminStatsText.number(figures.womenAccounts), dim: (figures.womenAccounts ?? 0) == 0,
                          tap: womenTap)
            AdminRowDivider()
            AdminStatsRow(title: L10n.t("بلا حساب", "No account"),
                          subtitle: AdminCensusText.split(men: menWithout, women: womenWithout),
                          value: AdminStatsText.number(without), dim: without == nil)
            if let staleSince {
                AdminStaleStamp(since: staleSince)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DS.Spacing.sm)
            }
        }
    }
}

/// «جديد في الشجرة»: «121 أُضيفوا» · «منهم 94 هذا الشهر» + أعمدة آخر ٦ أشهر
private struct AdminStatsGrowthSection: View {
    let growth: AdminStatsLogic.Growth

    var body: some View {
        AdminStatsSection(anchor: .growth) {
            AdminStatsCard {
                AdminStatsHeadline(title: AdminStatsText.added(growth.total),
                                   line: growth.total > 0 ? AdminStatsText.thisMonth(growth.current) : nil)
                    .adminStatsBlock()
                AdminStatsColumns(months: growth.months,
                                  labels: growth.months.map { AdminStatsMonthName.name($0.month) },
                                  spike: growth.spike)
                    .padding(.bottom, DS.Hub.cardPadding)
            }
        }
    }
}

/// أسماء الأشهر الميلادية («يونيو») — لغة التطبيق
enum AdminStatsMonthName {
    private static func symbols(_ locale: String) -> [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.calendar = Calendar(identifier: .gregorian)
        return f.standaloneMonthSymbols
    }

    private static let arabic = symbols("ar")
    private static let english = symbols("en")

    static func name(_ month: Int) -> String {
        let list = L10n.isArabic ? arabic : english
        return list.indices.contains(month - 1) ? list[month - 1] : ""
    }
}

/// «الأعمار»: «نعرف عمر 185 فقط» + شريط المعروف + أشرطة الفئات + «أكمل البيانات الناقصة» ‹ (spec C.12 البند ٥)
private struct AdminStatsAgesSection: View {
    let livingMen: Int
    let known: Int
    let bands: [Int]
    let missingData: Int?
    let noBirth: Int?
    let gapsTap: AdminPageTap

    var body: some View {
        let share = AdminStatsLogic.share(known, of: livingMen)
        let knownText = share.map { AdminStatsText.percent($0) } ?? AdminStatsText.number(nil)
        let unknownText = share.map { AdminStatsText.percent(100 - $0) } ?? AdminStatsText.number(nil)
        let missing = missingData ?? 0
        AdminStatsSection(anchor: .ages) {
            AdminStatsCard {
                AdminStatsHeadline(title: AdminStatsText.knownAges(known, of: livingMen),
                                   line: livingMen > 0 ? AdminStatsText.livingMen(livingMen, allKnown: known >= livingMen) : nil)
                    .adminStatsBlock()
                AdminStatsMeter(share: share, tint: DS.Chart.men, track: DS.Chart.menTrack,
                                leading: L10n.t("معروف \(knownText)", "Known \(knownText)"),
                                trailing: L10n.t("غير معروف \(unknownText)", "Unknown \(unknownText)"),
                                spoken: L10n.t("العمر معروف لـ\(knownText)", "Age known for \(knownText)"))
                    .padding(.bottom, DS.Spacing.sm)
                if known > 0 {
                    Text(verbatim: AdminStatsText.knownSplit(known))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.top, DS.Spacing.xs)
                        .accessibilityAddTraits(.isHeader)
                    AdminStatsBars(items: AdminStatsLogic.AgeBand.allCases.map { band in
                        AdminStatsBars.Item(id: band.rawValue, label: band.title, spoken: band.spoken,
                                            value: bands.indices.contains(band.rawValue) ? bands[band.rawValue] : 0)
                    })
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Hub.cardPadding)
                }
                AdminRowDivider()
                AdminStatsRow(title: L10n.t("أكمل البيانات الناقصة", "Complete missing data"),
                              subtitle: noBirth.map {
                                  L10n.t("منهم \(AdminNumberText.grouped($0)) بلا تاريخ ميلاد",
                                         "\(AdminNumberText.grouped($0)) without a birth date")
                              },
                              mark: missing > 0 ? .glyph("exclamationmark.triangle", DS.Color.warning) : .none,
                              value: AdminStatsText.number(missingData), dim: missing == 0, tap: gapsTap)
            }
        }
    }
}

/// «الأدوار»: مالك · مدير · عضو · مراقب ومشرف (الرجال الأحياء) + باب «فريق الإدارة»
private struct AdminStatsRolesSection: View {
    let roles: AdminStatsRoles
    let teamTap: AdminPageTap

    var body: some View {
        AdminStatsSection(anchor: .roles) {
            AdminStatsCard {
                row(L10n.t("مالك", "Owner"), "star", roles.owners)
                AdminRowDivider()
                row(L10n.t("مدير", "Admin"), "shield", roles.admins)
                AdminRowDivider()
                row(L10n.t("عضو", "Member"), "person", roles.members)
                AdminRowDivider()
                if roles.monitors + roles.supervisors == 0 {
                    AdminStatsRow(title: L10n.t("مراقب ومشرف", "Monitor and supervisor"),
                                  mark: .glyph("eye", DS.Color.textTertiary),
                                  value: L10n.t("لا أحد بعد", "None yet"), valueStyle: .note, dim: true)
                } else {
                    row(L10n.t("مراقب", "Monitor"), "eye", roles.monitors)
                    AdminRowDivider()
                    row(L10n.t("مشرف", "Supervisor"), "checkmark.shield", roles.supervisors)
                }
                if teamTap.isTappable {
                    AdminRowDivider()
                    AdminStatsRow(title: L10n.t("فريق الإدارة", "Admin team"), titleTint: DS.Color.primary, tap: teamTap)
                }
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ count: Int) -> AdminStatsRow {
        AdminStatsRow(title: title, mark: .glyph(symbol, DS.Color.textSecondary),
                      value: AdminNumberText.grouped(count), dim: count == 0)
    }
}

/// «الشجرة»: «1,043 أب لهم أبناء» · «12 أبناء في أكبر عائلة» — رقمان في بطاقة واحدة، بلا سهم (لا قائمة بعددهما)
private struct AdminStatsTreeSection: View {
    let fathers: Int
    let largestFamily: Int

    var body: some View {
        AdminStatsSection(anchor: .tree) {
            AdminStatsCard {
                AdminStatsDuo(items: [
                    AdminStatsDuo.Item(id: 0, value: AdminNumberText.grouped(fathers),
                                       label: L10n.t("أب لهم أبناء", "fathers with sons")),
                    AdminStatsDuo.Item(id: 1, value: AdminNumberText.grouped(largestFamily),
                                       label: L10n.t("أبناء في أكبر عائلة", "sons in the largest family"))
                ])
            }
        }
    }
}

/// «خارج العائلة»: «50 حياً من خارج العائلة» ‹ (= «فرع خارج العائلة» الأحياء) + أجزاؤه (spec C.12 البند ٨). الأحياء وحدهم —
/// صفّ «متوفون من خارج العائلة» حُذف (طلب المالك «خارج العائلة الأحياء فقط»، F1)
private struct AdminStatsOutsideSection: View {
    let figures: AdminCensusFigures
    let outsideWomen: Int?
    let husbands: Int?
    let daughtersSons: Int?
    let health: AdminStoreHealth
    let livingTap: AdminPageTap
    let retry: () -> Void

    var body: some View {
        AdminStatsSection(anchor: .outside) {
            switch health.look {
            case .hidden:
                EmptyView()
            case .unknown:
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل شجرة النساء", "Couldn't load the women's tree"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: retry))
            case .skeleton where figures.outsideLiving == nil:
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل خارج العائلة…", "Loading outside the family…"), rows: 3))
            default:
                AnyView(content)
            }
        }
    }

    private var content: some View {
        AdminStatsCard {
            // «50 حياً من خارج العائلة» حُذف («لا تكرر من الرئيسية»: «خارج العائلة 50 حياً» في رأس «اليوم») — الأجزاء وحدها
            part(L10n.t("نساء من خارج العائلة", "Women from outside the family"), outsideWomen)
            AdminRowDivider()
            part(L10n.t("أزواج البنات", "Daughters' husbands"), husbands)
            AdminRowDivider()
            part(L10n.t("أبناء البنات", "Daughters' sons"), daughtersSons)
        }
    }

    private func part(_ title: String, _ count: Int?) -> AdminStatsRow {
        AdminStatsRow(title: title, mark: .swatch(DS.Chart.outside, hatched: true),
                      value: AdminStatsText.number(count), dim: (count ?? 0) == 0)
    }
}
