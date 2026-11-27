// فحص «التسجيل: من العائلة أو من خارجها» (Components/Shared/SignupOriginRules.swift، الوحدة R1، موافقة المالك ٢٠٢٦-١١-٢٧
// «خل من او من خارج العائلة بدون نص فرعي») — بلا محاكي، يُشغَّل من جذر المستودع (يقرأ ملفات المصدر لفحص النصوص):
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/r1-logic \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/FamilyTreeMenOnly.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/MotherPickRules.swift \
//     FamilyTreeV2/FamilyTreeV2/Components/Shared/SignupOriginRules.swift tests/admin-redesign/R1/main.swift \
//     && /private/tmp/claude-501/r1-logic
//
// ما يُفحص: مربّعا التسجيل (الخياران ← مربّع البيانات بحقوله وترتيبها لكل مصدر، ومتى يُرسل) · العائلة المحفوظة · علامتا الطلب ·
// مربّع «استكمال التسجيل» («هل الأم من العائلة؟» نعم ← اسم الوالدة، لا ← صلاحيات محدودة مباشرة؛ الوالد من الاسم المسجّل) ·
// «الوارد»: طلبات الانضمام من العائلة / من خارجها (الأعداد = الصفوف) · نوع طلب «استكمال التسجيل» ·
// النصوص رسمية بلا «أبوك/أباك/أبيك/أمك» (نصوص الشاشات + النصوص الموجّهة للعضو في ملفات المصدر).
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias R = SignupOriginRules

// ١) مربّع الخيارين
check(R.Ar.choices, ["من العائلة", "من خارج العائلة"], "exactly two choices, in order")
check(R.Ar.chooseBoxTitle, "يُرجى تحديد صلتك بالعائلة", "choice box title")

// ٢) مربّع البيانات: الحقول وترتيبها
check(R.fields(.family), [.name, .birth, .gender], "family: name · birth · gender (no family, no father)")
check(R.fields(.outside), [.name, .family, .birth, .gender], "outside: name · family · birth · gender")
check(R.Ar.fieldLabels(.family), ["الاسم الرباعي", "تاريخ الميلاد", "الجنس"], "family labels")
check(R.Ar.fieldLabels(.outside), ["الاسم الثلاثي", "العائلة", "تاريخ الميلاد", "الجنس"], "outside labels (owner's order)")

func send(_ o: R.Origin, name: String = "سالم ناصر فهد", family: String = "العتيبي", born: Bool = true, age: Int? = 22,
          gender: String = "male") -> Bool {
    R.canSubmit(origin: o, name: name, family: family, birthChosen: born, age: age, gender: gender)
}
check(send(.outside), true, "outside: all filled → send")
check(send(.family), false, "family: three words is not a four-part name")
check(send(.family, name: "سالم ناصر فهد علي"), true, "family: four words → send")
check(send(.family, name: "سالم عبد الله فهد علي"), true, "family: «عبد الله» is one part")
check(send(.family, name: "سالم عبد الله فهد"), false, "family: «عبد الله» counted once → three parts")
check(send(.outside, name: "سالم عبد الله"), false, "outside: «عبد الله» counted once → two parts")
check(send(.outside, name: "سالم ناصر"), false, "outside: three-part name required")
check(send(.outside, family: ""), false, "outside: family required")
check(send(.outside, family: " ا "), false, "outside: family needs two letters")
check(send(.family, name: "سالم ناصر", family: ""), false, "family: two words not enough")
check(send(.family, name: "سالم"), false, "family: one word is not a name")
check(send(.outside, gender: ""), false, "gender required")
check(send(.outside, gender: "female"), true, "female too")
check(send(.outside, born: false), false, "birth date required")
check(send(.outside, age: 12), false, "under 13 → no account")
check(send(.outside, age: 13), true, "13 → allowed (guardian note)")
check(R.familyToSave(origin: .family, typed: "أي شيء"), "المحمدعلي", "family origin saves «المحمدعلي»")
check(R.familyToSave(origin: .outside, typed: "  الموسى "), "الموسى", "outside saves the typed family")

// ٣) علامتا الطلب
check(R.isOutside(details: "طلب انضمام — من خارج العائلة" + R.outsideMarker), true, "outside marker found")
check(R.isOutside(details: "طلب انضمام جديد" + R.familyMarker), false, "family marker is not outside")
check(R.isOutside(details: nil), false, "nil → no marker")
check(R.outsideMarker.hasPrefix("|") && R.familyMarker.hasPrefix("|"), true, "markers are |key:value before matched_ids")

