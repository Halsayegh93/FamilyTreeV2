import SwiftUI

// MARK: - التقسيم والشجرة (طلب المالك ٢٠٢٦-١١-٠٢)
//
// بعد التبسيط (٢٠٢٦-١١-٠٢، `samples/simplify`) صفحتا «العائلة» و«إدارة الوفيات» قائمة واحدة أبجدياً (`AdminGrouping.alphabetical`)
// بشريحة «الفرع: الكل ⌄» (`AdminBranchPickerBox` — فرع بأي مستوى) بلا «التقسيم» ولا بطاقات. خيارات التقسيم والتجميع هنا باقية
// لتقارير PDF (`AdminReportsBook`، `AdminReportFilterPage`). لا مفهوم «الجيل»: العمق مفتاح داخلي فقط.

/// طريقة تقسيم القائمة
enum AdminMemberGrouping: String, CaseIterable, Identifiable {
    case branch, birthDecade, father, alphabet, country, deathDecade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .branch:      return L10n.t("الفرع", "Branch")
        case .birthDecade: return L10n.t("عقد الميلاد", "Birth decade")
        case .father:      return L10n.t("الأب", "Father")
        case .alphabet:    return L10n.t("أبجدياً", "Alphabetical")
        case .country:     return L10n.t("الدولة", "Country")
        case .deathDecade: return L10n.t("عقد الوفاة", "Death decade")
        }
    }

    var icon: String {
        switch self {
        case .branch:      return "point.3.connected.trianglepath.dotted"
        case .birthDecade: return "calendar"
        case .father:      return "person.2.fill"
        case .alphabet:    return "textformat"
        case .country:     return "globe"
        case .deathDecade: return "calendar.badge.clock"
        }
    }

}

// MARK: - الشجرة (تُبنى مرة لكل تغيّر في الأعضاء)

/// روابط الآباء والأبناء من رأس الشجرة (`BranchPickerSheet.familyRoot`) — للفرع المختار وللتقسيم بالفرع وبالأب
struct AdminFamilyTree {
    let rootId: UUID?
    let father: [UUID: UUID]
    let children: [UUID: [UUID]]
    let byId: [UUID: FamilyMember]

    static let empty = AdminFamilyTree(rootId: nil, father: [:], children: [:], byId: [:])

    init(rootId: UUID?, father: [UUID: UUID], children: [UUID: [UUID]], byId: [UUID: FamilyMember]) {
        self.rootId = rootId
        self.father = father
        self.children = children
        self.byId = byId
    }

    init(_ all: [FamilyMember]) {
        var father: [UUID: UUID] = [:]
        var children: [UUID: [UUID]] = [:]
        var byId: [UUID: FamilyMember] = [:]
        byId.reserveCapacity(all.count)
        for m in all {
            byId[m.id] = m
            if let f = m.fatherId {
                father[m.id] = f
                children[f, default: []].append(m.id)
            }
        }
        self.init(rootId: BranchPickerSheet.familyRoot(in: all)?.id, father: father, children: children, byId: byId)
    }

    /// رأس الفرع وكل ذرّيته (بلا تكرار — يحمي من حلقة آباء خاطئة)
    func subtree(of head: UUID) -> Set<UUID> {
        var out: Set<UUID> = [head]
        var stack = [head]
        while let cur = stack.popLast() {
            for c in children[cur] ?? [] where !out.contains(c) {
                out.insert(c)
                stack.append(c)
            }
        }
        return out
    }

    /// سلسلة رؤوس الفروع من ابن رأس الشجرة حتى أبي العضو — [] = العضو نفسه رأس فرع أول، nil = خارج الفروع
    func chain(to id: UUID) -> [UUID]? {
        guard let rootId, id != rootId else { return nil }
        var path: [UUID] = []
        var cur = id
        while let f = father[cur] {
            if f == rootId { return path.reversed() }
            path.append(f)
            cur = f
            if path.count > BranchPickerSheet.maxTreeDepth { return nil }
        }
        return nil
    }

    /// ترتيب الإخوة كما في الشجرة
    func siblingOrder(_ a: UUID, _ b: UUID) -> Bool {
        let x = byId[a], y = byId[b]
        return (x?.sortOrder ?? 0, x?.firstName ?? "") < (y?.sortOrder ?? 0, y?.firstName ?? "")
    }

