import SwiftUI

// MARK: - «زجاج ونور» FT5G — رسوم التطبيق كله (الجولة الخامسة، ٢٠٢٦-١٠-٠٥)
//
// الفكرة نفسها التي أبقاها المالك: في كل مكان «قطعة زجاج» واحدة واضحة، مركّبة من طبقتين أو ثلاث متراكبة
// (تقاطع الطبقات أسطع، وكل طبقة تلقي ظلاً رقيقاً على ما خلفها)، بحافة ضوء ساطعة من أعلى جهة البداية.
// • فوق الألوان (المربّعات، رؤوس الصناديق، بطاقات الصفحات، رأس الأقسام): زجاج أبيض مصقول + وهج ناعم.
// • فوق الأسطح المحايدة (الصفحات الفاضية، الانتظار، الإشعارات، اللحظات، بطاقات لوحة الإدارة): زجاج ملوّن
//   بلون القسم نفسه بالحافة المضيئة نفسها — فتبقى عائلة واحدة.
// • الرموز الصغيرة (شارات الأخبار ≤ ٤٤، رموز الحالة، بطاقات الإدارة): نفس الطبقات بلا أي blur، وتفصلها
//   خطوط مقصوصة بدل الظلال — أوضح في الحجم الصغير وأخفّ.
//
// الأداء (شرط صارم):
// • كل رسم ساكن: Canvas يُرسم مرة (خصائصه قيم بسيطة فلا يُعاد رسمه مع الأب)، والكبيرة تُجهَّز خارج الخيط الرئيسي.
// • الحركة الوحيدة المسموحة لكل مكان: «لمعة» تعبر الزجاج مرة (تحريك موضع شريط متدرّج فوق قناع ساكن)، أو ظهور
//   مرة واحدة (تكبير/شفافية) — لا TimelineView ولا إعادة رسم إطاراً إطاراً. تحميل الشجرة وحده تتكرّر لمعته
//   (تحريك موضع فقط) إحساساً بالتقدّم. «تقليل الحركة» ⇒ ساكن تماماً. «وفاة» ساكنة دائماً، رمادية، بلا ذهبي.
// • iOS 16: الأشكال تُبنى بـ CGPath.union / subtracting / intersection (متاحة منذ iOS 16).
//
// الاتجاه: الإحداثيات «عربية» — القطعة في الجهة المقابلة للعنوان (يسار بالعربية) والضوء من أعلى اليمين.
// في الإنجليزية يُعكس الرسم كله أفقياً (عدا ما له اتجاه ثابت: سهم النمو، ورموز SF داخل اللوح الزجاجي).

// MARK: - الواجهة العامة (العقد)

@MainActor
enum FT5GTrial {

    /// القطعة تغني عن الدائرة الزجاجية في المربّع — العدد ينتقل مكانها
    static let showsTileIcon = false
    /// القطعة فوق طبقة التعتيم (لا تبهت أسفل المربّع)
    static let tileArtUnderOverlay = false

    static let libraryVariantNames = ["رف الكتب", "صور العائلة", "ملف الوثائق"]
    static let projectsVariantNames = ["حقيبة العمل", "سهم النمو", "مبنى الأعمال"]

    /// (إضافة اختيارية للدمج) شكل المكتبة/المشاريع المختار في شريط التجربة — تستعمله رؤوس الصناديق
    /// والصفحات الفاضية وبطاقات الصفحات لعائلتي المكتبة والمشاريع حتى يبقى الشكل واحداً أينما ظهر.
    static var libraryVariant = 0
    static var projectsVariant = 0

    // MARK: المربّعات

    static func tile(_ place: String, variant: Int, badge: Bool, animateOnce: Bool) -> AnyView {
        guard let kind = FT5GKind.tile(place, variant: variant) else { return AnyView(EmptyView()) }
        let order: Double
        switch place {
        case "tree": order = 0
        case "diwaniya", "diwaniyas": order = 1
        case "library": order = 2
        case "projects": order = 3
        default: order = 4
        }
        // `badge`: كبسولة العدد تأخذ مكان الدائرة (أعلى جهة العنوان) — القطعة في الجهة الأخرى فلا تلتقيان
        return AnyView(FT5GArtView(kind: kind, placement: .tile,
                                   spec: .onColor(glow: FT5GPalette.tileGlow(place)),
                                   glint: animateOnce ? .once(delay: 0.4 + 0.12 * order) : .none))
    }

    // MARK: رؤوس الصناديق

    static func header(icon: String, tint: Color, deep: Color) -> AnyView {
        let kind = FT5GKind.forSymbol(icon, library: libraryVariant, projects: projectsVariant) ?? .plaque(icon)
        let still = kind == .mourning
        return AnyView(FT5GArtView(kind: kind, placement: .header,
                                   spec: .onColor(glow: nil, shadow: deep, still: still),
                                   glint: still ? .none : .once(delay: 0.45)))
    }

    // MARK: الصفحات الفاضية ورموز الحالة

    static func empty(place: String?, icon: String, tint: Color) -> AnyView {
        let kind = FT5GKind.place(place, library: libraryVariant, projects: projectsVariant)
            ?? FT5GKind.forSymbol(icon, library: libraryVariant, projects: projectsVariant) ?? .plaque(icon)
        let still = kind == .mourning
        return AnyView(FT5GArtView(kind: kind, placement: .center(0.66, dy: 0),
                                   spec: .tinted(tint, still: still))
            .frame(width: 130, height: 130))
    }

    static func stateIcon(icon: String, tint: Color, size: CGFloat = 52) -> AnyView {
        AnyView(FT5GArtView(kind: .disc(icon), placement: .center(0.94, dy: 0),
                            spec: .tinted(tint, rich: false), asyncRender: false)
            .frame(width: size, height: size))
    }

    // MARK: الأماكن

    /// شجرة الزجاج نفسها (بلون الشجرة) ولمعة تعبرها كل ٢٫٦ ث إحساساً بالتقدّم (تحريك موضع فقط)
    static func treeLoading() -> AnyView {
        AnyView(FT5GArtView(kind: .tree, placement: .center(0.76, dy: -0.01),
                            spec: .tinted(light: FT5GPalette.treeInk.light, dark: FT5GPalette.treeInk.dark),
                            glint: .loop(period: 2.6))
            .frame(width: 240, height: 200))
    }

    /// ساعة رملية زجاجية بلون الإدارة — رملها ثابت، ولمعة واحدة عند الظهور
    static func waiting() -> AnyView {
        AnyView(FT5GArtView(kind: .hourglass, placement: .center(0.72, dy: 0),
                            spec: .tinted(light: FT5GPalette.adminInk.light, dark: FT5GPalette.adminInk.dark),
                            glint: .once(delay: 0.5))
            .frame(width: 140, height: 140))
    }

    /// جرس زجاجي ساكن بكحلي الرئيسية
    static func notificationsEmpty() -> AnyView {
        AnyView(FT5GArtView(kind: .bell, placement: .center(0.70, dy: 0),
                            spec: .tinted(light: FT5GPalette.homeInk.light, dark: FT5GPalette.homeInk.dark))
            .frame(width: 120, height: 120))
    }

    /// عدسة زجاج شبه غائبة حول الشعار (حلقة رفيعة + وهج) — ساكنة
    static func loginBackdrop(logoCenterY: CGFloat) -> AnyView {
        AnyView(Canvas { ctx, size in FT5GBackdrop.draw(in: &ctx, size: size, logoCenterY: logoCenterY) }
            .allowsHitTesting(false)
            .accessibilityHidden(true))
    }

    // MARK: شارات أنواع الأخبار

    static func newsBadge(type: String, tint: Color, onColor: Bool) -> AnyView? {
        guard let kind = FT5GKind.newsType(type) else { return nil }
        let still = kind == .mourning
        let spec: FT5GSpec = onColor ? .onColor(glow: nil, still: still, rich: false, tint: tint)
                                     : .tinted(tint, rich: false, still: still)
        return AnyView(FT5GArtView(kind: kind, placement: .center(0.62, dy: 0), spec: spec, asyncRender: false))
    }

    // MARK: لحظات التنبيه

    static func moment(_ name: String, tint: Color) -> AnyView {
        AnyView(FT5GMomentView(kind: FT5GKind.moment(name), tint: tint))
    }

    // MARK: بطاقة الترحيب

    static func greetingGlyph(hour: Int, tint: Color) -> AnyView {
        AnyView(FT5GTimeGlyph(mood: FT5GTimeMood.forHour(hour), tint: tint, size: 18))
    }

    /// بلا زخرفة داخل بطاقة الترحيب (المالك أحبّها كما هي — اللمسة الوحيدة رمز الوقت الزجاجي)
    static func greetingBackground(tint: Color) -> AnyView? { nil }

    // MARK: الإضافة — الأخبار والشجرة والديوانيات وحسابي والإدارة

    /// قضيب ضوء زجاجي تحت رأس كل قسم: جوهرة زجاج في الوسط وخرزتان وقضيبان يتلاشيان نحو الطرفين.
    /// الحركة الوحيدة: القضيبان يمتدّان من الوسط مرة عند الظهور.
    static func tabHeaderOrnament(section: String, tint: Color) -> AnyView? {
        AnyView(FT5GOrnamentView(section: section))
    }

    /// قطعة الزجاج في الطرف الآخر من بطاقة الصفحة (DSPageHero) — أعلى الربع الأخير، فوق صف الأرقام. ساكنة.
    static func pageHeroArt(icon: String, tint: Color) -> AnyView? {
        let kind = FT5GKind.forSymbol(icon, library: libraryVariant, projects: projectsVariant) ?? .plaque(icon)
        return AnyView(FT5GArtView(kind: kind, placement: .hero,
                                   spec: .onColor(glow: nil, shadow: tint, still: kind == .mourning)))
    }

    /// قطعة زجاج ملوّنة صغيرة (٤٤×٤٤) لبطاقات لوحة الإدارة — تحلّ محلّ الأيقونة العادية
    static func dashTileArt(icon: String, tint: Color) -> AnyView? {
        let kind = FT5GKind.forSymbol(icon, library: libraryVariant, projects: projectsVariant) ?? .plaque(icon)
        return AnyView(FT5GArtView(kind: kind, placement: .center(0.96, dy: 0),
                                   spec: .tinted(tint, rich: false, still: kind == .mourning), asyncRender: false)
            .frame(width: 44, height: 44))
    }

    /// ورقتا خبر من زجاج بلون الأخبار (٦٠×٤٤) لرأس بطاقة «الأخبار»
    static func newsCardArt(tint: Color) -> AnyView? {
        AnyView(FT5GArtView(kind: .news, placement: .center(0.98, dy: 0),
                            spec: .tinted(tint, rich: false), asyncRender: false)
            .frame(width: 60, height: 44))
    }
}

