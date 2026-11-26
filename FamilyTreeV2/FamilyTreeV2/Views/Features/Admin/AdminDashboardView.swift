import SwiftUI
import Combine

/// الشاشات التي يمكن دفعها عبر NavigationPath من إشعار خارجي
enum AdminReviewDestination: Hashable {
    case treeEditRequests
    case allRequests
    /// «الوارد» مفتوحاً على طلب بعينه (مربّع تفاصيله)
    case inboxItem(UUID)
    /// «رسائل الدخول · KWT SMS» (إشعار «رصيد الرسائل منخفض»)
    case sms
    /// «طلبات رمز الدخول» كاملة فوق صفحة الرسائل (إشعار «محاولات دخول مريبة»)
    case smsAttempts
    /// بيت إشارة «حالة النظام» السابقة — السطر ولوحته حُذفا (spec E.2) والمسار باقٍ (`AdminStatusPill.Home.page`)
    case status(AdminStatusPill.Home)
    /// صفحة قسم (مربّعات «اليوم» وأرقامه وقائمة العنوان) — العدّاد يجعل كل انتقال قيمة جديدة فيُستبدل المسار كله، وهو مفتاح
    /// هبوط القسم (`AdminAreaRouter.landings[hop]` — ما يفتح عليه: فلتر، قسم، قائمة فوقه)
    case area(AdminArea, Int)
}

// MARK: - لوحة الإدارة ← «اليوم» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.1، mock 1، الوحدة U7)
//
// v2 الاتجاه «أ» «بطاقات العائلة الملوّنة» (اختيار المالك ٢٠٢٦-١١-٢٦، الوحدة V2-1 — `reports/admin-redesign/v2/build-a.md`).
// من الأعلى:
//  • **الرأس الكحلي** (`AdminTodayBand`، يتمرّر مع الصفحة) يحمل كل ما فوق الأقسام: «الإدارة»، التحية وكبسولة الدور، دوائر
//    مكبّر الصوت (`canSendNotifications` × `today.megaphone`) والبحث والجرس — شارته الذهبية = ما يحتاج إجراء الآن وحده
//    (`AdminTodayBandLogic.bellCount` = «يحتاج إجراء N» في «إشعارات الإدارة»)؛ ثم **سطر التحية الذكي** حبّةً ٤٤
//    (`AdminTodayLogic.smartLine` — يظهر حين يقول شيئاً، ويفتح بيت حقيقته بهبوطها)؛ ثم حلقات «العائلة» على الكحلي
//    (`today.census`، `AdminCensusBand`) ورابطا «في التطبيق» و«خارج العائلة» (الأحياء) — كل رقم يفتح بيته بعقد T2.
//  • «الأقسام»: مربّع مسطّح بلون كل قسم ظاهر لدورك (`AdminRowTile`) بكلمة حال — «5 قوائم للمراجعة»، «لا شيء قريب»،
//    «الراحلون 502»، «يعمل للجميع ✓»، وما ينتظرك حبّة بيضاء («● 1 بانتظار ردّك»، «⚠ محاولة مريبة») — من حال مخزنها
//    (`AdminStoreHealth`: هيكل أثناء التحميل، «تعذّر التحميل ↻» عند الفشل — لا كلمة هادئة كاذبة). الضغط يفتح القسم
//    (`.area(area, hop)`) بهبوط ما تسمّيه الكلمة (`AdminAreaRouter.land`). تحتها «آخر تحديث 9:41 · اسحب للتحديث».
//  • «تواريخ الوفاة» أثناء الحملة، و«ذكرى الراحلين» بعدها (DeathDatesSpot.swift).
//  • «صلاحياتي» (المدير والمراقب والمشرف) ← `AdminMyScopeView`.
// التحميل: أرقام «العائلة» و«الوارد» أولاً، ثم مخازن المربّعات بلا انتظار (كلٌّ بمهلة إعادة جلب). الإشعار بلا `request_id`
// يفتح «الوارد» مصفّى بنوعه (`AdminInboxLanding(pushKind:)`). حارس المكدس: كل رابط خلف `AdminLazyPage { AnyView }`، وكل
// بطاقة كبيرة نوع مستقل خلف `AnyView` («اليوم» ≤ ٧٢٠ ك.ب — `-tmpStackDepth`).

