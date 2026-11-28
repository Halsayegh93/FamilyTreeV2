// فحص «هل أحد أفراد أسرتك من العائلة؟» والزوج/الزوجة (العيّنة spouse2.html، المالك ٢٠٢٦-١١-٢٨ «نفّذ كل شي») — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/sp1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/SignupOriginRules.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/SpouseLinkRules.swift tests/admin-redesign/SP1/main.swift \
//     && /private/tmp/claude-501/sp1-logic
//
// ما يُفحص: الصلة من الجنس · خطوات «استكمال التسجيل» (لا على الوالدة ← سؤال الأسرة؛ الزوجة/الزوج ← البيانات؛ «لا يوجد» ← مقيّد) ·
// اسم الزوج/الزوجة الرباعي (العائلة تُحذف وتُضاف ثابتة) · نوع الطلب في «الوارد» · أزرار بطاقة الإدارة حسب الاقتراحات ·
// النصوص رسمية بلا «زوجك/زوجتك/أمك».
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias R = SignupOriginRules
typealias S = SpouseLinkRules

// ١) الصلة من الجنس المسجّل
check(R.relation(gender: "male"), .wife, "man → «الزوجة»")
check(R.relation(gender: "female"), .husband, "woman → «الزوج»")
check(R.relation(gender: nil), .wife, "unknown gender → «الزوجة» (the server decides by gender too)")
check(R.Ar.spouseTile(.wife), "الزوجة", "tile: wife")
check(R.Ar.spouseTile(.husband), "الزوج", "tile: husband")
check(R.Ar.fromFamilyLine, "من عائلة المحمدعلي", "tile line")
check(R.Ar.noneTile, "لا يوجد", "none tile")

// ٢) الخطوات
check(R.afterQuestion(motherInFamily: true), .motherName, "mother yes → name")
check(R.afterQuestion(motherInFamily: false), .familyQuestion, "mother no → «هل أحد أفراد أسرتك من العائلة؟»")
check(R.afterFamily(hasSpouse: true), .spouseName, "spouse → data")
check(R.afterFamily(hasSpouse: false), .limited, "«لا يوجد» → limited (as «لا» was)")
check(R.CompletionStep.mother.rawValue, 0, "dot 1")
check(R.CompletionStep.family.rawValue, 1, "dot 2")
check(R.CompletionStep.spouse.rawValue, 2, "dot 3")
check(R.CompletionStep.allCases.count, 3, "three dots")
check(R.back(from: .spouse), .family, "back: data → question")
check(R.back(from: .family), .mother, "back: question → mother")
check(R.back(from: .mother), nil, "no back on the first step")

// ٣) اسم الزوج/الزوجة الرباعي
check(R.spouseNameComplete("فاطمة أحمد زيد حسن"), true, "four parts")
check(R.spouseNameComplete("فاطمة أحمد زيد"), false, "three parts are not enough")
check(R.spouseNameComplete("فاطمة عبد الله زيد حسن"), true, "«عبد الله» is one part")
check(R.spouseNameError(""), nil, "empty: no inline error")
check(R.spouseNameError("فاطمة أحمد", relation: .wife), R.Ar.spouseNameShort(.wife), "short wife name → error")
check(R.spouseNameError("زيد حسن", relation: .husband), R.Ar.spouseNameShort(.husband), "short husband name → error")
check(R.spouseNameToSend("  فاطمة  أحمد زيد حسن المحمدعلي "), "فاطمة أحمد زيد حسن", "typed family name dropped")
check(R.spouseNameToSend("فاطمة أحمد زيد حسن المحمد علي"), "فاطمة أحمد زيد حسن", "«المحمد علي» with a space dropped")
check(R.spouseNameToSend("فاطمة أحمد محمد علي"), "فاطمة أحمد محمد علي", "«محمد علي» as names is kept")
check(R.canSendSpouse("فاطمة أحمد زيد حسن"), true, "send")
check(R.canSendSpouse("فاطمة أحمد زيد المحمدعلي"), false, "family name is not a part")
check(R.canSendSpouse(String(repeating: "ا ", count: 70)), false, "too long")

