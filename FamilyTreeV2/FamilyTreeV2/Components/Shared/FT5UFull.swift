import SwiftUI

// MARK: - FT5U — «سدو حديث» لكل التطبيق (الجولة ٥، ٢٠٢٦-١٠-٠٥)
//
// لغة واحدة: «قطعة نسيج» بلون القسم العميق، على حدّها خيط كريمي بأسنان سدو، وعلى محورها خيط السَّدى،
// وفي وسطها «رقعة» كريمية منسوج فيها رمز المكان (هي البطل)، وحولها عينا سدو (معيّن بحلقة كريمية وقلب أحمر).
//   • المربّعات ورؤوس المربّعات الوسطى: الحاشية عمودية على الحافّة الخلفية (كما أحبّها المالك في الجولة ٤).
//   • الصفحات الفاضية والانتظار والإشعارات ولحظات النجاح وبطاقة الأخبار: الحاشية أفقية بشراشيب على طرفيها.
//   • بطاقة رأس الصفحة (DSPageHero): قطعة معلّقة من أعلى البطاقة بشراشيب.
//   • الشارات والأيقونات الصغيرة: الرمز نفسه من الشبكة ذاتها.
// الرموز كلها على شبكة واحدة ١١×١١ بحواف أفقية/عمودية/٤٥° فقط، وثلاثة ألوان فقط: الكريمي ولون القسم ولمسة حمراء.
// «وفاة» والحِداد: رمادي ساكن بلا أحمر ولا ذهبي.
//
// الأداء: كل شيء ساكن — Canvas يُرسم مرة واحدة (يُعاد فقط إن تغيّر الحجم أو الوضع/الاتجاه). لا TimelineView ولا
// مؤقّت ولا blur ولا ظلال. الحركة الوحيدة: (١) مكّوك تحميل الشجرة يتحرّك أفقياً بحركة ضمنية واحدة (إزاحة فقط)،
// (٢) لحظات النجاح تنفتح مرة واحدة (قناع يتّسع + رقعة تكبر) ثم تسكن. «تقليل الحركة» = الإطار الأخير مباشرة.
// كل الرسوم مخفيّة عن القارئ الصوتي ولا تلتقط اللمس، وتنعكس للإنجليزية (ما عدا سهم النموّ: يصعد يميناً دائماً).
//
// الجولة ٨ (٢٠٢٦-١٠-٠٦): مربّعات الرئيسية صارت «مجسّمات منسوجة» في الوسط (غافة، دلّة وفنجان، ظرف بختم، المكتبة
// والمشاريع بأشكالها الثلاثة) على شبكة ٢٠×٢٠ مدرّجة: جسم كريمي، تفاصيل بلون القسم العميق، معيّن ذهبي واحد، وظلّ تماس؛
// والحاشية العريضة صارت حاشية رفيعة (٨ نقاط) على الحافّة العلوية. الرقع والرؤوس والحالات تستعمل الرموز المنسوجة نفسها.

// MARK: - الواجهة (العقد)

@MainActor enum FT5UTrial {
    /// الرقعة المنسوجة تحلّ محلّ الدائرة الزجاجية (لا رمزان لشيء واحد) — العدد ينتقل مكانها
    static let showsTileIcon: Bool = false
    /// الحاشية جزء من نسيج المربّع: تحت طبقة الإضاءة/التعتيم
    static let tileArtUnderOverlay: Bool = true

    static let libraryVariantNames: [String] = ["رف الكتب", "صندوق المبيّت", "الوثيقة"]
    static let projectsVariantNames: [String] = ["حقيبة العمل", "سفينة البوم", "سهم النموّ"]

    /// لا حاشية جانبية بعد الجولة ٨ — العنوان لا يحتاج مسافة
    static func tileTitleInset(width: CGFloat) -> CGFloat { 0 }

    /// مجسّم مربّع الرئيسية في مربّع مركزي (المجسّم والاسم بالوسط): الرمز المنسوج يملأ إطاره
    static func tileIcon(_ place: String, variant: Int) -> AnyView? {
        guard case .glyph(let g) = FT5U.tileGlyph(place, variant: variant), FT5U.isWoven(g) else { return nil }
        return AnyView(FT5UObjectArt(glyph: g, deep: ArtPalette.section(for: place).deep))
    }
    /// شفافية النسخة الكبيرة من المجسّم في خلفية مربّع الرئيسية (علامة مائية كريمية هادئة)
    static let ghostOpacity: Double = 0.16
    static func tile(_ place: String, variant: Int, badge: Bool, animateOnce: Bool) -> AnyView {
        AnyView(FT5UTileArt(place: place, variant: variant))
    }

    static func header(icon: String, tint: Color, deep: Color) -> AnyView {
        AnyView(FT5UHeaderArt(icon: icon, deep: deep))
    }

    static func empty(place: String?, icon: String, tint: Color) -> AnyView {
        AnyView(FT5UBandArt(mark: FT5U.mark(place: place, icon: icon), mourning: FT5U.isMourning(icon),
                            ground: tint, band: CGSize(width: 112, height: 54), cell: 3))
    }

    static func stateIcon(icon: String, tint: Color, size: CGFloat) -> AnyView {
        AnyView(FT5UPatchIcon(mark: FT5U.mark(forIcon: icon), mourning: FT5U.isMourning(icon), tint: tint)
            .frame(width: size, height: size))
    }

    static func treeLoading() -> AnyView { AnyView(FT5UTreeLoading()) }

    static func waiting() -> AnyView {
        AnyView(FT5UBandArt(mark: .glyph(.hourglass), mourning: false,
                            ground: FT5U.adaptive(0x47467F, 0x525190), band: CGSize(width: 118, height: 56), cell: 3))
    }

    static func notificationsEmpty() -> AnyView {
        AnyView(FT5UBandArt(mark: .glyph(.bell), mourning: false,
                            ground: FT5U.adaptive(0x1F4E79, 0x285D8D), band: CGSize(width: 104, height: 52), cell: 3))
    }

    static func loginBackdrop(logoCenterY: CGFloat) -> AnyView {
        AnyView(FT5UStatic { ctx, size in FT5U.drawBackdrop(&ctx, size: size, logoY: logoCenterY) })
    }

    static func newsBadge(type: String, tint: Color, onColor: Bool) -> AnyView? {
        guard let g = FT5U.newsGlyph(type) else { return nil }
        let mourning = type == "وفاة"
        return AnyView(FT5UStatic { ctx, size in
            FT5U.drawBadge(&ctx, size: size, glyph: g, tint: tint, onColor: onColor, mourning: mourning)
        })
    }

    static func moment(_ name: String, tint: Color) -> AnyView {
        AnyView(FT5UMoment(glyph: FT5U.momentGlyph(name), tint: tint))
    }

    static func greetingGlyph(hour: Int, tint: Color) -> AnyView {
        AnyView(FT5UStatic { ctx, size in FT5U.drawGreetingGlyph(&ctx, size: size, hour: hour, tint: tint) })
    }

    static func greetingBackground(tint: Color) -> AnyView? {
        AnyView(FT5UStatic { ctx, size in FT5U.drawGreetingEdge(&ctx, size: size, tint: tint) })
    }

    // MARK: الإضافة (الأخبار، الشجرة، الديوانيات، حسابي، الإدارة)

    static func tabHeaderOrnament(section: String, tint: Color) -> AnyView? {
        AnyView(FT5UStatic { ctx, size in FT5U.drawOrnament(&ctx, size: size) }.frame(height: 12))
    }

    static func pageHeroArt(icon: String, tint: Color) -> AnyView? {
        let mark = FT5U.mark(forIcon: icon), mourning = FT5U.isMourning(icon)
        return AnyView(FT5UStatic { ctx, size in
            FT5U.drawPennant(&ctx, size: size, mark: mark, tint: tint, mourning: mourning)
        })
    }

    static func dashTileArt(icon: String, tint: Color) -> AnyView? {
        AnyView(FT5UPatchIcon(mark: FT5U.mark(forIcon: icon), mourning: FT5U.isMourning(icon), tint: tint)
            .frame(maxWidth: 40, maxHeight: 40))
    }

    static func newsCardArt(tint: Color) -> AnyView? {
        AnyView(FT5UBandArt(mark: .glyph(.newspaper), mourning: false, ground: tint,
                            band: CGSize(width: 56, height: 30), cell: 2, fringe: 0)
            .frame(maxWidth: 60, maxHeight: 44))
    }
}

// MARK: - الرموز

nonisolated enum FT5UGlyph: String, CaseIterable, Sendable {
    case tree, dalla, envelope
    case shelf, chest, scroll            // المكتبة
    case briefcase, dhow, growth         // المشاريع
    case newspaper, megaphone, person, personPlus, people, lock, shield, gear, crescent
    case bell, hourglass, check, plane, rosette, star, rings, pram, ballot, finjan, alarm
}

nonisolated enum FT5UMark: Sendable {
    case glyph(FT5UGlyph)
    /// أي رمز SF — يُنسج في الرقعة بلون الأرضية (المعالجة العامة)
    case sf(String)
    /// عين سدو كبيرة (لا رمز)
    case eye
}

nonisolated struct FT5UInk: Sendable {
    let cream: Color
    let red: Color
    /// أحمر أفتح قليلاً للرموز الكريمية فوق أرضية ملوّنة
    let redOnGround: Color

    static func of(dark: Bool, mourning: Bool = false) -> FT5UInk {
        if mourning {
            return dark ? FT5UInk(cream: FT5U.hex(0xC7C7CC), red: FT5U.hex(0x8E8E93), redOnGround: FT5U.hex(0x8E8E93))
                        : FT5UInk(cream: FT5U.hex(0xE5E5EA), red: FT5U.hex(0x8E8E93), redOnGround: FT5U.hex(0xAEAEB2))
        }
        return dark ? FT5UInk(cream: FT5U.hex(0xE6D6B4), red: FT5U.hex(0xCB4A3C), redOnGround: FT5U.hex(0xD9594A))
                    : FT5UInk(cream: FT5U.hex(0xF2E5C9), red: FT5U.hex(0xBE3B2F), redOnGround: FT5U.hex(0xD24F40))
    }
}

/// لون تعبئة + تعتيم أسود فوقه (يحاكي طبقة التعتيم في الداكن) + شفافية
nonisolated struct FT5UPaint: Sendable {
    var color: Color
    var shade: Double = 0
    var opacity: Double = 1
}

/// الرمز: طبقات بالترتيب — جسم (لون الأرضية)، لمسة (أحمر)، محو (يكشف ما تحت الرقعة)
nonisolated struct FT5USym {
    enum Role { case main, accent, erase }
    var layers: [(Path, Role, Bool)] = []
    /// لا ينعكس في الإنجليزية
    var fixed = false
    mutating func m(_ p: Path, eo: Bool = false) { layers.append((p, .main, eo)) }
    mutating func a(_ p: Path, eo: Bool = false) { layers.append((p, .accent, eo)) }
    mutating func x(_ p: Path) { layers.append((p, .erase, false)) }
}

// MARK: - المحرّك

