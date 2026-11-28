// فحص «دمج» المكرّرين (Views/Features/Admin/AdminMergeRules.swift، الوحدة M3، موافقة المالك ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/m3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMergeRules.swift tests/admin-redesign/M3/main.swift \
//     && /private/tmp/claude-501/m3-logic
//
// ما يُفحص: «دمج» واحد لكل بطاقة مجموعة (`plan`): من يبقى (صاحب الحساب مختار مسبقاً، حسابان/الإدارة/قبل وصول الحسابات
// = لا زرّ) ومن يُحذف (سؤال ثانٍ لثلاثة فأكثر) · حراس 20261127270000 (متوفى/حيّ، ميلادان بينهما أكثر من سنتين — لا زرّ) · قراءة نتيجة السيرفر
// (moved_husbands، صفوف not_moved) · «ينتقل: …» بالعدّ العربي والأبناء/البنات منفصلين في شجرة النساء · التعارض وما لا
// ينتقل · رسائل الأخطاء · فشل «ليسا مكرّرين».
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = AdminMergeRules
let a = UUID(), b = UUID(), c = UUID(), s = UUID()

// ١) زرّ واحد لكل بطاقة مجموعة («خله دمج واحد»، المالك ٢٠٢٦-١١-٢٧) — الخطة: من يبقى، ومن يُحذف لكل مُبقى
typealias F = M.Facts
let alive = F(deceased: false, birthYear: nil), dead = F(deceased: true, birthYear: nil)
let p2 = M.plan(group: [a, b], hasLogin: [], accountsReady: true)!
check(p2.keepOptions, [a, b], "اثنان بلا حساب: أيّهما يبقى")
check(p2.preselected, nil, "اثنان بلا حساب: بلا اختيار مسبق")
check(p2.removeOptions(keep: a), [b], "يبقى الأول: يُحذف الثاني")
check(p2.needsRemoveChoice(keep: a), false, "اثنان: بلا سؤال ثانٍ")
let pl = M.plan(group: [a, b], hasLogin: [b], accountsReady: true)!
check(pl.keepOptions, [b], "صاحب الحساب يبقى")
check(pl.preselected, b, "صاحب الحساب مختار مسبقاً")
check(pl.removeOptions(keep: b), [a], "الآخر يُحذف")
check(pl.removeOptions(keep: a), [], "لا يُحذف صاحب الحساب")
check(M.plan(group: [a, b, c], hasLogin: [a, b], accountsReady: true) == nil, true, "حسابان: لا زرّ")
check(M.plan(group: [a, s], hasLogin: [], staff: [s], accountsReady: true) == nil, true, "الآخر من الإدارة: لا زرّ")
check(M.plan(group: [a, b], hasLogin: [], accountsReady: false) == nil, true, "قبل وصول الحسابات: لا زرّ")
check(M.plan(group: [a], hasLogin: [], accountsReady: true) == nil, true, "شخص واحد: لا زرّ")
check(M.plan(group: [a, b], hasLogin: [], facts: [a: alive, b: dead], accountsReady: true) == nil, true, "متوفى وحيّ: لا زرّ على البطاقة")
check(M.plan(group: [a, b], hasLogin: [], facts: [a: F(deceased: false, birthYear: 1960), b: F(deceased: false, birthYear: 1990)],
             accountsReady: true) == nil, true, "ميلادان متباعدان: لا زرّ على البطاقة")
