import SwiftUI

// MARK: - صفحة «تواريخ الوفاة» (طلب المالك ٢٠٢٦-١٠-٢٤؛ مبسّطة ٢٠٢٦-١١-٠٢؛ إعادة التصميم U12 ٢٠٢٦-١١-٢٦ — spec B.7/C.8/C.16)
//
// البيت الواحد لاستكمال تواريخ الوفاة (spec E.19): تُفتح من «يحتاج مراجعتك ← تواريخ وفاة ناقصة»، ومن بقعة «اليوم» و«المناسبات»،
// و`AdminReviewListPage(.death)` يحوّل إليها.
// الرأس: ‹ رجوع · «تواريخ الوفاة» · «⋯» (للمالك: أدوات الحملة — إبرازها في «اليوم» وآخر يوم؛ قبل مفتاحي الحملة في السيرفر
// ملاحظة بلا أزرار) ← سطر الأرقام «364 بلا تاريخ كامل ‹» «229 السنة فقط ‹» «136 بلا تاريخ ‹» (كل رقم يضبط فلتر «التاريخ»
// فأول رقم تحت الشريط = الرقم المضغوط — T2) ← شريط رفيع و«اكتمل 3 من 367».
// المحتوى: شريط التصفية (spec A.13، F3: البحث بالاسم + «تصفية» — «التاريخ» اختيار متعدّد: الكل · السنة فقط · بلا تاريخ، و«الفرع»
// اختيار واحد: الكل أو صفّ يفتح `BranchPickerSheet` داخل الورقة؛ كل لمسة تُطبَّق فوراً) ← شريحة لكل اختيار بـ✕ و«364 متوفى ·
// أبجدياً» ← قائمة واحدة أبجدياً: الصورة ·
// الاسم · «بلا تاريخ · فرع X» / «السنة فقط: 1931 · فرع X» · زرّ «أدخل» يفتح مربّع الاستكمال الموجود (`DeceasedDateBox` —
// نفس الحفظ). ما يكتمل يخرج من القائمة فوراً مع لحظة «اكتمل».
// تجربة الأدوار (`-tmpAdminRole`): فتح مربّع التاريخ وأدوات الحملة تمرّ بـ`DebugAdminProbe.dryRun` (T0).