nonisolated enum FT5U {
    static let grid: CGFloat = 11
    static let thread: CGFloat = 1.5

    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    /// لون يتبع الوضع (للأماكن التي لا يمرّر التطبيق لونها)
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex(dark)) : UIColor(hex(light)) })
        #else
        return Color(NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex(dark)) : NSColor(hex(light))
        })
        #endif
    }

    // MARK: المقاسات

    /// المربّع العريض (≥ ١٥٠) شبكة ٣ نقاط (رمز ٣٣)، وإلا نقطتان (رمز ٢٢)
    static func tileCell(width: CGFloat) -> CGFloat { width >= 150 ? 3 : 2 }
    static func tileStrip(width: CGFloat) -> CGFloat {
        let margin: CGFloat = width >= 150 ? 4 : 2.5
        return tileCell(width: width) * grid + 4 + 2 * margin + thread
    }
    /// رأس المربّعات الوسطى (٨٦): شبكة ٣ ← حاشية ٤٦٫٥
    static let headerCell: CGFloat = 3
    static var headerStrip: CGFloat { headerCell * grid + 4 + 8 + thread }

    // MARK: ألوان الأماكن (المربّعات لا تمرّر لونها)

    static func tileDeep(_ place: String, dark: Bool) -> Color {
        switch place {
        case "tree": return hex(dark ? 0x092823 : 0x0D332D)
        case "diwaniya", "diwaniyas": return hex(dark ? 0x09262E : 0x0D313A)
        case "library": return hex(dark ? 0x2D1833 : 0x392041)
        case "projects": return hex(dark ? 0x0D2915 : 0x13341C)
        case "contact", "admin": return hex(dark ? 0x1E1C3E : 0x28274B)
        case "news": return hex(dark ? 0x082534 : 0x0D3041)
        case "profile": return hex(dark ? 0x142240 : 0x192A50)
        default: return hex(dark ? 0x0E2238 : 0x102B47)
        }
    }

    static func tileGlyph(_ place: String, variant: Int) -> FT5UMark {
        let v = ((variant % 3) + 3) % 3
        switch place {
        case "tree": return .glyph(.tree)
        case "diwaniya", "diwaniyas": return .glyph(.dalla)
        case "library": return .glyph([FT5UGlyph.shelf, .chest, .scroll][v])
        case "projects": return .glyph([FT5UGlyph.briefcase, .dhow, .growth][v])
        case "contact": return .glyph(.envelope)
        case "news": return .glyph(.newspaper)
        default: return .eye
        }
    }

    // MARK: ربط رموز SF بالعائلات

    static func isMourning(_ icon: String) -> Bool { icon.hasPrefix("heart.slash") }

    static func mark(forIcon icon: String) -> FT5UMark {
        let i = icon
        func any(_ p: [String]) -> Bool { p.contains { i.hasPrefix($0) } }
        if any(["heart.slash"]) { return .glyph(.crescent) }
        if any(["newspaper", "square.and.pencil", "doc.richtext"]) { return .glyph(.newspaper) }
        if any(["megaphone", "speaker"]) { return .glyph(.megaphone) }
        if any(["map", "mappin", "cup.and.saucer", "tent", "building.columns", "house"]) { return .glyph(.dalla) }
        if any(["storefront", "briefcase", "bag", "cart"]) { return .glyph(.briefcase) }
        if any(["books", "book", "archivebox", "doc.text"]) { return .glyph(.shelf) }
        if any(["tree", "leaf"]) { return .glyph(.tree) }
        if any(["person.badge.plus", "person.crop.circle.badge.plus", "figure.child", "person.fill.badge.plus"]) {
            return .glyph(.personPlus)
        }
        if any(["person.2", "person.3", "figure.2", "figure.and.child"]) { return .glyph(.people) }
        if any(["person", "figure"]) { return .glyph(.person) }
        if any(["envelope", "tray", "message", "bubble"]) { return .glyph(.envelope) }
        if any(["lock"]) { return .glyph(.lock) }
        if any(["shield", "checkmark.shield", "exclamationmark.shield"]) { return .glyph(.shield) }
        if any(["gearshape", "gear", "slider", "paintbrush", "key", "iphone", "wrench"]) { return .glyph(.gear) }
        if any(["bell"]) { return .glyph(.bell) }
        if any(["hourglass", "clock", "timer"]) { return .glyph(.hourglass) }
        if any(["checkmark.seal", "rosette", "medal"]) { return .glyph(.rosette) }
        if any(["checkmark"]) { return .glyph(.check) }
        if any(["paperplane"]) { return .glyph(.plane) }
        if any(["chart"]) { return .glyph(.growth) }
        if any(["star", "sparkles", "hands.clap"]) { return .glyph(.star) }
        return icon.isEmpty ? .eye : .sf(icon)
    }

    static func mark(place: String?, icon: String) -> FT5UMark {
        switch place {
        case "tree": return .glyph(.tree)
        case "diwaniya", "diwaniyas": return .glyph(.dalla)
        case "library": return .glyph(.shelf)
        case "projects": return .glyph(.briefcase)
        case "contact", "messages": return .glyph(.envelope)
        case "news": return .glyph(.newspaper)
        case "notifications": return .glyph(.bell)
        case "members": return .glyph(.people)
        case "profile": return .glyph(.person)
        case "requests", "pending": return .glyph(.hourglass)
        default: return mark(forIcon: icon)
        }
    }

    static func newsGlyph(_ type: String) -> FT5UGlyph? {
        switch type {
        case "خبر": return .newspaper
        case "إعلان": return .megaphone
        case "تهنئة": return .star
        case "زواج": return .rings
        case "مولود": return .pram
        case "وفاة": return .crescent
        case "تصويت": return .ballot
        case "دعوة": return .finjan
        case "تذكير": return .alarm
        default: return nil
        }
    }

    static func momentGlyph(_ name: String) -> FT5UGlyph {
        switch name {
        case "sentForApproval": return .plane
        case "approved": return .rosette
        case "newMember": return .personPlus
        default: return .check
        }
    }

    // MARK: أدوات الهندسة

    static func poly(_ raw: [(CGFloat, CGFloat)]) -> Path {
        var area: CGFloat = 0
        for i in raw.indices {
            let p = raw[i], q = raw[(i + 1) % raw.count]
            area += p.0 * q.1 - q.0 * p.1
        }
        let pts = area < 0 ? Array(raw.reversed()) : raw
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: CGPoint(x: f.0, y: f.1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)])
    }

    static func diamond(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        poly([(x, y - r), (x + r, y), (x, y + r), (x - r, y)])
    }

    /// مثمّن بحواف أفقية/عمودية/٤٥°: نصفا القطر rx/ry والشطف k
    static func oct(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ k: CGFloat) -> Path {
        poly([(cx - rx + k, cy - ry), (cx + rx - k, cy - ry), (cx + rx, cy - ry + k), (cx + rx, cy + ry - k),
              (cx + rx - k, cy + ry), (cx - rx + k, cy + ry), (cx - rx, cy + ry - k), (cx - rx, cy - ry + k)])
    }

    static func bar(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ w: CGFloat) -> Path {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / len * w / 2, ny = dx / len * w / 2
        return poly([(a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny)])
    }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    static func isLTR(_ ctx: GraphicsContext) -> Bool { ctx.environment.layoutDirection == .leftToRight }
    static func isDark(_ ctx: GraphicsContext) -> Bool { ctx.environment.colorScheme == .dark }

    /// الرسم بإحداثيات عربية ويُعكس للإنجليزية
    static func mirrorForLTR(_ ctx: inout GraphicsContext, width: CGFloat) {
        if isLTR(ctx) {
            ctx.translateBy(x: width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
    }

    static func fill(_ c: inout GraphicsContext, _ p: Path, _ paint: FT5UPaint, eo: Bool = false) {
        let style = FillStyle(eoFill: eo)
        c.fill(p, with: .color(paint.color.opacity(paint.opacity)), style: style)
        if paint.shade > 0 { c.fill(p, with: .color(.black.opacity(paint.shade * paint.opacity)), style: style) }
    }

    // MARK: الرموز (شبكة ١١×١١)

    static func sym(_ g: FT5UGlyph) -> FT5USym {
        var s = FT5USym()
        switch g {
        case .tree:
            s.m(poly([(3.3, 0.5), (7.7, 0.5), (10.3, 3.1), (10.3, 4.9), (7.9, 7.3), (3.1, 7.3), (0.7, 4.9), (0.7, 3.1)]))
            s.m(rect(4.8, 6.5, 1.4, 3.0))
            s.m(poly([(4.8, 9.0), (6.2, 9.0), (7.4, 10.2), (3.6, 10.2)]))
            s.m(rect(2.0, 10.2, 7.0, 0.8))
            s.x(rect(5.1, 3.6, 0.8, 3.7))
            s.x(bar((5.5, 6.0), (3.0, 3.5), 0.8))
            s.x(bar((5.5, 6.0), (8.0, 3.5), 0.8))
            s.a(diamond(5.5, 2.5, 1.2))
        case .dalla:
            s.m(diamond(6.2, 0.9, 0.9))
            s.m(poly([(5.5, 1.6), (6.9, 1.6), (7.9, 3.4), (4.5, 3.4)]))
            s.m(rect(4.0, 3.4, 4.4, 0.8))
            s.m(poly([(5.0, 4.2), (7.4, 4.2), (7.0, 5.8), (5.4, 5.8)]))
            s.m(poly([(5.4, 5.8), (7.0, 5.8), (9.0, 7.8), (9.0, 9.4), (8.3, 10.1), (4.1, 10.1), (3.4, 9.4), (3.4, 7.8)]))
            s.m(rect(3.8, 10.1, 4.8, 0.9))
            s.m(bar((4.1, 9.0), (0.9, 5.8), 1.15))
            s.m(poly([(1.31, 5.39), (0.49, 6.21), (0.3, 4.4)]))
            s.m(rect(8.0, 4.3, 2.6, 1.0))
            s.m(rect(9.6, 4.3, 1.0, 3.5))
            s.m(bar((10.1, 7.4), (8.6, 8.9), 1.0))
            s.a(rect(3.4, 7.8, 5.6, 0.8))
        case .envelope:
            s.m(rect(0.5, 2.3, 10.0, 7.2))
            s.x(bar((0.7, 2.6), (5.5, 6.6), 0.6))
            s.x(bar((10.3, 2.6), (5.5, 6.6), 0.6))
            s.a(diamond(5.5, 6.6, 1.6))

        case .shelf:
            // رف الكتب: ثلاثة كتب قائمة (الأوسط أحمر وأطولها) وكومة كتابين مسطّحين، على لوح بكتيفتين
            let xs: [CGFloat] = [0.5, 2.75, 5.0]
            let ws: [CGFloat] = [1.85, 1.85, 1.7]
            let tops: [CGFloat] = [2.2, 0.8, 3.0]
            for i in 0..<3 {
                let b = rect(xs[i], tops[i], ws[i], 9.0 - tops[i])
                if i == 1 { s.a(b) } else { s.m(b) }
                s.x(rect(xs[i], tops[i] + 1.1, ws[i], 0.55))
            }
            s.m(rect(7.1, 7.3, 3.4, 1.7))
            s.m(rect(7.5, 5.2, 2.8, 1.7))
            s.x(rect(9.2, 7.3, 0.45, 1.7))
            s.x(rect(8.6, 5.2, 0.45, 1.7))
            s.m(rect(0.2, 9.0, 10.6, 1.0))
            s.m(poly([(1.2, 10.0), (2.6, 10.0), (1.2, 11.0)]))
            s.m(poly([(9.8, 10.0), (8.4, 10.0), (9.8, 11.0)]))
        case .chest:
            // صندوق المبيّت: غطاء مشطوف بمسامير، وجسم بإطار نحاسي، وقفل أحمر في الوسط
            s.m(poly([(0.5, 3.6), (1.7, 2.4), (9.3, 2.4), (10.5, 3.6), (10.5, 4.8), (0.5, 4.8)]))
            s.m(rect(0.5, 5.4, 10.0, 4.4))
            s.m(rect(1.0, 9.8, 1.6, 0.9))
            s.m(rect(8.4, 9.8, 1.6, 0.9))
            for x in [2.1, 3.5, 7.5, 8.9] as [CGFloat] { s.x(diamond(x, 3.6, 0.5)) }
            s.x(rect(1.5, 6.3, 8.0, 0.5))
            s.x(rect(1.5, 8.5, 8.0, 0.5))
            s.x(rect(1.5, 6.3, 0.5, 2.7))
            s.x(rect(9.0, 6.3, 0.5, 2.7))
            s.a(rect(4.4, 3.8, 2.2, 3.4))
            s.x(oct(5.5, 5.0, 0.6, 0.6, 0.25))
            s.x(rect(5.2, 5.3, 0.6, 1.2))
        case .scroll:
            // الوثيقة: مخطوطة بلفّتين، وأسطر مقصوصة (محاذاة عربية)، وختم أحمر
            s.m(rect(1.4, 0.6, 8.2, 1.7))
            s.m(rect(0.5, 0.95, 1.0, 1.0))
            s.m(rect(9.5, 0.95, 1.0, 1.0))
            s.m(rect(2.2, 2.3, 6.6, 6.4))
            s.m(rect(1.4, 8.7, 8.2, 1.7))
            s.m(rect(0.5, 9.05, 1.0, 1.0))
            s.m(rect(9.5, 9.05, 1.0, 1.0))
            s.x(rect(1.4, 2.2, 8.2, 0.45))
            s.x(rect(1.4, 8.55, 8.2, 0.45))
            s.x(rect(3.3, 3.5, 4.4, 0.6))
            s.x(rect(4.5, 4.9, 3.2, 0.6))
            s.x(rect(3.3, 6.3, 4.4, 0.6))
            s.a(diamond(4.0, 7.4, 1.25))

        case .briefcase:
            s.m(rect(3.6, 1.0, 3.8, 0.9))
            s.m(rect(3.6, 1.0, 0.9, 2.6))
            s.m(rect(6.5, 1.0, 0.9, 2.6))
            s.m(poly([(0.5, 4.2), (1.2, 3.5), (9.8, 3.5), (10.5, 4.2), (10.5, 9.7), (9.8, 10.4), (1.2, 10.4), (0.5, 9.7)]))
            s.x(rect(0.5, 6.3, 10.0, 0.5))
            s.a(rect(4.4, 5.5, 2.2, 2.1))
        case .dhow:
            // سفينة البوم: صارٍ، شراع لاتيني، وشراع أمامي أحمر، وبدن بطرفين ٤٥°، وموج من أسنان السدو
            s.m(rect(5.1, 0.3, 0.8, 6.0))
            s.m(poly([(4.7, 0.9), (4.7, 5.4), (0.2, 5.4)]))
            s.a(poly([(6.3, 1.6), (6.3, 5.4), (10.1, 5.4)]))
            s.m(poly([(0.3, 6.1), (10.7, 6.1), (8.4, 8.4), (2.6, 8.4)]))
            s.x(rect(2.0, 6.9, 7.0, 0.45))
            for i in 0..<5 {
                let x0 = 0.5 + CGFloat(i) * 2
                s.m(poly([(x0, 10.6), (x0 + 1, 9.6), (x0 + 2, 10.6)]))
            }
        case .growth:
            s.fixed = true
            s.m(rect(0.8, 7.4, 2.2, 2.2))
            s.m(rect(4.4, 5.4, 2.2, 4.2))
            s.m(rect(8.0, 3.4, 2.2, 6.2))
            s.m(rect(0.4, 10.0, 10.2, 0.8))
            s.a(bar((1.0, 6.0), (5.4, 1.6), 1.1))
            s.a(poly([(6.6, 0.4), (6.6, 3.6), (3.4, 0.4)]))

        case .newspaper:
            s.m(rect(0.5, 3.4, 1.9, 6.6))
            s.m(rect(2.0, 0.8, 8.5, 9.2))
            s.x(rect(2.0, 3.4, 0.5, 6.6))
            s.a(rect(3.3, 2.0, 5.9, 1.4))
            s.x(rect(3.3, 4.4, 5.9, 0.55))
            s.x(rect(6.6, 5.7, 2.6, 0.55))
            s.x(rect(6.6, 7.0, 2.6, 0.55))
            s.x(rect(6.6, 8.3, 2.6, 0.55))
            s.x(rect(3.3, 5.7, 2.6, 3.15))
        case .megaphone:
            s.a(rect(1.0, 1.0, 1.1, 9.0))
            s.m(poly([(2.1, 1.0), (3.2, 1.0), (6.2, 4.0), (8.4, 4.0), (8.4, 7.0), (6.2, 7.0), (3.2, 10.0), (2.1, 10.0)]))
            s.m(rect(8.9, 3.6, 1.6, 3.8))
            s.m(rect(6.4, 7.0, 1.3, 2.8))
        case .person:
            s.m(oct(5.5, 2.9, 2.1, 2.1, 0.9))
            s.m(poly([(1.6, 10.5), (1.6, 8.6), (3.8, 6.4), (7.2, 6.4), (9.4, 8.6), (9.4, 10.5)]))
            s.a(diamond(5.5, 8.5, 1.0))
        case .personPlus:
            s.m(oct(6.4, 3.3, 2.0, 2.0, 0.85))
            s.m(poly([(2.8, 10.5), (2.8, 8.9), (4.9, 6.8), (7.9, 6.8), (10.0, 8.9), (10.0, 10.5)]))
            s.a(rect(1.75, 0.5, 1.1, 4.4))
            s.a(rect(0.1, 2.15, 4.4, 1.1))
        case .people:
            s.m(oct(2.75, 3.4, 1.65, 1.65, 0.7))
            s.m(poly([(0.5, 10.5), (0.5, 7.4), (1.55, 6.35), (3.95, 6.35), (5.0, 7.4), (5.0, 10.5)]))
            s.a(oct(8.25, 3.4, 1.65, 1.65, 0.7))
            s.a(poly([(6.0, 10.5), (6.0, 7.4), (7.05, 6.35), (9.45, 6.35), (10.5, 7.4), (10.5, 10.5)]))
        case .lock:
            s.m(rect(3.0, 0.7, 5.0, 1.1))
            s.m(rect(3.0, 0.7, 1.1, 3.8))
            s.m(rect(6.9, 0.7, 1.1, 3.8))
            s.m(oct(5.5, 7.45, 4.2, 3.05, 0.8))
            s.x(oct(5.5, 6.6, 1.0, 1.0, 0.4))
            s.x(rect(5.05, 7.0, 0.9, 2.0))
        case .shield:
            s.m(poly([(1.0, 1.0), (10.0, 1.0), (10.0, 6.0), (5.5, 10.5), (1.0, 6.0)]))
            s.x(poly([(2.0, 2.0), (9.0, 2.0), (9.0, 5.6), (5.5, 9.1), (2.0, 5.6)]))
            s.m(poly([(2.6, 2.6), (8.4, 2.6), (8.4, 5.35), (5.5, 8.25), (2.6, 5.35)]))
            s.a(poly([(2.9, 5.0), (4.7, 6.8), (8.1, 3.4), (7.3, 2.6), (4.7, 5.2), (3.7, 4.2)]))
        case .gear:
            s.m(rect(4.6, 0.3, 1.8, 1.8))
            s.m(rect(4.6, 8.9, 1.8, 1.8))
            s.m(rect(0.3, 4.6, 1.8, 1.8))
            s.m(rect(8.9, 4.6, 1.8, 1.8))
            for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
                s.m(diamond(5.5 + dx * 3.05, 5.5 + dy * 3.05, 1.3))
            }
            s.m(oct(5.5, 5.5, 3.9, 3.9, 1.6))
            s.x(oct(5.5, 5.5, 2.0, 2.0, 0.85))
            s.a(diamond(5.5, 5.5, 1.0))
        case .crescent:
            s.m(circle(5.0, 5.8, 4.6))
            s.x(circle(7.0, 4.4, 3.9))
            s.a(poly([(8.4, 5.6), (8.85, 6.75), (10.0, 7.2), (8.85, 7.65), (8.4, 8.8), (7.95, 7.65), (6.8, 7.2), (7.95, 6.75)]))
        case .bell:
            s.m(diamond(5.5, 0.9, 0.8))
            s.m(poly([(3.6, 1.8), (7.4, 1.8), (8.4, 2.8), (8.4, 7.2), (10.2, 9.0), (0.8, 9.0), (2.6, 7.2), (2.6, 2.8)]))
            s.x(rect(2.6, 6.1, 5.8, 0.5))
            s.a(diamond(5.5, 10.2, 0.85))
        case .hourglass:
            s.m(rect(1.4, 0.4, 8.2, 1.1))
            s.m(rect(1.4, 9.5, 8.2, 1.1))
            s.m(poly([(2.4, 1.5), (8.6, 1.5), (8.6, 2.8), (6.1, 5.3), (6.1, 5.7), (8.6, 8.2), (8.6, 9.5),
                      (2.4, 9.5), (2.4, 8.2), (4.9, 5.7), (4.9, 5.3), (2.4, 2.8)]))
            s.x(poly([(3.2, 2.1), (7.8, 2.1), (7.8, 2.5), (5.5, 4.8), (3.2, 2.5)]))
            s.x(poly([(5.5, 6.2), (7.8, 8.5), (7.8, 8.9), (3.2, 8.9), (3.2, 8.5)]))
            s.a(poly([(4.2, 3.1), (6.8, 3.1), (5.5, 4.4)]))
            s.a(poly([(3.6, 8.9), (7.4, 8.9), (5.5, 7.0)]))
        case .check:
            s.m(poly([(0.9, 6.3), (2.3, 4.9), (4.4, 7.0), (8.9, 2.5), (10.3, 3.9), (4.4, 9.8)]))
        case .plane:
            // يشير للأمام بالعربية (أعلى اليسار) — ينعكس للإنجليزية
            s.m(poly([(0.6, 0.6), (10.4, 4.8), (6.4, 6.4)]))
            s.a(poly([(0.6, 0.6), (6.4, 6.4), (4.8, 10.4)]))
            s.x(bar((0.6, 0.6), (6.4, 6.4), 0.5))
        case .rosette:
            s.a(poly([(2.6, 6.8), (4.8, 6.8), (4.8, 10.8), (3.7, 9.7), (2.6, 10.8)]))
            s.a(poly([(6.2, 6.8), (8.4, 6.8), (8.4, 10.8), (7.3, 9.7), (6.2, 10.8)]))
            s.m(rect(2.55, 1.85, 5.9, 5.9))
            s.m(diamond(5.5, 4.8, 4.15))
            s.x(poly([(3.4, 4.8), (4.8, 6.2), (7.7, 3.3), (7.0, 2.6), (4.8, 4.8), (4.1, 4.1)]))
        case .star:
            s.m(rect(2.0, 2.0, 7.0, 7.0))
            s.m(diamond(5.5, 5.5, 4.95))
            s.x(diamond(5.5, 5.5, 2.7))
            s.a(diamond(5.5, 5.5, 1.5))
        case .rings:
            // خاتم بفصّ أحمر
            var r = oct(5.5, 7.1, 3.7, 3.7, 1.55)
            r.addPath(oct(5.5, 7.1, 2.45, 2.45, 1.0))
            s.m(r, eo: true)
            s.m(poly([(4.3, 3.6), (4.8, 2.9), (6.2, 2.9), (6.7, 3.6)]))
            s.a(poly([(5.5, 0.2), (7.3, 1.6), (5.5, 3.0), (3.7, 1.6)]))
        case .pram:
            s.a(poly([(1.0, 5.0), (1.0, 3.0), (3.0, 1.0), (5.2, 1.0), (5.2, 5.0)]))
            s.m(poly([(1.0, 5.6), (10.0, 5.6), (10.0, 6.4), (8.6, 7.8), (2.4, 7.8), (1.0, 6.4)]))
            s.m(rect(9.2, 2.4, 0.9, 3.2))
            s.m(rect(9.2, 2.4, 1.7, 0.9))
            s.m(oct(3.2, 9.4, 1.4, 1.4, 0.6))
            s.m(oct(7.8, 9.4, 1.4, 1.4, 0.6))
            s.x(diamond(3.2, 9.4, 0.5))
            s.x(diamond(7.8, 9.4, 0.5))
        case .ballot:
            s.a(rect(3.5, 0.6, 4.0, 4.9))
            s.x(poly([(4.3, 3.0), (5.2, 3.9), (6.9, 2.2), (6.5, 1.8), (5.2, 3.1), (4.7, 2.6)]))
            s.m(rect(0.5, 5.5, 10.0, 1.0))
            s.m(rect(1.2, 7.0, 8.6, 3.6))
            s.x(rect(3.6, 5.85, 3.8, 0.35))
            s.x(rect(1.2, 8.4, 8.6, 0.45))
        case .finjan:
            s.a(rect(3.9, 1.6, 0.85, 2.3))
            s.a(rect(5.1, 0.5, 0.85, 3.4))
            s.a(rect(6.3, 1.6, 0.85, 2.3))
            s.m(poly([(1.6, 4.5), (9.4, 4.5), (9.4, 5.7), (7.1, 8.0), (3.9, 8.0), (1.6, 5.7)]))
            s.x(rect(1.6, 5.3, 7.8, 0.45))
            s.m(rect(0.6, 8.6, 9.8, 1.0))
        case .alarm:
            s.a(poly([(0.4, 2.6), (2.6, 0.4), (3.4, 1.2), (1.2, 3.4)]))
            s.a(poly([(10.6, 2.6), (8.4, 0.4), (7.6, 1.2), (9.8, 3.4)]))
            s.m(oct(5.5, 6.4, 4.2, 4.2, 1.7))
            s.x(oct(5.5, 6.4, 3.1, 3.1, 1.25))
            s.m(rect(5.1, 4.1, 0.8, 2.7))
            s.m(rect(5.1, 6.0, 2.5, 0.8))
            s.a(diamond(5.5, 6.4, 0.75))
        }
        return s
    }

    /// يرسم الرمز في طبقة واحدة (المحو يكشف ما تحته: الرقعة أو الأرضية أو الدائرة)
    static func drawSym(_ s: FT5USym, in c: inout GraphicsContext, center: CGPoint, cell: CGFloat,
                        main: FT5UPaint, accent: FT5UPaint, ltr: Bool) {
        c.drawLayer { l in
            l.translateBy(x: center.x, y: center.y)
            if s.fixed && ltr { l.scaleBy(x: -1, y: 1) }
            l.scaleBy(x: cell, y: cell)
            l.translateBy(x: -grid / 2, y: -grid / 2)
            for (p, role, eo) in s.layers {
                switch role {
                case .main: fill(&l, p, main, eo: eo)
                case .accent: fill(&l, p, accent, eo: eo)
                case .erase:
                    var e = l
                    e.blendMode = .destinationOut
                    e.fill(p, with: .color(.black), style: FillStyle(eoFill: eo))
                }
            }
        }
    }

    /// رمز SF منسوج (المعالجة العامة) — لا ينعكس (النظام يعكس ما يلزم بنفسه)
    static func drawSF(_ name: String, in c: inout GraphicsContext, center: CGPoint, side: CGFloat,
                       color: Color, ltr: Bool) {
        var g = c
        g.translateBy(x: center.x, y: center.y)
        if ltr { g.scaleBy(x: -1, y: 1) }
        let img = g.resolve(Text(Image(systemName: name)).font(.system(size: side * 0.72, weight: .bold))
            .foregroundColor(color))
        g.draw(img, at: .zero, anchor: .center)
    }

    static func drawMark(_ mark: FT5UMark, in c: inout GraphicsContext, center: CGPoint, cell: CGFloat,
                         main: FT5UPaint, accent: FT5UPaint, ink: FT5UInk, ltr: Bool) {
        switch mark {
        case .glyph(let g):
            if isWoven(g) {
                // الرمز المنسوج (الجولة ٨) بألوان الرقعة: الجسم بلون الأرضية، التفاصيل محو، واللمسة بلون اللمسة
                let side = grid * cell + 2
                let style = FT5UWovenStyle(body: .paint(main), detail: .erase,
                                           accent: accent.color.opacity(accent.opacity), accentLight: nil,
                                           soft: main.color.opacity(main.opacity * 0.6), shadow: nil)
                drawWoven(g, in: &c, box: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                          style: style, ltr: ltr)
            } else {
                drawSym(sym(g), in: &c, center: center, cell: cell, main: main, accent: accent, ltr: ltr)
            }
        case .sf(let name):
            c.drawLayer { l in
                drawSF(name, in: &l, center: center, side: grid * cell, color: main.color, ltr: ltr)
                if main.shade > 0 {
                    var d = l
                    d.blendMode = .sourceAtop
                    d.fill(rect(center.x - grid * cell, center.y - grid * cell, 2 * grid * cell, 2 * grid * cell),
                           with: .color(.black.opacity(main.shade)))
                }
            }
        case .eye:
            let half = grid * cell / 2
            var e = diamond(center.x, center.y, half - 0.5)
            e.addPath(diamond(center.x, center.y, half - 3.5))
            fill(&c, e, main, eo: true)
            fill(&c, diamond(center.x, center.y, (half * 0.42).rounded()), accent)
        }
    }

    // MARK: عين السدو

    static func drawEye(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ a: CGFloat,
                        ground: FT5UPaint, ink: FT5UInk, mourning: Bool) {
        guard a >= 2 else { return }
        fill(&c, diamond(x, y, a), ground)
        let rw = max(1.8, (a * 0.15).rounded())
        var ring = diamond(x, y, a)
        ring.addPath(diamond(x, y, a - rw))
        c.fill(ring, with: .color(ink.cream.opacity(0.88)), style: FillStyle(eoFill: true))
        c.fill(diamond(x, y, max(1.2, (a * 0.32).rounded())), with: .color(mourning ? ink.cream.opacity(0.6) : ink.red))
    }

    // MARK: الحاشية العمودية (المربّعات ورؤوس المربّعات)

    /// الحاشية بعرض `w` على الجهة اليسرى (إحداثيات عربية): أرضية + خيط كريمي بأسنان على الحدّ الداخلي +
    /// خيط السَّدى + عينان + الرقعة بالرمز في الوسط
    static func drawStrip(_ c: inout GraphicsContext, mark: FT5UMark, width w: CGFloat, height h: CGFloat,
                          ground: FT5UPaint, ink: FT5UInk, cell: CGFloat, mourning: Bool, ltr: Bool) {
        let inner = w - thread
        let cx = (inner / 2).rounded()
        let cy = (h / 2).rounded()
        let side = grid * cell + 4
        let half = side / 2

        fill(&c, rect(0, 0, w, h), ground)

        var teeth = Path()
        let tw: CGFloat = 4, th: CGFloat = 2.5
        var ty = (cy - tw / 2).truncatingRemainder(dividingBy: tw) - tw
        while ty < h {
            teeth.addPath(poly([(inner, ty), (inner - th, ty + tw / 2), (inner, ty + tw)]))
            ty += tw
        }
        c.fill(rect(inner, 0, thread, h), with: .color(ink.cream))
        c.fill(teeth, with: .color(ink.cream.opacity(0.5)))
        c.fill(rect(cx - 0.75, 0, 1.5, h), with: .color(ink.cream.opacity(0.5)))

        let space = cy - half
        let a = min((inner / 2 - 6).rounded(.down), (space / 2 - 4.5).rounded(.down))
        let ey = (space / 2).rounded()
        for e in [ey, h - ey] { drawEye(&c, cx, e, a, ground: ground, ink: ink, mourning: mourning) }

        c.fill(Path(roundedRect: CGRect(x: cx - half, y: cy - half, width: side, height: side), cornerRadius: 2.5),
               with: .color(ink.cream))
        drawMark(mark, in: &c, center: CGPoint(x: cx, y: cy), cell: cell, main: ground,
                 accent: FT5UPaint(color: ink.red), ink: ink, ltr: ltr)
    }

    /// المربّع (الجولة ٨): حاشية رفيعة على الحافّة العلوية فقط — المجسّم والعنوان في الوسط لا يلمسانها
    static func drawTile(_ c: inout GraphicsContext, size: CGSize, place: String, variant: Int) {
        drawTopBand(&c, size: size, place: place)
    }

    static func drawHeader(_ c: inout GraphicsContext, size: CGSize, icon: String, deep: Color) {
        guard size.width > 1, size.height > 1 else { return }
        var g = c
        let ltr = isLTR(c), dark = isDark(c), mourn = isMourning(icon)
        mirrorForLTR(&g, width: size.width)
        let ground = mourn ? FT5UPaint(color: hex(dark ? 0x48484A : 0x636366), shade: dark ? 0.2 : 0)
                           : FT5UPaint(color: deep, shade: dark ? 0.3 : 0)
        drawStrip(&g, mark: mark(forIcon: icon), width: headerStrip, height: size.height, ground: ground,
                  ink: .of(dark: dark, mourning: mourn), cell: headerCell, mourning: mourn, ltr: ltr)
    }

    // MARK: الحاشية الأفقية (الصفحات الفاضية، الانتظار، الإشعارات، اللحظات، بطاقة الأخبار)

    static func drawBand(_ c: inout GraphicsContext, rect r: CGRect, mark: FT5UMark?, ground: FT5UPaint,
                         ink: FT5UInk, cell: CGFloat, fringe: CGFloat, mourning: Bool, ltr: Bool) {
        let cx = r.midX.rounded(), cy = r.midY.rounded()
        let side = grid * cell + 4, half = side / 2

        if fringe > 0 {
            var f = Path()
            let n = max(3, Int((r.height - 6) / 6.5))
            let step = (r.height - 8) / CGFloat(n - 1)
            for i in 0..<n {
                let y = (r.minY + 4 + CGFloat(i) * step).rounded()
                f.addPath(rect(r.minX - fringe, y - 0.6, fringe, 1.2))
                f.addPath(rect(r.maxX, y - 0.6, fringe, 1.2))
            }
            var fp = ground
            fp.opacity *= 0.8
            fill(&c, f, fp)
        }
        fill(&c, Path(roundedRect: r, cornerRadius: 1.5), ground)

        let small = r.height < 40
        let inset: CGFloat = small ? 2 : 3
        let tTop = r.minY + inset, tBot = r.maxY - inset - thread
        c.fill(rect(r.minX, tTop, r.width, thread), with: .color(ink.cream))
        c.fill(rect(r.minX, tBot, r.width, thread), with: .color(ink.cream))
        if !small {
            var teeth = Path()
            let tw: CGFloat = 4, th: CGFloat = 2.5
            var tx = cx - tw / 2 - tw * ((cx - r.minX) / tw).rounded(.up)
            let ya = tTop + thread, yb = tBot
            while tx < r.maxX {
                teeth.addPath(poly([(tx, ya), (tx + tw / 2, ya + th), (tx + tw, ya)]))
                teeth.addPath(poly([(tx, yb), (tx + tw / 2, yb - th), (tx + tw, yb)]))
                tx += tw
            }
            var tc = c
            tc.clip(to: Path(r))
            tc.fill(teeth, with: .color(ink.cream.opacity(0.5)))
        }
        c.fill(rect(r.minX, cy - 0.75, r.width, 1.5), with: .color(ink.cream.opacity(0.5)))

        let space = (cx - half) - r.minX
        let a = min((r.height * 0.27).rounded(.down), (space / 2 - 3).rounded(.down))
        let ex = (r.minX + space / 2).rounded()
        for e in [ex, 2 * cx - ex] { drawEye(&c, e, cy, a, ground: ground, ink: ink, mourning: mourning) }

        if let mark {
            c.fill(Path(roundedRect: CGRect(x: cx - half, y: cy - half, width: side, height: side), cornerRadius: 2.5),
                   with: .color(ink.cream))
            drawMark(mark, in: &c, center: CGPoint(x: cx, y: cy), cell: cell, main: ground,
                     accent: FT5UPaint(color: ink.red), ink: ink, ltr: ltr)
        }
    }

    /// الحاشية الأفقية متمركزة في الإطار. `ground` لون القسم؛ في الداكن يُعتَّم ٣٠٪ (ألوان الحبر فاتحة فيه).
    static func drawBandCentered(_ c: inout GraphicsContext, size: CGSize, band: CGSize, mark: FT5UMark?,
                                 color: Color, cell: CGFloat, fringe: CGFloat, mourning: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        mirrorForLTR(&g, width: size.width)
        let k = min(1, (size.width - 2 * fringe) / band.width, size.height / max(band.height, 1))
        let w = (band.width * k).rounded(), h = (band.height * k).rounded()
        let r = CGRect(x: ((size.width - w) / 2).rounded(), y: ((size.height - h) / 2).rounded(), width: w, height: h)
        let ground = mourning ? FT5UPaint(color: hex(dark ? 0x48484A : 0x636366))
                              : FT5UPaint(color: color, shade: dark ? 0.3 : 0)
        drawBand(&g, rect: r, mark: mark, ground: ground, ink: .of(dark: dark, mourning: mourning),
                 cell: k < 1 ? max(2, (cell * k).rounded(.down)) : cell, fringe: fringe, mourning: mourning, ltr: ltr)
    }

    // MARK: الرقعة الصلبة (أيقونات الحالة ومربّعات لوحة الإدارة)

    static func drawPatchIcon(_ c: inout GraphicsContext, size: CGSize, mark: FT5UMark, tint: Color, mourning: Bool) {
        let s = min(size.width, size.height)
        guard s > 4 else { return }
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        mirrorForLTR(&g, width: size.width)
        let ink = FT5UInk.of(dark: dark, mourning: mourning)
        let r = CGRect(x: ((size.width - s) / 2).rounded(), y: ((size.height - s) / 2).rounded(), width: s, height: s)
        let ground = mourning ? FT5UPaint(color: hex(dark ? 0x48484A : 0x636366))
                              : FT5UPaint(color: tint, shade: dark ? 0.3 : 0)
        fill(&g, Path(roundedRect: r, cornerRadius: s * 0.24, style: .continuous), ground)
        // خيط الحاشية: إطار كريمي داخلي، وعلى منتصف حدّه السفلي «مشبك» عين صغير
        let i = max(3, (s * 0.085).rounded())
        let fr = r.insetBy(dx: i, dy: i)
        g.stroke(Path(roundedRect: fr, cornerRadius: s * 0.15, style: .continuous),
                 with: .color(ink.cream.opacity(0.5)), lineWidth: max(1, s * 0.022))
        let ca = max(2.2, (s * 0.06).rounded())
        fill(&g, diamond(r.midX, fr.maxY, ca + 1), ground)
        g.fill(diamond(r.midX, fr.maxY, ca), with: .color(mourning ? ink.cream : ink.redOnGround))
        let cell = s * 0.56 / grid
        drawMark(mark, in: &g, center: CGPoint(x: r.midX, y: (r.midY - s * 0.02).rounded()), cell: cell,
                 main: FT5UPaint(color: ink.cream), accent: FT5UPaint(color: mourning ? ink.cream : ink.redOnGround),
                 ink: ink, ltr: ltr)
    }

    // MARK: القطعة المعلّقة (DSPageHero)

    static func drawPennant(_ c: inout GraphicsContext, size: CGSize, mark: FT5UMark, tint: Color, mourning: Bool) {
        guard size.width > 80, size.height > 60 else { return }
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        mirrorForLTR(&g, width: size.width)
        let ink = FT5UInk.of(dark: dark, mourning: mourning)
        let ground = mourning ? FT5UPaint(color: hex(dark ? 0x3A3A3C : 0x48484A))
                              : FT5UPaint(color: tint, shade: dark ? 0.45 : 0.32)
        let cell: CGFloat = 3
        let side = grid * cell + 4, half = side / 2
        let w: CGFloat = side + 2 * 3 + 2 * thread + 2   // ٤٦
        let x0: CGFloat = 20
        let fringe: CGFloat = 7
        // سطر العنوان ينتهي عند ~٧٦ نقطة وصفّ الأرقام يبدأ بعده — القطعة لا تتجاوز ٧٠
        let total = min(70, max(56, (size.height * 0.62).rounded()))
        let yb = total - fringe
        let cx = (x0 + w / 2).rounded()

        // الشراشيب
        var f = Path()
        for k in 0..<6 {
            let x = x0 + 4 + CGFloat(k) * (w - 8) / 5
            f.addPath(rect(x.rounded() - 0.6, yb, 1.2, fringe))
        }
        var fp = ground
        fp.opacity = 0.9
        fill(&g, f, fp)
        fill(&g, rect(x0, -2, w, yb + 2), ground)
        // خيطا الحافّتين الطويلتين + الخيط السفلي بأسنان
        g.fill(rect(x0 + 2.5, -2, thread, yb - 1.5), with: .color(ink.cream))
        g.fill(rect(x0 + w - 2.5 - thread, -2, thread, yb - 1.5), with: .color(ink.cream))
        g.fill(rect(x0 + 2.5, yb - 4 - thread, w - 5, thread), with: .color(ink.cream))
        var teeth = Path()
        let tw: CGFloat = 4
        var tx = x0 + 2.5 + thread
        while tx + tw <= x0 + w - 2.5 - thread + 0.01 {
            teeth.addPath(poly([(tx, yb - 4 - thread), (tx + tw / 2, yb - 4 - thread - 2.5), (tx + tw, yb - 4 - thread)]))
            tx += tw
        }
        g.fill(teeth, with: .color(ink.cream.opacity(0.5)))
        g.fill(rect(cx - 0.75, -2, 1.5, yb - 4 - thread + 2), with: .color(ink.cream.opacity(0.45)))

        let pcy = (yb - 4 - thread - 5 - half).rounded()
        let top = pcy - half
        if top >= 22 {
            let a = min(w / 2 - 9, (top / 2 - 3).rounded(.down))
            drawEye(&g, cx, (top / 2).rounded(), a, ground: ground, ink: ink, mourning: mourning)
        }
        g.fill(Path(roundedRect: CGRect(x: cx - half, y: pcy - half, width: side, height: side), cornerRadius: 2.5),
               with: .color(ink.cream))
        drawMark(mark, in: &g, center: CGPoint(x: cx, y: pcy), cell: cell, main: ground,
                 accent: FT5UPaint(color: ink.red), ink: ink, ltr: ltr)
    }

    // MARK: نول تحميل الشجرة (٢٤٠×٢٠٠)

    static let loomDesign = CGSize(width: 240, height: 200)
    static let shuttleY: CGFloat = 146
    static let shuttleTravel: CGFloat = 50

    static func loomGround(dark: Bool) -> Color { hex(dark ? 0x1B534A : 0x1E5950) }

    static func drawLoom(_ c: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        let k = min(size.width / loomDesign.width, size.height / loomDesign.height)
        g.translateBy(x: (size.width - loomDesign.width * k) / 2, y: (size.height - loomDesign.height * k) / 2)
        g.scaleBy(x: k, y: k)
        mirrorForLTR(&g, width: loomDesign.width)
        let ink = FT5UInk.of(dark: dark)
        let ground = FT5UPaint(color: loomGround(dark: dark))
        // السَّدى المكشوف (خيوط النول تحت الجزء المنسوج)
        var warp = Path()
        for i in 0..<12 {
            let x = (42 + CGFloat(i) * 156 / 11).rounded()
            warp.addPath(rect(x - 0.6, 110, 1.2, 64))
        }
        var wp = ground
        wp.opacity = 0.45
        fill(&g, warp, wp)
        // العارضتان
        fill(&g, Path(roundedRect: CGRect(x: 22, y: 20, width: 196, height: 7), cornerRadius: 3.5), ground)
        fill(&g, Path(roundedRect: CGRect(x: 22, y: 172, width: 196, height: 7), cornerRadius: 3.5), ground)
        // الجزء المنسوج: حاشية أفقية برقعة الشجرة
        drawBand(&g, rect: CGRect(x: 34, y: 27, width: 172, height: 84), mark: .glyph(.tree), ground: ground,
                 ink: ink, cell: 4, fringe: 0, mourning: false, ltr: ltr)
    }

    static func drawShuttle(_ c: inout GraphicsContext, size: CGSize) {
        let dark = isDark(c)
        let ink = FT5UInk.of(dark: dark)
        let w = size.width, h = size.height
        c.fill(poly([(0, h / 2), (h / 2, 0), (w - h / 2, 0), (w, h / 2), (w - h / 2, h), (h / 2, h)]),
               with: .color(loomGround(dark: dark)))
        c.fill(rect(h / 2, h / 2 - 0.6, w - h, 1.2), with: .color(ink.cream.opacity(0.7)))
        c.fill(diamond(w / 2, h / 2, h / 2 - 1), with: .color(ink.red))
    }

    // MARK: خلفية الدخول (شبه غائبة)

    static func drawBackdrop(_ c: inout GraphicsContext, size: CGSize, logoY: CGFloat) {
        guard size.width > 1, size.height > 1 else { return }
        let dark = isDark(c)
        let ink = hex(dark ? 0x7FA8D6 : 0x1F4E79)
        let cx = (size.width / 2).rounded(), cy = logoY.rounded()
        // عين سدو كبيرة حول الشعار: حلقتان
        for (r, op) in [(124.0, 0.07), (146.0, 0.045)] as [(CGFloat, Double)] {
            c.stroke(diamond(cx, cy, r), with: .color(ink.opacity(op)), lineWidth: 1.2)
        }
        // خيط السَّدى أفقياً بعيون صغيرة تتلاشى نحو الطرفين
        var gc = c
        gc.clip(to: diamond(cx, cy, 152), options: .inverse)
        gc.fill(rect(0, cy - 0.5, size.width, 1), with: .linearGradient(
            Gradient(stops: [.init(color: ink.opacity(0), location: 0), .init(color: ink.opacity(0.07), location: 0.5),
                             .init(color: ink.opacity(0), location: 1)]),
            startPoint: CGPoint(x: 0, y: cy), endPoint: CGPoint(x: size.width, y: cy)))
        var step: CGFloat = 170
        var op = 0.06
        while step < size.width / 2 + 10 {
            for x in [cx - step, cx + step] {
                var e = diamond(x, cy, 5)
                e.addPath(diamond(x, cy, 3.6))
                c.fill(e, with: .color(ink.opacity(op)), style: FillStyle(eoFill: true))
            }
            step += 26
            op *= 0.8
        }
    }

    // MARK: الشارات

    static func drawBadge(_ c: inout GraphicsContext, size: CGSize, glyph: FT5UGlyph, tint: Color, onColor: Bool,
                          mourning: Bool) {
        let s = min(size.width, size.height)
        guard s > 4 else { return }
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        mirrorForLTR(&g, width: size.width)
        let ink = FT5UInk.of(dark: dark)
        let main = FT5UPaint(color: onColor ? .white : tint)
        let accent: FT5UPaint = onColor ? FT5UPaint(color: .white, opacity: 0.72)
                                        : FT5UPaint(color: mourning ? tint : ink.red)
        drawSym(sym(glyph), in: &g, center: CGPoint(x: size.width / 2, y: size.height / 2), cell: s * 0.58 / grid,
                main: main, accent: accent, ltr: ltr)
    }

    // MARK: التحية

    static func drawGreetingGlyph(_ c: inout GraphicsContext, size: CGSize, hour: Int, tint: Color) {
        let s = min(size.width, size.height)
        guard s > 2 else { return }
        var g = c
        g.translateBy(x: (size.width - s) / 2, y: (size.height - s) / 2)
        g.scaleBy(x: s / 18, y: s / 18)
        let col = GraphicsContext.Shading.color(tint)
        if (4..<12).contains(hour) {
            // الصباح: نصف عين تشرق فوق الأفق وثلاثة أشعة
            g.fill(rect(1, 13.4, 16, 1.8), with: col)
            g.fill(poly([(3.6, 12.3), (9, 6.9), (14.4, 12.3)]), with: col)
            g.fill(rect(8.1, 1.6, 1.8, 3.6), with: col)
            g.fill(bar((2.6, 5.8), (4.6, 7.8), 1.8), with: col)
            g.fill(bar((15.4, 5.8), (13.4, 7.8), 1.8), with: col)
        } else if (12..<17).contains(hour) {
            // الظهر: عين سدو مشعّة
            var ring = diamond(9, 9, 5.4)
            ring.addPath(diamond(9, 9, 3.2))
            g.fill(ring, with: col, style: FillStyle(eoFill: true))
            g.fill(diamond(9, 9, 1.6), with: col)
            for (a, b) in [((2.6, 2.6), (4.6, 4.6)), ((15.4, 2.6), (13.4, 4.6)),
                           ((2.6, 15.4), (4.6, 13.4)), ((15.4, 15.4), (13.4, 13.4))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                g.fill(bar(a, b, 1.8), with: col)
            }
        } else {
            // المساء: هلال ونجمة سدو
            var m = g
            mirrorForLTR(&m, width: 18)
            m.drawLayer { l in
                l.fill(circle(8.4, 9.6, 7.0), with: col)
                var e = l
                e.blendMode = .destinationOut
                e.fill(circle(11.6, 6.9, 5.8), with: .color(.black))
                l.fill(diamond(13.4, 6.4, 2.2), with: col)
            }
        }
    }

    /// لمسة بطاقة الترحيب (الجولة ٤): شريط ٤ نقاط بلون التحية على الحافّة الخلفية وعين صغيرة كالمشبك
    static func drawGreetingEdge(_ c: inout GraphicsContext, size: CGSize, tint: Color) {
        guard size.width > 1, size.height > 1 else { return }
        var g = c
        mirrorForLTR(&g, width: size.width)
        let ink = FT5UInk.of(dark: isDark(c))
        let w: CGFloat = 4, cy = (size.height / 2).rounded(), a: CGFloat = 5
        var band = rect(0, 0, w, size.height)
        band.addPath(diamond(w, cy, a))
        g.fill(band, with: .color(tint))
        var ring = diamond(w, cy, a - 1.3)
        ring.addPath(diamond(w, cy, a - 2.5))
        g.fill(ring, with: .color(ink.cream), style: FillStyle(eoFill: true))
        g.fill(diamond(w, cy, 1.2), with: .color(ink.red))
    }

    // MARK: زخرفة رأس التبويب (١٢ نقطة)

    static func drawOrnament(_ c: inout GraphicsContext, size: CGSize) {
        guard size.width > 40, size.height > 4 else { return }
        let ink = FT5UInk.of(dark: isDark(c))
        let w = size.width, cy = (size.height / 2).rounded(), cx = (w / 2).rounded()
        let eyes: [(CGFloat, CGFloat)] = [(0, 6), (-26, 4.5), (26, 4.5), (-48, 2.6), (48, 2.6)]
        var holes = Path()
        for (dx, a) in eyes { holes.addPath(diamond(cx + dx, cy, a + 2)) }
        // الخيط والأسنان يتلاشيان نحو الطرفين، ولا يمرّان تحت العيون
        var t = c
        t.clip(to: holes, options: .inverse)
        let fade = Gradient(stops: [.init(color: ink.cream.opacity(0), location: 0),
                                    .init(color: ink.cream.opacity(0.8), location: 0.3),
                                    .init(color: ink.cream.opacity(0.8), location: 0.7),
                                    .init(color: ink.cream.opacity(0), location: 1)])
        t.fill(rect(0, cy - 0.6, w, 1.2), with: .linearGradient(fade, startPoint: CGPoint(x: 0, y: cy),
                                                                  endPoint: CGPoint(x: w, y: cy)))
        var teeth = Path()
        var x = cx - 2 - 4 * ((cx - 2) / 4).rounded(.down)
        while x + 4 <= w {
            teeth.addPath(poly([(x, cy + 1.5), (x + 2, cy + 3.5), (x + 4, cy + 1.5)]))
            x += 4
        }
        let fade2 = Gradient(stops: [.init(color: ink.cream.opacity(0), location: 0.12),
                                     .init(color: ink.cream.opacity(0.5), location: 0.5),
                                     .init(color: ink.cream.opacity(0), location: 0.88)])
        t.fill(teeth, with: .linearGradient(fade2, startPoint: CGPoint(x: 0, y: cy), endPoint: CGPoint(x: w, y: cy)))
        // العيون: الوسطى بحلقة وقلب أحمر، ثم عينان أصغر بقلب كريمي، ثم نقطتان
        for (i, (dx, a)) in eyes.enumerated() {
            let ex = cx + dx
            if i == 0 {
                var r = diamond(ex, cy, a)
                r.addPath(diamond(ex, cy, a - 1.6))
                c.fill(r, with: .color(ink.cream), style: FillStyle(eoFill: true))
                c.fill(diamond(ex, cy, 2.2), with: .color(ink.red))
            } else if i < 3 {
                var r = diamond(ex, cy, a)
                r.addPath(diamond(ex, cy, a - 1.4))
                c.fill(r, with: .color(ink.cream.opacity(0.92)), style: FillStyle(eoFill: true))
                c.fill(diamond(ex, cy, 1.4), with: .color(ink.red.opacity(0.9)))
            } else {
                c.fill(diamond(ex, cy, a), with: .color(ink.cream.opacity(0.8)))
            }
        }
    }
}

