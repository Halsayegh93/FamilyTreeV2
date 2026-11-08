import SwiftUI

// MARK: - «العائلة» = صفحة الأعضاء الواحدة («ب — المراجعة أولاً»، اختيار المالك ٢٠٢٦-١١-٠٦، `samples/admin-family-reports`)
//
// رأس كحلي بالحلقات (`AdminMembersHeader.swift` — مفتوح ومطويّ)، «＋ تسجيل عضو» للمالك والمدير، التقارير بالفلتر الحالي،
// العنوان قائمة الأقسام ← «يحتاج مراجعتك»: أربع قوائم بأعدادها (هل ما زالوا أحياء؟ · تاريخ وفاة غير مكتمل · بيانات ناقصة ·
// مشكلات في الشجرة — `AdminMemberReview`) كل صفّ يفتح قائمته عضواً عضواً (ورقة العضو بالسابق/التالي، وتبقى القائمة تحت
// «الأعضاء»؛ «هل ما زالوا أحياء؟» قائمة بزرّي «متوفى» و«حي ✓») ← «الأعضاء»: «الفرع: الكل ⌄» (فرع بأي مستوى)، حقل بحث
// واحد (الاسم أو الرقم)، والشرائح الكل · مسجّلون · مقيّدون · متوفون ← قائمة واحدة أبجدياً (الصورة · الاسم · «فرع X» أو سبب
// المراجعة · الحالة كلمة ملوّنة خفيفة) بـ«عرض المزيد». الشرائح تُثبَّت في الرأس المطويّ حين تصل إليه.
// الحالات والإشارات في `AdminMembersModel.swift`. الصلاحيات كما كانت: الصفحة لـ`canEditMembers`، التسجيل
// `canRegisterMembers`، التصدير `isAdmin`.

/// ورقة العضو مفتوحة على قائمة (السابق/التالي يتنقّلان فيها)
/// «شجرة العائلة | شجرة النساء» في صفحة «العائلة»
enum AdminFamilyScope: Hashable {
    case family, women
    static var options: [DSSegmentOption<AdminFamilyScope>] {
        [DSSegmentOption(id: .family, title: L10n.t("شجرة العائلة", "Family tree"), icon: AppSection.tree.symbol),
         DSSegmentOption(id: .women, title: L10n.t("شجرة النساء", "Women's tree"), icon: "figure.stand.dress")]
    }
}

struct AdminMemberSheetContext: Identifiable {
    let id = UUID()
    let ids: [UUID]
    let start: Int
}

