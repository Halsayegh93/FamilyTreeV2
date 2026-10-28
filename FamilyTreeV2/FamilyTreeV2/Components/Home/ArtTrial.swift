import SwiftUI
import Combine

// اتجاه الرسوم النهائي: «مجسّمات» (soft3d) — اختيار المالك ٢٠٢٦-١٠-٠٦ بعد تجربة أربعة اتجاهات على الجهاز.
// حُذفت الاتجاهات الخاسرة (زجاج، ذهبي، سدو، و«الحالي») وشريط التبديل ولوحة المقارنة معها.
// يبقى هنا ما تشترك فيه شاشات التطبيق من أغلفة «مجسّمات»: حركة المجسّم، تكوين مربّع الوسط، ولمسة البطاقات.

// MARK: - شكل المكتبة والمشاريع — ثابت للكل

/// اختيار المالك من تجربة الرسومات (٢٠٢٦-١٠-٠٦) كان محفوظاً في جهازه فقط (UserDefaults tmpArt*Variant) فيرى الأعضاء غيره،
/// وصار ثابتاً للكل (٢٠٢٦-١٠-١٩): المكتبة = «مخطوطة» (١)، المشاريع = «واجهة محلّ» (٠). بلا مفتاح مخفي (إرشاد أبل 2.5.19).
enum FTArtVariants {
    static let library = 1
    static let projects = 0

    static func value(for place: String) -> Int {
        switch place {
        case "library": return library
        case "projects": return projects
        default: return 0
        }
    }
}

// MARK: - رمز المربّع/الرأس ← اسم المكان المشترك (nil = لا رسم)

enum FTArtPlace {
    static func place(for icon: String) -> String? {
        let i = icon
        if i.hasPrefix("tree") { return "tree" }
        if i.hasPrefix("sofa") || i.hasPrefix("map") || i.hasPrefix("mappin") || i.hasPrefix("cup.and.saucer")
            || i.hasPrefix("tent") || i.hasPrefix("building.columns") { return "diwaniya" }
        if i.hasPrefix("books") || i.hasPrefix("book.fill") || i.hasPrefix("book.closed") { return "library" }
        if i.hasPrefix("storefront") || i.hasPrefix("briefcase") || i.hasPrefix("bag") { return "projects" }
        if i.hasPrefix("envelope") { return "contact" }
        return nil
    }
}


// MARK: - أغلفة «مجسّمات» الصغيرة

/// رسم «مجسّمات» إن وُجد، وإلا البديل (للرسوم التي قد ترجع nil مثل شارات الأخبار)
struct TrialArt<Fallback: View>: View {
    let make: () -> AnyView?
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if let art = make() {
            art
        } else {
            fallback()
        }
    }
}

/// رمز الوقت في بطاقة الترحيب — قرص الوقت المجسّم (شمس طالعة · شمس الظهر · هلال)
struct TrialGreetingGlyph: View {
    let hour: Int
    let tint: Color

    var body: some View {
        FT5STrial.greetingGlyph(hour: hour, tint: tint)
            .frame(width: 18, height: 18)
    }
}

/// أيقونة رأس المربّع/البطاقة: المجسّم نفسه بدل الدائرة الزجاجية (بلا تكرار للرمز)
struct TrialHeaderIcon: View {
    let icon: String
    let tint: Color
    var side: CGFloat = 52

    var body: some View {
        FT5STrial.headerIcon(icon: icon, tint: tint)
            .frame(width: side, height: side)
            .modifier(TrialObjectMotion(side: side))
    }
}

// MARK: - لمسة «مجسّمات» على بطاقات المربّعات (أقسام المربّع، صفوف الحقول) — خفيفة ومعتدلة

