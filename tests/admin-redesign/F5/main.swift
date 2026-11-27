// فحص «مَن» داخل «تصفية» العائلة (الوحدة F5، طلب المالك ٢٠٢٦-١١-٢٦) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/f5-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminFilterKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersPeople.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInsightsArea.swift tests/admin-redesign/F5/main.swift \
//     && /private/tmp/claude-501/f5-logic
//
// ما يُفحص (f5-family-scope.md «Done when»): أعداد «مَن» = صفوف القائمة · الشريحة الافتراضية «رجال» · هبوط «اليوم»
// و«الإحصاءات» · المجموعات المخفية حين لا تنطبق · ترتيب الأقسام.
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true
typealias P = AdminPeopleLogic
typealias F = P.Filters

// MARK: - العيّنة: فرعان، ٤ رجال · ٣ نساء · ٣ من خارج العائلة (واحد متوفى — لا يُعدّ)

let a1 = UUID(), a2 = UUID(), b1 = UUID(), b2 = UUID()
let branchA: Set<UUID> = [a1, a2]
let branchB: Set<UUID> = [b1, b2]
let persons: [P.Person] = [
    // الرجال: المرساة = الرجل نفسه
    P.Person(population: .men, deceased: false, hasAccount: true, anchor: a1),     // 0
    P.Person(population: .men, deceased: false, hasAccount: false, anchor: a2),    // 1
    P.Person(population: .men, deceased: true, hasAccount: false, anchor: b1),     // 2
    P.Person(population: .men, deceased: false, hasAccount: true, anchor: b2),     // 3
    // النساء: المرساة = الأب
    P.Person(population: .women, deceased: false, hasAccount: true, anchor: a1),   // 4
    P.Person(population: .women, deceased: true, hasAccount: false, anchor: b1),   // 5
    P.Person(population: .women, deceased: false, hasAccount: false, anchor: nil), // 6 أبوها غير معروف
    // خارج العائلة: المرساة = قريبه من العائلة (الزوج، أو أبو الأم/الزوجة)
    P.Person(population: .outside, deceased: false, hasAccount: true, anchor: a2), // 7
    P.Person(population: .outside, deceased: false, hasAccount: false, anchor: b1), // 8
    P.Person(population: .outside, deceased: true, hasAccount: false, anchor: a1),  // 9 متوفى — خارج القائمة والأرقام
]
let everyone = Array(persons.indices)

/// نفس ما تفعله الصفحة: النطاق للفرع (والبحث قبله)، ثم العدد والأقسام من النطاق نفسه
func scope(_ s: F) -> P.Scope {
    let branch: Set<UUID>? = s.branch.map { $0 == a1 ? branchA : branchB }
    return P.scope(persons, candidates: everyone, branch: branch)
}
let loaded: Set<P.Population> = [.men, .women, .outside]
func count(_ s: F, sees: Bool = true, ready: Set<P.Population> = loaded, accountsReady: Bool = true) -> Int? {
    P.count(scope(s), s, seesOthers: sees, ready: ready, accountsReady: accountsReady)
}
func rows(_ s: F, sees: Bool = true) -> [P.Section] {
    P.sections(scope(s), persons: persons, s, seesOthers: sees, accountsReady: true)
}
func listed(_ s: F, sees: Bool = true) -> Int { rows(s, sees: sees).reduce(0) { $0 + $1.rows.count } }

// MARK: - الافتراضي: «رجال» شريحة عادية تُزال

check(F().people, [.men], "the page opens on {رجال}")
check(P.pageDefault, [.men], "page default = {رجال}")
let set = P.filterSet(seesOthers: true, result: { count($0) }, branchTitle: { _ in "فرع جاسم" },
                      subTitle: { $0 }, branchPicker: { _, _ in "picker" })
