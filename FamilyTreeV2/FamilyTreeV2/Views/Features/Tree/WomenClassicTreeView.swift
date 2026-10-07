import SwiftUI

/// خطوط أب واحد مع أبنائه (كل المجموعات والصفوف) — تُبنى مرة مع التخطيط لا كل إطار.
private struct WomenConnector {
    var path = Path()
    var dots: [CGPoint] = []   // نقاط تفرّع الأبناء عن الخط الأفقي
}

/// شجرة النساء بالتصميم المحسّن (يطابق الويب):
///  - الأب/العضو في المركز، الزوجات دوائر وردية جنبه (تظهر فقط عند فتح أبنائه).
///  - كل الأبناء تحته، مع فصل الجنسين (الذكور مجموعة، الإناث مجموعة).
///  - دوائر بالكامل: الذكور أزرق (بصورة)، الإناث وردي (بلا صورة). شارة وفاة حمراء.
///  - تكبير باللمس + سحب + توسّع/طيّ.
struct WomenClassicTreeView: View {
    let members: [FamilyMember]
    var onSelect: ((FamilyMember) -> Void)? = nil
    /// تبويب الشجرة [0=عائلة، 1=نساء] — لعرض شريط الأدوات العلوي.
    var treeTab: Binding<Int>? = nil
    /// عقدة المرأة المرتبطة بالمستخدم الحالي — لزر «موقعي».
    var meWomanId: UUID? = nil

    // أبعاد
    private let CIRCLE: CGFloat = 44        // حجم شكل العضو (squircle) — أكبر قليلاً ليقارب مربع الاسم
    private let CORNER: CGFloat = 12        // نعومة الحواف
    private let RING: CGFloat = 1.5         // إطار أخف
    private let PILL_H: CGFloat = 22
    private let BADGE_H: CGFloat = 17
    private let LIFE_H: CGFloat = 13        // سطر سنوات الميلاد–الوفاة للمتوفّى
    private let NODE_W: CGFloat = 62        // أضيق → أقرب
    private var NODE_H: CGFloat { CIRCLE + 4 + PILL_H + LIFE_H + BADGE_H - 6 }
    private let H_GAP: CGFloat = 6          // بين الإخوة جنب بعض (جنس واحد)
    private let V_GAP: CGFloat = 22    // بين الأب وأبنائه — مساحة أوسع عند التوسع (طلب المالك)
    private let ROW_GAP: CGFloat = 3        // بين الأبناء المكدّسين عموديًا
    private let WRAP_GAP: CGFloat = 16      // بين صفوف الإخوة الملتفّة — يتّسع لخط الصف فوقه
    private let SPINE_ROOM: CGFloat = 10    // مساحة العمود على جانبي المجموعة الملتفّة (يبقى التمركز)
    private let SPINE_OUT: CGFloat = 6      // بُعد العمود عن حافة أبعد ابن
    private let LINE_CORNER: CGFloat = 6    // استدارة زوايا الخطوط
    private let MAX_PER_ROW = 3             // صفوف أفقية عند وجود جنس واحد فقط
    private let PAD: CGFloat = 32
    /// بين كتلة الذكور وكتلة الإناث — خفيفة عمودياً، وأوسع في الوضع الأفقي
    /// ليتميّز الجنسان مع اتساع الشاشة (طلب المالك)
    private var GENDER_GAP: CGFloat { viewport.width > viewport.height ? 30 : 12 }

    private let rose = DS.Color.female

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var artScheme

    @State private var collapsed: Set<UUID> = []
    @State private var initedRoot: UUID? = nil
    @State private var fittedRoot: UUID? = nil
    @State private var userInteracted = false

    @State private var scale: CGFloat = 0.8
    @State private var baseScale: CGFloat = 0.8
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var viewport: CGSize = .zero
    @State private var pendingExpandScroll: UUID? = nil   // عقدة توسّعت لتوّها → ننزل لأبنائها
    @State private var pendingCollapseScroll: UUID? = nil // عقدة طُويت → ننزل لأبيها ليظهر الإخوة

    // كاش يُعاد حسابه فقط عند تغيّر الطيّ/البيانات — لا يُحسب أثناء السحب (سلاسة).
    @State private var layout = Layout()
    @State private var cChildrenOf: [UUID: [FamilyMember]] = [:]
    @State private var cWives: [UUID: [FamilyMember]] = [:]
    /// آخر عقدة توسّعت — أبناؤها يدخلون بتدرّج
    @State private var lastExpandedId: UUID? = nil