    /// «فرع محمد» — أو الاسم المخصّص من «أسماء الفروع»
    func branchTitle(_ head: UUID, names: (UUID) -> String?) -> String {
        if let name = names(head) { return name }
        let first = byId[head]?.firstName ?? ""
        return L10n.t("فرع \(first)", "\(first) branch")
    }
}

// MARK: - مجموعة (بطاقة) — متداخلة للفرع، ومسطّحة لغيره

struct AdminBranchGroup<Row: Identifiable>: Identifiable {
    let id: String
    let title: String
    /// كل من في البطاقة وما تحتها
    let count: Int
    /// الصفوف مباشرة في البطاقة (رأس الفرع أولاً ثم من ليس له فرع تحته)
    let rows: [Row]
    /// الفروع تحته
    let children: [AdminBranchGroup<Row>]
}

enum AdminGrouping {
    /// الفرع متداخلاً بكل المستويات: بطاقة لكل رأس فرع له أحد في القائمة تحته، وفيها صفّه وأبناؤه بلا ذرّية في القائمة،
    /// ثم بطاقات فروعه. `root` = الفرع المختار (يبدأ التداخل منه)، وإلا أبناء رأس الشجرة. من لا يتصل بالرأس: «خارج الفروع»
    static func nested<Row: Identifiable>(_ rows: [Row], member: (Row) -> FamilyMember, tree: AdminFamilyTree,
                                          root: UUID? = nil, names: (UUID) -> String?) -> [AdminBranchGroup<Row>] {
        var chains: [UUID: [UUID]] = [:]
        var listed: [(UUID, Row)] = []
        var outside: [Row] = []
        for r in rows {
            let id = member(r).id
            guard var c = tree.chain(to: id) else { outside.append(r); continue }
            if let root {
                if id == root { c = [] }
                else if let k = c.firstIndex(of: root) { c = Array(c[k...]) }
                else { outside.append(r); continue }
            }
            chains[id] = c
            listed.append((id, r))
        }
        // البطاقات: كل رأس في سلسلة أحد، والعضو الذي هو رأس أول
        var isCard = Set<UUID>()
        var tops = Set<UUID>()
        for (id, _) in listed {
            let c = chains[id] ?? []
            isCard.formUnion(c)
            if c.isEmpty { isCard.insert(id) }
            tops.insert(c.first ?? id)
        }
        var count: [UUID: Int] = [:]
        var headRow: [UUID: Row] = [:]
        var rowsOf: [UUID: [Row]] = [:]
        var kids: [UUID: Set<UUID>] = [:]
        for (id, r) in listed {
            let c = chains[id] ?? []
            for a in c { count[a, default: 0] += 1 }
            if c.count > 1 { for i in 0..<(c.count - 1) { kids[c[i], default: []].insert(c[i + 1]) } }
            if isCard.contains(id) {
                count[id, default: 0] += 1
                headRow[id] = r
                if let last = c.last { kids[last, default: []].insert(id) }
            } else if let last = c.last {
                rowsOf[last, default: []].append(r)
            }
        }
        func build(_ id: UUID, depth: Int) -> AdminBranchGroup<Row> {
            let sub = depth >= BranchPickerSheet.maxTreeDepth ? [] : (kids[id] ?? []).sorted(by: tree.siblingOrder)
            return AdminBranchGroup(id: id.uuidString, title: tree.branchTitle(id, names: names), count: count[id] ?? 0,
                                    rows: (headRow[id].map { [$0] } ?? []) + (rowsOf[id] ?? []),
                                    children: sub.map { build($0, depth: depth + 1) })
        }
        var groups = tops.sorted(by: tree.siblingOrder).map { build($0, depth: 0) }
        if !outside.isEmpty {
            groups.append(AdminBranchGroup(id: "outside", title: L10n.t("خارج الفروع", "Outside the branches"),
                                           count: outside.count, rows: outside, children: []))
        }
        return groups
    }

