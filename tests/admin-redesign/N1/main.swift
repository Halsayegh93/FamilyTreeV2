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
func cand(_ id: Int, full: String = "", first: String = "", pending: Bool = true, memberRole: Bool = true,
          father: Bool = false, review: Bool = false, login: Bool = true, created: Date?) -> D.Candidate {
    D.Candidate(id: uid(id), fullName: full, firstName: first, pending: pending, memberRole: memberRole,
                hasFather: father, isReview: review, hasLogin: login, created: created)
}
let cands = [
    cand(20, created: day(2026, 11, 18)),
    cand(21, full: "  ", first: " ", created: day(2026, 11, 25)),
    cand(22, full: "سالم", created: day(2026, 11, 25)),                    // له اسم كامل
    cand(26, first: "سالم", created: day(2026, 11, 25)),                   // له اسم أول — السيرفر لا يحذفه
    cand(23, pending: false, created: day(2026, 11, 25)),                  // مفعّل
    cand(24, login: false, created: day(2026, 11, 25)),                    // بلا دخول
    cand(27, memberRole: false, created: day(2026, 11, 25)),               // مشرف/مدير
    cand(28, father: true, created: day(2026, 11, 25)),                    // مربوط بأب
    cand(29, review: true, created: day(2026, 11, 25)),                    // حساب المراجعة
    cand(30, full: "بدون اسم", created: day(2026, 11, 25)),                // نص «بدون اسم» ليس فارغاً على السيرفر
    cand(25, created: nil),
]
let nameless = D.nameless(cands)
check(nameless, [uid(21), uid(20), uid(25)], "same rule as server cleanup, newest first, undated last")
check(D.addedLine(day(2025, 5, 3)), "أُضيف في 3 مايو 2025", "added line with year")
check(D.addedLine(nil), nil, "no date → no added line")
check(D.childrenLine(0, female: false), "بلا أبناء", "no children")
check(D.childrenLine(1, female: false), "له ابن واحد", "one child")
check(D.childrenLine(2, female: true), "لها ابنان", "two children (woman)")
check(D.childrenLine(3, female: false), "له 3 أبناء", "three children")
check(D.childrenLine(12, female: false), "له 12 ابناً", "twelve children")
check(D.registeredLine(day(2026, 11, 25)), "سُجّل في 25 نوفمبر", "registered line")
check(D.registeredLine(day(2026, 1, 3)), "سُجّل في 3 يناير", "registered line January")
check(D.registeredLine(nil), nil, "no date → no line")

// MARK: عدد المدخل

check(D.entryCount(duplicates: 0, problems: 0, nameless: 0), 0, "nothing")
check(D.entryCount(duplicates: 5, problems: 12, nameless: 9), 26, "sum of the three lists")
check(D.entryCount(duplicates: 5, problems: nil, nameless: 9), 14, "problems not ready yet")

// MARK: الترتيب داخل المجموعة «الأحدث» (قرار المالك ٢٠٢٦-١١-٢٨)
// الأحدث مواليداً أولاً (تاريخ الميلاد تنازلياً)، ومن بلا تاريخ في الآخر، ثم تاريخ الإضافة الأحدث، ثم ترتيب الدخل
func q(_ id: Int, _ birth: String?, _ added: Double?) -> D.Person {
    D.Person(id: uid(id), parent: uid(900), firstName: "محمد", birth: birth, added: added.map { Date(timeIntervalSince1970: $0) })
}
let newest = D.groups([q(1, "1950-03-01", 10), q(2, nil, 50), q(3, "1990-01-01", 5), q(4, "1970", 1),
                       q(5, nil, 70), q(6, "1990-01-01", 9), q(7, nil, nil), q(8, "bad", 80)])
check(newest.first?.ids, [uid(6), uid(3), uid(4), uid(1), uid(8), uid(5), uid(2), uid(7)],
      "born latest first · same birth → added latest · no/bad birth last by added · nothing at all → input order last")
check(D.newestFirst([q(10, "2001-05-05", nil), q(11, "2001-05-05", 3)]).map(\.id), [uid(11), uid(10)],
      "same birth: the one with an added date first")
check(D.birthKey("1985"), "1985-01-01", "year only = 1 Jan (as stored)")
check(D.birthKey(" 1985-07-09T00:00:00 "), "1985-07-09", "timestamp trimmed to the day")
check(D.birthKey(""), nil, "empty = no birth")
check(newest.first?.signature, D.Group.signature(parent: uid(900), ids: (1...8).map(uid)),
      "order does not change «ليسا مكرّرين» signature")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
