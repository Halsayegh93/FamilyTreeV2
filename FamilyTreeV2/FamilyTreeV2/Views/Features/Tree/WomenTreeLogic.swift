import Foundation

// منطق خالص لشجرة النساء (مراجعة ٢٠٢٦-١١-٢٧) — بلا SwiftUI، يُفحص بلا محاكي: tests/admin-redesign/W1/main.swift

/// كبسولة العقدة: «من خارج العائلة» للزوج نفسه فقط، و«ابن بنت / بنت بنت» لكل أبناء البنات (أمّه من العائلة وأبوه من
/// خارجها) — كانت حفيدة البنت تُكتب «من خارج العائلة»، و«ابن بنت» لا يظهر إلا للذكر صاحب الحساب
nonisolated enum WomenNodeTag: Equatable {
    case outsideFamily
    case daughterSon
    case daughterDaughter

    /// - outside: سجلّات «من خارج العائلة» (`WomenStore.outsideFamilyIds`)
    static func resolve(id: UUID, isFemale: Bool, fatherId: UUID?, motherId: UUID?,
                        outside: Set<UUID>) -> WomenNodeTag? {
        guard !outside.isEmpty else { return nil }
        // ابن/بنت البنت: الأب من خارج العائلة والأم من العائلة — قبل فحص السجل نفسه
        if let f = fatherId, outside.contains(f), let mom = motherId, !outside.contains(mom) {
            return isFemale ? .daughterDaughter : .daughterSon
        }
        if outside.contains(id) { return .outsideFamily }
        return nil
    }
}

/// عقدة المستخدم في شجرة النساء لزرّ «موقعك» — بالمعرّفات وحدها (كان تخميناً بأول ٣ كلمات من الاسم فيوصل لغيره):
/// ١) عقدة بمعرّف ملفه نفسه (الرجل: عقدته المرآة؛ ابن/بنت البنت بمعرّف ملفه) ٢) عقدة مربوطة بحسابه (`linked_user_id`)
nonisolated enum WomenMyNode {
    static func resolve(userId: UUID?, hasNode: (UUID) -> Bool, womanByLinkedUser: [UUID: UUID]) -> UUID? {
        guard let userId else { return nil }
        if hasNode(userId) { return userId }
        if let linked = womanByLinkedUser[userId], hasNode(linked) { return linked }
        return nil
    }
}

/// صورة في شجرة النساء وبطاقتها — قاعدة واحدة: الإناث بلا صور أبداً، والذكر صورته أو صورة حسابه المربوط (ابن البنت)
nonisolated enum WomenTreePhoto {
    static func url(isFemale: Bool, own: String?, linked: String?) -> String? {
        guard !isFemale else { return nil }
        if let own, !own.isEmpty { return own }
        if let linked, !linked.isEmpty { return linked }
        return nil
    }
}

/// جملة القارئ الصوتي للعقدة: «منال، ابنة، متوفاة» + تلميح ما يحدث بالضغط
nonisolated enum WomenNodeSpeech {
    /// - relation: الكبسولة إن وُجدت («ابن بنت»…)، وإلا «ابنة»/«ابن»
    static func label(name: String, isFemale: Bool, deceased: Bool, relation: String?) -> String {
        var parts = [name.trimmingCharacters(in: .whitespacesAndNewlines)]
        parts.append(relation ?? (isFemale ? "ابنة" : "ابن"))
        if deceased { parts.append(isFemale ? "متوفاة" : "متوفى") }
        return parts.filter { !$0.isEmpty }.joined(separator: "، ")
    }

    static func hint(children: Int, collapsed: Bool) -> String {
        guard children > 0 else { return "تُفتح التفاصيل" }
        return collapsed ? "تُفتح فيظهر الأبناء (\(children))" : "تُطوى فيختفي الأبناء"
    }
}
