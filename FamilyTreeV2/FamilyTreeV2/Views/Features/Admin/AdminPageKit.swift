import SwiftUI

// MARK: - عُدّة الصفحات الداخلية للوحة الإدارة (طلب المالك ٢٠٢٦-١٠-٢٠: «كل الصفحات بنفس شكل «اليوم»»)
//
// كل صفحة تُفتح من صفّ في قسم (سجل الأعضاء، صحة الشجرة، الأجهزة…) تأخذ شكل «اليوم» و«الوارد»: رأس كحلي (رجوع
// زجاجي + اسم القسم بالذهبي، عنوان كبير، سطر وصف، رمز الصفحة، حتى ٤ أرقام، أزرار دائرية، شرائح فلتر) ثم بطاقات
// بيضاء على الأرضية الرملية — وأولها يصعد فوق الرأس قليلاً. القطع الصغيرة من `AdminHubKit.swift`، والمقاسات من `DS.Hub`.
//
// الاستعمال (للأقسام الباقية):
//   AdminPage(header: AdminPageHeader(title: "الأجهزة", subtitle: "…", glyph: "iphone.gen3", readOnly: !canEdit,
//                 kpis: [AdminPageKPI("\(n)", "جهاز", icon: "iphone", tap: .action { … })],
//                 actions: [AdminPageAction(symbol: "plus", label: "إضافة", tap: .page { AnyView(AddView()) })],
//                 chips: [AdminPageChip(id: "all", title: "الكل", count: n, selected: f == .all) { f = .all }]),
//             lead: AnyView(firstCard),                 // أول بطاقة — تصعد فوق الرأس (اختياري)
//             layout: .scroll,                          // أو .list: صفوف `List` بأزرار سحب — كل صفّ `.adminPageRow()`
//             content: AnyView(cards))
//   • البطاقات: `AdminSectionCard(title:tag:link:)`، الصفوف `AdminTapRow(icon:title:subtitle:value:tap:)`، الحالات
//     `AdminPageStateCard(.loading/.empty/.error)`، الحلقة `AdminScoreRow`، الأزرار `DSButton` (عرض السطر) و`AdminPillButton`.
//   • الضغطة `AdminPageTap`: `.action { }` أو `.page { AnyView(صفحة) }` — الصفحة المدفوعة تعرف عنوان هذه الصفحة.
//   • «رجوع + اسم القسم»: من يفتح الصفحة يسمّيه بـ `.adminBackTitle(_:)` (الضغطات `AdminPageTap` تفعل ذلك تلقائياً)،
//     وإلا «رجوع». صفوف الأقسام (`AdminToolRow` في AdminAreaPages) تحتاج سطراً واحداً: `.adminBackTitle(tool.area.title)`.
//   • صفحات `.list`: الضغطات تدفع عبر وجهة واحدة على مستوى الصفحة (لا `NavigationLink` داخل صفّ `List` — يضيف سهماً
//     رمادياً ويجعل الصفّ كله رابطاً). استعمل `AdminTapWrap`/`AdminTapRow` لا `NavigationLink` مباشرة في هذه الصفحات.
//   • حماية الجوال (انهيار «اليوم» ٢٠٢٦-١٠-٢٠): الهيكل بلا أنواع عامة — مرّر المحتوى `AnyView` وقسّم الطويل إلى
//     بطاقات `AnyView(...)`، ثم قِس `-tmpStackDepth` (الحدّ ٦٠٠ ك.ب).

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
    enum Feel { case press, scale, plain }

    let tap: AdminPageTap
    var feel: Feel = .press
    let label: AnyView
    var accessibilityLabel: String? = nil
    @Environment(\.adminPageTitle) private var pageTitle
    @Environment(\.adminPagePusher) private var pusher

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
                styled(NavigationLink { AdminLazyPage(make: make).adminBackTitle(pageTitle) } label: { label })
            }
        }
    }

    private func styled<B: View>(_ button: B) -> AnyView {
        let labelled = button.accessibilityLabel(accessibilityLabel.map { Text($0) } ?? Text(""))
        let base: AnyView = accessibilityLabel == nil ? AnyView(button) : AnyView(labelled)
        switch feel {
        case .press: return AnyView(base.buttonStyle(DSPressStyle()))
        case .scale: return AnyView(base.buttonStyle(DSScaleButtonStyle()))
        case .plain: return AnyView(base.buttonStyle(.plain))
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

/// رقم في رأس الصفحة (القيمة «—» قبل اكتمال التحميل: `AdminPageKPI.count(_:ready:)`)
struct AdminPageKPI: Identifiable {
    let value: String
    let label: String
    let icon: String
    var tint: Color = DS.Color.textOnPrimary
    var tap: AdminPageTap = .none

    var id: String { label }

    init(_ value: String, _ label: String, icon: String, tint: Color = DS.Color.textOnPrimary,
         tap: AdminPageTap = .none) {
        self.value = value
        self.label = label
        self.icon = icon
        self.tint = tint
        self.tap = tap
    }

    /// العدد، أو «—» قبل وصول البيانات (لا أصفار مضلِّلة)
    static func count(_ n: Int, ready: Bool = true) -> String { ready ? "\(n)" : "—" }
}

/// زرّ دائري زجاجي في طرف الرأس
struct AdminPageAction: Identifiable {
    let symbol: String
    let label: String
    var dot: Bool = false
    let tap: AdminPageTap

    var id: String { symbol + label }
}

/// شريحة فلتر داخل الرأس (المختارة ذهبية — مثل «الوارد»)
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
    /// رمز الصفحة بجانب العنوان (مربّع زجاجي بذهبي)
    var glyph: String? = nil
    /// شارة «للقراءة — يعدّلها المالك»
    var readOnly: Bool = false
    var kpis: [AdminPageKPI] = []
    var actions: [AdminPageAction] = []
    var chips: [AdminPageChip] = []
    /// ملحق حرّ آخر الرأس (حقل بحث فوق الكحلي…)
    var accessory: AnyView? = nil

    static let readOnlyText = L10n.t("للقراءة — يعدّلها المالك", "Read-only — the owner edits")
}

// MARK: - الرأس الكحلي

/// الرأس: (رجوع زجاجي + اسم الصفحة السابقة) · أزرار ← رمز + عنوان (+ شارة) ← وصف ← أرقام ← شرائح ← ملحق
struct AdminPageBand: View {
    let header: AdminPageHeader
    /// الاسم بجانب زرّ الرجوع (محلول مسبقاً)
    let backTitle: String
    /// تصعد بطاقة فوقه — حشوة سفلية أكبر
    var overlapped: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            titleRow
            if let subtitle = header.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.onBandMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.xxs)
            }
            if !header.kpis.isEmpty {
                kpiRow.padding(.top, DS.Spacing.lg)
            }
            if !header.chips.isEmpty {
                chipRow.padding(.top, header.kpis.isEmpty ? DS.Spacing.md : DS.Spacing.sm)
            }
            if let accessory = header.accessory {
                accessory.padding(.top, DS.Spacing.md)
            }
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, overlapped ? DS.Hub.headerBottom : DS.Hub.headerBottomCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }

    private var topRow: AnyView {
        AnyView(HStack(spacing: DS.Spacing.sm) {
            if header.showsBack {
                AdminPageBackButton(title: backTitle) { dismiss() }
            }
            Spacer(minLength: DS.Spacing.sm)
            ForEach(header.actions) { action in
                AdminTapWrap(tap: action.tap, feel: .scale,
                             label: AnyView(AdminGlassCircle(symbol: action.symbol, dot: action.dot)),
                             accessibilityLabel: action.label)
            }
        }
        .frame(minHeight: DS.Hub.glassButton))
    }

    private var titleRow: AnyView {
        AnyView(HStack(alignment: .center, spacing: DS.Spacing.sm) {
            if let glyph = header.glyph {
                Image(dsSymbol: glyph)
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    .foregroundColor(DS.Color.accentLight)
                    .frame(width: DS.Hub.iconSquare, height: DS.Hub.iconSquare)
                    .background(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                        .fill(DS.Hub.glass))
                    .overlay(RoundedRectangle(cornerRadius: DS.Hub.iconSquareRadius, style: .continuous)
                        .strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
                    .accessibilityHidden(true)
            }
            Text(header.title)
                .dsFont(.hubTitle)
                .foregroundColor(DS.Color.textOnPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if header.readOnly {
                AdminBandChip(text: AdminPageHeader.readOnlyText, icon: "eye.fill")
            }
        }
        .padding(.top, DS.Spacing.sm))
    }

    private var kpiRow: AnyView {
        AnyView(HStack(spacing: DS.Spacing.sm) {
            ForEach(header.kpis) { kpi in
                AdminTapWrap(tap: kpi.tap,
                             label: AnyView(AdminKPITile(value: kpi.value, label: kpi.label,
                                                         icon: kpi.icon, tint: kpi.tint)))
            }
        })
    }

    private var chipRow: AnyView {
        AnyView(ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xsm) {
                ForEach(header.chips) { chip in
                    AdminBandFilterChip(title: chip.title, count: chip.count, icon: chip.icon,
                                        iconTint: chip.iconTint, selected: chip.selected, action: chip.action)
                }
            }
            .padding(.vertical, DS.Spacing.xxs)
        })
    }
}

