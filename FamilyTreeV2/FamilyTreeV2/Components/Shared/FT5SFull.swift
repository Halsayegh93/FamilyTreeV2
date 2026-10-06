import SwiftUI

// MARK: - FT5S — «مجسّمات صقيلة» (الجولة ٧، ٢٠٢٦-١٠-٠٥)
//
// طلب المالك: «المجسمات نبيها تصير شكل ثاني بجميع الفئات اعادة تصميم» — واختار «أشكال جديدة وأسلوب جديد»،
// مع شروطه السابقة: «بسيط وخفيف»، «بسيط وقوي ومرتب وباعتدال»، بلا مشاهد مزدحمة ولا علامات باهتة.
//
// الأسلوب «صقيل»: أيقونات مجسّمة حديثة بأحجام جريئة بسيطة —
//  • وجه بتدرّج واضح من الضوء (أعلى الجهة الخارجية) + سُمك أغمق تحته يعطي الحجم (بلا أي ضبابية)،
//  • لمعة واحدة حادّة الحافة على الحجم الرئيسي، وظلّ تلامس ناعم واحد تحته،
//  • ألوان مشتقّة من لون كل قسم (درجات أفتح منه حتى يقرأ المجسّم فوق مربّعه الملوّن) + لمسة دافئة واحدة
//    (ذهبي/رملي) + أبيض الورق. على الأسطح الفاتحة تنزل الدرجات خطوة حتى لا يبهت المجسّم.
// الرموز: شجرة مستديرة ثمارها أفراد العائلة · مبخرة الديوانية · فقاعتا حوار للتواصل ·
// المكتبة: كتاب مفتوح / مخطوطة / صندوق أرشيف · المشاريع: واجهة محلّ / سهم النموّ / صاروخ انطلاق ·
// صحيفة مطويّة ومكبّر صوت للأخبار · بيدقان للأعضاء · خزنة وختم موثّق للأمان · مفتاح تبديل للإعدادات ·
// هلال ونجمة رماديّان للوفاة (ساكن دائماً، بلا ذهبي) · جرس الإشعارات · ساعة الانتظار.
//
// الأداء: كل رسم ساكن ويُرسم مرة واحدة؛ لكل مجسّم ≤ ٨ عمليات تعبئة وبلا أي طبقة ضبابية. لا TimelineView ولا
// حركة متكرّرة؛ الحركة الوحيدة ظهور واحد بالشفافية (مجسّم مربّع الرئيسية ولحظات التنبيه) ويُلغى مع «تقليل الحركة».
// الإحداثيات بالعربية (المجسّم في الجهة اليسرى) وتُعكس للإنجليزية — عدا سهم النموّ والصاروخ فيبقيان صاعدين يميناً.

// MARK: - الواجهة (العقد)

@MainActor enum FT5STrial {
    /// ترتيب موحّد (طلب المالك ٢٠٢٦-١٠-٠٥ «رتب المجسمات مع المسميات»): المجسّم يأخذ مكان الأيقونة الزجاجية
    /// أعلى بداية المربّع بحجم واحد في كل المربّعات (`tileIcon`)، والاسم تحته، والعدد في الطرف الآخر — بلا تكرار
    static let showsTileIcon: Bool = true
    /// المجسّم فوق طبقة التعتيم (لا يبهت أسفل المربّع)
    static let tileArtUnderOverlay: Bool = false

    static let libraryVariantNames: [String] = ["كتاب مفتوح", "مخطوطة", "صندوق أرشيف"]
    static let projectsVariantNames: [String] = ["واجهة محلّ", "سهم النموّ", "صاروخ انطلاق"]

    /// آخر شكل اختاره المالك للمكتبة/المشاريع (يُحدَّث من مربّع الرئيسية) — رأس القسم وصفحته الفاضية يتبعانه
    static var libraryVariant: Int = 0
    static var projectsVariant: Int = 0

    /// لا رسم بملء المربّع — المجسّم في مكان الأيقونة (`tileIcon`)؛ يحدّث الشكل المختار للرؤوس والصفحات
    static func tile(_ place: String, variant: Int, badge: Bool, animateOnce: Bool) -> AnyView {
        if place == "library" { libraryVariant = FT5SArt.clampVariant(variant) }
        if place == "projects" { projectsVariant = FT5SArt.clampVariant(variant) }
        return AnyView(EmptyView())
    }

    /// أيقونة مربّع الرئيسية: مجسّم القسم في وسط إطاره (بدل الدائرة الزجاجية)
    static func tileIcon(_ place: String, variant: Int) -> AnyView? {
        guard let kind = FT5SArt.placeKind(place, variant: variant) else { return nil }
        if place == "library" { libraryVariant = FT5SArt.clampVariant(variant) }
        if place == "projects" { projectsVariant = FT5SArt.clampVariant(variant) }
        return AnyView(FT5SIconArt(kind: kind, icon: "", tint: .white))
    }

    /// رأس المربّع الأوسط: لا رسم في الطرف الآخر — المجسّم صار أيقونة الرأس نفسها (`headerIcon`) بلا تكرار
    static func header(icon: String, tint: Color, deep: Color) -> AnyView {
        AnyView(EmptyView())
    }

    /// أيقونة الرأس (رؤوس المربّعات وبطاقات الصفحات): مجسّم العائلة أو الرمز نفسه مجسّماً صقيلاً — يملأ إطاره
    static func headerIcon(icon: String, tint: Color) -> AnyView {
        let kind = FT5SArt.headerKind(icon: icon, library: libraryVariant, projects: projectsVariant)
        return AnyView(FT5SIconArt(kind: kind, icon: icon, tint: tint))
    }

    static func empty(place: String?, icon: String, tint: Color) -> AnyView {
        var kind: FT5SKind? = nil
        if let place {
            let v = place == "library" ? libraryVariant : (place == "projects" ? projectsVariant : 0)
            kind = FT5SArt.placeKind(place, variant: v)
        }
        return AnyView(FT5SEmptyArt(kind: kind, icon: icon, tint: tint))
    }

    static func stateIcon(icon: String, tint: Color, size: CGFloat) -> AnyView {
        AnyView(FT5SStateIcon(icon: icon, tint: tint, size: size))
    }

    static func treeLoading() -> AnyView { AnyView(FT5STreeLoading()) }

    static func waiting() -> AnyView { AnyView(FT5SWaiting()) }

    static func notificationsEmpty() -> AnyView { AnyView(FT5SNotificationsEmpty()) }

    static func loginBackdrop(logoCenterY: CGFloat) -> AnyView { AnyView(FT5SLoginBackdrop(logoCenterY: logoCenterY)) }

    static func newsBadge(type: String, tint: Color, onColor: Bool) -> AnyView? {
        guard let kind = FT5SBadgeKind(type: type) else { return nil }
        return AnyView(FT5SNewsBadge(kind: kind, tint: tint, onColor: onColor))
    }

    static func moment(_ name: String, tint: Color) -> AnyView {
        AnyView(FT5SMoment(kind: FT5SMomentKind(name: name), tint: tint))
    }

    static func greetingGlyph(hour: Int, tint: Color) -> AnyView {
        let mood: FT5STimeOrb.Mood = (4..<12).contains(hour) ? .morning : ((12..<17).contains(hour) ? .afternoon : .evening)
        return AnyView(FT5STimeOrbView(mood: mood, size: 18))
    }

    /// بطاقة الترحيب تبقى نظيفة: اللمسة الوحيدة فيها رمز الوقت
    static func greetingBackground(tint: Color) -> AnyView? { nil }

    // MARK: الإضافة (الأخبار، الشجرة، الديوانيات، حسابي، الإدارة)

    /// شريط تحت رأس كل تبويب: خطّ رفيع يتلاشى نحو الطرفين، وفي الوسط قطعة ذهبية صقيلة صغيرة وحبّتان — ساكن
    static func tabHeaderOrnament(section: String, tint: Color) -> AnyView? {
        AnyView(FT5SOrnament())
    }

    /// مجسّم القسم في الطرف الآخر لبطاقة رأس الصفحة (داخل ٤٠٪ من الطرف وأعلى صفّ الأرقام)
    static func pageHeroArt(icon: String, tint: Color) -> AnyView? {
        nil   // المجسّم صار أيقونة البطاقة نفسها (headerIcon) — بلا تكرار
    }

    /// أيقونة مربّعات لوحة الإدارة: زرّ مجسّم صقيل بلون المربّع (وجه + سُمك + لمعة) ورمز أبيض — ٤٤ نقطة
    static func dashTileArt(icon: String, tint: Color) -> AnyView? {
        AnyView(FT5SButton(icon: icon, tint: tint, size: 44, squircle: true))
    }

    /// بطاقة «الأخبار»: صحيفة مطويّة صغيرة بعنوان أزرق — ٦٠×٤٤
    static func newsCardArt(tint: Color) -> AnyView? {
        AnyView(FT5SNewsCardArt())
    }
}

// MARK: - المجسّمات والأماكن

nonisolated enum FT5SKind: String, Hashable, CaseIterable {
    // مربّعات الرئيسية
    case familyTree, mabkhara, chat
    // المكتبة — ثلاثة أشكال
    case openBook, scroll, archiveBox
    // المشاريع — ثلاثة أشكال
    case storefront, growth, rocket
    // رؤوس المربّعات
    case newspaper, megaphone, pawns, safe, seal, toggle, crescent
    // الأماكن
    case bell, clock

    /// يبقى باتجاهه في الإنجليزية (الرسم البياني والصاروخ يصعدان يميناً في اللغتين)
    var keepsOrientation: Bool { self == .growth || self == .rocket }
}

nonisolated enum FT5SSlot: Hashable {
    /// مربّع الرئيسية (الأيقونة الزجاجية تبقى): المجسّم في الجهة المقابلة للعنوان
    case tile
    /// نفس المربّع مع كبسولة العدد: المجسّم يتنحّى عن الكبسولة
    case tileBadge
    /// رأس المربّع الأوسط (٨٦ نقطة): في الطرف الآخر، خارج الوسط ٥٥٪
    case header
    /// وسط المساحة (الصفحات الفاضية والأماكن)
    case center
}

