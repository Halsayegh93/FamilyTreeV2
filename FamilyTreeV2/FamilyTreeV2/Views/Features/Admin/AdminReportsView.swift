import SwiftUI
import UIKit
import PDFKit

// MARK: - «التقارير» — مكتبة التقارير الرسمية + «كتاب الفرع» (طلب المالك ٢٠٢٦-١١-٠٢: مزيج الاتجاهين «أ» و«ج»)
//
// بيتها الواحد «العائلة ← زر التقارير» (والصفّ نفسه في البحث الشامل) — للمالك والمدير (`isAdmin`) كما كان التصدير.
// من الأعلى: رأس كحلي ← بطاقة «كتاب الفرع» البارزة (ثلاث خطوات: لمن؟ ← ماذا؟ ← كيف يبدو؟ — `AdminReportBookWizard`)
// ← «أعددتها مؤخراً» (محفوظة على الجهاز لكل مستخدم — `AdminReportRecentStore`) ← رفّ التقارير بأقسام صغيرة:
// العائلة · التواصل · الذكرى · البيانات، صفّ لكل تقرير (رمزه، اسمه، سطره، «جديد») يفتح صفحة تصفيته
// (`AdminReportFilterPage`). بلا تبويبات علوية ولا مبدّلات.
// «زر التقارير» من صفحة الأعضاء بالشريحة والبحث الحاليين (`AdminReportsView(scope:)`) يفتح مباشرة صفحة تصفية «سجل
// العائلة» بنفس الأعضاء (شريحة تُزال بـ ✕).
// TODO(تقارير مجدولة): «أرسل لي هذا التقرير كل شهر» يحتاج سيرفر وموافقة المالك — غير مبني.

/// ما يُصدَّر من صفحة الأعضاء: أعضاء الشريحة المختارة (والبحث) وعنوانها — «زر التقارير» بالفلتر الحالي
struct AdminReportScope {
    let ids: Set<UUID>
    let title: String
}

/// الأعمدة المختارة بترتيبها محفوظة في سلسلة `@AppStorage` واحدة لكل المستخدمين والأنواع:
/// `{"<معرّف المستخدم>|register": "name,birth,age"}` — الترتيب هو ترتيب الأعمدة؛ لا مفتاح = الافتراضي
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

    static func fields(_ raw: String, key: String) -> [AdminReportField]? {
        decode(raw)[key].map { $0.split(separator: ",").compactMap { AdminReportField(rawValue: String($0)) } }
    }
}

/// «أعددتها مؤخراً»: آخر ما شُورك أو حُفظ — على الجهاز فقط، لكل مستخدم (`{"<معرّف>": [مدخل…]}`)
enum AdminReportRecentStore {
    static let key = "adminReports.recent"
    static let limit = 6

    struct Entry: Codable, Hashable, Identifiable {
        let kind: String
        let title: String
        let date: Date
        let pages: Int
        var id: String { "\(kind)|\(title)" }
    }

    static func entries(_ raw: String, user: String) -> [Entry] {
        decode(raw)[user] ?? []
    }

    static func add(_ entry: Entry, raw: String, user: String) -> String {
        var all = decode(raw)
        var list = (all[user] ?? []).filter { $0.id != entry.id }
        list.insert(entry, at: 0)
        all[user] = Array(list.prefix(limit))
        guard let data = try? JSONEncoder().encode(all) else { return raw }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode(_ raw: String) -> [String: [Entry]] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: [Entry]].self, from: data) else { return [:] }
        return dict
    }
}

// MARK: - أسماء التقارير ورموزها (الواجهة)

