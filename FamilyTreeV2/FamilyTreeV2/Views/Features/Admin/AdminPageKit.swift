import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - عُدّة الصفحات الداخلية للوحة الإدارة (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec A.2–A.7 وA.12، الوحدة U3)
//
// كل صفحة تُفتح من صفّ في قسم (الأجهزة، التسجيل والمنع، التصنيفات…) بنفس رأس صفحات الأقسام: كحلي مسطّح (رجوع ذهبي بالنص،
// العنوان ٢٢، الوصف الذهبي، سطر «للاطلاع» بقفل، سطر الأرقام `AdminHeaderLine`، شرائح فلتر تلتفّ، ملحق) ثم بطاقات بيضاء
// بخطّ رفيع بلا ظلّ على الأرضية البيضاء — ١٦ تحت الرأس، لا شيء يصعد فوقه. القطع من `AdminHubKit.swift`، والمقاسات من `DS.Hub`.
//
// الاستعمال:
//   AdminPage(header: AdminPageHeader(title: "الأجهزة", subtitle: "…", readOnly: !canEdit,
//                 kpis: [AdminPageKPI("\(n)", "جهاز", icon: "iphone", tap: .action { … })],   // ← سطر الأرقام
//                 items: [AdminHeaderItem(value: n, label: "…", health: store.health, retry: { … })],
//                 actions: [AdminPageAction(symbol: "plus", label: "إضافة", tap: .page { AnyView(AddView()) })],
//                 chips: [AdminPageChip(id: "all", title: "الكل", count: n, selected: f == .all) { f = .all }]),
//             lead: AnyView(firstCard),                 // أول بطاقة (اختياري)
//             layout: .scroll,                          // أو .list: صفوف `List` بأزرار سحب — كل صفّ `.adminPageRow()`
//             content: AnyView(cards),
//             updatedAt: store.loadedAt)                // «آخر تحديث 9:41» آخر الصفحة (اختياري)
//   • البطاقات `AdminSectionCard(title:tag:link:)`، وبطاقة الحالة `AdminSectionCard(title:status:subtitle:)` (إطار يُرى
//     وحبّة الحالة في رأسها)؛ الصفوف `AdminTapRow` / `AdminInfoRow` / `AdminControlRow` / `AdminSettingChoiceRow` داخل
//     `AdminRowsCardBody { }` (فاصل يبدأ من النص)؛ الحالات `AdminPageStateCard(.loading/.empty/.error/.readOnly())`
//     أو `AdminPageStateCard(health:loading:failed:retry:)` من حال المخزن.
//   • الأرقام: `AdminPageKPI` (نصّ) يتحوّل إلى `AdminHeaderItem` (`headerItem`) — الصفر باهت بلا ضغطة، «—» تحميل، والأعداد
//     بفاصل الآلاف. رقم له حال مخزن (فشل/قديم/مرفوض) يُمرَّر `items:` مباشرة.
//   • الضغطة `AdminPageTap`: `.action { }` أو `.page { AnyView(صفحة) }` — الصفحة المدفوعة تعرف عنوان هذه الصفحة.
//   • «رجوع + اسم الصفحة السابقة»: من يفتح الصفحة يسمّيه بـ `.adminBackTitle(_:)` (الضغطات `AdminPageTap` تفعل ذلك تلقائياً)،
//     وإلا «رجوع». صفوف الأقسام (`AdminToolRow` في AdminAreaPages) تحتاج سطراً واحداً: `.adminBackTitle(tool.area.title)`.
//   • صفحات `.list`: الضغطات تدفع عبر وجهة واحدة على مستوى الصفحة (لا `NavigationLink` داخل صفّ `List` — يضيف سهماً
//     رمادياً ويجعل الصفّ كله رابطاً). استعمل `AdminTapWrap`/`AdminTapRow` لا `NavigationLink` مباشرة في هذه الصفحات.
//   • حماية المكدس (انهيار «اليوم» ٢٠٢٦-١٠-٢٠): الهيكل بلا أنواع عامة — مرّر المحتوى `AnyView` وقسّم الطويل إلى
//     بطاقات `AnyView(...)`، ثم قِس `-tmpStackDepth` (الحدّ ٦٠٠ ك.ب).
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u3-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminPageKit.swift tests/admin-redesign/U3/main.swift && /tmp/u3-logic

// MARK: - المنطق الخالص

