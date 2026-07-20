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

// MARK: - أنماط العرض
enum TreeDisplayMode: Hashable {
    case interactive // تفاعلي: صور وتفاصيل + ترتيب شبكي
    case fullTree    // كامل: أداء عالي (نص فقط) + ترتيب أفقي كامل (الإخوان جنب بعض)
}

// MARK: - ثوابت الشجرة
private enum TreeConst {
    // Zoom
    static let minScale: CGFloat = 0.2
    static let maxScale: CGFloat = 3.0
    static let zoomStep: CGFloat = 0.05
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

// MARK: - Branch Connector Style
/// نمط الخطوط بين الأب وأبنائه. مخزّن في @AppStorage لذا يبقى عبر التشغيل.
enum BranchConnectorStyle: String {
    case arc   // قوس (bezier)
    case angle // زاوية (L-shape)
}

// MARK: - Branch Connector Shape
/// يرسم فروع من نقطة الأب أعلى إلى نقاط الأبناء أسفل.
/// `branchCount`: عدد الفروع (1-3). الأبناء من الـ4 فما فوق لا يُرسم لهم فرع
/// (طلب صريح من المالك — الشجرة الكبيرة ما تنرسم).
/// `style`: قوس أو زاوية.
struct BranchConnector: Shape {
    let branchCount: Int
    let style: BranchConnectorStyle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard branchCount > 0 else { return path }
        let count = min(3, branchCount)
        let topCenter = CGPoint(x: rect.midX, y: 0)

        // نقاط النهاية أسفل — تطابق مراكز الأبناء في HStack بتوزيع متساوٍ.
        // عند 3 أبناء: نشيل الخط الأوسط (طلب صريح) — فقط الأطراف.
        let endpoints: [CGFloat]
        switch count {
        case 1: endpoints = [rect.midX]
        case 2: endpoints = [rect.width * 0.25, rect.width * 0.75]
        default: endpoints = [rect.width / 6, rect.width * 5 / 6] // 3 أبناء — أطراف فقط بدون الأوسط
        }

        for endX in endpoints {
            switch style {
            case .arc:
                // bezier curve ناعم من نقطة الأب إلى نقطة الابن
                path.move(to: topCenter)
                let c1 = CGPoint(x: topCenter.x, y: rect.height * 0.55)
                let c2 = CGPoint(x: endX, y: rect.height * 0.55)
                let end = CGPoint(x: endX, y: rect.height)
                path.addCurve(to: end, control1: c1, control2: c2)
            case .angle:
                // L-shape: عمودي → أفقي → عمودي
                let elbowY = rect.height * 0.5
                path.move(to: topCenter)
                path.addLine(to: CGPoint(x: topCenter.x, y: elbowY))
                path.addLine(to: CGPoint(x: endX, y: elbowY))
                path.addLine(to: CGPoint(x: endX, y: rect.height))
            }
        }
        return path
    }
}