struct AdminMembersPage: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// أبناء البنات — بيتهم شجرة النساء («مسجّلون» وحدها هنا)
    @ObservedObject private var sons = DaughterSonsIndex.shared
    /// «حي ✓» المحلية لهذا المستخدم
    @ObservedObject private var verified = AdminLivingVerifiedStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adminBackTitle) private var outerBack

    /// رأس الحلقات (`AdminMembersHeader.swift`): أرقامها، شجرة النساء (لعدد النساء)، والطيّ عند التمرير
    @State private var census = AdminFamilyCensus()
    @State private var womenRows: [FamilyMember] = WomenStore.cache
    @State private var collapsed = false
    @State private var compactLine: CGFloat = DS.Hub.compactBar
    /// زرّ البحث في السطر المطويّ: يمرّر إلى حقل البحث ثم يضع المؤشر فيه
    @State private var searchToken = 0
    @State private var searchFocus = 0

    @State private var chip: AdminMemberChip
    /// قائمة المراجعة المفتوحة في «الأعضاء» — nil = الشريحة
    @State private var review: AdminMemberReview?
    @State private var query = ""
    @State private var limit = Self.pageSize
    @State private var index = AdminMembersIndex.empty
    /// الآباء والأبناء (للفرع المختار) — مرة لكل تغيّر في الأعضاء
    @State private var tree = AdminFamilyTree.empty
    /// «الفرع: …» — رأس فرع بأي مستوى (nil = الكل) وذرّيته
    @State private var branchFilter: UUID?
    @State private var branchSet: Set<UUID>?
    /// أعداد الشرائح داخل الفرع المختار
    @State private var branchCounts: [AdminMembersIndex.Key: Int] = [:]
    @State private var showBranchPicker = false
    /// قوائم المراجعة الأربع محسوبة مرة لكل تغيّر (الفهرس أو «حي ✓») — مواضع الفهرس
    @State private var reviewRows: [AdminMemberReview: [Int]] = [:]
    @State private var sheet: AdminMemberSheetContext?
    /// «شجرة العائلة | شجرة النساء» تحت أرقام العائلة (طلب المالك ٢٠٢٦-١١-٠٨)
    @State private var scope: AdminFamilyScope = .family
    /// شريحة تُطلب في «شجرة النساء» من حلقة «خارج العائلة»
    @State private var womenChipRequest: AdminWomenChip?
    @State private var showExport = false
    /// «زر التقارير» بالفلتر الحالي: الشريحة والفرع والبحث — nil = كل العائلة
    @State private var exportScope: AdminReportScope?
    /// «متوفى» من مرشّح «تحقق من الأحياء» — مربّع تسجيل الوفاة الموجود (`AdminMemberDetailSheet(deathOnly:)`)
    @State private var deathTarget: FamilyMember?

    static let pageSize = 40
    private static let searchAnchor = "adminMembersSearch"

    /// `sub` باقٍ لمن يفتح الصفحة به (الشرائح الفرعية حُذفت في التبسيط) — يُتجاهل إلا «تاريخ الوفاة غير مكتمل»
    init(chip: AdminMemberChip = .all, sub: AdminMemberSub = .all) {
        _chip = State(initialValue: chip.shownChip)
        _review = State(initialValue: chip.review ?? (chip == .deceased && sub == .deathIncomplete ? .death : nil))
    }

    var body: some View {
        ScrollViewReader { proxy in
            AdminHubPage(pinned: collapsed ? AnyView(compactBar.transition(.opacity)) : nil) {
                AdminBandHeader(title: AdminArea.family.title, isAreaRoot: true) {
                    AnyView(headerButtons)
                } accessory: {
                    AnyView(headerAccessory)
                }
            } content: {
                AnyView(content)
            }
            .onChange(of: searchToken) { _ in
                if reduceMotion {
                    proxy.scrollTo(Self.searchAnchor, anchor: .center)
                } else {
                    withAnimation(DS.Anim.smooth) { proxy.scrollTo(Self.searchAnchor, anchor: .center) }
                }
            }
        }
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
        .modifier(AdminLivingDeathBox(member: $deathTarget))
        .modifier(AdminBranchPickerBox(isPresented: $showBranchPicker, members: memberVM.allMembers,
                                       selected: branchFilter, onSelect: { pickBranch($0) }))
        .navigationDestination(isPresented: $showExport) {
            AdminLazyPage { [exportScope] in
                AnyView(AdminReportsView(scope: exportScope).adminBackTitle(AdminArea.family.title).adminArea(.family))
            }
        }
        .task {
            verified.activate(user: authVM.currentUser?.id)
            if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
            rebuild()
            await sons.refresh()
            await accounts.refresh()
            // عدد النساء في الحلقة — من كاش شجرة النساء، أو جلب للقراءة مرة إن لم تُحمَّل
            if womenRows.isEmpty, let fetched = try? await WomenStore.fetch() {
                womenRows = fetched
                refreshCensus()
            }
        }
        .onChange(of: memberVM.membersVersion) { _ in rebuild() }
        .onChange(of: accounts.accounts) { _ in rebuild() }
        .onChange(of: accounts.loaded) { _ in rebuild() }
        .onChange(of: sons.ids) { _ in rebuild() }
        // تبديل «شجرة العائلة | شجرة النساء» يرجع الرأس كاملاً بلا قفزة (الطيّ يتبع شرائح «شجرة العائلة» وحدها)
        .onChange(of: scope) { s in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                collapsed = false
                if s == .family { womenChipRequest = nil }
            }
        }
        // أعداد «خارج العائلة» تحتاج شجرة النساء (أزواج البنات من خارج العائلة)
        .onChange(of: womenRows.count) { _ in refreshCensus() }
        .onChange(of: verified.ids) { _ in refreshReviews() }
        .onChange(of: query) { _ in limit = Self.pageSize }
    }

    private func rebuild() {
        let names = appSettingsVM
        index = AdminMembersIndex.build(members: memberVM.allMembers, accounts: accounts.accounts,
                                        accountsReady: accounts.loaded, daughterSons: sons.ids,
                                        branchName: { names.branchName(for: $0) })
        tree = AdminFamilyTree(memberVM.allMembers)
        applyBranchFilter()
        refreshReviews()
        refreshCensus()
    }

    /// أرقام الحلقات — مع كل بناء للفهرس، وبعد وصول شجرة النساء
    private func refreshCensus() {
        census = AdminFamilyCensus.make(members: memberVM.allMembers, women: womenRows)
    }

    /// القوائم الأربع: «هل ما زالوا أحياء؟» بلا من راجعه المستخدم («حي ✓») · تاريخ وفاة غير مكتمل · بيانات ناقصة
    /// (الأحياء) · مشكلات الشجرة
    private func refreshReviews() {
        reviewRows = [
            .living: index.rows(.verifyLiving, .all).filter { !verified.ids.contains(index.entries[$0].id) },
            .death: index.rows(.deceased, .deathIncomplete),
            .gaps: index.rows(.gaps, .all),
            .problems: index.rows(.problems, .all)
        ]
    }

    /// قائمة مراجعة داخل الفرع المختار
    private func rows(of r: AdminMemberReview) -> [Int] {
        let base = reviewRows[r] ?? []
        guard let set = branchSet else { return base }
        return base.filter { set.contains(index.entries[$0].id) }
    }

    // MARK: الطيّ عند التمرير

    /// الشرائح وصلت تحت سطر الرأس المطويّ ← يُثبَّت السطر والشرائح فوقها في الموضع نفسه؛ وتعود الصفحة لرأسها الكامل حين تنزل
    private func chipsMoved(_ top: CGFloat) {
        let shouldCollapse = top < compactLine
        guard shouldCollapse != collapsed else { return }
        if reduceMotion {
            collapsed = shouldCollapse
        } else {
            withAnimation(DS.Anim.quick) { collapsed = shouldCollapse }
        }
    }

    private var compactBar: some View {
        AdminMembersCompactBar(total: census.counts.total,
                               backTitle: outerBack ?? L10n.t("اليوم", "Today"),
                               back: { dismiss() },
                               search: {
                                   searchToken += 1
                                   DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : DS.Hub.compactSearchDelay)) {
                                       searchFocus += 1
                                   }
                               },
                               register: authVM.canRegisterMembers ? { Self.registerPage } : nil,
                               chips: AnyView(bandChipsRow),
                               lineHeight: $compactLine)
    }

    private static var registerPage: AnyView {
        AnyView(AdminRegisterMemberView().adminBackTitle(AdminArea.family.title).adminArea(.family))
    }

    // MARK: الفرع المختار

    private func pickBranch(_ id: UUID?) {
        guard id != branchFilter else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        branchFilter = id
        applyBranchFilter()
        limit = Self.pageSize
    }

    /// ذرّية الفرع المختار وأعداد الشرائح داخله
    private func applyBranchFilter() {
        guard let head = branchFilter else {
            branchSet = nil
            branchCounts = [:]
            return
        }
        let set = tree.subtree(of: head)
        branchSet = set
        var counts: [AdminMembersIndex.Key: Int] = [:]
        for (key, rows) in index.lists where key.sub == .all {
            counts[key] = rows.reduce(0) { $0 + (set.contains(index.entries[$1].id) ? 1 : 0) }
        }
        branchCounts = counts
    }

    /// عدد الشريحة — داخل الفرع المختار إن وُجد
    private func chipCount(_ c: AdminMemberChip) -> Int? {
        guard let base = index.shownCount(c) else { return nil }
        guard branchSet != nil else { return base }
        return branchCounts[AdminMembersIndex.Key(chip: c, sub: .all)] ?? 0
    }

    /// اسم الفرع المختار في الشريحة (الاسم المختصر للرأس — الأسماء المخصّصة لصفوف قائمة الفروع فقط)
    private var branchFilterTitle: String? {
        guard let id = branchFilter else { return nil }
        let m = tree.byId[id] ?? memberVM.member(byId: id)
        return m.map { $0.shortFullName.isEmpty ? $0.fullName : $0.shortFullName } ?? L10n.t("فرع", "Branch")
    }

    // MARK: الرأس

    private var headerButtons: some View {
        HStack(spacing: DS.Spacing.sm) {
            // «تسجيل عضو جديد» — بيته الوحيد (المالك والمدير)
            if authVM.canRegisterMembers {
                NavigationLink {
                    AdminLazyPage { Self.registerPage }
                } label: {
                    // رمز عارٍ كأزرار رأس «اليوم» (طلب المالك ٢٠٢٦-١١-٠٢ — كانت كبسولة «＋ تسجيل عضو» تُقصّ)
                    AdminGlassCircle(symbol: "person.badge.plus")
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register a new member"))
            }
            if authVM.isAdmin { reportsButton }
        }
    }

    /// زر «التقارير» المباشر للمالك والمدير — يفتح التقارير بالشريحة والفرع والبحث الحاليين
    private var reportsButton: some View {
        Button {
            exportScope = currentExportScope
            showExport = true
        } label: {
            AdminGlassCircle(symbol: "doc.text")
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("التقارير (PDF)", "Reports (PDF)"))
    }

    /// تحت العنوان: الحلقات فقط — البحث والشرائح نزلت تحت «يحتاج مراجعتك»
    private var headerAccessory: some View {
        AnyView(AdminFamilyCensusBand(census: census, openMen: { scope = .family; select(.all) },
                                      openOutside: authVM.isAdmin ? { womenChipRequest = .outside; scope = .women } : nil))
            // أنزل قليلاً عن العنوان (طلب المالك ٢٠٢٦-١١-٠٨ «نزل شوي الحلقات ما نخليهم لازقين»)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xs)
    }

    /// الشرائح الظاهرة في «شجرة العائلة» (فرع خارج العائلة ونساء الحسابات في «شجرة النساء»)
    private var visibleChips: [AdminMemberChip] { AdminMemberChip.shown }

    /// الشرائح فوق الكحلي — في الرأس المطويّ
    private var bandChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xsm) {
                ForEach(visibleChips) { c in
                    AdminBandFilterChip(title: c.chipTitle, count: c == .all ? nil : chipCount(c),
                                        selected: review == nil && c == chip) {
                        select(c)
                    }
                }
            }
            .padding(.vertical, DS.Spacing.xxs)
        }
    }

    /// الشرائح على الأبيض تحت «الأعضاء»: الكل · مسجّلون · مقيّدون · متوفون — موضعها يقرّر طيّ الرأس
    private var chipsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(visibleChips) { c in
                        Button { select(c) } label: {
                            AdminMembersLightChip(title: c.chipTitle, count: c == .all ? nil : chipCount(c),
                                                  selected: review == nil && c == chip)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(review == nil && c == chip ? .isSelected : [])
                        .id(c)
                    }
                }
                .padding(.horizontal, DS.Border.width)
            }
            .onAppear {
                // بعد أول تخطيط — الشريحة المختارة (من «اليوم» أو التنبيه) ظاهرة كاملة
                guard chip != .all else { return }
                DispatchQueue.main.async { proxy.scrollTo(chip, anchor: .center) }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(AdminHubScroll.space)).minY } action: { chipsMoved($0) }
    }

    private func select(_ c: AdminMemberChip) {
        guard c != chip || review != nil else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) {
            chip = c
            review = nil
            limit = Self.pageSize
        }
    }

    /// قائمة مراجعة: تفتح ورقة أول عضو فيها (السابق/التالي داخلها)، وتبقى القائمة تحت «الأعضاء» — «هل ما زالوا أحياء؟»
    /// قائمة بزرّي «متوفى» و«حي ✓» (لا مكان لهما في الورقة)
    private func openReview(_ r: AdminMemberReview) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) {
            review = r
            limit = Self.pageSize
        }
        let list = currentRows
        guard r != .living, !list.isEmpty else { return }
        sheet = AdminMemberSheetContext(ids: list.map { index.entries[$0].id }, start: 0)
    }

    /// الفلتر الحالي للتصدير: الشريحة (أو قائمة المراجعة) · الفرع · «البحث» — بلا فلتر = كل العائلة
    private var currentExportScope: AdminReportScope? {
        let q = trimmedQuery
        guard chip != .all || review != nil || !q.isEmpty || branchFilter != nil else { return nil }
        var parts = [review?.title ?? chip.title]
        if let b = branchFilterTitle { parts.append(L10n.t("الفرع: \(b)", "Branch: \(b)")) }
        if !q.isEmpty { parts.append("«\(q)»") }
        return AdminReportScope(ids: Set(currentRows.map { index.entries[$0].id }), title: parts.joined(separator: " · "))
    }

    // MARK: المحتوى

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !trimmedQuery.isEmpty }

    private var content: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            if !index.built {
                if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                              message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                              retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
                } else {
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
                }
            } else {
                // «شجرة النساء» للمالك والمدير فقط (طلب المالك ٢٠٢٦-١١-٠٨ «يطلع عليه المدير و المالك فقط لا غير»)
                if authVM.isAdmin {
                    // تبديل فوري بلا حركة — تحريك استبدال قائمتين طويلتين كان يهزّ الصفحة
                    DSSegmentedSwitch(options: AdminFamilyScope.options, selection: Binding(
                        get: { scope },
                        set: { v in
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) { scope = v }
                        }), size: .regular)
                }
                if scope == .family || !authVM.isAdmin {
                    AnyView(reviewCard)
                    AnyView(membersHead)
                    AnyView(listSection)
                } else {
                    AnyView(AdminWomenPanel(
                        women: womenRows,
                        requestedChip: womenChipRequest,
                        reload: {
                            if let fresh = try? await WomenStore.fetch() { womenRows = fresh }
                            refreshCensus()
                        },
                        openMember: { ids, start in sheet = AdminMemberSheetContext(ids: ids, start: start) }))
                }
            }
        }
    }

    // MARK: «يحتاج مراجعتك»

    private var reviewCard: some View {
        let counts = Dictionary(uniqueKeysWithValues: AdminMemberReview.allCases.map { ($0, rows(of: $0)) })
        var union = Set<Int>()
        for list in counts.values { union.formUnion(list) }
        return AdminMembersReviewCard(counts: counts.mapValues(\.count), total: union.count,
                                      accountsReady: index.accountsReady, selected: review,
                                      open: { openReview($0) })
    }

    // MARK: «الأعضاء»: العنوان والفرع، البحث، الشرائح

    private var membersHead: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xxs) {
                Button { showBranchPicker = true } label: {
                    AdminChoiceChip(title: L10n.t("الفرع: \(branchFilterTitle ?? "الكل")", "Branch: \(branchFilterTitle ?? "All")"),
                                    isSelected: branchFilterTitle != nil, expands: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.t("يفتح قائمة الفروع", "Opens the branch list"))
                if branchFilter != nil {
                    Button { pickBranch(nil) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dsGlyph(DS.Glyph.lg, weight: .regular)
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("كل الفروع", "All branches"))
                }
            }
            .frame(minHeight: DS.Icon.tapTarget)
            AdminMembersSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم أو رقم الهاتف", "Search by name or phone"),
                                    focusToken: searchFocus)
                .id(Self.searchAnchor)
            chipsRow
        }
    }

    // MARK: القائمة

    /// الصفوف المعروضة الآن: قائمة المراجعة أو الشريحة، ثم الفرع المختار، ثم البحث (الاسم أو الرقم)
    private var currentRows: [Int] {
        var base: [Int]
        if let review {
            base = rows(of: review)
        } else {
            base = index.rows(chip, .all)
            if let set = branchSet { base = base.filter { set.contains(index.entries[$0].id) } }
        }
        let q = trimmedQuery
        guard !q.isEmpty else { return base }
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب (والرقم أرقاماً فقط)
        if NameSearch.isPhoneQuery(q) {
            let digits = NameSearch.digits(q)
            return digits.count >= 3 ? base.filter { index.entries[$0].digits.contains(digits) } : []
        }
        let words = NameSearch.words(q)
        var hits: [(order: Int, score: Int, row: Int)] = []
        for (n, i) in base.enumerated() {
            if let score = NameSearch.score(queryWords: words, candidateWords: NameSearch.words(index.entries[i].needle)) {
                hits.append((order: n, score: score, row: i))
            }
        }
        hits.sort { $0.score != $1.score ? $0.score < $1.score : $0.order < $1.order }
        return hits.map(\.row)
    }

    @ViewBuilder
    private var listSection: some View {
        let rows = currentRows
        AnyView(listCaption(rows.count))
        if rows.isEmpty {
            AdminPageStateCard(emptyState)
        } else {
            AnyView(listCard(rows))
        }
    }

    /// «2,719 عضو · أبجدياً» — وفي قائمة المراجعة اسمها و✕ يرجع للشريحة
    private func listCaption(_ n: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if let review {
                Text(verbatim: review.title)
                    .dsFont(.caption)
                    .foregroundColor(review.tint.dsReadableGlyph)
                    .lineLimit(1)
                Button { select(chip) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.md, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -DS.Spacing.md)
                .accessibilityLabel(L10n.t("إغلاق قائمة المراجعة", "Close the review list"))
            }
            Spacer(minLength: DS.Spacing.sm)
            Text(verbatim: countText(n))
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «2,719 عضو · أبجدياً» — والبحث «12 نتيجة» (النتائج بالأقرب لا أبجدياً)
    private func countText(_ n: Int) -> String {
        let number = AdminMembersFilterBar.grouped(n)
        if searching { return L10n.t("\(number) نتيجة", "\(number) results") }
        if review == .living { return L10n.t("\(number) عضو · الأقدم أولاً", "\(number) members · oldest first") }
        return L10n.t("\(number) عضو · أبجدياً", "\(number) members · A–Z")
    }

    private var emptyState: AdminPageStateCard.Kind {
        if searching {
            return .empty(L10n.t("لا نتائج", "No results"), message: L10n.t("جرّب اسماً آخر أو رقماً", "Try another name or number"))
        }
        if review != nil {
            return .empty(L10n.t("لا شيء للمراجعة", "Nothing to review"),
                          message: L10n.t("هذه القائمة فارغة الآن", "This list is empty right now"),
                          tint: DS.Color.success)
        }
        return .empty(L10n.t("لا أحد هنا الآن", "Nobody here right now"))
    }

    private func listCard(_ rows: [Int]) -> some View {
        let visible = Array(rows.prefix(limit))
        let ids = rows.map { index.entries[$0].id }
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element) { pos, i in
                    if pos > 0 { AdminRowDivider() }
                    row(i, ids: ids, position: pos)
                }
            }
            if rows.count > limit {
                AdminPillButton(title: L10n.t("عرض المزيد (\(rows.count - limit))", "Show more (\(rows.count - limit))"),
                                icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                    limit += Self.pageSize
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func branchTitle(_ entry: AdminMembersIndex.Entry) -> String? {
        // ابن البنت («فرع خارج العائلة»): لا فرع له في شجرة الرجال — بيته شجرة النساء
        if sons.contains(entry.member.id) { return L10n.t("فرع خارج العائلة · في شجرة النساء", "Outside branch · women's tree") }
        return entry.branch.flatMap { b in index.branches.first { $0.id == b }?.title }
    }

    /// سبب الظهور في قائمة المراجعة: «بلا تاريخ ميلاد» / «مشكلة في الشجرة» / «السنة فقط» (+N حين يتعدّد)
    private func reason(_ entry: AdminMembersIndex.Entry, _ r: AdminMemberReview) -> String {
        var reasons: [String]
        switch r {
        case .living:   return L10n.t("تحقق: هل ما زال حياً؟", "Check: still alive?")
        case .death:    return AdminMemberGap.deathIncomplete.title
        case .gaps:     reasons = entry.gaps.filter { $0 != .deathIncomplete }.map(\.tag)
        case .problems: reasons = entry.problems.map(\.title)
        }
        guard let first = reasons.first else { return branchTitle(entry) ?? "" }
        return reasons.count > 1 ? "\(first) · +\(reasons.count - 1)" : first
    }

    @ViewBuilder
    private func row(_ i: Int, ids: [UUID], position: Int) -> some View {
        let entry = index.entries[i]
        if review == .living {
            // «متوفى» و«حي ✓» في الصفّ نفسه (لا مكان لهما في ورقة العضو)
            AnyView(livingRow(entry, ids: ids, position: position))
        } else {
            Button {
                sheet = AdminMemberSheetContext(ids: ids, start: position)
            } label: {
                // بلا اسم الفرع تحت كل اسم (طلب المالك ٢٠٢٦-١١-٠٨) — الفرع يُختار ويظهر باسمه أعلى القائمة «الفرع: …»
                AdminMemberListRow(entry: entry, subline: review.map { reason(entry, $0) } ?? "",
                                   warns: review != nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func livingRow(_ entry: AdminMembersIndex.Entry, ids: [UUID], position: Int) -> some View {
        AdminLivingCheckRow(entry: entry,
                            reason: L10n.t("تحقق: هل ما زال حياً؟", "Check: still alive?"),
                            canEdit: authVM.canEditMembers,
                            open: { sheet = AdminMemberSheetContext(ids: ids, start: position) },
                            deceased: { deathTarget = entry.member },
                            alive: {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation(DS.Anim.snappy) { verified.markAlive(entry.id) }
                            })
    }
}

// MARK: - «يحتاج مراجعتك» (اختيار المالك ٢٠٢٦-١١-٠٦ «ب»)

/// أربع قوائم بأعدادها، كل صفّ يفتح قائمته عضواً عضواً — في نوعه المستقل (حارس المكدس)
struct AdminMembersReviewCard: View {
    let counts: [AdminMemberReview: Int]
    let total: Int
    /// قبل وصول قوائم الحسابات: «هل ما زالوا أحياء؟» تقديرية (قد يخرج منها من له حساب)
    let accountsReady: Bool
    let selected: AdminMemberReview?
    let open: (AdminMemberReview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("يحتاج مراجعتك", "Needs your review"))
                    .dsFont(.sectionTitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Spacing.sm)
                Text(verbatim: L10n.t("\(AdminMembersFilterBar.grouped(total)) عضواً", "\(AdminMembersFilterBar.grouped(total)) members"))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(AdminMemberReview.allCases.enumerated()), id: \.element) { i, r in
                    if i > 0 { AdminRowDivider() }
                    row(r)
                }
                AdminRowDivider()
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "checkmark")
                        .dsGlyph(DS.Glyph.xs, weight: .semibold)
                        .foregroundColor(DS.Color.success)
                        .accessibilityHidden(true)
                    Text(L10n.t("كل قائمة تُراجَع عضواً عضواً بالسابق والتالي", "Each list is reviewed member by member"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DS.Spacing.sm)
            }
            .adminCard()
        }
    }

    private func row(_ r: AdminMemberReview) -> some View {
        let n = counts[r] ?? 0
        return Button { open(r) } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: r.icon)
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(r.tint.dsReadableGlyph)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(r.tint.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: r.title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: r.subtitle)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Spacing.sm)
                Text(verbatim: AdminMembersFilterBar.grouped(n))
                    .dsFont(.rowTitle)
                    .monospacedDigit()
                    .foregroundColor(n > 0 ? DS.Color.textPrimary : DS.Color.textTertiary)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.title)، \(n)")
        .accessibilityHint(L10n.t("يفتح القائمة عضواً عضواً", "Opens the list member by member"))
        .accessibilityAddTraits(selected == r ? .isSelected : [])
    }
}

