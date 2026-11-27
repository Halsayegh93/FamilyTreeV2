import SwiftUI
import Combine
import Supabase

// MARK: - «العائلة» في كرت العضو v3 «ب» — بيانات السيرفر كما هي (الوحدة V3، طلب المالك ٢٠٢٦-١١-٢٦: «بيانات السيرفر
// مرتبطة بالكرت و تعديلها من خلال الكرت»)
//
// المصادر (قراءة فقط هنا — الكتابة في المربّعات `AdminMemberCardBoxes.swift` بنداءاتها الموجودة):
//   • شجرة الرجال `profiles` (`memberVM`): الأب (`father_id`) والأبناء.
//   • شجرة النساء `women_members` (`WomenStore.fetch` — الرجال فيها بنفس معرّفاتهم): الأم، الزوجات (`husband_id`،
//     ترتيب `wife_order`)، الزوج، البنات (`parent_id`)، «من خارج العائلة» (`is_outside_family`)، الإخفاء ومن أخفاها
//     (`hidden_by_family`).
//   • `daughter_son_lineage` (يقرؤها المالك والمدير والمراقب): ابن البنت، من اعتمده ومتى، وعقدته في شجرة النساء.
// المخزن واحد للورقة (`AdminMemberCardFamilyStore.shared`) — يُجلب مرة عند الفتح وبعد كل حفظ.

@MainActor
final class AdminMemberCardFamilyStore: ObservableObject {
    static let shared = AdminMemberCardFamilyStore()

    /// شجرة النساء كاملة (الرجال بنسخهم والنساء)
    @Published private(set) var people: [FamilyMember] = []
    @Published private(set) var loaded = false
    /// صفّ ابن البنت لكل عضو جُلب (nil = ليس ابن بنت)
    @Published private(set) var lineageRows: [UUID: LineageRow] = [:]
    /// تدقيق ٢٠٢٦-١١-٢٧: من سُئل عن صفّه (وُجد أو لا) — قبله «العائلة» لابن البنت «—» (`AdminMemberCardLogic.familyKnown`)
    @Published private(set) var lineageChecked: Set<UUID> = []
    private var lastFetch: Date?

    nonisolated struct LineageRow: Decodable, Equatable, Sendable {
        let profileId: UUID
        let approvedBy: UUID?
        let approvedAt: String?
        let womenNodeId: UUID?

        enum CodingKeys: String, CodingKey {
            case profileId = "profile_id"
            case approvedBy = "approved_by"
            case approvedAt = "approved_at"
            case womenNodeId = "women_node_id"
        }
    }

    /// شجرة النساء — مرة كل ٢٠ ثانية على الأكثر، و`force` بعد كل حفظ
    func refresh(force: Bool = false) async {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < 20, loaded { return }
        lastFetch = Date()
        do {
            let rows = try await WomenStore.fetch()
            people = rows
            loaded = true
        } catch {
            lastFetch = nil
            if !WomenStore.cache.isEmpty { people = WomenStore.cache; loaded = true }
            Log.warning("[MemberCard] شجرة النساء: \(error.localizedDescription)")
        }
    }

    /// صفّ «ابن بنت» للعضو (من اعتمده ومتى وعقدته) — قراءة الجدول نفسه بسياسته
    func refreshLineage(_ memberId: UUID) async {
        do {
            let rows: [LineageRow] = try await SupabaseConfig.client.from("daughter_son_lineage")
                .select("profile_id, approved_by, approved_at, women_node_id")
                .eq("profile_id", value: memberId.uuidString)
                .limit(1)
                .execute().value
            if let row = rows.first { lineageRows[memberId] = row } else { lineageRows[memberId] = nil }
        } catch {
            Log.warning("[MemberCard] daughter_son_lineage: \(error.localizedDescription)")
        }
        // الفشل أيضاً ينهي الانتظار — يبقى ما نعرفه (لا «—» دائماً)
        lineageChecked.insert(memberId)
    }

    func node(_ id: UUID?) -> FamilyMember? {
        guard let id else { return nil }
        return people.first { $0.id == id }
    }
}

