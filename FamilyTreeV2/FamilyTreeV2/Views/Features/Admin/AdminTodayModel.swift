import SwiftUI
import Supabase

// MARK: - بيانات «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ — الصفحة الأولى تجيب «وش يحتاجني الآن؟»؛ إعادة التصميم U7 ٢٠٢٦-١١-٢٦)
//
// كل رقم هنا من بيانات محمّلة أصلاً في التطبيق (الطلبات، مسار الموافقات ٢، الرسائل، الأعضاء) أو من دوال
// قراءة موجودة على السيرفر (تقرير الموافقات، رصيد رسائل الدخول) — بلا أي دالة جديدة. ما لا
// يتوفّر لا يُرسم (لا أرقام مختلقة). مجال كل دور كما في «الوارد» (`AdminAllRequestsView.tabsForRole`).
// منطق الكلمات وسطر التحية الخالص في AdminTodayLogic.swift. زرّ الرأس `AdminHeaderIcon` (كان في AdminTodayPager.swift)
// آخر هذا الملف.

/// أرقام كلمات «الوارد» في «اليوم» (بانتظارك · عاجل · متأخر · رسائل) — نفس تعريف فلاتر «الوارد»
struct AdminTodayCounts: Equatable {
    var waiting = 0
    var urgent = 0
    var late = 0
    var unreadMessages = 0
    var pendingMessages = 0
    /// كل ما في قائمة «الوارد» لهذا الدور (= «كل الطلبات» فيه — بلا طلبات الخصوصية، بابها مستقل)
    var inboxTotal = 0
    /// طلبات الخصوصية المعلّقة (باب «طلبات الخصوصية · N بانتظار الرد» في «الوارد») — لا تُضاف إلى `waiting` (F1، T2)
    var policy = 0
}

/// بيوت إشارات «حالة النظام» السابقة (الصيانة · الرصيد · المجدول · بلا إشعارات). السطر ولوحته حُذفا (spec E.2 — حالها
/// صار كلمة مربّع «التطبيق والنظام» — الدخول والأجهزة فيه منذ ٢٠٢٦-١١-٢٨)، ويبقى البيت لمسار `AdminReviewDestination.status(_)` وحده (spec B.6)
struct AdminStatusPill {
    enum Home: Hashable { case maintenance, sms, scheduled, devices }
}

extension AdminStatusPill.Home {
    /// صفحة البيت (كانت `AdminSystemStatusLine.page`): الصيانة ← «التطبيق» (مجموعة «التشغيل»)، الرصيد ← «رسائل رمز
    /// الدخول»، المجدول ← «المناسبات» (القادم)، الأجهزة ← «الأجهزة ووصول الإشعارات»
    var page: AnyView {
        // يُدفع من «اليوم» — الرجوع باسم رأسه «الإدارة»
        let today = AdminArea.homeTitle
        switch self {
        case .maintenance: return AnyView(AdminAppAreaPage().adminArea(.app))
        case .sms:         return AnyView(AdminSmsView(backTitle: today).adminArea(.app))
        case .scheduled:   return AnyView(AdminOccasionsPage().adminArea(.occasions).adminBackTitle(today))
        case .devices:     return AnyView(AdminPushHealthView().adminArea(.app).adminBackTitle(today))
        }
    }
}

