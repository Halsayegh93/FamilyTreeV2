import SwiftUI

// MARK: - «افتح بالشجرة الكاملة» — الشجرة الحقيقية على مكان الطلب (٢٠٢٦-١١-١٣، الاختيار «ج»)
//
// غطاء ملء الشاشة فوق مربّع الطلب (المربّع يبقى تحته، والإغلاق يرجع له): رأس «معاينة في الشجرة» ← الشجرة نفسها
// ← لوحة سفلية بالملاحظة و«العودة إلى الطلب» + زرّ المربّع الرئيسي نفسه. الرسم هو رسم تبويب الشجرة لا نسخة:
//  • شجرة العائلة: محرّك التخطيط الواحد `FamilyTreeLayoutEngine` + `TreeMemberNode` + `TreeConnectorsLayer`
//    + قرصة `TreePinchZoomModifier` — بحالة خاصة بالمعاينة، فلا يتغيّر شيء في تبويب الشجرة.
//  • شجرة النساء: `WomenClassicTreeView` نفسها بوضع المعاينة (`preview:`) — نسخة معزولة بلا أدوات.
// الشبح (يُضاف/أُضيف) يُدرج آخر أبناء الأب في التخطيط فقط، والتعديل يُرسم بحالته «بعد التنفيذ».

/// كاميرا المعاينة الأولى في الشجرتين (طلب المالك ٢٠٢٦-١١-١٣ «ابيك تخلي صورة الشجرة بالمنتصف»): مجموعة المكان
/// (الجد إن ظهر، الأب، صفّ الإخوة بالشخص/الشبح/خانة الزوجة) بمنتصف المساحة الحرّة أفقياً وعمودياً — بين الشريط
/// الداكن واللوحة السفلية — بهامش مريح؛ المقياس يلائمها بين التصغير الخفيف للشجرة وتكبيرها الافتراضي (لا أكبر
/// من حجم تبويب الشجرة المعتاد). الأطول من المساحة بعد التصغير الخفيف: أعلاها في الأعلى. السحب والقرص حرّان بعدها
enum TreePlaceCamera {
    static let margin: CGFloat = TreeGroupFit.margin + DS.Spacing.sm

    static func center(rect: CGRect, viewport: CGSize, k: CGFloat) -> (scale: CGFloat, offset: CGSize) {
        let avail = CGRect(x: margin, y: margin, width: max(1, viewport.width - margin * 2),
                           height: max(1, viewport.height - margin * 2))
        let range = TreeGroupFit.autoRange(k: k)
        let fit = min(avail.width / max(1, rect.width), avail.height / max(1, rect.height))
        let s = min(range.hi, max(range.lo, fit))
        let x = avail.midX - rect.midX * s
        let y = rect.height * s <= avail.height ? avail.midY - rect.midY * s : avail.minY - rect.minY * s
        return (s, CGSize(width: x, height: y))
    }
}

/// ما تفتح عليه المعاينة في الشجرتين
struct TreePlaceTreeFocus {
    /// الشخص (أو الشبح) في بيانات المعاينة
    let personId: UUID
    /// أبوه — مسار الجذر ← الأب مفتوح، وباقي الفروع كما تطويها الشجرة
    let fatherId: UUID?
    let mark: TreePlaceMarkStyle
    /// الزوجة من خارج العائلة (مربّع شبح جنب الزوج)
    var wifeName: String? = nil
    /// ارتفاع ما يغطّي أعلى الشجرة (0 = لا شيء — الشريط فوقها)
    var chromeTop: CGFloat = 0
}

struct TreePlacePreviewScreen: View {
    let resolved: TreePlaceResolved
    let men: [FamilyMember]
    let women: [FamilyMember]
    let primaryTitle: String?
    var primaryIcon: String? = nil
    var backTitle: String = TreePlaceText.backToRequest
    let onBack: () -> Void
    let onPrimary: () -> Void

    private var focus: TreePlaceTreeFocus {
        TreePlaceTreeFocus(personId: resolved.person.id, fatherId: resolved.father?.id, mark: resolved.previewMark,
                           wifeName: resolved.wifeName)
    }

