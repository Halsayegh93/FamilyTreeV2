import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - «الإحصاءات» (كان «المؤشرات») — إعادة التصميم ٢٠٢٦-١١-٢٦، spec C.12، الوحدة U15
//
// جذر القسم هو صفحة «إحصاءات العائلة» نفسها (اتجاه المالك «أ»، `stats-filters-samples.html`) و«الموافقات» آخرها — حُذفت
// صفحة البطاقتين (spec E.14). الأقسام بالترتيب: العائلة · الراحلون · في التطبيق · جديد في الشجرة · الأعمار · الأدوار ·
// الشجرة · خارج العائلة · الموافقات، ثم «آخر تحديث 9:41».
//  • الصفحة `AdminAnalyticsView` (AdminAnalyticsView.swift) — الاسم باقٍ لمن يدفعها (`AdminToolCatalog` «metrics.family»،
//    رأس «العائلة»، «اليوم»)؛ هنا `AdminMetricsAreaView` = الصفحة نفسها جذراً للقسم (العنوان قائمة الأقسام).
//  • أدوات الرسم وقسم «الموافقات» في AdminInsightsReport.swift.
//  • الظهور (Autoplan note 7): أقسام العائلة بخانة `metrics.family`، و«الموافقات» بخانة `metrics.approvals` ومفتاح مسار
//    الموافقات معاً؛ من له «الموافقات» وحدها يرى «الموافقات» وحدها؛ لا هذه ولا تلك = بطاقة فارغة تقول لماذا.
//  • الهبوط `AdminStatsAnchor`: معامل `init` الصريح يغلب `AdminAreaRouter.take(.stats, hop:)`؛ الصفحة تُمرَّر إلى قسمه
//    («في التطبيق 170» و«خارج العائلة 50» في «اليوم» يفتحان القسم الذي عنوانه الرقم نفسه — Autoplan note 3).
//  • T2 «الرقم = القائمة»: الرقم بسهم يفتح قائمة أول عدد فيها يساويه (`AdminStatsLogic.destination`)؛ ما لا قائمة له بلا سهم.
//    حيث لا تستقبل القائمة فلتراً من الخارج، الصفّ يحمل عدد القائمة نفسها والرقم الأدق في سطره الثاني:
//    «بلا تاريخ وفاة كامل» = عدد صفحة «تواريخ الوفاة» (السنة فقط + بلا تاريخ)، و«بيانات ناقصة» = عدد قائمتها (منهم بلا ميلاد).
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u15-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInsightsArea.swift tests/admin-redesign/U15/main.swift && /tmp/u15-logic

// MARK: - ١) الظهور والهبوط (منطق خالص)