// MARK: - مجسّمات المربّعات (الجولة ٨): رموز منسوجة مدرّجة على شبكة ٢٠×٢٠

/// الرمز المنسوج: جسم كريمي (مسار واحد موحّد)، وتفاصيل داخلية (لون القسم العميق في المربّع، أو محو في الرقع)،
/// ولمسات كريمية خفيفة فوق الأرضية (بخار، موج)، ومعيّن ذهبي واحد، وخطّ أرض لظلّ التماس
nonisolated struct FT5UWoven {
    var body = Path()
    var detail = Path()
    var soft = Path()
    /// المعيّن الذهبي (x, y, r)
    var gem: (CGFloat, CGFloat, CGFloat)? = nil
    var baseline: CGFloat = 19
    var shadowX: CGFloat = 10
    var shadowHalf: CGFloat = 8
    /// لا ينعكس في الإنجليزية (سهم النموّ)
    var fixed = false
    mutating func b(_ p: Path) { body.addPath(p) }
    mutating func d(_ p: Path) { detail.addPath(p) }
    mutating func s(_ p: Path) { soft.addPath(p) }
}

/// ألوان الرمز المنسوج بحسب موضعه
nonisolated struct FT5UWovenStyle {
    enum Body { case light(Color, Color), paint(FT5UPaint) }
    enum Detail { case paint(Color), erase }
    var body: Body
    var detail: Detail
    var accent: Color
    var accentLight: Color? = nil
    var soft: Color
    var shadow: Color? = nil
}