/// «إحصاء الأفراد» أعلى «اليوم» — نفس تعريفات بطاقة «أفراد العائلة» القديمة (قبل إعادة التصميم):
/// الرجال = شجرة العائلة بلا المعلّقين، النساء = إناث شجرة النساء (جدولها يضمّ مرايا الرجال)، الأفراد = مجموعهما؛
/// والحسابات المفعّلة = «فعّال» في «استخدام التطبيق» (رقم وجهاز — فعّال + خامل، تعريف المالك). nil = لم يُعرف بعد.
struct AdminMemberCounts: Equatable {
    var men: Int? = nil
    var menAlive: Int? = nil
    var women: Int? = nil
    var womenAlive: Int? = nil
    var accounts: Int? = nil
    /// كل الأحياء في «استخدام التطبيق» (مقام نسبة الحسابات)
    var living: Int? = nil
    /// الأحياء المسجّل لهم رقم (دخلوا أو لا) — حلقة «المستخدمين» في «اليوم»
    var withPhone: Int? = nil
    /// لهم رقم وما دخلوا التطبيق أبداً
    var neverLogged: Int? = nil
    /// لم يفتحوا التطبيق ٢١ يوماً أو أكثر (`idle`) — خارج حلقة «المستخدمين» (طلب المالك ٢٠٢٦-١١-١٢)
    var idle: Int? = nil

    /// حلقة «المستخدمين»: من فتح التطبيق بلا المنقطعين ٢١ يوماً، والعدد = هؤلاء + من لم يفتحه بعد
    /// حلقة «المستخدمين» تبقى على «استخدام التطبيق» (كل من فتح التطبيق برقم) — لا تتأثر بتعريف «المسجّلون» للعائلة
    var usersOpened: Int? { usageAccounts.flatMap { a in idle.map { a - $0 } } }
    var usersTotal: Int? { withPhone.flatMap { w in idle.map { w - $0 } } }
    /// مرشّحو «تحقق من الأحياء» (كبار السن بلا وفاة مسجّلة) — قبل استبعاد ما راجعه المستخدم «حي ✓» على جهازه.
    /// ما دام منهم من لم يُراجَع فأحياء الرجال والإجمالي «تقديري»
    var oldLiving: Set<UUID>? = nil

    var total: Int? {
        guard let men, let women else { return nil }
        return men + women
    }

    var totalAlive: Int? {
        guard let menAlive, let womenAlive else { return nil }
        return menAlive + womenAlive
    }

    var menDeceased: Int? { men.flatMap { m in menAlive.map { m - $0 } } }
    var womenDeceased: Int? { women.flatMap { w in womenAlive.map { w - $0 } } }
    var totalDeceased: Int? { total.flatMap { t in totalAlive.map { t - $0 } } }

    /// الرجال من أعضاء الشجرة المحمّلة
    @MainActor
    mutating func setMen(from all: [FamilyMember]) {
        guard !all.isEmpty else { return }
        var total = 0, alive = 0
        // سجلّ بلا اسم (رقم دخول بلا اسم) ليس فرداً في العائلة — `FamilyMember.hasName`؛
        // وحساب المرأة (`isWomanAccount`) ليس رجلاً — تُعدّ مرة واحدة بعقدتها في شجرة النساء (`setWomen`)
        // وابن البنت (`DaughterSonsIndex`) ليس من شجرة الرجال — بيته شجرة النساء
        let sons = DaughterSonsIndex.shared.ids
        for m in all where m.role != .pending && m.hasName && !m.isWomanAccount && !sons.contains(m.id) {
            total += 1
            if m.isDeceased != true { alive += 1 }
        }
        men = total
        menAlive = alive
        // نفس معيار شريحة «تحقق من الأحياء» (ومن له حساب دخول حيّ قطعاً — حين وصلت قوائم الحسابات)
        let accounts = AdminAccountsStore.shared
        oldLiving = Set(AdminLivingCheck.candidates(all, hasLogin: accounts.loaded ? { accounts.info($0) != nil } : nil).keys)
    }

    /// `excluding`: نساء «خارج العائلة» (`is_outside_family`) — يُعددن في حلقة «خارج العائلة» لا هنا
    mutating func setWomen(_ rows: [FamilyMember], excluding: Set<UUID> = []) {
        guard !rows.isEmpty else { return }
        let females = rows.filter { $0.isFemale && $0.hasName && !excluding.contains($0.id) }
        women = females.count
        womenAlive = females.filter { $0.isDeceased != true }.count
    }