// MARK: - القطع

nonisolated enum FT5GKind: Sendable, Equatable {
    case tree, dallah, envelope, news, megaphone
    /// المكتبة: رف الكتب · صور العائلة · ملف الوثائق
    case shelf, photos, folder
    /// المشاريع: حقيبة العمل · سهم النمو · مبنى الأعمال
    case briefcase, growth, towers
    case member, family, shield, gear, mourning
    case hourglass, bell, reminderBell, seedling, checkDisc, seal, plane
    /// شارات الأخبار
    case sheet, sparkles, rings, pram, ballot, invite
    /// النظام العام: لوح زجاج مربّع (فوقه لوح مائل) عليه رمز SF — أو قرص زجاج للرموز الصغيرة
    case plaque(String), disc(String)

    static func library(_ v: Int) -> FT5GKind { [.shelf, .photos, .folder][((v % 3) + 3) % 3] }
    static func projects(_ v: Int) -> FT5GKind { [.briefcase, .growth, .towers][((v % 3) + 3) % 3] }

    static func tile(_ place: String, variant: Int) -> FT5GKind? {
        switch place {
        case "tree": return .tree
        case "diwaniya", "diwaniyas": return .dallah
        case "library": return library(variant)
        case "projects": return projects(variant)
        case "contact": return .envelope
        case "news": return .news
        default: return nil
        }
    }

    static func place(_ place: String?, library l: Int, projects p: Int) -> FT5GKind? {
        guard let place else { return nil }
        switch place {
        case "tree", "members", "member": return .tree
        case "diwaniya", "diwaniyas": return .dallah
        case "library", "archive": return library(l)
        case "projects": return projects(p)
        case "contact", "messages": return .envelope
        case "news": return .news
        case "notifications": return .bell
        case "waiting", "pending": return .hourglass
        default: return nil
        }
    }

    /// رمز SF ← عائلة القطعة (nil = النظام العام)
    static func forSymbol(_ s: String, library l: Int, projects p: Int) -> FT5GKind? {
        func has(_ x: String) -> Bool { s.hasPrefix(x) }
        if has("heart.slash") { return .mourning }
        if has("tree") { return .tree }
        if has("person") && s.contains("badge.plus") { return .member }
        if has("figure.child") || has("person.2") || has("person.3") || has("figure.2") { return .family }
        if s.contains("shield") || has("lock") { return .shield }
        if has("map") || has("mappin") || has("cup.and.saucer") || has("tent") || has("building.columns") { return .dallah }
        if has("books") || s == "book" || has("book.fill") || has("book.closed") { return library(l) }
        if has("storefront") || has("briefcase") || has("bag") { return projects(p) }
        if has("envelope") { return .envelope }
        if has("megaphone") { return .megaphone }
        if has("newspaper") || has("doc.text") || has("square.and.pencil") || has("doc.richtext") { return .news }
        if has("gearshape") || s == "gear" || has("slider") || has("paintbrush") || has("key") || has("iphone") { return .gear }
        if has("bell") { return .bell }
        if has("hourglass") { return .hourglass }
        return nil
    }

    static func newsType(_ t: String) -> FT5GKind? {
        switch t {
        case "خبر": return .sheet
        case "إعلان": return .megaphone
        case "تهنئة": return .sparkles
        case "زواج": return .rings
        case "مولود": return .pram
        case "وفاة": return .mourning
        case "تصويت": return .ballot
        case "دعوة": return .invite
        case "تذكير": return .reminderBell
        default: return nil
        }
    }

    static func moment(_ name: String) -> FT5GKind {
        switch name {
        case "sentForApproval": return .plane
        case "approved": return .seal
        case "newMember": return .seedling
        default: return .checkDisc
        }
    }
}

/// مكان القطعة داخل إطارها (إحداثيات عربية: الجهة اليسرى)
nonisolated enum FT5GPlacement: Sendable {
    /// مربّع الرئيسية (عريض ١٨٣×١٠١ أو ضيّق ١٢٠×٩٥)
    case tile
    /// رأس الصندوق (٨٦ نقطة): وسط القطعة على بعد ٤٦ نقطة من الطرف — لا تتجاوز ٧٨ نقطة (خارج الـ٥٥٪ الوسطى)
    case header
    /// بطاقة الصفحة: أعلى الطرف الآخر، فوق صف الأرقام
    case hero
    /// في الوسط بنسبة من أصغر ضلع
    case center(CGFloat, dy: CGFloat)

    func slot(_ size: CGSize, ltr: Bool) -> CGRect {
        switch self {
        case .tile:
            let wide = size.width / max(1, size.height) >= 1.5
            if ltr {
                // الإنجليزية: العناوين أطول وتنكسر لسطرين ⇒ القطعة أصغر في الزاوية العليا المقابلة
                let s = size.height * (wide ? 0.58 : 0.50)
                return CGRect(x: 8, y: 5, width: s, height: s)
            }
            if wide {
                let s = min(size.height * 0.80, size.width * 0.46)
                return CGRect(x: size.width * 0.27 - s / 2, y: size.height * 0.5 - s / 2, width: s, height: s)
            }
            let s = min(size.height * 0.64, size.width * 0.52)
            return CGRect(x: size.width * 0.33 - s / 2, y: size.height * 0.39 - s / 2, width: s, height: s)
        case .header:
            let s = min(size.height * 0.74, 64)
            return CGRect(x: 46 - s / 2, y: size.height * 0.5 - s / 2, width: s, height: s)
        case .hero:
            if size.height < 112 {   // بلا صف أرقام: في الوسط رأسياً
                let s = min(62, size.height * 0.70)
                return CGRect(x: 20, y: (size.height - s) / 2, width: s, height: s)
            }
            let s = min(62, size.height * 0.46)
            return CGRect(x: 20, y: 13, width: s, height: s)
        case .center(let f, let dy):
            let s = min(size.width, size.height) * f
            return CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2 + dy * s, width: s, height: s)
        }
    }

    /// الموضع على الشاشة بعد العكس في الإنجليزية
    func screenSlot(_ size: CGSize, ltr: Bool) -> CGRect {
        var s = slot(size, ltr: ltr)
        if ltr { s.origin.x = size.width - s.maxX }
        return s
    }
}

nonisolated enum FT5GLook: Sendable {
    /// زجاج أبيض فوق الألوان
    case onColor
    /// زجاج ملوّن بلون القسم فوق الأسطح المحايدة
    case tinted
}

/// طريقة رسم القطعة
nonisolated struct FT5GSpec: Sendable {
    var look: FT5GLook
    /// لون الزجاج الملوّن (فاتح/داكن) — وفي `onColor` الصغير: لون الدائرة تحت الرمز (لحافة السماكة)
    var light: Color = .white
    var dark: Color = .white
    /// وهج خلف الزجاج الأبيض (nil = أبيض خافت)
    var glow: Color? = nil
    /// لون الظل تحت الزجاج الأبيض
    var shadow: Color = .black
    /// true = بالظلال الناعمة والتوهّج الداخلي (القطع الكبيرة) · false = بلا blur وبخطوط مقصوصة (الرموز الصغيرة)
    var rich = true
    /// «وفاة»: أخفت، بلا وهج ولا لمعة
    var still = false

    func tint(_ isDark: Bool) -> Color { isDark ? dark : light }

    static func onColor(glow: Color?, shadow: Color = .black, still: Bool = false, rich: Bool = true,
                        tint: Color = .clear) -> FT5GSpec {
        FT5GSpec(look: .onColor, light: tint, dark: tint, glow: glow, shadow: shadow, rich: rich, still: still)
    }

    static func tinted(_ t: Color, rich: Bool = true, still: Bool = false) -> FT5GSpec {
        FT5GSpec(look: .tinted, light: t, dark: t, rich: rich, still: still)
    }

    static func tinted(light: Color, dark: Color, rich: Bool = true) -> FT5GSpec {
        FT5GSpec(look: .tinted, light: light, dark: dark, rich: rich)
    }
}

nonisolated enum FT5GPalette {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: a)
    }

    /// وهج كل مربّع: درجة فاتحة من لونه
    static func tileGlow(_ place: String) -> Color {
        switch place {
        case "tree": return hex(0x8FE6CF)
        case "diwaniya", "diwaniyas": return hex(0x8AD9EE)
        case "library": return hex(0xE6B6F5)
        case "projects": return hex(0xA8EAB2)
        case "contact": return hex(0xC2C0FF)
        default: return hex(0xA3CCF5)
        }
    }

    static let treeInk = (light: hex(0x1E5950), dark: hex(0x6CB6A8))
    static let adminInk = (light: hex(0x47467F), dark: hex(0x9E9FDC))
    static let homeInk = (light: hex(0x1F4E79), dark: hex(0x7FA8D6))
}

// MARK: - المحرّك

nonisolated struct FT5GSolid {
    var after: Int
    var path: CGPath
    var alpha: Double
}

/// قطعة على شبكة ١٠٠×١٠٠: طبقات من الخلف إلى الأمام
nonisolated struct FT5GPiece {
    var layers: [CGPath]
    /// تعبئات مصمتة بعد طبقة معيّنة (رمل الساعة)
    var solids: [FT5GSolid] = []
    /// طبقات «زجاج صافٍ» أخفّ جسماً (زجاجتا الساعة)
    var clear: [Int] = []
    /// رمز SF يُحفر في الطبقة الأخيرة (فوق الألوان) أو يُرسم أبيض (فوق المحايد)
    var symbol: String? = nil
    var symbolBox: CGRect = .zero
    /// لا يُعكس في الإنجليزية (سهم النمو)
    var fixedOrientation = false
}