extension FT5U {
    static let wovenGrid: CGFloat = 20
    static let gold = hex(0xD9A23E)
    static let goldLight = hex(0xF2C65E)
    static let wovenKinds: [FT5UGlyph] = [.tree, .dalla, .envelope, .shelf, .chest, .scroll, .briefcase, .dhow, .growth]

    static func isWoven(_ g: FT5UGlyph) -> Bool { wovenKinds.contains(g) }

    // MARK: هندسة الشبكة

    /// صفوف أفقية متراصّة من الأعلى حول المحور `cx`: (نصف العرض، الارتفاع) — الأشكال المدرّجة
    static func rows(_ cx: CGFloat, _ top: CGFloat, _ r: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        var y = top
        for (hw, h) in r {
            p.addPath(rect(cx - hw, y, 2 * hw, h))
            y += h
        }
        return p
    }

    /// خطّ مدرّج (سلّم) بسماكة `t` من `a` إلى `b` في `n` درجات
    static func stairs(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ n: Int, _ t: CGFloat) -> Path {
        var p = Path()
        let h = t / 2
        for i in 0..<n {
            let f0 = CGFloat(i) / CGFloat(n), f1 = CGFloat(i + 1) / CGFloat(n)
            let xa = a.0 + (b.0 - a.0) * f0, xb = a.0 + (b.0 - a.0) * f1
            let ya = a.1 + (b.1 - a.1) * f0, yb = a.1 + (b.1 - a.1) * f1
            p.addPath(rect(min(xa, xb) - h, ya - h, abs(xb - xa) + t, t))
            p.addPath(rect(xb - h, min(ya, yb) - h, t, abs(yb - ya) + t))
        }
        return p
    }