/// زرّ الرجوع: دائرة زجاجية بسهم + اسم الصفحة السابقة بالذهبي — ضغطة واحدة
struct AdminPageBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                AdminGlassCircle(symbol: "chevron.backward")
                Text(title)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.accentLight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("رجوع إلى \(title)", "Back to \(title)"))
    }
}

// MARK: - هيكل الصفحة

/// الصفحة الداخلية: الرأس الكحلي ثم المحتوى على الرملي — يُخفي شريط النظام (سحب الرجوع من الحافة يبقى)
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
    @Environment(\.adminBackTitle) private var outerBack
    @Environment(\.dsLandscape) private var landscape
    /// صفحة مدفوعة من صفحة `.list` (عبر `AdminPagePusher`)
    @State private var pushed: AdminPushedPage?
    @State private var isPushed = false

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
            .environment(\.adminPagePusher, nil))
    }

    private func frame(_ page: AnyView) -> some View {
        page
            .adminHideTopEdgeEffect()
            // السحب للأسفل فوق الرأس يكشف كحلياً لا رملياً
            .background(alignment: .top) {
                DS.Hub.bandTop.frame(height: DS.Hub.ringSide).ignoresSafeArea(edges: .top)
                    .accessibilityHidden(true)
            }
            .background(DS.Hub.background.ignoresSafeArea())
            .adminStatusBarCover()
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var band: AnyView {
        AnyView(AdminPageBand(header: header, backTitle: resolvedBack, overlapped: lead != nil))
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
                    if let lead { inPage(lead) }
                    inPage(content)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, lead != nil ? -DS.Hub.headerOverlap : DS.Hub.stackSpacing)
                .padding(.bottom, DS.Spacing.xxxl)
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
            // الرأس وأول بطاقة في صفّ واحد (لتصعد البطاقة فوقه)
            VStack(spacing: 0) {
                band
                if let lead {
                    inPage(lead)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, -DS.Hub.headerOverlap)
                        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth)
                        .frame(maxWidth: .infinity)
                        .background(DS.Hub.background)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            inPage(content)

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
            .listRowInsets(EdgeInsets(top: top, leading: DS.Spacing.lg, bottom: bottom, trailing: DS.Spacing.lg))
    }
}

