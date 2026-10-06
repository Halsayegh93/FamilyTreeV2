import SwiftUI

// TMP-ART-TRIAL — مؤقت للمقارنة على الجهاز (طلب المالك ٢٠٢٦-١٠-٠٥ «تصميم ثالث بعينات» ثم «كمل على الاقسام كلها»):
// أربعة اتجاهات رسوم + الحالي، يبدّل المالك بينها من شريط في الرئيسية، وتتبعها كل أماكن الرسوم في التطبيق.
// بعد اختياره يُحذف هذا الملف والشريط وملفات الاتجاهات الأخرى. لا تحفظ (commit) وهو موجود.

enum ArtTrial: String, CaseIterable, Identifiable {
    case emblem, soft3d, glass, gold, sadu

    static let storageKey = "tmpArtTrial"
    static let libraryKey = "tmpArtLibraryVariant"
    static let projectsKey = "tmpArtProjectsVariant"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .emblem: return "الحالي"
        case .soft3d: return "مجسّمات"
        case .glass: return "زجاج"
        case .gold: return "ذهبي"
        case .sadu: return "سدو"
        }
    }

    /// «الحالي» = تصميم ٢٨ سبتمبر: كحلي لكل الأقسام (تقرؤه AppSection — مخزّن حتى لا يُقرأ UserDefaults مع كل لون)
    static var legacyColors: Bool = (UserDefaults.standard.string(forKey: storageKey) ?? "emblem") == "emblem"

    static var current: ArtTrial {
        ArtTrial(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .emblem
    }
    static var libraryVariant: Int { UserDefaults.standard.integer(forKey: libraryKey) }
    static var projectsVariant: Int { UserDefaults.standard.integer(forKey: projectsKey) }

    /// رمز المربّع/الرأس ← اسم المكان المشترك بين الاتجاهات (nil = لا رسم)
    static func place(for icon: String) -> String? {
        let i = icon
        if i.hasPrefix("tree") { return "tree" }
        if i.hasPrefix("map") || i.hasPrefix("mappin") || i.hasPrefix("cup.and.saucer") || i.hasPrefix("tent")
            || i.hasPrefix("building.columns") { return "diwaniya" }
        if i.hasPrefix("books") || i.hasPrefix("book.fill") || i.hasPrefix("book.closed") { return "library" }
        if i.hasPrefix("storefront") || i.hasPrefix("briefcase") || i.hasPrefix("bag") { return "projects" }
        if i.hasPrefix("envelope") { return "contact" }
        return nil
    }
}

// MARK: - «الحالي» = الشكل القديم: خلفية فقط بلا رسوم (طلب المالك ٢٠٢٦-١٠-٠٥ «بدون اي شكل بس خلفية»)