check(set.snapshot(F()).items.map(\.title), ["رجال"], "default shows as a normal removable chip «رجال»")
check(set.snapshot(F()).items.map(\.count), ["4"], "the default chip carries its count")
check(set.activeCount(F()), 1, "«تصفية» button counts the default pick")
if let men = set.snapshot(F()).items.first {
    let after = set.applying(men.remove, to: F())
    check(after.people, [], "✕ «رجال» → no pick")
    check(P.effective(after.people, seesOthers: true), [.men, .women, .outside], "no pick = all three")
    check(set.snapshot(after).result, 9, "all three: 4 men + 3 women + 2 living outside")
}
check(set.groups(F()).first?.id, "people", "«مَن» is the first group")
check(set.groups(F()).first?.title, "مَن", "«مَن» title")
check(set.groups(F()).first?.rows.map(\.title), ["رجال", "نساء", "خارج العائلة"], "«مَن» options in order")
check(set.groups(F()).first?.selection == .multiple, true, "«مَن» is multi-select")
check(set.allCount(set.groups(F())[0], in: F()), 9, "«الكل» in «مَن» = all three")
let monitorSet = P.filterSet(seesOthers: false, result: { count($0, sees: false) }, branchTitle: { _ in "" },
                             subTitle: { $0 }, branchPicker: { _, _ in "picker" })
check(monitorSet.groups(F()).map(\.id), ["account", "life", "branch"], "no women page (monitor) → no «مَن» group")
check(monitorSet.snapshot(F()).items.count, 0, "monitor: no default chip (men only, as before)")
check(count(F(people: [.women]), sees: false), 4, "monitor: a women pick still counts men only")

// MARK: - الأعداد = صفوف القائمة (T2)

let states: [F] = [
    F(), F(people: []), F(people: [.women]), F(people: [.outside]), F(people: [.men, .women]),
    F(people: [.women, .outside], accounts: [.with]), F(people: [], lives: [.deceased]),
    F(people: [], accounts: [.without], lives: [.alive]), F(people: [], branch: a1), F(people: [.women], branch: b1),
    F(people: [.outside], branch: a1), F(people: [.men, .outside], accounts: [.with, .without], branch: b1),
]
for (n, s) in states.enumerated() {
    check(count(s), listed(s), "state \(n): result count = rows in the list")
}
check(count(F(people: [.women])), 3, "{نساء} = every family woman, living and deceased (the old «امرأة» box)")
check(count(F(people: [.outside])), 2, "{خارج العائلة} = the living only (the old «46 حياً» box)")
check(count(F(people: [.men])), 4, "{رجال} = the men list (the old «رجل» box)")
let peopleGroup = set.groups(F(people: [], lives: [.alive]))[0]
check(peopleGroup.rows.map(\.count), [3, 2, 2], "«مَن» counts follow «الحالة»: living men/women/outside")
for row in peopleGroup.rows {
    var probe = F(people: [], lives: [.alive])
    row.select(&probe)
    check(row.count, listed(probe), "«مَن» option \(row.title) count = its rows")
}
let accountGroup = set.groups(F(people: [.women, .outside]))[1]
check(accountGroup.rows.map(\.count), [2, 3], "«الحساب» per population: women by linked account, outside by linked")

// MARK: - «الحالة» و«الفرع» لكل فئة

check(count(F(people: [.outside], lives: [.deceased])), 0, "outside is living-only: deceased outside never listed")
check(count(F(people: [.women], branch: a1)), 1, "women by their father's branch")
check(count(F(people: [.women], branch: b1)), 1, "women by their father's branch (B)")
check(count(F(people: [.outside], branch: a1)), 1, "outside by their family relative's branch")
check(count(F(people: [], branch: a1)), 4, "branch A: 2 men + 1 woman + 1 outside (unknown father is not in a branch)")
check(rows(F(people: [], branch: a1)).first(where: { $0.population == .women })?.rows, [4], "woman with no known father leaves a branch pick")

// MARK: - المجموعات المخفية حين لا تنطبق

check(set.groups(F(people: [.outside])).map(\.id), ["people", "account", "branch"],
      "{خارج العائلة} alone: «الحالة» hidden (living-only)")
check(set.groups(F(people: [.men, .outside])).map(\.id), ["people", "account", "life", "branch"],
      "men with outside: «الحالة» shown")
check(set.groups(F(people: [.men], sub: "noPush")).map(\.id), ["people", "account", "life", "branch", "list"],
      "«القائمة» (old men link) shows while men are picked")
check(set.groups(F(people: [.women], sub: "noPush")).map(\.id), ["people", "account", "life", "branch"],
      "«القائمة» hidden when men aren't picked")
