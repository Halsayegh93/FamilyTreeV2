import SwiftUI

// MARK: - صفحة «إدارة تواريخ الوفاة» (طلب المالك ٢٠٢٦-١٠-٢٤)
//
// الرأس: العنوان والوصف، البحث بالاسم، وشرائح الكل · السنة فقط · بلا تاريخ ← أول بطاقة تصعد فوقه: الحلقة وحال الحملة
// (وللمالك: إيقافها وآخر يوم — `app_config` — يظهران فقط حين يكون مفتاحا الحملة في السيرفر؛ قبلها لا أزرار معطّلة: طلب
// المالك ٢٠٢٦-١٠-٢٥ «في ازرار مو شغال بالداخل») ← «حسب الفرع | حسب العقد» ← بطاقة لكل فرع
// أو عقد، كل صفّ متوفى بحاله («السنة فقط: 1995» / «بدون تاريخ») وزرّ «أدخل التاريخ» يفتح مربّع الاستكمال الموجود
// (`DeceasedDateBox` — عجلة اليوم والشهر والسنة) ← «أُكملت مؤخراً»: من أكمل ومتى. ما يكتمل يخرج من القائمة فوراً
// (تحديث محلي) مع لحظة «اكتمل». البطاقات أنواع مستقلة خلف `AnyView` (حارس المكدس).

struct DeathDatesCampaignPage: View {
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

    enum Grouping: Hashable { case branch, decade }

    /// بطاقة فرع أو عقد
    struct Section: Identifiable {
        let id: String
        let title: String
        let rows: [DeathDatesEntry]
    }

    @State private var filter: Filter = .all
    @State private var grouping: Grouping = .branch
    @State private var query = ""
    @State private var entries: [DeathDatesEntry] = []
    @State private var stats = DeathDatesStats()
    @State private var built = false
    @State private var target: FamilyMember?
    /// من فُتح مربّعه — لحظة «اكتمل» حين يصير تاريخه كاملاً
    @State private var editing: UUID?
    /// «عرض المزيد» لكل بطاقة
    @State private var limits: [String: Int] = [:]

    static let preview = 6
    static let pageSize = 20

