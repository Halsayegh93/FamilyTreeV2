import SwiftUI

// «خط ذهبي» — الجولة الخامسة: نفس الأسلوب الذي أعجب المالك (رسمة خطّية ذهبية واحدة لكل مكان) ممدوداً للتطبيق كله.
//
// القواعد:
// • لكل مكان فكرة واحدة واضحة: خط ذهبي شمباني بسمك ~٢ نقطة بأطراف مدوّرة + تعبئة كريمية خفيفة + لمسة ذهبية مصمتة واحدة.
// • ثلاثة أسطح فقط: فوق لون القسم (المربّعات والرؤوس) = ذهبي مباشرة؛ فوق الأسطح المحايدة (الصفحات الفاضية، الانتظار،
//   الإشعارات، اللحظات) = «وسام»: قرص بلون القسم وحلقة ذهبية رفيعة والرسمة الذهبية داخله؛ والبطاقات الصغيرة (مربّعات
//   الإدارة، بطاقة الأخبار، الشارات الفاتحة) = خط بلون القسم ولمسة ذهبية.
// • «وفاة» والحِداد: رمادي/فضّي ساكن دائماً، بلا ذهبي ولا حركة.
//
// الأداء: كل الرسوم أشكال SwiftUI ثابتة (Shape) تُرسم مرة. لا TimelineView ولا مؤقّت. الحركة المسموحة فقط:
// رسم الخط لنفسه مرة واحدة (trim) عند الظهور، أو حركة واحدة هادئة (شفافية/إزاحة) لطبقة مرسومة أصلاً
// (رمل الساعة، لمعة خط الأرض في تحميل الشجرة). «تقليل الحركة» = ثابت تماماً.
// الاتجاه: SwiftUI يعكس الأشكال تلقائياً في العربي — لذلك تُرسم الرسمة داخل بيئة LTR ثابتة ويُعكس المسار يدوياً
// للإنجليزي في الرسوم ذات الاتجاه فقط (الرسمة تواجه «الداخل» في اللغتين، والرسم البياني يصعد يميناً دائماً).
// iOS 16: لا عمليات مسارات iOS 17 — التقاطعات تُحذف حسابياً (قصّ الخطوط خارج المضلّع) أو تُتجنّب بالتصميم.

// MARK: - الواجهة (العقد)

@MainActor enum FT5DTrial {
    /// الرسمة الذهبية تحلّ محل الأيقونة الزجاجية في المربّع (كانت تكرّر نفس الشيء)، والعدد ينتقل لمكانها
    static let showsTileIcon: Bool = false
    /// فوق طبقة الإضاءة/التعتيم (لا تبهت أسفل المربّع)
    static let tileArtUnderOverlay: Bool = false

    static let libraryVariantNames: [String] = ["رف كتب", "صور العائلة", "مخطوطة"]
    static let projectsVariantNames: [String] = ["حقيبة عمل", "سفينة البوم", "نموّ"]

    static func tile(_ place: String, variant: Int, badge: Bool, animateOnce: Bool) -> AnyView {
        guard let art = FT5D.tileArt(place, variant: variant) else { return AnyView(EmptyView()) }
        return AnyView(FT5DTileArt(art: art, drawOnAppear: animateOnce))
    }

    static func header(icon: String, tint: Color, deep: Color) -> AnyView {
        AnyView(FT5DHeaderArt(icon: icon))
    }

    static func empty(place: String?, icon: String, tint: Color) -> AnyView {
        AnyView(FT5DEmptyArt(place: place, icon: icon, tint: tint))
    }

    static func stateIcon(icon: String, tint: Color, size: CGFloat = 52) -> AnyView {
        AnyView(FT5DStateIcon(icon: icon, tint: tint, size: size))
    }

    static func treeLoading() -> AnyView { AnyView(FT5DTreeLoading()) }

    static func waiting() -> AnyView { AnyView(FT5DWaiting()) }

    static func notificationsEmpty() -> AnyView { AnyView(FT5DNotificationsEmpty()) }

    static func loginBackdrop(logoCenterY: CGFloat) -> AnyView {
        AnyView(FT5DLoginBackdrop(logoCenterY: logoCenterY))
    }

    static func newsBadge(type: String, tint: Color, onColor: Bool) -> AnyView? {
        guard let art = FT5D.badgeArt(type) else { return nil }
        return AnyView(FT5DNewsBadge(art: art, type: type, tint: tint, onColor: onColor))
    }

    static func moment(_ name: String, tint: Color) -> AnyView {
        AnyView(FT5DMoment(name: name, tint: tint))
    }

    static func greetingGlyph(hour: Int, tint: Color) -> AnyView {
        AnyView(FT5DTimeGlyph(time: .forHour(hour)))
    }

    /// بلا زخرفة داخل بطاقة الترحيب — اللمسة الوحيدة فيها رمز الوقت الذهبي (المالك رفض العلامات المائية الباهتة)
    static func greetingBackground(tint: Color) -> AnyView? { nil }

    static func tabHeaderOrnament(section: String, tint: Color) -> AnyView? {
        AnyView(FT5DTabOrnament())
    }

    static func pageHeroArt(icon: String, tint: Color) -> AnyView? {
        AnyView(FT5DHeroArt(icon: icon))
    }

    /// للعائلات فقط — الرمز العام يبقى أيقونته العادية (رسمه في الزاوية كان يكرّر نفس الرمز مرتين)
    static func dashTileArt(icon: String, tint: Color) -> AnyView? {
        guard let fam = FT5D.family(for: icon) else { return nil }
        return AnyView(FT5DDashArt(family: fam, tint: tint))
    }

    static func newsCardArt(tint: Color) -> AnyView? {
        AnyView(FT5DNewsCardArt(tint: tint))
    }
}

// MARK: - الرسومات