let p3 = M.plan(group: [a, b, c], hasLogin: [], accountsReady: true)!
check(p3.keepOptions, [a, b, c], "ثلاثة: كلهم يصلحون للبقاء")
check(p3.removeOptions(keep: b), [a, c], "ثلاثة: يُسأل أيّهم يُحذف")
check(p3.needsRemoveChoice(keep: b), true, "ثلاثة: سؤال ثانٍ")
let p3d = M.plan(group: [a, b, c], hasLogin: [], facts: [a: alive, b: dead, c: alive], accountsReady: true)!
check(p3d.keepOptions, [a, c], "ثلاثة بمتوفى: المتوفى لا يبقى ولا يُحذف")
check(p3d.removeOptions(keep: a), [c], "ثلاثة بمتوفى: الحيّ الآخر فقط")
let p3l = M.plan(group: [a, b, c], hasLogin: [c], accountsReady: true)!
check(p3l.keepOptions, [a, b, c], "ثلاثة وحساب: يبقى أيٌّ منهم (صاحب الحساب لا يُحذف)")
check(p3l.preselected, c, "ثلاثة وحساب: صاحب الحساب مختار مسبقاً")
check(p3l.removeOptions(keep: a), [b], "ثلاثة وحساب: صاحب الحساب لا يُحذف")
check(M.buttonTitle, "دمج", "نص الزرّ")

// ١ب) «حذف» الفارغ («حط حذف بعد اذا في مكرر وبيانات ناقصة»، المالك ٢٠٢٦-١١-٢٧): لا أبناء ولا زوج ولا حساب ولا إدارة، وكل ما
// فيه (ميلاد، وفاة، صورة، رقم، سيرة) موجود عند آخر متوافق في المجموعة — حذفه لا يُفقد شيئاً
typealias R = M.Record
let d0 = Date(timeIntervalSince1970: 0), d1 = Date(timeIntervalSince1970: 100)
let full = R(birth: true, photo: true, facts: alive, addedAt: d1)
let bare = R(facts: alive, addedAt: d1)
check(M.isEmpty(bare, others: [full]), true, "بلا شيء وعند الآخر بيانات: فارغ")
check(M.isEmpty(R(children: 1, facts: alive), others: [full]), false, "له أبناء: ليس فارغاً")
check(M.isEmpty(R(spouses: 1, facts: alive), others: [full]), false, "له زوجة/زوج: ليس فارغاً")
check(M.isEmpty(R(hasLogin: true, facts: alive), others: [full]), false, "له حساب: ليس فارغاً")
check(M.isEmpty(R(isStaff: true, facts: alive), others: [full]), false, "من الإدارة: ليس فارغاً")
check(M.isEmpty(R(phone: true, facts: alive), others: [full]), false, "له رقم ليس عند الآخر: دمج فقط")
check(M.isEmpty(R(birth: true, facts: alive), others: [full]), true, "ميلاده عند الآخر أيضاً: فارغ")
check(M.isEmpty(R(bio: true, facts: alive), others: [bare]), false, "له سيرة: دمج فقط")
check(M.isEmpty(bare, others: [R(facts: dead)]), false, "الآخر متوفى: قد يكونان أخوين — لا حذف")
check(M.isEmpty(bare, others: []), false, "وحده: لا حذف")
check(M.isEmpty(R(death: true, facts: dead), others: [R(death: true, facts: dead)]), true, "متوفيان بتاريخ عند الاثنين: فارغ")
check(M.deleteCandidates(group: [a, b], records: [a: full, b: bare]), [b], "المرشّح: الفارغ وحده")
check(M.deleteCandidates(group: [a, b], records: [a: full, b: R(phone: true, facts: alive)]), [], "بيانات ناقصة عند الآخر: لا حذف")
check(M.deleteCandidates(group: [a, b], records: [a: bare]), [], "سجلّ ناقص: لا حذف")
// اثنان فارغان: الأفرغ أولاً، ثم الأحدث إضافة (الأقدم غالباً الأصل بتاريخه)
let thin = R(birth: true, facts: alive, addedAt: d0)
check(M.deleteCandidates(group: [a, b, c], records: [a: full, b: thin, c: bare]), [c, b], "الأفرغ أولاً")
check(M.deleteCandidates(group: [a, b, c], records: [a: full, b: R(facts: alive, addedAt: d1), c: R(facts: alive, addedAt: d0)]),
      [b, c], "التعادل: الأحدث إضافة أولاً")
