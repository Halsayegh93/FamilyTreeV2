// فحص منطق «الإحصاءات» (Views/Features/Admin/AdminInsightsArea.swift، الوحدة U15) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u15-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInsightsArea.swift tests/admin-redesign/U15/main.swift && /tmp/u15-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true
typealias L = AdminStatsLogic

// MARK: الظهور (Autoplan note 7)
let owner = L.Access.make(familyItem: true, approvalsItem: true, workflowOn: true)
check(L.sections(owner), [.family, .departed, .inApp, .growth, .ages, .roles, .tree, .outside, .approvals],
      "owner/admin: the «أ» order, approvals last")
let monitor = L.Access.make(familyItem: true, approvalsItem: false, workflowOn: true)
check(L.sections(monitor).contains(.approvals), false, "monitor: no approvals")
check(L.sections(monitor).count, 8, "monitor: the eight family sections")
let workflowOff = L.Access.make(familyItem: true, approvalsItem: true, workflowOn: false)
check(L.sections(workflowOff).contains(.approvals), false, "workflow off: no approvals section")
let approvalsOnly = L.Access.make(familyItem: false, approvalsItem: true, workflowOn: true)
check(L.sections(approvalsOnly), [.approvals], "family none + approvals read: approvals only")
let none = L.Access.make(familyItem: false, approvalsItem: false, workflowOn: true)
check(L.sections(none), [], "both none: no sections")
check(none.isEmpty, true, "both none → empty state")
check(L.empty(familyItem: false, approvalsItem: false, workflowOn: true), .noAccess, "empty: no access")
check(L.empty(familyItem: false, approvalsItem: true, workflowOn: false), .workflowOff, "empty: approvals but workflow off")
check(L.empty(familyItem: true, approvalsItem: false, workflowOn: false), nil, "family → not empty")
check(L.sections(owner, membersFailed: true), [.family, .approvals], "members failed: family error card + approvals")

// MARK: الهبوط
let all = L.sections(owner)
check(L.scrollTarget(explicit: nil, stored: .inApp, shown: all), .inApp, "stored landing scrolls to «في التطبيق»")
check(L.scrollTarget(explicit: .outside, stored: .inApp, shown: all), .outside, "explicit beats stored")
check(L.scrollTarget(explicit: nil, stored: .family, shown: all), nil, "«العائلة» = top, no scroll")
check(L.scrollTarget(explicit: .approvals, stored: nil, shown: L.sections(monitor)), nil, "hidden section ignored")
check(L.scrollTarget(explicit: nil, stored: nil, shown: all), nil, "no landing")

// MARK: T2 — ما يفتحه كل رقم
let oa = L.Viewer(family: true, womenPage: true, editMembers: true)
let m = L.Viewer(family: true, womenPage: false, editMembers: true)
check(L.destination(.ringTotal, viewer: oa), .none, "ring total: its home is this page (no chevron)")
// F5: فئات «مَن» في «العائلة»
check(L.destination(.ringMen, viewer: oa), .members(AdminMembersLanding(account: .all, life: .all, population: [.men])),
      "ring men → family {رجال}, filters cleared")
check(L.destination(.ringWomen, viewer: oa), .members(AdminMembersLanding(account: .all, life: .all, population: [.women])),
      "ring women (O/A) → family {نساء}, status all")
check(L.destination(.ringWomen, viewer: m), .womenTree, "ring women (M) → women tree")
check(L.destination(.estimate, viewer: m), .members(AdminMembersLanding(review: .living)), "≈ → still alive?")
check(L.destination(.living, viewer: oa), .none, "living: mixed, no chevron")
check(L.destination(.deceased, viewer: oa), .none, "deceased: mixed, no chevron")
check(L.destination(.deathIncomplete, viewer: oa), .deathDates, "no full death date → death dates page")
check(L.destination(.deathIncomplete, viewer: L.Viewer(family: true, womenPage: false, editMembers: false)), .none,
      "no full death date without canEditMembers → no chevron")
check(L.destination(.menAccounts, viewer: m), .members(AdminMembersLanding(account: .with, life: .alive)),
      "men with an account → family «لهم حساب + الأحياء»")
check(L.destination(.womenAccounts, viewer: oa), .women(AdminWomenLanding(status: .registered, branch: .all)),
      "women with an account (O/A) → registered women")
check(L.destination(.womenAccounts, viewer: m), .none, "women with an account (M) → no chevron")
check(L.destination(.withoutAccount, viewer: oa), .none, "without account: mixed, no chevron")
check(L.destination(.missingData, viewer: m), .missingData, "complete missing data → «بيانات ناقصة»")
for n in [L.Number.owners, .admins, .members, .monitors, .supervisors, .fathers, .largestFamily, .added, .addedThisMonth,
          .knownAges, .averageAge, .longestLife, .outsideWomen, .husbands, .daughtersSons, .approvals, .accountsTotal] {
    check(L.destination(n, viewer: oa), .none, "\(n.rawValue): no list with that count → no chevron")
}
check(L.destination(.outsideLiving, viewer: oa), .members(AdminMembersLanding(account: .all, life: .all, population: [.outside])),
      "50 outside (O/A) → family {خارج العائلة} (living only, F5)")
check(L.destination(.outsideDeceased, viewer: oa), .women(AdminWomenLanding(status: .deceased, branch: .outside)),
      "87 deceased outside (O/A) → outside branch, deceased")