@MainActor enum PlainArt {
    /// أيقونة نظام ساكنة داخل دائرة خفيفة — بديل الرسوم في الصفحات الفاضية والحالات
    static func icon(_ name: String, tint: Color, side: CGFloat, glyph: CGFloat) -> AnyView {
        AnyView(
            ZStack {
                Circle().fill(tint.opacity(0.12))
                Image(systemName: name)
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        )
    }
    static func momentIcon(_ name: String) -> String {
        switch name {
        case "sentForApproval": return "paperplane.fill"
        case "approved": return "checkmark.seal.fill"
        case "newMember": return "person.badge.plus"
        default: return "checkmark.circle.fill"
        }
    }
}

// MARK: - التوزيع على الاتجاهات (nil = يبقى البديل في مكانه)

@MainActor enum ArtDispatch {
    static func showsTileIcon(_ s: ArtTrial) -> Bool {
        switch s {
        case .emblem: return true
        case .soft3d: return FT5STrial.showsTileIcon
        case .glass: return FT5GTrial.showsTileIcon
        case .gold: return FT5DTrial.showsTileIcon
        case .sadu: return FT5UTrial.showsTileIcon
        }
    }
    static func underOverlay(_ s: ArtTrial) -> Bool {
        switch s {
        case .emblem: return true
        case .soft3d: return FT5STrial.tileArtUnderOverlay
        case .glass: return FT5GTrial.tileArtUnderOverlay
        case .gold: return FT5DTrial.tileArtUnderOverlay
        case .sadu: return FT5UTrial.tileArtUnderOverlay
        }
    }
    static func variantNames(_ s: ArtTrial) -> (library: [String], projects: [String]) {
        switch s {
        case .emblem: return ([], [])
        case .soft3d: return (FT5STrial.libraryVariantNames, FT5STrial.projectsVariantNames)
        case .glass: return (FT5GTrial.libraryVariantNames, FT5GTrial.projectsVariantNames)
        case .gold: return (FT5DTrial.libraryVariantNames, FT5DTrial.projectsVariantNames)
        case .sadu: return (FT5UTrial.libraryVariantNames, FT5UTrial.projectsVariantNames)
        }
    }
    static func tile(_ s: ArtTrial, place: String, badge: Bool, animateOnce: Bool) -> AnyView? {
        let v = place == "library" ? ArtTrial.libraryVariant : (place == "projects" ? ArtTrial.projectsVariant : 0)
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.tile(place, variant: v, badge: badge, animateOnce: animateOnce)
        case .glass: return FT5GTrial.tile(place, variant: v, badge: badge, animateOnce: animateOnce)
        case .gold: return FT5DTrial.tile(place, variant: v, badge: badge, animateOnce: animateOnce)
        case .sadu: return FT5UTrial.tile(place, variant: v, badge: badge, animateOnce: animateOnce)
        }
    }
    static func header(_ s: ArtTrial, icon raw: String, tint: Color, deep: Color) -> AnyView? {
        // رموز العضو العامة (تفاصيل العضو، الملف…) ← رسمة عائلة «الأعضاء» بدل رمز صغير عام
        let icon = (raw.hasPrefix("person.text.rectangle") || raw.hasPrefix("person.crop.circle")
                    || raw == "person.fill" || raw.hasPrefix("person.crop.square")) ? "person.2.fill" : raw
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.header(icon: icon, tint: tint, deep: deep)
        case .glass: return FT5GTrial.header(icon: icon, tint: tint, deep: deep)
        case .gold: return FT5DTrial.header(icon: icon, tint: tint, deep: deep)
        case .sadu: return FT5UTrial.header(icon: icon, tint: tint, deep: deep)
        }
    }
    /// أيقونة مربّع الرئيسية بدل الدائرة الزجاجية (المجسّم وحده بلا تكرار) — nil = الدائرة كما هي
    static func tileIcon(_ s: ArtTrial, place: String) -> AnyView? {
        let v = place == "library" ? ArtTrial.libraryVariant : (place == "projects" ? ArtTrial.projectsVariant : 0)
        switch s {
        case .soft3d: return FT5STrial.tileIcon(place, variant: v)
        default: return nil
        }
    }
    /// أيقونة الرأس بدل الدائرة الزجاجية (الاتجاه الذي يرسم المجسّم مكانها) — nil = الدائرة الزجاجية كما هي
    static func headerIcon(_ s: ArtTrial, icon: String, tint: Color) -> AnyView? {
        switch s {
        case .soft3d: return FT5STrial.headerIcon(icon: icon, tint: tint)
        default: return nil
        }
    }
    static func empty(_ s: ArtTrial, place: String?, icon: String, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return PlainArt.icon(icon, tint: tint, side: 96, glyph: 36)
        case .soft3d: return FT5STrial.empty(place: place, icon: icon, tint: tint)
        case .glass: return FT5GTrial.empty(place: place, icon: icon, tint: tint)
        case .gold: return FT5DTrial.empty(place: place, icon: icon, tint: tint)
        case .sadu: return FT5UTrial.empty(place: place, icon: icon, tint: tint)
        }
    }
    static func stateIcon(_ s: ArtTrial, icon: String, tint: Color, size: CGFloat) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.stateIcon(icon: icon, tint: tint, size: size)
        case .glass: return FT5GTrial.stateIcon(icon: icon, tint: tint, size: size)
        case .gold: return FT5DTrial.stateIcon(icon: icon, tint: tint, size: size)
        case .sadu: return FT5UTrial.stateIcon(icon: icon, tint: tint, size: size)
        }
    }
    static func treeLoading(_ s: ArtTrial) -> AnyView? {
        switch s {
        case .emblem: return AnyView(ProgressView().controlSize(.large))
        case .soft3d: return FT5STrial.treeLoading()
        case .glass: return FT5GTrial.treeLoading()
        case .gold: return FT5DTrial.treeLoading()
        case .sadu: return FT5UTrial.treeLoading()
        }
    }
    static func waiting(_ s: ArtTrial) -> AnyView? {
        switch s {
        case .emblem: return PlainArt.icon("hourglass", tint: AppSection.admin.ink, side: 96, glyph: 38)
        case .soft3d: return FT5STrial.waiting()
        case .glass: return FT5GTrial.waiting()
        case .gold: return FT5DTrial.waiting()
        case .sadu: return FT5UTrial.waiting()
        }
    }
    static func notificationsEmpty(_ s: ArtTrial) -> AnyView? {
        switch s {
        case .emblem: return PlainArt.icon("bell.slash", tint: AppSection.home.ink, side: 84, glyph: 32)
        case .soft3d: return FT5STrial.notificationsEmpty()
        case .glass: return FT5GTrial.notificationsEmpty()
        case .gold: return FT5DTrial.notificationsEmpty()
        case .sadu: return FT5UTrial.notificationsEmpty()
        }
    }
    static func loginBackdrop(_ s: ArtTrial, logoCenterY: CGFloat) -> AnyView? {
        switch s {
        case .emblem: return AnyView(EmptyView())
        case .soft3d: return FT5STrial.loginBackdrop(logoCenterY: logoCenterY)
        case .glass: return FT5GTrial.loginBackdrop(logoCenterY: logoCenterY)
        case .gold: return FT5DTrial.loginBackdrop(logoCenterY: logoCenterY)
        case .sadu: return FT5UTrial.loginBackdrop(logoCenterY: logoCenterY)
        }
    }
    static func newsBadge(_ s: ArtTrial, type: String, tint: Color, onColor: Bool) -> AnyView? {
        switch s {
        case .emblem:
            // أيقونة النوع كما كانت قبل الرسوم
            let name = NewsTypeHelper.icon(for: type)
            return AnyView(GeometryReader { g in
                Image(systemName: name)
                    .font(.system(size: min(g.size.width, g.size.height) * 0.46, weight: .bold))
                    .foregroundColor(onColor ? .white : tint)
                    .frame(width: g.size.width, height: g.size.height)
            }.accessibilityHidden(true))
        case .soft3d: return FT5STrial.newsBadge(type: type, tint: tint, onColor: onColor)
        case .glass: return FT5GTrial.newsBadge(type: type, tint: tint, onColor: onColor)
        case .gold: return FT5DTrial.newsBadge(type: type, tint: tint, onColor: onColor)
        case .sadu: return FT5UTrial.newsBadge(type: type, tint: tint, onColor: onColor)
        }
    }
    static func moment(_ s: ArtTrial, name: String, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return PlainArt.icon(PlainArt.momentIcon(name), tint: tint, side: 64, glyph: 28)
        case .soft3d: return FT5STrial.moment(name, tint: tint)
        case .glass: return FT5GTrial.moment(name, tint: tint)
        case .gold: return FT5DTrial.moment(name, tint: tint)
        case .sadu: return FT5UTrial.moment(name, tint: tint)
        }
    }
    static func greetingGlyph(_ s: ArtTrial, hour: Int, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.greetingGlyph(hour: hour, tint: tint)
        case .glass: return FT5GTrial.greetingGlyph(hour: hour, tint: tint)
        case .gold: return FT5DTrial.greetingGlyph(hour: hour, tint: tint)
        case .sadu: return FT5UTrial.greetingGlyph(hour: hour, tint: tint)
        }
    }
    static func greetingBackground(_ s: ArtTrial, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.greetingBackground(tint: tint)
        case .glass: return FT5GTrial.greetingBackground(tint: tint)
        case .gold: return FT5DTrial.greetingBackground(tint: tint)
        case .sadu: return FT5UTrial.greetingBackground(tint: tint)
        }
    }
    static func tabHeaderOrnament(_ s: ArtTrial, section: String, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.tabHeaderOrnament(section: section, tint: tint)
        case .glass: return FT5GTrial.tabHeaderOrnament(section: section, tint: tint)
        case .gold: return FT5DTrial.tabHeaderOrnament(section: section, tint: tint)
        case .sadu: return FT5UTrial.tabHeaderOrnament(section: section, tint: tint)
        }
    }
    static func pageHeroArt(_ s: ArtTrial, icon: String, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.pageHeroArt(icon: icon, tint: tint)
        case .glass: return FT5GTrial.pageHeroArt(icon: icon, tint: tint)
        case .gold: return FT5DTrial.pageHeroArt(icon: icon, tint: tint)
        case .sadu: return FT5UTrial.pageHeroArt(icon: icon, tint: tint)
        }
    }
    static func dashTileArt(_ s: ArtTrial, icon: String, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.dashTileArt(icon: icon, tint: tint)
        case .glass: return FT5GTrial.dashTileArt(icon: icon, tint: tint)
        case .gold: return FT5DTrial.dashTileArt(icon: icon, tint: tint)
        case .sadu: return FT5UTrial.dashTileArt(icon: icon, tint: tint)
        }
    }
    static func newsCardArt(_ s: ArtTrial, tint: Color) -> AnyView? {
        switch s {
        case .emblem: return nil
        case .soft3d: return FT5STrial.newsCardArt(tint: tint)
        case .glass: return FT5GTrial.newsCardArt(tint: tint)
        case .gold: return FT5DTrial.newsCardArt(tint: tint)
        case .sadu: return FT5UTrial.newsCardArt(tint: tint)
        }
    }
}