nonisolated enum FT5GEngine {

    static func render(_ kind: FT5GKind, placement: FT5GPlacement, spec: FT5GSpec,
                       in ctx: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let dark = ctx.environment.colorScheme == .dark
        let ltr = ctx.environment.layoutDirection == .leftToRight
        var c = ctx
        if ltr { c.translateBy(x: size.width, y: 0); c.scaleBy(x: -1, y: 1) }
        draw(kind, slot: placement.slot(size, ltr: ltr), spec: spec, dark: dark, mirrored: ltr, in: &c)
    }

    /// صورة ظلّية بيضاء للقطعة (قناع اللمعة)
    static func silhouette(_ kind: FT5GKind, placement: FT5GPlacement, in ctx: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let ltr = ctx.environment.layoutDirection == .leftToRight
        var c = ctx
        if ltr { c.translateBy(x: size.width, y: 0); c.scaleBy(x: -1, y: 1) }
        let piece = FT5GShapes.piece(kind)
        for p in placed(piece.layers, piece: piece, slot: placement.slot(size, ltr: ltr), mirrored: ltr) {
            c.fill(p, with: .color(.white))
        }
    }

    static func transform(_ piece: FT5GPiece, slot: CGRect, mirrored: Bool) -> CGAffineTransform {
        let k = slot.width / 100
        var m = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: slot.minX, ty: slot.minY)
        if piece.fixedOrientation && mirrored {
            m = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0).concatenating(m)
        }
        return m
    }

    static func placed(_ paths: [CGPath], piece: FT5GPiece, slot: CGRect, mirrored: Bool) -> [Path] {
        let m = transform(piece, slot: slot, mirrored: mirrored)
        return paths.map { Path($0).applying(m) }
    }

    static func draw(_ kind: FT5GKind, slot: CGRect, spec: FT5GSpec, dark: Bool, mirrored: Bool,
                     in ctx: inout GraphicsContext) {
        let piece = FT5GShapes.piece(kind)
        let m = transform(piece, slot: slot, mirrored: mirrored)
        let paths = piece.layers.map { Path($0).applying(m) }
        guard !paths.isEmpty else { return }
        let k = slot.width / 100
        var symbolRect: CGRect? = nil
        if piece.symbol != nil { symbolRect = piece.symbolBox.applying(m) }
        if spec.rich {
            drawRich(piece, paths: paths, m: m, k: k, slot: slot, spec: spec, dark: dark,
                     mirrored: mirrored, symbolRect: symbolRect, in: &ctx)
        } else {
            drawSmall(piece, paths: paths, m: m, k: k, slot: slot, spec: spec, dark: dark,
                      mirrored: mirrored, symbolRect: symbolRect, in: &ctx)
        }
    }

    // MARK: القطع الكبيرة

    static func drawRich(_ piece: FT5GPiece, paths: [Path], m: CGAffineTransform, k: CGFloat, slot: CGRect,
                         spec: FT5GSpec, dark: Bool, mirrored: Bool, symbolRect: CGRect?,
                         in ctx: inout GraphicsContext) {
        let tint = spec.tint(dark)
        let tinted = spec.look == .tinted

        // ١) وهج ناعم خلف القطعة (تدرّج شعاعي، بلا blur)
        if !spec.still {
            let center = CGPoint(x: slot.midX, y: slot.midY + slot.height * 0.04)
            let gr = slot.width * (tinted ? 0.74 : 0.80)
            let stops: [Gradient.Stop]
            if tinted {
                stops = [.init(color: tint.opacity(dark ? 0.26 : 0.17), location: 0),
                         .init(color: tint.opacity(dark ? 0.10 : 0.06), location: 0.55),
                         .init(color: tint.opacity(0), location: 1)]
            } else if let g = spec.glow {
                stops = [.init(color: g.opacity(dark ? 0.55 : 0.62), location: 0),
                         .init(color: g.opacity(dark ? 0.20 : 0.24), location: 0.5),
                         .init(color: g.opacity(0), location: 1)]
            } else {
                stops = [.init(color: .white.opacity(dark ? 0.16 : 0.22), location: 0),
                         .init(color: .white.opacity(dark ? 0.06 : 0.08), location: 0.5),
                         .init(color: .white.opacity(0), location: 1)]
            }
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - gr, y: center.y - gr, width: gr * 2, height: gr * 2)),
                     with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: gr))
        }

        // ٢) ظل القطعة كلها على الخلفية (خارجها فقط)
        if tinted {
            outerShadow(&ctx, paths, color: dark ? .black : tint, dy: 4 * k, blur: 5.5 * k,
                        opacity: dark ? 0.75 : (spec.still ? 0.18 : 0.30))
        } else {
            outerShadow(&ctx, paths, color: spec.shadow, dy: 3.2 * k, blur: 4.5 * k,
                        opacity: spec.still ? 0.22 : (dark ? 0.40 : 0.32))
        }

        // ٣) الطبقات
        let last = paths.count - 1
        for (i, p) in paths.enumerated() {
            if i > 0 {
                outerShadow(&ctx, [p], color: tinted ? .black : spec.shadow, dy: 1.6 * k, blur: 2.2 * k,
                            opacity: tinted ? 0.14 : 0.18)
            }
            let clear = piece.clear.contains(i)
            richLayer(&ctx, p, k: k, slot: slot, spec: spec, dark: dark, clear: clear)
            if i == last, let name = piece.symbol, let r = symbolRect, !tinted {
                // فوق الألوان: الرمز منقوش بلون الرأس الغامق على اللوح الزجاجي المصقول
                symbol(name, in: &ctx, rect: r, color: spec.shadow.opacity(spec.still ? 0.6 : 0.82), mirrored: mirrored)
            }
            for s in piece.solids where s.after == i {
                solid(&ctx, Path(s.path).applying(m), alpha: s.alpha, spec: spec, dark: dark, k: k)
            }
        }
        if tinted, let name = piece.symbol, let r = symbolRect {
            var sh = ctx
            sh.opacity = 0.35
            sh.translateBy(x: 0, y: 0.8 * k)
            symbol(name, in: &sh, rect: r, color: .black.opacity(0.5), mirrored: mirrored)
            symbol(name, in: &ctx, rect: r, color: .white, mirrored: mirrored)
        }

        // ٤) انعكاس ساكن: شريط ضوء مائل خافت على القطعة كلها
        var u = paths[0].cgPath
        for p in paths.dropFirst() { u = u.union(p.cgPath) }
        var c = ctx
        c.clip(to: Path(u))
        let w = slot.width
        var band = Path()
        band.move(to: CGPoint(x: slot.minX + w * 0.40, y: slot.minY - w * 0.1))
        band.addLine(to: CGPoint(x: slot.minX + w * 0.70, y: slot.minY - w * 0.1))
        band.addLine(to: CGPoint(x: slot.minX + w * 0.30, y: slot.maxY + w * 0.1))
        band.addLine(to: CGPoint(x: slot.minX + w * 0.00, y: slot.maxY + w * 0.1))
        band.closeSubpath()
        let bandA = spec.still ? 0.08 : (tinted ? 0.16 : 0.18)
        c.fill(band, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(bandA), location: 0.5),
            .init(color: .white.opacity(0), location: 1)
        ]), startPoint: CGPoint(x: slot.minX + w * 0.12, y: slot.midY),
            endPoint: CGPoint(x: slot.minX + w * 0.58, y: slot.midY)))
    }

    /// طبقة زجاج واحدة (كبيرة): جسم متدرّج + ضوء نافذ + سماكة مضيئة + لمعة سطحية + حافة ضوء حادة
    static func richLayer(_ ctx: inout GraphicsContext, _ p: Path, k: CGFloat, slot: CGRect, spec: FT5GSpec,
                          dark: Bool, clear: Bool) {
        let lit = CGPoint(x: slot.maxX, y: slot.minY)
        let shade = CGPoint(x: slot.minX, y: slot.maxY)
        let b = p.boundingRect
        let tint = spec.tint(dark)
        let tinted = spec.look == .tinted
        let a: Double = spec.still ? 0.78 : (dark ? 0.92 : 1)
        let body: Double = clear ? 0.45 : 1

        if tinted {
            ctx.fill(p, with: .linearGradient(Gradient(stops: [
                .init(color: tint.opacity((dark ? 0.46 : 0.42) * body), location: 0),
                .init(color: tint.opacity((dark ? 0.66 : 0.70) * body), location: 0.5),
                .init(color: tint.opacity((dark ? 0.84 : 0.90) * body), location: 1)
            ]), startPoint: lit, endPoint: shade))
        } else {
            ctx.fill(p, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(0.56 * a * body), location: 0),
                .init(color: .white.opacity(0.27 * a * body), location: 0.5),
                .init(color: .white.opacity(0.12 * a * body), location: 1)
            ]), startPoint: lit, endPoint: shade))
            // ضوء ملوّن نافذ يتجمّع في أسفل القطعة
            let g = spec.still ? Color.white.opacity(0.10) : (spec.glow ?? Color.white.opacity(0.42))
            ctx.fill(p, with: .linearGradient(Gradient(colors: [g.opacity(0), g.opacity(0.42 * a * body)]),
                                              startPoint: CGPoint(x: b.midX, y: b.minY + b.height * 0.30),
                                              endPoint: CGPoint(x: b.midX, y: b.maxY)))
        }

        var c = ctx
        c.clip(to: p)
        let e: Double = tinted ? (dark ? 0.55 : 0.85) : 1
        // سماكة الزجاج: توهّج أبيض ناعم ملاصق للحواف من الداخل
        c.drawLayer { l in
            l.addFilter(.blur(radius: 2.4 * k))
            l.stroke(p, with: .color(.white.opacity(0.60 * a * e)), lineWidth: 4.2 * k)
        }
        // لمعة سطحية واسعة نحو الضوء
        let sc = CGPoint(x: b.maxX - b.width * 0.26, y: b.minY + b.height * 0.16)
        let sr = max(b.width, b.height) * 0.62
        c.fill(Path(b.insetBy(dx: -2, dy: -2)), with: .radialGradient(
            Gradient(colors: [.white.opacity((tinted ? 0.34 : 0.30) * a * e), .white.opacity(0)]),
            center: sc, startRadius: 0, endRadius: sr))
        // حافة الضوء: ساطعة جهة الضوء، أخفت في الوسط، وانعكاس ثانٍ في الجهة المقابلة
        c.stroke(p, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(1.0 * a), location: 0),
            .init(color: .white.opacity(0.72 * a * e), location: 0.32),
            .init(color: .white.opacity(0.24 * a * e), location: 0.62),
            .init(color: .white.opacity(0.66 * a * e), location: 1)
        ]), startPoint: lit, endPoint: shade), lineWidth: 2.6 * k)
        // بريق الحافة قرب زاوية الضوء
        let gp = CGPoint(x: b.maxX - b.width * 0.12, y: b.minY + b.height * 0.06)
        c.stroke(p, with: .radialGradient(Gradient(colors: [.white.opacity(0.95 * a), .white.opacity(0)]),
                                          center: gp, startRadius: 0, endRadius: max(b.width, b.height) * 0.42),
                 lineWidth: 4.4 * k)
    }

    /// تعبئة مصمتة (رمل الساعة): أبيض فوق الألوان، لون القسم فوق المحايد — بحافة ضوء علوية
    static func solid(_ ctx: inout GraphicsContext, _ p: Path, alpha: Double, spec: FT5GSpec, dark: Bool, k: CGFloat) {
        let color: Color = spec.look == .tinted ? spec.tint(dark) : .white
        let b = p.boundingRect
        ctx.fill(p, with: .linearGradient(Gradient(colors: [color.opacity(alpha * 0.85), color.opacity(alpha)]),
                                          startPoint: CGPoint(x: b.midX, y: b.minY), endPoint: CGPoint(x: b.midX, y: b.maxY)))
    }

    // MARK: الرموز الصغيرة (بلا blur)

    static func drawSmall(_ piece: FT5GPiece, paths: [Path], m: CGAffineTransform, k: CGFloat, slot: CGRect,
                          spec: FT5GSpec, dark: Bool, mirrored: Bool, symbolRect: CGRect?,
                          in ctx: inout GraphicsContext) {
        let cut = max(1.0, 3.2 * k)
        let tinted = spec.look == .tinted
        ctx.drawLayer { l in
            for (i, p) in paths.enumerated() {
                if i > 0 {
                    // خط مقصوص حول الطبقة الأمامية يفصلها عمّا خلفها (يظهر لون الخلفية)
                    var e = l
                    e.blendMode = .destinationOut
                    e.stroke(p, with: .color(.black), lineWidth: cut)
                }
                smallLayer(&l, p, k: k, slot: slot, spec: spec, dark: dark, clear: piece.clear.contains(i))
                for s in piece.solids where s.after == i {
                    solid(&l, Path(s.path).applying(m), alpha: s.alpha, spec: spec, dark: dark, k: k)
                }
            }
            if let name = piece.symbol, let r = symbolRect {
                if tinted {
                    symbol(name, in: &l, rect: r, color: .white, mirrored: mirrored)
                } else {
                    symbol(name, in: &l, rect: r, color: spec.shadow.opacity(0.82), mirrored: mirrored)
                }
            }
        }
    }

    static func smallLayer(_ ctx: inout GraphicsContext, _ p: Path, k: CGFloat, slot: CGRect, spec: FT5GSpec,
                           dark: Bool, clear: Bool) {
        let lit = CGPoint(x: slot.maxX, y: slot.minY)
        let shade = CGPoint(x: slot.minX, y: slot.maxY)
        let b = p.boundingRect
        let tint = spec.tint(dark)
        let body: Double = clear ? 0.5 : 1
        let rim = max(1.1, 4.4 * k)
        if spec.look == .tinted {
            let a: Double = spec.still ? 0.85 : 1
            ctx.fill(p, with: .linearGradient(Gradient(stops: [
                .init(color: tint.opacity(0.66 * body * a), location: 0),
                .init(color: tint.opacity(0.84 * body * a), location: 0.5),
                .init(color: tint.opacity(1.0 * body * a), location: 1)
            ]), startPoint: lit, endPoint: shade))
            var c = ctx
            c.clip(to: p)
            c.fill(Path(b.insetBy(dx: -1, dy: -1)), with: .radialGradient(
                Gradient(colors: [.white.opacity(dark ? 0.30 : 0.42), .white.opacity(0)]),
                center: CGPoint(x: b.maxX - b.width * 0.22, y: b.minY + b.height * 0.14),
                startRadius: 0, endRadius: max(b.width, b.height) * 0.6))
            c.stroke(p, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(0.95), location: 0),
                .init(color: .white.opacity(0.40), location: 0.40),
                .init(color: .white.opacity(0.0), location: 0.70),
                .init(color: .white.opacity(0.22), location: 1)
            ]), startPoint: lit, endPoint: shade), lineWidth: rim)
        } else {
            let a: Double = spec.still ? 0.86 : 1
            ctx.fill(p, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(0.98 * a * body), location: 0),
                .init(color: .white.opacity(0.80 * a * body), location: 0.55),
                .init(color: .white.opacity(0.64 * a * body), location: 1)
            ]), startPoint: lit, endPoint: shade))
            var c = ctx
            c.clip(to: p)
            // سماكة: حافة ساطعة جهة الضوء، ومسحة من لون الدائرة في الجهة المقابلة
            c.stroke(p, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(1.0), location: 0),
                .init(color: .white.opacity(0.0), location: 0.5),
                .init(color: tint.opacity(0.30), location: 1)
            ]), startPoint: lit, endPoint: shade), lineWidth: rim)
        }
    }

    // MARK: أدوات

    /// ظل ناعم خارج الأشكال فقط
    static func outerShadow(_ ctx: inout GraphicsContext, _ paths: [Path], color: Color, dy: CGFloat, blur: CGFloat,
                            opacity: Double) {
        ctx.drawLayer { l in
            var sh = l
            sh.opacity = opacity
            sh.addFilter(.blur(radius: blur))
            sh.drawLayer { s in
                s.translateBy(x: -dy * 0.35, y: dy)
                for p in paths { s.fill(p, with: .color(color)) }
            }
            l.blendMode = .destinationOut
            for p in paths { l.fill(p, with: .color(.black)) }
        }
    }

    /// رمز SF مضبوط داخل مستطيل (لا يُعكس نصّه في الإنجليزية)
    static func symbol(_ name: String, in ctx: inout GraphicsContext, rect: CGRect, color: Color, mirrored: Bool) {
        var c = ctx
        c.translateBy(x: rect.midX, y: rect.midY)
        if mirrored { c.scaleBy(x: -1, y: 1) }
        let base: CGFloat = 40
        let text = c.resolve(Text(Image(systemName: name)).font(.system(size: base, weight: .bold)).foregroundColor(color))
        let ms = text.measure(in: CGSize(width: 1000, height: 1000))
        guard ms.width > 0, ms.height > 0 else { return }
        let f = min(rect.width / ms.width, rect.height / ms.height)
        c.scaleBy(x: f, y: f)
        c.draw(text, at: .zero, anchor: .center)
    }
}