struct DeathDatesCampaignPage: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var store = DeathDatesCampaignStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Filter: String, CaseIterable, Identifiable {
        case all, yearOnly, missing
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:      return L10n.t("الكل", "All")
            case .yearOnly: return L10n.t("السنة فقط", "Year only")
            case .missing:  return L10n.t("بلا تاريخ", "No date")
            }
        }

        func matches(_ e: DeathDatesEntry) -> Bool {
            switch self {
            case .all:      return true
            case .yearOnly: return !e.isMissing
            case .missing:  return e.isMissing
            }
        }
    }

    /// تصفية الصفحة (ورقة «تصفية»، F3): «التاريخ» اختيار متعدّد (فارغة = «الكل»، وأيّ المختار)، و«الفرع» رأس فرع بأي مستوى
    /// (nil = كل الفروع) وذرّيته — اختيار واحد
    struct Filters: Equatable {
        var kinds: Set<Filter>
        var branch: UUID?

        /// اختيار واحد في «التاريخ» (رقم الرأس) — «الكل» = لا اختيار
        init(kind: Filter = .all, branch: UUID? = nil) {
            self.init(kinds: [kind], branch: branch)
        }

        init(kinds: Set<Filter>, branch: UUID? = nil) {
            self.kinds = kinds.subtracting([.all])
            self.branch = branch
        }

        func matches(_ e: DeathDatesEntry) -> Bool {
            kinds.isEmpty || kinds.contains { $0.matches(e) }
        }
    }

    /// ورقة «تصفية» — من زرّها ومن «تعديل التصفية» في البطاقة الفارغة
    @State private var showsFilters = false

    @State private var filters = Filters()
    /// الآباء والأبناء — مرة لكل تغيّر في الأعضاء
    @State private var tree = AdminFamilyTree.empty
    /// ذرّية الفرع المطبَّق (`filters.branch`) — مرة لكل تغيّر فيه
    @State private var branchSet: Set<UUID>?
    @State private var query = ""
    /// المتوفون بلا تاريخ كامل — أبجدياً
    @State private var entries: [DeathDatesEntry] = []
    @State private var stats = DeathDatesStats()
    @State private var built = false
    @State private var target: FamilyMember?
    /// من فُتح مربّعه — لحظة «اكتمل» حين يصير تاريخه كاملاً
    @State private var editing: UUID?
    @State private var limit = Self.pageSize
    /// «⋯» أدوات الحملة (المالك)
    @State private var showTools = false

    static let pageSize = 40

    init() {}

    static var title: String { L10n.t("تواريخ الوفاة", "Death dates") }

    // حارس المكدس: الصفحة والمربّعات طبقات خلف `AnyView`
    var body: some View {
        AnyView(page)
            .debugStackProbe("DeathDatesCampaignPage")
    }

    private var page: some View {
        AdminPage(header: header, content: AnyView(content))
            .dsCenterBox(item: $target) { m in
                DeceasedDateBox(member: m)
            }
            .dsCenterBox(isPresented: $showTools) {
                DeathDatesToolsBox(stats: built ? stats : nil)
            }
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: query) { _ in limit = Self.pageSize }
            .onChange(of: filters) { f in
                limit = Self.pageSize
                branchSet = f.branch.map { tree.subtree(of: $0) }
            }
            .onChange(of: target?.id) { id in
                // أُغلق المربّع: من اكتمل تاريخه — لحظة «اكتمل»
                guard id == nil, let done = editing else { return }
                editing = nil
                guard let m = memberVM.member(byId: done), case .exact = DeceasedMemorial.classify(m.deathDate) else { return }
                DSMomentToast.show(L10n.t("اكتمل تاريخ \(m.shortFullName)", "\(m.shortFullName)'s date is complete"), moment: .success)
            }
    }

    private func reload(force: Bool) async {
        if memberVM.allMembers.isEmpty || force { await memberVM.fetchAllMembers(force: force) }
        rebuild()
        await store.refresh(force: force)
    }

    private func rebuild() {
        let all = memberVM.allMembers
        let list = DeathDatesCampaign.entries(all)
        // أبجدياً بالحروف العربية المطبّعة (نفس ترتيب «العائلة»)
        let order = AdminGrouping.alphabetical(list.map(\.member)).enumerated()
            .reduce(into: [UUID: Int]()) { $0[$1.element.id] = $1.offset }
        entries = list.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        stats = DeathDatesCampaign.stats(all)
        tree = AdminFamilyTree(all)
        branchSet = filters.branch.map { tree.subtree(of: $0) }
        built = !all.isEmpty
    }

    /// «أدخل» ومربّع التاريخ: صلاحية الدور مضروبة بـ«يعدّل» في جدول السيرفر (Autoplan note 7)
    private var canEdit: Bool { authVM.canEditMembers && authVM.adminCanEdit(.family) }

    private func open(_ m: FamilyMember) {
        guard canEdit else { return }
        if DebugAdminProbe.dryRun("death date box \(m.id)") { return }
        editing = m.id
        target = m
    }

    // MARK: الرأس

    private var header: AdminPageHeader {
        let ready = built
        let items = [
            AdminHeaderItem(id: "incomplete", value: ready ? stats.incomplete : nil,
                            label: L10n.t("بلا تاريخ كامل", "without a full date"),
                            tap: .action { land(.all) }),
            AdminHeaderItem(id: "yearOnly", value: ready ? stats.yearOnly : nil, label: Filter.yearOnly.title,
                            tap: .action { land(.yearOnly) }),
            AdminHeaderItem(id: "missing", value: ready ? stats.missing : nil, label: Filter.missing.title,
                            tap: .action { land(.missing) }),
        ]
        return AdminPageHeader(title: Self.title,
                               readOnly: !authVM.adminCanEdit(.family),
                               items: items,
                               actions: authVM.isOwner
                                   ? [AdminPageAction(symbol: "ellipsis", label: L10n.t("أدوات الحملة", "Campaign tools"),
                                                      tap: .action { showTools = true })]
                                   : [],
                               accessory: AnyView(DeathDatesHeadline(stats: built ? stats : nil)))
    }

    /// رقم الرأس يفتح قائمته: «التاريخ» وحده، بلا فرع ولا بحث — فأول رقم تحت الشريط = الرقم المضغوط (T2)
    private func land(_ kind: Filter) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
            filters = Filters(kind: kind)
            query = ""
        }
    }

    // MARK: الفلاتر

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// ورقة «تصفية»: «التاريخ» بأعداده لأي حالة (بعد البحث والفرع)، و«الفرع» صفّ يفتح قائمة الفروع داخل الورقة.
    /// «النتيجة الآن» = القائمة نفسها
    private func filterSet() -> AdminFilterSet<Filters> {
        let entries = self.entries
        let tree = self.tree
        let applied = filters.branch
        let appliedSet = branchSet
        let words = NameSearch.words(trimmedQuery)
        let members = memberVM.allMembers
        let name: (UUID) -> String = { id in self.branchTitle(id) }
        let subtree: (UUID?) -> Set<UUID>? = { id in
            guard let id else { return nil }
            return id == applied ? appliedSet : tree.subtree(of: id)
        }
        let count: (Filters) -> Int? = { s in
            let set = subtree(s.branch)
            return entries.reduce(0) { n, e in
                guard s.matches(e), set?.contains(e.id) ?? true else { return n }
                guard words.isEmpty || NameSearch.score(queryWords: words, candidateWords: NameSearch.words(e.needle)) != nil
                else { return n }
                return n + 1
            }
        }
        return AdminFilterSet(noun: { Self.deceasedNoun($0) }, resultCount: count) { s in
            // عدد كل خيار = النتيجة لو اختير وحده مع الفرع والبحث
            let kinds = Filter.allCases.filter { $0 != .all }.map { kind -> AdminFilterOption<Filter> in
                var probe = s
                probe.kinds = [kind]
                return AdminFilterOption(kind, kind.title, count: count(probe))
            }
            let groups: [AdminFilterGroup<Filters>] = [
                .choices("kind", title: L10n.t("التاريخ", "Date"), values: \.kinds, options: kinds),
                .picker("branch", title: L10n.t("الفرع", "Branch"), value: \.branch, all: nil,
                        allTitle: L10n.t("كل الفروع", "All branches"), valueTitle: s.branch.map(name),
                        chooseTitle: L10n.t("اختر فرعاً", "Pick a branch"),
                        count: s.branch == nil ? nil : count(s), ownsHeader: true) { current, pick in
                    AnyView(BranchPickerSheet(allMembers: members, selectedId: current, allLevels: true,
                                              onSelect: { pick($0) }))
                },
            ]
            return groups
        }
    }

    /// «متوفى» · «متوفيان» · «متوفين» · «متوفى»
    static func deceasedNoun(_ n: Int) -> String {
        L10n.t(AdminFilterText.noun(n, one: "متوفى", two: "متوفيان", few: "متوفين", many: "متوفى"),
               n == 1 ? "deceased" : "deceased")
    }

    /// اسم الفرع في صفّ «الفرع» وشريحته: الاسم المخصّص من «أسماء العوائل والفروع» إن وُجد، وإلا الاسم المختصر لرأسه
    private func branchTitle(_ id: UUID) -> String {
        if let custom = appSettingsVM.branchName(for: id) { return custom }
        let m = tree.byId[id] ?? memberVM.member(byId: id)
        return m.map { $0.shortFullName.isEmpty ? $0.fullName : $0.shortFullName } ?? L10n.t("فرع", "Branch")
    }

    // MARK: المحتوى

    private var visible: [DeathDatesEntry] {
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب
        let q = NameSearch.words(trimmedQuery)
        let set = branchSet
        let current = filters
        return entries.filter { e in
            current.matches(e) && (set?.contains(e.id) ?? true)
                && (q.isEmpty || NameSearch.score(queryWords: q, candidateWords: NameSearch.words(e.needle)) != nil)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            if memberVM.membersLoadFailed && memberVM.allMembers.isEmpty {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: { Task { await reload(force: true) } }))
            } else if !built {
                AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…"), rows: 5))
            } else if entries.isEmpty {
                AdminPageStateCard(.empty(L10n.t("اكتملت كل التواريخ", "Every date is complete"),
                                          message: L10n.t("ذكراهم كلها في «ذكرى الراحلين».", "All their memorials now show."),
                                          tint: DS.Color.success))
            } else {
                AnyView(loaded)
            }
        }
    }

    private var loaded: some View {
        let rows = visible
        let set = filterSet()
        return VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            AdminFilterPanel(set: set, selection: $filters, search: $query,
                             placeholder: L10n.t("ابحث بالاسم", "Search by name"),
                             note: L10n.t("أبجدياً", "A–Z"), openFilters: { showsFilters = true })
            if rows.isEmpty {
                if !trimmedQuery.isEmpty {
                    AdminPageStateCard(.empty(L10n.t("لا أحد بهذا الاسم", "Nobody with this name"),
                                              actionTitle: L10n.t("مسح البحث", "Clear search"),
                                              action: { query = "" }))
                } else {
                    // لا مسح للكل (F3): الورقة تُفتح للتعديل، والشرائح فوق تُزال واحدة واحدة
                    AdminFilterEmptyCard(editFilters: { showsFilters = true })
                }
            } else {
                AnyView(listCard(rows))
            }
        }
        .adminFilterSheet(isPresented: $showsFilters, set: set, selection: $filters)
    }

    // MARK: القائمة

    private func listCard(_ rows: [DeathDatesEntry]) -> some View {
        let shown = Array(rows.prefix(limit))
        let editable = canEdit
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { pos, e in
                    if pos > 0 { AdminRowDivider(inset: DS.Icon.avatar + DS.Spacing.md) }
                    entryRow(e, editable: editable)
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

    /// صفّ متوفى يفتح مربّع الاستكمال — للاطلاع: الصفّ وحده بلا «أدخل» ولا ضغطة
    @ViewBuilder
    private func entryRow(_ e: DeathDatesEntry, editable: Bool) -> some View {
        if editable {
            Button { open(e.member) } label: {
                DeathDatesRow(entry: e, detail: detail(e))
            }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityHint(L10n.t("يفتح مربّع إدخال تاريخ الوفاة", "Opens the death date box"))
        } else {
            DeathDatesRow(entry: e, detail: detail(e), canEdit: false)
        }
    }

    /// «بلا تاريخ · فرع X» / «السنة فقط: 1931 · فرع X»
    private func detail(_ e: DeathDatesEntry) -> String {
        var parts = [e.isMissing ? L10n.t("بلا تاريخ", "No date") : DeathDatesCampaign.note(e.kind)]
        if let branch = rowBranchTitle(e.branch) { parts.append(branch) }
        return parts.joined(separator: " · ")
    }

    /// «فرع X» — الاسم المخصّص من «أسماء العوائل والفروع» إن وُجد
    private func rowBranchTitle(_ head: UUID?) -> String? {
        guard let head else { return nil }
        if let name = appSettingsVM.branchName(for: head) { return name }
        return memberVM.member(byId: head).map { L10n.t("فرع \($0.firstName)", "\($0.firstName) branch") }
    }
}

// MARK: - شريط التقدّم في الرأس

/// شريط رفيع و«اكتمل 3 من 367» فوق الكحلي (الرقم الكبير صار سطر الأرقام — spec A.3/A.10)
struct DeathDatesHeadline: View {
    let stats: DeathDatesStats?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(verbatim: progressText)
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.accentLight)
                .fixedSize()
            DSMeterBar(parts: stats?.share.map { [DSGaugePart("full", share: $0, tint: DS.Color.accentLight)] },
                       track: DS.Ring.bandTrack)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressText)
    }

    /// «اكتمل 3 من 367»
    private var progressText: String {
        guard let s = stats else { return L10n.t("اكتمل — من —", "— of — complete") }
        let need = s.full + s.incomplete
        return L10n.t("اكتمل \(s.full) من \(need)", "\(s.full) of \(need) complete")
    }
}

