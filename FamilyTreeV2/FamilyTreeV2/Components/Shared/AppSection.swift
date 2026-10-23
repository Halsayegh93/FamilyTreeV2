import SwiftUI
import UIKit

/// لون كل قسم رئيسي في التطبيق — طلب المالك ٢٠٢٦-١٠-٠٤: «كل قسم بلونه».
/// الرئيسية · الشجرة · الديوانيات · حسابي · الإدارة. ألوان المعاني (الخطأ، التحذير، النجاح،
/// الأنثى، الذكور، الأدوار، أنواع الأخبار، الإعلان/المعلومة) لا تتغيّر.
///
/// الألوان: الهوية الموحدة من main (٢٠٢٦-١٠-١٧) — إطار كل الأقسام كحلي المصمم على band، ومربّعات
/// الرئيسية بعائلة الكحلي والذهبي (انظر `swatches` و`HomeTile`). البيئة والآلية أدناه كما هي.
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

    /// ألوان كل قسم مبنية مرة واحدة — نفس النسخة في كل مرة، فتصح مقارنتها بـ `==`
    /// (مثل `dsReadableGlyph`: تعبئة القسم ← حبره في الوضع الداكن).
    private struct Swatch {
        let deep: Color
        let fill: Color
        let light: Color
        let ink: Color
        let control: Color
        /// تعبئة أزرار الإجراء (لون واحد — الهوية بلا تدرّج)
        let gradient: LinearGradient
        /// خلفية رأس القسم (رأس التبويب، الصفحة الفرعية، بانر الشجرة)
        let header: LinearGradient
    }

    /// الهوية الموحدة (main «App identity» #78/#83، ٢٠٢٦-١٠-١٥/١٧ — نفس شكل main): إطار كل الأقسام بكحلي
    /// المصمم — الرؤوس على band (`DS.Color.gradientBand`)، الأزرار والأسطح ذات النص الأبيض `primaryFill`،
    /// الأيقونات والنصوص `primary`، بلون واحد بلا تدرّج. ألوان مربّعات الرئيسية والتصنيفات تبقى «عائلة الكحلي
    /// والذهبي» من main (`DS.Color.tile*` و`HomeTile` أدناه: أخضر، كحلي، عنّابي، ذهبي، بترولي) — لا تتبع هذا.
    /// (درجات «البحري الخفيف» لكل قسم قبل الدمج محفوظة في تاريخ الفرع wip/ios-2026-10-02.)
    ///
    /// استثناء (طلب المالك ٢٠٢٦-١٠-٢٢ «نفس لون مربّعها»): المشاريع والمكتبة تأخذ ألوان مربّعها في
    /// الرئيسية (`HomeTile` — مصدر واحد)، فيكون المربّع ورأس القسم وبطاقاته عائلة واحدة: الرأس بتدرّج
    /// المربّع (سطحه ← غامقه)، والأزرار والأسطح ذات النص الأبيض سطح المربّع (لون واحد)، والحبر حبر المربّع.
    private static let swatches: [Swatch] = allCases.map { section in
        if let tile = HomeTile.tile(for: section) {
            return Swatch(deep: tile.deep, fill: tile.fill, light: tile.fill,
                          ink: tile.ink, control: tile.deep,
                          gradient: LinearGradient(colors: [tile.fill, tile.fill],
                                                   startPoint: .bottomTrailing, endPoint: .topLeading),
                          header: LinearGradient(colors: [tile.fill, tile.deep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return Swatch(deep: DS.Color.bandFill, fill: DS.Color.primaryFill, light: DS.Color.primaryFill,
                      ink: DS.Color.primary, control: DS.Color.headerControlFill,
                      gradient: DS.Color.gradientPrimary, header: DS.Color.gradientBand)
    }

    private var swatch: Swatch { Self.swatches[rawValue] }

    /// تعبئة أزرار الإجراء للقسم — لون واحد (الهوية)
    var gradient: LinearGradient { swatch.gradient }
    /// خلفية رأس القسم — band (الهوية)
    var headerGradient: LinearGradient { swatch.header }
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
    /// وصف رأس القسم — ذهبي الهوية على band، وكريمي العلامة فوق رأس بلون المربّع (الذهبي لا يُقرأ على الذهبي)
    var headerSubtitle: Color {
        HomeTile.tile(for: self) == nil ? DS.Color.headerSubtitle : DS.Color.headerSubtitleOnTile
    }

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

        /// المربّع الذي يعطي قسمه ألوانه (المشاريع والمكتبة) — nil لغيرهما (الأخبار تبقى على الهوية)
        static func tile(for section: AppSection) -> HomeTile? {
            switch section {
            case .projects: return .projects
            case .library:  return .library
            default:        return nil
            }
        }

        /// قسم المربّع — صفحاته ومربّعاته بلونه (`dsSectionPage`)
        var section: AppSection {
            switch self {
            case .library:  return .library
            case .projects: return .projects
            case .news:     return .news
            }
        }

        /// ألوان المربّع من «عائلة الكحلي والذهبي» (main): سطح المربّع، وطرفه الغامق، وحبره للنص والأيقونات
        /// — المكتبة عنّابي (`DS.Color.tileLibrary`)، المشاريع ذهبي (`tileProjects`)، الأخبار كحلي المربّعات
        var fill: Color {
            switch self {
            case .library:  return DS.Color.tileLibrary
            case .projects: return DS.Color.tileProjects
            case .news:     return DS.Color.navyFill
            }
        }
        var deep: Color {
            switch self {
            case .library:  return DS.Color.tileLibraryDeep
            case .projects: return DS.Color.tileProjectsDeep
            case .news:     return DS.Color.navyDeep
            }
        }
        /// لون القسم كسطح مستقل (= سطح المربّع)
        var accent: Color { fill }
        /// أيقونات ونصوص بلون المربّع — مقروء في الوضعين
        var ink: Color {
            switch self {
            case .library:  return DS.Color.sadu
            case .projects: return DS.Color.accent
            case .news:     return DS.Color.primary
            }
        }
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
    /// بوقت أسود في الفاتح وباقي التبويبات بأبيض — والأقدم يبقى على سلوك النظام. «الهادئ»: سلوك النظام.
    @ViewBuilder
    func dsLightStatusBar() -> some View {
        if DS.Theme.isCalm {
            // «الهادئ»: الرأس فاتح — شريط الحالة يتبع النظام (داكن في الفاتح، فاتح في الداكن)
            self
        } else if #available(iOS 27.0, *) {
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
        // الهوية (main): الرؤوس والأزرار بلون واحد بلا تدرّج — الطرف الثاني = اللون نفسه
        // (`dsHeroEndColor` أدناه باقٍ لو رجع التدرّج)
        self
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

// MARK: - «الهادئ الفاتح» — تجربة المالك ٢٠٢٦-١٠-١٠ (مفتاح واحد، الافتراضي الشكل الحالي)
//
// طلب المالك «خنجرب شي جديد بالألوان والتنسيق، المربعات ونسوي جديد» — اختار «ب — الهادئ الفاتح» برأس
// «خفيف»: بدل التدرّج الغامق في الرؤوس، لون القسم خفيفاً (~١٣٪ فوق الخلفية الفاتحة، ١٨٪ من حبره فوق
// الداكنة) ونص داكن (فاتح في الداكن)؛ المجسّمات والأيقونات بلون القسم، وأزرار الإجراء ممتلئة بلونه كما هي،
// وألوان المعاني لا تتغيّر. الخلفية أبيض مكسور / أسود قريب.
// كل من يرسم رأساً أو مربّعاً يسأل التوكنات هنا — لا قيم في الشاشات:
//  • `DS.Theme.isCalm` المفتاح الوحيد — يُقرأ مرة عند التشغيل من `UserDefaults` بالمفتاح `tmpTheme`
//    (`-tmpTheme calm` عند التشغيل، أو `defaults write Hasan.FamilyTreeV2 tmpTheme calm`) في DEBUG والإصدار.
//  • خلفية الرأس: `DSHeaderBackground(section:)` (رأس التبويب، الصفحة الفرعية، بانر الشجرة)؛
//    لون أي رأس/مربّع: `AppSection.headerTint`، ولأي لون (معنى، رمادي المتوفى): `Color.dsCalmTint`.
//  • النص والأزرار فوق الرأس: `DS.Color.headerTitle` / `headerSubtitle` / `boxHeaderSubtitle` / `headerGlyph`
//    / `headerChipFill` / `headerChipStroke` / `headerControlCalm`؛ أيقونة الرأس: `AppSection.headerInk(for:)`.
//  • مربّعات الرئيسية: `DS.Color.tileTitle` / `tileTitleShadow` / `tileStroke` + `color.dsCalmTint`.
// التباين (محسوب للأقسام الثمانية + الرمادي + الأحمر): النص الأساسي ≥ ١٢٫٦:١ والوصف ≥ ٥٫٩:١ في الوضعين،
// وحبر القسم (الأيقونات) ≥ ٤٫٧:١.

extension DS {
    /// مظهر التطبيق — مفتاح التجربة الواحد (انظر أعلاه)
    enum Theme {
        /// «الهادئ الفاتح» — يُقرأ مرة واحدة عند التشغيل؛ الافتراضي false = الشكل الحالي
        static let isCalm: Bool = UserDefaults.standard.string(forKey: "tmpTheme") == "calm"

        /// نسبة لون القسم فوق الخلفية الفاتحة (لون القسم) والداكنة (حبره الفاتح)
        static let calmTintLight: CGFloat = 0.13
        static let calmTintDark: CGFloat = 0.18
        /// الخلفية في «الهادئ»: أبيض مكسور / أسود قريب (فاتح، داكن)
        static let calmBackgroundHex: (String, String) = ("#FAFAF8", "#0C0C0E")
        /// شفافية المجسّم المائل في طرف رأس المربّع — أخفّ فوق اللون الفاتح
        static let calmWatermarkOpacity: Double = 0.16
    }
}

extension DS.Color {
    /// وصف الرأس في «الهادئ» — ≥ ٥٫٩:١ فوق لون كل قسم الخفيف في الوضعين
    private static let calmHeaderSubtitle = SwiftUI.Color.adaptive(light: "#4E5464", dark: "#A3A9B8")

    /// عنوان الرأس (رأس التبويب، الصفحة الفرعية، المربّع): أبيض فوق التدرّج — «الهادئ» نص داكن
    static let headerTitle: SwiftUI.Color = DS.Theme.isCalm ? textPrimary : textOnPrimary
    /// وصف رأس التبويب/الصفحة الفرعية — الهوية (main): النص الثانوي على band ذهبي `accentLight`
    static let headerSubtitle: SwiftUI.Color = DS.Theme.isCalm ? calmHeaderSubtitle : accentLight
    /// وصف رأس القسم الملوّن بلون مربّعه (المشاريع، المكتبة): كريمي العلامة #F2EBDD — ≥ ٤٫٥:١ فوق
    /// الذهبي #806631 و٧٫٨:١ فوق العنّابي #693940. «الهادئ»: كما هو.
    static let headerSubtitleOnTile: SwiftUI.Color = DS.Theme.isCalm ? calmHeaderSubtitle : SwiftUI.Color(hex: "#F2EBDD")
    /// وصف رأس المربّع
    static let boxHeaderSubtitle: SwiftUI.Color = DS.Theme.isCalm ? calmHeaderSubtitle : SwiftUI.Color.white.opacity(0.86)
    /// رموز أزرار الرأس (رجوع، إغلاق، جرس، إعدادات…)
    static let headerGlyph: SwiftUI.Color = DS.Theme.isCalm ? textPrimary : textOnPrimary
    /// كبسولة/دائرة زجاجية فوق الرأس (عدد الأفراد، أيقونة الرأس)
    static let headerChipFill: SwiftUI.Color = DS.Theme.isCalm ? headerControlCalm : overlayIcon
    static let headerChipStroke: SwiftUI.Color = DS.Theme.isCalm ? cardBorder : overlayIconBorder
    /// دائرة أزرار الرأس في «الهادئ» — أبيض فوق اللون الخفيف (رمادي مرتفع في الداكن)
    static let headerControlCalm = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#2A2C31")

    /// اسم مربّع الرئيسية
    static let tileTitle: SwiftUI.Color = DS.Theme.isCalm ? textPrimary : SwiftUI.Color.white
    /// ظلّ الاسم (فوق التدرّج فقط)
    static let tileTitleShadow: SwiftUI.Color = DS.Theme.isCalm ? SwiftUI.Color.clear : SwiftUI.Color.black.opacity(0.35)
    /// إطار مربّع الرئيسية
    static let tileStroke: SwiftUI.Color = DS.Theme.isCalm ? cardBorder : overlayIcon
}

extension AppSection {
    /// لون القسم الخفيف (مصمت) — خلفية الرأس ومربّع الرئيسية في «الهادئ»: لون القسم ١٣٪ فوق الخلفية
    /// الفاتحة، وحبره ١٨٪ فوق الداكنة
    var headerTint: Color { Self.calmTints[rawValue] }

    private static let calmTints: [Color] = allCases.map { s in
        dsCalmTintColor(s.fill)
    }

    /// كحلي العلامة الخفيف — رأس بلا قسم (الدخول، البداية)
    static let brandHeaderTint: Color = dsCalmTintColor(DS.Color.brand)

    /// أيقونة رأس التبويب (الدائرة بجانب العنوان): بيضاء فوق التدرّج — «الهادئ» بحبر القسم
    static func headerInk(for section: AppSection?) -> Color {
        guard DS.Theme.isCalm else { return DS.Color.textOnPrimary }
        return section?.ink ?? DS.Color.brand
    }
}

extension Color {
    /// «الهادئ»: هذا اللون خفيفاً فوق الخلفية (لون مصمت) — رأس المربّع بلون قسمه أو بلون معناه
    /// (الأحمر، رمادي المتوفى…): ألوان الأقسام بدرجتها المعتمدة، والكحلي بكحلي العلامة، وغيرها بنفس النسبة
    var dsCalmTint: Color {
        if let section = dsSectionOfFill { return section.headerTint }
        if self == DS.Color.actionNavy || self == DS.Color.brandFill || self == DS.Color.primary {
            return AppSection.brandHeaderTint
        }
        return dsCalmTintColor(self)
    }
}

/// لون مصمت = اللون بنسبة «الهادئ» فوق خلفيته (حسب الوضع). في الداكن: اللون الغامق جداً يُفتَّح أولاً
/// (تعبئات الأزرار الغامقة) حتى يبقى الرأس مميّزاً عن الخلفية
private func dsCalmTintColor(_ color: Color) -> Color {
    let base = UIColor(color)
    let bg = UIColor(Color.adaptive(light: DS.Theme.calmBackgroundHex.0, dark: DS.Theme.calmBackgroundHex.1))
    let aLight = DS.Theme.calmTintLight, aDark = DS.Theme.calmTintDark
    return Color(uiColor: dsCalmMix(base, over: bg, light: aLight, dark: aDark))
}

nonisolated private func dsCalmMix(_ base: UIColor, over background: UIColor, light aLight: CGFloat, dark aDark: CGFloat) -> UIColor {
    UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var br: CGFloat = 0, bgG: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard base.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a),
              background.resolvedColor(with: traits).getRed(&br, green: &bgG, blue: &bb, alpha: &ba)
        else { return background.resolvedColor(with: traits) }
        if dark, 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.35 {
            // تعبئة غامقة في الداكن ← نحو الأبيض قبل الخلط
            r += (1 - r) * 0.45; g += (1 - g) * 0.45; b += (1 - b) * 0.45
        }
        let t = dark ? aDark : aLight
        return UIColor(red: br + (r - br) * t, green: bgG + (g - bgG) * t, blue: bb + (b - bb) * t, alpha: 1)
    }
}

/// خلفية رأس القسم الواحدة — رأس التبويب (`MainHeaderView`)، الصفحة الفرعية (`DSSubPageHeader`)، بانر الشجرة:
/// الأصلي تدرّج القسم (+ طبقة الرأس)، و«الهادئ» لون القسم الخفيف
struct DSHeaderBackground: View {
    /// nil = كحلي العلامة (خارج الأقسام)
    var section: AppSection?
    /// تدرّج صريح للأصلي (يتقدّم على تدرّج القسم)
    var gradient: LinearGradient? = nil
    /// طبقة الرأس البيضاء الخفيفة فوق التدرّج (الأصلي)
    var veil: Bool = true

    var body: some View {
        if DS.Theme.isCalm {
            section?.headerTint ?? AppSection.brandHeaderTint
        } else {
            ZStack {
                gradient ?? section?.headerGradient ?? DS.Color.gradientBand
                if veil { DS.Color.headerVeil }
            }
        }
    }
}