// MARK: - الأشكال (شبكة ١٠٠×١٠٠، إحداثيات عربية، من الخلف إلى الأمام)

nonisolated enum FT5GGeo {
    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil)
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil)
    }

    static func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        let rr = max(0, min(r, w / 2, h / 2))
        return CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: rr, cornerHeight: rr, transform: nil)
    }

    static func path(_ build: (CGMutablePath) -> Void) -> CGPath {
        let m = CGMutablePath()
        build(m)
        return m
    }

    static func stroke(_ p: CGPath, _ w: CGFloat) -> CGPath {
        p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    static func line(_ pts: [CGPoint], _ w: CGFloat) -> CGPath {
        stroke(path { m in m.addLines(between: pts) }, w)
    }

    static func rotate(_ p: CGPath, _ deg: CGFloat, _ cx: CGFloat, _ cy: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: deg * .pi / 180).translatedBy(x: -cx, y: -cy)
        return p.copy(using: &t) ?? p
    }

    static func mirror(_ p: CGPath, around x: CGFloat = 50) -> CGPath {
        var m = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * x, ty: 0)
        return p.copy(using: &m) ?? p
    }

    static func union(_ ps: [CGPath]) -> CGPath {
        guard var u = ps.first else { return CGMutablePath() }
        for q in ps.dropFirst() { u = u.union(q) }
        return u
    }

    /// مضلّع بزوايا مدوّرة
    static func poly(_ pts: [CGPoint], r: CGFloat) -> CGPath {
        let m = CGMutablePath()
        let n = pts.count
        guard n > 2 else { return m }
        let last = pts[n - 1], first = pts[0]
        m.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in 0..<n { m.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: r) }
        m.closeSubpath()
        return m
    }

    /// ورقة: من القاعدة إلى الطرف، عرضها في الوسط ≈ width
    static func leaf(_ a: CGPoint, _ b: CGPoint, width w: CGFloat) -> CGPath {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / len, ny = dx / len
        let c1 = CGPoint(x: a.x + dx * 0.45 + nx * w, y: a.y + dy * 0.45 + ny * w)
        let c2 = CGPoint(x: a.x + dx * 0.55 - nx * w, y: a.y + dy * 0.55 - ny * w)
        return path { m in
            m.move(to: a)
            m.addQuadCurve(to: b, control: c1)
            m.addQuadCurve(to: a, control: c2)
            m.closeSubpath()
        }
    }

    /// نجمة بريق رباعية بأضلاع مقعّرة
    static func star4(_ c: CGPoint, _ r: CGFloat, pinch: CGFloat) -> CGPath {
        let pts = [p(c.x, c.y - r), p(c.x + r, c.y), p(c.x, c.y + r), p(c.x - r, c.y)]
        return path { m in
            m.move(to: pts[0])
            for i in 0..<4 {
                let a = pts[i], b = pts[(i + 1) % 4]
                let ctrl = p(c.x + (a.x - c.x + b.x - c.x) * pinch, c.y + (a.y - c.y + b.y - c.y) * pinch)
                m.addQuadCurve(to: b, control: ctrl)
            }
            m.closeSubpath()
        }
    }

    static func star5(_ c: CGPoint, _ r: CGFloat, _ ri: CGFloat, round: CGFloat = 1) -> CGPath {
        var pts: [CGPoint] = []
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let rr = i % 2 == 0 ? r : ri
            pts.append(p(c.x + cos(a) * rr, c.y + sin(a) * rr))
        }
        return poly(pts, r: round)
    }

    static func gear(_ c: CGPoint, body: CGFloat, tip: CGFloat, teeth n: Int, toothW: CGFloat, hole: CGFloat,
                     phase: CGFloat = 0) -> CGPath {
        var g: CGPath = circle(c.x, c.y, body)
        for i in 0..<n {
            let a = phase + CGFloat(i) * 2 * .pi / CGFloat(n)
            let tooth = rrect(-toothW / 2, -tip, toothW, tip - body + 3, min(2.6, toothW * 0.3))
            var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a)
            if let tt = tooth.copy(using: &t) { g = g.union(tt) }
        }
        return g.subtracting(circle(c.x, c.y, hole))
    }
}

