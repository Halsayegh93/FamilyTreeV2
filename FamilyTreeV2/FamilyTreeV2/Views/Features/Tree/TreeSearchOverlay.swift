import SwiftUI

/// بحث الشجرة — View مستقل عشان تغيير النص ما يعيد رسم الشجرة
struct TreeSearchOverlay: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    let onSelect: (FamilyMember) -> Void

    /// عند `true` تأخذ قائمة النتائج كامل المساحة المتاحة (مناسب داخل sheet/شاشة كاملة).
    /// عند `false` تُحدَّد بـ 280pt (السلوك inline داخل الشجرة).
    var usesFullHeight: Bool = false
    /// عند `true` يركّز الحقل تلقائياً عند الظهور.
    var autoFocus: Bool = false

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchFocused = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var statusFilter: StatusFilter = .all
    @State private var branchFilterRootId: UUID? = nil
    @State private var generationFilter: GenerationFilter = .all
    @FocusState private var fieldFocused: Bool

    @AppStorage("recentTreeSearches") private var recentSearchesData: Data = Data()

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    struct SearchResult: Identifiable {
        let member: FamilyMember
        let score: Double
        let matchContext: String?
        let displayName: String // الاسم الرباعي محسوب مسبقاً
        let generation: Int     // عمق الجيل من الجذر (1 = جذر، 2 = أبناء الجذر، ...)
        let rootId: UUID        // معرّف جذر فرع هذا العضو
        var id: UUID { member.id }
    }

    enum StatusFilter: CaseIterable {
        case all
        case alive
        case deceased

        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .alive: return L10n.t("أحياء", "Alive")
            case .deceased: return L10n.t("متوفين", "Deceased")
            }
        }
    }

    enum GenerationFilter: Equatable, CaseIterable {
        case all, one, two, three, four, fivePlus

        var label: String {
            switch self {
            case .all: return L10n.t("الكل", "All")
            case .one: return "1"
            case .two: return "2"
            case .three: return "3"
            case .four: return "4"
            case .fivePlus: return L10n.t("+5", "5+")
            }
        }

        func matches(_ depth: Int) -> Bool {
            switch self {
            case .all: return true
            case .one: return depth == 1
            case .two: return depth == 2
            case .three: return depth == 3
            case .four: return depth == 4
            case .fivePlus: return depth >= 5
            }
        }
    }

    /// جذور الشجرة (أعضاء بدون أب موجود) — تُستخدم لقائمة فلتر الفرع.
    private var availableRoots: [FamilyMember] {
        let visible = memberVM.allMembers.filter { $0.isHiddenFromTree != true }
        let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        return visible.filter { m in
            guard let fid = m.fatherId else { return true }
            return byId[fid] == nil
        }.sortedForDisplay()
    }

    private var filteredResults: [SearchResult] {
        searchResults.filter { result in
            // فلتر الحالة
            switch statusFilter {
            case .all: break
            case .alive: if result.member.isDeceased == true { return false }
            case .deceased: if result.member.isDeceased != true { return false }
            }
            // فلتر الجيل
            if !generationFilter.matches(result.generation) { return false }
            // فلتر الفرع
            if let rootId = branchFilterRootId, result.rootId != rootId { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            recentSearchesSection
            resultsSection
        }
        .zIndex(100)
        .onAppear {
            if autoFocus {
                // تأخير صغير حتى تظهر لوحة المفاتيح في الـ sheet بسلاسة
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    fieldFocused = true
                }
            }
        }
        .onChange(of: searchText) { newValue in
            debounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                searchResults = []
                statusFilter = .all
                generationFilter = .all
                branchFilterRootId = nil
            } else {
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if !Task.isCancelled {
                        debouncedSearchText = newValue
                        performSearch(query: newValue)
                    }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "magnifyingglass")
                    .font(DS.Font.scaled(14, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }

            TextField(L10n.t("ابحث بالاسم أو الهاتف...", "Search by name or phone..."), text: $searchText, onEditingChanged: { focused in
                isSearchFocused = focused
            })
            .focused($fieldFocused)
            .font(DS.Font.body)
            .multilineTextAlignment(.leading)
            .submitLabel(.search)
            .autocorrectionDisabled()

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
                    isSearchFocused ? DS.Color.primary.opacity(0.4) : DS.Color.inactiveBorder,
                    lineWidth: isSearchFocused ? 1.5 : 1
                )
        )
        .dsGlowShadow()
    }

    // MARK: - Recent Searches Section

    @ViewBuilder
    private var recentSearchesSection: some View {
        if isSearchFocused && searchText.isEmpty && !recentSearches.isEmpty {
            VStack(spacing: DS.Spacing.xs) {
                HStack {
                    Text(L10n.t("بحث سابق", "Recent"))
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer()
                    Button(action: clearRecentSearches) {
                        Text(L10n.t("مسح", "Clear"))
                            .font(DS.Font.scaled(11, weight: .medium))
                            .foregroundColor(DS.Color.error)
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(recentSearches, id: \.self) { query in
                            Button(action: { searchText = query }) {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(DS.Font.scaled(10, weight: .regular))
                                    Text(query)
                                        .font(DS.Font.caption1)
                                }
                                .foregroundColor(DS.Color.primary)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs + 2)
                                .background(DS.Color.primary.opacity(0.08))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                }
            }
            .padding(.top, DS.Spacing.xs)
            .transition(.opacity)
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if !searchResults.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 4) {
                        Text(L10n.t("النتائج", "Results"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                        Text("(\(filteredResults.count))")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xs)

                Picker("", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xs)

                // فلتر الجيل
                generationFilterRow

                // فلتر الفرع (الجذر)
                branchFilterRow

                if filteredResults.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(DS.Font.scaled(16))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد نتائج ضمن هذه التصفية", "No results for this filter"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                    }
                    .padding(DS.Spacing.md)
                } else if filteredResults.count <= 4 {
                    // نتائج قليلة — بدون سكرول، حسب المحتوى
                    VStack(spacing: 0) {
                        ForEach(filteredResults) { result in
                            Button(action: {
                                saveRecentSearch(searchText)
                                fieldFocused = false
                                searchText = ""
                                isSearchFocused = false
                                searchResults = []
                                statusFilter = .all
                                onSelect(result.member)
                            }) {
                                searchResultRow(result)
                            }
                            if result.id != filteredResults.last?.id {
                                Divider().padding(.horizontal, DS.Spacing.md)
                            }
                        }
                    }
                } else {
                    // نتائج كثيرة — سكرول. inline: حد 280pt. fullHeight: يأخذ المساحة المتاحة.
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredResults) { result in
                                Button(action: {
                                    saveRecentSearch(searchText)
                                    fieldFocused = false
                                    searchText = ""
                                    isSearchFocused = false
                                    searchResults = []
                                    statusFilter = .all
                                    onSelect(result.member)
                                }) {
                                    searchResultRow(result)
                                }
                                if result.id != filteredResults.last?.id {
                                    Divider().padding(.horizontal, DS.Spacing.md)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: usesFullHeight ? .infinity : 280)
                }
            }
            .glassCard(radius: DS.Radius.lg)
            .padding(.top, DS.Spacing.xs)
        } else if !debouncedSearchText.isEmpty && searchText == debouncedSearchText {
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
            .padding(.top, DS.Spacing.xs)
        }
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        searchTask?.cancel()
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { searchResults = []; return }

        // snapshot البيانات مرة وحدة
        let members = memberVM.allMembers.filter { $0.isHiddenFromTree != true }
        let lookup = memberVM._memberById

        searchTask = Task {
            let results = await Self.computeResults(raw: raw, members: members, lookup: lookup)
            if !Task.isCancelled {
                searchResults = results
            }
        }
    }

    private static func computeResults(
        raw: String,
        members: [FamilyMember],
        lookup: [UUID: FamilyMember]
    ) async -> [SearchResult] {
        let normalizedQuery = ArabicTextNormalizer.normalizeForSearch(raw)
        let searchWords = normalizedQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if searchWords.isEmpty { return [] }

        let isDigitSearch = raw.allSatisfy { $0.isNumber || $0 == "+" }
        let searchDigits = raw.filter(\.isNumber)
        var results: [SearchResult] = []

        for member in members {
            if Task.isCancelled { return [] }
            var score: Double = 0
            var matchContext: String?

            let normalizedFirst = ArabicTextNormalizer.normalizeForSearch(member.firstName)

            if isDigitSearch && searchDigits.count >= 4 {
                if let phone = member.phoneNumber {
                    let phoneSuffix = String(phone.filter(\.isNumber).suffix(8))
                    if phoneSuffix.contains(searchDigits) || searchDigits.contains(phoneSuffix) {
                        score += 90
                        matchContext = L10n.t("تطابق الهاتف", "Phone match")
                    }
                }
            } else {
                let normalizedFull = ArabicTextNormalizer.normalizeForSearch(member.fullName)
                let fullWords = normalizedFull.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                let allMatch = searchWords.allSatisfy { sw in fullWords.contains { $0.hasPrefix(sw) } }

                if searchWords.count == 1 {
                    // كلمة وحدة — نعرض كل من يبدأ اسمه فيها
                    if normalizedFirst == searchWords[0] {
                        score += 100
                    } else if normalizedFirst.hasPrefix(searchWords[0]) {
                        score += 80
                    } else if allMatch {
                        score += 50
                    }
                } else {
                    // أكثر من كلمة — لازم كل الكلمات تطابق عشان يطلع بالنتائج
                    if allMatch {
                        // نقاط أساسية
                        if normalizedFirst == searchWords[0] {
                            score += 100
                        } else if normalizedFirst.hasPrefix(searchWords[0]) {
                            score += 80
                        } else {
                            score += 50
                        }

                        // أفضلية قوية للاسم الذي يبدأ بنفس عبارة البحث
                        if normalizedFull == normalizedQuery {
                            score += 260
                        } else if normalizedFull.hasPrefix(normalizedQuery) {
                            score += 220
                        }

                        // نقاط إضافية لكل كلمة تطابق بالترتيب
                        var matchedInOrder = 0
                        var wordIdx = 0
                        for sw in searchWords {
                            while wordIdx < fullWords.count {
                                if fullWords[wordIdx].hasPrefix(sw) {
                                    matchedInOrder += 1
                                    wordIdx += 1
                                    break
                                }
                                wordIdx += 1
                            }
                        }
                        score += Double(matchedInOrder) * 30.0
                    }
                }

                // بحث في السيرة فقط إذا ما طابق الاسم
                if score == 0 {
                    if let bio = member.bio, !bio.isEmpty {
                        let bioText = ArabicTextNormalizer.normalizeForSearch(
                            bio.map { "\($0.title) \($0.details)" }.joined(separator: " ")
                        )
                        if searchWords.allSatisfy({ bioText.contains($0) }) {
                            score += 20
                            matchContext = L10n.t("في السيرة", "In bio")
                        }
                    }
                }
            }

            if score > 0 {
                // حساب الاسم الرباعي + الجيل + الجذر مسبقاً
                let displayName = fourPartName(for: member, lookup: lookup)
                let depthAndRoot = generationAndRoot(for: member, lookup: lookup)
                results.append(SearchResult(
                    member: member,
                    score: score,
                    matchContext: matchContext,
                    displayName: displayName,
                    generation: depthAndRoot.depth,
                    rootId: depthAndRoot.rootId
                ))
            }
        }

        return Array(
            results
                .sorted {
                    if $0.score != $1.score {
                        return $0.score > $1.score
                    }
                    return $0.displayName.localizedCompare($1.displayName) == .orderedAscending
                }
                .prefix(50)
        )
    }

    /// عمق العضو من الجذر + معرّف الجذر — للفلترة. آمن ضد المراجع الدائرية.
    private static func generationAndRoot(for member: FamilyMember, lookup: [UUID: FamilyMember]) -> (depth: Int, rootId: UUID) {
        var depth = 1
        var current = member
        var visited: Set<UUID> = [member.id]
        while let fid = current.fatherId, let father = lookup[fid], !visited.contains(fid) {
            depth += 1
            visited.insert(fid)
            current = father
        }
        return (depth, current.id)
    }

    /// الاسم الرباعي + اسم العائلة
    private static func fourPartName(for member: FamilyMember, lookup: [UUID: FamilyMember]) -> String {
        var parts = [member.firstName]
        var current = member
        var visited: Set<UUID> = [member.id]
        while parts.count < 4,
              let fatherId = current.fatherId,
              let father = lookup[fatherId],
              !visited.contains(father.id) {
            parts.append(father.firstName)
            current = father
            visited.insert(father.id)
        }
        // إضافة اسم العائلة (آخر كلمة من الاسم الكامل)
        let fullParts = member.fullName.split(whereSeparator: \.isWhitespace)
        if fullParts.count > 1, let lastName = fullParts.last {
            let lastNameStr = String(lastName)
            if lastNameStr != parts.last {
                parts.append(lastNameStr)
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Filter Rows

    /// صف فلتر الجيل — segmented control بأرقام 1..5+
    private var generationFilterRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
            Text(L10n.t("الجيل", "Generation"))
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.sm)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(GenerationFilter.allCases, id: \.self) { gen in
                        Button {
                            generationFilter = gen
                        } label: {
                            Text(gen.label)
                                .font(DS.Font.scaled(11, weight: generationFilter == gen ? .bold : .medium))
                                .foregroundColor(generationFilter == gen ? .white : DS.Color.primary)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(generationFilter == gen ? DS.Color.primary : DS.Color.primary.opacity(0.10))
                                )
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.xs)
    }

    /// صف فلتر الفرع — chips بأسماء جذور الشجرة. عند الضغط يصبح مفعّلاً.
    @ViewBuilder
    private var branchFilterRow: some View {
        let roots = availableRoots
        if roots.count > 1 {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                Text(L10n.t("الفرع", "Branch"))
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: DS.Spacing.sm)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        // الكل
                        Button {
                            branchFilterRootId = nil
                        } label: {
                            Text(L10n.t("الكل", "All"))
                                .font(DS.Font.scaled(11, weight: branchFilterRootId == nil ? .bold : .medium))
                                .foregroundColor(branchFilterRootId == nil ? .white : DS.Color.accent)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(branchFilterRootId == nil ? DS.Color.accent : DS.Color.accent.opacity(0.10))
                                )
                        }
                        .buttonStyle(DSScaleButtonStyle())

                        ForEach(roots) { root in
                            Button {
                                branchFilterRootId = root.id
                            } label: {
                                Text(root.firstName)
                                    .font(DS.Font.scaled(11, weight: branchFilterRootId == root.id ? .bold : .medium))
                                    .foregroundColor(branchFilterRootId == root.id ? .white : DS.Color.accent)
                                    .padding(.horizontal, DS.Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(branchFilterRootId == root.id ? DS.Color.accent : DS.Color.accent.opacity(0.10))
                                    )
                            }
                            .buttonStyle(DSScaleButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)
        }
    }

    // MARK: - Search Result Row

    private func searchResultRow(_ result: SearchResult) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [result.member.roleColor, result.member.roleColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                if let urlStr = result.member.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Text(String(result.member.firstName.prefix(1)))
                            .font(DS.Font.scaled(14, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Text(String(result.member.firstName.prefix(1)))
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                }

                if result.member.isDeceased ?? false {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.red)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Image(systemName: "heart.slash.fill")
                                        .font(DS.Font.scaled(8, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                )
                        }
                    }
                    .frame(width: 36, height: 36)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(DS.Font.scaled(15, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    Text(result.member.roleName)
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(result.member.roleColor)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(result.member.roleColor.opacity(0.1))
                        .clipShape(Capsule())

                    if result.member.isDeceased ?? false {
                        Text(L10n.t("متوفى", "Deceased"))
                            .font(DS.Font.scaled(9, weight: .medium))
                            .foregroundColor(DS.Color.deceased)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(DS.Color.deceased.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if let context = result.matchContext {
                        Text(context)
                            .font(DS.Font.scaled(9, weight: .medium))
                            .foregroundColor(DS.Color.info)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(DS.Color.info.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left.circle.fill")
                .font(DS.Font.scaled(18))
                .foregroundColor(result.member.roleColor.opacity(0.6))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Recent Searches

    private func saveRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var searches = recentSearches.filter { $0 != trimmed }
        searches.insert(trimmed, at: 0)
        if searches.count > 10 { searches = Array(searches.prefix(10)) }
        recentSearchesData = (try? JSONEncoder().encode(searches)) ?? Data()
    }

    private func clearRecentSearches() {
        recentSearchesData = (try? JSONEncoder().encode([String]())) ?? Data()
    }
}
