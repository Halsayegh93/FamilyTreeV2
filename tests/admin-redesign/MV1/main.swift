// فحص منطق «ظهور زوج البنت من خارج العائلة وأبنائها» للإدارة ولابن البنت (Views/Features/Profile/MotherVisibilityLogic.swift، الوحدة MV1) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/mv1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/MotherVisibilityLogic.swift tests/admin-redesign/MV1/main.swift && /tmp/mv1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias V = MotherVisibilityLogic
let H = UUID(), F = UUID(), M = UUID(), U = UUID()
let outside: Set<UUID> = [H]

// ١) الإدارة: البنت التي زوجها من خارج العائلة فقط
check(V.adminShowsToggles(canEdit: true, isFemale: true, husbandId: H, outsideIds: outside), true, "admin + daughter with outside husband")
check(V.adminShowsToggles(canEdit: false, isFemale: true, husbandId: H, outsideIds: outside), false, "no edit right → hidden")
check(V.adminShowsToggles(canEdit: true, isFemale: true, husbandId: F, outsideIds: outside), false, "family husband → hidden")
check(V.adminShowsToggles(canEdit: true, isFemale: true, husbandId: nil, outsideIds: outside), false, "no husband → hidden")
check(V.adminShowsToggles(canEdit: true, isFemale: false, husbandId: H, outsideIds: outside), false, "male node → hidden")

// ٢) ابن البنت / بنت البنت: أمّه في الشجرة بلا حساب، وأبوه (أو زوج أمّه) من خارج العائلة
check(V.childShowsToggles(motherId: M, motherHasAccount: false, fatherId: H, motherHusbandId: H, outsideIds: outside), true, "outside father, mother no account")
check(V.childShowsToggles(motherId: M, motherHasAccount: false, fatherId: nil, motherHusbandId: H, outsideIds: outside), true, "mother's husband outside")
check(V.childShowsToggles(motherId: M, motherHasAccount: true, fatherId: H, motherHusbandId: H, outsideIds: outside), false, "mother has account → she decides")
check(V.childShowsToggles(motherId: nil, motherHasAccount: false, fatherId: H, motherHusbandId: nil, outsideIds: outside), false, "no mother → hidden")
check(V.childShowsToggles(motherId: M, motherHasAccount: false, fatherId: F, motherHusbandId: F, outsideIds: outside), false, "family father → hidden")

// ٣) الأصل = مخفي (null)، والقيمة المحفوظة كما هي
check(V.shown(nil), false, "null → hidden")
check(V.shown(true), true, "true → shown")

// ٤) رسائل الأخطاء بالعربية من hint السيرفر
check(V.errorMessage(hint: "mother_has_account"), "للوالدة حساب في التطبيق، والاختيار لها.", "mother_has_account")
check(V.errorMessage(hint: "no_mother"), "الوالدة غير مسجّلة في الشجرة.", "no_mother")
check(V.errorMessage(hint: "no_node"), "لا توجد لك عقدة في شجرة النساء بعد.", "no_node")
check(V.errorMessage(hint: "not_allowed"), "حسابك غير مفعّل بعد.", "not_allowed")
check(V.errorMessage(hint: nil), "تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "unknown → generic")
check(V.errorMessage(hint: "42501"), "تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "other hint → generic")

// ٥) العناوين الرسمية
check(V.childSpouseTitle, "ظهور الوالد بجانب الوالدة", "child spouse title")
check(V.childChildrenTitle, "ظهور الأبناء تحت الوالدة", "child children title")
check(V.adminSpouseTitle, "ظهور الزوج", "admin spouse title")
check(V.adminChildrenTitle, "ظهور الأبناء", "admin children title")
_ = U

// ٦) الزوجة صاحبة الحساب (العيّنة spouse2 القسم ٤): زوجها من خارج العائلة فقط، والمفتاحان بنصّ العيّنة
check(V.ownShowsToggles(canEdit: true, isFemale: true, husbandId: H, outsideIds: outside), true, "own: outside husband → toggles")
check(V.ownShowsToggles(canEdit: true, isFemale: true, husbandId: F, outsideIds: outside), false, "own: family husband → none")
check(V.ownShowsToggles(canEdit: false, isFemale: true, husbandId: H, outsideIds: outside), false, "own: deceased/no edit → none")
check(V.ownShowsToggles(canEdit: true, isFemale: false, husbandId: H, outsideIds: outside), false, "own: male → none")
check(V.ownSpouseTitle, "إظهار الزوج في الشجرة", "own spouse title")
check(V.ownChildrenTitle, "إظهار الأبناء", "own children title")
check(V.ownNote, "عند الإخفاء: لا يظهر الزوج ولا الأبناء للأعضاء. تبقين أنتِ والإدارة ترينهم.", "own note verbatim")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