nonisolated enum FT5SArt {

    static func clampVariant(_ v: Int) -> Int { max(0, min(2, v)) }

    /// المكان المشترك ← المجسّم
    static func placeKind(_ place: String, variant: Int) -> FT5SKind? {
        let v = clampVariant(variant)
        switch place {
        case "tree": return .familyTree
        case "diwaniya": return .mabkhara
        case "library": return [FT5SKind.openBook, .scroll, .archiveBox][v]
        case "projects": return [FT5SKind.storefront, .growth, .rocket][v]
        case "contact": return .chat
        case "news": return .newspaper
        case "member": return .pawns
        case "security": return .seal
        case "settings": return .toggle
        case "mourning": return .crescent
        case "notifications": return .bell
        case "waiting": return .clock
        default: return nil
        }
    }

    /// رمز SF للرأس ← المجسّم (nil = المعالجة العامة: الرمز نفسه مجسّماً صقيلاً بلون القسم)
    static func headerKind(icon: String, library: Int, projects: Int) -> FT5SKind? {
        func has(_ p: String) -> Bool { icon.hasPrefix(p) }
        if has("heart.slash") { return .crescent }
        if has("newspaper") || has("square.and.pencil") { return .newspaper }
        if has("megaphone") || has("speaker") { return .megaphone }
        if has("map") || has("mappin") || has("cup.and.saucer") || has("tent") || has("building.columns")
            || has("flame") { return .mabkhara }
        if has("chart") { return .growth }
        if has("storefront") || has("briefcase") || has("bag") || has("cart") { return placeKind("projects", variant: projects) }
        if has("archivebox") { return .archiveBox }
        if has("scroll") { return .scroll }
        if has("books") || has("book") { return placeKind("library", variant: library) }
        if has("tree") || has("leaf") { return .familyTree }
        if has("person.badge.plus") || has("person.crop.circle.badge.plus") || has("figure") || has("person.2")
            || has("person.3") { return .pawns }
        if has("envelope") || has("bubble") || has("message") || has("phone") { return .chat }
        if has("lock") { return .safe }
        if has("checkmark.shield") || has("checkmark.seal") || has("person.badge.shield") || has("shield") { return .seal }
        if has("gearshape") || has("gear") || has("slider") || has("paintbrush") || has("key") || has("iphone")
            || has("switch") { return .toggle }
        if has("bell") { return .bell }
        if has("hourglass") || has("clock") { return .clock }
        return nil
    }

    /// حدود المجسّم (مع ظلّه) داخل مربّع التصميم (١٠٠) — تُحسب من الهيئة نفسها
    static func bounds(_ kind: FT5SKind) -> CGRect {
        FT5SObjects.parts(kind, FT5SInk(dark: false)).bounds
    }

    /// يرسم المجسّم في مكانه. الإحداثيات بالعربية (المجسّم يساراً) وتُعكس للإنجليزية.
    static func draw(_ kind: FT5SKind, in ctx: inout GraphicsContext, size: CGSize, slot: FT5SSlot,
                     dark: Bool, onLight: Bool = false, longTitle: Bool = false) {
        guard size.width > 1, size.height > 1 else { return }
        var c = ctx
        let ltr = ctx.environment.layoutDirection == .leftToRight
        let flip = ltr && slot != .center
        if flip {
            c.translateBy(x: size.width, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        let box = placement(kind, size: size, slot: slot, ltr: ltr, longTitle: longTitle)
        c.translateBy(x: box.minX, y: box.minY)
        c.scaleBy(x: box.width / 100, y: box.width / 100)
        drawObject(kind, in: &c, ink: FT5SInk(dark: dark, onLight: onLight), mirrored: flip)
    }

    /// يرسم المجسّم في مربّع تصميم ١٠٠×١٠٠ (السياق محوَّل مسبقاً): ظلّ التلامس ثم المجسّم.
    /// mirrored = السياق معكوس للإنجليزية؛ المجسّمات الثابتة الاتجاه تُعاد حول منتصفها.
    static func drawObject(_ kind: FT5SKind, in c: inout GraphicsContext, ink: FT5SInk, mirrored: Bool = false) {
        let parts = FT5SObjects.parts(kind, ink)
        var g = c
        if mirrored && kind.keepsOrientation {
            let mid = parts.bounds.midX
            g.translateBy(x: 2 * mid, y: 0)
            g.scaleBy(x: -1, y: 1)
        }
        if let r = parts.contact { FT5SGloss.contact(g, r, opacity: ink.contactOpacity) }
        parts.body(&g)
    }

    /// يضع حدود المجسّم داخل منطقة: بأكبر مقياس ممكن، مستقرّاً على أسفلها (أو في وسطها)
    static func fit(_ kind: FT5SKind, in r: CGRect, maxSide: CGFloat = .infinity, bottom: Bool = true) -> CGRect {
        let b = bounds(kind)
        let s = max(0.01, min(r.width / b.width, r.height / b.height, maxSide / 100))
        let x = r.midX - b.midX * s
        let y = bottom ? r.maxY - b.maxY * s : r.midY - b.midY * s
        return CGRect(x: x, y: y, width: 100 * s, height: 100 * s)
    }

    /// مربّع التصميم (١٠٠ وحدة) داخل المكان — بإحداثيات العربية (المجسّم في الجهة اليسرى).
    static func placement(_ kind: FT5SKind, size: CGSize, slot: FT5SSlot, ltr: Bool = false, longTitle: Bool = false) -> CGRect {
        let w = size.width, h = size.height
        let wide = w / h >= 1.5
        switch slot {
        case .center:
            let side = min(w, h)
            return CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
        case .header:
            // خارج الوسط ٥٥٪: داخل أول ٢٢٫٥٪ من الطرف، وبارتفاع ٦٠٪ فقط — هادئ وحوله فراغ
            let maxX = min(w * 0.225, 108) - 4
            let r = CGRect(x: 12, y: h * 0.20, width: max(20, maxX - 12), height: h * 0.60)
            return fit(kind, in: r, bottom: false)
        case .tile, .tileBadge:
            if wide {
                if ltr && kind == .familyTree {
                    // العنوان الإنجليزي سطران طويلان: الشجرة أصغر وأعلى
                    return fit(kind, in: CGRect(x: 10, y: 7, width: w * 0.38, height: 48))
                }
                let side = slot == .tileBadge ? min(h * 0.62, w * 0.36) : min(h * 0.76, w * 0.42)
                return fit(kind, in: CGRect(x: 9, y: h - side - 6, width: side, height: side))
            }
            // الضيّق: فوق العنوان وبعيداً عن الأيقونة الزجاجية (تبدأ عند w − ٤٥) بفراغ ≥ ٦ نقاط
            let titleTop: CGFloat = longTitle && ltr ? 50 : 66
            let iconEdge = w - 45 - 6
            if slot == .tile {
                return fit(kind, in: CGRect(x: 9, y: 8, width: iconEdge - 11, height: titleTop - 14))
            }
            // مع كبسولة العدد (حتى رقمين: تنتهي عند ≈ ٣٨): أكبر الخيارين — بين الكبسولة والأيقونة، أو تحت الكبسولة
            let a = fit(kind, in: CGRect(x: 43, y: 8, width: iconEdge - 45, height: titleTop - 14))
            let bTop: CGFloat = 33
            let b = fit(kind, in: CGRect(x: 9, y: bTop, width: iconEdge - 11, height: max(10, titleTop - bTop - 6)))
            return a.width >= b.width ? a : b
        }
    }
}

// MARK: - الألوان: درجات مشتقّة من لون كل قسم (فاتح ← عميق) + الذهبي والرملي والورق والرمادي

nonisolated struct FT5SHue {
    /// خمس درجات من الأفتح إلى الأعمق (تدرّج HSL بنفس صبغة القسم)
    let t: [UInt32]

    static let tree = FT5SHue(t: [0xECFBF6, 0xC9EEE1, 0x9AD6C2, 0x64B99D, 0x429A7C])      // #1E5950
    static let diwan = FT5SHue(t: [0xECF8FB, 0xC9E6EE, 0x9AC9D6, 0x64A7B9, 0x42879A])     // #1E5665
    static let library = FT5SHue(t: [0xF7ECFB, 0xE5C9EE, 0xC79AD6, 0xA564B9, 0x85429A])   // #633C6F
    static let projects = FT5SHue(t: [0xECFBF0, 0xC9EED3, 0x9AD6AA, 0x64B97B, 0x429A59])  // #275B35
    static let contact = FT5SHue(t: [0xEDECFB, 0xC9C9EE, 0x9B9AD6, 0x6664B9, 0x43429A])   // #47467F
    static let news = FT5SHue(t: [0xECF6FB, 0xC9E1EE, 0x9AC1D6, 0x649DB9, 0x427C9A])      // #25566F
    static let home = FT5SHue(t: [0xECF4FB, 0xC9DCEE, 0x9AB9D6, 0x6491B9, 0x42709A])      // #1F4E79
    static let profile = FT5SHue(t: [0xECF1FB, 0xC9D5EE, 0x9AADD6, 0x647FB9, 0x425E9A])   // #334C81
    /// اللمسة الدافئة الوحيدة
    static let gold = FT5SHue(t: [0xFFF6DA, 0xFBE3A0, 0xF2C65E, 0xD9A23E, 0xB5832A])
    static let sand = FT5SHue(t: [0xFFF8EC, 0xF6E6C8, 0xE6CC9E, 0xCCA86F, 0xA98552])
    static let paper = FT5SHue(t: [0xFFFFFF, 0xF4F2EE, 0xE2DED6, 0xC8C1B5, 0xA79F91])
    /// الوفاة فقط — رمادي حجري بلا ذهبي
    static let grey = FT5SHue(t: [0xF4F4F6, 0xDCDCE0, 0xBDBDC3, 0x9C9CA3, 0x7C7C83])
}

/// درجات مجسّم واحد: hi (الوجه المضاء) · mid · lo (الظلّ) · deep (السُّمك) · rim (ارتداد الضوء على الحافة البعيدة)
nonisolated struct FT5SRamp {
    let hi: Color
    let mid: Color
    let lo: Color
    let deep: Color
    let rim: Color

    init(_ h: FT5SHue, start: Int, dim: Double) {
        let s = max(0, min(2, start)), t = h.t
        hi = FT5SHex.color(t[s], dim: dim)
        mid = FT5SHex.color(t[s + 1], dim: dim)
        lo = FT5SHex.color(t[min(4, s + 2)], dim: dim)
        deep = FT5SHex.color(t[min(4, s + 3)], dim: dim)
        rim = FT5SHex.color(FT5SHex.mix(t[min(4, s + 2)], t[s + 1], 0.45), dim: dim)
    }
}

nonisolated struct FT5SInk {
    let dark: Bool
    /// على سطح فاتح (صفحة فاضية، بطاقة) بدل المربّع الملوّن — الدرجات تنزل خطوة وظلّ أخفّ
    var onLight: Bool = false
    /// تخفيف بسيط في الداكن حتى لا يتوهّج المجسّم
    var dim: Double { dark ? 0.92 : 1 }
    func ramp(_ h: FT5SHue, shift: Int = 0) -> FT5SRamp {
        FT5SRamp(h, start: (onLight && !dark ? 1 : 0) + shift, dim: dim)
    }
    func color(_ v: UInt32, _ a: Double = 1) -> Color { FT5SHex.color(v, dim: dim, alpha: a) }
    /// قوّة ظلّ التلامس
    var contactOpacity: Double { onLight ? (dark ? 0.55 : 0.16) : (dark ? 0.46 : 0.30) }
}

nonisolated enum FT5SHex {
    static func color(_ v: UInt32, dim: Double = 1, alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255 * dim,
              green: Double((v >> 8) & 0xFF) / 255 * dim,
              blue: Double(v & 0xFF) / 255 * dim,
              opacity: alpha)
    }

    /// مزج لونين سداسيين (f = نصيب الثاني)
    static func mix(_ a: UInt32, _ b: UInt32, _ f: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, (ch(a, s) * (1 - f) + ch(b, s) * f).rounded()))) }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }
}

// MARK: - أدوات «صقيل» (كلها تعبئات مباشرة بلا ضبابية)

/// مجسّم جاهز: هيئته (للقياس) + ظلّ التلامس + رسمه
nonisolated struct FT5SParts {
    /// الهيئة بموضعها النهائي (مع السُّمك) — لحساب الحدود فقط
    var outline: [Path]
    /// ظلّ التلامس الواحد تحت المجسّم (بوحدات التصميم) — nil = بلا ظلّ
    var contact: CGRect?
    var body: (inout GraphicsContext) -> Void

    var bounds: CGRect {
        var r = outline.reduce(CGRect.null) { $0.union($1.boundingRect) }
        if let contact { r = r.union(contact) }
        return r.isNull || r.width < 1 || r.height < 1 ? CGRect(x: 0, y: 0, width: 100, height: 100) : r
    }
}

