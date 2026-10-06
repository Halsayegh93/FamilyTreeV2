import SwiftUI

// MARK: - FTBoxMark — شعار رأس المربّعات الوسطى («الشعار المصمت»، ٢٠٢٦-١٠-٠٥)
//
// يحلّ محلّ العلامة المائية في `DSComposerHeader` (رمز SF كبير بـ ٩٪ يطفو ويُقصّ بالحافة + لمعة عابرة).
// الآن: شعار مصمت واحد هادئ في الجهة المقابلة للعنوان (يسار بالعربية، يمين بالإنجليزية)،
// داخل `FTKit.headerSlot` — لا يتجاوز ١٠٥ نقاط من الحافة، فلا يقترب من عمود العنوان (١٤٠ نقطة).
//
// • لعائلات المربّعات الشائعة شعار خاص بدرجتين بيضاوين ولمسة ذهبية واحدة ذات معنى:
//   خبر (جريدة) · ديوانية (دلّة تصبّ) · مشروع (دكّان) · عضو/ابن (غصن بورقة جديدة) · تواصل (ظرف بختم)
//   · أمان وشروط (درع بثقب مفتاح) · إعدادات (مفتاح بيت قديم) · وفاة (هلال ونجمة ساكنان، بلا ذهبي).
// • أي رمز آخر: النظام العام `FTKit.drawSymbolMark` — الرمز نفسه مصمتاً بدرجة الجسم، بلا ذهبي.
// • الدكّان والظرف والدلّة هي نفس شعارات مربّعات الرئيسية (مسارات واحدة) — شعار واحد للمكان أينما ظهر.
// • بلا توهّج خلف الشعار: هالة الرأس الموجودة تكفي، والمحيط الحادّ أوضح.
// • الحركة: تنفّس واحد ٨ ث للشعار كله + حركة واحدة للذهبي فقط (دورتها ٤ أو ٨ ث). اللمعات العابرة
//   تبدأ بعد ٢ ث من الدورة، فلا تتزاحم مع ظهور المربّع ونبضة الأيقونة ودخول العنوان. «وفاة» ساكنة تماماً.
// • t = 0 لوحة ساكنة كاملة (تقليل الحركة). ≤ ٧ عمليات رسم في الإطار. لا blur ولا صور.
//
// الدمج داخل `DSComposerHeader`: احذف `watermark` و`shineBand` وحالتي `shine` و`drift`، وضع مكانهما:
//
//     FTBoxMark(icon: icon, tint: tint)
//         .id("wm-\(icon)")
//         .transition(.opacity)
//
// (الإطار `.frame(maxWidth: .infinity).frame(height: 86)` داخل العرض نفسه — إطار الهالة ١٥٠ لا يمطّه.)

/// شعار رأس المربّع الأوسط لأي رمز SF. فوق شريط الرأس الملوّن (الافتراضي) الرسم أبيض وذهبي فقط
/// ولا يدخل لون المربّع فيه؛ `tint` يُستعمل حبراً حين يوضع الشعار على سطح محايد (`surface: .light`).
struct FTBoxMark: View {
    let icon: String
    let tint: Color
    var surface: FTKit.Surface
    var delay: Double
    var height: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(icon: String, tint: Color, surface: FTKit.Surface = .header,
         delay: Double = FTKit.headerMarkDelay, height: CGFloat = 86) {
        self.icon = icon
        self.tint = tint
        self.surface = surface
        self.delay = delay
        self.height = height
    }