// MARK: - حقائق «العائلة» المحسوبة

@MainActor
struct AdminMemberCardFamily {
    typealias Lineage = AdminMemberCardLogic.Lineage

    /// العضو من شجرة الرجال (`profiles`) — لا: عقدة في شجرة النساء وحدها
    let isProfile: Bool
    /// عقدته في شجرة النساء (الرجل بمعرّفه، المرأة المسجّلة بعقدتها المربوطة، ابن البنت بعقدته) — nil = لا عقدة بعد
    let nodeId: UUID?
    let father: FamilyMember?
    /// الأب عقدة «زوج من خارج العائلة» (ابن البنت)
    let fatherIsOutside: Bool
    let mother: FamilyMember?
    /// الأم بنت رجل من شجرة العائلة
    let motherIsFamilyDaughter: Bool
    /// زوجات الرجل بترتيب الإدارة (`wife_order`) أو زوج المرأة
    let spouses: [FamilyMember]
    let outsideIds: Set<UUID>
    let sons: [FamilyMember]
    let daughters: [FamilyMember]
    let lineage: Lineage?
    let lineageRow: AdminMemberCardFamilyStore.LineageRow?
    /// عقدة شجرة النساء التي يُخفيها مفتاح «الظهور» (ابن البنت والمرأة) — nil = ملفه في شجرة الرجال
    let visibilityNode: FamilyMember?
    let hidden: Bool
    /// أخفاها أهلها — الإظهار منهم وحدهم
    let hiddenByFamily: Bool
    /// رأس الشجرة (بلا أب وله أبناء) — لا صفّ «الأب»
    let isProfileRoot: Bool
    /// تدقيق ٢٠٢٦-١١-٢٧: شجرة النساء (وصفّ ابن البنت) وصلت — قبلها الصفوف «—» لا «غير مسجّل» (`familyKnown`)
    let known: Bool