/// شريحة على الأبيض: المختارة ممتلئة كحلية، والباقي بإطار خفيف والعدد بجانب الاسم
struct AdminMembersLightChip: View {
    let title: String
    let count: Int?
    let selected: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(verbatim: title).dsFont(.chip)
            if let count {
                Text(verbatim: AdminMembersFilterBar.grouped(count))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(selected ? DS.Color.textOnPrimary : DS.Color.textTertiary)
            }
        }
        .lineLimit(1)
        .foregroundColor(selected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
        .padding(.horizontal, DSBox.chipPadding)
        .frame(minHeight: DSBox.chipHeight)
        .background {
            if selected {
                Capsule().fill(DS.Color.primaryFill)
            } else {
                Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width)
            }
        }
        .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
        .contentShape(Rectangle())
    }
}

/// حقل البحث على الأبيض تحت «الأعضاء» — زرّ البحث في الرأس المطويّ يضع المؤشر فيه
struct AdminMembersSearchField: View {
    @Binding var text: String
    let placeholder: String
    var focusToken: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(focused ? DS.Color.primary : DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .dsFieldFont(.fieldValue)
                .foregroundColor(DS.Color.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lgCompact, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -DS.Spacing.sm)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DSBox.searchHeight)
        .dsFocusFieldBox(focused: focused, tint: DS.Color.primary, fill: DS.Color.cardBackgroundSoft)
        .onChange(of: focusToken) { _ in focused = true }
    }
}

