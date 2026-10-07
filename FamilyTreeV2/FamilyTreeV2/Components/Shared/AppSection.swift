import SwiftUI
import UIKit

/// لون كل قسم رئيسي في التطبيق — طلب المالك ٢٠٢٦-١٠-٠٤: «كل قسم بلونه».
/// الرئيسية · الشجرة · الديوانيات · حسابي · الإدارة. ألوان المعاني (الخطأ، التحذير، النجاح،
/// الأنثى، الذكور، الأدوار، أنواع الأخبار، الإعلان/المعلومة) لا تتغيّر.
///
/// اختيار المالك «البحرية المتقاربة» (طلبه «قريبة من بعض بتنسيق واحد»): درجات باردة متجاورة
/// (~٢٠° بينها) بنفس العمق — الرئيسية كحلي العلامة، الشجرة أخضر مزرق، الديوانيات بترولي، حسابي
/// كوبالت نيلي، الإدارة نيلي بنفسجي. (رُفضت بعيّنات حقيقية: «الهادئة التراثية» بخمسة ألوان متباعدة،
/// و«المطفأة»، و«الأجرأ».)
///
/// القاعدة: **إطار التطبيق يتبع التبويب، وألوان المعاني لا تتغيّر أبداً.**
///  • `MainTabView` يضع `.dsSection(قسم التبويب)` على محتوى كل تبويب (البيئة + `tint` بحبر القسم)،
///    ويحدّث `AppSection.current` (لما يُعرض في نافذة مستقلّة: الرسائل، مربّع التاريخ…).
///  • المكوّنات المشتركة تقرأ `@Environment(\.dsSection)`: كحلي `DS.Color.primary` ← حبر القسم،
///    و`DS.Color.actionNavy` ← تعبئة القسم (`Color.dsChrome(in:)` / `dsChromeFill(in:)`)،
///    وأزرار الإجراء `DSActionFill.style()` بتدرّج القسم. بلا قسم (الدخول، البداية): كحلي العلامة.
///  • لون له معنى يُمرَّر بتوكنه الثابت (`DS.Color.male`, `brand`, `brandFill`, `female`…) فلا يتبدّل.
///  • أقسام الرئيسية بلا تبويب (المكتبة، المشاريع، الأخبار، والتواصل ← الإدارة): جذر صفحاتها
///    ومربّعاتها `.dsSectionPage(قسمها)` — نفس البيئة، و`AppSection.current` قسمها ما دامت ظاهرة.
///  • كل درجة لون قسم تُقرأ من هنا فقط — لا ألوان أقسام مكتوبة في مكان آخر.
enum AppSection: Int, CaseIterable {
    case home, tree, diwaniyas, profile, admin
    /// أقسام الرئيسية التي لا تبويب لها (طلب المالك ٢٠٢٦-١٠-٠٥ «داخل المكتبة نفس الالوان و المشاريع
    /// بعد و تواصل بعد … وحتى الاخبار»): صفحاتها ومربّعاتها بلونها مثل التبويبات تماماً.
    /// بعد التبويبات دائماً — `MainTabView` يطابق أرقام التبويبات ٠–٤ بـ `AppSection(rawValue:)`.
    /// «التواصل» = رسائل الإدارة ← يستعمل `.admin` (نفس لون مربّعه `tileContact`)، بلا قسم خاص.
    case library, projects, news

    /// درجات القسم (فاتح، داكن): غامق ← أساسي ← فاتح للتدرّج، و«حبر» للأيقونات والنصوص
    /// (أفتح في الداكن)، و«تحكّم» لخلفية أزرار الرأس الزجاجية (بين الغامق والأساسي).
    fileprivate struct Tones {
        let deep: (String, String)
        let base: (String, String)
        let light: (String, String)
        let ink: (String, String)
        let control: (String, String)
    }