/// لمسة الطين الواحدة (طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد»): لمعة علوية داخلية، واختيارياً ظلّ داخلي سفلي
/// خفيف (عقد الشجرة وأزرارها) وظلّ خارجي لطيف بلون غامق القسم (البطاقات). كل القيم من `DS.Card`.
/// تجمع `TrialCardSkin` (البطاقات) و`TreeArtSkin` (TreeView.swift — بنفس معاملاته، ليُستبدل به ثم يُحذف).
struct DSClaySkin: ViewModifier {
    var active: Bool = true
    /// nil = كبسولة
    var radius: CGFloat? = nil
    /// سطح ممتلئ بلون (عليه نص أبيض) — لمعة أخفّ
    var onFill: Bool = false
    /// للتوافق مع `TreeArtSkin` (لا يغيّر الرسم)
    var compact: Bool = false
    var eyeRow: CGFloat? = nil
    /// خلفية زجاج/مادة أو بطاقة: حواف فقط بلا الظلّ الداخلي السفلي
    var glassBacked: Bool = false
    /// الظلّ الخارجي (البطاقات)
    var shadow: Bool = false
    /// المحتوى مصمت داخل شكله (سطح البطاقة معتم) → الظلّ يُلقى من الشكل نفسه تحت البطاقة: يُرسم مرة ويبقى،
    /// بدل ظلّ «كل المحتوى» الذي يُعاد حسابه خارج الشاشة مع كل إطار (فحص «اللاق» ٢٠٢٦-١٠-٠٧). الشكل واحد.
    /// false = سطح شفّاف (بطاقة مختارة بلون خفيف) — يبقى ظلّ المحتوى كما كان.
    var solid: Bool = true
    /// nil = قسم البيئة، ثم الرئيسية
    var section: AppSection? = nil
    @Environment(\.dsSection) private var envSection
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        if active {
            let s = section ?? envSection ?? .home
            let dark = scheme == .dark
            let shade = s.deep.opacity(dark ? DS.Card.shadowDark : DS.Card.shadowLight)
            // الزخرفة فوق المحتوى لا تلتقط اللمس (أزرار البطاقة تحتها)
            let decorated = content
                .overlay(decoration(s, dark: dark).allowsHitTesting(false).accessibilityHidden(true))
            if !shadow {
                decorated
            } else if solid && DS.Card.shapeShadows {
                decorated.background(
                    // معتم ومخفي تحت البطاقة — يُلقي الظلّ فقط
                    shape(inset: DS.Card.shadowInset).fill(s.deep)
                        .shadow(color: shade, radius: DS.Card.shadowRadius, x: 0, y: DS.Card.shadowY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                )
            } else {
                decorated.shadow(color: shade, radius: DS.Card.shadowRadius, x: 0, y: DS.Card.shadowY)
            }
        } else {
            content
        }
    }

    private func shape(inset: CGFloat = 0) -> AnyShape {
        radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous).inset(by: inset)) }
            ?? AnyShape(Capsule().inset(by: inset))
    }

    private func decoration(_ s: AppSection, dark: Bool) -> some View {
        let shape = shape()
        let light = dark ? DS.Card.highlightDark : (onFill ? DS.Card.highlightOnFill : DS.Card.highlightLight)
        return ZStack {
            if !glassBacked {
                shape.fill(LinearGradient(colors: [.clear, s.deep.opacity(dark ? DS.Card.innerShadeDark : DS.Card.innerShadeLight)],
                                          startPoint: .center, endPoint: .bottom))
            }
            shape.stroke(LinearGradient(colors: [.white.opacity(light), .clear], startPoint: .top, endPoint: .center),
                         lineWidth: DS.Card.highlightWidth)
                .padding(DS.Card.highlightWidth / 2)
        }
    }
}

/// لمسة «مجسّمات» على البطاقات (أقسام المربّع، صفوف الحقول، البطاقات) = `DSClaySkin` بلمعة وظلّ خارجي
struct TrialCardSkin: ViewModifier {
    let radius: CGFloat
    /// سطح البطاقة معتم (الافتراضي) — انظر `DSClaySkin.solid`
    var solid: Bool = true

    func body(content: Content) -> some View {
        content.modifier(DSClaySkin(radius: radius, glassBacked: true, shadow: true, solid: solid))
    }
}

extension View {
    /// لمسة «مجسّمات» على بطاقة داخل مربّع — للبطاقة كاملة (سطح + إطار + لمسة) استعمل `.dsCard()`
    /// `solid: false` لسطح شفّاف (بطاقة مختارة بلون خفيف) — يبقى ظلّ المحتوى كما كان
    func trialCardSkin(radius: CGFloat, solid: Bool = true) -> some View { modifier(TrialCardSkin(radius: radius, solid: solid)) }