nonisolated enum AdminPageKitLogic {
    /// قيمة رقم الرأس القديم (`AdminPageKPI.value` نصّ حرّ) بعد قراءتها
    enum KPIValue: Equatable {
        /// «—» أو فارغ: لم يصل بعد
        case pending
        /// عدد عادي («170»، «2,991»، «١٢») — يُرسم بفاصل الآلاف، والصفر باهت بلا ضغطة
        case number(Int)
        /// ما ليس عدداً («83٪»، «✓»، «يعمل»، «1 من 2»، «+3») — يُرسم كما هو
        case text(String)
    }

    /// يقرأ نصّ الرقم: الأرقام العربية تُطبَّع، وفواصل الآلاف تُتجاهل، والإشارة أو أي حرف آخر = نصّ
    static func kpiValue(_ raw: String) -> KPIValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == AdminStoreHealthText.placeholder || trimmed == "-" { return .pending }
        var digits = ""
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39:     digits.unicodeScalars.append(scalar)
            case 0x660...0x669:   digits.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x660 + 0x30)!)
            case 0x6F0...0x6F9:   digits.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x6F0 + 0x30)!)
            // فاصل الآلاف: لاتيني «,»، عربي «٬»، ومسافة ضيّقة غير منقسمة
            case 0x2C, 0x66C, 0x202F: continue
            default:              return .text(trimmed)
            }
        }
        guard !digits.isEmpty, let n = Int(digits) else { return .text(trimmed) }
        return .number(n)
    }

    /// ما ترسمه الصفحة مكان بياناتها من حال مخزنها (spec A.12 + Autoplan note 2)
    enum PageState: Equatable {
        /// هيكل بشكل المحتوى
        case loading
        /// «تعذّر…» + «أعد المحاولة» — `lastGood` ≠ nil: البيانات القديمة تبقى ويُضاف «آخر تحديث 9:12»
        case failed(lastGood: Date?)
        /// البيانات حاضرة، أو المخزن مرفوض لهذا الدور (لا «أعد المحاولة» أبداً) — لا بطاقة حالة
        case content
    }

    static func pageState(_ health: AdminStoreHealth) -> PageState {
        switch health {
        case .idle, .loading:        return .loading
        case .loaded, .denied:       return .content
        case .failed(let lastGood):  return .failed(lastGood: lastGood)
        }
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - الضغطة

/// ما يحدث عند الضغط على رقم أو زرّ أو صفّ: لا شيء، إجراء، أو صفحة تُدفع في نفس المكدس
enum AdminPageTap {
    case none
    case action(() -> Void)
    case page(() -> AnyView)

    var isTappable: Bool {
        if case .none = self { return false }
        return true
    }
}

/// يغلّف وجهاً بضغطته — الصفحة المدفوعة تأخذ عنوان هذه الصفحة في «رجوع»
struct AdminTapWrap: View {
    /// `tile` = ضغطة مربّعات اللوحة (`AdminTilePressStyle` — يصغر وأيقونته تكبر)؛ `row` = ضغطة الصفّ (تظليل لا تصغير،
    /// `AdminRowPressStyle` — spec A.6/A.16)
    enum Feel { case press, scale, plain, tile, row }

    let tap: AdminPageTap
    var feel: Feel = .press
    let label: AnyView
    var accessibilityLabel: String? = nil
    @Environment(\.adminPageTitle) private var pageTitle
    @Environment(\.adminPagePusher) private var pusher
    /// قسم هذه الصفحة — يُمرَّر للصفحة المدفوعة (لا ترث بيئة موضع الرابط)
    @Environment(\.adminArea) private var area

    var body: some View {
        switch tap {
        case .none:
            label
        case .action(let run):
            styled(Button(action: run) { label })
        case .page(let make):
            if let pusher {
                // داخل صفحة `.list`: زرّ يدفع عبر وجهة الصفحة
                styled(Button { pusher.push(make, pageTitle) } label: { label })
            } else {
                styled(NavigationLink { AdminLazyPage(make: make).adminBackTitle(pageTitle).adminArea(area) } label: { label })
            }
        }
    }

    private func styled<B: View>(_ button: B) -> AnyView {
        let base: AnyView = accessibilityLabel.map { AnyView(button.accessibilityLabel(Text($0))) } ?? AnyView(button)
        switch feel {
        case .press: return AnyView(base.buttonStyle(DSPressStyle()))
        case .scale: return AnyView(base.buttonStyle(DSScaleButtonStyle()))
        case .plain: return AnyView(base.buttonStyle(.plain))
        case .tile:  return AnyView(base.buttonStyle(AdminTilePressStyle()))
        case .row:   return AnyView(base.buttonStyle(AdminRowPressStyle()))
        }
    }
}

// MARK: - البيئة: اسم الصفحة السابقة، ودفع الصفحات من صفحة `.list`

/// يدفع صفحة من داخل صفحة `.list` عبر `navigationDestination` واحدة على مستوى الصفحة
struct AdminPagePusher {
    let push: (_ make: @escaping () -> AnyView, _ backTitle: String?) -> Void
}

private struct AdminBackTitleKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct AdminPageTitleKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct AdminPagePusherKey: EnvironmentKey { static let defaultValue: AdminPagePusher? = nil }

extension EnvironmentValues {
    /// اسم الصفحة التي فُتحت منها هذه الصفحة (يظهر بجانب زرّ الرجوع) — nil = «رجوع»
    var adminBackTitle: String? {
        get { self[AdminBackTitleKey.self] }
        set { self[AdminBackTitleKey.self] = newValue }
    }
    /// عنوان صفحة اللوحة الحالية — لما تدفعه من صفحات
    var adminPageTitle: String? {
        get { self[AdminPageTitleKey.self] }
        set { self[AdminPageTitleKey.self] = newValue }
    }
    /// موجود داخل صفحة `.list` فقط — `AdminTapWrap` يدفع به بدل `NavigationLink`
    var adminPagePusher: AdminPagePusher? {
        get { self[AdminPagePusherKey.self] }
        set { self[AdminPagePusherKey.self] = newValue }
    }
}

extension View {
    /// على الصفحة المدفوعة: اسم الصفحة التي تعود إليها («العائلة»، «سجل الأعضاء»…)
    func adminBackTitle(_ title: String?) -> some View {
        environment(\.adminBackTitle, title)
    }
}

// MARK: - نموذج الرأس

/// رقم في رأس الصفحة (القيمة «—» قبل اكتمال التحميل: `AdminPageKPI.count(_:ready:)`). نموذج ثابت (Frozen API — plan
/// rule 2): يُرسم عنصراً في سطر الأرقام عبر `headerItem` — الرمز واللون والحلقة لا تُرسم بعد الآن (spec A.3: رقم أبيض +
/// اسم ذهبي، بلا مربّعات زجاجية ولا ألوان أرقام)
struct AdminPageKPI: Identifiable {
    let value: String
    let label: String
    let icon: String
    var tint: Color = DS.Color.textOnPrimary
    var tap: AdminPageTap = .none
    /// نسبة (٠…١) — كانت حلقة مصغّرة بجانب الرقم؛ القيمة نفسها تكفي في سطر الأرقام
    var ring: Double? = nil

    var id: String { label }

    init(_ value: String, _ label: String, icon: String, tint: Color = DS.Color.textOnPrimary,
         tap: AdminPageTap = .none, ring: Double? = nil) {
        self.value = value
        self.label = label
        self.icon = icon
        self.tint = tint
        self.tap = tap
        self.ring = ring
    }

    /// العدد، أو «—» قبل وصول البيانات (لا أصفار مضلِّلة)
    static func count(_ n: Int, ready: Bool = true) -> String { ready ? "\(n)" : "—" }
}

extension AdminPageKPI {
    /// الرقم بشكل سطر الرأس الجديد (`AdminHeaderLine`): «—» = تحميل (باهت بلا ضغطة)، العدد بفاصل الآلاف (والصفر باهت
    /// لا يفتح شيئاً)، وما ليس عدداً («83٪»، «يعمل») يُعرض كما هو
    var headerItem: AdminHeaderItem {
        switch AdminPageKitLogic.kpiValue(value) {
        case .pending:        return AdminHeaderItem(id: id, value: nil, label: label, tap: tap)
        case .number(let n):  return AdminHeaderItem(id: id, value: n, label: label, tap: tap)
        case .text(let text): return AdminHeaderItem(id: id, value: nil, text: text, label: label, tap: tap)
        }
    }
}

/// زرّ في طرف الرأس: دائرة زجاجية (٣٦ مرسومة، لمسها ٤٤)، أو نصّ («تحديد» — `textOnly`، إجراء فقط). زرّان على الأكثر
/// في الرأس (spec A.3)
struct AdminPageAction: Identifiable {
    let symbol: String
    let label: String
    var dot: Bool = false
    let tap: AdminPageTap
    /// يُرسم نصّاً بدل الدائرة (`AdminHeaderTextButton`) — لإجراء `.action` فقط؛ الصفحة `.page` تبقى دائرة
    var textOnly: Bool = false

    var id: String { symbol + label }
}

/// شريحة فلتر داخل الرأس (spec A.9: المختارة ذهبية بعلامة ✓ على الكحلي) — الصفّ يلتفّ ولا يتمرّر جانبياً
struct AdminPageChip: Identifiable {
    let id: String
    let title: String
    var count: Int? = nil
    var icon: String? = nil
    var iconTint: Color = DS.Color.textOnPrimary
    let selected: Bool
    let action: () -> Void
}

/// بيانات رأس الصفحة الكحلي — كلها اختيارية عدا العنوان
struct AdminPageHeader {
    /// اسم الصفحة السابقة — nil = من `.adminBackTitle` ثم «رجوع»
    var back: String? = nil
    /// false = بلا رجوع (صفحة جذر)
    var showsBack: Bool = true
    let title: String
    var subtitle: String? = nil
    /// قديم: كان رمز الصفحة في دائرة بجانب العنوان — الرأس الجديد بلا رمز (spec A.3)، فيُتجاهل
    var glyph: String? = nil
    /// سطر «للاطلاع فقط — التعديل للمالك» بقفل
    var readOnly: Bool = false
    /// أرقام الرأس القديمة (نصوص) — تُرسم في سطر الأرقام عبر `AdminPageKPI.headerItem`
    var kpis: [AdminPageKPI] = []
    /// عناصر سطر الأرقام بحال مخزنها (تحميل/فشل/قديم/مرفوض) — بعد `kpis`
    var items: [AdminHeaderItem] = []
    var actions: [AdminPageAction] = []
    var chips: [AdminPageChip] = []
    /// ملحق حرّ آخر الرأس (حقل بحث فوق الكحلي…)
    var accessory: AnyView? = nil

    static let readOnlyText = L10n.t("للاطلاع فقط — التعديل للمالك", "View only — the owner edits")

    /// كل عناصر سطر الأرقام بترتيبها
    var lineItems: [AdminHeaderItem] { kpis.map(\.headerItem) + items }
}

// MARK: - الرأس الكحلي

/// رأس الصفحة الداخلية (spec A.3) من قطع رأس الأقسام نفسها (`AdminHeaderLead`، `AdminBandChip`، `AdminHeaderLine` ومقاسات
/// `AdminBandHeader`): «‹ رجوع» ذهبي ← العنوان ٢٢ + زرّان ← الوصف الذهبي ← «للاطلاع» بقفل ← سطر الأرقام ← الشرائح ←
/// الملحق. كحلي مسطّح يلتفّ على محتواه.
/// لا يُستعمل `AdminBandHeader` نفسه لأن رجوعه `dismiss` من بيئته، وصفحة `.list` ترسم الرأس داخل خلية `List` حيث لا
/// يُخرج `dismiss` الصفحة من المكدس — فتمرّر الصفحة رجوعها هي (`onBack`)
struct AdminPageBand: View {
    let header: AdminPageHeader
    /// الاسم بجانب زرّ الرجوع (محلول مسبقاً)
    let backTitle: String
    /// قديم: البطاقة الأولى لم تعد تصعد فوق الرأس (`DS.Hub.headerOverlap` = ٠) — يُتجاهل
    var overlapped: Bool = false
    /// الرجوع من خارج الرأس (انظر أعلاه) — nil = `dismiss` من بيئة الرأس
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        let items = header.lineItems
        VStack(alignment: .leading, spacing: 0) {
            leadRow
            if header.readOnly {
                AdminBandChip(text: AdminPageHeader.readOnlyText, icon: "lock.fill")
            }
            if !items.isEmpty {
                AnyView(AdminHeaderLine(items: items))
            }
            if !header.chips.isEmpty {
                chipRow.padding(.top, items.isEmpty ? DS.Spacing.md : DS.Spacing.xs)
            }
            if let accessory = header.accessory {
                accessory.padding(.top, DS.Spacing.md)
            }
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, lineIsLast(items) ? DS.Hub.headerBottomLine : DS.Hub.headerBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }

    /// سطر الأرقام آخر ما في الرأس — حشوة سفلية أطول قليلاً (spec A.1)
    private func lineIsLast(_ items: [AdminHeaderItem]) -> Bool {
        !items.isEmpty && header.chips.isEmpty && header.accessory == nil
    }

    private var leadRow: AnyView {
        let dismiss = dismiss
        let back = onBack ?? { dismiss() }
        return AnyView(AdminHeaderLead(backTitle: header.showsBack ? backTitle : nil,
                                       onBack: header.showsBack ? back : nil,
                                       subtitle: header.subtitle) {
            Text(header.title)
                .dsFont(.hubTitle)
                .foregroundColor(DS.Color.headerTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        } trailing: {
            ForEach(header.actions) { action in
                if action.textOnly, case .action(let run) = action.tap {
                    AdminHeaderTextButton(title: action.label, action: run)
                } else {
                    AdminTapWrap(tap: action.tap, feel: .scale,
                                 label: AnyView(AdminGlassCircle(symbol: action.symbol, dot: action.dot)),
                                 accessibilityLabel: action.label)
                }
            }
        })
    }

    /// الشرائح تلتفّ لسطر ثانٍ — لا تمرير جانبي ولا قصّ (spec A.9). ٨ بين السطرين فيتلاصق لمسهما (٤٤) بلا تداخل
    private var chipRow: AnyView {
        AnyView(DSChipFlow(spacing: DS.Spacing.xsm, lineSpacing: DS.Spacing.sm) {
            ForEach(header.chips) { chip in
                AdminBandFilterChip(title: chip.title, count: chip.count, icon: chip.icon,
                                    iconTint: chip.iconTint, selected: chip.selected, action: chip.action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading))
    }
}

/// قديم: زرّ الرجوع الزجاجي — حلّ محلّه الرابط الذهبي بالنص (spec A.3)
@available(*, deprecated, message: "use AdminBackLink; U21 removes")
struct AdminPageBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        AdminBackLink(title: title, action: action)
    }
}

// MARK: - هيكل الصفحة

/// الصفحة الداخلية (spec A.2): الرأس الكحلي ثم المحتوى على الأرضية البيضاء — ١٦ تحت الرأس، ٢٤ آخرها فوق شريط
/// التبويبات، و«آخر تحديث» في الوسط إن مُرّر. يُخفي شريط النظام (سحب الرجوع من الحافة يبقى)
struct AdminPage: View {
    enum Layout {
        /// بطاقات في `ScrollView`
        case scroll
        /// صفوف `List` (لأزرار السحب والتحميل التدريجي) — كل صفّ في المحتوى `.adminPageRow()`
        case list
    }

    let header: AdminPageHeader
    var lead: AnyView? = nil
    var layout: Layout = .scroll
    let content: AnyView
    /// وقت آخر بيانات صالحة — «آخر تحديث 9:41» ١٣ رمادي في الوسط آخر الصفحة (spec A.2). nil = بلا سطر
    var updatedAt: Date? = nil
    @Environment(\.adminBackTitle) private var outerBack
    @Environment(\.adminArea) private var area
    @Environment(\.dsLandscape) private var landscape
    /// رجوع الصفحة نفسها (خارج `List`) — يُمرَّر للرأس
    @Environment(\.dismiss) private var dismiss
    /// صفحة مدفوعة من صفحة `.list` (عبر `AdminPagePusher`)
    @State private var pushed: AdminPushedPage?
    @State private var isPushed = false
    /// «ظهور موحّد»: البطاقة الأولى ثم المحتوى يصعدان تباعاً مرة عند الظهور الأول فقط — لا عند التحديث (`dsCardCascade`)
    @State private var appeared = false

    private var resolvedBack: String { header.back ?? outerBack ?? L10n.t("رجوع", "Back") }

    var body: some View {
        if layout == .list {
            frame(AnyView(listBody.environment(\.adminPagePusher, pusher)))
                .navigationDestination(isPresented: $isPushed) { pushedPage }
        } else {
            frame(scrollBody)
        }
    }

    private var pusher: AdminPagePusher {
        AdminPagePusher { make, back in
            pushed = AdminPushedPage(make: make, backTitle: back)
            isPushed = true
        }
    }

    /// الوجهة لا ترث دافع هذه الصفحة (لكل صفحة `.list` دافعها)
    private var pushedPage: AnyView {
        guard let pushed else { return AnyView(EmptyView()) }
        return AnyView(AdminLazyPage(make: pushed.make)
            .adminBackTitle(pushed.backTitle)
            .adminArea(area)
            .environment(\.adminPagePusher, nil))
    }

    private func frame(_ page: AnyView) -> some View {
        page
            .adminHideTopEdgeEffect()
            // السحب للأسفل فوق الرأس يكشف كحلياً لا أبيض (نفس صفحات الأقسام)
            .background(alignment: .top) {
                AdminBandBackground().frame(height: AdminHubMetrics.pullReveal).ignoresSafeArea(edges: .top)
            }
            .background(DS.Hub.background.ignoresSafeArea())
            .adminStatusBarCover()
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear { appeared = true }
    }

    /// ما يدفعه الرأس (رقم يفتح قائمة، زرّ ＋) يرجع باسم هذه الصفحة لا باسم ما قبلها
    private var band: AnyView {
        let dismiss = dismiss
        return AnyView(AdminPageBand(header: header, backTitle: resolvedBack, onBack: { dismiss() })
            .environment(\.adminPageTitle, header.title))
    }

    /// المحتوى يعرف عنوان هذه الصفحة (لـ«رجوع» ما يُدفع منه)
    private func inPage(_ view: AnyView) -> some View {
        view
            .environment(\.adminPageTitle, header.title)
            .environment(\.adminBackTitle, header.title)
    }

    private var scrollBody: AnyView {
        AnyView(ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                band
                VStack(spacing: DS.Hub.stackSpacing) {
                    if let lead { inPage(lead).dsCardCascade(0, appeared: appeared) }
                    inPage(content).dsCardCascade(lead == nil ? 0 : 1, appeared: appeared)
                    if let updatedAt {
                        AdminPageFooter(date: updatedAt).padding(.top, DS.Spacing.sm)
                    }
                }
                .dsPageMargin()
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Hub.pageBottom)
                .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
                .dsTabBarClearance()
                .frame(maxWidth: .infinity)
                .background(DS.Hub.background)
            }
        }
        .scrollDismissesKeyboard(.interactively))
    }

    private var listBody: AnyView {
        AnyView(List {
            // الرأس وأول بطاقة في صفّ واحد — ١٦ بينهما (أول صفوف المحتوى يحمل ٤ فوقه، فبلا بطاقة أولى يُكمل الفراغ)
            VStack(spacing: 0) {
                band
                if let lead {
                    inPage(lead)
                        .dsCardCascade(0, appeared: appeared)
                        .dsPageMargin()
                        .padding(.top, DS.Spacing.lg)
                        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
                        .frame(maxWidth: .infinity)
                        .background(DS.Hub.background)
                } else {
                    Color.clear
                        .frame(height: DS.Spacing.lg - DS.Spacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            inPage(content)

            if let updatedAt {
                AdminPageFooter(date: updatedAt)
                    .adminPageRow(top: DS.Spacing.lg, bottom: 0)
            }

            // آخر صفّ لا يختفي تحت شريط التبويبات
            DS.Hub.background
                .frame(height: landscape ? DS.Landscape.tabBarClearance + DS.Spacing.lg : DS.Spacing.xxxl)
                .listRowInsets(EdgeInsets())
                .listRowBackground(DS.Hub.background)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
        // أفقياً: الصفوف بعرض الشاشة كي يصل الكحلي للحافتين (المحتوى نفسه في عمود القراءة)
        .ignoresSafeArea(.container, edges: landscape ? .horizontal : []))
    }
}

/// «آخر تحديث 9:41» آخر الصفحة — ١٣ رمادي في الوسط (spec A.2)
private struct AdminPageFooter: View {
    let date: Date

    var body: some View {
        Text(AdminStoreHealthText.updated(date))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

private struct AdminPushedPage {
    let make: () -> AnyView
    let backTitle: String?
}

private struct AdminPageRowModifier: ViewModifier {
    let top: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content
            .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
            .listRowBackground(DS.Hub.background)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: DS.Page.margin, bottom: bottom, trailing: DS.Page.margin))
    }
}

extension View {
    /// صفّ في صفحة `.list`: أرضية اللوحة، بلا فاصل النظام (الفاصل خطّنا الرفيع)، بهوامش الصفحة، وعمود قراءة أفقياً
    func adminPageRow(top: CGFloat = DS.Spacing.xs, bottom: CGFloat = DS.Spacing.xs) -> some View {
        modifier(AdminPageRowModifier(top: top, bottom: bottom))
    }
}

// MARK: - البطاقات (spec A.5)

/// رابط في طرف عنوان البطاقة («عرض الكل ‹» — ١٥ كحلي)
struct AdminPageLink {
    let title: String
    let tap: AdminPageTap
}

/// بطاقة قسم بيضاء (spec A.5): إطار رفيع بلا ظلّ، زاوية ١٢، حشوة ١٤ — عنوان ١٥ (+ عدد) وطرف (ملاحظة ١٣ أو رابط) ثم
/// المحتوى. `isOpen` = بطاقة تُطوى: العنوان زرّ بسهم، والمحتوى يظهر عند الفتح.
/// بطاقة الحالة (`status:`): إطار يُرى (`DS.Hub.frameStroke`)، رأسها العنوان ١٧ وتحته سطر ذهبي (`subtitle`) وحبّة الحالة
/// في الطرف — كلمة دائماً (`AdminStatePill`، ومعها حال مخزنها) — ثم خطّ ثم الصفوف
struct AdminSectionCard<Content: View>: View {
    var title: String? = nil
    var badge: Int? = nil
    var badgeTint: Color = DS.Color.warning
    /// ملاحظة ١٣ رمادية في الطرف («اختياري»، «٤٥ فرد»)
    var tag: String? = nil
    var link: AdminPageLink? = nil
    var spacing: CGFloat = DS.Spacing.sm
    var isOpen: Binding<Bool>? = nil
    /// سطر ملخّص تحت عنوان البطاقة المطويّة (يختفي عند الفتح)
    var summary: String? = nil
    /// حبّة الحالة في رأس بطاقة الحالة («يعمل للجميع ✓»، «تعذّر التحميل ↻») — تجعلها بطاقة حالة
    var status: AdminStatePill? = nil
    /// سطر تحت العنوان (بطاقة الحالة: «الإصدار 1.0.1 (51)» بالذهبي الغامق؛ غيرها: رمادي)
    var subtitle: String? = nil
    /// إطار يُرى بلا حبّة حالة (صفّ الانتباه — spec A.1)
    var framed: Bool = false
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                if let status {
                    statusHead(title: title, status: status)
                    AdminRowDivider()
                } else if let isOpen {
                    Button {
                        withAnimation(reduceMotion ? nil : DSMotion.expand) { isOpen.wrappedValue.toggle() }
                    } label: {
                        AdminCardHeader(title: title, badge: badge, badgeTint: badgeTint) {
                            AnyView(HStack(spacing: DS.Spacing.xs) {
                                trailing
                                Image(systemName: "chevron.down")
                                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
                                    .accessibilityHidden(true)
                            })
                        }
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -DS.Spacing.xsm)
                    .accessibilityHint(isOpen.wrappedValue ? L10n.t("يخفي المحتوى", "Collapses")
                                                           : L10n.t("يعرض المحتوى", "Expands"))
                } else {
                    AdminCardHeader(title: title, badge: badge, badgeTint: badgeTint) { trailing }
                }
                if status == nil, let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isOpen?.wrappedValue ?? true {
                content()
                    .transition(.opacity)
            } else if let summary {
                Text(summary)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard(framed: framed || status != nil)
    }

    /// رأس بطاقة الحالة: العنوان ١٧ والسطر الذهبي، والحبّة في الطرف — تنزل تحت العنوان حين لا يتّسع السطر (أحجام الخط الكبيرة)
    private func statusHead(title: String, status: AdminStatePill) -> some View {
        let heading = VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .dsFont(.statValue)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                heading
                Spacer(minLength: DS.Spacing.sm)
                status.fixedSize()
                trailing
            }
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                heading
                HStack(spacing: DS.Spacing.sm) {
                    status
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .padding(.bottom, DS.Spacing.xxs)
    }

    private var trailing: AnyView {
        if let link {
            return AnyView(AdminTapWrap(tap: link.tap, feel: .plain, label: AnyView(AdminCardLinkLabel(title: link.title))))
        }
        if let tag {
            return AnyView(Text(tag)
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1))
        }
        return AnyView(EmptyView())
    }
}

// MARK: - الصفوف (spec A.6)

/// صفّ معلومة في بطاقة (بلا ضغطة): مربّع أيقونة + عنوان + وصف + طرف حرّ (رقم، حبّة، مفتاح…)
/// — بديل `DSRow` داخل بطاقات اللوحة (صفوف مفصولة بخط، لا صناديق داخل البطاقة)
struct AdminInfoRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        AdminListRow(icon: icon, tint: tint, title: title, subtitle: subtitle, showsChevron: false) {
            trailing ?? AnyView(EmptyView())
        }
    }
}

