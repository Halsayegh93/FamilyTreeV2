// فحص «شجرة العائلة للرجال فقط» (Views/Features/Tree/FamilyTreeMenOnly.swift، الوحدة G1، طلب المالك ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/g1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift tests/admin-redesign/G1/main.swift \
//     && /private/tmp/claude-501/g1-logic
//
// ما يُفحص: «أنثى» في مربّع إضافة لشجرة العائلة لا تُقبل (تنبيه + انتقال لشجرة النساء، أو «إلغاء» فقط بلا مسار) ·
// الجنس يبقى ذكراً بعد اختيار «أنثى» · الحارس الأخير قبل الكتابة · الاسم المنقول لمربّع البنت · النصوص.
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = FamilyTreeMenOnly

// ١) القرار
check(M.decision(gender: "male", hasWomenPath: true), .allow, "male → allowed")
check(M.decision(gender: "male", hasWomenPath: false), .allow, "male without women path → still allowed")
check(M.decision(gender: nil, hasWomenPath: true), .allow, "no gender (defaults male) → allowed")
check(M.decision(gender: "", hasWomenPath: true), .allow, "empty gender → allowed")
check(M.decision(gender: "female", hasWomenPath: true), .redirectToWomenTree, "female → alert + women tree")
check(M.decision(gender: " Female ", hasWomenPath: true), .redirectToWomenTree, "female any case/spaces → alert")
check(M.decision(gender: "FEMALE", hasWomenPath: false), .blockOnly, "female without women path → alert with cancel only")

// ٢) الاختيار في المربّع: «أنثى» لا تبقى
check(M.keptGender(picked: "female", current: "male"), "male", "pick female while male → stays male")
check(M.keptGender(picked: "male", current: "male"), "male", "pick male → male")
check(M.keptGender(picked: "female", current: "female"), "male", "stale female → back to male")
check(M.keptGender(picked: "male", current: "female"), "male", "pick male from stale female → male")

// ٣) الحارس الأخير قبل الكتابة
check(M.mayWriteToFamilyTree(gender: "male"), true, "male may be written")
check(M.mayWriteToFamilyTree(gender: nil), true, "nil may be written (server writes male)")
check(M.mayWriteToFamilyTree(gender: "female"), false, "female never written to the family tree")
check(M.isFemale("female"), true, "isFemale female")
check(M.isFemale("male"), false, "isFemale male")

// ٤) الاسم المنقول لمربّع «أبناء» في شجرة النساء
check(M.carriedName("  فاطمة \n"), "فاطمة", "typed name trimmed")
check(M.carriedName(""), "", "empty name stays empty")

// ٥) النصوص (العربية)
check(M.title, "شجرة العائلة للرجال فقط", "alert title")
check(M.message, "البنات يُضفن في شجرة النساء تحت أبيهن.", "alert line")
check(M.openTitle, "إلى شجرة النساء", "primary button")
check(M.cancelTitle, "إلغاء", "cancel button")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
