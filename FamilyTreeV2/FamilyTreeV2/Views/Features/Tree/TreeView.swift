import SwiftUI
import Foundation

// MARK: - Notification Names
extension Notification.Name {
    static let memberDeleted = Notification.Name("memberDeleted")
    static let showKinshipPath = Notification.Name("showKinshipPath")
}

// MARK: - أنماط العرض
enum TreeDisplayMode: Hashable {
    case interactive // تفاعلي: صور وتفاصيل + ترتيب شبكي
    case fullTree    // كامل: أداء عالي (نص فقط) + ترتيب أفقي كامل (الإخوان جنب بعض)
}

// MARK: - 1. واجهة الشجرة الرئيسية — Liquid Glass
struct TreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var showingTreeEditRequest = false
    @State private var selectedMember: FamilyMember? = nil
    @State private var scrollTarget: UUID? = nil
    @State private var scrollCounter: Int = 0
    @State private var currentLocationMemberID: UUID? = nil
    @State private var isRefreshing = false

    private let viewMode: TreeDisplayMode = .interactive

    @State private var searchedMemberID: UUID? = nil
    @State private var highlightTask: Task<Void, Never>?
    @State private var locationHighlightTask: Task<Void, Never>?

    @State private var scale: CGFloat = 0.60
    @State private var treeID = UUID()
    @State private var currentAnchor: UnitPoint = .center
    @State private var baseScale: CGFloat = 0.60
    @State private var zoomAnchor: UnitPoint = .center

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
        if count > 8000 { return 40 }
        if count > 5000 { return 60 }
        if count > 2000 { return 80 }
        if count > 500 { return 120 }
        return 200
    }

    private var preferredBaseScale: CGFloat { 0.60 }

    private func preferredScaleForCurrentExpansion() -> CGFloat { 0.60 }

    private var currentZoomPercentText: String {
        let zoom = Int((scale * 100).rounded())
        return "\(max(40, min(300, zoom)))%"
    }

    private var primaryRootMember: FamilyMember? {
        cachedRootMembers.first
    }

    /// يُعاد حساب البيانات المُخزنة عند تغيّر الأعضاء فقط
    private func rebuildCache() {
        let visible = memberVM.allMembers.filter {
            !$0.isHiddenFromTree
            && $0.role != .pending
            && $0.status != .frozen
            && !$0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })

        // مجموعة الأعضاء اللي عندهم أبناء (آباء حقيقيين)
        let fatherIds = Set(visible.compactMap(\.fatherId))

        let roots = sortedMembers(visible.filter { member in
            guard let fatherId = member.fatherId else {
                // عضو بدون أب: يظهر كجذر فقط إذا عنده أبناء (جد/أب أصلي)
                return fatherIds.contains(member.id)
            }
            return byId[fatherId] == nil
        })

        let childrenMap = Dictionary(
            grouping: visible.compactMap { m in m.fatherId.map { (m, $0) } },
            by: { $0.1 }
        ).mapValues { pairs in sortedMembers(pairs.map(\.0)) }

        cachedVisibleMembers = visible
        cachedMemberById = byId
        cachedRootMembers = roots
        cachedChildrenByFatherId = childrenMap
        cachedMemberIds = Set(visible.map(\.id))
    }

    private func sortedMembers(_ members: [FamilyMember]) -> [FamilyMember] {
        members.sorted { m1, m2 in
            if m1.sortOrder != m2.sortOrder { return m1.sortOrder < m2.sortOrder }
            if let b1 = m1.birthDate, let b2 = m2.birthDate, !b1.isEmpty, !b2.isEmpty { return b1 < b2 }
            return m1.firstName < m2.firstName
        }
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
                                .scaleEffect(scale, anchor: zoomAnchor)
                                .frame(
                                    minWidth: geometry.size.width,
                                    minHeight: geometry.size.height,
                                    alignment: .center
                                )
                                .padding(.top, DS.Spacing.xxxxl * 2)
                                .padding(.bottom, DS.Spacing.xxxxl * 4)
                                .padding(.horizontal, DS.Spacing.xxxxl)
                            }
                            .simultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        // تحديد نقطة الزوم حسب موقع الأصابع
                                        let loc = value.startLocation
                                        zoomAnchor = UnitPoint(
                                            x: min(max(loc.x / geometry.size.width, 0), 1),
                                            y: min(max(loc.y / geometry.size.height, 0), 1)
                                        )
                                        let newScale = baseScale * value.magnification
                                        scale = min(max(newScale, 0.2), 3.0)
                                    }
                                    .onEnded { value in
                                        let newScale = baseScale * value.magnification
                                        scale = min(max(newScale, 0.2), 3.0)
                                        baseScale = scale
                                    }
                            )
                            .onChange(of: scrollCounter) { _, _ in
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
                        ) {
                            // زر طلب تعديل الشجرة
                            Button(action: {
                                showingTreeEditRequest = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(DS.Color.overlayIcon)
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().stroke(DS.Color.overlayIconBorder, lineWidth: 1))
                                    Image(systemName: "pencil.line")
                                        .font(DS.Font.scaled(16, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel(L10n.t("طلب تعديل الشجرة", "Request tree edit"))

                            // زر الموقع
                            Button(action: {
                                if let currentUserID = authVM.currentUser?.id,
                                   let userMember = cachedMemberById[currentUserID] ?? memberVM.member(byId: currentUserID) {
                                    currentLocationMemberID = userMember.id
                                    centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                                    locationHighlightTask?.cancel()
                                    locationHighlightTask = Task {
                                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                                        guard !Task.isCancelled else { return }
                                        withAnimation { currentLocationMemberID = nil }
                                    }
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(DS.Color.overlayIcon)
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().stroke(DS.Color.overlayIconBorder, lineWidth: 1))
                                    Image(systemName: "location.fill")
                                        .font(DS.Font.scaled(18, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel(L10n.t("موقعي في الشجرة", "My location in tree"))
                        }

                        TreeSearchOverlay(onSelect: { member in
                            selectMemberFromSearch(member)
                        })
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
                                            scale = 0.60
                                            baseScale = 0.60
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
            .navigationBarHidden(true)
            .sheet(item: $selectedMember) { member in
                MemberDetailsView(member: member)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showingTreeEditRequest) {
                TreeEditRequestView()
            }

            .task {
                if cachedVisibleMembers.isEmpty {
                    rebuildCache()
                    currentLocationMemberID = authVM.currentUser?.id
                    // أول تحميل — نبدأ من الجذر بالمنتصف (نفس إعادة الوضع)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    resetToTopRoot(animated: false)
                }
            }
            .onChange(of: memberVM.membersVersion) { _, _ in
                withAnimation(DS.Anim.snappy) {
                    rebuildCache()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDeleted)) { _ in
                // إغلاق شاشة التفاصيل تلقائياً بعد حذف العضو
                withAnimation(DS.Anim.snappy) {
                    selectedMember = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKinshipPath)) { note in
                guard let info = note.userInfo,
                      let memberId = info["memberId"] as? UUID,
                      let relationship = info["relationship"] as? String else { return }

                // بناء مسار كامل من الجذر للعضو الممسوح (عشان كل الفروع تنفتح)
                var fullPath = Set<UUID>()

                // مسار العضو الممسوح من الجذر
                var current = cachedMemberById[memberId]
                while let c = current {
                    fullPath.insert(c.id)
                    if let fid = c.fatherId { current = cachedMemberById[fid] } else { current = nil }
                }

                // مسار المستخدم الحالي من الجذر
                if let myId = authVM.currentUser?.id {
                    var myCurrent = cachedMemberById[myId]
                    while let c = myCurrent {
                        fullPath.insert(c.id)
                        if let fid = c.fatherId { myCurrent = cachedMemberById[fid] } else { myCurrent = nil }
                    }
                }

                // إضافة IDs القرابة إذا موجودة
                if let pathIds = info["pathIds"] as? [UUID] {
                    fullPath.formUnion(pathIds)
                }

                // تصغير الزوم عشان يبان المسار كامل
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = 0.35
                    baseScale = 0.35
                }

                // فتح كل الفروع بالمسار + هايلايت
                withAnimation(.easeInOut(duration: 0.3)) {
                    activePath = fullPath
                    kinshipHighlightedIds = fullPath
                    searchedMemberID = memberId
                    kinshipBanner = relationship
                }

                // سكرول للعضو بعد فتح الفروع
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    scrollTarget = memberId
                    scrollCounter += 1
                }

                // إخفاء البانر والهايلايت بعد 12 ثانية
                Task {
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
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
            try? await Task.sleep(nanoseconds: 250_000_000)
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
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            currentAnchor = .center
            scrollTarget = member.id
            scrollCounter += 1
        }

        // Remove highlight after 5 seconds
        if highlight {
            highlightTask?.cancel()
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { searchedMemberID = nil }
            }
        }
    }

    private func resetToTopRoot(animated: Bool = true) {
        if let root = primaryRootMember {
            // فتح مستويين: الجذر + أبنائه
            var expandedIds: Set<UUID> = [root.id]
            let level2 = cachedChildrenByFatherId[root.id] ?? []
            for child in level2 {
                expandedIds.insert(child.id)
            }
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

    // MARK: - أدوات التكبير والتصغير — Glassy
    private var overlayTools: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Text(currentZoomPercentText)
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 44, height: 44)

                    Divider().frame(width: 30)

                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { scale = min(scale + 0.05, 3.0); baseScale = scale } }) {
                        Image(systemName: "plus")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("تكبير", "Zoom in"))

                    Divider().frame(width: 30)

                    Button(action: {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await memberVM.fetchAllMembers(force: true)
                            guard !Task.isCancelled else { return }
                            rebuildCache()
                            resetToTopRoot()
                            withAnimation { isRefreshing = false }
                        }
                    }) {
                        if isRefreshing {
                            ProgressView()
                                .tint(DS.Color.primary)
                                .scaleEffect(0.7)
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                                .font(DS.Font.scaled(15, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel(L10n.t("تحديث الشجرة", "Refresh tree"))

                    Divider().frame(width: 30)

                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { scale = max(scale - 0.05, 0.2); baseScale = scale } }) {
                        Image(systemName: "minus")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("تصغير", "Zoom out"))
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
            kinshipHighlightedIds: kinshipHighlightedIds
        )
    }

    // MARK: - حالة فارغة
    private var emptyStateView: some View {
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

    /// الفتح يعتمد على activePath كمصدر وحيد للحقيقة
    private var isExpanded: Bool {
        activePath.contains(member.id)
    }

    init(member: FamilyMember, childrenByFatherId: [UUID: [FamilyMember]], ancestorIDs: Set<UUID>, activePath: Binding<Set<UUID>>, searchedMemberID: Binding<UUID?>, selectedMember: Binding<FamilyMember?>, scrollTarget: Binding<UUID?>, scrollAnchor: Binding<UnitPoint>, scrollCounter: Binding<Int>, scale: Binding<CGFloat>, baseScale: Binding<CGFloat>, level: Int, viewMode: TreeDisplayMode, lightweightFullTree: Bool, currentLocationMemberID: UUID?, renderedCount: Binding<Int>, maxRendered: Int, kinshipHighlightedIds: Set<UUID> = []) {
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
    }

    private var visibleChildren: [FamilyMember] {
        let allChildren = (childrenByFatherId[member.id] ?? [])
            .filter { $0.id != member.id && !ancestorIDs.contains($0.id) }

        if viewMode == .fullTree {
            return allChildren
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
        isKinshipPath ? 4 : 2
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
                currentLocationMemberID: currentLocationMemberID
            ) {
                selectedMember = member
            } onToggle: {
                let willExpand = !isExpanded
                withAnimation(.easeInOut(duration: 0.2)) {
                    if willExpand {
                        // نضيف العقدة للمسار بدون ما نشيل الإخوان المفتوحين
                        activePath.insert(member.id)
                        // زوم 75% عند فتح عقدة
                        scale = 0.75
                        baseScale = 0.75
                    } else {
                        // نقفل هالعقدة وكل ذريتها
                        var idsToRemove: Set<UUID> = [member.id]
                        func collectDescendants(of parentId: UUID) {
                            for child in childrenByFatherId[parentId] ?? [] {
                                idsToRemove.insert(child.id)
                                collectDescendants(of: child.id)
                            }
                        }
                        collectDescendants(of: member.id)
                        activePath.subtract(idsToRemove)
                        searchedMemberID = nil
                        // رجوع 60% عند إغلاق العقدة
                        scale = 0.60
                        baseScale = 0.60
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    scrollAnchor = .center
                    // عند الفتح نركز على العقدة، عند الإغلاق نركز على الأب لعرض الإخوان
                    scrollTarget = willExpand ? member.id : (member.fatherId ?? member.id)
                    scrollCounter += 1
                }
            }.id(member.id)
            .onAppear { renderedCount += 1 }

            // ما نعرض الأبناء إلا إذا العقدة مفتوحة فعلياً (في المسار النشط)
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
                                        kinshipHighlightedIds: kinshipHighlightedIds
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
    let onTap: () -> Void
    let onToggle: () -> Void
    @State private var shouldLoadImage = false
    @State private var isPulsing = false
    @State private var arrowGlow = false

    private var isCurrentLocationMember: Bool {
        member.id == currentLocationMemberID
    }

    // لون دائرة الصورة — متوفى رمادي، أحياء حسب الرتبة
    private var nodeAccentColor: Color {
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
                .frame(minWidth: 126, alignment: .top)
                .zIndex(5)
            }

        } else {
            // الوضع التفاعلي — دائري
            VStack(spacing: 0) {
                Button(action: onTap) {
                    ZStack {
                        // حلقة خارجية بلون الرتبة
                        Circle()
                            .stroke(borderColor, lineWidth: 3)
                            .frame(width: interactiveNodeSize + 4, height: interactiveNodeSize + 4)

                        // الشكل الدائري الرئيسي
                        Circle()
                            .fill(nodeAccentColor)
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .dsSubtleShadow()

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
                        } else {
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44)
                                .foregroundColor(DS.Color.overlayTextMuted)
                        }

                        if member.isDeceased ?? false { deathTag }
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
                    // وميض الموقع
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
                            .overlay(Capsule().stroke(borderColor, lineWidth: 2.5))
                    }
                }.foregroundColor(DS.Color.textOnPrimary).zIndex(1)

                // سهم التوسيع — نص دائرة أسفل الاسم
                if hasChildren {
                    Button(action: onToggle) {
                        HStack(spacing: 4) {
                            Text("\(childrenCount)")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .heavy))
                        }
                        .foregroundColor(.white)
                        .frame(width: 60, height: 28)
                        .background(DS.Color.primaryDark)
                        .clipShape(SemiCircleShape())
                    }
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
                .font(DS.Font.scaled(9, weight: .black))
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
        return "\(birth ?? "?")-\(death ?? "?")"
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


