import SwiftUI
import Foundation

// MARK: - Notification Names
extension Notification.Name {
    static let memberDeleted = Notification.Name("memberDeleted")
    static let showKinshipPath = Notification.Name("showKinshipPath")
    /// Posted to navigate the tree to a specific member and open their details sheet.
    /// userInfo: ["memberId": UUID]
    static let openMemberInTree = Notification.Name("openMemberInTree")
}

// MARK: - ثوابت الشجرة
private enum TreeConst {
    // Zoom
    static let minScale: CGFloat = 0.2
    static let maxScale: CGFloat = 3.0
    static let defaultScale: CGFloat = 0.60
    static let openNodeScale: CGFloat = 0.75
    static let closeNodeScale: CGFloat = 0.80
    static let kinshipScale: CGFloat = 0.45

    // Durations (nanoseconds)
    static let shortDelay: UInt64 = 100_000_000     // 0.1s
    static let scrollDelay: UInt64 = 250_000_000     // 0.25s
    static let kinshipScrollDelay: UInt64 = 500_000_000 // 0.5s
    static let kinshipSecondScroll: UInt64 = 400_000_000 // 0.4s
    static let highlightDuration: UInt64 = 5_000_000_000 // 5s
    static let kinshipBannerDuration: UInt64 = 20_000_000_000 // 20s

    // Layout
    static let toolButtonSize: CGFloat = 44
    static let dividerWidth: CGFloat = 30
}

// MARK: - تخطيط الكانفس (إحداثيات مطلقة — نفس محرّك تبويب النساء)
/// نتيجة حساب مواضع كل العقد المرئية بإحداثيات مطلقة داخل كانفس ثابت.
private struct FamilyLayout {
    var positions: [UUID: CGPoint] = [:]     // الزاوية العليا-اليسرى لكل عقدة
    var depth: [UUID: Int] = [:]
    var heights: [UUID: CGFloat] = [:]       // ارتفاع صندوق كل عقدة
    var childRows: [UUID: [[UUID]]] = [:]     // صفوف أبناء كل أب (لرسم خطوط الربط)
    var connectors: [ConnectorGroup] = []     // خطوط كل أب مع أبنائه — تُبنى مرة مع التخطيط
    var size: CGSize = .zero
}

/// خطوط أب واحد مع كل أبنائه (كل الصفوف) — تُبنى مرة مع التخطيط بعد المرآة لا كل إطار.
private struct ConnectorGroup {
    var pid: UUID? = nil       // الأب — لرسم خطوط آخر أب فُتح بالتدريج
    var path = Path()          // الخطوط العادية
    var kinPath = Path()       // طريق القرابة — ذهبي وأسمك
    var dots: [CGPoint] = []   // نقاط تفرّع الأبناء عن الخط الأفقي
}

/// مسار جاهز كشكل — لرسم خطوط الأب المفتوح للتو بالتدريج (`trim`) من الأب نحو الأبناء.
private struct ConnectorPathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

/// قرصة التكبير مع تثبيت النقطة تحت الأصابع (iOS 17+) — نسخة شجرة العائلة.
private struct TreePinchZoomModifier: ViewModifier {
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
                        let ns = min(TreeConst.maxScale, max(TreeConst.minScale, baseScale * v.magnification))
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
                    .onChanged { v in userInteracted = true; scale = min(TreeConst.maxScale, max(TreeConst.minScale, baseScale * v)) }
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

// MARK: - 1. واجهة الشجرة الرئيسية — Liquid Glass
struct TreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Binding var selectedTab: Int
    /// تبويب علوي [عائلة/نساء] — يظهر تحت الهيدر عند تمريره.
    var treeTab: Binding<Int>? = nil
    @State private var showingNotifications = false
    @State private var selectedMember: FamilyMember? = nil
    @State private var currentLocationMemberID: UUID? = nil
    /// «موقعي» والحساب غير مربوط بالشجرة (بلا أب أو مخفي أو غير موجود) — رسالة بدل لا شيء
    @State private var showNotInTree = false
    @State private var isRefreshing = false

    @State private var searchedMemberID: UUID? = nil
    @State private var highlightTask: Task<Void, Never>?

    // ── محرّك الكانفس (إحداثيات مطلقة، يطابق تبويب النساء — زوم حقيقي + سحب بزخم) ──
    @State private var scale: CGFloat = TreeConst.defaultScale
    @State private var baseScale: CGFloat = TreeConst.defaultScale
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var viewport: CGSize = .zero
    @State private var layout = FamilyLayout()
    @State private var userInteracted = false
    @State private var fittedScale: CGFloat = TreeConst.defaultScale
    /// إظهار حقل البحث (مخفي افتراضياً خلف زر — العرض الكلاسيكي).
    @State private var showSearch = false

    // أبعاد العقدة الدائرية + فجوات الكانفس (النقل يحافظ على شكل العقد الحالي)
    private let NODE_W: CGFloat = 124        // عرض صندوق العقدة (الدائرة 105 + الإطار)
    private let CIRCLE_FULL: CGFloat = 112   // ارتفاع الدائرة + حلقة الرتبة
    private let NAME_H: CGFloat = 32         // كبسولة الاسم
    private let BADGE_H: CGFloat = 40        // شريحة التوسيع (36 + فجوة 4)
    private let LIFE_H: CGFloat = 20         // سطر سنوات المتوفّى
    private let H_GAP: CGFloat = 14          // بين الإخوة أفقيًا
    private let V_GAP: CGFloat = 48          // بين الأب وأبنائه عموديًا (عُوّضت مساحة شريحة التوسيع المحذوفة)
    private let ROW_GAP: CGFloat = 34        // بين صفوف الأبناء الملتفّة — يتّسع لخط الصف فوقه
    private let SPINE_ROOM: CGFloat = 18     // مساحة العمود على جانبي الأبناء الملتفّين (يبقى التمركز)
    private let SPINE_OUT: CGFloat = 12      // بُعد العمود عن حافة أبعد ابن
    private let LINE_CORNER: CGFloat = 10    // استدارة زوايا الخطوط
    private let CANVAS_PAD: CGFloat = 60     // هامش حول الشجرة
    /// أبناء لكل صف قبل الالتفاف — عمودياً ٣، وأفقياً يُحسب تلقائياً من عرض
    /// الشاشة ليتوسّع الإخوة جنب بعض بدل التكديس (طلب المالك)
    private var PER_ROW: Int {
        guard viewport.width > viewport.height, viewport.width > 0 else { return 3 }
        // أفقياً: صف واحد ما دام العدد معقولاً، وإذا كثر فسطران متساويان
        // (طلب المالك) — دالة perRow(for:) تتكفّل بالتقسيم لكل أب على حدة.
        return 99
    }
    private var NODE_H_DEFAULT: CGFloat { CIRCLE_FULL + NAME_H }
    /// عدد الأبناء في الصف الواحد لهذا الأب:
    /// عمودي ٣ · أفقي: صف واحد حتى ١٠، وإذا كثروا فسطران متساويان (طلب المالك).
    private func perRow(for count: Int) -> Int {
        guard viewport.width > viewport.height else { return 3 }
        if count <= 10 { return max(1, count) }
        return Int(ceil(Double(count) / 2.0))
    }
    /// ارتفاع صندوق العقدة حسب الحالة (يطابق ترتيب TreeMemberNode: دائرة+اسم[+سنوات]).
    /// شريحة التوسيع أُزيلت — العدّاد صار شارة فوق الصورة (طلب المالك).
    private func nodeBoxHeight(deceased: Bool, hasKids: Bool) -> CGFloat {
        CIRCLE_FULL + NAME_H + (deceased ? LIFE_H : 0)
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass
    private var isLandscapeMode: Bool { verticalSizeClass == .compact }
    @Environment(\.colorScheme) var colorScheme
    /// دخول الأدوات حول الشجرة (الشريط، زر التحديث، الحالة الفارغة) مرة مع أول ظهور
    /// للتبويب — من TreeTabContainer، فلا يتكرر عند التبديل «العائلة/النساء».
    /// الرسم والعُقد والإيماءات لا تُمسّ.
    @Environment(\.treeChromeAppeared) private var chromeAppeared
    /// «تقليل الحركة»: شريط المسار وبانر القرابة يظهران بتلاشٍ بلا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activePath: Set<UUID> = []
    @State private var kinshipBanner: String? = nil
    @State private var kinshipHighlightedIds: Set<UUID> = [] // الأعضاء المهايلايتين بصلة القرابة
    /// آخر أب فُتح — خطوطه تُرسم بالتدريج من الأب نحو أبنائه، وأبناؤه يدخلون تباعاً
    /// (طلب المالك ٢٠٢٦-١٠-٠٤: حركات بالشجرة). «تقليل الحركة»: بلا تدريج.
    @State private var drawOnId: UUID? = nil
    @State private var drawProgress: CGFloat = 1
    /// TMP-ART-TRIAL: اتجاه الرسوم المختار — يقرأ مرة هنا ويُمرَّر للعقد (لا قراءة لكل عقدة)
    @AppStorage(ArtTrial.storageKey) private var artRaw = ArtTrial.emblem.rawValue
    private var art: ArtTrial { ArtTrial(rawValue: artRaw) ?? .emblem }   // TMP-ART-TRIAL

    // MARK: - بيانات مُخزنة مؤقتاً لتجنب إعادة الحساب كل render
    @State private var cachedVisibleMembers: [FamilyMember] = []
    @State private var cachedMemberById: [UUID: FamilyMember] = [:]
    @State private var cachedRootMembers: [FamilyMember] = []
    @State private var cachedChildrenByFatherId: [UUID: [FamilyMember]] = [:]
    @State private var cachedMemberIds: Set<UUID> = []

    private var primaryRootMember: FamilyMember? {
        cachedRootMembers.first
    }

    /// نتيجة بناء الكاش — قابلة للتحويل بين threads (FamilyMember هو struct).
    private struct TreeCache {
        let visible: [FamilyMember]
        let byId: [UUID: FamilyMember]
        let roots: [FamilyMember]
        let childrenMap: [UUID: [FamilyMember]]
        let ids: Set<UUID>
    }

    /// حساب الكاش — pure function، تشتغل على أي thread.
    private nonisolated static func computeCache(from members: [FamilyMember]) -> TreeCache {
        // المعيار القانوني الموحّد لـ"عضو في العائلة" — نفسه في الويب وكل العدّادات
        let visible = members.filter(\.isCountable)
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })

        // مجموعة الأعضاء اللي عندهم أبناء (آباء حقيقيين)
        let fatherIds = Set(visible.compactMap(\.fatherId))

        let roots = visible.filter { member in
            guard let fatherId = member.fatherId else {
                // عضو بدون أب: يظهر كجذر فقط إذا عنده أبناء (جد/أب أصلي)
                return fatherIds.contains(member.id)
            }
            return byId[fatherId] == nil
        }.sortedForDisplay()

        let childrenMap = Dictionary(
            grouping: visible.compactMap { m in m.fatherId.map { (m, $0) } },
            by: { $0.1 }
        ).mapValues { pairs in pairs.map(\.0).sortedForDisplay() }

