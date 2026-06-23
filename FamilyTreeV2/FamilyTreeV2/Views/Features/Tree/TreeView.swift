import SwiftUI
import Foundation
import Supabase

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

// MARK: - 1. واجهة الشجرة الرئيسية — Liquid Glass
struct TreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var selectedMember: FamilyMember? = nil
    @State private var scrollTarget: UUID? = nil
    @State private var scrollCounter: Int = 0
    @State private var currentLocationMemberID: UUID? = nil
    @State private var isRefreshing = false

    private let viewMode: TreeDisplayMode = .interactive

    @State private var searchedMemberID: UUID? = nil
    @State private var highlightTask: Task<Void, Never>?
    @State private var locationHighlightTask: Task<Void, Never>?

    @State private var scale: CGFloat = TreeConst.closeNodeScale
    /// إظهار حقل البحث (مخفي افتراضياً خلف زر — العرض الكلاسيكي).
    @State private var showSearch = false
    @State private var treeID = UUID()
    @State private var currentAnchor: UnitPoint = .center
    @State private var baseScale: CGFloat = TreeConst.closeNodeScale
    @State private var zoomAnchor: UnitPoint = .center
    @State private var treeContentSize: CGSize = .zero

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
    @State private var cachedHusbandsWithWives: Set<UUID> = []
    @State private var cachedHusbandsAllWivesDeceased: Set<UUID> = []

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
        let husbandsWithWives: Set<UUID>
        let husbandsAllWivesDeceased: Set<UUID>
    }

    /// حساب الكاش — pure function، تشتغل على أي thread.
    private static func computeCache(from members: [FamilyMember]) -> TreeCache {
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

        // الرجال الذين لهم زوجات (لإظهار شارة الزوجة) — من كل الأعضاء لا المرئيين فقط.
        var wivesByHusband: [UUID: [FamilyMember]] = [:]
        for m in members where m.isFemale && m.husbandId != nil {
            wivesByHusband[m.husbandId!, default: []].append(m)
        }
        let husbandsWithWives = Set(wivesByHusband.keys)
        // الرجال الذين كل زوجاتهم متوفّيات (لإظهار حالة الوفاة على الشارة).
        let husbandsAllWivesDeceased = Set(
            wivesByHusband.filter { $0.value.allSatisfy { $0.isDeceased == true } }.keys
        )

        return TreeCache(
            visible: visible,
            byId: byId,
            roots: roots,
            childrenMap: childrenMap,
            ids: Set(visible.map(\.id)),
            husbandsWithWives: husbandsWithWives,
            husbandsAllWivesDeceased: husbandsAllWivesDeceased
        )
    }

    /// تطبيق الكاش على @State — يحب يكون على MainActor.
    private func applyCache(_ cache: TreeCache) {
        cachedVisibleMembers = cache.visible
        cachedMemberById = cache.byId
        cachedRootMembers = cache.roots
        cachedChildrenByFatherId = cache.childrenMap
        cachedMemberIds = cache.ids
        cachedHusbandsWithWives = cache.husbandsWithWives
        cachedHusbandsAllWivesDeceased = cache.husbandsAllWivesDeceased
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
                        ScrollViewReader { proxy in
                            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                                VStack(spacing: 0) {
                                    if let root = primaryRootMember {
                                        rootBranch(for: root)
                                            .id(treeID)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                                // drawingGroup() فقط للأشجار الكبيرة جداً —
                                // للأشجار الصغيرة، يضيف overhead أكثر من الفائدة
                                // ويعيد الـ rasterize عند كل zoom gesture مما يهنّق الواجهة
                                .modifier(ConditionalDrawingGroup(enabled: cachedVisibleMembers.count > 300))
                                .background(
                                    GeometryReader { g in
                                        SwiftUI.Color.clear
                                            .preference(key: TreeContentSizeKey.self, value: g.size)
                                    }
                                )
                                .onPreferenceChange(TreeContentSizeKey.self) { treeContentSize = $0 }
                                .simultaneousGesture(
                                    SpatialTapGesture(count: 2, coordinateSpace: .local)
                                        .onEnded { value in handleDoubleTap(at: value.location) }
                                )
                                .scaleEffect(scale, anchor: zoomAnchor)
                                .frame(
                                    minWidth: geometry.size.width,
                                    minHeight: geometry.size.height,
                                    alignment: .center
                                )
                                // top padding = مسافة تكفي لنزول الشجرة تحت الهيدر العائم (~120pt)
                                .padding(.top, DS.Spacing.xxxxl * 3)
                                .padding(.bottom, DS.Spacing.xxxxl * 3)
                                .padding(.horizontal, DS.Spacing.xxxxl)
                            }
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        // Note: MagnificationGesture (iOS 16+) ما يعطي startLocation
                                        // فنستخدم مركز الشاشة كنقطة زوم افتراضية
                                        zoomAnchor = .center
                                        let newScale = baseScale * value
                                        scale = min(max(newScale, TreeConst.minScale), TreeConst.maxScale)
                                    }
                                    .onEnded { value in
                                        let newScale = baseScale * value
                                        scale = min(max(newScale, TreeConst.minScale), TreeConst.maxScale)
                                        baseScale = scale
                                    }
                            )
                            .onChange(of: scrollCounter) { _ in
                                if let id = scrollTarget {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(id, anchor: currentAnchor)
                                    }
                                }
                            }
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

                        // تحت الهيدر: إمّا البحث (مع الفلاتر) أو صف الأدوات (إعادة موضع + موقعي).
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
                                            activePath = []
                                            searchedMemberID = nil
                                            scale = TreeConst.defaultScale
                                            baseScale = TreeConst.defaultScale
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
                // إلغاء أي highlight/location tasks عالقة لتفادي memory leaks عند التنقل السريع
                highlightTask?.cancel()
                highlightTask = nil
                locationHighlightTask?.cancel()
                locationHighlightTask = nil
            }
            .onChange(of: memberVM.membersVersion) { _ in
                Task {
                    let snapshot = memberVM.allMembers
                    let cache = await Task.detached(priority: .userInitiated) {
                        Self.computeCache(from: snapshot)
                    }.value
                    withAnimation(DS.Anim.snappy) {
                        applyCache(cache)
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

                // تصغير الزوم عشان يبان المسار كامل
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = TreeConst.kinshipScale
                    baseScale = TreeConst.kinshipScale
                }

                // سكرول للجد المشترك — عشان يكون بنص الشاشة
                let scrollToId = commonAncestor ?? memberId
                Task {
                    try? await Task.sleep(nanoseconds: TreeConst.kinshipScrollDelay)
                    currentAnchor = .center
                    scrollTarget = scrollToId
                    scrollCounter += 1

                    // سكرول ثاني للتأكد من التمركز بعد ما الشجرة تتحدث
                    try? await Task.sleep(nanoseconds: TreeConst.kinshipSecondScroll)
                    currentAnchor = .center
                    scrollTarget = scrollToId
                    scrollCounter += 1
                }

                // إخفاء البانر والهايلايت بعد 12 ثانية
                Task {
                    try? await Task.sleep(nanoseconds: TreeConst.kinshipBannerDuration)
                    withAnimation(DS.Anim.snappy) {
                        kinshipBanner = nil
                        kinshipHighlightedIds = []
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
        // فتح المسار بأنيميشن سريعة
        withAnimation(.easeInOut(duration: 0.25)) {
            activePath = ancestors
            activePath.insert(member.id)
        }
        // الانتقال للعضو بعد بناء العقد
        Task {
            try? await Task.sleep(nanoseconds: TreeConst.scrollDelay)
            guard !Task.isCancelled else { return }
            scrollTarget = member.id
            scrollCounter += 1
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
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activePath = ancestors
            if includeFocusedMemberInPath {
                activePath.insert(member.id)
            }
            if highlight {
                searchedMemberID = member.id
            } else {
                searchedMemberID = nil
            }
        }
        
        Task {
            try? await Task.sleep(nanoseconds: TreeConst.scrollDelay)
            guard !Task.isCancelled else { return }
            currentAnchor = .center
            scrollTarget = member.id
            scrollCounter += 1
            // إعادة توسيط بعد استقرار التوسّع — يضبط الموضع عند الذهاب لموقعي.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            currentAnchor = .center
            scrollCounter += 1
        }

        // Remove highlight after 5 seconds
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
        if let root = primaryRootMember {
            // الجذر فقط مفتوح — الأبناء يظهرون، وأبناؤهم لما يضغط المستخدم
            let expandedIds: Set<UUID> = [root.id]
            let updates = {
                scale = preferredBaseScale
                baseScale = preferredBaseScale
                activePath = expandedIds
                searchedMemberID = nil
                treeID = UUID()
                currentAnchor = .center
                scrollTarget = root.id
                scrollCounter += 1
            }
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) { updates() }
            } else {
                updates()
            }
        }
    }

    // MARK: - صف الأدوات تحت الهيدر — مطابق للتفرّع (بحث / البداية / موقعي) أيقونات فقط
    private var classicToolbarRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                withAnimation(DS.Anim.smooth) { showSearch = true }
            } label: {
                toolbarIconButton(icon: "magnifyingglass")
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("بحث", "Search"))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = TreeConst.defaultScale
                    baseScale = TreeConst.defaultScale
                }
                resetToTopRoot()
            } label: {
                toolbarIconButton(icon: "house.fill")
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("البداية", "Start"))

            Spacer()

            if authVM.currentUser != nil {
                Button {
                    if let currentUserID = authVM.currentUser?.id,
                       let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID) {
                        currentLocationMemberID = userMember.id
                        centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                        locationHighlightTask?.cancel()
                        locationHighlightTask = Task {
                            try? await Task.sleep(nanoseconds: TreeConst.highlightDuration)
                            guard !Task.isCancelled else { return }
                            withAnimation { currentLocationMemberID = nil }
                        }
                    }
                } label: {
                    toolbarIconButton(icon: "location.fill")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("موقعي", "Me"))
            }
        }
    }

    /// زر دائري بأيقونة فقط — نفس ستايل التفرّع.
    private func toolbarIconButton(icon: String, color: Color = DS.Color.primary) -> some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(16, weight: .bold))
            .foregroundColor(color)
            .frame(width: 40, height: 40)
            .background(Circle().fill(color.opacity(0.12)))
    }

    // MARK: - أدوات التحديث — Glassy (أُزيلت أدوات الزوم؛ التكبير باللمس)
    private var overlayTools: some View {
        VStack {
            Spacer()
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

    /// نقر مزدوج: تكبير نحو نقطة اللمس، أو تصغير للوضع الافتراضي إذا كان مكبّراً
    private func handleDoubleTap(at location: CGPoint) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if scale > TreeConst.defaultScale + 0.05 {
            // مكبّر حالياً → رجوع للوضع الافتراضي من المركز
            withAnimation(.easeInOut(duration: 0.3)) {
                zoomAnchor = .center
                scale = TreeConst.defaultScale
                baseScale = scale
            }
        } else {
            // تكبير نحو نقطة اللمس
            guard treeContentSize.width > 0, treeContentSize.height > 0 else { return }
            let anchor = UnitPoint(
                x: min(max(location.x / treeContentSize.width, 0), 1),
                y: min(max(location.y / treeContentSize.height, 0), 1)
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                zoomAnchor = anchor
                scale = min(TreeConst.defaultScale * 2.2, TreeConst.maxScale)
                baseScale = scale
            }
        }
    }

    @ViewBuilder
    private func rootBranch(for root: FamilyMember) -> some View {
        RecursiveTreeBranch(
            member: root,
            childrenByFatherId: cachedChildrenByFatherId,
            ancestorIDs: [],
            activePath: $activePath,
            searchedMemberID: $searchedMemberID,
            selectedMember: $selectedMember,
            scrollTarget: $scrollTarget,
            scrollAnchor: $currentAnchor,
            scrollCounter: $scrollCounter,
            scale: $scale,
            baseScale: $baseScale,
            level: 0,
            viewMode: viewMode,
            lightweightFullTree: lightweightFullTree,
            currentLocationMemberID: currentLocationMemberID,
            renderedCount: .constant(0),
            maxRendered: maxRenderedNodes,
            kinshipHighlightedIds: kinshipHighlightedIds,
            husbandsWithWives: cachedHusbandsWithWives,
            husbandsAllWivesDeceased: cachedHusbandsAllWivesDeceased
        )
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


// MARK: - 2. فرع الشجرة (الإخوان جنب بعض)
struct RecursiveTreeBranch: View {
    let member: FamilyMember
    let childrenByFatherId: [UUID: [FamilyMember]]
    let ancestorIDs: Set<UUID>
    @Binding var activePath: Set<UUID>
    @Binding var searchedMemberID: UUID?
    @Binding var selectedMember: FamilyMember?
    @Binding var scrollTarget: UUID?
    @Binding var scrollAnchor: UnitPoint
    @Binding var scrollCounter: Int
    @Binding var scale: CGFloat
    @Binding var baseScale: CGFloat
    let level: Int

    var viewMode: TreeDisplayMode
    let lightweightFullTree: Bool
    let currentLocationMemberID: UUID?
    @Binding var renderedCount: Int
    let maxRendered: Int
    var kinshipHighlightedIds: Set<UUID> = []
    var husbandsWithWives: Set<UUID> = []
    var husbandsAllWivesDeceased: Set<UUID> = []

    /// الفتح يعتمد على activePath كمصدر وحيد للحقيقة
    private var isExpanded: Bool {
        activePath.contains(member.id)
    }

    init(member: FamilyMember, childrenByFatherId: [UUID: [FamilyMember]], ancestorIDs: Set<UUID>, activePath: Binding<Set<UUID>>, searchedMemberID: Binding<UUID?>, selectedMember: Binding<FamilyMember?>, scrollTarget: Binding<UUID?>, scrollAnchor: Binding<UnitPoint>, scrollCounter: Binding<Int>, scale: Binding<CGFloat>, baseScale: Binding<CGFloat>, level: Int, viewMode: TreeDisplayMode, lightweightFullTree: Bool, currentLocationMemberID: UUID?, renderedCount: Binding<Int>, maxRendered: Int, kinshipHighlightedIds: Set<UUID> = [], husbandsWithWives: Set<UUID> = [], husbandsAllWivesDeceased: Set<UUID> = []) {
        self.member = member
        self.childrenByFatherId = childrenByFatherId
        self.ancestorIDs = ancestorIDs
        self._activePath = activePath
        self._searchedMemberID = searchedMemberID
        self._selectedMember = selectedMember
        self._scrollTarget = scrollTarget
        self._scrollAnchor = scrollAnchor
        self._scrollCounter = scrollCounter
        self._scale = scale
        self._baseScale = baseScale
        self.level = level
        self.viewMode = viewMode
        self.lightweightFullTree = lightweightFullTree
        self.currentLocationMemberID = currentLocationMemberID
        self._renderedCount = renderedCount
        self.maxRendered = maxRendered
        self.kinshipHighlightedIds = kinshipHighlightedIds
        self.husbandsWithWives = husbandsWithWives
        self.husbandsAllWivesDeceased = husbandsAllWivesDeceased
    }

    private var visibleChildren: [FamilyMember] {
        let allChildren = (childrenByFatherId[member.id] ?? [])
            .filter { $0.id != member.id && !ancestorIDs.contains($0.id) }

        if viewMode == .fullTree {
            return allChildren
        }

        // عند عرض صلة القرابة — فقط الأبناء اللي بمسار القرابة، وإذا ما فيه نرجع فاضي
        if !kinshipHighlightedIds.isEmpty {
            return allChildren.filter { kinshipHighlightedIds.contains($0.id) }
        }

        // إذا فيه فروع مفتوحة، نعرض كل الفروع المفتوحة
        let focusedChildren = allChildren.filter { activePath.contains($0.id) }
        if !focusedChildren.isEmpty {
            return focusedChildren
        }
        return allChildren
    }

    // لون الخطوط — ذهبي عريض إذا جزء من مسار القرابة
    private var isKinshipPath: Bool {
        kinshipHighlightedIds.contains(member.id)
    }

    private var connectorColor: Color {
        isKinshipPath ? DS.Color.warning : DS.Color.primary.opacity(0.6)
    }

    private var connectorWidth: CGFloat {
        isKinshipPath ? 5 : 2
    }

    var body: some View {
        VStack(spacing: 0) {
            TreeMemberNode(
                member: member,
                isExpanded: isExpanded,
                searchedMemberID: $searchedMemberID,
                hasChildren: !(childrenByFatherId[member.id] ?? []).isEmpty,
                childrenCount: (childrenByFatherId[member.id] ?? []).count,
                showName: true,
                viewMode: viewMode,
                lightweightFullTree: lightweightFullTree,
                level: level,
                currentLocationMemberID: currentLocationMemberID,
                isKinshipHighlighted: isKinshipPath,
                hasWives: husbandsWithWives.contains(member.id),
                wifeDeceased: husbandsAllWivesDeceased.contains(member.id)
            ) {
                selectedMember = member
            } onToggle: {
                // هل لهالعقدة مسار أعمق مفتوح (أحد أبنائها ضمن activePath)؟
                let hasDeeperPath = (childrenByFatherId[member.id] ?? []).contains { activePath.contains($0.id) }
                // نركّز على العقدة في حالتي: الفتح، أو التسطيح (إظهار كل الأبناء)
                let focusOnNode = !isExpanded || hasDeeperPath

                func collectDescendants(of parentId: UUID, into set: inout Set<UUID>) {
                    for child in childrenByFatherId[parentId] ?? [] {
                        set.insert(child.id)
                        collectDescendants(of: child.id, into: &set)
                    }
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    if !isExpanded {
                        // فتح — نضيف العقدة للمسار (تظهر كل أبنائها لعدم وجود مسار أعمق)
                        activePath.insert(member.id)
                        scale = TreeConst.openNodeScale
                        baseScale = TreeConst.openNodeScale
                    } else if hasDeeperPath {
                        // مفتوحة وفيها مسار أعمق → سطّح لهالعقدة عشان تظهر كل أبنائها
                        // (نشيل الذرية من المسار ونبقي العقدة نفسها)
                        var idsToRemove: Set<UUID> = []
                        collectDescendants(of: member.id, into: &idsToRemove)
                        activePath.subtract(idsToRemove)
                        searchedMemberID = nil
                        scale = TreeConst.openNodeScale
                        baseScale = TreeConst.openNodeScale
                    } else {
                        // طي — نقفل العقدة وكل ذريتها
                        var idsToRemove: Set<UUID> = [member.id]
                        collectDescendants(of: member.id, into: &idsToRemove)
                        activePath.subtract(idsToRemove)
                        searchedMemberID = nil
                        scale = TreeConst.closeNodeScale
                        baseScale = TreeConst.closeNodeScale
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: TreeConst.scrollDelay)
                    guard !Task.isCancelled else { return }
                    scrollAnchor = .center
                    scrollTarget = focusOnNode ? member.id : (member.fatherId ?? member.id)
                    scrollCounter += 1
                }
            }.id(member.id)
            .onAppear { renderedCount += 1 }

            // ما نعرض الأبناء إلا إذا العقدة مفتوحة فعلياً (في المسار النشط)
            // الوضع التفاعلي: الأبناء يظهرون لما المستخدم يضغط على العقدة فقط
            let isPathOpen = viewMode == .fullTree || activePath.contains(member.id)
            if isPathOpen && renderedCount < maxRendered {
                let childrenToDisplay = self.visibleChildren

                if !childrenToDisplay.isEmpty {
                    let verticalSpacing: CGFloat = viewMode == .fullTree ? 6 : 8
                    let rowSpacing: CGFloat = viewMode == .fullTree ? 16 : 28
                    let connectorHeight: CGFloat = viewMode == .fullTree ? 12 : 16

                    VStack(spacing: verticalSpacing) {
                        Rectangle()
                            .fill(connectorColor)
                            .frame(width: connectorWidth, height: connectorHeight)

                        let chunkSize = viewMode == .fullTree ? 4 : 3
                        let chunkedChildren = stride(from: 0, to: childrenToDisplay.count, by: chunkSize).map {
                            Array(childrenToDisplay[$0..<min($0 + chunkSize, childrenToDisplay.count)])
                        }

                        ForEach(0..<chunkedChildren.count, id: \.self) { rowIndex in
                            let row = chunkedChildren[rowIndex]
                            HStack(alignment: .top, spacing: rowSpacing) {
                                ForEach(row) { child in
                                    RecursiveTreeBranch(
                                        member: child,
                                        childrenByFatherId: childrenByFatherId,
                                        ancestorIDs: ancestorIDs.union([member.id]),
                                        activePath: $activePath,
                                        searchedMemberID: $searchedMemberID,
                                        selectedMember: $selectedMember,
                                        scrollTarget: $scrollTarget,
                                        scrollAnchor: $scrollAnchor,
                                        scrollCounter: $scrollCounter,
                                        scale: $scale,
                                        baseScale: $baseScale,
                                        level: level + 1,
                                        viewMode: viewMode,
                                        lightweightFullTree: lightweightFullTree,
                                        currentLocationMemberID: currentLocationMemberID,
                                        renderedCount: $renderedCount,
                                        maxRendered: maxRendered,
                                        kinshipHighlightedIds: kinshipHighlightedIds,
                                        husbandsWithWives: husbandsWithWives,
                                        husbandsAllWivesDeceased: husbandsAllWivesDeceased
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, viewMode == .fullTree ? 4 : 8)
                }
            }
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
    var hasWives: Bool = false
    var wifeDeceased: Bool = false
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
                        // حلقة خارجية بتدرج لون الرتبة
                        Circle()
                            .stroke(borderGradient, lineWidth: 3)
                            .frame(width: interactiveNodeSize + 4, height: interactiveNodeSize + 4)

                        // الشكل الدائري الرئيسي — تدرج
                        Circle()
                            .fill(nodeGradient)
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .dsSubtleShadow()

                        // الصورة أو الأيقونة (قاعدة: الأنثى بلا صورة → FemaleAvatarView)
                        if member.isFemale {
                            FemaleAvatarView()
                                .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                                .clipShape(Circle())
                        } else if shouldLoadImage, let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: member.fallbackSymbol)
                                    .font(DS.Font.scaled(30))
                                    .foregroundColor(DS.Color.overlayTextMuted)
                            }
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: member.fallbackSymbol)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44)
                                .foregroundColor(DS.Color.overlayTextMuted)
                        }

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
                .overlay(alignment: .topLeading) {
                    // شارة الزوجة — بنفسجي (نفس أيقونة العضو) + أيقونة متوفّى حمراء صغيرة عليها لو متوفّاة.
                    if hasWives {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color(hex: "#8E5BD0")))
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
                            .overlay(alignment: .bottomTrailing) {
                                if wifeDeceased {
                                    Image(systemName: "heart.slash.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .background(Circle().fill(Color(hex: "#8C2A2A")))
                                        .overlay(Circle().stroke(Color.white, lineWidth: 1.2))
                                        .offset(x: 3, y: 3)
                                }
                            }
                    }
                }
                .overlay {
                    // شريط المتوفى — overlay أخير ليكون فوق الدائرة الزرقاء
                    if member.isDeceased ?? false { deathTag }
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
                        .background(isKinshipHighlighted ? DS.Color.warning : DS.Color.primaryDark)
                        .clipShape(SemiCircleShape())
                    }
                    .accessibilityLabel(isExpanded
                        ? L10n.t("طي الأبناء", "Collapse children")
                        : L10n.t("عرض \(childrenCount) أبناء", "Show \(childrenCount) children"))
                    .offset(y: -1)
                    .zIndex(0)
                }
            }.fixedSize()
        }
    }

    private var deathTag: some View {
        VStack {
            Spacer()
            Text(getLifeSpan())
                .font(DS.Font.scaled(14, weight: .black))
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: interactiveLabelWidth, height: interactiveLabelHeight)
                .background(
                    Capsule()
                        .fill(DS.Color.error)
                )
                .offset(y: 5)
        }
        .frame(width: interactiveNodeSize, height: interactiveNodeSize)
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

