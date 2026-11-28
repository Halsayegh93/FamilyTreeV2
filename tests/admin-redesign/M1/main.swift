// فحص «أم ابن البنت» (Components/Shared/MotherPickRules.swift + Core/ArabicTextNormalizer.swift، الوحدة M1، بلاغ المالك ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/m1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/MotherPickRules.swift tests/admin-redesign/M1/main.swift \
//     && /private/tmp/claude-501/m1-logic
//
// ما يُفحص: ابن البنت (أبوه عقدة في شجرة النساء لا في `profiles`) يرى أمّه المتزوجة بأبيه بين بنات جدّه ·
// عقدته في شجرة النساء (صفّ ابن البنت ← العقدة المربوطة ← معرّفه) · التطبيع الواحد (ة/ه، أ/إ/آ/ا، ى/ي، التطويل،
// التشكيل) في البحث وفي «اسم بنت» · السطر الثاني لصفّ البنت «بنت فلان · زوجة فلان» / «غير متزوجة».
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias R = MotherPickRules

// الحالة الحقيقية: «حسين علي محمد الصاغة» — عقدته aae22d1c، أبوه «علي» a0ff5ad7 (من خارج العائلة، في شجرة النساء)،
// أمّه «سهيلة» e8492164 بنت «علي موسى…» وزوجها a0ff5ad7. ملفه في `profiles` بلا أب.
let husseinProfile = UUID(uuidString: "84E050F8-2E64-4FAD-A6EF-9FDBF4A62E16")!
let husseinNode = UUID(uuidString: "AAE22D1C-F4FD-48CC-A082-316DA048CFD3")!
let aliOutside = UUID(uuidString: "A0FF5AD7-9051-4BD1-8ED9-0233E4759AB9")!
let suhaila = UUID(uuidString: "E8492164-7033-47BB-BF8C-160F56A6F0A1")!
let otherHusband = UUID()
let otherDaughter = UUID()

// ١) أبو الشخص للمقارنة
check(R.personFatherIds(profileFatherId: nil, womenNodeFatherId: aliOutside), [aliOutside],
      "daughter's son: father = his women-tree father (not nil)")
let pf = UUID()
check(R.personFatherIds(profileFatherId: pf, womenNodeFatherId: nil), [pf], "family man: father from profiles")
check(R.personFatherIds(profileFatherId: pf, womenNodeFatherId: pf), [pf], "same father both trees → one id")
check(R.personFatherIds(profileFatherId: nil, womenNodeFatherId: nil), [], "no father anywhere → empty")

// ٢) قاعدة بنات الجدّ في قائمة الأم
let fathers = R.personFatherIds(profileFatherId: nil, womenNodeFatherId: aliOutside)
check(R.isMotherCandidate(daughterId: suhaila, husbandId: aliOutside, personFatherIds: fathers, knownMotherId: nil), true,
      "daughter's son: his mother (married to his women-tree father) shows")
check(R.isMotherCandidate(daughterId: suhaila, husbandId: aliOutside, personFatherIds: [], knownMotherId: nil), false,
      "old bug reproduced: nil father hides every married daughter")
check(R.isMotherCandidate(daughterId: suhaila, husbandId: aliOutside, personFatherIds: [], knownMotherId: suhaila), true,
      "his recorded mother always shows, even if the father is unknown")
check(R.isMotherCandidate(daughterId: otherDaughter, husbandId: otherHusband, personFatherIds: fathers, knownMotherId: suhaila), false,
      "daughter married to another man stays hidden")
check(R.isMotherCandidate(daughterId: otherDaughter, husbandId: nil, personFatherIds: fathers, knownMotherId: nil), true,
      "unmarried daughter shows")
check(R.isMotherCandidate(daughterId: otherDaughter, husbandId: pf, personFatherIds: [pf], knownMotherId: nil), true,
      "family man: daughter married to his father shows (unchanged)")

// ٣) عقدة الحساب في شجرة النساء
let inTree: Set<UUID> = [husseinNode, aliOutside, suhaila]
check(R.womenNodeId(accountId: husseinProfile, lineageNodeId: husseinNode, linkedNodeId: nil, existsInWomenTree: { inTree.contains($0) }),
      husseinNode, "node from daughter_son_lineage")
