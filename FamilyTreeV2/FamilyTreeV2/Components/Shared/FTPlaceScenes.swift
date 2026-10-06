import SwiftUI

// MARK: - FTPlaceScenes — رسوم الأماكن بأسلوب «الشعار المصمت» (الجولة النهائية ٢٠٢٦-١٠-٠٥)
//
// طلب المالك: «ابي تصميم ابسط و غرافيكس افضل … رسوم متحركة بسيطة مبدعة … في كرت الترحيب شيل خله ابسط
// بكثير … عطني شي مرتب و بسيط وقوي … صمم باحتراف وبساطة وباعتدال».
//
// لكل مكان شعار مصمت واحد بلون القسم بدرجتين (جسم + حزام)، فوق قرص هادئ عدا الشجرة، ولمسة ذهبية واحدة ذات معنى:
//   • تحميل الشجرة: شجرة غاف — نقطة «نسغ» ذهبية تصعد الجذع إلى الثمرة فتتوهّج (هي مؤشّر التحميل).
//   • انتظار الموافقة: ساعة رملية — لمعة كريمية تنساب في خيط الرمل الذهبي.
//   • لا إشعارات: جرس ساكن (بلا تأرجح — التأرجح رنين) — كرة اللسان الذهبية يتنفّس توهّجها.
//   • الدخول: توهّج واحد خلف الشعار يتنفّس — شبه لا شيء.
//   • بطاقة الترحيب: لا منظر إطلاقاً — رمز وقت صغير `FTGreetingGlyph` بجانب التحية فقط.
// الحركة: تنفّس واحد (٨ ث) + حركة ذهبية واحدة على الأكثر (دورتها ٤ ث). t = 0 لوحة ساكنة كاملة.
//
// يعتمد على FTKit.swift (الألوان، الدرجات، التنفّس، اللوحة). GraphicsContext فقط، iOS 16، دالة نقية في t،
// بلا blur (التوهّج تدرّج شعاعي)، ≤ ١٤ عملية رسم في الإطار لكل مشهد. لا أنواع من التطبيق.
// الواجهات العامة كما كانت (مع وسيط اختياري جديد `ink:` بقيمة افتراضية) — فالاستدعاءات الحالية تعمل كما هي.

// MARK: - بطاقة الترحيب

/// كانت لوحة الكويت داخل بطاقة الترحيب — حُذفت بطلب المالك («شيل، خله ابسط بكثير»).
/// تبقى الواجهة حتى لا ينكسر الاستدعاء الحالي، لكن `draw` لا يرسم شيئاً. البديل: `FTGreetingGlyph`
/// (رمز ١٨ نقطة بجانب التحية) ويعود مكان المنظر `Spacer(minLength: 8)`.
nonisolated enum FTGreetingScene {
    nonisolated enum Mood { case dawn, noon, sunset, night }

    /// مطابق لنص التحية ولونها في `HomeGreetingRow`: صباح ٤–١٢ · ظهر ١٢–١٧ · مغرب ١٧–١٩ · ليل غير ذلك
    static func mood(forHour h: Int) -> Mood {
        switch h {
        case 4..<12: return .dawn
        case 12..<17: return .noon
        case 17..<19: return .sunset
        default: return .night
        }
    }

    /// باقيان للتوافق فقط
    static let designHeight: CGFloat = 74
    static let minimumWidth: CGFloat = 46

    /// لا يرسم شيئاً (المنظر حُذف). استعمل `FTGreetingGlyph`.
    static func draw(_ mood: Mood, in ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool, mirrored: Bool = false) {}
}

/// رمز الوقت بجانب التحية — يحلّ محلّ `Image(systemName: greetingSymbol)` في `HomeGreetingRow`:
///
///     FTGreetingGlyph(mood: FTGreetingScene.mood(forHour: hour), tint: timeAccent)
///
/// صباح: نصف شمس تطلع فوق الأفق بخمسة أشعة (ترتفع وحدة واحدة كل ٨ ث) · ظهر: قرص وثمانية أشعة تدور ٤٥°
/// في ٨ ث بتسهيل جيبي (تلتئم بالتناظر) · مغرب: شمس تغيب في البحر بانعكاس واحد (تنزل وحدة واحدة) · ليل: هلال وحده (بلا نجمة —
/// الهلال مع النجمة محجوزان لـ«وفاة») يتمايل ٤° حول قاعدته. لون الوقت وحده، بلا ذهبي ولا توهّج ولا ظهور.
/// ٢–٣ عمليات رسم. «تقليل الحركة»: ساكن عند t = 0.
struct FTGreetingGlyph: View {
    let mood: FTGreetingScene.Mood
    let tint: Color
    var size: CGFloat