    var body: some View {
        let icon = self.icon, tint = self.tint, surface = self.surface
        return Group {
            if FTHeaderMarks.isStill(icon) {
                // «وفاة»: لا تنفّس ولا ظهور — لوحة ثابتة عند t = 0
                let dark = colorScheme == .dark
                Canvas { ctx, size in
                    FTHeaderMarks.draw(icon: icon, in: &ctx, size: size, t: 0, tint: tint, surface: surface, dark: dark)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            } else {
                FTKitCanvas(entrance: true, delay: delay) { ctx, size, t, dark in
                    FTHeaderMarks.draw(icon: icon, in: &ctx, size: size, t: t, tint: tint, surface: surface, dark: dark)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

// MARK: - FTHeaderMarks — الشعارات الخاصة + الربط بعائلة الرمز

nonisolated enum FTHeaderMarks {

    /// عائلات المربّعات التي لها شعار خاص
    nonisolated enum Kind: CaseIterable {
        /// جريدة — سطر العنوان الذهبي يُمحى ثم يُكتب من اليمين (٨ ث)
        case news
        /// دلّة تصبّ في فنجان — لمعة تنساب في خيط القهوة (٤ ث)
        case diwaniya
        /// واجهة دكّان — يتنفّس ضوء العتبة (٤ ث)
        case project
        /// غصن بثلاث ورقات — الورقة الذهبية الجديدة تتمايل ±٥° (٤ ث)
        case member
        /// ظرف بختم شمع — لمعة تعبر الختم (٤ ث)
        case contact
        /// درع بثقب مفتاح — يتنفّس الضوء داخل الثقب (٤ ث)
        case security
        /// مفتاح بيت قديم — الشرّابة الذهبية المعلّقة من الحلقة تتمايل ±٤° (٤ ث)
        case settings
        /// هلال ونجمة بدرجة الجسم — ساكن تماماً، بلا ذهبي
        case mourning
    }

    /// عائلة الرمز (بالبادئة: `envelope` يشمل `envelope.fill` و`envelope.open.fill`…) — nil ← النظام العام
    static func kind(for icon: String) -> Kind? {
        for (kind, prefixes) in families where prefixes.contains(where: { ftbxMatches(icon, $0) }) {
            return kind
        }
        return nil
    }

    /// «وفاة» تُعرض ساكنة (بلا `TimelineView`)
    static func isStill(_ icon: String) -> Bool { kind(for: icon) == .mourning }

    /// الترتيب مهم: الأخصّ أولاً (`person.badge.shield…` أمان، `person.badge.key…` إعدادات، ثم بقية `person…`)
    /// خارج الربط عمداً (يأخذ النظام العام، أي رمزه نفسه): `book.pages` هو «دليل الاستخدام» لا الأمان،
    /// و`arrow.up.arrow.down` هو «ترتيب الأبناء» لا الإعدادات — الشعار الخاص يجب أن يحمل معنى المربّع.
    private static let families: [(Kind, [String])] = [
        (.mourning, ["heart.slash"]),
        (.security, ["lock.shield", "checkmark.shield", "person.badge.shield.checkmark", "shield", "lock",
                     "doc.text"]),
        (.settings, ["gearshape", "slider.horizontal.3", "paintbrush", "person.badge.key", "key",
                     "iphone"]),
        (.member, ["person.crop.circle.badge.plus", "person.crop.circle.badge.checkmark", "person.badge.plus",
                   "person.2", "person.line.dotted.person", "figure.child", "tree"]),
        (.news, ["newspaper", "megaphone", "chart.bar"]),
        (.diwaniya, ["map", "mappin", "cup.and.saucer", "tent", "building.columns"]),
        (.project, ["briefcase", "storefront", "bag"]),
        (.contact, ["envelope"])
    ]

    /// نقطة الدخول الواحدة: شعار خاص إن وُجد، وإلا النظام العام. ارسم بملء شريط الرأس.
    static func draw(icon: String, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                     tint: Color? = nil, surface: FTKit.Surface = .header, dark: Bool = false) {
        let palette = FTKit.palette(surface, tint: tint, dark: dark)
        if let kind = kind(for: icon) {
            draw(kind, in: &ctx, size: size, t: t, palette: palette)
        } else {
            drawGeneric(icon, in: &ctx, size: size, t: t, surface: surface, palette: palette)
        }
    }

    /// يرسم شعار العائلة بملء شريط الرأس (٨٦ نقطة)، في الجهة المقابلة للعنوان، مائلاً −٩°.
    static func draw(_ kind: Kind, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                     palette: FTKit.Palette = FTKit.palette(.header)) {
        guard size.width > 1, size.height > 1 else { return }
        let still = kind == .mourning
        let t = still ? 0 : t

        var c = ctx
        FTKit.mirrorForLTR(&c, width: size.width)          // الإنجليزية: الشعار كله يُعكس إلى اليمين
        let slot = FTKit.headerSlot(size, rtl: true)
        let center = CGPoint(x: slot.midX, y: slot.midY)

        // بلا توهّج خلف الشعار: الرأس فيه هالته أصلاً (أعلى جهة الأيقونة)، والتوهّج الأبيض خلف شكل أبيض
        // بـ ١١٪ كان يطمس محيطه ويظهر قرصاً فاتحاً — المحيط الحادّ وحده أقوى وأبسط.
        if !still { FTKit.applyBreath(&c, anchor: center, t: t) }
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .degrees(FTBxDraw.tilt))
        c.translateBy(x: -center.x, y: -center.y)
        FTKit.fit(&c, into: slot)
        let unit = slot.height / 100                        // نقاط لكل وحدة من الشبكة

        switch kind {
        case .news: FTBxDraw.news(&c, t: t, p: palette)
        case .diwaniya: FTBxDraw.diwaniya(&c, t: t, p: palette, unit: unit)
        case .project: FTBxDraw.project(&c, t: t, p: palette)
        case .member: FTBxDraw.member(&c, t: t, p: palette)
        case .contact: FTBxDraw.contact(&c, t: t, p: palette)
        case .security: FTBxDraw.security(&c, t: t, p: palette)
        case .settings: FTBxDraw.settings(&c, t: t, p: palette)
        case .mourning: FTBxDraw.mourning(&c, p: palette)
        }
    }

    /// النظام العام: فوق الألوان هو `FTKit.drawSymbolMark` كما هو؛ وفوق سطح محايد الرمز نفسه بحبر القسم.
    private static func drawGeneric(_ icon: String, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                                    surface: FTKit.Surface, palette: FTKit.Palette) {
        switch surface {
        case .tile, .header, .backdrop:
            // كما هو في الأدوات (المعتمد): الرمز وحده بدرجة الجسم، بلا توهّج ولا ذهبي
            FTKit.drawSymbolMark(icon, in: &ctx, size: size, t: t, surface: surface)
        case .light, .glyph:
            guard size.width > 1, size.height > 1, !icon.isEmpty else { return }
            let rtl = ctx.environment.layoutDirection == .rightToLeft
            let slot = FTKit.headerSlot(size, rtl: rtl)
            let center = CGPoint(x: slot.midX, y: slot.midY)
            var c = ctx
            FTKit.applyBreath(&c, anchor: center, t: t)
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: .degrees(rtl ? FTBxDraw.tilt : -FTBxDraw.tilt))
            let glyph = c.resolve(Text(Image(systemName: icon))
                .font(.system(size: slot.height * 0.70, weight: .bold))
                .foregroundColor(palette.ink))
            FTKit.tone(&c, opacity: palette.tones.body) { l in l.draw(glyph, at: .zero, anchor: .center) }
        }
    }
}

// MARK: - أدوات خاصة

/// `envelope` يطابق `envelope` و`envelope.fill`… ولا يطابق `envelopes`
nonisolated fileprivate func ftbxMatches(_ icon: String, _ prefix: String) -> Bool {
    icon == prefix || icon.hasPrefix(prefix + ".")
}

nonisolated fileprivate func ftbxP(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// الرسوم نفسها — كل شعار على شبكة ١٠٠ داخل السياق المحوَّل (الميل والتنفّس مطبّقان مسبقاً)
nonisolated fileprivate enum FTBxDraw {
    /// ميل الشعار في العربية (الإنجليزية تعكسه)
    static let tilt: Double = -9

    // MARK: خبر — جريدة بورقتين؛ سطر العنوان الذهبي «يُكتب»

    static func news(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(FTBxPaper.back, with: .color(p.ink))
            let e = FTKit.eraser(l)
            e.stroke(FTBxPaper.front, with: .color(.black), lineWidth: 5.6)      // فاصل بين الورقتين
            l.fill(FTBxPaper.front, with: .color(p.ink))
            e.fill(FTBxPaper.holes, with: .color(.black))                         // الأسطر وخانتا العنوان والصورة
        }
        c.fill(FTBxPaper.photo, with: .color(p.band))

        // سطر العنوان: يُمحى بين ٥٫٠ و٥٫٨ ث ثم يُكتب من اليمين بين ٦٫٣ و٧٫٧ ث. يتغيّر عرضه لا شفافيته.
        let x = FTKit.local(t)
        let r = FTBxPaper.headline
        var x0 = r.minX, x1 = r.maxX
        if x < 6.3 {
            x1 = r.maxX - r.width * CGFloat(FTKit.progress(x, 5.0, 5.8))
        } else {
            x0 = r.maxX - r.width * CGFloat(FTKit.progress(x, 6.3, 7.7))
        }
        if x1 - x0 > 0.5 {
            c.fill(Path(roundedRect: CGRect(x: x0, y: r.minY, width: x1 - x0, height: r.height),
                        cornerRadius: min(r.height, x1 - x0) / 2),
                   with: .color(p.goldFill))
        }
    }

    // MARK: ديوانية — دلّة مائلة تصبّ في فنجان؛ لمعة تنساب في خيط القهوة

    static func diwaniya(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette, unit: CGFloat) {
        var g = c
        g.concatenate(FTBxDallah.toGrid)
        FTKit.tone(&g, opacity: p.tones.body) { l in
            l.fill(FTBxDallah.body, with: .color(p.ink))
            l.stroke(FTBxDallah.handle, with: .color(p.ink), style: FTKit.Stroke.handle)
        }
        FTKit.tone(&g, opacity: p.tones.band) { l in
            l.fill(FTBxDallah.bandsAndCup, with: .color(p.ink))
        }
        // الذهبي: خيط القهوة (٢ نقطة) وسطحها في الفنجان
        let px = 1 / (unit * FTBxDallah.scale)                       // نقطة واحدة بوحدات الدلّة
        g.stroke(FTBxDallah.stream, with: .color(p.goldFill), style: FTKit.Stroke.round(2.0 * px))
        g.fill(FTBxDallah.coffee, with: .color(p.goldFill))
        // انسياب: لمعة بطول ٣٠٪ تعبر الخيط بين ٢٫٤ و٣٫٦ ث من كل ٤ ث — بعد أن يستقرّ المربّع ودخول
        // العنوان (لا حركة ثانوية في أول ثانيتين)، ولا شيء عند t = 0
        let u = (FTKit.local(t, period: 4) - 2.4) / 1.2
        if u > 0, u < 1 {
            let a = CGFloat(u) * 1.3 - 0.3
            let from = max(0, a), to = min(1, a + 0.3)
            if to > from {
                g.stroke(FTBxDallah.stream.trimmedPath(from: from, to: to), with: .color(p.glint),
                         style: FTKit.Stroke.round(1.3 * px))
            }
        }
    }

    // MARK: مشروع — واجهة دكّان بمظلّة؛ ضوء العتبة يتنفّس

    static func project(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        // نفس دكّان مربّع «مشاريع العائلة» في الرئيسية: الكتلة يُقصّ منها الباب والنافذة والمظلّة بفاصل
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(FTBxShop.block, with: .color(p.ink))
            let e = FTKit.eraser(l)
            e.fill(FTBxShop.holes, with: .color(.black))                          // الباب المقوّس والنافذة
            e.fill(FTBxShop.awning, with: .color(.black))                         // مكان المظلّة + الفاصل
            e.stroke(FTBxShop.awning, with: .color(.black),
                     style: StrokeStyle(lineWidth: 2 * FTKit.Stroke.gap, lineJoin: .round))
        }
        c.fill(FTBxShop.awning, with: .color(p.band))
        // ضوء العتبة: قضيب ذهبي عند أسفل فتحة الباب، توهّجه بين ٠٫٥ و١ كل ٤ ث
        let k = 0.5 + 0.5 * FTKit.breath(t, period: 4)
        FTKit.glow(&c, at: FTBxShop.sill, radius: 12, color: p.gold, opacity: 0.55 * k)
        c.fill(Path(roundedRect: CGRect(x: FTBxShop.sill.x - 6, y: FTBxShop.sill.y - 1.3, width: 12, height: 2.6),
                    cornerRadius: 1.3),
               with: .color(p.goldFill))
    }

    // MARK: عضو أو ابن — غصن منحنٍ بورقتين، والورقة العليا الذهبية «الجديدة» تتمايل

    static func member(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        c.stroke(FTBxSprig.branch, with: .color(p.band), style: FTKit.Stroke.round(5.6))
        c.fill(FTBxSprig.leaves, with: .color(p.body))
        // تمايل ±٥° حول نقطة اتصالها بالغصن، كل ٤ ث — في مكانها عند t = 0
        var g = c
        let a = FTBxSprig.newLeafBase
        g.translateBy(x: a.x, y: a.y)
        g.rotate(by: .degrees(5 * FTKit.sway(t, period: 4)))
        g.translateBy(x: -a.x, y: -a.y)
        g.fill(FTBxSprig.newLeaf, with: .color(p.goldFill))
    }

    // MARK: تواصل — ظرف بلسان مثلّث بدرجة الحزام؛ لمعة تعبر ختم الشمع

    static func contact(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        // نفس ظرف مربّع «التواصل» في الرئيسية: الجسم بدرجة الجسم، واللسان مثلّث بدرجة الحزام يفصله فاصل
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(FTBxEnvelope.body, with: .color(p.ink))
            let e = FTKit.eraser(l)
            e.fill(FTBxEnvelope.flap, with: .color(.black))
            e.stroke(FTBxEnvelope.flap, with: .color(.black),
                     style: StrokeStyle(lineWidth: 2 * FTKit.Stroke.gap, lineJoin: .round))
        }
        var f = c
        f.clip(to: FTBxEnvelope.body)
        f.fill(FTBxEnvelope.flap, with: .color(p.band))
        c.fill(FTBxEnvelope.seal, with: .color(p.goldFill))
        // انسياب: شريط كريمي مائل يعبر الختم بين ٢٫٠ و٢٫٨ ث من كل ٤ ث (بعد استقرار المربّع)
        let u = (FTKit.local(t, period: 4) - 2.0) / 0.8
        if u > 0, u < 1 {
            var g = c
            g.clip(to: FTBxEnvelope.seal)
            let s = FTBxEnvelope.sealCenter
            let x = s.x - 10 + 20 * CGFloat(u)
            g.translateBy(x: x, y: s.y)
            g.rotate(by: .degrees(28))
            g.fill(Path(CGRect(x: -1.8, y: -10, width: 3.6, height: 20)), with: .color(p.glint.opacity(0.9)))
        }
    }

    // MARK: أمان وشروط — درع بثقب مفتاح؛ ضوء ذهبي يتنفّس داخل الثقب

    static func security(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(FTBxShield.body, with: .color(p.ink))
            let e = FTKit.eraser(l)
            e.fill(FTBxShield.keyRound, with: .color(.black))
            e.fill(FTBxShield.keyStem, with: .color(.black))
        }
        let k = 0.5 + 0.5 * FTKit.breath(t, period: 4)
        FTKit.goldPoint(&c, at: FTBxShield.light, core: 3.1, glowRadius: 8.5, intensity: k, gold: p.gold)
    }

    // MARK: إعدادات — مفتاح بيت قديم؛ شرّابة ذهبية معلّقة من الحلقة تتمايل

    static func settings(_ c: inout GraphicsContext, t: Double, p: FTKit.Palette) {
        FTKit.tone(&c, opacity: p.tones.band) { l in
            l.fill(FTBxKey.bow, with: .color(p.ink))
            FTKit.eraser(l).fill(FTBxKey.bowHole, with: .color(.black))
        }
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(FTBxKey.shaftAndBit, with: .color(p.ink))
            FTKit.eraser(l).fill(FTBxKey.notch, with: .color(.black))
        }
        // الشرّابة تتدلّى رأسياً على الشاشة (تعوّض ميل الشعار) وتتمايل ±٤° كل ٤ ث — شكل واحد = عملية واحدة
        var g = c
        let a = FTBxKey.hook
        g.translateBy(x: a.x, y: a.y)
        g.rotate(by: .degrees(-tilt + 4 * FTKit.sway(t, period: 4)))
        g.fill(FTBxKey.tassel, with: .color(p.goldFill))
    }