nonisolated enum FT5D {
    /// كل الرسومات (شبكة ١٠٠)
    nonisolated enum Art: String, CaseIterable, Sendable {
        // المربّعات والعائلات
        case tree, dallah, envelope, quill
        case shelf, photos, scroll          // المكتبة: رف كتب · صور العائلة · مخطوطة
        case briefcase, dhow, growth        // المشاريع: حقيبة عمل · سفينة البوم · نموّ
        case shield, gear, crescent, bell, hourglass
        // اللحظات
        case check, plane, seal, sapling
        // شارات الأخبار
        case bNews, bAnnounce, bCongrats, bWedding, bBirth, bVote, bInvite
    }

    /// fill = تعبئة كريمية · line = الخط الذهبي · mark = خط باللون الذهبي المصمت · accent = لمسة مصمتة · extra = طبقة الحركة الهادئة
    nonisolated enum Layer: Sendable { case fill, line, mark, accent, extra }

    nonisolated enum Align: Sendable { case bottom, center }

    nonisolated struct Parts: @unchecked Sendable {
        var box: CGRect
        var line = Path()
        var fill = Path()
        var mark = Path()
        var accent = Path()
        var extra = Path()
        /// تنعكس للإنجليزي (تواجه الداخل) — false للرموز بلا اتجاه والرسم البياني
        var directional = true
        var eoAccent = false
        func path(_ l: Layer) -> Path {
            switch l {
            case .fill: return fill
            case .line: return line
            case .mark: return mark
            case .accent: return accent
            case .extra: return extra
            }
        }
    }

    static func parts(_ a: Art) -> Parts {
        switch a {
        case .tree: return ft5dTree
        case .dallah: return ft5dDallah
        case .envelope: return ft5dEnvelope
        case .quill: return ft5dQuill
        case .shelf: return ft5dShelf
        case .photos: return ft5dPhotos
        case .scroll: return ft5dScroll
        case .briefcase: return ft5dBriefcase
        case .dhow: return ft5dDhow
        case .growth: return ft5dGrowth
        case .shield: return ft5dShield
        case .gear: return ft5dGear
        case .crescent: return ft5dCrescent
        case .bell: return ft5dBell
        case .hourglass: return ft5dHourglass
        case .check: return ft5dCheck
        case .plane: return ft5dPlane
        case .seal: return ft5dSeal
        case .sapling: return ft5dSapling
        case .bNews: return ft5dBadgeNews
        case .bAnnounce: return ft5dBadgeAnnounce
        case .bCongrats: return ft5dBadgeCongrats
        case .bWedding: return ft5dBadgeWedding
        case .bBirth: return ft5dBadgeBirth
        case .bVote: return ft5dBadgeVote
        case .bInvite: return ft5dBadgeInvite
        }
    }

    static func aspect(_ a: Art) -> CGFloat {
        let b = parts(a).box
        return b.width / b.height
    }

    /// المسار داخل `rect` (ملاءمة بلا تشويه) — `mirrored` يعكس أفقياً داخل الإطار
    static func path(_ a: Art, _ l: Layer, in rect: CGRect, mirrored: Bool, align: Align) -> Path {
        let p = parts(a)
        return p.path(l).applying(fit(p.box, into: rect, mirrored: mirrored, align: align))
    }

    static func fit(_ box: CGRect, into rect: CGRect, mirrored: Bool, align: Align) -> CGAffineTransform {
        let s = min(rect.width / box.width, rect.height / box.height)
        let w = box.width * s, h = box.height * s
        let ox = rect.minX + (rect.width - w) / 2
        let oy = align == .bottom ? rect.maxY - h : rect.minY + (rect.height - h) / 2
        var t = CGAffineTransform(translationX: ox, y: oy)
        if mirrored { t = t.translatedBy(x: w, y: 0).scaledBy(x: -1, y: 1) }
        return t.scaledBy(x: s, y: s).translatedBy(x: -box.minX, y: -box.minY)
    }

    // MARK: الأماكن والعائلات

    static func tileArt(_ place: String, variant: Int) -> Art? {
        switch place {
        case "tree": return .tree
        case "diwaniya", "diwaniyas": return .dallah
        case "contact": return .envelope
        case "news": return .quill
        case "library": return [Art.shelf, .photos, .scroll][min(2, max(0, variant))]
        case "projects": return [Art.briefcase, .dhow, .growth][min(2, max(0, variant))]
        default: return nil
        }
    }

    nonisolated enum Family: Sendable {
        case news, diwaniya, projects, library, tree, contact, security, settings, mourning, bell, waiting
        var art: Art {
            switch self {
            case .news: return .quill
            case .diwaniya: return .dallah
            case .projects: return .briefcase
            case .library: return .shelf
            case .tree: return .tree
            case .contact: return .envelope
            case .security: return .shield
            case .settings: return .gear
            case .mourning: return .crescent
            case .bell: return .bell
            case .waiting: return .hourglass
            }
        }
    }

    /// رمز SF ← عائلة رسمة (nil = المعالجة العامة: الرمز نفسه بالذهبي داخل حلقة)
    static func family(for icon: String) -> Family? {
        let comps = icon.split(separator: ".").map(String.init)
        guard let first = comps.first else { return nil }
        func has(_ c: String) -> Bool { comps.contains(c) }
        if icon.hasPrefix("heart.slash") { return .mourning }
        if has("lock") || has("shield") { return .security }
        if ["newspaper", "megaphone"].contains(first) || icon.hasPrefix("square.and.pencil") { return .news }
        if ["map", "mappin", "cup", "tent"].contains(first) || icon.hasPrefix("building.columns") { return .diwaniya }
        if ["storefront", "briefcase", "bag", "cart"].contains(first) { return .projects }
        if ["books", "book", "archivebox"].contains(first) { return .library }
        if first == "tree" || icon.hasPrefix("person.badge.plus") || icon.hasPrefix("person.crop.circle.badge.plus")
            || icon.hasPrefix("figure.child") || icon.hasPrefix("person.2") || icon.hasPrefix("person.3") { return .tree }
        if ["envelope", "paperplane"].contains(first) { return .contact }
        if ["gearshape", "gear", "slider", "paintbrush", "key", "iphone", "wrench", "switch"].contains(first)
            || (first == "person" && has("key")) { return .settings }
        if first == "bell" { return .bell }
        if first == "hourglass" || (first == "clock" && has("badge")) { return .waiting }
        return nil
    }

    /// أماكن الصفحات الفاضية
    static func placeArt(_ place: String?) -> Art? {
        guard let place else { return nil }
        if let a = tileArt(place, variant: 0) { return a }
        switch place {
        case "notifications": return .bell
        case "members", "member": return .tree
        case "waiting", "pending": return .hourglass
        case "settings": return .gear
        case "security": return .shield
        default: return nil
        }
    }

    static func badgeArt(_ type: String) -> Art? {
        switch type {
        case "خبر": return .bNews
        case "إعلان": return .bAnnounce
        case "تهنئة": return .bCongrats
        case "زواج": return .bWedding
        case "مولود": return .bBirth
        case "وفاة": return .crescent
        case "تصويت": return .bVote
        case "دعوة": return .bInvite
        case "تذكير": return .bell
        default: return nil
        }
    }

    // MARK: الألوان

    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: a)
    }

    static let champagne: [Color] = [hex(0xF3D99F), hex(0xE7C27A), hex(0xC9973F)]
    static let goldOnLight: [Color] = [hex(0xC9973F), hex(0xA77A2B)]
    static let goldOnDark: [Color] = [hex(0xF0D395), hex(0xD3A552)]

    // MARK: أدوات المسار

    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func poly(_ pts: [CGPoint], closed: Bool = true) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        if closed { p.closeSubpath() }
        return p
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    /// مستطيل كمضلّع (أعلى يسار ← أعلى يمين ← أسفل يمين ← أسفل يسار) — نفس الاتجاه دائماً فيصحّ جمع التعبئات
    static func rectPts(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> [CGPoint] {
        [pt(x, y), pt(x + w, y), pt(x + w, y + h), pt(x, y + h)]
    }

    static func transform(_ pts: [CGPoint], _ t: CGAffineTransform) -> [CGPoint] { pts.map { $0.applying(t) } }

    /// نقاط قوس (زوايا الشاشة: ٠° = يمين، ٩٠° = أسفل)
    static func arc(_ c: CGPoint, _ r: CGFloat, from a0: Double, to a1: Double, steps: Int = 40) -> [CGPoint] {
        (0...steps).map { i in
            let a = (a0 + (a1 - a0) * Double(i) / Double(steps)) * .pi / 180
            return pt(c.x + r * CGFloat(cos(a)), c.y + r * CGFloat(sin(a)))
        }
    }

    /// نجمة بعدد رؤوس (الرأس الأول للأعلى)
    static func star(_ c: CGPoint, outer: CGFloat, inner: CGFloat, points n: Int, rotation: Double = -90) -> Path {
        var pts: [CGPoint] = []
        for i in 0..<(2 * n) {
            let a = (rotation + Double(i) * 180 / Double(n)) * .pi / 180
            let r = i % 2 == 0 ? outer : inner
            pts.append(pt(c.x + r * CGFloat(cos(a)), c.y + r * CGFloat(sin(a))))
        }
        return poly(pts)
    }

    /// لمعة رباعية مقعّرة
    static func sparkle(_ c: CGPoint, _ r: CGFloat, pinch: CGFloat = 0.22) -> Path {
        var p = Path()
        let tips = [pt(c.x, c.y - r), pt(c.x + r, c.y), pt(c.x, c.y + r), pt(c.x - r, c.y)]
        let k = r * pinch
        let ctrls = [pt(c.x + k, c.y - k), pt(c.x + k, c.y + k), pt(c.x - k, c.y + k), pt(c.x - k, c.y - k)]
        p.move(to: tips[0])
        for i in 0..<4 { p.addQuadCurve(to: tips[(i + 1) % 4], control: ctrls[i]) }
        p.closeSubpath()
        return p
    }

    /// أجزاء الخط الواقعة خارج مضلّع محدّب (لإخفاء ما خلف شكل أمامي بلا عمليات مسارات iOS 17)
    static func outside(_ pts: [CGPoint], closed: Bool, of convex: [CGPoint]) -> Path {
        var out = Path()
        guard pts.count > 1, convex.count > 2 else { return poly(pts, closed: closed) }
        let cx = convex.map(\.x).reduce(0, +) / CGFloat(convex.count)
        let cy = convex.map(\.y).reduce(0, +) / CGFloat(convex.count)
        var edges: [(CGPoint, CGPoint)] = []   // (رأس، عمودي للداخل)
        for i in 0..<convex.count {
            let a = convex[i], b = convex[(i + 1) % convex.count]
            var n = pt(-(b.y - a.y), b.x - a.x)
            if n.x * (cx - a.x) + n.y * (cy - a.y) < 0 { n = pt(-n.x, -n.y) }
            edges.append((a, n))
        }
        var segs = Array(zip(pts, pts.dropFirst()))
        if closed, let l = pts.last, let f = pts.first { segs.append((l, f)) }
        for (p0, p1) in segs {
            let d = pt(p1.x - p0.x, p1.y - p0.y)
            var tE: CGFloat = 0, tL: CGFloat = 1, miss = false
            for (v, n) in edges {
                let num = n.x * (p0.x - v.x) + n.y * (p0.y - v.y)
                let den = n.x * d.x + n.y * d.y
                if abs(den) < 1e-9 {
                    if num < 0 { miss = true; break }
                } else if den > 0 {
                    tE = max(tE, -num / den)
                } else {
                    tL = min(tL, -num / den)
                }
            }
            func at(_ t: CGFloat) -> CGPoint { pt(p0.x + d.x * t, p0.y + d.y * t) }
            if miss || tE >= tL {
                out.move(to: p0); out.addLine(to: p1)
            } else {
                if tE > 0.001 { out.move(to: p0); out.addLine(to: at(tE)) }
                if tL < 0.999 { out.move(to: at(tL)); out.addLine(to: p1) }
            }
        }
        return out
    }

    // MARK: الظهور (للمعاينات: نفس منحنيات الحركة كدوال للزمن)

    nonisolated struct Phases: Sendable { let line: Double; let fill: Double; let accent: Double }

    static func phases(time: Double?, shown: Bool, draw: Double, delay: Double) -> Phases {
        guard let t0 = time else {
            let v = shown ? 1.0 : 0.0
            return Phases(line: v, fill: v, accent: v)
        }
        func c(_ x: Double) -> Double { min(1, max(0, x)) }
        let t = t0 - delay
        let a = c(t / draw)
        let line = a < 0.5 ? 2 * a * a : 1 - pow(-2 * a + 2, 2) / 2
        let f = c((t - draw * 0.64) / (draw * 0.45))
        let fill = 1 - (1 - f) * (1 - f)
        let accent = c((t - draw * 0.9) / 0.3)
        return Phases(line: line, fill: fill, accent: accent)
    }
}

// MARK: - الأحبار

nonisolated struct FT5DInk: Sendable {
    var line: [Color]
    var fill: [Color]
    var accent: [Color]
    var shadow: Double = 0

    /// فوق لون القسم (المربّعات، الرؤوس، الأوسمة)
    static let gold = FT5DInk(line: FT5D.champagne,
                              fill: [FT5D.hex(0xF2D9A6, 0.23), FT5D.hex(0xF2D9A6, 0.08)],
                              accent: FT5D.champagne, shadow: 0.28)
    /// خط بلون القسم ولمسة ذهبية (البطاقات الصغيرة على سطح فاتح/داكن)
    static func tint(_ c: Color, dark: Bool) -> FT5DInk {
        FT5DInk(line: [c, c], fill: [c.opacity(dark ? 0.22 : 0.15), c.opacity(dark ? 0.08 : 0.05)],
                accent: dark ? FT5D.goldOnDark : FT5D.goldOnLight)
    }
    /// أبيض فوق دائرة ملوّنة (شارات الأخبار) — اللمسة ذهبية فاتحة
    static func white(accentGold: Bool) -> FT5DInk {
        FT5DInk(line: [.white, .white.opacity(0.94)], fill: [.white.opacity(0.24), .white.opacity(0.10)],
                accent: accentGold ? [FT5D.hex(0xFBE7B5), FT5D.hex(0xF0CD82)] : [.white, .white], shadow: 0.16)
    }
    /// الحِداد فوق لون (فضّي) — بلا ذهبي
    static let silver = FT5DInk(line: [FT5D.hex(0xEDEDF0), FT5D.hex(0xC7C7CC)],
                                fill: [.white.opacity(0.16), .white.opacity(0.05)],
                                accent: [FT5D.hex(0xEDEDF0), FT5D.hex(0xC7C7CC)], shadow: 0.2)
    /// الحِداد فوق سطح محايد (رمادي)
    static func grey(_ c: Color) -> FT5DInk {
        FT5DInk(line: [c, c], fill: [c.opacity(0.14), c.opacity(0.05)], accent: [c, c])
    }
}