/// صفّ متوفى: الصورة · الاسم · حاله وفرعه · «أدخل» كحلي — مع الخط الكبير (XXL فأكبر) الزرّ تحت النص.
/// `canEdit: false` = للاطلاع بلا «أدخل»
struct DeathDatesRow: View {
    let entry: DeathDatesEntry
    let detail: String
    var canEdit: Bool = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let member = entry.member
        let stacked = typeSize >= .xxLarge
        let text = VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(member.shortFullName.isEmpty ? member.fullName : member.shortFullName)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .dsNameLines()
            Text(verbatim: detail)
                .dsFont(.footnote)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        return HStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: DS.Color.deceased)
                .grayscale(1)
                .accessibilityHidden(true)
            if stacked {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    text
                    if canEdit { action }
                }
                Spacer(minLength: 0)
            } else {
                text
                Spacer(minLength: DS.Spacing.xs)
                if canEdit { action }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.displayFullName)، \(detail)")
        .accessibilityAddTraits(canEdit ? .isButton : [])
    }

    private var action: some View {
        AdminPillLabel(title: L10n.t("أدخل", "Enter"), style: .navy, height: DS.Hub.pillHeightCard)
            .fixedSize()
    }
}

// MARK: - «⋯» أدوات الحملة (المالك)