nonisolated enum FT5SGloss {
    /// حجم مستدير مصقول: تدرّج كروي من الضوء (أعلى الجهة الخارجية) إلى الظلّ، مع ارتداد خفيف على الحافة البعيدة
    static func orb(_ c: inout GraphicsContext, _ p: Path, _ t: FT5SRamp, box b0: CGRect? = nil,
                    light: UnitPoint = UnitPoint(x: 0.32, y: 0.24), reach: CGFloat = 1.0) {
        let b = b0 ?? p.boundingRect
        guard b.width > 0, b.height > 0 else { return }
        let cp = CGPoint(x: b.minX + b.width * light.x, y: b.minY + b.height * light.y)
        c.fill(p, with: .radialGradient(Gradient(stops: [
            .init(color: t.hi, location: 0),
            .init(color: t.mid, location: 0.4),
            .init(color: t.lo, location: 0.8),
            .init(color: t.rim, location: 1)
        ]), center: cp, startRadius: 0, endRadius: max(b.width, b.height) * reach))
    }

    /// أسطوانة مصقولة: شريط ضوء قرب الجهة المضاءة ثم ظلّ ثم ارتداد (أفقي، أو رأسي للأسطوانات المستلقية)
    static func barrel(_ c: inout GraphicsContext, _ p: Path, _ t: FT5SRamp, box b0: CGRect? = nil, vertical: Bool = false) {
        let b = b0 ?? p.boundingRect
        guard b.width > 0, b.height > 0 else { return }
        let g = Gradient(stops: [
            .init(color: t.mid, location: 0),
            .init(color: t.hi, location: 0.24),
            .init(color: t.mid, location: 0.52),
            .init(color: t.lo, location: 0.86),
            .init(color: t.rim, location: 1)
        ])
        let s = vertical ? CGPoint(x: b.midX, y: b.minY) : CGPoint(x: b.minX, y: b.midY)
        let e = vertical ? CGPoint(x: b.midX, y: b.maxY) : CGPoint(x: b.maxX, y: b.midY)
        c.fill(p, with: .linearGradient(g, startPoint: s, endPoint: e))
    }

    /// وجه مسطّح مضاء من الأعلى
    static func face(_ c: inout GraphicsContext, _ p: Path, _ t: FT5SRamp, box b0: CGRect? = nil) {
        let b = b0 ?? p.boundingRect
        guard b.width > 0, b.height > 0 else { return }
        c.fill(p, with: .linearGradient(Gradient(stops: [
            .init(color: t.hi, location: 0),
            .init(color: t.mid, location: 0.72),
            .init(color: t.rim, location: 1)
        ]), startPoint: CGPoint(x: b.minX + b.width * 0.3, y: b.minY),
           endPoint: CGPoint(x: b.minX + b.width * 0.55, y: b.maxY)))
    }

    /// السُّمك (الجانب المظلّل)
    static func depth(_ c: inout GraphicsContext, _ p: Path, _ t: FT5SRamp, box b0: CGRect? = nil) {
        let b = b0 ?? p.boundingRect
        guard b.width > 0, b.height > 0 else { return }
        c.fill(p, with: .linearGradient(Gradient(colors: [t.lo, t.deep]),
                                        startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
    }

    /// لوح بسُمك: نسخة أغمق مزاحة للأسفل ثم الوجه فوقها — عمليتان
    static func slab(_ c: inout GraphicsContext, _ p: Path, _ t: FT5SRamp, d: CGFloat) {
        let b = p.boundingRect
        depth(&c, p.offsetBy(dx: 0, dy: d), t, box: b.offsetBy(dx: 0, dy: d))
        face(&c, p, t, box: b)
    }

    /// وجه بلون أي `Color` (لون القسم/النوع): اللون + ضوء أبيض من الأعلى — عمليتان
    static func tintFace(_ c: inout GraphicsContext, _ p: Path, _ tint: Color) {
        let b = p.boundingRect
        c.fill(p, with: .color(tint))
        c.fill(p, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.34), location: 0),
            .init(color: .white.opacity(0.07), location: 0.6),
            .init(color: .white.opacity(0), location: 1)
        ]), startPoint: CGPoint(x: b.minX + b.width * 0.25, y: b.minY),
           endPoint: CGPoint(x: b.minX + b.width * 0.55, y: b.maxY)))
    }

    /// لوح بلون أي `Color`: سُمك أغمق + وجه مضاء — أربع عمليات
    static func tintSlab(_ c: inout GraphicsContext, _ p: Path, _ tint: Color, d: CGFloat, dark: Bool) {
        let back = p.offsetBy(dx: 0, dy: d)
        c.fill(back, with: .color(tint))
        c.fill(back, with: .color(.black.opacity(dark ? 0.34 : 0.26)))
        tintFace(&c, p, tint)
    }

    /// اللمعة الواحدة الحادّة: شكل بحافة صلبة وتدرّج أبيض، مقصوص داخل الحجم
    static func glint(_ c: GraphicsContext, _ s: Path, clip: Path? = nil, opacity: Double = 0.92) {
        var l = c
        if let clip { l.clip(to: clip) }
        let b = s.boundingRect
        l.fill(s, with: .linearGradient(Gradient(colors: [.white.opacity(opacity), .white.opacity(opacity * 0.35)]),
                                        startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
    }

    /// بيضاوي بتلاشٍ ناعم من مركزه (تدرّج على سياق مضغوط رأسياً — بلا ضبابية)
    static func soft(_ c: GraphicsContext, _ r: CGRect, _ color: Color, _ opacity: Double) {
        guard r.width > 0, r.height > 0, opacity > 0 else { return }
        var l = c
        l.translateBy(x: r.midX, y: r.midY)
        l.scaleBy(x: 1, y: r.height / r.width)
        let rad = r.width / 2
        l.fill(Path(ellipseIn: CGRect(x: -rad, y: -rad, width: 2 * rad, height: 2 * rad)),
               with: .radialGradient(Gradient(stops: [
                .init(color: color.opacity(opacity), location: 0),
                .init(color: color.opacity(opacity * 0.62), location: 0.38),
                .init(color: color.opacity(0), location: 1)
               ]), center: .zero, startRadius: 0, endRadius: rad))
    }

    /// ظلّ التلامس الواحد (إطباق محيطي: قلب أغمق وحافة ناعمة)
    static func contact(_ c: GraphicsContext, _ r: CGRect, opacity: Double) {
        soft(c, r, .black, opacity)
    }

    /// مضلّع بزوايا مدوّرة (نصف قطر لكل رأس) — محيط واحد متّصل
    static func poly(_ pts: [CGPoint], _ radii: [CGFloat]) -> Path {
        var p = Path()
        let n = pts.count
        guard n > 2 else { return p }
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for i in 0..<n {
            let cur = pts[i], next = pts[(i + 1) % n]
            let r = radii[min(i, radii.count - 1)]
            if r > 0 { p.addArc(tangent1End: cur, tangent2End: next, radius: r) } else { p.addLine(to: cur) }
        }
        p.closeSubpath()
        return p
    }

    /// هلال كمحيط واحد (iOS 16: بلا عمليات الأشكال): قوس الدائرة الخارجية من قرن إلى قرن عبر الجهة البعيدة،
    /// ثم قوس الدائرة الداخلية رجوعاً عبر الجهة المقابلة لمركز الخارجية.
    static func crescent(outer c1: CGPoint, _ r1: CGFloat, inner c2: CGPoint, _ r2: CGFloat, steps: Int = 36) -> Path {
        let dx = Double(c2.x - c1.x), dy = Double(c2.y - c1.y)
        let d = max(0.001, (dx * dx + dy * dy).squareRoot())
        let R1 = Double(r1), R2 = Double(r2)
        let phi = atan2(dy, dx)
        let a = (R1 * R1 - R2 * R2 + d * d) / (2 * d)
        let alpha = acos(max(-1, min(1, a / R1)))
        var p = Path()
        for i in 0...steps {
            let t = phi + alpha + (2 * Double.pi - 2 * alpha) * Double(i) / Double(steps)
            let pt = CGPoint(x: Double(c1.x) + R1 * cos(t), y: Double(c1.y) + R1 * sin(t))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        let hornB = CGPoint(x: Double(c1.x) + R1 * cos(phi - alpha), y: Double(c1.y) + R1 * sin(phi - alpha))
        let hornA = CGPoint(x: Double(c1.x) + R1 * cos(phi + alpha), y: Double(c1.y) + R1 * sin(phi + alpha))
        let sb = atan2(Double(hornB.y - c2.y), Double(hornB.x - c2.x))
        let sa = atan2(Double(hornA.y - c2.y), Double(hornA.x - c2.x))
        var sweep = sa - sb
        while sweep <= 0 { sweep += 2 * Double.pi }
        var rel = (phi + Double.pi) - sb
        while rel < 0 { rel += 2 * Double.pi }
        while rel >= 2 * Double.pi { rel -= 2 * Double.pi }
        if rel > sweep { sweep -= 2 * Double.pi }
        for i in 1...steps {
            let t = sb + sweep * Double(i) / Double(steps)
            p.addLine(to: CGPoint(x: Double(c2.x) + R2 * cos(t), y: Double(c2.y) + R2 * sin(t)))
        }
        p.closeSubpath()
        return p
    }
}

/// مقطع لمسار متناظر (الجهة اليمنى فقط — اليسرى تُعكس تلقائياً)
nonisolated enum FT5SSeg {
    case line(CGPoint)
    case quad(CGPoint, CGPoint)
    case curve(CGPoint, CGPoint, CGPoint)

    var end: CGPoint {
        switch self {
        case .line(let p), .quad(let p, _), .curve(let p, _, _): return p
        }
    }
}

// MARK: - المجسّمات (مربّع تصميم ١٠٠×١٠٠، القاعدة عند y ≈ ٩٠)

nonisolated enum FT5SObjects {
    static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    static func E(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
    }
    static func rot(_ deg: Double, about p: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: p.x, y: p.y).rotated(by: CGFloat(deg * .pi / 180)).translatedBy(x: -p.x, y: -p.y)
    }
    /// بيضاوي مائل حول مركزه (للّمعات)
    static func tilted(_ e: CGRect, _ deg: Double) -> Path {
        Path(ellipseIn: e).applying(rot(deg, about: CGPoint(x: e.midX, y: e.midY)))
    }
    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    /// هيئة متناظرة حول x = cx: تُرسم الجهة اليمنى من `start` وتُعكس اليسرى — هيئة واحدة نظيفة
    static func lathe(_ cx: CGFloat, _ start: CGPoint, _ segs: [FT5SSeg]) -> Path {
        func m(_ q: CGPoint) -> CGPoint { CGPoint(x: 2 * cx - q.x, y: q.y) }
        var p = Path()
        p.move(to: start)
        var pts = [start]
        for s in segs {
            switch s {
            case .line(let t): p.addLine(to: t)
            case .quad(let t, let c): p.addQuadCurve(to: t, control: c)
            case .curve(let t, let a, let b): p.addCurve(to: t, control1: a, control2: b)
            }
            pts.append(s.end)
        }
        if let last = pts.last, abs(last.x - cx) > 0.01 { p.addLine(to: m(last)) }
        for i in stride(from: segs.count - 1, through: 0, by: -1) {
            let to = m(pts[i])
            switch segs[i] {
            case .line: p.addLine(to: to)
            case .quad(_, let c): p.addQuadCurve(to: to, control: m(c))
            case .curve(_, let a, let b): p.addCurve(to: to, control1: m(b), control2: m(a))
            }
        }
        p.closeSubpath()
        return p
    }

    static func star(_ c: CGPoint, outer: CGFloat, inner: CGFloat, points: Int = 5, rotation: Double = -90) -> Path {
        var pts: [CGPoint] = []
        for i in 0..<(points * 2) {
            let a = (rotation + Double(i) * 180 / Double(points)) * .pi / 180
            let r = i % 2 == 0 ? outer : inner
            pts.append(CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
        }
        return FT5SGloss.poly(pts, [0.8])
    }

    /// فقاعة حوار: مستطيل بزوايا ناعمة وذيل في حافته السفلية بين a و b — محيط واحد متّصل (بلا تداخل)
    static func bubble(_ r: CGRect, radius q: CGFloat, a: CGFloat, b: CGFloat, tip: CGPoint, c1: CGPoint, c2: CGPoint) -> Path {
        var p = Path()
        p.move(to: P(r.minX + q, r.minY))
        p.addLine(to: P(r.maxX - q, r.minY))
        p.addQuadCurve(to: P(r.maxX, r.minY + q), control: P(r.maxX, r.minY))
        p.addLine(to: P(r.maxX, r.maxY - q))
        p.addQuadCurve(to: P(r.maxX - q, r.maxY), control: P(r.maxX, r.maxY))
        p.addLine(to: P(b, r.maxY))
        p.addQuadCurve(to: tip, control: c1)
        p.addQuadCurve(to: P(a, r.maxY), control: c2)
        p.addLine(to: P(r.minX + q, r.maxY))
        p.addQuadCurve(to: P(r.minX, r.maxY - q), control: P(r.minX, r.maxY))
        p.addLine(to: P(r.minX, r.minY + q))
        p.addQuadCurve(to: P(r.minX + q, r.minY), control: P(r.minX, r.minY))
        p.closeSubpath()
        return p
    }

    /// بيدق (فرد): قاعدة متّسعة وعنق — والرأس كرة منفصلة فوقه
    static func pawnBody(_ cx: CGFloat, _ s: CGFloat, base: CGFloat = 90) -> Path {
        lathe(cx, P(cx, base), [
            .line(P(cx + 18 * s, base)),
            .quad(P(cx + 19.6 * s, base - 3.6 * s), P(cx + 20.2 * s, base)),
            .curve(P(cx + 7 * s, base - 26 * s), P(cx + 18 * s, base - 13 * s), P(cx + 8 * s, base - 18 * s)),
            .quad(P(cx, base - 30 * s), P(cx + 6.6 * s, base - 30 * s))
        ])
    }

    static func parts(_ kind: FT5SKind, _ k: FT5SInk) -> FT5SParts {
        switch kind {
        case .familyTree: return familyTree(k)
        case .mabkhara: return mabkhara(k)
        case .chat: return chat(k)
        case .openBook: return openBook(k)
        case .scroll: return scroll(k)
        case .archiveBox: return archiveBox(k)
        case .storefront: return storefront(k)
        case .growth: return growth(k)
        case .rocket: return rocket(k)
        case .newspaper: return newspaper(k)
        case .megaphone: return megaphone(k)
        case .pawns: return pawns(k)
        case .safe: return safe(k)
        case .seal: return seal(k)
        case .toggle: return toggle(k)
        case .crescent: return crescent(k)
        case .bell: return bell(k)
        case .clock: return clock(k)
        }
    }
}

// MARK: - مربّعات الرئيسية: شجرة العائلة، المبخرة، فقاعتا الحوار

nonisolated extension FT5SObjects {

    /// شجرة العائلة: تاج مستدير واحد على جذع قصير، وعليه ثمار ذهبية = أفراد العائلة (جدّ ← ابنان ← أحفاد)
    /// موصولة بخيوط ذهبية رفيعة — ٧ عمليات
    static func familyTree(_ k: FT5SInk) -> FT5SParts {
        let leaf = k.ramp(.tree, shift: 1), bark = k.ramp(.sand), gold = k.ramp(.gold, shift: 1)
        let trunk: Path = {
            var p = Path()
            p.move(to: P(42, 90))
            p.addQuadCurve(to: P(45.8, 80), control: P(45.6, 87.6))
            p.addLine(to: P(46.4, 60))
            p.addLine(to: P(53.6, 60))
            p.addLine(to: P(54.2, 80))
            p.addQuadCurve(to: P(58, 90), control: P(54.4, 87.6))
            p.addQuadCurve(to: P(42, 90), control: P(50, 91.4))
            p.closeSubpath()
            return p
        }()
        let crown: Path = {
            var p = Path()
            p.addEllipse(in: E(50, 37, 29, 26.5))
            p.addEllipse(in: E(31, 51, 18, 15))
            p.addEllipse(in: E(69, 51, 18, 15))
            return p
        }()
        let nodes: [(CGPoint, CGFloat)] = [
            (P(50, 24), 5.4), (P(36.5, 39.5), 4.6), (P(63.5, 39.5), 4.6),
            (P(27.5, 54), 4), (P(45, 55.5), 4), (P(72.5, 54), 4)
        ]
        var wires = Path()
        for (a, b) in [(0, 1), (0, 2), (1, 3), (1, 4), (2, 5)] {
            wires.move(to: nodes[a].0)
            wires.addLine(to: nodes[b].0)
        }
        let links = wires.strokedPath(StrokeStyle(lineWidth: 2.2, lineCap: .round))
        var fruit = Path(), shine = Path()
        for (p, r) in nodes {
            fruit.addEllipse(in: E(p.x, p.y, r, r))
            shine.addEllipse(in: E(p.x - r * 0.34, p.y - r * 0.38, r * 0.36, r * 0.26))
        }
        let goldFill = GraphicsContext.Shading.linearGradient(Gradient(colors: [gold.mid, gold.lo]),
                                                              startPoint: P(40, 18), endPoint: P(60, 60))
        return FT5SParts(outline: [crown, trunk], contact: E(50, 90.8, 25, 3)) { c in
            FT5SGloss.barrel(&c, trunk, bark, box: CGRect(x: 42, y: 60, width: 16, height: 31))
            FT5SGloss.orb(&c, crown, leaf, box: CGRect(x: 13, y: 10.5, width: 74, height: 55.5), light: UnitPoint(x: 0.3, y: 0.16))
            FT5SGloss.glint(c, tilted(E(31.5, 26, 8.5, 3.8), -36), clip: crown)
            c.fill(links, with: goldFill)
            c.fill(fruit, with: goldFill)
            c.fill(shine, with: .color(.white.opacity(0.9)))
        }
    }

    /// المبخرة (الديوانيات): قاعدة مربّعة متدرّجة وساق قصيرة وكأس متّسعة بلون القسم، حافة ذهبية ومسماران
    /// ذهبيان، ودخان بخور رفيع يتلاشى — ٧ عمليات
    static func mabkhara(_ k: FT5SInk) -> FT5SParts {
        let teal = k.ramp(.diwan), gold = k.ramp(.gold, shift: 1)
        let body = lathe(50, P(50, 90), [
            .line(P(68, 90)),
            .quad(P(71, 87), P(71, 90)),
            .line(P(71, 81)),
            .quad(P(68, 78), P(71, 78)),
            .line(P(65.5, 78)),
            .line(P(65.5, 76)),
            .quad(P(63, 73.5), P(65.5, 73.5)),
            .line(P(59.5, 73.5)),
            .curve(P(58.5, 63.5), P(58, 70), P(58, 66.5)),
            .line(P(72.5, 50)),
            .quad(P(74, 48), P(74, 49.5))
        ])
        let rim = rr(23.5, 43.5, 53, 6, 3)
        let mouth = Path(ellipseIn: E(50, 44.4, 21, 2.5))
        var studs = FT5SGloss.poly([P(50, 52.5), P(54, 57), P(50, 61.5), P(46, 57)], [0.8])
        studs.addPath(FT5SGloss.poly([P(50, 80.5), P(53.5, 84), P(50, 87.5), P(46.5, 84)], [0.8]))
        let smoke: Path = {
            var s = Path()
            s.move(to: P(50, 41))
            s.addCurve(to: P(47, 29.5), control1: P(54.5, 37), control2: P(42.5, 34))
            s.addCurve(to: P(52, 18), control1: P(51, 25), control2: P(55.5, 22))
            return s.strokedPath(StrokeStyle(lineWidth: 3.6, lineCap: .round))
        }()
        let wisp: Color = k.onLight && !k.dark ? FT5SHex.color(0x9AC9D6) : .white
        return FT5SParts(outline: [body, rim, smoke], contact: E(50, 91, 26, 3)) { c in
            FT5SGloss.barrel(&c, body, teal, box: CGRect(x: 26, y: 48, width: 48, height: 42))
            c.fill(studs, with: .linearGradient(Gradient(colors: [gold.hi, gold.lo]), startPoint: P(46, 52), endPoint: P(54, 88)))
            FT5SGloss.barrel(&c, rim, gold)
            c.fill(mouth, with: .linearGradient(Gradient(colors: [teal.deep, teal.lo]), startPoint: P(50, 42), endPoint: P(50, 47)))
            FT5SGloss.glint(c, rr(31.5, 51.5, 3.6, 9, 1.8).applying(rot(-28, about: P(33.3, 56))), clip: body)
            c.fill(smoke, with: .linearGradient(Gradient(colors: [wisp.opacity(0.9), wisp.opacity(0)]),
                                                startPoint: P(50, 42), endPoint: P(52, 16)))
        }
    }

    /// التواصل: فقاعتا حوار بسُمك — كبيرة بلون القسم وفيها ثلاث نقاط، وخلفها صغيرة ذهبية — ٧ عمليات
    static func chat(_ k: FT5SInk) -> FT5SParts {
        let ink = k.ramp(.contact), gold = k.ramp(.gold)
        let back = bubble(CGRect(x: 40, y: 14, width: 48, height: 34), radius: 14, a: 60, b: 72,
                          tip: P(84, 59), c1: P(76, 55), c2: P(67, 53))
        let front = bubble(CGRect(x: 12, y: 34, width: 60, height: 40), radius: 16, a: 28, b: 42,
                           tip: P(16, 87), c1: P(33, 82), c2: P(26, 78))
        var dots = Path()
        for x in [29, 42, 55] as [CGFloat] { dots.addEllipse(in: E(x, 54, 4.2, 4.2)) }
        let d: CGFloat = 4.5
        return FT5SParts(outline: [back, back.offsetBy(dx: 0, dy: 3.5), front, front.offsetBy(dx: 0, dy: d)],
                         contact: E(44, 92.5, 30, 2.8)) { c in
            FT5SGloss.slab(&c, back, gold, d: 3.5)
            FT5SGloss.slab(&c, front, ink, d: d)
            c.fill(dots, with: .color(ink.deep))
            FT5SGloss.glint(c, tilted(E(27, 40.2, 9, 2.4), -6), clip: front)
        }
    }
}

// MARK: - المكتبة: ثلاثة أشكال

nonisolated extension FT5SObjects {

    /// ٠ — كتاب مفتوح: صفحتان بيضاوان بطيّة في الوسط على غلاف بلون المكتبة، أسطر هادئة وشريط علامة ذهبي — ٦ عمليات
    static func openBook(_ k: FT5SInk) -> FT5SParts {
        let lilac = k.ramp(.library), paper = k.ramp(.paper), gold = k.ramp(.gold, shift: 1)
        let pages = lathe(50, P(50, 39), [
            .curve(P(86, 32), P(61, 31.5), P(75, 29)),
            .line(P(87.5, 73)),
            .curve(P(50, 79), P(75, 70), P(60, 72))
        ])
        let widen = CGAffineTransform(translationX: 50, y: 0).scaledBy(x: 1.08, y: 1).translatedBy(x: -50, y: 0)
        let cover = pages.applying(widen).offsetBy(dx: 0, dy: 5.5)
        var lines = Path()
        for (y, w) in [(45, 22), (53, 22), (61, 15)] as [(CGFloat, CGFloat)] {
            lines.move(to: P(44, y + 2.2)); lines.addLine(to: P(44 - w, y))
            lines.move(to: P(56, y + 2.2)); lines.addLine(to: P(56 + w, y))
        }
        let text = lines.strokedPath(StrokeStyle(lineWidth: 2.6, lineCap: .round))
        let ribbon = FT5SGloss.poly([P(51.6, 74), P(57, 74), P(57, 93), P(54.3, 89.8), P(51.6, 93)], [0.6, 0.6, 0.5, 0.3, 0.5])
        return FT5SParts(outline: [pages, cover, ribbon], contact: E(50, 92, 37, 3)) { c in
            FT5SGloss.depth(&c, cover, lilac)
            c.fill(pages, with: .linearGradient(Gradient(stops: [
                .init(color: paper.mid, location: 0), .init(color: paper.hi, location: 0.28),
                .init(color: paper.lo, location: 0.5), .init(color: paper.hi, location: 0.6),
                .init(color: paper.mid, location: 0.86), .init(color: paper.lo, location: 1)
            ]), startPoint: P(12.5, 50), endPoint: P(87.5, 50)))
            c.fill(text, with: .color(lilac.lo))
            FT5SGloss.face(&c, ribbon, gold)
            FT5SGloss.glint(c, tilted(E(27, 36.4, 10, 1.9), -9), clip: pages)
        }
    }

    /// ١ — مخطوطة: رقّ رملي بين لفافتين بلون المكتبة بأطراف ذهبية، وأسطر قليلة (من اليمين) — ٧ عمليات
    static func scroll(_ k: FT5SInk) -> FT5SParts {
        let lilac = k.ramp(.library), parchment = k.ramp(.sand), gold = k.ramp(.gold, shift: 1)
        let t = rot(-7, about: P(50, 51))
        let sheet = Path(CGRect(x: 27, y: 21, width: 46, height: 60))
        let top = rr(21, 14, 58, 11, 5.5)
        let bottom = rr(21, 76, 58, 11, 5.5)
        var knobs = Path()
        for (x, y) in [(18, 19.5), (82, 19.5), (18, 81.5), (82, 81.5)] as [(CGFloat, CGFloat)] {
            knobs.addEllipse(in: E(x, y, 3.6, 4.4))
        }
        var lines = Path()
        for (y, x0) in [(36, 33), (44, 38), (52, 33), (60, 42), (68, 36)] as [(CGFloat, CGFloat)] {
            lines.move(to: P(x0, y)); lines.addLine(to: P(67, y))
        }
        let text = lines.strokedPath(StrokeStyle(lineWidth: 2.6, lineCap: .round))
        return FT5SParts(outline: [top, bottom, knobs, sheet].map { $0.applying(t) }, contact: E(50, 92.5, 31, 2.8)) { c in
            var s = c
            s.concatenate(t)
            FT5SGloss.face(&s, sheet, parchment)
            s.fill(text, with: .color(lilac.lo))
            FT5SGloss.barrel(&s, top, lilac, vertical: true)
            FT5SGloss.barrel(&s, bottom, lilac, vertical: true)
            s.fill(knobs, with: .linearGradient(Gradient(colors: [gold.hi, gold.lo]), startPoint: P(50, 15), endPoint: P(50, 86)))
            FT5SGloss.glint(s, rr(25, 15.8, 26, 2.4, 1.2), clip: top)
        }
    }

    /// ٢ — صندوق أرشيف: صندوق بلون المكتبة يُرى وجهه وسطحه وجانبه، بفاصل غطاء ومقبض وبطاقة بيضاء — ٦ عمليات
    static func archiveBox(_ k: FT5SInk) -> FT5SParts {
        let lilac = k.ramp(.library), paper = k.ramp(.paper)
        let f = CGRect(x: 15, y: 46, width: 58, height: 42)
        let o = CGPoint(x: 11, y: -9)
        let hull = FT5SGloss.poly([P(f.minX, f.minY), P(f.minX + o.x, f.minY + o.y), P(f.maxX + o.x, f.minY + o.y),
                                   P(f.maxX + o.x, f.maxY + o.y), P(f.maxX, f.maxY), P(f.minX, f.maxY)], [3])
        let front = FT5SGloss.poly([P(f.minX, f.minY), P(f.maxX, f.minY), P(f.maxX, f.maxY), P(f.minX, f.maxY)], [3.4])
        var marks = Path()
        marks.addRoundedRect(in: CGRect(x: f.minX, y: f.minY + 12.5, width: f.width, height: 1.8),
                             cornerSize: CGSize(width: 0.9, height: 0.9))
        marks.addRoundedRect(in: CGRect(x: 34, y: 51.5, width: 20, height: 5.2), cornerSize: CGSize(width: 2.6, height: 2.6))
        let label = rr(32, 67, 24, 13, 2.6)
        return FT5SParts(outline: [hull], contact: E(47, 90.8, 35, 3)) { c in
            c.fill(hull, with: .linearGradient(Gradient(stops: [
                .init(color: lilac.hi, location: 0), .init(color: lilac.mid, location: 0.35), .init(color: lilac.deep, location: 1)
            ]), startPoint: P(20, 37), endPoint: P(84, 79)))
            c.fill(front, with: .linearGradient(Gradient(colors: [lilac.mid, lilac.lo]), startPoint: P(30, 46), endPoint: P(50, 88)))
            c.fill(marks, with: .color(lilac.deep))
            FT5SGloss.face(&c, label, paper)
            FT5SGloss.glint(c, FT5SGloss.poly([P(22, 45), P(29, 39.6), P(44, 39.6), P(37, 45)], [0.8]), clip: hull)
        }
    }
}

// MARK: - المشاريع: ثلاثة أشكال

nonisolated extension FT5SObjects {

    /// ٠ — واجهة محلّ: مبنى بلون المشاريع بسُمك، مظلّة مخطّطة (أبيض/ذهبي) بحافة مموّجة، نافذة وباب — ٧ عمليات
    static func storefront(_ k: FT5SInk) -> FT5SParts {
        let green = k.ramp(.projects), paper = k.ramp(.paper), gold = k.ramp(.gold, shift: 1)
        let body = rr(20, 42, 60, 44, 5)
        let top: CGFloat = 27, edge: CGFloat = 43, dip: CGFloat = 5.5
        let l0: CGFloat = 19, r0: CGFloat = 81, l1: CGFloat = 13, r1: CGFloat = 87
        let n = 6
        let awning: Path = {
            var p = Path()
            p.move(to: P(l0 + 2.5, top))
            p.addLine(to: P(r0 - 2.5, top))
            p.addQuadCurve(to: P(r0 + 0.8, top + 2.6), control: P(r0, top))
            p.addLine(to: P(r1, edge))
            let w = (r1 - l1) / CGFloat(n)
            for i in 0..<n {
                let x1 = r1 - CGFloat(i) * w, x0 = x1 - w
                p.addQuadCurve(to: P(x0, edge), control: P((x0 + x1) / 2, edge + dip * 2))
            }
            p.addLine(to: P(l0 - 0.8, top + 2.6))
            p.addQuadCurve(to: P(l0 + 2.5, top), control: P(l0, top))
            p.closeSubpath()
            return p
        }()
        var stripes = Path()
        for i in stride(from: 1, to: n, by: 2) {
            let a = CGFloat(i) / CGFloat(n), b = CGFloat(i + 1) / CGFloat(n)
            stripes.move(to: P(l0 + (r0 - l0) * a, top - 1))
            stripes.addLine(to: P(l0 + (r0 - l0) * b, top - 1))
            stripes.addLine(to: P(l1 + (r1 - l1) * b, edge + dip * 2))
            stripes.addLine(to: P(l1 + (r1 - l1) * a, edge + dip * 2))
            stripes.closeSubpath()
        }
        let window = CGRect(x: 27, y: 56, width: 22, height: 17)
        var openings = Path()
        openings.addRoundedRect(in: window, cornerSize: CGSize(width: 3, height: 3))
        openings.addRoundedRect(in: CGRect(x: 55, y: 57, width: 16, height: 29), cornerSize: CGSize(width: 3, height: 3))
        let d: CGFloat = 4
        return FT5SParts(outline: [awning, body.offsetBy(dx: 0, dy: d)], contact: E(50, 91.6, 35, 3)) { c in
            FT5SGloss.slab(&c, body, green, d: d)
            c.fill(openings, with: .linearGradient(Gradient(colors: [green.lo, green.deep]), startPoint: P(50, 56), endPoint: P(50, 86)))
            FT5SGloss.glint(c, FT5SGloss.poly([P(29, 73), P(37, 56), P(44, 56), P(36, 73)], [0.4]),
                            clip: Path(roundedRect: window, cornerRadius: 3), opacity: 0.6)
            FT5SGloss.face(&c, awning, paper)
            var s = c
            s.clip(to: awning)
            s.fill(stripes, with: .linearGradient(Gradient(colors: [gold.hi, gold.lo]), startPoint: P(50, top), endPoint: P(50, edge + dip)))
        }
    }

    /// ١ — سهم النموّ: ثلاثة أعمدة صاعدة بلون المشاريع (وجه + جانب) وسهم ذهبي — يبقى صاعداً يميناً — ٦ عمليات
    static func growth(_ k: FT5SInk) -> FT5SParts {
        let green = k.ramp(.projects), gold = k.ramp(.gold)
        let bars = [CGRect(x: 15, y: 64, width: 17, height: 24), CGRect(x: 37, y: 50, width: 17, height: 38),
                    CGRect(x: 59, y: 35, width: 17, height: 53)]
        let o = CGPoint(x: 5, y: -4.5)
        var sides = Path(), faces = Path(), shine = Path()
        for r in bars {
            sides.addPath(FT5SGloss.poly([P(r.minX, r.minY), P(r.minX + o.x, r.minY + o.y), P(r.maxX + o.x, r.minY + o.y),
                                          P(r.maxX + o.x, r.maxY + o.y), P(r.maxX, r.maxY), P(r.minX, r.maxY)], [1.8]))
            faces.addPath(FT5SGloss.poly([P(r.minX, r.minY), P(r.maxX, r.minY), P(r.maxX, r.maxY), P(r.minX, r.maxY)], [2.2]))
            shine.addRoundedRect(in: CGRect(x: r.minX + 2.6, y: r.minY + 3, width: 2.8, height: min(r.height - 8, 15)),
                                 cornerSize: CGSize(width: 1.4, height: 1.4))
        }
        var trend = Path()
        trend.move(to: P(13, 58)); trend.addLine(to: P(33, 44)); trend.addLine(to: P(47, 50)); trend.addLine(to: P(70, 26.5))
        let line = trend.strokedPath(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        let head = FT5SGloss.poly([P(83, 13), P(79, 32), P(63.5, 17.5)], [2.2])
        let goldFill = GraphicsContext.Shading.linearGradient(Gradient(colors: [gold.hi, gold.mid, gold.lo]),
                                                              startPoint: P(20, 20), endPoint: P(70, 62))
        return FT5SParts(outline: [sides, line, head], contact: E(48, 90, 37, 2.8)) { c in
            c.fill(sides, with: .linearGradient(Gradient(colors: [green.lo, green.deep]), startPoint: P(20, 30), endPoint: P(85, 88)))
            c.fill(faces, with: .linearGradient(Gradient(colors: [green.hi, green.mid]), startPoint: P(30, 34), endPoint: P(50, 88)))
            FT5SGloss.glint(c, shine, clip: faces, opacity: 0.85)
            c.fill(line, with: goldFill)
            c.fill(head, with: goldFill)
        }
    }

    /// ٢ — صاروخ انطلاق: جسم فاتح بلون المشاريع ونافذة بإطار ذهبي وزعانف أعمق ولهب ذهبي — ينطلق يميناً دائماً — ٧ عمليات
    static func rocket(_ k: FT5SInk) -> FT5SParts {
        let mint = k.ramp(.projects), gold = k.ramp(.gold)
        let t = rot(40, about: P(50, 52))
        let body = lathe(50, P(50, 76), [
            .line(P(59.5, 76)),
            .curve(P(63.5, 50), P(62, 69), P(63.5, 58)),
            .curve(P(50, 12), P(63.5, 33), P(57.5, 19))
        ])
        var fins = FT5SGloss.poly([P(38, 55), P(27, 70), P(28, 82), P(39.8, 75)], [1.4, 2.6, 2, 1.4])
        fins.addPath(FT5SGloss.poly([P(62, 55), P(60.2, 75), P(72, 82), P(73, 70)], [1.4, 1.4, 2, 2.6]))
        let ring = Path(ellipseIn: E(50, 43, 9.2, 9.2))
        let pane = Path(ellipseIn: E(50, 43, 6, 6))
        let flame: Path = {
            var p = Path()
            p.move(to: P(43, 76))
            p.addQuadCurve(to: P(50, 97), control: P(41.5, 89))
            p.addQuadCurve(to: P(57, 76), control: P(58.5, 89))
            p.closeSubpath()
            return p
        }()
        return FT5SParts(outline: [body, fins, flame].map { $0.applying(t) }, contact: E(46, 92.5, 22, 2.4)) { c in
            var r = c
            r.concatenate(t)
            r.fill(flame, with: .linearGradient(Gradient(colors: [.white, gold.mid, gold.lo.opacity(0)]),
                                                startPoint: P(50, 76), endPoint: P(50, 97)))
            r.fill(fins, with: .linearGradient(Gradient(colors: [mint.lo, mint.deep]), startPoint: P(30, 55), endPoint: P(70, 82)))
            FT5SGloss.barrel(&r, body, mint)
            FT5SGloss.orb(&r, ring, k.ramp(.gold, shift: 1))
            r.fill(pane, with: .radialGradient(Gradient(colors: [mint.lo, mint.deep]), center: P(47.5, 40.5), startRadius: 0, endRadius: 8))
            FT5SGloss.glint(r, rr(40.6, 48, 3.2, 17, 1.6), clip: body)
        }
    }
}

// MARK: - رؤوس المربّعات والأماكن: بقية المجسّمات

nonisolated extension FT5SObjects {

    /// الصحيفة المطويّة (الأخبار): ورقة بسُمك، عنوان أزرق، صورة ذهبية، أسطر قليلة — ٧ عمليات
    static func newspaper(_ k: FT5SInk) -> FT5SParts {
        let paper = k.ramp(.paper), blue = k.ramp(.news, shift: 1), gold = k.ramp(.gold, shift: 1)
        let t = rot(-7, about: P(50, 50))
        let sheet = rr(24, 15, 52, 67, 5)
        let mast = rr(30, 22, 40, 8.5, 2.6)
        let photo = rr(30, 36, 18, 16, 3)
        var lines = Path()
        for r in [CGRect(x: 52, y: 37, width: 18, height: 3.2), CGRect(x: 52, y: 44, width: 18, height: 3.2),
                  CGRect(x: 30, y: 58, width: 40, height: 3.2), CGRect(x: 30, y: 65, width: 40, height: 3.2),
                  CGRect(x: 30, y: 72, width: 26, height: 3.2)] {
            lines.addRoundedRect(in: r, cornerSize: CGSize(width: 1.6, height: 1.6))
        }
        let d: CGFloat = 4.5
        return FT5SParts(outline: [sheet.applying(t), sheet.offsetBy(dx: 0, dy: d).applying(t)], contact: E(51, 92, 26, 2.8)) { c in
            var s = c
            s.concatenate(t)
            FT5SGloss.slab(&s, sheet, paper, d: d)
            FT5SGloss.face(&s, mast, blue)
            FT5SGloss.face(&s, photo, gold)
            s.fill(lines, with: .color(blue.mid))
            FT5SGloss.glint(s, rr(32, 23.4, 17, 1.9, 0.95), clip: mast)
        }
    }

    /// مكبّر الصوت (إعلان): مخروط أزرق بحافة ذهبية، مقبض وطرف خلفي — يتّجه مع القراءة — ٦ عمليات
    static func megaphone(_ k: FT5SInk) -> FT5SParts {
        let blue = k.ramp(.news), gold = k.ramp(.gold)
        let t = rot(-16, about: P(50, 56))
        let cone = FT5SGloss.poly([P(71, 49), P(32, 34), P(32, 78), P(71, 63)], [4, 2, 2, 4])
        var grip = FT5SGloss.poly([P(56.5, 62), P(64.5, 60.5), P(68.5, 78), P(61, 79.5)], [1.5, 1.5, 3, 3])
        grip.addPath(rr(69.5, 48.5, 8.5, 15, 3.6))
        let rim = Path(ellipseIn: E(32, 56, 6.5, 22.5))
        let mouth = Path(ellipseIn: E(33, 56, 3.6, 18))
        return FT5SParts(outline: [cone, grip, rim].map { $0.applying(t) }, contact: E(51, 89, 26, 2.6)) { c in
            var m = c
            m.concatenate(t)
            m.fill(grip, with: .linearGradient(Gradient(colors: [blue.lo, blue.deep]), startPoint: P(60, 48), endPoint: P(70, 80)))
            FT5SGloss.barrel(&m, cone, blue, box: CGRect(x: 32, y: 34, width: 39, height: 44), vertical: true)
            FT5SGloss.orb(&m, rim, gold, light: UnitPoint(x: 0.3, y: 0.18))
            m.fill(mouth, with: .linearGradient(Gradient(colors: [blue.deep, blue.lo]), startPoint: P(33, 38), endPoint: P(33, 74)))
            FT5SGloss.glint(m, FT5SGloss.poly([P(40, 38.8), P(63, 47.4), P(63, 49.8), P(40, 41.8)], [1]), clip: cone)
        }
    }

    /// الأعضاء: بيدقان — كبير بلون الشجرة وصغير ذهبي — ٦ عمليات
    static func pawns(_ k: FT5SInk) -> FT5SParts {
        let teal = k.ramp(.tree), gold = k.ramp(.gold)
        let bigBody = pawnBody(40, 1), bigHead = Path(ellipseIn: E(40, 47, 11.5, 11.5))
        let smallBody = pawnBody(70, 0.72), smallHead = Path(ellipseIn: E(70, 61.2, 8.3, 8.3))
        return FT5SParts(outline: [bigBody, bigHead, smallBody, smallHead], contact: E(54, 91.2, 34, 2.8)) { c in
            FT5SGloss.barrel(&c, smallBody, gold)
            FT5SGloss.orb(&c, smallHead, gold)
            FT5SGloss.barrel(&c, bigBody, teal)
            FT5SGloss.orb(&c, bigHead, teal)
            FT5SGloss.glint(c, tilted(E(35.5, 41.5, 4.8, 2.8), -32), clip: bigHead)
        }
    }

    /// الأمان (القفل): خزنة بلون الإدارة بسُمك، قرص ذهبي، مقبض وقدمان — ٦ عمليات
    static func safe(_ k: FT5SInk) -> FT5SParts {
        let ink = k.ramp(.contact), gold = k.ramp(.gold)
        let body = rr(18, 22, 64, 62, 11)
        let dial = Path(ellipseIn: E(46, 53, 14, 14))
        var deep = Path()
        deep.addEllipse(in: E(46, 53, 4.6, 4.6))
        deep.addRoundedRect(in: CGRect(x: 68.5, y: 44, width: 4.6, height: 18), cornerSize: CGSize(width: 2.3, height: 2.3))
        deep.addRoundedRect(in: CGRect(x: 25, y: 86, width: 11, height: 4.4), cornerSize: CGSize(width: 2, height: 2))
        deep.addRoundedRect(in: CGRect(x: 64, y: 86, width: 11, height: 4.4), cornerSize: CGSize(width: 2, height: 2))
        let d: CGFloat = 4.5
        return FT5SParts(outline: [body, deep], contact: E(50, 91.6, 32, 2.8)) { c in
            FT5SGloss.slab(&c, body, ink, d: d)
            FT5SGloss.orb(&c, dial, gold, light: UnitPoint(x: 0.32, y: 0.26))
            c.fill(deep, with: .color(ink.deep))
            FT5SGloss.glint(c, tilted(E(30, 29.5, 8, 2.4), -10), clip: body)
        }
    }

    /// الأمان (الدرع/التحقّق): ختم موثّق مموّج بلون الإدارة، حلقة ذهبية وعلامة صح بيضاء — ٦ عمليات
    static func seal(_ k: FT5SInk) -> FT5SParts {
        let ink = k.ramp(.contact, shift: 1), gold = k.ramp(.gold)
        var rosette = Path()
        for i in 0...144 {
            let a = Double(i) / 144 * 2 * .pi
            let r = 31 + 2.4 * cos(a * 12)
            let pt = P(50 + CGFloat(r * cos(a)), 50 + CGFloat(r * sin(a)))
            if i == 0 { rosette.move(to: pt) } else { rosette.addLine(to: pt) }
        }
        rosette.closeSubpath()
        let ring = Path(ellipseIn: E(50, 50, 22, 22)).strokedPath(StrokeStyle(lineWidth: 2.6))
        var ck = Path()
        ck.move(to: P(38.5, 50.5)); ck.addLine(to: P(46.5, 58.5)); ck.addLine(to: P(62.5, 41))
        let mark = ck.strokedPath(StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round))
        let d: CGFloat = 4.5
        return FT5SParts(outline: [rosette, rosette.offsetBy(dx: 0, dy: d)], contact: E(50, 90.5, 26, 2.6)) { c in
            FT5SGloss.slab(&c, rosette, ink, d: d)
            c.fill(ring, with: .color(gold.lo))
            c.fill(mark, with: .color(.white))
            FT5SGloss.glint(c, tilted(E(34, 31, 9, 3.2), -38), clip: rosette)
        }
    }

    /// الإعدادات: مفتاح تبديل — مسار بلون «حسابي» بسُمك ومقبض أبيض لامع (جهة «تشغيل» بالعربية) — ٥ عمليات
    static func toggle(_ k: FT5SInk) -> FT5SParts {
        let blue = k.ramp(.profile, shift: 1), paper = k.ramp(.paper)
        let track = rr(12, 34, 76, 38, 19)
        let knob = Path(ellipseIn: E(31, 53, 15.5, 15.5))
        let d: CGFloat = 4.5
        return FT5SParts(outline: [track, track.offsetBy(dx: 0, dy: d), knob], contact: E(50, 80.5, 37, 3)) { c in
            FT5SGloss.slab(&c, track, blue, d: d)
            FT5SGloss.orb(&c, knob, paper, light: UnitPoint(x: 0.36, y: 0.26))
            FT5SGloss.glint(c, tilted(E(25.5, 45, 6.4, 3), -30), clip: knob)
        }
    }

    /// الوفاة: هلال ونجمة من حجر رمادي بسُمك خفيف، بلا لمعة ولا ذهبي — ساكن دائماً — ٥ عمليات
    static func crescent(_ k: FT5SInk) -> FT5SParts {
        let stone = k.ramp(.grey)
        let moon = FT5SGloss.crescent(outer: P(44, 52), 30, inner: P(58.5, 43), 25)
        let pin = star(P(64.5, 45), outer: 9, inner: 3.9)
        return FT5SParts(outline: [moon, pin, moon.offsetBy(dx: 0, dy: 3.5)], contact: E(46, 88, 22, 2.4)) { c in
            FT5SGloss.slab(&c, moon, stone, d: 3.5)
            FT5SGloss.slab(&c, pin, stone, d: 2.4)
        }
    }

    /// الجرس (الإشعارات): جسم كحلي فاتح، حافة ذهبية، لسان ومقبض ذهبيان — ٥ عمليات
    static func bell(_ k: FT5SInk) -> FT5SParts {
        let navy = k.ramp(.home), gold = k.ramp(.gold, shift: 1)
        let t = rot(-10, about: P(50, 18))
        let shell = lathe(50, P(50, 77), [
            .line(P(79, 77)),
            .quad(P(81, 73.5), P(81.8, 77)),
            .curve(P(69.5, 59), P(76, 70.5), P(70.5, 66.5)),
            .curve(P(67, 34), P(68.5, 49.5), P(69.5, 40)),
            .curve(P(50, 18.5), P(64, 24), P(57.5, 18.5))
        ])
        let rim = rr(16, 73, 68, 8, 4)
        var golds = Path()
        golds.addEllipse(in: E(50, 87, 7, 7))
        golds.addEllipse(in: E(50, 15.5, 4.6, 4.6))
        return FT5SParts(outline: [shell, rim, golds].map { $0.applying(t) }, contact: E(55, 95.5, 25, 2.6)) { c in
            var s = c
            s.concatenate(t)
            s.fill(golds, with: .linearGradient(Gradient(colors: [gold.hi, gold.lo]), startPoint: P(46, 11), endPoint: P(54, 94)))
            FT5SGloss.barrel(&s, shell, navy, box: CGRect(x: 18, y: 18, width: 64, height: 60))
            FT5SGloss.barrel(&s, rim, gold)
            FT5SGloss.glint(s, rr(31.5, 34, 4.4, 22, 2.2).applying(rot(9, about: P(33.7, 45))), clip: shell)
        }
    }

    /// الانتظار: ساعة مستديرة بإطار بلون الإدارة بسُمك، وجه أبيض، عقربان ومحور ذهبي — ٧ عمليات
    static func clock(_ k: FT5SInk) -> FT5SParts {
        let ink = k.ramp(.contact), paper = k.ramp(.paper), gold = k.ramp(.gold, shift: 1)
        let rim = Path(ellipseIn: E(50, 49, 32, 32))
        let face = Path(ellipseIn: E(50, 49, 24, 24))
        var h = Path()
        h.move(to: P(50, 49)); h.addLine(to: P(50, 32.5))
        h.move(to: P(50, 49)); h.addLine(to: P(61.5, 55.5))
        let hands = h.strokedPath(StrokeStyle(lineWidth: 4.6, lineCap: .round))
        let hub = Path(ellipseIn: E(50, 49, 4.6, 4.6))
        let d: CGFloat = 4.5
        return FT5SParts(outline: [rim, rim.offsetBy(dx: 0, dy: d)], contact: E(50, 88.5, 27, 2.6)) { c in
            FT5SGloss.slab(&c, rim, ink, d: d)
            c.fill(face, with: .linearGradient(Gradient(colors: [paper.lo, paper.hi]), startPoint: P(50, 25), endPoint: P(50, 73)))
            c.fill(hands, with: .color(ink.deep))
            FT5SGloss.orb(&c, hub, gold)
            FT5SGloss.glint(c, tilted(E(31, 30, 8.5, 2.8), -42), clip: rim)
        }
    }
}

// MARK: - رمز SF مجسّم صقيل (المعالجة العامة لأي رمز) والزرّ المجسّم

nonisolated enum FT5SGlyph {
    static func put(_ c: inout GraphicsContext, _ g: GraphicsContext.ResolvedText, _ p: CGPoint, _ color: Color) {
        var g = g
        g.shading = .color(color)
        c.draw(g, at: p, anchor: .center)
    }

    /// رمز النظام نفسه مجسّماً «صقيلاً»: سُمك أغمق تحته + وجه بتدرّج من الضوء + لمعة حادّة + ظلّ تلامس.
    /// على الألوان: وجه أبيض مشوب بلون القسم؛ على الأسطح الفاتحة: وجه بلون القسم. لا يُعكس (الرمز يبقى كما هو).
    static func polished(_ ctx: inout GraphicsContext, symbol: String, at p: CGPoint, size: CGFloat, weight: Font.Weight = .bold,
                         tint: Color, onLight: Bool, dark: Bool, shadow: Bool = true) {
        guard !symbol.isEmpty, size > 1 else { return }
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        let g = c.resolve(Text(Image(systemName: symbol)).font(.system(size: size, weight: weight)))
        let m = g.measure(in: CGSize(width: size * 4, height: size * 4))
        let box = CGRect(x: -m.width / 2, y: -m.height / 2, width: max(1, m.width), height: max(1, m.height))
        let d = max(1, size * 0.08)
        let ink = FT5SInk(dark: dark, onLight: onLight)
        if shadow {
            FT5SGloss.contact(c, CGRect(x: -box.width * 0.42, y: box.maxY + d - size * 0.05, width: box.width * 0.84, height: size * 0.16),
                              opacity: ink.contactOpacity)
        }
        let big = Path(box.insetBy(dx: -8, dy: -8))
        let light = onLight && !dark
        // السُّمك
        c.drawLayer { l in
            put(&l, g, CGPoint(x: 0, y: d), .white)
            l.blendMode = .sourceAtop
            if light {
                l.fill(big, with: .color(tint))
                l.fill(big, with: .color(.black.opacity(0.24)))
            } else {
                l.fill(big, with: .color(tint.opacity(0.62)))
            }
        }
        // الوجه + اللمعة الحادّة (حافة بيضاوية صلبة تعبر أعلى الرمز)
        c.drawLayer { l in
            put(&l, g, .zero, .white)
            l.blendMode = .sourceAtop
            if light {
                l.fill(big, with: .color(tint))
                l.fill(big, with: .linearGradient(Gradient(colors: [.white.opacity(0.32), .white.opacity(0)]),
                                                  startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)))
            } else {
                l.fill(big, with: .linearGradient(Gradient(colors: [tint.opacity(0.04), tint.opacity(0.36)]),
                                                  startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)))
            }
            let band = Path(ellipseIn: CGRect(x: box.minX - box.width * 0.35, y: box.minY - box.height * 0.62,
                                              width: box.width * 1.0, height: box.height * 1.0))
            l.fill(band, with: .color(.white.opacity(light ? 0.24 : 0.55)))
        }
    }

    /// زرّ مجسّم صقيل بلون القسم/النوع ورمز أبيض (أيقونات الحالة ولوحة الإدارة): سُمك + وجه + لمعة حادّة — ٧ عمليات
    static func button(_ ctx: inout GraphicsContext, symbol: String, tint: Color, size: CGSize, squircle: Bool, dark: Bool) {
        let s = min(size.width, size.height)
        guard s > 4 else { return }
        let bw = s * 0.84
        let d = max(1.5, s * 0.06)
        let body = CGRect(x: (size.width - bw) / 2, y: (size.height - bw - d) / 2, width: bw, height: bw)
        func shape(_ r: CGRect) -> Path {
            squircle ? Path(roundedRect: r, cornerRadius: bw * 0.3, style: .continuous) : Path(ellipseIn: r)
        }
        let face = shape(body)
        let back = shape(body.offsetBy(dx: 0, dy: d))
        FT5SGloss.contact(ctx, CGRect(x: body.minX + bw * 0.12, y: body.maxY + d - bw * 0.07, width: bw * 0.76, height: bw * 0.16),
                          opacity: dark ? 0.5 : 0.2)
        ctx.fill(back, with: .color(tint))
        ctx.fill(back, with: .color(.black.opacity(dark ? 0.34 : 0.26)))
        FT5SGloss.tintFace(&ctx, face, tint)
        var g = ctx
        g.clip(to: face)
        g.fill(Path(ellipseIn: CGRect(x: body.minX - bw * 0.25, y: body.minY - bw * 0.6, width: bw, height: bw)),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.28), .white.opacity(0.05)]),
                                     startPoint: CGPoint(x: body.minX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.midY)))
        let glyph = ctx.resolve(Text(Image(systemName: symbol)).font(.system(size: s * 0.38, weight: .bold)))
        put(&ctx, glyph, CGPoint(x: body.midX, y: body.midY), .white)
    }
}