    init(mood: FTGreetingScene.Mood, tint: Color, size: CGFloat = 18) {
        self.mood = mood
        self.tint = tint
        self.size = size
    }

    var body: some View {
        let mood = self.mood
        let tint = self.tint
        FTKitCanvas { ctx, sz, t, _ in
            FTGreetingGlyph.draw(mood, in: &ctx, size: sz, t: t, ink: tint)
        }
        .frame(width: size, height: size)
    }

    /// يرسم الرمز في أي مربّع (شبكة ٢٠×٢٠ متوسّطة)
    nonisolated static func draw(_ mood: FTGreetingScene.Mood, in ctx: inout GraphicsContext, size: CGSize, t: Double, ink: Color) {
        FTGlyphArt.draw(mood, in: &ctx, size: size, t: t, ink: ink)
    }

    /// نفس الرمز بأوقات FTKit الثلاثة (صباح · ظهر · مساء)
    nonisolated static func draw(_ mood: FTKit.Mood, in ctx: inout GraphicsContext, size: CGSize, t: Double, ink: Color) {
        let m: FTGreetingScene.Mood
        switch mood {
        case .morning: m = .dawn
        case .afternoon: m = .noon
        case .evening: m = .night
        }
        FTGlyphArt.draw(m, in: &ctx, size: size, t: t, ink: ink)
    }
}

// MARK: - FTPlaceScenes — رسوم الأماكن

