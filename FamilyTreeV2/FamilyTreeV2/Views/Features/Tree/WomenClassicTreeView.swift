import SwiftUI

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
    private let MAX_PER_ROW = 3             // صفوف أفقية عند وجود جنس واحد فقط
    private let STUB: CGFloat = 11
    private let PAD: CGFloat = 32
    private let GENDER_GAP: CGFloat = 12    // بين عمود الذكور وعمود الإناث — مسافة خفيفة (طلب المالك)

    private let rose = DS.Color.female

    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        var stubs: Set<UUID> = []   // آباء لديهم أبناء ظاهرون (لرسم الوصلة)
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
        let maxPerRow: Int = {
            guard viewport.width > viewport.height, viewport.width > 0 else { return MAX_PER_ROW }
            let fit = Int((viewport.width - PAD * 2) / (NODE_W + H_GAP))
            return max(MAX_PER_ROW, min(8, fit))
        }()
        func perRowH(_ n: Int) -> Int { n <= maxPerRow ? max(1, n) : maxPerRow }
        // عمودي (أعمدة جنسية): عمود واحد حتى ٤ · خمسة → عمودان والأخير تحتهم (٢+٢+١
        // — طلب المالك) · أكثر → ~٤ لكل عمود فرعي.
        func perRowV(_ n: Int) -> Int {
            // أفقياً: وزّع كل جنس على أعمدة أوسع (نصف ما تتحمّله الشاشة لكل جنس)
            if viewport.width > viewport.height {
                let half = max(2, maxPerRow / 2)
                return n <= half ? max(1, n) : half
            }
            if n <= 4 { return 1 }
            if n == 5 { return 2 }
            return Int(ceil(Double(n) / 4.0))
        }
        let stackGap: CGFloat = 10   // فجوة بين صفّ الذكور وصفّ الإناث (وضع مكدّس)
        let pairGap: CGFloat = H_GAP // ذكر+أنثى: نفس مسافة بقية الإخوة (طلب المالك)
        // الترتيب: جنس واحد → أفقي (٣/صف) · ذكر+أنثى فقط → جنب بعض · أقلية واحدة → مكدّس · كلاهما ≥٢ → عمودان.
        enum Arrange { case single, stacked, sideBySide, pair }
        func arrange(_ mCount: Int, _ fCount: Int) -> Arrange {
            if mCount == 0 || fCount == 0 { return .single }
            // حتى ٤ أبناء مختلطين → صف أفقي واحد (ذكور ثم إناث) بدل تكديس
            // الإناث تحت الذكور — التكديس كان يوهم أن الأخوات بنات لأخيهن
            if mCount + fCount <= (viewport.width > viewport.height ? maxPerRow : 4) { return .pair }
            if min(mCount, fCount) == 1 { return .stacked }
            return .sideBySide
        }

        // فجوة الصفوف: أي كتلة إخوة تلتف لأكثر من سطر (ذكوراً أو إناثاً)
        // تأخذ مسافة أوسع بين سطورها (طلب المالك)
        func rowGapFor(_ list: [FamilyMember], _ per: Int) -> CGFloat {
            list.count > per ? ROW_GAP + 9 : ROW_GAP
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
        func placeBlock(_ pid: UUID, _ list: [FamilyMember], _ cx: CGFloat, _ top: CGFloat, _ d: Int, _ per: Int) {
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
                rowTop += rowH + gap
                i += per
            }
        }
        func place(_ id: UUID, _ cx: CGFloat, _ top: CGFloat, _ d: Int) {
            if placed.contains(id) { return }
            placed.insert(id)
            L.positions[id] = CGPoint(x: cx - NODE_W / 2, y: top)
            L.depth[id] = d
            L.heights[id] = boxH(id)
            let kids = visibleChildren(id, cOf)
            if kids.isEmpty { return }
            L.stubs.insert(id)
            let rowTop = top + boxH(id) + V_GAP
            let males = kids.filter { !$0.isFemale }
            let females = kids.filter { $0.isFemale }
            switch arrange(males.count, females.count) {
            case .single:
                let list = males.isEmpty ? females : males
                placeBlock(id, list, cx, rowTop, d + 1, perRowH(list.count))
            case .stacked:
                // الأكبر أفقيًا فوق، والأقلية أفقيًا تحته — متمركزين.
                let mB = cachedBlock(males, perRowH(males.count))
                placeBlock(id, males, cx, rowTop, d + 1, perRowH(males.count))
                placeBlock(id, females, cx, rowTop + mB.height + stackGap, d + 1, perRowH(females.count))
            case .sideBySide:
                let pm = perRowV(males.count), pf = perRowV(females.count)
                let mW = cachedBlock(males, pm).width, fW = cachedBlock(females, pf).width
                let totalW = mW + GENDER_GAP + fW
                var bx = cx - totalW / 2
                placeBlock(id, males, bx + mW / 2, rowTop, d + 1, pm); bx += mW + GENDER_GAP
                placeBlock(id, females, bx + fW / 2, rowTop, d + 1, pf)
            case .pair:
                let pm = max(1, males.count), pf = max(1, females.count)
                let mW = cachedBlock(males, pm).width, fW = cachedBlock(females, pf).width
                let totalW = mW + pairGap + fW
                var bx = cx - totalW / 2
                placeBlock(id, males, bx + mW / 2, rowTop, d + 1, pm); bx += mW + pairGap
                placeBlock(id, females, bx + fW / 2, rowTop, d + 1, pf)
            }
        }

        let rootBox = measure(root)
        place(root, PAD + rootBox.width / 2, PAD, 0)
        let width = rootBox.width + PAD * 2
        let height = rootBox.height + PAD * 2
        // الـ canvas مثبّت LTR (لسحب صحيح)، فنقلب الإحداثيات رياضيًا:
        // الذكور يمين · الإناث يسار — مطابق للمعتمد سابقًا.
        for (id, p) in L.positions { L.positions[id] = CGPoint(x: width - p.x - NODE_W, y: p.y) }
        L.size = CGSize(width: width, height: height)
        return L
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
                            // الوصلات — قوس بكسرة خفيفة من أول لآخر ابن بالصف الأول
                            // (مثل شجرة العائلة)، وخط قصير عند ابن ظاهر واحد فقط
                            Canvas { ctx, _ in
                                for pid in layout.stubs {
                                    guard let a = layout.positions[pid] else { continue }
                                    let ph = layout.heights[pid] ?? NODE_H
                                    let pts = visibleChildren(pid, cChildrenOf)
                                        .compactMap { layout.positions[$0.id] }
                                    let minY = pts.map(\.y).min() ?? 0
                                    let topRow = pts.filter { abs($0.y - minY) < 1 }.sorted { $0.x < $1.x }
                                    if topRow.count >= 2, let f = topRow.first, let l = topRow.last {
                                        let apex = CGPoint(x: a.x + NODE_W / 2, y: a.y + ph - 2)
                                        let from = CGPoint(x: f.x + NODE_W / 2, y: f.y + 3)
                                        let to = CGPoint(x: l.x + NODE_W / 2, y: l.y + 3)
                                        var p = Path()
                                        p.move(to: from)
                                        p.addQuadCurve(to: apex,
                                                       control: CGPoint(x: from.x + (apex.x - from.x) * 0.5, y: from.y))
                                        p.addQuadCurve(to: to,
                                                       control: CGPoint(x: apex.x + (to.x - apex.x) * 0.5, y: to.y))
                                        ctx.stroke(p, with: .color(DS.Color.primary.opacity(0.45)),
                                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                    } else {
                                        var p = Path()
                                        let x = a.x + NODE_W / 2
                                        let top = a.y + ph + (V_GAP - STUB) / 2
                                        p.move(to: CGPoint(x: x, y: top))
                                        p.addLine(to: CGPoint(x: x, y: top + STUB))
                                        ctx.stroke(p, with: .color(DS.Color.primary.opacity(0.5)),
                                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    }
                                }
                            }
                            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                            .allowsHitTesting(false)
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
                        let L = rebuild()
                        fit(in: newSize, layout: L)
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

    // ─── شريط الأدوات العلوي — نفس بطاقة شجرة العائلة المدمّجة ───
    private var toolbarRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            // البداية — رجوع للجذر + إعادة الملاءمة (بحركة واضحة)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                goHome()
            } label: {
                toolbarIcon("house.fill")
            }
            .buttonStyle(DSScaleButtonStyle())

            Spacer()

            if let treeTab {
                FamilyTreeTabBar(selection: treeTab)
            }

            Spacer()

            // موقعي — يوسّع مسار العضو ويتمركز عليه (وإلا على الجذر)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let mid = meWomanId {
                    locate(mid)
                } else if let root = activeRoot {
                    centerOn(root, in: layout)
                }
            } label: {
                toolbarIcon("location.fill")
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 3)
        // مادة مخففة (50%) — نفس بار شجرة العائلة
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.75)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.mutedBackground.opacity(0.7), lineWidth: 1)
        )
        .dsSubtleShadow()
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }

    /// بار جانبي عمودي للوضع الأفقي — نفس أدوات البار العلوي (طلب المالك)
    private var landscapeSideToolbar: some View {
        VStack(spacing: DS.Spacing.sm) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                goHome()
            } label: {
                toolbarIcon("house.fill")
            }
            .buttonStyle(DSScaleButtonStyle())

            if let treeTab {
                VStack(spacing: 4) {
                    sideTabChip(L10n.t("العائلة", "Family"), idx: 0, treeTab: treeTab)
                    sideTabChip(L10n.t("النساء", "Women"), idx: 1, treeTab: treeTab)
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let mid = meWomanId {
                    locate(mid)
                } else if let root = activeRoot {
                    centerOn(root, in: layout)
                }
            } label: {
                toolbarIcon("location.fill")
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.75)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.mutedBackground.opacity(0.7), lineWidth: 1)
        )
        .dsSubtleShadow()
    }

    private func sideTabChip(_ title: String, idx: Int, treeTab: Binding<Int>) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { treeTab.wrappedValue = idx }
        } label: {
            Text(title)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(treeTab.wrappedValue == idx ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                .padding(.horizontal, 8)
                .frame(minWidth: 58, minHeight: 26)
                .background(Capsule().fill(treeTab.wrappedValue == idx ? DS.Color.primary : DS.Color.surface.opacity(0.8)))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func toolbarIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(14, weight: .bold))
            .foregroundColor(DS.Color.primary)
            .frame(width: 34, height: 34)
            .background(DS.Color.surface.opacity(0.8), in: Circle())   // أغمق (طلب المالك)
            .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.15), lineWidth: 1))
            .dsSubtleShadow()
            .contentShape(Circle())
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
        let accent: Color = deceased ? DS.Color.textTertiary : (female ? rose : DS.Color.primary)
        let kids = cChildrenOf[m.id] ?? []
        let isCollapsed = collapsed.contains(m.id)
        let showWives = !isCollapsed && !kids.isEmpty
        let wives = showWives ? (cWives[m.id] ?? []) : []

        let shape = RoundedRectangle(cornerRadius: CORNER, style: .continuous)

        VStack(spacing: 2) {
            ZStack {
                // الزوجات جنب العضو — دائماً جنب بعض (طلب المالك)؛
                // الاسم الطويل ينزل على سطرين تحت مربعه بدل تكديس المربعات
                if !wives.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
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
                    .overlay(shape.fill(deceased
                        ? (female ? DS.Color.textTertiary.opacity(0.85) : DS.Color.textTertiary.opacity(0.5))
                        : accent))
                    .frame(width: CIRCLE, height: CIRCLE)
                    .overlay(
                        Group {
                            if !female, let url = m.avatarUrl, let u = URL(string: url) {
                                CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: CIRCLE * 0.42, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .frame(width: CIRCLE, height: CIRCLE).clipShape(shape)
                                .saturation(deceased ? 0 : 1)          // متوفّى → غير ملوّنة
                            } else if female {
                                // الإناث: كلمة «ابنة» بدل الحرف الأول
                                Text(L10n.t("ابنة", "Daughter"))
                                    .font(.system(size: CIRCLE * 0.26, weight: .bold))
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                            } else {
                                // الذكور بلا صورة: أيقونة شخص بدل الحرف (طلب المالك)
                                Image(systemName: "person.fill")
                                    .font(.system(size: CIRCLE * 0.42, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                    .overlay(shape.stroke(Color.white, lineWidth: RING))
                    .overlay(shape.stroke(accent, lineWidth: 2).padding(-RING - 0.5))   // إطار ملوّن
                    // شارة الوفاة: قلب مكسور رمادي (غير ملوّن)
                    .overlay(alignment: .bottomTrailing) {
                        if deceased {
                            Circle().fill(DS.Color.background)
                                .frame(width: 17, height: 17)
                                .overlay(
                                    Image(systemName: "heart.slash.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(DS.Color.textSecondary)
                                )
                                .offset(x: 4, y: 4)
                        }
                    }
                    // شارة عدد الأبناء + سهم — فوق يسار الصورة (طلب المالك)
                    .overlay(alignment: .topLeading) {
                        if !kids.isEmpty {
                            HStack(spacing: 1.5) {
                                Text("\(kids.count)")
                                    .font(.system(size: 10, weight: .heavy))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .heavy))
                                    .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(DS.Color.primaryDark))   // أغمق من لون العضو بلا صورة (طلب المالك)
                            .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: NODE_W)
                        .frame(height: PILL_H)
                        .background(DS.Color.surface)
                    Text(lifeSpanNeat(m) ?? L10n.t(m.isFemale ? "متوفية" : "متوفى", "Deceased"))
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: NODE_W)
                        .frame(height: LIFE_H + 2)
                        .background(Color(hex: "#A62B32"))   // عنّابي بدرجة خفيفة (طلب المالك)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.4), lineWidth: 1))
                .onTapGesture { onSelect?(m) }   // الاسم يفتح تفاصيل العضو (طلب المالك)
            } else {
                Text(m.firstName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)   // تصغير أكبر → الاسم الطويل يظهر كاملاً بلا اقتطاع
                    .padding(.horizontal, 6)
                    .frame(maxWidth: NODE_W)
                    .frame(height: PILL_H)
                    .background(Capsule().fill(DS.Color.surface))
                    .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: 1))
                    .onTapGesture { onSelect?(m) }   // الاسم يفتح تفاصيل العضو (طلب المالك)
            }
        }
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
        VStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(w.isDeceased == true ? DS.Color.textTertiary : rose)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
                .overlay(
                    Text(L10n.t("زوجة", "Wife"))
                        .font(.system(size: 7.5, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundColor(.white)
                )
                .saturation(w.isDeceased == true ? 0 : 1)
            Text(wifeShortName(w))
                .font(.system(size: 8, weight: .medium))
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
        return "\(by ?? "0000")م - \(dy ?? "0000")م"
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