    init(member m: FamilyMember, isProfile: Bool, all: [FamilyMember], byId: (UUID) -> FamilyMember?,
         women: [FamilyMember], daughterSon: Bool, lineageRow: AdminMemberCardFamilyStore.LineageRow?,
         known: Bool = true) {
        self.isProfile = isProfile
        self.known = known
        let womenById = Dictionary(women.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // عقدته: ابن البنت بعقدته المسجّلة، المرأة المسجّلة بعقدتها المربوطة، وإلا معرّفه نفسه إن كان في شجرة النساء
        let node: UUID? = {
            if let n = lineageRow?.womenNodeId { return n }
            if !isProfile { return m.id }
            if m.isFemale, let linked = WomenStore.womanByLinkedUser[m.id] { return linked }
            return womenById[m.id] != nil ? m.id : nil
        }()
        nodeId = node
        let mirror = node.flatMap { womenById[$0] }
        let outside = WomenStore.outsideFamilyIds
        outsideIds = outside

        // الأب: شجرة الرجال، وإلا أبو العقدة في شجرة النساء (زوج من خارج العائلة لابن البنت)
        if let f = m.fatherId.flatMap(byId) {
            father = f
            fatherIsOutside = false
        } else if let pid = mirror?.fatherId, let f = byId(pid) ?? womenById[pid] {
            father = f
            fatherIsOutside = outside.contains(pid)
        } else {
            father = nil
            fatherIsOutside = false
        }

        let motherId = mirror?.motherId ?? m.motherId
        mother = motherId.flatMap { womenById[$0] }
        motherIsFamilyDaughter = mother.flatMap { $0.fatherId }.flatMap(byId) != nil

        // الزوجات (رجل) أو الزوج (امرأة)
        let female = m.isFemale
        if female {
            let hid = mirror?.husbandId ?? m.husbandId
            spouses = hid.flatMap { womenById[$0] ?? byId($0) }.map { [$0] } ?? []
        } else if let node {
            let orders = WomenStore.wifeOrderByWoman
            spouses = women.filter { $0.isFemale && $0.husbandId == node }
                .sorted { WomenStore.wifeOrdered($0, $1, orders: orders) }
        } else {
            spouses = []
        }

        isProfileRoot = isProfile && m.fatherId == nil && all.contains { $0.fatherId == m.id }
            && lineageRow == nil && !daughterSon
        sons = isProfile ? all.filter { $0.fatherId == m.id }.sorted { $0.sortOrder < $1.sortOrder } : []
        if let node, !female {
            daughters = women.filter { $0.isFemale && $0.fatherId == node }.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            daughters = []
        }

        self.lineageRow = lineageRow
        lineage = AdminMemberCardLogic.lineage(isDaughterSon: daughterSon || lineageRow != nil,
                                               outsideFlag: node.map { outside.contains($0) } ?? false,
                                               isFemale: female,
                                               hasFamilyFather: m.fatherId.flatMap(byId) != nil
                                                   || (female && mirror?.fatherId.flatMap(byId) != nil))

        // الظهور: ابن البنت والمرأة في شجرة النساء، والرجل في شجرة الرجال
        let usesWomenNode = daughterSon || lineageRow != nil || !isProfile || female
        visibilityNode = usesWomenNode ? mirror : nil
        if usesWomenNode, let mirror {
            hidden = mirror.isHiddenFromTree
            hiddenByFamily = WomenStore.hiddenInfo[mirror.id]?.byFamily == true
        } else {
            hidden = m.isHiddenFromTree
            hiddenByFamily = false
        }
    }

    static func firstName(_ m: FamilyMember?) -> String? {
        guard let m else { return nil }
        return AdminMemberSheetLogic.firstName(m.firstName, full: m.fullName)
    }

    /// «ابن وبنتان»
    var childrenSummary: String? {
        AdminMemberCardLogic.childrenSummary(sons: sons.count, daughters: daughters.count, arabic: L10n.isArabic)
    }

    /// «ابن وبنتان» أو «لا أبناء مسجّلون» — الصفّ وسطر الملخّص
    var childrenValue: String {
        AdminMemberCardLogic.childrenValue(sons: sons.count, daughters: daughters.count, arabic: L10n.isArabic)
    }

    var childrenNames: String? {
        AdminMemberSheetLogic.childrenLine((sons + daughters).map(\.firstName))
    }

    /// «زوجتان» / «زوج»
    func spousesSummary(female: Bool) -> String? {
        AdminMemberCardLogic.spousesSummary(count: spouses.count, female: female, arabic: L10n.isArabic)
    }

    var anySpouseOutside: Bool { spouses.contains { outsideIds.contains($0.id) } }

    /// «ابن بنت · أمّه سهيله» / «من العائلة · فرع حسن» / «زوج من خارج العائلة»
    func lineageTag(branch: String?) -> String? {
        guard let lineage else { return nil }
        switch lineage {
        case .family:
            return [Self.title(.family), branch].compactMap { $0 }.joined(separator: " · ")
        case .daughterSon:
            if let mom = Self.firstName(mother) {
                return Self.title(.daughterSon) + " · " + L10n.t("أمّه \(mom)", "mother \(mom)")
            }
            return Self.title(.daughterSon)
        case .outsideHusband, .outsideWife:
            return Self.title(lineage)
        }
    }

    /// «اعتمده حسن · 20/11/2026» — لابن البنت من صفّه، وإلا لا شيء
    func lineageSetBy(byId: (UUID) -> FamilyMember?) -> String? {
        guard lineage == .daughterSon, let row = lineageRow else { return nil }
        let who = row.approvedBy.flatMap(byId).flatMap { Self.firstName($0) }
        let when = DateHelper.displayDate(row.approvedAt)
        switch (who, when) {
        case let (w?, d?): return L10n.t("اعتمده \(w) · \(d)", "Set by \(w) · \(d)")
        case let (w?, nil): return L10n.t("اعتمده \(w)", "Set by \(w)")
        case let (nil, d?): return L10n.t("اعتُمد \(d)", "Set \(d)")
        default: return nil
        }
    }

    static func title(_ lineage: Lineage) -> String {
        switch lineage {
        case .family: return L10n.t("من العائلة", "From the family")
        case .daughterSon: return L10n.t("ابن بنت", "Daughter's son")
        case .outsideHusband: return L10n.t("زوج من خارج العائلة", "Husband from outside the family")
        case .outsideWife: return L10n.t("زوجة من خارج العائلة", "Wife from outside the family")
        }
    }

    /// شرح كل خيار في مربّع «صلته/صلتها بالعائلة» (م١٠: «أبوها… وتظهر تحت أبيها» للمرأة)
    static func explanation(_ lineage: Lineage, female: Bool = false) -> String {
        switch lineage {
        case .family:
            if female {
                return L10n.t("أبوها في شجرة العائلة، وتظهر تحت أبيها.", "Her father is in the family tree; shown under him.")
            }
            return L10n.t("أبوه في شجرة العائلة، ويظهر تحت أبيه.", "His father is in the family tree; shown under him.")
        case .daughterSon:
            return L10n.t("أبوه من خارج العائلة وأمّه من بنات العائلة. يظهر في شجرة النساء تحت أمّه.",
                          "Father from outside, mother a family daughter. Shown in the women's tree under her.")
        case .outsideHusband:
            return L10n.t("زوج لبنت من العائلة، ليس من نسبها.", "Husband of a family daughter, not of her lineage.")
        case .outsideWife:
            return L10n.t("زوجة لرجل من العائلة، ليست من نسبها.", "Wife of a family man, not of its lineage.")
        }
    }

    /// شارة الرأس: «ابن بنت» أو «من خارج العائلة» — nil لمن من العائلة
    var headerTag: String? {
        switch lineage {
        case .daughterSon: return Self.title(.daughterSon)
        case .outsideHusband, .outsideWife: return L10n.t("من خارج العائلة", "From outside the family")
        default: return nil
        }
    }
}

// MARK: - «العائلة» — المجموعة الثانية في «العضو»

/// الأب (بشارة صلته) · الأم · الزوجة/الزوجات أو الزوج (بشارة «من خارج العائلة») · الأبناء والبنات (صفّ واحد بملخّصه) ·
/// الظهور في الشجرة (مفتاح يسأل قبل الإخفاء، وبعده «تراجع») · الصلة بالعائلة (الشارة ومن اعتمدها ومتى). كل ‹ يفتح مربّعه
struct AdminMemberFamilyGroup: View {
    let member: FamilyMember
    let family: AdminMemberCardFamily
    let canEdit: Bool
    /// الأبناء والزوجات: من يدير الأبناء (`canEdit` بلا المراقب — كما كانت «الأبناء» في الورقة)
    let canManageChildren: Bool
    let branch: String?
    let requestRows: Set<AdminCardRow>
    let pendingRows: Set<AdminCardRow>
    let viewer: UUID?
    let byId: (UUID) -> FamilyMember?
    let handlers: AdminMemberCardHandlers

