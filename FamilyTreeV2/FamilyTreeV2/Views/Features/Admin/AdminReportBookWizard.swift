import SwiftUI
import UIKit

// MARK: - «كتاب الفرع» بثلاث خطوات (الاتجاه «ج»، طلب المالك ٢٠٢٦-١١-٠٢)
//
// البطاقة البارزة أعلى «التقارير» تفتح هذه الصفحة. ثلاث خطوات بلا تبويبات (كبسولات الخطوات تعيد لما سبق فقط):
//   ١ «لمن؟»: المسار «العائلة ‹ فرع ‹ فرع» والفرع الحالي بعدده ومتوفّيه وفروعه، ثم فروعه للنزول خطوة خطوة،
//     و«العائلة كاملة». الأعداد مرة لكل تغيّر في الأعضاء.
//   ٢ «ماذا؟»: أقسام الكتاب مفاتيح — غلاف · شجرة الفرع المطبوعة · سجل الأفراد · الراحلون وذكراهم · استمارة استكمال
//     البيانات (خانات منقّطة تُعبّأ باليد في الديوانية) · قائمة حضور بلا هواتف · بطاقات الأفراد — والتجميع (بيوت · عقد
//     الميلاد · أبجدياً). الهواتف لا تدخل الكتاب أبداً.
//   ٣ «كيف يبدو؟»: صور الصفحات (الضغط يفتح الملف كاملاً) ثم «مشاركة / حفظ» ملفاً واحداً.
// البناء والرسم خارج الخيط الرئيسي (`AdminReportBuilder.book`)؛ للمالك والمدير فقط كبقية التقارير.