/// صفّ إعداد في بطاقة بشكل `AdminListRow`: مربّع ٣٠ ممتلئ + عنوان ١٥ + وصف ١٣ رمادي + أداة تحكّم (مفتاح، عدّاد…) في
/// الطرف. الأداة لا تُدمج مع النص للقارئ الصوتي (يبقى العدّاد قابلاً للزيادة والنقص، والمفتاح بتسميته). الوصف يلتفّ كاملاً
/// — شرح الإعداد لا يُقصّ
struct AdminControlRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    let control: AnyView

    var body: some View {
        let twoLines = subtitle.map { !$0.isEmpty } ?? false
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
            AdminRowText(title: title, subtitle: subtitle)
            Spacer(minLength: DS.Spacing.xs)
            control
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: twoLines ? DS.Hub.rowMinHeightTwoLines : DS.Hub.rowMinHeight)
    }
}

/// صفّ إعداد باختيار من خيارين أو ثلاثة: الرمز والعنوان والشرح، ثم الاختيار الموحّد (`DSChoiceTiles`) بعرض الصفّ تحته
/// (طلب المالك ٢٠٢٦-١١-١١ — بدل القائمة الأصلية في طرف الصفّ)
struct AdminSettingChoiceRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    let control: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: icon, tint: tint, filled: true)
                AdminRowText(title: title, subtitle: subtitle)
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hub.rowMinHeight)
            control
        }
        .padding(.vertical, DS.Spacing.sm)
    }
}