// MARK: - الشكل والرسمة

/// يُرسم دائماً داخل بيئة LTR (لا عكس تلقائي) — `mirrored` يحدّده اتجاه الواجهة الخارجي
nonisolated struct FT5DShape: Shape {
    var art: FT5D.Art
    var layer: FT5D.Layer
    var mirrored: Bool
    var align: FT5D.Align
    func path(in rect: CGRect) -> Path {
        FT5D.path(art, layer, in: rect, mirrored: mirrored, align: align)
    }
}

/// ظلّ ناعم فقط حين يلزم (فوق الألوان) — بلا طبقة تركيب حين لا ظلّ
struct FT5DSoftShadow: ViewModifier {
    let opacity: Double
    func body(content: Content) -> some View {
        if opacity > 0 {
            content.compositingGroup().shadow(color: .black.opacity(opacity), radius: 1.2, x: 0, y: 0.8)
        } else {
            content
        }
    }
}

/// الرسمة وحدها تملأ إطارها مع الحفاظ على النسبة
struct FT5DArtView: View {
    let art: FT5D.Art
    var ink: FT5DInk = .gold
    var lineWidth: CGFloat = 2.2
    var align: FT5D.Align = .bottom
    /// يرسم الخط نفسه مرة واحدة ثم يسكن
    var drawOnAppear: Bool = false
    var drawDuration: Double = 1.1
    var drawDelay: Double = 0
    /// حركة هادئة واحدة لطبقة `extra` (شفافية) — رمل الساعة
    var pulseExtra: Bool = false
    /// للمعاينات فقط: ثوانٍ منذ الظهور
    var time: Double? = nil

    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var pulse = false

    var body: some View {
        let parts = FT5D.parts(art)
        let mirrored = parts.directional && direction == .leftToRight
        let animate = drawOnAppear && !reduceMotion
        let ph = FT5D.phases(time: time, shown: !animate || drawn, draw: drawDuration, delay: drawDelay)
        let lineG = LinearGradient(colors: ink.line, startPoint: .top, endPoint: .bottom)
        let fillG = LinearGradient(colors: ink.fill, startPoint: .top, endPoint: .bottom)
        let accG = LinearGradient(colors: ink.accent, startPoint: .top, endPoint: .bottom)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let d = drawDuration, dl = drawDelay

        return ZStack {
            if !parts.fill.isEmpty {
                FT5DShape(art: art, layer: .fill, mirrored: mirrored, align: align)
                    .fill(fillG)
                    .opacity(ph.fill)
                    .animation(.easeOut(duration: d * 0.45).delay(dl + d * 0.64), value: drawn)
            }
            FT5DShape(art: art, layer: .line, mirrored: mirrored, align: align)
                .trim(from: 0, to: ph.line)
                .stroke(lineG, style: style)
                .animation(.easeInOut(duration: d).delay(dl), value: drawn)
            if !parts.mark.isEmpty {
                FT5DShape(art: art, layer: .mark, mirrored: mirrored, align: align)
                    .trim(from: 0, to: ph.line)
                    .stroke(accG, style: style)
                    .animation(.easeInOut(duration: d).delay(dl), value: drawn)
            }
            if !parts.accent.isEmpty {
                FT5DShape(art: art, layer: .accent, mirrored: mirrored, align: align)
                    .fill(accG, style: FillStyle(eoFill: parts.eoAccent))
                    .opacity(ph.accent)
                    .animation(.easeOut(duration: 0.3).delay(dl + d * 0.9), value: drawn)
            }
            if !parts.extra.isEmpty {
                FT5DShape(art: art, layer: .extra, mirrored: mirrored, align: align)
                    .stroke(accG, style: StrokeStyle(lineWidth: lineWidth * 0.75, lineCap: .round, dash: [0.1, lineWidth * 1.9]))
                    .opacity(ph.accent * (pulse ? 0.25 : 1))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .modifier(FT5DSoftShadow(opacity: ink.shadow))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if animate && !drawn { DispatchQueue.main.async { drawn = true } }
            if pulseExtra && !reduceMotion && !pulse {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

// MARK: - الوسام (فوق الأسطح المحايدة)

/// قرص بلون القسم + حلقة ذهبية رفيعة — الرسمة الذهبية داخله كأنها مربّع صغير مستدير
struct FT5DMedallion<Content: View>: View {
    let tint: Color
    let diameter: CGFloat
    var ring: Bool = true
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Circle().fill(tint)
            // تعميق: الفاتح تدرّج خفيف، الداكن تعتيم ثابت (ألوان القسم فاتحة في الداكن) حتى يُقرأ الذهبي
            Circle().fill(LinearGradient(colors: dark ? [.black.opacity(0.38), .black.opacity(0.58)]
                                                      : [.white.opacity(0.07), .black.opacity(0.30)],
                                         startPoint: .top, endPoint: .bottom))
            if ring {
                Circle()
                    .inset(by: diameter * 0.055)
                    .stroke(LinearGradient(colors: FT5D.champagne, startPoint: .top, endPoint: .bottom),
                            lineWidth: max(0.9, diameter * 0.012))
                    .opacity(0.8)
            }
            if dark { Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1) }
            content()
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(dark ? 0 : 0.14), radius: diameter * 0.07, x: 0, y: diameter * 0.035)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// رمز SF عام بالذهبي (للرموز التي ليس لها رسمة خاصة)
struct FT5DSymbolGlyph: View {
    let symbol: String
    let size: CGFloat
    var colors: [Color] = FT5D.champagne
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }
}

/// المعالجة العامة فوق الألوان: حلقتان ذهبيتان (كختم) والرمز نفسه ذهبي في الوسط
struct FT5DSymbolSeal: View {
    let symbol: String
    let diameter: CGFloat
    var body: some View {
        let g = LinearGradient(colors: FT5D.champagne, startPoint: .top, endPoint: .bottom)
        ZStack {
            Circle().fill(LinearGradient(colors: [FT5D.hex(0xF2D9A6, 0.20), FT5D.hex(0xF2D9A6, 0.06)],
                                         startPoint: .top, endPoint: .bottom))
            Circle().stroke(g, lineWidth: max(1.4, diameter * 0.038))
            Circle().inset(by: diameter * 0.10).stroke(g, lineWidth: max(0.8, diameter * 0.016)).opacity(0.7)
            FT5DSymbolGlyph(symbol: symbol, size: diameter * 0.36)
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 1.2, x: 0, y: 0.8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - ١) مربّعات الرئيسية

struct FT5DTileArt: View {
    let art: FT5D.Art
    var drawOnAppear: Bool = false
    var time: Double? = nil
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // عنوان من سطرين عريضين يمتدّ للطرف الآخر (إنجليزي الشجرة/المشاريع، أو خط كبير جداً) — الرسمة تصعد للشريط العلوي
        let long = typeSize >= .xxLarge
            || (direction == .leftToRight && (art == .tree || [.briefcase, .dhow, .growth].contains(art)))
        GeometryReader { geo in
            let g = FT5DTileArt.frame(art, tile: geo.size, longTitle: long)
            if g.size.width > 0 {
                FT5DArtView(art: art, lineWidth: g.line, drawOnAppear: drawOnAppear, time: time)
                    .frame(width: g.size.width, height: g.size.height)
                    .padding(.trailing, g.trailing)
                    .padding(.top, g.top)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    struct Frame { let size: CGSize; let trailing: CGFloat; let top: CGFloat; let line: CGFloat }

    /// إطار الرسمة في الطرف الآخر من المربّع: العريض بكامل الارتفاع تقريباً، الضيّق أعلى الطرف الآخر فوق سطر العنوان
    static func frame(_ art: FT5D.Art, tile: CGSize, longTitle: Bool) -> Frame {
        let W = tile.width, H = tile.height
        let wide = W / max(H, 1) >= 1.5
        var top: CGFloat, bottom: CGFloat, maxW: CGFloat
        if wide {
            top = H * 0.13; bottom = H * 0.11; maxW = W * 0.50
            if longTitle { top = H * 0.09; bottom = H * 0.47 }
        } else {
            top = H * 0.10; bottom = H * 0.37; maxW = W * 0.54
            if longTitle { bottom = H * 0.51 }
        }
        let h = H - top - bottom
        if h < 24 { return Frame(size: .zero, trailing: 0, top: 0, line: 0) }
        let w = min(maxW, h * FT5D.aspect(art))
        let line: CGFloat = h >= 66 ? 2.3 : (h >= 44 ? 2.1 : 1.9)
        return Frame(size: CGSize(width: w, height: h), trailing: W * 0.075, top: top, line: line)
    }
}

// MARK: - ٢) رأس المربّعات الوسطى (٨٦ نقطة)

/// الرسمة في الطرف الآخر من الرأس، داخل أقصى ٧٨ نقطة من الحافة (لا تصل الوسط ٥٥٪ في أضيق شاشة)
struct FT5DHeaderArt: View {
    let icon: String
    var time: Double? = nil
    var body: some View {
        Group {
            if let fam = FT5D.family(for: icon) {
                let a = fam.art
                FT5DArtView(art: a, ink: fam == .mourning ? .silver : .gold, lineWidth: 2.2, align: .center, time: time)
                    .frame(width: min(62, 56 * FT5D.aspect(a)), height: 56)
            } else {
                FT5DSymbolSeal(symbol: icon, diameter: 52)
            }
        }
        .frame(width: 62, height: 60)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - ٣) الصفحات الفاضية ورموز الحالة

/// الرسمة الذهبية داخل الوسام (أو الرمز العام)
struct FT5DMedallionArt: View {
    let art: FT5D.Art?
    let symbol: String
    let tint: Color
    let diameter: CGFloat
    var lineWidth: CGFloat = 2.2
    var drawOnAppear = false
    var drawDuration: Double = 1.1
    var drawDelay: Double = 0
    var pulseExtra = false
    var time: Double? = nil

    var body: some View {
        FT5DMedallion(tint: tint, diameter: diameter) {
            if let art {
                let mourning = art == .crescent
                FT5DArtView(art: art, ink: mourning ? .silver : .gold, lineWidth: lineWidth, align: .center,
                            drawOnAppear: drawOnAppear, drawDuration: drawDuration, drawDelay: drawDelay,
                            pulseExtra: pulseExtra, time: time)
                    .padding(diameter * 0.235)
            } else {
                FT5DSymbolGlyph(symbol: symbol, size: diameter * 0.36)
            }
        }
    }
}

struct FT5DEmptyArt: View {
    let place: String?
    let icon: String
    let tint: Color
    var body: some View {
        let art = FT5D.placeArt(place) ?? FT5D.family(for: icon)?.art
        FT5DMedallionArt(art: art, symbol: icon, tint: tint, diameter: 112, lineWidth: 2.3)
            .frame(width: 130, height: 130)
    }
}

struct FT5DStateIcon: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 52
    var body: some View {
        FT5DMedallionArt(art: FT5D.family(for: icon)?.art, symbol: icon, tint: tint, diameter: size,
                         lineWidth: max(1.4, size * 0.032))
            .frame(width: size, height: size)
    }
}

// MARK: - ٤) تحميل الشجرة · الانتظار · الإشعارات

/// غافة الشجرة في وسام القسم، ولمعة ذهبية واحدة تجري على خط الأرض ذهاباً وإياباً (إزاحة فقط) — شعور «جارٍ التحميل»
struct FT5DTreeLoading: View {
    var time: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var go = false

    var body: some View {
        let d: CGFloat = 156
        let glyph = CGRect(x: d * 0.2, y: d * 0.2, width: d * 0.6, height: d * 0.6)
        // خط الأرض في الغافة (١٨…٨٤ عند ٨٧) بإحداثيات الوسام
        let t = FT5D.fit(FT5D.parts(.tree).box, into: glyph, mirrored: false, align: .center)
        let a = CGPoint(x: 18, y: 87).applying(t), b = CGPoint(x: 84, y: 87).applying(t)
        let len = b.x - a.x
        let tint = scheme == .dark ? FT5D.hex(0x24665B) : FT5D.hex(0x1E5950)
        ZStack {
            FT5DMedallion(tint: tint, diameter: d) {
                ZStack(alignment: .topLeading) {
                    FT5DArtView(art: .tree, lineWidth: 2.6, align: .center, time: time)
                        .frame(width: glyph.width, height: glyph.height)
                        .offset(x: glyph.minX, y: glyph.minY)
                    if !reduceMotion {
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0), FT5D.hex(0xFFF4DC), .white.opacity(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 22, height: 3.2)
                            .offset(x: go ? len - 11 : -11)
                            .frame(width: len, height: 3.2, alignment: .leading)
                            .clipShape(Capsule())
                            .offset(x: a.x, y: a.y - 1.6)
                    }
                }
                .frame(width: d, height: d, alignment: .topLeading)
            }
        }
        .frame(width: 240, height: 200)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion, !go else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { go = true }
        }
    }
}

/// «بانتظار الموافقة»: ساعة رملية ذهبية في وسام الإدارة — خيط الرمل وحده يخفت ويعود (حركة شفافية واحدة)
struct FT5DWaiting: View {
    var time: Double? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        FT5DMedallionArt(art: .hourglass, symbol: "", tint: scheme == .dark ? FT5D.hex(0x525190) : FT5D.hex(0x47467F),
                         diameter: 124, lineWidth: 2.4, pulseExtra: true, time: time)
            .frame(width: 140, height: 140)
    }
}

/// لا إشعارات: جرس ذهبي ساكن في وسام الكحلي
struct FT5DNotificationsEmpty: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        FT5DMedallionArt(art: .bell, symbol: "", tint: scheme == .dark ? FT5D.hex(0x285D8D) : FT5D.hex(0x1F4E79),
                         diameter: 104, lineWidth: 2.2)
            .frame(width: 120, height: 120)
    }
}

// MARK: - ٥) خلفية الدخول — حلقتان ذهبيتان شعريتان حول الشعار (شبه غائبتين)

struct FT5DLoginBackdrop: View {
    let logoCenterY: CGFloat
    var animate = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let dark = scheme == .dark
        let gold = dark ? FT5D.hex(0xE7C27A) : FT5D.hex(0xC9973F)
        let on = shown || !animate || reduceMotion
        GeometryReader { geo in
            ZStack {
                Circle().stroke(gold.opacity(dark ? 0.20 : 0.22), lineWidth: 1)
                    .frame(width: 168, height: 168)
                Circle().stroke(gold.opacity(dark ? 0.11 : 0.12), lineWidth: 0.8)
                    .frame(width: 236, height: 236)
                FT5DRingDiamonds(radius: 118, count: 8, size: 3.4)
                    .fill(gold.opacity(dark ? 0.24 : 0.26))
                    .frame(width: 244, height: 244)
            }
            .scaleEffect(on ? 1 : 0.96)
            .opacity(on ? 1 : 0)
            .position(x: geo.size.width / 2, y: logoCenterY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard animate, !reduceMotion, !shown else { return }
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) { shown = true }
        }
    }
}

nonisolated struct FT5DRingDiamonds: Shape {
    var radius: CGFloat
    var count: Int
    var size: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
            let q = CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a)))
            p.addPath(FT5D.poly([CGPoint(x: q.x, y: q.y - size), CGPoint(x: q.x + size * 0.75, y: q.y),
                                 CGPoint(x: q.x, y: q.y + size), CGPoint(x: q.x - size * 0.75, y: q.y)]))
        }
        return p
    }
}