// MARK: - «الفرع: الكل ⌄» والعدد فوق القائمة

struct AdminMembersFilterBar: View {
    /// اسم الفرع المختار — nil = «الكل»
    let branchTitle: String?
    let countText: String
    let pickBranch: () -> Void
    let clearBranch: () -> Void

    /// «2,719» — فاصل الآلاف بأرقام لاتينية (كأرقام اللوحة)
    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Button(action: pickBranch) {
                AdminChoiceChip(title: L10n.t("الفرع: \(branchTitle ?? "الكل")", "Branch: \(branchTitle ?? "All")"),
                                isSelected: branchTitle != nil, expands: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("يفتح قائمة الفروع", "Opens the branch list"))
            if branchTitle != nil {
                Button(action: clearBranch) {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lg, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("كل الفروع", "All branches"))
            }
            Spacer(minLength: DS.Spacing.sm)
            Text(verbatim: countText)
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
    }
}

/// شارة عدد رمادية بجانب اسم الفرع
struct AdminCountChip: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .dsFont(.chip)
            .monospacedDigit()
            .foregroundColor(DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .frame(minHeight: DS.Icon.section)
            .background(Capsule().fill(DS.Color.cardBackgroundSoft))
    }
}

// MARK: - صفّ العضو

/// صفّ عضو: الصورة · الاسم · سطر صغير («فرع X» أو سبب النقص) · شارة حالة واحدة (مسجّل · بدون حساب · موقوف · متوفى)
struct AdminMemberListRow: View {
    let entry: AdminMembersIndex.Entry
    let subline: String
    /// السطر سبب نقص («ناقصة») — بلون التنبيه
    var warns: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var member: FamilyMember { entry.member }

