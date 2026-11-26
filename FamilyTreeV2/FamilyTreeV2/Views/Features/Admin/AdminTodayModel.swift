import SwiftUI
import Supabase

// MARK: - بيانات «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ — الصفحة الأولى تجيب «وش يحتاجني الآن؟»؛ إعادة التصميم U7 ٢٠٢٦-١١-٢٦)
//
// كل رقم هنا من بيانات محمّلة أصلاً في التطبيق (الطلبات، مسار الموافقات ٢، الرسائل، الأعضاء) أو من دوال
// قراءة موجودة على السيرفر (النشطون الآن، تقرير الموافقات، رصيد رسائل الدخول) — بلا أي دالة جديدة. ما لا
// يتوفّر لا يُرسم (لا أرقام مختلقة). مجال كل دور كما في «الوارد» (`AdminAllRequestsView.tabsForRole`).
// منطق الكلمات وسطر التحية الخالص في AdminTodayLogic.swift. الأنواع المشتركة التي كانت في AdminTodayPager.swift
// (`AdminHeaderIcon`، `AdminFamilyStats`، `AdminFamilyStatsPage.aliveText/deceasedText`) نُقلت آخر هذا الملف بأسمائها.

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
/// صار كلمتي مربّعي «الفريق والأمان» و«التطبيق»)، ويبقى البيت لمسار `AdminReviewDestination.status(_)` وحده (spec B.6)
struct AdminStatusPill {
    enum Home: Hashable { case maintenance, sms, scheduled, devices }
}