    // ─── بيانات الشجرة ───
    private var byId: [UUID: FamilyMember] {
        Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private func isWife(_ m: FamilyMember) -> Bool {
        m.husbandId != nil && m.isFemale
    }
    private var wivesByHusband: [UUID: [FamilyMember]] {
        var map: [UUID: [FamilyMember]] = [:]
        for m in members where isWife(m) {
            map[m.husbandId!, default: []].append(m)
        }
        for k in map.keys { map[k]?.sort { $0.sortOrder < $1.sortOrder } }
        return map
    }
    private var childrenOf: [UUID: [FamilyMember]] {
        var map: [UUID: [FamilyMember]] = [:]
        let ids = Set(members.map(\.id))
        // البنت المتزوّجة تظهر تحت أبيها **و** ككبسولة زوجة جنب زوجها معاً —
        // سابقاً كانت تُستثنى من الأبناء كلياً فتختفي من فرع أبيها (طلب المالك).
        // أما الزوجة الوافدة (بلا أب في الشجرة) فتبقى ككبسولة زوجة فقط.
        for m in members {
            if let fid = m.fatherId, ids.contains(fid) {
                map[fid, default: []].append(m)
            } else if !isWife(m) {
                map[Self.rootKey, default: []].append(m)
            }
        }
        for k in map.keys {
            map[k]?.sort {
                ($0.sortOrder) != ($1.sortOrder) ? $0.sortOrder < $1.sortOrder
                : ($0.firstName).localizedCompare($1.firstName) == .orderedAscending
            }
        }
        return map
    }
    private static let rootKey = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var roots: [FamilyMember] { childrenOf[Self.rootKey] ?? [] }
    private var activeRoot: UUID? { roots.first?.id }

    // ─── التخطيط (measure/place مع فصل الجنسين) ───
    private struct Layout {
        var positions: [UUID: CGPoint] = [:]
        var depth: [UUID: Int] = [:]
        /// أبناء كل أب: مجموعات (الذكور/الإناث) → صفوف → معرّفات — لرسم الخطوط
        var childGroups: [UUID: [[[UUID]]]] = [:]
        var connectors: [WomenConnector] = []
        var heights: [UUID: CGFloat] = [:]   // ارتفاع صندوق كل عقدة (متغيّر)
        var size: CGSize = .zero
    }

    /// ارتفاع صندوق العقدة — يطابق الارتفاع الفعلي بدقّة (لمحاذاة الأسماء بين الأعمدة).
    private func nodeBoxHeight(deceased: Bool, hasKids: Bool) -> CGFloat {
        // شريحة السهم أُزيلت — العدّاد صار شارة فوق الصورة، فلا ارتفاع إضافي للأبناء
        var h = CIRCLE + 2 + PILL_H
        if deceased { h += 2 + LIFE_H }
        return h
    }

    /// الأبناء الظاهرون تحت عقدة. عند فتح أحد الأبناء (وله أبناء) نُخفي
    /// إخوته وأخواته للتركيز على المتفرّع فقط — مثل التفرّع في شجرة العائلة.
    private func visibleChildren(_ id: UUID, _ cOf: [UUID: [FamilyMember]]) -> [FamilyMember] {
        if collapsed.contains(id) { return [] }
        let all = cOf[id] ?? []
        // عند فتح أحد الأبناء (وله أبناء) نُخفي بقية الإخوة والأخوات
        // للتركيز على الفرع المتفرّع فقط (السلوك الأصلي — طلب المالك)
        let expanded = all.filter { !collapsed.contains($0.id) && !(cOf[$0.id]?.isEmpty ?? true) }
        return expanded.isEmpty ? all : expanded
    }

    private func computeLayout() -> Layout {
        var L = Layout()
        guard let root = activeRoot else { return L }
        let cOf = childrenOf
        var sizeCache: [UUID: CGSize] = [:]
        var seen = Set<UUID>()

        // ── منطق التوزيعة ──
        // أفقي (لفّ): ٣ كحدّ أقصى في الصف الواحد للذكور (مثلاً ٤ → ٣+١ · ٥ → ٣+٢).
        // الوضع الأفقي: عدد الإخوة في الصف يُحسب تلقائياً من عرض الشاشة
        // (كل عقدة NODE_W + الفجوة) فيتوسّعون جنب بعض بدل التكديس — طلب المالك
        // أفقياً: صف واحد حتى ١٠، وإذا كثروا فسطران متساويان (طلب المالك)
        let landscapeWide = viewport.width > viewport.height
        func splitRow(_ n: Int) -> Int {
            guard landscapeWide else { return min(MAX_PER_ROW, max(1, n)) }
            return n <= 10 ? max(1, n) : Int(ceil(Double(n) / 2.0))
        }
        let maxPerRow: Int = landscapeWide ? 99 : MAX_PER_ROW
        func perRowH(_ n: Int) -> Int { splitRow(n) }
        // عمودي (أعمدة جنسية): عمود واحد حتى ٤ · خمسة → عمودان والأخير تحتهم (٢+٢+١
        // — طلب المالك) · أكثر → ~٤ لكل عمود فرعي.
        /// عمودان لكل مجموعة جنس — والفرد الأخير يتوسّط عمودَيه لأن
        /// placeBlock يوسّط كل صف على مركز المجموعة.
        func perRowV(_ n: Int) -> Int { min(2, max(1, n)) }
        let stackGap: CGFloat = 10   // فجوة بين صفّ الذكور وصفّ الإناث (وضع مكدّس)
        // ذكر+أنثى بصف واحد: نفس مسافة الإخوة عمودياً، وأوسع أفقياً (طلب المالك)
        let pairGap: CGFloat = viewport.width > viewport.height ? 22 : H_GAP
        // الترتيب: جنس واحد → أفقي (٣/صف) · ذكر+أنثى فقط → جنب بعض · أقلية واحدة → مكدّس · كلاهما ≥٢ → عمودان.
        enum Arrange { case single, stacked, sideBySide, pair }
        func arrange(_ mCount: Int, _ fCount: Int) -> Arrange {
            if mCount == 0 || fCount == 0 { return .single }
            // وجود الجنسين ⇒ مجموعتان متجاورتان دائماً: الذكور بجهة والإناث
            // بجهة، كل مجموعة على عمودين (طلب المالك). لا تكديس ولا صف مختلط.
            return .sideBySide
        }

        // فجوة الصفوف: أي كتلة إخوة تلتف لأكثر من سطر (ذكوراً أو إناثاً)
        // تأخذ مسافة أوسع بين سطورها (طلب المالك)
        func rowGapFor(_ list: [FamilyMember], _ per: Int) -> CGFloat {
            list.count > per ? WRAP_GAP : ROW_GAP
        }
        func blockDims(_ boxes: [CGSize], _ per: Int, _ gap: CGFloat) -> CGSize {
            var w: CGFloat = 0, h: CGFloat = 0
            var i = 0
            while i < boxes.count {
                let row = Array(boxes[i..<min(i + per, boxes.count)])
                let rowW = row.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(row.count - 1)
                let rowH = row.map(\.height).max() ?? 0
                w = max(w, rowW); h += (i > 0 ? gap : 0) + rowH
                i += per
            }
            // مجموعة ملتفّة: مساحة العمود على الجانبين (بالتساوي فيبقى التمركز)
            if boxes.count > per { w += SPINE_ROOM * 2 }
            return CGSize(width: w, height: h)
        }
        // ارتفاع صندوق العقدة نفسها (بلا الأبناء) — متغيّر.
        func boxH(_ id: UUID) -> CGFloat {
            nodeBoxHeight(deceased: byId[id]?.isDeceased == true,
                          hasKids: !(cOf[id]?.isEmpty ?? true))
        }
        func measureBlock(_ list: [FamilyMember], _ per: Int) -> CGSize {
            list.isEmpty ? .zero : blockDims(list.map { measure($0.id) }, per, rowGapFor(list, per))
        }
        func cachedBlock(_ list: [FamilyMember], _ per: Int) -> CGSize {
            list.isEmpty ? .zero : blockDims(list.map { sizeCache[$0.id] ?? CGSize(width: NODE_W, height: boxH($0.id)) }, per, rowGapFor(list, per))
        }
        func measure(_ id: UUID) -> CGSize {
            let bh = boxH(id)
            L.heights[id] = bh
            if seen.contains(id) { return CGSize(width: NODE_W, height: bh) }
            seen.insert(id)
            let kids = visibleChildren(id, cOf)
            if kids.isEmpty { let b = CGSize(width: NODE_W, height: bh); sizeCache[id] = b; return b }
            let males = kids.filter { !$0.isFemale }
            let females = kids.filter { $0.isFemale }
            let childBlock: CGSize
            switch arrange(males.count, females.count) {
            case .single:
                let list = males.isEmpty ? females : males
                childBlock = measureBlock(list, perRowH(list.count))
            case .stacked:
                let mB = measureBlock(males, perRowH(males.count))
                let fB = measureBlock(females, perRowH(females.count))
                childBlock = CGSize(width: max(mB.width, fB.width), height: mB.height + stackGap + fB.height)
            case .sideBySide:
                let mB = measureBlock(males, perRowV(males.count))
                let fB = measureBlock(females, perRowV(females.count))
                childBlock = CGSize(width: mB.width + GENDER_GAP + fB.width, height: max(mB.height, fB.height))
            case .pair:
                let mB = measureBlock(males, max(1, males.count))
                let fB = measureBlock(females, max(1, females.count))
                childBlock = CGSize(width: mB.width + pairGap + fB.width, height: max(mB.height, fB.height))
            }
            let b = CGSize(width: max(NODE_W, childBlock.width), height: bh + V_GAP + childBlock.height)
            sizeCache[id] = b
            return b
        }

        var placed = Set<UUID>()
        @discardableResult
        func placeBlock(_ pid: UUID, _ list: [FamilyMember], _ cx: CGFloat, _ top: CGFloat, _ d: Int, _ per: Int) -> [[UUID]] {
            var rows: [[UUID]] = []
            var rowTop = top
            let gap = rowGapFor(list, per)
            var i = 0
            while i < list.count {
                let rowKids = Array(list[i..<min(i + per, list.count)])
                let rowBoxes = rowKids.map { sizeCache[$0.id] ?? CGSize(width: NODE_W, height: boxH($0.id)) }
                let rowW = rowBoxes.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(rowBoxes.count - 1)
                let rowH = rowBoxes.map(\.height).max() ?? 0
                var x = cx - rowW / 2
                for (j, k) in rowKids.enumerated() {
                    place(k.id, x + rowBoxes[j].width / 2, rowTop, d)
                    x += rowBoxes[j].width + H_GAP
                }
                rows.append(rowKids.map(\.id))
                rowTop += rowH + gap
                i += per
            }
            return rows
        }
        func place(_ id: UUID, _ cx: CGFloat, _ top: CGFloat, _ d: Int) {
            if placed.contains(id) { return }
            placed.insert(id)
            L.positions[id] = CGPoint(x: cx - NODE_W / 2, y: top)
            L.depth[id] = d
            L.heights[id] = boxH(id)
            let kids = visibleChildren(id, cOf)
            if kids.isEmpty { return }
            let rowTop = top + boxH(id) + V_GAP
            let males = kids.filter { !$0.isFemale }
            let females = kids.filter { $0.isFemale }
            var groups: [[[UUID]]] = []
            switch arrange(males.count, females.count) {
            case .single:
                let list = males.isEmpty ? females : males
                groups.append(placeBlock(id, list, cx, rowTop, d + 1, perRowH(list.count)))
            case .stacked:
                // الأكبر أفقيًا فوق، والأقلية أفقيًا تحته — متمركزين.
                let mB = cachedBlock(males, perRowH(males.count))
                groups.append(placeBlock(id, males, cx, rowTop, d + 1, perRowH(males.count)))
                groups.append(placeBlock(id, females, cx, rowTop + mB.height + stackGap, d + 1, perRowH(females.count)))
            case .sideBySide:
                let pm = perRowV(males.count), pf = perRowV(females.count)
                let mW = cachedBlock(males, pm).width, fW = cachedBlock(females, pf).width
                let totalW = mW + GENDER_GAP + fW
                var bx = cx - totalW / 2
                groups.append(placeBlock(id, males, bx + mW / 2, rowTop, d + 1, pm)); bx += mW + GENDER_GAP
                groups.append(placeBlock(id, females, bx + fW / 2, rowTop, d + 1, pf))
            case .pair:
                let pm = max(1, males.count), pf = max(1, females.count)
                let mW = cachedBlock(males, pm).width, fW = cachedBlock(females, pf).width
                let totalW = mW + pairGap + fW
                var bx = cx - totalW / 2
                groups.append(placeBlock(id, males, bx + mW / 2, rowTop, d + 1, pm)); bx += mW + pairGap
                groups.append(placeBlock(id, females, bx + fW / 2, rowTop, d + 1, pf))
            }
            L.childGroups[id] = groups.filter { !$0.isEmpty }
        }

        let rootBox = measure(root)
        place(root, PAD + rootBox.width / 2, PAD, 0)
        let width = rootBox.width + PAD * 2
        let height = rootBox.height + PAD * 2
        // الـ canvas مثبّت LTR (لسحب صحيح)، فنقلب الإحداثيات رياضيًا:
        // الذكور يمين · الإناث يسار — مطابق للمعتمد سابقًا.
        for (id, p) in L.positions { L.positions[id] = CGPoint(x: width - p.x - NODE_W, y: p.y) }
        L.size = CGSize(width: width, height: height)
        L.connectors = buildConnectors(L)
        return L
    }

    /// خطوط كل أب مع أبنائه بعد المرآة (الذكور يمين · الإناث يسار) — اختيار المالك ٢٠٢٦-١٠-٠٤:
    ///  • صف واحد بثلاثة أبناء أو أقل: أقواس من أسفل الأب إلى كل ابن/بنت.
    ///  • غير ذلك: خط أفقي في منتصف الفجوة يمرّ على الصف الأول، وكل مجموعة ملتفّة صفوفها
    ///    لها عمود على جهتها الخارجية (مجموعة واحدة: جهة الأكبر) يصل خطوط صفوفها بالخط الأول.
    private func buildConnectors(_ L: Layout) -> [WomenConnector] {
        typealias Kid = (id: UUID, x: CGFloat, top: CGFloat)
        let r = LINE_CORNER
        var out: [WomenConnector] = []
        for (pid, groupIds) in L.childGroups {
            guard let pp = L.positions[pid] else { continue }
            let fx = pp.x + NODE_W / 2
            let fy = pp.y + (L.heights[pid] ?? NODE_H) - 2
            let groups: [[[Kid]]] = groupIds.map { g in
                g.map { row in
                    row.compactMap { id in L.positions[id].map { (id: id, x: $0.x + NODE_W / 2, top: $0.y + 3) } }
                        .sorted { $0.x < $1.x }
                }.filter { !$0.isEmpty }
            }.filter { !$0.isEmpty }
            guard !groups.isEmpty else { continue }
            var c = WomenConnector()
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
            func drop(_ k: Kid, _ y: CGFloat) {
                c.path.move(to: p(k.x, y)); c.path.addLine(to: p(k.x, k.top)); c.dots.append(p(k.x, y))
            }
            func land(_ k: Kid, _ y: CGFloat) {
                c.path.addArc(tangent1End: p(k.x, y), tangent2End: p(k.x, k.top), radius: r)
                c.path.addLine(to: p(k.x, k.top))
            }
            let firstRow = groups.flatMap { $0[0] }.sorted { $0.x < $1.x }
            let total = groups.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
            // عائلة صغيرة: أقواس (نقاط تحكم بعيدة ٨٠٪)
            if !groups.contains(where: { $0.count > 1 }), total <= 3 {
                for k in firstRow {
                    let dy = k.top - fy
                    c.path.move(to: p(fx, fy))
                    c.path.addCurve(to: p(k.x, k.top), control1: p(fx, fy + dy * 0.8), control2: p(k.x, k.top - dy * 0.8))
                }
                out.append(c); continue
            }
            let bus0 = (fy + (firstRow.map(\.top).min() ?? fy) - 3) / 2
            /// عمود مجموعة ملتفّة: جهته، موضعه، وخط كل صف من صفوفها
            struct Spine { let right: Bool; let x: CGFloat; let rows: [[Kid]]; let bus: [CGFloat] }
            var spines: [Spine] = []
            for g in groups where g.count > 1 {
                let xs = g.flatMap { $0.map(\.x) }
                let center = ((xs.min() ?? fx) + (xs.max() ?? fx)) / 2
                let right = groups.count == 1 || center >= fx
                let x = right ? (xs.max() ?? fx) + NODE_W / 2 + SPINE_OUT : (xs.min() ?? fx) - NODE_W / 2 - SPINE_OUT
                let bus = g.enumerated().map { i, row in i == 0 ? bus0 : (row.map(\.top).min() ?? fy) - 3 - WRAP_GAP / 2 }
                spines.append(Spine(right: right, x: x, rows: g, bus: bus))
            }
            let leftSpine = spines.first { !$0.right }, rightSpine = spines.first { $0.right }
            /// الابن الأبعد عن العمود في صفّ: إليه ينتهي خط الصف بانعطافة
            func far(_ row: [Kid], _ s: Spine) -> Kid { s.right ? row.first! : row.last! }
            let rightEndX = rightSpine?.x ?? firstRow.last!.x

            // نزول الأب إلى الخط الأول
            c.path.move(to: p(fx, fy)); c.path.addLine(to: p(fx, bus0))
            // الطرف الأيسر: ابن ينعطف إليه الخط، أو عمود المجموعة اليسرى من آخر صفوفها
            if let s = leftSpine {
                let lastRow = s.rows[s.rows.count - 1], lb = s.bus[s.bus.count - 1], fk = far(lastRow, s)
                c.path.move(to: p(fk.x, fk.top))
                c.path.addArc(tangent1End: p(fk.x, lb), tangent2End: p(s.x, lb), radius: r)
                c.path.addArc(tangent1End: p(s.x, lb), tangent2End: p(s.x, bus0), radius: r)
                c.path.addArc(tangent1End: p(s.x, bus0), tangent2End: p(rightEndX, bus0), radius: r)
            } else {
                let k = firstRow.first!
                c.path.move(to: p(k.x, k.top))
                c.path.addArc(tangent1End: p(k.x, bus0), tangent2End: p(rightEndX, bus0), radius: r)
            }
            // الطرف الأيمن: ابن ينعطف الخط إليه، أو عمود المجموعة اليمنى حتى آخر صفوفها
            if let s = rightSpine {
                let lastRow = s.rows[s.rows.count - 1], lb = s.bus[s.bus.count - 1], fk = far(lastRow, s)
                c.path.addArc(tangent1End: p(s.x, bus0), tangent2End: p(s.x, lb), radius: r)
                c.path.addArc(tangent1End: p(s.x, lb), tangent2End: p(fk.x, lb), radius: r)
                land(fk, lb)
            } else {
                land(firstRow.last!, bus0)
            }
            // الصف الأول: نزول لكل ابن لم ينعطف إليه الخط
            let leftEndId = leftSpine == nil ? firstRow.first!.id : nil
            let rightEndId = rightSpine == nil ? firstRow.last!.id : nil
            for k in firstRow where k.id != leftEndId && k.id != rightEndId { drop(k, bus0) }
            // صفوف كل مجموعة ملتفّة بعد الأول: الأوسط يتفرّع من العمود، وكل صف ينعطف لأبعد ابن
            for s in spines {
                let lastIdx = s.rows.count - 1
                for i in 1...lastIdx {
                    let fk = far(s.rows[i], s)
                    if i < lastIdx {
                        c.path.move(to: p(s.x, s.bus[i]))
                        land(fk, s.bus[i])
                    }
                    for k in s.rows[i] where k.id != fk.id { drop(k, s.bus[i]) }
                }
            }
            out.append(c)
        }
        return out
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── منطقة الشجرة (تمر تحت البار العائم — مثل شجرة العائلة) ──
            GeometryReader { geo in
                // حاوية بحجم الشاشة + الكانفس كـ overlay — يمنع انزياح الشجرة
                // عندما يكون الكانفس أعرض من الشاشة (الحاوية لا تتمدد لحجمه).
                DS.Color.background
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            // خطوط الأب وأبنائه — كل الصفوف موصولة (اختيار المالك ٢٠٢٦-١٠-٠٤، مثل
                            // شجرة العائلة: أقواس للعائلة الصغيرة، و«العمود» للمجموعات الملتفّة)
                            // طبقات الخط ونقطة التفرّع بأسلوب «مجسّمات»
                            let lineLayers = TreeArtLines.layers(width: 1.5, dark: artScheme == .dark)
                            let lineDark = artScheme == .dark
                            Canvas { ctx, _ in
                                for c in layout.connectors {
                                    TreeArtLines.stroke(&ctx, c.path, lineLayers)
                                    for d in c.dots {
                                        TreeArtLines.dot(&ctx, at: d, r: 2, dark: lineDark)
                                    }
                                }
                            }
                            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            // العُقد
                            ForEach(members.filter { layout.positions[$0.id] != nil }, id: \.id) { m in
                                nodeView(m, at: layout.positions[m.id]!)
                            }
                        }
                        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(offset)
                    }
                // الـ canvas مثبّت LTR — يمنع انعكاس اتجاه السحب في بيئة RTL.
                .environment(\.layoutDirection, .leftToRight)
                .contentShape(Rectangle())
                .clipped()                                   // الحركة لا تتجاوز حدود الصندوق
                .gesture(dragGesture)
                .modifier(PinchZoomModifier(scale: $scale, baseScale: $baseScale,
                                            offset: $offset, baseOffset: $baseOffset,
                                            userInteracted: $userInteracted, clamp: clampOffset))
                .onAppear {
                    viewport = geo.size
                    initIfNeeded()
                    let L = rebuild()
                    fit(in: geo.size, layout: L)
                }
                .onChange(of: geo.size) { newSize in
                    // تدوير الشاشة: أعد ضبط موضع الشجرة للاتجاه الجديد (طلب المالك)
                    let orientationFlipped = (viewport.width > viewport.height) != (newSize.width > newSize.height)
                    viewport = newSize
                    if orientationFlipped {
                        // تدوير: أعد البناء ثم مركّز العقدة الحالية بالمنتصف تلقائياً
                        withAnimation(DS.Anim.smooth) {
                            let L = rebuild()
                            fit(in: newSize, layout: L)
                            if let r = activeRoot { centerOn(r, in: L) }
                        }
                    }
                }
                .onChange(of: members.count) { _ in
                    initedRoot = nil
                    initIfNeeded()
                    let L = rebuild()
                    if !userInteracted { fit(in: geo.size, layout: L) }
                }
                .onChange(of: collapsed) { _ in
                    // كل تغيّر التخطيط داخل الـ transaction — العقد والخطوط تتحرك بسلاسة
                    withAnimation(DS.Anim.snappy) {
                        let L = rebuild()
                        if let exp = pendingExpandScroll, L.positions[exp] != nil {
                            pendingExpandScroll = nil
                            scrollNodeToTop(exp, in: L)      // ينزل ليُظهر الأبناء والأب فوقهم
                        } else if let col = pendingCollapseScroll {
                            pendingCollapseScroll = nil
                            // طي: تمركز على أب العقدة المطوية — تنزل الشجرة ويظهر كل الإخوة
                            if L.positions[col] != nil { scrollNodeToTop(col, in: L) }
                        } else if !userInteracted {
                            fit(in: geo.size, layout: L)
                        }
                    }
                }
            }