extension View {
    /// صفّ في صفحة `.list`: أرضية رملية، بلا فاصل، بهوامش الصفحة، وعمود قراءة أفقياً
    func adminPageRow(top: CGFloat = DS.Spacing.xs, bottom: CGFloat = DS.Spacing.xs) -> some View {
        modifier(AdminPageRowModifier(top: top, bottom: bottom))
    }
}

// MARK: - البطاقات والصفوف

/// رابط ذهبي في طرف عنوان البطاقة
struct AdminPageLink {
    let title: String
    let tap: AdminPageTap
}

/// بطاقة قسم بيضاء: عنوان (+ عدد) وطرف (نص صغير أو رابط ذهبي) ثم المحتوى
struct AdminSectionCard<Content: View>: View {
    var title: String? = nil
    var badge: Int? = nil
    var badgeTint: Color = DS.Color.warning
    /// نص صغير في الطرف («اختياري»، «٤٥ فرد»)
    var tag: String? = nil
    var link: AdminPageLink? = nil
    var spacing: CGFloat = DS.Spacing.sm
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                AdminCardHeader(title: title, badge: badge, badgeTint: badgeTint) { trailing }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var trailing: AnyView {
        if let link {
            return AnyView(AdminTapWrap(tap: link.tap, feel: .plain, label: AnyView(AdminCardLinkLabel(title: link.title))))
        }
        if let tag {
            return AnyView(Text(tag)
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1))
        }
        return AnyView(EmptyView())
    }
}