check(M.deleteButtonTitle, "حذف", "نص زرّ الحذف")
check(M.nothingLostNote, "لا توجد بيانات تُفقد.", "سطر لا شيء يُفقد")
check(M.deleteForeverNote, "يُحذف نهائياً.", "سطر الحذف النهائي")
check(M.deleteMessage(hint: "family_links_protected"), "لا يمكن الحذف؛ ما زال أحد أفراد العائلة مرتبطاً بهذا الاسم.", "حذف مرفوض للروابط")
// الأم: إخوة من زوجتين ليسوا مكرّرين
let m1 = UUID(), m2 = UUID()
check(M.isEmpty(R(facts: alive, mother: m1), others: [R(birth: true, facts: alive, mother: m2)]), false, "أمّان مختلفتان: لا حذف")
check(M.isEmpty(R(facts: alive, mother: m1), others: [R(birth: true, facts: alive)]), false, "له أم والآخر بلا أم: لا حذف")
check(M.isEmpty(R(facts: alive, mother: m1), others: [R(birth: true, facts: alive, mother: m1)]), true, "الأم نفسها: فارغ")
check(M.isEmpty(R(facts: alive), others: [R(birth: true, facts: alive, mother: m1)]), true, "بلا أم والآخر له أم: لا يُفقد شيء")
// الغلاف والصور والطلبات المعلّقة: «دمج» فقط (ينقلها)
check(M.isEmpty(R(cover: true, facts: alive), others: [full]), false, "له غلاف: دمج فقط")
check(M.isEmpty(R(facts: alive, hasExtras: true), others: [full]), false, "له صور معرض أو طلبات معلّقة: دمج فقط")
check(M.deleteBlockedMessage, "لهذا الاسم صور أو طلبات معلّقة تُفقد بحذفه. استعمل «دمج» لتنتقل إلى الاسم الباقي.", "سطر المنع بعد الفحص")
check(M.deleteMessage(hint: "42501"), "الحذف متاح للمالك والمدير فقط.", "حذف: بلا صلاحية")
check(M.deleteMessage(hint: nil), "تعذّر الحذف. تحقّق من الاتصال ثم حاول مرة أخرى.", "حذف: خطأ عام")

// ٢) حراس السيرفر 20261127270000: متوفى/حيّ وميلادان متباعدان — لا زرّ حيث يرفض
check(M.compatible(F(deceased: true, birthYear: nil), F(deceased: false, birthYear: nil)), false, "متوفى وحيّ: لا دمج")
check(M.compatible(F(deceased: true, birthYear: 1950), F(deceased: true, birthYear: 1952)), true, "فرق سنتين: مسموح")
check(M.compatible(F(deceased: false, birthYear: 1950), F(deceased: false, birthYear: 1953)), false, "فرق ثلاث سنوات: لا دمج")
check(M.compatible(F(deceased: false, birthYear: nil), F(deceased: false, birthYear: 1953)), true, "ميلاد واحد فقط: مسموح")
check(M.refusalHint(F(deceased: true, birthYear: 1950), F(deceased: false, birthYear: 1990)), "deceased_mismatch", "الوفاة أولاً كالسيرفر")
check(M.refusalHint(F(deceased: false, birthYear: 1990), F(deceased: false, birthYear: 1950)), "birth_mismatch", "الميلاد")
check(M.refusalHint(F(deceased: false, birthYear: 1990), F(deceased: false, birthYear: 1991)), nil, "متوافقان")
check(M.year(fromBirthDate: "1975-04-02"), 1975, "سنة الميلاد من النص")
check(M.year(fromBirthDate: nil), nil, "بلا ميلاد")
check(M.year(fromBirthDate: "abcd"), nil, "نص غير صالح")
check(M.dismissFailedMessage, "تعذّر حفظ «ليسا مكرّرين». تحقّق من الاتصال ثم حاول مرة أخرى.", "فشل «ليسا مكرّرين»")