    // MARK: وفاة — هلال ونجمة بدرجة الجسم، ساكنان

    static func mourning(_ c: inout GraphicsContext, p: FTKit.Palette) {
        FTKit.tone(&c, opacity: p.tones.body) { l in
            l.fill(FTBxCrescent.disc, with: .color(p.ink))
            FTKit.eraser(l).fill(FTBxCrescent.bite, with: .color(.black))
            l.fill(FTBxCrescent.star, with: .color(p.ink))
        }
    }
}

// MARK: - المسارات (شبكة ١٠٠ — تُبنى مرة واحدة)

/// الجريدة (من المقترح ب كما هو، بسطرين أقلّ)
nonisolated fileprivate enum FTBxPaper {
    static let front = Path(roundedRect: CGRect(x: 16, y: 12, width: 70, height: 84), cornerRadius: 8)
    static let back = Path(roundedRect: CGRect(x: 6, y: 3, width: 70, height: 84), cornerRadius: 8)
    static let headlineSlot = CGRect(x: 25, y: 21, width: 52, height: 10)
    static let headline = CGRect(x: 26.8, y: 22.8, width: 48.4, height: 6.4)
    static let photoRect = CGRect(x: 25, y: 38, width: 24, height: 22)
    static let photo = Path(roundedRect: photoRect.insetBy(dx: 1.6, dy: 1.6), cornerRadius: 2.6)
    /// كل الفراغات مسار واحد = عملية رسم واحدة. الأسطر محاذاة يمين (عربي).
    static let holes: Path = {
        var p = Path()
        p.addRoundedRect(in: headlineSlot, cornerSize: CGSize(width: 5, height: 5))
        p.addRoundedRect(in: photoRect, cornerSize: CGSize(width: 3.5, height: 3.5))
        for r in [CGRect(x: 54, y: 39, width: 23, height: 4.4), CGRect(x: 54, y: 47, width: 23, height: 4.4),
                  CGRect(x: 60, y: 55, width: 17, height: 4.4), CGRect(x: 25, y: 68, width: 52, height: 4.4),
                  CGRect(x: 39, y: 77, width: 38, height: 4.4)] {
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 2.2, height: 2.2))
        }
        return p
    }()
}

