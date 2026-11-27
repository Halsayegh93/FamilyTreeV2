// فحص منطق شاشة الصيانة وسببها (Views/App/MaintenanceLogic.swift، الوحدة MT1) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/mt1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/App/MaintenanceLogic.swift tests/admin-redesign/MT1/main.swift && /tmp/mt1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = MaintenanceLogic
let def = "نقوم حالياً بتحديث التطبيق. يرجى المحاولة لاحقاً."

// ١) السطر تحت العنوان
check(M.bodyLine(nil), def, "nil → default line")
check(M.bodyLine(""), def, "empty → default line")
check(M.bodyLine("   \n "), def, "spaces only → default line")
check(M.bodyLine("  تحديث الشجرة  "), "تحديث الشجرة", "message trimmed and shown")
check(M.shouldShowMessage(nil), false, "no message → not shown")
check(M.shouldShowMessage(" "), false, "blank message → not shown")
check(M.shouldShowMessage("نحدّث قاعدة البيانات"), true, "message → shown")

// ٢) الحفظ
check(M.sanitized(""), nil, "empty saves as null")
check(M.sanitized("  سبب "), "سبب", "saved trimmed")
let long = String(repeating: "أ", count: 250)
check(M.sanitized(long)?.count, 200, "saved capped at 200")
check(M.maxMessageLength, 200, "limit = server check")
check(M.clampedDraft(long).count, 200, "field stops at 200")
check(M.clampedDraft("قصير"), "قصير", "short draft unchanged")
check(M.counter("abc"), "3/200", "counter")
check(M.counter(long), "200/200", "counter never above limit")

// ٣) تغيّر الحقل
check(M.isDirty(draft: "", saved: nil), false, "empty vs null not dirty")
check(M.isDirty(draft: "  ", saved: ""), false, "spaces not dirty")
check(M.isDirty(draft: "سبب ", saved: "سبب"), false, "trailing space not dirty")
check(M.isDirty(draft: "سبب جديد", saved: "سبب"), true, "changed text dirty")
check(M.isDirty(draft: "", saved: "سبب"), true, "clearing is dirty")

// ٤) الرجوع التلقائي
check(M.showsScreen(maintenanceOn: true, canModerate: false), true, "member sees screen")
check(M.showsScreen(maintenanceOn: false, canModerate: false), false, "off → app continues")
check(M.showsScreen(maintenanceOn: true, canModerate: true), false, "admins get in")
check(M.refreshSeconds, 60, "refetch every 60 s")

// الإنجليزية
L10n.isArabic = false
check(M.bodyLine(nil), "We're currently updating the app. Please try again later.", "english default")
L10n.isArabic = true

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