nonisolated enum FT5GShapes {
    private typealias G = FT5GGeo

    static func piece(_ kind: FT5GKind) -> FT5GPiece {
        switch kind {
        case .tree: return FT5GPiece(layers: tree())
        case .dallah: return FT5GPiece(layers: dallah())
        case .envelope: return FT5GPiece(layers: envelope())
        case .news: return FT5GPiece(layers: news())
        case .megaphone: return megaphone()
        case .shelf: return shelf()
        case .photos: return photos()
        case .folder: return folder()
        case .briefcase: return briefcase()
        case .growth: return growth()
        case .towers: return towers()
        case .member: return member()
        case .family: return family()
        case .shield: return shield()
        case .gear: return gearPiece()
        case .mourning: return mourning()
        case .hourglass: return hourglass()
        case .bell: return bell(dot: false)
        case .reminderBell: return bell(dot: true)
        case .seedling: return seedling()
        case .checkDisc: return checkDisc()
        case .seal: return seal()
        case .plane: return plane()
        case .sheet: return sheet()
        case .sparkles: return sparkles()
        case .rings: return rings()
        case .pram: return pram()
        case .ballot: return ballot()
        case .invite: return invite()
        case .plaque(let s): return plaque(s)
        case .disc(let s): return disc(s)
        }
    }

    // MARK: من الجولة الرابعة (أبقاها المالك)

    /// شجرة العائلة: تاج مستدير وأمامه جذع بفرعين
    static func tree() -> [CGPath] {
        let lobes: [CGPath] = [G.circle(50, 27, 22), G.circle(30.5, 38, 17), G.circle(69.5, 38, 17),
                               G.circle(36, 54, 17), G.circle(64, 54, 17), G.circle(50, 46, 20)]
        let crown = G.union(lobes)
        let trunk = CGMutablePath()
        trunk.move(to: G.p(42, 97))
        trunk.addQuadCurve(to: G.p(47.4, 85), control: G.p(47, 94.5))
        trunk.addLine(to: G.p(47.7, 67))
        trunk.addCurve(to: G.p(36.5, 54.5), control1: G.p(46.5, 61.5), control2: G.p(41.5, 57.5))
        trunk.addQuadCurve(to: G.p(39.6, 51.2), control: G.p(36.4, 51.0))
        trunk.addCurve(to: G.p(50, 60), control1: G.p(44, 54), control2: G.p(48.3, 56.5))
        trunk.addCurve(to: G.p(60.4, 48.2), control1: G.p(51.7, 55.5), control2: G.p(56, 51))
        trunk.addQuadCurve(to: G.p(63.5, 51.5), control: G.p(63.6, 48.0))
        trunk.addCurve(to: G.p(52.3, 67), control1: G.p(58.5, 55), control2: G.p(53.5, 60.5))
        trunk.addLine(to: G.p(52.6, 85))
        trunk.addQuadCurve(to: G.p(58, 97), control: G.p(53, 94.5))
        trunk.closeSubpath()
        return [crown, trunk]
    }

    /// دلّة: الجسم والمقبض والمنقار قطعة واحدة، والغطاء طبقة أمامية
    static func dallah() -> [CGPath] {
        let ax: CGFloat = 40
        typealias Seg = (c1: CGPoint, c2: CGPoint, to: CGPoint)
        let start = G.p(15, 96)
        let segs: [Seg] = [
            (G.p(16, 94), G.p(14, 92), G.p(12.5, 91)),
            (G.p(21, 88), G.p(25, 78), G.p(22, 69)),
            (G.p(19.5, 61), G.p(10, 58), G.p(8.2, 52)),
            (G.p(7, 48), G.p(9, 45), G.p(13.5, 41.5)),
            (G.p(14.5, 40.6), G.p(14.5, 39.4), G.p(12.5, 39))
        ]
        func half(_ p: CGMutablePath, sign: CGFloat, reverse: Bool) {
            let tx: (CGPoint) -> CGPoint = { CGPoint(x: ax + sign * $0.x, y: $0.y) }
            if !reverse {
                p.addLine(to: tx(start))
                for s in segs { p.addCurve(to: tx(s.to), control1: tx(s.c1), control2: tx(s.c2)) }
            } else {
                var pts: [CGPoint] = [start]
                for s in segs { pts.append(s.to) }
                for i in stride(from: segs.count - 1, through: 0, by: -1) {
                    let s = segs[i]
                    p.addCurve(to: tx(pts[i]), control1: tx(s.c2), control2: tx(s.c1))
                }
            }
        }
        let body = CGMutablePath()
        body.move(to: G.p(ax, 96))
        half(body, sign: 1, reverse: false)
        body.addLine(to: G.p(ax - 12.5, 39))
        half(body, sign: -1, reverse: true)
        body.closeSubpath()

        let spout = CGMutablePath()
        spout.move(to: G.p(52, 90))
        spout.addCurve(to: G.p(78, 64), control1: G.p(66, 89), control2: G.p(75, 79))
        spout.addCurve(to: G.p(87, 36), control1: G.p(80.5, 53), control2: G.p(82, 43))
        spout.addCurve(to: G.p(96.5, 27.5), control1: G.p(90, 32), control2: G.p(94, 30))
        spout.addQuadCurve(to: G.p(95, 24.6), control: G.p(98.6, 25.4))
        spout.addCurve(to: G.p(80.5, 30), control1: G.p(90, 24.6), control2: G.p(84, 26.5))
        spout.addCurve(to: G.p(70, 58), control1: G.p(76, 38), control2: G.p(73.5, 49))
        spout.addCurve(to: G.p(54, 70), control1: G.p(67.5, 64.5), control2: G.p(61, 69))
        spout.closeSubpath()

        let handleLine = CGMutablePath()
        handleLine.move(to: G.p(ax - 10, 45))
        handleLine.addCurve(to: G.p(13, 62), control1: G.p(18, 43), control2: G.p(10.5, 52))
        handleLine.addCurve(to: G.p(ax - 20.5, 76), control1: G.p(15, 69.5), control2: G.p(18, 74))
        let handle = G.stroke(handleLine, 5.4)
        let main = body.union(spout).union(handle)

        let lid = CGMutablePath()
        lid.move(to: G.p(ax - 10.5, 41.5))
        lid.addCurve(to: G.p(ax - 2.6, 22), control1: G.p(ax - 10.5, 33), control2: G.p(ax - 6, 25.5))
        lid.addLine(to: G.p(ax + 2.6, 22))
        lid.addCurve(to: G.p(ax + 10.5, 41.5), control1: G.p(ax + 6, 25.5), control2: G.p(ax + 10.5, 33))
        lid.closeSubpath()
        let finial = CGMutablePath()
        finial.move(to: G.p(ax, 9))
        finial.addCurve(to: G.p(ax + 3.6, 18.5), control1: G.p(ax + 1.2, 12.5), control2: G.p(ax + 3.6, 15))
        finial.addCurve(to: G.p(ax, 23.5), control1: G.p(ax + 3.6, 21.5), control2: G.p(ax + 2, 23.5))
        finial.addCurve(to: G.p(ax - 3.6, 18.5), control1: G.p(ax - 2, 23.5), control2: G.p(ax - 3.6, 21.5))
        finial.addCurve(to: G.p(ax, 9), control1: G.p(ax - 3.6, 15), control2: G.p(ax - 1.2, 12.5))
        finial.closeSubpath()
        return [main, lid.union(finial)]
    }

    /// ظرف: الجسم، ثم الجيب السفلي، ثم اللسان العلوي
    static func envelope() -> [CGPath] {
        let r = CGRect(x: 4, y: 20, width: 92, height: 62)
        let body = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
        let pocket = G.poly([G.p(r.minX + 1.5, r.maxY - 1.5), G.p(50, 49), G.p(r.maxX - 1.5, r.maxY - 1.5)], r: 6)
        let flap = G.poly([G.p(r.minX + 1.5, r.minY + 1.5), G.p(r.maxX - 1.5, r.minY + 1.5), G.p(50, 59)], r: 6)
        return [body, pocket.intersection(body), flap.intersection(body)]
    }

    /// خبر: ورقتان — الخلفية مائلة، والأمامية بزاوية مطويّة وأسطر محفورة (محاذاة عربية)
    static func news() -> [CGPath] {
        let back = G.rotate(G.rrect(22, 14, 56, 72, 7), -12, 50, 50)
        let sheet = G.poly([G.p(26, 15), G.p(64, 15), G.p(80, 31), G.p(80, 90), G.p(26, 90)], r: 6)
        let fold = G.poly([G.p(64, 15), G.p(64, 31), G.p(80, 31)], r: 2.5)
        let lines = G.union([G.rrect(34, 42, 30, 6, 3), G.rrect(34, 56, 38, 4, 2),
                             G.rrect(34, 67, 38, 4, 2), G.rrect(34, 78, 24, 4, 2)])
        return [back, sheet.subtracting(fold).subtracting(lines), fold]
    }

    // MARK: المكتبة (ثلاثة أشكال جديدة)

    /// ١) رف الكتب: ثلاثة كتب قائمة بأطوال مختلفة ورابع مائل يستند إليها، فوق لوح الرف
    static func shelf() -> FT5GPiece {
        func book(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
            let b = G.rrect(x, y, w, h, 3.4)
            let lw = w - 7.5
            let bands = G.union([G.rrect(x + 3.75, y + 7, lw, 3, 1.5), G.rrect(x + 3.75, y + h - 13, lw, 3, 1.5)])
            return b.subtracting(bands)
        }
        let a = book(8, 26, 17, 58)
        let b = book(28, 40, 15, 44)
        let c = book(46, 14, 20, 70)
        let d = G.rotate(book(74, 33, 15, 51), -15, 89, 84)
        let board = G.rrect(3, 82, 94, 10, 5)
        return FT5GPiece(layers: [a, b, c, d, board])
    }

    /// ٢) صور العائلة: صورتان متراكبتان، الأمامية بإطار عريض من أسفل وفيها جبل وشمس
    static func photos() -> FT5GPiece {
        let back = G.rotate(G.rrect(20, 12, 62, 52, 6), 10, 51, 38)
        let frameR = G.rrect(12, 30, 72, 62, 6.5)
        let window = G.rrect(19.5, 37.5, 57, 39, 3.5)
        let front = G.rotate(frameR.subtracting(window), -5, 48, 61)
        let hills = G.poly([G.p(17, 82), G.p(36, 56), G.p(48, 69), G.p(57, 59), G.p(80, 82)], r: 3)
        let sun = G.circle(64, 48, 6.5)
        let scene = G.rotate(hills.union(sun).intersection(window), -5, 48, 61)
        return FT5GPiece(layers: [back, front, scene])
    }

    /// ٣) ملف الوثائق: ملف بلسان، تخرج منه ورقة مسطّرة، وجيبه الأمامي ببطاقة اسم
    static func folder() -> FT5GPiece {
        let back = G.union([G.rrect(5, 24, 90, 66, 7), G.rrect(5, 15, 34, 18, 6),
                            G.poly([G.p(28, 15), G.p(38, 15), G.p(48, 26), G.p(28, 26)], r: 3)])
        let lines = G.union([G.rrect(30, 19, 34, 4, 2), G.rrect(30, 27, 40, 3.4, 1.7)])
        let paper = G.rotate(G.rrect(20, 9, 60, 50, 4).subtracting(lines), 4, 50, 34)
        let pocket = G.rrect(5, 40, 90, 50, 7).subtracting(G.rrect(37, 56, 26, 7, 3.5))
        return FT5GPiece(layers: [back, paper, pocket])
    }

    // MARK: المشاريع (ثلاثة أشكال جديدة)

    /// ١) حقيبة العمل: الجسم والمقبض، والغطاء العلوي طبقة، والقفل في الأمام
    static func briefcase() -> FT5GPiece {
        let handle = G.stroke(G.path { m in
            m.move(to: G.p(36, 31)); m.addLine(to: G.p(36, 23))
            m.addQuadCurve(to: G.p(43, 16), control: G.p(36, 16))
            m.addLine(to: G.p(57, 16))
            m.addQuadCurve(to: G.p(64, 23), control: G.p(64, 16))
            m.addLine(to: G.p(64, 31))
        }, 6)
        let body = G.rrect(5, 28, 90, 62, 10).union(handle)
        let lid = G.path { m in
            m.move(to: G.p(15, 28)); m.addLine(to: G.p(85, 28))
            m.addQuadCurve(to: G.p(95, 38), control: G.p(95, 28))
            m.addLine(to: G.p(95, 56)); m.addLine(to: G.p(5, 56)); m.addLine(to: G.p(5, 38))
            m.addQuadCurve(to: G.p(15, 28), control: G.p(5, 28))
            m.closeSubpath()
        }
        let clasp = G.rrect(40.5, 49, 19, 15, 4)
        return FT5GPiece(layers: [body, lid, clasp])
    }

    /// ٢) سهم النمو: ثلاثة أعمدة تصعد وسهم يرتفع فوقها (يصعد يميناً في اللغتين)
    static func growth() -> FT5GPiece {
        let bars = G.union([G.rrect(8, 64, 20, 28, 4.5), G.rrect(35, 50, 20, 42, 4.5), G.rrect(62, 33, 20, 59, 4.5)])
        let a = G.p(49, 46), b = G.p(80, 17)
        let dx = b.x - a.x, dy = b.y - a.y, len = (dx * dx + dy * dy).squareRoot()
        let ux = dx / len, uy = dy / len, nx = -uy, ny = ux
        let tip = G.p(b.x + ux * 12, b.y + uy * 12)
        let base = G.p(b.x - ux * 3, b.y - uy * 3)
        let head = G.poly([tip, G.p(base.x + nx * 11, base.y + ny * 11), G.p(base.x - nx * 11, base.y - ny * 11)], r: 2.4)
        let shaft = G.line([G.p(7, 56), G.p(31, 35), a, b], 8)
        return FT5GPiece(layers: [bars, shaft.union(head)], fixedOrientation: true)
    }

    /// ٣) مبنى الأعمال: برج زجاجي عالٍ بنوافذ شريطية، وأمامه مبنى أقصر بنوافذ وباب
    static func towers() -> FT5GPiece {
        var backWin: [CGPath] = []
        for row in 0..<6 { for col in 0..<2 {
            backWin.append(G.rrect(54 + CGFloat(col) * 14, 16 + CGFloat(row) * 11, 10, 5.5, 2))
        } }
        let back = G.rrect(48, 7, 38, 85, 5).subtracting(G.union(backWin))
        var frontWin: [CGPath] = []
        for row in 0..<2 { for col in 0..<2 {
            frontWin.append(G.rrect(19 + CGFloat(col) * 16, 49 + CGFloat(row) * 11, 12, 6, 2))
        } }
        frontWin.append(G.rrect(27, 74, 12, 24, 3))
        let front = G.rrect(12, 40, 42, 52, 5).subtracting(G.union(frontWin))
        return FT5GPiece(layers: [back, front])
    }

    // MARK: عائلات الرؤوس

    /// مكبّر صوت يتّجه للخارج (يسار بالعربية)
    static func megaphone() -> FT5GPiece {
        let cone = G.poly([G.p(18, 16), G.p(70, 37), G.p(70, 63), G.p(18, 84)], r: 4)
        let rear = G.rrect(66, 36, 22, 28, 7)
        let grip = G.rrect(71, 58, 12, 24, 4.5)
        let mouth = CGPath(ellipseIn: CGRect(x: 8, y: 12, width: 20, height: 76), transform: nil)
        return FT5GPiece(layers: [G.union([cone, rear, grip]), mouth])
    }

    /// عضو جديد: شخص وأمامه قرص بعلامة +
    static func member() -> FT5GPiece {
        let clip = G.rect(0, 0, 100, 92)
        let person = G.circle(40, 29, 17).union(G.rrect(10, 53, 60, 70, 30).intersection(clip))
        let plus = G.union([G.rrect(64, 68.5, 18, 5.5, 2.75), G.rrect(70.25, 62.25, 5.5, 18, 2.75)])
        let disc = G.circle(73, 71.5, 19).subtracting(plus)
        return FT5GPiece(layers: [person, disc])
    }

    /// العائلة: كبير وصغير
    static func family() -> FT5GPiece {
        let clip = G.rect(0, 0, 100, 92)
        let adult = G.circle(37, 27, 16).union(G.rrect(9, 50, 56, 70, 28).intersection(clip))
        let child = G.circle(72, 50, 12).union(G.rrect(51, 66, 42, 50, 21).intersection(clip))
        return FT5GPiece(layers: [adult, child])
    }

    /// الأمان: درع وأمامه علامة صح
    static func shield() -> FT5GPiece {
        let s = G.path { m in
            m.move(to: G.p(50, 6))
            m.addCurve(to: G.p(86, 18), control1: G.p(61, 13), control2: G.p(73, 17))
            m.addLine(to: G.p(86, 45))
            m.addCurve(to: G.p(50, 95), control1: G.p(86, 69), control2: G.p(71, 85))
            m.addCurve(to: G.p(14, 45), control1: G.p(29, 85), control2: G.p(14, 69))
            m.addLine(to: G.p(14, 18))
            m.addCurve(to: G.p(50, 6), control1: G.p(27, 17), control2: G.p(39, 13))
            m.closeSubpath()
        }
        let check = G.line([G.p(32, 50), G.p(45, 63), G.p(69, 36)], 9.5)
        return FT5GPiece(layers: [s, check])
    }

    /// الإعدادات: ترسان، كبير وصغير
    static func gearPiece() -> FT5GPiece {
        let big = G.gear(G.p(40, 42), body: 25, tip: 36, teeth: 8, toothW: 12, hole: 10, phase: .pi / 8)
        let small = G.gear(G.p(74, 74), body: 13, tip: 20.5, teeth: 6, toothW: 8, hole: 5)
        return FT5GPiece(layers: [big, small])
    }

    /// «وفاة»: هلال ونجمة — ساكنان، رماديان
    static func mourning() -> FT5GPiece {
        let crescent = G.circle(46, 52, 36).subtracting(G.circle(62, 42, 30))
        let star = G.star5(G.p(75, 47), 10.5, 4.6, round: 1.2)
        return FT5GPiece(layers: [crescent, star])
    }

    // MARK: الأماكن

    /// ساعة رملية: زجاجتان صافيتان، ورمل مصمت، وإطار بلوحين وعمودين في الأمام
    static func hourglass() -> FT5GPiece {
        let bulbs = G.path { m in
            m.move(to: G.p(31, 16)); m.addLine(to: G.p(69, 16))
            m.addCurve(to: G.p(53.4, 50), control1: G.p(69, 35), control2: G.p(56.5, 42))
            m.addCurve(to: G.p(69, 84), control1: G.p(56.5, 58), control2: G.p(69, 65))
            m.addLine(to: G.p(31, 84))
            m.addCurve(to: G.p(46.6, 50), control1: G.p(31, 65), control2: G.p(43.5, 58))
            m.addCurve(to: G.p(31, 16), control1: G.p(43.5, 42), control2: G.p(31, 35))
            m.closeSubpath()
        }
        let frame = G.union([G.rrect(16, 6, 68, 11, 5.5), G.rrect(16, 83, 68, 11, 5.5),
                             G.rrect(20, 14, 5.5, 72, 2.75), G.rrect(74.5, 14, 5.5, 72, 2.75)])
        let pile = G.path { m in
            m.move(to: G.p(33, 84))
            m.addCurve(to: G.p(50, 67), control1: G.p(35, 75), control2: G.p(44, 68))
            m.addCurve(to: G.p(67, 84), control1: G.p(56, 68), control2: G.p(65, 75))
            m.closeSubpath()
        }.intersection(bulbs)
        let top = G.path { m in
            m.move(to: G.p(38.5, 31)); m.addLine(to: G.p(61.5, 31))
            m.addCurve(to: G.p(50, 46), control1: G.p(59.5, 38), control2: G.p(54, 43))
            m.addCurve(to: G.p(38.5, 31), control1: G.p(46, 43), control2: G.p(40.5, 38))
            m.closeSubpath()
        }
        let stream = G.rrect(49.1, 45, 1.8, 23, 0.9)
        return FT5GPiece(layers: [bulbs, frame],
                         solids: [FT5GSolid(after: 0, path: G.union([pile, top, stream]), alpha: 0.92)],
                         clear: [0])
    }

    /// جرس: العروة خلفه، ولسانه في الأمام (والتذكير بنقطة)
    static func bell(dot: Bool) -> FT5GPiece {
        let body = G.path { m in
            m.move(to: G.p(50, 14))
            m.addCurve(to: G.p(24, 47), control1: G.p(31, 14), control2: G.p(24, 30))
            m.addLine(to: G.p(24, 62))
            m.addCurve(to: G.p(14, 75), control1: G.p(24, 68), control2: G.p(19, 72))
            m.addLine(to: G.p(86, 75))
            m.addCurve(to: G.p(76, 62), control1: G.p(81, 72), control2: G.p(76, 68))
            m.addLine(to: G.p(76, 47))
            m.addCurve(to: G.p(50, 14), control1: G.p(76, 30), control2: G.p(69, 14))
            m.closeSubpath()
        }.union(G.rrect(11, 71, 78, 11, 5.5))
        let knob = G.circle(50, 12, 6.5)
        let clapper = G.circle(50, 88, 8.5)
        var layers = [knob, body, clapper]
        if dot { layers.append(G.circle(80, 21, 12)) }
        return FT5GPiece(layers: layers)
    }

    /// شتلة: ساق على أرض وورقتان — «عضو جديد في الشجرة»
    static func seedling() -> FT5GPiece {
        let stem = G.stroke(G.path { m in
            m.move(to: G.p(50, 90)); m.addCurve(to: G.p(50, 52), control1: G.p(50, 78), control2: G.p(49, 64))
        }, 6.5)
        let ground = G.rrect(24, 86, 52, 9, 4.5)
        let left = G.leaf(G.p(48, 60), G.p(10, 38), width: 21)
        let right = G.leaf(G.p(52, 53), G.p(90, 18), width: 27)
        return FT5GPiece(layers: [stem.union(ground), left, right])
    }

    /// تمّ: قرص وأمامه علامة صح
    static func checkDisc() -> FT5GPiece {
        FT5GPiece(layers: [G.circle(50, 50, 43), G.line([G.p(29, 52), G.p(44, 66), G.p(72, 36)], 11)])
    }

    /// معتمد: ختم مسنّن بشريطين وعلامة صح
    static func seal() -> FT5GPiece {
        let tails = G.poly([G.p(33, 60), G.p(47, 60), G.p(45, 97), G.p(38.5, 89), G.p(30, 94)], r: 2)
            .union(G.poly([G.p(53, 60), G.p(67, 60), G.p(70, 94), G.p(61.5, 89), G.p(55, 97)], r: 2))
        var bumps: [CGPath] = [G.circle(50, 43, 31)]
        for i in 0..<14 {
            let a = CGFloat(i) * 2 * .pi / 14
            bumps.append(G.circle(50 + cos(a) * 31, 43 + sin(a) * 31, 7))
        }
        let check = G.line([G.p(37, 44), G.p(47, 54), G.p(64, 33)], 8.5)
        return FT5GPiece(layers: [tails, G.union(bumps), check])
    }

    /// أُرسل: طائرة ورقية تتّجه للأمام (يسار بالعربية)
    static func plane() -> FT5GPiece {
        let a = G.poly([G.p(6, 47), G.p(94, 10), G.p(40, 62)], r: 3)
        let b = G.poly([G.p(40, 62), G.p(94, 10), G.p(61, 90)], r: 3)
        let fold = G.poly([G.p(40, 62), G.p(49, 84), G.p(55, 70)], r: 2)
        return FT5GPiece(layers: [G.mirror(b), G.mirror(fold), G.mirror(a)])
    }

    // MARK: شارات الأخبار

    /// خبر: ورقة بزاوية مطويّة وأسطر (محاذاة عربية)
    static func sheet() -> FT5GPiece {
        let s = G.poly([G.p(16, 6), G.p(62, 6), G.p(84, 28), G.p(84, 94), G.p(16, 94)], r: 6)
        let fold = G.poly([G.p(62, 6), G.p(62, 28), G.p(84, 28)], r: 2.5)
        let lines = G.union([G.rrect(42, 40, 32, 8, 4), G.rrect(26, 56, 48, 6, 3),
                             G.rrect(26, 68, 48, 6, 3), G.rrect(40, 80, 34, 6, 3)])
        return FT5GPiece(layers: [s.subtracting(fold).subtracting(lines), fold])
    }

    /// تهنئة: بريق — نجمة كبيرة واثنتان صغيرتان
    static func sparkles() -> FT5GPiece {
        FT5GPiece(layers: [G.star4(G.p(76, 22), 17, pinch: 0.17), G.star4(G.p(80, 70), 11, pinch: 0.2),
                           G.star4(G.p(40, 56), 37, pinch: 0.15)])
    }

    /// زواج: خاتمان متشابكان، على الثاني فصّ
    static func rings() -> FT5GPiece {
        let ringA = G.circle(35, 61, 27).subtracting(G.circle(35, 61, 18.5))
        let ringB = G.circle(65, 52, 27).subtracting(G.circle(65, 52, 18.5))
        let gem = G.poly([G.p(65, 11), G.p(75, 20), G.p(65, 31), G.p(55, 20)], r: 2.5)
        return FT5GPiece(layers: [ringA, ringB.union(gem)])
    }

    /// مولود: عربة طفل — السلّة والمقبض، الغطاء، العجلتان
    static func pram() -> FT5GPiece {
        let disc = G.circle(44, 50, 34)
        let basket = disc.intersection(G.rect(0, 53, 100, 50))
        let hood = disc.intersection(G.rect(0, 0, 41, 49.5))
        let handle = G.line([G.p(75, 56), G.p(86, 36), G.p(95, 36)], 6)
        let wheels = G.circle(24, 89, 8.5).union(G.circle(64, 89, 8.5))
        return FT5GPiece(layers: [basket.union(handle), hood, wheels])
    }

    /// تصويت: ورقة بعلامة صح تدخل صندوقاً
    static func ballot() -> FT5GPiece {
        let tick = G.line([G.p(41, 30), G.p(48, 37), G.p(60, 22)], 5)
        let card = G.rotate(G.rrect(31, 6, 38, 48, 4).subtracting(tick), -8, 50, 40)
        let box = G.rrect(8, 46, 84, 47, 8).subtracting(G.rrect(29, 55, 42, 6, 3))
        return FT5GPiece(layers: [card, box])
    }

    /// دعوة: ظرف مفتوح تخرج منه بطاقة
    static func invite() -> FT5GPiece {
        let back = G.rrect(7, 44, 86, 49, 6).union(G.poly([G.p(9, 49), G.p(91, 49), G.p(50, 20)], r: 5))
        let card = G.rrect(21, 10, 58, 52, 4)
            .subtracting(G.union([G.rrect(32, 22, 36, 6, 3), G.rrect(38, 33, 24, 5, 2.5)]))
        let pocket = G.poly([G.p(7, 51), G.p(50, 75), G.p(93, 51), G.p(93, 93), G.p(7, 93)], r: 6)
        return FT5GPiece(layers: [back, card, pocket])
    }

    // MARK: النظام العام

    /// لوح زجاج مربّع مدوّر عليه الرمز (منقوش بلون الرأس فوق الألوان، أبيض فوق المحايد)
    static func plaque(_ s: String) -> FT5GPiece {
        FT5GPiece(layers: [G.rrect(10, 10, 80, 80, 22)], symbol: s, symbolBox: CGRect(x: 27, y: 27, width: 46, height: 46))
    }

    /// قرص زجاج واحد عليه الرمز (رموز الحالة الصغيرة)
    static func disc(_ s: String) -> FT5GPiece {
        FT5GPiece(layers: [G.circle(50, 50, 47)], symbol: s, symbolBox: CGRect(x: 27, y: 27, width: 46, height: 46))
    }
}