    var body: some View {
        AdminPage(header: header, lead: AnyView(DeathDatesProgressCard(stats: built ? stats : nil)),
                  content: AnyView(content))
            .dsCenterBox(item: $target) { m in
                DeceasedDateBox(member: m)
            }
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                rebuild()
                async let config: Void = store.refresh()
                async let recent: Void = store.refreshRecent()
                _ = await (config, recent)
            }
            .onChange(of: memberVM.membersVersion) { _ in rebuild() }
            .onChange(of: query) { _ in limits = [:] }
            .onChange(of: target?.id) { id in
                // أُغلق المربّع: من اكتمل تاريخه — لحظة «اكتمل»، و«أُكملت مؤخراً» تُحدَّث
                guard id == nil, let done = editing else { return }
                editing = nil
                guard let m = memberVM.member(byId: done), case .exact = DeceasedMemorial.classify(m.deathDate) else { return }
                DSMomentToast.show(L10n.t("اكتمل تاريخ \(m.shortFullName)", "\(m.shortFullName)'s date is complete"), moment: .success)
                Task { await store.refreshRecent() }
            }
    }

    private func rebuild() {
        let all = memberVM.allMembers
        entries = DeathDatesCampaign.entries(all)
        stats = DeathDatesCampaign.stats(all)
        built = !all.isEmpty
    }

    private func open(_ m: FamilyMember) {
        editing = m.id
        target = m
    }

    // MARK: الرأس

    private var header: AdminPageHeader {
        AdminPageHeader(title: L10n.t("إدارة تواريخ الوفاة", "Death dates"),
                        subtitle: L10n.t("أكمل اليوم والشهر والسنة — تظهر ذكراهم في «ذكرى الراحلين»",
                                         "Add the day, month and year — their memorial then shows"),
                        glyph: "calendar.badge.clock",
                        accessory: AnyView(headerAccessory))
    }

    private var headerAccessory: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminBandSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم", "Search by name"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(Filter.allCases) { f in
                        AdminBandFilterChip(title: f.title, count: built ? count(f) : nil, selected: filter == f) {
                            guard filter != f else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(DS.Anim.snappy) {
                                filter = f
                                limits = [:]
                            }
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
        }
    }

    private func count(_ f: Filter) -> Int {
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
        return entries.filter { e in
            filter.matches(e) && (q.isEmpty || NameSearch.matchPosition(queryWords: q, candidateWords: NameSearch.words(e.needle)) != nil)
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
            } else if rows.isEmpty {
                AdminPageStateCard(.empty(L10n.t("لا نتائج", "No results"),
                                          message: L10n.t("جرّب اسماً آخر أو شريحة أخرى", "Try another name or filter")))
            } else if !trimmedQuery.isEmpty {
                AnyView(sectionCard(Section(id: "results", title: L10n.t("النتائج", "Results"), rows: rows)))
            } else {
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: Grouping.branch, title: L10n.t("حسب الفرع", "By branch"), icon: "point.3.connected.trianglepath.dotted"),
                    DSSegmentOption(id: Grouping.decade, title: L10n.t("حسب العقد", "By decade"), icon: "calendar")
                ], selection: Binding(get: { grouping }, set: { g in
                    withAnimation(DS.Anim.snappy) { grouping = g; limits = [:] }
                }), size: .regular)
                ForEach(sections(rows)) { s in
                    AnyView(sectionCard(s))
                }
            }
            if built {
                AnyView(DeathDatesRecentCard(recent: store.recent))
            }
        }
    }

    // MARK: التجميع

    private func sections(_ rows: [DeathDatesEntry]) -> [Section] {
        grouping == .branch ? branchSections(rows) : decadeSections(rows)
    }

    /// الفروع بترتيب الشجرة (أبناء الرأس)، ثم «خارج الفروع»
    private func branchSections(_ rows: [DeathDatesEntry]) -> [Section] {
        var by: [UUID: [DeathDatesEntry]] = [:]
        var rest: [DeathDatesEntry] = []
        for e in rows {
            // رأس غير محمّل (نادر) يُعدّ خارج الفروع — لا يسقط أحد من القائمة
            if let b = e.branch, memberVM.member(byId: b) != nil { by[b, default: []].append(e) } else { rest.append(e) }
        }
        let heads = by.keys.compactMap { memberVM.member(byId: $0) }
            .sorted { ($0.sortOrder, $0.firstName) < ($1.sortOrder, $1.firstName) }
        var list = heads.map { head in
            Section(id: head.id.uuidString, title: branchTitle(head.id) ?? head.firstName, rows: by[head.id] ?? [])
        }
        if !rest.isEmpty {
            list.append(Section(id: "outside", title: L10n.t("خارج الفروع", "Outside the branches"), rows: rest))
        }
        return list
    }

    /// العقود الأحدث أولاً (أسهل بحثاً في النعي)، ثم الهجري، ثم بلا سنة
    private func decadeSections(_ rows: [DeathDatesEntry]) -> [Section] {
        var by: [Int: [DeathDatesEntry]] = [:]
        var hijri: [DeathDatesEntry] = []
        var missing: [DeathDatesEntry] = []
        for e in rows {
            if let d = e.decade { by[d, default: []].append(e) }
            else if e.isMissing { missing.append(e) }
            else { hijri.append(e) }
        }
        var list = by.keys.sorted(by: >).map { d in
            Section(id: "d\(d)", title: "\(d) – \(d + 9)", rows: by[d] ?? [])
        }
        if !hijri.isEmpty { list.append(Section(id: "hijri", title: L10n.t("مكتوب بالهجري", "Written as Hijri"), rows: hijri)) }
        if !missing.isEmpty { list.append(Section(id: "none", title: L10n.t("بلا سنة", "No year"), rows: missing)) }
        return list
    }

    /// «فرع X» — الاسم المخصّص من «أسماء العوائل والفروع» إن وُجد
    private func branchTitle(_ head: UUID?) -> String? {
        guard let head else { return nil }
        if let name = appSettingsVM.branchName(for: head) { return name }
        return memberVM.member(byId: head).map { L10n.t("فرع \($0.firstName)", "\($0.firstName) branch") }
    }

    // MARK: البطاقة والصف

    private func sectionCard(_ s: Section) -> some View {
        let limit = limits[s.id] ?? Self.preview
        let shown = Array(s.rows.prefix(limit))
        return AdminSectionCard(title: s.title, badge: s.rows.count, badgeTint: DS.Color.warning) {
            VStack(alignment: .leading, spacing: 0) {
                AdminLazyRows(items: shown) { e in
                    AnyView(Button { open(e.member) } label: {
                        DeathDatesRow(entry: e, detail: detail(e))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.t("يفتح مربّع إدخال تاريخ الوفاة", "Opens the death date box")))
                }
                if s.rows.count > limit {
                    AdminPillButton(title: L10n.t("عرض المزيد (\(s.rows.count - limit))", "Show more (\(s.rows.count - limit))"),
                                    icon: "chevron.down", style: .soft, height: DS.Hub.pillHeightCard) {
                        withAnimation(DS.Anim.snappy) { limits[s.id] = limit + Self.pageSize }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.sm)
                }
            }
        }
    }

    /// «السنة فقط: 1995 · مواليد 1920» (+ الفرع حين التجميع بالعقد أو البحث)
    private func detail(_ e: DeathDatesEntry) -> String {
        var parts = [DeathDatesCampaign.note(e.kind)]
        if let born = e.birthYear { parts.append(L10n.t("مواليد \(born)", "Born \(born)")) }
        if grouping == .decade || !trimmedQuery.isEmpty, let branch = branchTitle(e.branch) { parts.append(branch) }
        return parts.joined(separator: " · ")
    }
}

