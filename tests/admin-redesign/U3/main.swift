// فحص منطق عُدّة الصفحات (Views/Features/Admin/AdminPageKit.swift، الوحدة U3) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminPageKit.swift tests/admin-redesign/U3/main.swift && /tmp/u3-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias V = AdminPageKitLogic.KPIValue

// MARK: نصّ رقم الرأس القديم (`AdminPageKPI.value`) ← عنصر سطر الأرقام
check(AdminPageKitLogic.kpiValue("—"), V.pending, "«—» = not loaded (dim, no tap)")
check(AdminPageKitLogic.kpiValue(""), V.pending, "empty = not loaded")
check(AdminPageKitLogic.kpiValue(" - "), V.pending, "a bare dash = not loaded")
check(AdminPageKitLogic.kpiValue("170"), V.number(170), "plain count")
check(AdminPageKitLogic.kpiValue("0"), V.number(0), "zero stays a number (drawn dim, opens nothing)")
check(AdminPageKitLogic.kpiValue("2,991"), V.number(2991), "Latin thousands separator")
check(AdminPageKitLogic.kpiValue("٢٬٩٩١"), V.number(2991), "Arabic-Indic digits + Arabic separator (Int.formatted() on an Arabic device)")
check(AdminPageKitLogic.kpiValue("۱۲"), V.number(12), "Extended Arabic-Indic digits")
check(AdminPageKitLogic.kpiValue("83٪"), V.text("83٪"), "percent stays text")
check(AdminPageKitLogic.kpiValue("+3"), V.text("+3"), "a sign stays text (keeps «+»)")
check(AdminPageKitLogic.kpiValue("-3"), V.text("-3"), "negative stays text")
check(AdminPageKitLogic.kpiValue("✓"), V.text("✓"), "tick stays text")
check(AdminPageKitLogic.kpiValue("يعمل"), V.text("يعمل"), "a state word stays text")
check(AdminPageKitLogic.kpiValue("1 من 2"), V.text("1 من 2"), "mixed text stays text")
check(AdminPageKitLogic.kpiValue("2.5"), V.text("2.5"), "a decimal stays text")
check(AdminPageKitLogic.kpiValue("99999999999999999999999"), V.text("99999999999999999999999"), "overflow stays text")

// وما يرسمه سطر الأرقام لكل حالة (عقد U2 `AdminHeaderItemLook`)
let zero = AdminHeaderItemLook.make(value: 0, health: nil, opens: true)
check(zero.dim, true, "zero is dim")
check(zero.opens, false, "zero opens nothing")
let pending = AdminHeaderItemLook.make(value: nil, health: nil, opens: true)
check(pending.text, "—", "pending shows «—»")
check(pending.opens, false, "pending opens nothing")
let grouped = AdminHeaderItemLook.make(value: 2991, health: nil, opens: true)
check(grouped.text, "2,991", "count drawn with a Latin thousands separator")
check(grouped.opens, true, "a real number with a tap opens")

// MARK: حال المخزن ← بطاقة الحالة
let at = Date(timeIntervalSince1970: 1_800_000_000)
check(AdminPageKitLogic.pageState(.idle), .loading, "idle → skeleton")
check(AdminPageKitLogic.pageState(.loading), .loading, "loading → skeleton")
check(AdminPageKitLogic.pageState(.loaded(at: at)), .content, "loaded → no state card")
check(AdminPageKitLogic.pageState(.failed(lastGood: nil)), .failed(lastGood: nil), "failed with nothing → error + retry")
check(AdminPageKitLogic.pageState(.failed(lastGood: at)), .failed(lastGood: at), "failed after a good load → keep data + time")
check(AdminPageKitLogic.pageState(.denied), .content, "denied → no card, never a retry")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
