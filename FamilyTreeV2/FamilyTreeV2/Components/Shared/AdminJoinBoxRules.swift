import Foundation

// MARK: - مربّعات الإدارة لطلبات الانضمام واستكمال التسجيل (المالك ٢٠٢٦-١١-٢٧، الوحدة R2 — admin-boxes.png)
//
// فتح طلب في «الوارد» يفتح مربّعاً صغيراً في المنتصف (نفس شكل مربّعات التسجيل):
//  • «من العائلة»: بيانات صاحب الطلب ← «التالي: الربط» ← مربّع «الربط» باقتراحات (الرجل: شجرة العائلة بمطابقة الاسم الموجودة؛
//    المرأة: بنات شجرة النساء) ← «ربط» ← «تأكيد الربط». والثاني «عضو جديد» (الرجل) / «بنت جديدة» (المرأة) ← اختيار الوالد ←
//    «إضافة وربط» ← «تأكيد الربط».
//  • «من خارج العائلة»: مربّع البيانات بزرّ واحد «اعتماد».
//  • «استكمال التسجيل» (`outside_typed`): البيانات واقتراحات الوالدة في مربّع واحد ← «ربط بالوالدة» ← «تأكيد الربط».
// الاقتراح: الاسم الأول عريضاً + شرائح بالقيم وحدها «الوالد · الجد · سنة الميلاد (· الزوج للمرأة حين يفرّق)»، الأخضر = يطابق
// الطلب بالتطبيع العربي (`NameSearch.words`)، بلا تسميات رمادية (القارئ الصوتي يقرأ التسمية مع القيمة).
// نداءات السيرفر وفحوص الصلاحية هي الموجودة نفسها (في الشاشات). القواعد خالصة: `tests/admin-redesign/R2/main.swift`.

enum AdminJoinBoxRules {

    // MARK: النوع والمصدر

    enum Kind: Equatable { case familyJoin, outsideJoin, completion }

    static func kind(isOutside: Bool, isCompletion: Bool) -> Kind {
        isCompletion ? .completion : (isOutside ? .outsideJoin : .familyJoin)
    }

    /// من أين تأتي الاقتراحات
    enum Source: Equatable { case familyTree, womenDaughters, motherSuggestions, none }

    static func source(_ kind: Kind, female: Bool) -> Source {
        switch kind {
        case .familyJoin: return female ? .womenDaughters : .familyTree
        case .outsideJoin: return .none
        case .completion: return .motherSuggestions
        }
    }

    // MARK: الخطوات والأزرار

    enum Step: Equatable { case applicant, link, newMember, confirm, askMissing }

    enum Action: Equatable { case toLink, link, newMember, addAndLink, approveOutside, linkMother, confirm, askMissing, sendAsk }

    /// المربّعات بنقاط التقدّم (التأكيد واختيار الوالد خارجها)
    static func steps(_ kind: Kind) -> [Step] {
        kind == .familyJoin ? [.applicant, .link] : [.applicant]
    }

    /// موضع النقطة — nil = بلا نقاط (مربّع واحد، أو التأكيد/اختيار الوالد)
    static func dotIndex(_ kind: Kind, step: Step) -> Int? {
        let s = steps(kind)
        guard s.count > 1 else { return nil }
        return s.firstIndex(of: step)
    }

    static func primary(_ kind: Kind, step: Step) -> Action {
        switch step {
        case .applicant:
            switch kind {
            case .familyJoin: return .toLink
            case .outsideJoin: return .approveOutside
            case .completion: return .linkMother
            }
        case .link: return .link
        case .newMember: return .addAndLink
        case .confirm: return .confirm
        case .askMissing: return .sendAsk
        }
    }

    /// الزرّ الثاني: «طلب استكمال البيانات» في مربّع البيانات (كل الأنواع)، و«عضو جديد»/«بنت جديدة» في مربّع الربط
    static func secondary(_ kind: Kind, step: Step) -> Action? {
        switch step {
        case .applicant: return .askMissing
        case .link: return kind == .familyJoin ? .newMember : nil
        default: return nil
        }
    }