// MARK: - مشاهد الأماكن

nonisolated enum FT5SScene {
    static func isLTR(_ ctx: GraphicsContext) -> Bool { ctx.environment.layoutDirection == .leftToRight }

    /// يعكس السياق في الإنجليزية (المجسّم في الجهة المقابلة للعنوان)
    static func mirrored(_ ctx: GraphicsContext, width: CGFloat) -> GraphicsContext {
        var c = ctx
        if isLTR(ctx) {
            c.translateBy(x: width, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        return c
    }

    static func object(_ kind: FT5SKind, in c: inout GraphicsContext, target: CGRect, bottom: Bool, ink: FT5SInk,
                       mirrored: Bool = false) {
        let box = FT5SArt.fit(kind, in: target, bottom: bottom)
        var g = c
        g.translateBy(x: box.minX, y: box.minY)
        g.scaleBy(x: box.width / 100, y: box.width / 100)
        FT5SArt.drawObject(kind, in: &g, ink: ink, mirrored: mirrored)
    }

    /// رأس المربّع: المجسّم الخاص أو الرمز نفسه مجسّماً صقيلاً — داخل أول ٢٢٫٥٪ من الطرف
    static func header(_ kind: FT5SKind?, icon: String, tint: Color, in ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        if let kind {
            FT5SArt.draw(kind, in: &ctx, size: size, slot: .header, dark: dark)
            return
        }
        let rtl = !isLTR(ctx)
        let maxX = min(size.width * 0.225, 108) - 4
        let cx = (12 + maxX) / 2
        FT5SGlyph.polished(&ctx, symbol: icon, at: CGPoint(x: rtl ? cx : size.width - cx, y: size.height * 0.47),
                           size: min(size.height * 0.36, (maxX - 12) * 0.52), tint: tint, onLight: false, dark: dark)
    }

    /// أيقونة الرأس: المجسّم يملأ الإطار (هامش صغير) على السطح الملوّن، أو الرمز نفسه مجسّماً صقيلاً
    static func icon(_ kind: FT5SKind?, icon: String, tint: Color, in ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        let side = min(size.width, size.height)
        guard side > 1 else { return }
        let p = CGPoint(x: size.width / 2, y: size.height / 2)
        if let kind {
            var c = mirrored(ctx, width: size.width)
            object(kind, in: &c, target: CGRect(x: p.x - side * 0.46, y: p.y - side * 0.46, width: side * 0.92, height: side * 0.92),
                   bottom: true, ink: FT5SInk(dark: dark), mirrored: isLTR(ctx))
        } else {
            FT5SGlyph.polished(&ctx, symbol: icon, at: p, size: side * 0.62, tint: tint, onLight: false, dark: dark)
        }
    }

    /// بطاقة رأس الصفحة: مجسّم في الطرف الآخر (≤ ٤٠٪) وأعلى صفّ الأرقام
    static func hero(_ kind: FT5SKind?, icon: String, tint: Color, in ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let w = max(20, min(size.width * 0.40 - 24, 76))
        let target = CGRect(x: 18, y: 12, width: w, height: max(20, min(56, size.height - 24)))
        let ltr = isLTR(ctx)
        if let kind {
            var c = mirrored(ctx, width: size.width)
            object(kind, in: &c, target: target, bottom: false, ink: FT5SInk(dark: dark), mirrored: ltr)
            return
        }
        FT5SGlyph.polished(&ctx, symbol: icon, at: CGPoint(x: ltr ? size.width - target.midX : target.midX, y: target.midY),
                           size: min(target.height * 0.6, 34), tint: tint, onLight: false, dark: dark)
    }

    /// قرص خفيف بلون القسم (الصفحات الفاضية والأماكن) — عملية واحدة
    static func dish(_ c: inout GraphicsContext, center p: CGPoint, radius r: CGFloat, tint: Color, dark: Bool) {
        c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
               with: .color(tint.opacity(dark ? 0.18 : 0.08)))
    }

    /// صفحة فاضية: القرص + مجسّم القسم، أو رمز الصفحة مجسّماً صقيلاً بلون القسم
    static func empty(_ kind: FT5SKind?, icon: String, tint: Color, in ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        let side = min(size.width, size.height)
        guard side > 1 else { return }
        let p = CGPoint(x: size.width / 2, y: size.height / 2)
        dish(&ctx, center: p, radius: side * 0.45, tint: tint, dark: dark)
        let ink = FT5SInk(dark: dark, onLight: true)
        if let kind {
            var c = mirrored(ctx, width: size.width)
            object(kind, in: &c, target: CGRect(x: p.x - side * 0.29, y: p.y - side * 0.28, width: side * 0.58, height: side * 0.56),
                   bottom: true, ink: ink, mirrored: isLTR(ctx))
        } else {
            FT5SGlyph.polished(&ctx, symbol: icon, at: CGPoint(x: p.x, y: p.y - side * 0.02), size: side * 0.32,
                               tint: tint, onLight: true, dark: dark)
        }
    }

    /// مكان بمجسّم واحد على قرص (الانتظار، الإشعارات) أو على أرض خفيفة (تحميل الشجرة)
    static func place(_ kind: FT5SKind, in ctx: inout GraphicsContext, size: CGSize, dark: Bool, tint: Color,
                      ground: Bool, fraction: CGFloat) {
        let side = min(size.width, size.height)
        guard side > 1 else { return }
        let p = CGPoint(x: size.width / 2, y: size.height / 2)
        if ground {
            FT5SGloss.soft(ctx, CGRect(x: p.x - size.width * 0.40, y: size.height * 0.88 - side * 0.05,
                                       width: size.width * 0.80, height: side * 0.10), tint, dark ? 0.30 : 0.14)
        } else {
            dish(&ctx, center: p, radius: side * 0.45, tint: tint, dark: dark)
        }
        let t = side * fraction
        let target = ground
            ? CGRect(x: p.x - t * 0.6, y: size.height * 0.92 - t, width: t * 1.2, height: t)
            : CGRect(x: p.x - t / 2, y: p.y - t / 2, width: t, height: t * 0.96)
        var c = ctx
        object(kind, in: &c, target: target, bottom: true, ink: FT5SInk(dark: dark, onLight: true))
    }
}

// MARK: - العروض (كلها ساكنة؛ الحركة الوحيدة ظهور واحد بالشفافية ويُلغى مع «تقليل الحركة»)

/// مجسّم مربّع الرئيسية — يظهر مرة واحدة بالشفافية ثم يسكن
struct FT5STileArt: View {
    let kind: FT5SKind
    var badge: Bool = false
    var animateOnce: Bool = false
    var projectsTitle: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind, long = projectsTitle
        let slot: FT5SSlot = badge ? .tileBadge : .tile
        let hidden = animateOnce && !shown && !reduceMotion
        Canvas { ctx, size in
            FT5SArt.draw(kind, in: &ctx, size: size, slot: slot, dark: dark, longTitle: long)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard animateOnce, !shown, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { shown = true }
        }
    }
}