/// مربّع «أدوات الحملة»: حالها في «اليوم» ثم إبرازها وآخر يوم (`DeathDatesOwnerControls` — كما كانت في أعلى الصفحة)؛
/// قبل مفتاحي الحملة في السيرفر ملاحظة فقط بلا أزرار لا تعمل
private struct DeathDatesToolsBox: View {
    let stats: DeathDatesStats?
    @ObservedObject private var store = DeathDatesCampaignStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSComposer(title: L10n.t("أدوات الحملة", "Campaign tools"),
                   subtitle: L10n.t("للمالك", "Owner only"),
                   icon: "megaphone.fill",
                   tint: DS.Color.actionNavy,
                   actionTitle: "",
                   showsAction: false,
                   cancelTitle: L10n.t("إغلاق", "Close"),
                   canSubmit: false,
                   onSubmit: {},
                   onCancel: { dismiss() }) {
            DSComposerSection(title: L10n.t("في «اليوم»", "On Today"), icon: "star.fill", tint: DS.Color.actionNavy, index: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    AdminInfoRow(icon: active ? "megaphone.fill" : "leaf.fill",
                                 tint: active ? DS.Color.sadu : DS.Color.textTertiary,
                                 title: statusTitle, subtitle: statusDetail)
                    if store.serverReady {
                        AnyView(DeathDatesOwnerControls())
                    } else {
                        AdminRowDivider()
                        Text(L10n.t("إبرازها وآخر يوم يعملان بعد إضافة مفتاحي الحملة في السيرفر — حتى ذلك تبقى ظاهرة ما دام في التواريخ ناقص.",
                                    "Featuring and the last day work once the campaign keys are on the server — until then it shows while dates are missing."))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, DS.Spacing.sm)
                    }
                }
                .dsRowBox()
            }
        }
    }

    private var active: Bool { stats.map { store.isActive($0) } ?? true }

    private var statusTitle: String {
        if active { return L10n.t("ظاهرة في «اليوم» تحت الأقسام", "Shown on Today under the sections") }
        if let s = stats, s.incomplete == 0 { return L10n.t("اكتملت التواريخ", "The dates are complete") }
        return L10n.t("انتهت الحملة", "The campaign has ended")
    }

    private var statusDetail: String {
        if active {
            return store.until.map { L10n.t("حتى \(DeathDatesCampaignStore.untilText($0))، ثم مكانها «ذكرى الراحلين»",
                                            "Until \(DeathDatesCampaignStore.untilText($0)), then Memorials take its place") }
                ?? L10n.t("حتى تكتمل التواريخ، ثم مكانها «ذكرى الراحلين»", "Until the dates are complete, then Memorials take its place")
        }
        return L10n.t("مكانها في «اليوم» «ذكرى الراحلين» — ومن بلا تاريخ: «\(DeathDatesCampaign.noFullDate)»",
                      "Memorials take its place on Today — the rest show “\(DeathDatesCampaign.noFullDate)”")
    }
}

