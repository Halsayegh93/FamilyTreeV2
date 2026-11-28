import SwiftUI
import Supabase
import Combine

// MARK: - «الإحصاءات»: أدوات الرسم وقسم «الموافقات» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec A.10/A.11/C.12، الوحدة U15)
//
// قطع صفحة «الإحصاءات» (AdminAnalyticsView.swift) — كلها بألوان `DS.Chart` ورموز النص فقط، والأرقام لاتينية بفاصل الآلاف:
//  • `AdminStatsSection` عنوان ١٥ + ملاحظة ١٣ ثم البطاقة (spec A.4)؛ `AdminStatsCard` بطاقة بيضاء بخط رفيع بلا ظلّ (A.5).
//  • `AdminStatsHeadline` جملة تبدأ بالرقم ١٧ شبه عريض + سطر ١٣ رمادي («170 لهم حساب» / «من 2,489 حياً في العائلة»).
//  • `AdminStatsRow` صفّ [لون أو رمز][عنوان ١٥ / وصف ١٣]…[القيمة ١٥ شبه عريض][سهم إن فتح قائمة] — ٤٤ / ٥٦ (A.6).
//  • `AdminStatsMeter` نسبة واحدة من كلّ: شريط ٨ بمسار من درجة أفتح + سطر «لهم حساب 7٪ … بلا حساب 93٪» (A.11).
//  • `AdminStatsColumns` أعمدة الأشهر (القيم فوقها، الأشهر تحتها، من اليمين في العربية، تعليق بجانب الشهر الشاذّ).
//  • `AdminStatsBars` أشرطة أفقية للفئات بترتيبها الطبيعي، بلون واحد، والرقم عند طرف الشريط.
//  • `AdminStatsDuo` رقمان متجاوران في بطاقة واحدة («الشجرة»).
// dataviz: علامات رفيعة (الشريط ٨، العمود ≤ ٢٤)، طرف البيانات مدوّر ٤ والقاعدة مستقيمة، النصّ لا يلبس لون السلسلة، كل لون
// بجانب اسمه، ولكل رسم جملة للقارئ الصوتي بكل قيمه (لا تلميحات لمس على iOS — القيم مطبوعة). الحركة: تمتلئ مرة عند الظهور
// الأول (`DS.Ring.fill`)، وثابتة مع «تقليل الحركة».
// «الموافقات» (المالك والمدير، والمسار مفعّل): `approvals_report` لآخر ٣٠ يوماً ← «41 طلباً» + شريط مقسّم انقبلت · انرفضت ·
// تنتظر (ألوان الحال بكلماتها) + أكثر ٣ أنواع + «تقرير الموافقات كاملاً ‹» (`ApprovalsReportView`، بيته الوحيد).

// MARK: - المقاسات (من الرموز)

enum AdminStatsMetrics {
    /// العمود لا يتجاوز ٢٤ (dataviz) — يترك ما بقي من خانته هواءً
    static let columnMaxWidth: CGFloat = DS.Spacing.xxl
    /// طرف البيانات المدوّر (العمود والشريط)، والقاعدة مستقيمة
    static let dataEndRadius: CGFloat = DS.Spacing.xs
    /// بين الشريط ورقمه
    static let barValueGap: CGFloat = DS.Spacing.xsm
    /// تعليق الشهر الشاذّ: عرضه بجانب عموده
    static let spikeNoteWidth: CGFloat = DS.Chart.barLabelWidth
}

// MARK: - العنوان والبطاقة

/// عنوان قسم الصفحة وبطاقته: العنوان ١٥ شبه عريض + ملاحظة ١٣ رمادية في الطرف، ٨ ثم المحتوى (spec A.2/A.4)
struct AdminStatsSection<Content: View>: View {
    let anchor: AdminStatsAnchor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: AdminStatsText.title(anchor), trailing: AdminStatsText.note(anchor))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// بطاقة القسم (spec A.5): الحشوة الأفقية وحدها — الصفوف تحمل ارتفاعها والكتل حشوتها العمودية، وتظليل ضغط الصفّ يمتدّ
/// لحافتي البطاقة ويتبع زاويتها
struct AdminStatsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, DS.Hub.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
            .adminCard(padding: 0)
    }
}

/// كتلة داخل البطاقة بحشوتها العمودية (العنوان، الشريط، الرسم)
private struct AdminStatsBlockPadding: ViewModifier {
    let top: Bool
    let bottom: Bool

    func body(content: Content) -> some View {
        content
            .padding(.top, top ? DS.Hub.cardPadding : 0)
            .padding(.bottom, bottom ? DS.Hub.cardPadding : DS.Spacing.sm)
    }
}