    /// المربّع التالي — nil = يُنفَّذ نداء السيرفر
    static func next(after action: Action) -> Step? {
        switch action {
        case .toLink: return .link
        case .link, .linkMother, .addAndLink: return .confirm
        case .newMember: return .newMember
        case .askMissing: return .askMissing
        case .approveOutside, .confirm, .sendAsk: return nil
        }
    }

    static func title(_ action: Action, female: Bool) -> String {
        switch action {
        case .toLink: return text(Ar.toLink, "Next: link")
        case .link, .confirm: return text(Ar.link, "Link")
        case .newMember: return female ? text(Ar.newDaughter, "New daughter") : text(Ar.newMember, "New member")
        case .addAndLink: return text(Ar.addAndLink, "Add & link")
        case .approveOutside: return text(Ar.approve, "Approve")
        case .linkMother: return text(Ar.linkMother, "Link to the mother")
        case .askMissing: return text(Ar.askMissing, "Request missing details")
        case .sendAsk: return text(Ar.sendAsk, "Send the request to the member")
        }
    }

    // MARK: «طلب استكمال البيانات» (المالك ٢٠٢٦-١١-٢٧ «اذا البيانات ناقصة نقدر نرسلها حق العضو»)
    //
    // الإدارة تحدّد الناقص وتكتب ملاحظة اختيارية ← `ask_join_completion` (20261127180000) ← إشعار رسمي للعضو، والطلب يبقى
    // معلّقاً. العضو يفتح التطبيق ← مربّع التسجيل (أو «استكمال التسجيل») بالحقول المطلوبة مميّزة ← `answer_completion_ask`.

    /// المفاتيح كما يقبلها السيرفر
    enum MissingField: String, CaseIterable, Equatable {
        case fullName = "full_name", family, birthDate = "birth_date", gender, photo, motherName = "mother_name"
    }

    static func askFields(_ kind: Kind) -> [MissingField] {
        switch kind {
        case .familyJoin: return [.fullName, .birthDate, .gender, .photo]
        case .outsideJoin: return [.fullName, .family, .birthDate, .gender, .photo]
        case .completion: return [.motherName]
        }
    }

    static func fieldLabel(_ f: MissingField) -> String {
        switch f {
        case .fullName: return text(Ar.fullName, "Four-part name")
        case .family: return text(Ar.family, "Family")
        case .birthDate: return text(Ar.birth, "Birth date")
        case .gender: return text(Ar.gender, "Gender")
        case .photo: return text(Ar.photo, "Profile photo")
        case .motherName: return text(Ar.motherName, "Mother's name")
        }
    }

    static let askNoteLimit = 200