    /// «المسجّلون» بتعريف العائلة الواحد (طلب المالك ٢٠٢٦-١١-٢٦ «رتب الارقام عدل بالمسجلين و غير مسجلين و تحقق من
    /// الكل»): رجال الشجرة الأحياء لهم حساب دخول (`AdminAccountsStore` — نفس فلتر «لديهم حساب» في «العائلة») + نساء العائلة
    /// الأحياء المربوطات بحساب (نفس «مسجّلات» في قسم النساء). بلا «خارج العائلة» ولا السجلّات بلا اسم. كان من
    /// «استخدام التطبيق» وحده: يعدّ حسابات النساء كلها (ومنهن من خارج العائلة) ولا يعدّ النساء بلا حساب في «بدون حساب».
    /// قبل وصول قوائم الحسابات يبقى الرقم السابق.
    @MainActor
    mutating func setFamilyAccounts(members all: [FamilyMember]) {
        let store = AdminAccountsStore.shared
        guard store.loaded, !all.isEmpty else { return }
        let sons = DaughterSonsIndex.shared.ids
        let men = all.filter {
            $0.role != .pending && $0.hasName && !$0.isWomanAccount && !sons.contains($0.id)
                && $0.isDeceased != true && store.info($0.id) != nil
        }.count
        let outside = WomenStore.outsideFamilyIds
        let linked = WomenStore.linkedUserByWoman
        let women = WomenStore.cache.filter {
            $0.isFemale && $0.hasName && !outside.contains($0.id) && $0.isDeceased != true && linked[$0.id] != nil
        }.count
        menAccounts = men
        womenAccounts = women
        accounts = men + women
        if let alive = totalAlive { living = alive }
    }

    /// لهم حساب حسب «استخدام التطبيق» (قبل تعريف العائلة) — لحلقة «المستخدمين»
    var usageAccounts: Int? = nil
    /// المسجّلون من الرجال ومن نساء العائلة (الأحياء) — `setFamilyAccounts`
    var menAccounts: Int? = nil
    var womenAccounts: Int? = nil
    /// «بدون حساب» من الأحياء = الأحياء ناقص المسجّلين (رجالاً ونساءً)
    var menWithoutAccount: Int? { menAlive.flatMap { a in menAccounts.map { max(0, a - $0) } } }
    var womenWithoutAccount: Int? { womenAlive.flatMap { a in womenAccounts.map { max(0, a - $0) } } }
    var withoutAccount: Int? { menWithoutAccount.flatMap { m in womenWithoutAccount.map { m + $0 } } }

    mutating func setUsage(_ u: AppUsageStats?) {
        guard let u else { return }
        // «الأعضاء المسجّلون» = لهم حساب دخول (نفس شريحة «مسجّلون» في العائلة)
        accounts = u.active + u.idle + u.loginNoDevice
        usageAccounts = accounts
        living = u.active + u.idle + u.loginNoDevice + u.neverLogged + u.noPhone
        withPhone = u.active + u.idle + u.loginNoDevice + u.neverLogged
        neverLogged = u.neverLogged
        idle = u.idle
    }

    /// أعداد البداية من آخر ما حُمّل (الشجرة، كاش شجرة النساء، آخر «استخدام التطبيق») — بلا طلب جديد
    @MainActor
    static func seeded(members: [FamilyMember]) -> AdminMemberCounts {
        var c = AdminMemberCounts()
        c.setMen(from: members)
        // نساء العائلة بلا «خارج العائلة» — نفس `AdminFamilyCensus.make` (٢٠٢٦-١١-٢٦)
        c.setWomen(WomenStore.cache, excluding: WomenStore.outsideFamilyIds)
        c.setUsage(AppUsageStats.cached)
        c.setFamilyAccounts(members: members)
        return c
    }
}

// MARK: - نصوص مشتركة