/// شارة قيمة صغيرة في طرف الصفّ (عدد، «مكتمل»…) بلون معناها
struct AdminValueChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = DS.Color.textTertiary

    var body: some View {
        let ink = tint.dsReadableGlyph
        HStack(spacing: DS.Spacing.xxs) {
            if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.xs, weight: .bold)
            }
            Text(text)
                .dsFont(.chip)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(ink)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(minHeight: DS.Icon.section)
        .background(Capsule().fill(ink.opacity(DS.Opacity.tintFill)))
        .fixedSize()
    }
}

/// صفّ قابل للضغط في بطاقة: مربّع أيقونة + عنوان + وصف + قيمة (+ سهم إن كان يُضغط)
struct AdminTapRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueIcon: String? = nil
    var valueTint: Color = DS.Color.textTertiary
    var tap: AdminPageTap = .none

    var body: some View {
        AdminTapWrap(tap: tap, feel: .plain, label: AnyView(face))
    }

    private var face: some View {
        AdminListRow(icon: icon, tint: tint, title: title, subtitle: subtitle, showsChevron: tap.isTappable) {
            if let value {
                AdminValueChip(text: value, icon: valueIcon, tint: valueTint)
            }
        }
    }
}

/// صفوف مفصولة بخط رفيع داخل `AdminSectionCard` (الفاصل بين الظاهرة فقط — `AdminDividedLayout`)
struct AdminRowsCardBody<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        _VariadicView.Tree(AdminDividedLayout()) { content() }
    }
}

/// صفّ نسبة بحلقة (اكتمال البيانات، سلامة الشجرة): الحلقة بلون الحال + عنوان + سطر
struct AdminScoreRow: View {
    /// ٠…١ — nil = لم تكتمل الأرقام بعد («—»)
    let progress: Double?
    let title: String
    let subtitle: String

    private var percent: Int? { progress.map { Int(($0 * 100).rounded(.down)) } }

    private var tint: Color {
        guard let progress else { return DS.Color.textTertiary }
        return progress >= 0.9 ? DS.Color.success : (progress >= 0.6 ? DS.Color.warning : DS.Color.error)
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSRing(progress: progress ?? 0, tint: tint.dsReadableGlyph, lineWidth: DS.Spacing.xsm,
                   size: DS.Icon.sizeLg) {
                Text(percent.map { L10n.t("\($0)٪", "\($0)%") } ?? "—")
                    .dsFont(.chip)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, DS.Spacing.xs)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .dsFont(.footnote)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "\(title) \(L10n.t("\($0)٪", "\($0)%"))، \(subtitle)" } ?? title)
    }
}

/// حالة الصفحة داخل بطاقة بيضاء: تحميل (المجسّم يتنفّس)، فارغ، أو خطأ بزرّ «إعادة المحاولة»
struct AdminPageStateCard: View {
    enum Kind {
        case loading(String)
        case empty(String, message: String? = nil, tint: Color? = nil)
        case error(String, message: String? = nil, retry: (() -> Void)? = nil)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    var body: some View {
        content
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .adminCard()
    }

    private var content: AnyView {
        switch kind {
        case .loading(let text):
            return AnyView(DSPageLoader(text, fillsSpace: false))
        case .empty(let title, let message, let tint):
            return AnyView(DSEmptyView(title, message: message, tint: tint, style: .compact))
        case .error(let title, let message, let retry):
            return AnyView(DSEmptyView(title, message: message, icon: "wifi.exclamationmark", tint: DS.Color.error,
                                       actionTitle: retry == nil ? nil : L10n.t("إعادة المحاولة", "Retry"),
                                       actionIcon: "arrow.clockwise", style: .compact, action: retry))
        }
    }
}