    static func canSendAsk(_ fields: Set<MissingField>, note: String) -> Bool {
        !fields.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).count <= askNoteLimit
    }

    /// بترتيب القائمة (كما يُرسل ويكتبه السيرفر)
    static func orderedKeys(_ fields: Set<MissingField>) -> [String] {
        MissingField.allCases.filter(fields.contains).map(\.rawValue)
    }

    /// نصّ الإشعار كما يكتبه السيرفر حرفياً (العربية)
    static func askMessage(_ fields: Set<MissingField>, note: String) -> String {
        let items = MissingField.allCases.filter(fields.contains).map { arLabel($0) }.joined(separator: "، ")
        let n = note.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "يُرجى استكمال البيانات: " + items + "." + (n.isEmpty ? "" : "\n" + n)
    }

    private static func arLabel(_ f: MissingField) -> String {
        switch f {
        case .fullName: return Ar.fullName
        case .family: return Ar.family
        case .birthDate: return Ar.birth
        case .gender: return Ar.gender
        case .photo: return Ar.photo
        case .motherName: return Ar.motherName
        }
    }

    /// جهة العضو: الحقول المعروفة بلا تكرار (بترتيب السيرفر)
    /// سطر «طلبت الإدارة استكمال البيانات التالية: …» عند العضو. `spouse_name` (طلب ربط الزوج/الزوجة، 20261128150000)
    /// ليس في `MissingField` فكان السطر فارغاً بعد النقطتين (٢٠٢٦-١١-٢٨) — يُكتب «اسم الزوجة/الزوج الرباعي»؛ وطلب الزوج
    /// بلا حقول معروفة يُكتب الاسم نفسه.
    static func askedList(_ keys: [String], relation: SignupOriginRules.Relation, isSpouse: Bool = false) -> String {
        var labels: [String] = []
        for k in keys {
            let label: String?
            if k == "spouse_name" {
                label = text(SignupOriginRules.Ar.spouseNameLabel(relation),
                             relation == .wife ? "Wife's four-part name" : "Husband's four-part name")
            } else {
                label = MissingField(rawValue: k).map(fieldLabel)
            }
            if let label, !labels.contains(label) { labels.append(label) }
        }
        if labels.isEmpty && isSpouse {
            labels.append(text(SignupOriginRules.Ar.spouseNameLabel(relation),
                               relation == .wife ? "Wife's four-part name" : "Husband's four-part name"))
        }
        return labels.joined(separator: text("، ", ", "))
    }

    static func parseFields(_ keys: [String]) -> [MissingField] {
        var out: [MissingField] = []
        for k in keys { if let f = MissingField(rawValue: k), !out.contains(f) { out.append(f) } }
        return out
    }

    /// حقول مربّع التسجيل المميّزة
    static func signupHighlights(_ fields: [MissingField]) -> Set<SignupOriginRules.Field> {
        Set(fields.compactMap {
            switch $0 {
            case .fullName: return .name
            case .family: return .family
            case .birthDate: return .birth
            case .gender: return .gender
            case .photo, .motherName: return nil
            }
        })
    }

    /// «نعم» واسم الوالدة أقل من أربعة أجزاء ← يظهر سطر «مطلوب» (الإرسال معطّل حتى يكتمل)
    static func motherNameMissing(motherInFamily: Bool?, motherName: String) -> Bool {
        motherInFamily == true && !SignupOriginRules.motherNameComplete(motherName)
    }

    // MARK: الاقتراح: الاسم الكامل + شريحة الميلاد (المالك «وضحلي الاسم الكامل»)
    //
    // الاسم الكامل واضحاً (سطران إن لزم) بدل شرائح الوالد والجد، وكلماته المطابقة لأجزاء اسم الطلب خضراء (بالموضع نفسه،
    // تطبيع `NameSearch.words`، و«عبد الله» كلمة واحدة). تحته شريحة سنة الميلاد وحدها (خضراء إن طابقت)، و«الزوج: …»
    // للمرأة حين يفرّق بين متشابهتين أو يطابق الزوج المتوقَّع.

    struct Candidate: Equatable {
        let id: UUID
        let fullName: String
        let birthYear: Int?
        let husband: String?
    }

    /// بيانات الطلب التي تُقارن بها: الاسم المكتوب (الاسم ثم الوالد ثم الجد…)، وسنة الميلاد، والزوج المتوقَّع (الوالد
    /// المشتق في «استكمال التسجيل»، أو والد الشخص في مربّع الأم)
    struct Expect: Equatable {
        let typedName: String
        let birthYear: Int?
        let expectedHusband: String?
    }

    enum ChipKind: Equatable { case father, grandfather, birth, husband }

    struct Chip: Equatable {
        let kind: ChipKind
        let value: String
        let matches: Bool
    }

    struct NameWord: Equatable {
        let text: String
        let matches: Bool
    }

    static func words(_ s: String?) -> [String] { NameSearch.words(s ?? "") }

    private static func clean(_ s: String?) -> String? {
        let t = (s ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.isEmpty ? nil : t
    }

    /// كلمات الاسم كما كُتبت — «عبد الله» كلمة واحدة بمسافتها
    static func displayWords(_ full: String) -> [String] {
        var w: [String] = []
        for part in full.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let last = w.last, last == "عبد" { w[w.count - 1] = last + " " + part } else { w.append(part) }
        }
        return w
    }

    /// الاسم الكامل كلمةً كلمة، والمطابقة لجزء اسم الطلب في موضعها خضراء
    static func nameWords(_ c: Candidate, expect: Expect) -> [NameWord] {
        let typed = words(expect.typedName)
        return displayWords(c.fullName).enumerated().map { i, w in
            let key = words(w).joined()
            return NameWord(text: w, matches: i < typed.count && !key.isEmpty && key == typed[i])
        }
    }

    /// القارئ الصوتي يقرأ الاسم الكامل
    static func spokenName(_ c: Candidate) -> String { clean(c.fullName) ?? "" }

    /// الزوج يطابق المتوقَّع: أول كلمتين بعد التطبيع
    static func husbandMatches(_ husband: String?, expected: String?) -> Bool {
        let h = words(husband), e = words(expected)
        return e.count >= 2 && h.count >= 2 && Array(h.prefix(2)) == Array(e.prefix(2))
    }

    /// مرشّحة أخرى بنفس الاسم الأول والوالد والجد ← الزوج يفرّق بينهما
    static func husbandDisambiguates(_ c: Candidate, among: [Candidate]) -> Bool {
        let key = { (x: Candidate) in Array(words(x.fullName).prefix(3)) }
        let mine = key(c)
        return among.contains { $0.id != c.id && key($0) == mine }
    }

    static func chips(_ c: Candidate, among: [Candidate], expect: Expect, women: Bool) -> [Chip] {
        var out: [Chip] = []
        if let y = c.birthYear {
            out.append(Chip(kind: .birth, value: String(y), matches: expect.birthYear == y))
        }
        if women, let h = clean(c.husband) {
            let matches = husbandMatches(h, expected: expect.expectedHusband)
            if matches || husbandDisambiguates(c, among: among) {
                out.append(Chip(kind: .husband, value: h, matches: matches))
            }
        }
        return out
    }

    /// نصّ الشريحة: السنة وحدها، و«الزوج: …»
    static func chipText(_ chip: Chip) -> String {
        chip.kind == .husband ? text("الزوج: ", "Husband: ") + chip.value : chip.value
    }

    /// مربّعا الأم والزوجة (DSWifeFlow): الميلاد والزوج — الأخضر = الزوج المتوقَّع
    static func pickerChips(husband: String?, birthYear: Int?, expectedHusband: String?) -> [Chip] {
        var out: [Chip] = []
        if let birthYear { out.append(Chip(kind: .birth, value: String(birthYear), matches: false)) }
        if let h = clean(husband) {
            out.append(Chip(kind: .husband, value: h, matches: husbandMatches(h, expected: expectedHusband)))
        }
        return out
    }

    /// المرشّح من الشجرة: الاسم الكامل وسنة الميلاد
    static func candidate(id: UUID, fullName: String, birthDate: String?, husband: String?) -> Candidate {
        Candidate(id: id, fullName: clean(fullName) ?? "", birthYear: birthYear(birthDate), husband: clean(husband))
    }

    static func birthYear(_ date: String?) -> Int? {
        guard let s = date, s.count >= 4, let y = Int(s.prefix(4)), (1000...2999).contains(y) else { return nil }
        return y
    }

    // MARK: القارئ الصوتي

    static func label(_ kind: ChipKind) -> String {
        switch kind {
        case .father: return text("الوالد", "Father")
        case .grandfather: return text("الجد", "Grandfather")
        case .birth: return text("الميلاد", "Born")
        case .husband: return text("الزوج", "Husband")
        }
    }

    static func spoken(_ chip: Chip) -> String {
        label(chip.kind) + " " + chip.value + (chip.matches ? text("، مطابق", ", matches") : "")
    }

    // MARK: النصوص

    enum Ar {
        static let joinTitle = "طلب انضمام"
        static let completionTitle = "استكمال التسجيل"
        static let linkTitle = "الربط"
        static let confirmTitle = "تأكيد الربط"
        static let fromFamily = "من العائلة"
        static let fromOutside = "من خارج العائلة"
        static let completionTag = "استكمال التسجيل"
        static let toLink = "التالي: الربط"
        static let link = "ربط"
        static let newMember = "عضو جديد"
        static let newDaughter = "بنت جديدة"
        static let addAndLink = "إضافة وربط"
        static let approve = "اعتماد"
        static let linkMother = "ربط بالوالدة"
        static let cancel = "إلغاء"
        static let back = "رجوع"
        static let rejectWithReason = "رفض مع سبب"
        static let forward = "حوّل للمدير"
        static let details = "كل التفاصيل"
        static let familySuggestions = "اقتراحات من شجرة العائلة"
        static let womenSuggestions = "اقتراحات من شجرة النساء"
        static let motherSuggestions = "اقتراحات من شجرة النساء"
        static let pickFather = "اختيار الوالد من شجرة العائلة"
        static let noSuggestions = "لا توجد اقتراحات بهذا الاسم."
        static let confirmLine = "سيُربط الحساب بسجل الشجرة — لا يمكن التراجع من التطبيق."
        static let outsideNote = "بعد الاعتماد يُسأل في التطبيق: «هل الأم من العائلة؟»."
        static let fullName = "الاسم الرباعي"
        static let threeName = "الاسم الثلاثي"
        static let family = "العائلة"
        static let birth = "تاريخ الميلاد"
        static let motherTyped = "اسم الوالدة المكتوب"
        static let father = "الوالد"
        static let male = "ذكر"
        static let female = "أنثى"
        static let gender = "الجنس"
        static let photo = "الصورة الشخصية"
        static let motherName = "اسم الوالدة"
        static let askMissing = "طلب استكمال البيانات"
        static let sendAsk = "إرسال الطلب إلى العضو"
        static let askPrompt = "حدّد البيانات الناقصة:"
        static let askNote = "ملاحظة للعضو (اختيارية)"
        static let askPreview = "نص الإشعار:"
        static let askConfirmLine = "يصل العضو إشعار بهذا النص، ويبقى الطلب معلّقاً حتى يرسل البيانات."
        static let askSent = "أُرسل طلب استكمال البيانات"
        static let pickSuggestion = "يُرجى اختيار أحد الاقتراحات."
        static let pickFatherFirst = "يُرجى اختيار الوالد."
        static let mustTickOne = "يُرجى تحديد حقل واحد على الأقل."
        // جهة العضو
        static let memberAskTitle = "يُرجى استكمال البيانات"
        static let memberAskBody = "طلبت الإدارة استكمال البيانات التالية:"
        static let memberAskButton = "استكمال البيانات"
        static let memberAskRequired = "مطلوب من الإدارة"
        static let motherNameRequired = "يُرجى كتابة اسم الوالدة الرباعي، بدون اسم العائلة."
        static let addPhoto = "إضافة صورة شخصية"

        static var all: [String] {
            [joinTitle, completionTitle, linkTitle, confirmTitle, fromFamily, fromOutside, completionTag, toLink, link,
             newMember, newDaughter, addAndLink, approve, linkMother, cancel, back, rejectWithReason, forward, details,
             familySuggestions, womenSuggestions, motherSuggestions, pickFather, noSuggestions, confirmLine, outsideNote,
             fullName, threeName, family, birth, motherTyped, father, male, female, gender, photo, motherName,
             askMissing, sendAsk, askPrompt, askNote, askPreview, askConfirmLine, askSent, pickSuggestion, pickFatherFirst,
             mustTickOne, memberAskTitle, memberAskBody, memberAskButton, memberAskRequired, motherNameRequired, addPhoto]
        }
    }

    private static func text(_ ar: String, _ en: String) -> String {
        #if ADMIN_LOGIC_TEST
        ar
        #else
        L10n.t(ar, en)
        #endif
    }
}