check(R.womenNodeId(accountId: husseinProfile, lineageNodeId: nil, linkedNodeId: husseinNode, existsInWomenTree: { inTree.contains($0) }),
      husseinNode, "node from linked account (womanByLinkedUser)")
check(R.womenNodeId(accountId: pf, lineageNodeId: nil, linkedNodeId: nil, existsInWomenTree: { $0 == pf }),
      pf, "family man: his mirror node has his own id")
check(R.womenNodeId(accountId: pf, lineageNodeId: nil, linkedNodeId: nil, existsInWomenTree: { _ in false }),
      nil, "no node → nil")
check(R.isPlacedInWomenTree(accountId: husseinProfile, nodeId: husseinNode), true, "daughter's son is placed in the women tree")
check(R.isPlacedInWomenTree(accountId: pf, nodeId: pf), false, "mirror node (same id) is not a women-tree place")
check(R.isPlacedInWomenTree(accountId: pf, nodeId: nil), false, "no node → not placed")

// ٤) التطبيع الواحد
let N = ArabicTextNormalizer.self
check(N.normalizeLetters("سهيلة"), N.normalizeLetters("سهيله"), "ة/ه at word end are equal")
check(N.normalizeLetters("سهيلة علي"), "سهيله علي", "ة→ه per word")
check(N.normalizeLetters("ةحمد"), "ةحمد", "ة only at word end")
check(N.normalizeLetters("أحمد إبراهيم آمنة ٱلله"), "احمد ابراهيم امنه الله", "أ/إ/آ/ٱ → ا")
check(N.normalizeLetters("ليلى"), "ليلي", "ى → ي")
check(N.normalizeLetters("سهـــيلة"), "سهيله", "tatweel removed")
check(N.normalizeLetters("سُهَيْلَةُ"), "سهيله", "diacritics removed")
check(N.normalizeLetters("\u{200F}مريم\u{200F}"), "مريم", "invisible marks removed")
check(N.normalizeForSearch("سهـيلة"), N.normalizeForSearch("سهيله"), "search: tatweel + ة")
check(NameSearch.matches(query: "سهيلة", candidate: "سهيله علي موسى"), true, "search «سهيلة» finds «سهيله»")
check(NameSearch.matches(query: "سهيله", candidate: "سهيلة علي موسى"), true, "search «سهيله» finds «سهيلة»")
check(NameSearch.matches(query: "اسامه", candidate: "أسامة"), true, "search ا/أ + ة/ه")
check(NameSearch.matches(query: "ليلي", candidate: "ليلى"), true, "search ى/ي")
check(NameSearch.matches(query: "سهـيلة", candidate: "سهيلة"), true, "search ignores tatweel")
check(NameSearch.matches(query: "مُحَمَّد", candidate: "محمد"), true, "search ignores diacritics")
check(NameSearch.matches(query: "سهيلة", candidate: "سهى"), false, "different name not matched")
// «اسم بنت» في مربّع الابن يستعمل التطبيع نفسه
check(FamilyTreeMenOnly.normalizedFirstName("سهـيلة علي"), N.normalizeLetters("سهيله"), "men-only first name uses the shared normaliser")

// ٥) السطر الثاني لصفّ البنت
check(R.disambiguationLine(fatherName: "علي موسى حسين ابراهيم(العطار) المحمدعلي", husbandName: "علي محمد الصاغة", isMarried: true),
      "بنت علي موسى حسين · زوجة علي محمد الصاغة", "married: father · husband (three words each)")
check(R.disambiguationLine(fatherName: "علي موسى", husbandName: nil, isMarried: false),
      "بنت علي موسى · غير متزوجة", "unmarried")
check(R.disambiguationLine(fatherName: "علي موسى", husbandName: nil, isMarried: true),
      "بنت علي موسى · متزوجة", "married, husband unknown")
check(R.disambiguationLine(fatherName: nil, husbandName: "علي محمد", isMarried: true),
      "زوجة علي محمد", "no father name → husband only")
check(R.disambiguationLine(fatherName: "  ", husbandName: "", isMarried: false),
      "غير متزوجة", "blank names → status only")
check(R.shortName("  عبد الله   محمد  علي حسن "), "عبد الله محمد", "short name: three words, spaces collapsed")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILED"); exit(1) }
