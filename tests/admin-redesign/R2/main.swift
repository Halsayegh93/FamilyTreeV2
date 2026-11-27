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

// ٣) الشرائح: القيم وحدها بالترتيب، والأخضر = يطابق الطلب
let a = UUID(), b = UUID(), c = UUID()
let men: [J.Candidate] = [
    J.Candidate(id: a, firstName: "عبدالله", father: "خالد", grandfather: "سعود", birthYear: 1999, husband: nil),
    J.Candidate(id: b, firstName: "عبدالله", father: "خالد", grandfather: "سعود", birthYear: 1987, husband: nil)
]
let manExpect = J.Expect(typedName: "عبد الله خالد سعود محمد", birthYear: 1999, expectedHusband: nil)
let chipsA = J.chips(men[0], among: men, expect: manExpect, women: false)
check(chipsA.map(\.kind), [.father, .grandfather, .birth], "order: father · grandfather · birth year")
check(chipsA.map(\.value), ["خالد", "سعود", "1999"], "values only")
check(chipsA.map(\.matches), [true, true, true], "all match the request → green")
check(J.chips(men[1], among: men, expect: manExpect, women: false).map(\.matches), [true, true, false],
      "different birth year → not green")
check(J.chips(J.Candidate(id: c, firstName: "عبدالله", father: "خالد", grandfather: nil, birthYear: nil, husband: nil),
              among: [], expect: manExpect, women: false).map(\.kind), [.father], "missing values are skipped")
check(J.chips(men[0], among: men, expect: J.Expect(typedName: "عبدالله خالد", birthYear: nil, expectedHusband: nil),
              women: false).map(\.matches), [true, false, false], "no typed grandfather/birth → not green")
// التطبيع العربي: همزات وتاء مربوطة و«عبد الله»
let norm = J.Candidate(id: c, firstName: "أسامة", father: "عبد الله", grandfather: "إبراهيم", birthYear: nil, husband: nil)
check(J.chips(norm, among: [], expect: J.Expect(typedName: "اسامه عبدالله ابراهيم", birthYear: nil, expectedHusband: nil),
              women: false).map(\.matches), [true, true], "normalised Arabic matches")
// الرجل لا يُعرض له زوج
check(J.chips(J.Candidate(id: c, firstName: "x", father: "خالد", grandfather: nil, birthYear: nil, husband: "س"),
              among: [], expect: manExpect, women: false).map(\.kind), [.father], "men: no husband chip")

// المرأة: الزوج حين يفرّق بين متشابهتين فقط
let w1 = J.Candidate(id: a, firstName: "نورة", father: "خالد", grandfather: "سعود", birthYear: 2001, husband: nil)
let w2 = J.Candidate(id: b, firstName: "نوره", father: "خالد", grandfather: "عبدالله", birthYear: nil, husband: "بدر الكندري")
let w3 = J.Candidate(id: c, firstName: "نورة", father: "خالد", grandfather: "سعود", birthYear: nil, husband: "بدر الكندري")
let womanExpect = J.Expect(typedName: "نورة خالد سعود محمد", birthYear: 2001, expectedHusband: nil)
check(J.chips(w2, among: [w1, w2], expect: womanExpect, women: true).map(\.kind), [.father, .grandfather],
      "husband hidden when names already differ")
check(J.chips(w3, among: [w1, w3], expect: womanExpect, women: true).map(\.kind), [.father, .grandfather, .husband],
      "husband shown when same first · father · grandfather")
check(J.chips(w3, among: [w1, w3], expect: womanExpect, women: true).map(\.value), ["خالد", "سعود", "بدر الكندري"],
      "husband value only")
check(J.husbandDisambiguates(w3, among: [w3]), false, "alone → husband not needed")

// استكمال التسجيل: الزوج يطابق الوالد المشتق ← أخضر ويُعرض
let m1 = J.Candidate(id: a, firstName: "فاطمة", father: "عبدالله", grandfather: "أحمد", birthYear: nil, husband: "حسن حسين الموسى")
let m2 = J.Candidate(id: b, firstName: "فاطمة", father: "عبدالله", grandfather: "محمد", birthYear: 1975, husband: nil)
let motherExpect = J.Expect(typedName: "فاطمة عبدالله أحمد صالح", birthYear: nil, expectedHusband: "حسن حسين الموسى")
check(J.chips(m1, among: [m1, m2], expect: motherExpect, women: true).map(\.kind), [.father, .grandfather, .husband],
      "completion: husband shown when it matches the derived father")
check(J.chips(m1, among: [m1, m2], expect: motherExpect, women: true).map(\.matches), [true, true, true],
      "completion: father · grandfather · husband green")
check(J.chips(m2, among: [m1, m2], expect: motherExpect, women: true).map(\.matches), [true, false, false],
      "completion: other grandfather not green")

// ٤) القارئ الصوتي يقرأ التسمية مع القيمة
check(J.spoken(J.Chip(kind: .father, value: "خالد", matches: true)), "الوالد خالد، مطابق", "VoiceOver: label + value + match")
check(J.spoken(J.Chip(kind: .birth, value: "1987", matches: false)), "الميلاد 1987", "VoiceOver: birth")
check(J.spoken(J.Chip(kind: .husband, value: "بدر", matches: false)), "الزوج بدر", "VoiceOver: husband")

// ٥) بناء المرشّح من الشجرة (الأب والجد بالاسم الأول)
let gid = UUID(), fid = UUID()
let names: [UUID: (first: String, fatherId: UUID?)] = [fid: ("خالد", gid), gid: ("سعود", nil)]
let built = J.candidate(id: a, firstName: "عبدالله", fatherId: fid, birthDate: "1999-04-22", husband: nil) { names[$0] }
check(built, J.Candidate(id: a, firstName: "عبدالله", father: "خالد", grandfather: "سعود", birthYear: 1999, husband: nil),
      "candidate from the tree: father · grandfather · birth year")
check(J.candidate(id: a, firstName: "x", fatherId: nil, birthDate: "bad", husband: "  ") { names[$0] },
      J.Candidate(id: a, firstName: "x", father: nil, grandfather: nil, birthYear: nil, husband: nil), "no father, bad date")
check(J.birthYear("2001"), 2001, "year only")
check(J.birthYear(nil), nil, "nil date")

// ٦) مربّعا الأم والزوجة: نفس الشرائح (DSWifeFlow) — الزوج المتوقَّع أخضر
let wifeParts = J.pickerChips(father: "عبد الله أحمد", husband: "حسن حسين الموسى", birthYear: 1980,
                              expectedHusband: "حسن حسين")
check(wifeParts.map(\.kind), [.father, .grandfather, .birth, .husband], "picker chips order")
check(wifeParts.map(\.value), ["عبدالله", "أحمد", "1980", "حسن حسين الموسى"], "picker chip values (عبد الله one word)")
check(wifeParts.map(\.matches), [false, false, false, true], "picker: expected husband green")
check(J.pickerChips(father: nil, husband: nil, birthYear: nil, expectedHusband: nil), [], "picker: nothing known → no chips")

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
check(J.motherNameMissing(motherInFamily: true, motherName: "فاطمة عبدالله أحمد"), false, "three words → fine")
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