    /// لمسة الطين بخيارات `DSClaySkin` (كبسولة، سطح ملوّن، ظلّ داخلي) — بديل `TreeArtSkin`
    func dsClaySkin(active: Bool = true, radius: CGFloat? = nil, onFill: Bool = false, glassBacked: Bool = false,
                    shadow: Bool = false) -> some View {
        modifier(DSClaySkin(active: active, radius: radius, onFill: onFill, glassBacked: glassBacked, shadow: shadow))
    }
}

// MARK: - قرص الحالة المجسّم (بلا بديل SF)

/// قرص أيقونة «مجسّمات» صغير: الرمز أبيض على زرّ طين صقيل بلون القسم/المعنى. بديل كل
/// `TrialArt(make: { FT5STrial.stateIcon(...) }) { <SF احتياطي> }` — الاحتياطي لا يُرسم أبداً.
/// الكحلي (`DS.Color.primary`/`actionNavy`) ← لون القسم، وألوان المعاني كما هي (مقروءة في الداكن).
struct DSStateIcon: View {
    let icon: String
    var tint: Color = DS.Color.primary
    var size: CGFloat = DS.Icon.row
    /// false = اللون كما مُرِّر تماماً (لا تحويل للقسم ولا للحبر)
    var mapsChrome: Bool = true
    @Environment(\.dsSection) private var section
    /// وضع العرض: أيقونة الحالة الكبيرة (صفحات التجميد/الأجهزة…) تصغر إلى `DS.Landscape.stateHero`
    @Environment(\.dsLandscape) private var landscape

    init(_ icon: String, tint: Color = DS.Color.primary, size: CGFloat = DS.Icon.row, mapsChrome: Bool = true) {
        self.icon = icon
        self.tint = tint
        self.size = size
        self.mapsChrome = mapsChrome
    }

