// فحص «دمج» المكرّرين (Views/Features/Admin/AdminMergeRules.swift، الوحدة M3، موافقة المالك ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/m3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMergeRules.swift tests/admin-redesign/M3/main.swift \
//     && /private/tmp/claude-501/m3-logic
//
// ما يُفحص: «دمج» على كل صفّ إلا من له حساب أو من الإدارة أو قبل وصول الحسابات · في من يُدمج (الآخر مباشرة، أو
// السؤال لثلاثة فأكثر) · قراءة نتيجة السيرفر · «ينتقل: …» بالعدّ العربي · التعارض وما لا ينتقل · رسائل الأخطاء.
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = AdminMergeRules
let a = UUID(), b = UUID(), c = UUID(), s = UUID()

// ١) الزرّ على الصفّ
check(M.canRemove(hasLogin: false, isStaff: false, accountsReady: true), true, "بلا حساب: يظهر «دمج»")
check(M.canRemove(hasLogin: true, isStaff: false, accountsReady: true), false, "له حساب: لا زرّ")
check(M.canRemove(hasLogin: false, isStaff: true, accountsReady: true), false, "من الإدارة: لا زرّ")
check(M.canRemove(hasLogin: false, isStaff: false, accountsReady: false), false, "قبل وصول الحسابات: لا زرّ")

// ٢) في من يُدمج
check(M.targets(group: [a, b], remove: a, hasLogin: []), [b], "اثنان: الآخر")
check(M.needsTargetChoice(M.targets(group: [a, b], remove: a, hasLogin: [])), false, "اثنان: بلا سؤال")
check(M.targets(group: [a, b], remove: a, hasLogin: [b]), [b], "المُبقى له حساب: مسموح")
check(M.targets(group: [a, b], remove: a, hasLogin: [a]), [], "المحذوف له حساب: لا دمج")
check(M.targets(group: [a, b, c], remove: b, hasLogin: []), [a, c], "ثلاثة: الباقيان بترتيبهما")
check(M.needsTargetChoice(M.targets(group: [a, b, c], remove: b, hasLogin: [])), true, "ثلاثة: يُسأل في أيّهم")
check(M.targets(group: [a, s], remove: a, hasLogin: [], staff: [s]), [], "الآخر من الإدارة: لا دمج")
check(M.targets(group: [a, b], remove: c, hasLogin: []), [], "ليس في المجموعة: لا دمج")

// ٣) نتيجة السيرفر
let json = """
{"kept":"x","removed":"y","tree":"men","moved_children":3,"moved_daughters":1,"moved_wives":1,"moved_women":2,
 "filled":["birth_date","mother_id"],"conflicts":[{"field":"death_date","kept":"1990-01-01","removed":"1991-01-01"}],
 "not_moved":["phone_number"],"dry_run":true}
""".data(using: .utf8)!
let p = M.preview(from: json)!
check(p, M.Preview(tree: "men", children: 3, daughters: 1, wives: 1, women: 2, filled: ["birth_date", "mother_id"],
                   conflicts: ["death_date"], notMoved: ["phone_number"]), "قراءة النتيجة")
check(M.preview(from: "[]".data(using: .utf8)!) == nil, true, "ليست كائناً: nil")

// ٤) «ينتقل: …»
check(M.movesLine(p), "ينتقل: 3 أبناء، بنت واحدة، الزوجة، تاريخ الميلاد، الأم", "السطر الكامل")
check(M.movesLine(M.Preview(children: 1, wives: 2)), "ينتقل: ابن واحد، زوجتان", "ابن واحد وزوجتان")
check(M.movesLine(M.Preview(children: 2, daughters: 2)), "ينتقل: ابنان، بنتان", "المثنّى")
check(M.movesLine(M.Preview(children: 11, daughters: 12, wives: 3)), "ينتقل: 11 ابناً، 12 بنتاً، 3 زوجات", "فوق العشرة")
check(M.movesLine(M.Preview()), "لا ينتقل شيء؛ الاسم مكرر فقط.", "لا شيء")
check(M.movesLine(M.Preview(tree: "women", children: 2, daughters: 5, wives: 1, filled: ["husband_id"])),
      "ينتقل: ابنان، الزوج", "شجرة النساء: الأبناء والزوج فقط")
check(M.conflictsLine(p), "يختلفان في: تاريخ الوفاة. تبقى قيمة الاسم الباقي.", "التعارض")
check(M.conflictsLine(M.Preview()), nil, "بلا تعارض")
check(M.notMovedLine(p), "لا ينتقل: رقم الهاتف.", "ما لا ينتقل")
check(M.deleteNote, "يُحذف الاسم المكرر نهائياً.", "ملاحظة الحذف")

// ٥) الأخطاء
check(M.message(hint: "remove_has_login").contains("حساب دخول"), true, "له حساب")
check(M.message(hint: "both_have_login"), "كلا الاسمين مرتبط بحساب دخول، فلا يمكن دمجهما.", "الاثنان لهما حساب")
check(M.message(hint: "different_father"), "لا يمكن الدمج؛ الاسمان ليسا تحت الأب نفسه.", "أب مختلف")
check(M.message(hint: nil), "تعذّر الدمج. تحقّق من الاتصال ثم حاول مرة أخرى.", "خطأ عام")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