nonisolated enum FTPlaceScenes {

    // MARK: ١) تحميل الشجرة — شجرة غاف ونسغ ذهبي

    /// الإطار المقترح لتحميل الشجرة (نقطة)
    static let treeGrowthDesign = CGSize(width: 240, height: 200)

    /// «جاري مزامنة الشجرة…» (TreeView). شجرة الغاف نفسها التي في مربّع الشجرة (نفس المسارات: فصّا مظلّة
    /// وجذع Y، والثمرة معلّقة تحت التاج)، بحبر الشجرة بدرجتين، فوق خط أرض شعري. `أ` تنفّس حول قاعدة الجذع
    /// (٨ ث). `ث` نسغ المزامنة (٤ ث): نقطة ذهبية تصعد من الجذور في الجذع والغصن الأيمن حتى تدخل التاج
    /// (٠–١٫٦ ث) فتتوهّج الثمرة (١٫٦–٢٫٦ ث). t = 0: الثمرة مضيئة ولا نقطة صاعدة.
    /// يرسم في مربّع ٠٫٧٦ من أصغر ضلع (حتى ٢٣٠ نقطة) — يصلح في الإطار القديم ٢٨٠×٢٣٠ أيضاً.
    /// `ink`: حبر قسم الشجرة من التطبيق (اختياري؛ الافتراضي #1F6358 فاتح / #6CB6A8 داكن).
    static func drawTreeGrowth(in ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool, ink: Color? = nil) {
        guard size.width > 1, size.height > 1 else { return }
        let p = FTPS.neutral(ink ?? FTPS.treeInk(dark), dark: dark)
        var c = ctx
        FTKit.mirrorForLTR(&c, width: size.width)
        let slot = FTPS.square(center: FTPS.mid(size), side: min(size.width, size.height, 230) * 0.76)
        FTKit.fit(&c, into: slot)
        FTTreeArt.draw(&c, t: t, p: p, unit: slot.width / 100)
    }

    // MARK: ٢) انتظار الموافقة — ساعة رملية

    /// الإطار المقترح لشاشة الانتظار (نقطة)
    static let waitingMajlisDesign = CGSize(width: 140, height: 140)

    /// «قيد المراجعة» (WaitingForApprovalView، بدل `waitingIcon` و`animatedDots`). قرص بحبر الإدارة وعليه
    /// ساعة رملية: الزجاجتان شكل واحد بخصر ضيّق (الجسم)، والإطار لوحتان وعمودان (الحزام)، والرمل ذهبي ثابت
    /// المستوى: خيط رفيع وكومة في الأسفل. `أ` تنفّس (٨ ث). `ث` لمعة كريمية تنساب في خيط الرمل مرة كل ٤ ث.
    /// اللوحة بحجم أصغر ضلع حتى ١٤٠ نقطة — تصلح في الإطار القديم ٣٤٠×٢٠٠ أيضاً.
    /// `ink`: حبر قسم الإدارة (اختياري؛ الافتراضي #423F80 فاتح / #9E9FDC داكن).
    static func drawWaitingMajlis(in ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool, ink: Color? = nil) {
        guard size.width > 1, size.height > 1 else { return }
        let tint = ink ?? FTPS.adminInk(dark)
        let p = FTPS.neutral(tint, dark: dark)
        let side = min(size.width, size.height, 140)
        let c0 = FTPS.mid(size)
        FTPS.plate(&ctx, center: c0, radius: side * 0.44, color: tint.opacity(p.tones.plate))
        var c = ctx
        let slot = FTPS.square(center: c0, side: side * 0.62)
        FTKit.fit(&c, into: slot)
        FTHourglassArt.draw(&c, t: t, p: p, unit: slot.width / 100)
    }

    // MARK: ٣) لا توجد إشعارات — جرس ساكن

    /// الإطار المقترح لبطاقة «لا توجد إشعارات» (نقطة)
    static let quietPigeonDesign = CGSize(width: 120, height: 120)

    /// «لا توجد إشعارات» (NotificationsCenterView ← SysStateCard.art). قرص بحبر الرئيسية وعليه جرس ساكن:
    /// الجرس (الجسم) بحافة مقصوصة، والعروة (الحزام)، وكرة اللسان ذهبية تحته. `أ` تنفّس **بلا ميل** (الميل رنين،
    /// وهذا عكس «لا إشعارات»). `ث` توهّج الكرة يتنفّس بين ٠٫٥ و١ كل ٤ ث.
    /// اللوحة بحجم أصغر ضلع حتى ١٢٠ نقطة — تصلح في الإطار القديم ٣٠٠×١٥٠ أيضاً.
    /// `ink`: حبر قسم الرئيسية (اختياري؛ الافتراضي #1F4E79 فاتح / #7FA8D6 داكن).
    static func drawQuietPigeon(in ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool, ink: Color? = nil) {
        guard size.width > 1, size.height > 1 else { return }
        let tint = ink ?? FTPS.homeInk(dark)
        let p = FTPS.neutral(tint, dark: dark)
        let side = min(size.width, size.height, 120)
        let c0 = FTPS.mid(size)
        FTPS.plate(&ctx, center: c0, radius: side * 0.44, color: tint.opacity(p.tones.plate))
        var c = ctx
        let slot = FTPS.square(center: c0, side: side * 0.66)
        FTKit.fit(&c, into: slot)
        FTBellArt.draw(&c, t: t, p: p)
    }

    // MARK: ٤) خلفية الدخول — توهّج واحد

    /// خلفية شاشة الدخول (LoginView ← backgroundView). **شبه لا شيء**: توهّج شعاعي واحد خلف الشعار عند
    /// `logoCenterY` (افتراضياً ٣٠٪ من الارتفاع)، نصف قطره ٠٫٥٥ من العرض، تتنفّس شدّته كل ٨ ث.
    /// الفاتح: كحلي العلامة ٠٫٠٥٥ ← ٠٫٠٨ (الأبيض لا يُرى فوق خلفية الدخول الفاتحة) · الداكن: كحلي فاتح #7FA8D6 ٠٫١٠ ← ٠٫١٤. عملية رسم واحدة.
    static func drawLoginBackdrop(in ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool, logoCenterY: CGFloat? = nil) {
        guard size.width > 1, size.height > 1 else { return }
        let center = CGPoint(x: size.width / 2, y: logoCenterY ?? size.height * 0.3)
        let b = FTKit.breath(t)
        let (color, lo, hi): (Color, Double, Double) = dark
            ? (FTPS.hex(0x7FA8D6), 0.10, 0.14)
            : (FTPS.hex(0x1F4E79), 0.055, 0.08)
        FTKit.glow(&ctx, at: center, radius: size.width * 0.55, color: color, opacity: lo + (hi - lo) * b)
    }
}

// MARK: - FTSceneCanvas — اللوحة الجاهزة للدمج (نفس الاستدعاء القديم)

/// يرسم أي مشهد من هذا الملف ويحرّكه — صار غلافاً لـ `FTKitCanvas`: ٣٠ إطاراً/ث، الزمن مطويّ على الدورة
/// الكبرى، ظهور أول مرة واحدة (تلاشٍ + ارتفاع ٦ نقاط، ٠٫٩ ث)، ويتجمّد على t = 0 مع «تقليل الحركة».
/// لا يلتقط اللمس ولا يُقرأ بقارئ الشاشة.
///
///     FTSceneCanvas { ctx, size, t, dark in
///         FTPlaceScenes.drawTreeGrowth(in: &ctx, size: size, t: t, dark: dark)
///     }
///     .frame(width: 240, height: 200)
struct FTSceneCanvas: View {
    var entrance: Bool
    var delay: Double
    let draw: (inout GraphicsContext, CGSize, Double, Bool) -> Void