// ٣) نتيجة السيرفر
let json = """
{"kept":"x","removed":"y","tree":"men","moved_children":3,"moved_daughters":1,"moved_wives":1,"moved_women":2,
 "filled":["birth_date","mother_id"],"conflicts":[{"field":"death_date","kept":"1990-01-01","removed":"1991-01-01"}],
 "not_moved":["phone_number",{"table":"news_poll_votes","count":2},{"table":"odd_table","count":1}],"dry_run":true}
""".data(using: .utf8)!
let p = M.preview(from: json)!
check(p, M.Preview(tree: "men", children: 3, daughters: 1, wives: 1, women: 2, filled: ["birth_date", "mother_id"],
                   conflicts: ["death_date"], notMoved: ["phone_number"],
                   notMovedRows: [.init(table: "news_poll_votes", count: 2), .init(table: "odd_table", count: 1)]), "قراءة النتيجة")
let wjson = #"{"tree":"women","moved_children":2,"moved_daughters":1,"moved_wives":0,"moved_husbands":1,"moved_women":2,"filled":[],"conflicts":[],"not_moved":[]}"#.data(using: .utf8)!
check(M.preview(from: wjson)!.husbands, 1, "قراءة moved_husbands")
check(M.preview(from: "[]".data(using: .utf8)!) == nil, true, "ليست كائناً: nil")

// ٤) «ينتقل: …»
check(M.movesLine(p), "ينتقل: 3 أبناء، بنت واحدة، الزوجة، تاريخ الميلاد، الأم", "السطر الكامل")
check(M.movesLine(M.Preview(children: 1, wives: 2)), "ينتقل: ابن واحد، زوجتان", "ابن واحد وزوجتان")
check(M.movesLine(M.Preview(children: 2, daughters: 2)), "ينتقل: ابنان، بنتان", "المثنّى")
check(M.movesLine(M.Preview(children: 11, daughters: 12, wives: 3)), "ينتقل: 11 ابناً، 12 بنتاً، 3 زوجات", "فوق العشرة")
check(M.movesLine(M.Preview()), "لا ينتقل شيء؛ الاسم مكرر فقط.", "لا شيء")
check(M.movesLine(M.Preview(tree: "women", children: 2, daughters: 5, wives: 1, filled: ["husband_id"])),
      "ينتقل: ابنان، 5 بنات، الزوج", "شجرة النساء: الأبناء والبنات منفصلين، والزوج من الملء")
check(M.movesLine(M.preview(from: wjson)!), "ينتقل: ابنان، بنت واحدة، الزوج", "شجرة النساء: الزوج من moved_husbands")
check(M.movesLine(M.Preview(tree: "women", husbands: 1, filled: ["husband_id"])), "ينتقل: الزوج", "الزوج مرة واحدة")
check(M.conflictsLine(p), "يختلفان في: تاريخ الوفاة. تبقى قيمة الاسم الباقي.", "التعارض")
check(M.conflictsLine(M.Preview()), nil, "بلا تعارض")
check(M.notMovedLine(p), "لا ينتقل: رقم الهاتف، تصويتات الاستطلاعات (2)، سجلات أخرى (1).", "ما لا ينتقل مع الصفوف المتعارضة")
check(M.notMovedLine(M.Preview(notMovedRows: [.init(table: "app_usage_member_day", count: 1)])), "لا ينتقل: سجل الاستخدام (1).", "صفوف فقط")
check(M.deleteNote, "يُحذف الاسم المكرر نهائياً.", "ملاحظة الحذف")

// ٥) الأخطاء
check(M.message(hint: "remove_has_login").contains("حساب دخول"), true, "له حساب")
check(M.message(hint: "both_have_login"), "كلا الاسمين مرتبط بحساب دخول، فلا يمكن دمجهما.", "الاثنان لهما حساب")
check(M.message(hint: "different_father"), "لا يمكن الدمج؛ الاسمان ليسا تحت الأب نفسه.", "أب مختلف")
check(M.message(hint: "deceased_mismatch"), "لا يمكن دمج متوفى في حيّ — قد يكونان أخوين بنفس الاسم.", "متوفى وحيّ")
check(M.message(hint: "birth_mismatch"), "لا يمكن الدمج؛ سنتا الميلاد متباعدتان، وقد يكونان أخوين بنفس الاسم.", "ميلاد متباعد")
check(M.message(hint: nil), "تعذّر الدمج. تحقّق من الاتصال ثم حاول مرة أخرى.", "خطأ عام")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
