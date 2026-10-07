import SwiftUI

// MARK: - FTTileScenes — شعارات مربّعات الرئيسية والصفحات الفاضية («الشعار المصمت»، ٢٠٢٦-١٠-٠٥)
//
// طلب المالك: «ابي تصميم ابسط و غرافيكس افضل … شي مرتب و بسيط وقوي». لكل مكان شعار واحد مصمت:
// أبيض بدرجتين (جسم + حزام) فوق لون المربّع، أو بحبر القسم فوق الأسطح الفاتحة، والتفاصيل فراغات
// مقصوصة، ولمسة ذهبية واحدة ذات معنى. الحركة: تنفّس الشعار كله (٨ ث) + حركة واحدة للذهبي وحده.
//
// • الشجرة: غافة بتاج «مظلّة» من فصّين وجذع Y — ثمرة ذهبية يتنفّس توهّجها (٤ ث).
// • الديوانيات: دلّة تصبّ في فنجان — لمعة كريمية تنساب في خيط القهوة (كل ٤ ث).
// • المكتبة: كتاب مفتوح على رَحْل — شريط ذهبي يتمايل ±٤° (٤ ث).
// • المشاريع: واجهة دكّان بمظلّة — «ضوء العتبة» يتنفّس توهّجه (٤ ث).
// • التواصل: ظرف بختم شمع ذهبي — لمعة تعبر الختم (كل ٤ ث).
// • الصفحات الفاضية: قرص ساكن بحبر القسم + الشعار نفسه في حالة «الانتظار» (دلّة قائمة تقطر، دكّان
//   بابه مغلق وضوء تحته)، والمكتبة والشجرة والتواصل بشعار المربّع نفسه، والعامة = رمز الصفحة في القرص
//   (`FTKit.drawSymbolPlate`).
//
// القواعد: GraphicsContext فقط، iOS 16 (القصّ بطبقة + destinationOut)، دالة نقية في t، الحلقة ٨ ث،
// t = 0 لوحة ساكنة كاملة (تقليل الحركة)، لا blur، ≤ ١٤ عملية رسم للمربّع و≤ ١٢ للصفحة الفاضية.
// يعتمد على `FTKit.swift` (الدرجات، الطبقات، الزمن، المواضع، FTKitCanvas).

nonisolated enum FTTileScenes {
    nonisolated enum Kind { case tree, diwaniya, library, projects, contact }

    /// يرسم شعار المربّع بملء مساحته (داخل `gradientBackground`).
    /// `badge`: كبسولة العدد ظاهرة (أعلى الجهة المقابلة للأيقونة، أي مكان الشعار نفسه) — فيتنحّى الشعار
    /// ولا يُرسم شيء: المربّع يبقى أيقونة + عدد + عنوان (كحاله حين يكون للمشروع شعار مصوّر). شعار مصغّر
    /// بين الكبسولة والأيقونة كان يزحم صفّ الرأس ويكرّر رمز الأيقونة.
    static func draw(_ kind: Kind, in ctx: inout GraphicsContext, size: CGSize, t: Double, badge: Bool = false) {
        drawWithEntrance(kind, in: &ctx, size: size, t: t, progress: 1, badge: badge)
    }

    /// نفس الرسم مع «الظهور» مرة واحدة: `progress` من ٠ إلى ١ — تلاشٍ للداخل وارتفاع ٦ نقاط (outCubic).
    static func drawWithEntrance(_ kind: Kind, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                                 progress: Double, badge: Bool = false) {
        guard size.width > 1, size.height > 1, !badge else { return }
        var c = ctx
        let p = min(1, max(0, progress))
        if p < 1 {
            let e = FTKit.Ease.outCubic(p)
            guard e > 0.001 else { return }
            c.opacity *= e
            c.translateBy(x: 0, y: FTKit.emergeRise * CGFloat(1 - e))
        }
        // الشعار دائماً في الجهة المقابلة للعنوان والأيقونة (يسار بالعربية، يمين بالإنجليزية)
        FTKit.mirrorForLTR(&c, width: size.width)
        let pal = FTKit.palette(.tile)
        let slot = ftTileSlot(kind, size: size, ltr: ctx.environment.layoutDirection == .leftToRight)
        let spec = ftSpec(kind)
        let k = slot.height / 100
        // توهّج واحد خلف مركز الشعار، يتنفّس معه
        let gc = CGPoint(x: slot.minX + spec.glowAt.x * k, y: slot.minY + spec.glowAt.y * k)
        let b = FTKit.breath(t)
        FTKit.glow(&c, at: gc, radius: slot.height * 0.62, opacity: pal.tones.glow + (pal.tones.glowPeak - pal.tones.glow) * b)
        var g = c
        ftPlace(&g, slot: slot, anchor: spec.anchor, tilt: spec.tilt, t: t)
        let ink = FTEmblemInk(pal, gap: max(FTKit.Stroke.gap, 1.0 / k), unit: k)
        switch kind {
        case .tree:     FTGhaf.draw(&g, ink, t: t)
        case .diwaniya: FTDallahArt.drawPouring(&g, ink, t: t)
        case .library:  FTRahl.drawOpen(&g, ink, t: t)
        case .projects: FTShop.drawOpen(&g, ink, t: t)
        case .contact:  FTEnvelope.draw(&g, ink, t: t)
        }
    }
}

// MARK: - الصفحات الفاضية