struct AdminDashboardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @StateObject private var diwaniyaVM = DiwaniyasViewModel()
    @ObservedObject private var sms = SmsBalanceStore.shared
    /// «الأجهزة ووصول الإشعارات» — نفس مخزن صفحتها (رقم واحد بتعريف واحد)
    @ObservedObject private var devices = AdminDeviceReachStore.shared
    /// الديوانيات والمكتبة والمعرض المعلّقة — إشعاراتها تُعدّ على الجرس ما دامت تنتظر (V34)
    @ObservedObject private var pendingContent = AdminPendingContentStore.shared
    /// جدول «مين يشوف وش» يصل من السيرفر (`app_config.admin_role_matrix`) — تتحدّث «اليوم» حين يصل
    @ObservedObject private var config = AppConfigValues.shared
    @Binding var selectedTab: Int
    @State private var navigationPath = NavigationPath()
    /// عدّاد الانتقالات إلى صفحات الأقسام (قيمة جديدة في المسار كل مرة، ومفتاح الهبوط)
    @State private var areaHops = 0
    /// جذر المكدس («اليوم») ظاهر الآن
    @State private var rootVisible = false
    /// هوية المكدس — تتجدّد عند العودة لـ«اليوم» بعد مغادرة التبويب
    @State private var stackID = UUID()
    /// غادر المستخدم تبويب «الإدارة» منذ آخر ظهور لـ«اليوم»
    @State private var leftTab = false
    /// «ظهور موحّد»: البطاقات تصعد تباعاً مرة عند الظهور الأول (`dsCardCascade`)
    @State private var appeared = false

    // أرقام محسوبة من البيانات المحمّلة
    @State private var isInitialLoading = true
    @State private var refreshedAt: Date?
    @State private var pendingArchiveCount = 0
    @State private var treeIssuesCount = 0
    @State private var inboxTotal = 0
    @State private var joinedThisWeek = 0
    @State private var recentDeaths: [FamilyMember] = []
    /// المعلن عنهم — nil = تعذّر الجلب (لا «لم يُعلن» خطأً)
    @State private var announcedIds: Set<UUID>? = nil
    /// أرقام بطاقة «العائلة» — تعريفات «الإحصاءات» نفسها (`AdminCensusFigures.make`)
    @State private var figures = AdminCensusFigures()
    /// ذكرى وفاة اليوم (الأسماء المختصرة)، ومتى أقرب ذكرى خلال أسبوع («بعد 3 أيام»)
    @State private var memorialToday: [String] = []
    @State private var nextMemorial: String?
    /// أعداد قوائم «يحتاج مراجعتك» — كلمة مربّع «العائلة» v2 («5 قوائم للمراجعة»)، من مصدر صفّها في «العائلة» نفسه
    /// (`AdminReviewHubCounts`). المفتاح الغائب = لم يصل
    @State private var reviewCounts: [AdminReviewHubLogic.List: Int] = [:]
    /// ما بُنيت منه آخر مرة — فهرس الأعضاء يُبنى فقط حين يتغيّر (لا مع كل تغيّر في الطلبات)
    /// F4 (V30): فئة كل حساب في المفتاح — انتقال عضو بين «نشط» و«غير نشط» (العدد نفسه) يعيد الحساب
    @State private var reviewKey: AdminReviewHubLogic.CacheKey<AppUsageCategory>?

    // حال المخازن (Autoplan note 2) — كل كلمة ورقم من مخزنه
    @State private var inboxHealth: AdminStoreHealth = .idle
    /// جلب «اليوم» للأعضاء (أبناء البنات ثم الأعضاء) — جارٍ = هيكل ولو بقيت علامة فشل من جلب سابق (F1)
    @State private var membersFetch: AdminStoreHealth = .idle
    @State private var womenHealth: AdminStoreHealth = WomenStore.cache.isEmpty ? .idle : .loaded(at: Date())
    @State private var accountsHealth: AdminStoreHealth = AdminAccountsStore.shared.loaded ? .loaded(at: Date()) : .idle
    @State private var announcedHealth: AdminStoreHealth = .idle
    @State private var scheduledHealth: AdminStoreHealth = .idle
    @State private var settingsHealth: AdminStoreHealth = .idle
    /// آخر جلب لمخازن المربّعات التي لا مهلة لها في مخزنها
    @State private var fetchedAt: [TileStore: Date] = [:]

    /// «نساء العائلة» من حلقة «النساء» (المالك والمدير) — بفلاترها من الرقم المضغوط
    @State private var womenPushed = false
    @State private var womenLanding = AdminWomenLanding()

    /// مخازن المربّعات بمهلة إعادة الجلب هنا (`AdminTodayMetrics.refetchAfter`)
    private enum TileStore: Hashable { case scheduled, announced, bans }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            root
                .navigationDestination(for: AdminReviewDestination.self) { destination in
                    AdminLazyPage { Self.page(for: destination) }
                }
                .navigationDestination(isPresented: $womenPushed) {
                    AdminLazyPage { womenPage }
                }
                // «اليوم» ظاهر = المكدس عند جذره: مسار باقٍ هنا معناه أنه انفصل عن الشاشة بعد الرجوع، فكانت المربّعات لا تفتح
                // حتى يُغلق التطبيق (بلاغ المالك ٢٠٢٦-١١-٠٨) — يُصفَّر بعد لحظة وما زال الجذر ظاهراً
                .onAppear {
                    rootVisible = true
                    // «حي ✓» وما تغيّر في «العائلة» أثناء غيابها — كلمة مربّع «العائلة» (لا يُبنى شيء إن لم يتغيّر)
                    recalculateReview()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if rootVisible && !navigationPath.isEmpty { navigationPath = NavigationPath() }
                    }
                }
                .onDisappear { rootVisible = false }
                // أبناء البنات قد يصلون بعد الأعضاء — يُعاد الحساب فلا يُعدّون في «الرجال» (٢٠٢٦-١١-١٢)
                .onReceive(DaughterSonsIndex.shared.$ids.dropFirst().removeDuplicates()) { _ in recalculate() }
                .toolbar(.hidden, for: .navigationBar)
        }
        // بعد مغادرة تبويب «الإدارة» يفقد المكدس وجهاته (بلاغ المالك ٢٠٢٦-١١-٠٨) — يُعاد بناؤه عند العودة (`stackID`)
        .id(stackID)
        .onChange(of: selectedTab) { tab in
            if tab != 4 {
                leftTab = true
                // هبوط ينتظر لا يبقى بعد مغادرة التبويب (عقد U2)
                AdminAreaRouter.clearLandings()
            } else if leftTab {
                leftTab = false
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { stackID = UUID() }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // الضغط على تبويب «الإدارة» وهو مختار يرجع لـ«اليوم» (رجوع النظام كان يترك المسار — بلاغ المالك ٢٠٢٦-١١-٠٨)
        .onReceive(NotificationCenter.default.publisher(for: .didReselectTab)) { note in
            guard (note.userInfo?["tab"] as? Int) == 4, !navigationPath.isEmpty else { return }
            AdminAreaRouter.clearLandings()
            navigationPath = NavigationPath()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAdminReviewForKind)) { routePush($0) }
        .task {
            // قائمة العنوان «… ⌄» في كل صفحة من هذا المكدس تنقل عبر هذا
            AdminAreaRouter.navigate = openArea
            // «حي ✓» المحلية لهذا المستخدم — «≈» في بطاقة «العائلة»
            AdminLivingVerifiedStore.shared.activate(user: authVM.currentUser?.id)
            appeared = true
            // من آخر ما حُمّل في التطبيق — الأرقام فوراً، ثم الجلب
            recalculate()
            await loadAllAdminData()
        }
        .onChange(of: memberVM.membersVersion) { _ in recalculate() }
        .onChange(of: pendingRequestsSum) { _ in recalculate() }
        .onChange(of: pendingArchiveCount) { _ in recalculate() }
    }

    // MARK: - المسار

    /// وجهات المسار — كل وجهة بقسمها؛ وجهات «الوارد» من الإشعارات خلف بوابته (جدول الأدوار)
    static func page(for destination: AdminReviewDestination) -> AnyView {
        switch destination {
        case .treeEditRequests:
            return AnyView(AdminAreaGate(area: .inbox) { AnyView(AdminTreeEditRequestsView()) }.adminArea(.inbox))
        case .allRequests:
            return AnyView(AdminAreaGate(area: .inbox) { AnyView(AdminAllRequestsView()) }.adminArea(.inbox))
        case .inboxItem(let id):
            return AnyView(AdminAreaGate(area: .inbox) { AnyView(AdminAllRequestsView(focusId: id)) }.adminArea(.inbox))
        case .sms:               return AnyView(AdminSmsView(backTitle: AdminArea.homeTitle).adminArea(.team))
        case .smsAttempts:       return AnyView(SmsAttemptsListPage().adminArea(.team))
        case .status(let home):  return home.page
        case .area(let area, let hop): return AnyView(AdminAreaView(area: area).adminAreaHop(hop))
        }
    }

    /// من «اليوم» (مربّع، رقم، سطر التحية، إشعار): مسار جديد بصفحة القسم وحدها وهبوطها (قيمة فريدة كل مرة)
    private func openFromToday(_ area: AdminArea, landing: AdminLanding? = nil) {
        areaHops += 1
        AdminAreaRouter.land(landing, hop: areaHops)
        var path = NavigationPath()
        path.append(AdminReviewDestination.area(area, areaHops))
        navigationPath = path
    }

    /// قائمة العنوان: المسار كله يصير صفحة القسم المطلوب على افتراضه (`navigate` يمسح الهبوطات قبل هذا)
    private func openArea(_ area: AdminArea) {
        areaHops += 1
        var path = NavigationPath()
        path.append(AdminReviewDestination.area(area, areaHops))
        // من «اليوم»: دفع عادي؛ من قسم إلى قسم: تذوب الصفحة في الأخرى بلا انزلاق
        guard !navigationPath.isEmpty else { navigationPath = path; return }
        DSScreenCrossfade.run {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { navigationPath = path }
        }
    }

    private func open(_ link: AdminTodayLink) {
        openFromToday(link.home.area, landing: link.landing)
    }

    /// إشعار (push، «إشعارات الإدارة»، مركز الإشعارات): الطلب نفسه إن عُرف، وإلا «الوارد» مصفّى بنوع الإشعار (القائمة
    /// البيضاء في `AdminInboxLanding(pushKind:)` — نوع مجهول = «الوارد» بلا فلتر). رسائل الدخول للمالك وحده
    private func routePush(_ note: Notification) {
        guard let kind = note.userInfo?["kind"] as? String else { return }
        guard authVM.canViewSystemSettings || !AdminNotices.smsKinds.contains(kind) else { return }
        let requestId = (note.userInfo?["request_id"] as? String).flatMap(UUID.init(uuidString:))
        let destinations: [AdminReviewDestination]
        if kind == AdminNotices.smsSuspicious {
            destinations = [.sms, .smsAttempts]
        } else if kind == AdminNotices.smsBalanceLow {
            destinations = [.sms]
        } else if let requestId {
            destinations = [.inboxItem(requestId)]
        } else {
            let landing = AdminInboxLanding(pushKind: kind)
            openFromToday(.inbox, landing: landing.isEmpty ? nil : .inbox(landing))
            return
        }
        // قشّر المكدس الحالي قبل الدفع لتجنّب التراكم
        AdminAreaRouter.clearLandings()
        var path = NavigationPath()
        for destination in destinations { path.append(destination) }
        navigationPath = path
    }

    /// «نساء العائلة» بالفلاتر من الرقم المضغوط (الحالة = الكل — T2)
    private var womenPage: AnyView {
        AnyView(AdminAreaGate(area: .family) { [womenLanding] in AnyView(AdminWomenPanel(landing: womenLanding)) }
            .adminArea(.family)
            .adminBackTitle(AdminArea.homeTitle))
    }

    // MARK: - التحميل

    /// مجموع كل الطلبات المعلّقة — يعيد الحساب لحظياً عند أي تغيير
    private var pendingRequestsSum: Int {
        newsVM.pendingNewsRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + diwaniyaVM.pendingDiwaniyas.count
            + adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.treeEditRequests.count
            + projectsVM.pendingProjects.count
    }

    /// أرقام «العائلة» تُحسب لمن يرى البطاقة أو «الإحصاءات ← العائلة» (كلمة «170 في التطبيق»)
    private var needsFigures: Bool { authVM.adminSees(.todayCensus) || authVM.adminSees(.metricsFamily) }

    /// كل بيانات «اليوم» — في `.task` وفي السحب للتحديث. أرقام «العائلة» و«الوارد» أولاً (ما تُبنى عليه الصفحة)، ثم
    /// مخازن المربّعات بلا انتظار (السحب ينتهي حين تصل الأولى)
    private func loadAllAdminData(force: Bool = false) async {
        // جدول الأقسام والبطاقات لكل دور من السيرفر — قبل الباقي (غيابه = الافتراضي المكتوب في `AdminRoleMatrix`)
        await AppConfigValues.shared.refresh(force: force)
        diwaniyaVM.canModerate = authVM.canModerate
        diwaniyaVM.authVM = authVM
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await loadCensus(force: force) }
            group.addTask { @MainActor in await loadInbox() }
        }
        recalculate()
        refreshedAt = Date()
        if isInitialLoading { withAnimation(DS.Anim.smooth) { isInitialLoading = false } }
        Task { @MainActor in await loadTileStores(force: force) }
    }

    /// ١) «العائلة»: أبناء البنات قبل الأعضاء (لا يُعدّون في «الرجال»)، ثم شجرة النساء وقوائم الحسابات معاً
    private func loadCensus(force: Bool) async {
        membersFetch = membersFetch.beginning()
        if authVM.canModerateTree { await DaughterSonsIndex.shared.refresh(force: force) }
        await memberVM.fetchAllMembers(force: force)
        membersFetch = AdminTodayLogic.membersFetchEnded(hasMembers: !memberVM.allMembers.isEmpty,
                                                         loadFailed: memberVM.membersLoadFailed)
        // قوائم الحسابات لكل من يرى «العائلة» (قوائم «يحتاج مراجعتك» الثلاث تنتظرها — F4، V18)، وشجرة النساء لأرقام الرأس
        let needsAccounts = needsFigures || seesFamily
        guard needsFigures || needsAccounts else { return }
        await withTaskGroup(of: Void.self) { group in
            if needsFigures { group.addTask { @MainActor in await loadWomen(force: force) } }
            if needsAccounts { group.addTask { @MainActor in await loadAccounts(force: force) } }
        }
    }

    /// يرى قسم «العائلة» (مربّعه في «اليوم» يقول قوائمه)
    private var seesFamily: Bool { AdminArea.family.isVisible(for: authVM) }

    /// شجرة النساء (نساء العائلة و«خارج العائلة») — الكاش يكفي حتى السحب. `-tmpFailStores census` يُفشلها
    private func loadWomen(force: Bool) async {
        womenHealth = womenHealth.beginning()
        do {
            try DebugAdminProbe.failIfAsked(.census, hasLoaded: womenHealth.hasData)   // `-tmpFailStores census`
            if force || WomenStore.cache.isEmpty { _ = try await WomenStore.fetch() }
            womenHealth = womenHealth.ending(success: true)
        } catch {
            if ErrorHelper.isCancellation(error) {
                if womenHealth == .loading { womenHealth = .idle }
                return
            }
            if !DebugAdminProbe.isInjected(error) {
                Log.warning("[Today] تعذّر جلب شجرة النساء: \(error.localizedDescription)")
            }
            womenHealth = womenHealth.ending(success: false)
        }
    }

    /// قوائم الحسابات («في التطبيق» — مهلة ٦٠ ث في مخزنها). `-tmpFailStores accounts` يُفشلها
    private func loadAccounts(force: Bool) async {
        accountsHealth = accountsHealth.beginning()
        if DebugAdminProbe.shouldFail(.accounts, hasLoaded: AdminAccountsStore.shared.loaded) {
            accountsHealth = accountsHealth.ending(success: false)
            return
        }
        let store = AdminAccountsStore.shared
        await store.refresh(force: force)
        // بحال المخزن نفسه: جلب أُلغي (أو آخر ما زال جارياً) ليس فشلاً — كان «تعذّر التحميل» في مربّع «الإحصاءات» (F1)
        accountsHealth = AdminTodayLogic.accountsHealth(after: accountsHealth, store: store.health,
                                                        storeLoaded: store.loaded)
    }

    /// ١) «الوارد»: المفتاح طازجاً ثم كل قوائم الطلبات بالتوازي (نفس نداءات «الوارد»). `-tmpFailStores inbox` يُفشلها
    private func loadInbox() async {
        inboxHealth = inboxHealth.beginning()
        // «مسار الموافقات»: المفتاح قبل القوائم (عاجل · متأخر · بانتظارك)
        await adminRequestVM.refreshApprovalsFlag()
        let injected = DebugAdminProbe.shouldFail(.inbox, hasLoaded: inboxHealth.hasData)   // `-tmpFailStores inbox`
        if !injected {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in await adminRequestVM.fetchDeceasedRequests() }
                group.addTask { @MainActor in await newsVM.fetchPendingNewsRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchChildAddRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNewsReportRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhoneChangeRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchPhotoSuggestionRequests() }
                group.addTask { @MainActor in await diwaniyaVM.fetchPendingDiwaniyas() }
                group.addTask { @MainActor in await adminRequestVM.fetchTreeEditRequests() }
                group.addTask { @MainActor in await adminRequestVM.fetchNameChangeRequests() }
                // «الرسائل» رسائل خاصة — لمن يراها في جدول السيرفر (`inbox.messages`)، وغيره لا يجلبها أصلاً
                if authVM.adminSees(.inboxMessages) {
                    group.addTask { @MainActor in await adminRequestVM.fetchContactMessages() }
                }
                group.addTask { @MainActor in await adminRequestVM.fetchJoinApprovalRequests() }
                // طلبات الخصوصية (حذف الحساب، الخصوصية…) — حقيقة وحدها في مربّع «الوارد» وسطر التحية (لا في «بانتظار
                // قرارك» — F1) و«يحتاج إجراء» في «إشعارات الإدارة»
                group.addTask { @MainActor in await adminRequestVM.fetchPolicyRequests() }
                group.addTask { @MainActor in await projectsVM.fetchPendingProjects() }
                group.addTask { @MainActor in pendingArchiveCount = await FamilyArchiveViewModel.pendingCount() }
                group.addTask { @MainActor in await AdminPendingContentStore.shared.refresh(force: true) }
            }
        }
        inboxHealth = inboxHealth.ending(success: !injected && NetworkMonitor.shared.isConnected)
    }

    /// ٢) مخازن المربّعات — بعد أرقام الصفحة، بلا انتظار، وكلٌّ بمهلة إعادة جلب (السحب يتجاوزها)
    private func loadTileStores(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in await loadTeamStores(force: force) }
            group.addTask { @MainActor in await loadOccasionsStores(force: force) }
            // «استخدام التطبيق» لمن يرى «العائلة» (يقرؤه «إحصاء الأفراد» في «الإحصاءات») — يُجلب إن لم يُحمَّل بعد أو بالسحب
            if needsFigures && (force || AppUsageStats.cached == nil) {
                group.addTask { @MainActor in _ = await AppUsageStats.fetch() }
            }
        }
        publishNotices()
    }

    /// «الفريق والأمان» و«التطبيق» (المالك): الرصيد والأجهزة (مهلة ٦٠ ث في مخزنيهما)، الأرقام الممنوعة، والإعدادات
    private func loadTeamStores(force: Bool) async {
        guard authVM.canViewSystemSettings else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await sms.refresh(force: force)
                if sms.state == .loaded, force || AdminTeamClock.smsLoadedAt == nil { AdminTeamClock.smsLoadedAt = Date() }
            }
            group.addTask { @MainActor in await devices.refresh(force: force) }
            group.addTask { @MainActor in await loadSettings(force: force) }
            if due(.bans, force: force) {
                fetchedAt[.bans] = Date()
                group.addTask { @MainActor in await authVM.fetchBannedPhones() }
            }
        }
    }

    /// إعدادات التطبيق (الصيانة، الإشعارات، التسجيل) — محمّلة مع التطبيق عادةً؛ تُجلب هنا إن لم تصل أو بالسحب
    private func loadSettings(force: Bool) async {
        let has = appSettingsVM.settings.updatedAt != nil
        settingsHealth = AdminTeamLogic.seeded(settingsHealth, hasData: has)
        guard force || !has else { return }
        settingsHealth = settingsHealth.beginning()
        await appSettingsVM.fetchSettings()
        settingsHealth = settingsHealth.ending(success: appSettingsVM.settings.updatedAt != nil
                                                && NetworkMonitor.shared.isConnected)
    }

    /// «المناسبات» (المالك والمدير): الإشعارات المجدولة والوفيات المعلن عنها
    private func loadOccasionsStores(force: Bool) async {
        guard authVM.isAdmin else { return }
        await withTaskGroup(of: Void.self) { group in
            if due(.scheduled, force: force) {
                fetchedAt[.scheduled] = Date()
                group.addTask { @MainActor in
                    scheduledHealth = scheduledHealth.beginning()
                    await notificationVM.fetchScheduledNotifications()
                    scheduledHealth = scheduledHealth.ending(success: NetworkMonitor.shared.isConnected)
                }
            }
            if due(.announced, force: force) {
                fetchedAt[.announced] = Date()
                group.addTask { @MainActor in
                    announcedHealth = announcedHealth.beginning()
                    if let ids = await AdminTodayFetch.announcedDeathIds() {
                        announcedIds = ids
                        announcedHealth = announcedHealth.ending(success: true)
                    } else {
                        announcedHealth = announcedHealth.ending(success: false)
                    }
                }
            }
        }
        publishNotices()
    }

    private func due(_ store: TileStore, force: Bool) -> Bool {
        guard !force, let at = fetchedAt[store] else { return true }
        return Date().timeIntervalSince(at) >= AdminTodayMetrics.refetchAfter
    }

    // «تعذّر التحميل ↻» في مربّع: يعيد جلب مخزنه وحده
    private var retryInbox: () -> Void { { Task { @MainActor in await loadInbox(); recalculate() } } }
    private var retryCensus: () -> Void { { Task { @MainActor in await loadCensus(force: true); recalculate() } } }
    private var retryOccasions: () -> Void { { Task { @MainActor in await loadOccasionsStores(force: true) } } }
    private var retryTeam: () -> Void { { Task { @MainActor in await loadTeamStores(force: true) } } }
    private var retrySettings: () -> Void { { Task { @MainActor in await loadSettings(force: true) } } }

    /// الحالات المشتقة لـ«إشعارات الإدارة» (وفاة لم يُعلن عنها، مشكلات الشجرة للمراقب، خلل قاعدة البيانات)
    private var derivedNotices: [AdminNoticeItem] {
        AdminNoticeStore.derive(authVM: authVM, unannounced: unannounced,
                                treeIssues: isInitialLoading ? nil : treeIssuesCount)
    }

    private func publishNotices() {
        AdminNoticeStore.shared.publish(derivedNotices)
    }

    /// الأرقام المحسوبة من الأعضاء والطلبات — مرور واحد على الأعضاء
    private func recalculate() {
        let all = memberVM.allMembers
        var treeIssues = 0, joined = 0
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        // «مشكلات الشجرة» بتعريف قائمتها في «العائلة» نفسه (يتيم، بلا اسم، أب مفقود، مخفي، رقم مكرر)
        let tree = AdminMemberFacts.TreeContext(all)
        for m in all {
            if m.role == .pending { continue }
            // نفس «قُيّدوا هذا الأسبوع» في «العائلة»
            if m.isDeceased != true && m.isCountable,
               let created = ApprovalWorkflow.date(m.createdAt), created >= weekAgo { joined += 1 }
            // ابن البنت وحساب المرأة بيتهما شجرة النساء — ليسا «مشكلة» في شجرة الرجال
            if DaughterSonsIndex.shared.contains(m.id) || m.isWomanAccount { continue }
            if !AdminMemberFacts.problems(m, in: tree).isEmpty { treeIssues += 1 }
        }
        let total = AdminAllRequestsView.reviewRequestsTotal(
            memberVM: memberVM, newsVM: newsVM, adminRequestVM: adminRequestVM,
            diwaniyaVM: diwaniyaVM, projectsVM: projectsVM,
            pendingArchiveCount: pendingArchiveCount,
            scope: AdminAllRequestsView.reviewScope(for: authVM),
            includePhotos: AdminAllRequestsView.reviewIncludesPhotos(for: authVM),
            // قائمة «الوارد» وحدها = شريحة «بانتظار قرارك» فيه (T2)؛ طلبات الخصوصية رقمها وحدها (`counts.policy`)
            includePolicy: false)
        let deaths = all.filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate) }
            .sorted { ($0.deathDate ?? "") > ($1.deathDate ?? "") }
        // نفس أرقام «الإحصاءات» (`AdminStatsSnapshot`): الرقم المضغوط = أول رقم في بيته (T2)
        let women = WomenStore.cache
        let census = needsFigures && !all.isEmpty
            ? AdminCensusFigures.make(census: AdminFamilyCensus.make(members: all, women: women), members: all, women: women)
            : AdminCensusFigures()
        let board = DeceasedMemorialBoard(all)
        let today = board.today.map(\.member.shortFullName)
        let next = board.upcoming.first { $0.anniversary.daysUntil < DeceasedMemorial.weekDays }
            .map { DeceasedMemorial.whenLabel($0.anniversary.daysUntil, arabic: L10n.isArabic) }
        withAnimation(DS.Anim.smooth) {
            treeIssuesCount = treeIssues
            joinedThisWeek = joined
            inboxTotal = total
            recentDeaths = deaths
            if census != figures { figures = census }
            if today != memorialToday { memorialToday = today }
            if next != nextMemorial { nextMemorial = next }
        }
        recalculateReview()
        publishNotices()
    }

    /// أعداد قوائم «يحتاج مراجعتك» لمربّع «العائلة» — فهرس الأعضاء نفسه الذي تبنيه «العائلة» وصفحة القوائم، ويُعاد بناؤه
    /// فقط حين يتغيّر الأعضاء أو قوائم الحسابات أو أبناء البنات أو «حي ✓»
    private func recalculateReview() {
        guard AdminArea.family.isVisible(for: authVM), !memberVM.allMembers.isEmpty else { return }
        let accounts = AdminAccountsStore.shared
        let sons = DaughterSonsIndex.shared.ids
        let verified = AdminLivingVerifiedStore.shared.ids
        let key = AdminReviewHubLogic.CacheKey(membersVersion: memberVM.membersVersion, members: memberVM.allMembers.count,
                                               accountsLoaded: accounts.loaded,
                                               accounts: accounts.accounts.mapValues(\.usage),
                                               daughterSons: sons, verified: verified)
        guard key != reviewKey else { return }
        reviewKey = key
        let index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                            accountsReady: accounts.loaded, daughterSons: sons, branchName: { _ in nil })
        let counts = AdminReviewHubCounts.make(index: index, verified: verified, members: memberVM.allMembers,
                                               photos: .init(authVM: authVM))
        if counts != reviewCounts { reviewCounts = counts }
    }

    // MARK: - مشتقات

    private var visibleAreas: [AdminArea] { AdminArea.visible(for: authVM) }

    /// بانتظارك · عاجل · متأخر · رسائل — نفس تعريف فلاتر «الوارد»
    private var counts: AdminTodayCounts {
        AdminTodayFeed.counts(authVM: authVM, adminRequestVM: adminRequestVM, inboxTotal: inboxTotal)
    }

    /// المتوفون حديثاً ولم يُعلن عنهم (المالك والمدير) — فارغة إن لم يُعرف المعلن عنهم
    private var unannounced: [FamilyMember] {
        guard authVM.isAdmin, let announcedIds else { return [] }
        // مدة التنبيه من السيرفر (تُقرأ مع المعلن عنهم) — الوفيات الحديثة نفسها ٣٠ يوماً
        return recentDeaths.filter { !announcedIds.contains($0.id) && DeathRecency.isRecent($0.deathDate, within: DeathRecency.alertDays) }
    }

    /// الأعضاء: وصلوا = كلمة؛ وإلا حال جلب «اليوم» — «تعذّر التحميل» بعد أن ينتهي بفشل فقط (F1)
    private var membersHealth: AdminStoreHealth {
        AdminTodayLogic.membersHealth(hasMembers: !memberVM.allMembers.isEmpty, loadedAt: refreshedAt, fetch: membersFetch)
    }

    /// أرقام بطاقة «العائلة»: الأعضاء وشجرة النساء معاً
    private var censusHealth: AdminStoreHealth { .combined([membersHealth, womenHealth]) }

    /// الرقم الرابع في كلمات «الوارد» — من جدول الأدوار (`attention_fourth`)
    private var fourth: (kind: AdminTodayFourth, count: Int) {
        switch AdminRoleMatrix.attentionFourth(for: authVM.currentUser?.role) {
        case .messages:   return (.messages, counts.unreadMessages)
        case .treeIssues: return (.treeIssues, treeIssuesCount)
        case .reports:    return (.reports, adminRequestVM.newsReportRequests.count)
        }
    }

    private var scheduledToday: Int {
        notificationVM.scheduledNotifications.compactMap(\.scheduledDate).filter { Calendar.current.isDateInToday($0) }.count
    }

    /// «محاولات دخول مريبة» لم تُقرأ (المالك)
    private var suspicious: Int {
        notificationVM.notifications.filter { !$0.read && $0.kind == AdminNotices.smsSuspicious }.count
    }

    /// سطر التحية الذكي — العاجل أولاً (يتّفق مع مربّع «الوارد»)
    private var smartLine: AdminSmartLine? {
        let seesAttention = authVM.adminSees(.todayAttention)
        let c = counts
        let input = AdminTodayLogic.SmartInput(
            loading: isInitialLoading,
            urgent: seesAttention ? c.urgent : 0,
            waiting: seesAttention ? c.waiting : 0,
            policy: seesAttention ? c.policy : 0,
            memorialToday: memorialToday,
            unannounced: unannounced.map(\.shortFullName),
            joinedThisWeek: AdminArea.family.isVisible(for: authVM) ? joinedThisWeek : nil,
            opens: Set(visibleAreas.map(\.todayHome)))
        return AdminTodayLogic.smartLine(input)
    }

    /// «صلاحياتي» للمدير والمراقب والمشرف (spec B.1/C.1) — المالك يرى كل شي
    private var scopeGuide: RoleGuide? {
        guard let role = authVM.currentUser?.role, role != .owner else { return nil }
        return RoleGuide.forRole(role)
    }

    private var helloLine: String {
        let name = authVM.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hello = AdminTodayText.greeting()
        return name.isEmpty ? hello : L10n.t("\(hello)، \(name)", "\(hello), \(name)")
    }

    // MARK: - الجذر

    // كل جزء خلف AnyView: نوع الصفحة كاملاً كان عميقاً لدرجة أن حلّه في الجوال (مكدس الخيط الرئيسي ١ ميغا) يفيض
    // فينهار التطبيق عند فتح الإدارة (٢٠٢٦-١٠-٢٠). الحدود تقسم الحلّ إلى أجزاء صغيرة.
    // v2 (V2-1): الرأس الكحلي يحمل الحلقات فصار أطول من أن يثبت — يتمرّر مع الصفحة كرؤوس صفحات الأقسام (`AdminHubPage`)،
    // ومنطقة شريط الحالة كحلية ثابتة فوقه (`adminStatusBarCover`)
    private var root: AnyView {
        AnyView(ZStack(alignment: .top) {
            DS.Hub.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    todayBand
                    todayContent
                }
            }
            .refreshable { await loadAllAdminData(force: true) }
            .adminHideTopEdgeEffect()
            // السحب للتحديث يكشف لون الرأس لا الأبيض (وأفقياً حتى طرف الشاشة كالرأس)
            .background(alignment: .top) {
                DSHeaderBackground(section: .admin)
                    .frame(height: AdminTodayMetrics.pullReveal)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .accessibilityHidden(true)
            }
        }
        .adminStatusBarCover()
        .debugStackProbe("AdminDashboardView", limitKB: DebugStackLimit.today))
    }

    // MARK: - الرأس الكحلي (V2-1)

    /// الرأس كله (spec V2-1 البند ١): «الإدارة» والتحية والدور والأزرار ← سطر التحية حبّةً ← حلقات «العائلة» ورابطاها
    /// (`today.census`). نوع مستقل خلف `AnyView` (`AdminTodayBand`)، والحلقات نوعها (`AdminCensusBand`)
    private var todayBand: AnyView {
        let line = smartLine
        let target = line?.link.map { $0.home.area }
        let openLine: (() -> Void)? = line?.link.map { link in { self.open(link) } }
        let census: AnyView? = authVM.adminSees(.todayCensus)
            ? AnyView(AdminCensusBand(figures: figures, health: censusHealth, actions: censusActions))
            : nil
        return AnyView(AdminTodayBand(greeting: helloLine,
                                      role: authVM.currentUser.flatMap { RoleGuide.forRole($0.role)?.title },
                                      buttons: headerButtons, smartLine: line, openSmartLine: openLine,
                                      smartHint: target.map { L10n.t("يفتح \($0.title)", "Opens \($0.title)") },
                                      census: census))
    }

    /// أزرار الرأس دوائر ٤٤: مكبّر الصوت (لمن يرسل للأعضاء — `today.megaphone`)، البحث، وجرس «إشعارات الإدارة» — بيته
    /// كما هو، وشارته الذهبية = ما يحتاج إجراء الآن وحده (رقم شريحة «يحتاج إجراء N» في صفحته)
    private var headerButtons: AnyView {
        let bell = bellCount
        let canAnnounce = authVM.canSendNotifications && authVM.adminAccess(.todayMegaphone).canEdit
        return AnyView(HStack(spacing: DS.Spacing.xsm) {
            // «إعلان جديد» السريع (طلب المالك ٢٠٢٦-١٠-٢٠) — نوع مستقل خلف `AnyView` (حارس المكدس)
            if canAnnounce {
                AnyView(AdminAnnounceLauncher())
            }
            NavigationLink { AdminLazyPage { AnyView(AdminSearchView()) } } label: {
                AdminHeaderIcon(symbol: "magnifyingglass")
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(L10n.t("بحث في اللوحة", "Search the dashboard"))
            NavigationLink {
                // الرجوع باسم الرأس المرئي «الإدارة» كبقية ما يُدفع من «اليوم» (F1 — كانت «اليوم» تُترجم في الصفحة)
                AdminLazyPage { AnyView(AdminNotificationsPage().adminBackTitle(AdminArea.homeTitle)) }
            } label: {
                AdminHeaderIcon(symbol: "bell", count: bell)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(bell > 0
                ? L10n.t("إشعارات الإدارة، \(bell) تحتاج إجراء", "Admin notifications, \(bell) need action")
                : L10n.t("إشعارات الإدارة", "Admin notifications"))
        })
    }

    /// عدد الجرس: الحالات المشتقة + الإشعارات التي تنتظر قراراً — نفس «يحتاج إجراء N» في «إشعارات الإدارة»
    /// (`AdminTodayBandLogic.bellCount`)؛ غير المقروء وحده لا يُعدّ
    private var bellCount: Int {
        let open = AdminTodayFeed.openRequestIds(adminRequestVM: adminRequestVM, newsVM: newsVM,
                                                 projectsVM: projectsVM, memberVM: memberVM,
                                                 pendingContent: pendingContent.ids)
        let notices = AdminTodayFeed.bellNotices(notificationVM.notifications, me: authVM.currentUser?.id)
        return AdminTodayBandLogic.bellCount(derived: derivedNotices.count, notices: notices, open: open,
                                             seesMessages: authVM.adminSees(.inboxMessages))
    }

    // MARK: - المحتوى

    /// صفحة بيضاء (spec A.2): ١٦ تحت الرأس ← «الأقسام» و«آخر تحديث · اسحب للتحديث» تحتها ← «تواريخ الوفاة»/«ذكرى
    /// الراحلين» ← «صلاحياتي» — ٢٤ بين الأقسام. «العائلة» صارت في الرأس (V2-1). كل قسم نوع مستقل خلف `AnyView` (حارس
    /// المكدس) ويصعد تباعاً مرة واحدة
    private var todayContent: AnyView {
        AnyView(VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
            AnyView(VStack(alignment: .leading, spacing: DS.Hub.bandGap) {
                areasSection
                if let refreshedAt {
                    footer(refreshedAt)
                }
            }
            .dsCardCascade(0, appeared: appeared))
            AnyView(AdminDeathDatesSpot(openOccasions: occasionsMemorials).dsCardCascade(1, appeared: appeared))
            if let guide = scopeGuide {
                AnyView(AdminScopeLink(guide: guide).dsCardCascade(2, appeared: appeared))
            }
        }
        .dsPageMargin()
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, DS.Hub.pageBottom)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .dsTabBarClearance()
        .frame(maxWidth: .infinity)
        // أرضية اللوحة البيضاء فوق كشف السحب الكحلي
        .background(DS.Hub.background.ignoresSafeArea(edges: .horizontal)))
    }

    /// «آخر تحديث 9:41 · اسحب للتحديث» — ١٣ رمادي في الوسط
    private func footer(_ date: Date) -> some View {
        Text(verbatim: AdminStoreHealthText.updated(date) + " · " + L10n.t("اسحب للتحديث", "Pull to refresh"))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: «العائلة» (في الرأس)

    private var censusActions: AdminCensusRingsActions {
        AdminCensusRingsActions(total: censusAction(.total), men: censusAction(.men), women: censusAction(.women),
                                inApp: censusAction(.inApp), outside: censusAction(.outside),
                                estimate: censusAction(.estimate), retry: retryCensus)
    }

    /// المالك والمدير يفتحان صفحة «نساء العائلة»، والمراقب شجرة النساء (نفس `AdminStatsLogic.Viewer`)
    private var seesWomenPage: Bool { AdminArea.family.isVisible(for: authVM) && authVM.isAdmin }

    /// وجهة كل رقم من عقد T2 (`AdminCensusRoutes`) — بيت مخفي لدورك = رقم بلا سهم
    private func censusAction(_ number: AdminCensusNumber) -> (() -> Void)? {
        switch AdminCensusRoutes.destination(number, on: .today, seesWomenPage: seesWomenPage) {
        case .none:
            return nil
        case .stats(let anchor):
            guard AdminArea.metrics.isVisible(for: authVM) else { return nil }
            return { openFromToday(.metrics, landing: .stats(anchor)) }
        case .members(let landing):
            guard AdminArea.family.isVisible(for: authVM) else { return nil }
            return { openFromToday(.family, landing: .members(landing)) }
        case .women(let landing):
            return {
                womenLanding = landing
                womenPushed = true
            }
        case .womenTree:
            // شجرة النساء تُدار من تبويب الشجرة
            return {
                TreeTabContainer.openWomenOnAppear = true
                NotificationCenter.default.post(name: .openWomenTree, object: nil)
            }
        }
    }

    // MARK: «الأقسام»

    /// مربّع لكل قسم ظاهر لدورك بكلمة حاله (spec A.8/C.1) — عمودان، والفردي يمدّ آخره، وعمود واحد من أحجام إمكانية الوصول
    private var areasSection: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("الأقسام", "Sections"))
            AdminRowTileGrid {
                ForEach(visibleAreas) { area in
                    let model = tile(area)
                    // زرّ يضع مساراً جديداً بقيمة فريدة (لا رابط بقيمة ثابتة — كان يُتجاهل إن بقيت القيمة نفسها في المسار)
                    Button { openFromToday(area, landing: model.landing) } label: {
                        AdminRowTile(area: area, state: model.state, health: model.health, retry: model.retry,
                                     readOnly: area.isReadOnly(for: authVM))
                    }
                    .buttonStyle(AdminTilePressStyle())
                }
            }
        }
    }

    /// كلمة المربّع وحال مخزنها وإعادة جلبه وهبوط القسم
    private struct TileModel {
        var state: AdminTileState? = nil
        var health: AdminStoreHealth? = nil
        var retry: (() -> Void)? = nil
        var landing: AdminLanding? = nil
    }

    private func tile(_ area: AdminArea) -> TileModel {
        switch area {
        case .inbox:
            // `today.attention`: أرقام «الوارد» لهذا الدور — بدونها اسم القسم وحده
            guard authVM.adminSees(.todayAttention) else { return TileModel(health: inboxHealth, retry: retryInbox) }
            let c = counts
            let f = fourth
            let word = AdminTodayLogic.inboxWord(urgent: c.urgent, waiting: c.waiting, late: c.late, policy: c.policy,
                                                 fourth: f.kind, fourthCount: f.count)
            return TileModel(state: word.state, health: inboxHealth, retry: retryInbox, landing: word.landing)
        case .family:
            // v2: «5 قوائم للمراجعة» — قوائم «يحتاج مراجعتك» التي فيها أحد (رقم صفّها في «العائلة») أو «سليمة»؛ يفتح
            // «العائلة» حيث صفّ «يحتاج مراجعتك». قوائم الحسابات تنتظر قوائم الحسابات ما دام جلبها جارياً (لا عدد ناقص)
            let counts = AdminReviewHubLogic.List.allCases.map { reviewCounts[$0] }
            let word = AdminTodayBandLogic.reviewListsWord(counts: counts)
            // F4 (V18): حال قوائم الحسابات نفسها — فشلها «تعذّر التحميل ↻» بإعادة المحاولة (كان المربّع فارغاً بلا كلمة)
            let stores = [membersHealth, accountsHealth]
            return TileModel(state: word?.state, health: .combined(stores), retry: retryCensus, landing: word?.landing)
        case .occasions:
            // وفاة لم تُعلن ومجدول اليوم للمالك والمدير (`unannounced` فارغة لغيرهما)، والذكرى للجميع
            var stores = [membersHealth]
            if authVM.isAdmin { stores += [announcedHealth, scheduledHealth] }
            let word = AdminTodayLogic.occasionsWord(unannounced: unannounced.count,
                                                     scheduledToday: authVM.isAdmin ? scheduledToday : 0,
                                                     nextMemorial: nextMemorial)
            return TileModel(state: word.state, health: .combined(stores), retry: retryOccasions, landing: word.landing)
        case .metrics:
            guard authVM.adminSees(.metricsFamily) else { return TileModel() }
            // v2: «الراحلون 502» ← قسم «العائلة» حيث «متوفون 502» (F4، V16 — لا رقم من الرأس يتكرّر هنا)
            let word = AdminTodayBandLogic.departedWord(figures.totalDeceased)
            return TileModel(state: word?.state, health: censusHealth, retry: retryCensus, landing: word?.landing)
        case .team:
            // `today.system_status` (المالك): حال الدخول والأمان بكلمة — المدير يرى «للاطلاع» وحدها
            guard authVM.adminSees(.todaySystemStatus) else { return TileModel() }
            let seesSms = authVM.adminSees(.teamSms)
            let seesDevices = authVM.adminSees(.teamDevices)
            let seesRegistration = authVM.adminSees(.teamRegistration)
            var stores: [AdminStoreHealth] = []
            if seesSms { stores.append(sms.adminHealth) }
            if seesDevices { stores.append(devices.adminHealth) }
            if seesRegistration { stores.append(settingsHealth) }
            let settingsLoaded = appSettingsVM.settings.updatedAt != nil
            let word = AdminTodayLogic.teamWord(
                suspicious: seesSms ? suspicious : 0,
                smsLevel: seesSms ? sms.adminLevel.todayLevel : .unknown,
                devicesFailed: seesDevices ? (devices.stats?.invalid ?? 0) : 0,
                registrationOpen: seesRegistration && settingsLoaded ? appSettingsVM.settings.allowNewRegistrations : nil)
            return TileModel(state: word.state, health: stores.isEmpty ? nil : .combined(stores), retry: retryTeam)
        case .app:
            guard authVM.adminSees(.todaySystemStatus) else { return TileModel() }
            let s = appSettingsVM.settings
            let word = AdminTodayLogic.appWord(maintenance: s.maintenanceMode, notificationsPaused: s.notificationsPaused == true)
            return TileModel(state: word.state, health: settingsHealth, retry: retrySettings)
        }
    }

    /// «عرض الكل» في «ذكرى الراحلين» ← «المناسبات» على قسم الذكرى
    private var occasionsMemorials: (() -> Void)? {
        guard AdminArea.occasions.isVisible(for: authVM) else { return nil }
        return { openFromToday(.occasions, landing: .occasions(.memorials)) }
    }
}