    init(entrance: Bool = true, delay: Double = 0,
         _ draw: @escaping (inout GraphicsContext, CGSize, Double, Bool) -> Void) {
        self.entrance = entrance
        self.delay = delay
        self.draw = draw
    }

    var body: some View {
        FTKitCanvas(entrance: entrance, delay: delay, draw)
    }
}

// MARK: - أدوات خاصة

nonisolated fileprivate enum FTPS {
    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: 1)
    }

    /// أحبار الأقسام (فاتح / داكن) — يمكن للتطبيق تمرير `section.ink` بدلها
    static func treeInk(_ dark: Bool) -> Color { dark ? hex(0x6CB6A8) : hex(0x1E5950) }
    static func adminInk(_ dark: Bool) -> Color { dark ? hex(0x9E9FDC) : hex(0x47467F) }
    static func homeInk(_ dark: Bool) -> Color { dark ? hex(0x7FA8D6) : hex(0x1F4E79) }

    /// درجات الشعار فوق سطح محايد (أبيض / #1C1C1E): أقوى من جدول `light` في FTKit حتى يوازي وزنُه رمزَ
    /// الصفحة الفاضية العامة (`drawSymbolPlate` = الحزام + ٠٫١٥). القرص والذهبي كما في FTKit.
    static func neutral(_ tint: Color, dark: Bool) -> FTKit.Palette {
        let base = FTKit.tones(.light, dark: dark)
        let tones = FTKit.Tones(body: dark ? 0.48 : 0.36, band: dark ? 0.70 : 0.56, gold: base.gold,
                                glow: base.glow, glowPeak: base.glowPeak, plate: base.plate)
        return FTKit.Palette(ink: tint, tones: tones, gold: dark ? FTKit.gold : FTKit.goldOnLight, glint: FTKit.glint)
    }

    /// تنفّس قائم بلا ميل (الساعة الرملية والجرس): ارتفاع ٢ وتكبير ١٫٤٪ فقط
    static let level = FTKit.BreathAmount(rise: 2, scale: 0.014, tilt: 0)

    static func mid(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    static func square(center c: CGPoint, side s: CGFloat) -> CGRect {
        CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
    }

    /// القرص الخلفي الساكن
    static func plate(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// نقطة على خطّ منكسر عند نسبة u من طوله
    static func point(on pts: [CGPoint], at u: Double) -> CGPoint {
        guard pts.count > 1 else { return pts.first ?? .zero }
        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            lengths.append(d)
            total += d
        }
        var target = total * CGFloat(max(0, min(1, u)))
        for i in 1..<pts.count {
            let d = lengths[i - 1]
            if target <= d || i == pts.count - 1 {
                let k = d > 0 ? min(1, target / d) : 0
                return CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * k,
                               y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * k)
            }
            target -= d
        }
        return pts[pts.count - 1]
    }
}

// MARK: - رمز التحية (شبكة ٢٠)

