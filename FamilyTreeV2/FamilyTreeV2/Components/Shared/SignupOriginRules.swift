import Foundation

// MARK: - «التسجيل: من العائلة أو من خارجها» (موافقة المالك ٢٠٢٦-١١-٢٧، الوحدة R1)
//
// بعد رمز الدخول: مربّعان صغيران في منتصف الشاشة (boxes.png، المالك «خطوات أقل»):
//  ١) مربّع الخيارين بلا نص فرعي: «من العائلة» · «من خارج العائلة».
//  ٢) مربّع واحد بالحقول كلها ثم «إرسال الطلب إلى الإدارة» مباشرة (بلا مراجعة) ← مربّع «قيد المراجعة»:
//     من العائلة: الاسم الرباعي · تاريخ الميلاد · الجنس (العائلة «المحمدعلي» ضمناً، بلا اختيار الوالد — الإدارة تربط بعد
//     التحقق من اسم الوالد في الشجرة) · من خارج العائلة: الاسم الثلاثي · العائلة · تاريخ الميلاد · الجنس.
// بعد قبول الإدارة «من خارج العائلة» (`approve_join_as_daughter_son` — الذكر والأنثى، 20261127160000): مربّع «استكمال التسجيل»
// الواحد: «هل الأم من العائلة؟» نعم ← «اسم الوالدة الرباعي» و«إرسال إلى الإدارة» في المربّع نفسه (الوالد سطر للاطلاع من الاسم
// المسجّل) · لا ← الحساب «بصلاحيات محدودة» مباشرة ويُغلق المربّع (لا طلب، ولا يُعرض له شيء عنها).
// النصوص عربية فصحى رسمية: «الوالد» و«الوالدة» فقط. القواعد خالصة تُفحص بلا محاكي: `tests/admin-redesign/R1/main.swift`.

enum SignupOriginRules {

    enum Origin: Equatable { case family, outside }

    static let familyName = "المحمدعلي"

    // MARK: مربّع البيانات

    enum Field: Equatable { case name, family, birth, gender }

    /// الحقول بترتيب المالك — «العائلة» لمن هو من خارج العائلة فقط
    static func fields(_ origin: Origin) -> [Field] {
        origin == .outside ? [.name, .family, .birth, .gender] : [.name, .birth, .gender]
    }

    /// صورة التسجيل للذكور فقط: «الجنس» أولاً، والصورة تظهر بعد اختيار «ذكر» وحده، وتُرسل للذكر وحده
    static func showsPhoto(gender: String) -> Bool { gender.lowercased() == "male" }
    static func photoToSend<T>(_ photo: T?, gender: String) -> T? { gender.lowercased() == "male" ? photo : nil }

    static func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    /// أجزاء الاسم بتطبيع البحث الواحد (`NameSearch.words`): «عبد الله» جزء واحد كـ«عبدالله»
    static func nameParts(_ s: String) -> Int { NameSearch.words(s).count }

    /// عدد الأجزاء المطلوب: الرباعي (من العائلة) أربعة · الثلاثي (من خارج العائلة) ثلاثة
    static func requiredParts(_ origin: Origin) -> Int { origin == .outside ? 3 : 4 }

    /// اسم الوالدة الرباعي (بلا اسم العائلة)
    static let motherNameParts = 4

    /// «من العائلة»: الاسم الرباعي (أربعة أجزاء) · «من خارج العائلة»: الاسم الثلاثي (ثلاثة أجزاء، بلا العائلة)
    static func nameValid(_ s: String, origin: Origin) -> Bool {
        let n = tidy(s)
        return nameParts(n) >= requiredParts(origin) && n.filter(\.isLetter).count >= 2 && n.count <= 100
    }

    /// اسم الوالدة مكتمل؟ (أربعة أجزاء على الأقل)
    static func motherNameComplete(_ s: String) -> Bool { nameParts(tidy(s)) >= motherNameParts }

    static func familyValid(_ s: String) -> Bool {
        let f = tidy(s)
        return f.filter(\.isLetter).count >= 2 && f.count <= 50
    }

    /// ١٣ سنة فأكثر (شروط ٢٠٢٦-١٠-٢٨)
    static func birthValid(chosen: Bool, age: Int?) -> Bool { chosen && (age ?? 0) >= 13 }

    static func genderValid(_ g: String) -> Bool { g == "male" || g == "female" }