    /// بيانات المعاينة: الشبح (يُضاف، المحذوف) آخر أبناء أبيه، والتعديل بحالته بعده — نسخة محلية لا تمسّ الأصل
    private func previewMembers(_ base: [FamilyMember]) -> [FamilyMember] {
        var list = base
        if !list.contains(where: { $0.id == resolved.person.id }) { list.append(resolved.person) }
        if !resolved.place.rejected, let after = resolved.after, let i = list.firstIndex(where: { $0.id == after.id }) {
            list[i] = after
        }
        return list
    }

    /// الشريط تحت الرأس بحسب الزمن: قبل التنفيذ · بعد التغيير · مرفوض
    private var banner: String {
        if resolved.place.rejected { return TreePlaceText.rejectedNote }
        return resolved.place.tense == .past ? TreePlaceText.pastBanner : TreePlaceText.previewBanner
    }

    var body: some View {
        VStack(spacing: 0) {
            DSSubPageHeader(title: TreePlaceText.previewTitle,
                            subtitle: "\(resolved.place.kindLabel) · \(resolved.personFirstName)",
                            section: .tree, nav: .close, onBack: onBack)
            // الشريط فوق الشجرة لا عليها — فالكاميرا تبدأ تحته بلا قياس
            Text(banner)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textOnPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.primaryFill))
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
            tree
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            panel
        }
        .background(DS.Color.background.ignoresSafeArea())
        .dsSection(.tree)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    @ViewBuilder
    private var tree: some View {
        switch resolved.place.tree {
        case .men:
            TreePlaceMenCanvas(members: previewMembers(men), focus: focus)
        case .women:
            WomenClassicTreeView(members: previewMembers(women.isEmpty ? WomenStore.cache : women), preview: focus)
        }
    }

    /// اللوحة السفلية: الملاحظة بخط عريض ← «يمكنك التكبير…» ← «العودة إلى الطلب» + زرّ المربّع الرئيسي
    private var panel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Capsule()
                .fill(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                .frame(width: DS.Spacing.xxxl, height: DS.Spacing.xs)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(resolved.note)
                .dsFont(.headline)
                .foregroundColor(resolved.noteIsDanger ? DS.Color.error : DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(TreePlaceText.previewHint)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
            HStack(spacing: DS.Spacing.sm) {
                DSButton(backTitle, role: .cancel, action: onBack)
                if let primaryTitle {
                    DSButton(primaryTitle, icon: primaryIcon, action: onPrimary)
                }
            }
            .padding(.top, DS.Spacing.xs)
        }
        .padding(.horizontal, DS.Page.margin)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(alignment: .top) {
            // زوايا علوية مدوّرة: المستطيل يمتدّ تحت الحافة السفلية فتختفي زاويتاه السفليتان
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .fill(DS.Color.cardBackground)
                .padding(.bottom, -DS.Radius.xxl)
                .dsCardShadow()
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - شجرة العائلة في المعاينة — محرّك تبويب الشجرة نفسه بحالة معزولة

struct TreePlaceMenCanvas: View {
    let members: [FamilyMember]
    let focus: TreePlaceTreeFocus

    @Environment(\.dsTreeScale) private var envTreeScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index: FamilyTreeLayoutEngine.Index? = nil
    @State private var activePath: Set<UUID> = []
    /// المسار والأب وإخوة الشخص — الباقي باهت ٣٥٪
    @State private var lit: Set<UUID> = []
    @State private var layout = FamilyLayout()
    @State private var nodes: [FamilyMember] = []
    @State private var scale: CGFloat = TreeGroupFit.defaultScale
    @State private var baseScale: CGFloat = TreeGroupFit.defaultScale
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var fittedScale: CGFloat = TreeGroupFit.defaultScale
    @State private var viewport: CGSize = .zero
    @State private var userInteracted = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        TreeConnectorsLayer(connectors: layout.connectors, size: layout.size, skip: nil,
                                            dark: colorScheme == .dark, k: layout.m.k)
                            .equatable()
                        markLayer(.back)
                        ForEach(nodes, id: \.id) { m in
                            node(m)
                        }
                        wifeSlot
                        markLayer(.front)
                    }
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(offset)
                    // لمس العقد لا يفعل شيئاً — السحب والقرص والنقر المزدوج على الكانفس
                    .allowsHitTesting(false)
                }
                // الكانفس LTR مثل تبويب الشجرة (المرآة في التخطيط) → اتجاه السحب صحيح
                .environment(\.layoutDirection, .leftToRight)
                .contentShape(Rectangle())
                .clipped()
                .gesture(dragGesture)
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { doubleTap(at: $0.location) })
                .modifier(TreePinchZoomModifier(scale: $scale, baseScale: $baseScale, offset: $offset,
                                                baseOffset: $baseOffset, userInteracted: $userInteracted,
                                                clamp: clampOffset, k: layout.m.k))
                .onAppear {
                    viewport = geo.size
                    build()
                }
                .onChange(of: geo.size) { size in
                    // تدوير الشاشة: تُعاد الكاميرا للمنتصف كما تفعل الشجرة
                    if (viewport.width > viewport.height) != (size.width > size.height) { userInteracted = false }
                    viewport = size
                    relayout()
                }
                .onChange(of: focus.chromeTop) { _ in
                    if !userInteracted { focusPerson(in: layout) }
                }
                .onChange(of: envTreeScale) { _ in relayout() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TreePlaceText.previewTitle)
    }

    /// الفهرس (نفس قاعدة التبويب) ← مسار الجذر ← الأب مفتوح، والشخص غير مفتوح فيظهر إخوته كلهم
    /// خانة الزوجة من خارج العائلة في التخطيط (لا وجود لها في البيانات)
    static let wifeSlotId = UUID(uuidString: "7E1A0000-0000-4000-8000-00000000A0D2")!

    private func build() {
        var idx = FamilyTreeLayoutEngine.index(members)
        // الزوجة من خارج العائلة: خانة حقيقية بعد الزوج مباشرة بين إخوته (يسار الزوج في العربية) — فيتزحزح الإخوة ولا
        // يغطّي مربّعها عقدة أحد؛ بلا خط إليها (تُحذف من خطوط الأب في `relayout`)
        if let wife = focus.wifeName, let husband = idx.byId[focus.personId], let f = husband.fatherId,
           var kids = idx.children[f], let i = kids.firstIndex(where: { $0.id == husband.id }) {
            let slot = FamilyMember(id: Self.wifeSlotId, firstName: wife, fullName: wife, fatherId: f,
                                    sortOrder: husband.sortOrder, status: .active, gender: "female")
            kids.insert(slot, at: i + 1)
            var children = idx.children
            children[f] = kids
            var byId = idx.byId
            byId[slot.id] = slot
            idx = FamilyTreeLayoutEngine.Index(visible: idx.visible, byId: byId, roots: idx.roots, children: children)
        }
        index = idx
        var path = Set<UUID>()
        var cur = focus.fatherId
        while let c = cur, !path.contains(c) {
            path.insert(c)
            cur = idx.byId[c]?.fatherId
        }
        activePath = path
        let siblings = focus.fatherId.flatMap { idx.children[$0] } ?? []
        lit = path.union(siblings.map(\.id)).union([focus.personId])
        relayout()
    }

    private func relayout() {
        guard let idx = index else { return }
        var L = FamilyTreeLayoutEngine.layout(rootId: idx.roots.first?.id, children: idx.children, byId: idx.byId,
                                              activePath: activePath, kinship: [],
                                              landscape: viewport.width > viewport.height, k: envTreeScale)
        // خانة الزوجة: مكانها محجوز، وبلا خط من الأب إليها
        if L.positions[Self.wifeSlotId] != nil, let f = idx.byId[Self.wifeSlotId]?.fatherId, let rows = L.childRows[f] {
            L.childRows[f] = rows.map { $0.filter { $0 != Self.wifeSlotId } }.filter { !$0.isEmpty }
            L.connectors = FamilyTreeLayoutEngine.connectors(L, kinship: [])
        }
        layout = L
        nodes = idx.visible.filter { L.positions[$0.id] != nil }
        if !userInteracted { focusPerson(in: L) }
    }

    /// الكاميرا الأولى: مجموعة المكان (الجد إن ظهر، الأب، صفّ الإخوة بالشخص والشبح وخانة الزوجة) بالمنتصف —
    /// `TreePlaceCamera.center`
    private func focusPerson(in L: FamilyLayout) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        var ids: [UUID] = [focus.personId]
        if let f = focus.fatherId {
            ids.append(f)
            if let g = index?.byId[f]?.fatherId { ids.append(g) }
            ids += (L.childRows[f] ?? []).flatMap { $0 }
        }
        if L.positions[Self.wifeSlotId] != nil { ids.append(Self.wifeSlotId) }
        let nodes = ids.compactMap { id in
            L.positions[id].map { CGRect(x: $0.x, y: $0.y, width: L.m.nodeW, height: L.heights[id] ?? L.m.nodeHDefault) }
        }
        let fallback = index?.roots.first.flatMap { root in
            L.positions[root.id].map { CGRect(x: $0.x, y: $0.y, width: L.m.nodeW, height: L.heights[root.id] ?? L.m.nodeHDefault) }
        }
        let rect = (nodes.isEmpty ? [fallback].compactMap { $0 } : nodes).reduce(CGRect.null) { $0.union($1) }
            // الشريحة تحت عقدة الشخص
            .insetBy(dx: 0, dy: -L.m.k * DS.Spacing.lg)
        guard !rect.isNull, rect.width > 0 else { return }
        let cam = TreePlaceCamera.center(rect: rect, viewport: viewport, k: L.m.k)
        scale = cam.scale; baseScale = cam.scale; fittedScale = cam.scale
        offset = TreeGroupFit.looseClamp(cam.offset,
                                         content: CGSize(width: L.size.width * cam.scale, height: L.size.height * cam.scale),
                                         viewport: viewport)
        baseOffset = offset
    }

    private func node(_ m: FamilyMember) -> some View {
        let M = layout.m
        let p = layout.positions[m.id] ?? .zero
        let h = layout.heights[m.id] ?? M.nodeHDefault
        let kids = (index?.children[m.id] ?? []).filter { $0.id != Self.wifeSlotId }
        return TreeMemberNode(member: m, isExpanded: activePath.contains(m.id), searchedMemberID: .constant(nil),
                              hasChildren: !kids.isEmpty, childrenCount: kids.count, showName: true,
                              level: layout.depth[m.id] ?? 0, currentLocationMemberID: nil, k: M.k,
                              onTap: {}, onToggle: {})
            .equatable()
            .frame(width: M.nodeW, height: h, alignment: .top)
            .position(x: p.x + M.nodeW / 2, y: p.y + h / 2)
            .opacity(!lit.contains(m.id) ? 0.35 : (m.id == focus.personId && focus.mark.fadesPerson ? 0.45 : 1))
    }

    @ViewBuilder
    private func markLayer(_ layer: TreePlaceNodeMark.Layer) -> some View {
        if let p = layout.positions[focus.personId] {
            let M = layout.m
            let h = layout.heights[focus.personId] ?? M.nodeHDefault
            TreePlaceNodeMark(style: focus.mark, layer: layer, k: M.k, size: CGSize(width: M.nodeW, height: h))
                .position(x: p.x + M.nodeW / 2, y: p.y + h / 2)
        }
    }

    /// مربّع الزوجة من خارج العائلة في خانته المحجوزة بجانب الزوج
    @ViewBuilder
    private var wifeSlot: some View {
        if let name = focus.wifeName, let p = layout.positions[Self.wifeSlotId] {
            let M = layout.m
            let h = layout.heights[Self.wifeSlotId] ?? M.nodeHDefault
            TreePlaceWifeSlot(name: name, k: M.k)
                .frame(width: M.nodeW, height: h)
                .position(x: p.x + M.nodeW / 2, y: p.y + h / 2)
        }
    }

    // ─── الكاميرا: نفس حدود التبويب بعد الانتقال لعضو (المرتخية) ───

    private func clampOffset(_ o: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return o }
        return TreeGroupFit.looseClamp(o, content: CGSize(width: layout.size.width * scale, height: layout.size.height * scale),
                                       viewport: viewport)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                userInteracted = true
                offset = clampOffset(CGSize(width: baseOffset.width + v.translation.width,
                                            height: baseOffset.height + v.translation.height))
            }
            .onEnded { v in
                let target = clampOffset(CGSize(width: baseOffset.width + v.predictedEndTranslation.width,
                                                height: baseOffset.height + v.predictedEndTranslation.height))
                withAnimation(.easeOut(duration: 0.4)) { offset = target }
                baseOffset = target
            }
    }

    /// نقر مزدوج: تكبير نحو نقطة اللمس، أو رجوع للمقاس الافتراضي — مثل التبويب
    private func doubleTap(at location: CGPoint) {
        userInteracted = true
        let zoomedIn = scale > fittedScale + 0.05
        let ns: CGFloat = zoomedIn ? fittedScale : min(TreeConst.maxScale / layout.m.k, max(fittedScale * 2, 0.95))
        let r = scale > 0 ? ns / scale : 1
        let apply = {
            offset = clampOffset(CGSize(width: location.x - (location.x - offset.width) * r,
                                        height: location.y - (location.y - offset.height) * r))
            scale = ns; baseScale = ns; baseOffset = offset
        }
        if reduceMotion { apply() } else { withAnimation(.easeInOut(duration: 0.3)) { apply() } }
    }
}