nonisolated enum FTEmptyScenes {
    /// شعار القسم في حالة «الانتظار» فوق قرص ساكن بحبر القسم (١٣٠×١٣٠ في `EmptyStateArt`).
    /// الديوانيات: دلّة قائمة تقطر في الفنجان · المشاريع: الدكّان مغلق وضوء تحت الباب ·
    /// المكتبة والشجرة والتواصل: شعار المربّع نفسه بهدوء.
    static func draw(_ kind: FTTileScenes.Kind, in ctx: inout GraphicsContext, size: CGSize, t: Double, tint: Color) {
        guard size.width > 1, size.height > 1 else { return }
        let dark = ctx.environment.colorScheme == .dark
        let pal = FTKit.palette(.light, tint: tint, dark: dark)
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // القرص: ساكن دائماً (لا يتنفّس)
        let r = side * 0.44
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                 with: .color(tint.opacity(pal.tones.plate)))
        let slot = FTKit.centerSlot(size, fraction: 0.62)
        let k = slot.height / 100
        var g = ctx
        FTKit.mirrorForLTR(&g, width: size.width)
        let ink = FTEmblemInk(pal, gap: max(FTKit.Stroke.gap, 1.0 / k), unit: k)
        switch kind {
        case .diwaniya:
            ftPlace(&g, slot: slot, anchor: CGPoint(x: 50, y: 98), tilt: 0, t: t)
            FTDallahArt.drawWaiting(&g, ink, t: t)
        case .projects:
            ftPlace(&g, slot: slot, anchor: CGPoint(x: 50, y: 92), tilt: 0, t: t)
            FTShop.drawClosed(&g, ink, t: t)
        case .library:
            // الكتاب المفتوح نفسه (الكتاب المغلق القائم على الرَّحْل كان يُقرأ كرسيّاً) — يرتفع ٦ وحدات
            // لأن الشعار (١٩…٩٧) أثقل من الأسفل، فيتوسّط القرص
            ftPlace(&g, slot: slot, anchor: CGPoint(x: 50, y: 92), tilt: 0, t: t)
            g.translateBy(x: 0, y: -6)
            FTRahl.drawOpen(&g, ink, t: t)
        case .tree:
            ftPlace(&g, slot: slot, anchor: CGPoint(x: 50, y: 96), tilt: 0, t: t)
            FTGhaf.draw(&g, ink, t: t)
        case .contact:
            ftPlace(&g, slot: slot, anchor: CGPoint(x: 50, y: 80), tilt: -8, t: t)
            FTEnvelope.draw(&g, ink, t: t)
        }
    }

    /// الصفحة الفاضية العامة: قرص بحبر القسم + نقطة ذهبية على حافته يتنفّس توهّجها (٤ ث).
    /// `icon`: رمز الصفحة يُرسم داخل القرص ويتنفّس (`FTKit.drawSymbolPlate`) — إن كان nil يُترك
    /// المنتصف لأيقونة يضعها المستدعي فوق اللوحة (السلوك القديم لـ `EmptyStateArt`).
    static func drawGeneric(in ctx: inout GraphicsContext, size: CGSize, t: Double, tint: Color, icon: String? = nil) {
        guard size.width > 1, size.height > 1 else { return }
        let dark = ctx.environment.colorScheme == .dark
        FTKit.drawSymbolPlate(icon ?? "", in: &ctx, size: size, t: t, tint: tint, dark: dark)
    }
}

// MARK: - الأغلفة (نفس الواجهة السابقة — بديل مباشر)

/// شعار مربّع الرئيسية بملء مساحته (داخل `gradientBackground`) — ٣٠ إطاراً/ث، ويقف عند t = 0 (لوحة
/// كاملة) مع «تقليل الحركة». `playsEntrance`: ظهور هادئ مرة واحدة (٠٫٩ ث) أول عرض للرئيسية.
/// `badge`: كبسولة العدد ظاهرة على المربّع ⇒ لا شعار (الكبسولة في مكانه).
struct FTTileSceneView: View {
    let kind: FTTileScenes.Kind
    var playsEntrance = false
    var badge = false

    // «الحالي» = الشكل القديم، المربّع بخلفيته فقط بلا رسم (طلب المالك ٢٠٢٦-١٠-٠٥)
    var body: some View { EmptyView() }

    private var oldBody: some View { EmptyView() }
}

/// رسمة الصفحة الفاضية (١٣٠×١٣٠ في EmptyStateArt) — `kind == nil` ⇒ الصفحة العامة (قرص + نقطة ذهبية،
/// و`icon` إن مُرّر يُرسم داخل القرص فلا حاجة لأيقونة فوق اللوحة). تظهر بهدوء عند كل عرض.
struct FTEmptySceneView: View {
    let kind: FTTileScenes.Kind?
    let tint: Color
    var icon: String? = nil

    var body: some View {
        let kind = self.kind
        let tint = self.tint
        let icon = self.icon
        FTKitCanvas(entrance: true) { ctx, size, t, _ in
            if let kind {
                FTEmptyScenes.draw(kind, in: &ctx, size: size, t: t, tint: tint)
            } else {
                FTEmptyScenes.drawGeneric(in: &ctx, size: size, t: t, tint: tint, icon: icon)
            }
        }
    }
}

// MARK: - أدوات خاصة

