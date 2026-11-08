import Foundation
import CoreGraphics

// MARK: - «التقارير» بثلاث أسئلة في صفحة واحدة — ملف واحد (اختيار المالك ٢٠٢٦-١١-٠٦ «أ»، `samples/admin-family-reports`)
//
// ١ «شنو تبي تطبع؟» أجزاء الملف (`AdminReportPart`، واحد أو أكثر — كل جزء يبدأ صفحة ويدخل الفهرس) ٢ «عن مين؟» الفرع
// والتصفية ٣ «كيف ترتّبه؟» التجميع والأعمدة. التقارير العشرة و«كتاب الفرع» صارت «جاهزة بضغطة» (`AdminReportPreset`) تعبّئ
// الأسئلة نفسها. ورقة التقرير من البداية: **الصفحة الأولى = الملخّص** (بلا غلاف مزخرف): عنوان التقرير وتصفيته كلها،
// أربعة أرقام، الفرع مختصراً، التوزيع، وفهرس الملف بصفحاته — ثم **الأسماء في عمودين بالبيوت** (كل بيت مربّع مستقل).
// كل جزء غير الأسماء يأتي من بانيه الموجود (`AdminReportBuilder` — الخصوصية كما هي: الهواتف في «الهواتف» وحده،
// والمخفي «مخفي»). يُبنى ويُرسم خارج الخيط الرئيسي.

/// جزء من الملف — بترتيبه في الملف
nonisolated enum AdminReportPart: String, CaseIterable, Identifiable, Sendable {
    case names, phones, tree, numbers, memorial, calendar, incomplete, attendance, form, cards

    var id: String { rawValue }

    /// عنوان الجزء في الملف وفهرسه
    func pdfTitle(_ grouping: AdminReportGrouping) -> String {
        switch self {
        case .names:
            switch grouping {
            case .father: return "الأسماء بالبيوت"
            case .branch: return "الأسماء بالفروع"
            case .birthDecade: return "الأسماء بعقد الميلاد"
            case .alphabet: return "الأسماء أبجدياً"
            case .country: return "الأسماء بالدولة"
            }
        case .phones: return "دليل الهواتف"
        case .tree: return "شجرة الفرع"
        case .numbers: return "الأرقام بالتفصيل"
        case .memorial: return "الراحلون وذكراهم"
        case .calendar: return "تقويم الذكرى"
        case .incomplete: return "الناقصة بياناتهم"
        case .attendance: return "قائمة الحضور"
        case .form: return "استمارة استكمال البيانات"
        case .cards: return "بطاقات الأفراد"
        }
    }

    /// التقرير الموجود الذي يبني هذا الجزء
    var kind: AdminReportKind? {
        switch self {
        case .names: return nil
        case .phones: return .phones
        case .numbers: return .stats
        case .memorial: return .memorial
        case .calendar: return .calendar
        case .incomplete: return .incomplete
        case .tree, .attendance, .form, .cards: return .book
        }
    }

    var bookSection: AdminReportBookSection? {
        switch self {
        case .tree: return .tree
        case .attendance: return .attendance
        case .form: return .form
        case .cards: return .cards
        default: return nil
        }
    }
}

/// أعمدة «الأسماء» في العمودين — ما يتّسع لنصف الصفحة (الهاتف في «الهواتف» وحده)
nonisolated enum AdminReportNameColumns {
    static let allowed: [AdminReportField] = [.birth, .age, .registration, .death]
    static let defaults: [AdminReportField] = [.birth, .age, .registration]
}

/// ما يُطلب بناؤه من صفحة الأسئلة الثلاث
nonisolated struct AdminReportComposeRequest: Sendable {
    var parts: [AdminReportPart]
    var filter: AdminReportFilter
    /// أعمدة «الأسماء» بعد الاسم
    var columns: [AdminReportField]
    var plan: AdminReportGroupPlan
    /// «الفترة» (من قُيّد في الشجرة) — للأسماء
    var periodOn: Bool = false
    /// «الناقص» — للأسماء: من ينقصه شيء فقط
    var missingOn: Bool = false
    /// «جاهزة بضغطة» المختارة — عنوان الملف إن وُجد
    var presetTitle: String? = nil
}

