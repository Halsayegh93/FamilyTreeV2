// فحص مربّعات الإدارة لطلبات الانضمام واستكمال التسجيل (Components/Shared/AdminJoinBoxRules.swift، الوحدة R2،
// المالك ٢٠٢٦-١١-٢٧ admin-boxes.png) — بلا محاكي، يُشغَّل من جذر المستودع:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/r2-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/MotherPickRules.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/SignupOriginRules.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/AdminJoinBoxRules.swift tests/admin-redesign/R2/main.swift \
//     && /private/tmp/claude-501/r2-logic
//
// ما يُفحص: نوع الطلب ومصدر الاقتراحات لكل نوع وجنس · خطوات المربّعات وأزرارها (التالي: الربط ← ربط ← تأكيد، عضو جديد/
// بنت جديدة ← اختيار الوالد ← تأكيد، «اعتماد» وحده، «ربط بالوالدة» ← تأكيد) · الشرائح بالقيم وحدها وبترتيب الوالد · الجد ·
// الميلاد (· الزوج للمرأة حين يفرّق) · الأخضر = يطابق الطلب بالتطبيع العربي · القارئ الصوتي يقرأ التسمية مع القيمة ·
// نصّ التأكيد · نفس الشرائح في مربّعي الأم والزوجة (DSWifeFlow) · «طلب استكمال البيانات» (الحقول لكل نوع، نصّ الإشعار
// كما يكتبه السيرفر، الحقول المميّزة في مربّع التسجيل) · اسم الوالدة مطلوب عند «نعم» · النصوص رسمية بلا عامية.
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias J = AdminJoinBoxRules

// ١) النوع والمصدر
check(J.kind(isOutside: false, isCompletion: false), .familyJoin, "no marker → from the family")
check(J.kind(isOutside: true, isCompletion: false), .outsideJoin, "outside marker → from outside")
check(J.kind(isOutside: false, isCompletion: true), .completion, "outside_typed lineage → completion")
check(J.source(.familyJoin, female: false), .familyTree, "man from the family → family tree suggestions")
check(J.source(.familyJoin, female: true), .womenDaughters, "woman from the family → women-tree daughters")
check(J.source(.outsideJoin, female: false), .none, "outside join → no suggestions")
check(J.source(.outsideJoin, female: true), .none, "outside join (female) → no suggestions")
check(J.source(.completion, female: false), .motherSuggestions, "completion → mother suggestions")

