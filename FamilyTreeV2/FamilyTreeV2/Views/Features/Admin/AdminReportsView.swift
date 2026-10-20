import SwiftUI
import UIKit
import PDFKit

// MARK: - تقارير العائلة (PDF) — «رسمي بهوية العائلة» (طلب المالك ٢٠٢٦-١٠-٢٠)
//
// بيتها الواحد «العائلة ← ⋯ ← تصدير» (والصفّ نفسه في البحث الشامل) — للمالك والمدير (`isAdmin`) كما كان التصدير.
// من الأعلى: رأس كحلي ← بطاقة «التقرير»: أربع بطاقات نوع (بلا تبويبات علوية) وتحتها سطر شرائح واحد قصير يخص النوع
// («نطوّر فلاتر التقارير بشكل مبسط»): سجل العائلة «كل الفروع ⌄» + الكل · أحياء · متوفون — الهواتف الكل · مسجّلون ·
// بلا رقم هاتف — المتوفون الكل · التاريخ غير مكتمل — الملخّص بلا تصفية. الافتراضي تقرير مفيد بلا أي ضغطة.
// ← «المعاينة»: سطر النطاق («سجل العائلة · كل الفروع · أحياء — 2,344 فرداً») وصور أول الصفحات (الضغط يفتح الملف
// كاملاً) ← شريط سفلي ثابت «مشاركة / حفظ» (ورقة المشاركة).
// الملف يُنشأ تلقائياً عند تغيّر النوع أو التصفية (بعد مهلة قصيرة، والإنشاء السابق يُلغى) خارج الخيط الرئيسي —
// البناء والرسم في `AdminReportsModel.swift` / `AdminReportsPDF.swift`.
// «⋯ ← تصدير» من صفحة الأعضاء بالشريحة والبحث الحاليين = سجل العائلة بنفس الأعضاء (شريحة تُزال بـ ✕).

/// ما يُصدَّر من صفحة الأعضاء: أعضاء الشريحة المختارة (والبحث) وعنوانها — «⋯ ← تصدير» بالفلتر الحالي
struct AdminReportScope {
    let ids: Set<UUID>
    let title: String
}