// MARK: - ٦) شارات أنواع الأخبار

struct FT5DNewsBadge: View {
    let art: FT5D.Art
    let type: String
    let tint: Color
    let onColor: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let mourning = art == .crescent
            let ink: FT5DInk = onColor
                ? (mourning ? .white(accentGold: false) : .white(accentGold: type != "تهنئة"))
                : (mourning ? .grey(tint) : .tint(tint, dark: scheme == .dark))
            FT5DArtView(art: art, ink: ink, lineWidth: min(2.3, max(1.35, side * 0.05)), align: .center)
                .frame(width: side * 0.6, height: side * 0.6)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - ٧) لحظات النجاح (مرة واحدة ≤ ١٫٢ ث ثم سكون)

struct FT5DMoment: View {
    let name: String
    let tint: Color
    /// للمعاينات فقط
    var time: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var art: FT5D.Art {
        switch name {
        case "sentForApproval": return .plane
        case "approved": return .seal
        case "newMember": return .sapling
        default: return .check
        }
    }

    var body: some View {
        let animate = !reduceMotion
        let k: Double = {
            if let time { return min(1, max(0, time / 0.35)) }
            return (appeared || !animate) ? 1 : 0
        }()
        let e = 1 - pow(1 - k, 3)
        ZStack {
            if name == "approved" {
                FT5DRibbons()
                    .fill(LinearGradient(colors: FT5D.champagne, startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 24)
                    .offset(y: 38)
                    .opacity(e)
            }
            FT5DMedallionArt(art: art, symbol: "", tint: tint, diameter: 84, lineWidth: 2.4,
                             drawOnAppear: animate, drawDuration: 0.75, drawDelay: 0.15, time: time)
                .scaleEffect(0.86 + 0.14 * e)
                .opacity(e)
        }
        .offset(y: name == "approved" ? -6 : 0)
        .frame(width: 160, height: 112)
        .animation(.easeOut(duration: 0.35), value: appeared)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if animate && !appeared { DispatchQueue.main.async { appeared = true } } }
    }
}

/// شريطا الوسام تحت «تمّت الموافقة»
nonisolated struct FT5DRibbons: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.addPath(FT5D.poly([CGPoint(x: r.minX + w * 0.28, y: r.minY), CGPoint(x: r.minX + w * 0.48, y: r.minY),
                             CGPoint(x: r.minX + w * 0.30, y: r.maxY), CGPoint(x: r.minX + w * 0.18, y: r.minY + h * 0.80),
                             CGPoint(x: r.minX + w * 0.04, y: r.maxY - h * 0.06)]))
        p.addPath(FT5D.poly([CGPoint(x: r.maxX - w * 0.28, y: r.minY), CGPoint(x: r.maxX - w * 0.48, y: r.minY),
                             CGPoint(x: r.maxX - w * 0.30, y: r.maxY), CGPoint(x: r.maxX - w * 0.18, y: r.minY + h * 0.80),
                             CGPoint(x: r.maxX - w * 0.04, y: r.maxY - h * 0.06)]))
        return p
    }
}

// MARK: - ٨) شريط رأس التبويبات — خطّان ذهبيان شعريان يلتقيان عند نجمة ثمانية (بدل خط السدو)

struct FT5DTabOrnament: View {
    var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let on = shown || !animate || reduceMotion
        let g = LinearGradient(colors: FT5D.champagne, startPoint: .top, endPoint: .bottom)
        HStack(spacing: 6) {
            Rectangle()
                .fill(LinearGradient(colors: [FT5D.hex(0xE7C27A, 0), FT5D.hex(0xE7C27A, 0.85)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.2)
                .scaleEffect(x: on ? 1 : 0, anchor: .trailing)
            FT5DDiamond().fill(g).frame(width: 4.5, height: 6)
            FT5DStar8().fill(g).frame(width: 12, height: 12)
            FT5DDiamond().fill(g).frame(width: 4.5, height: 6)
            Rectangle()
                .fill(LinearGradient(colors: [FT5D.hex(0xE7C27A, 0.85), FT5D.hex(0xE7C27A, 0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.2)
                .scaleEffect(x: on ? 1 : 0, anchor: .leading)
        }
        .frame(height: 12)
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard animate, !reduceMotion, !shown else { return }
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { shown = true }
        }
    }
}

nonisolated struct FT5DStar8: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 2
        return FT5D.star(CGPoint(x: r.midX, y: r.midY), outer: s, inner: s * 0.52, points: 8, rotation: -90)
    }
}

nonisolated struct FT5DDiamond: Shape {
    func path(in r: CGRect) -> Path {
        FT5D.poly([CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
                   CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)])
    }
}