// ٢) الخطوات والأزرار
check(J.steps(.familyJoin), [.applicant, .link], "family: data → link (dots)")
check(J.steps(.outsideJoin), [.applicant], "outside: one box")
check(J.steps(.completion), [.applicant], "completion: one box with suggestions")
check(J.primary(.familyJoin, step: .applicant), .toLink, "family data box → «التالي: الربط»")
check(J.primary(.outsideJoin, step: .applicant), .approveOutside, "outside → «اعتماد»")
check(J.primary(.completion, step: .applicant), .linkMother, "completion → «ربط بالوالدة»")
check(J.primary(.familyJoin, step: .link), .link, "link box → «ربط»")
check(J.primary(.familyJoin, step: .newMember), .addAndLink, "new member box → «إضافة وربط»")
check(J.primary(.familyJoin, step: .confirm), .confirm, "confirm box → «ربط»")
check(J.secondary(.familyJoin, step: .link), .newMember, "link box secondary → new member/daughter")
check(J.secondary(.familyJoin, step: .applicant), .askMissing, "data box secondary → «طلب استكمال البيانات»")
check(J.secondary(.outsideJoin, step: .applicant), .askMissing, "outside: «اعتماد» + «طلب استكمال البيانات»")
check(J.secondary(.completion, step: .applicant), .askMissing, "completion: «ربط بالوالدة» + «طلب استكمال البيانات»")
check(J.secondary(.familyJoin, step: .askMissing), nil, "ask box: back + send only")
check(J.primary(.outsideJoin, step: .askMissing), .sendAsk, "ask box primary → send to the member")
check(J.next(after: .askMissing), .askMissing, "«طلب استكمال البيانات» → checklist box")
check(J.next(after: .sendAsk), nil, "«إرسال» runs the server call")
check(J.title(.askMissing, female: false), "طلب استكمال البيانات", "button: طلب استكمال البيانات")
check(J.title(.sendAsk, female: false), "إرسال الطلب إلى العضو", "button: إرسال الطلب إلى العضو")
check(J.dotIndex(.familyJoin, step: .askMissing), nil, "ask box has no dots")
check(J.next(after: .toLink), .link, "«التالي» → link box")
check(J.next(after: .link), .confirm, "«ربط» → confirm box")
check(J.next(after: .linkMother), .confirm, "«ربط بالوالدة» → confirm box")
check(J.next(after: .newMember), .newMember, "«عضو جديد» → pick father")
check(J.next(after: .addAndLink), .confirm, "«إضافة وربط» → confirm box")
check(J.next(after: .approveOutside), nil, "«اعتماد» runs directly")
check(J.next(after: .confirm), nil, "confirm runs the server call")
check(J.title(.link, female: false), "ربط", "button: ربط")
check(J.title(.toLink, female: false), "التالي: الربط", "button: next")
check(J.title(.approveOutside, female: false), "اعتماد", "button: اعتماد")
check(J.title(.linkMother, female: false), "ربط بالوالدة", "button: ربط بالوالدة")
check(J.title(.newMember, female: false), "عضو جديد", "men: عضو جديد")
check(J.title(.newMember, female: true), "بنت جديدة", "women: بنت جديدة")
check(J.title(.addAndLink, female: true), "إضافة وربط", "button: إضافة وربط")
check(J.Ar.confirmLine, "سيُربط الحساب بسجل الشجرة — لا يمكن التراجع من التطبيق.", "confirm wording")
check(J.dotIndex(.familyJoin, step: .link), 1, "link box = second dot")
check(J.dotIndex(.familyJoin, step: .confirm), nil, "confirm box has no dots")
check(J.dotIndex(.outsideJoin, step: .applicant), nil, "single box has no dots")

// ٣) الاقتراح: الاسم الكامل واضحاً (المالك «وضحلي الاسم الكامل»)، كلماته المطابقة للطلب خضراء، وشريحة الميلاد وحدها
//    (والزوج للمرأة حين يفرّق)
let a = UUID(), b = UUID(), c = UUID()
let men: [J.Candidate] = [
    J.Candidate(id: a, fullName: "عبدالله خالد سعود محمد الصايغ", birthYear: 1999, husband: nil),
    J.Candidate(id: b, fullName: "عبدالله خالد سعود علي الصايغ", birthYear: 1987, husband: nil)
]
let manExpect = J.Expect(typedName: "عبد الله خالد سعود محمد", birthYear: 1999, expectedHusband: nil)
let wordsA = J.nameWords(men[0], expect: manExpect)
check(wordsA.map(\.text), ["عبدالله", "خالد", "سعود", "محمد", "الصايغ"], "full name, word by word")
check(wordsA.map(\.matches), [true, true, true, true, false], "words matching the request are green (normalised, «عبد الله»)")
check(J.nameWords(men[1], expect: manExpect).map(\.matches), [true, true, true, false, false], "different 4th name → not green")
check(J.chips(men[0], among: men, expect: manExpect, women: false), [J.Chip(kind: .birth, value: "1999", matches: true)],
      "only the birth-year chip, green when it matches")
check(J.chips(men[1], among: men, expect: manExpect, women: false).map(\.matches), [false], "other birth year → not green")
check(J.chips(J.Candidate(id: c, fullName: "عبدالله خالد", birthYear: nil, husband: "س"), among: [], expect: manExpect,
              women: false), [], "men: no husband chip, no year → no chips")
let spaced = J.nameWords(J.Candidate(id: c, fullName: "أسامة  عبد الله إبراهيم", birthYear: nil, husband: nil),
                         expect: J.Expect(typedName: "اسامه عبدالله ابراهيم", birthYear: nil, expectedHusband: nil))
check(spaced.map(\.text), ["أسامة", "عبد الله", "إبراهيم"], "«عبد الله» stays one word as written")
check(spaced.map(\.matches), [true, true, true], "hamza / taa marbuta normalised")
check(J.nameWords(men[0], expect: J.Expect(typedName: "", birthYear: nil, expectedHusband: nil)).map(\.matches),
      [false, false, false, false, false], "no request name → nothing green")