// MARK: - شريط التبديل المؤقت في الرئيسية

struct ArtTrialBar: View {
    @AppStorage(ArtTrial.storageKey) private var raw = ArtTrial.emblem.rawValue
    @AppStorage(ArtTrial.libraryKey) private var libraryVariant = 0
    @AppStorage(ArtTrial.projectsKey) private var projectsVariant = 0

    var body: some View {
        let style = ArtTrial(rawValue: raw) ?? .emblem
        let names = ArtDispatch.variantNames(style)
        VStack(alignment: .leading, spacing: 6) {
            Text("تجربة الرسوم (مؤقت) — تتبعها كل أقسام التطبيق")
                .font(DS.Font.plex(11, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
            chips(ArtTrial.allCases.map(\.title), selected: ArtTrial.allCases.firstIndex(of: style) ?? 0) {
                ArtTrial.legacyColors = ArtTrial.allCases[$0] == .emblem
                raw = ArtTrial.allCases[$0].rawValue
            }
            if !names.library.isEmpty {
                row("المكتبة", names.library, selected: libraryVariant) { libraryVariant = $0; FT5GTrial.libraryVariant = $0 }
                row("المشاريع", names.projects, selected: projectsVariant) { projectsVariant = $0; FT5GTrial.projectsVariant = $0 }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .onAppear { FT5GTrial.libraryVariant = libraryVariant; FT5GTrial.projectsVariant = projectsVariant }
    }

    private func row(_ label: String, _ items: [String], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(DS.Font.plex(11, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)
                .frame(width: 52, alignment: .leading)
            chips(items, selected: selected, pick: pick)
        }
    }

    private func chips(_ items: [String], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, title in
                let on = i == selected
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pick(i)
                } label: {
                    Text(title)
                        .font(DS.Font.plex(11.5, weight: .bold))
                        .foregroundColor(on ? .white : DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Capsule().fill(on ? DS.Color.primary : DS.Color.mutedBackground))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - أغلفة صغيرة تقرأ الاختيار وتتحدّث فوراً

/// رسم رأس المربّعات الوسطى بحسب الاتجاه
struct TrialHeaderArt: View {
    let icon: String
    let tint: Color
    @AppStorage(ArtTrial.storageKey) private var raw = ArtTrial.emblem.rawValue
    @AppStorage(ArtTrial.libraryKey) private var lv = 0
    @AppStorage(ArtTrial.projectsKey) private var pv = 0
    @Environment(\.dsSection) private var section

    var body: some View {
        let style = ArtTrial(rawValue: raw) ?? .emblem
        if let art = ArtDispatch.header(style, icon: icon, tint: tint, deep: (section ?? .home).deep) {
            art.id("h-\(raw)-\(lv)-\(pv)")
        } else {
            LegacyHeaderMark(icon: icon)   // «الحالي»: علامة الرأس المائية القديمة (٢٨ سبتمبر)
        }
    }
}

/// رمز الوقت في بطاقة الترحيب بحسب الاتجاه
struct TrialGreetingGlyph: View {
    let hour: Int
    let tint: Color
    @AppStorage(ArtTrial.storageKey) private var raw = ArtTrial.emblem.rawValue

    var body: some View {
        if let art = ArtDispatch.greetingGlyph(ArtTrial(rawValue: raw) ?? .emblem, hour: hour, tint: tint) {
            art.frame(width: 18, height: 18)
        } else {
            // «الحالي»: رمز النظام القديم
            Image(systemName: (4..<12).contains(hour) ? "sun.and.horizon.fill"
                              : ((12..<17).contains(hour) ? "sun.max.fill" : "moon.stars.fill"))
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
    }
}

/// غلاف عام: رسم الاتجاه إن وُجد، وإلا البديل (رسم «الحالي»)
struct TrialArt<Fallback: View>: View {
    let make: (ArtTrial) -> AnyView?
    @ViewBuilder let fallback: () -> Fallback
    @AppStorage(ArtTrial.storageKey) private var raw = ArtTrial.emblem.rawValue
    @AppStorage(ArtTrial.libraryKey) private var lv = 0
    @AppStorage(ArtTrial.projectsKey) private var pv = 0

    var body: some View {
        if let art = make(ArtTrial(rawValue: raw) ?? .emblem) {
            art.id("a-\(raw)-\(lv)-\(pv)")
        } else {
            fallback()
        }
    }
}

// MARK: - داخل المربّعات: إطار البطاقات وأيقوناتها بحسب الاتجاه (طلب المالك «مربعات المنتصف… داخل الأقسام»)

/// لمسة الاتجاه على بطاقات المربّعات (أقسام المربّع، صفوف الحقول) — خفيفة ومعتدلة
struct TrialCardSkin: ViewModifier {
    let radius: CGFloat
    @AppStorage(ArtTrial.storageKey) private var raw = ArtTrial.emblem.rawValue
    @Environment(\.dsSection) private var section
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let s = section ?? .home
        let dark = scheme == .dark
        switch ArtTrial(rawValue: raw) ?? .emblem {
        case .emblem:
            content
        case .soft3d:
            // طين ناعم: إضاءة علوية داخلية وظلّ لطيف بلون القسم
            content
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.12 : 0.9), .clear],
                                                           startPoint: .top, endPoint: .center), lineWidth: 1.5))
                .shadow(color: s.deep.opacity(dark ? 0.35 : 0.10), radius: 6, x: 0, y: 3)
        case .glass:
            // زجاج: حافة ضوء ساطعة وتعبئة خفيفة بلون القسم
            content
                .background(shape.fill(s.ink.opacity(dark ? 0.06 : 0.035)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 0.95),
                                                                    s.ink.opacity(0.22), .white.opacity(dark ? 0.12 : 0.5)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1.2))
        case .gold:
            // خط ذهبي رفيع
            content
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color(hex: "#E7C27A"), Color(hex: "#C9973F")],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                                .opacity(dark ? 0.55 : 0.75), lineWidth: 1))
        case .sadu:
            // حاشية سدو رفيعة على الطرف: شريط بلون القسم الغامق وعيون كريمية بقلب أحمر
            content
                .overlay(alignment: .leading) {
                    ZStack {
                        Rectangle().fill(s.deep)
                        VStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { _ in
                                ZStack {
                                    Rectangle().fill(Color(hex: "#F3E7CF")).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                                    Rectangle().fill(Color(hex: "#B3262E")).frame(width: 2, height: 2).rotationEffect(.degrees(45))
                                }
                            }
                        }
                    }
                    .frame(width: 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .clipShape(shape)
        }
    }
}

