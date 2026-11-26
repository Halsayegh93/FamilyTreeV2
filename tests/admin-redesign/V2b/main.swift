// فحص منطق جذر «العائلة» v2 (الوحدة V2-2، اتجاه «أ») — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/v2b-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift tests/admin-redesign/V2b/main.swift && /tmp/v2b-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = AdminMembersLogic
typealias R = AdminMembersLogic.ReviewList

// MARK: - سطر الوصف تحت «العائلة ⌄»

check(M.caption(branch: nil), "كل العائلة", "no branch filter → «كل العائلة»")
check(M.caption(branch: "فرع حسن"), "فرع حسن", "branch filter → the branch name")
check(M.caption(branch: "  "), "كل العائلة", "blank branch name → «كل العائلة»")

// MARK: - سطر النتيجة: مع التصفية أو البحث فقط (بلاهما الرقم نفسه في مربّع «رجل»)

check(M.showsResultLine(filtered: false, searching: false), false, "no filter, no search → no result line")
check(M.showsResultLine(filtered: true, searching: false), true, "a filter → result line")
check(M.showsResultLine(filtered: false, searching: true), true, "searching → result line")

// MARK: - «حياً» بعد رقم «خارج العائلة»

check(M.livingUnit, "حياً", "outside KPI unit is «حياً» (living only)")

// MARK: - الاسم: أول كلمتين عريضتان

let p = M.nameParts("ابراهيم احمد ابراهيم حسين حسن محمدعلي حسن المحمدعلي")
check(p.lead, "ابراهيم احمد", "lead = first two words")
check(p.rest, "ابراهيم حسين حسن محمدعلي حسن المحمدعلي", "rest = everything after them")
check(M.nameParts("سلمان"), M.NameParts(lead: "سلمان", rest: ""), "one-word name → lead only")
check(M.nameParts("  ابراهيم   سلمان  محمدعلي "), M.NameParts(lead: "ابراهيم سلمان", rest: "محمدعلي"),
      "extra spaces collapse")
check(M.nameParts(""), M.NameParts(lead: "", rest: ""), "empty name → empty parts («بلا اسم» in the view)")

// MARK: - «5 قوائم»: عدد القوائم التي فيها أحد (قوائم لا أشخاص)

check(M.reviewListCount([12, 41, 363, 7, 1_800, 0]), 5, "five busy lists of six → 5")
check(M.reviewListCount([0, 0, 0, 0, 0, 0]), 0, "all clear → 0")
check(M.reviewListCount([nil, 41, nil, 0, nil, nil]), 1, "unknown counts are not busy")

check(M.listsText(1), "قائمة واحدة", "1 → «قائمة واحدة»")
check(M.listsText(2), "قائمتان", "2 → «قائمتان»")
check(M.listsText(5), "5 قوائم", "5 → «5 قوائم»")
check(M.listsText(6), "6 قوائم", "6 → «6 قوائم»")
check(M.listsText(11), "11 قائمةً", "11 → «11 قائمةً»")
check(M.listsText(100), "100 قائمة", "100 → «100 قائمة»")

// MARK: - سطرا البطاقة

check(M.reviewLine(R("تواريخ وفاة ناقصة", 363)), "363 تواريخ وفاة ناقصة", "noun list: number first")
check(M.reviewLine(R("هل ما زالوا أحياء؟", 41)), "هل ما زالوا أحياء؟ 41", "question list: question first")
check(M.reviewLine(R("بيانات ناقصة", 2_177)), "2,177 بيانات ناقصة", "thousands are grouped")

// ترتيب صفحة «يحتاج مراجعتك»: مشكلات · أحياء؟ · تواريخ الوفاة (تتصدّر) · ناقصة · لم يفتحوا · لم يدخلوا
func hub(_ c: [Int?]) -> [R] {
    let titles = ["مشكلات في الشجرة", "هل ما زالوا أحياء؟", "تواريخ وفاة ناقصة", "بيانات ناقصة",
                  "لم يفتحوا التطبيق بعد", "لم يدخلوا منذ 21 يوماً"]
    return zip(titles, c).enumerated().map { R($0.element.0, $0.element.1, leads: $0.offset == 2) }
}