    /// مثلّث قائم بوتر مدرّج: الضلع القائم عند `x0` والدرجات تتّسع نزولاً باتجاه `dir` (+١ يميناً)
    static func stairTri(_ x0: CGFloat, _ y0: CGFloat, _ w: CGFloat, _ h: CGFloat, _ n: Int, _ dir: CGFloat) -> Path {
        var p = Path()
        let rh = h / CGFloat(n)
        for i in 0..<n {
            let wi = w * CGFloat(i + 1) / CGFloat(n)
            p.addPath(rect(dir > 0 ? x0 : x0 - wi, y0 + CGFloat(i) * rh, wi, rh))
        }
        return p
    }

    // MARK: الرموز (شبكة ٢٠: البعد الأكبر ١٨ = ٩٠٪، وخطّ الأرض ١٩)

    /// (الغافة ليست هنا: هي شعار التطبيق `tree.fill` — انظر drawWovenTree)
    static func woven(_ g: FT5UGlyph) -> FT5UWoven? {
        var o = FT5UWoven()
        switch g {
        case .dalla:
            // دلّة: غطاء مدرّج بقمّة ذهبية، عنق، بطن، قاعدة مفلطحة؛ صنبور مدرّج يساراً ومقبض يميناً؛ فنجان ببخار
            o.b(rect(7.5, 2.6, 1, 0.9))
            o.b(rows(8, 3.2, [(1, 1), (2, 1), (3, 1), (3.6, 0.9), (2, 1.9), (3, 1), (3.6, 1), (4, 5), (3.4, 1), (2.4, 1), (3.6, 1)]))
            o.b(bar((5.2, 11.9), (2.15, 8.85), 1.7))
            o.b(rect(1.3, 4.6, 1.7, 4.6))
            o.b(bar((2.15, 5.0), (1.2, 4.05), 1.4))
            o.b(rect(11.6, 8, 2.9, 1.3))
            o.b(rect(13.2, 8, 1.3, 5))
            o.b(bar((13.85, 12.8), (12.05, 14.6), 1.3))
            o.b(rows(17.1, 14.4, [(1.8, 1.4), (1.4, 1.2), (1.0, 1.0), (1.9, 1)]))
            o.s(bar((16.5, 13.3), (17.6, 12.2), 0.75))
            o.s(bar((17.6, 12.2), (16.5, 11.1), 0.75))
            o.s(bar((16.5, 11.1), (17.6, 10.0), 0.75))
            o.d(rect(4.6, 6.35, 6.8, 0.6))
            o.d(rect(4.3, 11.6, 7.4, 0.55))
            for x in [6, 8, 10] as [CGFloat] { o.d(diamond(x, 13.3, 0.7)) }
            o.d(rect(15.5, 15.0, 3.2, 0.55))
            o.gem = (8, 1.9, 1.2)
            o.shadowX = 10.2
        case .envelope:
            // ظرف مشطوف الزوايا، لسانه خطّان مدرّجان يلتقيان عند ختم ذهبي، وطيّتا الجيب السفلي أقصر
            o.b(rows(10, 5.5, [(8, 1), (9, 10), (8, 1)]))
            o.d(stairs((1.7, 6.4), (10, 12.4), 5, 0.75))
            o.d(stairs((18.3, 6.4), (10, 12.4), 5, 0.75))
            o.d(stairs((1.7, 16.6), (6.2, 13.3), 3, 0.65))
            o.d(stairs((18.3, 16.6), (13.8, 13.3), 3, 0.65))
            o.gem = (10, 12.5, 1.75)
            o.baseline = 17.5
        case .shelf:
            // رف الكتب: ثلاثة كتب قائمة (الأوسط أطولها وعليه المعيّن) وكتابان مسطّحان على لوح بكتيفتين مدرّجتين
            o.b(rect(1.2, 4, 3.2, 12))
            o.b(rect(5, 2.4, 3.4, 13.6))
            o.b(rect(9, 5, 3, 11))
            o.b(rect(13, 12.6, 5.6, 1.7))
            o.b(rect(12.6, 14.3, 6.2, 1.7))
            o.b(rect(1, 16, 18, 1.4))
            o.b(rows(3.2, 17.4, [(1.0, 0.8), (0.5, 0.8)]))
            o.b(rows(16.8, 17.4, [(1.0, 0.8), (0.5, 0.8)]))
            for (x, w, top) in [(1.2, 3.2, 4.0), (5, 3.4, 2.4), (9, 3, 5.0)] as [(CGFloat, CGFloat, CGFloat)] {
                o.d(rect(x, top + 1.4, w, 0.6))
                o.d(rect(x, 13.8, w, 0.6))
            }
            o.d(rect(13.5, 13.2, 4.6, 0.45))
            o.d(rect(13.1, 14.9, 5.2, 0.45))
            o.d(rect(1.6, 16.45, 16.8, 0.45))
            o.gem = (6.7, 9, 1.3)
        case .chest:
            // صندوق المبيّت: غطاء مدرّج، حزامان، خطّ الغطاء وخطّ القاعدة، وقفل: عين عميقة بقلب ذهبي
            o.b(rows(10, 4.5, [(6, 1), (8, 1), (9, 10.7)]))
            o.b(rect(2, 17.2, 3, 1.8))
            o.b(rect(15, 17.2, 3, 1.8))
            o.d(rect(1, 9, 18, 0.6))
            o.d(rect(4.4, 5, 1.1, 12.2))
            o.d(rect(14.5, 5, 1.1, 12.2))
            o.d(rect(1, 15.8, 18, 0.5))
            o.d(diamond(10, 12.3, 2.3))
            o.gem = (10, 12.3, 1.4)
        case .scroll:
            // الوثيقة: لفّتان بطرفين، صفحة بثلاثة أسطر (محاذاة عربية) وختم ذهبي أسفل اليسار
            o.b(rect(2.6, 1, 14.8, 2.6))
            o.b(rect(1, 1.5, 1.6, 1.6))
            o.b(rect(17.4, 1.5, 1.6, 1.6))
            o.b(rect(4, 3.6, 12, 12.8))
            o.b(rect(2.6, 16.4, 14.8, 2.6))
            o.b(rect(1, 16.9, 1.6, 1.6))
            o.b(rect(17.4, 16.9, 1.6, 1.6))
            o.d(rect(2.6, 3.2, 14.8, 0.5))
            o.d(rect(2.6, 16.3, 14.8, 0.5))
            o.d(rect(6.5, 6.2, 8, 0.8))
            o.d(rect(8.5, 8.6, 6, 0.8))
            o.d(rect(6.5, 11, 8, 0.8))
            o.gem = (7.2, 13.9, 1.4)
            o.shadowHalf = 7.5
        case .briefcase:
            // حقيبة العمل: مقبض، جسم مشطوف، حزام الإغلاق بمشبكين عميقين وقفل ذهبي
            o.b(rect(7, 3, 6, 1.4))
            o.b(rect(7, 3, 1.4, 3.3))
            o.b(rect(11.6, 3, 1.4, 3.3))
            o.b(rows(10, 6, [(8, 1), (9, 11), (8, 1)]))
            o.d(rect(1, 10.6, 18, 0.7))
            o.d(diamond(4.6, 10.95, 0.85))
            o.d(diamond(15.4, 10.95, 0.85))
            o.gem = (10, 10.95, 1.5)
        case .dhow:
            // سفينة البوم: صارٍ بقمّة ذهبية، شراع لاتيني مدرّج وشراع أمامي أصغر، بدن مدرّج، وموج من أسنان كريمية
            o.b(rect(9.4, 2.4, 1.2, 11.4))
            o.b(stairTri(10.8, 2.8, 8.2, 10.4, 8, 1))
            o.b(stairTri(9.2, 5.6, 6.4, 7.6, 6, -1))
            o.b(rows(10, 13.4, [(9, 1.5), (7.5, 1.1), (5.8, 1.0), (4.2, 0.8)]))
            for i in 0..<6 {
                let x = 1 + CGFloat(i) * 3
                o.s(poly([(x, 19.3), (x + 1.5, 17.9), (x + 3, 19.3)]))
            }
            o.d(rect(1.6, 14.2, 16.8, 0.6))
            o.d(stairs((11.3, 3.9), (17.6, 12.0), 7, 0.7))
            o.gem = (10, 1.9, 1.2)
            o.baseline = 19.2
        case .growth:
            // سهم النموّ: ثلاثة أعمدة مدرّجة بعيون عميقة وسهم مدرّج يصعد يميناً إلى رأس ذهبي (لا ينعكس)
            o.fixed = true
            o.b(rect(1, 13, 4.5, 5))
            o.b(rect(7.75, 9.5, 4.5, 8.5))
            o.b(rect(14.5, 6, 4.5, 12))
            o.b(rect(1, 18, 18, 1))
            o.b(stairs((1.8, 10.6), (15.2, 2.8), 6, 1.3))
            o.d(diamond(3.25, 15.5, 0.9))
            o.d(diamond(10, 13.75, 0.9))
            o.d(diamond(16.75, 12, 0.9))
            o.gem = (16.4, 2.6, 1.6)
        default:
            return nil
        }
        return o
    }