            // ── شريط الأدوات يطفو فوق الشجرة (شفافيته تبان لما تمر العقد تحته) ──
            // الوضع الأفقي: البار يصير جانبياً عمودياً (طلب المالك)
            if verticalSizeClass == .compact {
                landscapeSideToolbar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, DS.Spacing.sm)
                    .zIndex(101)
            } else {
                toolbarRow
                    .zIndex(101)
            }
        }
    }

    /// إعادة بناء الكاش (البيانات + التخطيط) — تُستدعى فقط عند تغيّر الطيّ/البيانات.
    @discardableResult
    private func rebuild() -> Layout {
        cChildrenOf = childrenOf
        cWives = wivesByHusband
        let L = computeLayout()
        layout = L
        return L
    }

    // ─── شريط الأدوات العلوي — نفس بطاقة شجرة العائلة المدمّجة (`treeToolbarCard`) ───
    private var toolbarRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            // البداية — رجوع للجذر + إعادة الملاءمة (بحركة واضحة)
            homeButton(.toolbar)

            Spacer(minLength: 0)

            // التبويب [شجرة العائلة / النساء] — بعرض نصّه في الوسط
            if let treeTab {
                FamilyTreeTabBar(selection: treeTab)
            }

            Spacer(minLength: 0)

            // موقعي — يوسّع مسار العضو ويتمركز عليه (وإلا على الجذر)
            locateButton(.toolbar)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs)
        // زجاج + لمسة الطين + إطار شعري + ظلّ خفيف — نفس بار شجرة العائلة
        .treeToolbarCard()
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }

    /// بار جانبي عمودي للوضع الأفقي — نفس أدوات البار العلوي (طلب المالك)
    private var landscapeSideToolbar: some View {
        VStack(spacing: DS.Spacing.xs) {
            homeButton(.mini)

            if let treeTab {
                FamilyTreeSideTabs(selection: treeTab)
            }

            locateButton(.mini)
        }
        .padding(DS.Spacing.xs)
        .treeToolbarCard()
    }

    /// «البداية» — زرّ العُدّة الدائري (نفس زرّ شجرة العائلة: ٣٤ في الشريط العلوي، ٢٧ في الجانبي، برمز بحبر الشجرة)
    private func homeButton(_ size: DSNavButtonSize) -> some View {
        DSHeaderButton(symbol: "house.fill", label: L10n.t("البداية", "Start"), context: .surface,
                       size: size, tint: AppSection.tree.ink) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            goHome()
        }
    }

    /// «موقعي» — زرّ العُدّة الدائري
    private func locateButton(_ size: DSNavButtonSize) -> some View {
        DSHeaderButton(symbol: "location.fill", label: L10n.t("موقعي", "Me"), context: .surface,
                       size: size, tint: AppSection.tree.ink) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let mid = meWomanId {
                locate(mid)
            } else if let root = activeRoot {
                centerOn(root, in: layout)
            }
        }
    }

    /// تمركز على عقدة معيّنة داخل الشاشة (باستخدام تخطيط محدّد).
    private func centerOn(_ id: UUID, in L: Layout) {
        guard let p = L.positions[id], viewport.width > 0 else { return }
        userInteracted = true
        let s = baseScale
        let h = L.heights[id] ?? NODE_H
        let cx = (p.x + NODE_W / 2) * s
        let cy = (p.y + h / 2) * s
        withAnimation(DS.Anim.smooth) {
            offset = CGSize(width: viewport.width / 2 - cx, height: viewport.height / 2 - cy)
            baseOffset = offset
        }
    }

    /// ينزل ليجعل العقدة (الأب) قرب أعلى الشاشة فتظهر أبناؤه تحته.
    private func scrollNodeToTop(_ id: UUID, in L: Layout) {
        guard let p = L.positions[id], viewport.width > 0 else { return }
        userInteracted = true
        let s = baseScale
        // أفقي: بلا بار علوي — هامش أصغر يعطي مساحة أكبر للأبناء
        let topMargin: CGFloat = viewport.width > viewport.height ? 16 : 70
        let cx = (p.x + NODE_W / 2) * s
        withAnimation(DS.Anim.smooth) {
            offset = clampOffset(CGSize(width: viewport.width / 2 - cx,
                                        height: topMargin - p.y * s))
            baseOffset = offset
        }
    }

    /// «موقعي»: يوسّع مسار الأجداد حتى العضو، ويعرض **النسب كامل من الجذر لين اسمك** معًا.
    private func locate(_ id: UUID) {
        guard byId[id] != nil else { if let r = activeRoot { centerOn(r, in: layout) }; return }
        // مسار الأجداد (عبر الأب) من العضو للأعلى
        var path: [UUID] = []
        var cur: UUID? = id
        var seen = Set<UUID>()
        while let c = cur, !seen.contains(c) {
            seen.insert(c)
            path.append(c)
            cur = byId[c]?.fatherId
        }
        // وسّع كل الأجداد في المسار (أزلهم من المطويّ) — التركيز يُظهر المسار فقط
        var next = collapsed
        for a in path { next.remove(a) }
        collapsed = next
        let L = rebuild()
        // بدون زوم: تكبير طبيعي (1.0) وتمركز على اسمك — تقدر تسحب لأعلى وتشوف الجذر.
        guard let p = L.positions[id], viewport.width > 0 else { centerOn(id, in: L); return }
        userInteracted = true
        let s: CGFloat = 1.0
        let h = L.heights[id] ?? NODE_H
        let cx = (p.x + NODE_W / 2) * s
        let cy = (p.y + h / 2) * s
        withAnimation(DS.Anim.smooth) {
            scale = s; baseScale = s
            offset = clampOffset(CGSize(width: viewport.width / 2 - cx, height: viewport.height / 2 - cy))
            baseOffset = offset
        }
    }

    // ─── العقدة ───
    @ViewBuilder
    private func nodeView(_ m: FamilyMember, at p: CGPoint) -> some View {
        let deceased = m.isDeceased == true
        let female = m.isFemale
        // الإناث وردي ثابت؛ المتوفّاة وردي أغمق (طلب المالك). الذكر المتوفّى يبقى رمادياً.
        let accent: Color = female
            ? (deceased ? DS.Color.femaleDeceased : rose)
            : (deceased ? DS.Color.textTertiary : DS.Color.male)   // الذكر: كحلي ثابت (معنى)
        // حافة الأنثى المتوفّاة بلون متناسق مع الوردي الغامق (نبيذي) لتتميّز عن الحيّة — طلب المالك
        let border: Color = (female && deceased) ? DS.Color.femaleDeceasedBorder : accent
        let kids = cChildrenOf[m.id] ?? []
        let isCollapsed = collapsed.contains(m.id)
        let showWives = !isCollapsed && !kids.isEmpty
        let wives = showWives ? (cWives[m.id] ?? []) : []

        let shape = RoundedRectangle(cornerRadius: CORNER, style: .continuous)
        let noPhotoMale = !female && m.avatarUrl.flatMap { URL(string: $0) } == nil

        VStack(spacing: DS.Spacing.xxs) {
            ZStack {
                // الزوجات جنب العضو — دائماً جنب بعض (طلب المالك)؛
                // الاسم الطويل ينزل على سطرين تحت مربعه بدل تكديس المربعات
                if !wives.isEmpty {
                    HStack(alignment: .top, spacing: DS.Spacing.xsm) {
                        ForEach(wives.prefix(3)) { wifeCell($0) }
                    }
                    .offset(x: -(CIRCLE / 2 + 6
                                 + CGFloat(min(wives.count, 3)) * 17
                                 + CGFloat(max(0, min(wives.count, 3) - 1)) * 3),
                            y: -2)
                }
                // شكل العضو (squircle) — إطار أخف. المتوفّى: صورة غير ملوّنة.
                // قاعدة معتمة تحت اللون الشفاف — تمنع ظهور خط القوس خلف خلفية العضو
                shape
                    .fill(DS.Color.background)
                    // مربع الابنة بنفس غمقة مربع الزوجة (طلب المالك) — رمادي أنعم قليلاً
                    .overlay(shape.fill(deceased && !female
                        ? DS.Color.textTertiary.opacity(DS.Opacity.disabled)
                        : accent)
                        // الذكر بلا صورة — أرضية فاتحة بلونه والرسم فوقها
                        .opacity(noPhotoMale ? DS.Opacity.tintFillStrong : 1))
                    .frame(width: CIRCLE, height: CIRCLE)
                    .overlay(
                        Group {
                            if !female, let url = m.avatarUrl, let u = URL(string: url) {
                                CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: {
                                    Image(systemName: "person.fill")
                                        .dsGlyph(DS.Glyph.xl, weight: .semibold)
                                        .foregroundColor(DS.Color.textOnPrimary)
                                }
                                .frame(width: CIRCLE, height: CIRCLE).clipShape(shape)
                                .saturation(deceased ? 0 : 1)          // متوفّى → غير ملوّنة
                            } else if female {
                                // الإناث: كلمة «ابنة» بدل الحرف الأول
                                Text(L10n.t("ابنة", "Daughter"))
                                    .dsFont(.badge)
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                    .foregroundColor(DS.Color.textOnPrimary)
                            } else {
                                // الذكر بلا صورة: مجسّم «مجسّمات» بلون الذكر/المتوفّى نفسه
                                TreeAvatarArt(tint: accent, size: CIRCLE - 6)
                                    .equatable()
                            }
                        }
                    )
                    // حواف متّحدة المركز (طلب المالك): الأبيض داخل الحافة تماماً، والملوّن خارجها
                    // بنصف قطر أكبر بمقدار المسافة نفسها — فتتطابق الزوايا ولا تتعرّج
                    // (حلقة بيضاء رسم — نفس لون النص فوق التعبئة)
                    .overlay(shape.strokeBorder(DS.Color.textOnPrimary, lineWidth: RING))
                    .modifier(DSClaySkin(active: female, radius: CORNER, onFill: true, section: .tree))
                    .overlay(
                        RoundedRectangle(cornerRadius: CORNER + 2.5, style: .continuous)
                            .strokeBorder(border, lineWidth: 2)
                            .padding(-2.5)
                    )
                    // شارة الوفاة: قلب مكسور رمادي (غير ملوّن)
                    .overlay(alignment: .bottomTrailing) {
                        if deceased {
                            Circle().fill(DS.Color.background)
                                .frame(width: DS.Icon.avatarBadge, height: DS.Icon.avatarBadge)
                                .overlay(
                                    Image(systemName: "heart.slash.fill")
                                        .dsGlyph(DS.Glyph.microCompact)
                                        .foregroundColor(DS.Color.textSecondary)
                                )
                                .offset(x: 4, y: 4)
                        }
                    }
                    // شارة الإخفاء: عين مشطوبة — لا يراها إلا الإداري، لأن
                    // المخفيّ لا يصل العضو العادي أصلًا. تميّز «مخفية عن الشجرة»
                    // من الظاهرة بلا فتح التفاصيل.
                    .overlay(alignment: .topTrailing) {
                        if m.isHiddenFromTree {
                            Circle().fill(DS.Color.background)
                                .frame(width: DS.Icon.avatarBadge, height: DS.Icon.avatarBadge)
                                .overlay(
                                    Image(systemName: "eye.slash.fill")
                                        .dsGlyph(DS.Glyph.microCompact)
                                        .foregroundColor(DS.Color.warning)
                                )
                                .offset(x: 4, y: -4)
                        }
                    }
                    // المخفيّ باهت — إشارة ثانية تُقرأ من بعيد دون تمييز الشارة
                    .opacity(m.isHiddenFromTree ? DS.Opacity.disabled : 1)
                    // شارة عدد الأبناء + سهم — فوق يسار الصورة (طلب المالك)
                    .overlay(alignment: .topLeading) {
                        if !kids.isEmpty {
                            HStack(spacing: DS.Spacing.xxs) {
                                Text("\(kids.count)")
                                    .dsFont(.treeNodeMicro)
                                Image(systemName: "chevron.down")
                                    .dsGlyph(DS.Glyph.nano, weight: .heavy)
                                    .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                            }
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.xs)
                            .frame(minWidth: 16, minHeight: 16)
                            // غامق قسم الشجرة (كان كحلياً ثابتاً) — أغمق من لون العضو بلا صورة (طلب المالك)
                            .background(Capsule().fill(AppSection.tree.deep))
                            .overlay(Capsule().stroke(DS.Color.textOnPrimary, lineWidth: 1.2))
                            .offset(x: -7, y: -7)
                        }
                    }
            }
            .frame(width: CIRCLE, height: CIRCLE)
            // الصورة: توسيع/طي الأبناء — وبلا أبناء تفتح التفاصيل (طلب المالك)
            .onTapGesture {
                if kids.isEmpty { onSelect?(m); return }
                if collapsed.contains(m.id) {
                    pendingExpandScroll = m.id    // توسّع → انزل للأبناء
                    lastExpandedId = m.id         // أبناؤه يدخلون بتدرّج
                } else {
                    lastExpandedId = nil
                    pendingCollapseScroll = m.fatherId ?? m.id   // طي → اطلع لأب العقدة
                }
                withAnimation(DS.Anim.snappy) { toggle(m.id) }
            }

            if deceased {
                // بطاقة مدمجة للمتوفّى — الاسم فوق وشريط السنوات الأحمر ملتصق تحته
                // (نفس تصميم شجرة العائلة، بمقاس عقد النساء الصغيرة)
                VStack(spacing: 0) {
                    Text(m.firstName)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .frame(maxWidth: NODE_W)
                        .frame(height: PILL_H)
                        .background(DS.Color.surface)
                    Text(lifeSpanNeat(m) ?? L10n.t(m.isFemale ? "متوفية" : "متوفى", "Deceased"))
                        .dsFont(.treeNodeMicro)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, DS.Spacing.xs)
                        .frame(maxWidth: NODE_W)
                        .frame(height: LIFE_H + 2)
                        .background(DS.Color.deceasedStrip)   // عنّابي بدرجة خفيفة (طلب المالك)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .modifier(DSClaySkin(radius: 10, compact: true, section: .tree))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(female ? border.opacity(DS.Opacity.selectedStroke) : accent.opacity(DS.Opacity.tintStroke),
                            lineWidth: DS.Border.width))
                .onTapGesture { onSelect?(m) }   // الاسم يفتح تفاصيل العضو (طلب المالك)
            } else {
                Text(m.firstName)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)   // تصغير أكبر → الاسم الطويل يظهر كاملاً بلا اقتطاع
                    .padding(.horizontal, DS.Spacing.xsm)
                    .frame(maxWidth: NODE_W)
                    .frame(height: PILL_H)
                    .background(Capsule().fill(DS.Color.surface))
                    .modifier(DSClaySkin(compact: true, section: .tree))
                    .overlay(Capsule().stroke(accent.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                    .onTapGesture { onSelect?(m) }   // الاسم يفتح تفاصيل العضو (طلب المالك)
            }
        }
        // نصوص العقدة بمقاسها الثابت مثل خطوط النظام سابقاً — الكانفس يُكبَّر بالقرص لا بحجم الخط
        .dynamicTypeSize(.large)
        .frame(width: NODE_W, height: layout.heights[m.id] ?? NODE_H, alignment: .top)  // ارتفاع ثابت → الأسماء بنفس المستوى
        .position(x: p.x + NODE_W / 2, y: p.y + (layout.heights[m.id] ?? NODE_H) / 2)
        // دخول متدرّج: أبناء العقدة المتوسّعة ينزلون واحدًا بعد الآخر
        .transition(.asymmetric(
            insertion: AnyTransition.scale(scale: 0.55, anchor: .top)
                .combined(with: .offset(y: -10))
                .combined(with: .opacity)
                .animation(DS.Anim.snappy.delay(staggerDelay(m))),
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))
        ))
    }

    /// خلية زوجة واحدة: مربّع «زوجة» + الاسم الأول والأخير تحته.
    private func wifeCell(_ w: FamilyMember) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(w.isDeceased == true ? DS.Color.femaleDeceased : rose)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(w.isDeceased == true ? DS.Color.femaleDeceasedBorder : DS.Color.textOnPrimary,
                                  lineWidth: w.isDeceased == true ? DS.Border.widthBold : DS.Border.width))
                .overlay(
                    Text(L10n.t("زوجة", "Wife"))
                        .dsFont(.treeNodeTiny)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundColor(DS.Color.textOnPrimary)
                )
                // نفس شارة الإخفاء على مربّع الزوجة — بمقاس الخلية الصغيرة
                .overlay(alignment: .topTrailing) {
                    if w.isHiddenFromTree {
                        Circle().fill(DS.Color.background)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "eye.slash.fill")
                                    .dsGlyph(DS.Glyph.nano)
                                    .foregroundColor(DS.Color.warning)
                            )
                            .offset(x: 3, y: -3)
                    }
                }
                .opacity(w.isHiddenFromTree ? DS.Opacity.disabled : 1)
            Text(wifeShortName(w))
                .dsFont(.treeNodeTiny)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: 34)
        }
    }

    /// اسم الزوجة المختصر: الاسم الأول والأخير فقط (طلب المالك).
    /// نفضّل الاسم الكامل متى ما كان فيه أكثر من كلمة — بعض السجلات تخزّن
    /// كلمة وحدة فقط في حقل الاسم الأول والباقي في الاسم الكامل.
    private func wifeShortName(_ w: FamilyMember) -> String {
        let full = w.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = w.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let src = full.split(separator: " ").count >= 2 ? full : (first.isEmpty ? full : first)
        let parts = src.split(separator: " ")
        guard let f = parts.first else { return "" }
        guard parts.count > 1, let l = parts.last else { return String(f) }
        return "\(f) \(l)"
    }

    /// تأخير الدخول لكل ابن حسب ترتيبه بين إخوته (حد أقصى 0.35 ث).
    private func staggerDelay(_ m: FamilyMember) -> Double {
        guard let pid = lastExpandedId, m.fatherId == pid,
              let sibs = cChildrenOf[pid],
              let idx = sibs.firstIndex(where: { $0.id == m.id }) else { return 0 }
        return min(0.35, Double(idx) * 0.05)
    }

    /// سنوات المتوفّى «ميلاد - وفاة» مع لاحقة «م»، والمجهولة «٠٠٠٠م» — يطابق شجرة العائلة.
    private func lifeSpanNeat(_ m: FamilyMember) -> String? {
        guard m.isDeceased == true else { return nil }
        let by = year(m.birthDate), dy = year(m.deathDate)
        guard by != nil || dy != nil else { return nil }   // كلاهما مفقود → «متوفى» في الشريط
        // عزل كل سنة (U+2066…U+2069) لتبقى «م» بجانب رقمها — طلب المالك
        // الوفاة أولاً ثم الميلاد (معكوس — طلب المالك)
        return "\u{2066}م\(dy ?? "0000")\u{2069} - \u{2066}م\(by ?? "0000")\u{2069}"
    }
    private func year(_ s: String?) -> String? {
        guard let s, let r = s.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return String(s[r])
    }

    private func toggle(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func initIfNeeded() {
        guard let root = activeRoot, initedRoot != root else { return }
        var next = Set<UUID>()
        let cOf = childrenOf
        func walk(_ id: UUID, _ d: Int) {
            let kids = cOf[id] ?? []
            if !kids.isEmpty && d >= 0 { if d >= 0 { } }
            // اطوِ كل ما بعد الجيل الأول (الجذر وأبناؤه ظاهرون)
            if !kids.isEmpty && d >= 1 { next.insert(id) }
            for k in kids { walk(k.id, d + 1) }
        }
        walk(root, 0)
        collapsed = next
        initedRoot = root
    }

    private func fit(in size: CGSize, layout L: Layout) {
        guard L.size.width > 0, size.width > 0 else { return }
        // الوضع الأفقي: سقف زوم أصغر + بلا بار علوي فالهامش أصغر
        let landscape = size.width > size.height
        let s = max(0.35, min(landscape ? 0.85 : 1.2, (size.width - 32) / L.size.width))
        scale = s; baseScale = s
        // عمودي: 72 = ارتفاع البار العائم — الجذر يبدأ تحته لا خلفه
        offset = CGSize(width: (size.width - L.size.width * s) / 2, height: landscape ? 16 : 72)
        baseOffset = offset
    }

    /// زر البداية: يرجع لحالة الجذر ويعيد الملاءمة بحركة واضحة.
    private func goHome() {
        userInteracted = false
        initedRoot = nil
        initIfNeeded()
        let L = rebuild()
        withAnimation(.easeInOut(duration: 0.4)) {
            fit(in: viewport, layout: L)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                userInteracted = true
                // حدود يمين/يسار (وأعلى/أسفل) أثناء السحب — لا تخرج الشجرة عن الشاشة.
                offset = clampOffset(CGSize(width: baseOffset.width + v.translation.width,
                                            height: baseOffset.height + v.translation.height))
            }
            .onEnded { v in
                // زخم مثل ScrollView: أكمل الحركة حسب السرعة المتوقّعة ثم استقر داخل الحدود.
                let projected = CGSize(
                    width: baseOffset.width + v.predictedEndTranslation.width,
                    height: baseOffset.height + v.predictedEndTranslation.height
                )
                let target = clampOffset(projected)
                withAnimation(.easeOut(duration: 0.4)) { offset = target }
                baseOffset = target
            }
    }

    /// يُبقي الشجرة داخل حدود معقولة، مع السماح بالتحريك يمين/يسار حتى لو كانت أضيق من الشاشة.
    private func clampOffset(_ o: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return o }
        let overscroll: CGFloat = 90
        let contentW = layout.size.width * scale
        let contentH = layout.size.height * scale

        func clampAxis(_ value: CGFloat, content: CGFloat, view: CGFloat, topHi: CGFloat) -> CGFloat {
            if content <= view {
                // أضيق/أقصر من الشاشة: يتحرّك ضمن الفراغ + هامش (مو مقفول بالنص).
                let slack = view - content
                return min(max(value, -overscroll), slack + overscroll)
            }
            let lo = view - content - overscroll                 // الحافة السفلية مدفوعة للنهاية
            return min(max(value, lo), topHi)
        }
        return CGSize(
            width: clampAxis(o.width, content: contentW, view: viewport.width, topHi: overscroll),
            // عموديًا: يسمح بسحب أعلى الشجرة (الجذر) حتى نص الشاشة — ليظهر كامل الاسم+الصورة.
            height: clampAxis(o.height, content: contentH, view: viewport.height, topHi: viewport.height * 0.5)
        )
    }

}

