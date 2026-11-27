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

    static func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    /// «من العائلة»: الاسم الرباعي (كلمتان على الأقل) · «من خارج العائلة»: الاسم الثلاثي (ثلاث كلمات، بلا العائلة)
    static func nameValid(_ s: String, origin: Origin) -> Bool {
        let n = tidy(s)
        return wordCount(n) >= (origin == .outside ? 3 : 2) && n.filter(\.isLetter).count >= 2 && n.count <= 100
    }

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

    /// «هل الأم من العائلة؟»: نعم ← اسم الوالدة في المربّع نفسه · لا ← صلاحيات محدودة مباشرة
    enum QuestionOutcome: Equatable { case motherName, limited }

    static func afterQuestion(motherInFamily: Bool) -> QuestionOutcome {
        motherInFamily ? .motherName : .limited
    }

    /// اسم الوالد = اسم صاحب الحساب بعد الاسم الأول — nil إن بقي أقل من كلمتين (السيرفر يشتقّه بالقاعدة نفسها)
    static func derivedFatherName(fullName: String) -> String? {
        let w = tidy(fullName).split(separator: " ").map(String.init)
        guard w.count >= 3 else { return nil }
        return w.dropFirst().joined(separator: " ")
    }

    /// يُرسل؟ «نعم» · اسم الوالدة (ثلاث كلمات على الأقل من الرباعي، بلا العائلة) · اسم الوالد من الاسم المسجّل
    static func canSendCompletion(motherInFamily: Bool?, motherName: String, fatherName: String?) -> Bool {
        let m = tidy(motherName)
        return motherInFamily == true && fatherName != nil && wordCount(m) >= 3 && m.count <= 120
    }

    /// طلب «استكمال التسجيل» في «الوارد» (`outside_typed`): اسم الوالدة مكتوباً
    static func isTypedLineage(details: String?) -> Bool {
        guard let data = details?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (obj["kind"] as? String) == "outside_typed"
    }

    // MARK: «الوارد»: طلبات الانضمام من العائلة / من خارج العائلة (المالك ٢٠٢٦-١١-٢٧)
    //
    // المصدر من خطوة التسجيل: علامة `outsideMarker` = من خارج العائلة؛ غيرها (ومنها القديمة بلا علامة) = من العائلة.
    // طلبات «استكمال التسجيل» (`outside_typed`) تُعدّ مع «من خارج العائلة».

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

    static func originCounts(joins: [JoinOrigin], typedLineage: Int) -> OriginCounts {
        OriginCounts(family: joins.filter { $0 == .family }.count,
                     outside: joins.filter { $0 == .outside }.count + max(0, typedLineage))
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
        static let familyNameHint = "العائلة «المحمدعلي»، وتربط الإدارة الحساب بالوالد بعد التحقق من اسمه في الشجرة."
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
        static let motherQuestion = "هل الأم من العائلة؟"
        static let yes = "نعم"
        static let no = "لا"
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

        static var all: [String] {
            [brand, chooseTitle, chooseBoxTitle, fromFamily, fromOutside,
             familyFullName, outsideFullName, familyNameHint, outsideNameHint, familyName, familyPlaceholder, birthDate, gender,
             submit, back, under13, guardian, signOut,
             waitingTitle, waitingBody, waitingChip, refresh, editRequest, contactAdmin, deleteAccount,
             completeTitle, approvedLine, motherQuestion, yes, no, motherName, motherNamePlaceholder, motherNameHint,
             fatherLine("فلان"), fatherMissing, send, later, pendingTitle, sentBody, goToApp, rejectedTitle, rejectedBody,
             lockedTitle, lockedBody, homeBody, limitedTag,
             motherPlaceholder, motherHint, motherNotFound, fatherPlaceholder,
             cardOffer, cardOfferBody, cardRejected, cardRejectedBody, cardPendingTitle, cardPendingBody,
             inboxTag, approveOutside, approveOutsideNote, inboxAll, inboxFamilyJoins, inboxOutsideJoins, inboxCompleteDoor,
             inboxTypedTitle, inboxPickMother, inboxNoSuggestions, inboxHusbandMatches, fatherDerivedNote]
        }
    }
}