/// حبر الشعار لمكان واحد: اللون + الدرجتان + الذهبي، وعرض الفاصل المقصوص بوحدات الشبكة (≥ ١ نقطة)
nonisolated fileprivate struct FTEmblemInk {
    let ink: Color
    let body: Double
    let band: Double
    let gold: Color
    let glint: Color
    /// الفاصل المقصوص بوحدات الشبكة
    let gap: CGFloat
    /// نقاط لكل وحدة شبكة (لتحويل الأوزان المحدّدة بالنقاط)
    let unit: CGFloat

    init(_ p: FTKit.Palette, gap: CGFloat, unit: CGFloat) {
        ink = p.ink
        body = p.tones.body
        band = p.tones.band
        gold = p.goldFill
        glint = p.glint
        self.gap = gap
        self.unit = unit
    }

    /// ممحاة الفاصل: تمسح محيط الشكل الأمامي من الطبقة الخلفية (الشكل نفسه + خط بعرض ٢×الفاصل)
    /// `outline`: عرض خطّ يحيط بالشكل الأمامي نفسه (إن كان مدوّر الحافّة بخطّ) فيُضاف إلى الفاصل
    func cut(_ layer: GraphicsContext, _ front: Path, outline: CGFloat = 0) {
        let e = FTKit.eraser(layer)
        e.fill(front, with: .color(.black))
        e.stroke(front, with: .color(.black), style: StrokeStyle(lineWidth: 2 * gap + outline, lineJoin: .round))
    }
}

/// موضع الشعار ووسطه وميله لكل مربّع (شبكة ١٠٠ داخل المساحة المحجوزة)
nonisolated fileprivate struct FTTileSpec {
    /// نقطة التنفّس (قاعدة الشعار) بوحدات الشبكة
    let anchor: CGPoint
    /// مركز التوهّج بوحدات الشبكة
    let glowAt: CGPoint
    /// الميل الثابت بالدرجات (سالب = عكس عقارب الساعة)
    let tilt: Double
}

nonisolated fileprivate func ftSpec(_ kind: FTTileScenes.Kind) -> FTTileSpec {
    switch kind {
    case .tree:     return FTTileSpec(anchor: CGPoint(x: 50, y: 96), glowAt: CGPoint(x: 50, y: 40), tilt: 0)
    case .diwaniya: return FTTileSpec(anchor: CGPoint(x: 50, y: 92), glowAt: CGPoint(x: 50, y: 52), tilt: 0)
    case .library:  return FTTileSpec(anchor: CGPoint(x: 50, y: 90), glowAt: CGPoint(x: 50, y: 46), tilt: -6)
    case .projects: return FTTileSpec(anchor: CGPoint(x: 50, y: 92), glowAt: CGPoint(x: 50, y: 52), tilt: 0)
    case .contact:  return FTTileSpec(anchor: CGPoint(x: 50, y: 80), glowAt: CGPoint(x: 50, y: 50), tilt: -8)
    }
}

/// المساحة المحجوزة للشعار في المربّع (إحداثيات عربية؛ تُعكس في الإنجليزية).
/// • العريض: `FTKit.tileSlot` كما هو. وفي الإنجليزية عنوان الشجرة أطول (سطران حتى ثلثي المربّع)،
///   فتنتقل الشجرة إلى الحافة البعيدة وتصغر حتى يبقى تاجها كله داخل المربّع (لا قصّ بالحافة)
///   وجذعها ≥ ١٢ نقطة بعد نهاية «Ali».
/// • الضيّق (٣ أعمدة): العنوان يمتدّ أسفل المربّع كله تقريباً، فيرتفع الشعار إلى أعلى الجهة المقابلة
///   للأيقونة ويصغر حتى يبقى ≥ ١٢ نقطة فوق العنوان.
nonisolated fileprivate func ftTileSlot(_ kind: FTTileScenes.Kind, size: CGSize, ltr: Bool) -> CGRect {
    let wide = size.width / max(1, size.height) >= 1.5
    let h: CGFloat, cx: CGFloat, cy: CGFloat
    if wide {
        guard ltr, kind == .tree else { return FTKit.tileSlot(size) }
        h = size.height * 0.64
        cx = 2 + h / 2
        cy = size.height * 0.50
    } else {
        h = size.height * 0.58
        cx = size.width * 0.29
        cy = size.height * 0.38
    }
    return CGRect(x: cx - h / 2, y: cy - h / 2, width: h, height: h)
}

/// يضع الشعار: تنفّس حول قاعدته (بالنقاط) ← شبكة ١٠٠ داخل المساحة ← ميل ثابت حول وسط الشبكة
nonisolated fileprivate func ftPlace(_ ctx: inout GraphicsContext, slot: CGRect, anchor: CGPoint, tilt: Double, t: Double) {
    let k = min(slot.width, slot.height) / 100
    let a = CGPoint(x: slot.midX + (anchor.x - 50) * k, y: slot.midY + (anchor.y - 50) * k)
    FTKit.applyBreath(&ctx, anchor: a, t: t)
    FTKit.fit(&ctx, into: slot)
    if tilt != 0 {
        ctx.translateBy(x: 50, y: 50)
        ctx.rotate(by: .degrees(tilt))
        ctx.translateBy(x: -50, y: -50)
    }
}

/// «انسياب»: لمعة بطول ٣٠٪ تقطع المسار خطّياً داخل نافذة (ث) من دورة ٤ ث — لا شيء خارجها (ولا عند t = 0)
nonisolated fileprivate func ftGlide(_ t: Double, start: Double, length: Double, period: Double = 4) -> Double? {
    let x = FTKit.local(t, period: period)
    guard x >= start, x <= start + length else { return nil }
    return (x - start) / length
}