    static func fieldValid(_ f: Field, origin: Origin, name: String, family: String,
                           birthChosen: Bool, age: Int?, gender: String) -> Bool {
        switch f {
        case .name: return nameValid(name, origin: origin)
        case .family: return familyValid(family)
        case .birth: return birthValid(chosen: birthChosen, age: age)
        case .gender: return genderValid(gender)
        }
    }

    /// «إرسال الطلب إلى الإدارة»: كل حقول المربّع صحيحة
    static func canSubmit(origin: Origin, name: String, family: String, birthChosen: Bool, age: Int?, gender: String) -> Bool {
        fields(origin).allSatisfy {
            fieldValid($0, origin: origin, name: name, family: family, birthChosen: birthChosen, age: age, gender: gender)
        }
    }

    // MARK: وضوح الحقول (طلب المالك ٢٠٢٦-١١-٢٧ «كتابة البيانات… واضحة ومفهومة»)

    /// الحقول الناقصة أو غير الصحيحة بالترتيب — سطر «لإرسال الطلب يُرجى استكمال: …» يشرح لماذا الزرّ معطّل
    static func missingFields(origin: Origin, name: String, family: String, birthChosen: Bool, age: Int?,
                              gender: String) -> [Field] {
        fields(origin).filter {
            !fieldValid($0, origin: origin, name: name, family: family, birthChosen: birthChosen, age: age, gender: gender)
        }
    }

    /// خطأ الاسم تحت الحقل — nil وهو فارغ (الفارغ يقوله سطر الاستكمال) أو صحيح
    static func nameError(_ s: String, origin: Origin) -> String? {
        guard !tidy(s).isEmpty, !nameValid(s, origin: origin) else { return nil }
        return origin == .outside ? Ar.outsideNameShort : Ar.familyNameShort
    }

    static func familyError(_ s: String) -> String? {
        guard !tidy(s).isEmpty, !familyValid(s) else { return nil }
        return Ar.familyShort
    }

    static func motherNameError(_ s: String) -> String? {
        let m = tidy(s)
        guard !m.isEmpty, !motherNameComplete(m) else { return nil }
        return Ar.motherNameShort
    }

    /// العائلة المحفوظة: «المحمدعلي» لمن هو من العائلة، والمكتوبة لغيره
    static func familyToSave(origin: Origin, typed: String) -> String {
        origin == .outside ? tidy(typed) : familyName
    }

    /// علامة طلب الانضمام «من خارج العائلة» في تفاصيله — قبل `matched_ids` (قارئها يأخذ ما بعدها)
    static let outsideMarker = "|outside_family:1"

    /// علامة «من العائلة» (بلا اختيار الوالد) — السيرفر لا يعرض لها بطاقة «بنت بنت» في شاشة الانتظار
    static let familyMarker = "|family_signup:1"

    static func isOutside(details: String?) -> Bool {
        (details ?? "").contains(outsideMarker)
    }

    // MARK: مربّع «استكمال التسجيل» (بعد قبول الانضمام)

    /// «هل الأم من العائلة؟»: نعم ← اسم الوالدة في المربّع نفسه · لا ← «هل أحد أفراد أسرتك من العائلة؟» (٢٠٢٦-١١-٢٨)
    /// ← الزوجة/الزوج ← بياناته · «لا يوجد» ← صلاحيات محدودة مباشرة (كما كانت «لا»)
    enum QuestionOutcome: Equatable { case motherName, familyQuestion, spouseName, limited }

    static func afterQuestion(motherInFamily: Bool) -> QuestionOutcome {
        motherInFamily ? .motherName : .familyQuestion
    }

    static func afterFamily(hasSpouse: Bool) -> QuestionOutcome {
        hasSpouse ? .spouseName : .limited
    }

    // MARK: «هل أحد أفراد أسرتك من العائلة؟» — الزوج أو الزوجة (العيّنة spouse2، المالك ٢٠٢٦-١١-٢٨ «نفّذ كل شي»)

    /// صلة صاحب الحساب بالعائلة: الرجل ← «الزوجة»، المرأة ← «الزوج» (السيرفر يقرّرها بالجنس نفسه)
    enum Relation: String, Equatable, Sendable { case wife, husband }

    static func relation(gender: String?) -> Relation {
        (gender ?? "").lowercased() == "female" ? .husband : .wife
    }