/// الدلّة والفنجان (من المقترح ب كما هما) — مرسومة بوحداتها ثم تُحجَّم لتملأ شبكة ١٠٠
nonisolated fileprivate enum FTBxDallah {
    static let pivot = ftbxP(44, 72)
    /// وضع الصبّ: ميل ٢٠° حول وسط البطن
    static let pour = CGAffineTransform(translationX: pivot.x, y: pivot.y)
        .rotated(by: 20 * .pi / 180)
        .translatedBy(x: -pivot.x, y: -pivot.y)
    static let tip = ftbxP(97, 32).applying(pour)

    static let finial: Path = {
        var p = Path()
        p.move(to: ftbxP(44, 2))
        p.addQuadCurve(to: ftbxP(47.4, 9.5), control: ftbxP(47.4, 5))
        p.addQuadCurve(to: ftbxP(45.4, 14), control: ftbxP(47.4, 12.4))
        p.addLine(to: ftbxP(45.4, 17.5)); p.addLine(to: ftbxP(42.6, 17.5)); p.addLine(to: ftbxP(42.6, 14))
        p.addQuadCurve(to: ftbxP(40.6, 9.5), control: ftbxP(40.6, 12.4))
        p.addQuadCurve(to: ftbxP(44, 2), control: ftbxP(40.6, 5))
        p.closeSubpath()
        return p
    }()
    static let lid: Path = {
        var p = Path()
        p.move(to: ftbxP(33.5, 28))
        p.addCurve(to: ftbxP(44, 16.6), control1: ftbxP(33.5, 21), control2: ftbxP(38, 16.6))
        p.addCurve(to: ftbxP(54.5, 28), control1: ftbxP(50, 16.6), control2: ftbxP(54.5, 21))
        p.closeSubpath()
        return p
    }()
    static let rim = Path(roundedRect: CGRect(x: 30.5, y: 29.4, width: 27, height: 3.2), cornerRadius: 1.6)
    static let ring = Path(roundedRect: CGRect(x: 37.4, y: 51, width: 13.2, height: 3.4), cornerRadius: 1.7)
    static let neck: Path = {
        var p = Path()
        p.move(to: ftbxP(31.5, 33.8)); p.addLine(to: ftbxP(56.5, 33.8))
        p.addQuadCurve(to: ftbxP(48.5, 49.6), control: ftbxP(49.4, 39))
        p.addLine(to: ftbxP(39.5, 49.6))
        p.addQuadCurve(to: ftbxP(31.5, 33.8), control: ftbxP(38.6, 39))
        p.closeSubpath()
        return p
    }()
    static let belly: Path = {
        var p = Path()
        p.move(to: ftbxP(49.5, 55.8))
        p.addCurve(to: ftbxP(65, 76), control1: ftbxP(58, 58.5), control2: ftbxP(65, 66))
        p.addCurve(to: ftbxP(54, 90), control1: ftbxP(65, 84.5), control2: ftbxP(60.5, 90))
        p.addLine(to: ftbxP(34, 90))
        p.addCurve(to: ftbxP(23, 76), control1: ftbxP(27.5, 90), control2: ftbxP(23, 84.5))
        p.addCurve(to: ftbxP(38.5, 55.8), control1: ftbxP(23, 66), control2: ftbxP(30, 58.5))
        p.closeSubpath()
        return p
    }()
    static let foot: Path = {
        var p = Path()
        p.move(to: ftbxP(37.5, 91.4)); p.addLine(to: ftbxP(50.5, 91.4))
        p.addQuadCurve(to: ftbxP(55, 97.5), control: ftbxP(51, 96))
        p.addLine(to: ftbxP(33, 97.5))
        p.addQuadCurve(to: ftbxP(37.5, 91.4), control: ftbxP(37, 96))
        p.closeSubpath()
        return p
    }()
    static let spout: Path = {
        var p = Path()
        p.move(to: ftbxP(60, 85))
        p.addCurve(to: ftbxP(83.6, 50.5), control1: ftbxP(72, 82.5), control2: ftbxP(79.5, 66))
        p.addCurve(to: ftbxP(97, 32), control1: ftbxP(85.6, 43.5), control2: ftbxP(90.5, 36))
        p.addCurve(to: ftbxP(78.6, 46), control1: ftbxP(90, 34), control2: ftbxP(82.6, 38.5))
        p.addCurve(to: ftbxP(60, 72), control1: ftbxP(75, 55), control2: ftbxP(69.5, 67))
        p.closeSubpath()
        return p
    }()
    static let handleRaw: Path = {
        var p = Path()
        p.move(to: ftbxP(33, 36))
        p.addCurve(to: ftbxP(14.5, 54), control1: ftbxP(19, 33.5), control2: ftbxP(12.5, 44))
        p.addCurve(to: ftbxP(29, 70), control1: ftbxP(16.2, 62.5), control2: ftbxP(21, 68.5))
        return p
    }()

    /// الجسم بدرجة واحدة: الرقبة والبطن والقاعدة والصبّابة مسار واحد (مائل للصبّ)
    static let body: Path = {
        var p = neck
        p.addPath(belly); p.addPath(foot); p.addPath(spout)
        return p.applying(pour)
    }()
    static let handle = handleRaw.applying(pour)

    // الفنجان قائم تحت المنقار
    static let cupTop: CGFloat = 90
    static let cupX: CGFloat = tip.x + 3
    static let cup: Path = {
        let x = cupX, y = cupTop
        var p = Path()
        p.move(to: ftbxP(x - 10, y)); p.addLine(to: ftbxP(x + 10, y))
        p.addCurve(to: ftbxP(x + 5, y + 12), control1: ftbxP(x + 10, y + 6.5), control2: ftbxP(x + 8, y + 11))
        p.addLine(to: ftbxP(x - 5, y + 12))
        p.addCurve(to: ftbxP(x - 10, y), control1: ftbxP(x - 8, y + 11), control2: ftbxP(x - 10, y + 6.5))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: x - 4.5, y: y + 13.4, width: 9, height: 2.4), cornerSize: CGSize(width: 1.2, height: 1.2))
        return p
    }()
    /// الدرجة الثانية: القمّة والغطاء والحافة والخصر (مائلة) + الفنجان — عملية رسم واحدة
    static let bandsAndCup: Path = {
        var p = finial
        p.addPath(lid); p.addPath(rim); p.addPath(ring)
        var all = p.applying(pour)
        all.addPath(cup)
        return all
    }()
    static let coffee = Path(ellipseIn: CGRect(x: cupX - 8.2, y: cupTop - 1.2, width: 16.4, height: 2.8))
    static let stream: Path = {
        var p = Path()
        p.move(to: tip)
        p.addQuadCurve(to: ftbxP(cupX, cupTop - 0.4), control: ftbxP(tip.x + 5.5, tip.y + 8))
        return p
    }()

    /// حدود المجموعة كلها ← شبكة ١٠٠ (الضلع الأطول = ١٠٠، والمجموعة في الوسط)
    static let bounds: CGRect = {
        var p = body
        p.addPath(bandsAndCup)
        return p.boundingRect.union(handle.boundingRect.insetBy(dx: -2.3, dy: -2.3))
    }()
    static let scale: CGFloat = 100 / max(bounds.width, bounds.height)
    static let toGrid = CGAffineTransform(translationX: 50, y: 50)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
}