enum AdminTodayText {
    /// «صباح الخير» قبل الظهر، «مساء الخير» بعده
    static func greeting(_ date: Date = Date()) -> String {
        Calendar.current.component(.hour, from: date) < 12
            ? L10n.t("صباح الخير", "Good morning") : L10n.t("مساء الخير", "Good evening")
    }

    /// «الثلاثاء 20 أكتوبر» — ميلادي بالأرقام اللاتينية (نفس تواريخ التطبيق)
    static func dayLine(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    /// «منذ ٣ س» / «منذ يومين» — nil بلا تاريخ
    static func since(_ date: Date?) -> String? {
        guard let date else { return nil }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return L10n.t("منذ \(max(minutes, 1)) د", "\(max(minutes, 1))m ago") }
        let hours = minutes / 60
        if hours < 24 { return L10n.t("منذ \(hours) س", "\(hours)h ago") }
        return L10n.t("منذ \(days(hours / 24))", "\(hours / 24)d ago")
    }

    /// «يوم» / «يومين» / «٣ أيام» / «١٢ يوماً»
    static func days(_ n: Int) -> String {
        switch n {
        case ...1:   return L10n.t("يوم", "1 day")
        case 2:      return L10n.t("يومين", "2 days")
        case 3...10: return L10n.t("\(n) أيام", "\(n) days")
        default:     return L10n.t("\(n) يوماً", "\(n) days")
        }
    }

    /// العدد ومعدوده بالعربية: ١ و٢ بلا رقم («جهاز»، «جهازان»)، ٣–١٠ جمع، ١١–٩٩ مفرد منصوب، وغيرها مفرد
    static func arabicCount(_ n: Int, one: String, two: String, few: String, many: String, single: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        switch n % 100 {
        case 3...10:  return "\(n) \(few)"
        case 11...99: return "\(n) \(many)"
        default:      return "\(n) \(single)"
        }
    }

    /// «متأخر يومين» — من بداية مرحلته
    static func late(_ flow: ApprovalSnapshot?) -> String {
        guard let since = flow?.stageSince ?? flow?.createdAt else { return L10n.t("متأخر", "Late") }
        let d = Int(Date().timeIntervalSince(since) / 86_400)
        if d < 1 { return L10n.t("متأخر", "Late") }
        return d == 1 ? L10n.t("متأخر يوماً", "Late 1 day") : L10n.t("متأخر \(days(d))", "Late \(days(d))")
    }
}

// MARK: - المصدر

@MainActor
enum AdminTodayFeed {