        return TreeCache(
            visible: visible,
            byId: byId,
            roots: roots,
            childrenMap: childrenMap,
            ids: Set(visible.map(\.id))
        )
    }

    /// تطبيق الكاش على @State — يحب يكون على MainActor.
    private func applyCache(_ cache: TreeCache) {
        cachedVisibleMembers = cache.visible
        cachedMemberById = cache.byId
        cachedRootMembers = cache.roots
        cachedChildrenByFatherId = cache.childrenMap
        cachedMemberIds = cache.ids
    }

    /// إعادة بناء سريعة (synchronous) — للتحميل الأول.
    private func rebuildCache() {
        applyCache(Self.computeCache(from: memberVM.allMembers))
    }

    /// إعادة بناء في خلفية — يمنع تجميد الواجهة عند 10K+ عضو.
    private func rebuildCacheBackground() async {
        let snapshot = memberVM.allMembers
        let cache = await Task.detached(priority: .userInitiated) {
            Self.computeCache(from: snapshot)
        }.value
        applyCache(cache)
    }

    // MARK: - بحث (منقول إلى TreeSearchOverlay)
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    DS.Color.background.ignoresSafeArea()

                    if cachedVisibleMembers.isEmpty {
                        emptyStateView
                            // حالة المزامنة/الفراغ تدخل بتلاشٍ وصعود مع أول ظهور
                            .dsCardCascade(1, appeared: chromeAppeared)
                    } else {
                        // حاوية بحجم الشاشة بالضبط + الكانفس كـ overlay لا يؤثر على تخطيطها —
                        // يمنع انزياح الشجرة يساراً عندما يكون الكانفس أعرض من الشاشة
                        // (الحاوية السابقة كانت تتمدد لحجم الكانفس فينحرف التمركز).
                        SwiftUI.Color.clear
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .overlay(alignment: .topLeading) {
                                ZStack(alignment: .topLeading) {
                                    // خطوط الأب وأبنائه — كل الصفوف موصولة (طلب المالك ٢٠٢٦-١٠-٠٤:
                                    // كان الخط يصل الصف الأول فقط). المسارات مبنية مع التخطيط.
                                    // TMP-ART-TRIAL: طبقات الخط ونقطة التفرّع بحسب الاتجاه («الحالي» = خط ونقطة كما كانا)
                                    let lineLayers = TreeArtLines.layers(art, width: 2, dark: colorScheme == .dark)
                                    let lineArt = art, lineDark = colorScheme == .dark
                                    Canvas { ctx, _ in
                                        for g in layout.connectors where drawOnId == nil || g.pid != drawOnId {
                                            TreeArtLines.stroke(&ctx, g.path, lineLayers)
                                            for d in g.dots {
                                                TreeArtLines.dot(&ctx, at: d, r: 3, art: lineArt, dark: lineDark)
                                            }
                                            if !g.kinPath.isEmpty {
                                                ctx.stroke(g.kinPath, with: .color(DS.Color.warning),
                                                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                                            }
                                        }
                                    }
                                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                    // خطوط آخر أب فُتح: تمتدّ من الأب نحو الأبناء، ثم تظهر نقاط التفرّع
                                    if let id = drawOnId, let g = layout.connectors.first(where: { $0.pid == id }) {
                                        ZStack(alignment: .topLeading) {   // TMP-ART-TRIAL: نفس طبقات الخط
                                            ForEach(Array(lineLayers.enumerated()), id: \.offset) { _, l in
                                                ConnectorPathShape(path: l.dy == 0 ? g.path : g.path.offsetBy(dx: 0, dy: l.dy))
                                                    .trim(from: 0, to: drawProgress)
                                                    .stroke(l.color, style: l.style)
                                            }
                                        }
                                            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                        Canvas { ctx, _ in
                                            for d in g.dots {
                                                TreeArtLines.dot(&ctx, at: d, r: 3, art: lineArt, dark: lineDark)
                                            }
                                            if !g.kinPath.isEmpty {
                                                ctx.stroke(g.kinPath, with: .color(DS.Color.warning),
                                                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                                            }
                                        }
                                        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                        .opacity(Double(max(0, (drawProgress - 0.8) / 0.2)))
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                    }
                                    // العُقد — نفس شكل TreeMemberNode الدائري (بلا تغيير)
                                    ForEach(cachedVisibleMembers.filter { layout.positions[$0.id] != nil }, id: \.id) { m in
                                        canvasNode(m)
                                            .transition(nodeEntrance(for: m))
                                    }
                                }
                                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                .scaleEffect(scale, anchor: .topLeading)
                                .offset(offset)
                            }
                        // الكانفس مثبّت LTR → اتجاه السحب صحيح في واجهة RTL
                        .environment(\.layoutDirection, .leftToRight)
                        .contentShape(Rectangle())
                        .clipped()
                        .gesture(dragGesture)
                        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { handleDoubleTap(at: $0.location) })
                        .modifier(TreePinchZoomModifier(scale: $scale, baseScale: $baseScale,
                                                        offset: $offset, baseOffset: $baseOffset,
                                                        userInteracted: $userInteracted, clamp: clampOffset))
                        .onAppear {
                            viewport = geometry.size
                            if activePath.isEmpty, let root = primaryRootMember { activePath = [root.id] }
                            let L = rebuildLayout()
                            if !userInteracted { fitCanvas(in: geometry.size, layout: L) }
                        }
                        .onChange(of: geometry.size) { newSize in
                            // تدوير الشاشة: أعد ضبط موضع الشجرة للاتجاه الجديد (طلب المالك)
                            let orientationFlipped = (viewport.width > viewport.height) != (newSize.width > newSize.height)
                            viewport = newSize
                            if orientationFlipped {
                                // تدوير: أعد بناء التخطيط (عدد الأعمدة يتغيّر) ثم مركّز
                                // العقدة المفتوحة الحالية بمنتصف الشاشة تلقائياً (طلب المالك)
                                withAnimation(DS.Anim.smooth) {
                                    let L = rebuildLayout()
                                    fitCanvas(in: newSize, layout: L)
                                    if let focus = breadcrumbChain.last ?? primaryRootMember {
                                        centerOn(focus.id, in: L, verticalAnchor: 0.5)
                                    }
                                }
                            } else if !userInteracted {
                                fitCanvas(in: newSize, layout: layout)
                            }
                        }
                    }

                    if verticalSizeClass == .compact {
                        // ── الوضع الأفقي: بلا هيدر — شريط المسار بمكانه أعلى الشاشة فقط ──
                        VStack(spacing: DS.Spacing.sm) {
                            if showSearch {
                                TreeSearchOverlay(
                                    onSelect: { member in selectMemberFromSearch(member) },
                                    autoFocus: true,
                                    onClose: { withAnimation(DS.Anim.snappy) { showSearch = false } },
                                    showFiltersWhenEmpty: true
                                )
                            } else if breadcrumbChain.count > 1 {
                                breadcrumbStrip
                                    .padding(.horizontal, DS.Spacing.sm)
                                    .padding(.vertical, 3)
                                    .background(glassCardBackground)
                                    .modifier(TreeArtSkin(art: art, radius: DS.Radius.lg, compact: true, glassBacked: true))   // TMP-ART-TRIAL
                                    .overlay(glassCardStroke)
                                    .dsSubtleShadow()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        .dsCardCascade(0, appeared: chromeAppeared)
                        .zIndex(101)

                        // البار الجانبي — نفس أدوات البار العلوي عمودياً (طلب المالك)
                        landscapeSideToolbar
                            // يدخل بعد شريط المسار (نفس تتالي البطاقات)
                            .dsCardCascade(1, appeared: chromeAppeared)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.leading, DS.Spacing.sm)
                            .zIndex(101)
                    } else {
                        VStack(spacing: DS.Spacing.sm) {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("شجرة العائلة", "Family Tree"),
                            subtitle: "\(cachedVisibleMembers.count) " + L10n.t("فرد", "members"),
                            icon: "leaf.fill",
                            backgroundGradient: AppSection.tree.gradient,
                            subtitleChip: true
                        )

                        // تحت الهيدر: إمّا البحث (مع الفلاتر) أو الشريط الموحّد
                        // (أدوات + شريط المسار مدمجين في بطاقة واحدة مدمّجة).
                        Group {
                            if showSearch {
                                TreeSearchOverlay(
                                    onSelect: { member in selectMemberFromSearch(member) },
                                    autoFocus: true,
                                    onClose: { withAnimation(DS.Anim.snappy) { showSearch = false } },
                                    showFiltersWhenEmpty: true
                                )
                            } else {
                                VStack(spacing: 4) {
                                    classicToolbarRow

                                    // شريط المسار مدمج داخل نفس البطاقة — يظهر عند التعمق فقط
                                    if breadcrumbChain.count > 1 {
                                        DS.Color.mutedBackground
                                            .frame(height: 1)
                                            .padding(.horizontal, DS.Spacing.xs)
                                        breadcrumbStrip
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, 3)
                                // مادة مخففة — مائلة للشفافية لكن مو شفافة بالكامل
                                .background(glassCardBackground)
                                .modifier(TreeArtSkin(art: art, radius: DS.Radius.lg, compact: true, glassBacked: true))   // TMP-ART-TRIAL
                                .overlay(glassCardStroke)
                                .dsSubtleShadow()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        // الهيدر ثابت (مثل بقية التبويبات)، وبطاقة الأدوات تدخل تحته أولاً —
                        // مرة مع أول ظهور للتبويب. «تقليل الحركة»: تلاشٍ فقط
                        .dsCardCascade(0, appeared: chromeAppeared)
                        }
                        .zIndex(101)
                    }

                    if !cachedVisibleMembers.isEmpty {
                        overlayTools

                        // بانر صلة القرابة
                        if let banner = kinshipBanner {
                            VStack {
                                HStack(spacing: DS.Spacing.sm) {
                                    TrialArt(make: { ArtDispatch.stateIcon($0, icon: "person.2.fill", tint: AppSection.tree.ink, size: 30) }) {   // TMP-ART-TRIAL
                                        Image(systemName: "person.2.fill")
                                            .font(DS.Font.scaled(16, weight: .bold))
                                    }
                                    Text(banner)
                                        .font(DS.Font.calloutBold)
                                    Spacer()
                                    Button {
                                        withAnimation(DS.Anim.snappy) {
                                            kinshipBanner = nil
                                            kinshipHighlightedIds = []
                                            searchedMemberID = nil
                                            userInteracted = false
                                            if let root = primaryRootMember { activePath = [root.id] }
                                            let L = rebuildLayout()
                                            fitCanvas(in: viewport, layout: L)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(DS.Font.scaled(18))
                                            .foregroundColor(DS.Color.textOnPrimary.opacity(0.7))
                                    }
                                }
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)
                                .background(AppSection.tree.gradient)
                                .modifier(TreeArtSkin(art: art, radius: DS.Radius.lg, onFill: true))   // TMP-ART-TRIAL
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.sm)
                                .shadow(color: AppSection.tree.fill.opacity(0.3), radius: 8, y: 4)
                                // «تقليل الحركة»: تلاشٍ بلا انزلاق
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))

                                Spacer()
                            }
                        }
                    }
                }
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .dsAlert(L10n.t("حسابك غير مربوط بالشجرة بعد", "Your account isn't linked to the tree yet"),
                     isPresented: $showNotInTree) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t("طلب انضمامك عند الإدارة لربط حسابك بمكانك في الشجرة. بعد الربط يأخذك «موقعي» إلى اسمك مباشرة.",
                            "Your join request is with the admins to link your account to your place in the tree. After that, «Me» takes you straight to your name."))
            }
            // تفاصيل العضو: مربّع بالمنتصف قابل للتوسّع بدل الشيت (طلب المالك)
            .fullScreenCover(item: $selectedMember) { member in
                MemberDetailsView(member: member, centered: true)
                    .background(ClearPresentationBackground())
            }
            .transaction { t in
                // يظهر المربّع في مكانه بلا انزلاق من الأسفل
                // يظهر المربّع في مكانه بلا انزلاق — والإغلاق بلا انزلاق يتم داخل المربّع
                if selectedMember != nil { t.disablesAnimations = true }
            }
            .task {
                if cachedVisibleMembers.isEmpty {
                    rebuildCache()
                    currentLocationMemberID = authVM.currentUser?.id
                    // أول تحميل — نبدأ من الجذر بالمنتصف (نفس إعادة الوضع)
                    try? await Task.sleep(nanoseconds: TreeConst.shortDelay)
                    resetToTopRoot(animated: false)
                }
            }
            .onDisappear {
                // إلغاء أي highlight tasks عالقة لتفادي memory leaks عند التنقل السريع
                highlightTask?.cancel()
                highlightTask = nil
            }
            // «أنت هنا» دائم — يتبع حساب المستخدم الحالي
            .onChange(of: authVM.currentUser?.id) { newId in
                currentLocationMemberID = newId
            }
            .onChange(of: memberVM.membersVersion) { _ in
                Task {
                    let snapshot = memberVM.allMembers
                    let cache = await Task.detached(priority: .userInitiated) {
                        Self.computeCache(from: snapshot)
                    }.value
                    withAnimation(DS.Anim.snappy) {
                        applyCache(cache)
                        if activePath.isEmpty, let root = cache.roots.first { activePath = [root.id] }
                        let L = rebuildLayout()
                        if !userInteracted { fitCanvas(in: viewport, layout: L) }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDeleted)) { _ in
                // إغلاق شاشة التفاصيل تلقائياً بعد حذف العضو
                withAnimation(DS.Anim.snappy) {
                    selectedMember = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMemberInTree)) { note in
                // مزامنة الشجرة مع الشيت — التحريك فقط دون لمس selectedMember
                // (الشيت يبقى مفتوح ومحتواه يتحدث داخلياً عبر currentMemberId)
                guard let info = note.userInfo,
                      let memberId = info["memberId"] as? UUID,
                      let target = cachedMemberById[memberId] ?? memberVM.member(byId: memberId) else { return }
                selectMemberFromSearch(target)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKinshipPath)) { note in
                guard let info = note.userInfo,
                      let memberId = info["memberId"] as? UUID,
                      let relationship = info["relationship"] as? String else { return }

                // بناء مسار كامل من الجذر للعضو الممسوح
                var fullPath = Set<UUID>()

                // مسار العضو الممسوح من الجذر
                var memberAncestors: [UUID] = []
                var current = cachedMemberById[memberId]
                while let c = current {
                    fullPath.insert(c.id)
                    memberAncestors.append(c.id)
                    if let fid = c.fatherId { current = cachedMemberById[fid] } else { current = nil }
                }

                // مسار المستخدم الحالي من الجذر
                var myAncestors: [UUID] = []
                if let myId = authVM.currentUser?.id {
                    var myCurrent = cachedMemberById[myId]
                    while let c = myCurrent {
                        fullPath.insert(c.id)
                        myAncestors.append(c.id)
                        if let fid = c.fatherId { myCurrent = cachedMemberById[fid] } else { myCurrent = nil }
                    }
                }

                // حساب الجد المشترك — أقرب أب مشترك بين الاثنين
                let memberSet = Set(memberAncestors)
                let commonAncestor = myAncestors.first { memberSet.contains($0) }

                // إضافة IDs القرابة إذا موجودة
                if let pathIds = info["pathIds"] as? [UUID] {
                    fullPath.formUnion(pathIds)
                }

                // فتح كل الفروع بالمسار + هايلايت
                withAnimation(.easeInOut(duration: 0.3)) {
                    activePath = fullPath
                    kinshipHighlightedIds = fullPath
                    searchedMemberID = memberId
                    kinshipBanner = relationship
                }

                // تصغير الزوم لإظهار المسار كامل + التمركز على الجد المشترك (كانفس)
                let scrollToId = commonAncestor ?? memberId
                userInteracted = true
                withAnimation(.easeInOut(duration: 0.4)) {
                    scale = TreeConst.kinshipScale
                    baseScale = TreeConst.kinshipScale
                    fittedScale = TreeConst.kinshipScale
                    let L = rebuildLayout()
                    centerOn(scrollToId, in: L)
                }

                // إخفاء البانر والهايلايت بعد 12 ثانية
                Task {
                    try? await Task.sleep(nanoseconds: TreeConst.kinshipBannerDuration)
                    withAnimation(DS.Anim.snappy) {
                        kinshipBanner = nil
                        kinshipHighlightedIds = []
                        rebuildLayout()
                    }
                }
            }
            // البحث منقول إلى TreeSearchOverlay — لا يعيد رسم الشجرة عند الكتابة
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    func getFullLineage(for member: FamilyMember, lookup: [UUID: FamilyMember]) -> String {
        var name = member.firstName
        var current = member
        var depth = 0
        var visited: Set<UUID> = [member.id]
        while let fatherId = current.fatherId,
              let father = lookup[fatherId],
              !visited.contains(father.id),
              depth < 5 {
            name += " " + father.firstName
            current = father
            visited.insert(father.id)
            depth += 1
        }
        return name
    }

    private func selectMemberFromSearch(_ member: FamilyMember) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searchedMemberID = member.id
        var ancestors = Set<UUID>()
        var currentParentId = member.fatherId
        var visited = Set<UUID>()
        while let pId = currentParentId {
            if visited.contains(pId) { break }
            visited.insert(pId)
            ancestors.insert(pId)
            currentParentId = cachedMemberById[pId]?.fatherId
        }
        ancestors.insert(member.id)
        activePath = ancestors
        userInteracted = true
        withAnimation(.easeInOut(duration: 0.35)) {
            let L = rebuildLayout()
            centerOn(member.id, in: L)
        }
    }

    private func centerOnMember(_ member: FamilyMember, highlight: Bool = true, includeFocusedMemberInPath: Bool = true) {
        var ancestors = Set<UUID>()
        var currentParentId = member.fatherId
        var visited = Set<UUID>()
        while let pId = currentParentId {
            if visited.contains(pId) { break }
            visited.insert(pId)
            ancestors.insert(pId)
            currentParentId = cachedMemberById[pId]?.fatherId
        }
        if includeFocusedMemberInPath { ancestors.insert(member.id) }
        activePath = ancestors
        searchedMemberID = highlight ? member.id : nil
        userInteracted = true
        withAnimation(.easeInOut(duration: 0.35)) {
            let L = rebuildLayout()
            centerOn(member.id, in: L)
        }

        // إزالة التظليل بعد ٥ ثوانٍ
        if highlight {
            highlightTask?.cancel()
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: TreeConst.highlightDuration)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { searchedMemberID = nil }
            }
        }
    }

    private func resetToTopRoot(animated: Bool = true) {
        guard let root = primaryRootMember else { return }
        // الجذر فقط مفتوح — الأبناء يظهرون، وأبناؤهم لما يضغط المستخدم
        userInteracted = false
        activePath = [root.id]
        searchedMemberID = nil
        let L = rebuildLayout()
        if animated {
            withAnimation(.easeInOut(duration: 0.4)) { fitCanvas(in: viewport, layout: L) }
        } else {
            fitCanvas(in: viewport, layout: L)
        }
    }

    // MARK: - صف الأدوات تحت الهيدر — مطابق للتفرّع (بحث / البداية / موقعي) أيقونات فقط
    /// خلفية البطاقة الزجاجية الموحّدة (مادة 75%)
    @ViewBuilder
    private var glassCardBackground: some View {
        // iOS 26/27: زجاج سائل؛ الأقدم: مادة 75%
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.75)
        }
    }
    private var glassCardStroke: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .stroke(DS.Color.mutedBackground.opacity(0.7), lineWidth: 1)
    }

    /// بار جانبي عمودي للوضع الأفقي — نفس أدوات البار العلوي (طلب المالك)
    private var landscapeSideToolbar: some View {
        VStack(spacing: DS.Spacing.xs) {
            Button {
                withAnimation(DS.Anim.smooth) { showSearch = true }
            } label: {
                toolbarIconButton(icon: "magnifyingglass", compact: true)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("بحث", "Search"))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                resetToTopRoot()
            } label: {
                toolbarIconButton(icon: "house.fill", compact: true)
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("البداية", "Start"))

            if let treeTab {
                VStack(spacing: 4) {
                    sideTabChip(L10n.t("العائلة", "Family"), idx: 0, treeTab: treeTab)
                    sideTabChip(L10n.t("النساء", "Women"), idx: 1, treeTab: treeTab)
                }
            }

            if authVM.currentUser != nil {
                Button {
                    if let currentUserID = authVM.currentUser?.id,
                       let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID),
                       cachedMemberById[currentUserID] != nil {
                        currentLocationMemberID = userMember.id
                        centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                    } else {
                        showNotInTree = true
                    }
                } label: {
                    toolbarIconButton(icon: "location.fill", compact: true)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("موقعي", "Me"))
            }
        }
        .padding(4)
        .background(glassCardBackground)
        .modifier(TreeArtSkin(art: art, radius: DS.Radius.lg, compact: true, glassBacked: true))   // TMP-ART-TRIAL
        .overlay(glassCardStroke)
        .dsSubtleShadow()
    }

    private func sideTabChip(_ title: String, idx: Int, treeTab: Binding<Int>) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { treeTab.wrappedValue = idx }
        } label: {
            Text(title)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(treeTab.wrappedValue == idx ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                .padding(.horizontal, 5)
                .frame(minWidth: 40, minHeight: 20)
                .background(Capsule().fill(treeTab.wrappedValue == idx ? AppSection.tree.fill : DS.Color.surface.opacity(0.8)))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private var classicToolbarRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            // الترتيب: بحث → البداية → تبويب [عائلة/نساء] → موقعي
            Button {
                withAnimation(DS.Anim.smooth) { showSearch = true }
            } label: {
                toolbarIconButton(icon: "magnifyingglass")
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("بحث", "Search"))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                resetToTopRoot()
            } label: {
                toolbarIconButton(icon: "house.fill")
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("البداية", "Start"))

            Spacer()

            // التبويب [شجرة العائلة / النساء] بالنص
            if let treeTab {
                FamilyTreeTabBar(selection: treeTab)
            }

            Spacer()

            // زر موقعي — آخر شي
            if authVM.currentUser != nil {
                Button {
                    if let currentUserID = authVM.currentUser?.id,
                       let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID) {
                        // التمييز «أنت هنا» دائم — الزر يفتح المسار ويتمركز فقط
                        currentLocationMemberID = userMember.id
                        centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                    }
                } label: {
                    toolbarIconButton(icon: "location.fill")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("موقعي", "Me"))
            }
        }
    }

    /// زر دائري بأيقونة — تضليل خفيف (مو شفاف 100%).
    private func toolbarIconButton(icon: String, color: Color = AppSection.tree.ink, compact: Bool = false) -> some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(compact ? 12 : 14, weight: .bold))
            .foregroundColor(color)
            .frame(width: compact ? 27 : 34, height: compact ? 27 : 34)                         // بار مدمّج أصغر
            .background(DS.Color.surface.opacity(0.8), in: Circle())   // أغمق (طلب المالك)
            .overlay(Circle().strokeBorder(AppSection.tree.ink.opacity(0.15), lineWidth: 1))
            .dsSubtleShadow()
            .contentShape(Circle())
    }

    // MARK: - شريط المسار (فتات النسب) — يوضّح وين أنت وترجع لأي مستوى بضغطة
    /// سلسلة النسب المفتوحة حالياً: الجذر ← ... ← أعمق عقدة مفتوحة.
    private var breadcrumbChain: [FamilyMember] {
        guard let root = primaryRootMember, activePath.contains(root.id) else { return [] }
        var chain = [root]
        var cur = root
        var guardCounter = 0
        while guardCounter < 40 {
            guardCounter += 1
            let kids = cachedChildrenByFatherId[cur.id] ?? []
            guard let next = kids.first(where: { activePath.contains($0.id) && $0.id != cur.id }) else { break }
            chain.append(next)
            cur = next
        }
        return chain
    }

    /// الرجوع لمستوى معيّن: يطوي كل ما تحته ويتمركز عليه.
    private func jumpToBreadcrumb(_ member: FamilyMember) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var rm = Set<UUID>()
        collectDescendants(of: member.id, into: &rm)
        activePath.subtract(rm)
        activePath.insert(member.id)
        searchedMemberID = nil
        userInteracted = true
        withAnimation(.easeInOut(duration: 0.3)) {
            let L = rebuildLayout()
            centerOn(member.id, in: L)
        }
    }

    /// شريط المسار المدمّج — نسخة أصغر مدمجة داخل بطاقة الأدوات (يظهر عند التعمق فقط).
    private var breadcrumbStrip: some View {
        // يتحرّك مع المسار (طلب المالك): آخر اسم يبقى ظاهراً عند التعمّق وعند «موقعي»
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(breadcrumbChain.enumerated()), id: \.element.id) { idx, m in
                        let isLast = idx == breadcrumbChain.count - 1
                        HStack(spacing: 2) {
                            Button {
                                jumpToBreadcrumb(m)
                            } label: {
                                HStack(spacing: 3) {
                                    if idx == 0 {
                                        Image(systemName: "house.fill")
                                            .font(DS.Font.scaled(isLandscapeMode ? 11 : 8, weight: .bold))
                                    }
                                    Text(m.firstName.isEmpty ? "—" : m.firstName)
                                        .font(DS.Font.scaled(isLandscapeMode ? 13 : 10, weight: isLast ? .heavy : .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(isLast ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                                .padding(.horizontal, isLandscapeMode ? 10 : 6)
                                .padding(.vertical, isLandscapeMode ? 5 : 1)
                                .background(isLast ? AnyShapeStyle(AppSection.tree.fill) : AnyShapeStyle(DS.Color.surface), in: Capsule())
                                .overlay(Capsule().stroke(AppSection.tree.ink.opacity(isLast ? 0 : 0.2), lineWidth: 1))
                            }
                            .buttonStyle(DSScaleButtonStyle())
                            .accessibilityLabel(L10n.t("الرجوع إلى \(m.firstName)", "Back to \(m.firstName)"))

                            if !isLast {
                                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                    .font(DS.Font.scaled(isLandscapeMode ? 9 : 7, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                        .id(m.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
            }
            // يُعاد التمرير كلما تغيّر آخر اسم (وعند الظهور) بعد رسم العناصر —
            // مع مسار طويل (أكثر من ٧) كان التمرير يسبق الرسم فلا يصل للنهاية
            .task(id: breadcrumbChain.last?.id) {
                try? await Task.sleep(nanoseconds: 80_000_000)
                scrollBreadcrumbToEnd(proxy, animated: true)
                try? await Task.sleep(nanoseconds: 250_000_000)
                scrollBreadcrumbToEnd(proxy, animated: true)
            }
        }
        // «تقليل الحركة»: تلاشٍ بلا انزلاق
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    /// يمرّر شريط المسار حتى يظهر آخر اسم (الموقع الحالي)
    private func scrollBreadcrumbToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = breadcrumbChain.last?.id else { return }
        if animated {
            withAnimation(DS.Anim.snappy) { proxy.scrollTo(last, anchor: .trailing) }
        } else {
            proxy.scrollTo(last, anchor: .trailing)
        }
    }

    // MARK: - أداة التحديث — Glassy
    private var overlayTools: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Button(action: {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await memberVM.fetchAllMembers(force: true)
                            guard !Task.isCancelled else { return }
                            await rebuildCacheBackground()
                            resetToTopRoot()
                            withAnimation { isRefreshing = false }
                        }
                    }) {
                        if isRefreshing {
                            ProgressView()
                                .tint(AppSection.tree.ink)
                                .scaleEffect(0.7)
                                .frame(width: TreeConst.toolButtonSize, height: TreeConst.toolButtonSize)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                                .font(DS.Font.scaled(15, weight: .bold))
                                .foregroundColor(AppSection.tree.ink)
                                .frame(width: TreeConst.toolButtonSize, height: TreeConst.toolButtonSize)
                        }
                    }
                    // ضغطة ناعمة موحّدة (كان بلا إحساس بالضغط)
                    .buttonStyle(DSPressStyle())
                    .disabled(isRefreshing)
                    .accessibilityLabel(L10n.t("تحديث الشجرة", "Refresh tree"))
                }
                .dsGlass(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .modifier(TreeArtSkin(art: art, radius: DS.Radius.md, compact: true, glassBacked: true))   // TMP-ART-TRIAL
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.mutedBackground, lineWidth: 1)
                )
                .dsSubtleShadow()
                // الزر العائم يقفز آخراً بعد بطاقة الأدوات (مثل أزرار «+» العائمة)
                .modifier(TreeToolPop(shown: chromeAppeared))
                .padding(.bottom, DS.Spacing.xl)
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - محرّك الكانفس (إحداثيات مطلقة) — يصلّح الزوم المعطوب ويضيف خطوط ربط حقيقية

    /// نقر مزدوج: تكبير نحو نقطة اللمس، أو رجوع لملاءمة الشاشة إذا كان مكبّراً.
    private func handleDoubleTap(at location: CGPoint) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        userInteracted = true
        let zoomedIn = scale > fittedScale + 0.05
        let ns: CGFloat = zoomedIn ? fittedScale : min(TreeConst.maxScale, max(fittedScale * 2, 0.95))
        let r = scale > 0 ? ns / scale : 1
        withAnimation(.easeInOut(duration: 0.3)) {
            if zoomedIn {
                scale = ns; baseScale = ns
                offset = centeredOffset(scale: ns, in: viewport, layout: layout)
                baseOffset = offset
            } else {
                offset = clampOffset(CGSize(width: location.x - (location.x - offset.width) * r,
                                            height: location.y - (location.y - offset.height) * r))
                scale = ns; baseScale = ns; baseOffset = offset
            }
        }
    }

    /// إعادة حساب التخطيط من activePath الحالي وتخزينه.
    @discardableResult
    private func rebuildLayout() -> FamilyLayout {
        let L = computeLayout()
        layout = L
        return L
    }

    /// يحسب مواضع كل العقد المرئية بإحداثيات مطلقة (أبوي، صفوف بحدّ PER_ROW، بلا فصل جنسين).
    private func computeLayout() -> FamilyLayout {
        var L = FamilyLayout()
        guard let root = primaryRootMember else { return L }
        let cOf = cachedChildrenByFatherId
        let byId = cachedMemberById
        var sizeCache: [UUID: CGSize] = [:]
        var seen = Set<UUID>()

        func boxH(_ id: UUID) -> CGFloat {
            nodeBoxHeight(deceased: byId[id]?.isDeceased == true, hasKids: !((cOf[id] ?? []).isEmpty))
        }
        // الأبناء الظاهرون: العقدة يجب أن تكون في activePath، ثم نركّز على الفرع المفتوح (مثل السلوك السابق).
        func visKids(_ id: UUID) -> [FamilyMember] {
            guard activePath.contains(id) else { return [] }
            let all = (cOf[id] ?? []).filter { $0.id != id }
            if !kinshipHighlightedIds.isEmpty { return all.filter { kinshipHighlightedIds.contains($0.id) } }
            let focused = all.filter { activePath.contains($0.id) }
            return focused.isEmpty ? all : focused
        }
        func blockDims(_ boxes: [CGSize]) -> CGSize {
            var w: CGFloat = 0, h: CGFloat = 0, i = 0
            while i < boxes.count {
                let row = Array(boxes[i..<min(i + perRow(for: boxes.count), boxes.count)])
                let rowW = row.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(row.count - 1)
                let rowH = row.map(\.height).max() ?? 0
                w = max(w, rowW); h += (i > 0 ? ROW_GAP : 0) + rowH
                i += perRow(for: boxes.count)
            }
            // صفوف ملتفّة: مساحة العمود على الجانبين (بالتساوي فيبقى التمركز كما هو)
            if boxes.count > perRow(for: boxes.count) { w += SPINE_ROOM * 2 }
            return CGSize(width: w, height: h)
        }
        func measure(_ id: UUID) -> CGSize {
            let bh = boxH(id); L.heights[id] = bh
            if seen.contains(id) { return CGSize(width: NODE_W, height: bh) }
            seen.insert(id)
            let kids = visKids(id)
            if kids.isEmpty { let b = CGSize(width: NODE_W, height: bh); sizeCache[id] = b; return b }
            let childBlock = blockDims(kids.map { measure($0.id) })
            let b = CGSize(width: max(NODE_W, childBlock.width), height: bh + V_GAP + childBlock.height)
            sizeCache[id] = b; return b
        }
        var placed = Set<UUID>()
        func place(_ id: UUID, _ cx: CGFloat, _ top: CGFloat, _ d: Int) {
            if placed.contains(id) { return }
            placed.insert(id)
            L.positions[id] = CGPoint(x: cx - NODE_W / 2, y: top)
            L.depth[id] = d
            L.heights[id] = boxH(id)
            let kids = visKids(id)
            if kids.isEmpty { return }
            var rows: [[UUID]] = []
            var rowTop = top + boxH(id) + V_GAP
            let per = perRow(for: kids.count)
            var i = 0
            while i < kids.count {
                let rowKids = Array(kids[i..<min(i + per, kids.count)])
                let rowBoxes = rowKids.map { sizeCache[$0.id] ?? CGSize(width: NODE_W, height: boxH($0.id)) }
                let rowW = rowBoxes.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(rowBoxes.count - 1)
                let rowH = rowBoxes.map(\.height).max() ?? 0
                var x = cx - rowW / 2
                for (j, k) in rowKids.enumerated() {
                    place(k.id, x + rowBoxes[j].width / 2, rowTop, d + 1)
                    x += rowBoxes[j].width + H_GAP
                }
                rows.append(rowKids.map { $0.id })
                rowTop += rowH + ROW_GAP
                i += per
            }
            L.childRows[id] = rows
        }

        let rootBox = measure(root.id)
        place(root.id, CANVAS_PAD + rootBox.width / 2, CANVAS_PAD, 0)
        let width = rootBox.width + CANVAS_PAD * 2
        let height = rootBox.height + CANVAS_PAD * 2
        // مرآة أفقية → ترتيب الإخوة يمين‑لليسار (RTL) مثل تبويب النساء
        for (id, p) in L.positions { L.positions[id] = CGPoint(x: width - p.x - NODE_W, y: p.y) }
        L.size = CGSize(width: width, height: height)
        L.connectors = buildConnectors(L)
        return L
    }

    /// خطوط كل أب مع أبنائه — تُبنى مرة مع التخطيط بعد المرآة (الأكبر يميناً)، لا كل إطار.
    /// اختيار المالك ٢٠٢٦-١٠-٠٤ (كان الخط يصل الصف الأول وحده):
    ///  • صف واحد بثلاثة أبناء أو أقل: الأقواس القديمة من أسفل الأب إلى كل ابن.
    ///  • صف واحد أطول (أفقياً): خط أفقي في منتصف الفجوة ونزول لكل ابن.
    ///  • صفوف ملتفّة — «العمود»: خط أفقي فوق كل صف، وعمود على جهة الأكبر يصل الصفوف بخط الأب.
    private func buildConnectors(_ L: FamilyLayout) -> [ConnectorGroup] {
        typealias Kid = (id: UUID, x: CGFloat, top: CGFloat)
        let r = LINE_CORNER
        var groups: [ConnectorGroup] = []
        for (pid, ids) in L.childRows {
            guard let pp = L.positions[pid] else { continue }
            let fx = pp.x + NODE_W / 2
            let fy = pp.y + (L.heights[pid] ?? NODE_H_DEFAULT) - 2
            // كل صف: مركز كل ابن وأعلى دائرته، يساراً→يميناً
            let rows: [[Kid]] = ids.map { row in
                row.compactMap { id in L.positions[id].map { (id: id, x: $0.x + NODE_W / 2, top: $0.y + 4) } }
                    .sorted { $0.x < $1.x }
            }.filter { !$0.isEmpty }
            guard let first = rows.first else { continue }
            let kinFather = kinshipHighlightedIds.contains(pid)
            func isKin(_ id: UUID) -> Bool { kinFather && kinshipHighlightedIds.contains(id) }
            // خط كل صف: الأول في منتصف الفجوة بين الأب والصف، والتالية في منتصف الفجوة فوق صفّها
            let bus: [CGFloat] = rows.enumerated().map { i, row in
                let rowTop = (row.map(\.top).min() ?? fy) - 4
                return i == 0 ? (fy + rowTop) / 2 : rowTop - ROW_GAP / 2
            }
            let last = rows.count - 1
            var g = ConnectorGroup()
            g.pid = pid
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
            /// نزول ابن من خطّ صفّه + نقطة التفرّع
            func drop(_ k: Kid, _ y: CGFloat) {
                g.path.move(to: p(k.x, y)); g.path.addLine(to: p(k.x, k.top)); g.dots.append(p(k.x, y))
            }
            /// آخر الطريق: على خط الصف إلى الابن ثم نزول مدوّر إليه
            func land(_ path: inout Path, _ k: Kid, _ y: CGFloat) {
                path.addArc(tangent1End: p(k.x, y), tangent2End: p(k.x, k.top), radius: r)
                path.addLine(to: p(k.x, k.top))
            }

            // صف واحد بثلاثة أبناء أو أقل: الأقواس القديمة (نقاط تحكم بعيدة ٨٠٪ — قوس واضح)
            if rows.count == 1, first.count <= 3 {
                for k in first {
                    var c = Path()
                    let dy = k.top - fy
                    c.move(to: p(fx, fy))
                    c.addCurve(to: p(k.x, k.top), control1: p(fx, fy + dy * 0.8), control2: p(k.x, k.top - dy * 0.8))
                    g.path.addPath(c)
                    if isKin(k.id) { g.kinPath.addPath(c) }
                }
                groups.append(g); continue
            }
            // نزول الأب إلى خط الصف الأول
            g.path.move(to: p(fx, fy)); g.path.addLine(to: p(fx, bus[0]))

            if rows.count == 1 {
                // صف واحد أطول (أفقياً): خط أفقي بطرفين مدوّرين ينزلان لطرفي الصف، والوسط نزول مستقيم
                let a = first.first!, b = first.last!
                g.path.move(to: p(a.x, a.top))
                g.path.addArc(tangent1End: p(a.x, bus[0]), tangent2End: p(b.x, bus[0]), radius: r)
                land(&g.path, b, bus[0])
                for k in first.dropFirst().dropLast() { drop(k, bus[0]) }
                for k in first where isKin(k.id) {
                    g.kinPath.move(to: p(fx, fy))
                    if abs(k.x - fx) < 1 { g.kinPath.addLine(to: p(k.x, k.top)) }
                    else { g.kinPath.addLine(to: p(fx, bus[0] - r)); g.kinPath.addArc(tangent1End: p(fx, bus[0]), tangent2End: p(k.x, bus[0]), radius: r); land(&g.kinPath, k, bus[0]) }
                }
                groups.append(g); continue
            }

            // صفوف ملتفّة — «العمود» على جهة الأكبر (أول ابن في ترتيب التخطيط)
            let eldestX = ids.first?.first.flatMap { L.positions[$0] }.map { $0.x + NODE_W / 2 } ?? fx
            let eldestRight = eldestX >= fx
            let allX = rows.flatMap { $0.map(\.x) }
            let sx = eldestRight ? (allX.max() ?? fx) + NODE_W / 2 + SPINE_OUT
                                 : (allX.min() ?? fx) - NODE_W / 2 - SPINE_OUT
            // الابن الأبعد عن العمود في كل صف: إليه ينتهي خط الصف بانعطافة
            func far(_ row: [Kid]) -> Kid { eldestRight ? row.first! : row.last! }
            // الصف الأول ← العمود ← الصف الأخير
            let f0 = far(first), fl = far(rows[last])
            g.path.move(to: p(f0.x, f0.top))
            g.path.addArc(tangent1End: p(f0.x, bus[0]), tangent2End: p(sx, bus[0]), radius: r)
            g.path.addArc(tangent1End: p(sx, bus[0]), tangent2End: p(sx, bus[last]), radius: r)
            g.path.addArc(tangent1End: p(sx, bus[last]), tangent2End: p(fl.x, bus[last]), radius: r)
            land(&g.path, fl, bus[last])
            // الصفوف الوسطى: تفرّع من العمود
            if last > 1 {
                for i in 1..<last {
                    let fi = far(rows[i])
                    g.path.move(to: p(sx, bus[i]))
                    land(&g.path, fi, bus[i])
                }
            }
            for (i, row) in rows.enumerated() {
                let fi = far(row)
                for k in row where k.id != fi.id { drop(k, bus[i]) }
            }
            // طريق القرابة: الأب ← (العمود) ← خط الصف ← الابن
            for (i, row) in rows.enumerated() {
                for k in row where isKin(k.id) {
                    g.kinPath.move(to: p(fx, fy))
                    if i == 0 {
                        if abs(k.x - fx) < 1 { g.kinPath.addLine(to: p(k.x, k.top)); continue }
                        g.kinPath.addLine(to: p(fx, bus[0] - r))
                        g.kinPath.addArc(tangent1End: p(fx, bus[0]), tangent2End: p(k.x, bus[0]), radius: r)
                    } else {
                        g.kinPath.addLine(to: p(fx, bus[0] - r))
                        g.kinPath.addArc(tangent1End: p(fx, bus[0]), tangent2End: p(sx, bus[0]), radius: r)
                        g.kinPath.addArc(tangent1End: p(sx, bus[0]), tangent2End: p(sx, bus[i]), radius: r)
                        g.kinPath.addArc(tangent1End: p(sx, bus[i]), tangent2End: p(k.x, bus[i]), radius: r)
                    }
                    land(&g.kinPath, k, bus[i])
                }
            }

            groups.append(g)
        }
        return groups
    }

    /// دخول أبناء الأب المفتوح للتو: يكبرون من موضعهم تباعاً بعد امتداد الخط إليهم.
    private func nodeEntrance(for m: FamilyMember) -> AnyTransition {
        guard !reduceMotion, let fid = m.fatherId, fid == drawOnId,
              let idx = layout.childRows[fid]?.flatMap({ $0 }).firstIndex(of: m.id),
              let p = layout.positions[m.id], layout.size.width > 0, layout.size.height > 0
        else { return .opacity }
        let anchor = UnitPoint(x: (p.x + NODE_W / 2) / layout.size.width, y: p.y / layout.size.height)
        return .asymmetric(
            insertion: AnyTransition.scale(scale: 0.5, anchor: anchor)
                .combined(with: .opacity)
                .animation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.3 + Double(idx) * 0.07)),
            removal: .opacity)
    }

    /// عقدة واحدة بشكل TreeMemberNode الدائري، موضوعة بإحداثيات مطلقة.
    @ViewBuilder
    private func canvasNode(_ m: FamilyMember) -> some View {
        let p = layout.positions[m.id] ?? .zero
        let h = layout.heights[m.id] ?? NODE_H_DEFAULT
        TreeMemberNode(
            member: m,
            isExpanded: activePath.contains(m.id),
            searchedMemberID: $searchedMemberID,
            hasChildren: !((cachedChildrenByFatherId[m.id] ?? []).isEmpty),
            childrenCount: (cachedChildrenByFatherId[m.id] ?? []).count,
            showName: true,
            level: layout.depth[m.id] ?? 0,
            currentLocationMemberID: currentLocationMemberID,
            isKinshipHighlighted: kinshipHighlightedIds.contains(m.id),
            art: art,   // TMP-ART-TRIAL
            onTap: { selectedMember = m },
            onToggle: { toggleNode(m) }
        )
        .frame(width: NODE_W, height: h, alignment: .top)
        .position(x: p.x + NODE_W / 2, y: p.y + h / 2)
    }

    /// فتح/طيّ عقدة (نفس منطق التفرّع السابق) ثم تحريك الكاميرا.
    private func toggleNode(_ member: FamilyMember) {
        let kids = cachedChildrenByFatherId[member.id] ?? []
        guard !kids.isEmpty else { return }
        let wasExpanded = activePath.contains(member.id)
        let hasDeeper = kids.contains { activePath.contains($0.id) }
        if !wasExpanded {
            activePath.insert(member.id)
        } else if hasDeeper {
            var rm = Set<UUID>(); collectDescendants(of: member.id, into: &rm)
            activePath.subtract(rm); searchedMemberID = nil
        } else {
            var rm: Set<UUID> = [member.id]; collectDescendants(of: member.id, into: &rm)
            activePath.subtract(rm); searchedMemberID = nil
        }
        userInteracted = true
        let opening = !wasExpanded || hasDeeper
        let drawOn = !wasExpanded && !reduceMotion
        if drawOn { drawOnId = member.id; drawProgress = 0 }
        defer {
            if drawOn { withAnimation(.easeInOut(duration: 0.7).delay(0.15)) { drawProgress = 1 } }
        }
        withAnimation(DS.Anim.smooth) {
            let L = rebuildLayout()
            // التمركز على العقدة بعد كل توسيع/طي — الشجرة تبقى بالمنتصف دائماً.
            // عند الفتح يرتفع الأب حسب عدد صفوف أبنائه: صف واحد 42%،
            // صفّان 34%، ثلاثة صفوف وأكثر (٧+ أبناء) 26% — ليظهر الصف الأخير.
            if opening {
                let per = perRow(for: kids.count)
                let rowCount = (kids.count + per - 1) / per
                adaptiveCenter(on: member.id, rowCount: rowCount, in: L)
            } else {
                // عند الطي: تمركز على الأب بنفس المنطق التكيّفي حسب صفوف أبنائه —
                // الشجرة تنزل ويظهر جميع الإخوة (طلب المالك)
                let pid = member.fatherId ?? member.id
                let sibs = cachedChildrenByFatherId[pid] ?? []
                let per2 = perRow(for: sibs.count)
                let rowCount = max(1, (sibs.count + per2 - 1) / per2)
                adaptiveCenter(on: pid, rowCount: rowCount, in: L)
            }
        }
    }

    private func collectDescendants(of parentId: UUID, into set: inout Set<UUID>) {
        for child in cachedChildrenByFatherId[parentId] ?? [] where child.id != parentId {
            if set.insert(child.id).inserted {
                collectDescendants(of: child.id, into: &set)
            }
        }
    }

    /// تمركز تكيّفي بعد التوسيع/الطي — يراعي اتجاه الشاشة:
    /// عمودي: نفس النقاط المعتادة · أفقي: زوم أبعد + نقاط أعلى ليظهر الأب وكل صفوف
    /// الأبناء داخل الارتفاع القصير (طلب المالك)
    private func adaptiveCenter(on id: UUID, rowCount: Int, in L: FamilyLayout) {
        if viewport.width > viewport.height {
            let s: CGFloat = rowCount >= 3 ? 0.45 : (rowCount == 2 ? 0.55 : 0.7)
            scale = s; baseScale = s
            let anchor: CGFloat = rowCount >= 3 ? 0.18 : (rowCount == 2 ? 0.24 : 0.32)
            centerOn(id, in: L, verticalAnchor: anchor)
        } else {
            let anchor: CGFloat = rowCount >= 3 ? 0.26 : (rowCount == 2 ? 0.34 : 0.42)
            centerOn(id, in: L, verticalAnchor: anchor)
        }
    }

    // ─── الكاميرا (offset) ───

    /// يُمركز عقدة في الشاشة — أفقياً بالمنتصف دائماً، وعمودياً عند `verticalAnchor`
    /// (0.5 = منتصف تماماً، 0.42 = أعلى قليلاً لتظهر الأبناء تحتها بعد التوسيع).
    private func centerOn(_ id: UUID, in L: FamilyLayout, verticalAnchor: CGFloat = 0.5) {
        guard let p = L.positions[id], viewport.width > 0 else { return }
        userInteracted = true
        let s = scale
        let h = L.heights[id] ?? NODE_H_DEFAULT
        let cx = (p.x + NODE_W / 2) * s
        let cy = (p.y + h / 2) * s
        offset = clampOffset(CGSize(width: viewport.width / 2 - cx, height: viewport.height * verticalAnchor - cy))
        baseOffset = offset
    }

    /// يلائم الشجرة للشاشة ويوسّطها أفقياً وعمودياً (بمنتصف المساحة تحت الهيدر).
    private func fitCanvas(in size: CGSize, layout L: FamilyLayout) {
        guard L.size.width > 0, size.width > 0 else { return }
        // الوضع الأفقي: سقف زوم أصغر — الارتفاع قصير فلازم يبان الجذر وأبناؤه
        // بأسمائهم كاملة فوق البار السفلي
        let maxS: CGFloat = size.width > size.height ? 0.65 : 1.1
        let s = max(0.28, min(maxS, (size.width - 48) / L.size.width))
        scale = s; baseScale = s; fittedScale = s
        offset = centeredOffset(scale: s, in: size, layout: L)
        baseOffset = offset
    }

    /// إزاحة التوسيط: الكانفس بالمنتصف أفقياً، والجذر بمنتصف الشاشة عمودياً
    /// (نفس سلوك المحرّك السابق — scrollTo(root, anchor: .center)).
    private func centeredOffset(scale s: CGFloat, in size: CGSize, layout L: FamilyLayout) -> CGSize {
        var rootCY: CGFloat = CANVAS_PAD + NODE_H_DEFAULT / 2
        if let root = primaryRootMember, let p = L.positions[root.id] {
            rootCY = p.y + (L.heights[root.id] ?? NODE_H_DEFAULT) / 2
        }
        // عمودي: 0.37 (رفع الجذر — طلب المالك) · أفقي: 0.30 ليتّسع الجيل الأول بأسمائه
        let rootAnchor: CGFloat = size.width > size.height ? 0.30 : 0.37
        let y = size.height * rootAnchor - rootCY * s
        return CGSize(width: (size.width - L.size.width * s) / 2, height: y)
    }

    /// يُبقي الشجرة داخل حدود معقولة مع هامش overscroll.
    private func clampOffset(_ o: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return o }
        let overscroll: CGFloat = 120
        let contentW = layout.size.width * scale
        let contentH = layout.size.height * scale
        func clampAxis(_ v: CGFloat, content: CGFloat, view: CGFloat, topHi: CGFloat) -> CGFloat {
            if content <= view {
                let slack = view - content
                return min(max(v, -overscroll), slack + overscroll)
            }
            let lo = view - content - overscroll
            return min(max(v, lo), topHi)
        }
        return CGSize(
            width: clampAxis(o.width, content: contentW, view: viewport.width, topHi: overscroll),
            height: clampAxis(o.height, content: contentH, view: viewport.height, topHi: viewport.height * 0.5)
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                userInteracted = true
                offset = clampOffset(CGSize(width: baseOffset.width + v.translation.width,
                                            height: baseOffset.height + v.translation.height))
            }
            .onEnded { v in
                // زخم مثل ScrollView: يكمل حسب السرعة ثم يستقر داخل الحدود.
                let projected = CGSize(width: baseOffset.width + v.predictedEndTranslation.width,
                                       height: baseOffset.height + v.predictedEndTranslation.height)
                let target = clampOffset(projected)
                withAnimation(.easeOut(duration: 0.4)) { offset = target }
                baseOffset = target
            }
    }

    // MARK: - حالة فارغة
    @ViewBuilder
    private var emptyStateView: some View {
        if memberVM.membersLoadFailed {
            DSErrorState(retryAction: {
                memberVM.membersLoadFailed = false
                Task {
                    await memberVM.fetchAllMembers(force: true)
                    guard !Task.isCancelled else { return }
                    await rebuildCacheBackground()
                    resetToTopRoot()
                }
            })
        } else if memberVM.membersVersion > 0 && !memberVM.isLoading {
            // التحميل تم فعلاً لكن لا يوجد أعضاء — رسالة مختلفة عن "جاري المزامنة"
            DSEmptyState(
                icon: "leaf",
                title: L10n.t("لا يوجد أفراد في الشجرة بعد", "No family members yet"),
                subtitle: L10n.t("اسحب للتحديث أو تواصل مع الإدارة", "Pull to refresh or contact the admin"),
                buttonTitle: L10n.t("تحديث", "Refresh"),
                buttonAction: {
                    Task {
                        await memberVM.fetchAllMembers(force: true)
                        guard !Task.isCancelled else { return }
                        await rebuildCacheBackground()
                        resetToTopRoot()
                    }
                },
                buttonIcon: "arrow.clockwise"
            )
        } else {
            VStack(spacing: DS.Spacing.xl) {
                Spacer()

                // غافة المربّع نفسها تتنفّس أثناء المزامنة، ونقطة ذهبية تصعد من الجذور إلى الثمرة فتتوهّج
                // (طلب المالك ٢٠٢٦-١٠-٠٥ «أبسط وأقوى وباعتدال») — المشهد هو مؤشّر التقدّم
                TrialArt(make: { ArtDispatch.treeLoading($0) }) {   // TMP-ART-TRIAL
                    FTSceneCanvas { ctx, size, t, dark in
                        FTPlaceScenes.drawTreeGrowth(in: &ctx, size: size, t: t, dark: dark)
                    }
                }
                .frame(width: 240, height: 200)

                Text(L10n.t("جاري مزامنة الشجرة...", "Syncing tree..."))
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

}

/// زر الشجرة العائم يقفز آخراً — نفس قفزة DSIconPop (تكبير بنابض من ٠٫٥٥) وتأخير أزرار «+»
/// العائمة، لكن يقوده علم ظهور التبويب فلا يتكرر مع التبديل «العائلة/النساء».
/// «تقليل الحركة»: تلاشٍ فقط.
private struct TreeToolPop: ViewModifier {
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : DSMotion.iconFromScale)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? DSMotion.fade : DSMotion.iconPop.delay(0.4), value: shown)
    }
}


