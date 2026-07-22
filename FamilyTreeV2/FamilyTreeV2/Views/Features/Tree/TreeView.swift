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
    var size: CGSize = .zero
}

/// وصلة قصيرة تحت أب مفتوح — النمط الأصلي البسيط.
private struct ConnectorStub: Identifiable {
    let id: UUID
    let x: CGFloat
    let y: CGFloat
    let kinship: Bool
}

/// خط ربط حقيقي بين أسفل شارة الأب وأعلى دائرة الابن (يُرسم كمنحنى بيزيه في Canvas).
private struct ConnectorLink {
    let from: CGPoint   // أسفل شارة الأب
    let to: CGPoint     // أعلى دائرة الابن
    let kinship: Bool   // جزء من مسار القرابة — لون ذهبي وسماكة أكبر
}

/// قوس بين الأب وصفّ أبنائه الأول (من الابن الأول إلى الثالث) — للآباء بأكثر من ٤ أبناء.
private struct ConnectorArc {
    let from: CGPoint     // أعلى دائرة أول ابن في الصف الأول
    let control: CGPoint  // نقطة التحكم — أسفل شارة الأب (قمة القوس بين الأب والأبناء)
    let to: CGPoint       // أعلى دائرة آخر ابن في الصف الأول
    let kinship: Bool
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
    private let ROW_GAP: CGFloat = 14        // بين صفوف الأبناء الملتفّة
    private let CANVAS_PAD: CGFloat = 60     // هامش حول الشجرة
    private let PER_ROW = 3                  // أبناء لكل صف قبل الالتفاف
    private var NODE_H_DEFAULT: CGFloat { CIRCLE_FULL + NAME_H }
    /// ارتفاع صندوق العقدة حسب الحالة (يطابق ترتيب TreeMemberNode: دائرة+اسم[+سنوات]).
    /// شريحة التوسيع أُزيلت — العدّاد صار شارة فوق الصورة (طلب المالك).
    private func nodeBoxHeight(deceased: Bool, hasKids: Bool) -> CGFloat {
        CIRCLE_FULL + NAME_H + (deceased ? LIFE_H : 0)
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @State private var activePath: Set<UUID> = []
    @State private var kinshipBanner: String? = nil
    @State private var kinshipHighlightedIds: Set<UUID> = [] // الأعضاء المهايلايتين بصلة القرابة

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
                    } else {
                        // حاوية بحجم الشاشة بالضبط + الكانفس كـ overlay لا يؤثر على تخطيطها —
                        // يمنع انزياح الشجرة يساراً عندما يكون الكانفس أعرض من الشاشة
                        // (الحاوية السابقة كانت تتمدد لحجم الكانفس فينحرف التمركز).
                        SwiftUI.Color.clear
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .overlay(alignment: .topLeading) {
                                ZStack(alignment: .topLeading) {
                                    // خطوط الربط الحقيقية بين الأب وأبنائه (صف واحد ≤3 أبناء) — قوس عميق
                                    Canvas { ctx, _ in
                                        for link in connectorLinks {
                                            var p = Path()
                                            p.move(to: link.from)
                                            let dy = link.to.y - link.from.y
                                            // نقاط تحكم بعيدة (80%) — قوس مقوّس واضح بدل الخط شبه المستقيم
                                            p.addCurve(to: link.to,
                                                       control1: CGPoint(x: link.from.x, y: link.from.y + dy * 0.8),
                                                       control2: CGPoint(x: link.to.x, y: link.to.y - dy * 0.8))
                                            ctx.stroke(p,
                                                       with: .color(link.kinship ? DS.Color.warning : DS.Color.primary.opacity(0.45)),
                                                       style: StrokeStyle(lineWidth: link.kinship ? 3.5 : 2, lineCap: .round))
                                        }
                                        // قوس الآباء الملتفّة صفوفهم (>٣ أبناء مهما كثروا) — من أول ابن
                                        // لثالث ابن، بقمة فيها كسرة خفيفة تحت الأب (منحنيان يلتقيان بزاوية)
                                        for arc in connectorArcs {
                                            var p = Path()
                                            let apex = arc.control
                                            p.move(to: arc.from)
                                            p.addQuadCurve(to: apex,
                                                           control: CGPoint(x: arc.from.x + (apex.x - arc.from.x) * 0.5,
                                                                            y: arc.from.y))
                                            p.addQuadCurve(to: arc.to,
                                                           control: CGPoint(x: apex.x + (arc.to.x - apex.x) * 0.5,
                                                                            y: arc.to.y))
                                            ctx.stroke(p,
                                                       with: .color(arc.kinship ? DS.Color.warning : DS.Color.primary.opacity(0.45)),
                                                       style: StrokeStyle(lineWidth: arc.kinship ? 3.5 : 2, lineCap: .round, lineJoin: .round))
                                        }
                                    }
                                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                                    .allowsHitTesting(false)
                                    // وصلة قصيرة تحت الأب المفتوح (للآباء بأكثر من 3 أبناء — الشجرة الكبيرة ما تنرسم بخطوط)
                                    ForEach(connectorStubs) { stub in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(stub.kinship ? DS.Color.warning : DS.Color.primary.opacity(0.6))
                                            .frame(width: stub.kinship ? 5 : 2.5, height: 16)
                                            .position(x: stub.x, y: stub.y)
                                    }
                                    // العُقد — نفس شكل TreeMemberNode الدائري (بلا تغيير)
                                    ForEach(cachedVisibleMembers.filter { layout.positions[$0.id] != nil }, id: \.id) { m in
                                        canvasNode(m)
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
                                if userInteracted {
                                    // المستخدم متعمّق — أعد الشجرة داخل حدود الشاشة الجديدة
                                    fitCanvas(in: newSize, layout: layout)
                                    userInteracted = true
                                } else {
                                    fitCanvas(in: newSize, layout: layout)
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
                                    .overlay(glassCardStroke)
                                    .dsSubtleShadow()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        .zIndex(101)

                        // البار الجانبي — نفس أدوات البار العلوي عمودياً (طلب المالك)
                        landscapeSideToolbar
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
                            backgroundGradient: DS.Color.gradientPrimary,
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
                                .overlay(glassCardStroke)
                                .dsSubtleShadow()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        }
                        .zIndex(101)
                    }

                    if !cachedVisibleMembers.isEmpty {
                        overlayTools

                        // بانر صلة القرابة
                        if let banner = kinshipBanner {
                            VStack {
                                HStack(spacing: DS.Spacing.sm) {
                                    Image(systemName: "person.2.fill")
                                        .font(DS.Font.scaled(16, weight: .bold))
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
                                .background(DS.Color.gradientPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.sm)
                                .shadow(color: DS.Color.primary.opacity(0.3), radius: 8, y: 4)
                                .transition(.move(edge: .top).combined(with: .opacity))

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
            .sheet(item: $selectedMember) { member in
                // الارتفاعات تُدار داخل MemberDetailsView (0.46/large) — مصدر واحد بلا تعارض
                MemberDetailsView(member: member)
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
    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.75)
    }
    private var glassCardStroke: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .stroke(DS.Color.mutedBackground.opacity(0.7), lineWidth: 1)
    }

    /// بار جانبي عمودي للوضع الأفقي — نفس أدوات البار العلوي (طلب المالك)
    private var landscapeSideToolbar: some View {
        VStack(spacing: DS.Spacing.sm) {
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

            if let treeTab {
                VStack(spacing: 4) {
                    sideTabChip(L10n.t("العائلة", "Family"), idx: 0, treeTab: treeTab)
                    sideTabChip(L10n.t("النساء", "Women"), idx: 1, treeTab: treeTab)
                }
            }

            if authVM.currentUser != nil {
                Button {
                    if let currentUserID = authVM.currentUser?.id,
                       let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID) {
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
        .padding(6)
        .background(glassCardBackground)
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
                .padding(.horizontal, 8)
                .frame(minWidth: 58, minHeight: 26)
                .background(Capsule().fill(treeTab.wrappedValue == idx ? DS.Color.primary : DS.Color.surface.opacity(0.8)))
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
    private func toolbarIconButton(icon: String, color: Color = DS.Color.primary) -> some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(14, weight: .bold))
            .foregroundColor(color)
            .frame(width: 34, height: 34)                         // بار مدمّج أصغر
            .background(DS.Color.surface.opacity(0.8), in: Circle())   // أغمق (طلب المالك)
            .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.15), lineWidth: 1))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(breadcrumbChain.enumerated()), id: \.element.id) { idx, m in
                    let isLast = idx == breadcrumbChain.count - 1
                    Button {
                        jumpToBreadcrumb(m)
                    } label: {
                        HStack(spacing: 3) {
                            if idx == 0 {
                                Image(systemName: "house.fill")
                                    .font(DS.Font.scaled(8, weight: .bold))
                            }
                            Text(m.firstName.isEmpty ? "—" : m.firstName)
                                .font(DS.Font.scaled(10, weight: isLast ? .heavy : .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(isLast ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isLast ? AnyShapeStyle(DS.Color.primary) : AnyShapeStyle(DS.Color.surface), in: Capsule())
                        .overlay(Capsule().stroke(DS.Color.primary.opacity(isLast ? 0 : 0.2), lineWidth: 1))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("الرجوع إلى \(m.firstName)", "Back to \(m.firstName)"))

                    if !isLast {
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(7, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
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
                                .tint(DS.Color.primary)
                                .scaleEffect(0.7)
                                .frame(width: TreeConst.toolButtonSize, height: TreeConst.toolButtonSize)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                                .font(DS.Font.scaled(15, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                                .frame(width: TreeConst.toolButtonSize, height: TreeConst.toolButtonSize)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel(L10n.t("تحديث الشجرة", "Refresh tree"))
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.mutedBackground, lineWidth: 1)
                )
                .dsSubtleShadow()
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
                let row = Array(boxes[i..<min(i + PER_ROW, boxes.count)])
                let rowW = row.reduce(0) { $0 + $1.width } + H_GAP * CGFloat(row.count - 1)
                let rowH = row.map(\.height).max() ?? 0
                w = max(w, rowW); h += (i > 0 ? ROW_GAP : 0) + rowH
                i += PER_ROW
            }
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
            var i = 0
            while i < kids.count {
                let rowKids = Array(kids[i..<min(i + PER_ROW, kids.count)])
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
                i += PER_ROW
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
        return L
    }

    /// نقاط خطوط الربط الحقيقية — فقط للآباء بصف واحد (≤3 أبناء ظاهرين).
    /// أكثر من ذلك تبقى الوصلة القصيرة (طلب صريح سابق من المالك — الشجرة الكبيرة ما تنرسم بخطوط).
    private var connectorLinks: [ConnectorLink] {
        layout.childRows.flatMap { pid, rows -> [ConnectorLink] in
            guard rows.count == 1, let kids = rows.first, !kids.isEmpty, kids.count <= 3,
                  let pp = layout.positions[pid] else { return [] }
            let ph = layout.heights[pid] ?? NODE_H_DEFAULT
            let start = CGPoint(x: pp.x + NODE_W / 2, y: pp.y + ph - 2)
            return kids.compactMap { cid in
                guard let cp = layout.positions[cid] else { return nil }
                let end = CGPoint(x: cp.x + NODE_W / 2, y: cp.y + 4)
                let kin = kinshipHighlightedIds.contains(pid) && kinshipHighlightedIds.contains(cid)
                return ConnectorLink(from: start, to: end, kinship: kin)
            }
        }
    }

    /// أقواس الآباء الملتفّة صفوفهم (أكثر من ٣ أبناء — حتى ٦ وأكثر): قوس يمتد من أول
    /// ابن إلى ثالث ابن في الصف الأول، وقمته أسفل شارة الأب (بين الأب والأبناء).
    private var connectorArcs: [ConnectorArc] {
        layout.childRows.compactMap { pid, rows -> ConnectorArc? in
            let total = rows.reduce(0) { $0 + $1.count }
            guard total > 3, let firstRow = rows.first, firstRow.count >= 2,
                  let pp = layout.positions[pid],
                  let firstId = firstRow.first, let lastId = firstRow.last,
                  let fp = layout.positions[firstId], let lp = layout.positions[lastId]
            else { return nil }
            let ph = layout.heights[pid] ?? NODE_H_DEFAULT
            return ConnectorArc(
                from: CGPoint(x: fp.x + NODE_W / 2, y: fp.y + 4),
                control: CGPoint(x: pp.x + NODE_W / 2, y: pp.y + ph - 2),
                to: CGPoint(x: lp.x + NODE_W / 2, y: lp.y + 4),
                kinship: kinshipHighlightedIds.contains(pid)
            )
        }
    }

    /// وصلات قصيرة تحت الآباء المفتوحين — فقط لمن تجاوز أبناؤه حدّ رسم الخطوط (صف ملتفّ).
    private var connectorStubs: [ConnectorStub] {
        layout.childRows.compactMap { pid, rows in
            guard !rows.isEmpty, let pp = layout.positions[pid] else { return nil }
            // الآباء بصف واحد (≤3) لهم خطوط ربط حقيقية — لا وصلة قصيرة
            if rows.count == 1, let kids = rows.first, kids.count <= 3 { return nil }
            // الآباء الملتفّة صفوفهم لهم قوس يصل للأب — الوصلة القصيرة تصير زائدة
            if let firstRow = rows.first, firstRow.count >= 2 { return nil }
            let ph = layout.heights[pid] ?? NODE_H_DEFAULT
            return ConnectorStub(id: pid,
                                 x: pp.x + NODE_W / 2,
                                 y: pp.y + ph + 10,
                                 kinship: kinshipHighlightedIds.contains(pid))
        }
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
        withAnimation(DS.Anim.smooth) {
            let L = rebuildLayout()
            // التمركز على العقدة بعد كل توسيع/طي — الشجرة تبقى بالمنتصف دائماً.
            // عند الفتح يرتفع الأب حسب عدد صفوف أبنائه: صف واحد 42%،
            // صفّان 34%، ثلاثة صفوف وأكثر (٧+ أبناء) 26% — ليظهر الصف الأخير.
            if opening {
                let rowCount = (kids.count + PER_ROW - 1) / PER_ROW
                adaptiveCenter(on: member.id, rowCount: rowCount, in: L)
            } else {
                // عند الطي: تمركز على الأب بنفس المنطق التكيّفي حسب صفوف أبنائه —
                // الشجرة تنزل ويظهر جميع الإخوة (طلب المالك)
                let pid = member.fatherId ?? member.id
                let sibs = cachedChildrenByFatherId[pid] ?? []
                let rowCount = max(1, (sibs.count + PER_ROW - 1) / PER_ROW)
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

                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.08))
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(DS.Color.gridTree.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "leaf.arrow.triangle.circlepath")
                        .font(DS.Font.scaled(36, weight: .medium))
                        .foregroundStyle(DS.Color.gradientPrimary)
                }

                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("جاري مزامنة الشجرة...", "Syncing tree..."))
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.textPrimary)
                    ProgressView()
                        .tint(DS.Color.primary)
                        .scaleEffect(1.1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
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
        default: return DS.Color.primary
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
                        Circle()
                            .fill(nodeGradient)
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .shadow(color: nodeAccentColor.opacity(member.isDeceased == true ? 0.12 : 0.26),
                                    radius: 10, x: 0, y: 5)

                        // الصورة أو الأيقونة
                        if shouldLoadImage, let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.fill")
                                    .font(DS.Font.scaled(30))
                                    .foregroundColor(DS.Color.overlayTextMuted)
                            }
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .clipShape(Circle())
                            .saturation(member.isDeceased == true ? 0 : 1)   // المتوفّى: صورة غير ملوّنة
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
                                    colors: [DS.Color.primaryDark, DS.Color.primaryDark],
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
                        .background(Capsule().fill(isKinshipHighlighted ? DS.Color.warning : DS.Color.primaryDark))   // أغمق من لون العضو بلا صورة
                        .overlay(Capsule().stroke(DS.Color.textOnPrimary.opacity(0.45), lineWidth: 1.2))
                        .shadow(color: DS.Color.primary.opacity(0.4), radius: 4, y: 2)
                        .offset(x: -2, y: 0)
                    }
                }
                .overlay(alignment: .top) {
                    // علامة "أنت هنا" — overlay لا يأثر على الـ layout
                    if isCurrentLocationMember {
                        Text(L10n.t("أنت هنا", "You"))
                            .font(DS.Font.scaled(10, weight: .bold))
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
        if (birth == nil || birth == "") && (death == nil || death == "") { return L10n.t("متوفى", "Deceased") }
        // سنة الميلاد أولاً ثم الوفاة (معكوس — طلب المالك)
        // كل سنة تُلحق بـ«م» (ميلادي)، والمجهولة تُعرض «0000م»
        let b = (birth == nil || birth == "") ? "0000م" : "\(birth!)م"
        let d = (death == nil || death == "") ? "0000م" : "\(death!)م"
        return "\(b) - \(d)"
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