check(J.spokenName(men[0]), "عبدالله خالد سعود محمد الصايغ", "VoiceOver reads the full name")

// المرأة: الزوج حين يفرّق بين متشابهتين فقط
let w1 = J.Candidate(id: a, fullName: "نورة خالد سعود المحمدعلي", birthYear: 2001, husband: nil)
let w2 = J.Candidate(id: b, fullName: "نوره خالد عبدالله المحمدعلي", birthYear: nil, husband: "بدر الكندري")
let w3 = J.Candidate(id: c, fullName: "نورة خالد سعود المحمدعلي", birthYear: nil, husband: "بدر الكندري")
let womanExpect = J.Expect(typedName: "نورة خالد سعود محمد", birthYear: 2001, expectedHusband: nil)
check(J.chips(w2, among: [w1, w2], expect: womanExpect, women: true), [], "husband hidden when names already differ")
check(J.chips(w3, among: [w1, w3], expect: womanExpect, women: true),
      [J.Chip(kind: .husband, value: "بدر الكندري", matches: false)], "husband shown when the names are the same")
check(J.chipText(J.Chip(kind: .husband, value: "بدر الكندري", matches: false)), "الزوج: بدر الكندري", "«الزوج: …» short chip")
check(J.chipText(J.Chip(kind: .birth, value: "1999", matches: true)), "1999", "birth chip: the year only")
check(J.husbandDisambiguates(w3, among: [w3]), false, "alone → husband not needed")

// استكمال التسجيل: الزوج يطابق الوالد المشتق ← أخضر ويُعرض
let m1 = J.Candidate(id: a, fullName: "فاطمة عبدالله أحمد صالح المحمدعلي", birthYear: nil, husband: "حسن حسين الموسى")
let m2 = J.Candidate(id: b, fullName: "فاطمة عبدالله محمد المحمدعلي", birthYear: 1975, husband: nil)
let motherExpect = J.Expect(typedName: "فاطمة عبدالله أحمد صالح", birthYear: nil, expectedHusband: "حسن حسين الموسى")
check(J.nameWords(m1, expect: motherExpect).map(\.matches), [true, true, true, true, false], "mother: typed four parts green")
check(J.nameWords(m2, expect: motherExpect).map(\.matches), [true, true, false, false], "mother: other grandfather not green")
check(J.chips(m1, among: [m1, m2], expect: motherExpect, women: true),
      [J.Chip(kind: .husband, value: "حسن حسين الموسى", matches: true)], "completion: matching husband shown green")
check(J.chips(m2, among: [m1, m2], expect: motherExpect, women: true), [J.Chip(kind: .birth, value: "1975", matches: false)],
      "completion: year only")

// ٤) القارئ الصوتي للشرائح
check(J.spoken(J.Chip(kind: .birth, value: "1987", matches: false)), "الميلاد 1987", "VoiceOver: birth")
check(J.spoken(J.Chip(kind: .husband, value: "بدر", matches: true)), "الزوج بدر، مطابق", "VoiceOver: husband + match")

// ٥) المرشّح من الشجرة: الاسم الكامل وسنة الميلاد
check(J.candidate(id: a, fullName: "  عبدالله  خالد ", birthDate: "1999-04-22", husband: nil),
      J.Candidate(id: a, fullName: "عبدالله خالد", birthYear: 1999, husband: nil), "candidate: tidy full name + year")
check(J.candidate(id: a, fullName: "x", birthDate: "bad", husband: "  "),
      J.Candidate(id: a, fullName: "x", birthYear: nil, husband: nil), "bad date, blank husband")
check(J.birthYear("2001"), 2001, "year only")
check(J.birthYear(nil), nil, "nil date")

// ٦) مربّعا الأم والزوجة (DSWifeFlow): الاسم الكامل + الميلاد + الزوج — الزوج المتوقَّع أخضر
let wifeParts = J.pickerChips(husband: "حسن حسين الموسى", birthYear: 1980, expectedHusband: "حسن حسين")
check(wifeParts, [J.Chip(kind: .birth, value: "1980", matches: false), J.Chip(kind: .husband, value: "حسن حسين الموسى", matches: true)],
      "picker chips: year · husband (expected husband green)")
