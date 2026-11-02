import SwiftUI

// MARK: - صفحة «إدارة الوفيات» (طلب المالك ٢٠٢٦-١٠-٢٤؛ مبسّطة ٢٠٢٦-١١-٠٢ — `samples/simplify`)
//
// الرأس: ‹ اليوم · «إدارة الوفيات» · «⋯» (للمالك: أدوات الحملة — إبرازها في «اليوم» وآخر يوم، كما كانت؛ قبل مفتاحي الحملة
// في السيرفر ملاحظة بلا أزرار) ← رقم واحد كبير «364 متوفى بلا تاريخ وفاة كامل» ← شريط رفيع و«اكتمل 3 من 367» ← البحث بالاسم
// ← شرائح الكل · السنة فقط · بلا تاريخ ← «الفرع: الكل ⌄» والعدد ← قائمة واحدة أبجدياً: الصورة · الاسم · «بلا تاريخ · فرع X»
// / «السنة فقط: 1931 · فرع X» · زرّ «أدخل» يفتح مربّع الاستكمال الموجود (`DeceasedDateBox` — نفس الحفظ). ما يكتمل يخرج
// من القائمة فوراً مع لحظة «اكتمل». حُذف: الحلقة الكبيرة، بطاقات الفروع و«التقسيم»، و«أُكملت مؤخراً».

struct DeathDatesCampaignPage: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var store = DeathDatesCampaignStore.shared

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

    @State private var filter: Filter = .all
    /// الآباء والأبناء — مرة لكل تغيّر في الأعضاء
    @State private var tree = AdminFamilyTree.empty
    /// «الفرع: …» — رأس فرع بأي مستوى (nil = الكل) وذرّيته
    @State private var branchFilter: UUID?
    @State private var branchSet: Set<UUID>?
    @State private var showBranchPicker = false
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

    var body: some View {
        AdminPage(header: header, content: AnyView(content))
            .dsCenterBox(item: $target) { m in
                DeceasedDateBox(member: m)
            }
            .dsCenterBox(isPresented: $showTools) {
                DeathDatesToolsBox(stats: built ? stats : nil)
            }
            .modifier(AdminBranchPickerBox(isPresented: $showBranchPicker, members: memberVM.allMembers,
                                           selected: branchFilter, onSelect: { pickBranch($0) }))
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                rebuild()
                await store.refresh()
            }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: query) { _ in limit = Self.pageSize }
            .onChange(of: target?.id) { id in
                // أُغلق المربّع: من اكتمل تاريخه — لحظة «اكتمل»
                guard id == nil, let done = editing else { return }
                editing = nil
                guard let m = memberVM.member(byId: done), case .exact = DeceasedMemorial.classify(m.deathDate) else { return }
                DSMomentToast.show(L10n.t("اكتمل تاريخ \(m.shortFullName)", "\(m.shortFullName)'s date is complete"), moment: .success)
            }
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
        branchSet = branchFilter.map { tree.subtree(of: $0) }
        built = !all.isEmpty
    }

    // MARK: الفرع المختار

    private func pickBranch(_ id: UUID?) {
        guard id != branchFilter else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        branchFilter = id
        branchSet = id.map { tree.subtree(of: $0) }
        limit = Self.pageSize
    }

    /// اسم الفرع المختار في الشريحة (الاسم المختصر للرأس)
    private var branchFilterTitle: String? {
        guard let id = branchFilter else { return nil }
        let m = tree.byId[id] ?? memberVM.member(byId: id)
        return m.map { $0.shortFullName.isEmpty ? $0.fullName : $0.shortFullName } ?? L10n.t("فرع", "Branch")
    }

    private func open(_ m: FamilyMember) {
        editing = m.id
        target = m
    }

    // MARK: الرأس

    private var header: AdminPageHeader {
        AdminPageHeader(title: L10n.t("إدارة الوفيات", "Deaths"),
                        actions: authVM.isOwner
                            ? [AdminPageAction(symbol: "ellipsis", label: L10n.t("أدوات الحملة", "Campaign tools"),
                                               tap: .action { showTools = true })]
                            : [],
                        accessory: AnyView(headerAccessory))
    }

    private var headerAccessory: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AnyView(DeathDatesHeadline(stats: built ? stats : nil))
            AdminBandSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم", "Search by name"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(Filter.allCases) { f in
                        AdminBandFilterChip(title: f.title, count: built ? count(f) : nil, selected: filter == f) {
                            guard filter != f else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(DS.Anim.snappy) {
                                filter = f
                                limit = Self.pageSize
                            }
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
        }
    }

    private func count(_ f: Filter) -> Int {
        // داخل الفرع المختار: من القائمة نفسها
        if let set = branchSet {
            return entries.reduce(0) { $0 + (set.contains($1.id) && f.matches($1) ? 1 : 0) }
        }
        switch f {
        case .all:      return stats.incomplete
        case .yearOnly: return stats.yearOnly
        case .missing:  return stats.missing
        }
    }

    // MARK: المحتوى

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visible: [DeathDatesEntry] {
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب
        let q = NameSearch.words(trimmedQuery)
        let set = branchSet
        return entries.filter { e in
            filter.matches(e) && (set?.contains(e.id) ?? true) && (q.isEmpty || NameSearch.matchPosition(queryWords: q, candidateWords: NameSearch.words(e.needle)) != nil)
        }
    }

    private var content: some View {
        let rows = visible
        return VStack(spacing: DS.Hub.stackSpacing) {
            if !built {
                AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…")))
            } else if entries.isEmpty {
                AdminPageStateCard(.empty(L10n.t("اكتملت كل التواريخ", "Every date is complete"),
                                          message: L10n.t("ذكراهم كلها في «ذكرى الراحلين».", "All their memorials now show."),
                                          tint: DS.Color.success))
            } else {
                AnyView(AdminMembersFilterBar(branchTitle: branchFilterTitle,
                                              countText: L10n.t("\(AdminMembersFilterBar.grouped(rows.count)) متوفى",
                                                                "\(AdminMembersFilterBar.grouped(rows.count)) deceased"),
                                              pickBranch: { showBranchPicker = true },
                                              clearBranch: { pickBranch(nil) }))
                if rows.isEmpty {
                    AdminPageStateCard(.empty(L10n.t("لا نتائج", "No results"),
                                              message: L10n.t("جرّب اسماً آخر أو شريحة أخرى", "Try another name or filter")))
                } else {
                    AnyView(listCard(rows))
                }
            }
        }
    }

    // MARK: القائمة

    private func listCard(_ rows: [DeathDatesEntry]) -> some View {
        let shown = Array(rows.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { pos, e in
                    if pos > 0 { AdminRowDivider() }
                    entryRow(e)
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

    /// صفّ متوفى يفتح مربّع الاستكمال
    private func entryRow(_ e: DeathDatesEntry) -> some View {
        Button { open(e.member) } label: {
            DeathDatesRow(entry: e, detail: detail(e))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح مربّع إدخال تاريخ الوفاة", "Opens the death date box"))
    }

    /// «بلا تاريخ · فرع X» / «السنة فقط: 1931 · فرع X»
    private func detail(_ e: DeathDatesEntry) -> String {
        var parts = [e.isMissing ? L10n.t("بلا تاريخ", "No date") : DeathDatesCampaign.note(e.kind)]
        if let branch = branchTitle(e.branch) { parts.append(branch) }
        return parts.joined(separator: " · ")
    }

    /// «فرع X» — الاسم المخصّص من «أسماء العوائل والفروع» إن وُجد
    private func branchTitle(_ head: UUID?) -> String? {
        guard let head else { return nil }
        if let name = appSettingsVM.branchName(for: head) { return name }
        return memberVM.member(byId: head).map { L10n.t("فرع \($0.firstName)", "\($0.firstName) branch") }
    }
}

// MARK: - رقم الرأس وشريط التقدّم

/// «364 متوفى بلا تاريخ وفاة كامل» ثم شريط رفيع و«اكتمل 3 من 367» — فوق الكحلي
struct DeathDatesHeadline: View {
    let stats: DeathDatesStats?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) { number; label }
                VStack(alignment: .leading, spacing: 0) { number; label }
            }
            DSMeterBar(parts: stats?.share.map { [DSGaugePart("full", share: $0, tint: DS.Color.accentLight)] },
                       track: DS.Ring.bandTrack)
                .padding(.top, DS.Spacing.xs)
                .accessibilityHidden(true)
            Text(verbatim: progressText)
                .dsFont(.hubLabel)
                .monospacedDigit()
                .foregroundColor(DS.Hub.onBandMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(stats.map { "\($0.incomplete)" } ?? "—") متوفى بلا تاريخ وفاة كامل، \(progressText)",
                                   "\(stats.map { "\($0.incomplete)" } ?? "—") deceased without a full date, \(progressText)"))
    }

    private var number: some View {
        Text(verbatim: stats.map { "\($0.incomplete)" } ?? "—")
            .dsFont(.heroTitle)
            .monospacedDigit()
            .foregroundColor(DS.Color.accentLight)
    }

    private var label: some View {
        Text(L10n.t("متوفى بلا تاريخ وفاة كامل", "deceased without a full death date"))
            .dsFont(.hubRow)
            .foregroundColor(DS.Color.accentLight)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// «اكتمل 3 من 367»
    private var progressText: String {
        guard let s = stats else { return L10n.t("اكتمل — من —", "— of — complete") }
        let need = s.full + s.incomplete
        return L10n.t("اكتمل \(s.full) من \(need)", "\(s.full) of \(need) complete")
    }
}