extension View {
    /// كتلة في `AdminStatsCard`: ١٤ فوقها (أول البطاقة)، وتحتها ١٤ آخر البطاقة أو ٨ قبل صفوف
    func adminStatsBlock(top: Bool = true, bottom: Bool = false) -> some View {
        modifier(AdminStatsBlockPadding(top: top, bottom: bottom))
    }
}

// MARK: - الجملة الرئيسة

/// «170 لهم حساب» ١٧ شبه عريض + «من 2,489 حياً في العائلة» ١٣ رمادي (spec A.10). `opens` = سهم (الضغطة من الحاوي)
struct AdminStatsHeadline: View {
    let title: String
    var line: String? = nil
    var opens: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: title)
                    .dsFont(.statValue)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line {
                    Text(verbatim: line)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if opens { DSChevron() }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - الصفّ

/// صفّ في بطاقة الإحصاءات (spec A.6): `[لون/رمز][عنوان ١٥ / وصف ١٣]…[القيمة ١٥ شبه عريض][سهم إن فتح قائمة]`.
/// الرقم بلا قائمة بلا سهم (spec A.10). الضغطة تظليل لا تصغير، والقارئ الصوتي يقرأ جملة واحدة
struct AdminStatsRow: View {
    enum Mark: Equatable {
        case none
        /// رمز صغير رمادي (الأدوار)، أو تنبيه بلونه («بلا تاريخ وفاة كامل»)
        case glyph(String, Color)
        /// مربّع لون السلسلة بجانب اسمها — `hatched` = تظليل ٤٥° مع «التمييز بدون لون» (spec A.11)
        case swatch(Color, hatched: Bool)
    }

    enum ValueStyle { case number, note }

    let title: String
    var subtitle: String? = nil
    var mark: Mark = .none
    /// nil = صفّ باب بلا رقم
    var value: String? = nil
    var valueStyle: ValueStyle = .number
    /// القيمة باهتة: «—» والصفر و«لا أحد بعد»
    var dim: Bool = false
    var titleTint: Color = DS.Color.textPrimary
    var tap: AdminPageTap = .none

    private var spoken: String {
        AdminStatsText.spoken(title, value: value, sub: subtitle, opens: tap.isTappable)
    }

    var body: some View {
        AdminTapWrap(tap: tap, feel: .row, label: AnyView(face), accessibilityLabel: tap.isTappable ? spoken : nil)
    }

    private var face: some View {
        HStack(spacing: DS.Spacing.md) {
            markView
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.body)
                    .foregroundColor(titleTint)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            if let value {
                Text(verbatim: value)
                    .dsFont(valueStyle == .number ? .hubValue : .subtitle)
                    .foregroundColor(dim ? DS.Color.textTertiary : DS.Color.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if tap.isTappable { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? DS.Hub.rowMinHeight : DS.Hub.rowMinHeightTwoLines,
               alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .none:
            EmptyView()
        case .glyph(let symbol, let tint):
            Image(systemName: symbol)
                .dsGlyph(DS.Glyph.md, weight: .medium)
                .foregroundColor(tint)
                .frame(width: DS.Icon.inline)
                .accessibilityHidden(true)
        case .swatch(let tint, let hatched):
            AdminStatsSwatch(tint: tint, hatched: hatched)
        }
    }
}

/// مربّع لون بجانب اسمه — مع «التمييز بدون لون» تظليل ٤٥° لما طُلب له (spec A.11)
struct AdminStatsSwatch: View {
    let tint: Color
    var hatched: Bool = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.chartBarRadius, style: .continuous)
        shape
            .fill(tint)
            .overlay {
                if hatched && noColor {
                    Canvas { context, size in
                        // خطوط مائلة ٤٥° بلون سطح البطاقة — ثلاث في عرض المربّع
                        let step = size.width / 3
                        var path = Path()
                        var x = -size.height
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += step
                        }
                        context.stroke(path, with: .color(DS.Color.cardBackground), lineWidth: DS.Border.width)
                    }
                    .clipShape(shape)
                }
            }
            .frame(width: DS.Hub.chartSwatch, height: DS.Hub.chartSwatch)
            .accessibilityHidden(true)
    }
}

// MARK: - النسبة الواحدة

/// نسبة واحدة من كلّ (spec A.11): شريط ٨ بلون السلسلة فوق درجة أفتح منها، وتحته «لهم حساب 7٪» … «بلا حساب 93٪» ١٣ رمادي
struct AdminStatsMeter: View {
    /// ٠…١٠٠ — nil = مسار فارغ قبل الوصول
    let share: Int?
    let tint: Color
    let track: Color
    let leading: String
    let trailing: String
    /// الجملة للقارئ الصوتي («7 بالمئة لهم حساب»)
    let spoken: String