// ٤) مربّع «استكمال التسجيل»
check(R.Ar.motherQuestion, "هل الأم من العائلة؟", "owner's question wording")
check(R.afterQuestion(motherInFamily: true), .motherName, "«نعم» → mother's name in the same box")
check(R.afterQuestion(motherInFamily: false), .limited, "«لا» → limited, no request")
check(R.derivedFatherName(fullName: " سالم  ناصر فهد العتيبي "), "ناصر فهد العتيبي", "father = registered name after the first")
check(R.derivedFatherName(fullName: "سالم العتيبي"), nil, "father needs two words")
check(R.canSendCompletion(motherInFamily: true, motherName: "منيرة عبدالله أحمد صالح", fatherName: "ناصر فهد"), true, "«نعم» + name → send")
check(R.canSendCompletion(motherInFamily: true, motherName: "منيرة عبدالله أحمد", fatherName: "ناصر فهد"), false, "mother name needs four words")
check(R.canSendCompletion(motherInFamily: true, motherName: "منيرة عبد الله أحمد", fatherName: "ناصر فهد"), false, "mother: «عبد الله» is one part")
check(R.canSendCompletion(motherInFamily: true, motherName: "منيرة عبدالله أحمد صالح", fatherName: nil), false, "no derived father → no send")
check(R.canSendCompletion(motherInFamily: false, motherName: "منيرة عبدالله أحمد", fatherName: "ناصر فهد"), false, "«لا» never sends a request")
check(R.canSendCompletion(motherInFamily: nil, motherName: "منيرة عبدالله أحمد", fatherName: "ناصر فهد"), false, "unanswered → no send")
check(R.isTypedLineage(details: #"{"v":4,"kind":"outside_typed"}"#), true, "outside_typed lineage request")
check(R.isTypedLineage(details: #"{"v":3,"kind":"daughter_daughter"}"#), false, "daughter's daughter is not typed")
check(R.isTypedLineage(details: nil), false, "nil → not typed")

// ٥) «الوارد»: من العائلة / من خارج العائلة — الأعداد = الصفوف
let joinDetails: [String?] = [nil, "طلب انضمام جديد" + R.familyMarker, "x" + R.outsideMarker, "طلب ربط|matched_ids:a",
                              "y" + R.outsideMarker + "|matched_ids:b"]
let origins = joinDetails.map(R.joinOrigin(details:))
check(origins, [.family, .family, .outside, .family, .outside], "old requests without a marker count as family")
let counts = R.originCounts(joins: origins)
check(counts, R.OriginCounts(family: 3, outside: 2), "counts: join rows only (completion requests show their own count on their row)")
let items: [R.JoinOrigin?] = origins + [nil, nil]   // طلبان من نوع آخر
check(items.filter { R.passes(.family, origin: $0) }.count, counts.family, "family chip rows = family count")
check(items.filter { R.passes(.outside, origin: $0) }.count, counts.outside, "outside chip number = outside join rows listed")
check(items.filter { R.passes(.all, origin: $0) }.count, items.count, "«الكل» shows everything")

// ٥ب) صفّ المقترحة: شرائح «الوالد» · «الجد» · «الميلاد» · «الزوج» بدل السطر الطويل
typealias MP = MotherPickRules
check(MP.disambiguationParts(fatherName: "عبدالله خالد سعود محمد", husbandName: "فهد ناصر العتيبي الكبير", birthYear: 1975),
      [MP.NamePart(label: "الوالد", value: "عبدالله"), MP.NamePart(label: "الجد", value: "خالد"),
       MP.NamePart(label: "الميلاد", value: "1975"), MP.NamePart(label: "الزوج", value: "فهد ناصر العتيبي")],
      "parts: father · grandfather · birth · husband (short)")
check(MP.disambiguationParts(fatherName: "خالد", husbandName: nil).map(\.label), ["الوالد"], "no grandfather / husband → omitted")
check(MP.disambiguationParts(fatherName: nil, husbandName: "  "), [], "nothing known → no chips")

// ٥ج) الشريحة الخضراء: ما يطابق بيانات الطلب بالتطبيع العربي
let partsM = MP.markMatches(MP.disambiguationParts(fatherName: "عبد الله أحمد صالح", husbandName: "حسن حسين علي الموسى",
                                                   birthYear: 1975),
                            typedName: "فاطمه عبدالله احمد", expectedHusband: "حسن حسين الموسى", birthYear: 1975)
check(partsM.map(\.matches), [true, true, true, true], "«عبد الله»=«عبدالله»، أحمد=احمد، الزوج بأول كلمتين، السنة")
let partsN = MP.markMatches(MP.disambiguationParts(fatherName: "خالد سعود", husbandName: "فهد ناصر العتيبي"),
                            typedName: "فاطمة عبدالله أحمد", expectedHusband: "حسن حسين الموسى")
check(partsN.map(\.matches), [false, false, false], "different father, grandfather and husband → not green")
check(MP.markMatches(MP.disambiguationParts(fatherName: "عبدالله", husbandName: nil), typedName: "فاطمة", expectedHusband: nil)
        .map(\.matches), [false], "typed name without a father part → nothing green")

// ٦) النصوص الرسمية
let forbidden = ["أبوك", "أباك", "أبيك", "أمك", "أبوي", "أمي"]
func bad(_ s: String) -> [String] {
    let plain = s.replacingOccurrences(of: "\u{0651}", with: "") // الشدّة
    let tokens = plain.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    return tokens.filter { t in forbidden.contains { t == $0 || t.hasSuffix($0) && t.count <= $0.count + 2 } }
}
for s in R.Ar.all { check(bad(s), [], "formal: \(s.prefix(40))") }
check(R.Ar.waitingBody, "تم استلام طلبك، وستتم مراجعته من قِبل الإدارة. سيصلك إشعار عند اعتماده.", "waiting text verbatim")
check(R.Ar.submit, "إرسال الطلب إلى الإدارة", "submit button verbatim")
check(R.Ar.completeTitle, "استكمال التسجيل", "post-approval box title")
check(R.Ar.all.contains { $0.contains("مَن أنت") }, false, "no «مَن أنت»")

// نصوص العضو في المصدر (ما بين علامتي التنصيص): شاشات التسجيل والانتظار و«أكمل حسابك» و«بنت بنت»
let sources = [
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/SignupOriginViews.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/CompleteRegistrationViews.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/OutsideFamilyJoin.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/DaughterLineageViews.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/WaitingForApprovalView.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/RegistrationView.swift",
    "FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/DaughterSons.swift",
]
for path in sources {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL cannot read \(path) (run from the repo root)"); failures += 1; continue
    }
    var hits: [String] = []
    for (i, line) in text.components(separatedBy: "\n").enumerated() {
        let parts = line.components(separatedBy: "\"")
        guard parts.count >= 3 else { continue }
        for j in stride(from: 1, to: parts.count, by: 2) where !bad(parts[j]).isEmpty {
            hits.append("\(i + 1): \(parts[j].prefix(50))")
        }
    }
    check(hits, [], "no forbidden words in \((path as NSString).lastPathComponent)")
}


// ٧) وضوح الحقول (المالك ٢٠٢٦-١١-٢٧ «كتابة البيانات… واضحة ومفهومة») + صورة الذكر
check(R.missingFields(origin: .outside, name: "", family: "", birthChosen: false, age: nil, gender: ""),
      [.name, .family, .birth, .gender], "outside: all missing, in field order")
check(R.missingFields(origin: .family, name: "محمد عبدالله علي أحمد", family: "", birthChosen: true, age: 30, gender: "male"),
      [], "family: complete → nothing missing")
check(R.missingFields(origin: .family, name: "محمد عبدالله علي أحمد", family: "", birthChosen: true, age: 10, gender: "male"),
      [.birth], "under 13 → birth still missing")
check(R.nameError("", origin: .outside), nil, "empty name: no inline error (the missing line says it)")
check(R.nameError("سالم ناصر", origin: .outside), R.Ar.outsideNameShort, "outside: two words → three-part error")
check(R.nameError("سالم ناصر فهد", origin: .outside), nil, "outside: three words ok")
check(R.nameError("سالم", origin: .family), R.Ar.familyNameShort, "family: one word → error")
check(R.nameError("سالم ناصر فهد", origin: .family), R.Ar.familyNameShort, "family: three words → four-part error")
check(R.nameError("سالم ناصر فهد علي", origin: .family), nil, "family: four words ok")
check(R.familyError("ا"), R.Ar.familyShort, "family name: one letter → error")
check(R.familyError(""), nil, "family name empty: no inline error")
check(R.motherNameError("فاطمة أحمد"), R.Ar.motherNameShort, "mother: two words → error")
check(R.motherNameError("فاطمة أحمد علي"), R.Ar.motherNameShort, "mother: three words → error")
check(R.motherNameError("فاطمة أحمد علي حسن"), nil, "mother: four words ok")
check(R.Ar.missingLine(["الاسم الثلاثي", "الجنس"]), "لإرسال الطلب يُرجى استكمال: الاسم الثلاثي، الجنس", "missing line wording")
for ex in [R.Ar.familyNameExample, R.Ar.outsideNameExample, R.Ar.motherNameExample, R.Ar.familyPlaceholder] {
    check(ex.hasPrefix("مثال: "), true, "placeholder is an example: \(ex)")
}
check(R.showsPhoto(gender: ""), false, "no photo before gender is chosen (gender first)")
check(R.showsPhoto(gender: "male"), true, "photo shown for male")
check(R.showsPhoto(gender: "female"), false, "no photo for female")
check(R.photoToSend("img", gender: "female"), nil, "female: photo never sent")
check(R.photoToSend("img", gender: ""), nil, "no gender: photo not sent")
check(R.photoToSend("img", gender: "male"), "img", "male: photo sent")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
