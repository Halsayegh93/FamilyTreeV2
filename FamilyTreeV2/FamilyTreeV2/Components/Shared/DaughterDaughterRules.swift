import Foundation

// MARK: - «بنت بنت العائلة» (طلب المالك ٢٠٢٦-١١-٢٧ «طبق الالية الحالية للتطبيق اذا بنت بنت العائلة تبي تدخل التطبيق»)
//
// نفس آلية «ابن بنت» (DaughterSons.swift) للأنثى التي سجّلت ولم تجد أباها في الشجرة وأمّها من بنات العائلة:
// شاشة الانتظار ← «أمي من بنات العائلة» ← تختار أمّها وتكتب اسم أبيها ← `submit_daughter_daughter_lineage` ← طلب
// `lineage_request` بحمولة `kind = daughter_daughter` ← «الوارد» نفس بطاقة طلب النسب ← `decide_lineage_request`.
// السيرفر: `20261127150000_daughter_daughters`. القواعد خالصة تُفحص بلا محاكي: `tests/admin-redesign/B1/main.swift`.

enum DaughterDaughterRules {

    /// نوع طلب النسب من حمولته — القديم بلا `kind` = ابن بنت
    enum Kind: Equatable { case daughterSon, daughterDaughter }

    static func kind(ofDetails details: String?) -> Kind {
        guard let data = details?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["kind"] as? String) == "daughter_daughter" else { return .daughterSon }
        return .daughterDaughter
    }

    // MARK: الأب

    /// زوج الأم المسجّل من خارج العائلة يُعرض أباً لها · زوجها من العائلة = أبوها في الشجرة (لا هذا المسار) · بلا زوج = تكتب الاسم
    enum FatherOption: Equatable {
        case registered(UUID, String)
        case fatherInFamily(String)
        case typed
    }

    static func fatherOption(husbandId: UUID?, husbandName: String?, husbandInFamily: Bool) -> FatherOption {
        guard let husbandId else { return .typed }
        let name = (husbandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return husbandInFamily ? .fatherInFamily(name) : .registered(husbandId, name)
    }

    /// نفس قاعدة السيرفر `private.lineage_names_match`: الاسم الأول متطابق، والأقصر كلماته بالترتيب داخل الأطول؛
    /// كلمة واحدة لا تطابق إلا كلمة واحدة مثلها
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let x = NameSearch.words(a), y = NameSearch.words(b)
        guard let fx = x.first, let fy = y.first, fx == fy else { return false }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        if short.count == 1 { return long.count == 1 }
        var i = 0
        for w in long where i < short.count && short[i] == w { i += 1 }
        return i == short.count
    }

    static func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    static func canSend(motherChosen: Bool, option: FatherOption?, useRegistered: Bool, typedName: String, minWords: Int) -> Bool {
        guard motherChosen, let option else { return false }
        switch option {
        case .fatherInFamily: return false
        case .registered: return useRegistered || wordCount(typedName) >= minWords
        case .typed: return wordCount(typedName) >= minWords
        }
    }

    /// كتبت اسماً لا يطابق زوج أمّها المسجّل ← اسمه للتنبيه (الإدارة تقرّر، والسيرفر لا يكتب فوقه)
    static func conflictName(option: FatherOption?, useRegistered: Bool, typedName: String) -> String? {
        guard case .registered(_, let name)? = option, !useRegistered, wordCount(typedName) > 0,
              !namesMatch(typedName, name) else { return nil }
        return name
    }

    // MARK: شاشة الانتظار

    enum WaitingCard: Equatable { case hidden, offer, rejected, pending }

    /// nil = الدالة غائبة أو تعذّر الجلب ← لا بطاقة
    static func waitingCard(eligible: Bool?, pending: Bool, wasRejected: Bool) -> WaitingCard {
        if pending { return .pending }
        guard eligible == true else { return .hidden }
        return wasRejected ? .rejected : .offer
    }

    // MARK: «الوارد» (عربي — الإنجليزية من `L10n` في البطاقة)

    static func inboxTitle(_ k: Kind) -> String {
        k == .daughterDaughter ? "طلب نسب · بنت بنت" : "طلب نسب · ابن بنت"
    }

    static func approveNote(_ k: Kind, isNewFather: Bool) -> String {
        guard k == .daughterDaughter else {
            return "عند الموافقة يُضاف تحت أمّه في شجرة النساء" + (isNewFather ? "، ويُضاف أبوه زوجاً لها." : ".")
        }
        return isNewFather
            ? "عند الموافقة يُضاف أبوها زوجاً لأمّها، وتُضاف هي تحتهما في شجرة النساء ويُفعَّل حسابها."
            : "عند الموافقة تُضاف تحت أمّها وأبيها في شجرة النساء ويُفعَّل حسابها."
    }

    static func rejectNote(_ k: Kind) -> String {
        k == .daughterDaughter
            ? "يصلها السبب وتختار من جديد، ويبقى طلب انضمامها معلّقاً."
            : "تعود له خانة «أكمل حسابك» ليختار من جديد، ويصله السبب."
    }

    static func selfLabel(_ k: Kind) -> String { k == .daughterDaughter ? "هي بنفسها" : "هو بنفسه" }

    static func placeNote(_ k: Kind, motherName: String) -> String {
        (k == .daughterDaughter ? "بنت بنت العائلة «" : "ابن بنت العائلة «") + motherName + "»"
    }
}
