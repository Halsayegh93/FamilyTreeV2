import SwiftUI
import UIKit

// MARK: - «التقارير — ثلاث أسئلة وملف واحد» (اختيار المالك ٢٠٢٦-١١-٠٦ «أ»، `samples/admin-family-reports`)
//
// بدل رفّ عشرة تقارير ومعالج وعشر صفحات تصفية: صفحة واحدة بثلاث أسئلة بأسلوب «الإعلان» في المناسبات —
//   «جاهزة بضغطة»: التقارير العشرة و«كتاب الفرع» (`AdminReportPreset`) تعبّئ الأسئلة نفسها، أو تختار بنفسك.
//   ١ «شنو تبي تطبع؟» أجزاء الملف — واحد أو أكثر؛ شيئان فأكثر = ملف واحد بفهرس، وكل جزء يبدأ صفحة.
//   ٢ «عن مين؟» الفرع بأي مستوى («تغيير»)، والحالة · التسجيل · العمر، و«تصفية أخرى»: الفترة · الناقص · الهواتف · الراحلون.
//   ٣ «كيف ترتّبه؟» بالبيوت · بالفرع · بالعمر · أبجدياً · بالدولة، والأعمدة («تعديل» — محفوظة لكل مستخدم).
// أسفل الصفحة زرّ واحد: العدد والصفحات يتحدّثان مع كل اختيار، و«معاينة» تفتح الصفحات كما ستُطبع ثم المشاركة أو الحفظ
// في الملفات أو الطباعة. «آخر ما أعددت» (الساعة في الرأس) على الجهاز فقط. للمالك والمدير (`isAdmin`).
// البناء (`AdminReportComposer`) والرسم خارج الخيط الرئيسي بعد مهلة قصيرة من آخر تغيير.