extension AdminStatusPill.Home {
    /// صفحة البيت (كانت `AdminSystemStatusLine.page`): الصيانة ← «التطبيق» (مجموعة «التشغيل»)، الرصيد ← «رسائل رمز
    /// الدخول»، المجدول ← «المناسبات» (القادم)، الأجهزة ← «الأجهزة ووصول الإشعارات»
    var page: AnyView {
        let today = L10n.t("اليوم", "Today")
        switch self {
        case .maintenance: return AnyView(AdminAppAreaPage().adminArea(.app))
        case .sms:         return AnyView(AdminSmsView(backTitle: today).adminArea(.team))
        case .scheduled:   return AnyView(AdminOccasionsPage().adminArea(.occasions).adminBackTitle(today))
        case .devices:     return AnyView(AdminPushHealthView().adminArea(.team).adminBackTitle(today))
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
}


// MARK: - قراءات إضافية من دوال موجودة (لا شيء جديد على السيرفر)

enum AdminTodayFetch {
    /// من دخل التطبيق ولو مرة (`get_members_last_signin` — المالك والمدير والمراقب). لأبناء البنات في «خارج العائلة»:
    /// قوائم «استخدام التطبيق» تستبعدهم على السيرفر. nil إن تعذّر الجلب
    static func signedInIds() async -> Set<UUID>? {
        struct Row: Decodable { let member_id: UUID }
        guard let rows: [Row] = try? await SupabaseConfig.client
            .rpc("get_members_last_signin").execute().value else { return nil }
        return Set(rows.map(\.member_id))
    }

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

    /// عدد من يستخدم التطبيق الآن (`get_active_members_now` — المالك والمدير)
    static func activeNowCount() async -> Int? {
        struct Row: Decodable { let member_id: UUID }
        do {
            let response = try await SupabaseConfig.client.rpc("get_active_members_now").execute()
            let rows = try JSONDecoder().decode([Row].self, from: response.data)
            return Set(rows.map(\.member_id)).count
        } catch {
            return nil
        }
    }

    /// المنجز هذا الأسبوع من «تقرير الموافقات» (نُفّذ + رُفض خلال ٧ أيام) — nil إن لم يتوفّر
    static func weeklyDone() async -> (executed: Int, rejected: Int)? {
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let to = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -7, to: to) else { return nil }
        let iso = ISO8601DateFormatter()
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

/// زرّ رأس «اليوم» العاري — كأزرار رؤوس التبويبات (جرس الرئيسية و«عن التطبيق»): رمز أبيض بلمس ٤٤، وعدد أحمر على
/// ركنه (جرس «إشعارات الإدارة»)
struct AdminHeaderIcon: View {
    let symbol: String
    var count: Int = 0

    var body: some View {
        Image(dsSymbol: symbol)
            .dsGlyph(DS.Glyph.xxl, weight: .semibold)
            .foregroundStyle(DS.Color.headerGlyph)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    AdminTileBadge(kind: .count(count), ring: DS.Color.bandFill)
                        .offset(x: L10n.isArabic ? -AdminTileMetrics.badgeOffset : AdminTileMetrics.badgeOffset,
                                y: -AdminTileMetrics.badgeOffset)
                }
            }
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - «إحصائيات العائلة» القديمة (كانت الصفحة الثانية من مربّع «اليوم» — بقي ما يقرؤه غيرها)

/// أعداد العائلة من البيانات المحمّلة أصلاً — نفس تعريفات «إحصاء الأفراد» (`AdminMemberCounts`)، والفروع = أبناء رأس
/// الشجرة المباشرون، و«هذا الشهر» = من قُيّد في الشجرة هذا الشهر. nil = لم يُعرف بعد («—»)
@available(*, deprecated, message: "use AdminCensusFigures.make(census:members:women:); U21 removes")
struct AdminFamilyStats: Equatable {
    var counts = AdminMemberCounts()
    var branches: Int? = nil
    var joinedThisMonth: Int? = nil
    /// «خارج العائلة» — نفس تعريف `AdminFamilyCensus`
    var outsideMale: Int? = nil
    var outsideFemale: Int? = nil
    var outsideTotal: Int? { outsideMale.flatMap { m in outsideFemale.map { m + $0 } } }

    @MainActor
    static func make(members all: [FamilyMember]) -> AdminFamilyStats {
        var s = AdminFamilyStats()
        s.counts = AdminMemberCounts.seeded(members: all)
        guard !all.isEmpty else { return s }
        let census = AdminFamilyCensus.make(members: all, women: WomenStore.cache)
        s.outsideMale = census.outsideMale
        s.outsideFemale = census.outsideFemale

        let tree = all.filter { $0.role != .pending }
        if let root = BranchPickerSheet.familyRoot(in: tree) {
            s.branches = tree.filter { $0.fatherId == root.id && $0.hasName && !$0.isWomanAccount }.count
        }
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        s.joinedThisMonth = all.filter { m in
            guard m.hasName, let created = ApprovalWorkflow.date(m.createdAt) else { return false }
            return created >= monthStart
        }.count
        return s
    }
}

/// نصوص «إحصائيات العائلة» القديمة — بطاقتها حُذفت من «اليوم» (spec E.1/E.3)، وبقيت النصوص لمن يقرؤها
/// (`AdminMembersHeader`) حتى U21
enum AdminFamilyStatsPage {
    /// «2,582 حياً» (حيّ واحد، حيّان، 3 أحياء) — «≈» إن كانوا تقديريين
    @available(*, deprecated, message: "use AdminCensusText.living(_:); U21 removes")
    static func aliveText(_ n: Int?, estimated: Bool) -> String {
        guard let n else { return L10n.t("— أحياء", "— living") }
        let text = L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "حيّ واحد", two: "حيّان", few: "أحياء", many: "حياً", single: "حيّ")
            : "\(n) living"
        return estimated ? "≈ " + text : text
    }

    /// «557 متوفى» (متوفى واحد، متوفيان، 3 متوفين)
    @available(*, deprecated, message: "use AdminCensusText.deceased(_:); U21 removes")
    static func deceasedText(_ n: Int?) -> String {
        guard let n else { return L10n.t("— متوفون", "— deceased") }
        return L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "متوفى واحد", two: "متوفيان", few: "متوفين", many: "متوفى", single: "متوفى")
            : "\(n) deceased"
    }
}
