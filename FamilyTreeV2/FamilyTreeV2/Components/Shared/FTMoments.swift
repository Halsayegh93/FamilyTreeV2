import SwiftUI

// MARK: - شارات أنواع الأخبار ولحظات التنبيه — «الشعار المصمت» (٢٠٢٦-١٠-٠٥)
//
// ١) FTNewsBadges: رمز مصمت لكل نوع خبر يحلّ محلّ رمز SF داخل دائرة النوع (نفس المقاس واللون).
//    حبر النوع بدرجتين (١٫٠ و٠٫٨٥) + لمسة ذهبية واحدة ذات معنى. بلا تنفّس: نبضة ذهبية واحدة
//    (≤ ١٫٢ ث) كل ٨ ث، مزاحة بحسب `seed` فلا تتزامن الصفوف، والشارة تنام بين النبضات.
//    «وفاة»: هلال ونجمة رماديان، ساكنان دائماً.
// ٢) FTMoments: لحظة واحدة (١٫٢ ث) فوق عنوان مربّع التنبيه ثم سكون: الوسام يظهر ← الرمز الأبيض
//    يرسم نفسه ← اللمسة الذهبية. «تقليل الحركة»: الإطار الأخير مباشرة.
//
// يُبنى مع FTKit.swift · SwiftUI فقط · iOS 16 · كل رسم دالة نقية في t · بلا صور ولا رموز SF داخل الرسم.

// MARK: - الواجهة العامة: شارات أنواع الأخبار

nonisolated enum FTNewsBadges {
    /// soft: رمز بلون النوع فوق الدائرة الفاتحة (color.opacity(0.16)) — صف المناسبة وبلاطات التصنيف.
    /// onColor: رمز أبيض فوق سطح بلون النوع — البلاطة المختارة وصورة «إدارة العائلة».
    enum Style { case soft, onColor }

    /// الأنواع المرسومة (غيرها — مثل تصنيف مخصّص — يبقى برمزه القديم)
    static let types = ["خبر", "إعلان", "زواج", "مولود", "وفاة", "تهنئة", "دعوة", "تذكير", "تصويت"]

    static func hasArt(for type: String) -> Bool { FTMKind(type) != nil }

    /// مثل `hasArt(for:)` لكنه يحترم تخصيص الإدارة: إذا غُيّرت أيقونة النوع من «التصنيفات»
    /// (`NewsTypeHelper.icon(for:)` لم يعد الرمز الأصلي) يبقى الرمز الذي اختارته الإدارة.
    static func hasArt(for type: String, currentIcon: String) -> Bool {
        guard let k = FTMKind(type) else { return false }
        return currentIcon == k.defaultSymbol
    }

    /// «وفاة» لا تتحرّك أبداً (احترام + صفر استهلاك)
    static func isStill(_ type: String) -> Bool { FTMKind(type) == .death }

    /// (الدورة، طول النبضة) بالثواني — الدورة ٨ ث للجميع، والنبضة ≤ ١٫٢ ث
    static func rhythm(for type: String) -> (period: Double, beat: Double) {
        guard let k = FTMKind(type) else { return (FTKit.loop, 0) }
        return (FTKit.loop, k.beat)
    }

    /// موعد أول نبضة لهذا الصف. دائماً > ٠ ونهايته قبل نهاية الدورة، فعند t = 0 كل الشارات ساكنة.
    /// الصفوف المتتالية (seed = 0، 1، 2…) تتوزّع بالنسبة الذهبية فلا تتزامن ولا تتكدّس.
    static func firstBeat(type: String, seed: Int) -> Double {
        guard let k = FTMKind(type) else { return 0 }
        let room = max(0.1, FTKit.loop - k.beat - 0.7)
        let g = Double(seed) * 0.618034 + Double(k.salt) * 0.0137
        return 0.7 + (g - floor(g)) * room
    }

    /// مدة هالة الاحتفال (`celebrate`) حول شارة المناسبة
    static let haloDuration = 0.9

    /// هالة الاحتفال: حلقة ذهبية رفيعة واحدة تتّسع ٥ نقاط وتتلاشى — بلا لمعات ولا معيّنات.
    /// `size` = مقاس الشارة + ١٢ نقطة من كل جهة، `badge` = قطر الشارة.
    static func drawHalo(type: String, in ctx: inout GraphicsContext, size: CGSize, badge: CGFloat, t: Double, tint: Color) {
        guard let kind = FTMKind(type), kind != .death, t > 0, t < haloDuration else { return }
        let dark = ctx.environment.colorScheme == .dark
        let q = t / haloDuration
        let e = CGFloat(FTKit.Ease.outCubic(q))
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = badge / 2 + 1.5 + 5 * e
        let a = 0.9 * (1 - FTKit.Ease.smooth(q)) * FTKit.progress(q, 0, 0.12)
        ctx.stroke(FTMG.circle(c, r), with: .color((dark ? FTKit.gold : FTKit.goldOnLight).opacity(a)),
                   lineWidth: 1.6 - 0.8 * e)
    }

    /// يرسم الشارة داخل مربّع `size` (الدائرة نفسها يرسمها التطبيق خلفها كما هي).
    /// - t: ثوانٍ منذ الظهور · seed: رقم الصف (طور مختلف لكل صف) · tint: لون النوع.
    static func draw(type: String, in ctx: inout GraphicsContext, size: CGSize, t: Double,
                     tint: Color, seed: Int = 0, style: Style = .soft) {
        guard let kind = FTMKind(type) else { return }
        let side = min(size.width, size.height)
        guard side > 1 else { return }
        let dark = ctx.environment.colorScheme == .dark
        let ink = FTMInk(kind: kind, tint: tint, onColor: style == .onColor, dark: dark, micro: side < 27)

        // زمن النبضة ٠…١ (خارجها ٠ = السكون، وهو نفسه بداية النبضة ونهايتها)
        var q = 0.0
        if kind != .death && kind.beat > 0 {
            let x = t - firstBeat(type: type, seed: seed)
            let u = x - floor(x / FTKit.loop) * FTKit.loop
            if u < kind.beat { q = u / kind.beat }
        }

        var g = ctx
        let disc = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        g.clip(to: Path(ellipseIn: disc))
        // شبكة الرمز ٢٠×٢٠ في وسط الدائرة (٦٠٪ من القطر — بوزن رمز SF في نفس الدائرة)
        let box = side * FTMKind.glyphFraction
        g.translateBy(x: disc.midX - box / 2, y: disc.midY - box / 2)
        g.scaleBy(x: box / 20, y: box / 20)
        // مرسوم للعربية — يُعكس للإنجليزية في الأنواع ذات الاتجاه
        if kind.directional && ctx.environment.layoutDirection == .leftToRight {
            g.translateBy(x: 20, y: 0)
            g.scaleBy(x: -1, y: 1)
        }
        switch kind {
        case .news:     FTMGlyph.news(&g, ink, q)
        case .announce: FTMGlyph.announce(&g, ink, q)
        case .wedding:  FTMGlyph.wedding(&g, ink, q)
        case .birth:    FTMGlyph.birth(&g, ink, q)
        case .death:    FTMGlyph.death(&g, ink)
        case .congrats: FTMGlyph.congrats(&g, ink, q)
        case .invite:   FTMGlyph.invite(&g, ink, q)
        case .reminder: FTMGlyph.reminder(&g, ink, q)
        case .poll:     FTMGlyph.poll(&g, ink, q)
        }
    }
}

