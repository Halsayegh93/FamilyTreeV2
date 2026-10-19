import SwiftUI

// MARK: - FTKit — «الشعار المصمت» (الأسلوب النهائي للرسوم، ٢٠٢٦-١٠-٠٥)
//
// القاعدة: لكل مكان شعار واحد مصمت بمستوى أيقونة تطبيق — أبيض بدرجتين فقط (جسم + حزام) فوق الألوان،
// أو بلون القسم فوق الأسطح الفاتحة — وتفاصيله فراغات مقصوصة، ولمسة ذهبية واحدة ذات معنى.
// الحركة: تنفّس واحد للشعار كله (٨ ث) + حركة واحدة للّمسة الذهبية فقط (دورتها تقسم ٨). لا غير.
//
// قواعد صارمة:
// • GraphicsContext فقط (لا صور ولا رموز SF داخل الرسم — الاستثناء الوحيد: علامة الرأس/الصفحة العامة
//   `drawSymbolMark` / `drawSymbolPlate`، لأن هوية المربّع هي رمزه).
// • iOS 16: لا Path.subtracting/union… — القصّ بطبقة + `.destinationOut` (`FTKit.eraser`).
// • كل رسم دالة نقية في t: بلا Date() ولا عشوائية. t = 0 لوحة ساكنة كاملة (تقليل الحركة).
// • لا blur في الإطار: التوهّج تدرّج شعاعي (`FTKit.glow`). ≤ ٦٠ عملية تعبئة/خط في الإطار.
// • ملف SwiftUI فقط بلا أنواع التطبيق. كل ما يُصدَّر يبدأ بـ FT، والمساعدات fileprivate.