nonisolated fileprivate enum FTGlyphArt {
    /// خطّ الأفق للصباح والمغرب
    static let dawnHorizon: CGFloat = 14.6
    static let duskHorizon: CGFloat = 11.2

    /// انعكاس واحد قصير للشمس على البحر تحت أفق المغرب (خطّان كانا يُقرآن «ضباباً» بالحجم الصغير)
    static let duskReflection: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 7.4, y: duskHorizon + 3.5))
        p.addLine(to: CGPoint(x: 12.6, y: duskHorizon + 3.5))
        return p
    }()

    static let dawnRays: Path = {
        var p = Path()
        for i in 1...5 {
            let a = Double.pi + Double(i) * .pi / 6
            p.move(to: CGPoint(x: 10 + cos(a) * 7.0, y: dawnHorizon + sin(a) * 7.0))
            p.addLine(to: CGPoint(x: 10 + cos(a) * 9.1, y: dawnHorizon + sin(a) * 9.1))
        }
        return p
    }()

    static let noonRays: Path = {
        var p = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            p.move(to: CGPoint(x: cos(a) * 6.5, y: sin(a) * 6.5))
            p.addLine(to: CGPoint(x: cos(a) * 8.7, y: sin(a) * 8.7))
        }
        return p
    }()

    static func horizonLine(_ y: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 2.2, y: y))
        p.addLine(to: CGPoint(x: 17.8, y: y))
        return p
    }

    static func draw(_ mood: FTGreetingScene.Mood, in ctx: inout GraphicsContext, size: CGSize, t: Double, ink: Color) {
        guard size.width > 1, size.height > 1 else { return }
        var c = ctx
        let s = min(size.width, size.height) / 20
        c.translateBy(x: (size.width - 20 * s) / 2, y: (size.height - 20 * s) / 2)
        c.scaleBy(x: s, y: s)
        let rays = ink.opacity(0.85)
        switch mood {
        case .dawn:
            // نصف شمس تطلع: ترتفع وحدة واحدة (٨ ث) والأفق ثابت
            let h = dawnHorizon
            var u = c
            u.clip(to: Path(CGRect(x: 0, y: 0, width: 20, height: h - 1.75)))
            u.translateBy(x: 0, y: -1.0 * FTKit.breath(t))
            u.fill(Path(ellipseIn: CGRect(x: 10 - 4.9, y: h - 4.9, width: 9.8, height: 9.8)), with: .color(ink))
            u.stroke(dawnRays, with: .color(rays), style: FTKit.Stroke.ray)
            c.stroke(horizonLine(h), with: .color(ink), style: FTKit.Stroke.ray)
        case .sunset:
            // شمس تغيب في البحر: نصف قرص فوق الأفق وانعكاس واحد تحته — تنزل وحدة واحدة (٨ ث)
            let h = duskHorizon
            var u = c
            u.clip(to: Path(CGRect(x: 0, y: 0, width: 20, height: h - 1.75)))
            u.translateBy(x: 0, y: 1.0 * FTKit.breath(t))
            u.fill(Path(ellipseIn: CGRect(x: 10 - 5.6, y: h - 5.6, width: 11.2, height: 11.2)), with: .color(ink))
            c.stroke(horizonLine(h), with: .color(ink), style: FTKit.Stroke.ray)
            c.stroke(duskReflection, with: .color(rays), style: FTKit.Stroke.ray)
        case .noon:
            // قرص وثمانية أشعة تدور ٤٥° في الدورة (تلتئم بالتناظر) — بتسهيل جيبي: تبدأ وتنتهي ساكنة
            // فلا يبقى دوران دائم بجانب النص، والحلقة تلتئم بلا قفزة (السرعة صفر عند الطرفين)
            c.fill(Path(ellipseIn: CGRect(x: 10 - 4.2, y: 10 - 4.2, width: 8.4, height: 8.4)), with: .color(ink))
            var r = c
            r.translateBy(x: 10, y: 10)
            r.rotate(by: .degrees(45 * FTKit.Ease.inOutSine(FTKit.phase(t))))
            r.stroke(noonRays, with: .color(rays), style: FTKit.Stroke.ray)
        case .night:
            // هلال وحده يتمايل ٤° حول قاعدته
            FTKit.applyBreath(&c, anchor: CGPoint(x: 10, y: 17.6), t: t, amount: .glyph)
            FTKit.tone(&c, opacity: 1) { l in
                l.fill(Path(ellipseIn: CGRect(x: 10 - 7.3, y: 10.4 - 7.3, width: 14.6, height: 14.6)), with: .color(ink))
                FTKit.eraser(l).fill(Path(ellipseIn: CGRect(x: 13.9 - 6.2, y: 6.9 - 6.2, width: 12.4, height: 12.4)),
                                     with: .color(.black))
            }
        }
    }
}

// MARK: - شجرة الغاف (شبكة ١٠٠) — نفس غافة مربّع الشجرة في الرئيسية (FTTileScenes ← FTGhaf) حتى يتّسق المكانان