    private var avatarTint: Color {
        switch entry.status {
        case .registered: return DS.Color.palm
        case .frozen:     return DS.Color.error
        case .deceased:   return DS.Color.deceased
        default:          return DS.Color.slate
        }
    }

    var body: some View {
        let stacked = typeSize >= .accessibility1
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xs))
                             : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
        HStack(spacing: DS.Spacing.md) {
            // الرمادي للمتوفى فقط — `grayscale(0)` على كل صفّ كان مرور رسم زائداً أثناء التمرير
            Group {
                if member.isDeceased == true {
                    DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: avatarTint)
                        .grayscale(1)
                } else {
                    DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: avatarTint)
                }
            }
            .accessibilityHidden(true)
            layout {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    // الاسم كاملاً (طلب المالك ٢٠٢٦-١١-٠٨ «الاسم الكامل يبين») في سطر واحد يصغر ليتّسع — ارتفاع الصفّ ثابت
                    // فلا يتعثّر التمرير للأعلى (الصفوف بارتفاعات مختلفة كانت تعلّق القائمة الكسولة)
                    Text(member.fullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.fullName)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !subline.isEmpty {
                        Text(verbatim: subline)
                            .dsFont(.footnote)
                            .monospacedDigit()
                            .foregroundColor(warns ? DS.Color.warning.dsReadableGlyph : DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                if !stacked { Spacer(minLength: DS.Spacing.xs) }
                if entry.status == .treeOnly {
                    // «بدون حساب» علامة فقط (طلب المالك ٢٠٢٦-١١-٠٨ «خل علامة بس») — يبقى المكان للاسم الكامل
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .dsGlyph(DS.Glyph.lg, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityLabel(AdminMemberStatus.treeOnly.title)
                } else if let status = entry.status {
                    // الحالة كلمة ملوّنة خفيفة (اختيار المالك ٢٠٢٦-١١-٠٦) — لا شارة
                    Text(verbatim: status.shortTitle)
                        .dsFont(.caption)
                        .foregroundColor(status == .treeOnly ? DS.Color.textTertiary : status.tint.dsReadableGlyph)
                        .fixedSize()
                        .accessibilityLabel(status.title)
                }
            }
            if stacked { Spacer(minLength: 0) }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))
    }
}