// MARK: - 3. عقدة الفرد — Liquid Glass
struct TreeMemberNode: View {
    let member: FamilyMember
    let isExpanded: Bool
    @Binding var searchedMemberID: UUID?
    let hasChildren: Bool
    let childrenCount: Int
    let showName: Bool
    var level: Int = 0
    let currentLocationMemberID: UUID?
    var isKinshipHighlighted: Bool = false
    /// TMP-ART-TRIAL: اتجاه الرسوم — «الحالي» = العقدة كما كانت
    var art: ArtTrial = .emblem
    let onTap: () -> Void
    let onToggle: () -> Void
    @State private var shouldLoadImage = false
    @State private var isPulsing = false
    @State private var arrowGlow = false

    private var isCurrentLocationMember: Bool {
        member.id == currentLocationMemberID
    }

    // لون دائرة الصورة — ذهبي إذا جزء من مسار القرابة
    private var nodeAccentColor: Color {
        if isKinshipHighlighted {
            return DS.Color.warning
        }
        if member.isDeceased == true {
            return DS.Color.deceased
        }
        switch member.role {
        case .owner: return DS.Color.ownerRole
        case .admin: return DS.Color.adminRole
        case .monitor: return DS.Color.monitorRole
        case .supervisor: return DS.Color.supervisorRole
        default: return DS.Color.male   // عقدة العضو: كحلي ثابت (معنى) — لا يتبع لون القسم
        }
    }

