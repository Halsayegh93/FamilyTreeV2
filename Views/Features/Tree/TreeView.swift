import SwiftUI
import Foundation

// MARK: - أنماط العرض
enum TreeDisplayMode: Hashable {
    case interactive // تفاعلي: صور وتفاصيل + ترتيب شبكي
    case fullTree    // كامل: أداء عالي (نص فقط) + ترتيب أفقي كامل (الإخوان جنب بعض)
}

// MARK: - 1. واجهة الشجرة الرئيسية — Liquid Glass
struct TreeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var selectedMember: FamilyMember? = nil
    @State private var scrollTarget: UUID? = nil
    @State private var scrollCounter: Int = 0
    @State private var currentLocationMemberID: UUID? = nil
    @State private var isRefreshing = false

    private let viewMode: TreeDisplayMode = .interactive

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearchFocused = false
    @State private var searchedMemberID: UUID? = nil

    @State private var scale: CGFloat = 1.0
    @State private var treeID = UUID()
    @State private var currentAnchor: UnitPoint = .center
    @GestureState private var gestureZoom: CGFloat = 1.0

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @State private var activePath: Set<UUID> = []

    // MARK: - بيانات مُخزنة مؤقتاً لتجنب إعادة الحساب كل render
    @State private var cachedVisibleMembers: [FamilyMember] = []
    @State private var cachedMemberById: [UUID: FamilyMember] = [:]
    @State private var cachedRootMembers: [FamilyMember] = []
    @State private var cachedChildrenByFatherId: [UUID: [FamilyMember]] = [:]

    private var lightweightFullTree: Bool {
        cachedVisibleMembers.count > 90
    }

    private var preferredBaseScale: CGFloat {
        let count = cachedVisibleMembers.count
        if count > 140 { return 0.7 }
        if count > 100 { return 0.78 }
        if count > 70 { return 0.88 }
        if count > 40 { return 0.98 }
        return 1.14
    }

    private func preferredScaleForCurrentExpansion() -> CGFloat {
        let expansionPenalty = min(CGFloat(activePath.count) * 0.03, 0.22)
        return max(0.45, preferredBaseScale - expansionPenalty)
    }

    private var currentZoomPercentText: String {
        let zoom = Int((scale * gestureZoom * 100).rounded())
        return "\(max(40, min(300, zoom)))%"
    }

    private var primaryRootMember: FamilyMember? {
        cachedRootMembers.first
    }

    /// يُعاد حساب البيانات المُخزنة عند تغيّر الأعضاء فقط
    private func rebuildCache() {
        let visible = authVM.allMembers.filter { !$0.isHiddenFromTree }
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })

        let roots = sortedMembers(visible.filter { member in
            guard let fatherId = member.fatherId else { return true }
            return byId[fatherId] == nil
        })

        let childrenMap = Dictionary(
            grouping: visible.filter { $0.fatherId != nil },
            by: { $0.fatherId! }
        ).mapValues(sortedMembers)

        cachedVisibleMembers = visible
        cachedMemberById = byId
        cachedRootMembers = roots
        cachedChildrenByFatherId = childrenMap
    }

    private func sortedMembers(_ members: [FamilyMember]) -> [FamilyMember] {
        members.sorted { m1, m2 in
            if m1.sortOrder != m2.sortOrder { return m1.sortOrder < m2.sortOrder }
            if let b1 = m1.birthDate, let b2 = m2.birthDate, !b1.isEmpty, !b2.isEmpty { return b1 < b2 }
            return m1.firstName < m2.firstName
        }
    }

    var filteredMembers: [FamilyMember] {
        let normalizedSearch = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSearch.isEmpty { return [] }
        let folded = normalizedSearch.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return cachedVisibleMembers.filter { member in
            !(member.isDeceased ?? false) &&
            getFullLineage(for: member, lookup: cachedMemberById)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(folded)
        }.prefix(20).map { $0 }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    // خلفية جديدة Liquid Glass
                    BoldTreeBackground()
                        .edgesIgnoringSafeArea(.all)

                    if cachedVisibleMembers.isEmpty {
                        emptyStateView
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                                ZStack(alignment: .center) {
                                    if let root = primaryRootMember {
                                        rootBranch(for: root)
                                            .scaleEffect(scale * gestureZoom)
                                            .id(treeID)
                                            .gesture(
                                                MagnificationGesture()
                                                    .updating($gestureZoom) { value, state, _ in
                                                        state = value
                                                    }
                                                    .onEnded { value in
                                                        let newScale = scale * value
                                                        scale = min(max(newScale, 0.4), 3.0)
                                                    }
                                            )
                                    }
                                }
                                .frame(
                                    minWidth: geometry.size.width,
                                    minHeight: geometry.size.height
                                )
                                .padding(.vertical, 150)
                                .padding(.horizontal, 50)
                            }
                            .onChange(of: scrollCounter) { _, _ in
                                if let id = scrollTarget {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        proxy.scrollTo(id, anchor: .center)
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
                            subtitle: "\(cachedVisibleMembers.count) " + L10n.t("عضو", "members") + " • " + "\(cachedRootMembers.count) " + L10n.t("جذور", "roots"),
                            icon: "leaf.fill"
                        ) {
                            // زر تحديث الشجرة
                            Button(action: {
                                guard !isRefreshing else { return }
                                isRefreshing = true
                                Task {
                                    await authVM.fetchAllMembers()
                                    rebuildCache()
                                    withAnimation { isRefreshing = false }
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                    if isRefreshing {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(DS.Font.scaled(16, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(BounceButtonStyle())
                            .disabled(isRefreshing)

                            // زر الموقع
                            Button(action: {
                                if let currentUserID = authVM.currentUser?.id,
                                   let userMember = cachedMemberById[currentUserID] ?? authVM.allMembers.first(where: { $0.id == currentUserID }) {
                                    currentLocationMemberID = userMember.id
                                    centerOnMember(userMember, highlight: true, includeFocusedMemberInPath: false)
                                    Task {
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        withAnimation { currentLocationMemberID = nil }
                                    }
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                    Image(systemName: "location.fill")
                                        .font(DS.Font.scaled(18, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(BounceButtonStyle())
                        }

                        searchOverlay
                            .padding(.horizontal, DS.Spacing.sm)

                    }
                    .zIndex(101)

                    if !cachedVisibleMembers.isEmpty {
                        overlayTools
                    }
                }
                .onTapGesture {
                    isSearchFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) // MainActor safe
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedMember) { member in
                MemberDetailsView(member: member)
                    .onDisappear { searchedMemberID = nil }
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                Task {
                    await authVM.fetchAllMembers()
                    rebuildCache()
                    currentLocationMemberID = authVM.currentUser?.id
                    resetToTopRoot()
                }
            }
            .onChange(of: authVM.allMembers.count) { _, _ in
                rebuildCache()
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                if newValue.isEmpty {
                    debouncedSearchText = ""
                } else {
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 ثانية
                        if !Task.isCancelled {
                            debouncedSearchText = newValue
                        }
                    }
                }
            }
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

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: DS.Spacing.md - 2) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.primary.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "magnifyingglass")
                            .font(DS.Font.scaled(14, weight: .semibold))
                            .foregroundColor(DS.Color.primary)
                    }

                    TextField(L10n.t("ابحث عن فرد...", "Search member..."), text: $searchText, onEditingChanged: { focused in
                        isSearchFocused = focused
                    })
                    .font(DS.Font.body)
                    .multilineTextAlignment(.leading)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.error.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "xmark")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(DS.Color.error)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md - 2)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(
                            isSearchFocused ? DS.Color.primary.opacity(0.4) : Color.gray.opacity(0.12),
                            lineWidth: isSearchFocused ? 1.5 : 1
                        )
                )
                .shadow(color: isSearchFocused ? DS.Color.primary.opacity(0.1) : .clear, radius: 8)
            }

            if !filteredMembers.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredMembers) { member in
                            Button(action: { selectMemberFromSearch(member) }) {
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [member.roleColor, member.roleColor.opacity(0.7)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 28, height: 28)
                                        Text(String(member.firstName.prefix(1)))
                                            .font(DS.Font.scaled(11, weight: .bold))
                                            .foregroundColor(.white)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(getFullLineage(for: member, lookup: cachedMemberById))
                                            .font(DS.Font.scaled(13, weight: .semibold))
                                            .foregroundColor(DS.Color.textPrimary)
                                            .lineLimit(1)
                                        Text(member.roleName)
                                            .font(DS.Font.scaled(10))
                                            .foregroundColor(DS.Color.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left.circle.fill")
                                        .font(DS.Font.scaled(16))
                                        .foregroundColor(member.roleColor.opacity(0.7))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            }
                            if member.id != filteredMembers.last?.id {
                                Divider().padding(.horizontal, 10)
                            }
                        }
                    }
                }
                .glassCard(radius: DS.Radius.lg)
                .frame(maxHeight: 220)
                .padding(.top, 4)
            }
        }
        .zIndex(100)
    }

    private func selectMemberFromSearch(_ member: FamilyMember) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searchText = ""
        isSearchFocused = false
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
        // فتح المسار
        withAnimation(.spring()) {
            activePath = ancestors
            activePath.insert(member.id)
        }
        // الانتقال للعضو بعد بناء العقد
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
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
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
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
            try? await Task.sleep(nanoseconds: 500_000_000)
            scrollTarget = member.id
            scrollCounter += 1
        }
        
        // Remove highlight after 4 seconds
        if highlight {
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { searchedMemberID = nil }
            }
        }
    }

    private func resetToTopRoot(animated: Bool = true) {
        if let root = primaryRootMember {
            let updates = {
                scale = preferredBaseScale
                activePath.removeAll()
                searchedMemberID = nil
                treeID = UUID()
                scrollTarget = root.id
                scrollCounter += 1
            }
            if animated {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { updates() }
            } else {
                updates()
            }
        }
    }

    // MARK: - أدوات التكبير والتصغير — Glassy
    private var overlayTools: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Spacer()
                VStack(spacing: 0) {
                    Text(currentZoomPercentText)
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))

                    Divider()
                        .frame(width: 30)
                        .background(Color.gray.opacity(0.2))

                    // زر تكبير
                    Button(action: { withAnimation(.easeInOut(duration: 0.3)) { scale = min(scale + 0.15, 3.0) } }) {
                        Image(systemName: "plus")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(width: 30)
                        .background(Color.gray.opacity(0.2))

                    // زر إعادة
                    Button(action: { resetToTopRoot() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(width: 30)
                        .background(Color.gray.opacity(0.2))

                    // زر تصغير
                    Button(action: { withAnimation(.easeInOut(duration: 0.3)) { scale = max(scale - 0.15, 0.4) } }) {
                        Image(systemName: "minus")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                    }
                    .buttonStyle(.plain)
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                .padding(.bottom, DS.Spacing.xxl)
            }.padding(.horizontal, DS.Spacing.xl)
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
            level: 0,
            viewMode: viewMode,
            lightweightFullTree: lightweightFullTree,
            currentLocationMemberID: currentLocationMemberID
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


// MARK: - خلفية الشجرة — Bold Dynamic مع تدرجات قوية
private struct BoldTreeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var baseColor: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    var body: some View {
        ZStack {
            baseColor

            // دوائر زخرفية أكبر وأجرأ
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                DS.Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 240
                        )
                    )
                    .frame(width: 480, height: 480)
                    .offset(x: -100, y: -100)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                DS.Color.accent.opacity(colorScheme == .dark ? 0.08 : 0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
                    .frame(width: 560, height: 560)
                    .offset(x: geo.size.width - 200, y: geo.size.height - 200)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                DS.Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.4)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                DS.Color.accent.opacity(colorScheme == .dark ? 0.03 : 0.025),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(x: geo.size.width * 0.7, y: geo.size.height * 0.15)
            }

            // شبكة خطوط — أكثر وضوحاً
            Canvas { context, size in
                let spacing: CGFloat = colorScheme == .dark ? 36 : 34
                var highlight = Path()
                var shadow = Path()

                var x: CGFloat = 0
                while x <= size.width + spacing {
                    highlight.move(to: CGPoint(x: x, y: 0))
                    highlight.addLine(to: CGPoint(x: x, y: size.height))
                    shadow.move(to: CGPoint(x: x + 1, y: 0))
                    shadow.addLine(to: CGPoint(x: x + 1, y: size.height))
                    x += spacing
                }

                var y: CGFloat = 0
                while y <= size.height + spacing {
                    highlight.move(to: CGPoint(x: 0, y: y))
                    highlight.addLine(to: CGPoint(x: size.width, y: y))
                    shadow.move(to: CGPoint(x: 0, y: y + 1))
                    shadow.addLine(to: CGPoint(x: size.width, y: y + 1))
                    y += spacing
                }

                let hOpacity = colorScheme == .dark ? 0.025 : 0.05
                let sOpacity = colorScheme == .dark ? 0.05 : 0.03

                context.stroke(highlight, with: .color(.white.opacity(hOpacity)), lineWidth: 0.6)
                context.stroke(shadow, with: .color(.black.opacity(sOpacity)), lineWidth: 0.6)
            }
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
    let level: Int

    var viewMode: TreeDisplayMode
    let lightweightFullTree: Bool
    let currentLocationMemberID: UUID?

    @State private var isExpanded: Bool

    init(member: FamilyMember, childrenByFatherId: [UUID: [FamilyMember]], ancestorIDs: Set<UUID>, activePath: Binding<Set<UUID>>, searchedMemberID: Binding<UUID?>, selectedMember: Binding<FamilyMember?>, scrollTarget: Binding<UUID?>, scrollAnchor: Binding<UnitPoint>, scrollCounter: Binding<Int>, level: Int, viewMode: TreeDisplayMode, lightweightFullTree: Bool, currentLocationMemberID: UUID?) {
        self.member = member
        self.childrenByFatherId = childrenByFatherId
        self.ancestorIDs = ancestorIDs
        self._activePath = activePath
        self._searchedMemberID = searchedMemberID
        self._selectedMember = selectedMember
        self._scrollTarget = scrollTarget
        self._scrollAnchor = scrollAnchor
        self._scrollCounter = scrollCounter
        self.level = level
        self.viewMode = viewMode
        self.lightweightFullTree = lightweightFullTree
        self.currentLocationMemberID = currentLocationMemberID
        self._isExpanded = State(initialValue: level == 0)
    }

    private var visibleChildren: [FamilyMember] {
        let allChildren = (childrenByFatherId[member.id] ?? [])
            .filter { $0.id != member.id && !ancestorIDs.contains($0.id) }

        if viewMode == .fullTree {
            return allChildren
        }

        if let focusedChild = allChildren.first(where: { activePath.contains($0.id) }) {
            return [focusedChild]
        }
        return allChildren
    }

    // لون موحّد للخطوط
    private var connectorColor: Color {
        DS.Color.primary.opacity(0.45)
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
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                    if isExpanded {
                        activePath = ancestorIDs.union([member.id])
                    } else {
                        activePath = ancestorIDs
                        searchedMemberID = nil
                    }
                }
                // بعد فتح العقدة، ننتقل للعضو ليكون في النص مع أبنائه
                if isExpanded {
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        scrollTarget = member.id
                        scrollCounter += 1
                    }
                }
            }.id(member.id)

            let isPathOpen = viewMode == .fullTree || activePath.contains(member.id) || isExpanded

            if isPathOpen {
                let childrenToDisplay = self.visibleChildren

                if !childrenToDisplay.isEmpty {
                    let verticalSpacing: CGFloat = viewMode == .fullTree ? 6 : 8
                    let rowSpacing: CGFloat = viewMode == .fullTree ? 16 : 28
                    let connectorHeight: CGFloat = viewMode == .fullTree ? 12 : 16

                    VStack(spacing: verticalSpacing) {
                        // خط الربط العمودي من الأب
                        Rectangle()
                            .fill(connectorColor)
                            .frame(width: 2, height: connectorHeight)

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
                                        level: level + 1,
                                        viewMode: viewMode,
                                        lightweightFullTree: lightweightFullTree,
                                        currentLocationMemberID: currentLocationMemberID
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

    private var isCurrentLocationMember: Bool {
        member.id == currentLocationMemberID
    }

    // لون دائرة الصورة — موحّد لكل الأحياء بلون التطبيق
    private var nodeAccentColor: Color {
        if member.isDeceased == true {
            return Color.gray.opacity(0.7)
        }
        return DS.Color.primary
    }

    // لون الإطار — بنفسجي للمدير، برتقالي للمشرف، لون التطبيق فاتح للباقي
    private var borderColor: Color {
        if member.isDeceased == true {
            return Color.gray.opacity(0.5)
        }
        switch member.role {
        case .admin: return .purple.opacity(0.6)
        case .supervisor: return .orange.opacity(0.6)
        default: return DS.Color.primary.opacity(0.5)
        }
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
                                    ? Color.gray.opacity(0.7)
                                    : nodeAccentColor.opacity(0.9)
                            )
                            .frame(width: 14, height: 14)

                        Text(fullDisplayName)
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if member.isDeceased ?? false {
                            Text(getLifeSpan())
                                .font(DS.Font.scaled(8, weight: .black))
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(DS.Color.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(borderColor, lineWidth: 2.5)
                    )
                    .overlay {
                        if isCurrentLocationMember {
                            Capsule()
                                .stroke(Color(red: 0.56, green: 0.95, blue: 0.66), lineWidth: 2.8)
                                .scaleEffect(isPulsing ? 1.3 : 1.0)
                                .opacity(isPulsing ? 0.0 : 0.9)
                                .shadow(color: Color(red: 0.56, green: 0.95, blue: 0.66).opacity(0.45), radius: 7)
                                .animation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
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
                                .shadow(color: nodeAccentColor.opacity(0.25), radius: 6, y: 2)

                            Text(String(fullDisplayName.prefix(1)))
                                .font(DS.Font.scaled(19, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                    .overlay {
                        if isCurrentLocationMember {
                            Circle()
                                .stroke(Color(red: 0.56, green: 0.95, blue: 0.66), lineWidth: 4.2)
                                .frame(width: 64, height: 64)
                                .scaleEffect(isPulsing ? 1.4 : 1.0)
                                .opacity(isPulsing ? 0.0 : 0.9)
                                .shadow(color: Color(red: 0.56, green: 0.95, blue: 0.66).opacity(0.5), radius: 10)
                                .animation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
                                .onAppear { isPulsing = true }
                        }
                    }
                    .overlay(alignment: .top) {
                        if isCurrentLocationMember {
                            Text(L10n.t("موقعك ( أنا )", "Your Location (Me)"))
                                .font(DS.Font.scaled(10, weight: .bold))
                                .foregroundColor(.black.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.56, green: 0.95, blue: 0.66))
                                .clipShape(Capsule())
                                .offset(y: -14)
                        }
                    }

                    Text(fullDisplayName)
                        .font(DS.Font.scaled(10, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 60, minHeight: 22)
                        .background(DS.Color.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(borderColor, lineWidth: 2.5))
                }
                .frame(minWidth: 126, alignment: .top)
                .zIndex(5)
            }

        } else {
            // الوضع التفاعلي — Liquid Glass
            VStack(spacing: 0) {
                Button(action: onTap) {
                    ZStack {
                        // حلقة خارجية بلون الرتبة
                        Circle()
                            .stroke(borderColor, lineWidth: 3)
                            .frame(width: interactiveNodeSize + 4, height: interactiveNodeSize + 4)

                        // الدائرة الرئيسية
                        Circle()
                            .fill(nodeAccentColor.opacity(0.85))
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .shadow(color: nodeAccentColor.opacity(0.2), radius: 6, y: 3)

                        // الصورة أو الأيقونة
                        if shouldLoadImage, let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(DS.Font.scaled(30))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        if member.isDeceased ?? false { deathTag }
                    }
                }
                .overlay {
                    // حلقة البحث المتوهجة — overlay لا يأثر على الـ layout
                    if searchedMemberID == member.id {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [DS.Color.success, DS.Color.success.opacity(0.5)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: interactiveNodeSize + 10, height: interactiveNodeSize + 10)
                            .shadow(color: DS.Color.success.opacity(0.4), radius: 8)
                    }
                }
                .overlay {
                    // وميض الموقع — overlay لا يأثر على الـ layout
                    if isCurrentLocationMember {
                        Circle()
                            .stroke(Color(red: 0.56, green: 0.95, blue: 0.66), lineWidth: 4.2)
                            .frame(width: interactiveNodeSize + 10, height: interactiveNodeSize + 10)
                            .scaleEffect(isPulsing ? 1.35 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.9)
                            .shadow(color: Color(red: 0.56, green: 0.95, blue: 0.66).opacity(0.5), radius: 12)
                            .animation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
                            .onAppear { isPulsing = true }
                    }
                }
                .overlay(alignment: .top) {
                    // علامة "موقعك" — overlay لا يأثر على الـ layout
                    if isCurrentLocationMember {
                        Text(L10n.t("موقعك ( أنا )", "Your Location (Me)"))
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(.black.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.56, green: 0.95, blue: 0.66))
                            .clipShape(Capsule())
                            .offset(y: -16)
                    }
                }
                .onAppear { shouldLoadImage = true }

                Button(action: onToggle) {
                    VStack(spacing: 4) {
                        if showName {
                            ZStack {
                                Text(displayName)
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 24)

                                if childrenCount > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(childrenCount)")
                                            .font(DS.Font.scaled(11, weight: .black))
                                            .foregroundColor(DS.Color.textPrimary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DS.Color.textPrimary.opacity(0.08))
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                    .environment(\.layoutDirection, .leftToRight)
                                    .padding(.leading, 4)
                                }
                            }
                            .frame(minWidth: interactiveLabelWidth)
                            .frame(height: interactiveLabelHeight + 2, alignment: .center)
                            .background(DS.Color.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(borderColor, lineWidth: 2.5))
                        }

                        if hasChildren {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.gradientPrimary)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: DS.Color.primary.opacity(0.4), radius: 6, y: 3)
                                    .overlay(Circle().stroke(LinearGradient(colors: [Color.white, Color.white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(DS.Font.scaled(18, weight: .black))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            }
                            .frame(width: interactiveLabelWidth, alignment: .center)
                        }
                    }
                }.foregroundColor(.white).zIndex(1)
            }.fixedSize()
        }
    }

    private var deathTag: some View {
        VStack {
            Spacer()
            Text(getLifeSpan())
                .font(DS.Font.scaled(9, weight: .black))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: interactiveLabelWidth, height: interactiveLabelHeight)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [DS.Color.error, DS.Color.error.opacity(0.8)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
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
        return L10n.t("غير معروف", "Unknown")
    }

    private var fullDisplayName: String {
        let full = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let first = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        return L10n.t("غير معروف", "Unknown")
    }

    private var interactiveNodeSize: CGFloat { 105 }
    private var interactiveLabelWidth: CGFloat { 110 }
    private var interactiveLabelHeight: CGFloat { 28 }
}