// MARK: - شجرة العائلة (النساء)

/// صفّ جدول women_members (منفصل عن profiles).
private struct WomenRow: Decodable {
    let id: UUID
    let firstName: String?
    let fullName: String?
    let parentId: UUID?
    let sortOrder: Int?
    let isDeceased: Bool?
    let birthDate: String?
    let deathDate: String?
    let isHiddenFromTree: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case fullName = "full_name"
        case parentId = "parent_id"
        case sortOrder = "sort_order"
        case isDeceased = "is_deceased"
        case birthDate = "birth_date"
        case deathDate = "death_date"
        case isHiddenFromTree = "is_hidden_from_tree"
    }
}

/// طبقة بيانات شجرة النساء — قراءة/إضافة/تعديل/حذف (الكتابة للإدارة عبر RLS).
enum WomenStore {
    static func fetch() async throws -> [FamilyMember] {
        let rows: [WomenRow] = try await SupabaseConfig.client
            .from("women_members")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value
        return rows.map { r in
            FamilyMember(
                id: r.id,
                firstName: r.firstName ?? "",
                fullName: (r.fullName?.isEmpty == false ? r.fullName! : (r.firstName ?? "")),
                birthDate: r.birthDate,
                deathDate: r.deathDate,
                isDeceased: r.isDeceased,
                role: .member,
                fatherId: r.parentId,                 // parent → father لإعادة استخدام الشجرة
                isHiddenFromTree: r.isHiddenFromTree ?? false,
                sortOrder: r.sortOrder ?? 0,
                status: .active,
                gender: "male"                        // شكل العقدة بالأصلي (رجالي)
            )
        }
    }