// MARK: - كتل الورقة الجديدة

/// رأس الصفحة الأولى: «المحمدعلي» كبيراً والتاريخ، ثم عنوان التقرير وسطره وكل التصفية شرائح
nonisolated struct AdminReportMasthead: Sendable {
    struct Pill: Sendable {
        let label: String
        let value: String
    }

    let title: String
    let subtitle: String
    let pills: [Pill]
    let dateLine: String
    let timeLine: String
}

/// التوزيع: شريط التسجيل في التطبيق بمفتاحه، وأشرطة الأعمار
nonisolated struct AdminReportDistribution: Sendable {
    struct Segment: Sendable {
        let label: String
        let count: Int
        let tone: AdminReportTone
    }

    let registration: [Segment]
    let ages: [Segment]
}

/// «في هذا الملف»: الأجزاء بصفحاتها (تُعرف بعد التوزيع)، والبيوت بصفحاتها تحت الأسماء
nonisolated struct AdminReportFileIndex: Sendable {
    /// عناوين الأجزاء (`.section`) بالترتيب — «الملخّص» أولاً دائماً
    let parts: [String]
    /// الجزء الذي تُسرد بيوته تحته — nil = بلا بيوت
    let housesUnder: String?
    /// عدد البيوت المسرودة (يُحجز مكانها) — ٠ = لا تُسرد
    let houses: Int
}

/// الأسماء في عمودين: كل مجموعة (بيت، فرع، عقد…) مربّع بعنوانه وسطره، وصفوف الاسم والأعمدة المختارة
nonisolated struct AdminReportHouses: Sendable {
    struct Row: Sendable {
        let name: String
        /// بترتيب `columns`
        let cells: [String]
        let tones: [Int: AdminReportTone]
        let deceased: Bool
    }

    struct House: Sendable {
        let title: String
        let caption: String?
        let rows: [Row]
    }

    let columns: [AdminReportField]
    let houses: [House]
}

// MARK: - «جاهزة بضغطة»: التقارير العشرة و«كتاب الفرع»

nonisolated struct AdminReportPreset: Identifiable, Sendable {
    let kind: AdminReportKind
    let parts: [AdminReportPart]
    var life: AdminReportFilter.Life = .all
    var registration: AdminReportFilter.Registration = .all
    var grouping: AdminReportGrouping = .father
    var periodOn = false
    var missingOn = false

    var id: String { kind.rawValue }

    static let all: [AdminReportPreset] = [
        AdminReportPreset(kind: .phones, parts: [.phones], life: .living),
        AdminReportPreset(kind: .memorial, parts: [.memorial]),
        AdminReportPreset(kind: .book, parts: [.tree, .names, .memorial, .attendance]),
        AdminReportPreset(kind: .register, parts: [.names]),
        AdminReportPreset(kind: .tree, parts: [.tree]),
        AdminReportPreset(kind: .branchReport, parts: [.numbers, .tree, .names, .memorial]),
        AdminReportPreset(kind: .registered, parts: [.names], life: .living, registration: .registered),
        AdminReportPreset(kind: .calendar, parts: [.calendar]),
        AdminReportPreset(kind: .stats, parts: [.numbers]),
        AdminReportPreset(kind: .newThisMonth, parts: [.names], periodOn: true),
        AdminReportPreset(kind: .incomplete, parts: [.incomplete], missingOn: true)
    ]

    static func preset(_ kind: AdminReportKind) -> AdminReportPreset? { all.first { $0.kind == kind } }
}

// MARK: - البناء