nonisolated enum FTKit {

    // MARK: الإيقاع

    /// الدورة الكبرى الوحيدة في التطبيق كله — كل دورة أخرى يجب أن تقسمها
    static let loop: Double = 8
    /// الدورات المسموحة فقط (تقسم ٨ ← الحلقة تلتئم بلا قفزة)
    static let periods: [Double] = [8, 4, 2]
    /// معدّل الإطارات للحلقات الهادئة
    static let frameRate: Double = 30
    /// الظهور الأول (مرة واحدة): يتلاشى للداخل ويرتفع ٦ نقاط
    static let emergeDuration: Double = 0.9
    static let emergeRise: CGFloat = 6
    /// لحظات النجاح (مرة واحدة ثم سكون على الإطار الأخير)
    static let momentDuration: Double = 1.2
    /// تأخير الشعار في رأس المربّع حتى يكبر المربّع أولاً
    static let headerMarkDelay: Double = 0.25

    // MARK: الألوان

    /// الذهبي — اللون الوحيد داخل الرسوم فوق الألوان والوضع الداكن
    static let gold = FTK.rgb(0xF4C86A)
    /// ذهبي الأسطح الفاتحة (≥ ٣:١ على الأبيض كعنصر رسومي)
    static let goldOnLight = FTK.rgb(0xB8862B)
    /// لمعة كريمية — مسموحة فوق الذهبي فقط
    static let glint = FTK.rgb(0xFFF4DC)
    /// رمادي «وفاة» — ساكن دائماً، لا ذهبي ولا حركة
    static let mourning = FTK.rgb(0x8E8E93)

    /// ألوان الأقسام المرجعية (البحرية) — التطبيق يستعمل ألوانه هو؛ هذه للمعاينات والتوثيق
    nonisolated enum Section: CaseIterable {
        case home, tree, diwaniyas, profile, admin, library, projects, contact
        var color: Color {
            switch self {
            case .home: return FTK.rgb(0x1F4E79)
            case .tree: return FTK.rgb(0x1E5950)
            case .diwaniyas: return FTK.rgb(0x1E5665)
            case .profile: return FTK.rgb(0x334C81)
            case .admin, .contact: return FTK.rgb(0x47467F)
            case .library: return FTK.rgb(0x633C6F)
            case .projects: return FTK.rgb(0x275B35)
            }
        }
    }

    /// ألوان وقت التحية (الحبر) — فاتح/داكن
    static func timeAccent(_ mood: Mood, dark: Bool) -> Color {
        switch mood {
        case .morning: return dark ? FTK.rgb(0x6FB394) : FTK.rgb(0x2E6B4F)
        case .afternoon: return dark ? FTK.rgb(0x7FA8D6) : FTK.rgb(0x1F4E79)
        case .evening: return dark ? FTK.rgb(0xD4B062) : FTK.rgb(0xA07A2C)
        }
    }

    /// وقت التحية — صباح ٤–١٢ · ظهر ١٢–١٧ · مساء غير ذلك (كما في HomeGreetingRow)
    nonisolated enum Mood {
        case morning, afternoon, evening
        static func forHour(_ h: Int) -> Mood {
            if (4..<12).contains(h) { return .morning }
            if (12..<17).contains(h) { return .afternoon }
            return .evening
        }
    }

    // MARK: درجات الأسطح

    /// أين يُرسم الشعار — يحدّد شفافية الدرجتين والذهبي والتوهّج
    nonisolated enum Surface {
        /// مربّعات الرئيسية الملوّنة
        case tile
        /// شريط رأس المربّعات الوسطى (٨٦ نقطة) — أهدأ لأن العنوان على نفس الشريط
        case header
        /// خلفية شاشة كاملة (الدخول) — شبه غائبة
        case backdrop
        /// سطح فاتح/داكن محايد (الصفحات الفاضية، الانتظار، الإشعارات، تحميل الشجرة) — بلون القسم
        case light
        /// رمز صغير ≤ ٢٤ نقطة (التحية، الشارات) — حبر كامل
        case glyph
    }

    /// الشفافيات: body = الجسم، band = الدرجة الثانية والأخيرة، gold = اللمسة، glow → glowPeak = التوهّج
    nonisolated struct Tones: Equatable {
        let body: Double
        let band: Double
        let gold: Double
        let glow: Double
        let glowPeak: Double
        /// قرص خلفي (الأسطح الفاتحة فقط)
        let plate: Double
    }

    static func tones(_ surface: Surface, dark: Bool = false) -> Tones {
        switch surface {
        case .tile:     return Tones(body: 0.19, band: 0.32, gold: 0.90, glow: 0.075, glowPeak: 0.10, plate: 0)
        case .header:   return Tones(body: 0.11, band: 0.19, gold: 0.80, glow: 0.06, glowPeak: 0.08, plate: 0)
        case .backdrop: return Tones(body: 0.05, band: 0.08, gold: 0.40, glow: 0.05, glowPeak: 0.07, plate: 0)
        case .light:
            return dark ? Tones(body: 0.24, band: 0.50, gold: 1.0, glow: 0.10, glowPeak: 0.14, plate: 0.14)
                        : Tones(body: 0.18, band: 0.40, gold: 1.0, glow: 0.07, glowPeak: 0.10, plate: 0.08)
        case .glyph:    return Tones(body: 1.0, band: 0.85, gold: 1.0, glow: 0, glowPeak: 0, plate: 0)
        }
    }

    /// لوحة جاهزة لمكان: الحبر (أبيض فوق الألوان، لون القسم فوق الفاتح) + الدرجات + الذهبي المناسب
    nonisolated struct Palette {
        let ink: Color
        let tones: Tones
        let gold: Color
        let glint: Color
        /// للأشكال المنفردة فقط — الأشكال المتراكبة تُرسم داخل `FTKit.tone` بحبر معتم
        var body: Color { ink.opacity(tones.body) }
        var band: Color { ink.opacity(tones.band) }
        var goldFill: Color { gold.opacity(tones.gold) }
    }

    /// `tint` = لون القسم (للسطح الفاتح) أو لون الوقت (للرمز الصغير). فوق الألوان الحبر أبيض دائماً.
    static func palette(_ surface: Surface, tint: Color? = nil, dark: Bool = false) -> Palette {
        let t = tones(surface, dark: dark)
        switch surface {
        case .tile, .header, .backdrop:
            return Palette(ink: .white, tones: t, gold: gold, glint: glint)
        case .light, .glyph:
            return Palette(ink: tint ?? .primary, tones: t, gold: dark ? gold : goldOnLight, glint: glint)
        }
    }

    // MARK: الطبقات والقصّ

    /// درجة واحدة مسطّحة: ارسم الأشكال معتمة داخلها، فتُركَّب الطبقة كلها مرة واحدة بالشفافية
    /// (التراكب لا يغمّق). الشفافية تُضرب في شفافية السياق (فيعمل مع تلاشي الظهور).
    static func tone(_ ctx: inout GraphicsContext, opacity: Double, _ draw: (inout GraphicsContext) -> Void) {
        var g = ctx
        g.opacity *= opacity
        g.drawLayer { layer in draw(&layer) }
    }

    /// نسخة من سياق الطبقة تمحو بدل أن ترسم — ارسم بها الفراغات (الفواصل، النوافذ، الأسطر)
    static func eraser(_ layer: GraphicsContext) -> GraphicsContext {
        var c = layer
        c.blendMode = .destinationOut
        c.opacity = 1
        return c
    }

    // MARK: التوهّج والنقطة الذهبية

    /// توهّج = تدرّج شعاعي واحد (لا blur)
    static func glow(_ ctx: inout GraphicsContext, at c: CGPoint, radius r: CGFloat, color: Color = .white, opacity: Double) {
        guard r > 0, opacity > 0 else { return }
        let g = Gradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.42), location: 0.38),
            .init(color: color.opacity(0), location: 1)
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(g, center: c, startRadius: 0, endRadius: r))
    }

    /// «نقطة ضوء» ذهبية: توهّج + قلب. `intensity` ٠…١ يتحكّم في التوهّج فقط (القلب ثابت).
    static func goldPoint(_ ctx: inout GraphicsContext, at c: CGPoint, core: CGFloat = 2.2, glowRadius: CGFloat = 8,
                          intensity: Double = 1, gold: Color = FTKit.gold) {
        glow(&ctx, at: c, radius: glowRadius, color: gold, opacity: 0.55 * max(0, min(1, intensity)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: 2 * core, height: 2 * core)),
                 with: .color(gold))
    }

    // MARK: الخطوط

    /// كل الخطوط بأطراف ووصلات مستديرة. الأوزان بوحدات شبكة الشعار (١٠٠) إلا ما ذُكر.
    nonisolated enum Stroke {
        static func round(_ width: CGFloat) -> StrokeStyle {
            StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        }
        /// مقبض الدلّة/السلّة/الحقيبة — شبكة ١٠٠
        static let handle = round(4.6)
        /// خيط القهوة/الضوء — نقاط حقيقية (يُرسم خارج تحويل الشبكة أو يُقسم على المقياس)
        static let stream = round(2.3)
        /// أشعة رموز التحية — شبكة ٢٠
        static let ray = round(1.7)
        /// خط الأرض الشعري — الأسطح الفاتحة فقط
        static let hair = round(1)
        /// عرض الفاصل المقصوص بين أجزاء الشعار — شبكة ١٠٠ (≈ ١ نقطة على المربّع)
        static let gap: CGFloat = 1.4
    }

    // MARK: الزمن والتسهيل

    /// يطوي الزمن عند مضاعف للدورة (كل ساعة) حتى لا تفقد الأرقام دقّتها — الحلقة لا تقفز
    static func fold(_ elapsed: Double, loop: Double = FTKit.loop) -> Double {
        max(0, elapsed).truncatingRemainder(dividingBy: loop * 450)
    }

    /// الطور ٠…<١ داخل الدورة
    static func phase(_ t: Double, period: Double = loop) -> Double {
        let p = t / period
        return p - floor(p)
    }

    /// الثواني داخل الدورة
    static func local(_ t: Double, period: Double = loop) -> Double { phase(t, period: period) * period }

    /// تنفّس ٠ → ١ → ٠ بجيب التمام — ٠ عند t = 0، هادئ في الطرفين
    static func breath(_ t: Double, period: Double = loop) -> Double {
        (1 - cos(2 * .pi * t / period)) / 2
    }

    /// موجة −١…١ — ٠ عند t = 0 (للتمايل)
    static func sway(_ t: Double, period: Double = loop) -> Double { sin(2 * .pi * t / period) }

    nonisolated enum Ease {
        case linear, smooth, smoother, outCubic, inOutSine
        func callAsFunction(_ x: Double) -> Double {
            let u = min(1, max(0, x))
            switch self {
            case .linear: return u
            case .smooth: return u * u * (3 - 2 * u)
            case .smoother: return u * u * u * (u * (u * 6 - 15) + 10)
            case .outCubic: return 1 - pow(1 - u, 3)
            case .inOutSine: return (1 - cos(.pi * u)) / 2
            }
        }
    }

    /// تقدّم مسهَّل بين a وb (خارجهما ٠ أو ١)
    static func progress(_ x: Double, _ a: Double, _ b: Double, _ ease: Ease = .smooth) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        return ease((x - a) / (b - a))
    }

    /// نافذة داخل الدورة: ٠ قبل `from`، يصعد حتى ١ عند `to`، ويبقى ١ حتى نهاية الدورة
    static func window(_ t: Double, from: Double, to: Double, period: Double = loop, ease: Ease = .smooth) -> Double {
        progress(local(t, period: period), from, to, ease)
    }

    /// غلاف ٠ → ١ → ٠ داخل الدورة (صعود، ثبات، هبوط). إن كان `start` > ٠ فهو ٠ عند t = 0.
    static func beat(_ t: Double, start: Double, rise: Double, hold: Double = 0, fall: Double,
                     period: Double = loop, ease: Ease = .smooth) -> Double {
        let x = local(t, period: period)
        let up = progress(x, start, start + rise, ease)
        let down = progress(x, start + rise + hold, start + rise + hold + fall, ease)
        return up * (1 - down)
    }

    /// مقدار التنفّس: ارتفاع (نقاط)، تكبير (نسبة)، ميل (درجات)
    nonisolated struct BreathAmount {
        let rise: CGFloat
        let scale: CGFloat
        let tilt: Double
        /// الشعارات (المربّعات، الرؤوس، الصفحات الفاضية)
        static let standard = BreathAmount(rise: 2, scale: 0.014, tilt: 1.5)
        /// رمز صغير ≤ ٢٤ نقطة — ميل فقط تقريباً
        static let glyph = BreathAmount(rise: 0.6, scale: 0, tilt: 4)
        /// الخلفيات الكاملة — يكاد لا يُرى
        static let faint = BreathAmount(rise: 1, scale: 0.006, tilt: 0)
    }

    /// الحركة الأساسية الوحيدة: يرفع الشعار ويكبّره ويميله قليلاً حول `anchor` (٨ ث)
    static func applyBreath(_ ctx: inout GraphicsContext, anchor: CGPoint, t: Double,
                            amount: BreathAmount = .standard, period: Double = loop) {
        let b = breath(t, period: period)
        ctx.translateBy(x: anchor.x, y: anchor.y - amount.rise * CGFloat(b))
        if amount.tilt != 0 { ctx.rotate(by: .degrees(amount.tilt * b)) }
        let k = 1 + amount.scale * CGFloat(b)
        if k != 1 { ctx.scaleBy(x: k, y: k) }
        ctx.translateBy(x: -anchor.x, y: -anchor.y)
    }

    /// الظهور الأول (مرة واحدة): (الشفافية، الإزاحة الرأسية) عند الزمن المنقضي
    static func emerge(_ elapsed: Double) -> (opacity: Double, dy: CGFloat) {
        let e = Ease.outCubic(elapsed / emergeDuration)
        return (e, emergeRise * CGFloat(1 - e))
    }

    // MARK: المواضع (المساحات المحجوزة للشعار)

    /// يعكس السياق أفقياً في الإنجليزية — الشعار دائماً في الجهة المقابلة للعنوان
    static func mirrorForLTR(_ ctx: inout GraphicsContext, width: CGFloat) {
        if ctx.environment.layoutDirection == .leftToRight {
            ctx.translateBy(x: width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
    }

    /// مربّع الشعار في مربّعات الرئيسية (إحداثيات عربية: الجهة اليسرى، بعيداً عن الأيقونة والعنوان).
    /// العريض (≥ ١٫٥) ارتفاعه ٧٨٪ ووسطه ٣٠٪؛ الضيّق (٣ أعمدة) ٦٤٪ ووسطه ٢٨٪ ويُسمح أن يخرج ٨٪ من الحافة.
    static func tileSlot(_ size: CGSize) -> CGRect {
        let wide = size.width / max(1, size.height) >= 1.5
        let h = size.height * (wide ? 0.78 : 0.64)
        let cx = size.width * (wide ? 0.30 : 0.28)
        let cy = size.height * (wide ? 0.53 : 0.50)
        return CGRect(x: cx - h / 2, y: cy - h / 2, width: h, height: h)
    }

    /// مربّع الشعار في رأس المربّع الأوسط: ٨٠٪ من الارتفاع، وسطه على بعد ٦٦ نقطة من الحافة المقابلة للعنوان
    static func headerSlot(_ size: CGSize, rtl: Bool = true) -> CGRect {
        let h = size.height * 0.80
        let cx = rtl ? 66 : size.width - 66
        let cy = size.height * 0.54
        return CGRect(x: cx - h / 2, y: cy - h / 2, width: h, height: h)
    }

    /// مربّع في الوسط (الصفحات الفاضية، الانتظار، الإشعارات، لحظات النجاح)
    static func centerSlot(_ size: CGSize, fraction: CGFloat = 0.62) -> CGRect {
        let s = min(size.width, size.height) * fraction
        return CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
    }

    /// يحوّل شبكة التصميم (افتراضياً ١٠٠×١٠٠) إلى المربّع المحجوز، محافظاً على النسبة
    static func fit(_ ctx: inout GraphicsContext, grid: CGSize = CGSize(width: 100, height: 100), into rect: CGRect) {
        let s = min(rect.width / grid.width, rect.height / grid.height)
        ctx.translateBy(x: rect.midX - grid.width * s / 2, y: rect.midY - grid.height * s / 2)
        ctx.scaleBy(x: s, y: s)
    }

    // MARK: النظام العام لرؤوس المربّعات الوسطى (أي رمز SF)

    /// علامة الرأس العامة: رمز المربّع نفسه يصير شعاراً مصمتاً هادئاً — درجة الجسم (١١٪)، مائل ٩°،
    /// في الجهة المقابلة للعنوان، ويتنفّس ٨ ث. بلا ذهبي (الذهبي للشعارات الخاصة ذات المعنى).
    /// الاستثناء الوحيد المسموح فيه برمز SF داخل الرسم.
    static func drawSymbolMark(_ symbol: String, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                               surface: Surface = .header) {
        guard size.width > 1, size.height > 1, !symbol.isEmpty else { return }
        let rtl = ctx.environment.layoutDirection == .rightToLeft
        let slot = headerSlot(size, rtl: rtl)
        let tn = tones(surface)
        var c = ctx
        let center = CGPoint(x: slot.midX, y: slot.midY)
        applyBreath(&c, anchor: center, t: t)
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .degrees(rtl ? -9 : 9))
        let glyph = c.resolve(Text(Image(dsSymbol: symbol))
            .font(.system(size: slot.height * 0.70, weight: .bold))
            .foregroundColor(.white))
        tone(&c, opacity: tn.body) { l in l.draw(glyph, at: .zero, anchor: .center) }
    }

    /// الصفحة الفاضية العامة: قرص هادئ بلون القسم + رمز الصفحة بدرجة الحزام يتنفّس + نقطة ذهبية واحدة
    /// على حافة القرص (أعلى جهة البداية) يتنفّس توهّجها كل ٤ ث. كامل عند t = 0.
    static func drawSymbolPlate(_ symbol: String, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                                tint: Color, dark: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let p = palette(.light, tint: tint, dark: dark)
        let side = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = side * 0.44
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .color(tint.opacity(p.tones.plate)))
        if !symbol.isEmpty {
            var s = ctx
            applyBreath(&s, anchor: c, t: t)
            let glyph = s.resolve(Text(Image(dsSymbol: symbol))
                .font(.system(size: side * 0.30, weight: .semibold))
                .foregroundColor(tint))
            tone(&s, opacity: p.tones.band + 0.15) { l in l.draw(glyph, at: c, anchor: .center) }
        }
        // بلا نقطة ذهبية هنا: على حافة قرص «لا يوجد» كانت تُقرأ شارة «غير مقروء» — التنفّس يكفي
    }
}

