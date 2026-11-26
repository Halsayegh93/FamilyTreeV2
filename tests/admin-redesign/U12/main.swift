// فحص منطق صفحات «العائلة» الفرعية (الوحدة U12: «يحتاج مراجعتك» و«نساء العائلة») — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u12-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminReviewHubPage.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminWomenPanel.swift tests/admin-redesign/U12/main.swift && /tmp/u12-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

// MARK: - «يحتاج مراجعتك»

typealias H = AdminReviewHubLogic

check(H.look(nil), H.Look(text: "—", dim: true, opens: true, isEmpty: false), "hub: not loaded = «—», still opens")
check(H.look(0), H.Look(text: "0", dim: true, opens: false, isEmpty: true), "hub: zero = grey «0», no chevron, «لا شيء»")
check(H.look(2177), H.Look(text: "2,177", dim: false, opens: true, isEmpty: false), "hub: number with thousands separator")
check(H.look(41).text, "41", "hub: small number")

let allZero = Dictionary(uniqueKeysWithValues: H.List.allCases.map { ($0, 0) })
check(H.isAllClear(allZero), true, "hub row hidden when every list is zero")
var missingOne = allZero
missingOne[.inactive] = nil
check(H.isAllClear(missingOne), false, "hub row stays while a list has not loaded")
var oneBusy = allZero
oneBusy[.problems] = 4
check(H.isAllClear(oneBusy), false, "hub row shows when one list has members")

check(H.treeAndData + H.accounts, H.List.allCases, "hub: the two cards cover every list once")
check(H.accounts.allSatisfy(\.isUsage), true, "hub: «الحسابات» = usage lists")
check(H.treeAndData.contains { $0.isUsage }, false, "hub: «الشجرة والبيانات» has no usage list")

L10n.isArabic = true
let busy: [H.List: Int] = [.problems: 0, .living: 41, .death: 134, .gaps: 2177, .notOpened: 12, .inactive: 9]
check(H.summary(busy), "هل ما زالوا أحياء؟ · تواريخ وفاة ناقصة · و3 قوائم", "summary: two names then the rest")
check(H.summary([.gaps: 5]), "بيانات ناقصة", "summary: one list")
check(H.summary([.gaps: 5, .living: 2, .problems: 1]), "مشكلات في الشجرة · هل ما زالوا أحياء؟ · وقائمة أخرى",
      "summary: one more list")
check(H.summary(allZero), nil, "summary: nothing busy")
check(H.moreLists(2), "وقائمتان", "more lists: dual")
check(H.moreLists(4), "و4 قوائم", "more lists: plural 3–10")
check(H.moreLists(11), "و11 قائمةً", "more lists: 11+")

// MARK: - «نساء العائلة»

typealias W = AdminWomenLogic
typealias F = W.Filters

// العائلة: ٥ نساء (٣ حيّات منهن مسجّلة ومتزوجتان، ٢ متوفيات منهن متزوجة)؛ خارج العائلة: ٤ أحياء (ابن بنت مسجّل، زوج،
// امرأتان إحداهما متزوجة) و٢ متوفيان
let facts: [W.Fact] = [
    W.Fact(registered: true, married: true),
    W.Fact(married: true),
    W.Fact(),
    W.Fact(deceased: true, married: true),
    W.Fact(deceased: true),
    W.Fact(registered: true, outside: true),
    W.Fact(married: true, outside: true),
    W.Fact(married: true, outside: true),
    W.Fact(outside: true),
    W.Fact(deceased: true, outside: true),
    W.Fact(deceased: true, married: true, outside: true),
]

check(W.pageDefault, F(status: .living, branch: .family, order: .alphabetical), "women: page opens on «الحيّات»")
check(W.count(facts, W.pageDefault), 3, "women: living family women")
check(W.count(facts, F(status: .all)), 5, "women: «262 امرأة» total = every family woman (T2)")
check(W.count(facts, F(status: .living)) + W.count(facts, F(status: .deceased)), W.count(facts, F(status: .all)),
      "women: header «حية» + «متوفاة» = total")
check(W.count(facts, F(status: .registered)), 1, "women: registered")
check(W.count(facts, F(status: .married)), 3, "women: married (living + deceased)")
check(W.count(facts, F(status: .deceased)), 2, "women: deceased")

// فرع خارج العائلة: الأحياء في القائمة (= رقم «خارج العائلة»)، والمتوفون في قسمهم
check(W.count(facts, F(status: .living, branch: .outside)), 4, "outside: list = living outside (census number, T2)")
check(W.count(facts, F(status: .all, branch: .outside)), 4, "outside: «الكل» keeps the deceased in their own section")
check(facts.filter { W.inOutsideDeceased($0, F(status: .living, branch: .outside)) }.count, 2,
      "outside: collapsed deceased section")
check(facts.filter { W.inOutsideDeceased($0, F(status: .deceased, branch: .outside)) }.count, 0,
      "outside: no section when the list is the deceased")
check(W.count(facts, F(status: .deceased, branch: .outside)), 2, "outside: «متوفيات» lists the deceased")
check(W.count(facts, F(status: .married, branch: .outside)), 2, "outside: married stays living-only")
check(facts.filter { W.inOutsideDeceased($0, W.pageDefault) }.count, 0, "family branch: no outside section")
check(W.count(facts, F(status: .all, branch: .family)) + W.count(facts, F(status: .all, branch: .outside))
      + facts.filter { W.inOutsideDeceased($0, F(status: .all, branch: .outside)) }.count, facts.count,
      "every row is shown exactly once across the two branches")

// الهبوط
check(W.filters(landing: nil), W.pageDefault, "landing: none = page default")
check(W.filters(landing: AdminWomenLanding(status: .all, branch: .all)), F(status: .all, branch: .family),
      "landing: from a total sets «الحالة» = الكل (Autoplan note 3)")
check(W.filters(landing: AdminWomenLanding(branch: .outside)), F(status: .living, branch: .outside),
      "landing: outside branch keeps the living default")
check(W.filters(landing: AdminWomenLanding(status: .deceased)), F(status: .deceased), "landing: deceased")
check(W.filters(landing: AdminWomenLanding(status: .registered)).status, .registered, "landing: registered")
check(W.filters(landing: AdminWomenLanding(status: .married)).status, .married, "landing: married")
let stored = AdminWomenLanding(status: .registered, branch: .outside)
check(W.filters(landing: stored.overridden(by: AdminWomenLanding(status: .all))), F(status: .all, branch: .outside),
      "landing: explicit init field wins over the stored landing")

// «الأحدث»
let now = Date(timeIntervalSince1970: 1_800_000_000)
let day: TimeInterval = 86_400
let dates: [Date?] = [now - 40 * day, nil, now - 2 * day, now - 10 * day, nil, now - 2 * day]
check(W.newestOrder(dates), [2, 5, 3, 0, 1, 4], "newest: newest first, ties and undated keep their order")
check(W.recentCount(dates, now: now), 3, "newest: added or linked within 30 days")
check(W.recentCount([], now: now), 0, "newest: none")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