    var body: some View {
        let shown = mapsChrome ? tint.dsChrome(in: section).dsReadableGlyph : tint
        // (الدور «أيقونة الحالة الكبيرة» فقط — بقية المقاسات كما هي، والرسوم التي تكبّرها بنفسها لا تتأثر)
        let hero = self.size == DS.Icon.stateHero || self.size == DS.Icon.stateArt
        let size = landscape && hero ? DS.Landscape.stateHero : self.size
        FT5STrial.stateIcon(icon: icon, tint: shown, size: size)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// حركة المجسّم (طلب المالك ٢٠٢٦-١٠-٠٦ «وين حركات الانميشن وحركات المجسمات»): ظهور بنبضة مرة واحدة،
/// تنفّس بطيء دورته ٨ ث، ولمعة ضوء مائلة تعبر المجسّم كل ٨ ث مقصوصة على شكله — تسكن مع «تقليل الحركة»
/// ومع فتح مربّع فوقها (ftAnimationsPaused). التحويلات على الطبقة فقط، فلا يُعاد رسم الـ Canvas مع كل إطار.
///
/// الأداء (فحص «اللاق» ٢٠٢٦-١٠-٠٧): كانت كل نسخة تنفّس بـ`repeatForever` بمعدّل الشاشة (٦٠–١٢٠ إطاراً)، فيُعاد
/// تركيب الشاشة كلها (ظلال البطاقات والزجاج والقناع) كل إطار ما دام مجسّم ظاهراً. الآن: ساعة واحدة للتطبيق
/// (`FTAmbientClock`) بـ`breathFPS` إطاراً تحرّك كل المجسّمات معاً في تحديث واحد — التنفّس (١٫٨ نقطة في ٤ ث) لا
/// يُرى فرقه — وتقف خارج الشاشة وأثناء التمرير. اللمعة بمعدّل الشاشة كما كانت، وطبقتها (نسخة المجسّم قناعاً) لا توجد إلا أثناء
/// العبور. مؤقّت اللمعة واحد مشترك بدل مؤقّت لكل مجسّم. الشكل في السكون وأثناء الحركة كما هو.
struct TrialObjectMotion: ViewModifier {
    let side: CGFloat
    /// تأخير اللمعة بين المربّعات (ترتيب المربّع) حتى لا تلمع معاً
    var stagger: Double = 0
    /// الظهور الأول: نبضة من ٠٫٨٦ إلى ١ (المربّعات: مرة لكل تشغيل)
    var entrance: Bool = true
    /// لمعة الضوء العابرة — مربّعات الرئيسية بلا وهج على المجسّم (طلب المالك ٢٠٢٦-١٠-٠٧)
    var glints: Bool = true

    // قيم الحركة (المكان الواحد)
    /// التنفّس: تكبير ٣٫٥٪ ذهاباً في ٤ ث ثم إياباً (easeInOut)
    static let breathScale: CGFloat = 0.035
    static let breathHalfPeriod: Double = 4
    /// معدّل ساعة التنفّس — حركة ١٫٨ نقطة في ٤ ث لا تحتاج أكثر
    static let breathFPS: Float = 15
    /// اللمعة: كل ٨ ث، عبورها ١ ث، من -١٫٤ إلى ١٫٤ ضلع المجسّم
    static let glintPeriod: Double = 8
    static let glintDuration: Double = 1.0
    static let glintFrom: CGFloat = -1.4
    static let glintTo: CGFloat = 1.4
    static let glintOpacity: Double = 0.55
    static let glintWidth: CGFloat = 0.45
    static let glintHeight: CGFloat = 2.2
    static let glintAngle: Double = 22
    /// مهلة بعد العبور قبل إزالة طبقة اللمعة
    static let glintCleanup: Double = 0.1
    /// أول لمعة بعد الظهور، وتأخيرها/تأخير الظهور لكل درجة ترتيب
    static let firstGlint: Double = 1.2
    static let firstGlintStagger: Double = 0.3
    static let glintStagger: Double = 0.35
    static let entranceScale: CGFloat = 0.86
    static let entranceDelay: Double = 0.12
    static let entranceStagger: Double = 0.08
    static let entranceSpring = Animation.spring(response: 0.55, dampingFraction: 0.7)

    /// مؤقّت اللمعة الواحد (يعمل ما دام مجسّم يستمع)
    /// (وضع `.default`: لا تبدأ لمعة أثناء سحب/تمرير — تأتي بعده)
    static let glintTicker = Timer.publish(every: glintPeriod, on: .main, in: .default).autoconnect().share()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ftAnimationsPaused) private var paused
    private var clock: FTAmbientClock { FTAmbientClock.shared }
    @State private var shown = false
    /// بداية دورة التنفّس — nil = ساكن (خارج الشاشة/موقوف)
    @State private var breathStart: TimeInterval?
    /// زمن الساعة المشتركة — يتحدّث فقط والمجسّم يتنفّس (الساكن لا يُعاد رسمه مع النبضات)
    @State private var now: TimeInterval = 0
    @State private var onScreen = false
    @State private var glint: CGFloat = TrialObjectMotion.glintFrom
    /// طبقة اللمعة موجودة أثناء العبور فقط
    @State private var sweeping = false
    @State private var lastSweep = Date.distantPast
    @State private var token = FTAmbientClock.Token()
    private var still: Bool { reduceMotion || paused }

    func body(content: Content) -> some View {
        content
            .overlay { if glints && sweeping { glintBand(content) } }
            .scaleEffect(1 + Self.breathScale * Self.breath(since: breathStart, at: now))
            .scaleEffect(shown ? 1 : Self.entranceScale)
            .opacity(shown ? 1 : 0)
            .onAppear(perform: start)
            .onDisappear {
                onScreen = false
                restartBreath()
            }
            .onChange(of: paused) { _ in restartBreath() }
            .onReceive(Self.glintTicker) { _ in if glints { sweep() } }
            .onReceive(clock.$time) { t in if breathStart != nil { now = t } }
    }

    private func glintBand(_ content: Content) -> some View {
        LinearGradient(colors: [.clear, .white.opacity(Self.glintOpacity), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: side * Self.glintWidth, height: side * Self.glintHeight)
            .rotationEffect(.degrees(Self.glintAngle))
            .offset(x: glint * side)
            .mask(content)
            .allowsHitTesting(false)
    }

    private func start() {
        onScreen = true
        if still || !entrance {
            shown = true
        } else {
            withAnimation(Self.entranceSpring.delay(Self.entranceDelay + stagger * Self.entranceStagger)) { shown = true }
        }
        restartBreath()
        if !still && glints {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstGlint + stagger * Self.firstGlintStagger) { sweep() }
        }
    }

    /// التنفّس من بدايته (١) — أو السكون إن كان المجسّم خارج الشاشة/موقوفاً
    private func restartBreath() {
        let run = onScreen && !still
        clock.hold(self.clockToken, run)
        breathStart = run ? clock.time : nil
        now = clock.time
    }

    /// مفتاح ثابت لكل نسخة (للعدّ في الساعة المشتركة)
    private var clockToken: ObjectIdentifier { ObjectIdentifier(token) }

    private func sweep() {
        guard !still, onScreen, Date().timeIntervalSince(lastSweep) > Self.glintPeriod / 2 else { return }
        lastSweep = Date()
        let delay = stagger * Self.glintStagger
        // الطبقة تُضاف عند بدايتها، ثم تعبر في الدورة التالية (لا تحريك لعنصر لحظة إضافته)
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { glint = Self.glintFrom; sweeping = true }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: Self.glintDuration).delay(delay)) { glint = Self.glintTo }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.glintDuration + Self.glintCleanup) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { sweeping = false }
        }
    }

    /// موضع التنفّس ٠…١ (ذهاب ثم إياب بمنحنى easeInOut نفسه)
    static func breath(since start: TimeInterval?, at now: TimeInterval) -> CGFloat {
        guard let start else { return 0 }
        let e = max(0, now - start)
        let u = e.truncatingRemainder(dividingBy: breathHalfPeriod * 2) / breathHalfPeriod
        let x = u <= 1 ? u : 2 - u
        return CGFloat(FTAmbientClock.easeInOut(x))
    }
}