var outsideOnly = F(people: [.men, .outside], lives: [.deceased])
if let menRow = set.groups(outsideOnly)[0].rows.first {
    outsideOnly = set.applying(menRow.select, to: outsideOnly)
}
check(outsideOnly.people, [.outside], "dropping «رجال» leaves {خارج العائلة}")
check(outsideOnly.lives, [], "a hidden group's picks are cleared — no chip left that can't be removed")
check(set.snapshot(outsideOnly).items.map(\.title), ["خارج العائلة"], "only the outside chip remains")
var noMen = F(people: [.men], sub: "noPush")
P.normalize(&noMen, seesOthers: true)
check(noMen.sub, "noPush", "men picked → the old list filter stays")
noMen.people = [.women]
P.normalize(&noMen, seesOthers: true)
check(noMen.sub, nil, "no men → the men-only list filter is dropped")

// MARK: - ترتيب الأقسام

check(rows(F(people: [.outside, .women, .men])).map(\.population), [.men, .women, .outside],
      "sections: «الرجال» · «النساء» · «خارج العائلة»")
check(rows(F(people: [.outside, .women])).map(\.population), [.women, .outside], "sections keep the order without men")
check(P.showsSections(F(people: [.men, .women]).people, seesOthers: true), true, "two populations → sections")
check(P.showsSections(F(people: [.women]).people, seesOthers: true), false, "one population → a plain list")
check(P.showsSections([], seesOthers: true), true, "no pick (all three) → sections")
check(P.showsSections([], seesOthers: false), false, "monitor → men only, no sections")
check(rows(F(people: []))[0].rows, [0, 1, 2, 3], "men rows keep the list order")
check(P.sectionTitle(.men), "الرجال", "section title men")
check(P.sectionTitle(.women), "النساء", "section title women")
check(P.sectionTitle(.outside), "خارج العائلة", "section title outside")

// MARK: - سطر الوصف والمعدود

check(P.caption(F(), seesOthers: true, branch: nil), "رجال", "caption: the default population")
check(P.caption(F(people: []), seesOthers: true, branch: nil), "كل العائلة", "caption: all three → «كل العائلة»")
check(P.caption(F(people: [.women, .men]), seesOthers: true, branch: nil), "رجال · نساء", "caption: the picked populations in order")
check(P.caption(F(), seesOthers: true, branch: "فرع جاسم"), "رجال · فرع جاسم", "caption: population and branch")
check(P.caption(F(people: []), seesOthers: true, branch: "فرع جاسم"), "فرع جاسم", "caption: branch alone")
check(P.caption(F(), seesOthers: false, branch: nil), "كل العائلة", "caption (monitor): as before")
check(P.noun(F(), seesOthers: true, 783), "رجل", "noun: men")
check(P.noun(F(people: [.women]), seesOthers: true, 262), "امرأةً", "noun: women 11–99")
check(P.noun(F(people: [.women]), seesOthers: true, 300), "امرأة", "noun: women hundreds")
check(P.noun(F(people: [.women]), seesOthers: true, 5), "نساء", "noun: women 3–10")
check(P.noun(F(people: []), seesOthers: true, 50), "فرداً", "noun: mixed → people")
check(P.noun(F(people: [.outside]), seesOthers: true, 2), "فردان", "noun: outside → people")

// MARK: - الترتيب: الفروع للرجال بلا تصفية أخرى ولا بحث

check(P.order(F(), seesOthers: true, searching: false), .alphabetical, "default: men A–Z (no branch sections, owner 2026-11-27)")
check(P.order(F(people: [.men, .women]), seesOthers: true, searching: false), .alphabetical, "population picks stay A–Z")
check(P.order(F(lives: [.alive]), seesOthers: true, searching: false), .alphabetical, "another filter → A–Z")
check(P.order(F(people: [.women]), seesOthers: true, searching: false), .alphabetical, "women alone → A–Z")
check(P.order(F(), seesOthers: true, searching: true), .relevance, "search → best match")

// MARK: - الهبوط: «اليوم» و«الإحصاءات» و الروابط القديمة

typealias R = AdminCensusRoutes
func landing(_ d: AdminCensusDestination) -> AdminMembersLanding? {
    if case .members(let l) = d { return l } else { return nil }
}
check(R.destination(.men, on: .today, seesWomenPage: true),
      .members(AdminMembersLanding(account: .all, life: .all, population: [.men])), "men ring → «العائلة» {رجال}")
check(R.destination(.women, on: .today, seesWomenPage: true),
      .members(AdminMembersLanding(account: .all, life: .all, population: [.women])), "women ring → «العائلة» {نساء}")