// ٤) «الوارد»
check(R.isSpouseLink(details: #"{"v":1,"kind":"outside_spouse","relation":"wife"}"#), true, "spouse request")
check(R.isSpouseLink(details: #"{"v":4,"kind":"outside_typed"}"#), false, "mother request is not spouse")
check(R.isCompletionRequest(details: #"{"kind":"outside_spouse"}"#), true, "spouse counts as completion")
check(R.isCompletionRequest(details: #"{"kind":"outside_typed"}"#), true, "typed mother counts as completion")
check(R.isCompletionRequest(details: #"{"kind":"daughter_daughter"}"#), false, "daughter's daughter is not")
let d = S.Details.parse(#"{"kind":"outside_spouse","relation":"husband","spouse_typed_name":"زيد حسن علي","spouse_name":"زيد حسن علي المحمدعلي"}"#)
check(d?.relation, .husband, "parse relation")
check(d?.spouseName, "زيد حسن علي المحمدعلي", "parse name")
check(S.inboxTitle(.wife), "زوج من خارج العائلة", "card title when he wrote his wife")
check(S.inboxTitle(.husband), "زوجة من خارج العائلة", "card title when she wrote her husband")

// ٥) أزرار البطاقة
let m1 = S.Match(id: UUID(), fullName: "فاطمة أحمد زيد حسن المحمدعلي", fatherId: UUID(), canLink: true, wifeNodeId: nil)
let mBlocked = S.Match(id: UUID(), fullName: "فاطمة أحمد زيد حسن", fatherId: UUID(), canLink: false, wifeNodeId: nil)
let f1 = S.Father(id: UUID(), fullName: "أحمد زيد حسن علي المحمدعلي")
check(S.actions(.wife, matches: [m1], fathers: [f1]), [.link(m1.id), .pickManually, .askInfo], "found → «ربط» first")
check(S.actions(.wife, matches: [mBlocked], fathers: [f1]), [.addUnderFather(f1.id), .pickManually, .askInfo],
      "only unlinkable match → add under father")
check(S.actions(.wife, matches: [], fathers: [f1]), [.addUnderFather(f1.id), .pickManually, .askInfo], "not in app + father")
check(S.actions(.wife, matches: [], fathers: []), [.pickManually, .askInfo], "no father → manual or ask")
let man = S.Match(id: UUID(), fullName: "زيد حسن علي المحمدعلي", fatherId: UUID(), canLink: true, wifeNodeId: nil)
check(S.actions(.husband, matches: [man], fathers: []), [.link(man.id), .pickManually, .askInfo], "husband found → link (adds the wife)")
check(S.actions(.husband, matches: [], fathers: []), [.pickManually, .askInfo], "husband not found → manual or ask")
check(S.notInApp(.wife, matches: []), true, "banner when no match")
check(S.notInApp(.wife, matches: [mBlocked]), true, "banner when nothing linkable")
check(S.notInApp(.wife, matches: [m1]), false, "no banner when found")
check(S.firstName("فاطمة أحمد زيد حسن"), "فاطمة", "first name for «إضافة «فاطمة» تحت والدها»")
check(S.Ar.addUnderFather("فاطمة"), "إضافة «فاطمة» تحت والدها وربط الزوج", "add button wording")
check(S.Ar.notInApp(.wife), "الزوجة غير مضافة بالتطبيق", "banner wife")
check(S.Ar.notInApp(.husband), "الزوج غير مضاف بالتطبيق", "banner husband")

// ٥ب) اختيار زوجة الرجل قبل ربط «الزوج» (المنتقد ٢٠٢٦-١١-٢٨ — لا عقدة زوجة مكرّرة)
let wA = S.Wife(id: UUID(), fullName: "سارة علي", hasAccount: false, isDeceased: false, nameMatch: false)
let wB = S.Wife(id: UUID(), fullName: "مريم حسن", hasAccount: false, isDeceased: true, nameMatch: true)
let wC = S.Wife(id: UUID(), fullName: "نورة محمد", hasAccount: true)
check(S.linkableWives([wA, wB, wC]).map(\.id), [wB.id, wA.id], "linkable wives: no account, name match first")
check(S.needsWifeChoice(.husband, wives: [wA]), true, "husband with a free wife → choose")
check(S.needsWifeChoice(.husband, wives: [wC]), false, "only wives with accounts → no choice")
check(S.needsWifeChoice(.husband, wives: []), false, "no wives → link directly")
check(S.needsWifeChoice(.wife, wives: [wA]), false, "wife relation never asks")
let detail = #"[{"id": "\#(wA.id.uuidString)", "full_name": "سارة علي", "is_deceased": false}]"#
check(S.wives(fromErrorDetail: detail).map(\.id), [wA.id], "choose_wife DETAIL parsed")
check(S.wives(fromErrorDetail: nil).count, 0, "no detail → empty")
check(S.newWifeNode.uuidString, "00000000-0000-0000-0000-000000000000", "«زوجة أخرى» sentinel")
let sugg = try! JSONDecoder().decode(S.Suggestions.self, from: Data(#"{"matches":[{"id":"\#(man.id.uuidString)","full_name":"زيد","can_link":true,"wives":[{"id":"\#(wB.id.uuidString)","full_name":"مريم حسن","has_account":false,"is_deceased":true,"name_match":true}]}]}"#.utf8))
check(sugg.matches.first?.wives.map(\.id) ?? [], [wB.id], "match decodes wives")
check(sugg.matches.first?.wives.first?.nameMatch ?? false, true, "wife name_match decoded")

// ٦) نصوص رسمية
let forbidden = ["زوجك", "زوجتك", "أمك", "أبوك", "أباك", "أبيك"]
for s in R.Ar.all + S.Ar.all {
    let bad = forbidden.filter { s.contains($0) }
    check(bad, [], "formal: \(s.prefix(40))")
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