// MARK: - صفّ «تحقق من الأحياء» (داخل «ناقصة»)

/// الصورة · الاسم · السبب و«مواليد 1935 · 91 سنة»، وتحتها «متوفى» و«حي ✓» (الرمز SF بعد النص — علامة ✓ النصية تُرسم
/// بخط Plex كأنها «٧») — تحت النص دائماً حتى يبقى الاسم كاملاً. الضغط على الاسم يفتح ورقة العضو
struct AdminLivingCheckRow: View {
    let entry: AdminMembersIndex.Entry
    /// سبب الظهور في «ناقصة» («تحقق: هل ما زال حياً؟» …)
    let reason: String
    let canEdit: Bool
    let open: () -> Void
    let deceased: () -> Void
    let alive: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var member: FamilyMember { entry.member }

    /// السبب و«مواليد 1935 · 91 سنة» إن عُرف الميلاد — سطر واحد
    private var subline: String {
        guard let y = entry.living?.birthYear else { return reason }
        let age = Calendar(identifier: .gregorian).component(.year, from: Date()) - y
        return [reason, L10n.t("مواليد \(y) · \(age) سنة", "Born \(y) · \(age) yrs")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        let name = member.shortFullName.isEmpty ? L10n.t("بلا اسم", "No name") : member.shortFullName
        let person = Button(action: open) {
            HStack(spacing: DS.Spacing.md) {
                DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: DS.Color.slate)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(name)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .dsNameLines()
                    Text(verbatim: subline)
                        .dsFont(.footnote)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.warning.dsReadableGlyph)
                        .lineLimit(typeSize >= .xxxLarge ? nil : 1)
                        .fixedSize(horizontal: false, vertical: typeSize >= .xxxLarge)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))