    /// النص الأبيض فوق التدرّج ≥ ٤٫٥:١ في الوضعين، والحبر الداكن ≥ ٤٫٥:١ على #1C1C1E.
    private var tones: Tones {
        switch self {
        case .home:      return Tones(deep: ("#244771", "#1E3856"), base: ("#3A6DA6", "#2A4E78"), light: ("#3E74B2", "#305988"), ink: ("#326297", "#91B5DE"), control: ("#315F94", "#284A71"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        case .tree:      return Tones(deep: ("#1F4F68", "#1B3E50"), base: ("#337799", "#25566E"), light: ("#377FA4", "#2A627D"), ink: ("#2C6C8C", "#90C5E0"), control: ("#2B6988", "#235168"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        case .diwaniyas: return Tones(deep: ("#224A6B", "#1D3A52"), base: ("#38709F", "#285172"), light: ("#3C78AA", "#2E5C82"), ink: ("#306591", "#91BBDE"), control: ("#2F638D", "#264C6C"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        case .profile:   return Tones(deep: ("#284173", "#223458"), base: ("#4264A9", "#2F487A"), light: ("#466BB5", "#36528B"), ink: ("#39599A", "#94ACDB"), control: ("#385797", "#2D4473"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        case .admin:     return Tones(deep: ("#2D3774", "#262D59"), base: ("#4956AB", "#353E7B"), light: ("#515FB5", "#3C478D"), ink: ("#404C9C", "#97A0D8"), control: ("#3E4B99", "#323B75"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        // نفس سلّم «الاعتدال» (OKLCH): الغامق والأساسي والحبر = درجات مربّعات الرئيسية المعتمدة،
        // والفاتح (النص الأبيض ١٢ نقطة ≥ ٤٫٥:١ فوقه) والتحكّم مشتقّان بنفس السلّم
        case .library:   return Tones(deep: ("#3B3276", "#312A5A"), base: ("#5E52AD", "#443B7D"), light: ("#695EB3", "#4D438E"), ink: ("#53479E", "#A29AD6"), control: ("#51469B", "#403776"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        case .projects:  return Tones(deep: ("#1C5164", "#183F4D"), base: ("#2F7893", "#21576A"), light: ("#32819E", "#266379"), ink: ("#286D86", "#8ECBE1"), control: ("#276B83", "#205264"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        case .news:      return Tones(deep: ("#244673", "#1F3858"), base: ("#3C6BAA", "#2B4D7A"), light: ("#4073B6", "#31588B"), ink: ("#34609B", "#91B2DE"), control: ("#325E97", "#294973"))   // البحري الخفيف (٢٠٢٦-١٠-٠٧)
        }
    }

    // MARK: - الألوان الجاهزة

    /// ألوان كل قسم مبنية مرة واحدة — نفس النسخة في كل مرة، فتصح مقارنتها بـ `==`
    /// (مثل `dsReadableGlyph`: تعبئة القسم ← حبره في الوضع الداكن).
    private struct Swatch {
        let deep: Color
        let fill: Color
        let light: Color
        let ink: Color
        let control: Color
        let gradient: LinearGradient
    }

    private static let swatches: [Swatch] = allCases.map { section in
        let t = section.tones
        func c(_ pair: (String, String)) -> Color { Color.adaptive(light: pair.0, dark: pair.1) }
        let deep = c(t.deep), base = c(t.base), light = c(t.light)
        return Swatch(deep: deep, fill: base, light: light, ink: c(t.ink), control: c(t.control),
                      // نفس بناء `DS.Color.gradientPrimary` بلون القسم
                      gradient: LinearGradient(colors: [deep, base, light],
                                               startPoint: .bottomTrailing, endPoint: .topLeading))
    }

    // ألوان الأقسام «البحرية المتقاربة» — دائمة بعد اعتماد «مجسّمات» اتجاهاً نهائياً (٢٠٢٦-١٠-٠٦)
    private var swatch: Swatch { Self.swatches[rawValue] }

    /// تدرّج رأس القسم — نفس بناء `DS.Color.gradientPrimary` بلون القسم
    var gradient: LinearGradient { swatch.gradient }
    /// أسطح بنص أبيض (أزرار، شارات، رأس المربّع)
    var fill: Color { swatch.fill }
    /// أيقونات ونصوص بلون القسم — أفتح في الوضع الداكن
    var ink: Color { swatch.ink }
    /// الطرف الغامق من التدرّج (ظلال التوهّج، طرف المربّعات الملوّنة)
    var deep: Color { swatch.deep }
    /// الطرف الفاتح من التدرّج — النص الأبيض فوقه ≥ ٤٫٥:١
    var light: Color { swatch.light }
    /// خلفية أزرار الرأس الدائرية (زجاج بلون الرأس)
    var control: Color { swatch.control }

    // MARK: - القسم الحالي

    /// القسم المعروض الآن — لما يُعرض في نافذة مستقلّة بلا بيئة (dsAlert، مربّع التاريخ، نعي
    /// الوفاة)، واحتياطاً للمربّعات إن لم تصلها البيئة.
    /// القراءة: آخر صفحة قسم مفتوحة في التبويب المختار (`dsSectionPage`: المكتبة، المشاريع،
    /// الأخبار، التواصل)، وإلا قسم التبويب. الكتابة (`MainTabView`): قسم التبويب المختار، وnil
    /// خارج التبويبات (الدخول، البداية).
    static var current: AppSection? {
        get { openPages.last(where: { $0.tab == tabSection })?.section ?? tabSection }
        set {
            tabSection = newValue
            // الخروج من التبويبات (تسجيل الخروج، الانتظار، التجميد): لا صفحة قسم معروضة
            if newValue == nil { openPages.removeAll() }
        }
    }

    /// قسم التبويب المختار (يكتبه `MainTabView` عبر `current`)
    private static var tabSection: AppSection?

    /// صفحات/مربّعات الأقسام المعروضة الآن، الأحدث آخراً — كل واحدة تزيل نفسها بمعرّفها عند
    /// اختفائها، فلا يهم ترتيب ظهور الصفحة واختفاء غيرها. `tab`: التبويب الذي فُتحت فيه (لو
    /// بقيت مفتوحة تحت تبويب آخر لا تلوّن غيره).
    private static var openPages: [(id: UUID, section: AppSection, tab: AppSection?)] = []

    fileprivate static func pageAppeared(_ id: UUID, _ section: AppSection) {
        openPages.removeAll { $0.id == id }
        openPages.append((id, section, tabSection))
    }

    fileprivate static func pageDisappeared(_ id: UUID) {
        openPages.removeAll { $0.id == id }
    }
}

// MARK: - رمز القسم ومجسّمه — مكان واحد (طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد»)

extension AppSection {
    /// رمز SF للقسم — شريط التبويبات، فصل الدليل، رأس الصفحة. الديوانيات «مجلس» (`sofa.fill`) في كل مكان
    /// (اختيار المالك ٢٠٢٦-١٠-٠٧؛ كانت `map.fill` في التبويب و`building.columns.fill` في المربّعات).
    var symbol: String {
        switch self {
        case .home:      return "house.fill"
        case .tree:      return "tree.fill"
        case .diwaniyas: return "sofa.fill"
        case .profile:   return "person.crop.circle.fill"
        case .admin:     return "gearshape.2.fill"
        case .library:   return "books.vertical.fill"
        case .projects:  return "briefcase.fill"
        case .news:      return "newspaper.fill"
        }
    }

    /// الرمز المفرّغ (تبويب غير مختار)
    var symbolOutline: String {
        switch self {
        case .home:      return "house"
        case .tree:      return "tree"
        case .diwaniyas: return "sofa"
        case .profile:   return "person.crop.circle"
        case .admin:     return "gearshape.2"
        case .library:   return "books.vertical"
        case .projects:  return "briefcase"
        case .news:      return "newspaper"
        }
    }

    /// رمز مجسّم القسم («مجسّمات») — رأس الصفحة الفرعية، الصفحة الفاضية، التحميل، قرص التنبيه:
    /// الرئيسية والأخبار صحيفة، الشجرة غافة، الديوانيات «مجلس»، حسابي بيادق، الإدارة ختم، المكتبة كتاب،
    /// المشاريع حقيبة
    var artIcon: String {
        switch self {
        case .home, .news: return "newspaper.fill"
        case .tree:        return "tree.fill"
        case .diwaniyas:   return "sofa.fill"
        case .profile:     return "person.2.fill"
        case .admin:       return "checkmark.shield.fill"
        case .library:     return "books.vertical.fill"
        case .projects:    return "briefcase.fill"
        }
    }
}

// MARK: - ألوان أقسام الرئيسية التي لا تبويب لها

extension AppSection {
    /// طلب المالك ٢٠٢٦-١٠-٠٤: «حتى أقسام الرئيسية غيّر ألوانها» — كل مربّع في الرئيسية من نفس
    /// عائلة اللوحة: ما يقود لتبويب يأخذ لون التبويب (الشجرة، الديوانيات، التواصل ← الإدارة)،
    /// والباقي (المكتبة، المشاريع، الأخبار) أقسام بلا تبويب (`.library` / `.projects` / `.news`) —
    /// سطح المربّع وغامقه وحبره هي نفس ألوان القسم (نفس النسخة)، فلا درجات مكرّرة.
    enum HomeTile: Int, CaseIterable {
        case library, projects, news

        /// قسم المربّع — صفحاته ومربّعاته بلونه (`dsSectionPage`)
        var section: AppSection {
            switch self {
            case .library:  return .library
            case .projects: return .projects
            case .news:     return .news
            }
        }

        /// (فاتح، داكن) `accent`: لون القسم كسطح مستقل في الداكن (`DS.Color.tileLibrary` /
        /// `tileProjects`، مثل شارات لوحة الإدارة) — النص الأبيض فوقه ≥ ٤٫٥:١ ورمزه مقروء.
        private var accentPair: (String, String) {
            switch self {
            case .library:  return ("#633C6F", "#895D97") // بنفسجي المكتبة
            case .projects: return ("#275B35", "#488055") // أخضر المشاريع
            case .news:     return ("#25566F", "#3F7897") // أزرق الأخبار
            }
        }

        private static let accents: [Color] = allCases.map {
            Color.adaptive(light: $0.accentPair.0, dark: $0.accentPair.1)
        }

        /// سطح مربّع الرئيسية (مع `deep` لطرف التدرّج) = تعبئة القسم
        var fill: Color { section.fill }
        var deep: Color { section.deep }
        /// لون القسم كسطح مستقل (`DS.Color.tileLibrary` / `tileProjects`)
        var accent: Color { Self.accents[rawValue] }
        /// أيقونات ونصوص بلون القسم = حبر القسم
        var ink: Color { section.ink }
    }
}

// MARK: - البيئة

private struct DSSectionKey: EnvironmentKey {
    static let defaultValue: AppSection? = nil
}

/// تدرّج أزرار الإجراء للقسم — يقرؤه `DSActionFill.style()` من البيئة عند الرسم (iOS 17+)
nonisolated private struct DSActionGradientKey: EnvironmentKey {
    static let defaultValue: LinearGradient? = nil
}

extension EnvironmentValues {
    /// قسم التبويب الذي تُعرض فيه هذه الواجهة — nil = كحلي العلامة (خارج التبويبات)
    var dsSection: AppSection? {
        get { self[DSSectionKey.self] }
        set { self[DSSectionKey.self] = newValue }
    }

    /// تدرّج أزرار الإجراء (يضعه `.dsSection`) — nil = غير محدّد
    nonisolated var dsActionGradient: LinearGradient? {
        get { self[DSActionGradientKey.self] }
        set { self[DSActionGradientKey.self] = newValue }
    }
}

private struct DSSectionModifier: ViewModifier {
    let section: AppSection?

    func body(content: Content) -> some View {
        if let section {
            content
                .environment(\.dsSection, section)
                .environment(\.dsActionGradient, section.gradient)
                .tint(section.ink)
        } else {
            content
                .environment(\.dsSection, nil)
                .environment(\.dsActionGradient, DS.Color.gradientPrimary)
        }
    }
}

/// صفحة/مربّع قسم بلا تبويب: يلوّن ما بداخله ويجعل `AppSection.current` قسمه ما دام ظاهراً
private struct DSSectionPageModifier: ViewModifier {
    let section: AppSection?
    /// معرّف ثابت لهذه الصفحة طوال عمرها
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .dsSection(section)
            .onAppear { if let section { AppSection.pageAppeared(id, section) } }
            .onDisappear { AppSection.pageDisappeared(id) }
    }
}

extension View {
    /// يلوّن ما بداخله بلون القسم: البيئة `dsSection` + تدرّج أزرار الإجراء + `tint` بحبر القسم.
    /// nil = كحلي العلامة (بلا تغيير للـ tint).
    func dsSection(_ section: AppSection?) -> some View {
        modifier(DSSectionModifier(section: section))
    }

    /// جذر صفحة أو مربّع لقسم بلا تبويب (المكتبة، المشاريع، الأخبار، التواصل ← `.admin`):
    /// مثل `.dsSection` + يجعل `AppSection.current` قسمه ما دام ظاهراً (للنوافذ المستقلّة: الرسائل،
    /// مربّع التاريخ…) ويرجع قسم التبويب عند إغلاقه. ما يُفتح منه (`dsCenterBox`/`dsTallBox`/
    /// أوراق) يرث القسم من البيئة. nil = لا تغيير للقسم الموروث.
    @ViewBuilder
    func dsSectionPage(_ section: AppSection?) -> some View {
        if let section {
            modifier(DSSectionPageModifier(section: section))
        } else {
            self
        }
    }

    /// نص شريط الحالة أبيض فوق الرؤوس الملوّنة في الوضعين (iOS 27+). كان «الشجرة» يظهر
    /// بوقت أسود في الفاتح وباقي التبويبات بأبيض — والأقدم يبقى على سلوك النظام.
    @ViewBuilder
    func dsLightStatusBar() -> some View {
        if #available(iOS 27.0, *) {
            self.toolbarColorScheme(.dark, for: .statusBar)
        } else {
            self
        }
    }
}

// MARK: - الألوان داخل القسم

extension Color {
    /// كحلي «إطار» التطبيق يتبع لون القسم، وكل لون آخر (معنى) كما هو:
    /// `DS.Color.primary` ← حبر القسم، و`DS.Color.actionNavy` ← تعبئة القسم. بلا قسم: كما هو.
    func dsChrome(in section: AppSection?) -> Color {
        guard let section else { return self }
        if self == DS.Color.primary { return section.ink }
        if self == DS.Color.actionNavy { return section.fill }
        return self
    }

    /// مثل `dsChrome(in:)` لأسطح عليها نص أبيض (رؤوس، أزرار، شارات ممتلئة):
    /// الكحليّان كلاهما ← تعبئة القسم (حبر الداكن فاتح فلا يُقرأ عليه الأبيض).
    func dsChromeFill(in section: AppSection?) -> Color {
        guard let section, self == DS.Color.primary || self == DS.Color.actionNavy else { return self }
        return section.fill
    }

    /// تعبئة القسم التي هي هذا اللون — nil إن لم يكن تعبئة قسم
    var dsSectionOfFill: AppSection? {
        AppSection.allCases.first { $0.fill == self }
    }

    /// حبر قسم من أقسام الرئيسية الإضافية إن كان هذا سطحه أو لونه — nil لغيرها
    var dsHomeTileInk: Color? {
        AppSection.HomeTile.allCases.first { $0.fill == self || $0.accent == self }?.ink
    }

    /// الطرف الثاني لتدرّج رأس بلون واحد (رأس المربّع، بطاقة رأس الصفحة) — لون مصمت بدل
    /// `opacity(0.72)` التي تفتّح الرأس فوق الخلفية البيضاء فينزل النص الأبيض الصغير عن ٤٫٥:١:
    /// ألوان الأقسام والكحلي ← درجتها «الفاتحة» المعتمدة، وغيرها يُفتَّح بقدر يبقي التباين ≥ ٤٫٥:١
    /// (وإن لم يحتمل التفتيح يُغمَّق قليلاً فيبقى تدرّج).
    var dsHeroLight: Color {
        if let section = dsSectionOfFill { return section.light }
        if self == DS.Color.actionNavy || self == DS.Color.brandFill { return DS.Color.brandLight }
        return Color(uiColor: dsHeroEndColor(UIColor(self)))
    }
}

/// لون ديناميكي: نفس اللون (حسب الوضع) مفتّحاً نحو الأبيض حتى ٢٨٪ ما دام النص الأبيض ≥ ٤٫٥:١
nonisolated private func dsHeroEndColor(_ base: UIColor) -> UIColor {
    UIColor { traits in
        let c = base.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return c }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func whiteContrast(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
            1.05 / (0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) + 0.05)
        }
        var t: CGFloat = 0.28
        while t >= 0.06 {
            let lr = r + (1 - r) * t, lg = g + (1 - g) * t, lb = b + (1 - b) * t
            if whiteContrast(lr, lg, lb) >= 4.5 { return UIColor(red: lr, green: lg, blue: lb, alpha: a) }
            t -= 0.02
        }
        return UIColor(red: r * 0.9, green: g * 0.9, blue: b * 0.9, alpha: a)
    }
}