/// تطبيق `.drawingGroup()` بشكل مشروط — يفعّله فقط للأشجار الكبيرة
/// لتجنب overhead الـ rasterization على الأشجار الصغيرة.
private struct ConditionalDrawingGroup: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
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

    private let viewMode: TreeDisplayMode = .interactive

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
    private let BADGE_H: CGFloat = 28        // شارة العدّاد (نصف دائرة)
    private let LIFE_H: CGFloat = 20         // سطر سنوات المتوفّى
    private let H_GAP: CGFloat = 22          // بين الإخوة أفقيًا
    private let V_GAP: CGFloat = 48          // بين الأب وأبنائه عموديًا
    private let ROW_GAP: CGFloat = 22        // بين صفوف الأبناء الملتفّة
    private let CANVAS_PAD: CGFloat = 60     // هامش حول الشجرة
    private let PER_ROW = 3                  // أبناء لكل صف قبل الالتفاف
    private var NODE_H_DEFAULT: CGFloat { CIRCLE_FULL + NAME_H }
    /// ارتفاع صندوق العقدة حسب الحالة (يطابق ترتيب TreeMemberNode: دائرة+اسم[+عدّاد][+سنوات]).
    private func nodeBoxHeight(deceased: Bool, hasKids: Bool) -> CGFloat {
        CIRCLE_FULL + NAME_H + (hasKids ? BADGE_H : 0) + (deceased ? LIFE_H : 0)
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

    private var lightweightFullTree: Bool {
        cachedVisibleMembers.count > 90
    }

    /// الحد الأقصى لعدد العقد المرسومة في وقت واحد لتجنب التهنيق
    private var maxRenderedNodes: Int {
        let count = cachedVisibleMembers.count
        if count > 8000 { return 30 }
        if count > 5000 { return 50 }
        if count > 2000 { return 70 }
        if count > 500  { return 100 }
        return 150
    }

    private var preferredBaseScale: CGFloat { TreeConst.defaultScale }

    private func preferredScaleForCurrentExpansion() -> CGFloat { TreeConst.defaultScale }

    private var currentZoomPercentText: String {
        let zoom = Int((scale * 100).rounded())
        return "\(max(40, min(300, zoom)))%"
    }

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
                        ZStack(alignment: .topLeading) {
                            ZStack(alignment: .topLeading) {
                                // وصلة قصيرة تحت الأب المفتوح (النمط الأصلي — بلا خطوط ممتدة بين العقد)
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
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
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
                            viewport = newSize
                            if !userInteracted { fitCanvas(in: newSize, layout: layout) }
                        }
                    }

                    VStack(spacing: DS.Spacing.md) {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("شجرة العائلة", "Family Tree"),
                            subtitle: "\(cachedVisibleMembers.count) " + L10n.t("فرد", "members"),
                            icon: "leaf.fill",
                            backgroundGradient: DS.Color.gradientPrimary
                        )

                        // تحت الهيدر: إمّا البحث (مع الفلاتر) أو صف الأدوات (تبويب + بحث + بداية + موقعي).
                        Group {
                            if showSearch {
                                TreeSearchOverlay(
                                    onSelect: { member in selectMemberFromSearch(member) },
                                    autoFocus: true,
                                    onClose: { withAnimation(DS.Anim.snappy) { showSearch = false } },
                                    showFiltersWhenEmpty: true
                                )
                            } else {
                                classicToolbarRow
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                    }
                    .zIndex(101)

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
                MemberDetailsView(member: member)
                    .presentationDetents([.fraction(0.42), .large])
                    .presentationDragIndicator(.visible)
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
            .font(DS.Font.scaled(16, weight: .bold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)                         // هدف لمس ≥44pt
            .background(DS.Color.surface, in: Circle())           // غير شفاف
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

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(breadcrumbChain.enumerated()), id: \.element.id) { idx, m in
                    let isLast = idx == breadcrumbChain.count - 1
                    Button {
                        jumpToBreadcrumb(m)
                    } label: {
                        HStack(spacing: 4) {
                            if idx == 0 {
                                Image(systemName: "house.fill")
                                    .font(DS.Font.scaled(10, weight: .bold))
                            }
                            Text(m.firstName.isEmpty ? "—" : m.firstName)
                                .font(DS.Font.scaled(12, weight: isLast ? .heavy : .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(isLast ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, 6)
                        .background(isLast ? AnyShapeStyle(DS.Color.primary) : AnyShapeStyle(DS.Color.surface), in: Capsule())
                        .overlay(Capsule().stroke(DS.Color.primary.opacity(isLast ? 0 : 0.25), lineWidth: 1))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("الرجوع إلى \(m.firstName)", "Back to \(m.firstName)"))

                    if !isLast {
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(DS.Color.mutedBackground, lineWidth: 1))
        .dsSubtleShadow()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - أدوات التحديث — Glassy (أُزيلت أدوات الزوم؛ التكبير باللمس)
    private var overlayTools: some View {
        VStack(spacing: DS.Spacing.sm) {
            Spacer()
            // شريط المسار — يظهر أول ما تتعمّق في الشجرة
            if breadcrumbChain.count > 1 {
                breadcrumbBar
            }
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    // أُزيلت أدوات الزوم (+/−/%) — التكبير يبقى باللمس/الإيماءة.
                    // نُبقي زر التحديث فقط.
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

    /// وصلات قصيرة تحت الآباء المفتوحين — النمط الأصلي البسيط.
    private var connectorStubs: [ConnectorStub] {
        layout.childRows.compactMap { pid, rows in
            guard !rows.isEmpty, let pp = layout.positions[pid] else { return nil }
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
            viewMode: viewMode,
            lightweightFullTree: false,
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
        withAnimation(DS.Anim.snappy) {
            let L = rebuildLayout()
            if opening { scrollNodeToTop(member.id, in: L) }
            else { centerOn(member.fatherId ?? member.id, in: L) }
        }
    }

    private func collectDescendants(of parentId: UUID, into set: inout Set<UUID>) {
        for child in cachedChildrenByFatherId[parentId] ?? [] where child.id != parentId {
            if set.insert(child.id).inserted {
                collectDescendants(of: child.id, into: &set)
            }
        }
    }

    // ─── الكاميرا (offset) ───

    /// يُمركز عقدة في وسط الشاشة.
    private func centerOn(_ id: UUID, in L: FamilyLayout) {
        guard let p = L.positions[id], viewport.width > 0 else { return }
        userInteracted = true
        let s = scale
        let h = L.heights[id] ?? NODE_H_DEFAULT
        let cx = (p.x + NODE_W / 2) * s
        let cy = (p.y + h / 2) * s
        offset = clampOffset(CGSize(width: viewport.width / 2 - cx, height: viewport.height / 2 - cy))
        baseOffset = offset
    }

    /// يُنزل العقدة قرب أعلى الشاشة (تحت الهيدر) لتظهر أبناؤها تحتها.
    private func scrollNodeToTop(_ id: UUID, in L: FamilyLayout) {
        guard let p = L.positions[id], viewport.width > 0 else { return }
        userInteracted = true
        let s = scale
        let topMargin: CGFloat = 160
        let cx = (p.x + NODE_W / 2) * s
        offset = clampOffset(CGSize(width: viewport.width / 2 - cx, height: topMargin - p.y * s))
        baseOffset = offset
    }

    /// يلائم الشجرة للشاشة ويوسّطها أفقياً وعمودياً (بمنتصف المساحة تحت الهيدر).
    private func fitCanvas(in size: CGSize, layout L: FamilyLayout) {
        guard L.size.width > 0, size.width > 0 else { return }
        let s = max(0.28, min(1.1, (size.width - 48) / L.size.width))
        scale = s; baseScale = s; fittedScale = s
        offset = centeredOffset(scale: s, in: size, layout: L)
        baseOffset = offset
    }

    /// إزاحة توسيط المحتوى: أفقياً بالمنتصف، وعمودياً بمنتصف المساحة المتاحة
    /// تحت الهيدر العائم — وإذا كانت الشجرة أطول من الشاشة تبدأ من تحت الهيدر.
    private func centeredOffset(scale s: CGFloat, in size: CGSize, layout L: FamilyLayout) -> CGSize {
        let headerInset: CGFloat = 150
        let contentW = L.size.width * s
        let contentH = L.size.height * s
        let availH = max(size.height - headerInset, 0)
        let y = contentH < availH ? headerInset + (availH - contentH) / 2 : headerInset
        return CGSize(width: (size.width - contentW) / 2, height: y)
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
    var viewMode: TreeDisplayMode
    let lightweightFullTree: Bool
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
        if viewMode == .fullTree {
            if lightweightFullTree {
                // نسخة خفيفة Bold
                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                member.isDeceased == true
                                    ? DS.Color.muted
                                    : nodeAccentColor
                            )
                            .frame(width: 14, height: 14)

                        Text(fullDisplayName)
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if member.isDeceased ?? false {
                            Text(getLifeSpan())
                                .font(DS.Font.scaled(9, weight: .black))
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(DS.Color.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(borderColor, lineWidth: 2.5)
                    )
                    .overlay {
                        if isCurrentLocationMember {
                            Capsule()
                                .stroke(DS.Color.currentLocation, lineWidth: 2.8)
                                .scaleEffect(isPulsing ? 1.3 : 1.0)
                                .opacity(isPulsing ? 0.0 : 0.9)
                                .shadow(color: DS.Color.currentLocation.opacity(0.45), radius: 7)
                                .animation(Animation.easeOut(duration: 1.25).repeatCount(4, autoreverses: false), value: isPulsing)
                                .onAppear { isPulsing = true }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nodeAccessibilityLabel)
                .accessibilityHint(L10n.t("افتح التفاصيل", "Open details"))
                .frame(minWidth: 114, alignment: .top)
                .zIndex(5)
            } else {
                // الوضع الكامل — Bold مع تدرج
                VStack(spacing: 5) {
                    Button(action: onTap) {
                        ZStack {
                            Circle()
                                .fill(nodeAccentColor)
                                .frame(width: 56, height: 56)
                                .dsSubtleShadow()

                            Text(String(fullDisplayName.prefix(1)))
                                .font(DS.Font.scaled(19, weight: .black))
                                .foregroundColor(DS.Color.textOnPrimary)
                        }
                    }
                    .overlay {
                        if isCurrentLocationMember {
                            Circle()
                                .stroke(DS.Color.currentLocation, lineWidth: 4.2)
                                .frame(width: 64, height: 64)
                                .scaleEffect(isPulsing ? 1.4 : 1.0)
                                .opacity(isPulsing ? 0.0 : 0.9)
                                .shadow(color: DS.Color.currentLocation.opacity(0.5), radius: 10)
                                .animation(Animation.easeOut(duration: 1.25).repeatCount(4, autoreverses: false), value: isPulsing)
                                .onAppear { isPulsing = true }
                        }
                    }
                    .overlay(alignment: .top) {
                        if isCurrentLocationMember {
                            Text(L10n.t("أنت هنا", "You"))
                                .font(DS.Font.scaled(10, weight: .bold))
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(DS.Color.currentLocation)
                                .clipShape(Capsule())
                                .offset(y: -14)
                        }
                    }

                    Text(fullDisplayName)
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 60, minHeight: 24)
                        .background(DS.Color.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(borderColor, lineWidth: 2.5))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nodeAccessibilityLabel)
                .accessibilityHint(L10n.t("افتح التفاصيل", "Open details"))
                .frame(minWidth: 126, alignment: .top)
                .zIndex(5)
            }

        } else {
            // الوضع التفاعلي — دائري
            VStack(spacing: 0) {
                Button(action: onTap) {
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
                .accessibilityHint(L10n.t("افتح التفاصيل", "Open details"))

                // الاسم
                Button(action: onToggle) {
                    if showName {
                        Text(displayName)
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, DS.Spacing.lg)
                            .frame(minWidth: interactiveLabelWidth)
                            .frame(height: interactiveLabelHeight + 2, alignment: .center)
                            .background(DS.Color.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(borderGradient, lineWidth: 2.5))
                    }
                }.foregroundColor(DS.Color.textOnPrimary).zIndex(1)

                // سهم التوسيع — نص دائرة أسفل الاسم
                if hasChildren {
                    Button(action: onToggle) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text("\(childrenCount)")
                                .font(DS.Font.scaled(15, weight: .heavy))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(DS.Font.scaled(14, weight: .heavy))
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 28)
                        .background(
                            isKinshipHighlighted
                                ? DS.Color.warning
                                : (member.isDeceased == true ? DS.Color.textTertiary : DS.Color.primaryDark)
                        )
                        .clipShape(SemiCircleShape())
                    }
                    .accessibilityLabel(isExpanded
                        ? L10n.t("طي الأبناء", "Collapse children")
                        : L10n.t("عرض \(childrenCount) أبناء", "Show \(childrenCount) children"))
                    .offset(y: -1)
                    .zIndex(0)
                }

                // سنوات الميلاد–الوفاة كتعليق خافت تحت الاسم (بدل الشريط الأحمر السابق)
                if member.isDeceased ?? false {
                    Text(getLifeSpan())
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, DS.Spacing.xs)
                }
            }.fixedSize()
        }
    }

    func getLifeSpan() -> String {
        let birth = member.birthDate?.prefix(4); let death = member.deathDate?.prefix(4)
        if (birth == nil || birth == "") && (death == nil || death == "") { return L10n.t("متوفى", "Deceased") }
        // سنة الوفاة يسار، سنة الميلاد يمين — قراءة RTL تبدأ من الميلاد (يمين) للوفاة (يسار)
        return "\(death ?? "?") - \(birth ?? "?")"
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

// MARK: - مفتاح التقاط حجم محتوى الشجرة (لزوم النقر المزدوج نحو نقطة اللمس)
private struct TreeContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - نص دائرة (النص السفلي)
private struct SemiCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addArc(
            center: CGPoint(x: rect.midX, y: 0),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - شكل سداسي
private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        let r = min(w, h) / 2

        var path = Path()
        for i in 0..<6 {
            let angle = Angle(degrees: Double(i) * 60 - 90)
            let x = cx + r * CGFloat(cos(angle.radians))
            let y = cy + r * CGFloat(sin(angle.radians))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}
