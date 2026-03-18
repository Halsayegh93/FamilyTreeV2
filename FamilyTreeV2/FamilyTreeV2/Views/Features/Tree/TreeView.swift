import SwiftUI
import Foundation

// MARK: - Notification Names
extension Notification.Name {
    static let memberDeleted = Notification.Name("memberDeleted")
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

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearchFocused = false
    @State private var searchedMemberID: UUID? = nil

    @State private var scale: CGFloat = 0.70
    @State private var treeID = UUID()
    @State private var currentAnchor: UnitPoint = .center
    @State private var baseScale: CGFloat = 0.70

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @State private var activePath: Set<UUID> = []

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

    private var preferredBaseScale: CGFloat { 0.70 }

    private func preferredScaleForCurrentExpansion() -> CGFloat { 0.70 }

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
            && !$0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && $0.status != .frozen
        }
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
        cachedMemberIds = Set(visible.map(\.id))
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

        // تقسيم البحث إلى كلمات مستقلة
        let searchWords = normalizedSearch
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        if searchWords.isEmpty { return [] }

        let firstWord = searchWords[0]
        let remainingWords = Array(searchWords.dropFirst())

        var results: [FamilyMember] = []
        for member in cachedVisibleMembers {
            guard results.count < 20 else { break }

            let memberFirstName = member.firstName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            if searchWords.count == 1 {
                // كلمة وحدة → نبحث في كل شي (الاسم الكامل + النسب)
                let lineage = getFullLineage(for: member, lookup: cachedMemberById)
                let combinedText = "\(member.fullName) \(lineage)"
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if combinedText.contains(firstWord) {
                    results.append(member)
                }
            } else {
                // كلمتين أو أكثر → الكلمة الأولى لازم تكون بالاسم الأول
                guard memberFirstName.contains(firstWord) else { continue }

                // باقي الكلمات تُبحث في الاسم الكامل + النسب
                let lineage = getFullLineage(for: member, lookup: cachedMemberById)
                let combinedText = "\(member.fullName) \(lineage)"
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

                let restMatch = remainingWords.allSatisfy { word in
                    combinedText.contains(word)
                }

                if restMatch {
                    results.append(member)
                }
            }
        }
        return results
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
                                VStack(spacing: 0) {
                                    if let root = primaryRootMember {
                                        rootBranch(for: root)
                                            .id(treeID)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                                .scaleEffect(scale, anchor: .center)
                                .frame(
                                    minWidth: geometry.size.width,
                                    minHeight: geometry.size.height
                                )
                                .padding(.top, DS.Spacing.xxxxl * 3)
                                .padding(.bottom, DS.Spacing.xxxxl * 4)
                                .padding(.horizontal, DS.Spacing.xxxxl)
                            }
                            .simultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
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
                            icon: "leaf.fill"
                        ) {
                            // زر طلب تعديل الشجرة
                            Button(action: {
                                showingTreeEditRequest = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
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
                                    Task {
                                        try? await Task.sleep(nanoseconds: 5_000_000_000)
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
                                        .foregroundColor(DS.Color.textOnPrimary)
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel(L10n.t("موقعي في الشجرة", "My location in tree"))
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
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showingTreeEditRequest) {
                TreeEditRequestView()
            }

            .onAppear {
                let isFirstLoad = cachedVisibleMembers.isEmpty
                Task {
                    await memberVM.fetchAllMembers()
                    rebuildCache()
                    if isFirstLoad {
                        currentLocationMemberID = authVM.currentUser?.id
                        resetToTopRoot()
                    }
                }
            }
            .onChange(of: memberVM.allMembers.count) { _, _ in
                rebuildCache()
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
            // شريط البحث
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.primary.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "magnifyingglass")
                            .font(DS.Font.scaled(14, weight: .semibold))
                            .foregroundColor(DS.Color.primary)
                    }

                    TextField(L10n.t("ابحث بالاسم...", "Search by name..."), text: $searchText, onEditingChanged: { focused in
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
                .padding(.vertical, DS.Spacing.sm)
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

            // نتائج البحث
            if !filteredMembers.isEmpty {
                VStack(spacing: 0) {
                    // عدد النتائج
                    HStack {
                        Text(L10n.t("النتائج", "Results"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                        Text("(\(filteredMembers.count))")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredMembers) { member in
                                Button(action: { selectMemberFromSearch(member) }) {
                                    searchResultRow(for: member)
                                }
                                if member.id != filteredMembers.last?.id {
                                    Divider().padding(.horizontal, DS.Spacing.md)
                                }
                            }
                        }
                    }
                }
                .glassCard(radius: DS.Radius.lg)
                .frame(maxHeight: 280)
                .padding(.top, 4)
            } else if !debouncedSearchText.isEmpty && searchText == debouncedSearchText {
                // لا توجد نتائج
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.slash.fill")
                        .font(DS.Font.scaled(16))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("لا توجد نتائج", "No results found"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                }
                .padding(DS.Spacing.md)
                .glassCard(radius: DS.Radius.lg)
                .padding(.top, 4)
            }
        }
        .zIndex(100)
    }
    
    // MARK: - صف نتيجة البحث مع صورة
    private func searchResultRow(for member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // صورة العضو أو الأحرف الأولى
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [member.roleColor, member.roleColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Text(String(member.firstName.prefix(1)))
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Text(String(member.firstName.prefix(1)))
                        .font(DS.Font.scaled(16, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                }

                // مؤشر المتوفى
                if member.isDeceased ?? false {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(DS.Color.deceased)
                                .frame(width: 13, height: 13)
                                .overlay(
                                    Image(systemName: "heart.slash.fill")
                                        .font(DS.Font.scaled(7, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                )
                        }
                    }
                    .frame(width: 44, height: 44)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(getFullLineage(for: member, lookup: cachedMemberById))
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: DS.Spacing.xs) {
                    // الدور
                    Text(member.roleName)
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(member.roleColor)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(member.roleColor.opacity(0.1))
                        .clipShape(Capsule())
                    
                    // عدد الأبناء
                    let childCount = cachedChildrenByFatherId[member.id]?.count ?? 0
                    if childCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2.fill")
                                .font(DS.Font.scaled(8, weight: .medium))
                            Text("\(childCount)")
                                .font(DS.Font.scaled(10, weight: .bold))
                        }
                        .foregroundColor(DS.Color.textTertiary)
                    }

                    if member.isDeceased ?? false {
                        Text(L10n.t("متوفى", "Deceased"))
                            .font(DS.Font.scaled(9, weight: .medium))
                            .foregroundColor(DS.Color.deceased)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(DS.Color.deceased.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left.circle.fill")
                .font(DS.Font.scaled(18))
                .foregroundColor(member.roleColor.opacity(0.6))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
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
        // فتح المسار بأنيميشن سريعة
        withAnimation(.easeInOut(duration: 0.25)) {
            activePath = ancestors
            activePath.insert(member.id)
        }
        // الانتقال للعضو بعد بناء العقد
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
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
            currentAnchor = .center
            scrollTarget = member.id
            scrollCounter += 1
        }
        
        // Remove highlight after 3 seconds
        if highlight {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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

                    Divider().frame(width: 30)

                    Button(action: {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await memberVM.fetchAllMembers(force: true)
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

                    Divider().frame(width: 30)

                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { scale = max(scale - 0.05, 0.2); baseScale = scale } }) {
                        Image(systemName: "minus")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
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
            level: 0,
            viewMode: viewMode,
            lightweightFullTree: lightweightFullTree,
            currentLocationMemberID: currentLocationMemberID,
            renderedCount: .constant(0),
            maxRendered: maxRenderedNodes
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
        DS.Color.background
    }

    var body: some View {
        ZStack {
            baseColor

            // تدرج خفيف بدون GeometryReader
            LinearGradient(
                colors: [
                    DS.Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // شبكة خطوط بسيطة (خفيفة على الأداء)
            Color.clear
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
    @Binding var renderedCount: Int
    let maxRendered: Int

    /// الفتح يعتمد على activePath كمصدر وحيد للحقيقة
    private var isExpanded: Bool {
        activePath.contains(member.id)
    }

    init(member: FamilyMember, childrenByFatherId: [UUID: [FamilyMember]], ancestorIDs: Set<UUID>, activePath: Binding<Set<UUID>>, searchedMemberID: Binding<UUID?>, selectedMember: Binding<FamilyMember?>, scrollTarget: Binding<UUID?>, scrollAnchor: Binding<UnitPoint>, scrollCounter: Binding<Int>, level: Int, viewMode: TreeDisplayMode, lightweightFullTree: Bool, currentLocationMemberID: UUID?, renderedCount: Binding<Int>, maxRendered: Int) {
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
        self._renderedCount = renderedCount
        self.maxRendered = maxRendered
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
                let willExpand = !isExpanded
                withAnimation(.easeInOut(duration: 0.2)) {
                    if willExpand {
                        // نضيف العقدة للمسار بدون ما نشيل الإخوان المفتوحين
                        activePath.insert(member.id)
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
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
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
                                        currentLocationMemberID: currentLocationMemberID,
                                        renderedCount: $renderedCount,
                                        maxRendered: maxRendered
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

    // لون دائرة الصورة — موحّد لكل الأحياء بلون التطبيق
    private var nodeAccentColor: Color {
        if member.isDeceased == true {
            return Color.gray.opacity(0.7)
        }
        return DS.Color.primary
    }

    // لون الإطار — حسب الدور
    private var borderColor: Color {
        if member.isDeceased == true {
            return DS.Color.deceased.opacity(0.5)
        }
        switch member.role {
        case .admin: return DS.Color.adminRole.opacity(0.6)
        case .supervisor: return DS.Color.supervisorRole.opacity(0.6)
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
                                .shadow(color: nodeAccentColor.opacity(0.25), radius: 6, y: 2)

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
                            .fill(nodeAccentColor.opacity(0.85))
                            .frame(width: interactiveNodeSize, height: interactiveNodeSize)
                            .shadow(color: nodeAccentColor.opacity(0.2), radius: 6, y: 3)

                        // الصورة أو الأيقونة
                        if shouldLoadImage, let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.fill")
                                    .font(DS.Font.scaled(30))
                                    .foregroundColor(.white.opacity(0.7))
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
                            .shadow(color: DS.Color.primaryDark.opacity(0.7), radius: 14)
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DS.Color.currentLocation)
                            .clipShape(Capsule())
                            .offset(y: -16)
                    }
                }
                .onAppear {
                    // تأخير تحميل الصور حسب المستوى لتحسين الأداء
                    if level <= 1 {
                        shouldLoadImage = true
                    } else {
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(level) * 200_000_000)
                            shouldLoadImage = true
                        }
                    }
                }

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
                                    .shadow(color: DS.Color.primary.opacity(arrowGlow ? 0.8 : 0.4), radius: arrowGlow ? 12 : 6, y: 3)
                                    .overlay(Circle().stroke(LinearGradient(colors: [Color.white, Color.white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                                    .scaleEffect(arrowGlow ? 1.12 : 1.0)

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(DS.Font.scaled(18, weight: .black))
                                    .foregroundColor(DS.Color.textOnPrimary)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            }
                            .frame(width: interactiveLabelWidth, alignment: .center)
                            .onAppear {
                                if level <= 2 && !isExpanded {
                                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                        arrowGlow = true
                                    }
                                }
                            }
                            .onChange(of: isExpanded) { _, expanded in
                                if expanded && level <= 2 {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        arrowGlow = false
                                    }
                                }
                            }
                        }
                    }
                }.foregroundColor(DS.Color.textOnPrimary).zIndex(1)
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