/// دوران هادئ مستمر (إطار الشعار/الصورة المتقطّع — دورة كل `ringPeriod` ث) بـ`fps` إطاراً بدل معدّل الشاشة:
/// حركة ١٨ نقطة/ث لا يُرى فرقها، وتُعاد تركيب الشاشة نصف المرّات (فحص «اللاق» ٢٠٢٦-١٠-٠٧). ثابت مع «تقليل
/// الحركة»، ويقف خارج الشاشة وخلف مربّع مفتوح فوقه (`ftAnimationsPaused`).
struct DSAmbientSpin: ViewModifier {
    var period: Double = DSAmbientSpin.ringPeriod
    static let ringPeriod: Double = 14
    static let fps: Double = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ftAnimationsPaused) private var paused
    @State private var start = Date()
    @State private var onScreen = false

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / Self.fps, paused: reduceMotion || paused || !onScreen)) { tl in
            let turns = reduceMotion ? 0 : max(0, tl.date.timeIntervalSince(start)) / period
            content.rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}

/// نبضة العاجل (الدفعة ١٠ «نبضة للعاجل» — «حالة النظام» حمراء): هالة بلون الحال تتّسع من النقطة وتتلاشى كل `DS.Pulse.period` ث،
/// على الساعة الهادئة المشتركة (`FTAmbientClock`، ١٥ إطاراً) — لا `repeatForever` ولا مؤقّت. تقف (وتختفي الهالة) حين لا تكون
/// عاجلة، خارج الشاشة، أثناء التمرير، خلف مربّع (`ftAnimationsPaused`)، ومع «تقليل الحركة»؛ والنقطة/الرمز نفسه ساكن دائماً.
struct DSUrgentPulse: ViewModifier {
    let color: Color
    let active: Bool
    var side: CGFloat = DS.Pulse.dot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ftAnimationsPaused) private var paused
    @State private var onScreen = false
    /// بداية الدورة — nil = ساكن
    @State private var start: TimeInterval?
    @State private var now: TimeInterval = 0
    @State private var token = FTAmbientClock.Token()
    private var clock: FTAmbientClock { FTAmbientClock.shared }

    func body(content: Content) -> some View {
        let q = phase
        content
            .background {
                Circle()
                    .fill(color)
                    .frame(width: side, height: side)
                    .scaleEffect(1 + (DS.Pulse.scale - 1) * CGFloat(1 - (1 - q) * (1 - q)))
                    .opacity(start == nil ? 0 : DS.Pulse.opacity * (1 - q))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear { onScreen = true; sync() }
            .onDisappear { onScreen = false; sync() }
            .onChange(of: active) { _ in sync() }
            .onChange(of: paused) { _ in sync() }
            .onChange(of: reduceMotion) { _ in sync() }
            .onReceive(clock.$time) { t in if start != nil { now = t } }
    }

    /// موضع الدورة ٠…١
    private var phase: Double {
        guard let start else { return 0 }
        return max(0, now - start).truncatingRemainder(dividingBy: DS.Pulse.period) / DS.Pulse.period
    }

    private func sync() {
        let run = active && onScreen && !reduceMotion && !paused
        clock.hold(ObjectIdentifier(token), run)
        start = run ? clock.time : nil
        now = clock.time
    }
}

