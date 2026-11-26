// فحص منطق ورقة العضو «أ3 ملف موجز وأفعال» (Views/Features/Admin/AdminMemberSheetLogic.swift، الوحدة V2-3) — بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/v2c-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift tests/admin-redesign/V2c/main.swift \
//     && /private/tmp/claude-501/v2c-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminMemberSheetLogic
typealias A = AdminMemberSheetLogic.HeaderAction
typealias M = AdminMemberSheetLogic.Missing

// MARK: أزرار الرأس — قاعدة الرقم الظاهر والمتوفى
check(L.headerActions(canEdit: true, inTree: true, isDeceased: false, visiblePhone: "+96550001234"),
      [A.fullProfile, .tree, .call, .whatsapp], "living, visible number → all four, in order")
check(L.headerActions(canEdit: true, inTree: true, isDeceased: false, visiblePhone: nil),
      [A.fullProfile, .tree], "no visible number (hidden from this viewer) → call/WhatsApp gone, not dimmed")
check(L.headerActions(canEdit: true, inTree: true, isDeceased: false, visiblePhone: "  "),
      [A.fullProfile, .tree], "blank number → no call/WhatsApp")
check(L.headerActions(canEdit: true, inTree: true, isDeceased: false, visiblePhone: "+965 •••• 4417"),
      [A.fullProfile, .tree], "masked by the server → no call/WhatsApp")
check(L.headerActions(canEdit: true, inTree: true, isDeceased: true, visiblePhone: "+96550001234"),
      [A.fullProfile, .tree], "deceased → never call/WhatsApp, even with a number on file")
check(L.headerActions(canEdit: false, inTree: true, isDeceased: false, visiblePhone: "+96550001234"),
      [A.tree, .call, .whatsapp], "read-only role → no «الملف الكامل»")
check(L.headerActions(canEdit: true, inTree: false, isDeceased: false, visiblePhone: nil),
      [A.fullProfile], "not in the tree (hidden / frozen / daughter's son) → no «في الشجرة»")
check(L.headerActions(canEdit: false, inTree: false, isDeceased: true, visiblePhone: nil),
      [A](), "nothing to do → empty row (the band shows only the title)")

// MARK: صفّ الأزرار — أربعة أعمدة، و٢×٢ مع الخط الكبير
check(L.actionColumns(accessibilitySize: false), 4, "default size → four columns")
check(L.actionColumns(accessibilitySize: true), 2, "accessibility size → two columns")
check(L.actionRows(count: 4, accessibilitySize: false), [[0, 1, 2, 3]], "four actions → one row")
check(L.actionRows(count: 2, accessibilitySize: false), [[0, 1]], "two actions → one row (leading, quarter width)")
check(L.actionRows(count: 4, accessibilitySize: true), [[0, 1], [2, 3]], "large text, four → 2×2")
check(L.actionRows(count: 3, accessibilitySize: true), [[0, 1], [2]], "large text, three → 2 + 1")
check(L.actionRows(count: 2, accessibilitySize: true), [[0, 1]], "large text, two → one row of two")
check(L.actionRows(count: 0, accessibilitySize: true), [[Int]](), "no actions → no rows")

// MARK: «أكمل الناقص» — رقاقة لكل ناقص
check(L.missingChips(gaps: [.deathIncomplete], problems: [], canEdit: true), [M.deathIncomplete],
      "deceased with a year-only date → one chip «تاريخ الوفاة غير مكتمل · أكمل»")
check(L.missingChips(gaps: [], problems: [], canEdit: true), [M](), "nothing missing → no chips (hidden)")
check(L.missingChips(gaps: [.noBirth, .noGender], problems: [.orphan, .hidden], canEdit: true),
      [M.noBirth, .noGender, .orphan, .hidden], "gaps first, then tree problems, in order")
check(L.missingChips(gaps: [.noPhoto], problems: [], canEdit: true), [M](),
      "no photo → no chip (the photo row carries «نبّهه يضيف صورة»)")
check(L.missingChips(gaps: [.noBirth, .noPhoto], problems: [.dupPhone], canEdit: true), [M.noBirth, .dupPhone],
      "no-photo dropped, the rest kept")
check(L.missingChips(gaps: [.noBirth], problems: [.orphan], canEdit: false), [M](),
      "read-only viewer → no fix chips (the boxes are edits)")
check(L.missingChips(gaps: [.noBirth, .noBirth], problems: [], canEdit: true), [M.noBirth], "no duplicates")
check(M(rawValue: "deathIncomplete"), M.deathIncomplete, "raw value matches AdminMemberGap.deathIncomplete")
check(M(rawValue: "brokenParent"), M.brokenParent, "raw value matches AdminMemberProblem.brokenParent")
check(M(rawValue: "dupPhone"), M.dupPhone, "raw value matches AdminMemberProblem.dupPhone")