    /// لقطات المسار في مجال الدور (المشرف: البلاغات، المراقب: الباقي)
    static func scopedSnapshots(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [ApprovalSnapshot] {
        let all = adminRequestVM.allApprovalSnapshots
        if authVM.isAdmin { return all }
        if authVM.currentUser?.role == .supervisor {
            return all.filter { ApprovalWorkflow.specialistRole(for: $0.requestType) == .supervisor }
        }
        return all.filter { ApprovalWorkflow.specialistRole(for: $0.requestType) == .monitor }
    }

    // MARK: الأرقام

    /// أرقام كلمات مربّع «الوارد» وسطر التحية — نفس تعريف فلاتر «الوارد» (`AdminInboxLogic`): المسار شغّال = بانتظارك ·
    /// عاجل · متأخر من لقطات مجال الدور؛ مطفأ = كل ما في قائمة «الوارد» لدورك بانتظارك (`inboxTotal` = «كل الطلبات» فيه —
    /// `reviewRequestsTotal(includePolicy: false)`)، بلا عاجل ولا متأخر. طلبات الخصوصية رقمها وحدها (`policy`)
    static func counts(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel, inboxTotal: Int) -> AdminTodayCounts {
        var c = AdminTodayCounts()
        // «الرسائل» لمن يراها في جدول السيرفر فقط (`inbox.messages`)
        let seesMessages = authVM.adminSees(.inboxMessages)
        c.unreadMessages = seesMessages ? adminRequestVM.unreadContactMessagesCount : 0
        c.pendingMessages = seesMessages ? adminRequestVM.pendingContactMessagesCount : 0
        c.inboxTotal = inboxTotal
        // نفس شرط باب «طلبات الخصوصية» في «الوارد» (الجلب نفسه مقصور على ما يعالجه الدور)
        c.policy = adminRequestVM.policyRequestsCount
        if adminRequestVM.approvalsWorkflowOn {
            let flows = scopedSnapshots(authVM: authVM, adminRequestVM: adminRequestVM)
            c.waiting = flows.filter(adminRequestVM.isApprovalWaitingForMe).count
            c.urgent = flows.filter(\.isUrgent).count
            c.late = flows.filter { $0.isLate || $0.isEscalated }.count
        } else {
            c.waiting = inboxTotal
        }
        return c
    }

    // MARK: عدد الجرس (v2 — ما يحتاج إجراء الآن وحده)

    /// الطلبات المعلّقة الآن — نفس `AdminNotificationsPage.openRequestIds` حرفياً (الإشعار «يحتاج إجراء» ما دام طلبه هنا)،
    /// فيساوي الجرس شريحة «يحتاج إجراء N» في الصفحة
    /// - pendingContent: الديوانيات وعناصر المكتبة وصور المعرض المعلّقة (`AdminPendingContentStore` — F4، V34)
    static func openRequestIds(adminRequestVM vm: AdminRequestViewModel, newsVM: NewsViewModel,
                               projectsVM: ProjectsViewModel, memberVM: MemberViewModel,
                               pendingContent: Set<UUID> = []) -> Set<UUID> {
        var ids = pendingContent
        for list in [vm.deceasedRequests, vm.childAddRequests, vm.newsReportRequests, vm.photoSuggestionRequests,
                     vm.nameChangeRequests, vm.treeEditRequests, vm.joinApprovalRequests] {
            ids.formUnion(list.map(\.id))
        }
        ids.formUnion(vm.phoneChangeRequests.map(\.id))
        ids.formUnion(vm.relativeAddRequests.map(\.id))
        ids.formUnion(vm.relativeRemoveRequests.map(\.id))
        ids.formUnion(vm.contactMessages.filter { $0.status == ApprovalStatus.pending.rawValue }.map(\.id))
        ids.formUnion(newsVM.pendingNewsRequests.map(\.id))
        ids.formUnion(projectsVM.pendingProjects.map(\.id))
        for m in memberVM.allMembers where m.role == .pending { ids.insert(m.id) }
        return ids
    }

    /// إشعارات الإدارة بما يحتاجه عدد الجرس (`AdminTodayBandLogic.bellCount`) — التصنيف الواحد `AdminNotices.category`
    static func bellNotices(_ notifications: [AppNotification], me: UUID?) -> [AdminBellNotice] {
        notifications.compactMap { n in
            guard let category = AdminNotices.category(of: n, me: me) else { return nil }
            return AdminBellNotice(
                category: category,
                read: n.read,
                requestId: AdminNotices.requestId(of: n),
                suspicious: n.kind == AdminNotices.smsSuspicious,
                // «تمت إضافة ابن · راجعه» وللابن ملف (`applySelfChild` في الصفحة يشترطه)
                selfChildReview: category == .changes && n.details?.selfChild == true && n.details?.review == true
                    && n.subjectMemberId != nil,
                contactMessage: n.kind == NotificationKind.contactMessage.rawValue)
        }
    }
}


// MARK: - قراءات إضافية من دوال موجودة (لا شيء جديد على السيرفر)

enum AdminTodayFetch {
    // (F2) حُذف `signedInIds` (`get_members_last_signin`) و`activeNowCount` (`get_active_members_now`) بلا نداء باقٍ:
    // «خارج العائلة» الأحياء وحدهم بلا عدد حسابات، و«N الآن» ليس في التصميم الجديد («الاستخدام» يجلب قائمته بنفسه)