enum AdminReportKindUI {
    static func title(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return L10n.t("سجل العائلة", "Family register")
        case .tree: return L10n.t("شجرة فرع مطبوعة", "Printed branch tree")
        case .branchReport: return L10n.t("تقرير فرع شامل", "Full branch report")
        case .phones: return L10n.t("دليل الهواتف", "Phone directory")
        case .registered: return L10n.t("المسجّلون في التطبيق", "Registered in the app")
        case .memorial: return L10n.t("سجل الراحلين", "The departed")
        case .calendar: return L10n.t("تقويم الذكرى", "Anniversary calendar")
        case .stats: return L10n.t("الملخّص", "Summary")
        case .newThisMonth: return L10n.t("المقيّدون هذا الشهر", "Added this month")
        case .incomplete: return L10n.t("الناقصة بياناتهم", "Missing data")
        case .book: return L10n.t("كتاب الفرع", "Branch book")
        }
    }

    static func blurb(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return L10n.t("بالفروع وبترتيب الشجرة — الأعمدة تختارها", "By branch in tree order — your columns")
        case .tree: return L10n.t("رسم الفرع على صفحة أو أكثر", "The branch drawn on one page or more")
        case .branchReport: return L10n.t("غلاف + أرقام + شجرة + سجل + ذكرى", "Cover, numbers, tree, register, memorial")
        case .phones: return L10n.t("أرقام الأحياء — المخفي لا يُطبع", "Living members' numbers — hidden ones aren't printed")
        case .registered: return L10n.t("مسجّل · مقيّد · موقوف بنسبة لكل فرع", "Registered · listed · suspended per branch")
        case .memorial: return L10n.t("التواريخ والذكرى القادمة", "Dates and the next anniversary")
        case .calendar: return L10n.t("صفحة لكل شهر بمن تحلّ ذكراهم", "A page per month with its anniversaries")
        case .stats: return L10n.t("أعداد ورسوم في صفحة أو صفحتين", "Counts and charts on a page or two")
        case .newThisMonth: return L10n.t("من أُضيف للشجرة في فترة تختارها", "Who was added to the tree in a period")
        case .incomplete: return L10n.t("ما ينقص كل فرد: ميلاد، وفاة، صورة، أب", "What each person lacks: birth, death, photo, father")
        case .book: return L10n.t("لمن؟ ← ماذا؟ ← كيف يبدو؟", "Who? → What? → How it looks")
        }
    }

    static func icon(_ kind: AdminReportKind) -> String {
        switch kind {
        case .register: return "list.bullet.indent"
        case .tree: return "point.3.connected.trianglepath.dotted"
        case .branchReport: return "book.closed.fill"
        case .phones: return "phone.fill"
        case .registered: return "checkmark.seal.fill"
        case .memorial: return "leaf.fill"
        case .calendar: return "calendar"
        case .stats: return "chart.pie.fill"
        case .newThisMonth: return "person.badge.plus"
        case .incomplete: return "exclamationmark.triangle.fill"
        case .book: return "books.vertical.fill"
        }
    }

    /// ألوان المعنى في اللوحة: الشجرة والأعضاء أخضر، التواصل بترولي، الذكرى رصاصي، البيانات ذهبي
    static func tint(_ kind: AdminReportKind) -> Color {
        switch kind.shelf {
        case .family: return kind == .branchReport ? DS.Color.primary : DS.Color.palm
        case .contact: return DS.Color.sea
        case .memory: return DS.Color.deceased
        case .data: return DS.Color.accent
        }
    }

    static func shelfTitle(_ shelf: AdminReportKind.Shelf) -> String {
        switch shelf {
        case .family: return L10n.t("العائلة", "Family")
        case .contact: return L10n.t("التواصل", "Contact")
        case .memory: return L10n.t("الذكرى", "Remembrance")
        case .data: return L10n.t("البيانات", "Data")
        }
    }

    static func page(_ kind: AdminReportKind) -> AnyView {
        kind == .book ? AnyView(AdminReportBookWizard()) : AnyView(AdminReportFilterPage(kind: kind))
    }
}

// MARK: - الصفحة

struct AdminReportsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    /// nil = المكتبة، وإلا ما صُدّر من صفحة الأعضاء (يفتح «سجل العائلة» مباشرة)
    private let scope: AdminReportScope?
    @AppStorage(AdminReportRecentStore.key) private var recentRaw = ""

    init(scope: AdminReportScope? = nil) {
        self.scope = scope
    }

    var body: some View {
        if let scope {
            AdminReportFilterPage(kind: .register, scope: scope)
        } else {
            library
        }
    }

    private var library: some View {
        let allowed = authVM.isAdmin
        return AdminPage(header: header,
                         lead: AnyView(allowed ? AnyView(AdminReportBookCard()) : AnyView(notAllowedCard)),
                         content: AnyView(allowed ? AnyView(shelves) : AnyView(Color.clear.frame(height: 0))))
    }

    private var header: AdminPageHeader {
        let n = AdminReportKind.library.count
        return AdminPageHeader(
            title: L10n.t("التقارير", "Reports"),
            subtitle: L10n.t("\(n) \((3...10).contains(n) ? "تقارير" : "تقريراً") بهوية العائلة · PDF مقاس A4",
                             "\(n) family reports · A4 PDF"),
            glyph: "doc.text.fill")
    }

    private var userKey: String { authVM.currentUser?.id.uuidString.lowercased() ?? "-" }

    private var shelves: some View {
        let recent = AdminReportRecentStore.entries(recentRaw, user: userKey)
        return VStack(spacing: DS.Hub.stackSpacing) {
            if !recent.isEmpty { AnyView(AdminReportRecentCard(entries: recent)) }
            ForEach(AdminReportKind.Shelf.allCases, id: \.self) { shelf in
                AnyView(AdminReportShelfCard(shelf: shelf))
            }
        }
    }

    private var notAllowedCard: some View {
        AdminPageStateCard(.empty(L10n.t("التقارير للمالك والمدير", "Reports are for the owner and admins"),
                                  message: L10n.t("تحتوي أرقام هواتف وبيانات الأعضاء", "They include members' phones and data")))
    }
}