// MARK: الاسم الأول وحده في الصفوف (الكامل مرة واحدة في الرأس)
check(L.firstName("ابراهيم", full: "ابراهيم حسين حسن محمدعلي حسن المحمدعلي"), "ابراهيم", "stored first name wins")
check(L.firstName("  حسن ", full: "حسن صلاح"), "حسن", "first name is trimmed")
check(L.firstName("", full: "علي زيد حسن"), "علي", "no stored first name → first word of the full name")
check(L.firstName(nil, full: "  زيد   حسن "), "زيد", "nil first name, spaces around → first word")
check(L.firstName("بدون اسم", full: "بدون اسم"), nil as String?, "placeholder name → nil («بلا اسم»)")
check(L.firstName(nil, full: nil), nil as String?, "nothing → nil")
check(L.childrenLine(["عبدالنبي", "احمد", "منصور", "صالح", "ابراهيم"]), "عبدالنبي، احمد، منصور، صالح…",
      "five sons → first four first names + «…»")
check(L.childrenLine(["زيد", "علي"]), "زيد، علي", "two sons → both, no ellipsis")
check(L.childrenLine([]), nil as String?, "no sons → no sub line (the 0 says it)")
check(L.childrenLine(["", "  "]), nil as String?, "blank names → no sub line")

// MARK: قفل ورقتك — لا إيقاف ولا منع رقم ولا حذف
let me = UUID(), other = UUID(), owner2 = UUID()
let selfOwner = L.isOther(memberId: me, viewerId: me, memberIsOwner: true)
check(selfOwner, false, "your own sheet (owner) is not «other»")
check(L.accountCommands(isOther: selfOwner, canFreeze: true, canBan: true, banPrefill: "50001234", canDelete: true),
      .init(suspend: false, ban: false, delete: false), "owner on own sheet → no suspend, no ban, no delete")
let selfAdmin = L.isOther(memberId: me, viewerId: me, memberIsOwner: false)
check(L.accountCommands(isOther: selfAdmin, canFreeze: true, canBan: false, banPrefill: nil, canDelete: true),
      .init(suspend: false, ban: false, delete: false), "admin on own sheet → nothing dangerous")
let otherOwner = L.isOther(memberId: owner2, viewerId: me, memberIsOwner: true)
check(L.accountCommands(isOther: otherOwner, canFreeze: true, canBan: true, banPrefill: "50001234", canDelete: true),
      .init(suspend: false, ban: false, delete: false), "the other owner's sheet → locked too")
let plain = L.isOther(memberId: other, viewerId: me, memberIsOwner: false)
check(L.accountCommands(isOther: plain, canFreeze: true, canBan: true, banPrefill: "50001234", canDelete: true),
      .init(suspend: true, ban: true, delete: true), "owner on a member's sheet → all three")
check(L.accountCommands(isOther: plain, canFreeze: true, canBan: true, banPrefill: nil, canDelete: false),
      .init(suspend: true, ban: false, delete: false), "masked/blank number → no ban row; no delete right → no delete")
check(L.accountCommands(isOther: plain, canFreeze: false, canBan: false, banPrefill: "50001234", canDelete: false),
      .init(suspend: false, ban: false, delete: false), "monitor → none of the three")

check(L.lockNote(memberId: me, viewerId: me, memberIsOwner: true, isDeceased: false, viewerCanAct: true),
      .selfOwner, "owner's own sheet → «هذا حسابك، وأنت المالك: …»")
check(L.lockNote(memberId: me, viewerId: me, memberIsOwner: false, isDeceased: false, viewerCanAct: true),
      .selfAccount, "admin's own sheet → «هذا حسابك: …»")
check(L.lockNote(memberId: owner2, viewerId: me, memberIsOwner: true, isDeceased: false, viewerCanAct: true),
      .ownerAccount, "the other owner's sheet → «حساب المالك: …»")
check(L.lockNote(memberId: other, viewerId: me, memberIsOwner: false, isDeceased: false, viewerCanAct: true),
      nil as L.LockNote?, "a member's sheet → no lock note")
check(L.lockNote(memberId: me, viewerId: me, memberIsOwner: true, isDeceased: false, viewerCanAct: false),
      nil as L.LockNote?, "viewer with no command on the sheet → no note to explain")
check(L.lockNote(memberId: owner2, viewerId: me, memberIsOwner: true, isDeceased: true, viewerCanAct: true),
      nil as L.LockNote?, "deceased → no account, no note")

// MARK: ما بقي من U13 كما هو (الاتصال يعتمد عليه)
check(L.canContact("+96550001234"), true, "visible number → contact")
check(L.canContact("*****1234"), false, "masked → no contact")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
