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

/// «موقعك» من شجرة العائلة لابن البنت/بنت البنت (مكانه في شجرة النساء وحدها): التبديل للنساء يبني الشجرة من جديد
/// فيفوتها إشعار `.openWomenTree` — الطلب ينتظر هنا حتى تظهر الشجرة فتنفّذ «موقعك» بالمعرّفات مرة ثم يُمسح.
/// كان التمركز لحساب المرأة والمقيّد وحدهما (`autoLocate`)، فيصل ابن البنت لتبويب النساء بلا تمركز على عقدته
@MainActor
enum WomenLocateRequest {
    static var pending = false

    /// يقرأ الطلب ويمسحه (يُنفَّذ مرة واحدة)
    static func take() -> Bool {
        defer { pending = false }
        return pending
    }
}

/// ماذا تفعل شجرة النساء أول ما تظهر
nonisolated enum WomenOpenAction: Equatable {
    /// تتمركز على عقدته وتُظهر «أنت هنا»
    case locate(UUID)
    /// طلب «موقعك» صريح ولا عقدة له — رسالة «لا مكان لك في شجرة النساء» بدل البداية الصامتة
    case notInTree
    /// الفتح العادي: ملاءمة الجذر وأبنائه
    case fit

    /// - autoLocate: حساب امرأة أو حساب مقيّد — تفتح على عقدتها إن وُجدت (وإلا الفتح العادي كما كان)
    /// - requested: طلب «موقعك» من شجرة العائلة (`WomenLocateRequest`) — لكل أنواع الحسابات
    /// - meId: عقدته (`WomenMyNode.resolve`)
    static func resolve(autoLocate: Bool, requested: Bool, meId: UUID?, hasNode: (UUID) -> Bool) -> WomenOpenAction {
        if let meId, hasNode(meId), autoLocate || requested { return .locate(meId) }
        return requested ? .notInTree : .fit
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

/// العقدة التي يتمركز عليها «موقعك» (٢٠٢٦-١١-٢٨، مفحوص: tests/admin-redesign/W2):
/// الزوجة الوافدة (بلا أب في الشجرة) مربّع جنب زوجها ← عقدته، والزوج من خارج العائلة مربّع جنب زوجته البنت ← عقدتها
nonisolated enum WomenFocusTarget {
    static func resolve(id: UUID, fatherInTree: Bool, husbandId: UUID?, husbandInTree: Bool,
                        outsideWifeOf: [UUID: UUID]) -> UUID {
        var target = id
        if !fatherInTree, let h = husbandId, husbandInTree { target = h }
        if let w = outsideWifeOf[target] { target = w }
        return target
    }
}

/// زوج البنت جنبها (من خارج العائلة، أو من العائلة باختيارها `spouse_shown`) — يظهر متى فُتحت أو ما لها أبناء،
/// ويختفي معها وهي مطويّة ولها أبناء مثل الزوجات (طلب المالك ٢٠٢٦-١١-٢٨ «مابي الزوج يكون ظاهر حتى انطوت عقدة البنت»)
nonisolated enum WomenSpouseRule {
    static func showsHusband(hasHusband: Bool, collapsed: Bool, hasKids: Bool) -> Bool {
        hasHusband && (!collapsed || !hasKids)
    }
}

/// شكل واحد للزوج والزوجة جنب العقدة (طلب المالك ٢٠٢٦-١١-٢٨ «وحّد الشكل»): دائرة/ورقة بمقاس واحد، كبسولة اسم
/// بعرض واحد، ومسافة واحدة عن العقدة، وخطّ ذهبي واحد من حافة العقدة إلى أبعد زوج/زوجة في الجهة.
/// الأرقام = مقاس الزوج المعتمد (٢٠٢٦-١١-٢٤) × معامل «حجم النص»
nonisolated struct WomenSpouseGeometry: Equatable {
    let k: CGFloat
    let circle: CGFloat
    let nodeW: CGFloat

    /// قطر شكل الزوج/الزوجة
    var husbandSquare: CGFloat { 92 * k }
    var wifeSquare: CGFloat { husbandSquare }
    /// عرض خليته وكبسولة اسمه
    var husbandCellW: CGFloat { 150 * k }
    var wifeCellW: CGFloat { husbandCellW }
    /// بين خليتين متجاورتين (زوجتان في جهة واحدة)
    var spacing: CGFloat { 6 * k }
    /// بين حافة العقدة وأول خلية
    var gap: CGFloat { 18 * k }

    /// مركز صفّ من n خلايا عن مركز العقدة
    func centerX(_ n: Int) -> CGFloat {
        circle / 2 + gap + (CGFloat(n) * wifeCellW + CGFloat(max(0, n - 1)) * spacing) / 2
    }
    var husbandCellX: CGFloat { centerX(1) }

    /// كم يطلع صفّ n خلايا عن حافة العقدة
    func overhang(_ n: Int) -> CGFloat {
        guard n > 0 else { return 0 }
        return circle / 2 + gap + CGFloat(n) * wifeCellW + CGFloat(n - 1) * spacing + 2 * k - nodeW / 2
    }
    var husbandOverhang: CGFloat { overhang(1) }

    /// الخط الذهبي: من حافة شكل العضو…
    var lineFrom: CGFloat { circle / 2 }
    /// …إلى الحافة القريبة من شكل أبعد خلية في صفّ n
    func lineTo(_ n: Int) -> CGFloat {
        guard n > 0 else { return lineFrom }
        let far = circle / 2 + gap + CGFloat(n - 1) * (wifeCellW + spacing) + wifeCellW / 2
        return far - wifeSquare / 2
    }
}
