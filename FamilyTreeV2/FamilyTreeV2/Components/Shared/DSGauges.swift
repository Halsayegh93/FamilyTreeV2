import SwiftUI

// MARK: - المؤشرات الموحّدة (الدفعة ١٠ «وحّد شكلها كلها» — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// كل مؤشر/نسبة في لوحة الإدارة بشكل واحد = حلقة «إحصاء الأفراد» (الدفعة ٩):
// - `DSRingGauge`: حلقة بمقاسات `DS.Ring` (مصغّرة · صغيرة · متوسطة · كبيرة) تبدأ من أعلى وتدور مع عقارب الساعة في الاتجاهين،
//   جزء واحد فوق مسار (الباقي خافت) أو أجزاء ملوّنة (توزيع ٢–٣)، والرقم في الوسط بخط المقاس ويعدّ من الصفر.
// - `DSGaugeRow`: الحلقة بجانب عنوان وسطر (صفّ النسبة)، و`DSRingValue`: حلقة مصغّرة بجانب رقم (مربّعات الرأس والصفوف).
// - `DSMeterBar`: الشريط الواحد حيث الحلقة خطأ (خطّ زمني، توزيع ٤ أجزاء فأكثر، مقارنة أطوال) — سُمك الحلقة المتوسطة
//   وألوانها ومسارها وحركتها؛ و`DSGaugeLegend`: مفتاح واحد (نقطة اللون + الاسم + العدد).
// الحركة (`DS.Ring`): مرة عند الظهور الأول أو عند وصول الأرقام، ٠٫٧ ث تباطؤ — الحلقة تمتلئ والرقم يعدّ معاً؛ بعدها تتبدّل
// بلا حركة إلا إن تغيّرت القيمة تغيّراً واضحاً. «تقليل الحركة»: ثابتة فوراً. لا مؤقّت ولا `TimelineView`: إطارات الحركة
// من SwiftUI أثناءها فقط، وفي السكون لا إعادة رسم.

/// جزء من حلقة أو شريط: نسبته (٠…١ من الدائرة/العرض) ولونه
struct DSGaugePart: Equatable, Identifiable {
    let id: String
    let share: Double
    let tint: Color

    init(_ id: String, share: Double, tint: Color) {
        self.id = id
        self.share = max(0, min(1, share.isFinite ? share : 0))
        self.tint = tint
    }

    /// أجزاء من أعداد تملأ الدائرة/العرض كاملاً (الأصفار تُتخطّى) — nil إن لم يكن فيها شيء
    static func counts(_ items: [(id: String, value: Int, tint: Color)]) -> [DSGaugePart]? {
        let total = items.reduce(0) { $0 + max(0, $1.value) }
        guard total > 0 else { return nil }
        return items.filter { $0.value > 0 }.map { DSGaugePart($0.id, share: Double($0.value) / Double(total), tint: $0.tint) }
    }
}

/// ما في وسط الحلقة: عدد أو نسبة تعدّ من الصفر («—» قبل وصولها)
enum DSGaugeCenter: Equatable {
    case none
    case count(Int?)
    case percent(Int?)

    var number: Int? {
        switch self {
        case .none: return nil
        case .count(let n), .percent(let n): return n
        }
    }

    var isPercent: Bool { if case .percent = self { return true } else { return false } }
}

/// «انتظر»: الحلقات والأرقام داخلها ساكنة فارغة حتى يصير `false` ثم تمتلئ وتعدّ — لصفحة غير ظاهرة بعد (الصفحة الثانية في
/// «المربّع اللي ينسحب»)
private struct DSGaugeHoldKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var dsGaugeHold: Bool {
        get { self[DSGaugeHoldKey.self] }
        set { self[DSGaugeHoldKey.self] = newValue }
    }
}

/// نصوص المؤشرات المشتركة
enum DSGaugeText {
    /// «73٪» / «73%»
    static func percent(_ n: Int) -> String { L10n.t("\(n)٪", "\(n)%") }

    static func value(_ n: Int?, percent: Bool) -> String {
        guard let n else { return "—" }
        return percent ? self.percent(n) : "\(n)"
    }

    /// نسبة صحيحة (تقريب لأسفل — لا تعرض ١٠٠٪ قبل أن تكتمل)
    static func share(_ part: Int, of total: Int) -> Int? {
        guard total > 0 else { return nil }
        return Int((Double(part) / Double(total) * 100).rounded(.down))
    }
}

// MARK: - الحلقة