// MARK: - ٩) بطل الصفحات (DSPageHero) · مربّعات الإدارة · بطاقة الأخبار

/// أعلى الطرف الآخر من البطل، فوق صف الأرقام (٦٠ نقطة من الأعلى + ١٤ هامش)
struct FT5DHeroArt: View {
    let icon: String
    var body: some View {
        Group {
            if let fam = FT5D.family(for: icon) {
                FT5DArtView(art: fam.art, ink: fam == .mourning ? .silver : .gold, lineWidth: 2.2, align: .center)
                    .frame(width: min(66, 58 * FT5D.aspect(fam.art)), height: 58)
            } else {
                FT5DSymbolSeal(symbol: icon, diameter: 54)
            }
        }
        .frame(width: 66, height: 58)
        .padding(.top, 14)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// ٤٠×٤٠: خط بلون المربّع ولمسة ذهبية
struct FT5DDashArt: View {
    let family: FT5D.Family
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        FT5DArtView(art: family.art, ink: family == .mourning ? .grey(tint) : .tint(tint, dark: dark),
                    lineWidth: 1.7, align: .center)
            .padding(2)
            .frame(width: 40, height: 40)
            .brightness(dark ? 0.22 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// ورقة وريشة بلون الأخبار ولمسة ذهبية — ٥٦×٤٠
struct FT5DNewsCardArt: View {
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        FT5DArtView(art: .quill, ink: .tint(tint, dark: scheme == .dark), lineWidth: 1.8, align: .center)
            .frame(width: 56, height: 40)
    }
}

// MARK: - ١٠) رمز الوقت في بطاقة الترحيب (من الجولة الرابعة — أعجب المالك)

nonisolated enum FT5DTime: Sendable {
    case morning, afternoon, evening
    static func forHour(_ h: Int) -> FT5DTime {
        (4..<12).contains(h) ? .morning : ((12..<17).contains(h) ? .afternoon : .evening)
    }
}

/// شمس طالعة · شمس · هلال — بالخط الذهبي، ثابت، ١٨ نقطة
struct FT5DTimeGlyph: View {
    let time: FT5DTime
    var size: CGFloat = 18
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let lw = max(1.5, size * 0.095)
        let grad = LinearGradient(colors: scheme == .dark ? FT5D.goldOnDark : FT5D.goldOnLight,
                                  startPoint: .top, endPoint: .bottom)
        ZStack {
            FT5DGlyphShape(time: time, fill: true, flip: direction == .rightToLeft).fill(grad)
            FT5DGlyphShape(time: time, fill: false, flip: direction == .rightToLeft)
                .stroke(grad, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// الرمز بلا اتجاه: يُلغى العكس التلقائي في العربي (`flip`) فيبقى الهلال كرموز النظام
nonisolated struct FT5DGlyphShape: Shape {
    let time: FT5DTime
    let fill: Bool
    var flip = false
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20
        var t = CGAffineTransform(translationX: rect.midX - 10 * s, y: rect.midY - 10 * s).scaledBy(x: s, y: s)
        if flip { t = t.translatedBy(x: 20, y: 0).scaledBy(x: -1, y: 1) }
        let P = FT5D.pt
        var p = Path()
        switch time {
        case .evening:
            guard fill else { return Path() }
            p.move(to: P(12.2, 2.2))
            p.addCurve(to: P(17.4, 14.6), control1: P(3.0, 3.4), control2: P(3.6, 19.4))
            p.addCurve(to: P(12.2, 2.2), control1: P(11.0, 15.4), control2: P(8.6, 7.6))
            p.closeSubpath()
        case .afternoon:
            if fill {
                p.addEllipse(in: CGRect(x: 5.6, y: 5.6, width: 8.8, height: 8.8))
            } else {
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4
                    p.move(to: P(10 + 7.0 * CGFloat(cos(a)), 10 + 7.0 * CGFloat(sin(a))))
                    p.addLine(to: P(10 + 9.0 * CGFloat(cos(a)), 10 + 9.0 * CGFloat(sin(a))))
                }
            }
        case .morning:
            if fill {
                p.move(to: P(4.6, 15))
                p.addArc(center: P(10, 15), radius: 5.4, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                p.closeSubpath()
            } else {
                p.move(to: P(1.5, 15.2)); p.addLine(to: P(18.5, 15.2))
                for d in [-90.0, -140, -40] {
                    let a = d * .pi / 180
                    p.move(to: P(10 + 7.6 * CGFloat(cos(a)), 15 + 7.6 * CGFloat(sin(a))))
                    p.addLine(to: P(10 + 9.8 * CGFloat(cos(a)), 15 + 9.8 * CGFloat(sin(a))))
                }
            }
        }
        return p.applying(t)
    }
}

// MARK: - الرسومات (شبكة ١٠٠؛ الاتجاه للعربي: «الداخل» نحو اليمين)

// ── من الجولة الرابعة (أعجبت المالك): الغافة، الدلّة والفنجان، الظرف بختم، الورقة والريشة ──

nonisolated private let ft5dTree: FT5D.Parts = {
    let P = FT5D.pt
    func bumps(_ p: inout Path, _ pts: [CGPoint], _ bulge: CGFloat) {
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dx = b.x - a.x, dy = b.y - a.y
            p.addQuadCurve(to: b, control: P((a.x + b.x) / 2 + dy * bulge, (a.y + b.y) / 2 - dx * bulge))
        }
    }
    var crown = Path()
    let top = [P(8, 47), P(15, 35), P(29, 27), P(50, 23.5), P(71, 27), P(85, 35), P(92, 47)]
    crown.move(to: top[0])
    bumps(&crown, top, 0.24)
    bumps(&crown, [P(92, 47), P(71, 50), P(50, 49), P(29, 50), P(8, 47)], 0.12)
    crown.closeSubpath()

    var trunk = Path()
    trunk.move(to: P(39, 87))
    trunk.addCurve(to: P(46, 74), control1: P(44, 85), control2: P(46, 80))
    trunk.addCurve(to: P(31, 51), control1: P(46, 64), control2: P(38, 57))
    trunk.move(to: P(63, 87))
    trunk.addCurve(to: P(56, 74), control1: P(58, 85), control2: P(56, 80))
    trunk.addCurve(to: P(70, 51), control1: P(56, 64), control2: P(63, 57))
    trunk.move(to: P(42, 51))
    trunk.addCurve(to: P(51, 63), control1: P(46, 54), control2: P(50, 58))
    trunk.addCurve(to: P(59, 51), control1: P(52, 58), control2: P(55, 54))

    var trunkFill = Path()
    trunkFill.move(to: P(39, 87))
    trunkFill.addCurve(to: P(46, 74), control1: P(44, 85), control2: P(46, 80))
    trunkFill.addCurve(to: P(31, 51), control1: P(46, 64), control2: P(38, 57))
    trunkFill.addLine(to: P(42, 51))
    trunkFill.addCurve(to: P(51, 63), control1: P(46, 54), control2: P(50, 58))
    trunkFill.addCurve(to: P(59, 51), control1: P(52, 58), control2: P(55, 54))
    trunkFill.addLine(to: P(70, 51))
    trunkFill.addCurve(to: P(56, 74), control1: P(63, 57), control2: P(56, 64))
    trunkFill.addCurve(to: P(63, 87), control1: P(56, 80), control2: P(58, 85))
    trunkFill.closeSubpath()

    var parts = FT5D.Parts(box: CGRect(x: 4, y: 18, width: 92, height: 72))
    parts.line.move(to: P(18, 87)); parts.line.addLine(to: P(84, 87))
    parts.line.addPath(trunk)
    parts.line.addPath(crown)
    parts.fill.addPath(crown)
    parts.fill.addPath(trunkFill)
    return parts
}()

nonisolated private let ft5dDallah: FT5D.Parts = {
    let P = FT5D.pt
    var body = Path()
    body.move(to: P(31, 86))
    body.addCurve(to: P(25, 61), control1: P(17, 82), control2: P(15, 67))
    body.addCurve(to: P(34, 50), control1: P(30, 57), control2: P(34, 54))
    body.addCurve(to: P(28, 41), control1: P(34, 46), control2: P(30, 44))
    body.addLine(to: P(52, 41))
    body.addCurve(to: P(46, 50), control1: P(50, 44), control2: P(46, 46))
    body.addCurve(to: P(55, 61), control1: P(46, 54), control2: P(50, 57))
    body.addCurve(to: P(49, 86), control1: P(65, 67), control2: P(63, 82))
    body.closeSubpath()

    var line = Path()
    line.move(to: P(31, 86)); line.addLine(to: P(29, 90)); line.addLine(to: P(51, 90)); line.addLine(to: P(49, 86))
    line.addPath(body)
    line.move(to: P(30, 41))
    line.addCurve(to: P(40, 27), control1: P(30, 34), control2: P(36, 31))
    line.addCurve(to: P(50, 41), control1: P(44, 31), control2: P(50, 34))
    line.move(to: P(40, 27)); line.addLine(to: P(40, 23))
    line.move(to: P(59, 74))
    line.addCurve(to: P(81, 33), control1: P(72, 68), control2: P(72, 46))
    line.addCurve(to: P(56, 63), control1: P(70, 42), control2: P(65, 56))
    line.move(to: P(29, 44))
    line.addCurve(to: P(22, 67), control1: P(16, 45), control2: P(12, 57))
    var cup = Path()
    cup.move(to: P(69, 79)); cup.addLine(to: P(87, 79))
    cup.addCurve(to: P(78, 90), control1: P(87, 85), control2: P(83, 90))
    cup.addCurve(to: P(69, 79), control1: P(73, 90), control2: P(69, 85))
    cup.closeSubpath()
    line.addPath(cup)
    line.move(to: P(78, 73))
    line.addCurve(to: P(79, 61), control1: P(74, 69), control2: P(83, 65))

    var parts = FT5D.Parts(box: CGRect(x: 10, y: 10, width: 82, height: 83))
    parts.line = line
    parts.fill.addPath(body)
    parts.fill.addPath(cup)
    parts.accent.move(to: P(40, 13))
    parts.accent.addCurve(to: P(40, 24), control1: P(42.5, 17), control2: P(44, 21))
    parts.accent.addCurve(to: P(40, 13), control1: P(36, 21), control2: P(37.5, 17))
    parts.accent.closeSubpath()
    return parts
}()

nonisolated private let ft5dEnvelope: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 6, y: 12, width: 88, height: 62))
    let body = FT5D.rr(10, 16, 80, 54, 5)
    parts.line.addPath(body)
    parts.line.move(to: P(13, 19)); parts.line.addLine(to: P(40.5, 39.6))
    parts.line.move(to: P(59.5, 39.6)); parts.line.addLine(to: P(87, 19))
    parts.fill = body
    // ختم شمعي بحافة متموّجة ومعيّن مفرّغ
    let c = P(50, 47), n = 10
    for i in 0...(2 * n) {
        let a = Double(i) / Double(2 * n) * 2 * .pi - .pi / 2
        let r: CGFloat = i % 2 == 0 ? 10.2 : 9.0
        let p = P(c.x + r * CGFloat(cos(a)), c.y + r * CGFloat(sin(a)))
        if i == 0 { parts.accent.move(to: p) } else {
            let am = (Double(i) - 0.5) / Double(2 * n) * 2 * .pi - .pi / 2
            parts.accent.addQuadCurve(to: p, control: P(c.x + 9.9 * CGFloat(cos(am)), c.y + 9.9 * CGFloat(sin(am))))
        }
    }
    parts.accent.closeSubpath()
    parts.accent.addPath(FT5D.poly([P(50, 42.2), P(54.8, 47), P(50, 51.8), P(45.2, 47)]))
    parts.eoAccent = true
    parts.directional = false
    return parts
}()

nonisolated private let ft5dQuill: FT5D.Parts = {
    let P = FT5D.pt
    let sheet = FT5D.poly([P(14, 14), P(50, 14), P(60, 24), P(60, 82), P(14, 82)])
    var parts = FT5D.Parts(box: CGRect(x: 10, y: 8, width: 90, height: 82))
    parts.line.addPath(sheet)
    parts.line.move(to: P(50, 14)); parts.line.addLine(to: P(50, 24)); parts.line.addLine(to: P(60, 24))
    for (y, x1) in [(CGFloat(40), CGFloat(22)), (CGFloat(49), CGFloat(27)), (CGFloat(58), CGFloat(35))] {
        parts.line.move(to: P(x1, y)); parts.line.addLine(to: P(52, y))
    }
    var feather = Path()
    feather.move(to: P(72, 72))
    feather.addCurve(to: P(95, 11), control1: P(63, 52), control2: P(77, 21))
    feather.addCurve(to: P(96.5, 35), control1: P(97.5, 18), control2: P(98, 27))
    feather.addLine(to: P(89, 40.5))
    feather.addLine(to: P(94.5, 44))
    feather.addCurve(to: P(76.5, 73), control1: P(92, 58), control2: P(85, 68))
    feather.closeSubpath()
    parts.line.addPath(feather)
    parts.line.move(to: P(74, 73)); parts.line.addCurve(to: P(90, 21), control1: P(77, 58), control2: P(83, 35))
    parts.line.move(to: P(74, 73)); parts.line.addLine(to: P(69, 87))
    parts.fill.addPath(sheet)
    parts.fill.addPath(feather)
    parts.accent = FT5D.rr(30, 29, 22.5, 4.6, 2.3)
    return parts
}()

// ── المكتبة (جديدة): رف كتب · صور العائلة · مخطوطة ──

/// ١) رف كتب: ثلاثة كتب واقفة بأطوال مختلفة وكتاب رابع مائل يستند عليها، فوق لوح الرف — وشريط ذهبي على الأطول
nonisolated private let ft5dShelf: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 4, y: 15, width: 84, height: 76))
    let books: [(CGFloat, CGFloat, CGFloat, [CGFloat])] = [
        (12, 28, 14, [35, 73]),     // x, أعلى، عرض، أشرطة
        (26, 40, 12, [47, 73]),
        (38, 20, 16, [27, 73])
    ]
    for (x, y, w, bands) in books {
        let r = FT5D.rr(x, y, w, 80 - y, 1.8)
        parts.line.addPath(r)
        parts.fill.addPath(r)
        for b in bands { parts.line.move(to: P(x + 0.5, b)); parts.line.addLine(to: P(x + w - 0.5, b)) }
    }
    // الكتاب المائل: قاعدته عند ٦٤ ورأسه يلمس الكتاب الأطول عند ٥٤
    let h: CGFloat = 44, w: CGFloat = 13
    let s = (64.0 - 54.0) / h, c = (1 - s * s).squareRoot()
    let base = P(64, 80)
    let u = P(-s * h, -c * h), r = P(c * w, -s * w)
    let pts = [base, P(base.x + r.x, base.y + r.y), P(base.x + r.x + u.x, base.y + r.y + u.y), P(base.x + u.x, base.y + u.y)]
    parts.line.addPath(FT5D.poly(pts))
    parts.fill.addPath(FT5D.poly(pts))
    for f in [CGFloat(7) / h, CGFloat(37) / h] {
        parts.line.move(to: P(base.x + u.x * f, base.y + u.y * f))
        parts.line.addLine(to: P(base.x + r.x + u.x * f, base.y + r.y + u.y * f))
    }
    // اللوح وكتيفتاه
    let shelf = FT5D.rr(5, 80, 82, 6, 2)
    parts.line.addPath(shelf)
    parts.fill.addPath(shelf)
    parts.line.move(to: P(16, 86)); parts.line.addLine(to: P(16, 90))
    parts.line.move(to: P(76, 86)); parts.line.addLine(to: P(76, 90))
    parts.accent = FT5D.rr(41.5, 37, 9, 12, 1.6)
    return parts
}()