nonisolated fileprivate func ftP(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - الشجرة: غافة (شبكة ١٠٠ — التاج ٩٠ × الارتفاع ٨٣)

nonisolated fileprivate enum FTGhaf {
    /// فصّ «مظلّة»: قمّة مقوّسة هادئة، وقاع شبه مستوٍ، وطرفان يرقّان (حافّة المظلّة)
    static func lobe(_ x0: CGFloat, _ x1: CGFloat, base y: CGFloat, up: CGFloat, down: CGFloat) -> Path {
        let w = x1 - x0
        var p = Path()
        p.move(to: ftP(x0, y))
        p.addCurve(to: ftP(x0 + w * 0.5, y - up), control1: ftP(x0 + w * 0.04, y - up * 0.8), control2: ftP(x0 + w * 0.2, y - up))
        p.addCurve(to: ftP(x1, y), control1: ftP(x1 - w * 0.2, y - up), control2: ftP(x1 - w * 0.04, y - up * 0.8))
        p.addCurve(to: ftP(x0, y), control1: ftP(x1 - w * 0.22, y + down * 1.3), control2: ftP(x0 + w * 0.22, y + down * 1.3))
        p.closeSubpath()
        return p
    }
    /// الفصّ الخلفي: جهة اليسار، أدنى وأصغر — نسبة «المظلّة» ≈ ٣٫٢ : ١
    static let back = lobe(5, 60, base: 32, up: 13, down: 4.5)
    /// الفصّ الأمامي: جهة العنوان، أعلى وأعرض — يغطّي طرف الخلفي ويفصله فاصل مقصوص
    static let front = lobe(34, 95, base: 27, up: 14, down: 5.5)
    static let crown: Path = {
        var p = back
        p.addPath(front)
        return p
    }()
    /// تدوير طرفَي الفصّين (لا زوايا حادّة): خطّ مستدير بعرض ٣ بلون الشكل نفسه
    static let tipRound = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
    /// الجذع: قاعدة جذور قصيرة ← ساق ← تفرّع غير متناظر إلى غصنين يرقّان ويختفيان تحت التاج
    static let trunk: Path = {
        var p = Path()
        p.move(to: ftP(40, 96))
        p.addCurve(to: ftP(46.6, 86), control1: ftP(45, 95), control2: ftP(46.6, 91))
        p.addCurve(to: ftP(45.4, 67), control1: ftP(46.6, 78), control2: ftP(45.6, 72))
        p.addCurve(to: ftP(27, 38), control1: ftP(42, 56), control2: ftP(33, 46))
        p.addLine(to: ftP(31.5, 35.5))
        p.addCurve(to: ftP(50.6, 58), control1: ftP(38, 43), control2: ftP(47, 50))
        p.addCurve(to: ftP(63, 30), control1: ftP(54, 47), control2: ftP(59, 37))
        p.addLine(to: ftP(68, 32))
        p.addCurve(to: ftP(54.2, 68), control1: ftP(63, 44), control2: ftP(55, 56))
        p.addCurve(to: ftP(53.8, 86), control1: ftP(53.8, 74), control2: ftP(53.8, 80))
        p.addCurve(to: ftP(61, 96), control1: ftP(53.8, 91), control2: ftP(56, 95))
        p.closeSubpath()
        return p
    }()
    /// الثمرة الذهبية «نور العائلة»: معلّقة ملاصقة لحافة التاج السفلى جهة العنوان (لا تطفو منفصلة عنه)
    static let fruit = ftP(80, 35.6)

    static func draw(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        // الجذع (حزام) — يقصّه التاج بفاصل
        FTKit.tone(&c, opacity: ink.band) { l in
            l.fill(trunk, with: .color(ink.ink))
            ink.cut(l, crown, outline: tipRound.lineWidth)
        }
        // التاج (جسم): الفصّ الخلفي ثم الأمامي بفاصل بينهما
        FTKit.tone(&c, opacity: ink.body) { l in
            l.fill(back, with: .color(ink.ink))
            l.stroke(back, with: .color(ink.ink), style: tipRound)
            ink.cut(l, front, outline: tipRound.lineWidth)
            l.fill(front, with: .color(ink.ink))
            l.stroke(front, with: .color(ink.ink), style: tipRound)
        }
        // الحركة الثانوية: توهّج الثمرة بين ٠٫٥ و١ كل ٤ ث
        FTKit.goldPoint(&c, at: fruit, core: 3, glowRadius: 10,
                        intensity: 0.5 + 0.5 * FTKit.breath(t, period: 4), gold: ink.gold)
    }
}

// MARK: - الديوانيات: دلّة وفنجان (مسارات المقترح ب — شبكة المجموعة ٠…١٢٠)

nonisolated fileprivate enum FTDallahArt {
    /// وضع الصبّ: ميل ٢٠° حول وسط البطن
    static let pivot = ftP(44, 72)
    static let pour = CGAffineTransform(translationX: pivot.x, y: pivot.y)
        .rotated(by: 20 * .pi / 180)
        .translatedBy(x: -pivot.x, y: -pivot.y)
    static let tip = ftP(97, 32).applying(pour)

    static let finial: Path = {
        var p = Path()
        p.move(to: ftP(44, 2))
        p.addQuadCurve(to: ftP(47.4, 9.5), control: ftP(47.4, 5))
        p.addQuadCurve(to: ftP(45.4, 14), control: ftP(47.4, 12.4))
        p.addLine(to: ftP(45.4, 17.5)); p.addLine(to: ftP(42.6, 17.5)); p.addLine(to: ftP(42.6, 14))
        p.addQuadCurve(to: ftP(40.6, 9.5), control: ftP(40.6, 12.4))
        p.addQuadCurve(to: ftP(44, 2), control: ftP(40.6, 5))
        p.closeSubpath()
        return p
    }()
    static let lid: Path = {
        var p = Path()
        p.move(to: ftP(33.5, 28))
        p.addCurve(to: ftP(44, 16.6), control1: ftP(33.5, 21), control2: ftP(38, 16.6))
        p.addCurve(to: ftP(54.5, 28), control1: ftP(50, 16.6), control2: ftP(54.5, 21))
        p.closeSubpath()
        return p
    }()
    static let rim = Path(roundedRect: CGRect(x: 30.5, y: 29.4, width: 27, height: 3.2), cornerRadius: 1.6)
    static let neck: Path = {
        var p = Path()
        p.move(to: ftP(31.5, 33.8)); p.addLine(to: ftP(56.5, 33.8))
        p.addQuadCurve(to: ftP(48.5, 49.6), control: ftP(49.4, 39))
        p.addLine(to: ftP(39.5, 49.6))
        p.addQuadCurve(to: ftP(31.5, 33.8), control: ftP(38.6, 39))
        p.closeSubpath()
        return p
    }()
    static let ring = Path(roundedRect: CGRect(x: 37.4, y: 51, width: 13.2, height: 3.4), cornerRadius: 1.7)
    /// الأحزمة (القمّة · الغطاء · الحافة · الخصر) مسار واحد = عملية رسم واحدة
    static let bands: Path = {
        var p = finial
        p.addPath(lid); p.addPath(rim); p.addPath(ring)
        return p
    }()
    static let belly: Path = {
        var p = Path()
        p.move(to: ftP(49.5, 55.8))
        p.addCurve(to: ftP(65, 76), control1: ftP(58, 58.5), control2: ftP(65, 66))
        p.addCurve(to: ftP(54, 90), control1: ftP(65, 84.5), control2: ftP(60.5, 90))
        p.addLine(to: ftP(34, 90))
        p.addCurve(to: ftP(23, 76), control1: ftP(27.5, 90), control2: ftP(23, 84.5))
        p.addCurve(to: ftP(38.5, 55.8), control1: ftP(23, 66), control2: ftP(30, 58.5))
        p.closeSubpath()
        return p
    }()
    static let foot: Path = {
        var p = Path()
        p.move(to: ftP(37.5, 91.4)); p.addLine(to: ftP(50.5, 91.4))
        p.addQuadCurve(to: ftP(55, 97.5), control: ftP(51, 96))
        p.addLine(to: ftP(33, 97.5))
        p.addQuadCurve(to: ftP(37.5, 91.4), control: ftP(37, 96))
        p.closeSubpath()
        return p
    }()
    /// الصبّابة: تخرج من أسفل البطن وتنتهي بمنقار الدلّة المعقوف
    static let spout: Path = {
        var p = Path()
        p.move(to: ftP(60, 85))
        p.addCurve(to: ftP(83.6, 50.5), control1: ftP(72, 82.5), control2: ftP(79.5, 66))
        p.addCurve(to: ftP(97, 32), control1: ftP(85.6, 43.5), control2: ftP(90.5, 36))
        p.addCurve(to: ftP(78.6, 46), control1: ftP(90, 34), control2: ftP(82.6, 38.5))
        p.addCurve(to: ftP(60, 72), control1: ftP(75, 55), control2: ftP(69.5, 67))
        p.closeSubpath()
        return p
    }()
    static let handle: Path = {
        var p = Path()
        p.move(to: ftP(33, 36))
        p.addCurve(to: ftP(14.5, 54), control1: ftP(19, 33.5), control2: ftP(12.5, 44))
        p.addCurve(to: ftP(29, 70), control1: ftP(16.2, 62.5), control2: ftP(21, 68.5))
        return p
    }()
    /// العنق والبطن والقاعدة مسار واحد (لا تتراكب). الصبّابة تُعبّأ وحدها: اتّجاه رسمها معاكس للبطن،
    /// فدمجها في مسار واحد يُحدث ثقباً في موضع التقائهما (قاعدة non-zero).
    static let bodyFill: Path = {
        var p = neck
        p.addPath(belly); p.addPath(foot)
        return p
    }()

    static func cup(x: CGFloat, top y: CGFloat) -> Path {
        var p = Path()
        p.move(to: ftP(x - 10, y)); p.addLine(to: ftP(x + 10, y))
        p.addCurve(to: ftP(x + 5, y + 12), control1: ftP(x + 10, y + 6.5), control2: ftP(x + 8, y + 11))
        p.addLine(to: ftP(x - 5, y + 12))
        p.addCurve(to: ftP(x - 10, y), control1: ftP(x - 8, y + 11), control2: ftP(x - 10, y + 6.5))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: x - 4.5, y: y + 13.4, width: 9, height: 2.4), cornerSize: CGSize(width: 1.2, height: 1.2))
        return p
    }
    static func coffee(x: CGFloat, top y: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - 8.2, y: y - 1.2, width: 16.4, height: 2.8))
    }

    // الصبّ: الفنجان قائم تحت المنقار
    static let pourCupX: CGFloat = tip.x + 3
    static let pourCupTop: CGFloat = 90
    static let pourCup = cup(x: pourCupX, top: pourCupTop)
    static let pourCoffee = coffee(x: pourCupX, top: pourCupTop)
    /// خيط القهوة: يغادر المنقار بميل خفيف ثم يسقط في وسط الفنجان
    static let stream: Path = {
        var p = Path()
        p.move(to: tip)
        p.addQuadCurve(to: ftP(pourCupX, pourCupTop - 0.4), control: ftP(tip.x + 5.5, tip.y + 8))
        return p
    }()
    /// مركز مجموعة الصبّ (الدلّة المائلة + الفنجان) — يُطابَق على مركز المساحة المحجوزة
    static let pourCenter = ftP(70, 56)
    /// المجموعة ≈ ١٠٠ وحدة؛ تُصغَّر إلى ٠٫٩٢ من المساحة (مقياس ٠٫٧٢ من ارتفاع المربّع العريض)
    static let pourFit: CGFloat = 0.92

    /// مربّع الديوانيات: الدلّة تصبّ في الفنجان + لمعة كريمية تنساب في الخيط كل ٤ ث
    static func drawPouring(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        var g = c
        g.translateBy(x: 50, y: 50)
        g.scaleBy(x: pourFit, y: pourFit)
        g.translateBy(x: -pourCenter.x, y: -pourCenter.y)
        let u = ink.unit * pourFit           // نقاط لكل وحدة هنا
        FTKit.tone(&g, opacity: ink.body) { l in
            var d = l
            d.concatenate(pour)
            d.stroke(handle, with: .color(ink.ink), style: FTKit.Stroke.handle)
            d.fill(spout, with: .color(ink.ink))
            d.fill(bodyFill, with: .color(ink.ink))
        }
        FTKit.tone(&g, opacity: ink.band) { l in
            var d = l
            d.concatenate(pour)
            d.fill(bands, with: .color(ink.ink))
            l.fill(pourCup, with: .color(ink.ink))
        }
        // الذهبي: خيط القهوة (٢٫٣ نقطة) وسطحها في الفنجان — لا غير
        let w = 2.3 / max(0.01, u)
        g.stroke(stream, with: .color(ink.gold), style: FTKit.Stroke.round(w))
        g.fill(pourCoffee, with: .color(ink.gold))
        // انسياب: لمعة كريمية بطول ٣٠٪ داخل نافذة ١٫٢ ث من كل ٤ ث
        if let s = ftGlide(t, start: 2.0, length: 1.2) {
            let a = -0.3 + 1.3 * s
            let from = max(0, a), to = min(1, a + 0.3)
            if to > from {
                g.stroke(stream.trimmedPath(from: from, to: to), with: .color(ink.glint.opacity(0.95)),
                         style: FTKit.Stroke.round(w * 0.6))
            }
        }
    }

    // الانتظار (الصفحة الفاضية): الدلّة قائمة والفنجان بجانبها تحت المنقار على خط أرض شعري
    static let waitCupX: CGFloat = 97
    static let waitCupTop: CGFloat = 81.7
    static let waitCup = cup(x: waitCupX, top: waitCupTop)
    static let waitCoffee = coffee(x: waitCupX, top: waitCupTop)
    /// مركز مجموعة الانتظار (الدلّة القائمة ١٢٫٥…٩٧ + الفنجان حتى ١٠٧)
    static let waitCenter = ftP(60, 50)
    static let waitFit: CGFloat = 0.94

    /// الديوانيات الفاضية: قطرة ذهبية واحدة تتكوّن عند المنقار وتسقط في الفنجان (٣٫٠–٤٫٢ ث من ٨)
    static func drawWaiting(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        var g = c
        g.translateBy(x: 50, y: 50)
        g.scaleBy(x: waitFit, y: waitFit)
        g.translateBy(x: -waitCenter.x, y: -waitCenter.y)
        let u = ink.unit * waitFit
        // خط الأرض الشعري (١ نقطة) يتلاشى عند طرفيه
        var ground = Path()
        ground.move(to: ftP(6, 98.6)); ground.addLine(to: ftP(114, 98.6))
        g.stroke(ground, with: .linearGradient(Gradient(stops: [
            .init(color: ink.ink.opacity(0), location: 0),
            .init(color: ink.ink.opacity(0.25), location: 0.3),
            .init(color: ink.ink.opacity(0.25), location: 0.7),
            .init(color: ink.ink.opacity(0), location: 1)
        ]), startPoint: ftP(6, 98.6), endPoint: ftP(114, 98.6)), style: FTKit.Stroke.round(1 / max(0.01, u)))
        FTKit.tone(&g, opacity: ink.body) { l in
            l.stroke(handle, with: .color(ink.ink), style: FTKit.Stroke.handle)
            l.fill(spout, with: .color(ink.ink))
            l.fill(bodyFill, with: .color(ink.ink))
        }
        FTKit.tone(&g, opacity: ink.band) { l in
            l.fill(bands, with: .color(ink.ink))
            l.fill(waitCup, with: .color(ink.ink))
        }
        g.fill(waitCoffee, with: .color(ink.gold))
        // القطرة: تتكوّن عند المنقار (٣٫٠–٣٫٤) ثم تسقط بتسارع إلى سطح القهوة (٣٫٤–٤٫٢)
        let x = FTKit.local(t)
        if x > 3.0 && x < 4.2 {
            let grow = FTKit.progress(x, 3.0, 3.4, .smooth)
            let fall = FTKit.progress(x, 3.4, 4.2, .linear)
            let y = 33.5 + (waitCupTop - 1.5 - 33.5) * CGFloat(fall * fall)
            let r = 1.9 * CGFloat(grow)
            if r > 0.05 {
                var d = Path()
                // قطرة: دائرة بذيل علوي قصير يطول قليلاً أثناء السقوط
                let tail = r * (1.2 + 1.2 * CGFloat(fall))
                d.move(to: ftP(97, y - r - tail))
                d.addQuadCurve(to: ftP(97 + r, y), control: ftP(97 + r * 0.9, y - r * 0.9))
                d.addArc(center: ftP(97, y), radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                d.addQuadCurve(to: ftP(97, y - r - tail), control: ftP(97 - r * 0.9, y - r * 0.9))
                d.closeSubpath()
                g.fill(d, with: .color(ink.gold))
            }
        }
    }
}