// MARK: - FTKitCanvas — اللوحة القياسية (Canvas + TimelineView)

/// الغلاف الوحيد لكل رسم متكرّر: ٣٠ إطاراً/ث، يتجمّد عند t = 0 مع «تقليل الحركة»، مخفيّ عن القارئ
/// الصوتي، ولا يلتقط اللمس. `entrance`: ظهور أول مرة واحدة (تلاشٍ + ارتفاع ٦ نقاط، ٠٫٩ ث).
/// `delay`: تأخير الظهور (رأس المربّع ينتظر كبر المربّع).
///
///     FTKitCanvas(entrance: true) { ctx, size, t, dark in
///         FTKit.drawSymbolMark(icon, in: &ctx, size: size, t: t)
///     }
/// إيقاف الرسوم المتحركة مؤقتاً (مثلاً خلف مربّع «خبر جديد» المفتوح) — يتجمّد الرسم على آخر إطار
private struct FTAnimationsPausedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ftAnimationsPaused: Bool {
        get { self[FTAnimationsPausedKey.self] }
        set { self[FTAnimationsPausedKey.self] = newValue }
    }
}

struct FTKitCanvas: View {
    var loop: Double = FTKit.loop
    var entrance: Bool = false
    var delay: Double = 0
    let draw: (inout GraphicsContext, CGSize, Double, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ftAnimationsPaused) private var ftPaused
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()