// MARK: - الواجهات

nonisolated enum FT5GGlintMode: Sendable, Equatable {
    case none
    /// مرة واحدة عند الظهور بعد تأخير
    case once(delay: Double)
    /// تتكرّر (تحميل الشجرة فقط): عبور ثم انتظار خارج القطعة
    case loop(period: Double)
}

/// الرسم الساكن + لمعة اختيارية (تحريك موضع فقط فوق قناع ساكن)
struct FT5GArtView: View {
    let kind: FT5GKind
    let placement: FT5GPlacement
    let spec: FT5GSpec
    var glint: FT5GGlintMode = .none
    var asyncRender = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var glintDone = false

    var body: some View {
        let kind = self.kind, placement = self.placement, spec = self.spec
        ZStack {
            Canvas(rendersAsynchronously: asyncRender) { ctx, size in
                FT5GEngine.render(kind, placement: placement, spec: spec, in: &ctx, size: size)
            }
            if glint != .none && !reduceMotion && !glintDone {
                FT5GGlint(kind: kind, placement: placement, progress: progress,
                          travelScale: glintIsLoop ? 2.2 : 1)
                    .onAppear(perform: startGlint)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var glintIsLoop: Bool {
        if case .loop = glint { return true }
        return false
    }

    private func startGlint() {
        switch glint {
        case .none:
            return
        case .once(let delay):
            withAnimation(.easeInOut(duration: 1.5).delay(delay)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.6) { glintDone = true }
        case .loop(let period):
            withAnimation(.easeInOut(duration: period).delay(0.3).repeatForever(autoreverses: false)) { progress = 1 }
        }
    }
}

/// اللمعة: شريط ضوء مائل يعبر القطعة من جهة الضوء. `progress` ٠ (قبل القطعة) → ١ (بعدها)؛
/// `travelScale` > ١ يجعل جزءاً من العبور خارج القطعة (انتظار بين العبورات في التكرار).
struct FT5GGlint: View {
    let kind: FT5GKind
    let placement: FT5GPlacement
    let progress: CGFloat
    var travelScale: CGFloat = 1
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let kind = self.kind, placement = self.placement
        let ltr = direction == .leftToRight
        GeometryReader { g in
            let s = placement.screenSlot(g.size, ltr: ltr)
            let band = s.width * 0.42
            let travel = (s.width + band * 2) * travelScale
            let x0 = ltr ? s.minX - band : s.maxX + band
            let x = ltr ? x0 + progress * travel : x0 - progress * travel
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.6), location: 0.5),
                .init(color: .white.opacity(0), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: band, height: s.height * 1.7)
            .rotationEffect(.degrees(ltr ? 20 : -20))
            .position(x: x, y: s.midY)
        }
        .environment(\.layoutDirection, .leftToRight)
        .mask(Canvas { ctx, size in FT5GEngine.silhouette(kind, placement: placement, in: &ctx, size: size) })
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// لحظة التنبيه: القطعة تظهر مرة (تكبير وشفافية بنابض) ثم تعبرها لمعة — كلها ≤ ١٫٢ ث، ثم سكون.
/// «تقليل الحركة» أو `finalFrame`: الإطار الأخير مباشرة.
struct FT5GMomentView: View {
    let kind: FT5GKind
    let tint: Color
    var finalFrame = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @State private var appeared = false
    @State private var glint: CGFloat = 0
    @State private var glintDone = false

    var body: some View {
        let still = finalFrame || reduceMotion
        let shown = appeared || still
        let placement = FT5GPlacement.center(0.84, dy: 0)
        // «أُرسل»: الطائرة تدخل من الخلف (جهة النهاية) بدل التكبير
        let isPlane = kind == .plane
        let back: CGFloat = direction == .leftToRight ? -16 : 16
        ZStack {
            FT5GArtView(kind: kind, placement: placement, spec: .tinted(tint), asyncRender: false)
            if !still && !glintDone {
                FT5GGlint(kind: kind, placement: placement, progress: glint)
            }
        }
        .scaleEffect(shown || isPlane ? 1 : 0.7)
        .offset(x: shown || !isPlane ? 0 : back, y: shown || !isPlane ? 0 : 12)
        .opacity(shown ? 1 : 0)
        .frame(width: 160, height: 112)
        .onAppear {
            guard !still else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.64)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.6).delay(0.5)) { glint = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { glintDone = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - شريط رأس الأقسام

/// قضيب ضوء زجاجي (~١٢ نقطة): جوهرة زجاج في الوسط، خرزتان، وقضيبان يتلاشيان نحو الطرفين.
/// الحركة الوحيدة: القضيبان يمتدّان من الوسط مرة عند الظهور (تحجيم أفقي لطبقة مرسومة).
struct FT5GOrnamentView: View {
    let section: String
    var finalFrame = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let on = shown || finalFrame || reduceMotion
        ZStack {
            Canvas { ctx, size in FT5GOrnament.drawRails(in: &ctx, size: size) }
                .scaleEffect(x: on ? 1 : 0.12, y: 1, anchor: .center)
                .opacity(on ? 1 : 0)
            Canvas { ctx, size in FT5GOrnament.drawGem(in: &ctx, size: size) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 12)
        .environment(\.layoutDirection, .leftToRight)   // متماثل
        .onAppear {
            guard !(finalFrame || reduceMotion) else { return }
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { shown = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

nonisolated enum FT5GOrnament {
    static let gemHalf: CGFloat = 14

    static func drawRails(in ctx: inout GraphicsContext, size: CGSize) {
        guard size.width > 80 else { return }
        let cx = size.width / 2, cy = size.height / 2
        let inner = gemHalf + 15
        let h: CGFloat = 2.2
        for side in [-1.0, 1.0] {
            let s = CGFloat(side)
            let x0 = cx + s * inner
            let x1 = s < 0 ? 1 : size.width - 1
            let r = CGRect(x: min(x0, x1), y: cy - h / 2, width: abs(x1 - x0), height: h)
            let p = Path(roundedRect: r, cornerRadius: h / 2)
            let start = CGPoint(x: x0, y: cy), end = CGPoint(x: x1, y: cy)
            // جسم القضيب: أبيض شفاف يتلاشى للطرف
            ctx.fill(p, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(0.78), location: 0),
                .init(color: .white.opacity(0.34), location: 0.45),
                .init(color: .white.opacity(0), location: 1)
            ]), startPoint: start, endPoint: end))
            // خط ضوء رفيع فوقه
            let top = Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 0.6))
            ctx.fill(top, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(0.9), location: 0),
                .init(color: .white.opacity(0), location: 0.6)
            ]), startPoint: start, endPoint: end))
        }
    }

    static func drawGem(in ctx: inout GraphicsContext, size: CGSize) {
        guard size.width > 40 else { return }
        let cx = size.width / 2, cy = size.height / 2
        let hh = min(5.2, size.height * 0.44)
        // وهج خفيف خلف الجوهرة
        let gr: CGFloat = 20
        ctx.fill(Path(ellipseIn: CGRect(x: cx - gr, y: cy - gr * 0.6, width: gr * 2, height: gr * 1.2)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                                       center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: gr))
        let gem = Path(FT5GGeo.poly([CGPoint(x: cx - gemHalf, y: cy), CGPoint(x: cx, y: cy - hh),
                                     CGPoint(x: cx + gemHalf, y: cy), CGPoint(x: cx, y: cy + hh)], r: 1.8))
        let lit = CGPoint(x: cx + gemHalf, y: cy - hh), shade = CGPoint(x: cx - gemHalf, y: cy + hh)
        ctx.fill(gem, with: .linearGradient(Gradient(colors: [.white.opacity(0.62), .white.opacity(0.22)]),
                                            startPoint: lit, endPoint: shade))
        var c = ctx
        c.clip(to: gem)
        c.stroke(gem, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(1), location: 0),
            .init(color: .white.opacity(0.35), location: 0.55),
            .init(color: .white.opacity(0.75), location: 1)
        ]), startPoint: lit, endPoint: shade), lineWidth: 1.8)
        // خط الوسط المضيء (سطح الجوهرة)
        c.fill(Path(CGRect(x: cx - gemHalf, y: cy - 0.35, width: gemHalf * 2, height: 0.7)),
               with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.7), .white.opacity(0)]),
                                     startPoint: CGPoint(x: cx - gemHalf, y: cy), endPoint: CGPoint(x: cx + gemHalf, y: cy)))
        // خرزتان
        for s in [-1.0, 1.0] {
            let bx = cx + CGFloat(s) * (gemHalf + 7.5)
            let br: CGFloat = 2.1
            let bead = Path(ellipseIn: CGRect(x: bx - br, y: cy - br, width: br * 2, height: br * 2))
            ctx.fill(bead, with: .radialGradient(Gradient(colors: [.white.opacity(0.95), .white.opacity(0.45)]),
                                                 center: CGPoint(x: bx + 0.6, y: cy - 0.7), startRadius: 0, endRadius: br * 1.3))
        }
    }
}