    // MARK: الرسم

    /// يرسم الرمز المنسوج ليملأ `box` (مربّع): ظلّ التماس، اللمسات الخفيفة، الجسم، التفاصيل، ثم المعيّن
    static func drawWoven(_ g: FT5UGlyph, in c: inout GraphicsContext, box: CGRect, style: FT5UWovenStyle, ltr: Bool) {
        if g == .tree {
            drawWovenTree(in: &c, box: box, style: style)
            return
        }
        guard let o = woven(g), box.width > 2 else { return }
        let k = box.width / wovenGrid
        func paint(_ l: inout GraphicsContext) {
            l.translateBy(x: box.minX, y: box.minY)
            if o.fixed && ltr {
                l.translateBy(x: box.width, y: 0)
                l.scaleBy(x: -1, y: 1)
            }
            l.scaleBy(x: k, y: k)
            if let sh = style.shadow {
                var s = l
                s.translateBy(x: o.shadowX, y: o.baseline + 0.35)
                s.scaleBy(x: 1, y: 0.2)
                s.fill(circle(0, 0, o.shadowHalf),
                       with: .radialGradient(Gradient(colors: [sh.opacity(0.6), sh.opacity(0)]),
                                             center: .zero, startRadius: 0, endRadius: o.shadowHalf))
            }
            l.fill(o.soft, with: .color(style.soft))
            switch style.body {
            case .light(let a, let b):
                l.fill(o.body, with: .linearGradient(Gradient(colors: [a, b]), startPoint: .zero,
                                                     endPoint: CGPoint(x: wovenGrid, y: wovenGrid)))
            case .paint(let p):
                fill(&l, o.body, p)
            }
            switch style.detail {
            case .paint(let col):
                l.fill(o.detail, with: .color(col))
            case .erase:
                var e = l
                e.blendMode = .destinationOut
                e.fill(o.detail, with: .color(.black))
            }
            if let gem = o.gem {
                let (x, y, r) = gem
                l.fill(diamond(x, y, r), with: .color(style.accent))
                if let hi = style.accentLight {
                    l.fill(poly([(x - r, y), (x, y - r), (x + r, y)]), with: .color(hi))
                }
            }
        }
        if case .erase = style.detail {
            c.drawLayer { l in paint(&l) }
        } else {
            var l = c
            paint(&l)
        }
    }