// MARK: - علامة الشخص فوق عقدة الشجرة (الشجرتان)

/// إطار حول العقدة بشكل التغيير + شريحة تحتها — بإحداثيات العقدة × معامل
/// «حجم النص» فيكبر معها. `back` تحت العقد (التعبئة والهالة)، `front` فوقها (الإطار والشريحة)
struct TreePlaceNodeMark: View {
    enum Layer { case back, front }

    let style: TreePlaceMarkStyle
    let layer: Layer
    let k: CGFloat
    /// صندوق العقدة في التخطيط (عرض × ارتفاع)
    let size: CGSize

    private var pad: CGFloat { 8 * k }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 28 * k, style: .continuous) }

    var body: some View {
        switch layer {
        case .back:
            ZStack {
                if style.fillOpacity > 0 {
                    shape.fill(style.tint.opacity(style.fillOpacity))
                }
                if style.kind == .halo {
                    shape.stroke(style.tint.opacity(DS.Opacity.tintFillStrong), lineWidth: 12 * k)
                }
            }
            .padding(-pad)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        case .front:
            frame
                .padding(-pad)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    if let pill = style.pill {
                        // تحت الإطار مباشرة: فراغ بارتفاع العقدة ثم الشريحة
                        VStack(spacing: pad + DS.Spacing.xs * k) {
                            Color.clear.frame(width: 1, height: size.height)
                            Text(pill)
                                .dsTreeFont(.headline, k)
                                .foregroundColor(DS.Color.textOnPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, DS.Spacing.md * k)
                                .padding(.vertical, DS.Spacing.xs * k)
                                .background(Capsule().fill(style.pillFill))
                        }
                        .fixedSize()
                    }
                }
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var frame: some View {
        switch style.kind {
        case .ghost, .danger, .rejected:
            shape.stroke(style.tint, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round, dash: [9 * k, 7 * k]))
        case .halo:
            shape.stroke(style.tint, lineWidth: 3.5 * k)
        case .ring:
            shape.stroke(style.tint, lineWidth: 3 * k)
        case .grey:
            Color.clear
        }
    }

}