/// رأس المربّع الأوسط (٨٦ نقطة) — ساكن
struct FT5SHeaderArt: View {
    let kind: FT5SKind?
    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind, icon = self.icon, tint = self.tint
        Canvas { ctx, size in FT5SScene.header(kind, icon: icon, tint: tint, in: &ctx, size: size, dark: dark) }
            // الرأس ٨٦ نقطة دائماً — الهالة (١٥٠ نقطة) في نفس الـ ZStack تكبّر اللوحة بدون هذا الإطار
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// أيقونة الرأس: المجسّم في وسط إطاره (بدل الدائرة الزجاجية) — ساكن
struct FT5SIconArt: View {
    let kind: FT5SKind?
    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind, icon = self.icon, tint = self.tint
        Canvas { ctx, size in FT5SScene.icon(kind, icon: icon, tint: tint, in: &ctx, size: size, dark: dark) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// بطاقة رأس الصفحة — ساكن
struct FT5SHeroArt: View {
    let kind: FT5SKind?
    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind, icon = self.icon, tint = self.tint
        Canvas { ctx, size in FT5SScene.hero(kind, icon: icon, tint: tint, in: &ctx, size: size, dark: dark) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// الصفحة الفاضية ١٣٠×١٣٠ — ساكن
struct FT5SEmptyArt: View {
    let kind: FT5SKind?
    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind ?? FT5SArt.headerKind(icon: icon, library: FT5STrial.libraryVariant, projects: FT5STrial.projectsVariant)
        let icon = self.icon, tint = self.tint
        Canvas { ctx, size in FT5SScene.empty(kind, icon: icon, tint: tint, in: &ctx, size: size, dark: dark) }
            .frame(width: 130, height: 130)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// زرّ مجسّم صقيل بلون القسم ورمز أبيض — أيقونات الحالة (دائرة) ولوحة الإدارة (مربّع مدوّر)
struct FT5SButton: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 52
    var squircle: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let icon = self.icon, tint = self.tint, sq = squircle
        Canvas { ctx, sz in FT5SGlyph.button(&ctx, symbol: icon, tint: tint, size: sz, squircle: sq, dark: dark) }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FT5SStateIcon: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 52
    var body: some View { FT5SButton(icon: icon, tint: tint, size: size, squircle: false) }
}

/// تحميل الشجرة ٢٤٠×٢٠٠: شجرة العائلة على أرض خفيفة — ساكنة
struct FT5STreeLoading: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let green = FT5SHex.color(0x1E5950)
        Canvas { ctx, size in
            FT5SScene.place(.familyTree, in: &ctx, size: size, dark: dark, tint: green, ground: true, fraction: 0.66)
        }
        .frame(width: 240, height: 200)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// بانتظار الموافقة ١٤٠×١٤٠: ساعة بإطار نيلي (لون الإدارة) على قرص خفيف — ساكنة
struct FT5SWaiting: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let indigo = FT5SHex.color(0x47467F)
        Canvas { ctx, size in
            FT5SScene.place(.clock, in: &ctx, size: size, dark: dark, tint: indigo, ground: false, fraction: 0.6)
        }
        .frame(width: 140, height: 140)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// إشعارات فاضية ١٢٠×١٢٠: جرس كحلي بحافة ولسان ذهبيين على قرص كحلي خفيف — ساكن
struct FT5SNotificationsEmpty: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Canvas { ctx, size in
            FT5SScene.place(.bell, in: &ctx, size: size, dark: dark, tint: FT5SHex.color(0x1F4E79), ground: false, fraction: 0.58)
        }
        .frame(width: 120, height: 120)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// خلفية الدخول: توهّج دافئ خافت جداً وحلقة رفيعة واحدة حول الشعار — ساكنة
struct FT5SLoginBackdrop: View {
    let logoCenterY: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let y = logoCenterY
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: y)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 130, y: c.y - 130, width: 260, height: 260)),
                     with: .radialGradient(Gradient(colors: [FT5SHex.color(0xF2C65E, alpha: dark ? 0.05 : 0.08), .clear]),
                                           center: c, startRadius: 0, endRadius: 130))
            let r: CGFloat = 96
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color((dark ? Color.white : FT5SHex.color(0x1F4E79)).opacity(dark ? 0.05 : 0.06)), lineWidth: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// بطاقة «الأخبار» ٦٠×٤٤: صحيفة مطويّة صغيرة بعنوان أزرق — ساكن
struct FT5SNewsCardArt: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Canvas { ctx, size in
            let ltr = FT5SScene.isLTR(ctx)
            var c = FT5SScene.mirrored(ctx, width: size.width)
            FT5SScene.object(.newspaper, in: &c, target: CGRect(x: 4, y: 2, width: size.width - 8, height: size.height - 4),
                             bottom: false, ink: FT5SInk(dark: dark, onLight: true), mirrored: ltr)
        }
        .frame(width: 60, height: 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// شريط تحت رأس التبويب (١٢ نقطة) — ساكن
struct FT5SOrnament: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Canvas { ctx, size in FT5SOrnaments.draw(&ctx, size: size, dark: dark) }
            .frame(height: 12)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated enum FT5SOrnaments {
    /// خطّ رفيع يتلاشى نحو الطرفين، وفي الوسط قطعة ذهبية صقيلة (تدرّج + لمعة حادّة) وحبّتان كريميّتان — ٤ عمليات
    static func draw(_ c: inout GraphicsContext, size: CGSize, dark: Bool) {
        let w = size.width, cy = size.height / 2, cx = w / 2
        guard w > 60 else { return }
        let cream = FT5SHex.color(0xFFF4DE)
        let a = dark ? 0.30 : 0.42
        let gap = min(0.5, 22 / w)
        c.fill(Path(roundedRect: CGRect(x: 4, y: cy - 0.5, width: w - 8, height: 1), cornerRadius: 0.5),
               with: .linearGradient(Gradient(stops: [
                .init(color: cream.opacity(0), location: 0),
                .init(color: cream.opacity(a), location: 0.3),
                .init(color: cream.opacity(0), location: 0.5 - gap),
                .init(color: cream.opacity(0), location: 0.5 + gap),
                .init(color: cream.opacity(a), location: 0.7),
                .init(color: cream.opacity(0), location: 1)
               ]), startPoint: CGPoint(x: 4, y: cy), endPoint: CGPoint(x: w - 4, y: cy)))
        let gold = FT5SRamp(.gold, start: 1, dim: dark ? 0.92 : 1)
        let bar = CGRect(x: cx - 10, y: cy - 2.7, width: 20, height: 5.4)
        c.fill(Path(roundedRect: bar, cornerRadius: 2.7),
               with: .linearGradient(Gradient(colors: [gold.hi, gold.mid, gold.lo]),
                                     startPoint: CGPoint(x: bar.midX, y: bar.minY), endPoint: CGPoint(x: bar.midX, y: bar.maxY)))
        c.fill(Path(roundedRect: CGRect(x: bar.minX + 3, y: bar.minY + 0.9, width: 8, height: 1.3), cornerRadius: 0.65),
               with: .color(.white.opacity(0.9)))
        var beads = Path()
        beads.addEllipse(in: CGRect(x: cx - 18, y: cy - 1.6, width: 3.2, height: 3.2))
        beads.addEllipse(in: CGRect(x: cx + 14.8, y: cy - 1.6, width: 3.2, height: 3.2))
        c.fill(beads, with: .color(cream.opacity(dark ? 0.6 : 0.78)))
    }
}

// MARK: - شارات أنواع الأخبار (ساكنة: شكل واحد بسُمك رفيع + لمسة ذهبية واحدة على الأكثر، بلا ضبابية)

nonisolated enum FT5SBadgeKind: CaseIterable {
    case news, announce, congrats, wedding, birth, death, poll, invite, reminder

    init?(type: String) {
        switch type {
        case "خبر": self = .news
        case "إعلان": self = .announce
        case "تهنئة": self = .congrats
        case "زواج": self = .wedding
        case "مولود": self = .birth
        case "وفاة": self = .death
        case "تصويت": self = .poll
        case "دعوة": self = .invite
        case "تذكير": self = .reminder
        default: return nil
        }
    }

    /// يُعكس في الإنجليزية (مكبّر الصوت يتّجه مع القراءة، وأعمدة النتائج تبدأ من جهة القراءة)
    var directional: Bool { self == .announce || self == .poll }
}

struct FT5SNewsBadge: View {
    let kind: FT5SBadgeKind
    let tint: Color
    let onColor: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind, tint = self.tint, on = onColor
        Canvas { ctx, size in FT5SBadges.draw(kind, in: &ctx, size: size, tint: tint, onColor: on, dark: dark) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated enum FT5SBadges {
    static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    static func E(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)
    }
    static func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    /// الرسم في شبكة ٢٠×٢٠ في وسط الإطار (٦٦٪ من القطر) — الدائرة نفسها يرسمها التطبيق خلفها
    static func draw(_ kind: FT5SBadgeKind, in ctx: inout GraphicsContext, size: CGSize, tint: Color, onColor: Bool, dark: Bool) {
        let side = min(size.width, size.height)
        guard side > 4 else { return }
        var g = ctx
        let box = side * 0.66
        g.translateBy(x: (size.width - box) / 2, y: (size.height - box) / 2)
        g.scaleBy(x: box / 20, y: box / 20)
        if kind.directional && ctx.environment.layoutDirection == .leftToRight {
            g.translateBy(x: 20, y: 0)
            g.scaleBy(x: -1, y: 1)
        }
        let dim = dark ? 0.92 : 1
        let gold = FT5SRamp(.gold, start: onColor ? 0 : 1, dim: dim)
        // الشكل الرئيسي: سُمك رفيع تحته + وجه مضاء (أبيض فوق اللون، أو بلون النوع فوق الدائرة الفاتحة)
        func body(_ c: inout GraphicsContext, _ p: Path, depth: CGFloat = 0.9) {
            let b = p.boundingRect
            let back = p.offsetBy(dx: 0, dy: depth)
            if onColor {
                c.fill(back, with: .color(.black.opacity(0.2)))
                c.fill(p, with: .linearGradient(Gradient(colors: [.white, FT5SHex.color(0xE3E9F0)]),
                                                startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.midX, y: b.maxY)))
            } else {
                c.fill(back, with: .color(tint))
                c.fill(back, with: .color(.black.opacity(0.24)))
                FT5SGloss.tintFace(&c, p, tint)
            }
        }
        // اللمسة الذهبية الواحدة
        func accent(_ c: inout GraphicsContext, _ p: Path) {
            let b = p.boundingRect
            c.fill(p, with: .linearGradient(Gradient(colors: [gold.hi, gold.lo]),
                                            startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        }
        let detail: Color = onColor ? tint.opacity(0.55) : .white.opacity(0.9)
        switch kind {
        case .news:
            // صحيفة مطويّة: ورقة وعنوان ذهبي وأسطر
            var s = g
            s.concatenate(FT5SObjects.rot(-6, about: P(10, 10)))
            body(&s, R(4.4, 2.8, 11.2, 14, 1.8))
            accent(&s, R(6.3, 4.9, 7.4, 2.3, 0.9))
            var lines = Path()
            for y in [9.2, 11.8, 14.4] as [CGFloat] {
                lines.addRoundedRect(in: CGRect(x: 6.3, y: y, width: y > 14 ? 4.8 : 7.4, height: 1.4),
                                     cornerSize: CGSize(width: 0.7, height: 0.7))
            }
            s.fill(lines, with: .color(detail))
        case .announce:
            // مكبّر صوت بحافة ذهبية ومقبض
            var s = g
            s.concatenate(FT5SObjects.rot(-14, about: P(10, 10)))
            body(&s, FT5SGloss.poly([P(15.6, 7.8), P(5.8, 4), P(5.8, 16), P(15.6, 12.2)], [1.4, 0.8, 0.8, 1.4]))
            accent(&s, Path(ellipseIn: E(5.8, 10, 1.9, 6.2)))
            s.fill(FT5SGloss.poly([P(11.8, 12.2), P(13.8, 11.8), P(14.8, 16), P(12.8, 16.4)], [0.5, 0.5, 0.9, 0.9]), with: .color(detail))
        case .congrats:
            // بالونان: كبير بلون الشكل وصغير ذهبي، بخيطين رفيعين
            var strings = Path()
            strings.move(to: P(8.6, 15.4)); strings.addQuadCurve(to: P(10.4, 19.4), control: P(8, 17.6))
            strings.move(to: P(14, 11.4)); strings.addQuadCurve(to: P(10.6, 19.4), control: P(14.2, 16))
            g.fill(strings.strokedPath(StrokeStyle(lineWidth: 0.8, lineCap: .round)), with: .color(detail))
            accent(&g, Path(ellipseIn: E(14, 6.8, 3.6, 4.4)))
            var big = Path(ellipseIn: E(8.6, 8.4, 4.9, 5.9))
            big.addPath(FT5SGloss.poly([P(8.6, 14.3), P(9.9, 15.6), P(7.3, 15.6)], [0.3]))
            body(&g, big, depth: 0.7)
        case .wedding:
            // خاتم ذهبي بفصّ أبيض
            accent(&g, Path(ellipseIn: E(10, 12.4, 5.3, 5.3)).strokedPath(StrokeStyle(lineWidth: 2.1)))
            let gem = FT5SGloss.poly([P(7.4, 4.4), P(12.6, 4.4), P(14.4, 6.5), P(10, 10.8), P(5.6, 6.5)], [0.5])
            body(&g, gem, depth: 0.7)
            var facet = Path()
            facet.move(to: P(5.9, 6.5)); facet.addLine(to: P(14.1, 6.5))
            g.fill(facet.strokedPath(StrokeStyle(lineWidth: 0.6)), with: .color(detail))
        case .birth:
            // رضّاعة: قارورة وحلمة، وطوق ذهبي، وعلامتا قياس
            var bottle = R(6.6, 8.6, 6.8, 9.6, 2)
            bottle.addPath(R(8.4, 2.6, 3.2, 4.4, 1.6))
            body(&g, bottle, depth: 0.8)
            accent(&g, R(6, 6.4, 8, 2.6, 1))
            var marks = Path()
            marks.addRoundedRect(in: CGRect(x: 7.9, y: 11.4, width: 2.4, height: 0.9), cornerSize: CGSize(width: 0.45, height: 0.45))
            marks.addRoundedRect(in: CGRect(x: 7.9, y: 13.8, width: 1.8, height: 0.9), cornerSize: CGSize(width: 0.45, height: 0.45))
            g.fill(marks, with: .color(detail))
        case .death:
            // هلال ونجمة رماديّان — ساكن دائماً، بلا ذهبي ولا لمعة
            let stone: FT5SRamp = onColor ? FT5SRamp(.grey, start: 0, dim: 1) : FT5SRamp(.grey, start: dark ? 0 : 2, dim: 1)
            let moon = FT5SGloss.crescent(outer: P(9.2, 10.6), 6.8, inner: P(12.6, 8), 5.6, steps: 24)
            let pin = FT5SObjects.star(P(13.9, 8.6), outer: 2.6, inner: 1.1)
            let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [stone.hi, stone.lo]),
                                                               startPoint: P(4, 4), endPoint: P(14, 18))
            g.fill(moon, with: shade)
            g.fill(pin, with: shade)
        case .poll:
            // أعمدة نتائج تبدأ من جهة القراءة، والفائز ذهبي
            var bars = R(7.6, 3.4, 8.8, 3.4, 1.4)
            bars.addPath(R(9.8, 13.2, 6.6, 3.4, 1.4))
            body(&g, bars, depth: 0.7)
            accent(&g, R(3.6, 8.3, 12.8, 3.4, 1.4))
        case .invite:
            // تذكرة بحافتين مقصوصتين ونجمة ذهبية
            var ticket = Path()
            ticket.move(to: P(4.8, 5.2))
            ticket.addLine(to: P(15.2, 5.2))
            ticket.addQuadCurve(to: P(17, 7), control: P(17, 5.2))
            ticket.addLine(to: P(17, 8.2))
            ticket.addQuadCurve(to: P(17, 11.8), control: P(14.6, 10))
            ticket.addLine(to: P(17, 13))
            ticket.addQuadCurve(to: P(15.2, 14.8), control: P(17, 14.8))
            ticket.addLine(to: P(4.8, 14.8))
            ticket.addQuadCurve(to: P(3, 13), control: P(3, 14.8))
            ticket.addLine(to: P(3, 11.8))
            ticket.addQuadCurve(to: P(3, 8.2), control: P(5.4, 10))
            ticket.addLine(to: P(3, 7))
            ticket.addQuadCurve(to: P(4.8, 5.2), control: P(3, 5.2))
            ticket.closeSubpath()
            body(&g, ticket)
            accent(&g, FT5SObjects.star(P(10, 10.1), outer: 3, inner: 1.3))
        case .reminder:
            // ورقة تقويم: رأس ذهبي وحلقتان ويوم معلّم
            let page = R(3.8, 4.6, 12.4, 12.6, 2)
            body(&g, page)
            var top = g
            top.clip(to: page)
            accent(&top, Path(CGRect(x: 3.8, y: 4.6, width: 12.4, height: 3.8)))
            var marks = Path()
            marks.addRoundedRect(in: CGRect(x: 6.3, y: 2.8, width: 1.5, height: 3.6), cornerSize: CGSize(width: 0.75, height: 0.75))
            marks.addRoundedRect(in: CGRect(x: 12.2, y: 2.8, width: 1.5, height: 3.6), cornerSize: CGSize(width: 0.75, height: 0.75))
            marks.addRoundedRect(in: CGRect(x: 8.3, y: 10.6, width: 3.4, height: 3.4), cornerSize: CGSize(width: 0.8, height: 0.8))
            g.fill(marks, with: .color(detail))
        }
    }
}

// MARK: - لحظات التنبيه (١٦٠×١١٢): مجسّم واحد بسيط يظهر مرة واحدة بالشفافية ثم يسكن

nonisolated enum FT5SMomentKind {
    case success, sentForApproval, approved, newMember
    init(name: String) {
        switch name {
        case "sentForApproval": self = .sentForApproval
        case "approved": self = .approved
        case "newMember": self = .newMember
        default: self = .success
        }
    }
}

struct FT5SMoment: View {
    let kind: FT5SMomentKind
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    init(kind: FT5SMomentKind, tint: Color, final: Bool = false) {
        self.kind = kind
        self.tint = tint
        _shown = State(initialValue: final)
    }

    var body: some View {
        let dark = scheme == .dark
        let kind = self.kind, tint = self.tint
        Canvas { ctx, size in FT5SMoments.draw(kind, in: &ctx, size: size, tint: tint, dark: dark) }
            .opacity(shown || reduceMotion ? 1 : 0)
            .frame(width: 160, height: 112)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.35)) { shown = true } }
            }
    }
}