    private var m: FamilyMember { member }
    private var female: Bool { m.isFemale }

    private func jump(_ row: AdminCardRow) -> (() -> Void)? {
        requestRows.contains(row) ? { handlers.jumpToRequest(row) } : nil
    }

    /// «—» قبل المعرفة (`family.known`)، وإلا القيمة
    private func shown(_ value: String?) -> String? {
        AdminMemberCardLogic.knownValue(value, known: family.known, placeholder: AdminStoreHealthText.placeholder)
    }

    var summary: String {
        guard family.known else { return AdminStoreHealthText.placeholder }
        let ar = L10n.isArabic
        var parts: [String] = []
        if !family.isProfileRoot {
            parts.append(AdminMemberCardLogic.part(AdminMemberCardFamily.firstName(family.father).map { L10n.t("الأب \($0)", "Father \($0)") },
                                                   label: L10n.t("الأب", "Father"), arabic: ar))
        }
        if family.lineage == .daughterSon || !family.isProfile || female {
            parts.append(AdminMemberCardLogic.part(AdminMemberCardFamily.firstName(family.mother).map {
                female ? L10n.t("أمّها \($0)", "Mother \($0)") : L10n.t("أمّه \($0)", "Mother \($0)")
            }, label: L10n.t("الأم", "Mother"), arabic: ar, feminine: true))
        }
        parts.append(AdminMemberCardLogic.part(family.spousesSummary(female: female),
                                               label: female ? L10n.t("الزوج", "Husband") : L10n.t("الزوجة", "Wife"),
                                               arabic: ar, feminine: !female))
        if !female {
            // م١٠: الملخّص والصفّ بكلمة واحدة («لا أبناء مسجّلون»)
            parts.append(family.childrenValue)
        }
        return AdminMemberCardLogic.summary(parts)
    }