/// قرصة التكبير مع تثبيت نقطة القرصة تحت الأصابع (iOS 17+)، وإلا تكبير عادي.
private struct PinchZoomModifier: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var baseScale: CGFloat
    @Binding var offset: CGSize
    @Binding var baseOffset: CGSize
    @Binding var userInteracted: Bool
    let clamp: (CGSize) -> CGSize

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        userInteracted = true
                        let ns = min(1.8, max(0.3, baseScale * v.magnification))
                        // نقطة القرصة داخل الـ canvas — نُثبّتها تحت الأصابع أثناء التكبير.
                        let f = v.startLocation
                        let r = scale > 0 ? ns / scale : 1
                        offset = CGSize(width: f.x - (f.x - offset.width) * r,
                                        height: f.y - (f.y - offset.height) * r)
                        scale = ns
                    }
                    .onEnded { _ in
                        baseScale = scale
                        let t = clamp(offset)
                        withAnimation(.easeOut(duration: 0.25)) { offset = t }
                        baseOffset = t
                    }
            )
        } else {
            content.simultaneousGesture(
                MagnificationGesture()
                    .onChanged { v in userInteracted = true; scale = min(1.8, max(0.3, baseScale * v)) }
                    .onEnded { _ in
                        baseScale = scale
                        let t = clamp(offset)
                        withAnimation(.easeOut(duration: 0.25)) { offset = t }
                        baseOffset = t
                    }
            )
        }
    }
}

/// شكل نصف-كبسولة (أعلى مستقيم، أسفل مقوّس) لشارة العدّاد.
private struct SemiCapsule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.height
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