struct AdminReportBookWizard: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    /// الفرع المختار — nil = العائلة كاملة
    @State private var current: UUID?
    @State private var sections: Set<AdminReportBookSection> = AdminReportBookSection.wizardDefault
    @State private var grouping: AdminReportGrouping = .father
    @State private var result: AdminReportResult?
    @State private var generating = false
    @State private var failed = false
    @State private var viewerURL: AdminReportViewerItem?
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    /// شجرة الآباء وأعداد كل فرع — مرة لكل تغيّر في الأعضاء
    @State private var familyTree: AdminFamilyTree = .empty
    @State private var counts: [UUID: Count] = [:]
    @AppStorage(AdminReportRecentStore.key) private var recentRaw = ""

    struct Count: Equatable {
        var total = 0
        var deceased = 0
    }

    private static let groupings: [AdminReportGrouping] = [.father, .birthDecade, .alphabet]

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let allowed = authVM.isAdmin
        return AdminPage(header: header,
                         lead: AnyView(!allowed ? AnyView(notAllowedCard) : AnyView(stepsCard)),
                         content: AnyView(allowed && loaded ? AnyView(stepContent)
                                          : allowed ? AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…"))))
                                          : AnyView(Color.clear.frame(height: 0))))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if allowed && loaded { bottomBar }
            }
            .task(id: treeKey) { rebuildTree() }
            .task(id: bookKey) { await generate() }
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                await accounts.refresh()
            }
            .sheet(item: $viewerURL) { item in AdminReportViewer(item: item, onShare: recordRecent) }
            .sheet(isPresented: $showShare, onDismiss: { shareItems.removeAll() }) {
                AdminReportShareSheet(items: shareItems) { showShare = false }
            }
    }

    private var header: AdminPageHeader {
        AdminPageHeader(title: L10n.t("كتاب الفرع", "Branch book"), subtitle: selectionLine, glyph: AdminReportKindUI.icon(.book))
    }

    // MARK: - الشجرة والأعداد

    private var treeKey: String { "\(memberVM.membersVersion)-\(memberVM.allMembers.count)" }

    private func rebuildTree() {
        let members = memberVM.allMembers.filter { $0.role != .pending && $0.hasName }
        let tree = AdminFamilyTree(members)
        // الأعداد من الأسفل: كل عضو + ذرّيته (ترتيب عكسي لمرور عمق أول)
        var order: [UUID] = []
        var stack = tree.rootId.map { [$0] } ?? []
        var seen: Set<UUID> = []
        while let id = stack.popLast() {
            guard seen.insert(id).inserted else { continue }
            order.append(id)
            stack.append(contentsOf: tree.children[id] ?? [])
        }
        var c: [UUID: Count] = [:]
        for id in order.reversed() {
            var n = Count(total: 1, deceased: tree.byId[id]?.isDeceased == true ? 1 : 0)
            for k in tree.children[id] ?? [] {
                n.total += c[k]?.total ?? 0
                n.deceased += c[k]?.deceased ?? 0
            }
            c[id] = n
        }
        familyTree = tree
        counts = c
    }

    private var focus: UUID? { current ?? familyTree.rootId }

    private func title(_ id: UUID?) -> String {
        guard let id, id != familyTree.rootId else { return L10n.t("العائلة كاملة", "The whole family") }
        let names = appSettingsVM
        return familyTree.branchTitle(id, names: { names.branchName(for: $0) })
    }

    /// «فرع عبدالله كاملاً · 148 فرداً»
    private var selectionLine: String {
        let n = focus.flatMap { counts[$0]?.total } ?? 0
        let base = current == nil ? title(nil) : L10n.t("\(title(current)) كاملاً", "All of \(title(current))")
        return "\(base) · \(L10n.t(AdminReportText.people(n), n == 1 ? "1 person" : "\(n) people"))"
    }

    /// فروع تحت العقدة: أبناء لهم نسل، بترتيب الشجرة
    private func subBranches(of id: UUID?) -> [UUID] {
        guard let id else { return [] }
        return (familyTree.children[id] ?? [])
            .filter { !(familyTree.children[$0] ?? []).isEmpty }
            .sorted(by: familyTree.siblingOrder)
    }

    // MARK: - الخطوات

    private var stepsCard: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<3, id: \.self) { i in
                let done = i < step
                Button {
                    guard done else { return }
                    go(i)
                } label: {
                    HStack(spacing: DS.Spacing.xxs) {
                        Text(done ? "✓" : "\(i + 1)")
                            .dsFont(.badge)
                        Text(AdminReportStepDots.title(i))
                            .dsFont(.chip)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(i == step ? DS.Hub.onGold : done ? DS.Color.textPrimary : DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                    .background(Capsule().fill(i == step ? DS.Color.accentLight : DS.Color.cardBackgroundSoft))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!done)
                .accessibilityLabel(L10n.t("الخطوة \(i + 1): \(AdminReportStepDots.title(i))",
                                           "Step \(i + 1): \(AdminReportStepDots.title(i))"))
                .accessibilityValue(i == step ? L10n.t("الحالية", "Current") : done ? L10n.t("منجزة", "Done") : "")
                .accessibilityHint(done ? L10n.t("يرجع لهذه الخطوة", "Goes back to this step") : "")
            }
        }
        .adminCard()
    }

    private func go(_ s: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { step = s }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: AnyView(whoCard)
        case 1: AnyView(whatCard)
        default: AnyView(previewCard)
        }
    }

    // MARK: - ١ «لمن؟»

    private var whoCard: some View {
        let path = breadcrumb
        let subs = subBranches(of: focus)
        let c = focus.flatMap { counts[$0] } ?? Count()
        return VStack(spacing: DS.Hub.stackSpacing) {
            AdminSectionCard(title: L10n.t("لمن؟", "For whom?"), spacing: DS.Spacing.md) {
                AdminReportBreadcrumb(path: path, onPick: { id in
                    UISelectionFeedbackGenerator().selectionChanged()
                    current = id
                })
                Text(L10n.t("انزل إلى أي فرع، أو اطبع هذا الفرع كاملاً", "Go down to any branch, or print this one whole"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                selectedRow(c, branches: subs.count)
            }
            if !subs.isEmpty {
                AdminSectionCard(title: L10n.t("فروعه", "Its branches"), tag: AdminReportText.num(subs.count)) {
                    AdminRowsCardBody {
                        ForEach(subs, id: \.self) { id in
                            branchRow(id)
                        }
                    }
                }
            }
            if current != nil {
                AdminSectionCard {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        current = nil
                    } label: {
                        AdminChoiceChip(title: L10n.t("أو: العائلة كاملة", "Or: the whole family"), icon: "person.3.fill",
                                        isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var breadcrumb: [(id: UUID?, title: String)] {
        var out: [(id: UUID?, title: String)] = [(nil, L10n.t("العائلة", "Family"))]
        guard let b = current else { return out }
        for id in (familyTree.chain(to: b) ?? []) + [b] { out.append((id, title(id))) }
        return out
    }

    private func selectedRow(_ c: Count, branches: Int) -> some View {
        let line = [L10n.t(AdminReportText.people(c.total), "\(c.total) people"),
                    branches > 0 ? L10n.t("\(AdminReportText.branches(branches)) تحته", "\(branches) branches below") : nil,
                    c.deceased > 0 ? L10n.t("\(AdminReportText.num(c.deceased)) متوفى", "\(c.deceased) deceased") : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: "checkmark")
                .dsGlyph(DS.Glyph.md, weight: .bold)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Hub.iconSquare, height: DS.Hub.iconSquare)
                .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous).fill(DS.Color.palmFill))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(current == nil ? title(nil) : L10n.t("\(title(current)) كاملاً", "All of \(title(current))"))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                Text(verbatim: line)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
    }

    private func branchRow(_ id: UUID) -> some View {
        let name = title(id)
        let n = counts[id]?.total ?? 0
        let letter = familyTree.byId[id]?.firstName.first.map(String.init) ?? ""
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            current = id
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Text(verbatim: letter)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.palm)
                    .frame(width: DS.Hub.iconSquare, height: DS.Hub.iconSquare)
                    .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                        .fill(DS.Color.palm.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: name)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t(AdminReportText.people(n), n == 1 ? "1 person" : "\(n) people"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("ينزل إلى هذا الفرع", "Goes down into this branch"))
    }

    // MARK: - ٢ «ماذا؟»

    private var whatCard: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            AdminSectionCard(title: L10n.t("أقسام الكتاب", "Book sections"), tag: L10n.t("\(sections.count) من 7", "\(sections.count) of 7")) {
                AdminRowsCardBody {
                    ForEach(AdminReportBookSection.wizard) { s in
                        sectionRow(s)
                    }
                }
            }
            if sections.contains(.register) || sections.contains(.form) || sections.contains(.attendance) {
                AdminSectionCard(title: L10n.t("التجميع داخل الكتاب", "Grouping inside the book")) {
                    AdminChoiceRow {
                        ForEach(Self.groupings) { g in
                            Button {
                                guard g != grouping else { return }
                                UISelectionFeedbackGenerator().selectionChanged()
                                grouping = g
                            } label: {
                                AdminChoiceChip(title: g == .father ? L10n.t("بيوت (الأب وأبناؤه)", "Households")
                                                                    : AdminReportFilterPage.groupingTitle(g),
                                                isSelected: g == grouping)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(g == grouping ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
            DSNoteCard(L10n.t("الهواتف لا تدخل الكتاب — مكانها «دليل الهواتف» وحده.",
                              "Phones never go into the book — only in the phone directory."),
                       icon: "lock.fill")
        }
    }

    private static func sectionTitle(_ s: AdminReportBookSection) -> String {
        switch s {
        case .cover: return L10n.t("غلاف", "Cover")
        case .tree: return L10n.t("شجرة الفرع المطبوعة", "Printed branch tree")
        case .register: return L10n.t("سجل الأفراد", "Register")
        case .memorial: return L10n.t("الراحلون وذكراهم", "The departed")
        case .form: return L10n.t("استمارة استكمال البيانات", "Data completion form")
        case .attendance: return L10n.t("قائمة حضور بلا هواتف", "Attendance list (no phones)")
        case .cards: return L10n.t("بطاقات الأفراد", "Member cards")
        case .numbers: return L10n.t("الأعداد", "Numbers")
        }
    }

    private static func sectionBlurb(_ s: AdminReportBookSection) -> String {
        switch s {
        case .cover: return L10n.t("كريمي بإطار ذهبي وفهرس بالأقسام", "Cream with a gold frame and contents")
        case .tree: return L10n.t("الفرع مرسوماً بخطوط ذهبية ومفتاح للقراءة", "The branch drawn in gold with a key")
        case .register: return L10n.t("كل بيت بشريطه ومجموعه", "Each household with its total")
        case .memorial: return L10n.t("التواريخ والذكرى القادمة", "Dates and the next anniversary")
        case .form: return L10n.t("خانات منقّطة تُعبّأ باليد في الديوانية", "Dotted blanks filled by hand at the diwaniya")
        case .attendance: return L10n.t("الأسماء بالبيوت وخانة حضور", "Names by household with a tick box")
        case .cards: return L10n.t("بطاقة لكل فرد: الاسم والنسب والميلاد", "A card each: name, lineage, birth")
        case .numbers: return ""
        }
    }

    private static func sectionIcon(_ s: AdminReportBookSection) -> String {
        switch s {
        case .cover: return "book.closed.fill"
        case .tree: return "point.3.connected.trianglepath.dotted"
        case .register: return "list.bullet.indent"
        case .memorial: return "leaf.fill"
        case .form: return "square.and.pencil"
        case .attendance: return "checklist"
        case .cards: return "person.text.rectangle.fill"
        case .numbers: return "number"
        }
    }

    private func sectionRow(_ s: AdminReportBookSection) -> some View {
        let on = Binding(get: { sections.contains(s) }, set: { v in
            UISelectionFeedbackGenerator().selectionChanged()
            if v { sections.insert(s) } else { sections.remove(s) }
        })
        return Toggle(isOn: on) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: Self.sectionIcon(s))
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.Hub.iconSquare, height: DS.Hub.iconSquare)
                    .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                        .fill(on.wrappedValue ? DS.Color.navyFill : DS.Color.slateFill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(Self.sectionTitle(s))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(Self.sectionBlurb(s))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(DS.Color.primary)
        .frame(minHeight: DS.Icon.tapTarget)
        .padding(.vertical, DS.Spacing.xxs)
    }

    // MARK: - ٣ «كيف يبدو؟»

    private var previewCard: some View {
        AdminSectionCard(title: L10n.t("كيف يبدو؟", "How it looks"), tag: result == nil ? nil : "PDF · A4") {
            if let result, !generating {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text(verbatim: result.summary)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    AdminReportThumbs(result: result, limit: AdminReportsLayout.bookPreviewPages) {
                        viewerURL = AdminReportViewerItem(url: result.url, title: result.title)
                    }
                    Text(L10n.t("اضغط على صفحة لعرض الكتاب كاملاً", "Tap a page to view the whole book"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            } else if failed {
                DSEmptyView(L10n.t("تعذّر إنشاء الكتاب", "Couldn't create the book"),
                            message: L10n.t("حاول مرة أخرى", "Try again"),
                            actionTitle: L10n.t("إعادة المحاولة", "Retry"), actionIcon: "arrow.clockwise",
                            style: .compact, action: { Task { await generate() } })
            } else {
                DSPageLoader(L10n.t("جارٍ إعداد الكتاب…", "Preparing the book…"), size: DS.Icon.loaderArtInline, fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.lg)
            }
        }
    }

    private struct BookKey: Equatable {
        let step: Int
        let current: UUID?
        let sections: Set<AdminReportBookSection>
        let grouping: AdminReportGrouping
        let tree: String
        let accounts: Int
        let names: [String: String]?
    }

    private var bookKey: BookKey {
        // يُبنى في الخطوة الثالثة فقط
        BookKey(step: step == 2 ? 2 : 0, current: current, sections: sections, grouping: grouping, tree: treeKey,
                accounts: accounts.accounts.count, names: appSettingsVM.settings.branchNames)
    }

    private func generate() async {
        guard step == 2, authVM.isAdmin, !memberVM.allMembers.isEmpty, !sections.isEmpty else { return }
        generating = true
        failed = false
        let names = appSettingsVM
        let input = AdminReportInput.make(
            members: memberVM.allMembers, women: nil,
            registered: accounts.loaded ? Set(accounts.accounts.keys) : nil,
            branchName: { names.branchName(for: $0) },
            generatedBy: authVM.currentUser?.displayFullName ?? "")
        let tree = familyTree.byId.isEmpty ? AdminFamilyTree(memberVM.allMembers) : familyTree
        let plan = AdminReportGroupPlan.make(grouping, members: memberVM.allMembers, tree: tree, root: current,
                                             names: { names.branchName(for: $0) })
        var filter = AdminReportFilter()
        filter.branch = current
        filter.grouping = grouping
        let request = AdminReportRequest(kind: .book, filter: filter, fields: [.name, .birth, .age, .status], plan: plan,
                                         book: sections)
        let flag = AdminReportCancelFlag()
        let thumbs = AdminReportsLayout.bookPreviewPages
        let job = Task.detached(priority: .userInitiated) { () -> AdminReportResult? in
            let doc = AdminReportJob.build(request, input: input)
            if flag.isCancelled { return nil }
            return try? AdminReportJob.render(doc, thumbnails: thumbs, flag: flag)
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

    // MARK: - الشريط السفلي

    private var bottomBar: some View {
        let ready = result != nil && !generating
        let title: String
        let icon: String
        switch step {
        case 0:
            title = L10n.t("التالي: ماذا تطبع؟", "Next: what to print?")
            icon = L10n.isArabic ? "arrow.left" : "arrow.right"
        case 1:
            title = L10n.t("التالي: كيف يبدو؟", "Next: how it looks")
            icon = L10n.isArabic ? "arrow.left" : "arrow.right"
        default:
            let pages = result.map { L10n.t(" · \(AdminReportText.pages($0.pages))", " · \($0.pages) pages") } ?? ""
            title = L10n.t("مشاركة / حفظ", "Share / Save") + (ready ? pages : "")
            icon = "square.and.arrow.up"
        }
        let enabled = step == 0 || (step == 1 && !sections.isEmpty) || (step == 2 && ready)
        return DSActionButton(title: title, icon: icon, isBusy: step == 2 && generating, enabled: enabled) {
            if step < 2 { go(step + 1) } else { share() }
        }
        .dsSubtleShadow()
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [DS.Hub.background.opacity(0), DS.Hub.background],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func share() {
        guard let url = result?.url else { return }
        recordRecent()
        shareItems = [url]
        showShare = true
    }

    private func recordRecent() {
        guard let r = result else { return }
        let user = authVM.currentUser?.id.uuidString.lowercased() ?? "-"
        recentRaw = AdminReportRecentStore.add(.init(kind: AdminReportKind.book.rawValue, title: r.title, date: Date(),
                                                     pages: r.pages), raw: recentRaw, user: user)
    }

    private var notAllowedCard: some View {
        AdminPageStateCard(.empty(L10n.t("التقارير للمالك والمدير", "Reports are for the owner and admins"),
                                  message: L10n.t("تحتوي بيانات الأعضاء", "They include members' data")))
    }
}