/// مربّع الزوجة الشبح بشكل شجرة النساء داخل خانتها المحجوزة (بعرض العقدة — لا يتجاوزها فلا يغطّي جاراً):
/// إطار وردي متقطّع، اسمها، وشريحة «زوجة من خارج العائلة»
struct TreePlaceWifeSlot: View {
    let name: String
    let k: CGFloat

    var body: some View {
        let box = RoundedRectangle(cornerRadius: 22 * k, style: .continuous)
        VStack(spacing: DS.Spacing.xs * k) {
            Image(systemName: "person.fill")
                .dsTreeGlyph(DS.Glyph.xxl, k, weight: .semibold)
                .foregroundColor(DS.Color.female)
            Text(PersonName.firstUnit(name.trimmingCharacters(in: .whitespacesAndNewlines)))
                .dsTreeFont(.title3Tree, k)
                .foregroundColor(DS.Color.female)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(TreePlaceText.outsideWifePill)
                .dsTreeFont(.badge, k)
                .foregroundColor(DS.Color.textOnPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, DS.Spacing.sm * k)
                .padding(.vertical, DS.Spacing.xxs * k)
                .background(Capsule().fill(DS.Color.femaleFill))
        }
        .padding(DS.Spacing.sm * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(box.fill(DS.Color.female.opacity(DS.Opacity.tintFillSoft)))
        .background(box.fill(DS.Color.background))
        .overlay(box.stroke(DS.Color.female, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round, dash: [9 * k, 7 * k])))
        .padding(.horizontal, DS.Spacing.xs * k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