// MARK: - بطاقة «كتاب الفرع» البارزة

private struct AdminReportBookCard: View {
    var body: some View {
        AdminTapWrap(tap: .page { AdminReportKindUI.page(.book) }, feel: .press, label: AnyView(face),
                     accessibilityLabel: L10n.t("كتاب الفرع، ثلاث خطوات: لمن، ماذا، كيف يبدو. يفتح المعالج",
                                                "Branch book, three steps: who, what, how it looks. Opens the wizard"))
    }

    private var face: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Image(systemName: AdminReportKindUI.icon(.book))
                .dsGlyph(DS.Glyph.xl, weight: .semibold)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Hub.iconSquare + DS.Spacing.md, height: DS.Hub.iconSquare + DS.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                    .fill(DS.Color.goldFill))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("كتاب الفرع", "Branch book"))
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("ثلاث خطوات: لمن؟ ← ماذا؟ ← كيف يبدو؟ — شجرة واستمارة وقائمة حضور في ملف واحد للديوانية",
                            "Three steps: who? → what? → how it looks — tree, form and attendance list in one file"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                AdminReportStepDots(current: 0, done: [])
                    .padding(.top, DS.Spacing.xs)
            }
            Spacer(minLength: 0)
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .dsGlyph(DS.Glyph.sm, weight: .semibold)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
        .overlay(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
            .strokeBorder(DS.Color.accentLight, lineWidth: DS.Border.widthBold))
    }
}

/// خطوات المعالج الثلاث كبسولات صغيرة — الحالية ذهبية، والمنجزة بعلامة
struct AdminReportStepDots: View {
    let current: Int
    let done: Set<Int>

    static func title(_ i: Int) -> String {
        switch i {
        case 0: return L10n.t("لمن؟", "Who?")
        case 1: return L10n.t("ماذا؟", "What?")
        default: return L10n.t("كيف يبدو؟", "How it looks")
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: DS.Spacing.xxs) {
                    Text(done.contains(i) ? "✓" : "\(i + 1)")
                        .dsFont(.badge)
                    Text(Self.title(i))
                        .dsFont(.micro)
                }
                .foregroundColor(i == current ? DS.Hub.onGold : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .background(Capsule().fill(i == current ? DS.Color.accentLight : DS.Color.cardBackgroundSoft))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الخطوة \(current + 1) من 3: \(Self.title(current))",
                                   "Step \(current + 1) of 3: \(Self.title(current))"))
    }
}

// MARK: - «أعددتها مؤخراً»

private struct AdminReportRecentCard: View {
    let entries: [AdminReportRecentStore.Entry]

    var body: some View {
        AdminSectionCard(title: L10n.t("أعددتها مؤخراً", "Made recently")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(entries) { e in
                        if let kind = AdminReportKind(rawValue: e.kind) {
                            AdminTapWrap(tap: .page { AdminReportKindUI.page(kind) }, label: AnyView(chip(e, kind)),
                                         accessibilityLabel: "\(e.title)، \(Self.when(e.date))، \(AdminReportText.pages(e.pages))")
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
        }
    }

    private func chip(_ e: AdminReportRecentStore.Entry, _ kind: AdminReportKind) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: AdminReportKindUI.icon(kind))
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(AdminReportKindUI.tint(kind))
                    .accessibilityHidden(true)
                Text(verbatim: e.title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
            }
            Text(verbatim: "\(Self.when(e.date)) · \(L10n.t(AdminReportText.pages(e.pages), "\(e.pages) pages"))")
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.md)
        .frame(minWidth: AdminReportsLayout.recentWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
    }

