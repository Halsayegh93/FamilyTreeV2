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

    /// مجسّم مربّع الرئيسية في مربّع مركزي (المجسّم والاسم بالوسط): زجاج مصنفر بلون المربّع
    /// (FT5GObjectArt في آخر الملف) — nil = لا مجسّم لهذا المكان فيبقى الشكل السابق
    static func tileIcon(_ place: String, variant: Int) -> AnyView? {
        guard FT5GObjectArt.supports(place) else { return nil }
        return AnyView(FT5GObjectView(place: place, variant: variant))
    }
    /// شفافية النسخة الكبيرة من المجسّم في خلفية مربّع الرئيسية (الطيف في الزاوية)
    static let ghostOpacity: Double = 0.16
    /// لا رسم على خلفية المربّع (طلب المالك ٢٠٢٦-١٠-٠٦): المجسّم والاسم في الوسط والطيف في الزاوية فقط
    static func tile(_ place: String, variant: Int, badge: Bool, animateOnce: Bool) -> AnyView {
        AnyView(EmptyView())
    }

    // MARK: رؤوس الصناديق

    static func header(icon: String, tint: Color, deep: Color) -> AnyView {
        let kind = FT5GKind.forSymbol(icon, library: libraryVariant, projects: projectsVariant) ?? .plaque(icon)
        let still = kind == .mourning
        return AnyView(FT5GArtView(kind: kind, placement: .header,
                                   spec: .onColor(glow: nil, shadow: deep, still: still, tint: tint),
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
                                   spec: .onColor(glow: nil, shadow: tint, still: kind == .mourning, tint: tint)))
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
        let slot = placement.slot(size, ltr: ltr)
        if kind == .tree {   // الشجرة = رمز `tree.fill` (قرار المالك ٢٠٢٦-١٠-٠٦)
            var img = c.resolve(Image(systemName: FT5GObjectArt.treeSymbol))
            img.shading = .color(.white)
            c.draw(img, in: FT5GObjectArt.treeRect(in: slot, aspect: img.size.width / max(1, img.size.height)))
            return
        }
        let piece = FT5GShapes.piece(kind)
        for p in placed(piece.layers, piece: piece, slot: slot, mirrored: ltr) {
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
        if kind == .tree {   // الشجرة = رمز `tree.fill` بزجاج مصنفر في كل مكان (قرار المالك ٢٠٢٦-١٠-٠٦)
            FT5GObjectArt.drawTreeGlass(box: slot, spec: spec, dark: dark, in: &ctx)
            return
        }
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
        // الخمسة الكبار من مجسّمات المربّعات (الجولة السادسة) — الشكل واحد في المربّع والرأس والصفحة الفاضية
        case .tree: return FT5GPiece(layers: [])   // لا يُستعمل: المحرّك يرسم رمز `tree.fill` مباشرة (drawTreeGlass)
        case .dallah: return FT5GObjectArt.piece("diwaniya", variant: 0)
        case .envelope: return FT5GObjectArt.piece("contact", variant: 0)
        case .news: return FT5GPiece(layers: news())
        case .megaphone: return megaphone()
        case .shelf: return FT5GObjectArt.piece("library", variant: 0)
        case .photos: return FT5GObjectArt.piece("library", variant: 1)
        case .folder: return FT5GObjectArt.piece("library", variant: 2)
        case .briefcase: return FT5GObjectArt.piece("projects", variant: 0)
        case .growth: return FT5GObjectArt.piece("projects", variant: 1)
        case .towers: return FT5GObjectArt.piece("projects", variant: 2)
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

    // MARK: الخبر (الشجرة والدلّة والظرف صارت في FT5GObjectArt آخر الملف)

    /// خبر: ورقتان — الخلفية مائلة، والأمامية بزاوية مطويّة وأسطر محفورة (محاذاة عربية)
    static func news() -> [CGPath] {
        let back = G.rotate(G.rrect(22, 14, 56, 72, 7), -12, 50, 50)
        let sheet = G.poly([G.p(26, 15), G.p(64, 15), G.p(80, 31), G.p(80, 90), G.p(26, 90)], r: 6)
        let fold = G.poly([G.p(64, 15), G.p(64, 31), G.p(80, 31)], r: 2.5)
        let lines = G.union([G.rrect(34, 42, 30, 6, 3), G.rrect(34, 56, 38, 4, 2),
                             G.rrect(34, 67, 38, 4, 2), G.rrect(34, 78, 24, 4, 2)])
        return [back, sheet.subtracting(fold).subtracting(lines), fold]
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

// MARK: - مجسّمات مربّعات الرئيسية — زجاج مصنفر بلون المربّع (الجولة السادسة، ٢٠٢٦-١٠-٠٦)
//
// TMP-ART-TRIAL — طلب المالك «الأشكال أجمل وأكثر ترتيباً، وألوانها متناسقة مع المربّعات»:
// خمسة مجسّمات على شبكة ١٠٠×١٠٠ تملأ الصندوق نفسه (البعد الأكبر ٩٠٪ والأصغر ≥ ٦٠٪، وتقف على خط أرض واحد
// عند ٩٥)، زجاج أبيض مصنفر يسكنه لون المربّع بنسبة ٢٥–٤٠٪، حافة بيضاء حادة بسماكة نقطة واحدة، لمعة واحدة
// من أعلى اليسار، تفاصيل بدرجة المربّع الداكنة، لمسة ذهبية معدنية واحدة، وظل تماسّ بيضاوي ناعم تحت المجسّم.
// ساكنة تماماً (بلا TimelineView): تُرسم مرة في Canvas بالحجم الذي يحدّده المستدعي (٤٨ في الوسط، ٨٦ للطيف).

/// طبقة زجاج واحدة وما يُرسم فوقها (الطبقات من الخلف إلى الأمام)
nonisolated struct FT5GLayer {
    var glass: CGPath
    /// تفاصيل بدرجة المربّع الداكنة (نقاط العائلة، النوافذ، أسطر الورق، القهوة)
    var detail: [CGPath] = []
    /// أبيض مصمت (البخار، بطاقة الملف، جبال الصورة)
    var light: [CGPath] = []
    /// صبغة بيضاء خفيفة (سماء الصورة)
    var haze: [CGPath] = []
    /// اللمسة الذهبية الواحدة (معدن مصمت)
    var gold: [CGPath] = []
}

/// مجسّم كامل: طبقاته ومكان لمعته الواحدة
nonisolated struct FT5GObject {
    var layers: [FT5GLayer]
    /// الطبقة التي تحمل اللمعة، ومركزها ونصف قطرها على الشبكة
    var specularLayer = 0
    var specular = CGPoint(x: 30, y: 25)
    var specularRadius: CGFloat = 24
}

/// درجتا لون المربّع — من قيم AppSection نفسها (قاعدة «لون واحد لكل مجسّم»: أبيض + لون مربّعه + ذهبي)
nonisolated struct FT5GObjectHue {
    var base: Color
    var deep: Color

    static func of(_ place: String) -> FT5GObjectHue {
        func h(_ v: UInt32) -> Color { FT5GPalette.hex(v) }
        switch place {
        case "tree": return FT5GObjectHue(base: h(0x1E5950), deep: h(0x0D332D))
        case "diwaniya", "diwaniyas": return FT5GObjectHue(base: h(0x1E5665), deep: h(0x0D313A))
        case "library": return FT5GObjectHue(base: h(0x633C6F), deep: h(0x392041))
        case "projects": return FT5GObjectHue(base: h(0x275B35), deep: h(0x13341C))
        case "contact": return FT5GObjectHue(base: h(0x47467F), deep: h(0x28274B))
        default: return FT5GObjectHue(base: h(0x1F4E79), deep: h(0x102B47))
        }
    }
}

nonisolated enum FT5GObjectArt {
    private typealias G = FT5GGeo

    static let gold = FT5GPalette.hex(0xD9A23E)
    static let goldHi = FT5GPalette.hex(0xF2C65E)
    static let goldLo = FT5GPalette.hex(0xB07E2A)

    /// القطعة نفسها للمحرّك القديم (رؤوس الصناديق، الصفحات الفاضية، بطاقات الصفحات، تحميل الشجرة):
    /// الزجاج وحده — التفاصيل والذهب الداخلي فراغات مقصوصة، وما يقع خارج الزجاج (قمّة الدلّة، رأس السهم،
    /// البخار، جبال الصورة) يُضمّ إليه — فيبقى الشكل واحداً أينما ظهر
    static func piece(_ place: String, variant: Int) -> FT5GPiece {
        guard let o = object(place, variant: variant) else {
            return FT5GPiece(layers: [G.rrect(10, 10, 80, 80, 22)])
        }
        let layers: [CGPath] = o.layers.map { layer in
            var g = layer.glass
            for d in layer.detail { g = g.subtracting(d) }
            for extra in layer.light + layer.gold {
                let b = extra.boundingBox
                let inside = g.contains(CGPoint(x: b.midX, y: b.midY))
                g = inside ? g.subtracting(extra) : g.union(extra)
            }
            return g
        }
        let growth = place == "projects" && ((variant % 3) + 3) % 3 == 1
        return FT5GPiece(layers: layers, fixedOrientation: growth)   // سهم النمو يصعد يميناً في اللغتين
    }

    /// الأماكن التي لها مجسّم
    static func supports(_ place: String) -> Bool {
        ["tree", "diwaniya", "diwaniyas", "library", "projects", "contact"].contains(place)
    }

    /// المجسّم لكل مكان (nil = لا مجسّم لهذا المكان)
    static func object(_ place: String, variant: Int) -> FT5GObject? {
        let v = ((variant % 3) + 3) % 3
        switch place {
        case "tree": return nil   // الشجرة من رمز `tree.fill` (drawTreeTile)
        case "diwaniya", "diwaniyas": return dallah()
        case "library": return v == 0 ? shelf() : (v == 1 ? photos() : folder())
        case "projects": return v == 0 ? briefcase() : (v == 1 ? growth() : towers())
        case "contact": return envelope()
        default: return nil
        }
    }

    // MARK: الرسم

    static func draw(_ o: FT5GObject, hue: FT5GObjectHue, in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        guard s > 1, !o.layers.isEmpty else { return }
        let k = s / 100
        let m = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: (size.width - s) / 2, ty: (size.height - s) / 2)
        let dark = ctx.environment.colorScheme == .dark
        // الضوء من أعلى اليسار لكل المجسّمات
        let lit = CGPoint(x: 6, y: 4).applying(m), shade = CGPoint(x: 94, y: 96).applying(m)
        let glass = o.layers.map { Path($0.glass).applying(m) }

        // ١) ظل التماس: قطع ناقص ناعم عند خط الأرض (٩٥)، داخل المربّع
        contactShadow(&ctx, box: CGRect(x: m.tx, y: m.ty, width: s, height: s), k: k, hue: hue, dark: dark)

        // ٢) ظل رفع خفيف للمجسّم كله (خارج الزجاج فقط) نحو أسفل اليمين، بعيداً عن الضوء
        lift(&ctx, glass, color: hue.deep, dx: 0.9 * k, dy: 1.8 * k, blur: 2.6 * k, opacity: dark ? 0.42 : 0.30)

        // ٣) الطبقات من الخلف إلى الأمام: زجاج، لمعة، صبغة، أبيض، تفاصيل، ذهب
        for (i, layer) in o.layers.enumerated() {
            let p = glass[i]
            if i > 0 { lift(&ctx, [p], color: hue.deep, dx: 0.6 * k, dy: 1.2 * k, blur: 1.6 * k, opacity: 0.22) }
            frosted(&ctx, p, k: k, hue: hue, dark: dark, lit: lit, shade: shade)
            if i == o.specularLayer { specular(&ctx, p, at: o.specular.applying(m), radius: o.specularRadius * k) }
            for h in layer.haze { ctx.fill(Path(h).applying(m), with: .color(.white.opacity(dark ? 0.16 : 0.20))) }
            for l in layer.light { ctx.fill(Path(l).applying(m), with: .color(.white.opacity(0.92))) }
            for d in layer.detail { ctx.fill(Path(d).applying(m), with: .color(hue.deep.opacity(dark ? 0.80 : 0.86))) }
            for g in layer.gold { metal(&ctx, Path(g).applying(m)) }
        }
    }

    /// ظل التماس: قطع ناقص ناعم عند خط الأرض (٩٥٫٥ من الصندوق)، داخل المربّع
    static func contactShadow(_ ctx: inout GraphicsContext, box: CGRect, k: CGFloat, hue: FT5GObjectHue, dark: Bool) {
        var sh = ctx
        sh.translateBy(x: box.midX, y: box.minY + box.height * 0.955)
        sh.scaleBy(x: 1, y: 0.10)
        let r = 40 * k
        sh.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(Gradient(stops: [
                    .init(color: hue.deep.opacity(dark ? 0.62 : 0.48), location: 0),
                    .init(color: hue.deep.opacity(dark ? 0.28 : 0.20), location: 0.55),
                    .init(color: hue.deep.opacity(0), location: 1)
                ]), center: .zero, startRadius: 0, endRadius: r))
    }

    /// طبقة زجاج مصنفر: جسم أبيض يسكنه لون المربّع (يتجمّع بعيداً عن الضوء)، صنفرة بيضاء عند الحافة من
    /// الداخل (سماكة الزجاج)، وحافة بيضاء حادة بسماكة نقطة واحدة أسطع جهة الضوء
    static func frosted(_ ctx: inout GraphicsContext, _ p: Path, k: CGFloat, hue: FT5GObjectHue, dark: Bool,
                        lit: CGPoint, shade: CGPoint) {
        ctx.fill(p, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(dark ? 0.90 : 0.86), location: 0),
            .init(color: .white.opacity(dark ? 0.76 : 0.70), location: 1)
        ]), startPoint: lit, endPoint: shade))
        ctx.fill(p, with: .linearGradient(Gradient(stops: [
            .init(color: hue.base.opacity(dark ? 0.16 : 0.24), location: 0),
            .init(color: hue.base.opacity(dark ? 0.32 : 0.42), location: 1)
        ]), startPoint: lit, endPoint: shade))
        var c = ctx
        c.clip(to: p)
        c.drawLayer { l in
            l.addFilter(.blur(radius: 1.8 * k))
            l.stroke(p, with: .color(.white.opacity(0.50)), lineWidth: 3.6 * k)
        }
        c.stroke(p, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(1.0), location: 0),
            .init(color: .white.opacity(0.78), location: 0.5),
            .init(color: .white.opacity(0.55), location: 1)
        ]), startPoint: lit, endPoint: shade), lineWidth: 2.0)   // مقصوصة بالشكل ⇒ نقطة واحدة ظاهرة
    }

    /// اللمعة الواحدة: بقعة ضوء ناعمة قرب أعلى يسار الجسم الرئيس
    static func specular(_ ctx: inout GraphicsContext, _ p: Path, at c: CGPoint, radius r: CGFloat) {
        var cl = ctx
        cl.clip(to: p)
        cl.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(Gradient(stops: [
                    .init(color: .white.opacity(0.72), location: 0),
                    .init(color: .white.opacity(0.28), location: 0.45),
                    .init(color: .white.opacity(0), location: 1)
                ]), center: c, startRadius: 0, endRadius: r))
    }

    /// اللمسة الذهبية: معدن مصمت بتدرّج من الضوء إلى الظل وحافة ضوء رفيعة جهة الضوء
    static func metal(_ ctx: inout GraphicsContext, _ p: Path) {
        let b = p.boundingRect
        let a = CGPoint(x: b.minX, y: b.minY), z = CGPoint(x: b.maxX, y: b.maxY)
        ctx.fill(p, with: .linearGradient(Gradient(stops: [
            .init(color: goldHi, location: 0),
            .init(color: gold, location: 0.55),
            .init(color: goldLo, location: 1)
        ]), startPoint: a, endPoint: z))
        var c = ctx
        c.clip(to: p)
        c.stroke(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.78), .white.opacity(0.04)]),
                                          startPoint: a, endPoint: z), lineWidth: 1.4)
    }

    /// ظل ناعم خارج الأشكال فقط، منزاح نحو أسفل اليمين
    static func lift(_ ctx: inout GraphicsContext, _ paths: [Path], color: Color, dx: CGFloat, dy: CGFloat,
                     blur: CGFloat, opacity: Double) {
        ctx.drawLayer { l in
            var sh = l
            sh.opacity = opacity
            sh.addFilter(.blur(radius: blur))
            sh.drawLayer { s in
                s.translateBy(x: dx, y: dy)
                for p in paths { s.fill(p, with: .color(color)) }
            }
            l.blendMode = .destinationOut
            for p in paths { l.fill(p, with: .color(.black)) }
        }
    }

    /// أنبوب يضيق تدريجياً على منحنى بيزييه تكعيبي (منقار الدلّة)
    static func tube(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint,
                     from w0: CGFloat, to w1: CGFloat, steps: Int = 28) -> CGPath {
        var a: [CGPoint] = [], b: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps), u = 1 - t
            let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
            let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
            let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
            let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            let nx = -dy / len, ny = dx / len
            let w = (w0 + (w1 - w0) * t) / 2
            a.append(CGPoint(x: x + nx * w, y: y + ny * w))
            b.append(CGPoint(x: x - nx * w, y: y - ny * w))
        }
        let m = CGMutablePath()
        m.move(to: a[0])
        for q in a.dropFirst() { m.addLine(to: q) }
        for q in b.reversed() { m.addLine(to: q) }
        m.closeSubpath()
        return m
    }

    // MARK: الشجرة — الظلّية نفسها في أيقونة التطبيق: رمز SF `tree.fill` (تاج بخمسة فصوص وجذع بثلاثة أصابع)،
    // بلا نقاط عائلة ولا فصوص مرسومة (قرار المالك ٢٠٢٦-١٠-٠٦) — الزجاج المصنفر يُرسم داخل قناع الرمز نفسه،
    // ونقطة ذهبية صغيرة واحدة في الفصّ الأعلى

    static let treeSymbol = "tree.fill"

    /// إطار الرمز داخل صندوق المجسّم: ارتفاعه ٩٢٫٥٪ من أعلى ٥٪ — وبهامش الرمز السفلي (≈ ٢٫٨٪) يقف على خط الأرض ٩٥
    static func treeRect(in box: CGRect, aspect: CGFloat) -> CGRect {
        let h = box.height * 0.925
        let w = min(h * max(0.3, aspect), box.width * 0.92)
        return CGRect(x: box.midX - w / 2, y: box.minY + box.height * 0.05, width: w, height: h)
    }

    /// مجسّم مربّع الشجرة: ظل التماس ثم الرمز بزجاج مصنفر بلون المربّع
    static func drawTreeTile(in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        guard s > 1 else { return }
        let k = s / 100
        let box = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
        let dark = ctx.environment.colorScheme == .dark
        let hue = FT5GObjectHue.of("tree")
        contactShadow(&ctx, box: box, k: k, hue: hue, dark: dark)
        drawSymbolGlass(treeSymbol, box: box, k: k, hue: hue, dark: dark, tinted: false, in: &ctx)
    }

    /// الشجرة للمحرّك القديم (رؤوس الصناديق، الصفحات الفاضية، تحميل الشجرة): وهج خلفها كبقية القطع ثم الزجاج
    static func drawTreeGlass(box: CGRect, spec: FT5GSpec, dark: Bool, in ctx: inout GraphicsContext) {
        let k = box.width / 100
        let tinted = spec.look == .tinted
        let tint = spec.tint(dark)
        let hue = tinted ? FT5GObjectHue(base: tint, deep: tint) : FT5GObjectHue(base: tint, deep: spec.shadow)
        if !spec.still {
            let center = CGPoint(x: box.midX, y: box.midY + box.height * 0.04)
            let gr = box.width * (tinted ? 0.74 : 0.80)
            let g: Color = tinted ? tint : (spec.glow ?? .white)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - gr, y: center.y - gr, width: gr * 2, height: gr * 2)),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: g.opacity(tinted ? (dark ? 0.26 : 0.17) : (dark ? 0.16 : 0.22)), location: 0),
                        .init(color: g.opacity(tinted ? (dark ? 0.10 : 0.06) : (dark ? 0.06 : 0.08)), location: 0.55),
                        .init(color: g.opacity(0), location: 1)
                     ]), center: center, startRadius: 0, endRadius: gr))
        }
        drawSymbolGlass(treeSymbol, box: box, k: k, hue: hue, dark: dark, tinted: tinted, in: &ctx)
    }

    /// زجاج مصنفر داخل رمز SF: ظل رفع خارجه، جسم (أبيض يسكنه لون المربّع — أو ملوّن فوق المحايد)، صنفرة
    /// الحافة من الداخل، حافة ضوء بسماكة نقطة واحدة (الرمز ناقص نسخه المزاحة)، لمعة واحدة، ونقطة ذهبية
    static func drawSymbolGlass(_ name: String, box: CGRect, k: CGFloat, hue: FT5GObjectHue, dark: Bool, tinted: Bool,
                                in ctx: inout GraphicsContext) {
        var img = ctx.resolve(Image(systemName: name))
        img.shading = .color(.white)
        let rect = treeRect(in: box, aspect: img.size.width / max(1, img.size.height))
        let lit = CGPoint(x: box.minX + box.width * 0.06, y: box.minY + box.height * 0.04)
        let shade = CGPoint(x: box.maxX - box.width * 0.06, y: box.maxY - box.height * 0.04)
        let offs: [(CGFloat, CGFloat)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7)]
        let outer = rect.insetBy(dx: -4 * k, dy: -4 * k)

        // ظل الرفع خارج الرمز، نحو أسفل اليمين
        ctx.drawLayer { l in
            var sh = l
            sh.opacity = tinted ? (dark ? 0.55 : 0.28) : (dark ? 0.42 : 0.30)
            sh.addFilter(.blur(radius: 2.6 * k))
            var dsh = img
            dsh.shading = .color(tinted && dark ? .black : hue.deep)
            sh.draw(dsh, in: rect.offsetBy(dx: 0.9 * k, dy: 1.8 * k))
            l.blendMode = .destinationOut
            l.draw(img, in: rect)
        }

        ctx.drawLayer { g in
            g.clipToLayer { $0.draw(img, in: rect) }
            if tinted {
                g.fill(Path(outer), with: .linearGradient(Gradient(stops: [
                    .init(color: hue.base.opacity(dark ? 0.46 : 0.50), location: 0),
                    .init(color: hue.base.opacity(dark ? 0.84 : 0.88), location: 1)
                ]), startPoint: lit, endPoint: shade))
            } else {
                g.fill(Path(outer), with: .linearGradient(Gradient(stops: [
                    .init(color: .white.opacity(dark ? 0.90 : 0.86), location: 0),
                    .init(color: .white.opacity(dark ? 0.76 : 0.70), location: 1)
                ]), startPoint: lit, endPoint: shade))
                g.fill(Path(outer), with: .linearGradient(Gradient(stops: [
                    .init(color: hue.base.opacity(dark ? 0.16 : 0.24), location: 0),
                    .init(color: hue.base.opacity(dark ? 0.32 : 0.42), location: 1)
                ]), startPoint: lit, endPoint: shade))
            }
            // صنفرة الحافة من الداخل: أبيض يبقى قرب الحافة فقط (الرمز ناقص نسخه المزاحة) ثم يُنعَّم
            g.drawLayer { f in
                f.fill(Path(outer), with: .color(.white.opacity(0.50)))
                var e = f
                e.blendMode = .destinationOut
                e.addFilter(.blur(radius: 1.4 * k))
                let d = 2.6 * k
                for o in offs { e.draw(img, in: rect.offsetBy(dx: o.0 * d, dy: o.1 * d)) }
            }
            // حافة الضوء: نقطة واحدة، أسطع جهة الضوء
            g.drawLayer { r in
                r.fill(Path(outer), with: .linearGradient(Gradient(stops: [
                    .init(color: .white.opacity(1.0), location: 0),
                    .init(color: .white.opacity(0.78), location: 0.5),
                    .init(color: .white.opacity(0.55), location: 1)
                ]), startPoint: lit, endPoint: shade))
                var e = r
                e.blendMode = .destinationOut
                for o in offs { e.draw(img, in: rect.offsetBy(dx: o.0, dy: o.1)) }
            }
            // اللمعة الواحدة على أعلى يسار التاج
            let sp = CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.22)
            let sr = rect.width * 0.30
            g.fill(Path(ellipseIn: CGRect(x: sp.x - sr, y: sp.y - sr, width: 2 * sr, height: 2 * sr)),
                   with: .radialGradient(Gradient(stops: [
                    .init(color: .white.opacity(tinted ? 0.50 : 0.72), location: 0),
                    .init(color: .white.opacity(tinted ? 0.18 : 0.28), location: 0.45),
                    .init(color: .white.opacity(0), location: 1)
                   ]), center: sp, startRadius: 0, endRadius: sr))
        }
        // نقطة ذهبية صغيرة واحدة في الفصّ الأعلى
        let gr = rect.width * 0.045
        metal(&ctx, Path(ellipseIn: CGRect(x: rect.midX - gr, y: rect.minY + rect.height * 0.15 - gr,
                                            width: 2 * gr, height: 2 * gr)))
    }

    // MARK: الدلّة والفنجان — منقار طويل، غطاء مقبّب بقمّة ذهبية، مقبض جانبي، وفنجان صغير يتصاعد منه بخار

    static func dallah() -> FT5GObject {
        let ax: CGFloat = 36
        typealias Seg = (c1: CGPoint, c2: CGPoint, to: CGPoint)
        // النصف الأيمن من القاعدة إلى الكتف (إزاحات عن المحور)، والأيسر مرآته
        let segs: [Seg] = [
            (G.p(12.5, 92.5), G.p(8.5, 90), G.p(8, 86)),
            (G.p(7.5, 80), G.p(18, 77), G.p(17.5, 69)),
            (G.p(17, 62), G.p(11.5, 58), G.p(9, 53)),
            (G.p(7.5, 50), G.p(7, 47), G.p(7.5, 43))
        ]
        let body = G.path { m in
            m.move(to: G.p(ax - 12.5, 95))
            m.addLine(to: G.p(ax + 12.5, 95))
            for s in segs {
                m.addCurve(to: G.p(ax + s.to.x, s.to.y), control1: G.p(ax + s.c1.x, s.c1.y), control2: G.p(ax + s.c2.x, s.c2.y))
            }
            m.addLine(to: G.p(ax - 7.5, 43))
            let starts = [G.p(12.5, 95)] + segs.dropLast().map { $0.to }
            for i in stride(from: segs.count - 1, through: 0, by: -1) {
                let s = segs[i]
                m.addCurve(to: G.p(ax - starts[i].x, starts[i].y),
                           control1: G.p(ax - s.c2.x, s.c2.y), control2: G.p(ax - s.c1.x, s.c1.y))
            }
            m.closeSubpath()
        }
        let spout = tube(G.p(47, 66), G.p(70, 64), G.p(71, 36), G.p(84, 19), from: 11, to: 5.2)
            .union(G.circle(84, 19, 2.6))
        let handle = G.stroke(G.path { m in
            m.move(to: G.p(ax - 7, 47))
            m.addCurve(to: G.p(ax - 13, 74), control1: G.p(ax - 25, 44), control2: G.p(ax - 25, 72))
        }, 5.2)
        let dome = CGPath(ellipseIn: CGRect(x: ax - 11, y: 27, width: 22, height: 28), transform: nil)
            .intersection(G.rect(ax - 13, 20, 26, 21))
        let lid = dome.union(G.rrect(ax - 12.5, 39.5, 25, 5, 2.5))
        let finial = G.path { m in
            m.move(to: G.p(ax, 7))
            m.addCurve(to: G.p(ax + 4.6, 15.5), control1: G.p(ax + 2.6, 8.5), control2: G.p(ax + 4.6, 12))
            m.addCurve(to: G.p(ax + 1.6, 23), control1: G.p(ax + 4.6, 19.5), control2: G.p(ax + 3.2, 22.2))
            m.addLine(to: G.p(ax + 1.6, 29)); m.addLine(to: G.p(ax - 1.6, 29)); m.addLine(to: G.p(ax - 1.6, 23))
            m.addCurve(to: G.p(ax - 4.6, 15.5), control1: G.p(ax - 3.2, 22.2), control2: G.p(ax - 4.6, 19.5))
            m.addCurve(to: G.p(ax, 7), control1: G.p(ax - 4.6, 12), control2: G.p(ax - 2.6, 8.5))
            m.closeSubpath()
        }
        let cup = G.path { m in
            m.move(to: G.p(73, 79)); m.addLine(to: G.p(93, 79))
            m.addCurve(to: G.p(88, 95), control1: G.p(93, 86), control2: G.p(92, 95))
            m.addLine(to: G.p(78, 95))
            m.addCurve(to: G.p(73, 79), control1: G.p(74, 95), control2: G.p(73, 86))
            m.closeSubpath()
        }
        let coffee = CGPath(ellipseIn: CGRect(x: 74.5, y: 77.3, width: 17, height: 4.4), transform: nil)
        let steam = G.union([
            G.stroke(G.path { m in
                m.move(to: G.p(79.5, 75)); m.addCurve(to: G.p(80.5, 64), control1: G.p(75.5, 71.5), control2: G.p(84.5, 68))
            }, 2.4),
            G.stroke(G.path { m in
                m.move(to: G.p(86.5, 75)); m.addCurve(to: G.p(87.5, 65), control1: G.p(82.5, 72), control2: G.p(91.5, 69))
            }, 2.4)
        ])
        return FT5GObject(layers: [FT5GLayer(glass: handle),
                                   FT5GLayer(glass: body.union(spout)),
                                   FT5GLayer(glass: lid, gold: [finial]),
                                   FT5GLayer(glass: cup, detail: [coffee], light: [steam])],
                          specularLayer: 1, specular: G.p(30, 62), specularRadius: 18)
    }

    // MARK: التواصل — ظرف بختم شمع ذهبي مستدير

    static func envelope() -> FT5GObject {
        let body = G.rrect(5, 27, 90, 68, 7)
        let pocket = G.poly([G.p(6.5, 93.5), G.p(50, 57), G.p(93.5, 93.5)], r: 5).intersection(body)
        let flap = G.poly([G.p(6.5, 28.5), G.p(93.5, 28.5), G.p(50, 70)], r: 5).intersection(body)
        return FT5GObject(layers: [FT5GLayer(glass: body), FT5GLayer(glass: pocket),
                                   FT5GLayer(glass: flap, gold: [G.circle(50, 65, 10.5)])],
                          specularLayer: 2, specular: G.p(22, 36), specularRadius: 24)
    }

    // MARK: المكتبة ١ — رف الكتب: أربعة كتب قائمة بأطوال مختلفة على لوح، شريط ذهبي على أطولها

    static func shelf() -> FT5GObject {
        func book(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> FT5GLayer {
            FT5GLayer(glass: G.rrect(x, y, w, 89 - y, 3),
                      detail: [G.rrect(x + 4, y + 8, w - 8, 3, 1.5), G.rrect(x + 4, 78, w - 8, 2.4, 1.2)])
        }
        var tall = book(50, 5, 22)
        tall.detail = [G.rrect(54, 78, 14, 2.4, 1.2)]
        tall.gold = [G.rrect(54, 13, 14, 4.6, 2.3)]
        let board = FT5GLayer(glass: G.rrect(5, 88, 90, 7, 3.5))
        return FT5GObject(layers: [book(7, 23, 20), book(29.5, 35, 18), tall, book(74.5, 17, 19), board],
                          specularLayer: 2, specular: G.p(56, 16), specularRadius: 20)
    }

    // MARK: المكتبة ٢ — صور العائلة: صورتان متراكبتان، الأمامية بإطار ونافذة فيها جبال بيضاء وشمس ذهبية

    static func photos() -> FT5GObject {
        let back = G.rotate(G.rrect(24, 9, 66, 54, 5), 7, 57, 36)
        func rot(_ p: CGPath) -> CGPath { G.rotate(p, -4, 44, 59.5) }
        let frame = G.rrect(9, 26.5, 70, 66, 5)
        let window = G.rrect(15, 32.5, 58, 44, 3)
        let hills = G.poly([G.p(15, 76.5), G.p(15, 66), G.p(30, 52), G.p(41, 62), G.p(53, 49), G.p(73, 68), G.p(73, 76.5)], r: 2.5)
            .intersection(window)
        let sun = G.circle(61, 43, 5.5)
        return FT5GObject(layers: [FT5GLayer(glass: back),
                                   FT5GLayer(glass: rot(frame.subtracting(window)), light: [rot(hills)], haze: [rot(window)], gold: [rot(sun)])],
                          specularLayer: 1, specular: G.p(17, 33), specularRadius: 22)
    }

    // MARK: المكتبة ٣ — ملف الوثائق: ملف بلسان، تخرج منه ورقة مسطّرة، وجيبه الأمامي ببطاقة اسم ومشبك ذهبي

    static func folder() -> FT5GObject {
        let back = G.union([G.rrect(5, 22, 90, 73, 7), G.rrect(62, 12, 33, 20, 6)])
        func rot(_ p: CGPath) -> CGPath { G.rotate(p, -3, 35, 32) }
        let paper = rot(G.rrect(10, 7, 50, 50, 4))
        let lines = rot(G.union([G.rrect(18, 17, 34, 3.2, 1.6), G.rrect(18, 25, 28, 3.2, 1.6), G.rrect(18, 33, 34, 3.2, 1.6)]))
        let pocket = G.rrect(5, 45, 90, 50, 7)
        return FT5GObject(layers: [FT5GLayer(glass: back),
                                   FT5GLayer(glass: paper, detail: [lines]),
                                   FT5GLayer(glass: pocket, detail: [G.rrect(39, 63, 22, 3, 1.5)],
                                             light: [G.rrect(33, 59, 34, 11, 3.5)], gold: [G.circle(50, 81, 4.2)])],
                          specularLayer: 2, specular: G.p(16, 52), specularRadius: 24)
    }

    // MARK: المشاريع ١ — حقيبة العمل: مقبض خلفي، جسم، غطاء علوي، وقفل ذهبي

    static func briefcase() -> FT5GObject {
        let handle = G.stroke(G.path { m in
            m.move(to: G.p(36, 32)); m.addLine(to: G.p(36, 23))
            m.addQuadCurve(to: G.p(43, 16), control: G.p(36, 16))
            m.addLine(to: G.p(57, 16))
            m.addQuadCurve(to: G.p(64, 23), control: G.p(64, 16))
            m.addLine(to: G.p(64, 32))
        }, 6)
        let body = G.rrect(5, 30, 90, 65, 10)
        let lid = body.intersection(G.rect(0, 0, 100, 56))
        return FT5GObject(layers: [FT5GLayer(glass: handle), FT5GLayer(glass: body),
                                   FT5GLayer(glass: lid, gold: [G.rrect(42, 48, 16, 12, 3.5)])],
                          specularLayer: 2, specular: G.p(22, 40), specularRadius: 22)
    }

    // MARK: المشاريع ٢ — سهم النمو: ثلاثة أعمدة تصعد وسهم زجاجي يرتفع فوقها برأس ذهبي

    static func growth() -> FT5GObject {
        let bars = G.union([G.rrect(6, 60, 22, 35, 5), G.rrect(39, 44, 22, 51, 5), G.rrect(72, 28, 22, 67, 5)])
        let pts = [G.p(10, 50), G.p(34, 31), G.p(54, 39), G.p(84, 12)]
        let a = pts[2], b = pts[3]
        let dx = b.x - a.x, dy = b.y - a.y, len = (dx * dx + dy * dy).squareRoot()
        let ux = dx / len, uy = dy / len, nx = -uy, ny = ux
        let tip = G.p(b.x + ux * 9, b.y + uy * 9), base = G.p(b.x - ux * 3, b.y - uy * 3)
        let head = G.poly([tip, G.p(base.x + nx * 8.5, base.y + ny * 8.5), G.p(base.x - nx * 8.5, base.y - ny * 8.5)], r: 1.6)
        return FT5GObject(layers: [FT5GLayer(glass: bars), FT5GLayer(glass: G.line(pts, 7), gold: [head])],
                          specularLayer: 0, specular: G.p(76, 34), specularRadius: 18)
    }

    // MARK: المشاريع ٣ — مبنى الأعمال: برج زجاجي عالٍ بنوافذ (إحداها ذهبية مضاءة) وأمامه مبنى أقصر بباب

    static func towers() -> FT5GObject {
        var win: [CGPath] = []
        for row in 0..<6 {
            for col in 0..<2 where !(row == 1 && col == 1) {
                win.append(G.rrect(56 + CGFloat(col) * 15, 13 + CGFloat(row) * 12, 10, 6, 2))
            }
        }
        let tower = FT5GLayer(glass: G.rrect(48, 5, 42, 90, 5), detail: [G.union(win)], gold: [G.rrect(71, 25, 10, 6, 2)])
        var fw: [CGPath] = []
        for row in 0..<2 {
            for col in 0..<2 { fw.append(G.rrect(13 + CGFloat(col) * 16, 51 + CGFloat(row) * 12, 12, 6.5, 2)) }
        }
        fw.append(G.rrect(24, 78, 12, 17, 3))
        let front = FT5GLayer(glass: G.rrect(6, 42, 48, 53, 5), detail: [G.union(fw)])
        return FT5GObject(layers: [tower, front], specularLayer: 0, specular: G.p(56, 14), specularRadius: 18)
    }
}

/// مجسّم مربّع الرئيسية: Canvas ساكن يملأ إطاره (٤٨ في الوسط، ٨٦ للطيف)
struct FT5GObjectView: View {
    let place: String
    let variant: Int

    var body: some View {
        let place = self.place, variant = self.variant
        Canvas { ctx, size in
            if place == "tree" { FT5GObjectArt.drawTreeTile(in: &ctx, size: size); return }
            guard let o = FT5GObjectArt.object(place, variant: variant) else { return }
            FT5GObjectArt.draw(o, hue: FT5GObjectHue.of(place), in: &ctx, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