    /// بطاقة مسطّحة
    static func flat<Row: Identifiable>(_ id: String, _ title: String, _ rows: [Row]) -> AdminBranchGroup<Row> {
        AdminBranchGroup(id: id, title: title, count: rows.count, rows: rows, children: [])
    }

    /// سنة ميلادية من «yyyy-MM-dd» (أو سنة فقط) — nil = بلا تاريخ؛ تحت ١٧٠٠ = هجري
    static func year(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4,
              let y = Int(raw.prefix(4)), y > 0 else { return nil }
        return y
    }

    /// «مواليد 1950–1959» الأقدم أولاً، ثم «مكتوب بالهجري»، ثم «بلا تاريخ ميلاد»
    static func birthDecades<Row: Identifiable>(_ rows: [Row], member: (Row) -> FamilyMember) -> [AdminBranchGroup<Row>] {
        var by: [Int: [Row]] = [:]
        var hijri: [Row] = [], none: [Row] = []
        for r in rows {
            guard let y = year(member(r).birthDate) else { none.append(r); continue }
            if y < DeceasedMemorial.minGregorianYear { hijri.append(r) } else { by[y / 10 * 10, default: []].append(r) }
        }
        var list = by.keys.sorted().map { d in
            flat("b\(d)", L10n.t("مواليد \(String(d))–\(String(d + 9))", "Born \(String(d))–\(String(d + 9))"), by[d] ?? [])
        }
        if !hijri.isEmpty { list.append(flat("bhijri", L10n.t("مكتوب بالهجري", "Written as Hijri"), hijri)) }
        if !none.isEmpty { list.append(flat("bnone", L10n.t("بلا تاريخ ميلاد", "No birth date"), none)) }
        return list
    }

    /// بطاقة لكل أب (اسمه المختصر) وأبناؤه تحته بترتيب الشجرة، ثم «بلا أب في الشجرة»
    static func fathers<Row: Identifiable>(_ rows: [Row], member: (Row) -> FamilyMember,
                                           tree: AdminFamilyTree) -> [AdminBranchGroup<Row>] {
        var by: [UUID: [Row]] = [:]
        var none: [Row] = []
        for r in rows {
            if let f = member(r).fatherId, tree.byId[f] != nil { by[f, default: []].append(r) } else { none.append(r) }
        }
        let titles: [UUID: String] = by.keys.reduce(into: [:]) { out, f in
            let m = tree.byId[f]
            out[f] = (m?.shortFullName).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.t("بلا اسم", "No name")
        }
        var list = by.keys.sorted { a, b in
            let x = titles[a] ?? "", y = titles[b] ?? ""
            return x != y ? x.localizedStandardCompare(y) == .orderedAscending : a.uuidString < b.uuidString
        }.map { f in
            flat("f\(f.uuidString)", titles[f] ?? "", (by[f] ?? []).sorted { tree.siblingOrder(member($0).id, member($1).id) })
        }
        if !none.isEmpty { list.append(flat("fnone", L10n.t("بلا أب في الشجرة", "No father in the tree"), none)) }
        return list
    }

    /// الترتيب الأبجدي العربي (الهمزات على الألف ألفاً، والتاء المربوطة والهاء حرفان)
    static let arabicLetters: [Character] = Array("ابتثجحخدذرزسشصضطظعغفقكلمنهةوي")

    /// أول حرف من الاسم الأول مطبّعاً — nil = لا حرف
    static func initial(_ name: String) -> Character? {
        let tashkeel: Set<Character> = ["ً", "ٌ", "ٍ", "َ", "ُ", "ِ", "ّ", "ْ", "ـ"]
        guard let c = name.trimmingCharacters(in: .whitespacesAndNewlines).first(where: { !tashkeel.contains($0) }) else { return nil }
        switch c {
        case "أ", "إ", "آ", "ٱ": return "ا"
        case "ى", "ئ": return "ي"
        case "ؤ": return "و"
        default: return String(c).uppercased().first ?? c
        }
    }