check(R.destination(.outside, on: .today, seesWomenPage: true),
      .members(AdminMembersLanding(account: .all, life: .all, population: [.outside])), "«خارج العائلة» link → {خارج العائلة}")
check(R.destination(.women, on: .today, seesWomenPage: false), .womenTree, "monitor: women ring → women tree (unchanged)")
check(R.destination(.outside, on: .today, seesWomenPage: false), .stats(.outside), "monitor: outside → stats (unchanged)")
check(R.destination(.women, on: .stats, seesWomenPage: true),
      .members(AdminMembersLanding(account: .all, life: .all, population: [.women])), "stats women ring → {نساء}")
for (number, want) in [(AdminCensusNumber.men, F(people: [.men])), (.women, F(people: [.women])),
                       (.outside, F(people: [.outside]))] {
    guard let l = landing(R.destination(number, on: .today, seesWomenPage: true)) else {
        check(false, true, "\(number) lands on «العائلة»")
        continue
    }
    let opened = F(AdminMembersLogic.opening(landing: l))
    check(opened, want, "\(number) landing → the right population chip, nothing else")
    check(set.snapshot(opened).items.count, 1, "\(number) landing → one chip")
}
// T2: الرقم في «اليوم» = أول عدد هناك
let figures = AdminCensusFigures(men: 4, menAlive: 3, women: 3, womenAlive: 2, outsideLiving: 2)
check(count(F(people: [.men])), figures.value(of: .men), "T2: men ring = {رجال} count")
check(count(F(people: [.women])), figures.value(of: .women), "T2: women ring = {نساء} count")
check(count(F(people: [.outside])), figures.value(of: .outside), "T2: outside link = {خارج العائلة} count")

typealias S = AdminStatsLogic
let oa = S.Viewer(family: true, womenPage: true, editMembers: true)
let mon = S.Viewer(family: true, womenPage: false, editMembers: true)
check(S.destination(.ringWomen, viewer: oa), .members(AdminMembersLanding(account: .all, life: .all, population: [.women])),
      "stats: women ring (O/A) → «العائلة» {نساء}")
check(S.destination(.ringWomen, viewer: mon), .womenTree, "stats: women ring (monitor) → women tree")
check(S.destination(.outsideLiving, viewer: oa), .members(AdminMembersLanding(account: .all, life: .all, population: [.outside])),
      "stats: «خارج العائلة» living → «العائلة» {خارج العائلة}")
check(S.destination(.outsideLiving, viewer: mon), .none, "stats: outside (monitor) → no arrow, as before")
check(S.destination(.outsideDeceased, viewer: oa), .women(AdminWomenLanding(status: .deceased, branch: .outside)),
      "stats: deceased outside keep the women page (not in «العائلة» — living only)")

check(AdminMembersLogic.opening(chip: "registered", sub: "all", womenOutside: true), AdminMembersLogic.Opening(people: [.outside]),
      "old womenOutside link → «العائلة» {خارج العائلة} (no page pushed)")
check(F(AdminMembersLogic.opening(landing: AdminMembersLanding(account: .with))).people, [.men],
      "landing without a population → page default {رجال}")
check(F(AdminMembersLogic.opening(landing: AdminMembersLanding(population: []))).people, [],
      "landing with an empty population → all three")
check(AdminMembersLanding(population: [.women]).overridden(by: AdminMembersLanding(account: .with)),
      AdminMembersLanding(account: .with, population: [.women]), "explicit fields keep the stored population")
check(AdminMembersLanding(population: [.women]).overridden(by: AdminMembersLanding(population: [.outside])).population,
      [.outside], "an explicit population wins")
var linked = F(AdminMembersLogic.opening(chip: "registered", sub: "all", womenOutside: false))
check(set.snapshot(linked).items.map(\.title), ["رجال", "لهم حساب", "الأحياء"], "old «مسجّلون» link: men + its two chips")
linked = F(AdminMembersLogic.opening(chip: "all", sub: "all", womenOutside: false))
check(linked, F(), "plain open = page default")

// MARK: - التحميل: «—» لا صفر

check(count(F(people: [.women]), ready: [.men]), nil, "women not loaded yet → «—»")
check(count(F(), ready: [.men]), 4, "men count needs no women data")
check(count(F(accounts: [.with]), accountsReady: false), nil, "men by account wait for the account lists")
check(count(F(people: [.women], accounts: [.with]), accountsReady: false), 1, "women by account need no men account lists")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