    /// الوفيات المعلن عنها — nil إن تعذّر الجلب (فلا يظهر تنبيه «لم يُعلن عنها» خطأً)
    static func announcedDeathIds() async -> Set<UUID>? {
        struct Row: Decodable { let member_id: UUID }
        await refreshDeathAlertDays()
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("death_announcements").select("member_id").execute().value
            return Set(rows.map(\.member_id))
        } catch {
            return nil
        }
    }

    /// `app_settings.death_alert_days` (١–٣٠) ← `DeathRecency.alertDays`؛ يبقى ما كان إن تعذّرت القراءة
    private static func refreshDeathAlertDays() async {
        struct Row: Decodable { let death_alert_days: Int? }
        guard let rows: [Row] = try? await SupabaseConfig.client
            .from("app_settings").select("death_alert_days").limit(1).execute().value,
              let days = rows.first?.death_alert_days else { return }
        DeathRecency.alertDays = min(max(days, 1), DeathRecency.days)
    }

    /// المنجز هذا الأسبوع من «تقرير الموافقات» (نُفّذ + رُفض خلال ٧ أيام) — nil إن لم يتوفّر
    static func weeklyDone() async -> (executed: Int, rejected: Int)? {
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let to = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -7, to: to) else { return nil }
        let iso = DateParsing.isoPlain
        do {
            let report: ApprovalsReport = try await SupabaseConfig.client
                .rpc("approvals_report", params: Params(p_from: iso.string(from: from), p_to: iso.string(from: to)))
                .execute().value
            return (report.totals.executed, report.totals.rejected)
        } catch {
            return nil
        }
    }
}

// MARK: - مقاسات «اليوم» (كانت في AdminTodayPager.swift)

enum AdminTodayMetrics {
    /// لون الرأس خلف أعلى التمرير — السحب للتحديث يكشف كحلياً لا أبيض
    static let pullReveal: CGFloat = 260
    /// مهلة إعادة جلب مخازن المربّعات (ثوانٍ) — السحب للتحديث يتجاوزها. `SmsBalanceStore` و`AdminDeviceReachStore`
    /// و`AdminAccountsStore` لها مهلتها نفسها في مخزنها
    static let refetchAfter: TimeInterval = 60
}

// MARK: - أزرار الرأس (يقرؤها `AdminAnnounceComposer` أيضاً)

/// زرّ رأس «اليوم» — v2 (الاتجاه «أ»، V2-1): دائرة زجاجية ٤٤ (لمسها كاملة) برمز أبيض مفرّغ، وعلى ركن الجرس شارة ذهبية
/// صغيرة بنصّ كحلي = ما يحتاج إجراء الآن (`AdminTodayBandLogic.bellCount`) — لا أحمر ولا غير المقروء
struct AdminHeaderIcon: View {
    let symbol: String
    var count: Int = 0

    var body: some View {
        Image(dsSymbol: symbol)
            .dsGlyph(DS.Glyph.xl, weight: .medium)
            .foregroundStyle(DS.Color.headerGlyph)
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .background(Circle().fill(DS.Hub.glass))
            .overlay(Circle().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
            .overlay(alignment: .topTrailing) {
                if let badge = AdminTodayBandLogic.bellBadge(count) {
                    Text(verbatim: badge)
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.bandFill)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, DS.Spacing.xs)
                        .frame(minWidth: DS.Hub.bellBadgeGold, minHeight: DS.Hub.bellBadgeGold)
                        .background(Capsule().fill(DS.Color.accentLight))
                        .overlay(Capsule().strokeBorder(DS.Color.bandFill, lineWidth: DS.Border.widthBold))
                        .offset(x: L10n.isArabic ? -DS.Spacing.xxs : DS.Spacing.xxs, y: -DS.Spacing.xxs)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Circle())
    }
}