/// يبني الصفحة عند ظهورها فقط (لا عند بناء اللوحة) — كانت كلها تُنسخ في مكدّس اللوحة فينغلق التطبيق (٢٠٢٦-١٠-٠٥)
struct AdminLazyPage: View {
    let make: () -> AnyView
    var body: some View { make() }
}

// MARK: - «صلاحياتي»

/// صفّ «صلاحياتي» في بطاقة (المدير والمراقب والمشرف): ما يقدر عليه دورك وما لا يقدر — يفتح `AdminMyScopeView`
private struct AdminScopeLink: View {
    let guide: RoleGuide

    var body: some View {
        NavigationLink {
            AdminLazyPage { AnyView(AdminMyScopeView(guide: guide).adminBackTitle(AdminArea.homeTitle)) }
        } label: {
            // صفّ صاحب الدور نفسه: «مجالك: …» (الغائب «مجاله: …» لصفحات «الأدوار» — F2)
            AdminListRow(icon: guide.icon, tint: guide.color, title: L10n.t("صلاحياتي", "My permissions"),
                         subtitle: guide.mandateForSelf)
                .padding(.horizontal, DS.Hub.cardPadding)
                .padding(.vertical, DS.Spacing.xxs)
        }
        // تظليل الصفّ يملأ البطاقة كلها (بزاويتيها)
        .buttonStyle(AdminRowPressStyle(bleed: 0))
        .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
        .adminCard(padding: 0)
    }
}

// MARK: - ربط المنطق الخالص بأنواع التطبيق

private extension AdminTodayLink.Home {
    var area: AdminArea {
        switch self {
        case .inbox:     return .inbox
        case .family:    return .family
        case .occasions: return .occasions
        case .metrics:   return .metrics
        case .team:      return .team
        case .app:       return .app
        }
    }
}

private extension AdminArea {
    var todayHome: AdminTodayLink.Home {
        switch self {
        case .inbox:     return .inbox
        case .family:    return .family
        case .occasions: return .occasions
        case .metrics:   return .metrics
        case .team:      return .team
        case .app:       return .app
        }
    }
}

private extension AdminTeamLogic.SmsLevel {
    var todayLevel: AdminTodaySmsLevel {
        switch self {
        case .unknown: return .unknown
        case .good:    return .good
        case .low:     return .low
        case .urgent:  return .urgent
        }
    }
}