        let buttons = HStack(spacing: DS.Spacing.sm) {
            AdminPillButton(title: L10n.t("متوفى", "Deceased"), style: .soft, height: DS.Hub.pillHeightCard, action: deceased)
                .accessibilityLabel(L10n.t("تسجيل وفاة \(name)", "Record \(name)'s death"))
            AdminPillButton(title: L10n.t("حي", "Alive"), icon: "checkmark", style: .navy, height: DS.Hub.pillHeightCard,
                            iconTrailing: true, action: alive)
                .accessibilityLabel(L10n.t("\(name) حي — تمت المراجعة", "\(name) is alive — reviewed"))
        }
        .fixedSize()

        // الزرّان تحت النص بمحاذاته (بعد الصورة)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            person
            if canEdit {
                buttons.padding(.leading, typeSize.isAccessibilitySize ? 0 : DS.Icon.avatar + DS.Spacing.md)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// مربّع «تسجيل الوفاة» — نفس `AdminMemberDetailSheet` (حفظه ونداءاته وإعلان الوفاة) مفتوحاً على التواريخ فقط
/// (في نوعه المستقل — حارس المكدس)
private struct AdminLivingDeathBox: ViewModifier {
    @Binding var member: FamilyMember?

    func body(content: Content) -> some View {
        content.dsCenterBox(item: $member) { m in
            AdminMemberDetailSheet(member: m, showsAccount: false, deathOnly: true)
        }
    }
}

// MARK: - حقل البحث فوق الكحلي

/// حقل بحث زجاجي فوق الرأس الكحلي (النص أبيض، والعدسة والتلميح فاتحان)
struct AdminBandSearchField: View {
    @Binding var text: String
    let placeholder: String
    /// كل تغيّر فيه يضع المؤشر في الحقل (زرّ البحث في الرأس المطويّ)
    var focusToken: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(DS.Hub.onBandMuted)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(DS.Hub.onBandMuted))
                .dsFieldFont(.fieldValue)
                .foregroundColor(DS.Color.textOnPrimary)
                .tint(DS.Color.accentLight)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lgCompact, weight: .regular)
                        .foregroundColor(DS.Hub.onBandMuted)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -DS.Spacing.sm)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: DSBox.searchHeight)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Hub.glass))
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
            .strokeBorder(focused ? DS.Color.accentLight : DS.Hub.glassLine, lineWidth: DS.Border.width))
        .onChange(of: focusToken) { _ in focused = true }
    }
}