    /// «اليوم» · «أمس» · «28 أكتوبر»
    static func when(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.t("اليوم", "Today") }
        if cal.isDateInYesterday(date) { return L10n.t("أمس", "Yesterday") }
        let c = cal.dateComponents([.day, .month], from: date)
        return DeceasedMemorial.dayMonth(day: c.day ?? 1, month: c.month ?? 1, arabic: L10n.isArabic)
    }
}

// MARK: - قسم من الرفّ

private struct AdminReportShelfCard: View {
    let shelf: AdminReportKind.Shelf

    var body: some View {
        AdminSectionCard(title: AdminReportKindUI.shelfTitle(shelf)) {
            AdminRowsCardBody {
                ForEach(AdminReportKind.library.filter { $0.shelf == shelf }) { kind in
                    AdminTapRow(icon: AdminReportKindUI.icon(kind), tint: AdminReportKindUI.tint(kind),
                                title: AdminReportKindUI.title(kind), subtitle: AdminReportKindUI.blurb(kind),
                                value: kind.isNew ? L10n.t("جديد", "New") : nil, valueTint: DS.Color.accent,
                                tap: .page { AdminReportKindUI.page(kind) })
                }
            }
        }
    }
}

// MARK: - مقاسات الصفحات (مكان واحد)

enum AdminReportsLayout {
    /// عرض صورة الصفحة في المعاينة
    static let thumbWidth: CGFloat = 132
    /// صفحات المعاينة في صفحة التصفية (الغلاف + أول صفحة داخلية)
    static let previewPages = 2
    /// صفحات المعاينة في «كيف يبدو؟»
    static let bookPreviewPages = 12
    /// أقلّ عرض لبطاقة «أعددتها مؤخراً»
    static let recentWidth: CGFloat = 150
    /// شريط العمر: مقبض ومسار
    static let ageThumb: CGFloat = 26
    static let ageTrack: CGFloat = 4
    /// مهلة قبل إعادة الإنشاء (ضغطات وسحبات متتالية = ملف واحد)
    static let debounce: UInt64 = 350_000_000
}

// MARK: - عرض الملف كاملاً (PDFKit)

struct AdminReportViewerItem: Identifiable {
    let url: URL
    let title: String
    var id: URL { url }
}

struct AdminReportViewer: View {
    let item: AdminReportViewerItem
    var onShare: (() -> Void)? = nil
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            DSSubPageHeader(title: item.title, subtitle: L10n.t("معاينة الملف", "File preview"),
                            section: .admin, nav: .close)
            AdminReportPDFView(url: item.url)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel(L10n.t("صفحات الملف", "File pages"))
            HStack {
                DSActionButton(title: L10n.t("مشاركة / حفظ", "Share / Save"), icon: "square.and.arrow.up") {
                    onShare?()
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

struct AdminReportShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - صور الصفحات (المعاينة)

/// صفّ صور الصفحات: الضغط يفتح الملف كاملاً، وعلى الأولى عدد الصفحات
struct AdminReportThumbs: View {
    let result: AdminReportResult
    var limit: Int = AdminReportsLayout.previewPages
    let open: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(Array(result.thumbnails.prefix(limit).enumerated()), id: \.offset) { i, image in
                    page(image, index: i)
                }
            }
            .padding(.vertical, DS.Spacing.xs)
            .padding(.horizontal, DS.Spacing.xxs)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("معاينة: \(AdminReportText.pages(result.pages))", "Preview: \(result.pages) pages"))
        .accessibilityHint(L10n.t("يفتح الملف كاملاً", "Opens the whole file"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    private func page(_ image: UIImage, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
        return Button(action: open) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: AdminReportsLayout.thumbWidth)
                .clipShape(shape)
                .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
                .overlay(alignment: .topTrailing) {
                    if index == 0 {
                        Text(L10n.t(AdminReportText.pages(result.pages), result.pages == 1 ? "1 page" : "\(result.pages) pages"))
                            .dsFont(.badge)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(Capsule().fill(DS.Color.brandFill))
                            .padding(DS.Spacing.sm)
                    }
                }
                .dsSubtleShadow()
        }
        .buttonStyle(DSPressStyle())
    }
}