/// ٢) صور العائلة: صورتان قديمتان بإطار أبيض (بولارويد) — الخلفية مائلة، والأمامية فيها كبير وصغير، وزوايا ألبوم ذهبية
nonisolated private let ft5dPhotos: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 5, y: 10, width: 88, height: 78))
    let backT = CGAffineTransform(translationX: 39, y: 42).rotated(by: -9 * .pi / 180)
    let frontT = CGAffineTransform(translationX: 60, y: 59).rotated(by: 6 * .pi / 180)
    let backOuter = FT5D.transform(FT5D.rectPts(-25, -21, 50, 42), backT)
    let backInner = FT5D.transform(FT5D.rectPts(-20.5, -16.5, 41, 25), backT)
    let frontOuter = FT5D.transform(FT5D.rectPts(-27, -24, 54, 48), frontT)
    let frontInner = FT5D.transform(FT5D.rectPts(-22.5, -19.5, 45, 30), frontT)
    // الصورة الخلفية: يُرسم منها ما يظهر فقط
    parts.line.addPath(FT5D.outside(backOuter, closed: true, of: frontOuter))
    parts.line.addPath(FT5D.outside(backInner, closed: true, of: frontOuter))
    parts.line.addPath(FT5D.poly(frontOuter))
    parts.line.addPath(FT5D.poly(frontInner))
    // كبير وصغير داخل الصورة الأمامية (إحداثيات محلية، القاعدة = أسفل الصورة الداخلية عند ١٠٫٥)
    var people = Path()
    people.addPath(FT5D.circle(P(-8, -5), 5.2))
    people.move(to: P(-18.5, 10.5)); people.addQuadCurve(to: P(2, 10.5), control: P(-8.2, -5.5))
    people.addPath(FT5D.circle(P(10.5, 1.5), 3.7))
    people.move(to: P(4.5, 10.5)); people.addQuadCurve(to: P(16.5, 10.5), control: P(10.5, 3.6))
    parts.line.addPath(people.applying(frontT))
    parts.fill.addPath(FT5D.poly(backOuter))
    parts.fill.addPath(FT5D.poly(frontOuter))
    // زوايا الألبوم
    var corners = Path()
    let k: CGFloat = 8
    for (x, y, sx, sy) in [(CGFloat(-27), CGFloat(-24), CGFloat(1), CGFloat(1)), (27, -24, -1, 1), (27, 24, -1, -1), (-27, 24, 1, -1)] {
        corners.addPath(FT5D.poly([P(x - sx * 1.2, y - sy * 1.2), P(x + sx * k, y - sy * 1.2), P(x - sx * 1.2, y + sy * k)]))
    }
    parts.accent = corners.applying(frontT)
    return parts
}()

/// ٣) مخطوطة: ورقة بين عمودين (أعلى وأسفل) بمقابض، ونجمة ذهبية ثمانية في رأسها، وأسطر بمحاذاة الكتابة العربية
nonisolated private let ft5dScroll: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 9, y: 8, width: 82, height: 74))
    let top = FT5D.rr(19, 12, 62, 9, 4.5), bottom = FT5D.rr(19, 69, 62, 9, 4.5)
    parts.line.addPath(top)
    parts.line.addPath(bottom)
    for (x, y) in [(CGFloat(15), CGFloat(16.5)), (85, 16.5), (15, 73.5), (85, 73.5)] {
        parts.line.addPath(FT5D.circle(P(x, y), 3.2))
    }
    parts.line.move(to: P(26, 21)); parts.line.addLine(to: P(26, 69))
    parts.line.move(to: P(74, 21)); parts.line.addLine(to: P(74, 69))
    for (y, x1) in [(CGFloat(43), CGFloat(34)), (CGFloat(51), CGFloat(39)), (CGFloat(59), CGFloat(47))] {
        parts.line.move(to: P(x1, y)); parts.line.addLine(to: P(66, y))
    }
    parts.fill.addPath(FT5D.poly(FT5D.rectPts(26, 21, 48, 48)))
    parts.fill.addPath(top)
    parts.fill.addPath(bottom)
    parts.accent = FT5D.star(P(50, 31.5), outer: 6.4, inner: 3.6, points: 8, rotation: -90)
    return parts
}()

// ── المشاريع (جديدة): حقيبة عمل · سفينة البوم · نموّ ──