extension View {
    /// نبضة هادئة للعاجل على الساعة المشتركة (`DSUrgentPulse`)
    func dsUrgentPulse(_ color: Color, active: Bool, side: CGFloat = DS.Pulse.dot) -> some View {
        modifier(DSUrgentPulse(color: color, active: active, side: side))
    }
}

/// الساعة الهادئة الواحدة للتطبيق: مؤشّر عرض واحد بمعدّل منخفض يحرّك كل المجسّمات المتنفّسة في تحديث واحد،
/// ويقف تماماً حين لا يتنفّس أي مجسّم ظاهر (خارج الشاشة، «تقليل الحركة»، خلف مربّع، التطبيق في الخلفية).
/// وضع `.default`: يسكن أثناء السحب والتمرير (لا يزاحم إطاراته) ويكمل بعده من حيث وقف — زمنه لا يقفز.
@MainActor final class FTAmbientClock: NSObject, ObservableObject {
    static let shared = FTAmbientClock()
    /// مرجع ثابت لكل مستمع
    final class Token {}

    /// زمن الحركة بالثواني — يتقدّم مع النبضات فقط (لا يقفز بعد توقّف أو تمرير)
    @Published private(set) var time: TimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var holders = Set<ObjectIdentifier>()
    private var link: CADisplayLink?

    func hold(_ token: ObjectIdentifier, _ on: Bool) {
        if on { holders.insert(token) } else { holders.remove(token) }
        if holders.isEmpty { stop() } else { startIfNeeded() }
    }

    private func startIfNeeded() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        let fps = TrialObjectMotion.breathFPS
        l.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        l.add(to: .main, forMode: .default)
        lastTick = CACurrentMediaTime()
        link = l
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        let t = CACurrentMediaTime()
        // بعد توقّف (تمرير، خلفية) يتقدّم نبضة واحدة فقط — تكمل الحركة من مكانها
        time += min(t - lastTick, 2.0 / Double(TrialObjectMotion.breathFPS))
        lastTick = t
    }

    /// منحنى SwiftUI `.easeInOut` نفسه (bezier 0.42, 0, 0.58, 1)
    nonisolated static func easeInOut(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        let p1 = 0.42, p2 = 0.58
        func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t }
        func by(_ t: Double) -> Double { 3 * (1 - t) * t * t + t * t * t }   // y1 = 0, y2 = 1
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<20 {
            t = (lo + hi) / 2
            if bx(t) < x { lo = t } else { hi = t }
        }
        return by(t)
    }
}

/// مربّع الرئيسية بتكوين وسطي («مجسّمات»): المجسّم في الوسط على ضوء ناعم والاسم تحته بالوسط — بلا عدد
struct TrialCenteredTile: View {
    let art: AnyView
    let title: String
    let count: Int?
    let scale: CGFloat
    /// ضلع المجسّم بالنقاط — يتبع ارتفاع المربّع (المربّعان الكبيران مجسّمهما أكبر)؛ nil = ٤٨ × المقياس
    var artSide: CGFloat? = nil
    /// ترتيب المربّع (لتأخير اللمعة) وهل يُلعب الظهور الأول
    var stagger: Double = 0
    var entrance: Bool = true

    var body: some View {
        let side = artSide ?? 48 * scale
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                // المجسّم بشكله الأساسي: بلا ضوء خلفه (طلب المالك ٢٠٢٦-١٠-٠٧ «بدون وهج»)، مع لمعة الضوء العابرة
                // عليه والظهور الأول والتنفّس البطيء («خل لمعة الضوء على المجسّم»)
                art.frame(width: side, height: side)
                    .modifier(TrialObjectMotion(side: side, stagger: stagger, entrance: entrance))
                .frame(height: side + 2)
                Text(title)
                    .dsFont(.tileTitle)
                    .foregroundColor(DS.Color.tileTitle)
                    .lineLimit(1)   // الاسم سطر واحد في كل المربّعات (يصغر قليلاً إن ضاق)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: DS.Color.tileTitleShadow, radius: 3, x: 0, y: 1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // بلا عدد في الزاوية (طلب المالك) — المربّع: المجسّم والاسم بالوسط فقط
        }
    }
}