nonisolated fileprivate enum FTTreeArt {
    typealias P = FTPS

    /// فصّ «مظلّة»: قمّة مقوّسة هادئة، وقاع شبه مستوٍ، وطرفان يرقّان (حافّة المظلّة)
    static func lobe(_ x0: CGFloat, _ x1: CGFloat, base y: CGFloat, up: CGFloat, down: CGFloat) -> Path {
        let w = x1 - x0
        var p = Path()
        p.move(to: P.pt(x0, y))
        p.addCurve(to: P.pt(x0 + w * 0.5, y - up), control1: P.pt(x0 + w * 0.04, y - up * 0.8), control2: P.pt(x0 + w * 0.2, y - up))
        p.addCurve(to: P.pt(x1, y), control1: P.pt(x1 - w * 0.2, y - up), control2: P.pt(x1 - w * 0.04, y - up * 0.8))
        p.addCurve(to: P.pt(x0, y), control1: P.pt(x1 - w * 0.22, y + down * 1.3), control2: P.pt(x0 + w * 0.22, y + down * 1.3))
        p.closeSubpath()
        return p
    }
    /// الفصّ الخلفي (أدنى وأصغر) والأمامي (أعلى وأعرض، جهة الثمرة) — نسبة المظلّة ≈ ٣٫٢ : ١
    static let back = lobe(5, 60, base: 32, up: 13, down: 4.5)
    static let front = lobe(34, 95, base: 27, up: 14, down: 5.5)
    static let crown: Path = {
        var p = back
        p.addPath(front)
        return p
    }()
    /// تدوير طرفَي الفصّين (لا زوايا حادّة): خطّ مستدير بلون الشكل نفسه
    static let tipRound = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)

    /// الجذع: قاعدة جذور قصيرة ← ساق ← تفرّع Y غير متناظر إلى غصنين يختفيان تحت التاج (شكل واحد)
    static let trunk: Path = {
        var p = Path()
        p.move(to: P.pt(40, 96))
        p.addCurve(to: P.pt(46.6, 86), control1: P.pt(45, 95), control2: P.pt(46.6, 91))
        p.addCurve(to: P.pt(45.4, 67), control1: P.pt(46.6, 78), control2: P.pt(45.6, 72))
        p.addCurve(to: P.pt(27, 38), control1: P.pt(42, 56), control2: P.pt(33, 46))
        p.addLine(to: P.pt(31.5, 35.5))
        p.addCurve(to: P.pt(50.6, 58), control1: P.pt(38, 43), control2: P.pt(47, 50))
        p.addCurve(to: P.pt(63, 30), control1: P.pt(54, 47), control2: P.pt(59, 37))
        p.addLine(to: P.pt(68, 32))
        p.addCurve(to: P.pt(54.2, 68), control1: P.pt(63, 44), control2: P.pt(55, 56))
        p.addCurve(to: P.pt(53.8, 86), control1: P.pt(53.8, 74), control2: P.pt(53.8, 80))
        p.addCurve(to: P.pt(61, 96), control1: P.pt(53.8, 91), control2: P.pt(56, 95))
        p.closeSubpath()
        return p
    }()

    /// الثمرة الذهبية «نور العائلة»: معلّقة تحت حافة التاج الأمامي (كما في المربّع)
    static let fruit = P.pt(81, 38.5)
    /// مسار النسغ: من الجذور صعوداً في الجذع ثم الغصن الأيمن حتى يدخل التاج
    static let sap: [CGPoint] = [P.pt(50, 92), P.pt(50, 68), P.pt(54.6, 56), P.pt(58.6, 46), P.pt(61.6, 38.5)]
    /// الشجرة ترتفع من ١٣ إلى ٩٦ ← تُنزَّل ٤٫٥ وحدات لتتوسّط الشبكة
    static let lift: CGFloat = -4.5

    static func draw(_ ctx: inout GraphicsContext, t: Double, p: FTKit.Palette, unit: CGFloat) {
        var c = ctx
        c.translateBy(x: 0, y: lift)
        let gap = max(FTKit.Stroke.gap, 1 / unit)

        // خط أرض شعري ساكن (نقطة واحدة، ٠٫٢٥) يتلاشى عند طرفيه — خارج التنفّس فلا يتحرّك
        var ground = Path()
        ground.move(to: P.pt(18, 96.6))
        ground.addLine(to: P.pt(82, 96.6))
        c.stroke(ground, with: .linearGradient(
            Gradient(stops: [.init(color: p.ink.opacity(0), location: 0),
                             .init(color: p.ink.opacity(0.25), location: 0.3),
                             .init(color: p.ink.opacity(0.25), location: 0.7),
                             .init(color: p.ink.opacity(0), location: 1)]),
            startPoint: P.pt(18, 0), endPoint: P.pt(82, 0)), lineWidth: 1 / unit)

        // `أ` التنفّس: الشجرة كلها حول قاعدة الجذع — تكبير وميل خفيفان بلا ارتفاع (تبقى على الأرض)
        FTKit.applyBreath(&c, anchor: P.pt(50, 96), t: t,
                          amount: FTKit.BreathAmount(rise: 0, scale: 0.016, tilt: 1.2))

        // الحزام: الجذع والغصنان — يقصّهما التاج بفاصل
        FTKit.tone(&c, opacity: p.tones.band) { l in
            l.fill(trunk, with: .color(p.ink))
            let e = FTKit.eraser(l)
            e.fill(crown, with: .color(.black))
            e.stroke(crown, with: .color(.black), style: StrokeStyle(lineWidth: 2 * gap + tipRound.lineWidth, lineJoin: .round))
        }

        // الجسم: الفصّ الخلفي ثم الأمامي، يفصلهما فاصل مقصوص
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(back, with: .color(p.ink))
            l.stroke(back, with: .color(p.ink), style: tipRound)
            let e = FTKit.eraser(l)
            e.fill(front, with: .color(.black))
            e.stroke(front, with: .color(.black), style: StrokeStyle(lineWidth: 2 * gap + tipRound.lineWidth, lineJoin: .round))
            l.fill(front, with: .color(p.ink))
            l.stroke(front, with: .color(p.ink), style: tipRound)
        }

        // `ث` نسغ المزامنة (دورة ٤ ث): نقطة ذهبية تصعد من الجذور في الجذع والغصن وتدخل التاج (٠–١٫٦ ث)،
        // ثم تتوهّج الثمرة (١٫٦–٢٫٦ ث). عند t = 0 الثمرة مضيئة ولا نقطة.
        let x = FTKit.local(t, period: 4)
        let glowUp = FTKit.beat(t, start: 1.55, rise: 0.35, hold: 0.15, fall: 0.55, period: 4, ease: .inOutSine)
        FTKit.goldPoint(&c, at: fruit, core: 3, glowRadius: 10, intensity: 0.5 + 0.5 * glowUp, gold: p.goldFill)

        let alpha = FTKit.progress(x, 0, 0.25) * (1 - FTKit.progress(x, 1.3, 1.6))
        if alpha > 0.001 {
            var s = c
            s.opacity *= alpha
            FTKit.goldPoint(&s, at: P.point(on: sap, at: FTKit.progress(x, 0, 1.6, .inOutSine)),
                            core: 2.1, glowRadius: 6.5, intensity: 0.9, gold: p.goldFill)
        }
    }
}