/// نصّ الصفّ: العنوان ١٥ عادي بالحبر، والوصف ١٣ رمادي — عنصر واحد للقارئ الصوتي
private struct AdminRowText: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// قيمة في طرف صفّ المعلومة (عدد الأجهزة، الرموز…) — ١٥ شبه عريض بأرقام متساوية العرض (spec A.6/A.10)
struct AdminRowValue: View {
    let text: String
    var tint: Color = DS.Color.textPrimary

    var body: some View {
        Text(text)
            .dsFont(.hubValue)
            .monospacedDigit()
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// صفوف قائمة طويلة كسولة داخل بطاقة، بخط رفيع بين كل صفّين (القوائم التي قد تطول لمئات الصفوف)
struct AdminLazyRows<Item: Identifiable>: View {
    let items: [Item]
    let row: (Item) -> AnyView

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    if index > 0 { AdminRowDivider() }
                    row(item)
                }
            }
        }
    }
}

/// قيمة صغيرة في طرف الصفّ (عدد، «مكتمل»…) بشكل حبّة الحالة (spec A.7): كبسولة ١٣ متوسط، حشوة ٦ × ١١، النصّ بلونه على
/// ١٢٪ منه. الرمادي الافتراضي يُكتب بالرمادي الأغمق (`textSecondary`) ليبقى مقروءاً فوق تعبئته
struct AdminValueChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = DS.Color.textTertiary

    var body: some View {
        let neutral = tint == DS.Color.textTertiary
        let ink = neutral ? DS.Color.textSecondary : tint.dsReadableGlyph
        HStack(spacing: DS.Spacing.xs) {
            if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.sm, weight: .semibold)
            }
            Text(text)
                .dsFont(.chip)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(ink)
        .padding(.vertical, DS.Hub.statePillPaddingV)
        .padding(.horizontal, DS.Hub.statePillPaddingH)
        .background(Capsule().fill((neutral ? DS.Color.textTertiary : ink).opacity(DS.Opacity.tintFill)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// صفّ قابل للضغط في بطاقة: مربّع أيقونة + عنوان + وصف + قيمة (+ سهم إن كان يُضغط). الضغطة تظليل لا تصغير (spec A.6).
/// `destructive` = صفّ الحذف: العنوان أحمر والمربّع رمز أحمر على ١٢٪، بلا سهم — آخر بطاقته، وضغطته تسأل أولاً (`dsAlert`)
struct AdminTapRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueIcon: String? = nil
    var valueTint: Color = DS.Color.textTertiary
    var tap: AdminPageTap = .none
    var destructive: Bool = false

    var body: some View {
        AdminTapWrap(tap: tap, feel: .row, label: AnyView(face))
    }

    private var face: some View {
        AdminListRow(icon: icon, tint: tint, title: title, subtitle: subtitle,
                     showsChevron: tap.isTappable && !destructive, destructive: destructive) {
            if let value {
                AdminValueChip(text: value, icon: valueIcon, tint: valueTint)
            }
        }
    }
}

/// صفوف مفصولة بخط رفيع داخل `AdminSectionCard` — الفاصل بين الظاهرة فقط، ويبدأ من النص بعد مربّع الأيقونة
/// (`dividerInset`؛ ٠ لصفوف بلا أيقونة — spec A.5)
struct AdminRowsCardBody<Content: View>: View {
    var dividerInset: CGFloat = AdminRowDivider.iconInset
    @ViewBuilder var content: () -> Content

    var body: some View {
        _VariadicView.Tree(AdminDividedLayout(inset: dividerInset)) { content() }
    }
}

/// صفّ نسبة بحلقة (اكتمال البيانات، سلامة الشجرة): الحلقة الصغيرة الموحّدة بالنسبة في وسطها (تعدّ من الصفر) + عنوان + سطر.
/// اللون بالحال (≥ ٩٠٪ نجاح، ≥ ٦٠٪ تحذير، وإلا خطأ) أو لون ثابت (`tint`)
struct AdminScoreRow: View {
    /// ٠…١ — nil = لم تكتمل الأرقام بعد («—»)
    let progress: Double?
    let title: String
    let subtitle: String
    /// لون ثابت بدل لون الحال (اكتمال البيانات ذهبي)
    var tint: Color? = nil

    private var percent: Int? { progress.map { Int(($0 * 100).rounded(.down)) } }

    private var ink: Color {
        if let tint { return tint }
        guard let progress else { return DS.Color.textTertiary }
        return (progress >= 0.9 ? DS.Color.success : (progress >= 0.6 ? DS.Color.warning : DS.Color.error)).dsReadableGlyph
    }

    var body: some View {
        DSGaugeRow(gauge: DSRingGauge(progress: progress, tint: ink, size: DS.Ring.small, center: .percent(percent)),
                   title: title, subtitle: subtitle,
                   spoken: percent.map { "\(title) \(DSGaugeText.percent($0))، \(subtitle)" } ?? title)
    }
}

// MARK: - حالات الصفحة (spec A.12)

/// حالة الصفحة في بطاقة مكان بياناتها:
/// - تحميل: هيكل صفوف رمادية بشكل المحتوى النهائي (لا دوّارة) — النصّ للقارئ الصوتي
/// - فارغ: ما الفارغ + أول إجراء (مجسّم القسم الصغير)
/// - خطأ: ما الذي تعذّر + «أعد المحاولة»، و«آخر تحديث 9:12» حين تبقى بيانات قديمة تحته
/// - للاطلاع: «للاطلاع فقط — التعديل للمالك» بقفل مكان أدوات التعديل
struct AdminPageStateCard: View {
    enum Kind {
        /// نصّ التحميل (للقارئ الصوتي) وعدد صفوف الهيكل
        case loading(String, rows: Int = 3)
        case empty(String, message: String? = nil, tint: Color? = nil, actionTitle: String? = nil,
                   action: (() -> Void)? = nil)
        /// `lastGood` = وقت آخر بيانات صالحة تبقى معروضة (nil = لا شيء)
        case error(String, message: String? = nil, retry: (() -> Void)? = nil, lastGood: Date? = nil)
        /// nil = «للاطلاع فقط — التعديل للمالك»
        case readOnly(String? = nil, message: String? = nil)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    /// من حال المخزن (`AdminStoreHealth`): تحميل أول ← هيكل، فشل ← خطأ بإعادة المحاولة (وقت آخر بيانات إن وُجدت).
    /// nil حين وصلت البيانات، أو حين المخزن مرفوض لدورك — لا بطاقة ولا «أعد المحاولة» للمرفوض
    init?(health: AdminStoreHealth, loading: String, failed: String, message: String? = nil,
          retry: (() -> Void)? = nil) {
        switch AdminPageKitLogic.pageState(health) {
        case .content:
            return nil
        case .loading:
            kind = .loading(loading)
        case .failed(let lastGood):
            kind = .error(failed, message: message, retry: health.canRetry ? retry : nil, lastGood: lastGood)
        }
    }

    var body: some View {
        switch kind {
        case .loading(let text, let rows):
            AdminSkeletonRows(count: max(1, rows))
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        case .empty(let title, let message, let tint, let actionTitle, let action):
            DSEmptyView(title, message: message, tint: tint, actionTitle: actionTitle, style: .compact, action: action)
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity)
                .adminCard()
        case .error(let title, let message, let retry, let lastGood):
            AdminStateNotice(symbol: "exclamationmark.triangle.fill", tint: DS.Color.error, title: title,
                             lines: [message, lastGood.map { AdminStoreHealthText.updated($0) }].compactMap { $0 },
                             retry: retry)
                .adminCard(framed: true)
        case .readOnly(let title, let message):
            AdminStateNotice(symbol: "lock.fill", tint: DS.Color.textSecondary,
                             title: title ?? AdminPageHeader.readOnlyText,
                             lines: [message].compactMap { $0 }, retry: nil)
                .adminCard()
        }
    }
}

/// صفّ حالة داخل بطاقة: مربّع ٣٠ خفيف (الرمز بلونه على ١٢٪ منه) + العنوان ١٥ + أسطر ١٣ رمادية، و«أعد المحاولة» تحت النص
private struct AdminStateNotice: View {
    let symbol: String
    let tint: Color
    let title: String
    let lines: [String]
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: symbol, tint: tint, filled: false)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, DS.Spacing.xs)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            if let retry {
                AdminPillButton(title: AdminStoreHealthText.retry, icon: "arrow.clockwise", style: .soft, action: retry)
                    .padding(.leading, AdminRowDivider.iconInset)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeightTwoLines, alignment: .leading)
    }
}