/// صفّ متوفى: الاسم، حاله وميلاده، و«أدخل التاريخ» — مع الخط الكبير (XXL فأكبر) الزرّ تحت النص (الاسم بعرض الصفّ)
struct DeathDatesRow: View {
    let entry: DeathDatesEntry
    let detail: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tint = DeathDatesCampaign.tint(entry.kind)
        let action = AdminPillLabel(title: L10n.t("أدخل التاريخ", "Add date"), icon: "calendar.badge.plus", style: .soft)
        return Group {
            if typeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 0) {
                    AdminListRow(icon: "calendar.badge.exclamationmark", tint: tint, title: entry.member.displayFullName,
                                 subtitle: detail, showsChevron: false)
                    // تحت النص بمحاذاته (بعد مربّع الأيقونة)
                    action
                        .padding(.leading, DS.Hub.iconSquare + DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.sm)
                }
            } else {
                AdminListRow(icon: "calendar.badge.exclamationmark", tint: tint, title: entry.member.displayFullName,
                             subtitle: detail, showsChevron: false) {
                    action
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - أول بطاقة: الحلقة وحال الحملة

/// الحلقة وحال الحملة — وللمالك: إيقافها وآخر يوم، فقط حين يكون مفتاحا الحملة في السيرفر (`serverReady`)؛ قبلها تبقى ظاهرة
/// في «اليوم» ما دام في التواريخ ناقص، بلا أزرار لا تعمل
struct DeathDatesProgressCard: View {
    let stats: DeathDatesStats?
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = DeathDatesCampaignStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DeathDatesGaugeRow(stats: stats)
            AdminRowDivider()
            AdminInfoRow(icon: statusIcon, tint: active ? DS.Color.sadu : DS.Color.textTertiary,
                         title: statusTitle, subtitle: statusDetail)
            if authVM.isOwner && store.serverReady {
                AnyView(DeathDatesOwnerControls())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var active: Bool { stats.map { store.isActive($0) } ?? true }

    private var statusIcon: String { active ? "megaphone.fill" : "moon.stars.fill" }

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

// MARK: - «أُكملت مؤخراً»

/// من اكتمل تاريخه خلال ٣٠ يوماً: الاسم، التاريخ، ومن أكمله ومتى (`profiles.updated_by/updated_at`)
struct DeathDatesRecentCard: View {
    let recent: [DeathDatesCompletion]
    @EnvironmentObject private var memberVM: MemberViewModel

    private static let shown = 5

    private struct Row: Identifiable {
        let member: FamilyMember
        let date: String
        let by: String?
        let at: Date?
        var id: UUID { member.id }
    }

    private var rows: [Row] {
        recent.compactMap { c -> Row? in
            guard let m = memberVM.member(byId: c.id), DeathDatesCampaign.isCounted(m),
                  case let .exact(y, mo, d) = DeceasedMemorial.classify(m.deathDate) else { return nil }
            let by = c.by.flatMap { memberVM.member(byId: $0)?.firstName }
            return Row(member: m, date: "\(DeceasedMemorial.dayMonth(day: d, month: mo, arabic: L10n.isArabic)) \(y)", by: by, at: c.at)
        }
    }

    var body: some View {
        let list = Array(rows.prefix(Self.shown))
        if !list.isEmpty {
            AdminSectionCard(title: L10n.t("أُكملت مؤخراً", "Recently completed"),
                             tag: L10n.t("آخر \(DeathDatesCampaignStore.recentDays) يوماً", "Last \(DeathDatesCampaignStore.recentDays) days")) {
                AdminRowsCardBody {
                    ForEach(list) { r in
                        AdminInfoRow(icon: "checkmark.seal.fill", tint: DS.Color.success, title: r.member.displayFullName,
                                     subtitle: [r.by.map { L10n.t("أكمله \($0)", "By \($0)") },
                                                r.at.map { DateHelper.relativeTime(from: $0) }]
                                        .compactMap { $0 }.joined(separator: " · "),
                                     trailing: AnyView(AdminValueChip(text: r.date, tint: DS.Color.success)))
                    }
                }
            }
        }
    }
}