    /// خطوات «استكمال التسجيل» = النقاط الثلاث: الوالدة · الأسرة · بيانات الزوج/الزوجة
    enum CompletionStep: Int, CaseIterable, Equatable { case mother = 0, family = 1, spouse = 2 }

    /// «رجوع» (زرّ الرأس وزرّ المربّع): خطوة واحدة للخلف — لا رجوع من الأولى
    static func back(from step: CompletionStep) -> CompletionStep? {
        CompletionStep(rawValue: step.rawValue - 1)
    }

    /// اسم الزوج/الزوجة الرباعي بلا العائلة — «المحمدعلي» تُحذف إن كُتبت (تُضاف ثابتة)، و«محمد علي» اسمين يبقى
    static func spouseNameToSend(_ s: String) -> String {
        var w = tidy(s).split(separator: " ").map(String.init)
        if let last = w.last, last == familyName { w.removeLast() }
        else if w.count >= 2, w[w.count - 2] == "المحمد", w[w.count - 1] == "علي" { w.removeLast(2) }
        return w.joined(separator: " ")
    }

    static let spouseNameParts = 4

    static func spouseNameComplete(_ s: String) -> Bool { nameParts(spouseNameToSend(s)) >= spouseNameParts }

    static func spouseNameError(_ s: String, relation: Relation = .wife) -> String? {
        guard !tidy(s).isEmpty, !spouseNameComplete(s) else { return nil }
        return Ar.spouseNameShort(relation)
    }

    static func canSendSpouse(_ s: String) -> Bool {
        let n = spouseNameToSend(s)
        return spouseNameComplete(n) && n.count <= 120 && n.filter(\.isLetter).count >= 2
    }

    private static func requestKind(_ details: String?) -> String? {
        guard let data = details?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["kind"] as? String
    }

    /// طلب ربط الزوج/الزوجة في «الوارد» (`outside_spouse`، 20261128150000)
    static func isSpouseLink(details: String?) -> Bool { requestKind(details) == "outside_spouse" }

    /// طلبات «استكمال التسجيل» كلها: اسم الوالدة مكتوباً أو الزوج/الزوجة
    static func isCompletionRequest(details: String?) -> Bool {
        let k = requestKind(details)
        return k == "outside_typed" || k == "outside_spouse"
    }

    /// اسم الوالد = اسم صاحب الحساب بعد الاسم الأول — nil إن بقي أقل من كلمتين (السيرفر يشتقّه بالقاعدة نفسها)
    static func derivedFatherName(fullName: String) -> String? {
        let w = tidy(fullName).split(separator: " ").map(String.init)
        guard w.count >= 3 else { return nil }
        return w.dropFirst().joined(separator: " ")
    }

    /// يُرسل؟ «نعم» · اسم الوالدة الرباعي (أربعة أجزاء، بلا العائلة) · اسم الوالد من الاسم المسجّل
    static func canSendCompletion(motherInFamily: Bool?, motherName: String, fatherName: String?) -> Bool {
        let m = tidy(motherName)
        return motherInFamily == true && fatherName != nil && motherNameComplete(m) && m.count <= 120
    }

    /// طلب «استكمال التسجيل» في «الوارد» (`outside_typed`): اسم الوالدة مكتوباً
    static func isTypedLineage(details: String?) -> Bool { requestKind(details) == "outside_typed" }

    // MARK: «الوارد»: طلبات الانضمام من العائلة / من خارج العائلة (المالك ٢٠٢٦-١١-٢٧)
    //
    // المصدر من خطوة التسجيل: علامة `outsideMarker` = من خارج العائلة؛ غيرها (ومنها القديمة بلا علامة) = من العائلة.
    // طلبات «استكمال التسجيل» (`outside_typed`) لا تُعدّ في الشريحة: لها صفّ واحد تحتها بعددها هي (الرقم = الصفوف الظاهرة).

    enum JoinOrigin: Equatable { case family, outside }

    enum JoinFilter: Hashable { case all, family, outside }

    static func joinOrigin(details: String?) -> JoinOrigin {
        isOutside(details: details) ? .outside : .family
    }

    /// يظهر العنصر مع الشريحة؟ `origin` nil = ليس طلب انضمام (يظهر مع «الكل» وحدها)
    static func passes(_ filter: JoinFilter, origin: JoinOrigin?) -> Bool {
        switch filter {
        case .all: return true
        case .family: return origin == .family
        case .outside: return origin == .outside
        }
    }