/// الشارة جاهزة كواجهة: ضعها مكان `Image(systemName:)` داخل دائرة النوع.
/// تتحدّث بـ٣٠ إطاراً فقط أثناء النبضة، وتنام بين النبضات (جدول زمني مخصّص).
/// «تقليل الحركة» أو «وفاة»: رسمة ساكنة بلا مؤقّت.
struct FTNewsBadge: View {
    let type: String
    let tint: Color
    var seed: Int = 0
    var style: FTNewsBadges.Style = .soft
    /// للمناسبة الأحدث (صف «آخر مناسبة»): أول نبضة بعد ثلث ثانية من الظهور مع حلقة ذهبية مرة واحدة
    var celebrate: Bool = false
    /// أول نبضة فوراً (بعد ثلث ثانية) بلا حلقة — مثل بلاطة النوع لحظة اختيارها (مع `.id(selected)`)
    var beatOnAppear: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// إزاحة الزمن حتى تبدأ أول نبضة عند ٠٫٣٥ ث
    private var shift: Double {
        celebrate || beatOnAppear ? FTNewsBadges.firstBeat(type: type, seed: seed) - 0.35 : 0
    }

    @AppStorage(ArtTrial.storageKey) private var artTrialRaw = ArtTrial.emblem.rawValue   // TMP-ART-TRIAL

    @ViewBuilder var body: some View {
        if let art = ArtDispatch.newsBadge(ArtTrial(rawValue: artTrialRaw) ?? .emblem, type: type, tint: tint,
                                           onColor: style == .onColor) {
            art
        } else {
            emblemBody
        }
    }

    private var emblemBody: some View {
        Group {
            if reduceMotion || FTNewsBadges.isStill(type) {
                canvas(t: 0)
            } else {
                let s0 = start.addingTimeInterval(-shift)
                TimelineView(FTMBeatSchedule(start: s0, type: type, seed: seed)) { tl in
                    canvas(t: max(0, tl.date.timeIntervalSince(s0)))
                }
                .overlay { if celebrate { halo } }
            }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var halo: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            let type = self.type, tint = self.tint
            FTKitMomentCanvas(duration: FTNewsBadges.haloDuration, delay: 0.35) { ctx, size, t, _ in
                FTNewsBadges.drawHalo(type: type, in: &ctx, size: size, badge: d, t: t, tint: tint)
            }
            .frame(width: d + 24, height: d + 24)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func canvas(t: Double) -> some View {
        Canvas { ctx, size in
            FTNewsBadges.draw(type: type, in: &ctx, size: size, t: t, tint: tint, seed: seed, style: style)
        }
    }
}

/// جدول زمني: ٣٠ إطاراً أثناء النبضة، وقفزة واحدة إلى النبضة التالية بين النبضات.
nonisolated fileprivate struct FTMBeatSchedule: TimelineSchedule {
    let start: Date
    let type: String
    let seed: Int

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        let r = FTNewsBadges.rhythm(for: type)
        return Entries(cursor: startDate, start: start, period: r.period, beat: r.beat,
                       first: FTNewsBadges.firstBeat(type: type, seed: seed),
                       step: mode == .lowFrequency ? r.period : 1.0 / FTKit.frameRate)
    }

    nonisolated struct Entries: Sequence, IteratorProtocol {
        var cursor: Date
        let start: Date
        let period: Double, beat: Double, first: Double, step: Double

        mutating func next() -> Date? {
            let now = cursor
            let x = now.timeIntervalSince(start) - first
            let k = floor(x / period)
            let u = x - k * period
            if u < beat && step < period {
                cursor = now.addingTimeInterval(step)                 // داخل النبضة
            } else {
                // سكون: إطار واحد الآن ثم القفز إلى بداية النبضة التالية.
                // لازم يتقدّم دائماً: تقريب Date (خطوة ٢^-٢٣ ث) قد يعيد التاريخ نفسه فيدور SwiftUI
                // على الخيط الرئيسي بلا نهاية (تجمّد التطبيق عند إضافة خبر — ٢٠٢٦-١٠-٠٥)
                let target = start.addingTimeInterval(first + (k + 1) * period)
                cursor = Swift.max(target, now.addingTimeInterval(1.0 / FTKit.frameRate))
            }
            return now
        }
    }
}

// MARK: - الواجهة العامة: لحظات التنبيه

nonisolated enum FTMoments {
    enum Moment: CaseIterable {
        /// «تم» عام: علامة صح ترسم نفسها، ثم حلقة ذهبية رفيعة تكتمل حول الوسام مع عقارب الساعة
        case success
        /// «أُرسل للإدارة للموافقة»: ظرف أبيض، وختم شمع ذهبي ينطبع على لسانه
        case sentForApproval
        /// موافقة الإدارة: علامة صح، وختم العائلة الذهبي (١٢ تموّجاً) ينطبع حول الوسام
        case approved
        /// «تمت الإضافة»: غصن «إضافة ابن» يرسم نفسه بورقتين، وتتفتّح على طرفه الورقة الذهبية الجديدة
        case newMember
    }

    /// كل اللحظات ١٫٢ ث ثم سكون على الإطار الأخير
    static func duration(_ m: Moment) -> Double { FTKit.momentDuration }

    /// يرسم اللحظة عند الزمن t (من ٠ إلى المدة، وبعدها تبقى على الإطار الأخير).
    /// اللوحة بارتفاع ~١٢٠ نقطة (التنبيه يعطيها ١١٢) — كل شيء يتحجّم مع الارتفاع.
    static func draw(_ moment: Moment, in ctx: inout GraphicsContext, size: CGSize, t: Double, tint: Color) {
        guard size.width > 1, size.height > 1 else { return }
        let dark = ctx.environment.colorScheme == .dark
        let tt = min(max(t, 0), duration(moment))
        var c = ctx
        c.translateBy(x: size.width / 2, y: size.height / 2)
        let s = size.height / 120
        c.scaleBy(x: s, y: s)
        // الذهبي فوق سطح التنبيه نفسه (أبيض في الفاتح) — والذهبي داخل الوسام دائماً الفاتح
        let surfaceGold = dark ? FTKit.gold : FTKit.goldOnLight

        // ختم «تمت الموافقة» خلف الوسام
        if moment == .approved { FTMMoment.seal(&c, tt, dark: dark) }

        // الوسام: يظهر ويكبر ٠٫٨٦ → ١ (٠–٠٫٥ ث، outCubic، بلا ارتداد)
        let fade = FTKit.progress(tt, 0, 0.22, .smooth)
        guard fade > 0.001 else { return }
        let grow = FTKit.progress(tt, 0, 0.5, .outCubic)
        var m = c
        m.opacity *= fade
        let k = 0.86 + 0.14 * CGFloat(grow)
        m.scaleBy(x: k, y: k)
        let R = FTMMoment.radius
        m.fill(FTMG.disc(.zero, R), with: .color(tint))
        m.stroke(FTMG.circle(.zero, R - 3.5), with: .color(.white.opacity(0.35)), lineWidth: 1)

        switch moment {
        case .success:
            FTMMoment.check(&m, tt)
            FTMMoment.ring(&c, tt, gold: surfaceGold)
        case .sentForApproval:
            FTMMoment.envelope(&m, tt)
        case .approved:
            FTMMoment.check(&m, tt)
        case .newMember:
            FTMMoment.branch(&m, tt)
        }
    }
}

/// اللحظة جاهزة كواجهة: تُعرض مرة عند الظهور ثم تقف على إطارها الأخير.
/// «تقليل الحركة»: الإطار الأخير مباشرة.
struct FTMomentView: View {
    let moment: FTMoments.Moment
    let tint: Color
    /// تأخير بسيط حتى يكبر المربّع أولاً
    var delay: Double = 0.12

