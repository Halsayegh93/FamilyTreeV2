import SwiftUI
import Combine

// اتجاه الرسوم النهائي: «مجسّمات» (soft3d) — اختيار المالك ٢٠٢٦-١٠-٠٦ بعد تجربة أربعة اتجاهات على الجهاز.
// حُذفت الاتجاهات الخاسرة (زجاج، ذهبي، سدو، و«الحالي») وشريط التبديل ولوحة المقارنة معها.
// يبقى هنا ما تشترك فيه شاشات التطبيق من أغلفة «مجسّمات»: حركة المجسّم، تكوين مربّع الوسط، ولمسة البطاقات.

// MARK: - أشكال المكتبة/المشاريع المخزّنة (اختيار المالك على جهازه — يبقى محفوظاً)

enum FTArtVariants {
    static let libraryKey = "tmpArtLibraryVariant"
    static let projectsKey = "tmpArtProjectsVariant"

    /// الشكل المختار للمكان (٠ افتراضياً) — المكتبة: كتاب مفتوح/مخطوطة/صندوق أرشيف، المشاريع: واجهة محلّ/سهم/صاروخ
    static func value(for place: String) -> Int {
        switch place {
        case "library": return UserDefaults.standard.integer(forKey: libraryKey)
        case "projects": return UserDefaults.standard.integer(forKey: projectsKey)
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
    /// nil = قسم البيئة، ثم الرئيسية
    var section: AppSection? = nil
    @Environment(\.dsSection) private var envSection
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if active {
            let s = section ?? envSection ?? .home
            let dark = scheme == .dark
            content
                // الزخرفة فوق المحتوى لا تلتقط اللمس (أزرار البطاقة تحتها)
                .overlay(decoration(s, dark: dark).allowsHitTesting(false).accessibilityHidden(true))
                .shadow(color: shadow ? s.deep.opacity(dark ? DS.Card.shadowDark : DS.Card.shadowLight) : .clear,
                        radius: shadow ? DS.Card.shadowRadius : 0, x: 0, y: shadow ? DS.Card.shadowY : 0)
        } else {
            content
        }
    }

    private func decoration(_ s: AppSection, dark: Bool) -> some View {
        let shape: AnyShape = radius.map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
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

    func body(content: Content) -> some View {
        content.modifier(DSClaySkin(radius: radius, glassBacked: true, shadow: true))
    }
}

extension View {
    /// لمسة «مجسّمات» على بطاقة داخل مربّع — للبطاقة كاملة (سطح + إطار + لمسة) استعمل `.dsCard()`
    func trialCardSkin(radius: CGFloat) -> some View { modifier(TrialCardSkin(radius: radius)) }

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
struct TrialObjectMotion: ViewModifier {
    let side: CGFloat
    /// تأخير اللمعة بين المربّعات (ترتيب المربّع) حتى لا تلمع معاً
    var stagger: Double = 0
    /// الظهور الأول: نبضة من ٠٫٨٦ إلى ١ (المربّعات: مرة لكل تشغيل)
    var entrance: Bool = true
    /// لمعة الضوء العابرة — مربّعات الرئيسية بلا وهج على المجسّم (طلب المالك ٢٠٢٦-١٠-٠٧)
    var glints: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ftAnimationsPaused) private var paused
    @State private var shown = false
    @State private var breathe = false
    @State private var glint: CGFloat = -1.4
    private let ticker = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    private var still: Bool { reduceMotion || paused }

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: side * 0.45, height: side * 2.2)
                    .rotationEffect(.degrees(22))
                    .offset(x: glint * side)
                    .mask(content)
                    .opacity(glints ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .scaleEffect(breathe ? 1.035 : 1)
            .scaleEffect(shown ? 1 : 0.86)
            .opacity(shown ? 1 : 0)
            .onAppear(perform: start)
            .onChange(of: paused) { _ in restartBreath() }
            .onReceive(ticker) { _ in if glints { sweep() } }
    }

    private func start() {
        if still || !entrance {
            shown = true
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.12 + stagger * 0.08)) { shown = true }
        }
        restartBreath()
        if !still && glints { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + stagger * 0.3) { sweep() } }
    }

    private func restartBreath() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { breathe = false }
        guard !still else { return }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathe = true }
    }

    private func sweep() {
        guard !still else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { glint = -1.4 }
        withAnimation(.easeInOut(duration: 1.0).delay(stagger * 0.35)) { glint = 1.4 }
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
                    .font(DS.Font.scaled(13, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)   // الاسم سطر واحد في كل المربّعات (يصغر قليلاً إن ضاق)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // بلا عدد في الزاوية (طلب المالك) — المربّع: المجسّم والاسم بالوسط فقط
        }
    }
}