/// واجهة الدكّان — نفس مسارات مربّع «مشاريع العائلة» (`FTShop` في FTTileScenes) حتى يكون الشعار واحداً
/// في المكانين: كتلة يُقصّ منها باب مقوّس مفتوح حتى الأرض ونافذة، ومظلّة بأربع تموّجات نصف دائرية.
nonisolated fileprivate enum FTBxShop {
    static let awning: Path = {
        var p = Path()
        p.move(to: ftbxP(10, 22))
        p.addLine(to: ftbxP(15, 11))
        p.addQuadCurve(to: ftbxP(18, 9), control: ftbxP(16, 9))
        p.addLine(to: ftbxP(82, 9))
        p.addQuadCurve(to: ftbxP(85, 11), control: ftbxP(84, 9))
        p.addLine(to: ftbxP(90, 22))
        for i in 0..<4 {                                   // التموّجات من اليمين إلى اليسار (نصف قطرها ١٠)
            let cx = 80 - CGFloat(i) * 20
            p.addArc(center: ftbxP(cx, 22), radius: 10, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }
        p.closeSubpath()
        return p
    }()
    /// الكتلة تمتدّ تحت المظلّة، والمظلّة تُقصّ منها بفاصل ١٫٤
    static let block = Path(roundedRect: CGRect(x: 15, y: 24, width: 70, height: 68), cornerRadius: 2.5)
    static let doorRect = CGRect(x: 25, y: 47, width: 22, height: 45)
    static let holes: Path = {
        let r = doorRect
        var p = Path()
        p.move(to: ftbxP(r.minX, r.maxY + 2))
        p.addLine(to: ftbxP(r.minX, r.minY + r.width / 2))
        p.addArc(center: ftbxP(r.midX, r.minY + r.width / 2), radius: r.width / 2,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: ftbxP(r.maxX, r.maxY + 2))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: 55, y: 50, width: 21, height: 19), cornerSize: CGSize(width: 3, height: 3))
        return p
    }()
    /// ضوء العتبة: أسفل فتحة الباب
    static let sill = ftbxP(doorRect.midX, doorRect.maxY - 2)
}