// MARK: - خلفية الدخول

nonisolated enum FT5GBackdrop {
    /// عدسة شبه غائبة: وهج كحلي خلف الشعار + حلقة زجاج رفيعة بحافة ضوء من أعلى اليمين + حلقة ثانية أبعد
    static func draw(in ctx: inout GraphicsContext, size: CGSize, logoCenterY: CGFloat) {
        guard size.width > 1, size.height > 1 else { return }
        let dark = ctx.environment.colorScheme == .dark
        let navy = dark ? FT5GPalette.homeInk.dark : FT5GPalette.homeInk.light
        let c = CGPoint(x: size.width / 2, y: logoCenterY)
        let gr = size.width * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)),
                 with: .radialGradient(Gradient(colors: [navy.opacity(dark ? 0.12 : 0.06), navy.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: gr))
        for (i, f) in [0.36, 0.50].enumerated() {
            let r = size.width * CGFloat(f)
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let lit = CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.7), shade = CGPoint(x: c.x - r * 0.7, y: c.y + r * 0.7)
            let a = i == 0 ? 1.0 : 0.6
            // سماكة العدسة: شريط بلون الكحلي يخفت نحو الأسفل
            ctx.stroke(ring, with: .linearGradient(Gradient(colors: [navy.opacity((dark ? 0.16 : 0.08) * a),
                                                                     navy.opacity(0.0)]),
                                                   startPoint: lit, endPoint: shade), lineWidth: 7)
            // حافة الضوء
            ctx.stroke(ring, with: .linearGradient(Gradient(colors: [(dark ? Color.white : navy).opacity((dark ? 0.22 : 0.16) * a),
                                                                     navy.opacity(0.02)]),
                                                   startPoint: lit, endPoint: shade), lineWidth: 1)
        }
    }
}