extension View {
    /// TMP-ART-TRIAL: لمسة الاتجاه على بطاقة داخل مربّع
    func trialCardSkin(radius: CGFloat) -> some View { modifier(TrialCardSkin(radius: radius)) }
}


/// علامة رأس المربّع كما كانت قبل أسبوع: رمز كبير شفاف يطفو ببطء + لمعة تمرّ مرة
struct LegacyHeaderMark: View {
    let icon: String
    @State private var markIn = false
    @State private var shine = false
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(systemName: icon)
                .font(.system(size: 96, weight: .bold))
                .foregroundColor(.white.opacity(0.09))
                .rotationEffect(.degrees(drift ? -10 : -16))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 18, y: drift ? 10 : 20)
                .opacity(markIn ? 1 : 0)
            LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 80)
                .rotationEffect(.degrees(18))
                .offset(x: shine ? 320 : -320)
        }
        .frame(height: 86)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { markIn = true; return }
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { markIn = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.34)) { shine = true }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// ألوان مربّعات الرئيسية قبل أسبوع (DesignSystem @ a021842c): الشجرة أخضر غابي، الديوانيات كحلي، المكتبة عنّابي،
/// المشاريع ذهبي، التواصل رمادي مزرق — (لون، طرف غامق)
enum LegacyTileColors {
    static func pair(for icon: String) -> (Color, Color)? {
        switch ArtTrial.place(for: icon) {
        case "tree": return (Color.adaptive(light: "#2E6B4F", dark: "#6FB394"), Color.adaptive(light: "#1F4F39", dark: "#3E8566"))
        case "diwaniya": return (Color.adaptive(light: "#1F4E79", dark: "#7FA8D6"), Color.adaptive(light: "#14365A", dark: "#2B5F90"))
        case "library": return (Color.adaptive(light: "#7A2E3A", dark: "#A8505E"), Color.adaptive(light: "#561F29", dark: "#7A2E3A"))
        case "projects": return (Color.adaptive(light: "#A07A2C", dark: "#D4B062"), Color.adaptive(light: "#7A5B1C", dark: "#A8842F"))
        case "contact": return (Color.adaptive(light: "#3D6670", dark: "#5E8A95"), Color.adaptive(light: "#284850", dark: "#3D6670"))
        default: return nil
        }
    }
}