check(L.destination(.outsideLiving, viewer: m), .none, "50 outside (M) → no chevron")
check(L.destination(.ringMen, viewer: L.Viewer(family: false, womenPage: false, editMembers: false)), .none,
      "no family area → nothing opens")
check(L.opens(.menAccounts, value: 123, viewer: oa), true, "123 opens")
check(L.opens(.menAccounts, value: 0, viewer: oa), false, "zero opens nothing")
check(L.opens(.menAccounts, value: nil, viewer: oa), false, "«—» opens nothing")

// MARK: التواريخ والأعمار
check(L.day("1950-07-03"), L.Day(year: 1950, month: 7, day: 3), "parse date")
check(L.day("2026-11-26T10:20:30.123Z"), L.Day(year: 2026, month: 11, day: 26), "parse timestamp prefix")
check(L.day("1350-01-01"), nil, "hijri-like year rejected")
check(L.day(""), nil, "blank")
check(L.day("1950-13-01"), nil, "bad month")
check(L.lifespan(birth: "1920-05-10", death: "1990-05-09"), 69, "birthday not reached → 69")
check(L.lifespan(birth: "1920-05-10", death: "1990-05-10"), 70, "birthday reached → 70")
check(L.lifespan(birth: "1920-05-10", death: "1990-01-01"), 69, "year-only death = 1 January")
check(L.lifespan(birth: "1990-01-01", death: "1980-01-01"), nil, "death before birth")
check(L.lifespan(birth: "1700-01-01", death: "1990-01-01"), nil, "over 120 = typo")
check(L.lifespan(birth: "1920-05-10", death: nil), nil, "no death date")
check(L.lifespans([]), L.Lifespans(), "no data → «—»")
check(L.lifespans([70, 81, 64]), L.Lifespans(count: 3, average: 72, longest: 81), "average rounded, longest")
check(L.AgeBand(age: 17), .under18, "17 → under 18")
check(L.AgeBand(age: 18), .from18, "18 → 18–29")
check(L.AgeBand(age: 44), .from30, "44 → 30–44")
check(L.AgeBand(age: 45), .from45, "45 → 45–59")
check(L.AgeBand(age: 60), .from60, "60 → 60+")
check(L.bands([5, 20, 31, 50, 70, 75]), [1, 1, 1, 1, 2], "band counts in natural order")
check(L.share(185, of: 2_362), 8, "8٪ known")
check(L.share(170, of: 2_489), 7, "7٪ in the app")
check(L.share(nil, of: 10), nil, "not loaded")

// MARK: جديد في الشجرة
let today = L.Day(year: 2026, month: 11, day: 26)
var created: [L.Day] = []
func add(_ n: Int, _ y: Int, _ mo: Int, _ d: Int) { for _ in 0..<n { created.append(L.Day(year: y, month: mo, day: d)) } }
add(13, 2026, 6, 4); add(3, 2026, 7, 9); add(6, 2026, 8, 2); add(5, 2026, 10, 1)
add(80, 2026, 11, 12); add(14, 2026, 11, 20)
add(9, 2025, 12, 1)   // before the window
let growth = L.growth(created: created, today: today)
check(growth.months.map(\.month), [6, 7, 8, 9, 10, 11], "six months, oldest first")
check(growth.months.map(\.count), [13, 3, 6, 0, 5, 94], "counts per month")
check(growth.total, 121, "121 added")
check(growth.current, 94, "94 this month")
check(growth.spike, 5, "November spike: mostly one day")
var spread: [L.Day] = []
for d in 1...28 { spread.append(contentsOf: Array(repeating: L.Day(year: 2026, month: 11, day: d), count: 3)) }
check(L.growth(created: spread + [L.Day(year: 2026, month: 10, day: 1)], today: today).spike, nil,
      "big month spread over many days → no import note")
check(L.growth(created: Array(repeating: L.Day(year: 2026, month: 11, day: 2), count: 10), today: today).spike, nil,
      "small month → no note")
let january = L.growth(created: [L.Day(year: 2025, month: 12, day: 5)], today: L.Day(year: 2026, month: 1, day: 3))
check(january.months.map(\.year), [2025, 2025, 2025, 2025, 2025, 2026], "window crosses the year")
check(january.months.map(\.month), [8, 9, 10, 11, 12, 1], "Aug … Jan")
check(january.months[4].count, 1, "December counted")

// MARK: النصوص
check(AdminStatsText.accounts(170), "170 لهم حساب", "«170 لهم حساب»")
check(AdminStatsText.ofLiving(2_489), "من 2,489 حياً في العائلة", "«من 2,489 حياً في العائلة»")
check(AdminStatsText.added(121), "121 أُضيفوا", "«121 أُضيفوا»")
check(AdminStatsText.thisMonth(94), "منهم 94 هذا الشهر", "«منهم 94 هذا الشهر»")
check(AdminStatsText.knownAges(185, of: 2_362), "نعرف عمر 185 فقط", "«نعرف عمر 185 فقط»")
check(AdminStatsText.livingMen(2_362, allKnown: false), "من 2,362 رجلاً حياً. الباقون بلا تاريخ ميلاد.", "living men line")
check(AdminStatsText.requests(41), "41 طلباً", "«41 طلباً»")
check(AdminStatsText.years(71), "71 سنة", "«71 سنة»")
check(AdminStatsText.outsideLiving(50), "50 حياً من خارج العائلة", "«50 حياً من خارج العائلة»")
check(AdminStatsText.title(.inApp), "في التطبيق", "section title")
check(AdminStatsText.note(.outside), "لا يُحسبون في الأرقام فوق", "section note")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