// MARK: - المكتبة: كتاب مفتوح على رَحْل (شبكة ١٠٠ — ٨٨ × ٧٨)

nonisolated fileprivate enum FTRahl {
    /// الكتاب المفتوح: جناحان من الكعب، حافّتا الصفحتين منحنيتان قليلاً
    static let openBook: Path = {
        var p = Path()
        // الصفحة اليسرى
        p.move(to: ftP(50, 27))
        p.addCurve(to: ftP(6, 23), control1: ftP(38, 20), control2: ftP(18, 18))
        p.addLine(to: ftP(8, 55))
        p.addCurve(to: ftP(50, 61), control1: ftP(22, 51), control2: ftP(40, 52))
        p.closeSubpath()
        // الصفحة اليمنى
        p.move(to: ftP(50, 27))
        p.addCurve(to: ftP(94, 23), control1: ftP(62, 20), control2: ftP(82, 18))
        p.addLine(to: ftP(92, 55))
        p.addCurve(to: ftP(50, 61), control1: ftP(78, 51), control2: ftP(60, 52))
        p.closeSubpath()
        return p
    }()
    static let spine: Path = {
        var p = Path()
        p.move(to: ftP(50, 27)); p.addLine(to: ftP(50, 61))
        return p
    }()
    /// ساقا الرَّحْل (حزام): تتقاطعان مباشرة تحت الكعب (٥٠، ٦٤) ثم تنفرجان إلى القدمين على ٩٤ —
    /// هيئة الرَّحْل الحقيقية، لا علامة «X» كبيرة تحت الكتاب. طرفاهما العلويان مختفيان خلف الصفحتين.
    static let legs: Path = {
        let k: CGFloat = 1.75, cy: CGFloat = 64, top: CGFloat = 46, foot: CGFloat = 94
        var p = Path()
        p.move(to: ftP(50 - (cy - top) / k, top)); p.addLine(to: ftP(50 + (foot - cy) / k, foot))
        p.move(to: ftP(50 + (cy - top) / k, top)); p.addLine(to: ftP(50 - (foot - cy) / k, foot))
        return p
    }()
    static let legStyle = FTKit.Stroke.round(5.6)

    /// شريط علامة ذهبي (عرض ٣٫٦ ≈ ٢ نقطة على المربّع، وطرفه مشقوق V) يتدلّى من أسفل الصفحة البعيدة
    /// عن العنوان، بعيداً عن الساقين — معلّق من (٠،٠)
    static let ribbon: Path = {
        let w: CGFloat = 1.8, L: CGFloat = 13
        var p = Path()
        p.move(to: ftP(-w, 0)); p.addLine(to: ftP(w, 0))
        p.addLine(to: ftP(w, L)); p.addLine(to: ftP(0, L - 2.6)); p.addLine(to: ftP(-w, L))
        p.closeSubpath()
        return p
    }()
    /// نقطة التعليق: على حافة الصفحة اليسرى السفلى (منحنى الصفحة عند x ≈ ٢٦)
    static let ribbonPin = ftP(26, 52.9)

    /// الكتاب المفتوح على الرَّحْل — للمربّع وللصفحة الفاضية معاً (الشعار نفسه في المكانين).
    /// `ث`: الشريط الذهبي يتمايل ±٤° كل ٤ ث حول نقطة تعليقه (٠ عند t = 0).
    static func drawOpen(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        FTKit.tone(&c, opacity: ink.band) { l in
            l.stroke(legs, with: .color(ink.ink), style: legStyle)
            ink.cut(l, openBook)
        }
        FTKit.tone(&c, opacity: ink.body) { l in
            l.fill(openBook, with: .color(ink.ink))
            FTKit.eraser(l).stroke(spine, with: .color(.black), style: FTKit.Stroke.round(ink.gap))
        }
        var r = c
        r.translateBy(x: ribbonPin.x, y: ribbonPin.y)
        r.rotate(by: .degrees(4 * FTKit.sway(t, period: 4)))
        r.fill(ribbon, with: .color(ink.gold))
    }
}