// MARK: - رمز الوقت في بطاقة الترحيب (من الجولة الرابعة)

nonisolated enum FT5GTimeMood: Sendable {
    case morning, noon, evening, night
    /// الصباح ٤–١٢، الظهر ١٢–١٧، المغرب ١٧–١٩، الليل بعدها
    static func forHour(_ h: Int) -> FT5GTimeMood {
        switch h {
        case 4..<12: return .morning
        case 12..<17: return .noon
        case 17..<19: return .evening
        default: return .night
        }
    }
}

/// شمس أو هلال من زجاج ملوّن بلون الوقت، بحافة ضوء ولمعة — ساكن
struct FT5GTimeGlyph: View {
    let mood: FT5GTimeMood
    let tint: Color
    var size: CGFloat = 18

    var body: some View {
        let mood = self.mood, tint = self.tint
        Canvas { ctx, sz in FT5GTime.draw(mood, tint: tint, in: &ctx, size: sz) }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated enum FT5GTime {
    static func ray(cx: CGFloat, cy: CGFloat, angle: CGFloat, r0: CGFloat, r1: CGFloat, w: CGFloat) -> CGPath {
        let l = CGMutablePath()
        l.move(to: CGPoint(x: cx + cos(angle) * r0, y: cy + sin(angle) * r0))
        l.addLine(to: CGPoint(x: cx + cos(angle) * r1, y: cy + sin(angle) * r1))
        return l.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    static func draw(_ mood: FT5GTimeMood, tint: Color, in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let k = s / 100
        var c = ctx
        if ctx.environment.layoutDirection == .leftToRight {
            c.translateBy(x: size.width, y: 0); c.scaleBy(x: -1, y: 1)
        }
        let dark = ctx.environment.colorScheme == .dark
        let shape: Path
        let m = CGAffineTransform(scaleX: k, y: k)
        switch mood {
        case .night:
            shape = Path(FT5GGeo.circle(50, 52, 40).subtracting(FT5GGeo.circle(33, 40, 33))).applying(m)
        case .morning, .evening:
            let cy: CGFloat = mood == .morning ? 74 : 78
            var sun: CGPath = FT5GGeo.circle(50, cy, 25).subtracting(FT5GGeo.rect(0, 76, 100, 40))
            for i in 0..<5 {
                let ang = CGFloat.pi * (1.0 + Double(i + 1) / 6.0)
                sun = sun.union(ray(cx: 50, cy: cy, angle: ang, r0: 33, r1: 45, w: 8))
            }
            shape = Path(sun).applying(m)
        case .noon:
            var sun: CGPath = FT5GGeo.circle(50, 50, 24)
            for i in 0..<8 {
                sun = sun.union(ray(cx: 50, cy: 50, angle: CGFloat.pi / 4 * CGFloat(i), r0: 33, r1: 46, w: 9))
            }
            shape = Path(sun).applying(m)
        }
        let b = shape.boundingRect
        let gc = CGPoint(x: b.midX, y: b.midY)
        c.fill(Path(ellipseIn: CGRect(x: gc.x - s * 0.46, y: gc.y - s * 0.46, width: s * 0.92, height: s * 0.92)),
               with: .radialGradient(Gradient(colors: [tint.opacity(dark ? 0.10 : 0.12), tint.opacity(0)]),
                                     center: gc, startRadius: 0, endRadius: s * 0.46))
        c.fill(shape, with: .linearGradient(Gradient(colors: [tint.opacity(dark ? 0.70 : 0.62), tint.opacity(1)]),
                                            startPoint: CGPoint(x: b.maxX, y: b.minY), endPoint: CGPoint(x: b.minX, y: b.maxY)))
        var cl = c
        cl.clip(to: shape)
        let hc = mood == .noon ? CGPoint(x: 58 * k, y: 40 * k)
            : (mood == .night ? CGPoint(x: 72 * k, y: 30 * k) : CGPoint(x: 58 * k, y: 58 * k))
        cl.fill(Path(b), with: .radialGradient(Gradient(colors: [.white.opacity(0.6), .white.opacity(0)]),
                                               center: hc, startRadius: 0, endRadius: 30 * k))
        cl.stroke(shape, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.85), location: 0),
            .init(color: tint.opacity(0.55), location: 0.45),
            .init(color: tint.opacity(1), location: 1)
        ]), startPoint: CGPoint(x: b.maxX, y: b.minY), endPoint: CGPoint(x: b.minX, y: b.maxY)), lineWidth: max(1.2, 7 * k))
        if mood == .morning || mood == .evening {
            c.fill(Path(roundedRect: CGRect(x: 14 * k, y: 82 * k, width: 72 * k, height: max(1.4, 7 * k)), cornerRadius: 3.5 * k),
                   with: .color(tint.opacity(0.9)))
        }
    }
}
