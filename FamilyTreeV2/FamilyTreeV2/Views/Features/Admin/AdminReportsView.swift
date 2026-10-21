import SwiftUI
import UIKit
import PDFKit

// MARK: - تقارير العائلة (PDF) — «رسمي بهوية العائلة» (طلب المالك ٢٠٢٦-١٠-٢٠)
//
// بيتها الواحد «العائلة ← زر التقارير» (والصفّ نفسه في البحث الشامل) — للمالك والمدير (`isAdmin`) كما كان التصدير.
// من الأعلى: رأس كحلي ← بطاقة «التقرير»: صفّ واحد من أربع «صفحات» صغيرة (طلب المالك «ابسط و اصغر و شي مبدع»:
// ورقة بطرف مطويّ وشريط كحلي بسدو ذهبي ورمز النوع، وتحتها اسم قصير — العنوان الكامل في سطر المعاينة؛ بلا تبويبات علوية)
// وتحتها سطر شرائح واحد قصير يخص النوع
// («نطوّر فلاتر التقارير بشكل مبسط»): سجل العائلة «كل الفروع ⌄» + «كل الأعمار ⌄» (قائمة الفئات — «اذا بس بالاعمار؟»)
// + الكل · أحياء · متوفون — الهواتف الكل · مسجّلون · بلا رقم هاتف — المتوفون الكل · التاريخ غير مكتمل — الملخّص بلا
// تصفية. الافتراضي تقرير مفيد بلا أي ضغطة.
// وتحته سطر «البيانات:» (طلب المالك «اضيف البيانات او اشيل البيانات بشكل بسيط و مرتب بدون اي تعقيد»): شرائح صغيرة
// بما يُطبع — أعمدة الجداول، أو أقسام الملخّص — الممتلئة ✓ تُطبع والمحدّدة + لا، والضغط يبدّلها؛ الاسم (والرقم في
// الهواتف) مقفل. الافتراضي = أعمدة التقرير السابقة، والاختيار يُحفظ لكل نوع ولكل مستخدم (`AdminReportFieldsStore`)،
// و«الافتراضي» آخر السطر متى تغيّر. الملف يتكيّف (`AdminReportPDF.plan`): الأعمدة المختارة فقط والاسم يأخذ ما بقي.
// ← «المعاينة»: سطر النطاق («سجل العائلة · كل الفروع · أحياء — 2,344 فرداً») وصورة الغلاف وحدها بشارة «14 صفحة»
// (الضغط يفتح الملف كاملاً — طلب المالك «خل بس وحدة وانا ادش عليها») ← زرّ «مشاركة / حفظ» عائم مثبّت فوق شريط
// التبويبات (ورقة المشاركة) — بلا شريط زجاجي عريض ولا عدد صفحات بجانبه.
// الملف يُنشأ تلقائياً عند تغيّر النوع أو التصفية (بعد مهلة قصيرة، والإنشاء السابق يُلغى) خارج الخيط الرئيسي —
// البناء والرسم في `AdminReportsModel.swift` / `AdminReportsPDF.swift`.
// «زر التقارير» من صفحة الأعضاء بالشريحة والبحث الحاليين = سجل العائلة بنفس الأعضاء (شريحة تُزال بـ ✕).

/// ما يُصدَّر من صفحة الأعضاء: أعضاء الشريحة المختارة (والبحث) وعنوانها — «زر التقارير» بالفلتر الحالي
struct AdminReportScope {
    let ids: Set<UUID>
    let title: String
}

/// اختيار «البيانات:» محفوظاً في سلسلة `@AppStorage` واحدة لكل المستخدمين والأنواع:
/// `{"<معرّف المستخدم>|register": "name,birth,age"}` — لا مفتاح = الافتراضي
enum AdminReportFieldsStore {
    static let key = "adminReports.fields"