    static func addChild(parentId: UUID, name: String, sortOrder: Int,
                         birthDate: String? = nil, isDeceased: Bool = false,
                         deathDate: String? = nil) async throws {
        let payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(name),
            "parent_id": AnyEncodable(parentId.uuidString),
            "sort_order": AnyEncodable(sortOrder),
            "gender": AnyEncodable("female"),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none)
        ]
        try await SupabaseConfig.client.from("women_members").insert(payload).execute()
    }

    static func update(id: UUID, fullName: String, isDeceased: Bool, deathDate: String?,
                       birthDate: String?, isHidden: Bool) async throws {
        let first = fullName.components(separatedBy: " ").first ?? fullName
        let payload: [String: AnyEncodable] = [
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(first),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none),
            "birth_date": AnyEncodable(birthDate),
            "is_hidden_from_tree": AnyEncodable(isHidden)
        ]
        try await SupabaseConfig.client.from("women_members").update(payload).eq("id", value: id.uuidString).execute()
    }

    static func delete(id: UUID) async throws {
        try await SupabaseConfig.client.from("women_members").delete().eq("id", value: id.uuidString).execute()
    }
}

/// شاشة «شجرة العائلة (النساء)» — تُفتح من اختصار الرئيسية، تعيد استخدام
/// RecursiveTreeBranch ببيانات women_members. التعديل للإدارة فقط.
struct WomenTreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var allMembers: [FamilyMember] = []
    @State private var childrenByParent: [UUID: [FamilyMember]] = [:]
    @State private var roots: [FamilyMember] = []
    @State private var isLoading = true

    @State private var activePath: Set<UUID> = []
    @State private var searchedMemberID: UUID? = nil
    @State private var selectedWoman: FamilyMember? = nil
    @State private var scrollTarget: UUID? = nil
    @State private var currentAnchor: UnitPoint = .center
    @State private var scrollCounter = 0
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var zoomAnchor: UnitPoint = .center
    @State private var treeContentSize: CGSize = .zero

    @State private var addParent: FamilyMember? = nil
    @State private var editTarget: FamilyMember? = nil

    private var canEdit: Bool { authVM.canEditMembers }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.background.ignoresSafeArea()
            GeometryReader { geometry in
                Group {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if roots.isEmpty {
                        Text(L10n.t("لا توجد بيانات", "No data"))
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                                VStack(spacing: DS.Spacing.xxl) {
                                    ForEach(roots) { root in
                                        branch(for: root)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                                .background(GeometryReader { g in
                                    SwiftUI.Color.clear
                                        .preference(key: TreeContentSizeKey.self, value: g.size)
                                })
                                .onPreferenceChange(TreeContentSizeKey.self) { treeContentSize = $0 }
                                .scaleEffect(scale, anchor: zoomAnchor)
                                .frame(minWidth: geometry.size.width,
                                       minHeight: geometry.size.height, alignment: .center)
                                .padding(.top, DS.Spacing.xxxxl * 3)
                                .padding(.bottom, DS.Spacing.xxxxl * 3)
                                .padding(.horizontal, DS.Spacing.xxxxl)
                            }
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { v in
                                        zoomAnchor = .center
                                        scale = min(max(baseScale * v, TreeConst.minScale), TreeConst.maxScale)
                                    }
                                    .onEnded { v in
                                        scale = min(max(baseScale * v, TreeConst.minScale), TreeConst.maxScale)
                                        baseScale = scale
                                    }
                            )
                            .onChange(of: scrollCounter) { _ in
                                if let id = scrollTarget {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(id, anchor: currentAnchor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                header
                womenToolsBar
            }
        }
        .navigationBarHidden(true)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await load() }
        .sheet(item: $selectedWoman) { w in actionSheet(for: w) }
        .sheet(item: $editTarget) { w in
            WomenEditView(member: w) { Task { await load() } }
        }
        .sheet(item: $addParent) { p in
            WomenEditView(member: nil, parentId: p.id,
                          siblingCount: allMembers.filter { $0.fatherId == p.id }.count) {
                Task { await load() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: L10n.isArabic ? "chevron.right" : "chevron.left")
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(.white)
            }
            ZStack {
                Circle().fill(Color.white.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: "person.2.fill").foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("شجرة العائلة (النساء)", "Family Tree (Women)"))
                    .font(DS.Font.headline).foregroundColor(.white)
                Text(L10n.t("فرع النساء", "Women branch"))
                    .font(DS.Font.caption1).foregroundColor(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DS.Color.gradientPrimary.ignoresSafeArea(edges: .top))
    }

    // بار الأدوات تحت الهيدر — مطابق لشجرة العائلة (البداية + تحديث).
    private var womenToolsBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            womenToolButton(icon: "house.fill", label: L10n.t("البداية", "Home")) {
                resetToRoot()
            }
            womenToolButton(icon: "arrow.clockwise", label: L10n.t("تحديث", "Refresh")) {
                Task { await load() }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .background(DS.Color.background)
    }

    private func womenToolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.scaled(16, weight: .semibold))
                .foregroundColor(DS.Color.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func resetToRoot() {
        guard let first = roots.first else { return }
        withAnimation(DS.Anim.snappy) { activePath = [first.id] }
        currentAnchor = .center
        scrollTarget = first.id
        scrollCounter += 1
    }

    private func branch(for root: FamilyMember) -> some View {
        RecursiveTreeBranch(
            member: root,
            childrenByFatherId: childrenByParent,
            ancestorIDs: [],
            activePath: $activePath,
            searchedMemberID: $searchedMemberID,
            selectedMember: $selectedWoman,
            scrollTarget: $scrollTarget,
            scrollAnchor: $currentAnchor,
            scrollCounter: $scrollCounter,
            scale: $scale,
            baseScale: $baseScale,
            level: 0,
            viewMode: .interactive,
            lightweightFullTree: false,
            currentLocationMemberID: nil,
            renderedCount: .constant(0),
            maxRendered: 4000
        )
    }

    @ViewBuilder
    private func actionSheet(for w: FamilyMember) -> some View {
        NavigationStack {
            List {
                if canEdit {
                    Button {
                        selectedWoman = nil
                        addParent = w
                    } label: {
                        Label(L10n.t("إضافة فرع", "Add branch"), systemImage: "person.badge.plus")
                    }
                    Button {
                        let t = w
                        selectedWoman = nil
                        editTarget = t
                    } label: {
                        Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                    }
                    if w.fatherId != nil {
                        Button(role: .destructive) {
                            selectedWoman = nil
                            Task { try? await WomenStore.delete(id: w.id); await load() }
                        } label: {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                        }
                    }
                } else {
                    Text(L10n.t("للعرض فقط", "View only"))
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .navigationTitle(w.fullName.isEmpty ? w.firstName : w.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { selectedWoman = nil }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .presentationDetents([.medium])
    }

    private func load() async {
        do {
            let fetched = try await WomenStore.fetch()
            let visible = fetched.filter { !$0.isHiddenFromTree && !$0.fullName.isEmpty }
            let ids = Set(visible.map(\.id))
            var byParent: [UUID: [FamilyMember]] = [:]
            for m in visible {
                if let p = m.fatherId { byParent[p, default: []].append(m) }
            }
            for k in byParent.keys { byParent[k]?.sort { $0.sortOrder < $1.sortOrder } }
            let rootList = visible
                .filter { $0.fatherId == nil || !ids.contains($0.fatherId!) }
                .sorted { $0.sortOrder < $1.sortOrder }
            await MainActor.run {
                self.allMembers = visible
                self.childrenByParent = byParent
                self.roots = rootList
                if let first = rootList.first { self.activePath = [first.id] }
                self.isLoading = false
            }
        } catch {
            Log.error("خطأ تحميل شجرة النساء: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
}

/// نموذج إضافة/تعديل عضوة شجرة النساء — مثل الشجرة العامة (اسم + ميلاد + وفاة).
struct WomenEditView: View {
    let member: FamilyMember?          // وضع التعديل
    var parentId: UUID? = nil          // وضع الإضافة (تحت هذا الأب)
    var siblingCount: Int = 0
    let onSaved: () -> Void

    private var isAdd: Bool { member == nil }

    @Environment(\.dismiss) private var dismiss
    @State private var fullName: String = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var isDeceased = false
    @State private var hasDeathDate = false
    @State private var deathDate = Date()
    @State private var isHidden = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("الاسم الكامل", "Full name")) {
                    TextField(L10n.t("الاسم الكامل", "Full name"), text: $fullName)
                }
                Section {
                    Toggle(isOn: $hasBirthDate.animation()) {
                        Label(L10n.t("تاريخ الميلاد معروف", "Birth date known"), systemImage: "calendar")
                    }.tint(DS.Color.primary)
                    if hasBirthDate {
                        DatePicker(L10n.t("تاريخ الميلاد", "Birth date"),
                                   selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section {
                    Toggle(isOn: $isDeceased.animation()) {
                        Label(L10n.t("متوفّاة", "Deceased"), systemImage: "leaf.fill")
                    }.tint(DS.Color.error)
                    if isDeceased {
                        Toggle(isOn: $hasDeathDate.animation()) {
                            Label(L10n.t("أعرف تاريخ الوفاة", "Death date known"), systemImage: "calendar")
                        }.tint(DS.Color.primary)
                        if hasDeathDate {
                            DatePicker(L10n.t("تاريخ الوفاة", "Death date"),
                                       selection: $deathDate, in: ...Date(), displayedComponents: .date)
                        }
                    }
                }
                if !isAdd {
                    Section {
                        Toggle(isOn: Binding(get: { !isHidden }, set: { isHidden = !$0 })) {
                            Label(L10n.t("إظهار في الشجرة", "Show in tree"),
                                  systemImage: isHidden ? "eye.slash" : "eye")
                        }.tint(DS.Color.primary)
                    }
                }
            }
            .navigationTitle(isAdd ? L10n.t("إضافة فرع", "Add branch") : L10n.t("تعديل", "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isAdd ? L10n.t("إضافة", "Add") : L10n.t("حفظ", "Save")) { save() }
                        .disabled(fullName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear {
            guard let m = member else { return }
            fullName = m.fullName.isEmpty ? m.firstName : m.fullName
            isDeceased = m.isDeceased ?? false
            isHidden = m.isHiddenFromTree
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = m.deathDate, let parsed = f.date(from: String(d.prefix(10))) {
                deathDate = parsed; hasDeathDate = true
            }
            if let b = m.birthDate, let parsed = f.date(from: String(b.prefix(10))) {
                birthDate = parsed; hasBirthDate = true
            }
        }
    }

    private func save() {
        let name = fullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let bStr = hasBirthDate ? f.string(from: birthDate) : nil
        let dStr = (isDeceased && hasDeathDate) ? f.string(from: deathDate) : nil
        Task {
            if let m = member {
                try? await WomenStore.update(id: m.id, fullName: name, isDeceased: isDeceased,
                                             deathDate: dStr, birthDate: bStr, isHidden: isHidden)
            } else if let pid = parentId {
                try? await WomenStore.addChild(parentId: pid, name: name, sortOrder: siblingCount,
                                               birthDate: bStr, isDeceased: isDeceased, deathDate: dStr)
            }
            await MainActor.run { isSaving = false; onSaved(); dismiss() }
        }
    }
}