/// الحلقة الموحّدة — المقاس من `DS.Ring`، والقارئ الصوتي يقرأ ما بجانبها (الحلقة نفسها مخفية عنه)
struct DSRingGauge: View {
    /// nil = لم تصل الأرقام (مسار فارغ و«—»)
    let parts: [DSGaugePart]?
    var size: DS.Ring.Size = DS.Ring.medium
    /// المسار تحت الأجزاء — nil = لون الجزء الأول خافتاً
    var track: Color? = nil
    var center: DSGaugeCenter = .none
    /// كلمة تحت الرقم («أحياء»، «قبول») — في المتوسطة والكبيرة فقط
    var caption: String? = nil
    var ink: Color = DS.Color.textPrimary
    var captionInk: Color = DS.Color.textSecondary
    /// ما يقرؤه القارئ الصوتي — nil = الحلقة مخفية عنه (يقرأ ما بجانبها)
    var spoken: String? = nil

    init(parts: [DSGaugePart]?, size: DS.Ring.Size = DS.Ring.medium, track: Color? = nil,
         center: DSGaugeCenter = .none, caption: String? = nil,
         ink: Color = DS.Color.textPrimary, captionInk: Color = DS.Color.textSecondary, spoken: String? = nil) {
        self.parts = parts
        self.size = size
        self.track = track
        self.center = center
        self.caption = caption
        self.ink = ink
        self.captionInk = captionInk
        self.spoken = spoken
    }

    /// جزء واحد (٠…١) بلون الحال فوق مساره — nil = لم تصل
    init(progress: Double?, tint: Color, size: DS.Ring.Size = DS.Ring.medium, track: Color? = nil,
         center: DSGaugeCenter = .none, caption: String? = nil,
         ink: Color = DS.Color.textPrimary, captionInk: Color = DS.Color.textSecondary, spoken: String? = nil) {
        self.init(parts: progress.map { [DSGaugePart("p", share: $0, tint: tint)] }, size: size,
                  track: track ?? tint.opacity(DS.Opacity.tintFill), center: center, caption: caption,
                  ink: ink, captionInk: captionInk, spoken: spoken)
    }