    struct OriginCounts: Equatable {
        var family: Int
        var outside: Int
    }

    static func originCounts(joins: [JoinOrigin]) -> OriginCounts {
        OriginCounts(family: joins.filter { $0 == .family }.count,
                     outside: joins.filter { $0 == .outside }.count)
    }

    static func tidy(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: النصوص (العربية — الإنجليزية في الشاشات)

    enum Ar {
        static let brand = "عائلة المحمدعلي"
        static let chooseTitle = "التسجيل"
        static let chooseBoxTitle = "يُرجى تحديد صلتك بالعائلة"
        static let fromFamily = "من العائلة"
        static let fromOutside = "من خارج العائلة"
        static var choices: [String] { [fromFamily, fromOutside] }

        // مربّع البيانات
        static let familyFullName = "الاسم الرباعي"
        static let outsideFullName = "الاسم الثلاثي"
        static let familyNameHint = "بدون اسم العائلة، وتُضاف «المحمدعلي» تلقائياً."
        static let outsideNameHint = "الاسم الأول واسم الوالد والجد، بدون اسم العائلة."
        static let familyName = "العائلة"
        static let familyPlaceholder = "مثال: الموسى"
        static let birthDate = "تاريخ الميلاد"
        static let gender = "الجنس"
        static let submit = "إرسال الطلب إلى الإدارة"
        static let back = "رجوع"
        static let under13 = "لا يمكن إنشاء حساب لمن هم دون الثالثة عشرة."
        static let guardian = "يحتاج الحساب إلى موافقة ولي الأمر قبل تفعيله."
        static let signOut = "تسجيل الخروج"
        static func fieldLabels(_ origin: Origin) -> [String] {
            fields(origin).map {
                switch $0 {
                case .name: return origin == .outside ? outsideFullName : familyFullName
                case .family: return familyName
                case .birth: return birthDate
                case .gender: return gender
                }
            }
        }

        // مربّع «قيد المراجعة»
        static let waitingTitle = "تم استلام طلبك"
        static let waitingBody = "تم استلام طلبك، وستتم مراجعته من قِبل الإدارة. سيصلك إشعار عند اعتماده."
        static let waitingChip = "قيد المراجعة"
        static let refresh = "تحديث الحالة"
        static let editRequest = "تعديل الطلب"
        static let contactAdmin = "التواصل مع الإدارة"
        static let deleteAccount = "حذف الحساب"

        // مربّع «استكمال التسجيل»
        static let completeTitle = "استكمال التسجيل"
        static let approvedLine = "تم قبول طلبك. يُرجى الإجابة لاستكمال التسجيل."
        static let motherQuestion = "هل الوالدة من العائلة؟"
        static let yes = "نعم"
        static let no = "لا"
        /// تأكيد «لا» — بلا أي ذكر للصلاحيات (قاعدة المالك)
        static let confirmNoTitle = "تأكيد الاختيار"
        static let confirmNoBody = "الوالدة ليست من عائلة المحمدعلي. لا يمكن تغيير هذا الاختيار لاحقاً من التطبيق."
        static let confirm = "تأكيد"
        static let motherName = "اسم الوالدة الرباعي"
        static let motherNamePlaceholder = "الاسم الأول واسم والدها وجدها وجد والدها"
        static let motherNameHint = "بدون اسم العائلة. تطابق الإدارة الاسم مع سجلّ الوالدة في الشجرة."
        static func fatherLine(_ name: String) -> String { "الوالد: \(name) — من الاسم المسجّل." }
        static let fatherMissing = "اسم الوالد غير مكتمل في الاسم المسجّل، ويُرجى التواصل مع الإدارة."
        static let send = "إرسال إلى الإدارة"
        static let later = "لاحقاً"
        static let pendingTitle = "التسجيل قيد المراجعة"
        static let sentBody = "سيصلك إشعار عند اعتماد الإدارة، وتتم الإضافة إلى الشجرة ويكتمل التسجيل."
        static let goToApp = "الانتقال إلى التطبيق"
        static let rejectedTitle = "يُرجى مراجعة البيانات وإرسالها من جديد"
        static let rejectedBody = "يُرجى مراجعة البيانات وإرسالها من جديد."
        static let lockedTitle = "يُرجى استكمال التسجيل لعرض هذا القسم"
        static let lockedBody = "يُرجى إدخال بيانات الوالدة، وبعد اعتماد الإدارة يُفتح القسم."
        static let homeBody = "يُرجى إدخال بيانات الوالدة لاستكمال التسجيل وفتح جميع الأقسام."
        // «هل أحد أفراد أسرتك من العائلة؟» (٢٠٢٦-١١-٢٨)
        static let familyQuestion = "هل أحد أفراد أسرتك من العائلة؟"
        static let familyQuestionSub = "يساعد الإدارة على ربطك بالشجرة."
        static func spouseTile(_ r: Relation) -> String { r == .wife ? "الزوجة" : "الزوج" }
        static let fromFamilyLine = "من عائلة المحمدعلي"
        static let noneTile = "لا يوجد"
        static let confirmNoneBody = "لا يوجد أحد من أفراد الأسرة من عائلة المحمدعلي. لا يمكن تغيير هذا الاختيار لاحقاً من التطبيق."
        static func spouseTitle(_ r: Relation) -> String { r == .wife ? "بيانات الزوجة" : "بيانات الزوج" }
        static func spouseSub(_ r: Relation) -> String {
            r == .wife ? "تتحقّق الإدارة من الاسم وتربطك بها في الشجرة." : "تتحقّق الإدارة من الاسم وتربطك به في الشجرة."
        }
        static func spouseNameLabel(_ r: Relation) -> String { r == .wife ? "اسم الزوجة الرباعي" : "اسم الزوج الرباعي" }
        static func spouseNameExample(_ r: Relation) -> String { r == .wife ? "مثال: فاطمة أحمد زيد حسن" : "مثال: زيد حسن علي أحمد" }
        static func spouseNameShort(_ r: Relation) -> String {
            r == .wife ? "يُرجى كتابة اسم الزوجة رباعياً، بدون اسم العائلة." : "يُرجى كتابة اسم الزوج رباعياً، بدون اسم العائلة."
        }
        static let spouseSentTitle = "تم إرسال البيانات"
        static func spouseSentBody(_ r: Relation) -> String {
            r == .wife ? "تتحقّق الإدارة من الاسم وتربطك بالزوجة في الشجرة، ويصلك إشعار عند الربط."
                       : "تتحقّق الإدارة من الاسم وتربطك بالزوج في الشجرة، ويصلك إشعار عند الربط."
        }
        static let editData = "تعديل البيانات"
        static let relationLabel = "الصلة"
        static let nameLabel = "الاسم"

        /// «صلاحيات محدودة» (الأم ليست من العائلة) — للإدارة وحدها في بطاقة العضو؛ لا يُعرض للعضو شيء عنها
        static let limitedTag = "صلاحيات محدودة"

        // صفحة «بنت بنت» الاحتياطية (DaughterLineageViews)
        static let motherPlaceholder = "اسم الوالدة واسم والدها وجدها"
        static let motherHint = "اكتب الاسم الثلاثي، ولا تظهر الأسماء قبل ذلك."
        static let motherNotFound = "إذا لم تظهر الوالدة، فاكتب اسمها واسم والدها وجدها، أو تواصل مع الإدارة."
        static let fatherPlaceholder = "اسم الوالد الثلاثي"

        // بطاقة شاشة الانتظار (بنت البنت التي سجّلت قبل هذه الخطوة — المسار الحي)
        static let cardOffer = "هل الوالدة من بنات العائلة؟"
        static let cardOfferBody = "يُرجى اختيار الوالدة من بنات العائلة وكتابة اسم الوالد."
        static let cardRejected = "يُرجى مراجعة اختيار الوالدة والوالد"
        static let cardRejectedBody = "يُرجى إرسالها من جديد إلى الإدارة."
        static let cardPendingTitle = "النسب قيد المراجعة"
        static let cardPendingBody = "أُرسل اختيار الوالدة والوالد إلى الإدارة، وسيصلك إشعار عند الاعتماد."

        // «الوارد»
        static let inboxTag = "من خارج العائلة"
        static let approveOutside = "قبول «من خارج العائلة»"
        static let approveOutsideNote = "يُقبل الحساب الآن، وعند فتح التطبيق يُستكمل التسجيل بإدخال بيانات الوالدة، ثم تعتمده الإدارة من «الوارد»."
        static let inboxAll = "الكل"
        static let inboxFamilyJoins = "طلبات انضمام من العائلة"
        static let inboxOutsideJoins = "طلبات انضمام من خارج العائلة"
        static let inboxCompleteDoor = "طلبات استكمال التسجيل"
        static let inboxTypedTitle = "طلب نسب · استكمال التسجيل"
        static let inboxPickMother = "يُرجى اختيار الوالدة من بنات العائلة"
        static let inboxNoSuggestions = "لم يُعثر على بنات بهذا الاسم. يُرجى التواصل مع صاحب الطلب أو رفض الطلب."
        static let inboxHusbandMatches = "زوجها يطابق اسم الوالد"
        static let fatherDerivedNote = "من الاسم المسجّل."
        /// لحظة النجاح بعد «إرسال» (A1): علامة صح صغيرة واهتزاز نجاح قبل «قيد المراجعة»
        static let sentMoment = "أُرسل الطلب"
        /// صورة الذكر في مربّع البيانات (اختيارية؛ لا صور للنساء)
        static let addPhoto = "إضافة صورة"
        // أمثلة الحقول، والأخطاء تحتها، وسطر ما ينقص قبل الإرسال
        static let familyNameExample = "مثال: محمد عبدالله علي أحمد"
        static let outsideNameExample = "مثال: محمد حسن حسين"
        static let motherNameExample = "مثال: فاطمة أحمد علي حسن"
        static let motherNameHelp = "الاسم الأول واسم والدها وجدها وجد والدها، بدون اسم العائلة."
        static let familyNameShort = "يُرجى كتابة الاسم الرباعي كاملاً: الاسم الأول واسم الوالد والجد وجد الوالد."
        static let outsideNameShort = "يُرجى كتابة الاسم الثلاثي كاملاً: الاسم الأول واسم الوالد والجد."
        static let familyShort = "يُرجى كتابة اسم العائلة بحرفين على الأقل."
        static let motherNameShort = "يُرجى كتابة اسم الوالدة رباعياً، بدون اسم العائلة."
        static let missingPrefix = "لإرسال الطلب يُرجى استكمال: "
        static func missingLine(_ labels: [String]) -> String { missingPrefix + labels.joined(separator: "، ") }
        static let photoOptional = "اختيارية"

        static var all: [String] {
            [brand, chooseTitle, chooseBoxTitle, fromFamily, fromOutside,
             familyFullName, outsideFullName, familyNameHint, outsideNameHint, familyName, familyPlaceholder, birthDate, gender,
             submit, back, under13, guardian, signOut,
             waitingTitle, waitingBody, waitingChip, refresh, editRequest, contactAdmin, deleteAccount,
             completeTitle, approvedLine, motherQuestion, yes, no, confirmNoTitle, confirmNoBody, confirm, motherName, motherNamePlaceholder, motherNameHint,
             fatherLine("فلان"), fatherMissing, send, later, pendingTitle, sentBody, goToApp, rejectedTitle, rejectedBody,
             lockedTitle, lockedBody, homeBody, limitedTag,
             motherPlaceholder, motherHint, motherNotFound, fatherPlaceholder,
             cardOffer, cardOfferBody, cardRejected, cardRejectedBody, cardPendingTitle, cardPendingBody,
             inboxTag, approveOutside, approveOutsideNote, inboxAll, inboxFamilyJoins, inboxOutsideJoins, inboxCompleteDoor,
             inboxTypedTitle, inboxPickMother, inboxNoSuggestions, inboxHusbandMatches, fatherDerivedNote, sentMoment, addPhoto, photoOptional,
             familyNameExample, outsideNameExample, motherNameExample, motherNameHelp, familyNameShort, outsideNameShort,
             familyShort, motherNameShort, missingLine(["الجنس"]),
             familyQuestion, familyQuestionSub, spouseTile(.wife), spouseTile(.husband), fromFamilyLine, noneTile, confirmNoneBody,
             spouseTitle(.wife), spouseTitle(.husband), spouseSub(.wife), spouseSub(.husband),
             spouseNameLabel(.wife), spouseNameLabel(.husband), spouseNameExample(.wife), spouseNameExample(.husband),
             spouseNameShort(.wife), spouseNameShort(.husband), spouseSentTitle, spouseSentBody(.wife), spouseSentBody(.husband),
             editData, relationLabel, nameLabel]
        }
    }
}