    /// قائمة واحدة أبجدياً (قائمتا «العائلة» و«إدارة الوفيات» بعد التبسيط): رتبة الحرف الأول من الاسم الأول في
    /// `arabicLetters` (ثم اللاتيني ثم غيره)، ثم الاسم كاملاً مطبّعاً (`ArabicTextNormalizer`) — المفاتيح تُحسب مرة لكل عضو
    static func alphabetical(_ members: [FamilyMember]) -> [FamilyMember] {
        let rank: [Character: Int] = Dictionary(uniqueKeysWithValues: arabicLetters.enumerated().map { ($0.element, $0.offset) })
        let keyed = members.map { m -> (member: FamilyMember, rank: Int, name: String) in
            let first = m.firstName.trimmingCharacters(in: .whitespaces)
            let c = initial(first.isEmpty ? m.fullName : first)
            let r = c.flatMap { rank[$0] } ?? (c?.isLetter == true ? arabicLetters.count : arabicLetters.count + 1)
            return (m, r, ArabicTextNormalizer.normalizeForSearch(m.fullName))
        }
        return keyed.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return order == .orderedAscending }
            return a.member.id.uuidString < b.member.id.uuidString
        }.map(\.member)
    }

    /// بطاقة لكل حرف بالترتيب العربي، ثم الحروف اللاتينية، ثم «أخرى»
    static func alphabet<Row: Identifiable>(_ rows: [Row], member: (Row) -> FamilyMember) -> [AdminBranchGroup<Row>] {
        var by: [Character: [Row]] = [:]
        var other: [Row] = []
        for r in rows {
            let m = member(r)
            let name = m.firstName.trimmingCharacters(in: .whitespaces).isEmpty ? m.fullName : m.firstName
            if let c = initial(name), c.isLetter { by[c, default: []].append(r) } else { other.append(r) }
        }
        let rank: [Character: Int] = Dictionary(uniqueKeysWithValues: arabicLetters.enumerated().map { ($0.element, $0.offset) })
        var list = by.keys.sorted { a, b in
            switch (rank[a], rank[b]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return String(a) < String(b)
            }
        }.map { c in flat("a\(c)", String(c), by[c] ?? []) }
        if !other.isEmpty { list.append(flat("aother", L10n.t("أخرى", "Other"), other)) }
        return list
    }

    /// الدولة من رقم الهاتف (الأحياء بأرقامهم — الكويت والسعودية أولاً ثم الأكثر)، ثم «بلا رقم»، ثم «متوفون»
    static func countries<Row: Identifiable>(_ rows: [Row], member: (Row) -> FamilyMember) -> [AdminBranchGroup<Row>] {
        var by: [String: [Row]] = [:]
        var noPhone: [Row] = [], deceased: [Row] = []
        for r in rows {
            let m = member(r)
            if m.isDeceased == true { deceased.append(r); continue }
            if let iso = AdminAnnounceKit.iso(m) { by[iso, default: []].append(r) } else { noPhone.append(r) }
        }
        let pinned = ["KW", "SA"]
        let codes = by.keys.sorted { a, b in
            let pa = pinned.firstIndex(of: a), pb = pinned.firstIndex(of: b)
            switch (pa, pb) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (by[a]?.count ?? 0, b) > (by[b]?.count ?? 0, a)
            }
        }
        var list = codes.map { code -> AdminBranchGroup<Row> in
            let name = KuwaitPhone.supportedCountries.first { $0.isoCode == code }.map { AdminAnnounceKit.countryName($0) } ?? code
            return flat("c\(code)", name, by[code] ?? [])
        }
        if !noPhone.isEmpty { list.append(flat("cnone", L10n.t("بلا رقم", "No number"), noPhone)) }
        if !deceased.isEmpty { list.append(flat("cdead", L10n.t("متوفون", "Deceased"), deceased)) }
        return list
    }
}

/// مربّع اختيار الفرع (كل المستويات) — نوع مستقل (حارس المكدس)
struct AdminBranchPickerBox: ViewModifier {
    @Binding var isPresented: Bool
    let members: [FamilyMember]
    let selected: UUID?
    let onSelect: (UUID) -> Void

    func body(content: Content) -> some View {
        content.dsTallBox(isPresented: $isPresented) {
            BranchPickerSheet(allMembers: members, selectedId: selected, allLevels: true, onSelect: { id in
                onSelect(id)
                isPresented = false
            })
        }
    }
}