/// للمالك: «إبرازها في «اليوم»» وآخر يوم — `set_app_config`. تُرسم فقط بعد إضافة المفتاحين في السيرفر (ترحيل بانتظار
/// موافقة المالك) — لا أزرار معطّلة قبلها
private struct DeathDatesOwnerControls: View {
    @ObservedObject private var store = DeathDatesCampaignStore.shared
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminRowDivider()
            AdminControlRow(icon: "star.fill", tint: DS.Color.accent,
                            title: L10n.t("إبرازها في «اليوم»", "Feature on Today"),
                            subtitle: L10n.t("يمكن إيقافها في أي وقت، وتعود مكانها «ذكرى الراحلين»", "Stop it any time — Memorials return"),
                            control: AnyView(Toggle(L10n.t("إبرازها في «اليوم»", "Feature on Today"), isOn: Binding(
                                get: { store.enabled ?? true },
                                set: { on in
                                    if DebugAdminProbe.dryRun("app_config death_dates_campaign=\(on)") { return }
                                    Task { failure = await store.save(enabled: on) }
                                }))
                                .labelsHidden()
                                .tint(DS.Color.accent)))
            AdminRowDivider()
            AdminControlRow(icon: "calendar", tint: DS.Color.sadu,
                            title: L10n.t("آخر يوم", "Last day"),
                            subtitle: store.until == nil ? L10n.t("تبقى حتى تكتمل التواريخ", "Stays until the dates are complete")
                                                         : L10n.t("بعده تعود مكانها «ذكرى الراحلين»", "Memorials return after it"),
                            control: AnyView(untilControl))
            if let failure {
                Text(failure)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .disabled(store.isSaving)
    }

