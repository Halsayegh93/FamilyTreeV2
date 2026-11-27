// فحص منطق «أسماء مكررة» في «المكرر والأخطاء» (Views/Features/Admin/AdminDuplicateNames.swift، الوحدة N1) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/n1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminDuplicateNames.swift tests/admin-redesign/N1/main.swift && /tmp/n1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias D = AdminDuplicateNames
func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
func p(_ id: Int, _ parent: Int?, _ name: String) -> D.Person { D.Person(id: uid(id), parent: parent.map(uid), firstName: name) }

// MARK: المفتاح بعد التطبيع

check(D.key("جمانة"), D.key("جمانه"), "ة at end = ه")
check(D.key("أحمد"), D.key("احمد"), "أ = ا")
check(D.key("إبراهيم"), D.key("ابراهيم"), "إ = ا")
check(D.key("آمنة"), D.key("امنه"), "آ = ا and ة = ه")
check(D.key("مصطفى"), D.key("مصطفي"), "ى = ي")
check(D.key("عبد الله"), D.key("عبدالله"), "spaces ignored")
check(D.key("  علي "), D.key("علي"), "trim")
check(D.key("عَلِيّ"), D.key("علي"), "tashkeel ignored")
check(D.key("حسن") == D.key("حسين"), false, "حسن ≠ حسين")
check(D.key("محمد") == D.key("محمود"), false, "محمد ≠ محمود")

// MARK: التجميع

let people = [
    p(1, 100, "بدر"), p(2, 100, "بدر"), p(3, 100, "سالم"),         // أخوان بنفس الاسم
    p(4, 200, "جمانة"), p(5, 200, "جمانه"),                          // بعد التطبيع
    p(6, 300, "علي"), p(7, 301, "علي"),                              // أبوان مختلفان — ليسا مكرّرين
    p(8, nil, "وليد"), p(9, nil, "وليد"),                            // بلا أب — لا تجميع
    p(10, 400, ""), p(11, 400, "  "),                                // بلا اسم — مشكلة «بلا اسم» لا «مكرر»
    p(12, 500, "حسين"), p(13, 500, "حسين"), p(14, 500, "حسين"),      // ثلاثة
]
let g = D.groups(people)
check(g.count, 3, "three groups")
check(g.map { Set($0.ids) }.contains(Set([uid(1), uid(2)])), true, "بدر group")
check(g.map { Set($0.ids) }.contains(Set([uid(4), uid(5)])), true, "جمانة/جمانه group")
check(g.map { Set($0.ids) }.contains(Set([uid(12), uid(13), uid(14)])), true, "حسين ×3 group")
check(g.contains { $0.ids.contains(uid(6)) }, false, "different fathers not grouped")
check(g.contains { $0.ids.contains(uid(8)) }, false, "no father not grouped")
check(g.contains { $0.ids.contains(uid(10)) }, false, "empty names not grouped")
check(g.first { $0.ids.contains(uid(1)) }?.parent, uid(100), "group keeps father id")
check(g.first { $0.ids.contains(uid(1)) }?.name, "بدر", "group shows the first spelling")
check(g.first { $0.ids.contains(uid(4)) }?.ids, [uid(4), uid(5)], "ids keep input order")
check(D.groups(people).map(\.id), g.map(\.id), "stable order")
check(Set(g.map(\.id)).count, g.count, "unique ids")

// MARK: استبعاد (عقد الرجال المنسوخة في شجرة النساء)

let excluded = D.groups(people, excluding: [uid(2)])
check(excluded.contains { $0.ids.contains(uid(1)) }, false, "mirrored man excluded breaks the pair")
check(excluded.count, 2, "two groups after exclusion")

// MARK: «ليسا مكرّرين»

let badr = g.first { $0.ids.contains(uid(1)) }!
let dismissed = D.groups(people, dismissed: [badr.signature])
check(dismissed.count, 2, "dismissed group hidden")
check(dismissed.contains { $0.ids.contains(uid(1)) }, false, "dismissed بدر gone")
check(badr.signature, D.Group.signature(parent: uid(100), ids: [uid(2), uid(1)]), "signature ignores order")
// ثالث بنفس الاسم يُضاف بعد الإخفاء: المجموعة تعود (توقيع آخر)
let more = people + [p(15, 100, "بدر")]
check(D.groups(more, dismissed: [badr.signature]).contains { $0.ids.contains(uid(15)) }, true, "new member brings group back")


// MARK: «أرقام بدون أسماء» — دخلوا برمز الدخول ولم يكملوا التسجيل

func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
    var cal = Calendar(identifier: .gregorian); cal.timeZone = D.kuwait
    return cal.date(from: c)!
}
let cands = [
    D.Candidate(id: uid(20), name: "", pending: true, hasLogin: true, created: day(2026, 11, 18)),
    D.Candidate(id: uid(21), name: "  ", pending: true, hasLogin: true, created: day(2026, 11, 25)),
    D.Candidate(id: uid(22), name: "سالم", pending: true, hasLogin: true, created: day(2026, 11, 25)),   // له اسم
    D.Candidate(id: uid(23), name: "", pending: false, hasLogin: true, created: day(2026, 11, 25)),      // مفعّل
    D.Candidate(id: uid(24), name: "", pending: true, hasLogin: false, created: day(2026, 11, 25)),      // بلا دخول
    D.Candidate(id: uid(25), name: "بدون اسم", pending: true, hasLogin: true, created: nil),
]
let nameless = D.nameless(cands)
check(nameless, [uid(21), uid(20), uid(25)], "blank/«بدون اسم» + pending + login, newest first, undated last")
check(D.registeredLine(day(2026, 11, 25)), "سُجّل في 25 نوفمبر", "registered line")
check(D.registeredLine(day(2026, 1, 3)), "سُجّل في 3 يناير", "registered line January")
check(D.registeredLine(nil), nil, "no date → no line")

// MARK: عدد المدخل

check(D.entryCount(duplicates: 0, problems: 0, nameless: 0), 0, "nothing")
check(D.entryCount(duplicates: 5, problems: 12, nameless: 9), 26, "sum of the three lists")
check(D.entryCount(duplicates: 5, problems: nil, nameless: 9), 14, "problems not ready yet")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