    static func decode(_ raw: String) -> [String: String] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func encode(_ dict: [String: String]) -> String {
        guard !dict.isEmpty, let data = try? JSONEncoder().encode(dict) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct AdminReportsView: View {
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// أقلّ عرض لخانة الصفحة — يكبر مع حجم النص حتى يتّسع الاسم تحتها
    @ScaledMetric(relativeTo: .footnote) private var tileWidth: CGFloat = AdminReportsLayout.tileWidth

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
    /// «البيانات:» لكل نوع ولكل مستخدم (`AdminReportFieldsStore`)
    @AppStorage(AdminReportFieldsStore.key) private var fieldsRaw = ""

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
        let fields: Set<AdminReportField>
    }

    private var genKey: GenKey {
        GenKey(kind: kind, filter: filter, members: memberVM.allMembers.count, version: memberVM.membersVersion,
               accounts: accounts.accounts.count, accountsLoaded: accounts.loaded, women: women?.count,
               names: appSettingsVM.settings.branchNames, allowed: authVM.isAdmin, fields: fields)
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
        let jobFields = fields
        let flag = AdminReportCancelFlag()
        let job = Task.detached(priority: .userInitiated) {
            try? AdminReportJob.run(jobKind, input: input, filter: jobFilter, fields: jobFields, flag: flag)
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

    // MARK: - بطاقة «التقرير»: النوع + سطر التصفية + «البيانات:»

    private var pickerCard: some View {
        AdminSectionCard(title: L10n.t("التقرير", "Report"), spacing: DS.Spacing.md) {
            typeRow
            AdminRowDivider()
            if kind != .stats { filterRow }
            fieldsRow
        }
        .dsTallBox(isPresented: $branchPickerOpen) {
            BranchPickerSheet(allMembers: memberVM.allMembers, selectedId: filter.branch, onSelect: { id in
                filter.branch = id
                branchPickerOpen = false
            })
        }
    }

    /// صفّ واحد دائماً: يملأ العرض إن اتّسع، وإلا (نص كبير جداً) يُمرَّر أفقياً ويظهر المختار
    private var typeRow: some View {
        ViewThatFits(in: .horizontal) {
            typeTiles(fill: true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    typeTiles(fill: false)
                        .padding(.vertical, DS.Spacing.md)
                        .padding(.horizontal, DS.Spacing.md)
                }
                // حشوة التمرير تتّسع لظلّ المختار (ScrollView يقصّ ما خرج عنه) دون أن تكبر المسافات
                .padding(.vertical, -DS.Spacing.md)
                .padding(.horizontal, -DS.Spacing.md)
                .onAppear { proxy.scrollTo(kind, anchor: .center) }
            }
        }
    }

    private func typeTiles(fill: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            ForEach(AdminReportKind.allCases) { k in
                AdminReportTypeCard(kind: k, selected: k == kind) { select(k) }
                    .frame(minWidth: tileWidth, maxWidth: fill ? .infinity : nil)
                    .id(k)
            }
        }
        // مكان لرفعة المختار
        .padding(.vertical, DS.Spacing.xs)
    }

    private func select(_ k: AdminReportKind) {
        guard k != kind else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { kind = k }
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
        ageChip
        choice(L10n.t("الكل", "All"), filter.life == .all) { filter.life = .all }
        choice(L10n.t("أحياء", "Living"), filter.life == .living) { filter.life = .living }
        choice(L10n.t("متوفون", "Deceased"), filter.life == .deceased) { filter.life = .deceased }
    }

    /// «كل الأعمار ⌄» — قائمة أصلية بالفئات (والمختارة بعلامة)، بشكل شريحة الفرع نفسه
    private var ageChip: some View {
        Menu {
            Picker(selection: Binding(get: { filter.age }, set: { value in
                guard value != filter.age else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                filter.age = value
            })) {
                ForEach(AdminReportFilter.Age.allCases, id: \.self) { age in
                    Text(Self.ageTitle(age)).tag(age)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            AdminReportMenuChip(title: Self.ageTitle(filter.age), tint: DS.Color.palm, selected: filter.age != .all)
        }
        .accessibilityLabel(L10n.t("العمر: \(Self.ageTitle(filter.age))", "Age: \(Self.ageTitle(filter.age))"))
    }

    static func ageTitle(_ age: AdminReportFilter.Age) -> String {
        switch age {
        case .all: return L10n.t("كل الأعمار", "All ages")
        case .under18: return L10n.t("أقل من 18", "Under 18")
        case .from18to30: return "18–30"
        case .from31to50: return "31–50"
        case .from51to70: return "51–70"
        case .over70: return L10n.t("فوق 70", "Over 70")
        case .unknown: return L10n.t("غير معروف", "Unknown")
        }
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

    // MARK: - «البيانات:» ما يُطبع في التقرير

    /// مفتاح الحفظ: المستخدم + النوع
    private var fieldsKey: String {
        "\(authVM.currentUser?.id.uuidString.lowercased() ?? "-")|\(kind.rawValue)"
    }

    /// المحفوظ لهذا النوع — nil = الافتراضي
    private var savedFields: Set<AdminReportField>? {
        AdminReportFieldsStore.decode(fieldsRaw)[fieldsKey].map { raw in
            Set(raw.split(separator: ",").compactMap { AdminReportField(rawValue: String($0)) })
        }
    }

    /// ما يُطبع الآن (المقفل دائماً)
    private var fields: Set<AdminReportField> { kind.resolvedFields(savedFields) }

    /// يحفظ الاختيار — الافتراضي (أو nil) يُمسح فيرجع الحفظ كما كان
    private func saveFields(_ chosen: Set<AdminReportField>?) {
        var all = AdminReportFieldsStore.decode(fieldsRaw)
        let resolved = kind.resolvedFields(chosen)
        if chosen != nil, resolved != kind.resolvedFields(nil) {
            all[fieldsKey] = kind.fields.filter(resolved.contains).map(\.rawValue).joined(separator: ",")
        } else {
            all[fieldsKey] = nil
        }
        fieldsRaw = AdminReportFieldsStore.encode(all)
    }

    /// سطر واحد: «البيانات:» ثم شريحة لكل بيان (✓ يُطبع · + لا يُطبع · قفل دائماً) تُمرَّر أفقياً إن ضاق،
    /// و«الافتراضي» ثابت آخر السطر متى تغيّر شيء (لا يختفي خلف التمرير)
    private var fieldsRow: some View {
        let current = fields
        let changed = current != kind.resolvedFields(nil)
        return HStack(spacing: DS.Spacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xsm) {
                    Text(L10n.t("البيانات:", "Data:"))
                        .dsFont(.chipCompact)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize()
                    ForEach(kind.fields) { f in
                        fieldChip(f, on: current.contains(f), locked: kind.lockedFields.contains(f), current: current)
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
            if changed {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? nil : DS.Anim.snappy) { saveFields(nil) }
                } label: {
                    Text(L10n.t("الافتراضي", "Default"))
                        .dsFont(.chipCompact)
                        .foregroundColor(DS.Color.primary)
                        .fixedSize()
                        .frame(minHeight: DSBox.chipHeightSmall)
                        .dsTapArea(width: DS.Icon.tapTarget, height: DSBox.chipHeightSmall)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("إرجاع البيانات الافتراضية", "Restore the default data"))
                .transition(.opacity)
            }
        }
    }

    private func fieldChip(_ f: AdminReportField, on: Bool, locked: Bool, current: Set<AdminReportField>) -> some View {
        let title = Self.fieldTitle(f, kind: kind)
        return DSChipButton(title, icon: locked ? "lock.fill" : on ? "checkmark" : "plus", tint: kindTint,
                            isSelected: on, size: .small) {
            guard !locked else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            var next = current
            if on { next.remove(f) } else { next.insert(f) }
            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { saveFields(next) }
        }
        .accessibilityLabel(title)
        .accessibilityValue(on ? L10n.t("في التقرير", "In the report") : L10n.t("ليس في التقرير", "Not in the report"))
        .accessibilityHint(locked ? L10n.t("دائماً في التقرير", "Always in the report")
                           : on ? L10n.t("يزيله من التقرير", "Removes it from the report")
                           : L10n.t("يضيفه للتقرير", "Adds it to the report"))
    }

    static func fieldTitle(_ f: AdminReportField, kind: AdminReportKind) -> String {
        switch f {
        case .name: return kind == .register ? L10n.t("الاسم الكامل", "Full name") : L10n.t("الاسم", "Name")
        case .branch: return L10n.t("الفرع", "Branch")
        case .birth: return L10n.t("الميلاد", "Birth")
        case .age: return L10n.t("العمر", "Age")
        case .status: return L10n.t("الحالة", "Status")
        case .death: return L10n.t("تاريخ الوفاة", "Death date")
        case .phone: return L10n.t("الهاتف", "Phone")
        case .registration: return L10n.t("التسجيل في التطبيق", "App registration")
        case .anniversary: return L10n.t("الذكرى القادمة", "Next anniversary")
        case .ageAtDeath: return L10n.t("العمر عند الوفاة", "Age at death")
        case .people: return L10n.t("إحصاء الأفراد", "Head count")
        case .ages: return L10n.t("الأعمار", "Ages")
        case .branches: return L10n.t("الفروع", "Branches")
        case .registered: return L10n.t("المسجّلون", "Registered")
        }
    }

    // MARK: - المعاينة

    private var previewCard: some View {
        AdminSectionCard(title: L10n.t("المعاينة", "Preview"), tag: result == nil ? nil : "PDF · A4") {
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

            // صفحة واحدة: الغلاف وعليه عدد الصفحات — الضغط يفتح الملف كاملاً
            if let cover = r.thumbnails.first {
                thumbnail(cover, pages: r.pages, url: r.url)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xs)
            }

            Text(L10n.t("اضغط على الصفحة لعرض الملف كاملاً", "Tap the page to view the whole file"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $viewerURL) { item in
            AdminReportViewer(item: item)
        }
    }

    private func thumbnail(_ image: UIImage, pages: Int, url: URL) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
        return Button {
            viewerURL = AdminReportViewerItem(url: url, title: AdminReportTypeCard.title(kind))
        } label: {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: AdminReportsLayout.thumbWidth)
                .clipShape(shape)
                .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
                // شارة عدد الصفحات في الزاوية العليا عند نهاية سطر القراءة (فوق بياض الغلاف، بعيداً عن الشعار والختم)
                .overlay(alignment: .topTrailing) {
                    Text(L10n.t(AdminReportText.pages(pages), pages == 1 ? "1 page" : "\(pages) pages"))
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(Capsule().fill(DS.Color.brandFill))
                        .padding(DS.Spacing.sm)
                }
                .dsSubtleShadow()
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(L10n.t("\(AdminReportText.pages(pages)) — عرض الملف", "\(pages) pages — view file"))
    }

    // MARK: - المشاركة

    /// زرّ واحد عائم فوق شريط التبويبات وبعرضه تقريباً — بلا شريط زجاجي عريض (كان يبدو شريطاً ثانياً فوق
    /// شريط التبويبات بفجوة بينهما، وبجانبه «ملف PDF · 4 صفحات» مكرّراً). تدرّج قصير من لون الصفحة خلفه.
    private var shareBar: some View {
        DSActionButton(title: L10n.t("مشاركة / حفظ", "Share / Save"),
                       icon: "square.and.arrow.up",
                       isBusy: generating && result?.kind != kind,
                       enabled: result?.kind == kind && !generating) {
            share()
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
    /// عرض صورة الغلاف في المعاينة
    static let thumbWidth: CGFloat = 150

    // «صفحة» نوع التقرير في الصفّ الواحد
    /// أقلّ عرض لخانة النوع عند حجم النص الافتراضي (يكبر مع النص)
    static let tileWidth: CGFloat = 64
    /// الورقة الصغيرة (قريبة من نسبة A4)
    static let pageSize = CGSize(width: 54, height: 70)
    /// زوايا الورقة
    static let pageRadius: CGFloat = 5
    /// الطرف المطويّ (أعلى الطرف الآخر من بداية القراءة)
    static let pageFold: CGFloat = 12
    /// الشريط الكحلي أعلى الورقة (مثل شريط صفحات الملف)
    static let pageBand: CGFloat = 13
    /// رفعة المختار
    static let liftScale: CGFloat = 1.05
}

// MARK: - شريحة قائمة (Menu) بشكل `DSChipButton`

/// تسمية `Menu` بنفس شكل الشريحة (زرّ داخل تسمية القائمة يبتلع الضغطة) — المختار ممتلئ بلونه ونصّه أبيض
private struct AdminReportMenuChip: View {
    let title: String
    let tint: Color
    let selected: Bool
    @Environment(\.dsSection) private var section

    var body: some View {
        let ink = tint.dsChrome(in: section).dsReadableGlyph
        HStack(spacing: DS.Spacing.xsm) {
            Image(dsSymbol: "chevron.down").dsGlyph(DS.Glyph.sm)
            Text(title)
                .dsFont(.chip)
                .lineLimit(1)
                .monospacedDigit()
        }
        .foregroundColor(selected ? .white : ink)
        .padding(.horizontal, DSBox.chipPadding)
        .frame(minHeight: DSBox.chipHeight)
        .background {
            if selected {
                Capsule().fill(tint.dsChromeFill(in: section).dsSolidFill)
            } else {
                Capsule().fill(ink.opacity(DS.Opacity.tintFill))
            }
        }
        .overlay(Capsule().strokeBorder(selected ? Color.clear : ink.opacity(DS.Opacity.tintStroke),
                                        lineWidth: DS.Border.width))
        .dsTapArea(width: DS.Icon.tapTarget, height: DSBox.chipHeight)
    }
}

// MARK: - «صفحة» نوع التقرير

/// ورقة صغيرة بطرف مطويّ وشريط كحلي بسدو ذهبي ورمز النوع، وتحتها اسم قصير.
/// المختارة ترتفع قليلاً بظلّ ناعم وإطار ذهبي و«تمتلئ» بلون النوع من الأسفل؛ غيرها هادئة مسطّحة.
/// مع «تقليل الحركة»: بلا رفعة ولا نابض — يتبدّل اللون والإطار مباشرة.
struct AdminReportTypeCard: View {
    let kind: AdminReportKind
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// الاسم القصير تحت الورقة — العنوان الكامل في سطر المعاينة
    static func shortTitle(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return L10n.t("السجل", "Register")
        case .stats: return L10n.t("الملخّص", "Summary")
        case .memorial: return L10n.t("المتوفون", "Deceased")
        case .phones: return L10n.t("الهواتف", "Phones")
        }
    }

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
        Button(action: action) {
            VStack(spacing: DS.Spacing.xsm) {
                page
                Text(Self.shortTitle(kind))
                    .dsFont(.chipCompact)
                    .foregroundColor(selected ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.title(kind))، \(Self.blurb(kind))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var page: some View {
        let size = AdminReportsLayout.pageSize
        let band = AdminReportsLayout.pageBand
        let shape = AdminReportPageShape(fold: AdminReportsLayout.pageFold, radius: AdminReportsLayout.pageRadius)
        let ink = Self.tint(kind).dsReadableGlyph
        let lifted = selected && !reduceMotion
        return ZStack {
            // «تمتلئ» الورقة بلون النوع من الأسفل
            shape.fill(DS.Color.surfaceElevated)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ink.opacity(DS.Opacity.tintFillStrong))
                        .frame(height: selected ? size.height - band : 0)
                }
                .clipShape(shape)
            AdminReportPageArt()
            shape.stroke(selected ? DS.Color.accentLight : DS.Color.textTertiary.opacity(DS.Opacity.tintStroke),
                         lineWidth: selected ? DS.Border.widthBold : DS.Border.width)
        }
        .frame(width: size.width, height: size.height)
        // الطرف المطويّ عند نهاية سطر القراءة (يسار في العربي)
        .flipsForRightToLeftLayoutDirection(true)
        .overlay(
            Image(systemName: Self.icon(kind))
                .dsGlyph(DS.Glyph.xl, weight: .semibold)
                .foregroundColor(ink)
                .padding(.top, band)
        )
        .shadow(color: selected ? DS.Shadow.glow.color : .clear,
                radius: DS.Shadow.glow.radius, x: DS.Shadow.glow.x, y: DS.Shadow.glow.y)
        .scaleEffect(lifted ? AdminReportsLayout.liftScale : 1)
        .animation(reduceMotion ? nil : DS.Anim.bouncy, value: selected)
    }
}

/// الورقة: مستطيل مدوّر زاويته العليا اليمنى (قبل قلب العربي) مقصوصة قطرياً للطرف المطويّ
struct AdminReportPageShape: Shape {
    let fold: CGFloat
    let radius: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius)
        p.closeSubpath()
        return p
    }
}

/// رسم الورقة: الشريط الكحلي (كحلي العلامة — يبان في الداكن) وخطّه الذهبي وسدو صغير (خطّان وخمسة معيّنات، الأوسط أكبر — شكل سدو الملف نفسه)
/// والطرف المطويّ فوقه. رسم ثابت بلا حركة، مخفي عن القارئ الصوتي.
private struct AdminReportPageArt: View {
    var body: some View {
        Canvas { ctx, size in
            let fold = AdminReportsLayout.pageFold
            let band = AdminReportsLayout.pageBand
            let rect = CGRect(origin: .zero, size: size)
            let page = AdminReportPageShape(fold: fold, radius: AdminReportsLayout.pageRadius).path(in: rect)
            let gold = DS.Color.accentLight

            var inside = ctx
            inside.clip(to: page)
            inside.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: band)), with: .color(DS.Color.brandFill))
            inside.fill(Path(CGRect(x: 0, y: band, width: size.width, height: 0.8)), with: .color(gold))

            // السدو في وسط الجزء الظاهر من الشريط
            let unit: CGFloat = 1.7
            let diamonds: [CGFloat] = [unit, unit, unit * 1.5, unit, unit]
            let gap = unit * 1.15
            let width = diamonds.reduce(0, +) + gap * 4
            let cx = (size.width - fold) / 2
            let cy = band / 2
            var x = cx - width / 2
            for (i, d) in diamonds.enumerated() {
                let c = CGPoint(x: x + d / 2, y: cy)
                let r = d / 2 * 1.2
                var dp = Path()
                dp.move(to: CGPoint(x: c.x, y: c.y - r))
                dp.addLine(to: CGPoint(x: c.x + r, y: c.y))
                dp.addLine(to: CGPoint(x: c.x, y: c.y + r))
                dp.addLine(to: CGPoint(x: c.x - r, y: c.y))
                dp.closeSubpath()
                inside.fill(dp, with: .color(gold.opacity(i == 2 ? 1 : 0.75)))
                x += d + gap
            }
            let lineGap = unit * 1.6
            let lineLength: CGFloat = 5
            let line = Path(CGRect(x: cx - width / 2 - lineGap - lineLength, y: cy - 0.3, width: lineLength, height: 0.6))
            inside.fill(line, with: .color(gold.opacity(0.6)))
            inside.fill(Path(CGRect(x: cx + width / 2 + lineGap, y: cy - 0.3, width: lineLength, height: 0.6)),
                        with: .color(gold.opacity(0.6)))

            // الطرف المطويّ: مثلث بلون ظهر الورقة فوق زاوية الشريط
            var flap = Path()
            flap.move(to: CGPoint(x: size.width - fold, y: 0))
            flap.addLine(to: CGPoint(x: size.width - fold, y: fold))
            flap.addLine(to: CGPoint(x: size.width, y: fold))
            flap.closeSubpath()
            ctx.fill(flap, with: .color(DS.Color.cardBorder))
            ctx.stroke(flap, with: .color(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke)), lineWidth: 0.6)
        }
        .accessibilityHidden(true)
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