    /// الغافة = شجرة شعار التطبيق نفسها (رمز `tree.fill`: تاج بخمسة فصوص وجذع يتفرّع ثلاث أصابع) — قرار المالك.
    /// تُرسم كريمية بارتفاع ٩٠٪ وخطّ أرض ٩٥٪، ثم تُنسج داخلها (قصّ على طبقتها) خيطا لُحمة وعينان عميقتان وخيط
    /// سَدى في الجذع، والعين الوسطى ذهبية، وظلّ التماس المعتاد
    static func drawWovenTree(in c: inout GraphicsContext, box: CGRect, style: FT5UWovenStyle) {
        let side = box.width
        var img = c.resolve(Image(systemName: "tree.fill"))
        let natural = img.size
        guard side > 2, natural.width > 0, natural.height > 0 else { return }
        let h = side * 0.9
        let w = h * natural.width / natural.height
        let r = CGRect(x: box.midX - w / 2, y: box.minY + side * 0.95 - h, width: w, height: h)
        func paint(_ l: inout GraphicsContext) {
            if let sh = style.shadow {
                var s = l
                s.translateBy(x: r.midX, y: r.maxY + side * 0.015)
                s.scaleBy(x: 1, y: 0.2)
                let hw = side * 0.3
                s.fill(circle(0, 0, hw), with: .radialGradient(Gradient(colors: [sh.opacity(0.6), sh.opacity(0)]),
                                                               center: .zero, startRadius: 0, endRadius: hw))
            }
            switch style.body {
            case .light(let a, let b):
                img.shading = .linearGradient(Gradient(colors: [a, b]), startPoint: CGPoint(x: box.minX, y: box.minY),
                                              endPoint: CGPoint(x: box.maxX, y: box.maxY))
            case .paint(let p):
                img.shading = .color(p.color.opacity(p.opacity))
            }
            l.draw(img, in: r)
            // الداخل: كل ما يلي مقصوص على شكل الشجرة
            var inner = l
            inner.clipToLayer { $0.draw(img, in: r) }
            if case .paint(let p) = style.body, p.shade > 0 {
                inner.fill(Path(r), with: .color(.black.opacity(p.shade * p.opacity)))
            }
            let t = side * 0.03
            let wy = r.minY + r.height * 0.36
            var detail = Path()
            detail.addPath(rect(r.minX, r.minY + r.height * 0.22 - t / 2, r.width, t))
            detail.addPath(rect(r.minX, wy - t / 2, r.width, t))
            detail.addPath(rect(r.midX - t / 2, r.minY + r.height * 0.56, t, r.height * 0.44))
            detail.addPath(diamond(r.midX - r.width * 0.24, wy, side * 0.05))
            detail.addPath(diamond(r.midX + r.width * 0.24, wy, side * 0.05))
            switch style.detail {
            case .paint(let col):
                inner.fill(detail, with: .color(col))
            case .erase:
                var e = inner
                e.blendMode = .destinationOut
                e.fill(detail, with: .color(.black))
            }
            let gr = side * 0.07
            l.fill(diamond(r.midX, wy, gr), with: .color(style.accent))
            if let hi = style.accentLight {
                l.fill(poly([(r.midX - gr, wy), (r.midX, wy - gr), (r.midX + gr, wy)]), with: .color(hi))
            }
        }
        if case .erase = style.detail {
            c.drawLayer { l in paint(&l) }
        } else {
            var l = c
            paint(&l)
        }
    }