/// صفّ متوفى: الصورة · الاسم · حاله وفرعه · «أدخل» كحلي — مع الخط الكبير (XXL فأكبر) الزرّ تحت النص
struct DeathDatesRow: View {
    let entry: DeathDatesEntry
    let detail: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let member = entry.member
        let stacked = typeSize >= .xxLarge
        let action = AdminPillLabel(title: L10n.t("أدخل", "Enter"), style: .navy, height: DS.Hub.pillHeightCard)
            .fixedSize()
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
                VStack(alignment: .leading, spacing: DS.Spacing.sm) { text; action }
                Spacer(minLength: 0)
            } else {
                text
                Spacer(minLength: DS.Spacing.xs)
                action
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.displayFullName)، \(detail)")
        .accessibilityAddTraits(.isButton)
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
                    AdminInfoRow(icon: active ? "megaphone.fill" : "moon.stars.fill",
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
                            subtitle: L10n.t("أوقفها متى شئت — يرجع مكانها «ذكرى الراحلين»", "Stop it any time — Memorials return"),
                            control: AnyView(Toggle("", isOn: Binding(
                                get: { store.enabled ?? true },
                                set: { on in Task { failure = await store.save(enabled: on) } }))
                                .labelsHidden()
                                .tint(DS.Color.accent)))
            AdminRowDivider()
            AdminControlRow(icon: "calendar", tint: DS.Color.sadu,
                            title: L10n.t("آخر يوم", "Last day"),
                            subtitle: store.until == nil ? L10n.t("تبقى حتى تكتمل التواريخ", "Stays until the dates are complete")
                                                         : L10n.t("بعده يرجع مكانها «ذكرى الراحلين»", "Memorials return after it"),
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
        Task { failure = await store.save(until: day) }
    }
}