    private var fatherTag: AdminMemberTag? {
        guard family.father != nil else { return nil }
        if family.fatherIsOutside { return .lineage(.outsideHusband) }
        return nil
    }

    private var motherTag: AdminMemberTag? {
        guard family.mother != nil else { return nil }
        return family.motherIsFamilyDaughter ? AdminMemberTag(text: L10n.t("بنت العائلة", "Family daughter"), tone: .family) : nil
    }

    private var spouseTitle: String {
        if female { return L10n.t("الزوج", "Husband") }
        return family.spouses.count > 1 ? L10n.t("الزوجات", "Wives") : L10n.t("الزوجة", "Wife")
    }

    private var spouseValue: String? {
        guard let first = family.spouses.first else { return nil }
        if family.spouses.count > 1 { return family.spousesSummary(female: female) }
        return AdminMemberCardFamily.firstName(first)
    }

    private var spouseNames: String? {
        guard family.spouses.count > 1 else { return nil }
        return AdminMemberSheetLogic.childrenLine(family.spouses.map(\.firstName))
    }

    var body: some View {
        AdminMemberGroupCard(group: .family, summary: summary, requestRows: requestRows, pendingRows: pendingRows,
                             viewer: viewer) {
            if !family.isProfileRoot {
                // الأب: شجرة الرجال تُربط/تُغيَّر بمربّع الأب (`LinkFatherSheet`)؛ أبو ابن البنت في شجرة النساء — للاطلاع
                AdminMemberFactRow(icon: "arrow.triangle.branch", tint: DS.Color.palm, title: L10n.t("الأب", "Father"),
                                   tag: fatherTag, value: shown(AdminMemberCardFamily.firstName(family.father)),
                                   hasRequest: requestRows.contains(.father),
                                   action: canEdit && family.isProfile && family.lineage != .daughterSon
                                       ? { handlers.openTall(.father(m)) } : nil,
                                   actionHint: family.father == nil ? L10n.t("ربط", "Link") : L10n.t("تغيير", "Change"),
                                   jump: jump(.father))
            }
            // م٤: منتقي الأم (بنات العائلة — `DSWifeFlowBox(relation: .mother)` ← `WomenStore.setMotherId`)، لا شجرة النساء
            AdminMemberFactRow(icon: "heart", tint: DS.Color.palm, title: L10n.t("الأم", "Mother"),
                               tag: motherTag, value: shown(AdminMemberCardFamily.firstName(family.mother)), feminine: true,
                               hasRequest: requestRows.contains(.mother),
                               action: canEdit && family.nodeId != nil ? { handlers.openFamily(.mother(m)) } : nil,
                               actionHint: family.mother == nil ? L10n.t("إضافة", "Add") : L10n.t("تغيير", "Change"),
                               jump: jump(.mother))
            AdminMemberFactRow(icon: "heart", tint: DS.Color.palm, title: spouseTitle, subtitle: spouseNames,
                               tag: family.anySpouseOutside ? AdminMemberTag(text: L10n.t("من خارج العائلة", "From outside the family"),
                                                                            tone: .outside) : nil,
                               value: shown(spouseValue), feminine: !female, hasRequest: requestRows.contains(.spouses),
                               action: canEdit && family.nodeId != nil ? { handlers.openFamily(.spouses(m)) } : nil,
                               actionHint: L10n.t("إدارة", "Manage"), jump: jump(.spouses))
            if !female {
                AdminMemberFactRow(icon: "person.2", tint: DS.Color.palm, title: L10n.t("الأبناء والبنات", "Sons and daughters"),
                                   subtitle: family.known ? family.childrenNames : nil, value: shown(family.childrenValue),
                                   hasRequest: requestRows.contains(.children),
                                   action: canManageChildren && family.isProfile ? { handlers.openFamily(.children(m)) } : nil,
                                   actionHint: L10n.t("إدارة", "Manage"), jump: jump(.children))
            }
            visibilityRow
            // م١١: «من العائلة» وحدها — الفرع في الرأس
            AdminMemberFactRow(icon: "tag", tint: DS.Color.palm, title: L10n.t("الصلة بالعائلة", "Relation to the family"),
                               subtitle: family.lineageSetBy(byId: byId),
                               tag: family.lineage.map { .lineage($0, text: family.lineageTag(branch: nil)) },
                               value: family.lineage == nil ? nil : "", feminine: true, hidesValue: family.lineage != nil,
                               hasRequest: requestRows.contains(.lineage),
                               action: canEdit ? { handlers.openFamily(.lineage(m)) } : nil,
                               actionHint: L10n.t("تعديل", "Edit"), jump: jump(.lineage))
        }
    }