/// الغصن: منحنى واحد، ورقتان بدرجة الجسم، والورقة العليا الجديدة ذهبية
nonisolated fileprivate enum FTBxSprig {
    static let p0 = ftbxP(30, 95), c1 = ftbxP(26, 66), c2 = ftbxP(40, 34), p3 = ftbxP(64, 19)

    static let branch: Path = {
        var p = Path()
        p.move(to: p0)
        p.addCurve(to: p3, control1: c1, control2: c2)
        return p
    }()

    static func point(_ s: CGFloat) -> CGPoint {
        let u = 1 - s
        let a = u * u * u, b = 3 * u * u * s, c = 3 * u * s * s, d = s * s * s
        return ftbxP(a * p0.x + b * c1.x + c * c2.x + d * p3.x, a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    static func direction(_ s: CGFloat) -> CGFloat {
        let u = 1 - s
        let dx = 3 * u * u * (c1.x - p0.x) + 6 * u * s * (c2.x - c1.x) + 3 * s * s * (p3.x - c2.x)
        let dy = 3 * u * u * (c1.y - p0.y) + 6 * u * s * (c2.y - c1.y) + 3 * s * s * (p3.y - c2.y)
        return atan2(dy, dx)
    }

    /// ورقة عدسية من قاعدتها باتجاه `angle`: عرضها `width` وأعرض نقطة فيها عند ٤٠٪ من طولها
    static func leaf(base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) -> Path {
        let d = ftbxP(cos(angle), sin(angle)), n = ftbxP(-sin(angle), cos(angle))
        func at(_ a: CGFloat, _ o: CGFloat) -> CGPoint {
            ftbxP(base.x + d.x * a + n.x * o, base.y + d.y * a + n.y * o)
        }
        var p = Path()
        p.move(to: base)
        p.addCurve(to: at(length, 0), control1: at(length * 0.22, width * 0.78), control2: at(length * 0.72, width * 0.62))
        p.addCurve(to: base, control1: at(length * 0.72, -width * 0.62), control2: at(length * 0.22, -width * 0.78))
        p.closeSubpath()
        return p
    }

    /// قاعدة ورقة تبعد عن محور الغصن نصف سمكه + فاصل
    static func base(_ s: CGFloat, angle: CGFloat) -> CGPoint {
        let o = point(s)
        return ftbxP(o.x + cos(angle) * 4.6, o.y + sin(angle) * 4.6)
    }

    static let leaves: Path = {
        let aL = direction(0.36) - 1.05                    // الورقة اليسرى السفلى
        let aR = direction(0.66) + 1.0                     // الورقة اليمنى
        var p = leaf(base: base(0.36, angle: aL), angle: aL, length: 36, width: 18)
        p.addPath(leaf(base: base(0.66, angle: aR), angle: aR, length: 31, width: 16))
        return p
    }()

    static let newLeafAngle: CGFloat = direction(1) - 0.12
    static let newLeafBase = ftbxP(p3.x + cos(newLeafAngle) * 3.6, p3.y + sin(newLeafAngle) * 3.6)
    static let newLeaf = leaf(base: newLeafBase, angle: newLeafAngle, length: 21, width: 11.5)
}

/// الظرف — نفس مسارات مربّع «التواصل» (`FTEnvelope` في FTTileScenes): جسم، ولسان مثلّث بدرجة الحزام
/// يفصله فاصل مقصوص، وختم الشمع الذهبي على رأسه.
nonisolated fileprivate enum FTBxEnvelope {
    static let body = Path(roundedRect: CGRect(x: 7, y: 20, width: 86, height: 60), cornerRadius: 7)
    static let sealCenter = ftbxP(50, 52)
    static let flap: Path = {
        var p = Path()
        p.move(to: ftbxP(12, 20))
        p.addLine(to: ftbxP(88, 20))
        p.addLine(to: sealCenter)
        p.closeSubpath()
        return p
    }()
    static let seal = Path(ellipseIn: CGRect(x: sealCenter.x - 6, y: sealCenter.y - 6, width: 12, height: 12))
}

/// الدرع: شكل واحد بثقب مفتاح مقصوص، وضوء ذهبي في الثقب
nonisolated fileprivate enum FTBxShield {
    static let body: Path = {
        var p = Path()
        p.move(to: ftbxP(50, 6))
        p.addCurve(to: ftbxP(80, 15.5), control1: ftbxP(60, 12.5), control2: ftbxP(70, 15.5))
        p.addQuadCurve(to: ftbxP(85, 20.5), control: ftbxP(85, 15.5))
        p.addCurve(to: ftbxP(53.4, 92.4), control1: ftbxP(85, 58), control2: ftbxP(73, 81))
        p.addQuadCurve(to: ftbxP(46.6, 92.4), control: ftbxP(50, 95))
        p.addCurve(to: ftbxP(15, 20.5), control1: ftbxP(27, 81), control2: ftbxP(15, 58))
        p.addQuadCurve(to: ftbxP(20, 15.5), control: ftbxP(15, 15.5))
        p.addCurve(to: ftbxP(50, 6), control1: ftbxP(30, 15.5), control2: ftbxP(40, 12.5))
        p.closeSubpath()
        return p
    }()
    static let light = ftbxP(50, 42)
    static let keyRound = Path(ellipseIn: CGRect(x: 50 - 9.5, y: 42 - 9.5, width: 19, height: 19))
    static let keyStem: Path = {
        var p = Path()
        p.move(to: ftbxP(46.4, 47))
        p.addLine(to: ftbxP(53.6, 47))
        p.addLine(to: ftbxP(55.8, 64.6))
        p.addQuadCurve(to: ftbxP(53.4, 67), control: ftbxP(56.1, 67))
        p.addLine(to: ftbxP(46.6, 67))
        p.addQuadCurve(to: ftbxP(44.2, 64.6), control: ftbxP(43.9, 67))
        p.closeSubpath()
        return p
    }()
}

/// المفتاح القديم: حلقة الرأس (الدرجة الثانية)، الساق والأسنان (الجسم)، وشرّابة ذهبية معلّقة
nonisolated fileprivate enum FTBxKey {
    /// المفتاح مرسوم أفقياً (الحلقة عند الأصل) ثم يوضع قطرياً: الحلقة أعلى البداية والأسنان نحو الأسفل
    static let angle: CGFloat = 32 * .pi / 180
    static let place = CGAffineTransform(translationX: 27, y: 31).rotated(by: angle)
    static let bowRadius: CGFloat = 18.5
    static let bow = Path(ellipseIn: CGRect(x: -18.5, y: -18.5, width: 37, height: 37)).applying(place)
    static let bowHole = Path(ellipseIn: CGRect(x: -8, y: -8, width: 16, height: 16)).applying(place)
    static let shaftAndBit: Path = {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 20.6, y: -5, width: 56, height: 10), cornerSize: CGSize(width: 5, height: 5))
        p.addRoundedRect(in: CGRect(x: 55, y: 1, width: 20, height: 23), cornerSize: CGSize(width: 3, height: 3))
        return p.applying(place)
    }()
    static let notch = Path(roundedRect: CGRect(x: 61.6, y: 13, width: 6.4, height: 14), cornerRadius: 1.8).applying(place)
    /// نقطة التعليق: أسفل يسار الحلقة على الشاشة (١٣٥°) — بعيداً عن محورها فلا تُقرأ كدبّوس خريطة
    static let hook: CGPoint = {
        let a = CGFloat.pi * 0.75 - CGFloat(FTBxDraw.tilt) * .pi / 180
        return ftbxP(27 + cos(a) * bowRadius, 31 + sin(a) * bowRadius)
    }()
    /// الشرّابة حول نقطة التعليق (محورها رأسي، y للأسفل): عروة قصيرة ← عقدة ← تنّورة تتّسع للأسفل.
    /// مسار واحد يُعبّأ مرة واحدة (التراكب داخل المسار لا يغمّق). كانت خيطاً مستقيماً بحبّة فتُقرأ «دبّوساً».
    static let tassel: Path = {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: -1, y: -0.6, width: 2, height: 4.4), cornerSize: CGSize(width: 1, height: 1))
        p.addEllipse(in: CGRect(x: -2.9, y: 3.0, width: 5.8, height: 5.8))
        p.move(to: ftbxP(-1.9, 8.2))
        p.addLine(to: ftbxP(1.9, 8.2))
        p.addLine(to: ftbxP(4.6, 17.2))
        p.addQuadCurve(to: ftbxP(-4.6, 17.2), control: ftbxP(0, 19.4))
        p.closeSubpath()
        return p
    }()
}

/// هلال ونجمة: قرص يُقضم منه قرص، ونجمة خماسية في فتحته
nonisolated fileprivate enum FTBxCrescent {
    static let disc = Path(ellipseIn: CGRect(x: 46 - 33, y: 53 - 33, width: 66, height: 66))
    static let bite = Path(ellipseIn: CGRect(x: 61 - 27.5, y: 43 - 27.5, width: 55, height: 55))
    static let star: Path = {
        let c = ftbxP(68, 46), outer: CGFloat = 10, inner: CGFloat = 4.3
        var p = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let pt = ftbxP(c.x + cos(a) * r, c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }()
}