/// هيكل التحميل: صفوف بشكل صفوف البطاقة (مربّع + سطرا العنوان والوصف) رمادية ثابتة — بلا حركة، وبفاصل يبدأ من النص
private struct AdminSkeletonRows: View {
    let count: Int

    private let fill = DS.Color.textTertiary.opacity(DS.Opacity.tintFill)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                if i > 0 { AdminRowDivider(inset: AdminRowDivider.iconInset) }
                HStack(spacing: DS.Spacing.md) {
                    RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                        .fill(fill)
                        .frame(width: DS.Hub.iconSquare, height: DS.Hub.iconSquare)
                    VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                        Capsule().fill(fill)
                            .frame(width: AdminSkeletonMetrics.titleWidths[i % AdminSkeletonMetrics.titleWidths.count],
                                   height: AdminSkeletonMetrics.titleBar)
                        Capsule().fill(fill)
                            .frame(width: AdminSkeletonMetrics.subtitleWidths[i % AdminSkeletonMetrics.subtitleWidths.count],
                                   height: AdminSkeletonMetrics.subtitleBar)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
            }
        }
    }
}

/// مقاسات هيكل التحميل (رسم فقط): سُمك سطري العنوان (١٥) والوصف (١٣)، وأطوال تتبدّل بين الصفوف فلا تبدو نسخاً
private enum AdminSkeletonMetrics {
    static let titleBar: CGFloat = 12
    static let subtitleBar: CGFloat = 10
    static let titleWidths: [CGFloat] = [148, 112, 168]
    static let subtitleWidths: [CGFloat] = [92, 128, 76]
}

#endif
