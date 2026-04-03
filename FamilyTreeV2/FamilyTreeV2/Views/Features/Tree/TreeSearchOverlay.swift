import SwiftUI

/// بحث الشجرة — View مستقل عشان تغيير النص ما يعيد رسم الشجرة
struct TreeSearchOverlay: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    let onSelect: (FamilyMember) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchFocused = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?

    @AppStorage("recentTreeSearches") private var recentSearchesData: Data = Data()

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    struct SearchResult: Identifiable {
        let member: FamilyMember
        let score: Double
        let matchContext: String?
        let displayName: String // الاسم الرباعي محسوب مسبقاً
        var id: UUID { member.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            recentSearchesSection
            resultsSection
        }
        .zIndex(100)
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                searchResults = []
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
                                        .font(.system(size: 10))
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
                    Text(L10n.t("النتائج", "Results"))
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                    Text("(\(searchResults.count))")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xs)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                saveRecentSearch(searchText)
                                searchText = ""
                                isSearchFocused = false
                                searchResults = []
                                onSelect(result.member)
                            }) {
                                searchResultRow(result)
                            }
                            if result.id != searchResults.last?.id {
                                Divider().padding(.horizontal, DS.Spacing.md)
                            }
                        }
                    }
                }
            }
            .glassCard(radius: DS.Radius.lg)
            .frame(maxHeight: 280)
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

                // تطابق الاسم الأول
                if normalizedFirst == searchWords[0] {
                    score += 100
                } else if normalizedFirst.hasPrefix(searchWords[0]) {
                    score += 80
                }

                // نقاط إضافية لكل كلمة بحث تطابق بالترتيب — اللي يطابق أكثر يطلع أول
                if searchWords.count > 1 && score > 0 {
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
                    // كل كلمة مطابقة بالترتيب تضيف 30 نقطة
                    score += Double(matchedInOrder) * 30.0
                }

                let allMatch = searchWords.allSatisfy { sw in fullWords.contains { $0.hasPrefix(sw) } }

                if allMatch && score == 0 {
                    score += 50
                } else if !allMatch && score == 0 {
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
                // حساب الاسم الرباعي مسبقاً
                let displayName = fourPartName(for: member, lookup: lookup)
                results.append(SearchResult(member: member, score: score, matchContext: matchContext, displayName: displayName))
            }
        }

        return Array(results.sorted { $0.score > $1.score }.prefix(50))
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
                                .fill(DS.Color.deceased)
                                .frame(width: 11, height: 11)
                                .overlay(
                                    Image(systemName: "heart.slash.fill")
                                        .font(DS.Font.scaled(6, weight: .bold))
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
        .padding(.vertical, DS.Spacing.sm + 2)
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