struct AdminReportBuilderPage: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared

    @State private var parts: Set<AdminReportPart>
    @State private var filter: AdminReportFilter
    @State private var grouping: AdminReportGrouping = .father
    @State private var periodOn = false
    @State private var missingOn = false
    @State private var preset: AdminReportKind?
    @State private var moreOpen = false
    @State private var columnsOpen = false
    @State private var branchPickerOpen = false
    @State private var recentOpen = false
    @State private var result: AdminReportResult?
    @State private var generating = false
    @State private var failed = false
    @State private var showPreview = false
    @State private var women: [FamilyMember]? = WomenStore.cache.isEmpty ? nil : WomenStore.cache
    @State private var familyTree: AdminFamilyTree = .empty
    @State private var planCache: (key: String, plan: AdminReportGroupPlan)?
    @AppStorage(AdminReportFieldsStore.key) private var fieldsRaw = ""
    @AppStorage(AdminReportRecentStore.key) private var recentRaw = ""

    init(scope: AdminReportScope? = nil) {
        var f = AdminReportFilter()
        if let scope { f.scope = .init(ids: scope.ids, title: scope.title) }
        f.grouping = .father
        _filter = State(initialValue: f)
        _parts = State(initialValue: scope == nil ? [.numbers, .names] : [.names])
    }

    // MARK: - Body

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let allowed = authVM.isAdmin
        return AdminPage(header: header,
                         lead: AnyView(!allowed ? AnyView(notAllowedCard)
                                       : loaded ? AnyView(presetsCard) : AnyView(membersStateCard)),
                         content: AnyView(allowed && loaded ? AnyView(questions) : AnyView(Color.clear.frame(height: 0))))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if allowed && loaded { AnyView(bottomBar) }
            }
            .task(id: genKey) { await regenerate() }
            .task(id: treeKey) { familyTree = AdminFamilyTree(memberVM.allMembers) }
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                await accounts.refresh()
                if women == nil, let fetched = try? await WomenStore.fetch() { women = fetched }
            }
            .modifier(AdminBranchPickerBox(isPresented: $branchPickerOpen, members: memberVM.allMembers,
                                           selected: filter.branch, onSelect: { filter.branch = $0 }))
            .dsCenterBox(isPresented: $columnsOpen) { AnyView(columnsBox) }
            .confirmationDialog(L10n.t("آخر ما أعددت", "Made recently"), isPresented: $recentOpen, titleVisibility: .visible) {
                ForEach(recentEntries) { e in
                    Button(e.title) { applyRecent(e) }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                AdminLazyPage { [result] in
                    AnyView(Group {
                        if let result {
                            AdminReportPreviewPage(result: result, onDone: recordRecent)
                                .adminBackTitle(L10n.t("التقارير", "Reports"))
                        }
                    })
                }
            }
    }

    private var header: AdminPageHeader {
        var h = AdminPageHeader(title: L10n.t("التقارير", "Reports"),
                                subtitle: L10n.t("ثلاث أسئلة ← ملف بهوية العائلة جاهز للمشاركة",
                                                 "Three questions → a family-branded file ready to share"),
                                glyph: "doc.text.fill")
        if !recentEntries.isEmpty {
            h.actions = [AdminPageAction(symbol: "clock", label: L10n.t("آخر ما أعددت", "Made recently"),
                                         tap: .action { recentOpen = true })]
        }
        return h
    }

    private var questions: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            AnyView(whatCard)
            AnyView(whoCard)
            AnyView(orderCard)
        }
    }

    // MARK: - المفاتيح

    private var treeKey: String { "\(memberVM.membersVersion)-\(memberVM.allMembers.count)" }
    private var userKey: String { authVM.currentUser?.id.uuidString.lowercased() ?? "-" }
    private var columnsKey: String { "\(userKey)|builder" }

    /// أعمدة الأسماء المحفوظة لهذا المستخدم (بترتيبها) — وإلا الافتراضية
    private var columns: [AdminReportField] {
        let saved = AdminReportFieldsStore.fields(fieldsRaw, key: columnsKey)?
            .filter { AdminReportNameColumns.allowed.contains($0) }
        return saved ?? AdminReportNameColumns.defaults
    }

    private struct GenKey: Equatable {
        let parts: Set<AdminReportPart>
        let filter: AdminReportFilter
        let grouping: AdminReportGrouping
        let columns: [AdminReportField]
        let periodOn: Bool
        let missingOn: Bool
        let preset: AdminReportKind?
        let members: Int
        let version: Int
        let accounts: Int
        let accountsLoaded: Bool
        let women: Int?
        let names: [String: String]?
        let allowed: Bool
    }

    private var genKey: GenKey {
        GenKey(parts: parts, filter: filter, grouping: grouping, columns: columns, periodOn: periodOn, missingOn: missingOn,
               preset: preset, members: memberVM.allMembers.count, version: memberVM.membersVersion,
               accounts: accounts.accounts.count, accountsLoaded: accounts.loaded, women: women?.count,
               names: appSettingsVM.settings.branchNames, allowed: authVM.isAdmin)
    }

    // MARK: - الإنشاء

    private func groupPlan() -> AdminReportGroupPlan {
        let key = "\(grouping.rawValue)|\(filter.branch?.uuidString ?? "-")|\(treeKey)|\(appSettingsVM.settings.branchNames?.count ?? 0)"
        if let c = planCache, c.key == key { return c.plan }
        let tree = familyTree.byId.isEmpty ? AdminFamilyTree(memberVM.allMembers) : familyTree
        let names = appSettingsVM
        let plan = AdminReportGroupPlan.make(grouping, members: memberVM.allMembers, tree: tree,
                                             root: filter.branch, names: { names.branchName(for: $0) })
        planCache = (key, plan)
        return plan
    }

    private func regenerate() async {
        guard authVM.isAdmin, !memberVM.allMembers.isEmpty, !parts.isEmpty else { return }
        if result != nil {
            try? await Task.sleep(nanoseconds: AdminReportsLayout.debounce)
            guard !Task.isCancelled else { return }
        }
        generating = true
        failed = false
        let names = appSettingsVM
        let input = AdminReportInput.make(
            members: memberVM.allMembers,
            women: women ?? (WomenStore.cache.isEmpty ? nil : WomenStore.cache),
            registered: accounts.loaded ? Set(accounts.accounts.keys) : nil,
            branchName: { names.branchName(for: $0) },
            generatedBy: authVM.currentUser?.displayFullName ?? "")
        var f = filter
        f.grouping = grouping
        let request = AdminReportComposeRequest(parts: Array(parts), filter: f, columns: columns, plan: groupPlan(),
                                                periodOn: periodOn, missingOn: missingOn,
                                                presetTitle: preset.map { AdminReportKindUI.title($0) })
        let flag = AdminReportCancelFlag()
        let job = Task.detached(priority: .userInitiated) { () -> AdminReportResult? in
            let doc = AdminReportComposer.build(request, input: input)
            if flag.isCancelled { return nil }
            return try? AdminReportJob.render(doc, thumbnails: 1, flag: flag)
        }
        let out = await withTaskCancellationHandler { await job.value } onCancel: { flag.cancel() }
        guard !Task.isCancelled else { return }
        generating = false
        if let out {
            if let old = result?.url, old != out.url { try? FileManager.default.removeItem(at: old) }
            result = out
        } else {
            failed = true
        }
    }

    // MARK: - «جاهزة بضغطة»

    private var presetsCard: some View {
        AdminSectionCard(title: L10n.t("جاهزة بضغطة", "Ready in one tap")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(AdminReportPreset.all) { p in
                        Button { apply(p) } label: {
                            AdminChoiceChip(title: AdminReportKindUI.title(p.kind), icon: AdminReportKindUI.icon(p.kind),
                                            isSelected: preset == p.kind)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
                        .accessibilityHint(AdminReportKindUI.blurb(p.kind))
                    }
                }
                .padding(.horizontal, DS.Border.width)
            }
        }
    }

    private func apply(_ p: AdminReportPreset) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) {
            preset = p.kind
            parts = Set(p.parts)
            filter.life = p.life
            filter.registration = p.registration
            grouping = p.grouping
            periodOn = p.periodOn
            missingOn = p.missingOn
            if p.periodOn || p.missingOn { moreOpen = true }
        }
    }

    // MARK: - ١ «شنو تبي تطبع؟»

    private var whatCard: some View {
        AdminReportQuestionCard(number: 1, title: L10n.t("شنو تبي تطبع؟", "What to print?"),
                                tag: L10n.t("واحد أو أكثر", "One or more")) {
            AnyView(VStack(alignment: .leading, spacing: DS.Spacing.md) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: AdminReportsLayout.partTile), spacing: DS.Spacing.sm)],
                          spacing: DS.Spacing.sm) {
                    ForEach(AdminReportPart.allCases) { part in
                        AdminReportPartTile(part: part, selected: parts.contains(part)) { toggle(part) }
                    }
                }
                AdminReportHint(icon: "doc.on.doc",
                                text: L10n.t("اختر شيئين ← ملف واحد بفهرس، وكل جزء يبدأ صفحة",
                                             "Pick two → one file with an index, each part starts a page"))
            })
        }
    }

    private func toggle(_ part: AdminReportPart) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) {
            if parts.contains(part) {
                guard parts.count > 1 else { return }
                parts.remove(part)
            } else {
                parts.insert(part)
            }
            preset = nil
        }
    }

    // MARK: - ٢ «عن مين؟»

    private var whoCard: some View {
        AdminReportQuestionCard(number: 2, title: L10n.t("عن مين؟", "About whom?"), tag: nil) {
            AnyView(VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let s = filter.scope {
                    DSChipButton(s.title, icon: "xmark.circle.fill", tint: DS.Color.palm, isSelected: true) {
                        filter.scope = nil
                    }
                    .accessibilityHint(L10n.t("يزيل تصفية صفحة الأعضاء", "Removes the members-page filter"))
                }
                branchRow
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        menuChip(lifeTitle(filter.life), selected: filter.life != .all) {
                            Picker("", selection: $filter.life) {
                                ForEach(AdminReportFilter.Life.allCases, id: \.self) { Text(lifeTitle($0)).tag($0) }
                            }
                        }
                        menuChip(L10n.t("التسجيل: ", "Registration: ") + registrationTitle(filter.registration),
                                 selected: filter.registration != .all) {
                            Picker("", selection: $filter.registration) {
                                ForEach(AdminReportFilter.Registration.allCases, id: \.self) {
                                    Text(registrationTitle($0)).tag($0)
                                }
                            }
                        }
                        menuChip(L10n.t("العمر: ", "Age: ") + (filter.ageLimited ? filter.ageLabel : L10n.t("الكل", "All")),
                                 selected: filter.ageLimited) {
                            ForEach(Self.ageRanges, id: \.label) { r in
                                Button(r.label) {
                                    filter.ageMin = r.min
                                    filter.ageMax = r.max
                                }
                            }
                        }
                    }
                    .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
                    .padding(.horizontal, DS.Border.width)
                }
                Button {
                    withAnimation(DS.Anim.snappy) { moreOpen.toggle() }
                } label: {
                    AdminReportHint(icon: moreOpen ? "minus.circle" : "plus.circle",
                                    text: L10n.t("تصفية أخرى حسب ما تطبعه: الفترة · الناقص · الهواتف",
                                                 "More filters: period · missing · phones"))
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if moreOpen { AnyView(moreFilters) }
            })
        }
    }

    private var branchRow: some View {
        let names = appSettingsVM
        let title = filter.branch.map { familyTree.branchTitle($0, names: { names.branchName(for: $0) }) }
            ?? L10n.t("العائلة كاملة", "The whole family")
        let count = filter.branch.map { familyTree.subtree(of: $0).count } ?? memberVM.allMembers.filter { $0.role != .pending }.count
        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(DS.Color.palm)
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(DS.Color.palm.opacity(DS.Opacity.tintFill)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(verbatim: L10n.t("\(AdminReportText.num(count)) فرداً", "\(count) people"))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: DS.Spacing.sm)
            if filter.branch != nil {
                Button { filter.branch = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.lg, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("العائلة كاملة", "The whole family"))
            }
            Button { branchPickerOpen = true } label: {
                Text(L10n.t("تغيير", "Change"))
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.accent)
                    .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("يفتح قائمة الفروع", "Opens the branch list"))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
    }

    private func menuChip<C: View>(_ title: String, selected: Bool, @ViewBuilder content: () -> C) -> some View {
        Menu {
            content()
        } label: {
            AdminChoiceChip(title: title, isSelected: selected, expands: true)
        }
    }

    private var moreFilters: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    menuChip(L10n.t("الفترة: ", "Period: ") + (periodOn ? periodTitle(filter.period) : L10n.t("الكل", "All")),
                             selected: periodOn) {
                        Button(L10n.t("الكل", "All")) { periodOn = false; preset = nil }
                        ForEach(AdminReportFilter.Period.allCases, id: \.self) { p in
                            Button(periodTitle(p)) { filter.period = p; periodOn = true }
                        }
                    }
                    menuChip(L10n.t("الناقص: ", "Missing: ") + (missingOn ? missingTitle(filter.missing) : L10n.t("الكل", "All")),
                             selected: missingOn) {
                        Button(L10n.t("الكل", "All")) { missingOn = false; preset = nil }
                        ForEach(AdminReportFilter.Missing.allCases, id: \.self) { m in
                            Button(missingTitle(m)) { filter.missing = m; missingOn = true }
                        }
                    }
                    if parts.contains(.phones) {
                        menuChip(L10n.t("الهواتف: ", "Phones: ") + phonesTitle(filter.phones), selected: filter.phones != .all) {
                            Picker("", selection: $filter.phones) {
                                ForEach(AdminReportFilter.Phones.allCases, id: \.self) { Text(phonesTitle($0)).tag($0) }
                            }
                        }
                    }
                    if parts.contains(.memorial) {
                        menuChip(L10n.t("الراحلون: ", "Departed: ") + memorialTitle(filter.memorial),
                                 selected: filter.memorial != .all) {
                            Picker("", selection: $filter.memorial) {
                                ForEach(AdminReportFilter.Memorial.allCases, id: \.self) { Text(memorialTitle($0)).tag($0) }
                            }
                        }
                    }
                }
                .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
                .padding(.horizontal, DS.Border.width)
            }
        }
    }

    // MARK: - ٣ «كيف ترتّبه؟»

    static let groupings: [AdminReportGrouping] = [.father, .branch, .birthDecade, .alphabet, .country]

    static func groupingTitle(_ g: AdminReportGrouping) -> String {
        switch g {
        case .father: return L10n.t("بالبيوت", "By house")
        case .branch: return L10n.t("بالفرع", "By branch")
        case .birthDecade: return L10n.t("بالعمر", "By age")
        case .alphabet: return L10n.t("أبجدياً", "A–Z")
        case .country: return L10n.t("بالدولة", "By country")
        }
    }

    private var orderCard: some View {
        AdminReportQuestionCard(number: 3, title: L10n.t("كيف ترتّبه؟", "How to order it?"), tag: nil) {
            AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(Self.groupings, id: \.self) { g in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                grouping = g
                            } label: {
                                AdminChoiceChip(title: Self.groupingTitle(g), isSelected: grouping == g)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(grouping == g ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
                    .padding(.horizontal, DS.Border.width)
                }
                if parts.contains(.names) {
                    HStack(spacing: DS.Spacing.sm) {
                        AdminReportHint(icon: "list.bullet",
                                        text: L10n.t("الأعمدة: ", "Columns: ")
                                            + ([L10n.t("الاسم", "Name")] + columns.map(Self.columnTitle)).joined(separator: " · "))
                        Spacer(minLength: DS.Spacing.xs)
                        Button { columnsOpen = true } label: {
                            Text(L10n.t("تعديل", "Edit"))
                                .dsFont(.chip)
                                .foregroundColor(DS.Color.accent)
                                .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Icon.tapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            })
        }
    }

    static func columnTitle(_ f: AdminReportField) -> String {
        switch f {
        case .birth: return L10n.t("الميلاد", "Birth")
        case .age: return L10n.t("العمر", "Age")
        case .registration: return L10n.t("التسجيل", "Registration")
        case .death: return L10n.t("الوفاة", "Death")
        default: return AdminReportFilterPage.fieldTitle(f)
        }
    }

    /// مربّع الأعمدة: الاسم دائماً، والباقي يُطبع أو لا (الترتيب ثابت ليتّسع العمودان)
    private var columnsBox: some View {
        DSComposer(title: L10n.t("أعمدة الأسماء", "Name columns"),
                   subtitle: L10n.t("الاسم دائماً — والهاتف مكانه «الهواتف»", "Name always — phones live in «Phones»"),
                   icon: "list.bullet", tint: DS.Color.actionNavy, actionTitle: "", showsAction: false,
                   cancelTitle: L10n.t("تم", "Done"), canSubmit: false, onSubmit: {}, onCancel: { columnsOpen = false }) {
            VStack(spacing: 0) {
                ForEach(AdminReportNameColumns.allowed, id: \.self) { f in
                    let on = columns.contains(f)
                    Button { setColumn(f, on: !on) } label: {
                        HStack {
                            Text(Self.columnTitle(f))
                                .dsFont(.rowTitle)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .dsGlyph(DS.Glyph.lg, weight: .regular)
                                .foregroundColor(on ? DS.Color.primary : DS.Color.textTertiary)
                        }
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func setColumn(_ f: AdminReportField, on: Bool) {
        var chosen = Set(columns)
        if on { chosen.insert(f) } else { chosen.remove(f) }
        let ordered = AdminReportNameColumns.allowed.filter { chosen.contains($0) }
        var dict = AdminReportFieldsStore.decode(fieldsRaw)
        dict[columnsKey] = ordered.map(\.rawValue).joined(separator: ",")
        fieldsRaw = AdminReportFieldsStore.encode(dict)
    }

    // MARK: - الشريط السفلي: العدد والصفحات و«معاينة»

    private var bottomBar: some View {
        HStack(spacing: DS.Spacing.md) {
            if let image = result?.thumbnails.first {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: AdminReportsLayout.barThumb)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: barLine)
                    .dsFont(.rowTitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(failed ? L10n.t("تعذّر إعداد الملف — غيّر اختياراً للمحاولة", "Couldn't prepare the file — change a choice to retry")
                     : L10n.t("يتحدّث مع كل اختيار", "Updates with every choice"))
                    .dsFont(.caption)
                    .foregroundColor(failed ? DS.Color.error : DS.Color.textTertiary)
                    .lineLimit(2)
            }
            .opacity(generating ? 0.55 : 1)
            Spacer(minLength: DS.Spacing.xs)
            DSButton(L10n.t("معاينة", "Preview"), icon: "eye", isLoading: generating && result == nil) {
                showPreview = true
            }
            .fixedSize()
            .disabled(result == nil)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity)
        .background(DS.Color.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.cardBorder).frame(height: DS.Border.width)
        }
    }

    /// «152 فرداً · 6 صفحات»
    private var barLine: String {
        guard let r = result else { return L10n.t("جارٍ إعداد الملف…", "Preparing the file…") }
        return L10n.t("\(AdminReportText.people(r.count)) · \(AdminReportText.pages(r.pages))",
                      "\(r.count) people · \(r.pages) pages")
    }

    // MARK: - «آخر ما أعددت»

    private var recentEntries: [AdminReportRecentStore.Entry] {
        AdminReportRecentStore.entries(recentRaw, user: userKey)
    }

    private func recordRecent() {
        guard let r = result else { return }
        let ordered = AdminReportPart.allCases.filter { parts.contains($0) }
        let kind = preset?.rawValue ?? "parts:" + ordered.map(\.rawValue).joined(separator: ",")
        recentRaw = AdminReportRecentStore.add(.init(kind: kind, title: r.title, date: Date(), pages: r.pages),
                                               raw: recentRaw, user: userKey)
    }

    private func applyRecent(_ e: AdminReportRecentStore.Entry) {
        if let kind = AdminReportKind(rawValue: e.kind), let p = AdminReportPreset.preset(kind) {
            apply(p)
        } else if e.kind.hasPrefix("parts:") {
            let list = e.kind.dropFirst("parts:".count).split(separator: ",").compactMap { AdminReportPart(rawValue: String($0)) }
            if !list.isEmpty {
                parts = Set(list)
                preset = nil
            }
        }
    }

    // MARK: - نصوص الخيارات

    static let ageRanges: [(label: String, min: Int, max: Int)] = [
        (L10n.t("الكل", "All"), 0, AdminReportFilter.ageCap),
        (L10n.t("أقل من 18", "Under 18"), 0, 17),
        ("18–30", 18, 30),
        ("31–50", 31, 50),
        ("51–70", 51, 70),
        (L10n.t("فوق 70", "Over 70"), 71, AdminReportFilter.ageCap)
    ]

    private func lifeTitle(_ v: AdminReportFilter.Life) -> String {
        switch v {
        case .all: return L10n.t("الأحياء والمتوفون", "Living and deceased")
        case .living: return L10n.t("الأحياء", "Living")
        case .deceased: return L10n.t("المتوفون", "Deceased")
        }
    }

    private func registrationTitle(_ v: AdminReportFilter.Registration) -> String {
        switch v {
        case .all: return L10n.t("الكل", "All")
        case .registered: return L10n.t("مسجّلون", "Registered")
        case .treeOnly: return L10n.t("بدون حساب", "In tree")
        case .frozen: return L10n.t("موقوفون", "Suspended")
        }
    }

    private func phonesTitle(_ v: AdminReportFilter.Phones) -> String {
        switch v {
        case .all: return L10n.t("الكل", "All")
        case .registered: return L10n.t("المسجّلون", "Registered")
        case .noPhone: return L10n.t("بلا رقم", "No number")
        }
    }

    private func memorialTitle(_ v: AdminReportFilter.Memorial) -> String {
        switch v {
        case .all: return L10n.t("الكل", "All")
        case .incomplete: return L10n.t("تاريخ غير مكتمل", "Incomplete date")
        }
    }

    private func periodTitle(_ v: AdminReportFilter.Period) -> String {
        switch v {
        case .thisMonth: return L10n.t("هذا الشهر", "This month")
        case .lastMonth: return L10n.t("الشهر الماضي", "Last month")
        case .last90: return L10n.t("آخر 90 يوماً", "Last 90 days")
        }
    }

    private func missingTitle(_ v: AdminReportFilter.Missing) -> String {
        switch v {
        case .any: return L10n.t("أي نقص", "Anything")
        case .birth: return L10n.t("الميلاد", "Birth")
        case .death: return L10n.t("الوفاة", "Death")
        case .photo: return L10n.t("الصورة", "Photo")
        case .father: return L10n.t("الأب", "Father")
        }
    }

    // MARK: - الحالات

    @ViewBuilder
    private var membersStateCard: some View {
        if memberVM.membersLoadFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
        } else {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…")))
        }
    }

    private var notAllowedCard: some View {
        AdminPageStateCard(.empty(L10n.t("التقارير للمالك والمدير", "Reports are for the owner and admins"),
                                  message: L10n.t("تحتوي أرقام هواتف وبيانات الأعضاء", "They include members' phones and data")))
    }
}

// MARK: - أجزاء الصفحة

/// بطاقة سؤال: رقمه في دائرة كحلية، والعنوان، وسطر صغير في الطرف
struct AdminReportQuestionCard: View {
    let number: Int
    let title: String
    let tag: String?
    let content: () -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Text(verbatim: "\(number)")
                    .dsFont(.badge)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: AdminReportsLayout.stepBadge, height: AdminReportsLayout.stepBadge)
                    .background(Circle().fill(DS.Color.primaryFill))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Spacing.sm)
                if let tag {
                    Text(verbatim: tag)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// مربّع جزء: رمزه فوق اسمه، والمختار بإطار كحلي وعلامة ✓ على ركنه
struct AdminReportPartTile: View {
    let part: AdminReportPart
    let selected: Bool
    let action: () -> Void

    static func title(_ p: AdminReportPart) -> String {
        switch p {
        case .names: return L10n.t("الأسماء", "Names")
        case .phones: return L10n.t("الهواتف", "Phones")
        case .tree: return L10n.t("الشجرة", "Tree")
        case .numbers: return L10n.t("الأرقام", "Numbers")
        case .memorial: return L10n.t("الراحلون", "Departed")
        case .calendar: return L10n.t("التقويم", "Calendar")
        case .incomplete: return L10n.t("الناقص", "Missing")
        case .attendance: return L10n.t("الحضور", "Attendance")
        case .form: return L10n.t("الاستمارة", "Form")
        case .cards: return L10n.t("البطاقات", "Cards")
        }
    }

    static func icon(_ p: AdminReportPart) -> String {
        switch p {
        case .names: return "list.bullet"
        case .phones: return "phone"
        case .tree: return "point.3.connected.trianglepath.dotted"
        case .numbers: return "chart.bar"
        case .memorial: return "leaf"
        case .calendar: return "calendar"
        case .incomplete: return "exclamationmark.triangle"
        case .attendance: return "checklist"
        case .form: return "doc.text"
        case .cards: return "person.text.rectangle"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: Self.icon(part))
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textSecondary)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(DS.Color.cardBackgroundSoft))
                    .accessibilityHidden(true)
                Text(verbatim: Self.title(part))
                    .dsFont(.chip)
                    .foregroundColor(selected ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(selected ? DS.Color.primary : DS.Color.cardBorder,
                              lineWidth: selected ? DS.Border.widthBold : DS.Border.width))
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.md, weight: .semibold)
                        .foregroundColor(DS.Color.primary)
                        .background(Circle().fill(DS.Color.surface))
                        .offset(x: -DS.Spacing.xs, y: -DS.Spacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(Self.title(part))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// سطر صغير برمز في أوله
struct AdminReportHint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.sm, weight: .regular)
                .foregroundColor(DS.Color.accent)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - المعاينة ثم المشاركة

/// الصفحات كما ستُطبع: صورة كبيرة للصفحة المختارة وتحتها كل الصفحات، ثم «مشاركة الملف» و«حفظ في الملفات» و«طباعة»
struct AdminReportPreviewPage: View {
    let result: AdminReportResult
    let onDone: () -> Void

    @State private var pages: [UIImage] = []
    @State private var selected = 0
    @State private var viewer: AdminReportViewerItem?
    @State private var showShare = false
    @State private var showExport = false

    var body: some View {
        AdminPage(header: AdminPageHeader(title: L10n.t("المعاينة", "Preview"), subtitle: result.title, glyph: "eye"),
                  lead: AnyView(pageCard),
                  content: AnyView(actionsCard))
            .task { await loadPages() }
            .sheet(item: $viewer) { item in AdminReportViewer(item: item, onShare: onDone) }
            .sheet(isPresented: $showShare) {
                AdminReportShareSheet(items: [result.url]) { showShare = false }
            }
            .sheet(isPresented: $showExport) {
                AdminReportExportPicker(url: result.url) { showExport = false }
            }
    }

    private func loadPages() async {
        let url = result.url
        let images = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return AdminReportJob.thumbnails(data, count: AdminReportsLayout.bookPreviewPages * 3,
                                             width: AdminReportsLayout.previewWidth)
        }.value
        pages = images
    }

    private var pageCard: some View {
        VStack(spacing: DS.Spacing.md) {
            if pages.indices.contains(selected) {
                Button {
                    viewer = AdminReportViewerItem(url: result.url, title: result.title)
                } label: {
                    Image(uiImage: pages[selected])
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(Rectangle().strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
                        .dsSubtleShadow()
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("الصفحة \(selected + 1) — يفتح الملف كاملاً", "Page \(selected + 1) — opens the file"))
            } else {
                DSPageLoader(L10n.t("جارٍ تجهيز الصفحات…", "Preparing pages…"), size: DS.Icon.loaderArtInline, fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xl)
            }
            Text(verbatim: L10n.t("الصفحة \(selected + 1) من \(result.pages)", "Page \(selected + 1) of \(result.pages)"))
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(pages.indices, id: \.self) { i in
                        Button { selected = i } label: {
                            Image(uiImage: pages[i])
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: AdminReportsLayout.stripThumb)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .strokeBorder(i == selected ? DS.Color.primary : DS.Color.cardBorder,
                                                  lineWidth: i == selected ? DS.Border.widthBold : DS.Border.width))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("الصفحة \(i + 1)", "Page \(i + 1)"))
                        .accessibilityAddTraits(i == selected ? .isSelected : [])
                    }
                }
                .padding(DS.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .adminCard()
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "doc.text")
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(DS.Color.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: L10n.t("\(AdminReportText.people(result.count)) · \(AdminReportText.pages(result.pages))",
                                          "\(result.count) people · \(result.pages) pages"))
                        .dsFont(.rowTitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textPrimary)
                    Text(verbatim: result.summary)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            DSActionButton(title: L10n.t("مشاركة الملف", "Share the file"), icon: "square.and.arrow.up") {
                onDone()
                showShare = true
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("حفظ في الملفات", "Save to Files"), icon: "folder", role: .cancel) {
                    onDone()
                    showExport = true
                }
                DSButton(L10n.t("طباعة", "Print"), icon: "printer", role: .cancel) {
                    onDone()
                    let controller = UIPrintInteractionController.shared
                    let info = UIPrintInfo(dictionary: nil)
                    info.outputType = .general
                    info.jobName = result.title
                    controller.printInfo = info
                    controller.printingItem = result.url
                    controller.present(animated: true)
                }
            }
            Text(L10n.t("يُحفظ في «آخر ما أعددت» على جهازك فقط", "Kept in «Made recently» on this device only"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// «حفظ في الملفات» — نسخة من الملف
struct AdminReportExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: () -> Void
        init(_ onComplete: @escaping () -> Void) { self.onComplete = onComplete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onComplete() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onComplete() }
    }
}