    /// آخر يوم: قائمة أصلية بمدد جاهزة (أسبوعان · شهر · شهران · ٣ أشهر) و«بلا نهاية» — الشريحة تعرض الحالي
    private var untilControl: some View {
        Menu {
            ForEach(Self.presets, id: \.days) { preset in
                Button(preset.title) { save(days: preset.days) }
            }
            if store.until != nil {
                Divider()
                Button(L10n.t("بلا نهاية — حتى تكتمل التواريخ", "No end — until the dates are complete"), role: .destructive) {
                    if DebugAdminProbe.dryRun("app_config death_dates_campaign_until=nil") { return }
                    Task { failure = await store.save(until: nil) }
                }
            }
        } label: {
            AdminValueChip(text: store.until.map { DeathDatesCampaignStore.untilText($0) } ?? L10n.t("بلا نهاية", "No end"),
                           icon: "chevron.up.chevron.down", tint: DS.Color.sadu)
                .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.section)
        }
        .accessibilityLabel(L10n.t("آخر يوم للحملة", "Campaign last day"))
    }

    private struct Preset { let days: Int; let title: String }

    private static let presets: [Preset] = [
        Preset(days: 14, title: L10n.t("بعد أسبوعين", "In two weeks")),
        Preset(days: 30, title: L10n.t("بعد شهر", "In a month")),
        Preset(days: 60, title: L10n.t("بعد شهرين", "In two months")),
        Preset(days: 90, title: L10n.t("بعد ٣ أشهر", "In 3 months"))
    ]

    /// اليوم (بتوقيت الكويت) + المدة
    private func save(days: Int) {
        let cal = DeathDatesCampaignStore.calendar
        guard let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) else { return }
        if DebugAdminProbe.dryRun("app_config death_dates_campaign_until=+\(days)d") { return }
        Task { failure = await store.save(until: day) }
    }
}