struct AdminReportsView: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    /// nil = كل العائلة، وإلا ما صُدّر من صفحة الأعضاء
    private let scope: AdminReportScope?

    @State private var kind: AdminReportKind = .register
    @State private var filter: AdminReportFilter
    @State private var result: AdminReportResult?
    @State private var generating = false
    @State private var failed = false
    @State private var women: [FamilyMember]? = WomenStore.cache.isEmpty ? nil : WomenStore.cache
    @State private var branchPickerOpen = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var viewerURL: AdminReportViewerItem?

    /// `kind`: التقرير المفتوح أولاً (الافتراضي سجل العائلة)
    init(scope: AdminReportScope? = nil, kind: AdminReportKind = .register) {
        self.scope = scope
        _kind = State(initialValue: scope == nil ? kind : .register)
        var f = AdminReportFilter()
        if let scope { f.scope = .init(ids: scope.ids, title: scope.title) }
        _filter = State(initialValue: f)
    }

    // MARK: - Body

    var body: some View {
        let loaded = !memberVM.allMembers.isEmpty
        let allowed = authVM.isAdmin
        return AdminPage(header: header,
                         lead: AnyView(!allowed ? AnyView(notAllowedCard)
                                       : loaded ? AnyView(pickerCard) : AnyView(membersStateCard)),
                         content: AnyView(allowed && loaded ? AnyView(previewCard) : AnyView(Color.clear.frame(height: 0))))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if allowed && loaded { shareBar }
            }
            .task(id: genKey) { await regenerate() }
            .task {
                if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
                await accounts.refresh()
                if women == nil, let fetched = try? await WomenStore.fetch() { women = fetched }
            }
            .sheet(isPresented: $showShare, onDismiss: { shareItems.removeAll() }) {
                AdminReportShareSheet(items: shareItems) { showShare = false }
            }
    }

    private var header: AdminPageHeader {
        AdminPageHeader(
            title: L10n.t("تصدير قائمة الأعضاء (PDF)", "Export member list (PDF)"),
            subtitle: L10n.t("أربعة تقارير رسمية بهوية العائلة — اختر التقرير ثم شاركه أو احفظه",
                             "Four official family reports — pick one, then share or save it"),
            glyph: "doc.text.fill")
    }

    // MARK: - إنشاء الملف

    /// ما يُعاد الإنشاء عند تغيّره: النوع والتصفية والبيانات (الأعضاء، الحسابات، شجرة النساء، أسماء الفروع)
    private struct GenKey: Equatable {
        let kind: AdminReportKind
        let filter: AdminReportFilter
        let members: Int
        let version: Int
        let accounts: Int
        let accountsLoaded: Bool
        let women: Int?
        let names: [String: String]?
        let allowed: Bool
    }

    private var genKey: GenKey {
        GenKey(kind: kind, filter: filter, members: memberVM.allMembers.count, version: memberVM.membersVersion,
               accounts: accounts.accounts.count, accountsLoaded: accounts.loaded, women: women?.count,
               names: appSettingsVM.settings.branchNames, allowed: authVM.isAdmin)
    }

    private func regenerate() async {
        guard authVM.isAdmin, !memberVM.allMembers.isEmpty else { return }
        // مهلة قصيرة: ضغطات متتالية على الشرائح تُنشئ ملفاً واحداً
        if result != nil {
            try? await Task.sleep(nanoseconds: 300_000_000)
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
        let jobKind = self.kind
        var current = self.filter
        if jobKind != .register { current.scope = nil }
        let jobFilter = current
        let flag = AdminReportCancelFlag()
        let job = Task.detached(priority: .userInitiated) {
            try? AdminReportJob.run(jobKind, input: input, filter: jobFilter, flag: flag)
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

    // MARK: - بطاقة «التقرير»: النوع + سطر التصفية

    private var pickerCard: some View {
        AdminSectionCard(title: L10n.t("التقرير", "Report"), spacing: DS.Spacing.md) {
            typeGrid
            if kind != .stats {
                AdminRowDivider()
                filterRow
            }
        }
        .dsTallBox(isPresented: $branchPickerOpen) {
            BranchPickerSheet(allMembers: memberVM.allMembers, selectedId: filter.branch, onSelect: { id in
                filter.branch = id
                branchPickerOpen = false
            })
        }
    }

    private var typeGrid: some View {
        let cols = typeSize.isAccessibilitySize ? 1 : 2
        let kinds = AdminReportKind.allCases
        return VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(stride(from: 0, to: kinds.count, by: cols)), id: \.self) { start in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(kinds[start..<min(start + cols, kinds.count)]) { k in
                        AdminReportTypeCard(kind: k, selected: k == kind) { select(k) }
                    }
                }
            }
        }
    }

    private func select(_ k: AdminReportKind) {
        guard k != kind else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) { kind = k }
    }

    /// سطر واحد قصير يخص النوع — يُمرَّر أفقياً إن ضاق
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xsm) {
                switch kind {
                case .register: registerChips
                case .phones:
                    choice(L10n.t("الكل", "All"), filter.phones == .all) { filter.phones = .all }
                    choice(L10n.t("مسجّلون", "Registered"), filter.phones == .registered) { filter.phones = .registered }
                    choice(L10n.t("بلا رقم هاتف", "No phone"), filter.phones == .noPhone) { filter.phones = .noPhone }
                case .memorial:
                    choice(L10n.t("الكل", "All"), filter.memorial == .all) { filter.memorial = .all }
                    choice(L10n.t("التاريخ غير مكتمل", "Incomplete date"), filter.memorial == .incomplete) {
                        filter.memorial = .incomplete
                    }
                case .stats: EmptyView()
                }
            }
            .padding(.vertical, DS.Spacing.xxs)
        }
    }

    @ViewBuilder
    private var registerChips: some View {
        if let s = filter.scope {
            // من صفحة الأعضاء — ✕ يرجع لكل العائلة
            DSChipButton(s.title, icon: "xmark.circle.fill", tint: DS.Color.palm, isSelected: true) {
                filter.scope = nil
            }
            .accessibilityHint(L10n.t("يزيل تصفية صفحة الأعضاء", "Removes the members-page filter"))
        }
        DSChipButton(branchChipTitle, icon: "chevron.down", tint: DS.Color.palm, isSelected: filter.branch != nil) {
            branchPickerOpen = true
        }
        if filter.branch != nil {
            Button {
                filter.branch = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -DS.Spacing.sm)
            .accessibilityLabel(L10n.t("كل الفروع", "All branches"))
        }
        choice(L10n.t("الكل", "All"), filter.life == .all) { filter.life = .all }
        choice(L10n.t("أحياء", "Living"), filter.life == .living) { filter.life = .living }
        choice(L10n.t("متوفون", "Deceased"), filter.life == .deceased) { filter.life = .deceased }
    }

    private var branchChipTitle: String {
        guard let id = filter.branch else { return L10n.t("كل الفروع", "All branches") }
        if let name = appSettingsVM.branchName(for: id) { return name }
        let first = memberVM.allMembers.first { $0.id == id }?.firstName ?? ""
        return L10n.t("فرع \(first)", "\(first) branch")
    }

    private func choice(_ title: String, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
        DSChipButton(title, tint: kindTint, isSelected: selected) {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }
    }

    private var kindTint: Color { AdminReportTypeCard.tint(kind) }

    // MARK: - المعاينة

    private var previewCard: some View {
        AdminSectionCard(title: L10n.t("المعاينة", "Preview"),
                         tag: result.map { L10n.t("\(AdminReportText.pages($0.pages)) · A4", "\($0.pages) pages · A4") }) {
            if let result, result.kind == kind {
                AnyView(previewBody(result))
            } else if failed {
                AnyView(DSEmptyView(L10n.t("تعذّر إنشاء التقرير", "Couldn't create the report"),
                                    message: L10n.t("حاول مرة أخرى", "Try again"),
                                    actionTitle: L10n.t("إعادة المحاولة", "Retry"), actionIcon: "arrow.clockwise",
                                    style: .compact, action: { Task { await regenerate() } }))
            } else {
                AnyView(DSPageLoader(L10n.t("جارٍ إعداد التقرير…", "Preparing the report…"),
                                     size: DS.Icon.loaderArtInline, fillsSpace: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.lg))
            }
        }
    }

    private func previewBody(_ r: AdminReportResult) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Image(systemName: "doc.richtext.fill")
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(kindTint)
                    .accessibilityHidden(true)
                Text(r.summary)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if generating {
                    ProgressView().scaleEffect(DS.Spinner.chipScale)
                }
            }
            .opacity(generating ? 0.55 : 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    ForEach(Array(r.thumbnails.enumerated()), id: \.offset) { i, image in
                        thumbnail(image, page: i + 1, total: r.pages, url: r.url)
                    }
                }
                .padding(.vertical, DS.Spacing.xs)
                .padding(.horizontal, DS.Border.width)
            }

            Text(L10n.t("اضغط على صفحة لعرض الملف كاملاً", "Tap a page to view the whole file"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $viewerURL) { item in
            AdminReportViewer(item: item)
        }
    }

    private func thumbnail(_ image: UIImage, page: Int, total: Int, url: URL) -> some View {
        Button {
            viewerURL = AdminReportViewerItem(url: url, title: AdminReportTypeCard.title(kind))
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: AdminReportsLayout.thumbWidth)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
                    .dsSubtleShadow()
                Text(L10n.t("صفحة \(page) من \(total)", "Page \(page) of \(total)"))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("صفحة \(page) من \(total) — عرض الملف", "Page \(page) of \(total) — view file"))
    }

    // MARK: - المشاركة

    private var shareBar: some View {
        HStack(spacing: DS.Spacing.md) {
            DSActionButton(title: L10n.t("مشاركة / حفظ", "Share / Save"),
                           icon: "square.and.arrow.up",
                           isBusy: generating && result?.kind != kind,
                           enabled: result?.kind == kind && !generating) {
                share()
            }
            if let r = result, r.kind == kind {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.t("ملف PDF", "PDF file"))
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.fieldValue)
                    Text(L10n.t(AdminReportText.pages(r.pages), "\(r.pages) pages"))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.fieldLabel)
                        .monospacedDigit()
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsGlass(Rectangle())
        .overlay(Divider(), alignment: .top)
    }

    private func share() {
        guard let url = result?.url else { return }
        shareItems = [url]
        showShare = true
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

// MARK: - مقاسات الصفحة (مكان واحد)

enum AdminReportsLayout {
    /// عرض صورة الصفحة في المعاينة
    static let thumbWidth: CGFloat = 132
}

// MARK: - بطاقة نوع التقرير

struct AdminReportTypeCard: View {
    let kind: AdminReportKind
    let selected: Bool
    let action: () -> Void

    static func title(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return L10n.t("سجل العائلة بالفروع", "Family register by branch")
        case .stats: return L10n.t("ملخّص إحصائي للعائلة", "Family statistics")
        case .memorial: return L10n.t("المتوفون وذكراهم", "The deceased & anniversaries")
        case .phones: return L10n.t("دليل الهواتف", "Phone directory")
        }
    }

    static func blurb(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return L10n.t("كل فرع برأسه وأفراده بترتيب الشجرة", "Each branch with its members in tree order")
        case .stats: return L10n.t("أعداد ورسوم في صفحة أو صفحتين", "Counts and charts on a page or two")
        case .memorial: return L10n.t("تواريخ الوفاة وموعد الذكرى القادمة", "Death dates and the next anniversary")
        case .phones: return L10n.t("أرقام الأحياء بالفروع — المخفي لا يُطبع", "Living members' numbers — hidden ones aren't printed")
        }
    }

    static func icon(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return "list.bullet.indent"
        case .stats: return "chart.pie.fill"
        case .memorial: return "leaf.fill"
        case .phones: return "phone.fill"
        }
    }

    /// ألوان المعنى في اللوحة: الشجرة والأعضاء أخضر، الإحصاء ذهبي، المتوفون رصاصي، التواصل بترولي
    static func tint(_ kind: AdminReportKind) -> Color {
        switch kind {
        case .register: return DS.Color.palm
        case .stats: return DS.Color.accent
        case .memorial: return DS.Color.deceased
        case .phones: return DS.Color.sea
        }
    }

    var body: some View {
        let tint = Self.tint(kind)
        let shape = RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top) {
                    AdminIconSquare(symbol: Self.icon(kind), tint: tint, filled: selected, glyph: DS.Glyph.lg)
                    Spacer(minLength: DS.Spacing.xs)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .dsGlyph(DS.Glyph.xl, weight: .semibold)
                        .foregroundColor(selected ? tint.dsReadableGlyph : DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(Self.title(kind))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.blurb(kind))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: DS.Hub.tileMinHeight, alignment: .topLeading)
            .background(shape.fill(selected ? tint.dsReadableGlyph.opacity(DS.Opacity.tintFill) : DS.Color.background))
            .overlay(shape.strokeBorder(selected ? tint.dsReadableGlyph.opacity(DS.Opacity.selectedStroke)
                                                 : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                        lineWidth: selected ? DS.Border.widthBold : DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.title(kind))، \(Self.blurb(kind))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - عرض الملف كاملاً (PDFKit)

struct AdminReportViewerItem: Identifiable {
    let url: URL
    let title: String
    var id: URL { url }
}

struct AdminReportViewer: View {
    let item: AdminReportViewerItem
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            DSSubPageHeader(title: item.title, subtitle: L10n.t("معاينة الملف", "File preview"),
                            section: .admin, nav: .close)
            AdminReportPDFView(url: item.url)
                .ignoresSafeArea(edges: .bottom)
            HStack {
                DSActionButton(title: L10n.t("مشاركة / حفظ", "Share / Save"), icon: "square.and.arrow.up") {
                    showShare = true
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .dsGlass(Rectangle())
        }
        .background(DS.Color.background.ignoresSafeArea())
        .sheet(isPresented: $showShare) {
            AdminReportShareSheet(items: [item.url]) { showShare = false }
        }
    }
}

private struct AdminReportPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor.secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

// MARK: - ورقة المشاركة

private struct AdminReportShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