// MARK: - الساعة الرملية (شبكة ١٠٠)

nonisolated fileprivate enum FTHourglassArt {
    typealias P = FTPS

    /// الإطار: لوحتان وعمودان رفيعان (شكل واحد بالحزام)
    static let frame: Path = {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 20, y: 8, width: 60, height: 8.5), cornerSize: CGSize(width: 3, height: 3))
        p.addRoundedRect(in: CGRect(x: 20, y: 83.5, width: 60, height: 8.5), cornerSize: CGSize(width: 3, height: 3))
        p.addRoundedRect(in: CGRect(x: 24, y: 14, width: 3.6, height: 72), cornerSize: CGSize(width: 1.6, height: 1.6))
        p.addRoundedRect(in: CGRect(x: 72.4, y: 14, width: 3.6, height: 72), cornerSize: CGSize(width: 1.6, height: 1.6))
        return p
    }()

    /// الزجاجتان: شكل واحد بخصر ضيّق، بعيد عن الإطار بفاصل ١٫٤
    static let glass: Path = {
        let top: CGFloat = 17.9, bottom: CGFloat = 82.1, l: CGFloat = 32.5, r: CGFloat = 67.5
        var p = Path()
        p.move(to: P.pt(l + 2.5, top))
        p.addLine(to: P.pt(r - 2.5, top))
        p.addQuadCurve(to: P.pt(r, top + 2.5), control: P.pt(r, top))
        p.addCurve(to: P.pt(52.1, 50), control1: P.pt(r, 35), control2: P.pt(53.4, 42.5))
        p.addCurve(to: P.pt(r, bottom - 2.5), control1: P.pt(53.4, 57.5), control2: P.pt(r, 65))
        p.addQuadCurve(to: P.pt(r - 2.5, bottom), control: P.pt(r, bottom))
        p.addLine(to: P.pt(l + 2.5, bottom))
        p.addQuadCurve(to: P.pt(l, bottom - 2.5), control: P.pt(l, bottom))
        p.addCurve(to: P.pt(47.9, 50), control1: P.pt(l, 65), control2: P.pt(46.6, 57.5))
        p.addCurve(to: P.pt(l, top + 2.5), control1: P.pt(46.6, 42.5), control2: P.pt(l, 35))
        p.addQuadCurve(to: P.pt(l + 2.5, top), control: P.pt(l, top))
        p.closeSubpath()
        return p
    }()

    /// كومة الرمل الذهبية في الأسفل
    static let mound: Path = {
        var p = Path()
        p.move(to: P.pt(39, 80.6))
        p.addCurve(to: P.pt(50, 71.5), control1: P.pt(41.5, 75.2), control2: P.pt(45.2, 71.5))
        p.addCurve(to: P.pt(61, 80.6), control1: P.pt(54.8, 71.5), control2: P.pt(58.5, 75.2))
        p.addQuadCurve(to: P.pt(39, 80.6), control: P.pt(50, 81.4))
        p.closeSubpath()
        return p
    }()

    /// خيط الرمل: من الخصر إلى قمّة الكومة
    static let stream: Path = {
        var p = Path()
        p.move(to: P.pt(50, 49))
        p.addLine(to: P.pt(50, 72.5))
        return p
    }()

    static func draw(_ ctx: inout GraphicsContext, t: Double, p: FTKit.Palette, unit: CGFloat) {
        var c = ctx
        // تنفّس بلا ميل: الساعة الرملية قائمة دائماً وخيط الرمل يبقى عمودياً (الميل يكسر الجاذبية)
        FTKit.applyBreath(&c, anchor: P.pt(50, 50), t: t, amount: FTPS.level)

        // الأشكال لا تتراكب داخل الدرجة الواحدة ← تعبئة مباشرة بلا طبقات
        c.fill(frame, with: .color(p.band))
        c.fill(glass, with: .color(p.body))

        // الرمل الذهبي: الكومة + الخيط (٢٫٣ نقطة)
        let w = FTKit.Stroke.round(2.3 / unit)
        c.fill(mound, with: .color(p.goldFill))
        c.stroke(stream, with: .color(p.goldFill), style: w)

        // انسياب: لمعة كريمية بطول ٣٠٪ تنزل في الخيط داخل نافذة ١٫٢ ث كل ٤ ث (لا شيء عند t = 0)
        let x = FTKit.local(t, period: 4)
        if x > 0.6, x < 1.8 {
            let head = -0.3 + 1.3 * (x - 0.6) / 1.2
            let a = max(0, head), b = min(1, head + 0.3)
            if b > a {
                c.stroke(stream.trimmedPath(from: a, to: b), with: .color(p.glint.opacity(0.9)), style: w)
            }
        }
    }
}