check(J.pickerChips(husband: nil, birthYear: nil, expectedHusband: nil), [], "picker: nothing known → no chips")

// ٧) «طلب استكمال البيانات»
typealias MF = AdminJoinBoxRules.MissingField
check(J.askFields(.familyJoin), [.fullName, .birthDate, .gender, .photo], "family join: name · birth · gender · photo")
check(J.askFields(.outsideJoin), [.fullName, .family, .birthDate, .gender, .photo], "outside join: + family")
check(J.askFields(.completion), [.motherName], "completion: mother's name")
check(MF.allCases.map(\.rawValue), ["full_name", "family", "birth_date", "gender", "photo", "mother_name"], "server keys")
check([MF.fullName, .birthDate, .gender, .photo, .motherName, .family].map { J.fieldLabel($0) },
      ["الاسم الرباعي", "تاريخ الميلاد", "الجنس", "الصورة الشخصية", "اسم الوالدة", "العائلة"], "plain labels")
check(J.canSendAsk([], note: ""), false, "nothing ticked → can't send")
check(J.canSendAsk([.birthDate], note: ""), true, "one field → send (note optional)")
check(J.canSendAsk([.birthDate], note: String(repeating: "س", count: 201)), false, "note over 200 → no")
check(J.askMessage([.birthDate, .fullName], note: "  "), "يُرجى استكمال البيانات: الاسم الرباعي، تاريخ الميلاد.",
      "message in checklist order (= server text)")
check(J.askMessage([.motherName], note: " الاسم الرباعي "), "يُرجى استكمال البيانات: اسم الوالدة.\nالاسم الرباعي",
      "note on its own line, trimmed")
check(J.orderedKeys([.photo, .fullName]), ["full_name", "photo"], "sent keys in checklist order")
check(J.parseFields(["birth_date", "x", "gender", "birth_date"]), [.birthDate, .gender], "member side: known fields, no repeats")
check(J.signupHighlights([.fullName, .gender, .photo]), [.name, .gender], "sign-up box highlights its own fields")
check(J.signupHighlights([.family, .birthDate]), [.family, .birth], "family + birth")
check(J.Ar.askConfirmLine, "يصل العضو إشعار بهذا النص، ويبقى الطلب معلّقاً حتى يرسل البيانات.", "ask: what will happen")

// ٨) «نعم» تشترط اسم الوالدة (لا إرسال فارغ)
check(SignupOriginRules.canSendCompletion(motherInFamily: true, motherName: "   ", fatherName: "حسن حسين"), false,
      "«نعم» + empty mother's name → can't send")
check(J.motherNameMissing(motherInFamily: true, motherName: "فاطمة"), true, "«نعم» + one word → show the requirement")
check(J.motherNameMissing(motherInFamily: true, motherName: "فاطمة عبدالله أحمد"), true, "three words → still missing (four-part)")
check(J.motherNameMissing(motherInFamily: true, motherName: "فاطمة عبدالله أحمد حسن"), false, "four words → fine")
check(J.motherNameMissing(motherInFamily: false, motherName: ""), false, "«لا» → no name asked")

// ٩) النصوص رسمية (بلا «أبوك/أمك» وبلا عامية)
let informal = ["أبوك", "أمك", "حق", "شنو", "وش", "ابي", "تبي"]
for s in J.Ar.all {
    let tokens = s.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    check(tokens.filter { informal.contains($0) }, [], "formal: \(s.prefix(30))")
}

// نصوص المربّعات في المصدر (ما بين علامتي التنصيص) بلا عامية ولا «أبوك/أمك»
let sources = [
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminJoinBoxes.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/CompletionAskViews.swift",
]
for path in sources {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL cannot read \(path) (run from the repo root)"); failures += 1; continue
    }
    var hits: [String] = []
    for (i, line) in text.components(separatedBy: "\n").enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
        let parts = line.components(separatedBy: "\"")
        guard parts.count >= 3 else { continue }
        for j in stride(from: 1, to: parts.count, by: 2) {
            let tokens = parts[j].components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            if tokens.contains(where: informal.contains) { hits.append("\(i + 1): \(parts[j].prefix(40))") }
        }
    }
    check(hits, [], "formal source: \((path as NSString).lastPathComponent)")
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