    init(loop: Double = FTKit.loop, entrance: Bool = false, delay: Double = 0,
         _ draw: @escaping (inout GraphicsContext, CGSize, Double, Bool) -> Void) {
        self.loop = loop
        self.entrance = entrance
        self.delay = delay
        self.draw = draw
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / FTKit.frameRate, paused: reduceMotion || ftPaused)) { tl in
            let still = reduceMotion
            let elapsed = still ? 0 : max(0, tl.date.timeIntervalSince(start) - delay)
            let t = still ? 0 : FTKit.fold(elapsed, loop: loop)
            let fade: (opacity: Double, dy: CGFloat) = (entrance && !still) ? FTKit.emerge(elapsed) : (1, 0)
            let dark = colorScheme == .dark
            let draw = self.draw
            Canvas { ctx, size in
                guard fade.opacity > 0.001 else { return }
                ctx.opacity *= fade.opacity
                if fade.dy != 0 { ctx.translateBy(x: 0, y: fade.dy) }
                draw(&ctx, size, t, dark)
            }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - FTKitMomentCanvas — لحظة تُعرض مرة ثم تسكن

/// لحظات النجاح: تُرسم من t = 0 إلى `duration` مرة واحدة (٦٠ إطاراً/ث) ثم يتوقّف المؤقّت على الإطار الأخير.
/// «تقليل الحركة»: الإطار الأخير مباشرة.
struct FTKitMomentCanvas: View {
    var duration: Double = FTKit.momentDuration
    var delay: Double = 0.12
    let draw: (inout GraphicsContext, CGSize, Double, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()

    init(duration: Double = FTKit.momentDuration, delay: Double = 0.12,
         _ draw: @escaping (inout GraphicsContext, CGSize, Double, Bool) -> Void) {
        self.duration = duration
        self.delay = delay
        self.draw = draw
    }

    var body: some View {
        Group {
            if reduceMotion {
                canvas(t: duration)
            } else {
                TimelineView(FTKOnceSchedule(start: start, length: delay + duration)) { tl in
                    canvas(t: min(duration, max(0, tl.date.timeIntervalSince(start) - delay)))
                }
            }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func canvas(t: Double) -> some View {
        let dark = colorScheme == .dark
        let draw = self.draw
        return Canvas { ctx, size in draw(&ctx, size, t, dark) }
    }
}

// MARK: - أدوات خاصة

nonisolated fileprivate enum FTK {
    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
    }
}

/// ٦٠ إطاراً حتى نهاية اللحظة، ثم إطار أخير ويتوقّف المؤقّت نهائياً
nonisolated fileprivate struct FTKOnceSchedule: TimelineSchedule {
    let start: Date
    let length: Double

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(cursor: startDate, end: start.addingTimeInterval(length), step: 1.0 / 60.0)
    }

    nonisolated struct Entries: Sequence, IteratorProtocol {
        var cursor: Date
        let end: Date
        let step: Double
        var finished = false

        mutating func next() -> Date? {
            guard !finished else { return nil }
            if cursor >= end {
                finished = true
                return end
            }
            let now = cursor
            cursor = cursor.addingTimeInterval(step)
            return now
        }
    }
}
