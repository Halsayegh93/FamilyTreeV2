import Foundation

// MARK: - «أم ابن البنت» (بلاغ المالك ٢٠٢٦-١١-٢٧، الوحدة M1)
//
// ابن البنت ملفه في `profiles` بلا أب ولا أم (`profiles.mother_id` يشير إلى `profiles` فلا تُحفظ فيه أمّ من شجرة النساء):
// بيته عقدته في شجرة النساء (`daughter_son_lineage.women_node_id`، أو العقدة المربوطة بحسابه `linked_user_id`)،
// وأبوه `parent_id` تلك العقدة (زوج من خارج العائلة) وأمّه `mother_id`. كان مربّع «الأم من العائلة» يقارن زوج البنت
// بأبيه من `profiles` (nil) فتُخفى كل بنت متزوجة — ومنها أمّه نفسها.
// القواعد خالصة تُفحص بلا محاكي: `tests/admin-redesign/M1/main.swift`.

enum MotherPickRules {

    /// آباء الشخص الذين تُقارن بهم أزواج البنات: أبوه في شجرة العائلة، وأبو عقدته في شجرة النساء (لابن البنت)
    static func personFatherIds(profileFatherId: UUID?, womenNodeFatherId: UUID?) -> Set<UUID> {
        Set([profileFatherId, womenNodeFatherId].compactMap { $0 })
    }

    /// تظهر البنت في قائمة الأم؟ بلا زوج، أو زوجها أحد آباء الشخص، أو هي أمّه المسجّلة في عقدته
    static func isMotherCandidate(daughterId: UUID, husbandId: UUID?, personFatherIds: Set<UUID>,
                                  knownMotherId: UUID?) -> Bool {
        if let knownMotherId, daughterId == knownMotherId { return true }
        guard let husbandId else { return true }
        return personFatherIds.contains(husbandId)
    }

    /// عقدة الحساب في شجرة النساء: صفّ ابن البنت أولاً، ثم العقدة المربوطة بالحساب، ثم معرّفه نفسه (نسخة الرجل)
    static func womenNodeId(accountId: UUID, lineageNodeId: UUID?, linkedNodeId: UUID?,
                            existsInWomenTree: (UUID) -> Bool) -> UUID? {
        if let lineageNodeId { return lineageNodeId }
        if let linkedNodeId { return linkedNodeId }
        return existsInWomenTree(accountId) ? accountId : nil
    }

    /// مكانه في شجرة النساء لا في شجرة العائلة (ابن البنت، أو حساب مربوط بعقدة غير نسخته): أمّه من عقدته.
    /// منذ «بنت بنت» (B1، ٢٠٢٦-١١-٢٧) عقدة ابن/بنت البنت بمعرّف ملفه: نسخة بمعرّفه لها أب وملفه بلا أب = مكانه هناك
    /// (نسخة الرجل لها أب في ملفه، وجذر الفرع بلا أب في عقدته)
    static func isPlacedInWomenTree(accountId: UUID, nodeId: UUID?, nodeParentId: UUID? = nil,
                                    profileFatherId: UUID? = nil) -> Bool {
        guard let nodeId else { return false }
        if nodeId != accountId { return true }
        return nodeParentId != nil && profileFatherId == nil
    }

    // MARK: السطر الثاني لصفّ البنت في مربّعي الأم والزوجة

    /// «بنت فلان · زوجة فلان» / «بنت فلان · غير متزوجة» — يفرّق بين الأسماء المتشابهة
    static func disambiguationLine(fatherName: String?, husbandName: String?, isMarried: Bool) -> String {
        var parts: [String] = []
        let father = shortName(fatherName ?? "")
        if !father.isEmpty { parts.append(text("بنت ", "Daughter of ") + father) }
        let husband = shortName(husbandName ?? "")
        if !husband.isEmpty {
            parts.append(text("زوجة ", "Wife of ") + husband)
        } else {
            parts.append(isMarried ? text("متزوجة", "Married") : text("غير متزوجة", "Unmarried"))
        }
        return parts.joined(separator: " · ")
    }

    /// السطر الثاني مجزّأً (المالك ٢٠٢٦-١١-٢٧ «نص أخف»): شرائح صغيرة «الوالد: …» · «الجد: …» · «الميلاد: …» · «الزوج: …».
    /// الوالد والجد من اسم والدها الكامل (الكلمة الأولى والثانية)، والزوج مختصراً إن وُجد
    struct NamePart: Equatable {
        let label: String
        let value: String
        /// يطابق بيانات الطلب ← شريحة خضراء (المالك «حركة ممتازة»)
        var matches: Bool = false
    }

    /// الشرائح المطابقة لبيانات الطلب، بالتطبيع العربي الواحد (`NameSearch.words`):
    /// «الوالد»/«الجد» = الكلمة الثانية/الثالثة من الاسم المكتوب (الاسم ثم والدها ثم جدها) · «الزوج» = أول كلمتين من اسم
    /// الوالد المتوقَّع · «الميلاد» = السنة نفسها
    static func markMatches(_ parts: [NamePart], typedName: String?, expectedHusband: String?,
                            birthYear: Int? = nil) -> [NamePart] {
        let typed = NameSearch.words(typedName ?? "")
        let husband = NameSearch.words(expectedHusband ?? "")
        return parts.map { p in
            var q = p
            let v = NameSearch.words(p.value)
            switch p.label {
            case text("الوالد", "Father"): q.matches = typed.count > 1 && v.first == typed[1]
            case text("الجد", "Grandfather"): q.matches = typed.count > 2 && v.first == typed[2]
            case text("الزوج", "Husband"): q.matches = husband.count >= 2 && v.count >= 2 && Array(v.prefix(2)) == Array(husband.prefix(2))
            case text("الميلاد", "Born"): q.matches = birthYear.map { String($0) == p.value } ?? false
            default: break
            }
            return q
        }
    }

    static func disambiguationParts(fatherName: String?, husbandName: String?, birthYear: Int? = nil) -> [NamePart] {
        var parts: [NamePart] = []
        // «عبد الله» كلمة واحدة (نفس قاعدة البحث)
        var w: [String] = []
        for part in (fatherName ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if let last = w.last, last == "عبد" { w[w.count - 1] = last + part } else { w.append(part) }
        }
        if let f = w.first { parts.append(NamePart(label: text("الوالد", "Father"), value: f)) }
        if w.count > 1 { parts.append(NamePart(label: text("الجد", "Grandfather"), value: w[1])) }
        if let birthYear { parts.append(NamePart(label: text("الميلاد", "Born"), value: String(birthYear))) }
        let h = shortName(husbandName ?? "")
        if !h.isEmpty { parts.append(NamePart(label: text("الزوج", "Husband"), value: h)) }
        return parts
    }

    /// أول ثلاث كلمات من الاسم (الاسم والأب والجد) بمسافات موحّدة
    static func shortName(_ full: String, words: Int = 3) -> String {
        full.split(whereSeparator: { $0.isWhitespace }).prefix(words).joined(separator: " ")
    }

    private static func text(_ ar: String, _ en: String) -> String {
        #if ADMIN_LOGIC_TEST
        ar
        #else
        L10n.t(ar, en)
        #endif
    }
}
