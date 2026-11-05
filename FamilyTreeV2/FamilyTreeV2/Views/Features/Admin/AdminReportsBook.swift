import Foundation

// MARK: - التقارير الجديدة و«كتاب الفرع» (طلب المالك ٢٠٢٦-١١-٠٢ — مزيج الاتجاهين «أ» و«ج»)
//
// • «المسجّلون في التطبيق»: الأحياء — مسجّل · مقيّد · موقوف، بنسبة لكل فرع، ثم القائمة بالتجميع المختار.
// • «المقيّدون في الشجرة» (هذا الشهر / الشهر الماضي / ٩٠ يوماً) من `created_at` بتوقيت الكويت.
// • «الناقصة بياناتهم»: ما ينقص كل فرد (الميلاد · تاريخ وفاة كامل · الصورة · الأب في الشجرة).
// • «تقويم الذكرى»: صفحة لكل شهر بمن تحلّ ذكراهم (تاريخ الوفاة الكامل فقط — الباقي «لا يوجد تاريخ كامل للوفاة» في ملاحظة).
// • «شجرة فرع مطبوعة»: الفرع مرسوماً بخطوط ذهبية — يتّسع على A4، وما لا يتّسع يُختصر وينزل لصفحة فرعه، أو يُصغَّر،
//   أو يُقسَّم الأبناء على صفحات؛ ومفتاح صغير للقراءة.
// • «كتاب الفرع» (المعالج) و«تقرير فرع شامل»: أقسام تبدأ كل منها صفحة وتدخل الفهرس. بلا هواتف أبداً.
// التجميع من صفحة الأعضاء (`AdminGrouping`) يُحسب هنا على الخيط الرئيسي (`AdminReportGroupPlan.make`).

extension AdminReportGroupPlan {
    /// الخطّة من أدوات التجميع في صفحة الأعضاء — `root`: الفرع المختار (يبدأ التداخل منه)
    @MainActor
    static func make(_ grouping: AdminReportGrouping, members: [FamilyMember], tree: AdminFamilyTree,
                     root: UUID?, names: @escaping (UUID) -> String?) -> AdminReportGroupPlan {
        let rows = members.filter { $0.role != .pending && $0.hasName }
        var sections: [Section] = []
        switch grouping {
        case .branch:
            let groups = AdminGrouping.nested(rows, member: { $0 }, tree: tree, root: root, names: names)
            func walk(_ g: AdminBranchGroup<FamilyMember>, path: [String], depth: Int) {
                if !g.rows.isEmpty {
                    sections.append(Section(title: g.title, path: path.isEmpty ? nil : path.joined(separator: " ‹ "),
                                            depth: depth, ids: g.rows.map(\.id)))
                }
                for c in g.children { walk(c, path: path + [g.title], depth: depth + 1) }
            }
            groups.forEach { walk($0, path: [], depth: 0) }
        case .father:
            for g in AdminGrouping.fathers(rows, member: { $0 }, tree: tree) {
                let title = g.id == "fnone" ? g.title : "أبناء \(g.title)"
                sections.append(Section(title: title, path: nil, depth: 0, ids: g.rows.map(\.id)))
            }
        case .birthDecade:
            sections = AdminGrouping.birthDecades(rows, member: { $0 })
                .map { Section(title: $0.title, path: nil, depth: 0, ids: $0.rows.map(\.id)) }
        case .alphabet:
            sections = AdminGrouping.alphabet(rows, member: { $0 })
                .map { Section(title: $0.title, path: nil, depth: 0, ids: $0.rows.map(\.id)) }
        case .country:
            // من أخفى رقمه لا تُستنتج دولته — يدخل «بلا رقم»
            let masked = rows.map { m -> FamilyMember in
                guard m.isPhoneHidden == true else { return m }
                var copy = m
                copy.phoneNumber = nil
                return copy
            }
            sections = AdminGrouping.countries(masked, member: { $0 })
                .map { Section(title: $0.title, path: nil, depth: 0, ids: $0.rows.map(\.id)) }
        }
        return AdminReportGroupPlan(grouping: grouping, sections: sections)
    }
}

