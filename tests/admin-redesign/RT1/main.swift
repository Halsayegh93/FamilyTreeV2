// فحص منطق مربّعات «يحتاج مراجعتك» (Views/Features/Admin/AdminReviewTiles.swift، اختيار المالك «ب» ٢٠٢٦-١١-٢٨) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/rt1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminReviewTiles.swift tests/admin-redesign/RT1/main.swift && /tmp/rt1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminReviewTilesLogic

// MARK: الترتيب — مربّعات النموذج أولاً بترتيبه، ثم بقية القوائم الحقيقية
check(L.columns, 3, "three per row (option «ب»)")
check(L.kinds(seesWomen: true), [.issues, .problems, .death, .photos, .married, .living, .gaps, .notOpened, .inactive],
      "owner/admin: mock-up tiles first, then the other real review lists")
check(L.kinds(seesWomen: false).contains(.married), false, "monitor (no women's tree): no «متزوجة بلا زوج مربوط»")
check(L.kinds(seesWomen: false).count, 8, "monitor: eight tiles")
check(Set(L.kinds(seesWomen: true)), Set(AdminReviewTileKind.allCases), "every tile kind shown to owner/admin")

// MARK: لون الرقم — رمادي للصفر وقبل الوصول
check(L.tone(0), .grey, "zero → grey")
check(L.tone(nil), .grey, "not arrived → grey")
check(L.tone(-1), .grey, "negative guard → grey")
check(L.tone(1), .tinted, "one → tile colour")
check(L.tone(363), .tinted, "363 → tile colour")

// MARK: النص والضغط
check(L.text(nil), AdminStoreHealthText.placeholder, "not arrived → «—»")
check(L.text(0), "0", "zero")
check(L.text(2177), "2,177", "thousands separator")
check(L.opens(0), false, "zero opens nothing")
check(L.opens(nil), true, "not arrived still opens (the page counts itself)")
check(L.opens(17), true, "17 opens its page")

// MARK: «✓ الباقي سليم» يملأ فراغ آخر صفّ
check(L.showsFiller(tileCount: 9), false, "9 tiles = three full rows, no filler")
check(L.showsFiller(tileCount: 8), true, "8 tiles → filler fills the gap")
check(L.showsFiller(tileCount: 5), true, "5 tiles (mock-up) → filler")
check(L.showsFiller(tileCount: 6), false, "6 tiles → none")
check(L.showsFiller(tileCount: 8, columns: 2), false, "two columns (XXXL), 8 tiles → none")
check(L.showsFiller(tileCount: 0), false, "no tiles → none")
check(L.showsFiller(tileCount: 3, columns: 1), false, "one column → never")

// MARK: «المكرر والأخطاء» بلا مشكلات الشجرة والمتزوجات (لهما مربّعاهما)
check(L.issuesCount(duplicates: 12, nameless: 5), 17, "duplicates + nameless numbers")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