/// ١) حقيبة عمل: جسم بمقبض، وخط الوسط ينقطع عند قفل ذهبي
nonisolated private let ft5dBriefcase: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 6, y: 16, width: 88, height: 70))
    let body = FT5D.rr(10, 32, 80, 50, 7)
    parts.line.addPath(body)
    parts.line.move(to: P(38, 32)); parts.line.addLine(to: P(38, 25.5))
    parts.line.addQuadCurve(to: P(42.5, 21), control: P(38, 21))
    parts.line.addLine(to: P(57.5, 21))
    parts.line.addQuadCurve(to: P(62, 25.5), control: P(62, 21))
    parts.line.addLine(to: P(62, 32))
    parts.line.move(to: P(10.5, 51)); parts.line.addLine(to: P(42, 51))
    parts.line.move(to: P(58, 51)); parts.line.addLine(to: P(89.5, 51))
    parts.fill = body
    parts.accent = FT5D.rr(42.5, 45, 15, 12, 2.6)
    parts.accent.addPath(FT5D.rr(48.4, 49, 3.2, 4.8, 1.2))
    parts.eoAccent = true
    parts.directional = false
    return parts
}()

/// ٢) سفينة البوم: بدن كويتي بمقدّمة مرتفعة، وشراع مثلث مائل، وراية ذهبية أعلى الصاري، وموجة واحدة
nonisolated private let ft5dDhow: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 4, y: 7, width: 94, height: 83))
    var hull = Path()
    hull.move(to: P(10, 57))
    hull.addLine(to: P(17, 72))
    hull.addQuadCurve(to: P(72, 74), control: P(42, 79))
    hull.addCurve(to: P(96, 47), control1: P(84, 70), control2: P(92, 58))
    hull.addQuadCurve(to: P(10, 57), control: P(56, 64))
    hull.closeSubpath()
    var sail = Path()
    sail.move(to: P(80, 49))
    sail.addLine(to: P(24, 12))
    sail.addQuadCurve(to: P(30, 50), control: P(13, 33))
    sail.addQuadCurve(to: P(80, 49), control: P(55, 45))
    sail.closeSubpath()
    parts.line.addPath(hull)
    parts.line.move(to: P(19, 64.5)); parts.line.addQuadCurve(to: P(83, 59.5), control: P(50, 68.5))
    parts.line.addPath(sail)
    // الصاري: أسفل الشراع وأعلى العارضة فقط (ما خلف الشراع مخفيّ)
    parts.line.move(to: P(52, 58.2)); parts.line.addLine(to: P(52, 47.6))
    parts.line.move(to: P(52, 30.5)); parts.line.addLine(to: P(52, 19))
    // موجة
    parts.line.move(to: P(14, 85))
    parts.line.addQuadCurve(to: P(32, 85), control: P(23, 81))
    parts.line.addQuadCurve(to: P(50, 85), control: P(41, 89))
    parts.line.addQuadCurve(to: P(68, 85), control: P(59, 81))
    parts.line.addQuadCurve(to: P(86, 85), control: P(77, 89))
    parts.fill.addPath(hull)
    parts.fill.addPath(sail)
    parts.accent = FT5D.poly([P(52.6, 18.5), P(65, 22.5), P(52.6, 26.5)])
    return parts
}()

/// ٣) نموّ: ثلاثة أعمدة متصاعدة وخط صاعد ينتهي برأس سهم ذهبي (يصعد يميناً في اللغتين)
nonisolated private let ft5dGrowth: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 5, y: 7, width: 90, height: 81))
    parts.line.move(to: P(8, 84)); parts.line.addLine(to: P(92, 84))
    for (x, y) in [(CGFloat(16), CGFloat(66)), (40, 52), (64, 36)] {
        let bar = FT5D.rr(x, y, 16, 84 - y, 2.4)
        parts.line.addPath(bar)
        parts.fill.addPath(bar)
    }
    parts.line.move(to: P(10, 55)); parts.line.addLine(to: P(30, 37))
    parts.line.addLine(to: P(46, 45)); parts.line.addLine(to: P(75, 18))
    let e = P(75, 18), dx: CGFloat = 29, dy: CGFloat = -27
    let L = (dx * dx + dy * dy).squareRoot()
    let u = P(dx / L, dy / L), n = P(-u.y, u.x)
    parts.accent = FT5D.poly([P(e.x + u.x * 9, e.y + u.y * 9),
                              P(e.x - u.x * 2.5 + n.x * 6.5, e.y - u.y * 2.5 + n.y * 6.5),
                              P(e.x - u.x * 2.5 - n.x * 6.5, e.y - u.y * 2.5 - n.y * 6.5)])
    parts.directional = false
    return parts
}()

// ── رؤوس العائلات الأخرى ──

/// الأمان: درع بإطار داخلي وثقب مفتاح ذهبي
nonisolated private let ft5dShield: FT5D.Parts = {
    let P = FT5D.pt
    var shield = Path()
    shield.move(to: P(20, 19))
    shield.addQuadCurve(to: P(50, 11), control: P(36, 18))
    shield.addQuadCurve(to: P(80, 19), control: P(64, 18))
    shield.addLine(to: P(80, 46))
    shield.addCurve(to: P(50, 90), control1: P(80, 69), control2: P(64, 82))
    shield.addCurve(to: P(20, 46), control1: P(36, 82), control2: P(20, 69))
    shield.closeSubpath()
    var parts = FT5D.Parts(box: CGRect(x: 14, y: 7, width: 72, height: 87))
    parts.line.addPath(shield)
    let inner = CGAffineTransform(translationX: 50, y: 50).scaledBy(x: 0.74, y: 0.74).translatedBy(x: -50, y: -50)
    parts.line.addPath(shield.applying(inner))
    parts.fill = shield
    var key = FT5D.arc(P(50, 41), 7.2, from: 128, to: 412, steps: 36)
    key.append(P(55, 63)); key.append(P(45, 63))
    parts.accent = FT5D.poly(key)
    parts.directional = false
    return parts
}()

/// الإعدادات: ترس بثمانية أسنان وحلقة داخلية ومحور ذهبي
nonisolated private let ft5dGear: FT5D.Parts = {
    let P = FT5D.pt
    let c = P(50, 50)
    var pts: [CGPoint] = []
    for i in 0..<8 {
        let a = Double(i) * 45
        pts += FT5D.arc(c, 30, from: a - 31, to: a - 13, steps: 4)
        pts += FT5D.arc(c, 39, from: a - 8, to: a + 8, steps: 3)
    }
    let gear = FT5D.poly(pts)
    var parts = FT5D.Parts(box: CGRect(x: 8, y: 8, width: 84, height: 84))
    parts.line.addPath(gear)
    parts.line.addPath(FT5D.circle(c, 14))
    parts.fill = gear
    parts.accent = FT5D.circle(c, 6.5)
    parts.directional = false
    return parts
}()

/// الحِداد: هلال ونجمة — رمادي/فضّي ساكن
nonisolated private let ft5dCrescent: FT5D.Parts = {
    let P = FT5D.pt
    let o1 = P(46, 52), r1: CGFloat = 32, o2 = P(60, 42), r2: CGFloat = 26.5
    let dx = o2.x - o1.x, dy = o2.y - o1.y, d = (dx * dx + dy * dy).squareRoot()
    let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d), h = (r1 * r1 - a * a).squareRoot()
    let m = P(o1.x + a * dx / d, o1.y + a * dy / d)
    let p1 = P(m.x - h * dy / d, m.y + h * dx / d), p2 = P(m.x + h * dy / d, m.y - h * dx / d)
    func ang(_ o: CGPoint, _ p: CGPoint) -> Double { Double(atan2(p.y - o.y, p.x - o.x)) * 180 / .pi }
    var a1 = ang(o1, p1), a2 = ang(o1, p2)
    if a2 < a1 { a2 += 360 }
    var outer = FT5D.arc(o1, r1, from: a1, to: a2, steps: 48)
    // القوس الطويل يمرّ بعيداً عن الدائرة الثانية
    let mid = outer[outer.count / 2]
    if hypot(mid.x - o2.x, mid.y - o2.y) < r2 { outer = FT5D.arc(o1, r1, from: a1, to: a2 - 360, steps: 48) }
    var b1 = ang(o2, outer.last!), b2 = ang(o2, outer.first!)
    var inner = FT5D.arc(o2, r2, from: b1, to: b2, steps: 40)
    let im = inner[inner.count / 2]
    if hypot(im.x - o1.x, im.y - o1.y) > r1 {
        if b2 < b1 { b2 += 360 } else { b1 += 360 }
        inner = FT5D.arc(o2, r2, from: b1, to: b2, steps: 40)
    }
    let crescent = FT5D.poly(outer + inner.dropFirst())
    var parts = FT5D.Parts(box: CGRect(x: 10, y: 14, width: 80, height: 74))
    parts.line = crescent
    parts.fill = crescent
    parts.accent = FT5D.star(P(75, 30), outer: 8.5, inner: 3.6, points: 5)
    parts.directional = false
    return parts
}()

/// الجرس (الإشعارات والتذكير): جسم بحافة متّسعة وحلقة، ولسان ذهبي
nonisolated private let ft5dBell: FT5D.Parts = {
    let P = FT5D.pt
    var bell = Path()
    bell.move(to: P(50, 18))
    bell.addCurve(to: P(31, 39), control1: P(39, 18), control2: P(31, 27))
    bell.addLine(to: P(31, 57))
    bell.addQuadCurve(to: P(21, 69), control: P(30, 64))
    bell.addLine(to: P(79, 69))
    bell.addQuadCurve(to: P(69, 57), control: P(70, 64))
    bell.addLine(to: P(69, 39))
    bell.addCurve(to: P(50, 18), control1: P(69, 27), control2: P(61, 18))
    bell.closeSubpath()
    var parts = FT5D.Parts(box: CGRect(x: 14, y: 6, width: 72, height: 82))
    parts.line.addPath(bell)
    parts.line.addPath(FT5D.circle(P(50, 13.5), 4.5))
    parts.fill = bell
    parts.accent = FT5D.circle(P(50, 77.5), 6)
    parts.directional = false
    return parts
}()

