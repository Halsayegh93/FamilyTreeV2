// فحص «بنت بنت العائلة» (Components/Shared/DaughterDaughterRules.swift + MotherPickRules.isPlacedInWomenTree، الوحدة B1،
// طلب المالك ٢٠٢٦-١١-٢٧ «طبق الالية الحالية للتطبيق اذا بنت بنت العائلة تبي تدخل التطبيق») — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/b1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/MotherPickRules.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/DaughterDaughterRules.swift tests/admin-redesign/B1/main.swift \
//     && /private/tmp/claude-501/b1-logic
//
// ما يُفحص: نوع طلب النسب من حمولته (ابن بنت / بنت بنت) · خيار الأب حسب زوج الأم (مسجّل من خارج العائلة / من العائلة /
// لا زوج) · مطابقة الاسم المكتوب لزوج الأم (نفس قاعدة السيرفر lineage_names_match) · متى يُرسل · بطاقة شاشة الانتظار ·
// نصوص «الوارد» المؤنّثة · مكان الحساب في شجرة النساء لعقدة بمعرّف ملفه (أسماء 8070fd5c…).
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias DD = DaughterDaughterRules

// ١) نوع الطلب من الحمولة
check(DD.kind(ofDetails: #"{"v":3,"kind":"daughter_daughter","mother_id":"x"}"#), .daughterDaughter, "kind = daughter_daughter")
check(DD.kind(ofDetails: #"{"v":2,"mother_id":"x"}"#), .daughterSon, "no kind → daughter's son (old payloads)")
check(DD.kind(ofDetails: nil), .daughterSon, "nil details → daughter's son")
check(DD.kind(ofDetails: "not json"), .daughterSon, "bad json → daughter's son")

// ٢) خيار الأب حسب زوج الأم
let h = UUID()
check(DD.fatherOption(husbandId: h, husbandName: "حسن حسين علي الموسى", husbandInFamily: false),
      .registered(h, "حسن حسين علي الموسى"), "outside husband → offered as her father")
check(DD.fatherOption(husbandId: h, husbandName: "جاسم محمد المحمدعلي", husbandInFamily: true),
      .fatherInFamily("جاسم محمد المحمدعلي"), "family husband → her father is in the tree (blocked)")
check(DD.fatherOption(husbandId: nil, husbandName: nil, husbandInFamily: false), .typed, "no husband → type the name")

// ٣) مطابقة الاسم (السيرفر lineage_names_match)
check(DD.namesMatch("حسن حسين الموسى", "حسن حسين علي الموسى"), true, "shorter in order inside longer → match")
check(DD.namesMatch("حسن  حسين الموسي", "حسن حسين علي الموسى"), true, "ى/ي and spaces normalised")
check(DD.namesMatch("حسين حسن الموسى", "حسن حسين علي الموسى"), false, "different first name → no match")
check(DD.namesMatch("حسن الرشيد", "حسن حسين علي الموسى"), false, "word not in the longer → no match")
check(DD.namesMatch("حسن", "حسن حسين"), false, "one word only matches one word")
check(DD.namesMatch("حسن", "حسن"), true, "one word = one word")
check(DD.namesMatch("", "حسن"), false, "empty → no match")
check(DD.namesMatch("عبد الله سالم", "عبدالله سالم الرشيد"), true, "«عبد الله» joined like the server")

// ٤) متى يُرسل
check(DD.canSend(motherChosen: false, option: .typed, useRegistered: false, typedName: "حسن حسين الموسى", minWords: 3), false, "no mother → no")
check(DD.canSend(motherChosen: true, option: .typed, useRegistered: false, typedName: "حسن الموسى", minWords: 3), false, "2 words < 3 → no")
check(DD.canSend(motherChosen: true, option: .typed, useRegistered: false, typedName: " حسن  حسين الموسى ", minWords: 3), true, "3 words → yes")
check(DD.canSend(motherChosen: true, option: .registered(h, "x"), useRegistered: true, typedName: "", minWords: 3), true, "registered husband chosen → yes")
check(DD.canSend(motherChosen: true, option: .registered(h, "x"), useRegistered: false, typedName: "سالم أحمد الرشيد", minWords: 3), true, "typed another name → yes (admin decides)")
check(DD.canSend(motherChosen: true, option: .fatherInFamily("x"), useRegistered: false, typedName: "سالم أحمد الرشيد", minWords: 3), false, "family husband → never")

// تنبيه «يختلف عن زوج أمك» قبل الإرسال
check(DD.conflictName(option: .registered(h, "حسن حسين علي الموسى"), useRegistered: false, typedName: "سالم أحمد الرشيد"),
      "حسن حسين علي الموسى", "typed name ≠ registered husband → warn with his name")
check(DD.conflictName(option: .registered(h, "حسن حسين علي الموسى"), useRegistered: false, typedName: "حسن حسين الموسى"),
      nil, "typed name matches → no warning")
check(DD.conflictName(option: .typed, useRegistered: false, typedName: "سالم أحمد الرشيد"), nil, "no husband → no warning")

// ٥) بطاقة شاشة الانتظار
check(DD.waitingCard(eligible: true, pending: false, wasRejected: false), .offer, "eligible → offer")
check(DD.waitingCard(eligible: true, pending: false, wasRejected: true), .rejected, "rejected → send again")
check(DD.waitingCard(eligible: false, pending: true, wasRejected: false), .pending, "sent → under review")
check(DD.waitingCard(eligible: true, pending: true, wasRejected: false), .pending, "pending wins")
check(DD.waitingCard(eligible: false, pending: false, wasRejected: false), .hidden, "not eligible (picked a father / male / server off) → hidden")
check(DD.waitingCard(eligible: nil, pending: false, wasRejected: false), .hidden, "unknown (function missing) → hidden")

// ٦) نصوص «الوارد»
check(DD.inboxTitle(.daughterDaughter), "طلب نسب · بنت بنت", "inbox title (daughter)")
check(DD.inboxTitle(.daughterSon), "طلب نسب · ابن بنت", "inbox title (son)")
check(DD.approveNote(.daughterDaughter, isNewFather: true),
      "عند الموافقة يُضاف أبوها زوجاً لأمّها، وتُضاف هي تحتهما في شجرة النساء ويُفعَّل حسابها.", "approve note (new father)")
check(DD.approveNote(.daughterDaughter, isNewFather: false),
      "عند الموافقة تُضاف تحت أمّها وأبيها في شجرة النساء ويُفعَّل حسابها.", "approve note (registered father)")
check(DD.rejectNote(.daughterDaughter), "يصلها السبب وتختار من جديد، ويبقى طلب انضمامها معلّقاً.", "reject note (daughter)")
check(DD.selfLabel(.daughterDaughter), "هي بنفسها", "who registered (female)")
check(DD.selfLabel(.daughterSon), "هو بنفسه", "who registered (male)")
check(DD.placeNote(.daughterDaughter, motherName: "نورة"), "بنت بنت العائلة «نورة»", "tree place note (daughter)")
check(DD.placeNote(.daughterSon, motherName: "نورة"), "ابن بنت العائلة «نورة»", "tree place note (son)")

// ٧) مكان الحساب في شجرة النساء: عقدة بمعرّف ملفه (القاعدة الجديدة — النسخ القديمة تجدها بالمعرّف)
let asma = UUID(uuidString: "8070FD5C-8D2A-402A-A1A6-A4D8F76B6574")!
let outsideDad = UUID()
let familyDad = UUID()
typealias R = MotherPickRules
check(R.isPlacedInWomenTree(accountId: asma, nodeId: asma, nodeParentId: outsideDad, profileFatherId: nil), true,
      "node id = profile id, parent outside, no profile father → placed in women tree")
check(R.isPlacedInWomenTree(accountId: familyDad, nodeId: familyDad, nodeParentId: UUID(), profileFatherId: UUID()), false,
      "men mirror (profile has a father) → not placed")
check(R.isPlacedInWomenTree(accountId: familyDad, nodeId: familyDad, nodeParentId: nil, profileFatherId: nil), false,
      "root man's node (no parent) → not placed")
check(R.isPlacedInWomenTree(accountId: asma, nodeId: UUID()), true, "older daughter's son node (new id) → still placed")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