// MARK: - المشاريع: واجهة دكّان (شبكة ١٠٠ — ٨٠ × ٨٤)

nonisolated fileprivate enum FTShop {
    /// المظلّة: سقف مائل خفيفاً وأربع تموّجات سفلية
    static let awning: Path = {
        var p = Path()
        p.move(to: ftP(10, 22))
        p.addLine(to: ftP(15, 11))
        p.addQuadCurve(to: ftP(18, 9), control: ftP(16, 9))
        p.addLine(to: ftP(82, 9))
        p.addQuadCurve(to: ftP(85, 11), control: ftP(84, 9))
        p.addLine(to: ftP(90, 22))
        // التموّجات من اليمين إلى اليسار (أنصاف دوائر نصف قطرها ١٠)
        for i in 0..<4 {
            let cx = 80 - CGFloat(i) * 20
            p.addArc(center: ftP(cx, 22), radius: 10, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }
        p.closeSubpath()
        return p
    }()
    /// كتلة الواجهة (تحت المظلّة) — الباب مفتوح حتى الأرض فيُقصّ لاحقاً
    static let block = Path(roundedRect: CGRect(x: 15, y: 24, width: 70, height: 68), cornerRadius: 2.5)
    /// فتحة الباب بقوس علوي: ٢٢ عرضاً، من ٥٠ إلى الأرض (٩٢)
    static let doorRect = CGRect(x: 25, y: 47, width: 22, height: 45)
    static let door: Path = {
        let r = doorRect
        var p = Path()
        p.move(to: ftP(r.minX, r.maxY + 2))
        p.addLine(to: ftP(r.minX, r.minY + r.width / 2))
        p.addArc(center: ftP(r.midX, r.minY + r.width / 2), radius: r.width / 2,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: ftP(r.maxX, r.maxY + 2))
        p.closeSubpath()
        return p
    }()
    static let window = Path(roundedRect: CGRect(x: 55, y: 50, width: 21, height: 19), cornerRadius: 3)
    static let holes: Path = {
        var p = door
        p.addPath(window)
        return p
    }()

    static func drawFacade(_ c: inout GraphicsContext, _ ink: FTEmblemInk) {
        FTKit.tone(&c, opacity: ink.body) { l in
            l.fill(block, with: .color(ink.ink))
            let e = FTKit.eraser(l)
            e.fill(holes, with: .color(.black))
            ink.cut(l, awning)
        }
    }

    /// مربّع المشاريع: الباب مفتوح و«ضوء العتبة» الذهبي عند أسفله يتنفّس توهّجه (٤ ث)
    static func drawOpen(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        drawFacade(&c, ink)
        FTKit.tone(&c, opacity: ink.band) { l in l.fill(awning, with: .color(ink.ink)) }
        let i = 0.5 + 0.5 * FTKit.breath(t, period: 4)
        let at = ftP(doorRect.midX, doorRect.maxY - 2)
        FTKit.glow(&c, at: at, radius: 12, color: ink.gold, opacity: 0.55 * i)
        c.fill(Path(roundedRect: CGRect(x: at.x - 6, y: at.y - 1.5, width: 12, height: 3), cornerRadius: 1.5),
               with: .color(ink.gold))
    }

    /// المشاريع الفاضية «قريباً»: الباب مغلق (لوح بدرجة الحزام) وشقّ ضوء ذهبي تحته يتّسع ٢→٥ ثم يعود
    static func drawClosed(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        drawFacade(&c, ink)
        let slit = 2 + 3 * CGFloat(FTKit.beat(t, start: 5.0, rise: 1.5, hold: 0, fall: 1.2))
        let r = doorRect.insetBy(dx: ink.gap, dy: 0)
        let panelBottom = r.maxY - slit - ink.gap
        FTKit.tone(&c, opacity: ink.band) { l in
            l.fill(awning, with: .color(ink.ink))
            var p = Path()
            p.move(to: ftP(r.minX, panelBottom))
            p.addLine(to: ftP(r.minX, doorRect.minY + doorRect.width / 2))
            p.addArc(center: ftP(r.midX, doorRect.minY + doorRect.width / 2), radius: r.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: ftP(r.maxX, panelBottom))
            p.closeSubpath()
            l.fill(p, with: .color(ink.ink))
        }
        c.fill(Path(roundedRect: CGRect(x: r.minX, y: r.maxY - slit, width: r.width, height: slit),
                    cornerRadius: min(1, slit / 2)), with: .color(ink.gold))
    }
}

// MARK: - التواصل: ظرف بختم شمع (شبكة ١٠٠ — ٨٦ × ٦٠)

nonisolated fileprivate enum FTEnvelope {
    static let body = Path(roundedRect: CGRect(x: 7, y: 20, width: 86, height: 60), cornerRadius: 7)
    static let sealCenter = ftP(50, 52)
    /// اللسان: مثلّث من الحافة العليا إلى الختم، بزوايا مستديرة
    static let flap: Path = {
        var p = Path()
        p.move(to: ftP(12, 20))
        p.addLine(to: ftP(88, 20))
        p.addLine(to: sealCenter)
        p.closeSubpath()
        return p
    }()
    static let seal = Path(ellipseIn: CGRect(x: sealCenter.x - 6, y: sealCenter.y - 6, width: 12, height: 12))

    static func draw(_ c: inout GraphicsContext, _ ink: FTEmblemInk, t: Double) {
        // الجسم (جسم): يُقصّ منه اللسان بفاصل — خطّا V فراغ
        FTKit.tone(&c, opacity: ink.body) { l in
            l.fill(body, with: .color(ink.ink))
            ink.cut(l, flap)
        }
        // اللسان (حزام) محصور داخل الظرف
        FTKit.tone(&c, opacity: ink.band) { l in
            var f = l
            f.clip(to: body)
            f.fill(flap, with: .color(ink.ink))
        }
        // الختم الذهبي على رأس اللسان
        c.fill(seal, with: .color(ink.gold))
        // انسياب: لمعة كريمية تعبر الختم مرة كل ٤ ث (نافذة ٠٫٨ ث)
        if let s = ftGlide(t, start: 2.0, length: 0.8) {
            var g = c
            g.clip(to: seal)
            let x = sealCenter.x - 10 + 20 * CGFloat(s)
            var band = Path()
            band.move(to: ftP(x - 1.6, sealCenter.y + 7)); band.addLine(to: ftP(x + 2.4, sealCenter.y - 7))
            band.addLine(to: ftP(x + 5.0, sealCenter.y - 7)); band.addLine(to: ftP(x + 1.0, sealCenter.y + 7))
            band.closeSubpath()
            g.fill(band, with: .color(ink.glint.opacity(0.9)))
        }
    }
}