    /// مجسّم مربّع الرئيسية: يملأ الإطار (٩٠٪ من الضلع)، كريمي مضاء من أعلى اليسار، تفاصيله بلون القسم العميق،
    /// معيّن ذهبي واحد وظلّ تماس بلون القسم — الرسم نفسه في الوسط (٤٨) وكعلامة مائية (٨٦)
    static func drawTileObject(_ c: inout GraphicsContext, size: CGSize, glyph: FT5UGlyph, deep: Color) {
        let s = min(size.width, size.height)
        guard s > 2 else { return }
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        mirrorForLTR(&g, width: size.width)
        let box = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
        let cream = hex(dark ? 0xF6ECD8 : 0xFBF5E8)
        let style = FT5UWovenStyle(body: .light(cream, hex(dark ? 0xDECBA6 : 0xE7D5B0)), detail: .paint(deep),
                                   accent: gold, accentLight: goldLight, soft: cream.opacity(0.7), shadow: deep)
        drawWoven(glyph, in: &g, box: box, style: style, ltr: ltr)
    }

    // MARK: حاشية المربّع العلوية (٨ نقاط)

    static let bandHeight: CGFloat = 8

    /// حاشية رفيعة على الحافّة العلوية للمربّع: أرضية بلون القسم العميق، خيط كريمي وعيون سدو صغيرة كل ١٦ نقطة
    static func drawTopBand(_ c: inout GraphicsContext, size: CGSize, place: String) {
        guard size.width > 24, size.height > 24 else { return }
        let dark = isDark(c), ink = FT5UInk.of(dark: dark)
        let w = size.width, h = bandHeight, cy = h / 2
        fill(&c, rect(0, 0, w, h), FT5UPaint(color: tileDeep(place, dark: dark), shade: dark ? 0.12 : 0))
        c.fill(rect(0, cy - 0.5, w, 1), with: .color(ink.cream.opacity(0.45)))
        let cx = (w / 2).rounded(), step: CGFloat = 16, a: CGFloat = 2.6
        var x = cx - step * ((cx + a) / step).rounded(.down)
        while x <= w + a {
            var ring = diamond(x, cy, a)
            ring.addPath(diamond(x, cy, a - 1.1))
            c.fill(ring, with: .color(ink.cream.opacity(0.85)), style: FillStyle(eoFill: true))
            x += step
        }
    }
}

/// مجسّم مربّع الرئيسية (الرمز المنسوج يملأ إطاره — يُرسم ٤٨ في الوسط و٨٦ كعلامة مائية)
struct FT5UObjectArt: View {
    let glyph: FT5UGlyph
    let deep: Color

    var body: some View {
        let glyph = self.glyph, deep = self.deep
        return FT5UStatic { ctx, size in FT5U.drawTileObject(&ctx, size: size, glyph: glyph, deep: deep) }
    }
}

// MARK: - الأغلفة (ساكنة)

/// لوحة ساكنة: تُرسم مرة واحدة، مخفيّة عن القارئ الصوتي، ولا تلتقط اللمس
struct FT5UStatic: View {
    let draw: (inout GraphicsContext, CGSize) -> Void

    init(_ draw: @escaping (inout GraphicsContext, CGSize) -> Void) { self.draw = draw }

    var body: some View {
        Canvas(renderer: draw)
            .font(.system(size: 96))   // رمز الشجرة (tree.fill) يُحلّ كبيراً ليبقى حادّاً في كل مقاس
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct FT5UTileArt: View {
    let place: String
    let variant: Int

    var body: some View {
        let place = self.place, variant = self.variant
        return FT5UStatic { ctx, size in FT5U.drawTile(&ctx, size: size, place: place, variant: variant) }
    }
}

/// حاشية رأس المربّعات الوسطى — ارتفاعها مثبّت ٨٦ (هالة الرأس تمدّ الـ ZStack)
struct FT5UHeaderArt: View {
    let icon: String
    let deep: Color

    var body: some View {
        let icon = self.icon, deep = self.deep
        return FT5UStatic { ctx, size in FT5U.drawHeader(&ctx, size: size, icon: icon, deep: deep) }
            .frame(height: 86)
    }
}

struct FT5UBandArt: View {
    let mark: FT5UMark
    let mourning: Bool
    let ground: Color
    let band: CGSize
    let cell: CGFloat
    var fringe: CGFloat = 6

    var body: some View {
        let mark = self.mark, mourning = self.mourning, ground = self.ground, band = self.band
        let cell = self.cell, fringe = self.fringe
        return FT5UStatic { ctx, size in
            FT5U.drawBandCentered(&ctx, size: size, band: band, mark: mark, color: ground, cell: cell,
                                  fringe: fringe, mourning: mourning)
        }
    }
}

struct FT5UPatchIcon: View {
    let mark: FT5UMark
    let mourning: Bool
    let tint: Color

    var body: some View {
        let mark = self.mark, mourning = self.mourning, tint = self.tint
        return FT5UStatic { ctx, size in
            FT5U.drawPatchIcon(&ctx, size: size, mark: mark, tint: tint, mourning: mourning)
        }
    }
}

/// تحميل الشجرة: نول عليه حاشية الشجرة منسوجة، ومكّوك يعبر خيوط السَّدى ذهاباً وإياباً
/// (حركة ضمنية واحدة: إزاحة أفقية فقط). «تقليل الحركة»: المكّوك ساكن في الوسط.
struct FT5UTreeLoading: View {
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swing = false

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / FT5U.loomDesign.width, geo.size.height / FT5U.loomDesign.height)
            let moving = !(still || reduceMotion)
            let dx: CGFloat = moving ? (swing ? FT5U.shuttleTravel : -FT5U.shuttleTravel) * k : 0
            ZStack {
                FT5UStatic { ctx, size in FT5U.drawLoom(&ctx, size: size) }
                FT5UStatic { ctx, size in FT5U.drawShuttle(&ctx, size: size) }
                    .frame(width: 30 * k, height: 9 * k)
                    .offset(x: dx, y: (FT5U.shuttleY - FT5U.loomDesign.height / 2) * k)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            guard !still, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { swing = true }
        }
    }
}

/// لحظة النجاح: الحاشية تنفتح من الوسط وتكبر الرقعة — مرة واحدة (~٠٫٨ ث) ثم سكون
struct FT5UMoment: View {
    let glyph: FT5UGlyph
    let tint: Color
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let on = shown || still || reduceMotion
        let glyph = self.glyph, tint = self.tint
        let band = CGSize(width: 136, height: 62)
        return ZStack {
            FT5UStatic { ctx, size in
                FT5U.drawBandCentered(&ctx, size: size, band: band, mark: nil, color: tint, cell: 4, fringe: 7,
                                      mourning: false)
            }
            .mask(Rectangle().scaleEffect(x: on ? 1 : 0.02, y: 1, anchor: .center))
            FT5UStatic { ctx, size in
                FT5U.drawMomentPatch(&ctx, size: size, glyph: glyph, tint: tint)
            }
            .scaleEffect(on ? 1 : 0.5)
            .opacity(on ? 1 : 0)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            guard !still, !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.1)) { shown = true }
        }
    }
}

extension FT5U {
    /// رقعة اللحظة (شبكة ٤) في وسط الإطار
    static func drawMomentPatch(_ c: inout GraphicsContext, size: CGSize, glyph: FT5UGlyph, tint: Color) {
        let ltr = isLTR(c), dark = isDark(c)
        var g = c
        mirrorForLTR(&g, width: size.width)
        let ink = FT5UInk.of(dark: dark)
        let cell: CGFloat = 4
        let side = grid * cell + 4, half = side / 2
        let cx = (size.width / 2).rounded(), cy = (size.height / 2).rounded()
        g.fill(Path(roundedRect: CGRect(x: cx - half, y: cy - half, width: side, height: side), cornerRadius: 3),
               with: .color(ink.cream))
        drawMark(.glyph(glyph), in: &g, center: CGPoint(x: cx, y: cy), cell: cell,
                 main: FT5UPaint(color: tint, shade: dark ? 0.3 : 0), accent: FT5UPaint(color: ink.red), ink: ink, ltr: ltr)
    }
}