    @State private var drawn: [DSGaugePart] = []
    @State private var reveal: Double = 0
    @State private var revealed = false
    @State private var number: Double = 0
    @State private var counted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsGaugeHold) private var hold

    private var trackColor: Color {
        guard parts != nil else { return DS.Ring.emptyTrack }
        return track ?? (parts?.first?.tint.opacity(DS.Opacity.tintFill) ?? DS.Ring.emptyTrack)
    }

    var body: some View {
        ZStack {
            DSRingArcs(parts: drawn, reveal: reveal, line: size.line, side: size.side, track: trackColor)
            if let role = size.value, center != .none {
                VStack(spacing: 0) {
                    EmptyView()
                        .modifier(DSCountUpText(value: number, known: center.number != nil, percent: center.isPercent))
                        .dsFont(role)
                        .monospacedDigit()
                        .foregroundColor(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    // من أحجام إمكانية الوصول: الرقم وحده (الكلمة لا تتّسع — الاسم بجانب الحلقة)
                    if let caption, let captionRole = size.caption, !typeSize.isAccessibilitySize {
                        Text(caption)
                            .dsFont(captionRole)
                            .foregroundColor(captionInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, size.line + DS.Spacing.xxs)
            }
        }
        .frame(width: size.side, height: size.side)
        .onAppear { appear(held: hold) }
        .onChange(of: parts) { update($0) }
        .onChange(of: center.number) { count($0) }
        // القيمة الجديدة صراحةً — داخل `onChange` قد تكون خصائص البيئة من الرسم السابق
        .onChange(of: hold) { if !$0 { appear(held: false) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? "")
        .accessibilityHidden(spoken == nil)
    }

    private func appear(held: Bool) {
        guard !held else { return }
        if !revealed, let parts { show(parts) }
        if !counted, let n = center.number { countFirst(n) }
    }

    /// أول ظهور للأرقام: الأجزاء كما هي، ثم تمتلئ من الصفر
    private func show(_ parts: [DSGaugePart]) {
        revealed = true
        DSGaugeMotion.snap { drawn = parts; reveal = reduceMotion ? 1 : 0 }
        guard !reduceMotion else { return }
        withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { reveal = 1 }
    }

    private func update(_ new: [DSGaugePart]?) {
        guard let new else {
            DSGaugeMotion.snap { drawn = []; reveal = 0; revealed = false }
            return
        }
        guard revealed else { if !hold { show(new) }; return }
        if !reduceMotion && DSGaugeMotion.isNotable(drawn, new) {
            withAnimation(DS.Ring.change) { drawn = new }
        } else {
            DSGaugeMotion.snap { drawn = new }
        }
    }

    private func countFirst(_ n: Int) {
        counted = true
        DSGaugeMotion.snap { number = reduceMotion ? Double(n) : 0 }
        guard !reduceMotion else { return }
        withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { number = Double(n) }
    }

    private func count(_ new: Int?) {
        guard let new else { DSGaugeMotion.snap { number = 0; counted = false }; return }
        guard counted else { if !hold { countFirst(new) }; return }
        if !reduceMotion && DSGaugeMotion.isNotable(number, Double(new)) {
            withAnimation(DS.Ring.change) { number = Double(new) }
        } else {
            DSGaugeMotion.snap { number = Double(new) }
        }
    }
}

/// رسم الحلقة: المسار ثم الأجزاء من أعلى مع عقارب الساعة (الاتجاه ثابت في العربية أيضاً) — طرف مستدير للجزء الواحد،
/// ومقطوع بفراغ صغير بين الأجزاء
struct DSRingArcs: View {
    let parts: [DSGaugePart]
    let reveal: Double
    let line: CGFloat
    let side: CGFloat
    let track: Color

    var body: some View {
        let many = parts.count > 1
        let spans = DSGaugeSpans.make(parts, gap: many ? DS.Ring.segmentGap / (CGFloat.pi * max(side - line, 1)) : 0)
        ZStack {
            Circle()
                .stroke(track, lineWidth: line)
            ForEach(spans) { span in
                Circle()
                    .trim(from: span.from * reveal, to: span.to * reveal)
                    .stroke(span.tint, style: StrokeStyle(lineWidth: line, lineCap: many ? .butt : .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        // تبدأ من أعلى وتدور مع عقارب الساعة في الاتجاهين
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// بداية ونهاية كل جزء على الدائرة/العرض (٠…١) بعد الفراغ بين الأجزاء
struct DSGaugeSpans {
    struct Span: Identifiable {
        let id: String
        let from: Double
        let to: Double
        let tint: Color
    }

    static func make(_ parts: [DSGaugePart], gap: Double) -> [Span] {
        var start = 0.0
        var spans: [Span] = []
        for part in parts where part.share > 0 {
            let end = min(1, start + part.share)
            let inset = end - start > gap * 2 ? gap / 2 : 0
            spans.append(Span(id: part.id, from: start + inset, to: end - inset, tint: part.tint))
            start = end
        }
        return spans
    }
}

/// الرقم يعدّ: نصّ يُبنى من قيمة تتحرّك (SwiftUI يمرّر القيم الوسيطة أثناء الحركة فقط)
struct DSCountUpText: ViewModifier, Animatable {
    var value: Double
    let known: Bool
    let percent: Bool

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(verbatim: known ? DSGaugeText.value(Int(value.rounded()), percent: percent) : "—")
    }
}

/// قواعد الحركة المشتركة: ماذا يُعدّ تغيّراً واضحاً، والتبديل بلا حركة
enum DSGaugeMotion {
    static func isNotable(_ old: Double, _ new: Double) -> Bool {
        guard old != 0 else { return new != 0 }
        return abs(new - old) / abs(old) >= DS.Ring.notableCount
    }

    static func isNotable(_ old: [DSGaugePart], _ new: [DSGaugePart]) -> Bool {
        guard old.map(\.id) == new.map(\.id) else { return true }
        var a = 0.0, b = 0.0
        for (o, n) in zip(old, new) {
            a += o.share
            b += n.share
            if abs(a - b) >= DS.Ring.notableShare { return true }
        }
        return false
    }

    /// تغيير بلا حركة (ولا يرث حركة من حوله — «اليوم» يحدّث أرقامه داخل `withAnimation`)
    static func snap(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }
}

// MARK: - الرقم الذي يعدّ وحده

/// رقم يعدّ من الصفر عند ظهوره الأول (وعند وصوله بعد «—»)، ثم يتبدّل بلا حركة إلا لتغيّر واضح — أرقام «يحتاج انتباهك».
/// الخط واللون من حوله (`dsFont`/`foregroundColor`)
struct DSCountText: View {
    let value: Int?
    var percent: Bool = false
    @State private var shown: Double = 0
    @State private var counted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        EmptyView()
            .modifier(DSCountUpText(value: shown, known: value != nil, percent: percent))
            .onAppear { if !counted, let value { first(value) } }
            .onChange(of: value) { change($0) }
    }

    private func first(_ n: Int) {
        counted = true
        DSGaugeMotion.snap { shown = reduceMotion ? Double(n) : 0 }
        guard !reduceMotion else { return }
        withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { shown = Double(n) }
    }

    private func change(_ new: Int?) {
        guard let new else { DSGaugeMotion.snap { shown = 0; counted = false }; return }
        guard counted else { first(new); return }
        if !reduceMotion && DSGaugeMotion.isNotable(shown, Double(new)) {
            withAnimation(DS.Ring.change) { shown = Double(new) }
        } else {
            DSGaugeMotion.snap { shown = Double(new) }
        }
    }
}

// MARK: - صفّ النسبة

/// الحلقة بجانب عنوان وسطر (اكتمال البيانات، سلامة الشجرة، تسجيل الأجهزة، المسجّلون، نوع في تقرير الموافقات).
/// القارئ الصوتي يقرأ `spoken` (أو العنوان والسطر) مرة واحدة
struct DSGaugeRow: View {
    let gauge: DSRingGauge
    let title: String
    var subtitle: String? = nil
    var titleInk: Color = DS.Color.textPrimary
    var spoken: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // من أحجام إمكانية الوصول: الحلقة فوق النص (النص بعرض البطاقة كله)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: DS.Spacing.md))
        layout {
            gauge
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(titleInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .dsFont(.footnote)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? [title, subtitle].compactMap { $0 }.joined(separator: L10n.t("، ", ", ")))
    }
}

/// حلقة مصغّرة بجانب رقم أو نسبة (مربّع رقم في الرأس، قيمة في طرف صفّ، مربّع إحصاء) — `text` = القيمة بجانبها بخط
/// الشريحة ولون الحال
struct DSRingValue: View {
    let progress: Double?
    let tint: Color
    var track: Color? = nil
    var text: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            DSRingGauge(progress: progress, tint: tint, size: DS.Ring.mini, track: track)
            if let text {
                Text(verbatim: text)
                    .dsFont(.chip)
                    .monospacedDigit()
                    .foregroundColor(tint.dsReadableGlyph)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - الشريط

/// الشريط الموحّد (حيث الحلقة خطأ): جزء أو أجزاء من بداية السطر فوق مسار — سُمك الحلقة المتوسطة، ويمتلئ مثلها
struct DSMeterBar: View {
    /// nil = لم تصل الأرقام (مسار فارغ)
    let parts: [DSGaugePart]?
    var track: Color? = nil
    var height: CGFloat = DS.Ring.barHeight

    @State private var drawn: [DSGaugePart] = []
    @State private var reveal: Double = 0
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(parts: [DSGaugePart]?, track: Color? = nil, height: CGFloat = DS.Ring.barHeight) {
        self.parts = parts
        self.track = track
        self.height = height
    }

    /// جزء واحد (٠…١)
    init(progress: Double?, tint: Color, track: Color? = nil, height: CGFloat = DS.Ring.barHeight) {
        self.init(parts: progress.map { [DSGaugePart("p", share: $0, tint: tint)] },
                  track: track ?? tint.opacity(DS.Opacity.tintFill), height: height)
    }

    var body: some View {
        let visible = drawn.filter { $0.share > 0 }
        let gap = visible.count > 1 ? DS.Ring.segmentGap : 0
        GeometryReader { geo in
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, visible.count - 1)))
            HStack(spacing: gap) {
                ForEach(visible) { part in
                    Capsule()
                        .fill(part.tint)
                        .frame(width: max(0, min(usable, max(height, usable * part.share)) * reveal))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Capsule().fill(parts == nil ? DS.Ring.emptyTrack : (track ?? DS.Ring.emptyTrack)))
        .clipShape(Capsule())
        .onAppear { if !revealed, let parts { show(parts) } }
        .onChange(of: parts) { update($0) }
        .accessibilityHidden(true)
    }

    private func show(_ parts: [DSGaugePart]) {
        revealed = true
        DSGaugeMotion.snap { drawn = parts; reveal = reduceMotion ? 1 : 0 }
        guard !reduceMotion else { return }
        withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { reveal = 1 }
    }

    private func update(_ new: [DSGaugePart]?) {
        guard let new else { DSGaugeMotion.snap { drawn = []; reveal = 0; revealed = false }; return }
        guard revealed else { show(new); return }
        if !reduceMotion && DSGaugeMotion.isNotable(drawn, new) {
            withAnimation(DS.Ring.change) { drawn = new }
        } else {
            DSGaugeMotion.snap { drawn = new }
        }
    }
}

// MARK: - المفتاح

/// مفتاح الحلقة/الشريط: نقطة اللون + الاسم + العدد بخط صغير، عمودان (أو عمود واحد بجانب حلقة) ويلتفّ الاسم
struct DSGaugeLegend: View {
    struct Item: Identifiable {
        let id: String
        let label: String
        let value: String
        let tint: Color

        init(_ id: String, _ label: String, _ value: String, tint: Color) {
            self.id = id
            self.label = label
            self.value = value
            self.tint = tint
        }
    }

    let items: [Item]
    var columns: Int = 2

    var body: some View {
        let grid = Array(repeating: GridItem(.flexible(), alignment: .leading), count: max(1, columns))
        LazyVGrid(columns: grid, alignment: .leading, spacing: DS.Spacing.xs) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Circle()
                        .fill(item.tint)
                        .frame(width: DS.Icon.legendDotCompact, height: DS.Icon.legendDotCompact)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(item.label) \(item.value)")
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