nonisolated enum AdminStatsLogic {
    /// ما يراه الدور في الصفحة
    struct Access: Equatable {
        /// أقسام العائلة (خانة `metrics.family`)
        var family: Bool
        /// «الموافقات» (خانة `metrics.approvals` + مسار الموافقات مفعّل)
        var approvals: Bool

        static func make(familyItem: Bool, approvalsItem: Bool, workflowOn: Bool) -> Access {
            Access(family: familyItem, approvals: approvalsItem && workflowOn)
        }

        var isEmpty: Bool { !family && !approvals }
    }

    /// أقسام الصفحة بترتيب «أ». `membersFailed` = فشل جلب الأعضاء بلا بيانات: يبقى «العائلة» وحده ببطاقة الخطأ وإعادة
    /// المحاولة (لا ثماني بطاقات خطأ متتالية)
    static func sections(_ access: Access, membersFailed: Bool = false) -> [AdminStatsAnchor] {
        var list: [AdminStatsAnchor] = []
        if access.family {
            list += membersFailed ? [.family] : [.family, .departed, .inApp, .growth, .ages, .roles, .tree, .outside]
        }
        if access.approvals { list.append(.approvals) }
        return list
    }

    /// لماذا الصفحة فارغة
    enum Empty: Equatable {
        /// لا «العائلة» ولا «الموافقات» لهذا الدور
        case noAccess
        /// «الموافقات» وحدها ومسار الموافقات مطفأ
        case workflowOff
    }

    static func empty(familyItem: Bool, approvalsItem: Bool, workflowOn: Bool) -> Empty? {
        guard Access.make(familyItem: familyItem, approvalsItem: approvalsItem, workflowOn: workflowOn).isEmpty else {
            return nil
        }
        return approvalsItem ? .workflowOff : .noAccess
    }

    /// القسم الذي تُمرَّر إليه الصفحة عند الفتح: الصريح يغلب المخزَّن، و«العائلة» أول الصفحة (لا تمرير)، والقسم غير الظاهر
    /// لهذا الدور يُتجاهل
    static func scrollTarget(explicit: AdminStatsAnchor?, stored: AdminStatsAnchor?,
                             shown: [AdminStatsAnchor]) -> AdminStatsAnchor? {
        guard let anchor = explicit ?? stored, anchor != .family, shown.contains(anchor) else { return nil }
        return anchor
    }

    // MARK: التواريخ

    /// يوم من نصّ «yyyy-MM-dd…» — السنة قبل ١٧٠٠ (سنة هجرية مكتوبة كميلادية، `DeceasedMemorial`) لا تُحسب
    struct Day: Equatable, Comparable {
        let year: Int
        let month: Int
        let day: Int

        static func < (a: Day, b: Day) -> Bool {
            (a.year, a.month, a.day) < (b.year, b.month, b.day)
        }
    }

    static let earliestYear = 1700
    /// أكبر عمر يُقبل (ما فوقه خطأ إدخال لا عمر)
    static let maxAge = 120

    static func day(_ raw: String?) -> Day? {
        guard let raw else { return nil }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              y >= earliestYear, (1...12).contains(m), (1...31).contains(d) else { return nil }
        return Day(year: y, month: m, day: d)
    }

    static func day(of date: Date, calendar: Calendar) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(year: c.year ?? earliestYear, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// السنوات الكاملة بين يومين — nil إن سبق الآخر الأول أو جاوز `maxAge`
    static func years(from start: Day, to end: Day) -> Int? {
        guard end >= start else { return nil }
        var n = end.year - start.year
        if (end.month, end.day) < (start.month, start.day) { n -= 1 }
        return (0...maxAge).contains(n) ? n : nil
    }

    /// العمر عند الوفاة (السنة وحدها = أول يناير — كما تُخزَّن)
    static func lifespan(birth: String?, death: String?) -> Int? {
        guard let b = day(birth), let d = day(death) else { return nil }
        return years(from: b, to: d)
    }

    // MARK: «الراحلون»

    struct Lifespans: Equatable {
        /// كم متوفى له تاريخا ميلاد ووفاة صالحان
        var count = 0
        var average: Int? = nil
        var longest: Int? = nil
    }

    static func lifespans(_ ages: [Int]) -> Lifespans {
        guard !ages.isEmpty else { return Lifespans() }
        let mean = Double(ages.reduce(0, +)) / Double(ages.count)
        return Lifespans(count: ages.count, average: Int(mean.rounded()), longest: ages.max())
    }

    // MARK: «الأعمار»

    /// فئات العمر بترتيبها الطبيعي (spec C.12)
    enum AgeBand: Int, CaseIterable {
        case under18, from18, from30, from45, from60

        init(age: Int) {
            switch age {
            case ..<18: self = .under18
            case ..<30: self = .from18
            case ..<45: self = .from30
            case ..<60: self = .from45
            default:    self = .from60
            }
        }

        /// «18–29» معزولة من اليسار لليمين داخل السطر العربي
        var title: String {
            switch self {
            case .under18: return L10n.t("أقل من 18", "Under 18")
            case .from18:  return "\u{2066}18–29\u{2069}"
            case .from30:  return "\u{2066}30–44\u{2069}"
            case .from45:  return "\u{2066}45–59\u{2069}"
            case .from60:  return L10n.t("60 فأكثر", "60 and over")
            }
        }

        /// للقارئ الصوتي («من 18 إلى 29»)
        var spoken: String {
            switch self {
            case .under18: return title
            case .from18:  return L10n.t("من 18 إلى 29", "18 to 29")
            case .from30:  return L10n.t("من 30 إلى 44", "30 to 44")
            case .from45:  return L10n.t("من 45 إلى 59", "45 to 59")
            case .from60:  return title
            }
        }
    }

    /// عدد كل فئة بترتيب `AgeBand.allCases`
    static func bands(_ ages: [Int]) -> [Int] {
        var counts = Array(repeating: 0, count: AgeBand.allCases.count)
        for age in ages { counts[AgeBand(age: age).rawValue] += 1 }
        return counts
    }

    // MARK: «جديد في الشجرة»

    struct Month: Equatable {
        let year: Int
        let month: Int
        var count: Int
        /// أكبر عدد أُضيف في يوم واحد من الشهر (لسطر «أغلبه استيراد دفعة واحدة»)
        var biggestDay: Int
    }

    struct Growth: Equatable {
        /// الأقدم أولاً — في العربية الأقدم يميناً
        var months: [Month]
        /// الشهر الشاذّ الذي أغلبه يوم واحد (استيراد دفعة) — nil = لا تعليق
        var spike: Int?

        var total: Int { months.reduce(0) { $0 + $1.count } }
        var current: Int { months.last?.count ?? 0 }
    }

    static let growthMonths = 6
    /// الشهر الشاذّ: ٢٠ فأكثر، وثلاثة أضعاف أكبر شهر غيره على الأقل، ونصفه أو أكثر في يوم واحد
    static let spikeMinimum = 20
    static let spikeRatio = 3
    static let spikeDayShare = 0.5

    /// آخر `months` أشهر حتى شهر `today` (الحالي آخرها) من أيام الإضافة
    static func growth(created: [Day], today: Day, months n: Int = growthMonths) -> Growth {
        var keys: [(year: Int, month: Int)] = []
        var y = today.year, m = today.month
        for _ in 0..<max(n, 1) {
            keys.append((y, m))
            m -= 1
            if m == 0 { m = 12; y -= 1 }
        }
        keys.reverse()
        var perMonth: [Int: Int] = [:]
        var perDay: [Int: Int] = [:]
        for d in created {
            perMonth[d.year * 100 + d.month, default: 0] += 1
            perDay[(d.year * 100 + d.month) * 100 + d.day, default: 0] += 1
        }
        var biggest: [Int: Int] = [:]
        for (key, count) in perDay {
            biggest[key / 100] = max(biggest[key / 100] ?? 0, count)
        }
        let months = keys.map { k -> Month in
            let key = k.year * 100 + k.month
            return Month(year: k.year, month: k.month, count: perMonth[key] ?? 0, biggestDay: biggest[key] ?? 0)
        }
        return Growth(months: months, spike: spikeIndex(months))
    }

    static func spikeIndex(_ months: [Month]) -> Int? {
        guard let top = months.indices.max(by: { months[$0].count < months[$1].count }) else { return nil }
        let peak = months[top]
        let others = months.indices.filter { $0 != top }.map { months[$0].count }.max() ?? 0
        guard peak.count >= spikeMinimum, peak.count >= spikeRatio * max(others, 1),
              Double(peak.biggestDay) >= spikeDayShare * Double(peak.count) else { return nil }
        return top
    }

    // MARK: النسب

    /// نسبة صحيحة بالتقريب، والجزئي بين ١ و٩٩ (نفس حساب الحلقات) — nil قبل الوصول أو لمقام صفر
    static func share(_ part: Int?, of whole: Int?) -> Int? {
        AdminCensusMath.livingShare(alive: part, of: whole)
    }

    // MARK: - ٢) T2: ما يفتحه كل رقم (منطق خالص)

    /// كل رقم في الصفحة
    enum Number: String, CaseIterable {
        // العائلة
        case ringTotal, ringMen, ringWomen, estimate, living, deceased
        // الراحلون
        case averageAge, longestLife, deathIncomplete
        // في التطبيق
        case accountsTotal, menAccounts, womenAccounts, withoutAccount
        // جديد في الشجرة
        case added, addedThisMonth
        // الأعمار
        case knownAges, missingData
        // الأدوار
        case owners, admins, monitors, supervisors, members
        // الشجرة
        case fathers, largestFamily
        // خارج العائلة
        case outsideLiving, outsideWomen, husbands, daughtersSons, outsideDeceased
        // الموافقات
        case approvals
    }

    /// ما يفتحه رقم — الصفحة تدفعه فوقها (الرجوع يعود إليها)
    enum Destination: Hashable {
        /// لا شيء (بلا سهم)
        case none
        /// «العائلة» بفلاترها (`AdminMembersPage`)
        case members(AdminMembersLanding)
        /// «نساء العائلة» بفلاترها (`AdminWomenPanel(landing:)`) — المالك والمدير
        case women(AdminWomenLanding)
        /// تبويب الشجرة على شجرة النساء — المراقب
        case womenTree
        /// «تواريخ الوفاة» (`DeathDatesCampaignPage`) — أول رقم فيها «بلا تاريخ كامل»
        case deathDates
        /// «بيانات ناقصة» (`AdminReviewListPage(.gaps)`) — رقمها عدد القائمة كاملة
        case missingData
    }

    /// من يشاهد: يرى «العائلة»، يرى صفحة «نساء العائلة» (المالك والمدير)، يعدّل الأعضاء
    struct Viewer: Equatable {
        var family: Bool
        var womenPage: Bool
        var editMembers: Bool
    }

    /// وجهة الرقم (spec C.12 بعد قاعدة T2): الرقم بسهم يفتح قائمة أول عدد فيها يساويه، وغيره بلا سهم.
    /// كل القوائم تحت «العائلة» — من لا يرى «العائلة» لا يُفتح له شيء
    static func destination(_ number: Number, viewer: Viewer) -> Destination {
        guard viewer.family else { return .none }
        switch number {
        case .ringTotal: return ring(.total, viewer)
        case .ringMen:   return ring(.men, viewer)
        case .ringWomen: return ring(.women, viewer)
        case .estimate:  return ring(.estimate, viewer)
        case .deathIncomplete:
            return viewer.editMembers ? .deathDates : .none
        case .menAccounts:
            return .members(AdminMembersLanding(account: .with, life: .alive))
        case .womenAccounts:
            return viewer.womenPage ? .women(AdminWomenLanding(status: .registered, branch: .all)) : .none
        case .missingData:
            return .missingData
        case .outsideLiving:
            return viewer.womenPage ? .women(AdminWomenLanding(status: .living, branch: .outside)) : .none
        case .outsideDeceased:
            return viewer.womenPage ? .women(AdminWomenLanding(status: .deceased, branch: .outside)) : .none
        // مختلطة أو بلا قائمة بعددها (أحياء/متوفون رجالاً ونساءً، «بلا حساب»، أجزاء «خارج العائلة»، الأدوار — صفحة الفريق
        // أول رقم فيها «المدراء» مالكون ومديرون معاً)
        case .living, .deceased, .averageAge, .longestLife, .accountsTotal, .withoutAccount, .added, .addedThisMonth,
             .knownAges, .owners, .admins, .monitors, .supervisors, .members, .fathers, .largestFamily,
             .outsideWomen, .husbands, .daughtersSons, .approvals:
            return .none
        }
    }

    /// حلقات «العائلة»: نفس عقد U6 (`AdminCensusRoutes`) على شاشة «الإحصاءات»
    private static func ring(_ number: AdminCensusNumber, _ viewer: Viewer) -> Destination {
        switch AdminCensusRoutes.destination(number, on: .stats, seesWomenPage: viewer.womenPage) {
        case .none, .stats:          return .none
        case .members(let landing):  return .members(landing)
        case .women(let landing):    return .women(landing)
        case .womenTree:             return .womenTree
        }
    }

    /// الرقم يُضغط: له وجهة، ووصل، وليس صفراً
    static func opens(_ number: Number, value: Int?, viewer: Viewer) -> Bool {
        destination(number, viewer: viewer) != .none && (value ?? 0) > 0
    }
}

// MARK: - ٣) النصوص (منطق خالص)

nonisolated enum AdminStatsText {
    static func title(_ anchor: AdminStatsAnchor) -> String {
        switch anchor {
        case .family:    return L10n.t("العائلة", "Family")
        case .departed:  return L10n.t("الراحلون", "The departed")
        case .inApp:     return L10n.t("في التطبيق", "In the app")
        case .growth:    return L10n.t("جديد في الشجرة", "New in the tree")
        case .ages:      return L10n.t("الأعمار", "Ages")
        case .roles:     return L10n.t("الأدوار", "Roles")
        case .tree:      return L10n.t("الشجرة", "The tree")
        case .outside:   return L10n.t("خارج العائلة", "Outside the family")
        case .approvals: return L10n.t("الموافقات", "Approvals")
        }
    }

    /// ملاحظة ١٣ رمادية في طرف العنوان (spec C.12)
    static func note(_ anchor: AdminStatsAnchor) -> String? {
        switch anchor {
        case .family:          return L10n.t("الحلقة = نسبة الأحياء", "Ring = living share")
        case .inApp:           return L10n.t("من الأحياء", "Of the living")
        case .growth:          return L10n.t("آخر 6 أشهر", "Last 6 months")
        case .ages, .roles:    return L10n.t("الرجال الأحياء", "Living men")
        case .outside:         return L10n.t("لا يُحسبون في الأرقام فوق", "Not counted above")
        case .approvals:       return L10n.t("آخر 30 يوماً", "Last 30 days")
        case .departed, .tree: return nil
        }
    }

    /// وصف الرأس (spec C.12)
    static func subtitle(_ access: AdminStatsLogic.Access) -> String? {
        if access.family {
            return L10n.t("أرقام اليوم. العائلة = رجال الشجرة ونساء العائلة.",
                          "Today's numbers. The family = the tree's men and the family's women.")
        }
        return access.approvals ? L10n.t("الموافقات · آخر 30 يوماً", "Approvals · last 30 days") : nil
    }

    static func number(_ n: Int?) -> String { AdminCensusText.number(n) }

    static func percent(_ n: Int) -> String { AdminCensusText.percent(n) }

    /// «170 لهم حساب»
    static func accounts(_ n: Int) -> String {
        guard L10n.isArabic else { return "\(AdminNumberText.grouped(n)) " + (n == 1 ? "has an account" : "have an account") }
        switch n {
        case 0:  return "لا أحد له حساب بعد"
        case 1:  return "واحد له حساب"
        case 2:  return "اثنان لهما حساب"
        default: return "\(AdminNumberText.grouped(n)) لهم حساب"
        }
    }

    /// «من 2,489 حياً في العائلة»
    static func ofLiving(_ n: Int) -> String {
        L10n.t("من \(AdminCensusText.living(n)) في العائلة", "of \(AdminNumberText.grouped(n)) living in the family")
    }

    /// «من 2,362» تحت «رجال لهم حساب»
    static func of(_ n: Int) -> String {
        L10n.t("من \(AdminNumberText.grouped(n))", "of \(AdminNumberText.grouped(n))")
    }

    /// «121 أُضيفوا»
    static func added(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 0 ? "None added" : "\(AdminNumberText.grouped(n)) added" }
        switch n {
        case 0:  return "لا إضافات"
        case 1:  return "أُضيف واحد"
        case 2:  return "أُضيف اثنان"
        default: return "\(AdminNumberText.grouped(n)) أُضيفوا"
        }
    }

    /// «منهم 94 هذا الشهر»
    static func thisMonth(_ n: Int) -> String {
        n == 0 ? L10n.t("لا أحد هذا الشهر", "None this month")
               : L10n.t("منهم \(AdminNumberText.grouped(n)) هذا الشهر", "\(AdminNumberText.grouped(n)) this month")
    }

    /// تعليق الشهر الشاذّ (spec A.11)
    static var spikeNote: String { L10n.t("أغلبه استيراد دفعة واحدة", "Mostly one bulk import") }

    /// «نعرف عمر 185 فقط»
    static func knownAges(_ known: Int, of living: Int) -> String {
        if known == 0 { return L10n.t("لا نعرف عمر أحد بعد", "No ages known yet") }
        if known >= living { return L10n.t("نعرف أعمارهم كلهم", "All ages known") }
        return L10n.t("نعرف عمر \(AdminNumberText.grouped(known)) فقط", "Only \(AdminNumberText.grouped(known)) ages known")
    }

    /// «من 2,362 رجلاً حياً. الباقون بلا تاريخ ميلاد.»
    static func livingMen(_ n: Int, allKnown: Bool) -> String {
        let men = L10n.isArabic
            ? AdminCensusText.counted(n, one: "رجل حيّ واحد", two: "رجلين حيّين", few: "رجال أحياء", many: "رجلاً حياً",
                                      single: "رجل حيّ")
            : "\(AdminNumberText.grouped(n)) living men"
        return allKnown ? L10n.t("من \(men).", "Of \(men).")
                        : L10n.t("من \(men). الباقون بلا تاريخ ميلاد.", "Of \(men). The rest have no birth date.")
    }

    /// «توزيع الـ185 المعروفين»
    static func knownSplit(_ n: Int) -> String {
        L10n.t("توزيع الـ\(AdminNumberText.grouped(n)) المعروفين", "How the \(AdminNumberText.grouped(n)) known split")
    }

    /// «71 سنة»
    static func years(_ n: Int) -> String {
        L10n.isArabic ? AdminCensusText.counted(n, one: "سنة واحدة", two: "سنتان", few: "سنوات", many: "سنة", single: "سنة")
                      : "\(n) " + (n == 1 ? "year" : "years")
    }

    /// «من 226 لهم تاريخ ميلاد ووفاة»
    static func lifespanBase(_ n: Int) -> String {
        L10n.t("من \(AdminNumberText.grouped(n)) لهم تاريخ ميلاد ووفاة", "From \(AdminNumberText.grouped(n)) with birth and death dates")
    }

    static var notEnoughDates: String { L10n.t("لا تواريخ كافية", "Not enough dates") }

    /// «50 حياً من خارج العائلة»
    static func outsideLiving(_ n: Int) -> String {
        L10n.t("\(AdminCensusText.living(n)) من خارج العائلة", "\(AdminNumberText.grouped(n)) living outside the family")
    }

    /// «41 طلباً»
    static func requests(_ n: Int) -> String {
        guard L10n.isArabic else { return "\(AdminNumberText.grouped(n)) " + (n == 1 ? "request" : "requests") }
        if n == 0 { return "لا طلبات في آخر 30 يوماً" }
        return AdminCensusText.counted(n, one: "طلب واحد", two: "طلبان", few: "طلبات", many: "طلباً", single: "طلب")
    }

    /// جملة صفّ للقارئ الصوتي: «رجال لهم حساب: 123، من 2,362. يفتح القائمة»
    static func spoken(_ title: String, value: String?, sub: String?, opens: Bool) -> String {
        var text = title
        if let value { text += L10n.t(": \(value)", ": \(value)") }
        if let sub { text += L10n.t("، \(sub)", ", \(sub)") }
        return opens ? text + ". " + AdminCensusText.opensList : text
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - ٤) جذر القسم

/// صفحة قسم «الإحصاءات» (`AdminAreaView(.metrics)`) = «إحصاءات العائلة» جذراً: العنوان قائمة الأقسام «الإحصاءات ⌄»،
/// والهبوط من «اليوم» يمرّ إليها (`AdminStatsAnchor`)
struct AdminMetricsAreaView: View {
    /// قسم يُفتح عليه — nil = هبوط «اليوم» المخزَّن إن وُجد، وإلا أول الصفحة
    var anchor: AdminStatsAnchor? = nil

    var body: some View {
        AdminAnalyticsView(anchor: anchor, isAreaRoot: true)
    }
}

#endif