/// الساعة الرملية (الانتظار): لوحان وعمودان وزجاجتان، رمل ذهبي، وخيط رمل (طبقة الحركة الهادئة)
nonisolated private let ft5dHourglass: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 16, y: 7, width: 68, height: 86))
    let top = FT5D.rr(21, 11, 58, 8, 3), bottom = FT5D.rr(21, 81, 58, 8, 3)
    parts.line.addPath(top)
    parts.line.addPath(bottom)
    parts.line.move(to: P(26.5, 19)); parts.line.addLine(to: P(26.5, 81))
    parts.line.move(to: P(73.5, 19)); parts.line.addLine(to: P(73.5, 81))
    var glass = Path()
    glass.move(to: P(33, 19))
    glass.addCurve(to: P(47.5, 47.5), control1: P(33, 36), control2: P(45, 41))
    glass.addLine(to: P(47.5, 52.5))
    glass.addCurve(to: P(33, 81), control1: P(45, 59), control2: P(33, 64))
    glass.addLine(to: P(67, 81))
    glass.addCurve(to: P(52.5, 52.5), control1: P(67, 64), control2: P(55, 59))
    glass.addLine(to: P(52.5, 47.5))
    glass.addCurve(to: P(67, 19), control1: P(55, 41), control2: P(67, 36))
    glass.closeSubpath()
    parts.line.addPath(glass)
    parts.fill.addPath(glass)
    parts.fill.addPath(top)
    parts.fill.addPath(bottom)
    parts.accent = FT5D.poly([P(37.5, 34), P(62.5, 34), P(51.2, 45.5), P(48.8, 45.5)])
    var mound = Path()
    mound.move(to: P(35.5, 79.5))
    mound.addQuadCurve(to: P(64.5, 79.5), control: P(50, 61))
    mound.closeSubpath()
    parts.accent.addPath(mound)
    parts.extra.move(to: P(50, 51)); parts.extra.addLine(to: P(50, 69))
    parts.directional = false
    return parts
}()

// ── اللحظات ──

nonisolated private let ft5dCheck: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 18, y: 12, width: 68, height: 66))
    parts.line.move(to: P(28, 50)); parts.line.addLine(to: P(44, 66)); parts.line.addLine(to: P(74, 33))
    parts.accent = FT5D.sparkle(P(78, 19), 7.5)
    return parts
}()

nonisolated private let ft5dPlane: FT5D.Parts = {
    let P = FT5D.pt
    let outline = FT5D.poly([P(88, 16), P(12, 46), P(36, 57), P(46, 82)])
    var parts = FT5D.Parts(box: CGRect(x: 4, y: 12, width: 88, height: 76))
    parts.line.addPath(outline)
    parts.line.move(to: P(36, 57)); parts.line.addLine(to: P(88, 16))
    parts.line.move(to: P(46, 82)); parts.line.addLine(to: P(52, 64))
    parts.fill = outline
    parts.accent = FT5D.circle(P(25, 70), 2.8)
    parts.accent.addPath(FT5D.circle(P(15.5, 77), 2.3))
    parts.accent.addPath(FT5D.circle(P(8, 83), 1.8))
    return parts
}()

nonisolated private let ft5dSeal: FT5D.Parts = {
    let P = FT5D.pt
    let c = P(50, 50)
    var seal = Path()
    let n = 14
    for i in 0...n {
        let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
        let p = P(c.x + 31 * CGFloat(cos(a)), c.y + 31 * CGFloat(sin(a)))
        if i == 0 { seal.move(to: p) } else {
            let am = (Double(i) - 0.5) / Double(n) * 2 * .pi - .pi / 2
            seal.addQuadCurve(to: p, control: P(c.x + 37 * CGFloat(cos(am)), c.y + 37 * CGFloat(sin(am))))
        }
    }
    seal.closeSubpath()
    var parts = FT5D.Parts(box: CGRect(x: 12, y: 12, width: 76, height: 76))
    parts.line.addPath(seal)
    parts.line.move(to: P(37, 51)); parts.line.addLine(to: P(46.5, 60.5)); parts.line.addLine(to: P(64, 41))
    parts.fill = seal
    parts.directional = false
    return parts
}()

/// عضو جديد: الغافة ولمعة ذهبية جديدة عند تاجها
nonisolated private let ft5dSapling: FT5D.Parts = {
    var parts = ft5dTree
    parts.box = CGRect(x: 4, y: 8, width: 94, height: 82)
    parts.accent = FT5D.sparkle(FT5D.pt(88, 17), 8.5)
    return parts
}()

// ── شارات الأخبار (مبسّطة لتُقرأ بقطر ٢٨ نقطة) ──

nonisolated private let ft5dBadgeNews: FT5D.Parts = {
    let P = FT5D.pt
    let sheet = FT5D.poly([P(24, 12), P(64, 12), P(78, 26), P(78, 88), P(24, 88)])
    var parts = FT5D.Parts(box: CGRect(x: 14, y: 6, width: 74, height: 88))
    parts.line.addPath(sheet)
    parts.line.move(to: P(64, 12)); parts.line.addLine(to: P(64, 26)); parts.line.addLine(to: P(78, 26))
    parts.line.move(to: P(36, 54)); parts.line.addLine(to: P(66, 54))
    parts.line.move(to: P(44, 70)); parts.line.addLine(to: P(66, 70))
    parts.fill = sheet
    parts.accent = FT5D.rr(34, 33, 32, 8, 4)
    return parts
}()

nonisolated private let ft5dBadgeAnnounce: FT5D.Parts = {
    let P = FT5D.pt
    let cone = FT5D.poly([P(28, 38), P(70, 17), P(70, 83), P(28, 62)])
    var parts = FT5D.Parts(box: CGRect(x: 6, y: 10, width: 88, height: 82))
    parts.line.addPath(cone)
    parts.line.move(to: P(36, 66)); parts.line.addLine(to: P(40, 86)); parts.line.addLine(to: P(49, 86)); parts.line.addLine(to: P(47, 70))
    parts.fill = cone
    parts.mark.move(to: P(81, 36)); parts.mark.addQuadCurve(to: P(81, 64), control: P(91, 50))
    parts.accent = FT5D.rr(12, 38, 16, 24, 4)
    return parts
}()

nonisolated private let ft5dBadgeCongrats: FT5D.Parts = {
    let P = FT5D.pt
    let big = FT5D.sparkle(P(42, 56), 36, pinch: 0.2)
    var parts = FT5D.Parts(box: CGRect(x: 2, y: 4, width: 94, height: 92))
    parts.line = big
    parts.fill = big
    parts.accent = FT5D.sparkle(P(80, 21), 13, pinch: 0.2)
    return parts
}()

nonisolated private let ft5dBadgeWedding: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 12, y: 18, width: 76, height: 68))
    parts.line.addPath(FT5D.circle(P(38, 61), 21))
    parts.line.addPath(FT5D.circle(P(62, 61), 21))
    parts.fill.addPath(FT5D.circle(P(38, 61), 21))
    parts.fill.addPath(FT5D.circle(P(62, 61), 21))
    parts.accent = FT5D.poly([P(53, 30), P(57.5, 23), P(66.5, 23), P(71, 30), P(62, 40.5)])
    parts.directional = false
    return parts
}()

nonisolated private let ft5dBadgeBirth: FT5D.Parts = {
    let P = FT5D.pt
    var bowl = Path()
    bowl.move(to: P(16, 50)); bowl.addLine(to: P(84, 50))
    bowl.addQuadCurve(to: P(62, 73), control: P(83, 71))
    bowl.addLine(to: P(38, 73))
    bowl.addQuadCurve(to: P(16, 50), control: P(17, 71))
    bowl.closeSubpath()
    var parts = FT5D.Parts(box: CGRect(x: 10, y: 12, width: 90, height: 84))
    parts.line.addPath(bowl)
    parts.line.move(to: P(84, 50)); parts.line.addLine(to: P(91, 31)); parts.line.addLine(to: P(97, 31))
    parts.line.addPath(FT5D.circle(P(34, 85), 7))
    parts.line.addPath(FT5D.circle(P(66, 85), 7))
    parts.fill = bowl
    var hood = Path()
    hood.move(to: P(19, 46)); hood.addQuadCurve(to: P(50, 16), control: P(19, 16))
    hood.addLine(to: P(50, 46)); hood.closeSubpath()
    parts.accent = hood
    return parts
}()

nonisolated private let ft5dBadgeVote: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 10, y: 8, width: 80, height: 84))
    let box = FT5D.rr(16, 48, 68, 38, 4)
    parts.line.addPath(box)
    parts.line.move(to: P(35, 48)); parts.line.addLine(to: P(35, 14)); parts.line.addLine(to: P(65, 14)); parts.line.addLine(to: P(65, 48))
    parts.line.move(to: P(40, 68)); parts.line.addLine(to: P(60, 68))
    parts.fill.addPath(FT5D.poly(FT5D.rectPts(16, 48, 68, 38)))
    parts.fill.addPath(FT5D.poly(FT5D.rectPts(35, 14, 30, 34)))
    parts.mark.move(to: P(42, 31)); parts.mark.addLine(to: P(48, 37)); parts.mark.addLine(to: P(58, 24))
    parts.directional = false
    return parts
}()

nonisolated private let ft5dBadgeInvite: FT5D.Parts = {
    let P = FT5D.pt
    var parts = FT5D.Parts(box: CGRect(x: 10, y: 14, width: 80, height: 78))
    let env = FT5D.rectPts(16, 47, 68, 40)
    let card = FT5D.rectPts(28, 26, 44, 36)
    let flap = [P(16, 47), P(50, 23), P(84, 47)]
    parts.line.addPath(FT5D.outside(flap, closed: false, of: card))
    parts.line.addPath(FT5D.outside(card, closed: true, of: env))
    parts.line.addPath(FT5D.rr(16, 47, 68, 40, 4))
    parts.line.move(to: P(17, 48)); parts.line.addLine(to: P(50, 70)); parts.line.addLine(to: P(83, 48))
    parts.fill.addPath(FT5D.poly(env))
    parts.fill.addPath(FT5D.poly(card))
    parts.fill.addPath(FT5D.poly(flap))
    parts.accent = FT5D.poly([P(50, 31), P(55, 37), P(50, 43), P(45, 37)])
    parts.directional = false
    return parts
}()