/// أيقونة رأس المربّع/البطاقة: مجسّم الاتجاه بدل الدائرة الزجاجية (بلا تكرار الرمز مرتين) — وإلا الدائرة كما هي
struct TrialHeaderIcon<Glass: View>: View {
    let icon: String
    let tint: Color
    var side: CGFloat = 52
    @ViewBuilder let glass: () -> Glass
    @AppStorage(ArtTrial.storageKey) private var raw = ArtTrial.emblem.rawValue
    @AppStorage(ArtTrial.libraryKey) private var lv = 0
    @AppStorage(ArtTrial.projectsKey) private var pv = 0

    var body: some View {
        if let art = ArtDispatch.headerIcon(ArtTrial(rawValue: raw) ?? .emblem, icon: icon, tint: tint) {
            art.frame(width: side, height: side).id("hi-\(raw)-\(icon)-\(lv)-\(pv)")
        } else {
            glass()
        }
    }
}

/// مربّع الرئيسية بتكوين وسطي («مجسّمات»): المجسّم في الوسط على ضوء ناعم والاسم تحته بالوسط — بلا عدد
struct TrialCenteredTile: View {
    let art: AnyView
    let title: String
    let count: Int?
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                ZStack {
                    // ضوء ناعم خلف المجسّم — يعطيه عمقاً بلا زخرفة
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.20), .white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 36 * scale))
                        .frame(width: 76 * scale, height: 58 * scale)
                    art.frame(width: 48 * scale, height: 48 * scale)
                }
                .frame(height: 50 * scale)
                Text(title)
                    .font(DS.Font.scaled(13, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
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