    /// «الظهور في الشجرة»: مفتاح لمن يعدّل (الإخفاء يسأل أولاً، وبعده «تراجع»)، وكلمة لمن يطّلع. ابن البنت والمرأة:
    /// عقدتهما في شجرة النساء. ما أخفاه أهلها مقفول — الإظهار منهم وحدهم
    @ViewBuilder
    private var visibilityRow: some View {
        let womenTree = family.visibilityNode != nil
        let title = womenTree ? L10n.t("الظهور في شجرة النساء", "Shown in the women's tree")
                              : L10n.t("الظهور في الشجرة", "Shown in the tree")
        let note: String? = {
            if family.hiddenByFamily { return L10n.t("أخفاها أهلها — الإظهار منهم", "Hidden by her family — only they can show her") }
            if family.lineage == .daughterSon { return L10n.t("ابن بنت: في شجرة النساء فقط", "Daughter's son: women's tree only") }
            if family.hidden { return female ? L10n.t("مخفية عن الأعضاء", "Hidden from members")
                                             : L10n.t("مخفي عن الأعضاء", "Hidden from members") }
            return nil
        }()
        // ابن البنت بلا عقدة محمّلة: لا مفتاح على ملفه في شجرة الرجال (السيرفر يرفض إظهاره هناك). قبل وصول شجرة النساء
        // لا مفتاح ولا «مخفي» — «—» (كان ابن البنت «مخفي» بإخفاء ملفه حتى تصل عقدته)
        let canToggle = family.known && canEdit && !family.hiddenByFamily
            && (family.visibilityNode != nil || (family.isProfile && family.lineage != .daughterSon && !female))
        if canToggle {
            AdminMemberFactRow(icon: "tree", tint: DS.Color.palm, title: title, subtitle: note, hidesValue: true,
                               pending: pendingRows.contains(.visibility),
                               accessory: AnyView(Toggle(title, isOn: Binding(get: { !family.hidden },
                                                                              set: { shown in handlers.setHidden(!shown) }))
                                   .labelsHidden()
                                   .tint(DS.Color.toggleOn)
                                   .disabled(pendingRows.contains(.visibility))
                                   .accessibilityHint(Text(family.hidden ? (female ? L10n.t("يُظهرها", "Shows her")
                                                                                   : L10n.t("يُظهره", "Shows them"))
                                                                         : L10n.t("يسأل قبل الإخفاء", "Asks before hiding")))))
        } else {
            AdminMemberFactRow(icon: "tree", tint: DS.Color.palm, title: title, subtitle: family.known ? note : nil,
                               value: shown(family.hidden ? (female ? L10n.t("مخفية", "Hidden") : L10n.t("مخفي", "Hidden"))
                                                          : (female ? L10n.t("ظاهرة", "Shown") : L10n.t("ظاهر", "Shown"))))
        }
    }
}