    // لون الإطار = نفس لون الدائرة
    private var borderColor: Color { nodeAccentColor }

    // تدرج العقدة
    private var nodeGradient: LinearGradient {
        LinearGradient(
            colors: [nodeAccentColor, nodeAccentColor.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [nodeAccentColor.opacity(0.9), nodeAccentColor.opacity(0.4)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
            // الوضع التفاعلي — دائري
            VStack(spacing: 0) {
                // الصورة: توسيع/طي الأبناء — وبلا أبناء تفتح التفاصيل (طلب المالك)
                Button {
                    if hasChildren {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onToggle()
                    } else {
                        onTap()
                    }
                } label: {
                    ZStack {
                        // الدائرة الرئيسية — ظل ملوّن ناعم بلون الرتبة (عمق أنظف)
                        // TMP-ART-TRIAL: مع رسم الاتجاه تصير الدائرة أرضية فاتحة بلون الرتبة والرسم فوقها
                        Circle()
                            .fill(art == .emblem ? AnyShapeStyle(nodeGradient)
                                                 : AnyShapeStyle(nodeAccentColor.opacity(0.14)))
                            .background(Circle().fill(art == .emblem ? Color.clear : DS.Color.surface))
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .shadow(color: nodeAccentColor.opacity(member.isDeceased == true ? 0.12 : 0.26),
                                    radius: 10, x: 0, y: 5)

                        // الصورة أو الأيقونة
                        if shouldLoadImage, let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                if art == .emblem {
                                    Image(systemName: "person.fill")
                                        .font(DS.Font.scaled(30))
                                        .foregroundColor(DS.Color.overlayTextMuted)
                                } else {
                                    avatarArt   // TMP-ART-TRIAL
                                }
                            }
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .clipShape(Circle())
                            .saturation(member.isDeceased == true ? 0 : 1)   // المتوفّى: صورة غير ملوّنة
                        } else if art != .emblem {
                            avatarArt   // TMP-ART-TRIAL
                        } else {
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44)
                                .foregroundColor(DS.Color.overlayTextMuted)
                        }

                        // فاصل داخلي بلون السطح — يفصل الصورة عن الحلقة (مظهر أنظف)
                        Circle()
                            .stroke(DS.Color.surface, lineWidth: 2.5)
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)

                        // حلقة خارجية بتدرج لون الرتبة (رمادية للمتوفّى — تمييز أوضح)
                        Circle()
                            .stroke(borderGradient, lineWidth: 3)
                            .frame(width: interactiveNodeSize + 6, height: interactiveNodeSize + 6)
                    }
                }
                .overlay {
                    // «أنت هنا» — حلقة زرقاء ثابتة دائمة حول عقدتك
                    if isCurrentLocationMember {
                        Circle()
                            .stroke(DS.Color.currentLocation.opacity(0.9), lineWidth: 3)
                            .frame(width: interactiveNodeSize + 16, height: interactiveNodeSize + 16)
                    }
                }
                .overlay {
                    // حلقة البحث المتوهجة
                    if searchedMemberID == member.id {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppSection.tree.ink, AppSection.tree.ink],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 5
                            )
                            .frame(width: interactiveNodeSize + 14, height: interactiveNodeSize + 14)
                            .dsGlowShadow()
                    }
                }
                .overlay {
                    // وميض الموقع (الدائرة الزرقاء — يجب أن يكون تحت شريط المتوفى)
                    if isCurrentLocationMember {
                        Circle()
                            .stroke(DS.Color.currentLocation, lineWidth: 4.2)
                            .frame(width: interactiveNodeSize + 10, height: interactiveNodeSize + 10)
                            .scaleEffect(isPulsing ? 1.35 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.9)
                            .shadow(color: DS.Color.currentLocation.opacity(0.5), radius: 12)
                            .animation(Animation.easeOut(duration: 1.25).repeatCount(4, autoreverses: false), value: isPulsing)
                            .onAppear { isPulsing = true }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // شارة الوفاة — قلب مكسور رمادي في الزاوية (نفس نمط شجرة النساء والتفاصيل)
                    if member.isDeceased ?? false {
                        Circle()
                            .fill(DS.Color.background)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "heart.slash.fill")
                                    .font(DS.Font.scaled(15, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            )
                            .overlay(Circle().stroke(DS.Color.deceased.opacity(0.35), lineWidth: 1))
                            .offset(x: -6, y: -6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // شارة عدد الأبناء + سهم — فوق يسار الصورة (رقم أكبر — طلب المالك)
                    if hasChildren {
                        HStack(spacing: 2) {
                            Text("\(childrenCount)")
                                .font(DS.Font.scaled(16, weight: .heavy))
                            Image(systemName: "chevron.down")
                                .font(DS.Font.scaled(11, weight: .heavy))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 34, minHeight: 32)
                        // غامق قسم الشجرة (كان كحلياً ثابتاً) — أغمق من لون العضو بلا صورة
                        // TMP-ART-TRIAL: «الحالي» الكحلي القديم كما هو
                        .background(Capsule().fill(isKinshipHighlighted ? DS.Color.warning
                                                   : (art == .emblem ? DS.Color.primaryDark : AppSection.tree.deep)))
                        .modifier(TreeArtSkin(art: art, onFill: true, compact: true))   // TMP-ART-TRIAL
                        .overlay(Capsule().stroke(DS.Color.textOnPrimary.opacity(0.45), lineWidth: 1.2))
                        .shadow(color: (art == .emblem ? DS.Color.primary : AppSection.tree.deep).opacity(0.4), radius: 4, y: 2)
                        .offset(x: -2, y: 0)
                    }
                }
                .overlay(alignment: .top) {
                    // علامة "أنت هنا" — overlay لا يأثر على الـ layout
                    if isCurrentLocationMember {
                        Text(L10n.t("أنت هنا", "You"))
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(DS.Color.currentLocation)
                            .clipShape(Capsule())
                            .offset(y: -16)
                    }
                }
                .task {
                    // تأخير تحميل الصور حسب المستوى لتحسين الأداء
                    if level <= 1 {
                        shouldLoadImage = true
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(level) * 200_000_000)
                        guard !Task.isCancelled else { return }
                        shouldLoadImage = true
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nodeAccessibilityLabel)
                .accessibilityHint(hasChildren
                    ? L10n.t("توسيع أو طي الأبناء", "Expand or collapse children")
                    : L10n.t("افتح التفاصيل", "Open details"))

                // الاسم — كبسولة مستقلة، وتحتها مربع التاريخ المنفصل للمتوفى.
                // نموذج تفاعل موحّد: كل ما يخص الشخص (دائرة/اسم/تواريخ) يفتح تفاصيله،
                // والتوسيع له زر مستقل مدخل تحت آخر مربع (شريحة العدد + السهم).
                Button(action: onTap) {
                    Group {
                        if member.isDeceased ?? false {
                            // ── المتوفّى: بطاقة واحدة مدمجة — الاسم فوق وشريط السنوات الأحمر تحته ──
                            VStack(spacing: 0) {
                                if showName {
                                    Text(displayName)
                                        .font(DS.Font.scaled(15, weight: .bold))
                                        .foregroundColor(DS.Color.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .padding(.horizontal, DS.Spacing.lg)
                                        .padding(.vertical, 5)
                                        .frame(minWidth: interactiveLabelWidth, minHeight: interactiveLabelHeight + 2)
                                        .background(DS.Color.surface)
                                }
                                Text(getLifeSpan())
                                    .font(DS.Font.scaled(11, weight: .heavy))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.horizontal, DS.Spacing.md)
                                    .padding(.vertical, 4)
                                    // maxWidth يمدّد الشريط الأحمر ليطابق عرض الاسم مهما طال
                                    .frame(minWidth: interactiveLabelWidth, maxWidth: .infinity, minHeight: 21)
                                    .background(Color(hex: "#A62B32"))   // عنّابي بدرجة خفيفة (طلب المالك)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                            .modifier(TreeArtSkin(art: art, radius: DS.Radius.lg,
                                                  eyeRow: showName ? interactiveLabelHeight + 2 : nil))   // TMP-ART-TRIAL
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(borderGradient, lineWidth: 2.5))
                        } else if showName {
                            Text(displayName)
                                .font(DS.Font.scaled(15, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, 5)
                                .frame(minWidth: interactiveLabelWidth, minHeight: interactiveLabelHeight + 2)
                                .background(DS.Color.surface)
                                .clipShape(Capsule())
                                .modifier(TreeArtSkin(art: art))   // TMP-ART-TRIAL
                                .overlay(Capsule().stroke(borderGradient, lineWidth: 2.5))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .zIndex(1)
                .accessibilityLabel(displayName)
                .accessibilityHint(L10n.t("افتح التفاصيل", "Open details"))
                // (شريحة التوسيع أُزيلت — العدّاد شارة فوق الصورة والصورة تتوسّع)
            }.fixedSize()
    }

    func getLifeSpan() -> String {
        let birth = member.birthDate?.prefix(4); let death = member.deathDate?.prefix(4)
        if (birth == nil || birth == "") && (death == nil || death == "") {
            return L10n.t(member.isFemale ? "متوفية" : "متوفى", "Deceased")
        }
        // سنة الوفاة أولاً ثم الميلاد (طلب المالك)
        // «م» تسبق الرقم (م1947)، والمجهولة «م0000» — طلب المالك
        // كل سنة داخل عزل LTR (U+2066…U+2069) فتبقى «م» ملتصقة بيمين رقمها
        // ولا تنتقل لجهة السنة الأخرى مهما كان اتجاه الواجهة (طلب المالك)
        func iso(_ y: String?) -> String {
            let v = (y == nil || y == "") ? "0000" : y!
            return "\u{2066}م\(v)\u{2069}"
        }
        // الوفاة أولاً ثم الميلاد (معكوس — طلب المالك)
        return "\(iso(death.map(String.init))) - \(iso(birth.map(String.init)))"
    }

    private var displayName: String {
        let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let full = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            return full.split(separator: " ").first.map(String.init) ?? full
        }
        return L10n.t("بدون اسم", "No name")
    }

    private var fullDisplayName: String {
        let full = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        return L10n.t("بدون اسم", "No name")
    }

    /// TMP-ART-TRIAL: رسم العضو بلا صورة بحسب الاتجاه، بلون الرتبة/الجنس نفسه (المعنى لا يتغيّر).
    /// غلاف Equatable فلا يُعاد رسم الكانفس مع كل سحب/تكبير للشجرة.
    private var avatarArt: some View {
        TreeAvatarArt(art: art, tint: nodeAccentColor, size: interactiveNodeSize - 4)
            .equatable()
            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
            .clipShape(Circle())
    }

    private var interactiveNodeSize: CGFloat { 105 }
    private var interactiveLabelWidth: CGFloat { 110 }
    private var interactiveLabelHeight: CGFloat { 28 }

    /// وصف صوتي موحّد للعقدة (VoiceOver): الاسم + الحالة + عدد الأبناء
    var nodeAccessibilityLabel: String {
        var parts: [String] = [fullDisplayName]
        if member.isDeceased == true {
            parts.append(L10n.t("متوفى", "deceased"))
        }
        if hasChildren {
            parts.append("\(childrenCount) " + L10n.t("أبناء", "children"))
        }
        if isCurrentLocationMember {
            parts.append(L10n.t("موقعك الحالي", "your location"))
        }
        return parts.joined(separator: "، ")
    }
}

// MARK: - TMP-ART-TRIAL: الشجرة تتبع اتجاه الرسوم (يُحذف مع ملف ArtTrial بعد اختيار المالك)
// كل ما هنا ساكن وخفيف — الشجرة فيها مئات العقد: لا ظلال إضافية، ولا كانفس متحرك لكل عقدة،
// ولا TimelineView. «الحالي» يرجع المحتوى كما هو تماماً. الألوان: حبر/غامق قسم الشجرة،
// وألوان المعنى (ذكر/أنثى/رتبة/متوفّى/القرابة) لا تتغيّر.

/// طبقة واحدة من خط الوصل
struct TreeLineLayer {
    let color: Color
    let style: StrokeStyle
    var dy: CGFloat = 0
}

enum TreeArtLines {
    private static let gold = Color(hex: "#C9973F")
    private static let cream = Color(hex: "#F3E7CF")
    private static let saduRed = Color(hex: "#B3262E")

    /// طبقات خط الأب وأبنائه — «الحالي»: خط واحد بحبر القسم ٤٥٪ كما كان
    static func layers(_ art: ArtTrial, width w: CGFloat, dark: Bool) -> [TreeLineLayer] {
        let ink = AppSection.tree.ink
        func st(_ lw: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
            StrokeStyle(lineWidth: lw, lineCap: dash.isEmpty ? .round : .butt, lineJoin: .round, dash: dash)
        }
        switch art {
        case .emblem:
            return [TreeLineLayer(color: ink.opacity(0.45), style: st(w))]
        case .soft3d:
            // أنبوب طين: ظلّ ناعم تحته + جسم أعرض + لمعة علوية رفيعة
            return [TreeLineLayer(color: AppSection.tree.deep.opacity(dark ? 0.45 : 0.14), style: st(w + 1.6), dy: 1.6),
                    TreeLineLayer(color: ink.opacity(dark ? 0.6 : 0.5), style: st(w + 0.8)),
                    TreeLineLayer(color: .white.opacity(dark ? 0.14 : 0.55), style: st(max(0.6, w * 0.3)), dy: -0.5)]
        case .glass:
            // أنبوب زجاجي: حافة شفافة وخيط ضوء في قلبه
            return [TreeLineLayer(color: ink.opacity(dark ? 0.4 : 0.3), style: st(w + 1.4)),
                    TreeLineLayer(color: .white.opacity(dark ? 0.3 : 0.8), style: st(max(0.6, w * 0.35)))]
        case .gold:
            // خيط ذهبي رفيع في قلب خط القسم
            return [TreeLineLayer(color: ink.opacity(0.45), style: st(w)),
                    TreeLineLayer(color: gold.opacity(dark ? 0.75 : 0.9), style: st(max(0.6, w * 0.32)))]
        case .sadu:
            // غرزة نسيج متقطّعة
            return [TreeLineLayer(color: ink.opacity(dark ? 0.7 : 0.6), style: st(w, dash: [w * 2.6, w * 1.6]))]
        }
    }

    static func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ layers: [TreeLineLayer]) {
        for l in layers {
            ctx.stroke(l.dy == 0 ? path : path.offsetBy(dx: 0, dy: l.dy), with: .color(l.color), style: l.style)
        }
    }

    /// نقطة التفرّع — «الحالي»: دائرة بحبر القسم ٦٠٪ كما كانت
    static func dot(_ ctx: inout GraphicsContext, at d: CGPoint, r: CGFloat, art: ArtTrial, dark: Bool) {
        let ink = AppSection.tree.ink
        let rect = CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)
        switch art {
        case .emblem:
            ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.6)))
        case .soft3d:
            let big = rect.insetBy(dx: -r * 0.25, dy: -r * 0.25)
            ctx.fill(Path(ellipseIn: big), with: .color(ink.opacity(0.75)))
            ctx.fill(Path(ellipseIn: CGRect(x: big.minX + big.width * 0.22, y: big.minY + big.height * 0.16,
                                            width: big.width * 0.36, height: big.height * 0.3)),
                     with: .color(.white.opacity(dark ? 0.3 : 0.6)))
        case .glass:
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 0.3, dy: -r * 0.3)), with: .color(ink.opacity(0.18)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(0.75)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.55, dy: r * 0.55)), with: .color(.white.opacity(dark ? 0.5 : 0.9)))
        case .gold:
            ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.7)))
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -0.8, dy: -0.8)), with: .color(gold), lineWidth: 1)
        case .sadu:
            ctx.fill(diamond(d, r * 1.45), with: .color(AppSection.tree.deep))
            ctx.fill(diamond(d, r * 0.6), with: .color(cream))
        }
    }

    private static func diamond(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - r, y: c.y))
        p.closeSubpath()
        return p
    }
}