nonisolated enum FT5SMoments {
    static func draw(_ kind: FT5SMomentKind, in ctx: inout GraphicsContext, size: CGSize, tint: Color, dark: Bool) {
        let side = min(size.width, size.height)
        guard side > 1 else { return }
        var c = FT5SScene.mirrored(ctx, width: size.width)
        c.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        c.scaleBy(x: side / 100, y: side / 100)
        let k = FT5SInk(dark: dark, onLight: true)
        let P = FT5SObjects.P, E = FT5SObjects.E
        func check(_ a: CGPoint, _ b: CGPoint, _ e: CGPoint, _ w: CGFloat) -> Path {
            var ck = Path()
            ck.move(to: a); ck.addLine(to: b); ck.addLine(to: e)
            return ck.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        switch kind {
        case .success:
            // قرص صقيل بلون القسم وعلامة صح بيضاء — ٧ عمليات
            let disc = Path(ellipseIn: E(50, 45, 30, 30))
            FT5SGloss.contact(c, E(50, 85, 25, 3), opacity: k.contactOpacity)
            FT5SGloss.tintSlab(&c, disc, tint, d: 5, dark: dark)
            c.fill(check(P(37, 46), P(46, 55), P(64, 36), 8), with: .color(.white))
            FT5SGloss.glint(c, FT5SObjects.tilted(E(36.5, 27.5, 9, 3.4), -36), clip: disc, opacity: 0.5)
        case .sentForApproval:
            // طائرة ورقية بلون القسم: جناح مضاء وعارضة مظلّلة — ٦ عمليات
            let wing = FT5SGloss.poly([P(8, 30), P(92, 38), P(50, 62)], [1.6])
            let keel = FT5SGloss.poly([P(8, 30), P(50, 62), P(62, 88)], [1.6])
            FT5SGloss.contact(c, E(54, 93, 27, 2.6), opacity: k.contactOpacity)
            c.fill(keel, with: .color(tint))
            c.fill(keel, with: .color(.black.opacity(dark ? 0.32 : 0.26)))
            FT5SGloss.tintFace(&c, wing, tint)
            FT5SGloss.glint(c, FT5SGloss.poly([P(22, 34), P(66, 38.2), P(64, 40.6), P(24, 36.4)], [0.6]), clip: wing, opacity: 0.7)
        case .approved:
            // ختم موثّق مموّج بلون القسم وحلقة ذهبية وعلامة صح بيضاء — ٨ عمليات
            var rosette = Path()
            for i in 0...144 {
                let a = Double(i) / 144 * 2 * .pi
                let r = 28 + 2.2 * cos(a * 12)
                let pt = P(50 + CGFloat(r * cos(a)), 44 + CGFloat(r * sin(a)))
                if i == 0 { rosette.move(to: pt) } else { rosette.addLine(to: pt) }
            }
            rosette.closeSubpath()
            FT5SGloss.contact(c, E(50, 84, 23, 2.6), opacity: k.contactOpacity)
            FT5SGloss.tintSlab(&c, rosette, tint, d: 4.5, dark: dark)
            c.fill(Path(ellipseIn: E(50, 44, 19.5, 19.5)).strokedPath(StrokeStyle(lineWidth: 2.4)),
                   with: .color(FT5SRamp(.gold, start: 1, dim: k.dim).mid))
            c.fill(check(P(39.5, 44.5), P(47, 52), P(61.5, 36.5), 7), with: .color(.white))
            FT5SGloss.glint(c, FT5SObjects.tilted(E(36, 27, 8, 3), -38), clip: rosette, opacity: 0.5)
        case .newMember:
            // عضو جديد: بيدق بلون الشجرة وقرص ذهبي عليه «+» — ٧ عمليات
            let teal = k.ramp(.tree), gold = k.ramp(.gold)
            let body = FT5SObjects.pawnBody(42, 1.05)
            let head = Path(ellipseIn: E(42, 43, 12, 12))
            let coin = Path(ellipseIn: E(70, 40, 12.5, 12.5))
            var plus = Path()
            plus.addRoundedRect(in: CGRect(x: 63.5, y: 37.8, width: 13, height: 4.4), cornerSize: CGSize(width: 2.2, height: 2.2))
            plus.addRoundedRect(in: CGRect(x: 67.8, y: 33.5, width: 4.4, height: 13), cornerSize: CGSize(width: 2.2, height: 2.2))
            FT5SGloss.contact(c, E(52, 91, 28, 2.6), opacity: k.contactOpacity)
            FT5SGloss.barrel(&c, body, teal)
            FT5SGloss.orb(&c, head, teal)
            FT5SGloss.glint(c, FT5SObjects.tilted(E(37, 37, 5, 2.8), -32), clip: head)
            FT5SGloss.orb(&c, coin, gold)
            c.fill(plus, with: .color(.white))
        }
    }
}

// MARK: - رمز الوقت (بطاقة الترحيب، ١٨ نقطة)

struct FT5STimeOrbView: View {
    let mood: FT5STimeOrb.Mood
    var size: CGFloat = 18
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let mood = self.mood
        Canvas { ctx, sz in FT5STimeOrb.draw(mood, in: &ctx, size: sz, dark: dark) }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated enum FT5STimeOrb {
    enum Mood { case morning, afternoon, evening }

    /// شمس ذهبية صقيلة بأشعّة قصيرة، أو هلال ذهبي فاتح ونجمة، أو شمس خلف غيمة بيضاء بسُمك — بلا ضبابية
    static func draw(_ mood: Mood, in ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        let k = FT5SInk(dark: dark)
        var c = ctx
        let s = min(size.width, size.height)
        c.translateBy(x: (size.width - s) / 2, y: (size.height - s) / 2)
        c.scaleBy(x: s / 20, y: s / 20)
        let E = FT5SObjects.E
        let sun = FT5SRamp(.gold, start: 1, dim: k.dim)
        switch mood {
        case .afternoon:
            var rays = Path()
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                rays.move(to: CGPoint(x: 10 + 7.6 * cos(a), y: 10 + 7.6 * sin(a)))
                rays.addLine(to: CGPoint(x: 10 + 9.3 * cos(a), y: 10 + 9.3 * sin(a)))
            }
            c.fill(rays.strokedPath(StrokeStyle(lineWidth: 1.5, lineCap: .round)), with: .color(sun.lo))
            let disc = Path(ellipseIn: E(10, 10, 5.8, 5.8))
            FT5SGloss.orb(&c, disc, sun, light: UnitPoint(x: 0.34, y: 0.3))
            FT5SGloss.glint(c, FT5SObjects.tilted(E(8.1, 7.5, 2.1, 1.1), -35), clip: disc, opacity: 0.85)
        case .evening:
            let moonT = FT5SRamp(.gold, start: 0, dim: k.dim)
            let moon = FT5SGloss.crescent(outer: CGPoint(x: 9.4, y: 10.4), 7.2, inner: CGPoint(x: 13.2, y: 7.6), 6.2, steps: 24)
            FT5SGloss.orb(&c, moon, moonT, box: E(9.4, 10.4, 7.2, 7.2), light: UnitPoint(x: 0.3, y: 0.55))
            c.fill(FT5SObjects.star(CGPoint(x: 15.4, y: 13.2), outer: 1.9, inner: 0.8), with: .color(moonT.lo))
        case .morning:
            FT5SGloss.orb(&c, Path(ellipseIn: E(12.6, 7.8, 5, 5)), sun, light: UnitPoint(x: 0.34, y: 0.3))
            var cloud = Path()
            cloud.addEllipse(in: E(6.8, 14.2, 4.0, 3.2))
            cloud.addEllipse(in: E(10.8, 12.6, 4.6, 4.2))
            cloud.addEllipse(in: E(14.6, 14.6, 3.6, 2.8))
            cloud.addEllipse(in: E(10.6, 15.6, 7.4, 2.2))
            c.fill(cloud.offsetBy(dx: 0, dy: 0.9), with: .color(k.color(0xC5CFDA)))
            c.fill(cloud, with: .linearGradient(Gradient(colors: [k.color(0xFFFFFF), k.color(0xE9EEF3)]),
                                                startPoint: CGPoint(x: 10, y: 8.4), endPoint: CGPoint(x: 10, y: 18)))
        }
    }
}