    var body: some View {
        VStack(spacing: DS.Spacing.xsm) {
            DSMeterBar(progress: share.map { Double($0) / 100 }, tint: tint, track: track)
            HStack(spacing: DS.Spacing.sm) {
                Text(verbatim: leading)
                Spacer(minLength: DS.Spacing.sm)
                Text(verbatim: trailing)
            }
            .dsFont(.subtitle)
            .monospacedDigit()
            .foregroundColor(DS.Color.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - الأعمدة

/// شكل العلامة: طرف البيانات مدوّر والقاعدة مستقيمة (dataviz). `vertical` = عمود يرتفع من القاعدة، وإلا شريط يمتدّ من
/// بداية السطر (يُقلب مع العربية)
struct AdminStatsBarShape: Shape {
    var vertical: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(AdminStatsMetrics.dataEndRadius, vertical ? rect.width / 2 : rect.height / 2, vertical ? rect.height : rect.width)
        var p = Path()
        if vertical {
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// أعمدة الأشهر (spec A.11): العدد ١٣ فوق كل عمود، الشهر ١٣ تحته، الأقدم في البداية (يمين العربية)، لون الحبر الواحد،
/// والصفر بلا عمود. الشهر الشاذّ (`spike`) بجانبه «أغلبه استيراد دفعة واحدة» نحو وسط الرسم — ومن أحجام إمكانية الوصول
/// تحت الرسم. يرتفع مرة عند الظهور الأول، وارتفاع المنطقة ثابت (لا تتمدّد البطاقة)
struct AdminStatsColumns: View {
    let months: [AdminStatsLogic.Month]
    let labels: [String]
    var spike: Int? = nil
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let peak = max(months.map(\.count).max() ?? 1, 1)
        let noteBeside = !typeSize.isAccessibilitySize
        VStack(spacing: DS.Spacing.xs) {
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                    column(month, peak: peak)
                        .overlay(alignment: index * 2 >= months.count ? .topLeading : .topTrailing) {
                            if noteBeside, index == spike { note(towardLeading: index * 2 >= months.count) }
                        }
                }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Chart.columnsAreaHeight, alignment: .bottom)
            AdminRowDivider()
            HStack(spacing: DS.Spacing.sm) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            if !noteBeside, let spike, labels.indices.contains(spike) {
                Text(verbatim: "\(labels[spike]): \(AdminStatsText.spikeNote)")
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true; return }
            withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { shown = true }
        }
    }

    private func column(_ month: AdminStatsLogic.Month, peak: Int) -> some View {
        let full = CGFloat(month.count) / CGFloat(peak) * DS.Chart.columnMaxHeight
        return VStack(spacing: DS.Spacing.xs) {
            Text(verbatim: AdminNumberText.grouped(month.count))
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(month.count == 0 ? DS.Color.textTertiary : DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if month.count > 0 {
                AdminStatsBarShape(vertical: true)
                    .fill(DS.Chart.total)
                    .frame(maxWidth: AdminStatsMetrics.columnMaxWidth)
                    .frame(height: shown || reduceMotion ? max(full, DS.Chart.columnMinHeight) : DS.Chart.columnMinHeight)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// التعليق خارج عموده: نحو البداية (`towardLeading`) أو النهاية — دائماً نحو وسط الرسم
    private func note(towardLeading: Bool) -> some View {
        Text(AdminStatsText.spikeNote)
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(towardLeading ? .trailing : .leading)
            .frame(width: AdminStatsMetrics.spikeNoteWidth, alignment: towardLeading ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .alignmentGuide(.leading) { d in towardLeading ? d[.trailing] + DS.Spacing.xs : d[.leading] }
            .alignmentGuide(.trailing) { d in towardLeading ? d[.trailing] : d[.leading] - DS.Spacing.xs }
    }

    private var spoken: String {
        let values = zip(labels, months).map { "\($0): \(AdminNumberText.grouped($1.count))" }
            .joined(separator: L10n.t("، ", ", "))
        let head = L10n.t("المضافون شهرياً: ", "Added per month: ")
        guard let spike, labels.indices.contains(spike) else { return head + values }
        return head + values + L10n.t(". \(labels[spike]): \(AdminStatsText.spikeNote)", ". \(labels[spike]): \(AdminStatsText.spikeNote)")
    }
}

// MARK: - الأشرطة الأفقية

/// أشرطة الفئات (spec A.11): الاسم في عمود ثابت، الشريط بلون واحد من بداية السطر، والعدد عند طرفه. من أحجام إمكانية الوصول
/// الاسم فوق شريطه
struct AdminStatsBars: View {
    struct Item: Identifiable {
        let id: Int
        let label: String
        let spoken: String
        let value: Int
    }

    let items: [Item]
    var tint: Color = DS.Chart.men
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let peak = max(items.map(\.value).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(items) { item in
                row(item, share: Double(item.value) / Double(peak))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.spoken): \(AdminNumberText.grouped($0.value))" }
            .joined(separator: L10n.t("، ", ", ")))
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true; return }
            withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { shown = true }
        }
    }

    @ViewBuilder
    private func row(_ item: Item, share: Double) -> some View {
        let label = Text(verbatim: item.label)
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textSecondary)
            .lineLimit(2)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                label
                bar(item, share: share)
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                label
                    .minimumScaleFactor(0.8)
                    .frame(width: DS.Chart.barLabelWidth, alignment: .leading)
                bar(item, share: share)
            }
        }
    }

    private func bar(_ item: Item, share: Double) -> some View {
        AdminStatsBarLayout(share: shown || reduceMotion ? share : 0) {
            AdminStatsBarShape(vertical: false)
                .fill(tint)
                .flipsForRightToLeftLayoutDirection(true)
                .frame(height: DS.Chart.barHeight)
                .opacity(item.value == 0 ? 0 : 1)
            Text(verbatim: AdminNumberText.grouped(item.value))
                .dsFont(.subtitle)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// الشريط بنسبته من العرض الباقي بعد رقمه، والرقم ملاصق لطرفه — يُقلب تلقائياً مع العربية
private struct AdminStatsBarLayout: Layout {
    var share: Double

    var animatableData: Double {
        get { share }
        set { share = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let value = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width ?? (value.width + AdminStatsMetrics.barValueGap + DS.Chart.barLabelWidth)
        return CGSize(width: width, height: max(value.height, DS.Chart.barHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let value = subviews[1].sizeThatFits(.unspecified)
        let room = max(0, bounds.width - value.width - AdminStatsMetrics.barValueGap)
        let length = share > 0 ? max(DS.Chart.barMinLength, room * min(max(share, 0), 1)) : 0
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: length, height: DS.Chart.barHeight))
        let valueX = bounds.minX + length + (length > 0 ? AdminStatsMetrics.barValueGap : 0)
        subviews[1].place(at: CGPoint(x: valueX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
    }
}

// MARK: - رقمان متجاوران

/// رقمان في بطاقة واحدة بخط رفيع بينهما (spec C.12 «الشجرة»: صفّ بعمودين لا بطاقتان) — من أحجام إمكانية الوصول فوق بعض
struct AdminStatsDuo: View {
    struct Item: Identifiable {
        let id: Int
        let value: String
        let label: String
    }

    let items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        layout {
            ForEach(items) { item in
                if item.id > 0 {
                    if typeSize.isAccessibilitySize {
                        AdminRowDivider()
                    } else {
                        Rectangle()
                            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke * 2))
                            .frame(width: DS.Border.width / 2)
                            .frame(maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: item.value)
                        .dsFont(.statValue)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textPrimary)
                    Text(item.label)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DS.Spacing.smd)
                .padding(.leading, item.id > 0 && !typeSize.isAccessibilitySize ? DS.Hub.cardPadding : 0)
                .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeightTwoLines, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - آخر الصفحة

/// «آخر تحديث 9:41» — ١٣ رمادي في الوسط (spec A.2)
struct AdminStatsFooter: View {
    let date: Date

    var body: some View {
        Text(AdminStoreHealthText.updated(date))
            .dsFont(.subtitle)
            .foregroundColor(DS.Color.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - «الموافقات» (آخر ٣٠ يوماً)

/// خلاصة `approvals_report` لآخر ٣٠ يوماً — نفس دالة «تقرير الموافقات». حاله `AdminStoreHealth` (Autoplan note 2):
/// الفشل يبقي آخر أرقام وصلت ووقتها، والمرفوض (42501) مخفي بلا إعادة محاولة
@MainActor
final class AdminInsightsApprovalsStore: ObservableObject {
    @Published private(set) var report = ApprovalsReport()
    @Published private(set) var health: AdminStoreHealth = .idle
    /// السيرفر بلا الدالة (لم يُحدَّث) — ملاحظة بلا «أعد المحاولة»
    @Published private(set) var unavailable = false

    static let days = 30

    func load() async {
        health = health.beginning()
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -Self.days, to: now) ?? now
        let iso = DateParsing.isoPlain
        do {
            let result: ApprovalsReport = try await SupabaseConfig.client
                .rpc("approvals_report", params: Params(p_from: iso.string(from: from), p_to: iso.string(from: now)))
                .execute()
                .value
            report = result
            unavailable = false
            health = health.ending(success: true)
        } catch {
            guard !ErrorHelper.isCancellation(error) else {
                if health == .loading { health = .idle }
                return
            }
            let code = (error as? PostgrestError)?.code
            if code == "42501" {
                health = .denied
                return
            }
            Log.warning("[Insights] تعذّر جلب خلاصة الموافقات: \(error)")
            unavailable = code == "PGRST202" || ErrorHelper.description(error).contains("could not find the function")
            health = health.ending(success: false)
        }
    }
}

/// قسم «الموافقات»: «41 طلباً» + شريط مقسّم (ألوان الحال، كل جزء بكلمته وعدده في صفّه) + أكثر ٣ أنواع + «تقرير الموافقات
/// كاملاً ‹» (spec C.12 البند ٩). الحالات: هيكل · خطأ بإعادة المحاولة · ملاحظة «يحتاج تحديث السيرفر» · أرقام قديمة بوقتها
struct AdminInsightsApprovalsCard: View {
    @ObservedObject var store: AdminInsightsApprovalsStore
    let openReport: () -> Void

    private static let topCount = 3

    var body: some View {
        // المرفوض لهذا الدور (42501): لا عنوان ولا بطاقة ولا «أعد المحاولة»
        if store.health.look != .hidden {
            section
        }
    }

    private var section: some View {
        AdminStatsSection(anchor: .approvals) {
            if store.unavailable && !store.health.hasData {
                AdminPageStateCard(.empty(L10n.t("التقرير يحتاج تحديث السيرفر", "The report needs a server update"),
                                          message: L10n.t("تظهر أرقام الموافقات هنا بعد التحديث",
                                                          "Approval numbers appear here after the update")))
            } else {
                switch store.health.look {
                case .hidden:
                    EmptyView()
                case .skeleton:
                    AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الموافقات…", "Loading approvals…"), rows: 3))
                case .unknown:
                    AdminPageStateCard(.error(L10n.t("تعذّر تحميل الموافقات", "Couldn't load approvals"),
                                              message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                              retry: { Task { await store.load() } }))
                case .word:
                    AnyView(content(staleSince: nil))
                case .staleWord(let since):
                    AnyView(content(staleSince: since))
                }
            }
        }
    }

    private var parts: [(id: String, title: String, value: Int, tint: Color)] {
        let t = store.report.totals
        return [("executed", L10n.t("انقبلت", "Approved"), t.executed, DS.Color.success),
                ("rejected", L10n.t("انرفضت", "Rejected"), t.rejected, DS.Color.error),
                ("pending", L10n.t("تنتظر", "Waiting"), t.pending, DS.Color.slate)]
    }

    private var topTypes: [ApprovalsReport.TypeRow] {
        Array(store.report.types.filter { $0.count > 0 }.sorted { $0.count > $1.count }.prefix(Self.topCount))
    }

    private func content(staleSince: Date?) -> some View {
        let parts = self.parts
        let total = parts.reduce(0) { $0 + $1.value }
        let top = topTypes
        return AdminStatsCard {
            AdminStatsHeadline(title: AdminStatsText.requests(total))
                .adminStatsBlock(top: true, bottom: total == 0)
            if total > 0 {
                DSMeterBar(parts: DSGaugePart.counts(parts.map { (id: $0.id, value: $0.value, tint: $0.tint) }), track: DS.Ring.emptyTrack)
                    .padding(.bottom, DS.Spacing.sm)
                    .accessibilityHidden(true)
                ForEach(parts, id: \.id) { part in
                    AdminRowDivider()
                    AdminStatsRow(title: part.title, mark: .swatch(part.tint, hatched: false),
                                  value: AdminNumberText.grouped(part.value), dim: part.value == 0)
                }
            }
            if !top.isEmpty {
                AdminRowDivider()
                Text(L10n.t("أكثر الطلبات", "Top requests"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.top, DS.Spacing.sm)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(top.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { AdminRowDivider() }
                    AdminStatsRow(title: ApprovalTypeTitle.title(row.type), value: AdminNumberText.grouped(row.count))
                }
            }
            AdminRowDivider()
            AdminStatsRow(title: L10n.t("تقرير الموافقات كاملاً", "Full approvals report"),
                          titleTint: DS.Color.primary, tap: .action(openReport))
            if let staleSince {
                AdminStaleStamp(since: staleSince)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DS.Spacing.sm)
            }
        }
    }
}