/// رسم العضو بلا صورة — Equatable: لا يُعاد رسمه إلا إن تغيّر الاتجاه أو اللون أو المقاس
struct TreeAvatarArt: View, Equatable {
    let art: ArtTrial
    let tint: Color
    let size: CGFloat
    var icon: String = "person.fill"

    nonisolated static func == (a: TreeAvatarArt, b: TreeAvatarArt) -> Bool {
        a.art == b.art && a.tint == b.tint && a.size == b.size && a.icon == b.icon
    }

    var body: some View {
        if let v = ArtDispatch.stateIcon(art, icon: icon, tint: tint, size: size) {
            v.frame(width: size, height: size).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// لمسة الاتجاه على عناصر الشجرة (كبسولة الاسم، بطاقة المتوفّى، الشارات، بطاقة الأدوات):
/// حواف وخطوط فقط فوق الخلفية الموجودة — «الحالي» = بلا تغيير.
struct TreeArtSkin: ViewModifier {
    let art: ArtTrial
    /// nil = كبسولة
    var radius: CGFloat? = nil
    /// سطح ممتلئ بلون (عليه نص أبيض) بدل سطح فاتح
    var onFill: Bool = false
    /// عنصر صغير/ضيّق: بلا عيون السدو الجانبية (حاشية سفلية بدلها)
    var compact: Bool = false
    /// ارتفاع صف الاسم لعيون السدو (بطاقة المتوفّى: الاسم فوق والسنوات تحت) — nil = كامل الارتفاع
    var eyeRow: CGFloat? = nil
    /// خلفية زجاج/مادة النظام: حواف فقط بلا تعبئة إضافية
    var glassBacked: Bool = false
    @Environment(\.colorScheme) private var scheme

    private static let gold = LinearGradient(colors: [Color(hex: "#E7C27A"), Color(hex: "#C9973F")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    func body(content: Content) -> some View {
        if art == .emblem {
            content
        } else {
            // الزخرفة فوق المحتوى لا تلتقط اللمس (أزرار البطاقة تحتها)
            content.overlay(decoration.allowsHitTesting(false).accessibilityHidden(true))
        }
    }

    @ViewBuilder
    private var decoration: some View {
        let shape: AnyShape = radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
        let dark = scheme == .dark
        let tree = AppSection.tree
        switch art {
        case .emblem:
            EmptyView()
        case .soft3d:
            // طين ناعم: ظلّ داخلي سفلي خفيف + لمعة علوية
            ZStack {
                if !glassBacked {
                    shape.fill(LinearGradient(colors: [.clear, tree.deep.opacity(dark ? 0.22 : 0.08)],
                                              startPoint: .center, endPoint: .bottom))
                }
                shape.stroke(LinearGradient(colors: [.white.opacity(dark ? 0.16 : (onFill ? 0.5 : 0.95)), .clear],
                                            startPoint: .top, endPoint: .center), lineWidth: 1.4)
                    .padding(0.7)
            }
        case .glass:
            // زجاج: حافة ضوء وتعبئة خفيفة بلون القسم (أو لمعة علوية فوق الممتلئ)
            ZStack {
                if onFill {
                    shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.14 : 0.24), .clear],
                                              startPoint: .top, endPoint: .center))
                } else if !glassBacked {
                    shape.fill(tree.ink.opacity(dark ? 0.08 : 0.05))
                }
                shape.stroke(LinearGradient(colors: [.white.opacity(dark ? 0.4 : 0.95), tree.ink.opacity(0.25),
                                                     .white.opacity(dark ? 0.12 : 0.55)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.1)
                    .padding(0.55)
            }
        case .gold:
            // خط ذهبي رفيع داخل الحافة
            shape.stroke(Self.gold, lineWidth: compact ? 0.8 : 0.9)
                .opacity(dark ? 0.65 : 0.85)
                .padding(compact ? 1.8 : 3)
        case .sadu:
            if compact {
                // حاشية سدو سفلية رفيعة داخل الشكل
                shape.fill(onFill ? Color(hex: "#F3E7CF").opacity(0.85) : tree.deep.opacity(0.85))
                    .mask(alignment: .bottom) { Rectangle().frame(height: 2) }
            } else {
                VStack(spacing: 0) {
                    let eyes = HStack(spacing: 0) {
                        saduEye(onFill: onFill)
                        Spacer(minLength: 0)
                        saduEye(onFill: onFill)
                    }
                    .padding(.horizontal, 6)
                    if let eyeRow {
                        eyes.frame(height: eyeRow)
                        Spacer(minLength: 0)
                    } else {
                        eyes.frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    /// عين سدو: معيّن بلون القسم الغامق وقلب كريمي (وفوق الممتلئ: كريمي بقلب أحمر)
    private func saduEye(onFill: Bool) -> some View {
        ZStack {
            // الداكن: حبر القسم بدل غامقه (الغامق يذوب في السطح الداكن)
            Rectangle().fill(onFill ? Color(hex: "#F3E7CF") : (scheme == .dark ? AppSection.tree.ink : AppSection.tree.deep))
                .frame(width: 5, height: 5).rotationEffect(.degrees(45))
            Rectangle().fill(onFill ? Color(hex: "#B3262E") : Color(hex: "#F3E7CF"))
                .frame(width: 2, height: 2).rotationEffect(.degrees(45))
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