// MARK: - الجرس (شبكة ١٠٠)

nonisolated fileprivate enum FTBellArt {
    typealias P = FTPS

    /// العروة: حلقة (تعبئة زوجية-فردية فتُقصّ الفتحة بعملية واحدة)
    static let loop: Path = {
        var p = Path()
        p.addEllipse(in: CGRect(x: 50 - 5.8, y: 13.5 - 5.8, width: 11.6, height: 11.6))
        p.addEllipse(in: CGRect(x: 50 - 2.6, y: 13.5 - 2.6, width: 5.2, height: 5.2))
        return p
    }()

    /// جسم الجرس: قبّة تنزل إلى حافة متّسعة
    static let bell: Path = {
        var p = Path()
        p.move(to: P.pt(50, 20.8))
        p.addCurve(to: P.pt(68.5, 40), control1: P.pt(62, 20.8), control2: P.pt(68.5, 29))
        p.addLine(to: P.pt(70, 56))
        p.addCurve(to: P.pt(80.5, 68.5), control1: P.pt(70.8, 62.5), control2: P.pt(76.5, 65))
        p.addQuadCurve(to: P.pt(78, 73.5), control: P.pt(83.2, 71.6))
        p.addLine(to: P.pt(22, 73.5))
        p.addQuadCurve(to: P.pt(19.5, 68.5), control: P.pt(16.8, 71.6))
        p.addCurve(to: P.pt(30, 56), control1: P.pt(23.5, 65), control2: P.pt(29.2, 62.5))
        p.addLine(to: P.pt(31.5, 40))
        p.addCurve(to: P.pt(50, 20.8), control1: P.pt(31.5, 29), control2: P.pt(38, 20.8))
        p.closeSubpath()
        return p
    }()

    /// الحافة: خطّ مقصوص يفصل شفة الجرس
    static let rim: Path = {
        var p = Path()
        p.move(to: P.pt(14, 65))
        p.addLine(to: P.pt(86, 65))
        return p
    }()

    static let clapper = P.pt(50, 80.6)

    static func draw(_ ctx: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        var c = ctx
        c.translateBy(x: 0, y: 2.6)   // توسيط الشكل (١٠–٨٥) على الشبكة
        FTKit.applyBreath(&c, anchor: P.pt(50, 50), t: t, amount: FTPS.level)
        c.fill(loop, with: .color(p.band), style: FillStyle(eoFill: true))
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(bell, with: .color(p.ink))
            FTKit.eraser(l).stroke(rim, with: .color(.black), lineWidth: FTKit.Stroke.gap * 1.6)
        }
        FTKit.goldPoint(&c, at: clapper, core: 4.4, glowRadius: 12,
                        intensity: 0.5 + 0.5 * FTKit.breath(t, period: 4), gold: p.goldFill)
    }
}