nonisolated extension AdminReportBuilder {

    // MARK: المسجّلون في التطبيق

    static func registered(_ tree: AdminReportTree, _ input: AdminReportInput, _ r: AdminReportRequest) -> AdminReportDoc {
        let filter = r.filter
        let reg = input.registered
        var parts: [String] = []
        var pool = scoped(tree, input, filter, tree.pool.filter { !$0.deceased }, parts: &parts)
        let ages = ages(pool, input)
        pool = lifeAndAge(pool, filter, ages: ages, usesLife: false, usesAge: true, parts: &parts)
        let all = pool
        pool = registrationFilter(pool, filter, reg, parts: &parts)

        var counts: [AdminReportFilter.Registration: Int] = [:]
        for p in all { if let s = registration(p, reg) { counts[s, default: 0] += 1 } }
        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(all.count), label: "الأحياء"),
                    AdminReportTile(value: reg == nil ? "—" : AdminReportText.num(counts[.registered] ?? 0), label: "مسجّلون"),
                    AdminReportTile(value: reg == nil ? "—" : AdminReportText.num(counts[.treeOnly] ?? 0), label: "مقيّدون"),
                    AdminReportTile(value: AdminReportText.num(counts[.frozen] ?? 0), label: "موقوف")])
        ]
        if reg == nil {
            blocks.append(.note("تعذّر تحميل حالة التسجيل وقت إنشاء التقرير.", tone: .warning))
        } else if !all.isEmpty {
            blocks.append(.split(AdminReportSplit(firstLabel: AdminReportText.registered, first: counts[.registered] ?? 0,
                                                  secondLabel: "غير مسجّل", second: all.count - (counts[.registered] ?? 0))))
            // النسبة لكل فرع أول
            var table = AdminReportTable(columns: [
                .init(title: "الفرع", weight: 0.34, wraps: true),
                .init(title: "الأحياء", weight: 0.13, centered: true),
                .init(title: "مسجّلون", weight: 0.13, centered: true),
                .init(title: "مقيّدون", weight: 0.13, centered: true),
                .init(title: "موقوف", weight: 0.12, centered: true),
                .init(title: "النسبة", weight: 0.15, centered: true)
            ], rows: [])
            for g in tree.groups(all, names: input.branchNames) {
                var c: [AdminReportFilter.Registration: Int] = [:]
                for p in g.members { if let s = registration(p, reg) { c[s, default: 0] += 1 } }
                table.rows.append(.init(cells: [g.title, AdminReportText.num(g.members.count),
                                                AdminReportText.num(c[.registered] ?? 0), AdminReportText.num(c[.treeOnly] ?? 0),
                                                AdminReportText.num(c[.frozen] ?? 0),
                                                AdminReportText.percent(c[.registered] ?? 0, of: g.members.count)]))
            }
            table.footer = .init(cells: ["المجموع", AdminReportText.num(all.count), AdminReportText.num(counts[.registered] ?? 0),
                                         AdminReportText.num(counts[.treeOnly] ?? 0), AdminReportText.num(counts[.frozen] ?? 0),
                                         AdminReportText.percent(counts[.registered] ?? 0, of: all.count)])
            blocks.append(.heading("النسبة لكل فرع", subtitle: "الأحياء من رجال الشجرة", panel: true))
            blocks.append(.table(table))
        }
        if pool.isEmpty {
            blocks.append(.note("لا يوجد أفراد يطابقون هذا النطاق.", tone: .muted))
        } else {
            let ctx = CellContext(tree: tree, input: input, ages: ages, fields: r.fields)
            blocks += memberSections(pool, ctx: ctx, plan: r.plan) { registrationSummary($0, reg) }
        }
        let intro = "الأحياء من أفراد الشجرة وحالة كل منهم في التطبيق: عضو مسجّل (له حساب دخول)، أو مقيّد في الشجرة فقط،"
            + " أو حساب موقوف — بنسبة لكل فرع ثم القائمة."
        var doc = AdminReportDoc(kind: .registered, scope: parts.joined(separator: " · "), count: pool.count, intro: intro,
                                 blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.grouping = r.plan.grouping.pdfLabel
        return doc
    }

    // MARK: المقيّدون في الشجرة (الفترة)

    /// بداية الفترة ونهايتها بتوقيت الكويت، واسمها
    static func period(_ p: AdminReportFilter.Period, today: Date) -> (from: Date, to: Date, label: String) {
        let cal = AdminReportText.kuwait
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        switch p {
        case .thisMonth:
            let m = cal.component(.month, from: today)
            return (startOfMonth, .distantFuture, "هذا الشهر (\(DeceasedMemorial.arabicMonths[max(0, m - 1)]))")
        case .lastMonth:
            let from = cal.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
            let m = cal.component(.month, from: from)
            return (from, startOfMonth, "الشهر الماضي (\(DeceasedMemorial.arabicMonths[max(0, m - 1)]))")
        case .last90:
            return (cal.date(byAdding: .day, value: -90, to: cal.startOfDay(for: today)) ?? today, .distantFuture, "آخر 90 يوماً")
        }
    }

    static func newMembers(_ tree: AdminReportTree, _ input: AdminReportInput, _ r: AdminReportRequest) -> AdminReportDoc {
        let filter = r.filter
        let range = period(filter.period, today: input.date)
        var parts: [String] = [range.label]
        var pool = tree.pool.filter { p in p.createdAt.map { $0 >= range.from && $0 < range.to } ?? false }
        pool = scoped(tree, input, filter, pool, parts: &parts)
        let ages = ages(pool, input)
        pool = lifeAndAge(pool, filter, ages: ages, usesLife: true, usesAge: false, parts: &parts)
        let living = pool.filter { !$0.deceased }.count
        let branchCount = Set(pool.compactMap { tree.branchOf[$0.id] }).count
        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(pool.count), label: "قُيّدوا"),
                    AdminReportTile(value: AdminReportText.num(living), label: "أحياء"),
                    AdminReportTile(value: AdminReportText.num(pool.count - living), label: "متوفون"),
                    AdminReportTile(value: AdminReportText.num(branchCount), label: "الفروع")])
        ]
        if pool.isEmpty {
            blocks.append(.note("لم يُقيَّد أحد في الشجرة في هذه الفترة.", tone: .muted))
        } else {
            let ctx = CellContext(tree: tree, input: input, ages: ages, fields: r.fields)
            blocks += memberSections(pool, ctx: ctx, plan: r.plan) { lifeSummary($0) }
        }
        let intro = "من أُضيفوا إلى شجرة العائلة في \(range.label) — من تاريخ قيدهم في السجل."
        var doc = AdminReportDoc(kind: .newThisMonth, scope: parts.joined(separator: " · "), count: pool.count, intro: intro,
                                 blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.grouping = r.plan.grouping.pdfLabel
        return doc
    }

    // MARK: الناقصة بياناتهم

    static func incomplete(_ tree: AdminReportTree, _ input: AdminReportInput, _ r: AdminReportRequest) -> AdminReportDoc {
        let filter = r.filter
        var parts: [String] = []
        var pool = scoped(tree, input, filter, tree.pool.filter(\.countable), parts: &parts)
        let ages = ages(pool, input)
        pool = lifeAndAge(pool, filter, ages: ages, usesLife: true, usesAge: false, parts: &parts)
        var missing: [UUID: [AdminReportFilter.Missing]] = [:]
        var counts: [AdminReportFilter.Missing: Int] = [:]
        for p in pool {
            let m = AdminReportBuilder.missing(p, tree: tree)
            guard !m.isEmpty else { continue }
            missing[p.id] = m
            for k in m { counts[k, default: 0] += 1 }
        }
        if filter.missing != .any { parts.append("ينقصه: \(missingLabel(filter.missing))") }
        pool = pool.filter { p in
            guard let m = missing[p.id] else { return false }
            return filter.missing == .any || m.contains(filter.missing)
        }
        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(counts[.birth] ?? 0), label: "بلا تاريخ ميلاد"),
                    AdminReportTile(value: AdminReportText.num(counts[.death] ?? 0), label: "وفاة بلا تاريخ كامل"),
                    AdminReportTile(value: AdminReportText.num(counts[.photo] ?? 0), label: "بلا صورة"),
                    AdminReportTile(value: AdminReportText.num(counts[.father] ?? 0), label: "بلا أب في الشجرة")])
        ]
        if pool.isEmpty {
            blocks.append(.note("لا ينقص أحداً في هذا النطاق شيء.", tone: .muted))
        } else {
            var ctx = CellContext(tree: tree, input: input, ages: ages, fields: r.fields)
            ctx.missing = missing
            blocks += memberSections(pool, ctx: ctx, plan: r.plan) { "المجموع: \(AdminReportText.people($0.count))" }
        }
        let intro = "ما ينقص كل فرد في الشجرة: تاريخ الميلاد، أو تاريخ وفاة كامل، أو الصورة، أو أبوه في الشجرة —"
            + " للاستكمال من ورقة العضو أو باستمارة «كتاب الفرع»."
        var doc = AdminReportDoc(kind: .incomplete, scope: parts.joined(separator: " · "), count: pool.count, intro: intro,
                                 blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.grouping = r.plan.grouping.pdfLabel
        return doc
    }

    // MARK: تقويم الذكرى

    static func calendar(_ tree: AdminReportTree, _ input: AdminReportInput, _ filter: AdminReportFilter) -> AdminReportDoc {
        let cal = AdminReportText.kuwait
        var parts: [String] = []
        let dead = scoped(tree, input, filter, tree.pool.filter { $0.deceased && $0.countable }, parts: &parts)
        struct Entry { let p: AdminReportPerson; let y: Int; let m: Int; let d: Int }
        var byMonth: [Int: [Entry]] = [:]
        var excluded = 0
        for p in dead {
            if !p.deathUnknown, case let .exact(y, m, d) = DeceasedMemorial.classify(p.death) {
                byMonth[m, default: []].append(Entry(p: p, y: y, m: m, d: d))
            } else {
                excluded += 1
            }
        }
        let thisYear = cal.component(.year, from: input.date)
        let included = dead.count - excluded
        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(dead.count), label: "المتوفون"),
                    AdminReportTile(value: AdminReportText.num(included), label: "في التقويم"),
                    AdminReportTile(value: AdminReportText.num(excluded), label: "بلا تاريخ كامل"),
                    AdminReportTile(value: "\(thisYear)", label: "السنة")])
        ]
        if excluded > 0 {
            blocks.append(.note("\(AdminReportText.people(excluded)): \(AdminReportText.noFullDeathDate) — لا يدخلون التقويم"
                                + " حتى يُستكمل التاريخ (السنة وحدها أو الهجري لا يحدّدان يوم الذكرى).", tone: .warning))
        }
        for m in 1...12 {
            let list = (byMonth[m] ?? []).sorted { ($0.d, $0.p.name) < ($1.d, $1.p.name) }
            blocks.append(.section(DeceasedMemorial.arabicMonths[m - 1],
                                   subtitle: list.isEmpty ? "لا ذكرى في هذا الشهر" : "ذكرى \(AdminReportText.people(list.count))"))
            guard !list.isEmpty else { continue }
            var table = AdminReportTable(columns: [
                .init(title: "اليوم", centered: true),
                .init(title: "الاسم الكامل", wraps: true, fill: true),
                .init(title: "سنة الوفاة", centered: true),
                .init(title: "الذكرى", centered: true),
                .init(title: "الفرع", wraps: true)
            ], rows: [])
            for e in list {
                let years = thisYear - e.y
                table.rows.append(.init(cells: ["\(e.d)", e.p.name, "\(e.y)", years >= 1 ? "الـ\(years)" : "—",
                                                tree.branchLabel(of: e.p, names: input.branchNames)]))
            }
            table.summary = "المجموع: \(AdminReportText.people(list.count))"
            blocks.append(.table(table))
        }
        parts.append("سنة \(thisYear)")
        let intro = "اثنا عشر شهراً، لكل شهر صفحة بمن تحلّ ذكرى وفاتهم فيه ورقم الذكرى هذه السنة — يُعلَّق في الديوانية."
        return AdminReportDoc(kind: .calendar, scope: parts.joined(separator: " · "), count: included, intro: intro,
                              blocks: blocks, generatedBy: input.generatedBy, date: input.date)
    }

    // MARK: شجرة فرع مطبوعة (وحدها)

    static func treeOnly(_ tree: AdminReportTree, _ input: AdminReportInput, _ filter: AdminReportFilter) -> AdminReportDoc {
        var parts: [String] = []
        let root = filter.branch ?? tree.rootId
        let pool = scoped(tree, input, filter, tree.pool, parts: &parts)
        var blocks: [AdminReportBlock] = []
        if let root, tree.byId[root] != nil {
            blocks = chartBlocks(tree, input, root: root)
        } else {
            blocks.append(.note("لا يوجد رأس للشجرة.", tone: .muted))
        }
        let intro = "الفرع مرسوماً بخطوط ذهبية: الرأس ثم أبناؤه وأحفاده. ما لا يتّسع في صفحة ينزل لصفحة فرعه."
        return AdminReportDoc(kind: .tree, scope: parts.joined(separator: " · "), count: pool.count, intro: intro,
                              blocks: blocks, generatedBy: input.generatedBy, date: input.date)
    }

    /// أقصى عدد صفحات شجرة في ملف واحد (العائلة كاملة) — الباقي في «سجل الأفراد»
    static let maxTreePages = 40
    /// خانات الأوراق في سطر الصفحة: مريحة، ثم مصغّرة
    static let treeSlotsComfort = 12
    static let treeSlotsScaled = 20
    /// المستويات تحت الرأس في الصفحة
    static let treeDepth = 3

    /// صفحات الشجرة: الرأس بأعمق مستوى يتّسع؛ والعقدة المختصرة (لها نسل خارج الصفحة) تأخذ صفحتها بعد ذلك
    static func chartBlocks(_ tree: AdminReportTree, _ input: AdminReportInput, root: UUID) -> [AdminReportBlock] {
        var blocks: [AdminReportBlock] = []
        var queue: [UUID] = [root]
        var pages = 0
        var truncated = false

        func leaves(_ id: UUID, _ depth: Int) -> Int {
            let k = tree.kids[id] ?? []
            if depth == 0 || k.isEmpty { return 1 }
            return k.reduce(0) { $0 + leaves($1, depth - 1) }
        }

        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard pages < maxTreePages else { truncated = true; break }
            let kids = tree.kids[id] ?? []
            // أعمق مستوى يتّسع بالمقاس المريح، وإلا بالمصغّر، وإلا يُقسَّم الأبناء
            var depth = 0
            for limit in [treeSlotsComfort, treeSlotsScaled] where depth == 0 {
                for d in stride(from: treeDepth, through: 1, by: -1) where leaves(id, d) <= limit {
                    depth = d
                    break
                }
            }
            // أبناء أكثر من السطر: يُقسَّمون على صفحات بمستوى واحد
            let chunks: [[UUID]] = depth == 0
                ? stride(from: 0, to: kids.count, by: treeSlotsScaled).map { Array(kids[$0..<min($0 + treeSlotsScaled, kids.count)]) }
                : [kids]
            let showDepth = max(depth, 1)
            for (ci, chunk) in chunks.enumerated() {
                guard pages < maxTreePages else { truncated = true; break }
                var nodes: [AdminReportTreeChart.Node] = []
                var continued: [UUID] = []
                func add(_ id: UUID, _ level: Int, only: [UUID]? = nil) -> Int {
                    let index = nodes.count
                    nodes.append(AdminReportTreeChart.Node(title: "", caption: nil, deceased: false, continued: false, children: []))
                    let p = tree.byId[id]
                    let children = only ?? (tree.kids[id] ?? [])
                    var childIdx: [Int] = []
                    let showsKids = level < showDepth
                    if showsKids { for c in children { childIdx.append(add(c, level + 1)) } }
                    let hasHidden = !showsKids && !(tree.kids[id] ?? []).isEmpty
                    if hasHidden { continued.append(id) }
                    nodes[index] = AdminReportTreeChart.Node(
                        title: p.map { $0.firstName.isEmpty ? $0.name : $0.firstName } ?? "",
                        caption: chartCaption(p, count: hasHidden || (level == 1 && !(tree.kids[id] ?? []).isEmpty)
                                              ? tree.count(under: id) : nil),
                        deceased: p?.deceased ?? false, continued: hasHidden, children: childIdx)
                    return index
                }
                _ = add(id, 0, only: chunk)
                let head = tree.byId[id]
                let title = head.map { "شجرة \(tree.byId[id] != nil && id != tree.rootId ? tree.title(ofHead: $0, names: input.branchNames) : $0.name)" } ?? "الشجرة"
                var sub = id == tree.rootId ? "رأس الشجرة" : tree.path(to: id, names: input.branchNames)
                if chunks.count > 1 { sub += " · الجزء \(ci + 1) من \(chunks.count)" }
                blocks.append(.treeChart(AdminReportTreeChart(title: title, subtitle: sub, nodes: nodes)))
                pages += 1
                queue += continued
            }
        }
        if truncated {
            blocks.append(.note("بقية الفروع الأعمق لا تُرسم في هذا الملف — أفرادها في «سجل الأفراد». اختر فرعاً أصغر لرسمه كاملاً.",
                                tone: .muted))
        }
        return blocks
    }

    /// تحت الاسم: «1918 – 1989» للمتوفى، وعدد الفرع لمن له صفحته
    private static func chartCaption(_ p: AdminReportPerson?, count: Int?) -> String? {
        guard let p else { return nil }
        if let count, count > 1 { return AdminReportText.people(count) }
        guard p.deceased else { return nil }
        let b = p.birthHidden ? nil : AdminReportText.year(p.birth)
        let d = AdminReportText.year(p.death)
        switch (b, d) {
        case let (b?, d?): return "\(b) – \(d)"
        case let (nil, d?): return "ت \(d)"
        default: return nil
        }
    }

    // MARK: كتاب الفرع / تقرير فرع شامل

    static func book(_ tree: AdminReportTree, _ input: AdminReportInput, _ r: AdminReportRequest,
                     sections: Set<AdminReportBookSection>) -> AdminReportDoc {
        let filter = r.filter
        var parts: [String] = []
        let root = filter.branch ?? tree.rootId
        let pool = scoped(tree, input, filter, tree.pool, parts: &parts)
        let ids = Set(pool.map(\.id))
        let ages = ages(pool, input)
        let reg = input.registered
        var blocks: [AdminReportBlock] = []
        var contents: [String] = []

        if sections.contains(.numbers) {
            contents.append("الأعداد")
            let alive = pool.filter { !$0.deceased }
            let regCount = reg.map { set in alive.filter { set.contains($0.id) }.count }
            blocks.append(.section(AdminReportBookSection.numbers.pdfTitle, subtitle: parts.joined(separator: " · ")))
            blocks.append(.tiles([AdminReportTile(value: AdminReportText.num(pool.count), label: "الأفراد"),
                                  AdminReportTile(value: AdminReportText.num(alive.count), label: "أحياء"),
                                  AdminReportTile(value: AdminReportText.num(pool.count - alive.count), label: "متوفون"),
                                  AdminReportTile(value: regCount.map(AdminReportText.num) ?? "—", label: "مسجّلون")]))
            blocks.append(.rings([AdminReportRing(title: "الأفراد", living: alive.count, deceased: pool.count - alive.count,
                                                  tone: .total)]))
            if let regCount {
                blocks.append(.heading("التسجيل في التطبيق", subtitle: "الأحياء في هذا الفرع", panel: true))
                blocks.append(.split(AdminReportSplit(firstLabel: AdminReportText.registered, first: regCount,
                                                      secondLabel: AdminReportText.treeOnly, second: alive.count - regCount)))
            }
        }

        if sections.contains(.tree), let root, tree.byId[root] != nil {
            contents.append("شجرة الفرع")
            blocks.append(.section(AdminReportBookSection.tree.pdfTitle, subtitle: "الفرع مرسوماً — ومفتاح القراءة أسفل كل صفحة"))
            blocks += chartBlocks(tree, input, root: root)
        }

        let households = tree.sections(pool, plan: r.plan, names: input.branchNames)

        if sections.contains(.register) {
            contents.append("سجل الأفراد")
            blocks.append(.section(AdminReportBookSection.register.pdfTitle,
                                   subtitle: "\(r.plan.grouping.pdfLabel) — \(AdminReportText.people(pool.count))"))
            // الكتاب بلا هواتف أبداً
            let fields = (r.fields.isEmpty ? [.name, .birth, .age, .status] : r.fields).filter { $0 != .phone }
            let ctx = CellContext(tree: tree, input: input, ages: ages, fields: fields)
            let shown = fields.contains(.registration)
            var sub = memberSections(pool, ctx: ctx, plan: r.plan) { shown ? registrationSummary($0, reg) : lifeSummary($0) }
            // داخل الكتاب: الفهرس بالأقسام لا بالبيوت
            sub = sub.map { b in
                if case let .band(t, s, _) = b { return .band(t, subtitle: s, toc: false) }
                return b
            }
            blocks += sub
        }

        if sections.contains(.memorial) {
            contents.append("الراحلون وذكراهم")
            let m = memorial(tree, input, AdminReportFilter(), [.name, .death, .anniversary, .ageAtDeath], within: ids)
            blocks.append(.section(AdminReportBookSection.memorial.pdfTitle, subtitle: AdminReportText.people(m.count)))
            blocks += m.blocks.dropFirst()   // بلا مربّعات الأرقام المكرّرة
        }

        if sections.contains(.form) {
            contents.append("استمارة استكمال البيانات")
            blocks.append(.section(AdminReportBookSection.form.pdfTitle,
                                   subtitle: "بيت لكل صفحة — تُوزَّع في الديوانية وتعود معبّأة للإدارة"))
            for (i, h) in households.enumerated() {
                if i > 0 { blocks.append(.pageBreak) }
                blocks += formPage(h, tree: tree)
            }
        }

        if sections.contains(.attendance) {
            contents.append("قائمة الحضور")
            let living = pool.filter { !$0.deceased }
            blocks.append(.section(AdminReportBookSection.attendance.pdfTitle,
                                   subtitle: "الأحياء بالبيوت — بلا هواتف · \(AdminReportText.people(living.count))"))
            blocks.append(.signatures(["المناسبة", "التاريخ", "المكان"]))
            let livingIds = Set(living.map(\.id))
            var seq = 0
            for h in households {
                let list = h.members.filter { livingIds.contains($0.id) }
                guard !list.isEmpty else { continue }
                blocks.append(.band(h.title, subtitle: AdminReportText.people(list.count), toc: false))
                var table = AdminReportTable(columns: [
                    .init(title: "م", centered: true),
                    .init(title: "الاسم الكامل", wraps: true, fill: true),
                    .init(title: "حضر", centered: true, minWidth: 34),
                    .init(title: "ملاحظة", minWidth: 150)
                ], rows: [], roomy: true)
                for p in list {
                    seq += 1
                    table.rows.append(.init(cells: ["\(seq)", p.name, "", ""], tones: [2: .checkbox, 3: .blank]))
                }
                table.summary = "الحضور: ........ من \(AdminReportText.people(list.count))"
                blocks.append(.table(table))
            }
        }

        if sections.contains(.cards) {
            contents.append("بطاقات الأفراد")
            blocks.append(.section(AdminReportBookSection.cards.pdfTitle, subtitle: "بطاقة لكل فرد بترتيب الشجرة"))
            let ordered = pool.sorted { (tree.order[$0.id] ?? Int.max) < (tree.order[$1.id] ?? Int.max) }
            var row: [AdminReportCard] = []
            for p in ordered {
                row.append(card(p, tree: tree, input: input))
                if row.count == AdminReportPDF.cardsPerRow {
                    blocks.append(.cardRow(row))
                    row = []
                }
            }
            if !row.isEmpty { blocks.append(.cardRow(row)) }
        }

        if blocks.isEmpty { blocks.append(.note("اختر قسماً واحداً على الأقل.", tone: .muted)) }
        let list = contents.enumerated().map { $0.offset == 0 ? $0.element : "و" + $0.element }.joined(separator: "، ")
        let intro = list.isEmpty ? "" : "يضمّ هذا الكتاب: \(list). الهواتف لا تدخله — مكانها «دليل الهواتف» وحده."
        let rootTitle = root.flatMap { id in tree.byId[id].map { id == tree.rootId ? "العائلة كاملة" : tree.title(ofHead: $0, names: input.branchNames) } }
        var doc = AdminReportDoc(kind: r.kind, scope: parts.joined(separator: " · "), count: pool.count, intro: intro,
                                 blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.cover = sections.contains(.cover)
        doc.grouping = r.plan.grouping.pdfLabel
        if r.kind == .book, let rootTitle { doc.customTitle = "كتاب \(rootTitle)" }
        return doc
    }

    /// صفحة استمارة لبيت: طريقة التعبئة، جدول البيت بخانات منقّطة لما ينقص، وأبناء غير مقيّدين، وخطوط التوقيع
    private static func formPage(_ h: AdminReportTree.Section, tree: AdminReportTree) -> [AdminReportBlock] {
        var blocks: [AdminReportBlock] = [
            .band("استمارة: \(h.title)", subtitle: AdminReportText.people(h.members.count), toc: false),
            .note("طريقة التعبئة: الخانات المنقّطة ناقصة في الشجرة. اكتبها بخط واضح، وضع ✓ إن كان المطبوع صحيحاً،"
                  + " ثم سلّم الورقة للإدارة. ما يُكتب هنا يُدخَل بعد مراجعته.", tone: .warning)
        ]
        var table = AdminReportTable(columns: [
            .init(title: "✓", centered: true, minWidth: 22),
            .init(title: "الاسم كما في الشجرة", wraps: true, fill: true),
            .init(title: "تاريخ الميلاد", minWidth: 110),
            .init(title: "الحالة", minWidth: 44),
            .init(title: "تاريخ الوفاة", minWidth: 110)
        ], rows: [], roomy: true)
        for p in h.members {
            var row = AdminReportRowBuilder()
            row.add("", .checkbox)
            row.add(p.name)
            switch (p.birthHidden, DeceasedMemorial.classify(p.birth)) {
            case (true, _): row.add(AdminReportText.hidden, .muted)
            case let (false, .exact(y, m, d)): row.add("\(DeceasedMemorial.dayMonth(day: d, month: m, arabic: true)) \(y)")
            case let (false, .yearOnly(y)): row.add("\(y) · اليوم/الشهر:", .blank)
            default: row.add("", .blank)
            }
            row.add(p.deceased ? "متوفى" : "حي", p.deceased ? .muted : nil)
            if !p.deceased {
                row.add("—")
            } else if p.deathUnknown {
                row.add("غير معروف", .muted)
            } else {
                switch DeceasedMemorial.classify(p.death) {
                case let .exact(y, m, d): row.add("\(DeceasedMemorial.dayMonth(day: d, month: m, arabic: true)) \(y)")
                case let .yearOnly(y): row.add("\(y) · اليوم/الشهر:", .blank)
                default: row.add("", .blank)
                }
            }
            table.rows.append(row.row)
        }
        blocks.append(.table(table))
        blocks.append(.heading("أبناء غير مقيّدين في الشجرة؟", subtitle: nil, panel: true))
        var extra = AdminReportTable(columns: [
            .init(title: "الاسم الثلاثي", fill: true),
            .init(title: "ابن من؟", minWidth: 110),
            .init(title: "تاريخ الميلاد", minWidth: 90),
            .init(title: "الحالة", minWidth: 60)
        ], rows: [], roomy: true)
        for _ in 0..<3 {
            extra.rows.append(.init(cells: ["", "", "", ""], tones: [0: .blank, 1: .blank, 2: .blank, 3: .blank]))
        }
        blocks.append(.table(extra))
        blocks.append(.signatures(["اسم من عبّأها", "التاريخ", "استلمها (الإدارة)"]))
        blocks.append(.caption("رمز الورقة: \(h.title) · \(AdminReportText.people(h.members.count))"))
        return blocks
    }

    private static func card(_ p: AdminReportPerson, tree: AdminReportTree, input: AdminReportInput) -> AdminReportCard {
        var lines: [String] = []
        let birth = p.birthHidden ? AdminReportText.hidden : (AdminReportText.date(p.birth) ?? "—")
        lines.append("الميلاد: \(birth)")
        if p.deceased {
            lines.append("الوفاة: \(p.deathUnknown ? "غير معروف" : AdminReportText.deathDate(p.death))")
        }
        lines.append("الفرع: \(tree.branchLabel(of: p, names: input.branchNames))")
        return AdminReportCard(name: p.name, lineage: p.lineage, lines: lines, deceased: p.deceased)
    }
}