// العيّنة (dir-a): 363 تواريخ وفاة ناقصة / هل ما زالوا أحياء؟ · 5 قوائم — «لم يفتحوا» بالآلاف لا تتصدّر
check(M.reviewState(hub([0, 41, 363, 120, 2_177, 9]), accountsFailed: false),
      .card(M.ReviewCard(first: "363 تواريخ وفاة ناقصة", second: "هل ما زالوا أحياء؟", lists: 5)),
      "mock: death-date backlog leads, next list in hub order second, «5 قوائم»")
check(M.reviewState(hub([4, 41, 363, 120, 2_177, 9]), accountsFailed: false),
      .card(M.ReviewCard(first: "363 تواريخ وفاة ناقصة", second: "مشكلات في الشجرة", lists: 6)),
      "tree problems take the second line when present")
check(M.reviewState(hub([4, 41, 0, 120, 2_177, 9]), accountsFailed: false),
      .card(M.ReviewCard(first: "4 مشكلات في الشجرة", second: "هل ما زالوا أحياء؟", lists: 5)),
      "no death-date backlog → first busy list in hub order leads (not the biggest)")
check(M.reviewState(hub([0, 0, 7, 0, 0, 0]), accountsFailed: false),
      .card(M.ReviewCard(first: "7 تواريخ وفاة ناقصة", second: nil, lists: 1)), "one busy list → one sub line")
check(M.reviewState(hub([0, 9, 0, 0, 0, 3]), accountsFailed: false),
      .card(M.ReviewCard(first: "هل ما زالوا أحياء؟ 9", second: "لم يدخلوا منذ 21 يوماً", lists: 2)),
      "a question list leading keeps the question first")
check(M.reviewState(hub([0, 0, 0, 0, 0, 0]), accountsFailed: false), .hidden, "all lists empty → card hidden")
check(M.reviewState(hub([nil, nil, nil, nil, nil, nil]), accountsFailed: false), .loading,
      "nothing arrived → skeleton (never «تعذّر التحميل»)")
check(M.reviewState(hub([0, 0, 0, 0, nil, nil]), accountsFailed: false), .loading,
      "tree lists empty, accounts lists still loading → skeleton")
check(M.reviewState(hub([0, 0, 0, 0, nil, nil]), accountsFailed: true), .hidden,
      "accounts failed and the rest are zero → hidden (as v1)")
check(M.reviewState(hub([0, 41, 363, 0, nil, nil]), accountsFailed: false),
      .card(M.ReviewCard(first: "363 تواريخ وفاة ناقصة", second: "هل ما زالوا أحياء؟", lists: nil)),
      "lines show before the accounts lists arrive; the «N قوائم» pill waits (skeleton)")
check(M.reviewState(hub([0, 41, 363, 0, nil, nil]), accountsFailed: true),
      .card(M.ReviewCard(first: "363 تواريخ وفاة ناقصة", second: "هل ما زالوا أحياء؟", lists: 2)),
      "accounts failed → the pill counts what arrived")

// الحبّة والكلمة على مربّع «العائلة» في «اليوم» رقم واحد
let counts: [Int?] = [0, 41, 363, 120, 2_177, 9]
if case .card(let c) = M.reviewState(hub(counts), accountsFailed: false) {
    check(c.lists, M.reviewListCount(counts), "pill number = reviewListCount (the «اليوم» tile's «5 قوائم للمراجعة»)")
} else {
    check(false, true, "expected a card")
}

// MARK: - الإنجليزية

L10n.isArabic = false
check(M.caption(branch: nil), "The whole family", "EN caption")
check(M.listsText(5), "5 lists", "EN lists")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
