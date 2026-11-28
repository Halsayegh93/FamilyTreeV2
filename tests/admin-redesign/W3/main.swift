// فحص اسم البنت (الوحدة W3، ٢٠٢٦-١١-٢٨) — يُحفظ كاملاً «اسمها + اسم أبيها» ويُعرض بالاسم الأول — بلا محاكي:
//   xcrun swiftc -swift-version 5 -default-isolation MainActor -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/w3-logic \
//     FamilyTreeV2/FamilyTreeV2/Models/Tree/PersonName.swift tests/admin-redesign/W3/main.swift \
//     && /private/tmp/claude-501/w3-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}
struct FamilyMember { let id: UUID; let firstName: String; let fatherId: UUID? }

let father = "فيصل علي حسن المحمدعلي"

// MARK: العرض — الاسم الأول وحده
check(PersonName.displayFirst(firstName: "أفنان", fullName: "أفنان " + father), "أفنان", "العرض: الاسم الأول المحفوظ")
check(PersonName.displayFirst(firstName: "", fullName: "أفنان " + father), "أفنان", "العرض: بلا اسم أول ← أول وحدة لا الكامل")
check(PersonName.displayFirst(firstName: "فاطمة الزهراء", fullName: "فاطمة الزهراء " + father), "فاطمة الزهراء", "العرض: المركّب وحدة واحدة")

// MARK: الحفظ من حقل الاسم الأول (الملف الشخصي)
func save(_ typed: String, full: String, first: String, dad: String? = father) -> String {
    PersonName.daughterSave(typedFirst: typed, storedFull: full, storedFirst: first, fatherFullName: dad).full
}
check(save("أفنان", full: "أفنان", first: "أفنان"), "أفنان " + father, "محفوظة كلمة واحدة ← تُكمَّل (السبب: كان يُرسل الاسم الأول)")
check(save("أفنان", full: "أفنان " + father, first: "أفنان"), "أفنان " + father, "بلا تغيير ← كما هو (لا ينقص)")
check(save("أفنان " + father, full: "أفنان " + father, first: "أفنان"), "أفنان " + father, "لصق الاسم الكامل ← لا تكرار لاسم الأب")
check(PersonName.daughterSave(typedFirst: "أفنان " + father, storedFull: "أفنان " + father, storedFirst: "أفنان",
                              fatherFullName: father).first, "أفنان", "لصق الاسم الكامل ← الاسم الأول وحده")
check(save("ماريا", full: "أفنان " + father, first: "أفنان"), "ماريا " + father, "تغيير الاسم ← السلسلة كما هي")
check(save("فاطمة الزهراء", full: "زهراء", first: "زهراء"), "فاطمة الزهراء " + father, "المركّب يبقى كاملاً + اسم الأب")
check(save("أفنان", full: "", first: ""), "أفنان " + father, "بلا اسم كامل ← يُكمَّل")
check(save("أفنان", full: "أفنان", first: "أفنان", dad: nil), "أفنان", "بلا أب معروف ← الاسم كما هو")
check(save("أفنان", full: "أفنان فيصل علي حسن عبدالله المحمدعلي", first: "أفنان"),
      "أفنان فيصل علي حسن عبدالله المحمدعلي", "سلسلة أطول من اسم الأب ← لا تنقص")

// MARK: الحفظ من حقل الاسم الكامل (إدارة السجل)
check(PersonName.completedDaughterFullName("أفنان", fatherFullName: father), "أفنان " + father, "كلمة واحدة ← تُكمَّل")
check(PersonName.completedDaughterFullName("أفنان " + father, fatherFullName: father), "أفنان " + father, "كامل ← بلا تكرار")
check(PersonName.completedDaughterFullName("فاطمة الزهراء", fatherFullName: father, storedFirst: "فاطمة الزهراء"),
      "فاطمة الزهراء " + father, "الاسم الأول المركّب وحده ← يُكمَّل")
check(PersonName.completedDaughterFullName("أفنان فيصل المحمدعلي", fatherFullName: father, storedFirst: "أفنان"),
      "أفنان فيصل المحمدعلي", "سلسلة كتبها المدير ← كما هي")
check(PersonName.completedDaughterFullName("زينب", fatherFullName: nil), "زينب", "زوجة بلا أب ← كما هي")

// MARK: الاسمان المحفوظان من «إدارة السجل» (WomenStore.update)
func admin(_ n: String, first: String?, dad: String? = father) -> String {
    let r = PersonName.savedNames(n, storedFirst: first, fatherFullName: dad); return r.first + " | " + r.full
}
check(admin("أفنان", first: "أفنان"), "أفنان | أفنان " + father, "إدارة: كلمة واحدة ← الكامل مُكمَّل والأول كما هو")
check(admin("فاطمة الزهراء " + father, first: "فاطمة الزهراء"), "فاطمة الزهراء | فاطمة الزهراء " + father, "إدارة: المركّب يبقى أولاً")
check(admin("ماريا " + father, first: "أفنان"), "ماريا | ماريا " + father, "إدارة: تغيير الأول ← ما قبل اسم الأب")
check(admin("زينب حسن بوشهري", first: "زينب", dad: nil), "زينب | زينب حسن بوشهري", "إدارة: زوجة بلا أب ← كما هي")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
