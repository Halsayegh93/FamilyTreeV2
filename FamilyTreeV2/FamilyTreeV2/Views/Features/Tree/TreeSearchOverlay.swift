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
    /// عند توفّره: يظهر زر إغلاق (✕) داخل مربع البحث نفسه عندما يكون الحقل فارغاً
    /// — يُستخدم لإغلاق لوحة البحث (مثلاً في شجرة التفرّع).
    var onClose: (() -> Void)? = nil
    /// عند `true` تظهر الفلاتر فور فتح البحث حتى لو الحقل فارغ (العرض الكلاسيكي).
    var showFiltersWhenEmpty: Bool = false

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchFocused = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var statusFilter: StatusFilter = .all
    /// تخزين داخلي للفرع — يُستخدم فقط إذا لم يُمرَّر binding خارجي.
    @State private var internalBranchRootId: UUID? = nil
    @State private var branchPickerOpen = false
    @FocusState private var fieldFocused: Bool

    /// عند توفّره: مصدر حقيقة خارجي لاختيار الفرع — يبقى ثابتاً طول عمر الشاشة
    /// الأم (مثلاً شجرة التفرّع) حتى لو أُعيد فتح لوحة البحث. بدونه يُستخدم
    /// التخزين الداخلي (السلوك السابق للوضع المضمّن).
    var externalBranchRootId: Binding<UUID?>? = nil

    /// الفرع المختار — يقرأ/يكتب على الـ binding الخارجي إن وُجد، وإلا الداخلي.
    private var branchRootId: UUID? {
        get { externalBranchRootId?.wrappedValue ?? internalBranchRootId }
        nonmutating set {
            if let ext = externalBranchRootId { ext.wrappedValue = newValue }
            else { internalBranchRootId = newValue }
        }
    }

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

        /// رمز الخيار في المبدّل الواحد (`DSSegmentedSwitch`)
        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .alive: return "heart.fill"
            case .deceased: return "heart.slash.fill"
            }
        }
    }

    /// عضو جذر الفرع المختار (إن وُجد).
    private var branchRootMember: FamilyMember? {
        guard let id = branchRootId else { return nil }
        return memberVM.allMembers.first { $0.id == id }
    }

    /// مجموعة معرّفات الفرع المختار (الجذر + كل ذرّيته). محسوبة بإمتداد BFS.
    private var branchDescendantIds: Set<UUID>? {
        guard let rootId = branchRootId else { return nil }
        let kidsMap = Dictionary(grouping: memberVM.allMembers) { $0.fatherId }
        var ids: Set<UUID> = [rootId]
        var stack: [UUID] = [rootId]
        while let cur = stack.popLast() {
            for c in kidsMap[cur] ?? [] where !ids.contains(c.id) {
                ids.insert(c.id)
                stack.append(c.id)
            }
        }
        return ids
    }

    private var filteredResults: [SearchResult] {
        let branchIds = branchDescendantIds
        return searchResults.filter { result in
            // فلتر الحالة
            switch statusFilter {
            case .all: break
            case .alive: if result.member.isDeceased == true { return false }
            case .deceased: if result.member.isDeceased != true { return false }
            }
            // فلتر الفرع (حصر على فرع معيّن)
            if let ids = branchIds, !ids.contains(result.member.id) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filtersBar
            // أُزيل قسم «آخر عمليات البحث» بطلب المستخدم.
            resultsSection
        }
        .zIndex(100)
        // اختيار الفرع — مربّع بمنتصف الشاشة (بحجم محتواه)
        .dsTallBox(isPresented: $branchPickerOpen) {   // شجرة فروع طويلة (توصية أبل)
            BranchPickerSheet(
                allMembers: memberVM.allMembers,
                selectedId: branchRootId,
                showsSearch: false,
                onSelect: { id in
                    branchRootId = id
                    branchPickerOpen = false
                }
            )
        }
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
                // لا نعيد تعيين الفلاتر (الحالة/الفرع) — تبقى ثابتة كما اختارها المستخدم.
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

    /// حقل البحث بشكل حقل البحث الموحّد في الصفحات (`DSSearchField`: عدسة + نص + × وصندوق
    /// `dsFocusFieldBox` بارتفاع `DSBox.searchHeight`) — هنا بتركيز تلقائي وزرّ إغلاق اللوحة
    private var searchBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(isSearchFocused ? AppSection.tree.ink : DS.Color.textTertiary)
                .accessibilityHidden(true)

            TextField(L10n.t("ابحث بالاسم أو الهاتف...", "Search by name or phone..."), text: $searchText, onEditingChanged: { focused in
                isSearchFocused = focused
            })
            .focused($fieldFocused)
            .dsFieldFont(.body)
            .foregroundColor(DS.Color.textPrimary)
            .multilineTextAlignment(.leading)
            .submitLabel(.search)
            .autocorrectionDisabled()

            // زر داخل المربع: يمسح النص إذا فيه نص، وإلا يغلق لوحة البحث (إن توفّر onClose).
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) { searchTrailingIcon }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            } else if onClose != nil {
                Button(action: { onClose?() }) { searchTrailingIcon }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DSBox.searchHeight)
        .dsFocusFieldBox(focused: isSearchFocused, tint: AppSection.tree.ink, fill: DS.Color.surface)
        // فوق كانفس الشجرة — ظلّ خفيف يفصله عنها
        .dsSubtleShadow()
    }

    /// أيقونة الزر داخل المربع (✕) — تُستخدم للمسح والإغلاق.
    /// نفس × مسح البحث في بقية الحقول (رمادي خافت) — كانت حمراء، والأحمر للحذف فقط
    private var searchTrailingIcon: some View {
        Image(systemName: "xmark.circle.fill")
            .dsGlyph(DS.Glyph.lg, weight: .regular)
            .foregroundColor(DS.Color.textTertiary)
            // مساحة ضغط ٤٤ (توصية أبل) بلا تغيير ارتفاع الشريط
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .contentShape(Rectangle())
            .padding(.vertical, -DS.Spacing.sm)
    }

    // MARK: - Filters Bar (ثابتة طوال البحث — لا تختفي مع غياب النتائج)

    /// صف الفلاتر (الحالة + الفرع) — في وضع التفرّع (full-height) يظهر فور فتح
    /// البحث ويبقى ثابتاً؛ في الوضع المضمّن يظهر بمجرد وجود نص بحث. لا يختفي
    /// حتى لو ما فيه نتائج لهذه التصفية.
    @ViewBuilder
    private var filtersBar: some View {
        if usesFullHeight || showFiltersWhenEmpty || !searchText.isEmpty {
            // طلب المالك ٢٠٢٦-١٠-٠٩: الحالة شرائح صغيرة بسطر الفرع، والفرع المختار باسمه وعدده
            // (بلا «آخر عمليات البحث» ولا فروع جاهزة — طلبه)
            // الشرائح بمنتصف عرض الشاشة (طلب المالك ٢٠٢٦-١٠-٠٩)؛ إن ضاقت (خط كبير) تتمرّر أفقياً
            ViewThatFits(in: .horizontal) {
                // شرائح واسعة تملأ عرض البطاقة (طلب المالك «خلها وسيعة»)
                filterChipsRow(fill: true)
                    .padding(.horizontal, DS.Spacing.sm)
                ScrollView(.horizontal, showsIndicators: false) {
                    filterChipsRow(fill: false)
                        .padding(.horizontal, DS.Spacing.sm)
                }
            }
            .padding(.vertical, DS.Spacing.xs)
            // فوق الكانفس: بطاقة الأدوات الزجاجية الواحدة (لا تظهر العُقد من خلف الشرائح)
            .treeToolbarCard()
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xs)
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if !searchResults.isEmpty {
            VStack(spacing: 0) {
                if filteredResults.isEmpty {
                    // الحالة الفارغة الواحدة (مجسّم القسم + العنوان) — صغيرة داخل البطاقة
                    DSEmptyView(L10n.t("لا توجد نتائج ضمن هذه التصفية", "No results for this filter"),
                                section: .tree, style: .inline)
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
                    .frame(maxHeight: usesFullHeight ? .infinity : DSBox.overlayListMaxHeight)
                }
            }
            // البطاقة الواحدة
            .dsCard(padding: nil)
            .padding(.top, DS.Spacing.xs)
        } else if !debouncedSearchText.isEmpty && searchText == debouncedSearchText {
            DSEmptyView(L10n.t("لا توجد نتائج", "No results found"), section: .tree, style: .inline)
                .dsCard(padding: nil)
                .padding(.top, DS.Spacing.xs)
        }
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        searchTask?.cancel()
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { searchResults = []; return }

        // snapshot البيانات مرة وحدة — isCountable يستثني المعلّق/المجمّد/المخفي (يُبقي المتوفّى)
        let members = memberVM.allMembers.filter { $0.isCountable }
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
                // احترام الهاتف المخفي — لا يُطابَق بالرقم
                if let phone = member.phoneNumber, member.isPhoneHidden != true {
                    let phoneSuffix = String(phone.filter(\.isNumber).suffix(8))
                    if phoneSuffix.contains(searchDigits) || searchDigits.contains(phoneSuffix) {
                        score += 90
                        matchContext = L10n.t("تطابق الهاتف", "Phone match")
                    }
                }
            } else {
                // البحث يشمل العائلة المختارة كآخر اسم
                let normalizedFull = ArabicTextNormalizer.normalizeForSearch(member.nameWordsWithFamily.joined(separator: " "))
                let fullWords = normalizedFull.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                // تطابق بالبادئة (أولوية عالية) أو تطابق جزئي substring (طبقة احتياطية)
                let allMatchPrefix = searchWords.allSatisfy { sw in fullWords.contains { $0.hasPrefix(sw) } }
                let allMatchPartial = searchWords.allSatisfy { sw in fullWords.contains { $0.contains(sw) } }

                if searchWords.count == 1 {
                    let sw = searchWords[0]
                    // كلمة وحدة — البادئة أولاً، ثم تطابق جزئي
                    if normalizedFirst == sw {
                        score += 100
                    } else if normalizedFirst.hasPrefix(sw) {
                        score += 80
                    } else if allMatchPrefix {
                        score += 50
                    } else if fullWords.contains(where: { $0.contains(sw) }) {
                        score += 35
                        matchContext = L10n.t("تطابق جزئي", "Partial match")
                    }
                } else {
                    // أكثر من كلمة — كل الكلمات لازم تطابق (بادئة أو جزئياً)
                    if allMatchPrefix || allMatchPartial {
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

                        // نقاط إضافية لكل كلمة تطابق بالترتيب (بادئة)
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

                        // تطابق جزئي فقط (بدون بادئة) → نقاط أقل + سياق
                        if !allMatchPrefix {
                            score = max(score - 45, 20)
                            matchContext = L10n.t("تطابق جزئي", "Partial match")
                        }
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
                // حساب الاسم الرباعي مسبقاً
                let displayName = fourPartName(for: member, lookup: lookup)
                results.append(SearchResult(
                    member: member,
                    score: score,
                    matchContext: matchContext,
                    displayName: displayName
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
                .prefix(500)
        )
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
        // لقب العائلة المختارة بين قوسين («ابراهيم(العطار)») — صاحبه وما بعده يُختصر بالعائلة نفسها
        if let head = FamilyNameCatalog.unitsBeforeNickname(parts, family: member.familyName) { parts = head }
        // الاسم الأخير = العائلة المختارة (طلب المالك)، وإلا آخر كلمة من الاسم الكامل
        let lastNameStr = member.lastName
        if !lastNameStr.isEmpty, lastNameStr != parts.last, lastNameStr != member.firstName || parts.count > 1 {
            parts.append(lastNameStr)
        }
        return parts.joined(separator: " ")
    }

    /// شرائح الحالة + فاصل + شريحة الفرع — `fill`: تتمدّد بعرض البطاقة، وإلا بعرض نصّها (للتمرير)
    @ViewBuilder
    private func filterChipsRow(fill: Bool) -> some View {
        let row = HStack(spacing: DS.Spacing.xs) {
            ForEach(StatusFilter.allCases, id: \.self) { f in
                DSChipButton(f.label, isSelected: statusFilter == f, size: .small, fillsWidth: fill) {
                    withAnimation(DS.Anim.snappy) { statusFilter = f }
                }
            }
            Capsule()
                .fill(DS.Color.textTertiary.opacity(DS.Opacity.divider))
                .frame(width: DS.Border.width, height: DSBox.chipHeightSmall * 0.6)
                .padding(.horizontal, DS.Spacing.xxs)
            // الفرع بعرض نصّه كاملاً (لا يُقصّ) — الشرائح الثلاث تتقاسم الباقي
            branchPill(fill: false)
                .fixedSize()
        }
        if fill { row } else { row.fixedSize() }
    }

    // MARK: - Branch Pill (مدمج داخل صف الفلاتر)

    /// شريحة الفرع (`DSChipButton`) — مختارة: ممتلئة بـ«فرع <الاسم>» وعدد أفراده، و× بجانبها يلغيه.
    @ViewBuilder
    private func branchPill(fill: Bool) -> some View {
        if let m = branchRootMember {
            HStack(spacing: DS.Spacing.xxs) {
                DSChipButton(L10n.t("فرع \(m.firstName)", "\(m.firstName)'s branch"), icon: "tree.fill",
                             isSelected: true, count: branchDescendantIds?.count, size: .small,
                             fillsWidth: fill) { branchPickerOpen = true }
                Button {
                    branchRootId = nil
                } label: {
                    searchTrailingIcon
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -DS.Spacing.sm)
                .accessibilityLabel(L10n.t("إلغاء الفرع", "Clear branch"))
            }
        } else {
            DSChipButton(L10n.t("اختر فرعاً", "Pick branch"), icon: "tree", size: .small,
                         fillsWidth: fill) { branchPickerOpen = true }
        }
    }

    // MARK: - Search Result Row

    private func searchResultRow(_ result: SearchResult) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // صورة العضو الواحدة في صفوف القوائم (`DSMemberAvatar`) + شارة الوفاة على طرفها
            DSMemberAvatar(name: result.member.firstName, avatarUrl: result.member.avatarUrl,
                           size: DS.Icon.avatarRow, roleColor: result.member.roleColor)
                .overlay(alignment: .bottomTrailing) {
                    if result.member.isDeceased ?? false {
                        Image(systemName: "heart.slash.fill")
                            .dsGlyph(DS.Glyph.micro)
                            .foregroundColor(DS.Color.onTint) // نص فوق لون الدور: داكن في الوضع الداكن
                            .frame(width: DS.Icon.avatarBadge, height: DS.Icon.avatarBadge)
                            .background(Circle().fill(DS.Color.deceased))
                    }
                }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(result.displayName)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    if result.member.isDeceased ?? false {
                        DSStatusChip(text: L10n.t("متوفى", "Deceased"), tint: DS.Color.deceased, size: .mini)
                    }
                    if let context = result.matchContext {
                        DSStatusChip(text: context, tint: DS.Color.info, size: .mini)
                    }
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left.circle.fill")
                .dsGlyph(DS.Glyph.xlCompact, weight: .regular)
                .foregroundColor(result.member.roleColor.opacity(DS.Opacity.selectedStroke))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .contentShape(Rectangle())
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
}