nonisolated enum AdminReportComposer {

    /// أقصى عدد بيوت يُسرد في فهرس الصفحة الأولى
    static let indexHousesMax = 16

    static func build(_ r: AdminReportComposeRequest, input: AdminReportInput) -> AdminReportDoc {
        let B = AdminReportBuilder.self
        let tree = AdminReportTree(input.people, rootId: input.rootId)
        let f = r.filter
        var parts: [String] = []
        var pool = tree.pool
        var scopeTitle: String? = nil
        if let scope = f.scope {
            pool = pool.filter { scope.ids.contains($0.id) }
            scopeTitle = scope.title
            parts.append("من صفحة الأعضاء: \(scope.title)")
        }
        pool = B.scoped(tree, input, f, pool, parts: &parts)
        let scopePath = parts.last ?? ""
        let wholeScope = pool
        var qualifiers: [String] = []
        let ages = B.ages(pool, input)
        pool = B.lifeAndAge(pool, f, ages: ages, usesLife: true, usesAge: true, parts: &qualifiers)
        pool = B.registrationFilter(pool, f, input.registered, parts: &qualifiers)
        if r.periodOn {
            let range = B.period(f.period, today: input.date)
            pool = pool.filter { p in p.createdAt.map { $0 >= range.from && $0 < range.to } ?? false }
            qualifiers.append("انضافوا \(range.label)")
        }
        if r.missingOn {
            pool = pool.filter { p in
                let m = B.missing(p, tree: tree)
                return f.missing == .any ? !m.isEmpty : m.contains(f.missing)
            }
            qualifiers.append(f.missing == .any ? "ينقصهم شيء" : "ينقصهم \(B.missingLabel(f.missing))")
        }
        parts += qualifiers

        let head = f.branch.map { B.branchTitle($0, input: input) } ?? scopeTitle ?? "العائلة كاملة"
        let title = r.presetTitle.map { "\($0) — \(head)" }
            ?? (qualifiers.isEmpty ? head : "\(head) — \(qualifiers.joined(separator: " · "))")
        let ordered = AdminReportPart.allCases.filter { r.parts.contains($0) }
        let partTitles = ordered.map { $0.pdfTitle(r.plan.grouping) }
        let subtitle = (["الأرقام"] + partTitles).joined(separator: "، ثم ")

        // الأسماء بالمجموعات (مرة واحدة: للبيوت ولعددها في الملخّص)
        let sections = tree.sections(pool, plan: r.plan, names: input.branchNames)
        let houseTitle: (AdminReportTree.Section) -> String = { s in
            guard r.plan.grouping == .father, s.title.hasPrefix("أبناء ") else { return s.title }
            return "بيت " + s.title.dropFirst("أبناء ".count)
        }

        var blocks: [AdminReportBlock] = []
        blocks.append(.masthead(masthead(title: title, subtitle: subtitle, r: r, scopePath: scopePath, input: input)))
        blocks += summary(pool: pool, whole: wholeScope, sections: sections, tree: tree, input: input, r: r, ages: ages)
        let namesTitle = ordered.contains(.names) ? AdminReportPart.names.pdfTitle(r.plan.grouping) : nil
        let listedHouses = namesTitle != nil && sections.count <= indexHousesMax ? sections.count : 0
        blocks.append(.heading("في هذا الملف", subtitle: nil, panel: true))
        blocks.append(.fileIndex(AdminReportFileIndex(parts: ["الملخّص"] + partTitles, housesUnder: namesTitle,
                                                      houses: listedHouses)))
        blocks.append(.heading("عن هذا الملف", subtitle: nil, panel: true))
        blocks.append(.note(aboutText(r, ordered), tone: .muted))

        // الأجزاء — كل جزء يبدأ صفحة بعنوانه (`.section` يدخل الفهرس)، وما في داخله لا يدخل الفهرس
        for part in ordered {
            let partTitle = part.pdfTitle(r.plan.grouping)
            switch part {
            case .names:
                let houses = sections.count
                let noun = r.plan.grouping == .father ? "\(AdminReportText.num(houses)) \(houses >= 3 && houses <= 10 ? "بيوت" : "بيتاً")"
                    : "\(AdminReportText.num(houses)) \(houses >= 3 && houses <= 10 ? "مجموعات" : "مجموعة")"
                blocks.append(.section(partTitle, subtitle: "\(AdminReportText.people(pool.count)) في \(noun) · \(r.plan.grouping.pdfLabel)"))
                if pool.isEmpty {
                    blocks.append(.note("لا يوجد أفراد يطابقون هذا النطاق.", tone: .muted))
                } else {
                    blocks.append(.caption("● عضو مسجّل في التطبيق   ○ بدون حساب   ● حساب موقوف — الاسم الثلاثي والعائلة في رأس كل بيت"))
                    blocks.append(.houses(houseBlock(sections, title: houseTitle, r: r, tree: tree, input: input, ages: ages)))
                }
            default:
                guard let kind = part.kind else { continue }
                var partFilter = f
                partFilter.scope = nil
                var request = AdminReportRequest(kind: kind, filter: partFilter, fields: defaultFields(kind), plan: r.plan)
                let doc: AdminReportDoc
                if let section = part.bookSection {
                    request.book = [section]
                    doc = B.build(request, input: input)
                    // الكتاب يبدأ قسمه بعنوانه — يُستبدل بعنوان الجزء
                    blocks.append(.section(partTitle, subtitle: doc.scope.isEmpty ? nil : doc.scope))
                    blocks += strip(doc.blocks, dropFirstSection: true)
                } else {
                    doc = B.build(request, input: input)
                    blocks.append(.section(partTitle, subtitle: doc.scope.isEmpty ? nil : doc.scope))
                    blocks += strip(doc.blocks, dropFirstSection: false)
                }
            }
        }

        var doc = AdminReportDoc(kind: ordered.count == 1 ? (ordered[0].kind ?? .register) : .register,
                                 scope: parts.joined(separator: " · "), count: pool.count, intro: subtitle,
                                 blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.grouping = r.plan.grouping.pdfLabel
        doc.cover = false
        doc.summaryFirst = true
        doc.customTitle = title
        return doc
    }

    /// الأعمدة الافتراضية لتقرير جزء
    static func defaultFields(_ kind: AdminReportKind) -> [AdminReportField] {
        kind.fields.filter { kind.defaultFields.contains($0) }
    }

    /// داخل الجزء: الأشرطة والأقسام الداخلية لا تدخل الفهرس (أشهر التقويم تبقى صفحات بلا فهرس)
    static func strip(_ blocks: [AdminReportBlock], dropFirstSection: Bool) -> [AdminReportBlock] {
        var out: [AdminReportBlock] = []
        var dropped = !dropFirstSection
        for b in blocks {
            switch b {
            case let .band(t, s, _): out.append(.band(t, subtitle: s, toc: false))
            case let .section(t, s):
                if !dropped { dropped = true; continue }
                out.append(.pageBreak)
                out.append(.heading(t, subtitle: s, panel: false))
            default: out.append(b)
            }
        }
        return out
    }

    // MARK: الصفحة الأولى

    private static func masthead(title: String, subtitle: String, r: AdminReportComposeRequest, scopePath: String,
                                 input: AdminReportInput) -> AdminReportMasthead {
        let f = r.filter
        typealias Pill = AdminReportMasthead.Pill
        var pills: [Pill] = [Pill(label: "النطاق", value: scopePath.isEmpty ? "العائلة كاملة" : scopePath)]
        let life: String
        switch f.life {
        case .all: life = "الكل"
        case .living: life = "الأحياء"
        case .deceased: life = "المتوفون"
        }
        pills.append(Pill(label: "الحالة", value: life))
        let reg: String
        switch f.registration {
        case .all: reg = "الكل"
        case .registered: reg = "مسجّلون"
        case .treeOnly: reg = "بدون حساب"
        case .frozen: reg = "موقوفون"
        }
        pills.append(Pill(label: "التسجيل", value: reg))
        pills.append(Pill(label: "العمر", value: f.ageLimited ? f.ageLabel : "الكل"))
        pills.append(Pill(label: "الترتيب", value: r.plan.grouping.pdfLabel))
        if r.parts.contains(.names) {
            let cols = ["الاسم"] + r.columns.map(columnTitle)
            pills.append(Pill(label: "الأعمدة", value: cols.joined(separator: " · ")))
        }
        return AdminReportMasthead(title: title, subtitle: subtitle, pills: pills,
                                   dateLine: AdminReportText.longDate(input.date),
                                   timeLine: "\(AdminReportText.time(input.date)) بتوقيت الكويت")
    }

    static func columnTitle(_ f: AdminReportField) -> String {
        switch f {
        case .birth: return "الميلاد"
        case .age: return "العمر"
        case .registration: return "التسجيل"
        case .death: return "الوفاة"
        default: return AdminReportBuilder.column(f).title
        }
    }

    private static func summary(pool: [AdminReportPerson], whole: [AdminReportPerson], sections: [AdminReportTree.Section],
                                tree: AdminReportTree, input: AdminReportInput, r: AdminReportComposeRequest,
                                ages: [UUID: Int]) -> [AdminReportBlock] {
        let reg = input.registered
        let living = pool.filter { !$0.deceased }
        let registered = reg.map { set in living.filter { set.contains($0.id) && !$0.frozen }.count }
        let known = pool.compactMap { ages[$0.id] }
        let avg = known.isEmpty ? nil : Int((Double(known.reduce(0, +)) / Double(known.count)).rounded())
        let houses = Set(pool.compactMap(\.fatherId)).count
        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(pool.count), label: "فرداً في هذا التقرير"),
                    AdminReportTile(value: AdminReportText.num(houses), label: houses >= 3 && houses <= 10 ? "بيوت" : "بيتاً"),
                    AdminReportTile(value: registered.map(AdminReportText.num) ?? "—", label: "مسجّلاً في التطبيق"),
                    AdminReportTile(value: avg.map { "\($0) سنة" } ?? "—", label: "متوسط العمر")])
        ]
        if whole.count != pool.count {
            let out = whole.count - pool.count
            blocks.append(.caption("النطاق كاملاً \(AdminReportText.people(whole.count)): \(AdminReportText.people(out)) خارج هذا التقرير بسبب التصفية."))
        }
        if let mini = branchTree(pool: pool, tree: tree, input: input, branch: r.filter.branch) {
            blocks.append(.heading("الفرع مختصراً", subtitle: "أبناء رأس الفرع وعدد الأفراد في بيت كلٍّ منهم", panel: true))
            blocks.append(.miniTree(mini))
        }
        var regSegs: [AdminReportDistribution.Segment] = []
        if let reg {
            let frozen = living.filter(\.frozen).count
            let r1 = living.filter { reg.contains($0.id) && !$0.frozen }.count
            regSegs = [.init(label: "عضو مسجّل", count: r1, tone: .registered),
                       .init(label: "بدون حساب", count: max(0, living.count - r1 - frozen), tone: .treeOnly),
                       .init(label: "حساب موقوف", count: frozen, tone: .warning)]
        }
        var bands: [AdminReportFilter.Age: Int] = [:]
        for p in pool { bands[AdminReportFilter.Age.band(ages[p.id]), default: 0] += 1 }
        let ageSegs = (AdminReportFilter.Age.bands + [.unknown]).map {
            AdminReportDistribution.Segment(label: $0.label, count: bands[$0] ?? 0, tone: $0 == .unknown ? .muted : .men)
        }
        if !pool.isEmpty {
            blocks.append(.heading("التوزيع", subtitle: nil, panel: true))
            blocks.append(.distribution(AdminReportDistribution(registration: regSegs, ages: ageSegs)))
        }
        _ = sections
        return blocks
    }

    /// رأس الفرع المختار (أو الشجرة) ← أبناؤه، وعدد من في التقرير تحت كلٍّ منهم
    private static func branchTree(pool: [AdminReportPerson], tree: AdminReportTree, input: AdminReportInput,
                                   branch: UUID?) -> AdminReportMiniTree? {
        guard let headId = branch ?? tree.rootId, let head = tree.byId[headId] else { return nil }
        let inPool = Set(pool.map(\.id))
        let reg = input.registered
        var nodes: [(count: Int, node: AdminReportMiniTree.Node)] = []
        for c in tree.kids[headId] ?? [] {
            guard let p = tree.byId[c] else { continue }
            let ids = tree.subtree(c).intersection(inPool)
            guard !ids.isEmpty else { continue }
            let alive = ids.filter { tree.byId[$0]?.deceased == false }
            var caption = "\(AdminReportText.num(alive.count)) حياً"
            if let reg { caption += " · \(AdminReportText.num(alive.filter { reg.contains($0) }.count)) مسجّلاً" }
            nodes.append((ids.count, .init(title: p.firstName.isEmpty ? p.name : p.firstName, caption: caption, count: ids.count)))
        }
        guard !nodes.isEmpty else { return nil }
        let maxNodes = AdminReportBuilder.miniTreeMaxNodes
        var shown = nodes.map(\.node)
        if nodes.count > maxNodes {
            let sorted = nodes.sorted { $0.count > $1.count }
            shown = sorted.prefix(maxNodes - 1).map(\.node)
            let rest = sorted.dropFirst(maxNodes - 1)
            shown.append(.init(title: "وغيرهم", caption: AdminReportText.people(rest.count),
                               count: rest.reduce(0) { $0 + $1.count }, isRest: true))
        }
        var caption = branch == nil ? "رأس الشجرة" : "رأس الفرع"
        if head.deceased {
            let years = [AdminReportText.year(head.birth), AdminReportText.year(head.death)].compactMap { $0 }.map(String.init)
            caption += " · متوفى" + (years.count == 2 ? " · \(years.joined(separator: "–"))" : "")
        }
        return AdminReportMiniTree(founder: head.name, founderCaption: caption, nodes: shown)
    }

    private static func aboutText(_ r: AdminReportComposeRequest, _ parts: [AdminReportPart]) -> String {
        var lines: [String] = []
        if parts.contains(.phones) {
            lines.append("• الهواتف في «دليل الهواتف» وحده، والرقم المخفي يُطبع «مخفي».")
        } else {
            lines.append("• الهواتف لا تُطبع هنا — مكانها اختيار «الهواتف» وحده، والرقم المخفي يُطبع «مخفي».")
        }
        lines.append("• «بدون حساب» = اسمه في الشجرة بلا حساب في التطبيق.")
        lines.append("• العمر من تاريخ الميلاد؛ الميلاد المخفي أو الناقص يُعدّ «غير معروف».")
        lines.append("• خاص بعائلة المحمدعلي — لا يُنشر خارجها.")
        return lines.joined(separator: "\n")
    }

    // MARK: الأسماء في عمودين

    private static func houseBlock(_ sections: [AdminReportTree.Section], title: (AdminReportTree.Section) -> String,
                                   r: AdminReportComposeRequest, tree: AdminReportTree, input: AdminReportInput,
                                   ages: [UUID: Int]) -> AdminReportHouses {
        let cols = r.columns.filter { AdminReportNameColumns.allowed.contains($0) }
        let reg = input.registered
        let houses = sections.map { s -> AdminReportHouses.House in
            let rows = s.members.map { p -> AdminReportHouses.Row in
                var cells: [String] = []
                var tones: [Int: AdminReportTone] = [:]
                for (i, c) in cols.enumerated() {
                    switch c {
                    case .birth:
                        cells.append(p.birthHidden ? AdminReportText.hidden : AdminReportText.year(p.birth).map(String.init) ?? "—")
                    case .age:
                        cells.append(ages[p.id].map(String.init) ?? "—")
                    case .death:
                        cells.append(p.deceased ? AdminReportText.deathDate(p.death) : "")
                        if p.deceased { tones[i] = .muted }
                    case .registration:
                        if p.deceased {
                            cells.append("متوفى")
                            tones[i] = .muted
                        } else if p.frozen {
                            cells.append("موقوف")
                            tones[i] = .warning
                        } else if let reg {
                            let on = reg.contains(p.id)
                            cells.append(on ? "مسجّل" : "بدون حساب")
                            tones[i] = on ? .registered : .treeOnly
                        } else {
                            cells.append("—")
                        }
                    default:
                        cells.append("")
                    }
                }
                return .init(name: p.name, cells: cells, tones: tones, deceased: p.deceased)
            }
            var caption = AdminReportText.people(s.members.count)
            if let path = s.path { caption += " · \(path)" }
            return .init(title: title(s), caption: caption, rows: rows)
        }
        return AdminReportHouses(columns: cols, houses: houses)
    }
}