    @AppStorage(ArtTrial.storageKey) private var artTrialRaw = ArtTrial.emblem.rawValue   // TMP-ART-TRIAL

    @ViewBuilder var body: some View {
        if let art = ArtDispatch.moment(ArtTrial(rawValue: artTrialRaw) ?? .emblem,
                                        name: String(describing: moment), tint: tint) {
            art
        } else {
            emblemBody
        }
    }

    private var emblemBody: some View {
        let moment = self.moment, tint = self.tint
        return FTKitMomentCanvas(duration: FTMoments.duration(moment), delay: delay) { ctx, size, t, _ in
            FTMoments.draw(moment, in: &ctx, size: size, t: t, tint: tint)
        }
    }
}

// MARK: - الأنواع

nonisolated fileprivate enum FTMKind {
    case news, announce, wedding, birth, death, congrats, invite, reminder, poll

    /// قطر شبكة الرمز (٢٠ وحدة) من قطر الدائرة
    static let glyphFraction: CGFloat = 0.60

    init?(_ type: String) {
        switch type {
        case "خبر": self = .news
        case "إعلان": self = .announce
        case "زواج": self = .wedding
        case "مولود": self = .birth
        case "وفاة": self = .death
        case "تهنئة": self = .congrats
        case "دعوة": self = .invite
        case "تذكير": self = .reminder
        case "تصويت": self = .poll
        default: return nil
        }
    }

    /// طول النبضة الذهبية (ث)
    var beat: Double {
        switch self {
        case .news: return 0.8
        case .announce: return 1.0
        case .wedding: return 0.8
        case .birth: return 1.2
        case .death: return 0
        case .congrats: return 0.8
        case .invite: return 0.8
        case .reminder: return 0.8
        case .poll: return 0.9
        }
    }

    /// يُعكس في الإنجليزية: الصفحة (الكتابة من البداية)، مكبّر الصوت (يتّجه للبداية)، نقطة الجرس (أعلى البداية)
    var directional: Bool { self == .news || self == .announce || self == .reminder }

    /// رمز SF الأصلي لهذا النوع في `NewsTypeHelper.icon(for:)`
    var defaultSymbol: String {
        switch self {
        case .news: return "newspaper.fill"
        case .announce: return "megaphone.fill"
        case .wedding: return "heart.fill"
        case .birth: return "figure.child"
        case .death: return "heart.slash.fill"
        case .congrats: return "hands.clap.fill"
        case .invite: return "envelope.open.fill"
        case .reminder: return "bell.badge.fill"
        case .poll: return "chart.bar.fill"
        }
    }

    var salt: Int {
        switch self {
        case .news: return 11
        case .announce: return 23
        case .wedding: return 37
        case .birth: return 41
        case .death: return 53
        case .congrats: return 67
        case .invite: return 71
        case .reminder: return 83
        case .poll: return 97
        }
    }
}

/// حبر الرمز: لون النوع (أو الأبيض فوق اللون) بدرجتين + الذهبي المناسب للسطح
nonisolated fileprivate struct FTMInk {
    let ink: Color
    let gold: Color
    /// الدرجة الثانية (جزء ثانوي من الرمز)
    let band: Color
    let micro: Bool

    init(kind: FTMKind, tint: Color, onColor: Bool, dark: Bool, micro: Bool) {
        let base: Color
        if onColor {
            base = .white
        } else if kind == .death {
            // «وفاة» رمادية دائماً حتى لو خُصّص لون النوع
            base = dark ? FTKit.mourning : FTMG.rgb(0x68686D)
        } else {
            base = tint
        }
        ink = base
        band = base.opacity(0.85)
        gold = onColor || dark ? FTKit.gold : FTKit.goldOnLight
        self.micro = micro
    }
}

// MARK: - الرموز (شبكة ٢٠×٢٠، y للأسفل، مرسومة للعربية)

nonisolated fileprivate enum FTMGlyph {
    typealias G = GraphicsContext
    static let gap: CGFloat = 1.2

    // ── خبر: صفحة بزاوية مطويّة أسفل البداية، عنوان ذهبي وثلاثة أسطر مقصوصة.
    //    النبضة: العنوان يُمحى من اليمين ثم يُكتب من اليمين (٠٫٨ ث) ──
    static func news(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let L: CGFloat = 3.6, R: CGFloat = 16.4, T: CGFloat = 1.6, B: CGFloat = 18.4, f: CGFloat = 4.0
        // الصفحة بحزّ مربّع للطيّة (فلا تتراكب معها)
        let page = FTMG.poly([FTMG.p(L, T), FTMG.p(R, T), FTMG.p(R, B), FTMG.p(L + f + gap, B),
                              FTMG.p(L + f + gap, B - f - gap), FTMG.p(L, B - f - gap)],
                             r: [1.8, 1.8, 1.8, 0.5, 0.5, 0.5])
        let flap = FTMG.poly([FTMG.p(L, B - f), FTMG.p(L + f, B - f), FTMG.p(L + f, B)], r: [0.5, 1.0, 0.5])
        let x0: CGFloat = 6.2, x1: CGFloat = 13.8
        let barY: CGFloat = 4.0, barH: CGFloat = 2.0
        var cut = FTMG.rrect(x0 - 0.9, barY - 0.9, x1 - x0 + 1.8, barH + 1.8, r: 1.9)
        if k.micro {
            cut.addPath(FTMG.rrect(x0, 9.6, x1 - x0, 2.2, r: 1.1))
        } else {
            cut.addPath(FTMG.rrect(x0, 8.25, x1 - x0, 1.5, r: 0.75))
            cut.addPath(FTMG.rrect(x0, 11.05, x1 - x0, 1.5, r: 0.75))
            cut.addPath(FTMG.rrect(10.0, 13.85, x1 - 10.0, 1.5, r: 0.75))
        }
        // العنوان: [lo, hi] — يُمحى من اليمين (الحافة اليمنى تتراجع) ثم يُكتب من اليمين
        var lo = x0, hi = x1
        if q > 0 {
            if q < 0.42 {
                hi = x1 - (x1 - x0) * CGFloat(FTKit.progress(q, 0, 0.32, .smooth))
            } else {
                lo = x1 - (x1 - x0) * CGFloat(FTKit.progress(q, 0.42, 1, .smooth))
            }
        }
        g.drawLayer { l in
            l.fill(page, with: .color(k.ink))
            FTKit.eraser(l).fill(cut, with: .color(.black))
            l.fill(flap, with: .color(k.band))
            if hi - lo > 0.25 {
                l.fill(FTMG.rrect(lo, barY, hi - lo, barH, r: min(1, (hi - lo) / 2)), with: .color(k.gold))
            }
        }
    }

    // ── إعلان: مكبّر صوت يتّجه للبداية، وقوس صوت ذهبي واحد. النبضة: القوس يتّسع ويتلاشى،
    //    ثم يتكوّن قوس جديد مكانه (١ ث) ──
    static func announce(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let mc = FTMG.p(8.2, 10)
        var body = FTMG.ellipse(mc, 2.0, 6.6)
        body.addPath(FTMG.poly([FTMG.p(8.2, 3.4), FTMG.p(14.8, 7.4), FTMG.p(14.8, 12.6), FTMG.p(8.2, 16.6)],
                               r: [0.6, 0.8, 0.8, 0.6]))
        body.addPath(FTMG.rrect(14.2, 7.6, 3.4, 4.8, r: 1.4))
        let handle = FTMG.rrect(13.3, 14.7, 2.1, 3.3, r: 1.05)
        g.drawLayer { l in
            l.fill(body, with: .color(k.ink))
            if !k.micro { FTKit.eraser(l).fill(FTMG.ellipse(FTMG.p(mc.x + 0.6, 10), 0.9, 4.8), with: .color(.black)) }
            l.fill(handle, with: .color(k.band))
        }
        // قوس الصوت
        let span = 36.0 * .pi / 180
        func arc(_ r: CGFloat, _ a: Double, _ w: CGFloat) {
            guard a > 0.01 else { return }
            g.stroke(FTMG.arc(mc, r, .pi - span, .pi + span), with: .color(k.gold.opacity(a)),
                     style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        if q <= 0 {
            arc(5.2, 1, 1.9)
        } else {
            let out = FTKit.progress(q, 0, 0.6, .outCubic)
            if q < 0.6 { arc(5.2 + 3.4 * CGFloat(out), 1 - FTKit.Ease.smooth(q / 0.6), 1.9 - 0.5 * CGFloat(out)) }
            let back = FTKit.progress(q, 0.45, 1, .smooth)
            if q > 0.45 { arc(4.2 + 1.0 * CGFloat(back), back, 1.9) }
        }
    }

    // ── زواج: خاتمان متشابكان (١٫٠ و٠٫٨٥) وماسة ذهبية على الخاتم الثاني.
    //    النبضة: لمعة كريمية على الماسة (٠٫٨ ث) ──
    static func wedding(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let cy: CGFloat = 12.2, r: CGFloat = 4.3, w: CGFloat = k.micro ? 2.5 : 2.1
        let cL = FTMG.p(7.5, cy), cR = FTMG.p(12.5, cy)
        let ringL = FTMG.circle(cL, r), ringR = FTMG.circle(cR, r)
        let top = Path(CGRect(x: 0, y: -2, width: 20, height: cy + 2))
        let bottom = Path(CGRect(x: 0, y: cy, width: 20, height: 12))
        g.drawLayer { l in
            // الثاني أولاً، ويُقصّ حيث يمرّ الأول فوقه (التقاطع العلوي)
            l.stroke(ringR, with: .color(k.band), lineWidth: w)
            var e = FTKit.eraser(l)
            e.clip(to: top)
            e.stroke(ringL, with: .color(.black), lineWidth: w + 2 * 1.0)
            // الأول في طبقته، مقصوصاً حيث يمرّ الثاني فوقه (التقاطع السفلي)
            l.drawLayer { a in
                a.stroke(ringL, with: .color(k.ink), lineWidth: w)
                var e2 = FTKit.eraser(a)
                e2.clip(to: bottom)
                e2.stroke(ringR, with: .color(.black), lineWidth: w + 2 * 1.0)
            }
        }
        // الماسة
        let gc = FTMG.p(cR.x, cy - r - w / 2 - 1.0 - 2.4)
        let gem = FTMG.poly([FTMG.p(gc.x - 2.6, gc.y - 0.6), FTMG.p(gc.x - 1.5, gc.y - 2.1), FTMG.p(gc.x + 1.5, gc.y - 2.1),
                             FTMG.p(gc.x + 2.6, gc.y - 0.6), FTMG.p(gc.x, gc.y + 2.4)], r: [0.4, 0.4, 0.4, 0.4, 0.3])
        // لمعة كريمية على الماسة نفسها فقط (بلا توهّج حولها — أهدأ وعمليتان أقل)
        let shine = FTMG.hump(q)
        g.fill(gem, with: .color(k.gold))
        if shine > 0.01 { g.fill(gem, with: .color(FTKit.glint.opacity(0.9 * shine))) }
    }

    // ── مولود: عربة المولود — مظلّة (ربع) فوق السلّة (نصف) بفاصل مقصوص، وعجلتان بالدرجة الثانية،
    //    ونجمة ذهبية في الربع المفتوح. النبضة: النجمة تدور خُمس دورة (٧٢°) فتعود إلى شكلها نفسه (١٫٢ ث).
    //    (المهد بقوس هزّاز كان يُقرأ بالحجم الحقيقي دائرةً ناقصة ربعاً فوق ابتسامة — العجلتان تحسمان المعنى.)
    //    بلا هلال: الهلال مع النجمة محجوزان لوفاة ──
    static func birth(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let c = FTMG.p(10.6, 9.2), rx: CGFloat = 7.0
        var body = FTMG.halfEllipseDown(center: c, rx: rx, ry: 5.3)
        body.addPath(FTMG.quarterHood(center: FTMG.p(c.x + 0.2, c.y - gap), rx: rx - 0.2, ry: 6.6))
        g.fill(body, with: .color(k.ink))
        var wheels = FTMG.disc(FTMG.p(6.5, 17.1), 1.95)
        wheels.addPath(FTMG.disc(FTMG.p(14.7, 17.1), 1.95))
        g.fill(wheels, with: .color(k.band))
        let spin = 2 * Double.pi / 5 * FTKit.Ease.smooth(q)
        g.fill(FTMG.star(FTMG.p(5.0, 4.3), k.micro ? 3.1 : 2.8, k.micro ? 1.4 : 1.25, rot: -.pi / 2 + spin),
               with: .color(k.gold))
    }

    // ── وفاة: هلال ونجمة — ساكنان دائماً، بلا ذهبي ──
    static func death(_ g: inout G, _ k: FTMInk) {
        g.drawLayer { l in
            l.fill(FTMG.disc(FTMG.p(9.2, 10.9), 7.1), with: .color(k.ink))
            FTKit.eraser(l).fill(FTMG.disc(FTMG.p(12.5, 8.0), 6.0), with: .color(.black))
            l.fill(FTMG.star(FTMG.p(14.5, 6.3), 2.6, 1.15, rot: -.pi / 2 + 0.2), with: .color(k.ink))
        }
    }

    // ── تهنئة: أبراج الكويت — البرج الرئيسي بكرتين، والثاني بكرة، والإبرة. حزام الكرة الكبرى ذهبي.
    //    النبضة: لمعة كريمية تعبر الحزام (٠٫٨ ث) ──
    static func congrats(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let mx: CGFloat = 12.9, base: CGFloat = 18.6
        let big = FTMG.p(mx, 10.0), bigR: CGFloat = 4.0
        var main = FTMG.poly([FTMG.p(mx, 0.9), FTMG.p(mx + 1.0, base), FTMG.p(mx - 1.0, base)], r: [0.3, 0.3, 0.3])
        main.addPath(FTMG.disc(big, bigR))
        main.addPath(FTMG.disc(FTMG.p(mx, 4.6), 1.8))
        // البرج الثاني أمام الرئيسي بفاصل مقصوص، والإبرة
        let sx: CGFloat = 7.6, sc = FTMG.p(sx, 12.4), sr: CGFloat = 2.7
        var second = FTMG.poly([FTMG.p(sx, 5.2), FTMG.p(sx + 0.85, base), FTMG.p(sx - 0.85, base)], r: [0.3, 0.3, 0.3])
        second.addPath(FTMG.disc(sc, sr))
        second.addPath(FTMG.poly([FTMG.p(3.6, 9.8), FTMG.p(4.25, base), FTMG.p(2.95, base)], r: [0.25, 0.25, 0.25]))
        let bandY: CGFloat = 10.4, bandH: CGFloat = k.micro ? 1.8 : 1.5
        let sphere = FTMG.disc(big, bigR)
        let bandRect = CGRect(x: mx - 5, y: bandY - bandH / 2, width: 10, height: bandH)
        g.drawLayer { l in
            l.fill(main, with: .color(k.ink))
            // الحزام: شقّ مقصوص في الكرة الكبرى، وفيه القضيب الذهبي
            var e = FTKit.eraser(l)
            e.clip(to: sphere)
            e.fill(Path(CGRect(x: mx - 5, y: bandY - bandH / 2 - 0.95, width: 10, height: bandH + 1.9)), with: .color(.black))
            var gb = l
            gb.clip(to: FTMG.disc(big, bigR - 0.15))
            gb.fill(Path(bandRect), with: .color(k.gold))
            if q > 0 && q < 1 {
                let x = mx - 5.5 + 11 * CGFloat(FTKit.Ease.inOutSine(q))
                gb.clip(to: Path(bandRect))
                gb.fill(FTMG.rrect(x - 1.4, bandRect.minY, 2.8, bandH, r: bandH / 2),
                        with: .color(FTKit.glint.opacity(0.95 * FTMG.hump(q))))
            }
            FTKit.eraser(l).fill(FTMG.disc(sc, sr + gap), with: .color(.black))
            l.fill(second, with: .color(k.band))
        }
    }

    // ── دعوة: ظرف يفصل لسانه خط V مقصوص، وختم شمع ذهبي على رأس اللسان.
    //    النبضة: لمعة كريمية تمرّ على الختم (٠٫٨ ث) ──
    static func invite(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let env = FTMG.rrect(2.4, 4.6, 15.2, 11.0, r: 1.8)
        let tip = FTMG.p(10, 10.6)
        let sealR: CGFloat = k.micro ? 3.0 : 2.6
        let ringR = sealR + 0.95
        // خطّا اللسان ينتهيان قبل حلقة الختم (لا تراكب في القصّ)
        func leg(_ from: CGPoint) -> Path {
            let dx = tip.x - from.x, dy = tip.y - from.y
            let len = sqrt(dx * dx + dy * dy)
            let stop = (len - ringR - 0.6) / len
            return FTMG.line(from, FTMG.p(from.x + dx * stop, from.y + dy * stop))
        }
        var cut = FTMG.stroked(leg(FTMG.p(3.6, 5.7)), 1.4)
        cut.addPath(FTMG.stroked(leg(FTMG.p(16.4, 5.7)), 1.4))
        cut.addPath(FTMG.disc(tip, ringR))
        g.drawLayer { l in
            l.fill(env, with: .color(k.ink))
            FTKit.eraser(l).fill(cut, with: .color(.black))
        }
        let seal = FTMG.disc(tip, sealR)
        g.fill(seal, with: .color(k.gold))
        let shine = FTMG.hump(q)
        if shine > 0.01 {
            var s = g
            s.clip(to: seal)
            let x = tip.x - 4 + 8 * CGFloat(FTKit.Ease.inOutSine(q))
            let band = FTMG.poly([FTMG.p(x - 0.6, tip.y - 4), FTMG.p(x + 1.4, tip.y - 4),
                                  FTMG.p(x + 0.6, tip.y + 4), FTMG.p(x - 1.4, tip.y + 4)], r: [0, 0, 0, 0])
            s.fill(band, with: .color(FTKit.glint.opacity(0.95 * shine)))
        }
    }

    // ── تذكير: جرس ونقطة تنبيه ذهبية أعلى البداية. النبضة: النقطة تكبر ١ → ١٫٢٥ → ١ (٠٫٨ ث) ──
    static func reminder(_ g: inout G, _ k: FTMInk, _ q: Double) {
        var bell = Path()
        bell.move(to: FTMG.p(5.3, 13.6))
        bell.addLine(to: FTMG.p(5.6, 10.0))
        bell.addCurve(to: FTMG.p(10, 4.4), control1: FTMG.p(5.6, 6.6), control2: FTMG.p(7.4, 4.4))
        bell.addCurve(to: FTMG.p(14.4, 10.0), control1: FTMG.p(12.6, 4.4), control2: FTMG.p(14.4, 6.6))
        bell.addLine(to: FTMG.p(14.7, 13.6))
        bell.closeSubpath()
        bell.addPath(FTMG.rrect(3.4, 13.0, 13.2, 2.1, r: 1.05))
        bell.addPath(FTMG.disc(FTMG.p(10, 3.7), 1.3))
        let clapC = FTMG.p(10, 16.9)
        let dotC = FTMG.p(15.2, 5.0), dotR: CGFloat = k.micro ? 2.8 : 2.4
        var cut = FTMG.disc(clapC, 2.6)
        cut.addPath(FTMG.disc(dotC, dotR + 0.95))
        g.drawLayer { l in
            l.fill(bell, with: .color(k.ink))
            FTKit.eraser(l).fill(cut, with: .color(.black))
            l.fill(FTMG.disc(clapC, 1.65), with: .color(k.band))
        }
        let up = FTKit.progress(q, 0, 0.4, .smooth), down = FTKit.progress(q, 0.4, 1, .smooth)
        let sc = 1 + 0.25 * CGFloat(up * (1 - down))
        g.fill(FTMG.disc(dotC, dotR * sc), with: .color(k.gold))
    }

    // ── تصويت: ثلاثة أعمدة على قاعدة، وغطاء ذهبي فوق الأطول.
    //    النبضة: العمود يهبط قليلاً ثم يصعد بغطائه إلى مكانه ويستقرّ (٠٫٩ ث) ──
    static func poll(_ g: inout G, _ k: FTMInk, _ q: Double) {
        let bottom: CGFloat = 15.2
        let dip = 2.0 * CGFloat(FTKit.progress(q, 0, 0.3, .smooth) * (1 - FTKit.progress(q, 0.3, 1, .smooth)))
        let midTop: CGFloat = 6.6 + dip
        g.fill(FTMG.rrect(2.6, 16.6, 14.8, 1.6, r: 0.8), with: .color(k.band))
        var bars = FTMG.rrect(3.4, 11.6, 3.4, bottom - 11.6, r: 1.2)
        bars.addPath(FTMG.rrect(8.3, midTop, 3.4, bottom - midTop, r: 1.2))
        bars.addPath(FTMG.rrect(13.2, 9.2, 3.4, bottom - 9.2, r: 1.2))
        g.fill(bars, with: .color(k.ink))
        g.fill(FTMG.rrect(8.3, midTop - 1.3 - 2.2, 3.4, 2.2, r: 1.1), with: .color(k.gold))
    }
}

// MARK: - رسوم اللحظات (نقاط حقيقية، المركز = مركز اللوحة، الارتفاع ١٢٠)

nonisolated fileprivate enum FTMMoment {
    typealias G = GraphicsContext
    /// نصف قطر الوسام (قطره ٥٦ نقطة)
    static let radius: CGFloat = 28

    /// علامة صح بيضاء ترسم نفسها (٠٫٣–٠٫٨ ث)
    static func check(_ m: inout G, _ t: Double) {
        let k = FTKit.progress(t, 0.3, 0.8, .smooth)
        guard k > 0.001 else { return }
        var p = Path()
        p.move(to: FTMG.p(-10.5, 0.6))
        p.addLine(to: FTMG.p(-3.6, 7.4))
        p.addLine(to: FTMG.p(10.6, -7.2))
        m.stroke(p.trimmedPath(from: 0, to: k), with: .color(.white),
                 style: StrokeStyle(lineWidth: 4.6, lineCap: .round, lineJoin: .round))
    }

    /// نجاح: حلقة ذهبية رفيعة (١٫٥) تكتمل حول الوسام مع عقارب الساعة، من الأعلى (٠٫٧–١٫٢ ث)
    static func ring(_ c: inout G, _ t: Double, gold: Color) {
        let k = FTKit.progress(t, 0.7, 1.2, .inOutSine)
        guard k > 0.001 else { return }
        var p = Path()
        p.addArc(center: .zero, radius: radius + 6, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
        c.stroke(p.trimmedPath(from: 0, to: k), with: .color(gold), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    /// أُرسل للموافقة: ظرف أبيض يظهر ويُرسم لسانه (٠٫٣–٠٫٨)، ثم ختم شمع ذهبي ينطبع (١٫٣ → ١، ٠٫٧–١٫٢)
    static func envelope(_ m: inout G, _ t: Double) {
        let appear = FTKit.progress(t, 0.3, 0.55, .smooth)
        guard appear > 0.001 else { return }
        let rise = 4 * CGFloat(1 - FTKit.progress(t, 0.3, 0.75, .outCubic))
        let draw = CGFloat(FTKit.progress(t, 0.42, 0.8, .smooth))
        let stamp = FTKit.progress(t, 0.7, 1.2, .outCubic)
        let stampA = FTKit.progress(t, 0.7, 0.85, .smooth)
        let tip = FTMG.p(0, 3.2)
        let sealR: CGFloat = 5.0
        let sealK = 1.3 - 0.3 * CGFloat(stamp)

        // خطّا اللسان ينتهيان عند حلقة الختم (الإطار الأخير نفسه) فلا يظهر شيء تحت الذهبي وهو يتلاشى للداخل
        let ringR = sealR + 1.6
        func leg(_ from: CGPoint) -> Path {
            let dx = tip.x - from.x, dy = tip.y - from.y
            let len = sqrt(dx * dx + dy * dy)
            let stop = (len - ringR + 0.4) / len
            return FTMG.line(from, FTMG.p(from.x + dx * stop, from.y + dy * stop))
        }
        var e = m
        e.translateBy(x: 0, y: rise)
        e.opacity *= appear
        e.drawLayer { l in
            l.fill(FTMG.rrect(-15, -10, 30, 20, r: 2.8), with: .color(.white))
            let er = FTKit.eraser(l)
            if draw > 0.001 {
                var legs = leg(FTMG.p(-12.8, -7.6)).trimmedPath(from: 0, to: draw)
                legs.addPath(leg(FTMG.p(12.8, -7.6)).trimmedPath(from: 0, to: draw))
                er.stroke(legs, with: .color(.black), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if stampA > 0.001 {
                // حلقة مقصوصة فقط (لا قرص كامل) — فالذهبي يتلاشى فوق الأبيض صافياً بلا رمادي
                var ring = er
                ring.opacity = stampA
                var ann = FTMG.disc(tip, ringR * sealK)
                ann.addPath(FTMG.circle(tip, sealR * sealK))
                ring.fill(ann, with: .color(.black), style: FillStyle(eoFill: true))
            }
        }
        if stampA > 0.001 {
            e.fill(FTMG.disc(tip, sealR * sealK), with: .color(FTKit.gold.opacity(stampA)))
        }
    }

    /// تمت الموافقة: ختم العائلة الذهبي بحافة من ١٢ تموّجاً خفيفاً ينطبع حول الوسام (١٫١٨ → ١، ٠٫٧–١٫٢)
    static func seal(_ c: inout G, _ t: Double, dark: Bool) {
        let a = FTKit.progress(t, 0.7, 0.88, .smooth)
        guard a > 0.001 else { return }
        let k = 1.18 - 0.18 * CGFloat(FTKit.progress(t, 0.7, 1.2, .outCubic))
        var s = c
        s.opacity *= a
        s.scaleBy(x: k, y: k)
        var ring = Path()
        let n = 12, steps = 144
        let r0 = radius + 6.0, amp: CGFloat = 1.3
        for i in 0...steps {
            let th = Double(i) / Double(steps) * 2 * .pi
            let r = r0 + amp * CGFloat(cos(Double(n) * th))
            let pt = FTMG.p(r * CGFloat(cos(th)), r * CGFloat(sin(th)))
            if i == 0 { ring.move(to: pt) } else { ring.addLine(to: pt) }
        }
        ring.closeSubpath()
        ring.addPath(FTMG.circle(.zero, radius + 1.4))
        s.fill(ring, with: .color(dark ? FTKit.gold : FTMG.sealLight), style: FillStyle(eoFill: true))
    }

    /// عضو جديد: غصن رأس «إضافة ابن» نفسه (اتّساق بين المربّع والتنبيه) بوزن أثقل يناسب الوسام.
    /// الغصن يرسم نفسه (٠٫٣–٠٫٦٢)، فالورقتان البيضاوان تتفتّحان من قاعدتيهما، ثم الورقة الذهبية
    /// «الجديدة» تتفتّح وتستقرّ على طرفه (٠٫٧–١٫٢). أشكال مصمتة فقط — حُذفت العروق الشعرية (< ١٫٥ نقطة).
    static func branch(_ m: inout G, _ t: Double) {
        let grow = CGFloat(FTKit.progress(t, 0.3, 0.62, .smooth))
        guard grow > 0.001 else { return }
        var g = m
        g.concatenate(FTMSprig.fit)
        g.stroke(FTMSprig.stem.trimmedPath(from: 0, to: grow), with: .color(.white),
                 style: FTKit.Stroke.round(FTMSprig.width))
        func opened(_ p: Path, at a: CGPoint, _ k: Double, turn: Double = 0) -> Path {
            let s = CGFloat(k)
            return p.applying(CGAffineTransform(translationX: -a.x, y: -a.y)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(turn)))
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: a.x, y: a.y)))
        }
        let l1 = FTKit.progress(t, 0.42, 0.74, .outCubic)
        let l2 = FTKit.progress(t, 0.52, 0.84, .outCubic)
        var leaves = Path()
        if l1 > 0.001 { leaves.addPath(opened(FTMSprig.leftLeaf, at: FTMSprig.leftBase, l1)) }
        if l2 > 0.001 { leaves.addPath(opened(FTMSprig.rightLeaf, at: FTMSprig.rightBase, l2)) }
        if !leaves.isEmpty { g.fill(leaves, with: .color(.white)) }
        let n = FTKit.progress(t, 0.7, 1.2, .outCubic)
        if n > 0.001 {
            g.fill(opened(FTMSprig.newLeaf, at: FTMSprig.newBase, n, turn: -0.42 * (1 - n)), with: .color(FTKit.gold))
        }
    }
}

/// غصن «عضو جديد» — هندسة غصن رأس «إضافة ابن» (FTBoxMarks) على شبكة ١٠٠، بخطّ أثقل، ومحجَّم
/// ليملأ مربّعاً ٣٣ نقطة في وسط الوسام (قطره ٥٦) داخل حلقته الشعرية.
nonisolated fileprivate enum FTMSprig {
    static let p0 = FTMG.p(30, 95), c1 = FTMG.p(26, 66), c2 = FTMG.p(40, 34), p3 = FTMG.p(64, 19)
    /// سمك الغصن بوحدات الشبكة (≈ ٣ نقاط في الوسام)
    static let width: CGFloat = 8.4
    /// الفاصل بين الغصن والورقة (≈ ١ نقطة)
    static let gap: CGFloat = 2.8

    static let stem: Path = {
        var p = Path()
        p.move(to: p0)
        p.addCurve(to: p3, control1: c1, control2: c2)
        return p
    }()

    static func point(_ s: CGFloat) -> CGPoint {
        let u = 1 - s
        let a = u * u * u, b = 3 * u * u * s, c = 3 * u * s * s, d = s * s * s
        return FTMG.p(a * p0.x + b * c1.x + c * c2.x + d * p3.x, a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    static func direction(_ s: CGFloat) -> CGFloat {
        let u = 1 - s
        let dx = 3 * u * u * (c1.x - p0.x) + 6 * u * s * (c2.x - c1.x) + 3 * s * s * (p3.x - c2.x)
        let dy = 3 * u * u * (c1.y - p0.y) + 6 * u * s * (c2.y - c1.y) + 3 * s * s * (p3.y - c2.y)
        return atan2(dy, dx)
    }

    /// ورقة عدسية من قاعدتها باتجاه `angle`، أعرض نقطة فيها عند ~٤٠٪ من طولها
    static func leaf(base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) -> Path {
        let d = FTMG.p(cos(angle), sin(angle)), n = FTMG.p(-sin(angle), cos(angle))
        func at(_ a: CGFloat, _ o: CGFloat) -> CGPoint {
            FTMG.p(base.x + d.x * a + n.x * o, base.y + d.y * a + n.y * o)
        }
        var p = Path()
        p.move(to: base)
        p.addCurve(to: at(length, 0), control1: at(length * 0.22, width * 0.78), control2: at(length * 0.72, width * 0.62))
        p.addCurve(to: base, control1: at(length * 0.72, -width * 0.62), control2: at(length * 0.22, -width * 0.78))
        p.closeSubpath()
        return p
    }

    /// قاعدة ورقة تبعد عن محور الغصن نصف سمكه + الفاصل
    static func base(_ s: CGFloat, angle: CGFloat) -> CGPoint {
        let o = point(s), r = width / 2 + gap
        return FTMG.p(o.x + cos(angle) * r, o.y + sin(angle) * r)
    }

    static let leftAngle = direction(0.36) - 1.05
    static let rightAngle = direction(0.66) + 1.0
    static let leftBase = base(0.36, angle: leftAngle)
    static let rightBase = base(0.66, angle: rightAngle)
    static let leftLeaf = leaf(base: leftBase, angle: leftAngle, length: 40, width: 23)
    static let rightLeaf = leaf(base: rightBase, angle: rightAngle, length: 35, width: 20)
    static let newAngle = direction(1) - 0.12
    static let newBase = FTMG.p(p3.x + cos(newAngle) * (width / 2 + gap), p3.y + sin(newAngle) * (width / 2 + gap))
    static let newLeaf = leaf(base: newBase, angle: newAngle, length: 31, width: 17)

    /// من الشبكة إلى نقاط الوسام: الشكل الكامل في مربّع ٣٣ نقطة، مركزه مركز الوسام
    static let fit: CGAffineTransform = {
        var all = stem.strokedPath(FTKit.Stroke.round(width))
        all.addPath(leftLeaf)
        all.addPath(rightLeaf)
        all.addPath(newLeaf)
        let b = all.boundingRect
        let s = 33 / max(b.width, b.height)
        return CGAffineTransform(translationX: -b.midX, y: -b.midY).concatenating(CGAffineTransform(scaleX: s, y: s))
    }()
}

// MARK: - هندسة مساعدة (كل الأشكال بنفس اتجاه الدوران، فاتحادها داخل مسار واحد لا يترك ثقوباً)

nonisolated fileprivate enum FTMG {
    /// ذهبي الختم فوق السطح الأبيض — بين `gold` و`goldOnLight` حتى يُقرأ الختم كذهب لا كنحاس
    static let sealLight = rgb(0xD9A846)

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    @inline(__always) static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// ٠ → ١ → ٠ ناعم (مشتقّته صفر عند الطرفين)
    static func hump(_ q: Double) -> Double {
        let s = sin(.pi * min(max(q, 0), 1))
        return s * s
    }

    /// قرص بدوران مع عقارب الساعة على الشاشة
    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x + r, y: c.y))
        p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        return p
    }

    /// دائرة للخطوط
    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        disc(.zero, 1).applying(CGAffineTransform(scaleX: rx, y: ry).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }

    /// مستطيل مستدير الزوايا بنفس اتجاه الدوران
    static func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat) -> Path {
        let r = max(0, min(r, w / 2, h / 2))
        var p = Path()
        p.move(to: CGPoint(x: x + r, y: y))
        p.addLine(to: CGPoint(x: x + w - r, y: y))
        p.addArc(center: CGPoint(x: x + w - r, y: y + r), radius: r, startAngle: .degrees(-90), endAngle: .zero, clockwise: false)
        p.addLine(to: CGPoint(x: x + w, y: y + h - r))
        p.addArc(center: CGPoint(x: x + w - r, y: y + h - r), radius: r, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: x + r, y: y + h))
        p.addArc(center: CGPoint(x: x + r, y: y + h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: x, y: y + r))
        p.addArc(center: CGPoint(x: x + r, y: y + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }

    /// مضلّع بزوايا مستديرة (`r` لكل رأس) — الرؤوس بترتيب عقارب الساعة على الشاشة
    static func poly(_ pts: [CGPoint], r: [CGFloat]) -> Path {
        var p = Path()
        let n = pts.count
        guard n > 2 else { return p }
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            let rad = i < r.count ? r[i] : 0
            let d1 = hypot(prev.x - cur.x, prev.y - cur.y), d2 = hypot(next.x - cur.x, next.y - cur.y)
            let k1 = d1 > 0 ? min(rad, d1 / 2) / d1 : 0, k2 = d2 > 0 ? min(rad, d2 / 2) / d2 : 0
            let a = CGPoint(x: cur.x + (prev.x - cur.x) * k1, y: cur.y + (prev.y - cur.y) * k1)
            let b = CGPoint(x: cur.x + (next.x - cur.x) * k2, y: cur.y + (next.y - cur.y) * k2)
            if i == 0 { p.move(to: a) } else { p.addLine(to: a) }
            if rad > 0 { p.addQuadCurve(to: b, control: cur) } else { p.addLine(to: b) }
        }
        p.closeSubpath()
        return p
    }

    static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    static func arc(_ c: CGPoint, _ r: CGFloat, _ a0: Double, _ a1: Double) -> Path {
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        return p
    }

    /// خط مستدير الأطراف كشكل مملوء (يُدمج مع غيره في عملية تعبئة واحدة)
    static func stroked(_ p: Path, _ w: CGFloat) -> Path {
        p.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    /// نجمة خماسية برؤوس ملساء
    static func star(_ c: CGPoint, _ r1: CGFloat, _ r2: CGFloat, rot: Double) -> Path {
        var pts: [CGPoint] = []
        for i in 0..<10 {
            let a = rot + Double(i) * .pi / 5
            let r = i % 2 == 0 ? r1 : r2
            pts.append(CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
        }
        return poly(pts, r: Array(repeating: r1 * 0.12, count: 10))
    }

    /// نصف قطع ناقص سفلي (السلّة): من الطرف الأيمن نزولاً إلى الأيسر ثم الحافة العليا
    static func halfEllipseDown(center c: CGPoint, rx: CGFloat, ry: CGFloat) -> Path {
        var u = Path()
        u.move(to: CGPoint(x: 1, y: 0))
        u.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        u.closeSubpath()
        return u.applying(CGAffineTransform(scaleX: rx, y: ry).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }

    /// مظلّة المهد: الربع العلوي الخلفي من قطع ناقص مركزه `center` (من القمّة إلى الطرف الأيمن)
    static func quarterHood(center c: CGPoint, rx: CGFloat, ry: CGFloat) -> Path {
        var u = Path()
        u.move(to: .zero)
        u.addLine(to: CGPoint(x: 0, y: -1))
        u.addArc(center: .zero, radius: 1, startAngle: .degrees(-90), endAngle: .zero, clockwise: false)
        u.closeSubpath()
        return u.applying(CGAffineTransform(scaleX: rx, y: ry).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }
}
