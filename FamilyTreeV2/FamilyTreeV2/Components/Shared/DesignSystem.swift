import SwiftUI

// MARK: - Design Tokens — المحمدعلي Family App
// الهوية الموحدة: ألوان دليل المصمم — كحلي #172536 + ذهبي #B89A5A + كريمي #F2EBDD | Light & Dark Mode
// القيم من نظام التصميم «المحمدعلي» (tokens.json) — نفس قيم الموقع. ألوان الأقسام الداعمة
// (أخضر غابي، عنّابي، ألوان الأخبار والأدوار) باقية كما هي.
// الدمج (٢٠٢٦-١٠-١٧): قيم الهوية من main، وتوكنات التطبيق المحلية (القسم، المعاني الثابتة، الحقول…)
// باقية بأسمائها وتأخذ قيم الهوية.
enum DS {

    // MARK: Colors
    enum Color {
        // Brand — كحلي المصمم (navy)، أفتح في الداكن ليبقى مقروءاً
        static let primary       = SwiftUI.Color.adaptive(light: "#172536", dark: "#7FA8D6") // navy
        /// كحلي الأزرار الممتلئة — لا يفتح في الداكن مثل primary (= `primaryFill`، نفس النسخة)
        static var actionNavy: SwiftUI.Color { primaryFill }
        // «كل قسم بلونه» (طلب المالك ٢٠٢٦-١٠-٠٤): `primary` و`actionNavy` في المكوّنات المشتركة
        // صارا «إطار» يتبع لون التبويب (AppSection). ما له معنى يُمرَّر بتوكن ثابت من هنا —
        // نفس الكحلي تماماً، لكنه نسخة مستقلّة فلا يتبدّل مع القسم:
        /// كحلي العلامة الثابت: الإعلان، المعلومة، نوع الخبر الافتراضي، الصورة الرمزية الافتراضية
        static let brand         = SwiftUI.Color.adaptive(light: "#172536", dark: "#7FA8D6")
        /// تعبئة كحلي العلامة الثابتة (رأس مربّع «إعلان»/«خبر») — مثل primaryFill ولا تتبع القسم
        static let brandFill     = SwiftUI.Color.adaptive(light: "#172536", dark: "#2B5F90")
        /// الطرف الثاني لرأس بلون الكحلي — الهوية بلون واحد بلا تدرّج (= تعبئة الكحلي)
        static let brandLight    = SwiftUI.Color.adaptive(light: "#172536", dark: "#2B5F90")
        /// الذكور/الأبناء وعقدة العضو في الشجرة — كحلي ثابت
        static let male          = SwiftUI.Color.adaptive(light: "#172536", dark: "#7FA8D6")
        /// تعبئة «ذكر» المختار — كحلي ثابت يُقرأ عليه النص الأبيض في الوضعين
        static let maleFill      = SwiftUI.Color.adaptive(light: "#172536", dark: "#2B5F90")
        /// الكلمة المتغيّرة في تعديل البيانات — كبسولة خضراء خفيفة جداً بلا إطار (طلب المالك)
        static let changedBg     = SwiftUI.Color.adaptive(light: "#EEF8F1", dark: "#1C3327")
        static let changedFg     = SwiftUI.Color.adaptive(light: "#3C9A63", dark: "#9FE3B8")
        /// عنوان الحقل في تعديل البيانات — أغمق من القيمة ليتميّز عنها (طلب المالك)
        static let fieldLabel    = SwiftUI.Color.adaptive(light: "#03070F", dark: "#FFFFFF")
        /// قيمة الحقل — أهدى قليلاً من العنوان
        static let fieldValue    = SwiftUI.Color.adaptive(light: "#414958", dark: "#C4CAD6")
        static let primaryDark   = SwiftUI.Color.adaptive(light: "#0F1824", dark: "#2B5F90") // كحلي أغمق
        static let primaryLight  = SwiftUI.Color.adaptive(light: "#5D6672", dark: "#A9C4E4") // كحلي فاتح
        // الثانوي = أخضر العائلة (نفس الأخضر بعمق الكحلي)
        static let secondary     = palm
        static let secondaryDark = SwiftUI.Color.adaptive(light: "#244B44", dark: "#65927D") // أخضر العائلة غامق
        static let secondaryLight = SwiftUI.Color.adaptive(light: "#759C8A", dark: "#BCD9CB") // أخضر العائلة فاتح
        static let accent        = SwiftUI.Color.adaptive(light: "#725D31", dark: "#B89A5A") // gold-text — ذهبي المصمم أغمق للنص (٦:١ على الأبيض)
        static let accentDark    = SwiftUI.Color.adaptive(light: "#5A4927", dark: "#9C8045") // ذهبي غامق
        static let accentLight   = SwiftUI.Color.adaptive(light: "#B89A5A", dark: "#B89A5A") // gold — ذهبي المصمم للخطوط والإطارات (نفس الموقع في الوضعين)

        // Supporting Accents — أسماء قديمة تشير لعائلة الكحلي والذهبي
        static let neonBlue     = SwiftUI.Color.adaptive(light: "#172536", dark: "#A9C4E4") // band
        static let neonPurple   = slate   // رصاصي العائلة
        static let neonCyan     = palm    // أخضر العائلة
        static let neonPink     = sadu    // عنّابي العائلة

        // MARK: عائلة الكحلي والذهبي — ألوان الأقسام
        // نفس ألوان التطبيق السابقة (أخضر، بترولي، عنّابي، رصاصي، ذهبي، كحلي) بعمق واحد ولمسة كحلي (#172536)
        // وذهبه (#B89A5A). لكل لون ثلاث درجات:
        //   • اللون نفسه (palm…) — للنص والأيقونات: يعدّي AA على الرملي والأبيض، وأفتح في الداكن.
        //   • Fill — تعبئة المربّعات والشارات بنص أبيض (٧:١ وأكثر، والذهبي ٤٫٨:١). ثابت بالوضعين.
        //   • Deep — الطرف الغامق لتدرّج المربّع.
        // الألوان للأقسام والتصنيفات بس — الحالات (مقبول/ينتظر/خطأ) تبقى success/warning/error.
        static let palm      = SwiftUI.Color.adaptive(light: "#2C614B", dark: "#9ACBB1") // أخضر العائلة — الشجرة والأعضاء
        static let palmFill  = SwiftUI.Color(hex: "#2C5846")
        static let palmDeep  = SwiftUI.Color(hex: "#10302B")
        static let sea       = SwiftUI.Color.adaptive(light: "#2C5D69", dark: "#9AC6D2") // بترولي — التواصل والرسائل
        static let seaFill   = SwiftUI.Color(hex: "#2C5460")
        static let seaDeep   = SwiftUI.Color(hex: "#112E3A")
        static let sadu      = SwiftUI.Color.adaptive(light: "#7B414A", dark: "#EAAAAF") // عنّابي العائلة — المكتبة والصور
        static let saduFill  = SwiftUI.Color(hex: "#693940")
        static let saduDeep  = SwiftUI.Color(hex: "#382028")
        static let slate     = SwiftUI.Color.adaptive(light: "#56606B", dark: "#B4BCC5") // رصاصي العائلة — المحايد والمعلّق
        static let slateFill = SwiftUI.Color(hex: "#4D5B67")
        static let slateDeep = SwiftUI.Color(hex: "#333F49")
        /// كحلي المربّعات: يتدرّج إلى كحلي المصمم
        static let navyFill  = SwiftUI.Color(hex: "#324561")
        static let navyDeep  = SwiftUI.Color(hex: "#17263C")
        /// ذهبي المربّعات: أغمق من ذهبي المصمم حتى يُقرأ الأبيض فوقه
        static let goldFill  = SwiftUI.Color(hex: "#806631")
        static let goldDeep  = SwiftUI.Color(hex: "#40351E")

        // Gradients
        // الهوية: الأزرار والهيدرات والبطاقات بلون واحد بدون تدرّج — يبقى الاسم للتوافق.
        // كحلي المصمم في الفاتح؛ وفي الداكن كحلي أفتح (#2B5F90) حتى يبان الزر والعنصر المختار فوق
        // البطاقات الداكنة (٢٫٥:١) — والنص الأبيض فوقه ٦٫٧:١. للنص والأيقونات الكحلية استخدم primary لا التدرّج.
        static let primaryFill = SwiftUI.Color.adaptive(light: "#172536", dark: "#2B5F90")
        static let gradientPrimary = LinearGradient(
            colors: [primaryFill, primaryFill],
            startPoint: .bottomTrailing, endPoint: .topLeading
        )
        // الأشرطة الكحلية الغامقة (band): الهيدرات ولوحات الترحيب — كحلي المصمم، وفي الداكن #1B2638 (نفس band في الموقع)
        static let bandFill = SwiftUI.Color.adaptive(light: "#172536", dark: "#1B2638")
        /// خلفية شاشة البداية: أبيض #FFFFFF في الفاتح (طلب المالك 17/10/2026 — كان كحلياً)، وأسود صافٍ في الداكن.
        /// من لون الأصول LaunchBackground نفسه الذي تستعمله شاشة الإقلاع في Info.plist، فلا يومض لون بينهما.
        static let splashBackground = SwiftUI.Color("LaunchBackground")
        static let gradientBand = LinearGradient(
            colors: [bandFill, bandFill],
            startPoint: .bottomTrailing, endPoint: .topLeading
        )
        static let gradientAccent = LinearGradient(
            colors: [accent, accent],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        // تدرّجات العائلة — من نفس اللون إلى درجته الغامقة فقط (بدون خلط ألوان)
        static let gradientSecondary = LinearGradient(colors: [palmFill, palmDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let gradientWarm  = LinearGradient(colors: [navyFill, navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let gradientCool  = LinearGradient(colors: [cardBackgroundSoft, cardBackgroundSoft], startPoint: .leading, endPoint: .trailing)
        static let gradientDark  = LinearGradient(colors: [bandFill, bandFill], startPoint: .top, endPoint: .bottom)
        static let gradientAuth  = LinearGradient(colors: [bandFill, bandFill], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let gradientFire  = LinearGradient(colors: [saduFill, saduDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let gradientOcean = LinearGradient(colors: [seaFill, seaDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let gradientNeon  = LinearGradient(colors: [goldFill, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let gradientRoyal = LinearGradient(colors: [navyFill, navyDeep], startPoint: .bottomTrailing, endPoint: .topLeading)
        static let gradientGold  = LinearGradient(colors: [goldFill, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

        // MARK: Feature Gradients / Tints — اختصارات لـ AppSection (المصدر الوحيد)؛ الهيدرات على band (الهوية)
        static var gradientHome: LinearGradient     { AppSection.home.headerGradient }
        static var gradientTree: LinearGradient     { AppSection.tree.headerGradient }
        static var gradientDiwaniya: LinearGradient { AppSection.diwaniyas.headerGradient }
        static var gradientProfile: LinearGradient  { AppSection.profile.headerGradient }
        static var gradientAdmin: LinearGradient    { AppSection.admin.headerGradient }

        static var tintHome: SwiftUI.Color     { AppSection.home.ink }
        static var tintTree: SwiftUI.Color     { AppSection.tree.ink }
        static var tintDiwaniya: SwiftUI.Color { AppSection.diwaniyas.ink }
        static var tintProfile: SwiftUI.Color  { AppSection.profile.ink }
        static var tintAdmin: SwiftUI.Color    { AppSection.admin.ink }

        // Surfaces — الكروت لازم تبان فوق الخلفية
        // الهوية: خلفية بيضاء صافية / سوداء صافية والكروت فوقها. «الهادئ الفاتح» (`DS.Theme.isCalm`، تجربة
        // مطفأة افتراضياً): أبيض مكسور / أسود قريب
        static let background       = DS.Theme.isCalm
            ? SwiftUI.Color.adaptive(light: DS.Theme.calmBackgroundHex.0, dark: DS.Theme.calmBackgroundHex.1)
            : SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#000000") // أبيض صافي / أسود صافي
        static let surface          = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#1C1F25") // surface
        static let surfaceElevated  = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#23272E")
        static let cardBackground   = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#1C1F25") // surface
        static let cardBackgroundSoft = SwiftUI.Color.adaptive(light: "#F2EBDD", dark: "#23272E") // sand-deep = كريمي المصمم
        static let cardBorder       = SwiftUI.Color.adaptive(light: "#DCCFB4", dark: "#343A44") // line
        static let cardBorderStrong = SwiftUI.Color.adaptive(light: "#8A7B60", dark: "#6B7380") // line-strong
        static let sectionFill      = SwiftUI.Color.gray.opacity(0.08)
        static let actionRowFill    = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#1C1F25")
        static let actionRowOverlay = SwiftUI.Color.adaptive(light: "#F2EBDD", dark: "#23272E")
        static let headerVeil       = SwiftUI.Color.white.opacity(0.08)
        static let headerBorder     = SwiftUI.Color.white.opacity(0.16)
        /// خلفية أزرار الهيدر — أفتح بدرجة من لون الهيدر الكحلي، فتبدو منه
        static let headerControlFill = SwiftUI.Color.adaptive(light: "#2A3A52", dark: "#26344B")

        // Text
        static let textPrimary   = SwiftUI.Color.adaptive(light: "#172536", dark: "#FFFFFF") // ink
        static let textSecondary = SwiftUI.Color.adaptive(light: "#4A5560", dark: "#C9CED5") // ink-muted
        /// ink-subtle في الهوية — نص ثالث (تلميحات، أسهم الصفوف، الحالات المعطّلة)؛ مقروء (AA) على الأبيض والأسود
        static let textTertiary  = SwiftUI.Color.adaptive(light: "#6B7280", dark: "#8A93A0") // ink-subtle
        static let textOnPrimary = SwiftUI.Color.white
        static let textGold      = accent // ذهبي
        /// أيقونة/نص فوق مربّع معبّأ بلون متكيّف (مثل palm أو primary): أبيض في الفاتح، وحبر غامق في الداكن
        /// لأن الألوان المتكيّفة تفتح في الداكن فيضيع الأبيض فوقها
        static let onTint        = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#14171C")

        /// نص/أيقونة فوق تعبئة بلون غير معروف مسبقاً (ألوان التصنيفات، ومنها ما يختاره المستخدم من
        /// CategoryPalette): أبيض أو حبر داكن #14171C — أيّهما أعلى تبايناً مع اللون كما يُعرض في الوضع
        /// الحالي (فاتح/داكن). للتعبئات الثابتة استخدم textOnPrimary، وللألوان المتكيّفة المعروفة onTint.
        static func readableText(on fill: SwiftUI.Color) -> SwiftUI.Color {
            let base = UIColor(fill)
            let ink = UIColor(red: 20.0 / 255.0, green: 23.0 / 255.0, blue: 28.0 / 255.0, alpha: 1)
            return SwiftUI.Color(uiColor: UIColor { traits in
                let resolved = base.resolvedColor(with: traits)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
                func linear(_ value: CGFloat) -> Double {
                    let c = Double(min(max(value, 0), 1))
                    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                }
                // اللمعان النسبي (WCAG)، ثم تباين الأبيض (لمعانه ١) والحبر (لمعانه ≈ ٠٫٠٠٨)
                let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
                let whiteContrast = 1.05 / (luminance + 0.05)
                let inkContrast = (luminance + 0.05) / 0.0585
                return whiteContrast >= inkContrast ? .white : ink
            })
        }

        /// النقطة الذهبية الصغيرة — اللمسة الواحدة بذهب المجسّمات (#F2C65E ← #D9A23E بحافة #B5832A)،
        /// مثل ثمرة الغافة على مجسّمات الرئيسية: «غير مقروء» في الإشعارات وعلامات الدليل (`DSGoldDot`)
        static let goldDotLight  = SwiftUI.Color(hex: "#F2C65E")
        static let goldDot       = SwiftUI.Color(hex: "#D9A23E")
        static let goldDotRim    = SwiftUI.Color.adaptive(light: "#B5832A", dark: "#F2C65E")

        // Semantic
        static let success = SwiftUI.Color.adaptive(light: "#216C4F", dark: "#4A9E7C") // success — يعدّي AA كنص
        static let warning = SwiftUI.Color.adaptive(light: "#875C0A", dark: "#F0B040") // warning — يعدّي AA كنص
        static let error   = SwiftUI.Color.adaptive(light: "#C0282A", dark: "#F47370") // danger — يعدّي AA كنص
        /// تعبئة الشارات والأزرار الحمراء ذات النص الأبيض — ثابتة في الوضعين (الأبيض فوقها ٥٫٩:١)
        static let errorFill = SwiftUI.Color.adaptive(light: "#C0282A", dark: "#C0282A")
        /// تعبئة الأزرار والشارات الخضراء/الكهرمانية ذات النص الأبيض — ثابتة في الوضعين (٦٫٤:١ و٥٫٩:١)
        static let successFill = SwiftUI.Color.adaptive(light: "#216C4F", dark: "#216C4F")
        static let warningFill = SwiftUI.Color.adaptive(light: "#875C0A", dark: "#875C0A")
        /// info — أزرق الإشعارات المحايدة وروابط المساعدة فيها (حالة، كنص وأيقونة). تحت نص أبيض استخدم primaryFill.
        static let info    = SwiftUI.Color.adaptive(light: "#1F6FA3", dark: "#5FA8DA")

        // Role Colors — كل دور بلونه السابق بعمق العائلة (الشارة: النص باللون فوق نفس اللون ١٢٪)
        static func role(_ roleColor: SwiftUI.Color) -> SwiftUI.Color { roleColor }
        static let ownerRole      = SwiftUI.Color.adaptive(light: "#594C7A", dark: "#C2B5E4") // بنفسجي العائلة
        static let adminRole      = SwiftUI.Color.adaptive(light: "#7E3F42", dark: "#EDA9A8") // وردي عنّابي
        static let monitorRole    = SwiftUI.Color.adaptive(light: "#286153", dark: "#97CBB9") // أخضر نعناعي
        static let supervisorRole = SwiftUI.Color.adaptive(light: "#6C4F20", dark: "#D9B88A") // ذهبي
        static let memberRole     = SwiftUI.Color.adaptive(light: "#32587C", dark: "#9DC2E7") // أزرق
        static let pendingRole    = slate   // رصاصي

        // News Type Colors — نفس ألوان البوستات: الزواج ذهبي مثل بوست الزواج، والمولود أزرق مثل بوست المولود
        static let newsWedding      = SwiftUI.Color.adaptive(light: "#944E62", dark: "#F7ACBD") // وردي
        static let newsBirth        = SwiftUI.Color.adaptive(light: "#316145", dark: "#9DCBAC") // أخضر
        static let newsDeath        = SwiftUI.Color.adaptive(light: "#53545D", dark: "#BDBDC5") // رمادي
        static let newsVote         = SwiftUI.Color.adaptive(light: "#415673", dark: "#ABBFDD") // رصاصي مزرق
        static let newsAnnouncement = brand                                                      // كحلي ثابت (لا يتبع القسم)
        static let newsCongrats     = accent
        static let newsReminder     = newsWedding
        static let newsInvitation   = SwiftUI.Color.adaptive(light: "#7C3E4C", dark: "#ECA8B2") // عنّابي

        // Status Colors
        /// المتوفّى — رصاصي العائلة (slate) للنص والأيقونات والحلقات؛ كان #A0A0A0 والأبيض فوقه ٢٫٦:١
        static let deceased         = slate
        /// تعبئة المتوفّى تحت نص/أيقونة بيضاء — slateFill الثابت (الأبيض فوقه ٧:١)
        static let deceasedFill     = slateFill
        /// شريط «متوفّى» على عقدة الشجرة — عنّابي بدرجة خفيفة (كان مكتوباً في TreeView وWomenClassicTreeView)
        static let deceasedStrip    = SwiftUI.Color(hex: "#A62B32")

        /// ألوان شعارات التواصل (معنى: هوية المنصّة — لا تتبع القسم). كانت مكرّرة في FamilyProjectsView وProjectDetailView
        enum Social {
            static let whatsapp  = SwiftUI.Color(hex: "#25D366")
            static let instagram = SwiftUI.Color(hex: "#E1306C")
            static let x         = SwiftUI.Color(hex: "#000000")
            static let snapchat  = SwiftUI.Color(hex: "#FFFC00")
            static let maps      = SwiftUI.Color(hex: "#EA4335")
            /// تدرّج إنستغرام الرسمي
            static let instagramGradient = LinearGradient(
                colors: [SwiftUI.Color(hex: "#F58529"), SwiftUI.Color(hex: "#DD2A7B"),
                         SwiftUI.Color(hex: "#8134AF"), SwiftUI.Color(hex: "#515BD4")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        static let currentLocation  = SwiftUI.Color.adaptive(light: "#2C623B", dark: "#9ACDA1") // أخضر
        static let likeAction       = newsWedding // وردي
        /// لون الإناث في شجرة النساء — وردي تراثي موحّد (بدل القيم المرمّزة يدوياً في WomenTreeView/WomenClassicTreeView)
        static let female           = SwiftUI.Color.adaptive(light: "#92526F", dark: "#F4B1CB") // وردي
        /// الأنثى المتوفّاة — بنفسجي خوخي مطفأ: لون مختلف عن وردي الحيّة لكنه من عائلته (طلب المالك)
        static let femaleDeceased   = SwiftUI.Color.adaptive(light: "#7A5578", dark: "#9D7A9B")
        /// حافة الأنثى المتوفّاة — بنفسجي داكن متناسق (وفي الداكن فاتح ليظهر)
        static let femaleDeceasedBorder = SwiftUI.Color.adaptive(light: "#3B2440", dark: "#D3BCD1")

        // Quick Access Grid Colors
        static let gridTree      = primary
        static let gridAlerts    = error
        static let gridDiwaniya  = secondary
        static let gridContact   = sea // بترولي — التواصل
        static let gridMessaging = sea

        // مربّعات الرئيسية — عائلة الكحلي والذهبي: كل قسم بلونه، ومن نفس العمق
        static let tileTree     = palmFill  // أخضر
        static let tileDiwaniya = navyFill  // كحلي
        static let tileLibrary  = saduFill  // عنّابي
        static let tileProjects = goldFill  // ذهبي
        static let tileContact  = seaFill   // بترولي

        // الطرف الغامق من تدرّج كل مربّع
        static let tileTreeDeep     = palmDeep
        static let tileDiwaniyaDeep = navyDeep
        static let tileLibraryDeep  = saduDeep
        static let tileProjectsDeep = goldDeep
        static let tileContactDeep  = seaDeep

        // Glass Effect Helpers — adaptive for light/dark mode
        static func glassBright(_ cs: ColorScheme) -> SwiftUI.Color {
            cs == .dark ? SwiftUI.Color.white.opacity(0.12) : SwiftUI.Color.white.opacity(0.8)
        }
        static func glassMedium(_ cs: ColorScheme) -> SwiftUI.Color {
            cs == .dark ? SwiftUI.Color.white.opacity(0.06) : SwiftUI.Color.white.opacity(0.4)
        }
        static func glassSubtle(_ cs: ColorScheme) -> SwiftUI.Color {
            cs == .dark ? SwiftUI.Color.white.opacity(0.04) : SwiftUI.Color.white.opacity(0.15)
        }
        static func glassBorder(_ cs: ColorScheme) -> SwiftUI.Color {
            cs == .dark ? SwiftUI.Color.white.opacity(0.10) : SwiftUI.Color.white.opacity(0.6)
        }
        static func glassBorderBright(_ cs: ColorScheme) -> SwiftUI.Color {
            cs == .dark ? SwiftUI.Color.white.opacity(0.15) : SwiftUI.Color.white.opacity(0.8)
        }
        static func glassDivider(_ cs: ColorScheme) -> SwiftUI.Color {
            cs == .dark ? SwiftUI.Color.white.opacity(0.08) : SwiftUI.Color.white.opacity(0.15)
        }

        // Overlay Colors — ألوان مستخدمة فوق الخلفيات الداكنة/المتدرجة
        /// أيقونة شفافة فوق تدرج (مثل header icons)
        static let overlayIcon = SwiftUI.Color.white.opacity(0.15)
        /// حدود أيقونة شفافة فوق تدرج
        static let overlayIconBorder = SwiftUI.Color.white.opacity(0.3)
        /// نص فوق تدرج (أقل سطوعاً من textOnPrimary)
        static let overlayText = SwiftUI.Color.white.opacity(0.85)
        /// نص/أيقونة فاتحة فوق خلفية داكنة (opacity 0.7)
        static let overlayTextMuted = SwiftUI.Color.white.opacity(0.7)
        /// نص/أيقونة فاتحة فوق خلفية داكنة (opacity 0.8)
        static let overlayTextBright = SwiftUI.Color.white.opacity(0.8)
        /// نص أبيض شبه كامل (opacity 0.92)
        static let overlayTextFull = SwiftUI.Color.white.opacity(0.92)
        /// خلفية شفافة فاتحة (opacity 0.12)
        static let overlayFill = SwiftUI.Color.white.opacity(0.12)
        /// خلفية شفافة فاتحة خفيفة (opacity 0.08)
        static let overlayFillSubtle = SwiftUI.Color.white.opacity(0.08)
        /// أيقونة نصف شفافة (opacity 0.5)
        static let overlayHalf = SwiftUI.Color.white.opacity(0.5)
        /// غلاف أسود شفاف (fullscreen overlays)
        static let overlayDark = SwiftUI.Color.black
        /// ظل خفيف (بديل عن Color.black.opacity)
        static let shadowSubtle = SwiftUI.Color.black.opacity(0.05)
        static let shadowLight = SwiftUI.Color.black.opacity(0.06)
        static let shadowMedium = SwiftUI.Color.black.opacity(0.08)
        static let shadowRegular = SwiftUI.Color.black.opacity(0.15)
        static let shadowMediumDark = SwiftUI.Color.black.opacity(0.2)
        static let shadowStrong = SwiftUI.Color.black.opacity(0.3)
        static let shadowHeavy = SwiftUI.Color.black.opacity(0.5)
        static let shadowOverlay = SwiftUI.Color.black.opacity(0.55)
        static let shadowDense = SwiftUI.Color.black.opacity(0.6)
        /// نص داكن مرئي فوق خلفيات فاتحة
        static let textDark = SwiftUI.Color.black.opacity(0.85)
        /// تدرج ثانوي شفاف (icon hierarchical rendering)
        static let hierarchicalSecondary = SwiftUI.Color.black.opacity(0.35)
        /// حالة غير نشطة
        static let inactive = SwiftUI.Color.gray
        /// حدود حالة غير نشطة
        static let inactiveBorder = SwiftUI.Color.gray.opacity(0.12)
        /// لون ثانوي خافت
        static let muted = SwiftUI.Color.adaptive(light: "#9E9E9E", dark: "#757575")
        /// خلفية ثانوية خافتة
        static let mutedBackground = SwiftUI.Color.gray.opacity(0.2)
    }

    // MARK: Typography — خطوط حديثة ونظيفة مع دعم Dynamic Type
    enum Font {
        /// الصوت الطباعي المميّز لهوية العائلة التراثية — أدفأ وأكثر تميّزاً من SF Pro.
        /// SF Rounded يدعم العربية (SF Arabic Rounded) فيظهر الدفء على اسم العائلة والعناوين
        /// العربية والإنجليزية معاً، بعكس الخط السيريفي (New York) الذي لا يملك محارف عربية.
        /// يُطبَّق على العناوين الكبرى فقط؛ ويبقى نص المحتوى على خط النظام (SF Pro) لأقصى وضوح.
        static let displayDesign: SwiftUI.Font.Design = .rounded

        // MARK: URW Geometric Arabic — خط الهوية (تجربة)
        /// أسماء PostScript للأوزان المضافة في Resources/Fonts
        enum Plex {
            static let regular  = AppTypeface.regular
            static let medium   = AppTypeface.medium
            static let semibold = AppTypeface.semibold
            static let bold     = AppTypeface.bold

            /// وزن الواجهة المطلوب ← ملف الخط (نفس `DS.Font.plexName`) — اسم main للتوافق
            static func name(for weight: SwiftUI.Font.Weight) -> String { DS.Font.plexName(weight) }
        }

        /// اسم ملف الوزن (Plex فيه أربعة أوزان: الأثقل من العريض يُرسم عريضاً)
        static func plexName(_ weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .black, .heavy, .bold: return Plex.bold
            case .semibold:             return Plex.semibold
            case .medium:               return Plex.medium
            default:                    return Plex.regular
            }
        }

        /// خط URW Geometric Arabic مع دعم Dynamic Type — يكبر ويصغر مع «حجم النص» في إعدادات الجهاز
        /// بنفس نسبة نمط Apple الأقرب لحجمه (`textStyle(for:)`)
        static func plex(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(plexName(weight), size: size, relativeTo: textStyle(for: size))
        }

        /// نفس الخط مقيّداً بنمط Apple معيّن (أدوار النص) — الحجم الأساسي ثم يتبع إعداد الجهاز
        static func plex(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular,
                         relativeTo style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            .custom(plexName(weight), size: size, relativeTo: style)
        }

        /// مطابقة خط الآيفون بالعين (طلب المالك ٢٠٢٦-١٠-٠٨ «يطابق شكل خط الآيفون»): خط الهوية أكبر بصرياً من
        /// خط النظام بنفس الرقم (قياس: الحروف أطول ١١٪ والسطر ١٤٪) — فكل دور نصّ يُرسم بحجمه × هذا المعامل.
        /// المعامل الواحد لحجم النص في التطبيق كله؛ مقاسات الرسم الثابتة (`TextRole(size:)`) مستثناة.
        static let opticalScale: CGFloat = 0.9

        // MARK: مقاسات Apple الافتراضية (حجم النص «كبير» — الافتراضي في الآيفون)
        // طلب المالك ٢٠٢٦-١٠-٠٨: «حجم الخط في التطبيق وجميع النصوص … على حجم الخط الافتراضي في الآيفون».
        // كل أدوار النص (`DS.TextRole`) مبنية على هذه الأحجام ومقيّدة بنمطها، فتتبع إعداد «حجم النص» في الجهاز.
        /// الحجم الافتراضي لنمط Apple (HIG — Dynamic Type، الإعداد «كبير»)
        static func appleSize(_ style: SwiftUI.Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle:  return 34
            case .title:       return 28
            case .title2:      return 22
            case .title3:      return 20
            case .headline:    return 17
            case .body:        return 17
            case .callout:     return 16
            case .subheadline: return 15
            case .footnote:    return 13
            case .caption:     return 12
            case .caption2:    return 11
            @unknown default:  return 17
            }
        }

        /// نمط Apple الأقرب لحجم بالنقاط (على مقاسات Apple الافتراضية أعلاه) — يقيّد الحجم الحرّ بـ Dynamic Type
        static func textStyle(for size: CGFloat) -> SwiftUI.Font.TextStyle {
            switch size {
            case ..<11.5: return .caption2     // ١١
            case ..<12.5: return .caption      // ١٢
            case ..<14:   return .footnote     // ١٣
            case ..<15.5: return .subheadline  // ١٥
            case ..<16.5: return .callout      // ١٦
            case ..<18.5: return .body         // ١٧
            case ..<21:   return .title3       // ٢٠
            case ..<25:   return .title2       // ٢٢
            case ..<31:   return .title        // ٢٨
            default:      return .largeTitle   // ٣٤
            }
        }

        // أنماط Apple بخط الهوية — بأحجامها الافتراضية. العناوين وحدها أكبر من ١٧ (طلب المالك ٢٠٢٦-١٠-٠٨):
        // كل نصّ غير العناوين (أرقام، أسماء كقيم، حقول) سقفه Body ١٧
        static var hero: SwiftUI.Font        { largeTitle }
        static var largeTitle: SwiftUI.Font  { plex(appleSize(.largeTitle) * opticalScale, weight: .bold, relativeTo: .largeTitle) }
        static var title1: SwiftUI.Font      { plex(appleSize(.title) * opticalScale, weight: .bold, relativeTo: .title) }
        static var title2: SwiftUI.Font      { plex(appleSize(.title2) * opticalScale, weight: .bold, relativeTo: .title2) }
        static var title3: SwiftUI.Font      { plex(appleSize(.title3) * opticalScale, weight: .semibold, relativeTo: .title3) }
        static var headline: SwiftUI.Font    { plex(appleSize(.headline) * opticalScale, weight: .semibold, relativeTo: .headline) }
        static var body: SwiftUI.Font        { role(.body) }
        static var bodyBold: SwiftUI.Font    { role(.bodySemibold) }
        static var callout: SwiftUI.Font     { role(.callout) }
        static var calloutBold: SwiftUI.Font { plex(DS.TextRole.callout.textSize, weight: .bold, relativeTo: .callout) }
        static var subheadline: SwiftUI.Font { role(.subtitle) }
        static var footnote: SwiftUI.Font    { role(.footnote) }
        static var caption1: SwiftUI.Font    { plex(appleSize(.caption) * opticalScale, relativeTo: .caption) }
        static var caption2: SwiftUI.Font    { plex(appleSize(.caption2) * opticalScale, relativeTo: .caption2) }

        /// خط مرن يدعم Dynamic Type — الحجم المطلوب نفسه مقيّداً بنمط Apple الأقرب (`textStyle(for:)`)؛
        /// الحجم الصحيح من مقاسات Apple (١١، ١٢، ١٣، ١٥، ١٦، ١٧، ٢٠، ٢٢، ٢٨، ٣٤) = النمط الافتراضي نفسه.
        /// للنص استعمل دوراً (`DS.TextRole`) — هذا للرموز والرسوم ذات المقاس الحرّ
        static func scaled(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
            // خط واحد في التطبيق كله (طلب المالك ٢٠٢٦-١٠-٠٧): خط الهوية بالحجم المطلوب نفسه —
            // الأرقام أحادية العرض فقط تبقى بخط النظام
            guard design == .monospaced else { return plex(size, weight: weight) }
            return SwiftUI.Font.system(textStyle(for: size), design: design).weight(weight)
        }

        /// الخط المميّز (display) بحجم مخصّص — لاسم العائلة والعناوين الكبيرة، مع دعم Dynamic Type.
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            scaled(size, weight: weight, design: displayDesign)
        }

        /// URW Geometric Arabic بحجم ثابت لا يتبع Dynamic Type — لنصوص لوحة الشجرة داخل عُقد بمقاس ثابت
        /// (بدل .system(size:) في تلك الأماكن) — من main (الهوية)
        static func plexFixed(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(plexName(weight), fixedSize: size)
        }

        /// نمط النص المقابل للحجم — يحدّد منحنى Dynamic Type لـ icon() (من main).
        /// الحدود بـ ..< حتى تأخذ الأحجام الكسرية (13.5 مثلاً) النمط الأقرب بدل largeTitle.
        static func scaledTextStyle(for size: CGFloat) -> SwiftUI.Font.TextStyle {
            switch size {
            case ..<11.5: return .caption2
            case ..<12.5: return .caption
            case ..<13.5: return .footnote
            case ..<15.5: return .subheadline
            case ..<16.5: return .callout
            case ..<17.5: return .body
            case ..<19.5: return .headline
            case ..<21.5: return .title3
            case ..<27.5: return .title2
            case ..<35.5: return .title
            default:      return .largeTitle
            }
        }

        /// خط رموز SF Symbols (الهوية، main) — خط النظام بنمط النص المقابل للحجم مع الوزن، ويكبر ويصغر مع
        /// Dynamic Type. لـ Image(systemName:) فقط؛ النص يبقى على scaled()/plex()/الأدوار. (الرموز داخل الأقراص
        /// بمقاس ثابت: `.dsGlyph(DS.Glyph.x)`.)
        static func icon(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            SwiftUI.Font.system(scaledTextStyle(for: size), design: .default).weight(weight)
        }
    }

    // MARK: Spacing
    enum Spacing {
        /// ٢ — بين عنوان ووصفه، وحشوة الشارات الرأسية (كان `spacing: 2` / `.padding(2)` في ٥٣ ملفاً)
        static let xxs:   CGFloat = 2
        static let xs:    CGFloat = 4
        /// ٦ — بين أيقونة صغيرة ونصّها، وبين عناصر الشبكات الضيقة (كان `spacing: 6` في ٤٥ ملفاً)
        static let xsm:   CGFloat = 6
        static let sm:    CGFloat = 8
        static let md:    CGFloat = 12
        static let lg:    CGFloat = 16
        static let xl:    CGFloat = 20
        static let xxl:   CGFloat = 24
        static let xxxl:  CGFloat = 32
        static let xxxxl: CGFloat = 40
    }

    // MARK: Radius — حواف حديثة ناعمة
    // MARK: Opacity
    enum Opacity {
        static let disabled: Double = 0.5
        static let divider: Double  = 0.3
        static let border: Double   = 0.12
        // «أسلوب واحد» (طلب المالك ٢٠٢٦-١٠-٠٧): شفافيات اللون المكرّرة في الشاشات — من هنا فقط
        /// تعبئة خفيفة جداً بلون (خلفية ملاحظة، صفّ مختار) — كانت ٠٫٠٦–٠٫٠٨
        static let tintFillSoft: Double   = 0.08
        /// تعبئة قرص/شارة/شريحة بلون (الدور الأشيع) — كانت ٠٫١٠–٠٫١٤
        static let tintFill: Double       = 0.12
        /// تعبئة أقوى (المختار، الداكن) — كانت ٠٫١٥–٠٫١٨
        static let tintFillStrong: Double = 0.18
        /// إطار البطاقة على السطح (`textTertiary`) — بطاقات الأقسام والحالات
        static let cardStroke: Double     = 0.10
        /// إطار صندوق الحقل (`textTertiary`)
        static let fieldStroke: Double    = 0.15
        /// إطار ملوّن خفيف (ملاحظة، شريحة) — كان ٠٫٢٢–٠٫٣٥
        static let tintStroke: Double     = 0.30
        /// إطار الخيار المختار بلونه
        static let selectedStroke: Double = 0.55
    }

    // MARK: Border
    enum Border {
        static let width: CGFloat     = 1.0
        static let widthBold: CGFloat = 1.5
    }

    enum Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let xxl:  CGFloat = 24
        static let xxxl: CGFloat = 28
        static let full: CGFloat = 999
    }

    // MARK: Icon
    enum Icon {
        static let size:   CGFloat = 46
        static let sizeSm: CGFloat = 38
        static let sizeLg: CGFloat = 58
        static let opacity: CGFloat = 0.15
        // أقراص الأيقونات (المجسّم/الرمز داخل قرص) — مقاس واحد لكل دور (طلب المالك ٢٠٢٦-١٠-٠٧)
        /// مساحة اللمس الدنيا (توصية أبل)
        static let tapTarget: CGFloat = 44
        /// زرّ الإضافة العائم (`DSFloatingButton` بلا نص) — دائرة ٥٦
        static let floatingButton: CGFloat = 56
        /// أيقونة عنوان قسم داخل المربّع (= `DSBox.sectionIcon`)
        static let inline: CGFloat = 16
        /// أيقونة عنوان قسم في صفحة / شارة صغيرة
        static let section: CGFloat = 22
        /// أيقونة صفّ/حقل في صفحة (داخل المربّع: `DSBox.fieldIcon`)
        static let row: CGFloat = 32
        /// أيقونة صفّ كبير (طلب، عضو)
        static let rowLarge: CGFloat = 36
        /// قرص بطاقة الحالة (فارغ صغير، خطأ داخل بطاقة)
        static let state: CGFloat = 52
        /// مجسّم الصفحة الفاضية
        static let emptyArt: CGFloat = 130
        /// مجسّم التحميل (يتنفّس)
        static let loaderArt: CGFloat = 96
        /// زوايا القرص المستدير في الصفحات، وداخل المربّعات
        static let discRadius: CGFloat = 9
        static let discRadiusSmall: CGFloat = 8
    }

    // MARK: Glyph — مقاسات رموز SF داخل الأقراص والأزرار (ثابتة لا تكبر مع Dynamic Type فلا تخرج من قرصها)
    // كانت ٢٨٢ `.system(size:)` بسبعة مقاسات (١١ ×٣٤، ١٣ ×٣٤، ١٠٫٥ ×٢٣، ١٤ ×٢٢…) — الآن من هنا
    enum Glyph {
        /// شارة حالة، عدّاد
        static let micro: CGFloat = 9.5
        /// قرص عنوان القسم (٢٢)، رمز داخل شريحة
        static let xs: CGFloat = 10.5
        /// رمز صفّ صغير، سهم الصف، ملاحظة
        static let sm: CGFloat = 12
        /// رمز زرّ ٤٠، قرص صفّ (٣٢–٣٦)
        static let md: CGFloat = 14
        /// رمز زرّ ٤٨
        static let lg: CGFloat = 16
        /// زرّ الرأس الملوّن (رجوع/إغلاق/إجراء)
        static let xl: CGFloat = 18
        /// قرص كبير
        static let xxl: CGFloat = 22

        static func font(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
    }

    // MARK: Card — بطاقة «مجسّمات» الواحدة (`.dsCard()` / `DSComposerSection` / `TrialCardSkin`)
    enum Card {
        /// زوايا كل البطاقات (= بطاقة قسم المربّع)
        static var radius: CGFloat { DSBox.sectionRadius }
        /// حشوة البطاقة (= بطاقة قسم المربّع)
        static var padding: CGFloat { DSBox.sectionPadding }
        static let strokeWidth: CGFloat = 1
        /// لمسة الطين: إضاءة علوية داخلية (فاتح/داكن) وعرضها
        static let highlightLight: Double = 0.9
        static let highlightDark: Double = 0.12
        /// اللمعة فوق سطح ملوّن (عليه نص أبيض) — أخفّ
        static let highlightOnFill: Double = 0.5
        static let highlightWidth: CGFloat = 1.5
        /// ظلّ داخلي سفلي خفيف بلون غامق القسم (عقد الشجرة وأزرارها — `DSClaySkin(glassBacked: false)`)
        static let innerShadeLight: Double = 0.08
        static let innerShadeDark: Double = 0.22
        /// ظلّ الطين بلون غامق القسم (فاتح/داكن)
        static let shadowLight: Double = 0.10
        static let shadowDark: Double = 0.35
        static let shadowRadius: CGFloat = 6
        static let shadowY: CGFloat = 3
        /// الشكل الذي يُلقي الظلّ تحت البطاقة/المربّع أصغر بنقطة — يبقى مخفياً تحت حافّتها المنعّمة (بلا خيط فاتح)
        static let shadowInset: CGFloat = 1
        /// مفتاح الظلال الواحد (فحص «اللاق» ٢٠٢٦-١٠-٠٧) لبطاقات «مجسّمات» (`DSClaySkin`/`.dsCard`) والمربّعات
        /// (`dsBoxChrome`): `false` = الظلّ كما اعتمده المالك (ظلّ «كل المحتوى» — كل أيقونة ونص داخل البطاقة يلقي ظلاً
        /// خفيفاً، ويُعاد حسابه خارج الشاشة مع كل إطار تمرير/حركة). `true` = ظلّ الشكل نفسه تحت البطاقة: يُرسم مرة
        /// (تركيب الشاشة أخفّ ~٢٫٣× في المربّعات والبطاقات) لكن تختفي الظلال الداخلية الخفيفة تحت الأيقونات والنصوص
        /// (فرق ≤ ٧٪ في الفاتح، شبه معدوم في الداكن). لا يُقلب إلا بموافقة المالك.
        static let shapeShadows = false
    }

    // MARK: Shadow — ظلال عصرية أنيقة
    enum Shadow {
        static let card     = ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        static let subtle   = ShadowStyle(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
        // ظلال «التوهّج» — بلمسة لون العلامة الحالية (أزرق/نيلي) بعد توحيدها مع الهوية
        static let glow     = ShadowStyle(color: SwiftUI.Color(hex: "#172536").opacity(0.16), radius: 14, x: 0, y: 4)
        static let glowAccent = ShadowStyle(color: SwiftUI.Color(hex: "#B89A5A").opacity(0.16), radius: 12, x: 0, y: 4)
        static let neon     = ShadowStyle(color: SwiftUI.Color(hex: "#172536").opacity(0.14), radius: 12, x: 0, y: 3)
        static let none     = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
    }

    struct ShadowStyle {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: Animation — أنيميشن حديثة وسلسة
    enum Anim {
        static let bouncy    = Animation.spring(response: 0.4, dampingFraction: 0.65, blendDuration: 0)
        static let snappy    = Animation.spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0)
        static let smooth    = Animation.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0)
        static let elastic   = Animation.spring(response: 0.45, dampingFraction: 0.55, blendDuration: 0)
        static let quick     = Animation.easeOut(duration: 0.18)
        static let medium    = Animation.easeInOut(duration: 0.32)

        /// يحترم "تقليل الحركة" (Reduce Motion): يُعيد الأنيميشن كما هو عند تفعيل الحركة،
        /// و`nil` (بلا حركة) عند تفعيله — لإيقاف الأنيميشن المتكرر/السبرنق مع احترام إعدادات الوصول.
        static func respectingMotion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    // MARK: Layout — تخطيط متجاوب حسب موديل الجهاز (العرض الحقيقي + size class)
    enum Layout {
        /// مقاييس متكيّفة تُشتق من عرض الشاشة الفعلي
        struct Metrics: Equatable {
            /// عدد أعمدة شبكة الوصول السريع
            let gridColumns: Int
            /// ارتفاع مربعات الوصول السريع
            let tileHeight: CGFloat
            /// المسافة بين عناصر الشبكة
            let gridSpacing: CGFloat
            /// مُضاعِف عام للعناصر الزخرفية والأيقونات (1.0 = الحجم القياسي)
            let scale: CGFloat
        }

        /// نقاط الكسر:
        /// - regular (iPad/أفقي) → 4 أعمدة
        /// - ≥430 (Pro Max/Plus) → مربعات أطول
        /// - 390–429 (الموديلات القياسية) → القياس المرجعي
        /// - 375–389 (mini/الأقدم) → أصغر قليلاً
        /// - <375 (SE الجيل الأول) → مدمج
        static func metrics(width: CGFloat, isRegularWidth: Bool) -> Metrics {
            if isRegularWidth {
                return Metrics(gridColumns: 4, tileHeight: 104, gridSpacing: Spacing.md, scale: 1.12)
            } else if width >= 430 {
                return Metrics(gridColumns: 2, tileHeight: 96, gridSpacing: Spacing.md, scale: 1.06)
            } else if width >= 390 {
                return Metrics(gridColumns: 2, tileHeight: 90, gridSpacing: Spacing.sm, scale: 1.0)
            } else if width >= 375 {
                return Metrics(gridColumns: 2, tileHeight: 86, gridSpacing: Spacing.sm, scale: 0.97)
            } else {
                return Metrics(gridColumns: 2, tileHeight: 78, gridSpacing: Spacing.xs, scale: 0.9)
            }
        }
    }
}

// MARK: - أدوار النص — «التعديل من مكان واحد» (طلب المالك ٢٠٢٦-١٠-٠٧)
//
// كل نص في التطبيق دوره واحد من هذا الجدول (خط URW Geometric Arabic + نمط Apple + وزن). تغيير سطر هنا يغيّر
// كل مكان بنفس الدور. كانت الأحجام تُقرَّر في كل شاشة (~١٠٤٠ موضعاً بثلاثين تركيبة).
// «حجم الخط الافتراضي في الآيفون» (طلب المالك ٢٠٢٦-١٠-٠٨): كل دور = نمط Apple بحجمه الافتراضي
// (`DS.Font.appleSize`) ومقيّد به (`relativeTo:`)، فيتبع «حجم النص» في إعدادات الجهاز — لا أحجام خاصة بالتطبيق.
//   • `.dsFont(.rowTitle)` — الحجم كما هو في كل مكان.
//   • `.dsFieldFont(.rowTitle)` — نفس الدور (كان أصغر داخل المربّعات؛ الآن `DSFieldFont.boxReduction` = ٠).
//   • `DS.Font.role(.rowTitle)` — قيمة `Font` لمن يحتاجها (Label، تركيب نصوص).
extension DS {
    struct TextRole: Hashable {
        let size: CGFloat
        let weight: SwiftUI.Font.Weight
        /// نمط Apple الذي يكبر معه الدور مع «حجم النص» في الجهاز
        let style: SwiftUI.Font.TextStyle
        /// دور نصّ (يُطابق خط الآيفون بالعين بـ `DS.Font.opticalScale`) — لا لمقاسات الرسم الثابتة
        let optical: Bool

        /// الحجم المرسوم فعلاً
        var textSize: CGFloat { optical ? size * DS.Font.opticalScale : size }

        /// دور نصّ = نمط Apple بحجمه الافتراضي + وزن
        init(_ style: SwiftUI.Font.TextStyle, weight: SwiftUI.Font.Weight = .regular) {
            self.size = DS.Font.appleSize(style)
            self.weight = weight
            self.style = style
            self.optical = true
        }

        /// مقاس رسم ثابت (عقد الشجرة، الحرف داخل صورة كبيرة، أرقام رمز التحقق) — يتبع النمط الأقرب لحجمه
        /// أو نمطاً محدّداً
        init(size: CGFloat, weight: SwiftUI.Font.Weight, style: SwiftUI.Font.TextStyle? = nil) {
            self.size = size
            self.weight = weight
            self.style = style ?? DS.Font.textStyle(for: size)
            self.optical = false
        }
    }
}

extension DS.TextRole {
    /// عنوان رأس الصفحة الفرعية / بطاقة رأس الصفحة — Title 3 (٢٠)
    static let pageTitle    = DS.TextRole(.title3, weight: .bold)
    /// عنوان الحالة الفارغة — Title 3 (٢٠)
    static let emptyTitle   = DS.TextRole(.title3, weight: .bold)
    /// رقم إحصاء (داخل الحلقة، صفّ الأرقام، «+N» فوق الصور) — نصّ غير عنوان: سقفه Headline (١٧ عريض)
    /// (طلب المالك ٢٠٢٦-١٠-٠٨ «لا نصّ أكبر من ١٧ إلا العناوين»؛ كان `emptyTitle` ٢٠)
    static let statValue    = DS.TextRole(.headline, weight: .bold)
    /// عنوان رأس المربّع — Headline (١٧)
    static let title        = DS.TextRole(.headline, weight: .bold)
    /// عنوان التنبيه والبطاقة — Headline (١٧)
    static let headline     = DS.TextRole(.headline, weight: .bold)
    /// نص عادي وقيمة الحقل — Body (١٧)
    static let body         = DS.TextRole(.body)
    /// عنوان الصفّ — Body (١٧) شبه عريض
    static let rowTitle     = DS.TextRole(.body, weight: .semibold)
    /// نص التنبيه والملاحظة — Callout (١٦)
    static let callout      = DS.TextRole(.callout)
    /// عنوان قسم في صفحة (`DSSectionTitle`) — Footnote (١٣)
    static let sectionTitle = DS.TextRole(.footnote, weight: .bold)
    /// وصف تحت عنوان / صفّ، ووصف رأس المربّع — Subheadline (١٥)
    static let subtitle     = DS.TextRole(.subheadline)
    /// وصف رأس الصفحة الفرعية — Subheadline (١٥)
    static let pageSubtitle = DS.TextRole(.subheadline, weight: .medium)
    /// عنوان الحقل في الصفحات (`DSFieldLabel`) — Footnote (١٣)
    static let label        = DS.TextRole(.footnote, weight: .heavy)
    /// الشرائح والأزرار الصغيرة — Subheadline (١٥)
    static let chip         = DS.TextRole(.subheadline, weight: .semibold)
    /// نص جانبي وتلميح (طرف عنوان القسم) — Caption 1 (١٢)
    static let caption      = DS.TextRole(.caption, weight: .semibold)
    /// شارة حالة — Caption 2 (١١)
    static let badge        = DS.TextRole(.caption2, weight: .bold)
    /// عنوان قسم داخل المربّع (`DSComposerSection`) — Footnote (١٣)
    static let boxSectionTitle = DS.TextRole(.footnote, weight: .bold)
    /// ملاحظة صغيرة (فوق أزرار المربّع) — Footnote (١٣)
    static let footnote     = DS.TextRole(.footnote)
    /// عدّاد ورقم صغير — Caption 2 (١١)
    static let micro        = DS.TextRole(.caption2, weight: .semibold)
    /// نص الزرّ الواحد (٤٤ في المربّعات والصفحات) — Body (١٧) شبه عريض كأزرار iOS
    static let button       = DS.TextRole(.body, weight: .semibold)
    /// زرّ ٤٨ (الإجراء الرئيسي في شاشات ملء الشاشة) — Body (١٧)
    static let buttonLarge  = DS.TextRole(.body, weight: .semibold)
}

extension DS.TextRole {
    /// عنوان رأس التبويب (`MainHeaderView`: اسم القسم، واسم العضو في الرئيسية) — Title 2 (٢٢)
    static let tabTitle     = DS.TextRole(.title2, weight: .bold)
    /// «مرحباً بك» فوق اسم العضو في رأس الرئيسية — Footnote (١٣)
    static let tabGreeting  = DS.TextRole(.footnote, weight: .semibold)
    /// اسم مربّع القسم في الرئيسية (تحت المجسّم، سطر واحد يصغر إن ضاق) — Subheadline (١٥)
    static let tileTitle    = DS.TextRole(.subheadline, weight: .bold)
}

extension DS.Font {
    /// خط الدور — `DS.Font.role(.rowTitle)`: حجم Apple الافتراضي للدور، مقيّداً بنمطه (Dynamic Type)
    static func role(_ role: DS.TextRole) -> SwiftUI.Font { plex(role.textSize, weight: role.weight, relativeTo: role.style) }
}

extension View {
    /// خط الدور بحجمه في كل مكان
    func dsFont(_ role: DS.TextRole) -> some View { font(DS.Font.role(role)) }

    /// خط الدور لعنوان الحقل وقيمته — نفس `dsFont` (كان أصغر داخل المربّعات؛ `DSFieldFont.boxReduction` = ٠)
    func dsFieldFont(_ role: DS.TextRole) -> some View { modifier(DSFieldRoleFontModifier(role: role)) }

    /// رمز SF بمقاس ثابت من `DS.Glyph` — `.dsGlyph(DS.Glyph.md)`
    func dsGlyph(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> some View {
        font(DS.Glyph.font(size, weight: weight))
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// لون متكيف مع الوضع الفاتح والداكن
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

// MARK: - View Extensions
extension View {
    func dsCardShadow() -> some View {
        self.shadow(color: DS.Shadow.card.color,
                    radius: DS.Shadow.card.radius,
                    x: DS.Shadow.card.x,
                    y: DS.Shadow.card.y)
    }

    /// نفس `dsCardShadow()` لبطاقة مقصوصة بشكل معروف: الظلّ يُلقى من الشكل تحتها (يُرسم مرة ويبقى) بدل ظلّ
    /// كل المحتوى الذي يُعاد حسابه مع كل إطار (فحص «اللاق» ٢٠٢٦-١٠-٠٧). `fill` = ما خلف البطاقة (يظهر
    /// من خلال سطح شبه شفاف كما كان) — الشكل أصغر بـ`DS.Card.shadowInset` فيبقى مخفياً تحت حافّتها.
    func dsCardShadow<S: InsettableShape>(in shape: S, fill: Color = DS.Color.background) -> some View {
        background(
            shape.inset(by: DS.Card.shadowInset).fill(fill)
                .dsCardShadow()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }

    /// زر دائري فوق الهيدر الملوّن — زجاج iOS 27 اللامع (طلب المالك):
    /// زجاج «clear» تفاعلي بلون الهيدر (لون القسم)، فيلمع ويبقى من لون الهيدر.
    /// الأنظمة الأقدم: دائرة بلون الهيدر وإطار أبيض خفيف.
    func dsHeaderGlassCircle() -> some View {
        modifier(DSHeaderGlassCircle())
    }

    func dsSubtleShadow() -> some View {
        self.shadow(color: DS.Shadow.subtle.color,
                    radius: DS.Shadow.subtle.radius,
                    x: DS.Shadow.subtle.x,
                    y: DS.Shadow.subtle.y)
    }

    /// ظل «التوهّج» — بلمسة لون القسم (كحلي العلامة خارج التبويبات)
    func dsGlowShadow() -> some View {
        modifier(DSSectionGlow(style: DS.Shadow.glow, sectionOpacity: 0.16))
    }

    /// شريط التبويبات: على iOS 26+ نترك زجاج النظام السائل كما هو
    /// (فرض مادة يدوية يطفئه)، وعلى الأقدم مادة شفافة كما كان.
    @ViewBuilder
    func dsTabBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            // شريط سفلي بزجاج iOS 27 — ثابت لا يصغر ولا يختفي عند التمرير (طلب المالك)
            self.tabBarMinimizeBehavior(.never)
        } else {
            self.toolbarBackground(.ultraThinMaterial, for: .tabBar)
        }
    }

    /// خلفية زجاجية: زجاج iOS 26/27 السائل (Liquid Glass)، ومادة شفافة على الأقدم.
    /// للعناصر العائمة فوق المحتوى (أشرطة أدوات، أزرار دائرية، أشرطة سفلية).
    @ViewBuilder
    func dsGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
}

/// خلفية زر الرأس الدائري بلون القسم (`AppSection.control`)، وكحلي العلامة خارج التبويبات
private struct DSHeaderGlassCircle: ViewModifier {
    @Environment(\.dsSection) private var section

    func body(content: Content) -> some View {
        let fill = section?.control ?? DS.Color.headerControlFill
        if DS.Theme.isCalm {
            // «الهادئ»: دائرة بيضاء بإطار شعري فوق لون القسم الخفيف (رمادي مرتفع في الداكن)
            content
                .background(Circle().fill(DS.Color.headerControlCalm))
                .overlay(Circle().strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.clear.tint(fill.opacity(0.55)).interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(SwiftUI.Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}

/// ظل ملوّن بنفس شفافية `DS.Shadow` — بغامق القسم بدل الكحلي الثابت
private struct DSSectionGlow: ViewModifier {
    let style: DS.ShadowStyle
    /// شفافية لون القسم — نفس شفافية الكحلي في `style`
    let sectionOpacity: Double
    @Environment(\.dsSection) private var section

    func body(content: Content) -> some View {
        content.shadow(color: section.map { $0.deep.opacity(sectionOpacity) } ?? style.color,
                       radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Reusable Components

/// زر رئيسي — الزرّ الواحد بمقاس ٤٨ (الإجراء الرئيسي في شاشات ملء الشاشة) — كان ٥٨ بتدرّج وسهم وظلّ.
/// `color`: الكحلي (والرمادي المعطّل `inactive`) = تعبئة القسم؛ غيره لون معنى صلب. `useGradient` بقي
/// للتوافق ولا يغيّر الشكل (شكل واحد) — المعطّل يُعرف من `.disabled(...)` بشفافية الهيكل.
struct DSPrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void
    var useGradient: Bool = true
    var color: Color = DS.Color.primary
    var size: DSButtonSize = .large

    init(_ title: String, icon: String? = nil, isLoading: Bool = false, useGradient: Bool = true,
         color: Color = DS.Color.primary, size: DSButtonSize = .large, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.useGradient = useGradient
        self.color = color
        self.size = size
        self.action = action
    }

    /// لون معنى صلب — nil = تعبئة القسم (الكحلي/المعطّل)
    private var meaningTint: Color? {
        if color == DS.Color.primary || color == DS.Color.actionNavy || color == DS.Color.inactive { return nil }
        return color
    }

    var body: some View {
        DSButton(title, icon: icon, size: size, tint: meaningTint, isLoading: isLoading, action: action)
    }
}

/// زر ثانوي — الزرّ الواحد بدور «إلغاء/ثانوي» الرمادي (كان زجاجاً بنص أخضر ٥٢). `color: DS.Color.error`
/// = إجراء خطِر (تسجيل الخروج) ← الأحمر. المقاس ٤٠ — الـ٤٨ للإجراء الرئيسي وحده.
struct DSSecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var color: Color = DS.Color.secondary
    var size: DSButtonSize = .regular

    init(_ title: String, icon: String? = nil, color: Color = DS.Color.secondary,
         size: DSButtonSize = .regular, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.size = size
        self.action = action
    }

    var body: some View {
        DSButton(title, icon: icon, role: color == DS.Color.error ? .destructive : .cancel, size: size, action: action)
    }
}

/// فاصل
struct DSDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, DS.Spacing.lg)
            .overlay(DS.Color.cardBorder.opacity(0.9))
            .opacity(0.9)
    }
}

/// شارة دور — Bold Glass pill
struct DSRoleBadge: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(DS.Font.caption2)
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.7))
    }
}

/// زر عائم — Bold glass capsule مع gradient
/// نمط زر الإضافة العائم: شفّاف في الوضع العادي (المحتوى خلفه يظهر)،
/// ولونه الطبيعي المصمت أثناء الضغط (طلب المالك).
private struct FloatingButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background {
                // اللون الطبيعي يظهر عند الضغط فقط
                Capsule().fill(gradient).opacity(pressed ? 1 : 0)
            }
            .modifier(FloatingButtonGlass(gradient: gradient, color: color, pressed: pressed))
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
    }
}

private struct FloatingButtonGlass: ViewModifier {
    let gradient: LinearGradient
    let color: Color
    let pressed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // زجاج «شفاف» (clear) بلمسة لون خفيفة — الخبر أو الصورة خلف الزر تظهر من خلاله
            content
                .clipShape(Capsule())
                .glassEffect(.clear.tint(color.opacity(0.28)), in: Capsule())
                .shadow(color: SwiftUI.Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        } else {
            // بلا ضبابية: لون العلامة نصف شفاف فيظهر المحتوى خلفه
            content
                .background(Capsule().fill(gradient).opacity(pressed ? 0 : 0.42))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DS.Color.headerBorder, lineWidth: 1))
                .shadow(color: SwiftUI.Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
        }
    }
}

struct DSFloatingButton: View {
    var icon: String? = nil
    var label: String? = nil
    var color: Color = DS.Color.primary
    /// تدرّج التعبئة — nil = نفس تدرّج الهيدر (لون القسم)
    var gradient: LinearGradient? = nil
    var action: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الكحلي يتبع لون القسم
    @Environment(\.dsSection) private var section

    private var debouncedAction: () -> Void {
        let key = "DSFloating_\(icon ?? "")_\(label ?? "")"
        let original = action
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DS.Spacing.sm) {
                if let icon, !icon.isEmpty {
                    Image(dsSymbol: icon)
                        .font(DS.Font.scaled(20, weight: .black))
                }
                if let label {
                    Text(label).font(DS.Font.calloutBold)
                }
            }
            // نص أبيض مع ظل — يبقى مقروءاً فوق ما يمرّ خلف الزر
            .foregroundColor(.white)
            .shadow(color: SwiftUI.Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
            // علامة فقط (بلا نص) → دائرة ثابتة 56؛ مع نص → كبسولة كما كانت
            .padding(.horizontal, label != nil ? DS.Spacing.xl : 0)
            .padding(.vertical, label != nil ? DS.Spacing.md + 2 : 0)
            .frame(width: label == nil ? DS.Icon.floatingButton : nil, height: label == nil ? DS.Icon.floatingButton : nil)
        }
        // شفّاف عادةً، ولونه الطبيعي عند الضغط (طلب المالك)
        .buttonStyle(FloatingButtonStyle(gradient: gradient ?? section?.gradient ?? DS.Color.gradientPrimary,
                                         color: color.dsChrome(in: section)))
        .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !appeared else { return }
            // «تقليل الحركة»: يظهر بتلاشٍ فقط بلا قفزة
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : DS.Anim.elastic.delay(0.4)) { appeared = true }
        }
    }
}

// MARK: - Icon Button — زر أيقوني دائري صغير
/// زر أيقوني دائري — للـ headers, toolbars, zoom controls
struct DSIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 18
    var iconColor: Color = .white
    var fillColor: Color = DS.Color.overlayIcon
    var borderColor: Color = DS.Color.overlayIconBorder
    var borderWidth: CGFloat = 1.5
    var action: () -> Void

    init(
        icon: String,
        size: CGFloat = 44,
        iconSize: CGFloat = 18,
        iconColor: Color = .white,
        fillColor: Color = DS.Color.overlayIcon,
        borderColor: Color = DS.Color.overlayIconBorder,
        borderWidth: CGFloat = 1.5,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconSize = iconSize
        self.iconColor = iconColor
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.action = action
    }

    private var debouncedAction: () -> Void {
        let key = "DSIconButton_\(icon)"
        let original = action
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    var body: some View {
        Button(action: debouncedAction) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(borderColor, lineWidth: borderWidth))
                Image(dsSymbol: icon)
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(iconColor)
            }
            .contentShape(Circle())
        }
        .buttonStyle(DSBoldButtonStyle())
    }
}

// MARK: - Bold Button Style
struct DSBoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Scale Button Style (Elegant)
struct DSScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Production Components

/// صورة عضو دائرية — قابلة لإعادة الاستخدام (بدل 57 تكرار)
struct DSMemberAvatar: View {
    let name: String
    let avatarUrl: String?
    var size: CGFloat = 44
    /// افتراضياً كحلي ثابت (معنى: عضو) — لا يتبع لون القسم
    var roleColor: Color = DS.Color.brand

    var body: some View {
        ZStack {
            if let urlStr = avatarUrl, let url = URL(string: urlStr) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [roleColor, roleColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(String(name.prefix(1)))
                        .font(DS.Font.scaled(16, weight: .bold))
                        .foregroundColor(roleColor)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(roleColor.opacity(0.12))
                    .frame(width: size, height: size)

                Text(String(name.prefix(1)))
                    .font(DS.Font.scaled(16, weight: .bold))
                    .foregroundColor(roleColor)
            }
        }
    }
}

/// زر «إلغاء» الموحّد أعلى الأوراق — أحمر عريض
struct DSToolbarCancelButton: View {
    var title: String = L10n.t("إلغاء", "Cancel")
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(DS.Font.calloutBold)
            .foregroundColor(DS.Color.error)
    }
}

// MARK: - شريط الورقة الموحّد — الحفظ/الإضافة يمين، الإغلاق يسار (طلب المالك)
//
// مواضع فيزيائية ثابتة: في الواجهة العربية (RTL) البداية = اليمين، فنعكس
// المواضع حتى يبقى زر التأكيد يميناً والإغلاق يساراً في اللغتين.
enum DSToolbar {
    static var confirmPlacement: ToolbarItemPlacement { L10n.isArabic ? .topBarLeading : .topBarTrailing }
    static var cancelPlacement: ToolbarItemPlacement { L10n.isArabic ? .topBarTrailing : .topBarLeading }
}

extension View {
    /// أعلى الورقة: زر تأكيد (حفظ/إضافة) يميناً + زر إغلاق يساراً
    func dsSheetToolbar(
        confirm: String,
        isLoading: Bool = false,
        disabled: Bool = false,
        onConfirm: @escaping () -> Void,
        cancel: String = L10n.t("إلغاء", "Cancel"),
        onCancel: @escaping () -> Void
    ) -> some View {
        toolbar {
            // «إلغاء» بالأحمر — نفس شاشة تعديل الملف الشخصي (طلب المالك)
            ToolbarItem(placement: DSToolbar.cancelPlacement) {
                DSToolbarCancelButton(title: cancel, action: onCancel)
            }
            ToolbarItem(placement: DSToolbar.confirmPlacement) {
                if isLoading {
                    ProgressView()
                } else {
                    DSToolbarConfirmButton(title: confirm, disabled: disabled, action: onConfirm)
                }
            }
        }
    }
}

/// زر التأكيد أعلى الورقة — بحبر القسم (كحلي خارج التبويبات)
private struct DSToolbarConfirmButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void
    @Environment(\.dsSection) private var section

    var body: some View {
        Button(title, action: action)
            .font(DS.Font.calloutBold)
            .foregroundColor(disabled ? DS.Color.textTertiary : DS.Color.primary.dsChrome(in: section))
            .disabled(disabled)
    }
}

// MARK: - هيكل المربّعات الموحّد (طلب المالك ٢٠٢٦-١٠-٠٦)
//
// لغة واحدة لكل ما يظهر فوق المحتوى: مربّع العمل (نموذج برأس ملوّن) ومربّع التأكيد/التنبيه
// (مضغوط، بلا رأس — شريط رفيع بلون القسم وقرص أيقونة صغير). الهيكل المشترك هنا في مكان واحد:
// الزوايا، السطح والإطار والظلّ، قرص الأيقونة، خط العنوان والنص، وشكل الأزرار — ولا تُكرَّر
// هذه القيم في الشاشات. ما يختلف: الرأس (كامل في العمل، شريط رفيع في التنبيه) وحجم القرص.
enum DSBox {
    // المربّع نفسه
    /// زوايا المربّع نفسه
    static let radius: CGFloat = DS.Radius.xxl
    /// الرأس الملوّن لمربّع العمل (٨٦ ← ٨٠، `DSComposerHeader`)
    static let headerHeight: CGFloat = 80
    /// شريط القسم الرفيع أعلى البطاقات بلا رأس (مثل ربط حساب التواصل)
    static let accentHeight: CGFloat = 4
    /// الرأس المضغوط لمربّع التنبيه/التأكيد (طلب المالك ٢٠٢٦-١٠-٠٧ «أقرب لمربّعات العمل»): نفس رأس العمل
    /// (`DSComposerHeader(compact:)`) بارتفاع ٥٦، مجسّم ٣٠، ونسخة مائلة شفافة ٨٠ بشفافية ٠٫١٨
    static let compactHeaderHeight: CGFloat = 56
    /// أقل حشوة رأسية فوق عنوان الرأس وتحته — الرأس يطول مع خط الجهاز بدل أن يُقصّ (مقاسات Apple ٢٠٢٦-١٠-٠٨)؛
    /// ٣ = العنوان (١٧) والوصف (١٥) يملآن الرأس المضغوط ٥٦ بالضبط في الحجم الافتراضي
    static let headerVerticalPadding: CGFloat = 3
    static let compactHeaderIcon: CGFloat = 30
    static let compactWatermark: CGFloat = 80
    static let compactWatermarkOpacity: Double = 0.18
    /// مجسّم رأس العمل ٤٤، وقرص التنبيه أخ أصغر له (٣٦ ← ٢٨)
    static let headerIcon: CGFloat = 44
    static let alertIcon: CGFloat = 28
    /// مجسّم رأس مربّع العمل (`DSComposerHeader`) وقرص المربّع الإضافي (`DSExtraBox`)
    static let composerIcon: CGFloat = 40

    // ما بداخل المربّع — أصغر بنحو ٣٠٪ ليتناسب مع الرأس الأصغر (طلب المالك ٢٠٢٦-١٠-٠٧ «وصّله إلى ٣٠٪»).
    // الحدّ: نص القيمة ≥ ١٣ نقطة والأزرار ≥ ٤٠ نقطة وصناديق الحقول ≥ ٣٦ (مساحة اللمس والقراءة) —
    // عندها يتوقّف التصغير قبل ٣٠٪ ويُذكر ذلك في التعليق.
    /// هامش محتوى مربّع العمل الجانبي (١٦ ← ١١) وأعلاه (١٢ ← ٨) وأسفله (٨ ← ٦)
    static let contentPadding: CGFloat = 11
    static let contentTop: CGFloat = 8
    static let contentBottom: CGFloat = 6
    /// بين الأقسام (١٢ ← ٨)
    static let sectionSpacing: CGFloat = 8
    /// بطاقة القسم: حشوة (١٢ ← ٨)، زوايا (١٦ ← ١٢)، المسافة بين عنوانها ومحتواها (١٠ ← ٧)
    static let sectionPadding: CGFloat = 8
    static let sectionRadius: CGFloat = 12
    static let sectionInnerSpacing: CGFloat = 7
    /// أيقونة عنوان القسم (٢٢ ← ١٦) وخطّه (١٢٫٥ ← ١١ — حدّ القراءة، لا ٨٫٧٥)
    static let sectionIcon: CGFloat = 16
    static var sectionTitleFont: Font { DS.Font.role(.boxSectionTitle) }
    /// صفّ الحقل داخل المربّع: الأيقونة (٢٨ ← ٢٢)، الحشوة الرأسية (٦ ← ٤) والجانبية (١٠ ← ٧)،
    /// أدنى ارتفاع لصندوق الحقل (٤٢ ← ٣٦ — حدّ اللمس، لا ٣٢)، وخط القيمة = Body وعنوانه = Footnote
    /// (مقاسات Apple الافتراضية، طلب المالك ٢٠٢٦-١٠-٠٨)
    static let fieldIcon: CGFloat = 22
    static let fieldVerticalPadding: CGFloat = 4
    static let fieldHorizontalPadding: CGFloat = 7
    static let fieldMinHeight: CGFloat = 36
    static var fieldValueSize: CGFloat { DS.TextRole.body.size }
    static var fieldLabelSize: CGFloat { DS.TextRole.label.size }
    /// صور المربّع: مربّع الصورة المصغّرة في شريط الصور (٧٦ ← ٥٦) ودائرة الشعار (٩٢ ← ٦٤) — كانت
    /// أرقاماً في الشاشات (٦٨/٨٠/٨٨)، والآن من هنا فقط
    static let photoTile: CGFloat = 56
    static let logoSide: CGFloat = 64
    /// صفوف النماذج (`DSFormRow`/`DSLabeledFieldRow` في إضافة/تعديل الابن): الارتفاع (٥٢ ← ٤٠ — حدّ
    /// اللمس، لا ٣٦)، قرص الأيقونة (٤٦ ← ٣٢)، الهامش الجانبي (١٦ ← ١١)
    static let formRowHeight: CGFloat = 40
    static let formRowIcon: CGFloat = 32
    static let formRowPadding: CGFloat = 11

    // مربّع التنبيه/التأكيد — نفس النسبة
    /// هامش المحتوى (٢٠ ← ١٤)، المسافة بين عناصره (١٢ ← ٨)، العنوان (١٧ ← ١٥)، النص (١٤ ← ١٣ — حدّ
    /// القراءة)، قرص الأيقونة (٣٦ ← ٢٨)، وعرضه الأقصى (٣٤٠ ← ٣٢٠)
    static let alertPadding: CGFloat = 14
    static let alertSpacing: CGFloat = 8
    static let alertMaxWidth: CGFloat = 320
    static var alertTitleFont: Font { DS.Font.role(.headline) }
    static var alertBodyFont: Font { DS.Font.role(.callout) }

    // الأزرار — مواصفة واحدة في كل أقسام التطبيق ومربّعاته (طلب المالك)، بمقاسين فقط (٢٠٢٦-١٠-٠٧):
    /// ارتفاع ٤٤ (كان ٤٠ — «كبّر شوي» طلب المالك ٢٠٢٦-١٠-٠٧)، زوايا ١٢، خط ١٥ عريض؛
    /// الإجراء بتعبئة القسم، الحذف أحمر، الإلغاء رمادي — `DSBoxButtonStyle` / `DSButton` / `DSButtonSize`
    static let buttonHeight: CGFloat = 44
    /// الإجراء الرئيسي في شاشات ملء الشاشة (الدخول، التسجيل، الانتظار، التجميد، التحديث) — كان ٥٨/٥٢
    static let buttonHeightLarge: CGFloat = 48
    static let buttonRadius: CGFloat = 12
    static let buttonSpacing: CGFloat = 7
    static var buttonFont: Font { DS.Font.role(.button) }
    static var buttonFontLarge: Font { DS.Font.role(.buttonLarge) }
    /// نص الزرّ سطر واحد يصغر حتى هذه النسبة قبل أن يُقصّ (مع الخط الكبير في الجهاز) — والارتفاع
    /// `buttonHeight` حدّ أدنى يكبر مع الخط (ن-٥ فحص ٢٠٢٦-١٠-٠٧: كان «حفظ/إضافة/نشر» يلتفّ ويُقصّ)
    static let buttonLabelMinScale: CGFloat = 0.7
    /// شريط الأزرار السفلي لمربّع العمل: هوامشه (١٦/٨/١٢ ← ١١/٦/٨)
    static let footerHorizontal: CGFloat = 11
    static let footerTop: CGFloat = 6
    static let footerBottom: CGFloat = 8

    // الشرائح (أزرار صغيرة، فلاتر، «+ صور») — `DSChipButton` / `DSExtraChip`
    /// ارتفاع الشريحة (كانت ٢٨–٣٨ في الشاشات) وحشوتها الجانبية
    static let chipHeight: CGFloat = 34
    static let chipPadding: CGFloat = 12

    /// زوايا قرص الأيقونة المستدير داخل المربّعات (في الصفحات `DS.Icon.discRadius`)
    static let iconRadius: CGFloat = DS.Icon.discRadiusSmall

    // رأس الصفحة الفرعية الملوّن (`DSSubPageHeader`) ورأس التبويب (`MainHeaderView`) — نفس الأبعاد
    /// ارتفاع صفّ الرأس تحت شريط الحالة (والأفقي المضغوط)
    static let pageHeaderHeight: CGFloat = 70
    static let pageHeaderHeightCompact: CGFloat = 46
    /// مجسّم الرأس (= مجسّم رأس المربّع) والمضغوط
    static var pageHeaderIcon: CGFloat { headerIcon }
    static var pageHeaderIconCompact: CGFloat { compactHeaderIcon }
    /// النسخة الكبيرة المائلة الشفافة في طرف الرأس (اختيارية)
    static let pageWatermark: CGFloat = 104
    static let pageWatermarkOpacity: Double = 0.2
    static let pageWatermarkAngle: Double = -18
    static var pageTitleFont: Font { DS.Font.role(.pageTitle) }
    static var pageSubtitleFont: Font { DS.Font.role(.pageSubtitle) }
    /// أقصى أسطر وصف الرأس (الطويل يلتفّ والرأس يطول بدل «…»)
    static let pageSubtitleLines = 2

    // أزرار الرجوع/الإغلاق/الإجراء (`DSNavButtons`): فوق الرأس الملوّن ٤٤ (المضغوط ٣٦)، وفوق السطح ٣٨
    static let navButtonOnColor: CGFloat = 44
    static let navButtonCompact: CGFloat = 36
    static let navButtonSurface: CGFloat = 38
    static var navGlyph: CGFloat { DS.Glyph.xl }
    static let navGlyphCompact: CGFloat = 15
    static var navGlyphSurface: CGFloat { DS.Glyph.md }

    // الخطوط المشتركة: عنوان الرأس ١٧ عريض، وصفه ١٢، نص عادي ١٤ (أدوارها في `DS.TextRole`)
    static var titleFont: Font { DS.Font.role(.title) }
    static var subtitleFont: Font { DS.Font.role(.subtitle) }
    static var bodyFont: Font { DS.Font.role(.body) }

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    static var buttonShape: RoundedRectangle { RoundedRectangle(cornerRadius: buttonRadius, style: .continuous) }
    static var sectionShape: RoundedRectangle { RoundedRectangle(cornerRadius: sectionRadius, style: .continuous) }
}

/// سطح المربّع: قصّ بزوايا الهيكل + إطار (أوضح في الداكن، طلب المالك) + ظلّ — الظلّ أعمق قليلاً
/// للوح الكبير (`strong`)
struct DSBoxChrome: ViewModifier {
    var strong: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        let shade = Color.black.opacity(strong ? 0.3 : 0.25)
        let framed = content
            .clipShape(DSBox.shape)
            .overlay(
                DSBox.shape.strokeBorder(colorScheme == .dark ? Color.white.opacity(0.2)
                                                              : Color.black.opacity(0.06),
                                         lineWidth: colorScheme == .dark ? 1.25 : 1)
            )
        if !DS.Card.shapeShadows {
            framed.shadow(color: shade, radius: strong ? 28 : 24, x: 0, y: strong ? 12 : 10)
        } else {
            // الظلّ من شكل المربّع نفسه تحته (معتم ومخفي) — يُرسم مرة بدل ظلّ كل المحتوى مع كل إطار
            framed.background(
                DSBox.shape.inset(by: DS.Card.shadowInset).fill(Color.black)
                    .shadow(color: shade, radius: strong ? 28 : 24, x: 0, y: strong ? 12 : 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
        }
    }
}

extension View {
    /// سطح المربّع الموحّد (زوايا + إطار + ظلّ) — الخلفية يضعها المحتوى قبله
    func dsBoxChrome(strong: Bool = false) -> some View { modifier(DSBoxChrome(strong: strong)) }
}

// MARK: - البطاقة الواحدة (طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد»)

/// بطاقة «مجسّمات» الواحدة — نفس بطاقة قسم المربّع (`DSComposerSection`): سطح + إطار شعري + لمسة الطين
/// (`TrialCardSkin`). أبعادها من `DS.Card` (زوايا ١٢، حشوة ٨)، فتغيير سطر هناك يغيّر كل البطاقات.
struct DSCardModifier: ViewModifier {
    /// nil = بلا حشوة (المحتوى يحمل هامشه)
    var padding: CGFloat? = DS.Card.padding
    var radius: CGFloat = DS.Card.radius
    /// سطح البطاقة — `DS.Color.background` لصندوق داخل بطاقة (صفّ/حقل)
    var fill: Color = DS.Color.surface
    /// الإطار الخفيف — false لبطاقة بلا إطار (خبر «إدارة العائلة»، طلب المالك)
    var stroked: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(padding ?? 0)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(stroked ? DS.Opacity.cardStroke : 0),
                                        lineWidth: DS.Card.strokeWidth))
            .trialCardSkin(radius: radius)
    }
}

extension View {
    /// البطاقة الواحدة: `.dsCard()` (حشوة ٨)، `.dsCard(padding: nil)` (بلا حشوة)،
    /// `.dsCard(fill: DS.Color.background)` (صندوق فوق بطاقة)
    func dsCard(padding: CGFloat? = DS.Card.padding, radius: CGFloat = DS.Card.radius,
                fill: Color = DS.Color.surface, stroked: Bool = true) -> some View {
        modifier(DSCardModifier(padding: padding, radius: radius, fill: fill, stroked: stroked))
    }
}

/// قرص أيقونة المربّع: مربّع مستدير بلون القسم يحمل مجسّم «مجسّمات» (`TrialHeaderIcon`).
/// `onTint`: فوق الرأس الملوّن (قرص زجاجي أبيض خفيف)، وإلا فوق البطاقة (قرص بلون القسم الخفيف).
struct DSBoxIconDisc: View {
    let icon: String
    let tint: Color
    var side: CGFloat = DSBox.headerIcon
    var onTint: Bool = false

    var body: some View {
        let disc = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        ZStack {
            disc.fill(onTint ? Color.white.opacity(0.16) : tint.opacity(0.12))
            disc.strokeBorder(onTint ? Color.white.opacity(0.22) : tint.opacity(0.18), lineWidth: 1)
            TrialHeaderIcon(icon: icon, tint: tint, side: side * 0.78)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// صفّ عنوان مربّع التنبيه ومربّعات البطاقة: قرص صغير بلون القسم + العنوان بخط الهيكل
struct DSBoxTitleRow: View {
    let title: String
    var icon: String? = nil
    /// لون القرص — nil = لون القسم؛ يُمرَّر لون معنى (تحذير مثلاً) عند الحاجة
    var tint: Color? = nil
    @Environment(\.dsSection) private var section

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let icon {
                DSBoxIconDisc(icon: icon, tint: tint ?? (section ?? AppSection.current)?.fill ?? DS.Color.actionNavy,
                              side: DSBox.alertIcon)
            }
            Text(title)
                .font(DSBox.alertTitleFont)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - الزرّ الواحد (طلب المالك ٢٠٢٦-١٠-٠٧ «أسلوب واحد»)
//
// شكل واحد (الزوايا، الألوان، الخط، الضغطة) بمقاسين فقط:
//   • `.regular` ٤٠ — داخل المربّعات والصفحات.
//   • `.large`   ٤٨ — الإجراء الرئيسي في شاشات ملء الشاشة (الدخول، التسجيل، الانتظار، التجميد، التحديث).
// الإجراء بتعبئة القسم (`DSActionFill`)، الحذف أحمر (`role: .destructive`)، الإلغاء/الثانوي رمادي
// (`role: .cancel`)، ولون معنى صلب عند الحاجة (`tint:` نجاح/تحذير). المعطّل نفس الشكل بشفافية واحدة.
// كل الأزرار تُرسم هنا: `DSBoxButtonStyle` (و`.buttonStyle(.ds(...))`)، `DSButton`، `DSBoxButtons`،
// `DSPrimaryButton`، `DSSecondaryButton`، `DSDestructiveButton`، `UnifiedButtonStyle`، `DSApproveRejectButtons`.

/// مقاس الزرّ — اثنان فقط
enum DSButtonSize {
    /// ٤٠ — داخل المربّعات والصفحات
    case regular
    /// ٤٨ — الإجراء الرئيسي في شاشات ملء الشاشة
    case large

    var height: CGFloat { self == .large ? DSBox.buttonHeightLarge : DSBox.buttonHeight }
    var font: Font { self == .large ? DSBox.buttonFontLarge : DSBox.buttonFont }
    /// رمز الزرّ (قبل النص)
    var glyph: CGFloat { self == .large ? DS.Glyph.lg : DS.Glyph.md }
}

/// شكل زرّ المربّعات في كل مكان (تنبيه، بطاقة، شريط مربّع العمل، الصفحات): الإجراء بتدرّج القسم ونص
/// أبيض، الحذف أحمر، الإلغاء رمادي هادئ — ضغطة ناعمة موحّدة (DSMotion)
struct DSBoxButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil
    var size: DSButtonSize = .regular
    /// لون معنى صلب بدل تعبئة القسم (نجاح، تحذير…) — nil = حسب الدور
    var tint: Color? = nil
    /// false = بعرض محتواه (زرّ الحالة الفارغة مثلاً) بدل عرض السطر
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        DSBoxButtonBody(configuration: configuration, role: role, size: size, tint: tint, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == DSBoxButtonStyle {
    /// الزرّ الموحّد — `.buttonStyle(.ds())`، `.buttonStyle(.ds(.cancel))`، `.buttonStyle(.ds(size: .large))`
    static func ds(_ role: ButtonRole? = nil, size: DSButtonSize = .regular, tint: Color? = nil,
                   fullWidth: Bool = true) -> DSBoxButtonStyle {
        DSBoxButtonStyle(role: role, size: size, tint: tint, fullWidth: fullWidth)
    }
}

private struct DSBoxButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: ButtonRole?
    var size: DSButtonSize = .regular
    var tint: Color? = nil
    var fullWidth: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .modifier(DSButtonFace(role: role, size: size, tint: tint, fullWidth: fullWidth, enabled: isEnabled))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DSMotion.press, value: configuration.isPressed)
    }
}

/// وجه الزرّ (الخط، اللون، الارتفاع، الزوايا، التعبئة، شفافية المعطّل) — المكان الوحيد الذي يُرسم فيه
struct DSButtonFace: ViewModifier {
    var role: ButtonRole? = nil
    var size: DSButtonSize = .regular
    var tint: Color? = nil
    var fullWidth: Bool = true
    var enabled: Bool = true
    /// وضع العرض: الزرّ «بعرض السطر» في الصفحات لا يتجاوز `DS.Landscape.buttonMaxWidth` ويتوسّط سطره
    /// (داخل المربّعات الوسطية يبقى بعرض المربّع — المربّع نفسه محدود العرض)
    @Environment(\.dsLandscape) private var landscape
    @Environment(\.dsInCenterBox) private var inCenterBox

    func body(content: Content) -> some View {
        let cancel = role == .cancel && tint == nil
        let capped = fullWidth && landscape && !inCenterBox
        return content
            .font(size.font)
            .foregroundColor(cancel ? DS.Color.textPrimary : .white)
            // سطر واحد يصغر بدل الالتفاف والقصّ، والارتفاع حدّ أدنى (ن-٥ فحص ٢٠٢٦-١٠-٠٧)
            .dsButtonLabelFit()
            .padding(.horizontal, fullWidth ? 0 : DS.Spacing.lg)
            .frame(maxWidth: fullWidth ? (capped ? DS.Landscape.buttonMaxWidth : .infinity) : nil)
            .frame(minHeight: size.height)
            .background { fill }
            .contentShape(DSBox.buttonShape)
            // المعطّل: نفس الشكل بشفافية الهيكل (كزرّ الإجراء في مربّع العمل)
            .opacity(enabled ? 1 : DSActionFill.disabledOpacity)
            .frame(maxWidth: capped ? .infinity : nil)
    }

    @ViewBuilder
    private var fill: some View {
        if let tint {
            // لون المعنى بدرجة تعبئته (النص أبيض) — لا بحبره الفاتح في الداكن
            DSBox.buttonShape.fill(tint.dsSolidFill)
        } else if role == .destructive {
            DSBox.buttonShape.fill(DS.Color.errorFill)
        } else if role == .cancel {
            DSBox.buttonShape.fill(DS.Color.mutedBackground.opacity(0.8))
        } else {
            DSBox.buttonShape.fill(DSActionFill.style())
        }
    }
}

/// الاسم الكامل في صفّ قائمة (منتقي الأب، المستلمون، الأجهزة، الفريق…): سطر واحد بالحجم الافتراضي وما دونه كما
/// كان، ويلتفّ لسطرين حين يكبر «حجم النص» في الجهاز بدل «…» يقصر كلما كبر الخط (فحص ٢٠٢٦-١٠-٠٨)
struct DSNameLines: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let grows = typeSize > .large
        content
            .lineLimit(grows ? DSBox.nameLinesLargeText : 1)
            .fixedSize(horizontal: false, vertical: grows)
    }
}

extension DSBox {
    /// أسطر الاسم الكامل في صفّ القائمة مع «حجم النص» الأكبر من الافتراضي (`.dsNameLines()`)
    static let nameLinesLargeText = 2
}

extension View {
    /// الاسم الكامل في صفّ: سطر واحد افتراضياً، سطران مع الخط الأكبر — `DSNameLines`
    func dsNameLines() -> some View { modifier(DSNameLines()) }
}

extension Color {
    /// لون معنى كتعبئة تحت نص أبيض: التنبيه والنجاح والخطأ بدرجتها الثابتة (`warningFill`/`successFill`/
    /// `errorFill`)، والكحلي المتكيّف `primaryFill` (الهوية: الأبيض مقروء في الداكن) — الباقي كما هو
    var dsSolidFill: Color {
        if self == DS.Color.warning { return DS.Color.warningFill }
        if self == DS.Color.success { return DS.Color.successFill }
        if self == DS.Color.error { return DS.Color.errorFill }
        if self == DS.Color.primary || self == DS.Color.brand || self == DS.Color.info { return DS.Color.primaryFill }
        // عائلة الكحلي والذهبي: اللون المتكيّف (يفتح في الداكن) ← تعبئته الثابتة تحت النص الأبيض
        if self == DS.Color.palm { return DS.Color.palmFill }
        if self == DS.Color.sea { return DS.Color.seaFill }
        if self == DS.Color.sadu { return DS.Color.saduFill }
        if self == DS.Color.slate { return DS.Color.slateFill }
        if self == DS.Color.accent { return DS.Color.goldFill }
        return self
    }
}

extension View {
    /// نص الزرّ الواحد: سطر واحد يصغر حتى `DSBox.buttonLabelMinScale` — يُستعمل في `DSButtonFace` وزرّ
    /// الإجراء في `DSComposer` (المكان الواحد لسلوك النص مع الخط الكبير، ن-٥ فحص ٢٠٢٦-١٠-٠٧)
    func dsButtonLabelFit() -> some View {
        lineLimit(1).minimumScaleFactor(DSBox.buttonLabelMinScale)
    }
}

/// زرّ جاهز بالمواصفة الواحدة: رمز اختياري + نص (+ دوّارة أثناء العمل)
struct DSButton: View {
    let title: String
    var icon: String? = nil
    var role: ButtonRole? = nil
    var size: DSButtonSize = .regular
    var tint: Color? = nil
    var isLoading: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    init(_ title: String, icon: String? = nil, role: ButtonRole? = nil, size: DSButtonSize = .regular,
         tint: Color? = nil, isLoading: Bool = false, fullWidth: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.size = size
        self.tint = tint
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }

    private var debouncedAction: () -> Void {
        let key = "DSButton_\(title)"
        let original = action
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DSBox.buttonSpacing) {
                if isLoading {
                    ProgressView()
                        .tint(role == .cancel && tint == nil ? DS.Color.textPrimary : .white)
                        .scaleEffect(DS.Spinner.buttonScale)
                } else if let icon {
                    Image(dsSymbol: icon).dsGlyph(size.glyph)
                }
                Text(title)
            }
        }
        .buttonStyle(DSBoxButtonStyle(role: role, size: size, tint: tint, fullWidth: fullWidth))
        // أثناء العمل: نفس اللون (بلا خفوت المعطّل) ولا يُضغط مرة ثانية
        .allowsHitTesting(!isLoading)
    }
}

/// النقطة الذهبية الصغيرة (اللمسة الواحدة، مثل ثمرة الغافة على مجسّمات الرئيسية): كرة طين صغيرة
/// بذهب المجسّمات وحافة أغمق تُرى على السطح الفاتح — ساكنة ومخفية عن القارئ الصوتي
struct DSGoldDot: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [DS.Color.goldDotLight, DS.Color.goldDot],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(DS.Color.goldDotRim.opacity(0.55), lineWidth: 0.75))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// نقطة «جديد» الصفراء (طلب المالك ٢٠٢٦-١٠-١٠ «نقاط صفراء صغيرة إذا شي جديد»): النقطة الذهبية بحلقة
/// بيضاء رفيعة تُرى على المربّعات الملوّنة، وهالة تنبض بهدوء — «تقليل الحركة»: ساكنة
struct DSNewDot: View {
    var size: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        DSGoldDot(size: size)
            .padding(1.5)
            .background(Circle().fill(Color.white))
            .background(
                Circle()
                    .fill(DS.Color.goldDot.opacity(0.5))
                    .scaleEffect(pulse ? 2.3 : 1)
                    .opacity(pulse ? 0 : 0.9)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.4)) { pulse = true }
            }
            .accessibilityHidden(true)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - دفعة 2-B «أسلوب واحد» (٢٠٢٦-١٠-٠٧): مقاسات صور الأعضاء في صفوف صفحات الإدارة
extension DS.Icon {
    /// صورة العضو في صفّ قائمة (السجل، الطلبات، الفريق، النشاط) — كانت `size: 40` في كل شاشة
    static let avatar: CGFloat = 40
    /// شارة الحالة الصغيرة على طرف صورة العضو (متوفّى، مجمّد، متصل)
    static let avatarBadge: CGFloat = 17
    /// صورة العضو الكبيرة في بطاقة (محطة استكمال الحسابات)
    static let avatarLarge: CGFloat = 66
    /// دائرة اختيار صورة العضو داخل المربّع (فارغة بحلقة متقطّعة، أو الصورة المختارة)
    static let photoPicker: CGFloat = 96
    /// شارة «+ / تعديل» على طرف دائرة الصورة
    static let photoBadge: CGFloat = 28
    /// نقطة «متصل الآن» على طرف صورة العضو (حلقتها النابضة ضعفها)
    static let onlineDot: CGFloat = 11
}

// MARK: - شفافية العنصر المعلّق/المخفي (دفعة 2-A «أسلوب واحد»، ٢٠٢٦-١٠-٠٧)

extension DS.Opacity {
    /// بطاقة عنصر «بانتظار» الموافقة أو مخفي عن الأعضاء (المكتبة، المشاريع) — خافتة قليلاً
    /// (المرفوض = `disabled`)
    static let dimmed: Double = 0.8
}

// MARK: - لون «رفض» (طلب المالك ٢٠٢٦-١٠-٠٧ «غيّر بين لون الرفض والحذف النهائي»)
extension DS.Color {
    /// الرفض برتقالي محروق — يتميّز عن «حذف نهائي» الأحمر؛ النص الأبيض فوقه ≥ ٤٫٥:١ في الوضعين
    static let reject = SwiftUI.Color.adaptive(light: "#B94E0C", dark: "#C8621E")
}

// MARK: - دفعة 3-B «أسلوب واحد» (٢٠٢٦-١٠-٠٧): شارة العدد ونقطة الفئة في صفحات الإدارة
extension DS.Icon {
    /// ارتفاع شارة العدد الحمراء «ما ينتظرك» (بطاقات اللوحة والمربّعات) — كانت ٢٠/٢١ في كل شاشة
    static let countBadge: CGFloat = 20
    /// نقطة لون صغيرة قبل اسم فئة (توزيع الاستخدام، مفتاح الرسم، حالة) — كانت ٧–١٠
    static let legendDot: CGFloat = 8
    /// قرص بطاقة كبيرة في لوحة الإدارة (طلبات المراجعة، الرسائل، استخدام التطبيق) ومربّعها
    static let tile: CGFloat = 42
}

extension DSBox {
    /// أدنى ارتفاع لمربّع أداة في شبكات لوحة الإدارة: ثلاثة أعمدة (المضغوط) وعمودان
    static let dashTileHeightCompact: CGFloat = 108
    static let dashTileHeight: CGFloat = 116
}

// MARK: - دفعة 3-A «أسلوب واحد» (٢٠٢٦-١٠-٠٧): «حسابي» والدخول
extension DS.Icon {
    /// صورة الحساب في رأس «حسابي» وقرصها الخارجي (الحلقة الملوّنة بينهما)
    static let profileAvatar: CGFloat = 98
    static let profileAvatarRing: CGFloat = 110
    /// قرص رقم الترتيب في وضع ترتيب الأبناء
    static let orderBadge: CGFloat = 28
    /// شعار التطبيق الدائري (الدخول، شاشة البداية — وحلقاتها نِسَب منه)
    static let appLogo: CGFloat = 100
    /// قرص الحالة الكبير في شاشات ملء الشاشة (الحساب مجمّد، حد الأجهزة، التحديث الإجباري)
    static let stateHero: CGFloat = 110
    /// رسمة شاشة الانتظار (الساعة الرملية)
    static let heroArt: CGFloat = 140
}

extension DS.TextRole {
    /// الحرف الأول مكان الصورة: في رأس «حسابي»، وفي معاينة الصورة المكبّرة
    /// — Large Title (٣٤)؛ والكبيرة رسم بمقاس ثابت داخل الدائرة
    static let avatarInitial = DS.TextRole(.largeTitle, weight: .bold)
    static let avatarInitialLarge = DS.TextRole(size: 96, weight: .bold)
    /// اسم العائلة تحت الشعار (الدخول، شاشة البداية) — Title 1 (٢٨)
    static let heroTitle = DS.TextRole(.title, weight: .heavy)
    /// رقم في مربّعات رمز التحقق — مستثنى من تغيير الخط (طلب المالك ٢٠٢٦-١٠-٠٨): كما كان ٢٦ مقيّداً بـ Title 2
    static let codeDigit = DS.TextRole(size: 26, weight: .bold, style: .title2)
}

extension DS.Opacity {
    /// تعتيم الشاشة خلف صورة مكبّرة (معاينة الصورة)
    static let mediaDim: Double = 0.88
}

extension DS.Color {
    /// خلفية رمز QR — بيضاء دائماً (تقرؤها الكاميرا في الوضعين)
    static let codeBackground = SwiftUI.Color.white
}

extension DSBox {
    /// ضلع رمز QR في مربّع «رمزي» (والأفقي)
    static let qrSide: CGFloat = 200
    static let qrSideCompact: CGFloat = 130
    /// عرض المربّع الصغير الخارج من خانته (اختيار الأم/الزوجة في «عائلتي»)
    static let popoverWidth: CGFloat = 280
    /// أقصى ضلع للصورة المكبّرة (معاينة الصورة الشخصية)
    static let mediaMaxSide: CGFloat = 420
    /// أقصى عرض لبطاقة الإدخال في شاشة الدخول (الأجهزة العريضة والأفقي)
    static let formMaxWidth: CGFloat = 380
}

extension DSBox {
    /// ارتفاع حقل البحث في الصفحات (`DSSearchField` وبحث «المستلمون») — كان ٤٦ في كل منهما
    static let searchHeight: CGFloat = 46
}

extension DSBox {
    /// محرّر نص متعدد الأسطر في الصفحات: العادي (تفاصيل الإشعار) والطويل (ما الجديد في التحديث)
    static let editorMinHeight: CGFloat = 64
    static let editorMaxHeight: CGFloat = 140
    static let editorTallMinHeight: CGFloat = 160
    static let editorTallMaxHeight: CGFloat = 320
}

extension DS {
    /// رسوم «الإحصائيات» (أشرطة التوزيع وأعمدة النمو) وعجلة اختيار الوقت — مقاسات الرسم من هنا
    enum Chart {
        /// عمود اسم الفئة وعمود الرقم بجانب شريط التوزيع، وسماكة الشريط وأقلّ طول ظاهر له
        static let barLabelWidth: CGFloat = 92
        static let barValueWidth: CGFloat = 58
        static let barHeight: CGFloat = 10
        static let barMinLength: CGFloat = 6
        /// أعمدة النمو الشهري: أطول عمود، أقصره، وارتفاع المنطقة كلها (ثابت حتى لا تتمدّد البطاقة)
        static let columnMaxHeight: CGFloat = 100
        static let columnMinHeight: CGFloat = 4
        static let columnsAreaHeight: CGFloat = 142
        /// عجلة التاريخ والوقت داخل مربّع (جدولة الإشعار)
        static let wheelHeight: CGFloat = 190
    }
}

// MARK: - وضع العرض (طلب المالك ٢٠٢٦-١٠-٠٧ «ضبط كل التطبيق بحيث تناسب وضع العرض»)
//
// الجوال مائلاً: الارتفاع ~٤٠٠ نقطة والعرض ~٩٠٠. كل قواعد الوضع الأفقي من هنا — مكان واحد:
// المربّعات الوسطية (عرضها، هامشها، رأسها المضغوط)، الصفحات الفاضية والتحميل، عرض القراءة،
// وسقف عرض الأزرار. يُقرأ «هل نحن أفقياً؟» من `@Environment(\.dsLandscape)` (= `verticalSizeClass == .compact`)
// والأدوات الجاهزة في `LandscapeLayout.swift` (`.dsLandscapeReadable()`، `AdaptiveCardStack`…).
// الوضع العمودي لا يتأثر بأي قيمة هنا.
extension DS {
    enum Landscape {
        /// عمود القراءة في الصفحات الكاملة والنماذج (الدخول، التجميد، الانتظار…) — يتوسّط الشاشة
        static let maxContentWidth: CGFloat = 560
        /// أقصى عرض للزرّ «بعرض السطر» — لا يتمدّد عبر الشاشة كلها
        static let buttonMaxWidth: CGFloat = 420
        /// المربّع الوسطي (`DSCenterPanel`): أقصى عرض (العمودي ٥٢٠)، والمسافة فوقه وتحته داخل المنطقة الآمنة
        static let panelMaxWidth: CGFloat = 600
        static let panelMargin: CGFloat = DS.Spacing.sm
        /// مربّع الرسالة (`dsAlert`): أعرض قليلاً فيقصر — والعمودي `DSBox.alertMaxWidth`
        static let alertMaxWidth: CGFloat = 420
        /// المربّع الإضافي فوق مربّع العمل (`DSExtraBox`) — العمودي ٣٨٠
        static let extraBoxMaxWidth: CGFloat = 480
        /// رأس مربّع العمل المضغوط (العمودي ٨٠) — نفس أبعاد رأس الرسالة
        static var boxHeaderHeight: CGFloat { DSBox.compactHeaderHeight }
        static var boxHeaderIcon: CGFloat { DSBox.compactHeaderIcon }
        static var boxWatermark: CGFloat { DSBox.compactWatermark }
        /// مجسّم الصفحة الفاضية (العمودي `DS.Icon.emptyArt`) — بجانب النص بدل فوقه
        static let emptyArt: CGFloat = 88
        /// مجسّم التحميل (العمودي `DS.Icon.loaderArt`)
        static let loaderArt: CGFloat = 72
        /// أيقونة الحالة الكبيرة في الصفحات الكاملة (العمودي `DS.Icon.stateHero`)
        static let stateHero: CGFloat = 72
        /// أقل عرض لعمود في الشبكة التكيّفية (عمودان على الجوال المائل)
        static let columnMinWidth: CGFloat = 340
        /// أقل عرض لمربّع أداة في شبكات الأدوات (لوحة الإدارة) — ٤ أعمدة تقريباً بدل ٢–٣
        static let tileMinWidth: CGFloat = 170
        /// أقل عرض للمربّع الصغير (مربّعات الإعدادات المضغوطة، ٣ في الصف عمودياً) — ٥ تقريباً في الصف أفقياً
        static let compactTileMinWidth: CGFloat = 130
        /// أقل عرض لبطاقة في شبكات البطاقات (المكتبة، المشاريع) — ٣–٤ أعمدة بدل عمودين
        static let gridCardMinWidth: CGFloat = 200
        /// أقل عرض لصورة في شبكة الألبوم
        static let photoMinWidth: CGFloat = 110
        /// فراغ إضافي أسفل الصفحات فوق شريط التبويبات العائم أفقياً
        static var tabBarClearance: CGFloat { DS.Icon.tapTarget }
        /// الرئيسية أفقياً: مربّعات الأقسام أقصر بمقدار، بحدّ أدنى — وعمود الأخبار بجانبها (حدّ أدنى وحصّة من العرض)
        /// (١٨ ← ١٤: اسم المربّع بمقاس Apple ١٥ تحت المجسّم يتّسع مع الخط الأكبر — ٢٠٢٦-١٠-٠٨)
        static let homeTileTrim: CGFloat = 14
        static let homeTileMinHeight: CGFloat = 66
        static let homeNewsMinWidth: CGFloat = 260
        static let homeNewsShare: CGFloat = 0.36
        static var columnSpacing: CGFloat { DS.Spacing.md }
    }
}

extension EnvironmentValues {
    /// «وضع العرض»: جوال مائل (ارتفاع مضغوط) — القاعدة الواحدة لكل مكوّن يتكيّف أفقياً
    var dsLandscape: Bool { verticalSizeClass == .compact }
}

// MARK: - دفعة 4-W «أسلوب واحد» (٢٠٢٦-١٠-٠٧): شجرة النساء
// العقدة المصغّرة في شجرة النساء (مربّع ٤٤، مربّع الزوجة ٢٤) أصغر من أصغر دور (`micro` ١١) — مقاسات رسم
// داخل لوحة الشجرة: تكبر مع العقدة كلها بمعامل `DS.TreeScale` (لا بنمط Apple وحده — كان يكسر العقد)
extension DS.TextRole {
    /// سنوات المتوفّى في شريطه، وعدد الأبناء في شارة العقدة
    static let treeNodeMicro = DS.TextRole(size: 8.5, weight: .heavy)
    /// كلمة «زوجة» داخل مربّع الزوجة الصغير، واسمها تحته
    static let treeNodeTiny = DS.TextRole(size: 8, weight: .semibold)
}

extension DS.Glyph {
    /// سهم شارة عدد الأبناء، وعين الإخفاء على مربّع الزوجة الصغير
    static let nano: CGFloat = 6
}

// MARK: - دفعة 4 «أسلوب واحد» (٢٠٢٦-١٠-٠٧): الشجرة
extension DS.TextRole {
    /// عدد الأبناء على شارة عقدة شجرة العائلة — مقاس رسم داخل العقدة (× `DS.TreeScale`)
    static let nodeCount = DS.TextRole(size: 16, weight: .heavy)
}

// MARK: - عقد الشجرتين تكبر مع «حجم النص» (طلب المالك ٢٠٢٦-١٠-٠٨ «بشي منظم»)
// العقدة كلها تكبر وتصغر بمعامل واحد: الاسم، الصورة، الصندوق، الشارات، الفجوات بين العقد وخطوط الربط —
// فتبقى الشجرة منتظمة بلا تراكب، وتكبر الشجرة مع الخط الأكبر (سحب أكثر). مقاسات الرسم الحقيقية × المعامل
// (لا `scaleEffect` — الرسم يبقى حاداً). المعامل يُقرأ مرة في الشجرة (`@Environment(\.dsTreeScale)`) ويُخزَّن مع
// التخطيط ويُمرَّر للعقد؛ نصوص العقدة بحجم ثابت (`dsTreeFont`) فلا تكبر مرتين مع Dynamic Type.
// الزوم (الملاءمة، القرابة، «موقعي») بوحدات العقدة الافتراضية فتظهر الشجرة أكبر فعلاً؛ حدود القرص على الشاشة كما كانت.
extension DS {
    enum TreeScale {
        /// السقف — «كبير جداً جداً» وكل مقاسات «تسهيلات الوصول» تقف عنده (عقدة العائلة ١٢٤ → ١٦١ نقطة)
        static let cap: CGFloat = 1.3

        /// معامل العقدة لإعداد «حجم النص» — «كبير» (الافتراضي) = ١ تماماً، فالشجرة كما كانت
        static func factor(for size: DynamicTypeSize) -> CGFloat {
            switch size {
            case .xSmall:   return 0.88
            case .small:    return 0.92
            case .medium:   return 0.96
            case .large:    return 1
            case .xLarge:   return 1.1
            case .xxLarge:  return 1.2
            case .xxxLarge: return cap
            default:        return size.isAccessibilitySize ? cap : 1
            }
        }

        /// خط نص العقدة: حجم الدور (× `DS.Font.opticalScale` للأدوار) × المعامل — حجم ثابت لا يتبع Dynamic Type ثانية.
        /// مقرَّب لنقطة كاملة كما يقرّب Dynamic Type (`relativeTo:`) — فعند «كبير» يطابق الرسم السابق بكسلاً بكسلاً
        /// (الاسم ١٥٫٣ كان يُرسم ١٥)
        static func font(_ role: DS.TextRole, _ k: CGFloat) -> SwiftUI.Font {
            .custom(DS.Font.plexName(role.weight), fixedSize: (role.textSize * k).rounded())
        }
    }
}

extension EnvironmentValues {
    /// معامل عقد الشجرة من «حجم النص» في الجهاز (`DS.TreeScale`)
    var dsTreeScale: CGFloat { DS.TreeScale.factor(for: dynamicTypeSize) }
}

extension View {
    /// نص داخل عقدة شجرة — الدور × معامل الشجرة
    func dsTreeFont(_ role: DS.TextRole, _ k: CGFloat) -> some View { font(DS.TreeScale.font(role, k)) }
    /// رمز SF داخل عقدة شجرة — مقاس `DS.Glyph` × معامل الشجرة
    func dsTreeGlyph(_ size: CGFloat, _ k: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> some View {
        font(DS.Glyph.font(size * k, weight: weight))
    }
}

extension DSBox {
    /// أقصى ارتفاع لقائمة نتائج تطفو فوق صفحة (نتائج بحث الشجرة المضمّنة) — بعده تتمرّر
    static let overlayListMaxHeight: CGFloat = 280
}

extension DS.Icon {
    /// الصورة المكبّرة عند الضغط على صورة العضو في تفاصيله
    static let avatarPreview: CGFloat = 300
}

// MARK: - «ردّ الأحجام» (طلب المالك ٢٠٢٦-١٠-٠٧: «أبي أي شي حجمه صار كبير تردّه حجمه السابق»)
// التوحيد نقل الشاشات إلى قطع مشتركة بمقاس واحد أكبر مما كانت ترسمه. هنا المقاسات الأصغر — مكان واحد:
// أحجام أزرار الرأس على السطح (شريط أدوات الشجرة)، المبدّل، الشريحة، شارة الحالة، الحالة الفارغة المضمّنة،
// ودرجات نصف النقطة للنص والرموز حيث كانت الشاشة أصغر بنصف/نقطة من الدور الأقرب.
extension DSBox {
    // أزرار الرأس فوق السطح (`DSNavButtonSize`): شريط أدوات الشجرة ٣٤ ورمز ١٤، وشريطها الجانبي (الأفقي) ٢٧ ورمز ١٢
    /// شريط أدوات الشجرة (طلب المالك ٢٠٢٦-١٠-٠٩: البطاقة أكبر والأزرار أصغر حبّة — كانت ٣٤ ثم ٣٧)
    static let navButtonToolbar: CGFloat = 35
    static let navGlyphToolbar: CGFloat = 14.5
    /// حشوة بطاقة أدوات الشجرة الرأسية (كانت ٢) — البطاقة أطول والأزرار داخلها أصغر
    static let treeToolbarPadV: CGFloat = 6
    static let navButtonMini: CGFloat = 27
    static let navGlyphMini: CGFloat = 12
    /// الإغلاق الصغير فوق سطح ملوّن (بانر صلة القرابة): رمز «×» داخل دائرة ممتلئة بلا قرص زجاجي
    static let navGlyphMiniOnColor: CGFloat = 18
    static let navGlyphMiniOnColorOpacity: Double = 0.75

    // المبدّل (`DSSegmentedSwitch`): الكبير ٤٤ (صفحات الإشعارات والتعليمات)، العادي ٣٢ (فلاتر داخل الصفحات)،
    // المدمّج ٣٠ (تبويب الشجرة) — والحشوة حول الأزرار
    static let segmentHeight: CGFloat = 44
    static let segmentHeightRegular: CGFloat = 32
    static let segmentHeightCompact: CGFloat = 33   // تبويب الشجرة [العائلة/النساء] — كان ٣٠ (٢٠٢٦-١٠-٠٩)
    static let segmentPadding: CGFloat = 4
    static let segmentPaddingSmall: CGFloat = 3

    // الشريحة (`DSChipSize`): الصغيرة ٢٨ (أزرار صفّ، فروع البحث)، والمصغّرة (شريط المسار، تبويب الشريط الجانبي)
    static let chipHeightSmall: CGFloat = 28
    static let chipPaddingSmall: CGFloat = 10
    static let chipHeightMini: CGFloat = 18
    static var chipPaddingMini: CGFloat { DS.Spacing.xsm }
}

extension DS.TextRole {
    /// نص المبدّل الكبير / العادي — Subheadline (١٥)، والمدمّج (تبويب الشجرة) — Footnote (١٣)
    static let segment        = DS.TextRole(.subheadline, weight: .semibold)
    static let segmentRegular = DS.TextRole(.subheadline, weight: .semibold)
    static let segmentCompact = DS.TextRole(.footnote, weight: .semibold)
    // «نصف الدرجة» القديمة (نصف نقطة أصغر) — مع مقاسات Apple صارت نفس نمط الدور الأصلي (طلب المالك ٢٠٢٦-١٠-٠٨)؛
    // الشريحة المضغوطة وحدها أصغر بنمط (Footnote بدل Subheadline)
    static let headlineCompact = DS.TextRole(.headline, weight: .bold)
    static let bodyCompact     = DS.TextRole(.body)
    static let rowTitleCompact = DS.TextRole(.body, weight: .semibold)
    static let calloutCompact  = DS.TextRole(.callout)
    static let chipCompact     = DS.TextRole(.footnote, weight: .semibold)
    static let captionCompact  = DS.TextRole(.caption, weight: .semibold)
    static let badgeCompact    = DS.TextRole(.caption2, weight: .bold)
    static let footnoteCompact = DS.TextRole(.footnote)
    static let microCompact    = DS.TextRole(.caption2, weight: .semibold)
}

extension DS.Glyph {
    // نصف الدرجة للرموز (كانت `.system(size: 11/13/15/17…)` في الشاشات)
    static let microCompact: CGFloat = 9
    static let xsCompact: CGFloat = 10
    static let smCompact: CGFloat = 11
    static let mdCompact: CGFloat = 13
    static let lgCompact: CGFloat = 15
    static let xlCompact: CGFloat = 17
    static let xxlCompact: CGFloat = 21
    /// قلب الإعجاب الكبير عند الضغط المزدوج على الخبر
    static let doubleTapHeart: CGFloat = 34
    /// نقطة الحالة الصغيرة في شاشة البداية
    static let splashDot: CGFloat = 7
}

extension DS.Icon {
    /// مجسّم التحميل داخل بطاقة/قائمة (`DSPageLoader(fillsSpace: false)`) — = قرص بطاقة الحالة
    static var loaderArtInline: CGFloat { state }
    /// مجسّم الصفحة الفاضية المدمجة (`DSEmptyView(style: .compact)`) — صفحات الإدارة
    static let emptyArtCompact: CGFloat = 64
    /// صورة العضو في صفّ نتائج/أبناء (أصغر من `avatar` ٤٠) والصغيرة
    static let avatarRow: CGFloat = 36
    static let avatarSmall: CGFloat = 34
    /// قرص صغير (بانر صلة القرابة، صفوف التصنيفات) ومتوسط
    static let discSmall: CGFloat = 30
    static let rowCompact: CGFloat = 34
    /// نقطة مفتاح صغيرة (شجرة النساء) ونقطة التوزيع
    static let legendDotSmall: CGFloat = 5
    static let legendDotCompact: CGFloat = 7
    /// قرص الحالة الكبير في الصفحة (حساب محذوف، حد الأجهزة) — أصغر من `stateHero`
    static let stateArt: CGFloat = 100
    /// قرص صغير جداً قبل عنوان بطاقة (المكتبة، المشاريع) ومكان أيقونة صفّ الإشعار
    static let discMini: CGFloat = 26
    /// دائرة صورة العضو في مراجعة طلب (أصغر من `photoPicker`)
    static let photoPickerCompact: CGFloat = 88
    /// حلقة النسبة الكبيرة (التحليلات، صحة الإشعارات)
    static let ring: CGFloat = 92
}

extension DSBox {
    /// كبسولة بارتفاع ٣٠ (شارة إحصاء في اللوحة، صندوق السنة) — بين الصغيرة ٢٨ والعادية ٣٤
    static let chipHeightCompact: CGFloat = 30
}

// MARK: - قسم «العائلة» في تفاصيل العضو (طلب المالك ٢٠٢٦-١٠-٠٧: الخط كما كان قبل التوحيد)
extension DS.TextRole {
    /// «الأبناء · N» فوق صور الأبناء — Footnote (١٣)
    static let familyLabel = DS.TextRole(.footnote, weight: .heavy)
    /// قيمة صفّ العلاقة (الأم/الزوج) في «العائلة» — Callout (١٦)
    static let familyValue = DS.TextRole(.callout)
}

// MARK: - دفعة 5 «أسلوب واحد» (٢٠٢٦-١٠-٠٧): آخر الأوزان التي كانت أرقاماً في المكوّنات المشتركة والدليل
extension DS.TextRole {
    /// نص المحتوى بوزن أثقل: عريض (صفّ فرع مختار)، شبه عريض (قيمة تاريخ، شرح نقطة الدليل)، متوسط (مفتاح)
    static let bodyStrong   = DS.TextRole(.body, weight: .bold)
    static let bodySemibold = DS.TextRole(.body, weight: .semibold)
    static let bodyMedium   = DS.TextRole(.body, weight: .medium)
    /// نص ملاحظة بوزن متوسط (قيمة «قبل/بعد»، رقم الإصدار، تلميح فوق صورة، سطر تحت اسم) — Callout (١٦)
    static let calloutMedium        = DS.TextRole(.callout, weight: .medium)
    static let calloutCompactMedium = DS.TextRole(.callout, weight: .medium)
    /// عنوان نهاية فصل الدليل (= `DS.Font.title2`) — Title 2 (٢٢)
    static let celebrationTitle = DS.TextRole(.title2, weight: .bold)
    /// رقم في خانة رمز التحقق داخل المربّع (`DSOTPField`) — مستثنى من تغيير الخط: كما كان ٢٢ مقيّداً بـ Title 2
    static let codeDigitCompact = DS.TextRole(size: 22, weight: .bold, style: .title2)
}

extension DSBox {
    /// خانة رقم في رمز التحقق داخل المربّع (`DSOTPField`)
    static let otpBoxHeight: CGFloat = 50
}

extension DS {
    /// الدوّارة الصغيرة المسموحة (داخل زرّ أو شريحة فقط — الصفحات والبطاقات `DSPageLoader`): مقاسها من هنا
    enum Spinner {
        /// داخل الزرّ الواحد (`DSButton`)
        static let buttonScale: CGFloat = 0.85
        /// داخل الشريحة (`DSChipButton`) أو حقل
        static let chipScale: CGFloat = 0.7
    }
}

extension DS.Glyph {
    /// رمز داخل مكان صورة فارغ (اختيار صورة العضو)
    static let placeholder: CGFloat = 40
}

extension DS.Icon {
    /// صورة العضو الكبيرة في مربّع تفاصيله
    static let memberHero: CGFloat = 130
}

extension DS.Border {
    /// حلقة حول صورة العضو وشارة الكاميرا فوقها
    static let ring: CGFloat = 2.5
}

// MARK: - لوحة الإدارة «مركز القيادة» (طلب المالك ٢٠٢٦-١٠-٢٠: الاتجاه «أ» + لمستان من «ب»)
//
// رأس كحلي بتدرّج خفيف وحلقة ذهبية ساكنة، وأرقام كبيرة («اللوحة العلوي ب أ ممتازه» — المالك ٢٠٢٦-١٠-٢٠،
// فأرقام الرأس والنبض استثناء مقصود من «لا نصّ فوق ١٧ إلا العناوين»)، بطاقات على أرضية بيضاء (كانت رملية)، وشبكة أقسام.
// كل ألوان ومقاسات الرأس والبطاقات وأزرارها من هنا — الشاشات (`AdminHubKit.swift`) لا تكتب أرقاماً.
extension DS {
    enum Hub {
        // الألوان
        /// أرضية صفحات اللوحة: أبيض في الفاتح (طلب المالك ٢٠٢٦-١٠-٢٠ «ابيض بدال الكريمي» — كان رملياً #F5F2EC) — أسود صافٍ
        /// في الداكن. البطاقات فوقها تنفصل بالإطار الرفيع وظلّ البطاقة الخفيف
        static let background = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#000000")
        /// طرفا تدرّج الرأس: كحلي المصمم ← كحلي أفتح؛ وفي الداكن أعمق
        static let bandTop = SwiftUI.Color.adaptive(light: "#172536", dark: "#0B111A")
        static let bandBottom = SwiftUI.Color.adaptive(light: "#2A3E5C", dark: "#1B2638")
        /// عمودي (حافته العليا كحلي واحد فتلتقي بشريط الحالة الثابت بلا خطّ)
        static let band = LinearGradient(colors: [bandTop, bandBottom], startPoint: .top, endPoint: .bottom)
        /// زجاج الرأس (الأزرار الدائرية، مربّعات الأرقام، شرائح الفلتر) وإطاره الداخلي
        static let glass = SwiftUI.Color.white.opacity(0.09)
        static let glassLine = SwiftUI.Color.white.opacity(0.14)
        /// الحلقة الذهبية الساكنة في طرف الرأس وهالتها
        static let ringStroke = DS.Color.accentLight.opacity(0.22)
        static let ringHalo = DS.Color.accentLight.opacity(0.05)
        /// نص ثانوي فوق الرأس (التاريخ، عناوين الأرقام)
        static let onBandMuted = SwiftUI.Color.white.opacity(0.72)
        /// شارة الدور فوق الرأس
        static let rolePillFill = DS.Color.accentLight.opacity(0.2)
        static let rolePillInk = SwiftUI.Color(hex: "#E7D3A6")
        static let rolePillStroke = DS.Color.accentLight.opacity(0.45)
        /// أرقام الرأس: «بانتظارك» ذهبي فاتح، «مستعجل» مرجاني، «متأخر» كهرماني (ثابتة في الوضعين — فوق الكحلي)
        static let kpiMine = SwiftUI.Color(hex: "#E7D3A6")
        static let kpiHot = SwiftUI.Color(hex: "#FF9C8F")
        static let kpiLate = SwiftUI.Color(hex: "#F5C46B")
        /// نقطة «جديد» على جرس الرأس (وعدد «إشعارات الإدارة» عليه)
        static let bellDot = SwiftUI.Color(hex: "#F47370")
        /// نقاط سطر الحالة فوق الكحلي: سليم أخضر فاتح، تنبيه = `kpiLate`، عاجل = `bellDot` (ثابتة في الوضعين)
        static let statusOk = SwiftUI.Color(hex: "#7FD3A2")
        /// نص فوق الشريحة الذهبية المختارة
        static let onGold = SwiftUI.Color(hex: "#1B1407")
        /// قسم «الدخول والأمان» (صدئي من عائلة الكحلي والذهبي)
        static let securityFill = SwiftUI.Color(hex: "#9A3B2E")

        // المقاسات
        static let cardRadius: CGFloat = DS.Radius.xl
        static let cardPadding: CGFloat = 14
        static let tileRadius: CGFloat = 18
        static let kpiRadius: CGFloat = DS.Radius.lg
        static let kpiPadding: CGFloat = 10
        static let stackSpacing: CGFloat = 14
        /// عرض عمود اللوحة أفقياً (الرأس والبطاقات معاً) — أعرض من عمود القراءة لأن البطاقات شبكات
        static var landscapeWidth: CGFloat { DS.Landscape.maxContentWidth * 1.4 }
        /// الهوامش داخل الرأس، وكم تصعد البطاقة الأولى فوقه
        static let headerSide: CGFloat = 18
        static let headerTop: CGFloat = DS.Spacing.sm
        static let headerBottom: CGFloat = 46
        static let headerBottomCompact: CGFloat = 20
        static let headerOverlap: CGFloat = 30
        /// الأزرار الدائرية الزجاجية في الرأس
        static let glassButton: CGFloat = 36
        static let bellDotSize: CGFloat = 8
        /// عدد الجرس: ارتفاع الكبسولة الحمراء
        static let bellBadge: CGFloat = 17
        /// سطر «حالة النظام» أسفل «يحتاج انتباهك»: نقطة اللون في صفوف لوحته، تعبئة السطر بلون حالته، وعرض اللوحة المنبثقة
        static let statusDot: CGFloat = 7
        static let statusLineFill: Double = 0.14
        static let statusPanelWidth: CGFloat = 320
        /// عرض اللوحة من أحجام إمكانية الوصول (الإجراء تحت النص)
        static let statusPanelWidthLarge: CGFloat = 360
        /// مربّع الأيقونة الملوّن في صفوف البطاقات، ومربّع الأقسام، ومربّع نوع الطلب
        static let iconSquare: CGFloat = 36
        static let iconSquareRadius: CGFloat = 11
        static let tileIcon: CGFloat = 34
        static let tileIconRadius: CGFloat = 10
        static let typeIcon: CGFloat = 24
        static let typeIconRadius: CGFloat = 7
        static let tileMinHeight: CGFloat = 96
        /// الحلقة الذهبية: قطرها، عرض الهالة، وكم تخرج من طرف الرأس
        static let ringSide: CGFloat = 260
        static let ringHaloWidth: CGFloat = 28
        static let ringOffsetX: CGFloat = 60
        static let ringOffsetY: CGFloat = 90
        /// أزرار الكبسولة في الصفوف والبطاقات (اشحن، أعلن، رفض…)
        static let pillHeight: CGFloat = 32
        static let pillHeightCard: CGFloat = 36
        static let pillPadding: CGFloat = 13
        /// الإجراءات السريعة: الدائرة وعرض العمود
        static let quickCircle: CGFloat = 54
        static let quickWidth: CGFloat = 66
        /// خط حالة الطلب على طرف البطاقة، وشريط مراحل الطلب (المقاييس والنسب: `DS.Ring`)
        static let stripeWidth: CGFloat = 4
        static let trackHeight: CGFloat = 4
        /// دائرة إنجاز المهمة («مهام اليوم»)
        static let taskRing: CGFloat = 23
        /// رسم «آخر ٣٠ يوماً» في صفحة رسائل الدخول: ارتفاعه، عرض خط الرصيد ونقطته، زاوية العمود والفراغ بينها
        static let chartHeight: CGFloat = 92
        static let chartLine: CGFloat = 2
        static let chartDot: CGFloat = 6
        static let chartBarRadius: CGFloat = 2
        static let chartBarGap: CGFloat = 2
        /// مربّع الرسم الصغير في المفتاح (عمود/خط)
        static let chartSwatch: CGFloat = 10
        /// شبكة الأقسام في «اليوم»: ٣ أعمدة × صفّان، وعمودان مع الخط الكبير جداً
        static let areaColumns = 3
        static let areaColumnsLargeText = 2
        /// خلايا بطاقة «الإعلانات» المختصرة (٢×٢ بخطوط رفيعة): مربّع الأيقونة الأصغر وحشوة الخلية
        static let miniIcon: CGFloat = 30
        static let miniIconRadius: CGFloat = 9
        static let miniCellPadding: CGFloat = DS.Spacing.sm
    }
}

extension DS.TextRole {
    /// التحية في رأس «اليوم» وعنوان صفحة القسم — Title 1 (٢٨)
    static let hubTitle = DS.TextRole(.title, weight: .bold)
    /// رقم المربّع الزجاجي في رؤوس الأقسام (`AdminKPITile`) ووسط الحلقة الكبيرة (`DS.Ring.large`: رصيد رسائل الدخول) —
    /// Title 1 (٢٨) بموافقة المالك على رأس «أ». وأرقام المربّع اللي ينسحب في «اليوم» (الدفعة ١٣ «إلى داخله نكبر»): الأربعة في
    /// «يحتاج انتباهك» ووسط حلقات «إحصاء الأفراد» (`DS.Ring.census`)
    static let hubKPI = DS.TextRole(.title, weight: .bold)
    /// وسط الحلقة المتوسطة الموحّدة (`DS.Ring.medium`)، ورقم رسائل الدخول — Title 2 (٢٢)
    static let hubPulse = DS.TextRole(.title2, weight: .bold)
    /// اسم الرقم في «يحتاج انتباهك» وسطر «54 حياً · 14 متوفى» تحت حلقات «إحصاء الأفراد» (الدفعة ١٣ — كانت Caption 1 ١٢) —
    /// Footnote (١٣) شبه عريض
    static let hubLabel = DS.TextRole(.footnote, weight: .semibold)
    /// عنوان صفّ داخل بطاقات اللوحة وعنوان مربّع القسم — Subheadline (١٥) عريض
    static let hubRow = DS.TextRole(.subheadline, weight: .bold)
    /// نص زرّ الكبسولة في الصفوف — Footnote (١٣) عريض
    static let hubButton = DS.TextRole(.footnote, weight: .bold)
}

// MARK: - المؤشرات الموحّدة (الدفعة ١٠ «وحّد شكلها كلها» — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// كل مؤشر/نسبة في لوحة الإدارة بشكل حلقة «إحصاء الأفراد» (`DSRingGauge` في `DSGauges.swift`): المقاس والسُّمك وخط الرقم
// والحركة من هنا. حيث الحلقة خطأ (خطّ زمني، توزيع من ٤ أجزاء فأكثر، مقارنة أطوال) شريط واحد `DSMeterBar` بسُمك الحلقة
// المتوسطة وألوانها ومسارها وحركتها.
extension DS {
    enum Ring {
        struct Size: Equatable {
            let side: CGFloat
            let line: CGFloat
            /// خط الرقم في الوسط — nil = بلا رقم (المصغّرة)
            let value: DS.TextRole?
            /// كلمة صغيرة تحت الرقم («أحياء»، «قبول») — nil = بلا كلمة
            let caption: DS.TextRole?
        }
        /// بجانب نصّ أو رقم (مربّع رقم في الرأس، قيمة صفّ، مربّع إحصاء، مربّع فترة) — بلا رقم في الوسط
        static let mini = Size(side: 22, line: 4, value: nil, caption: nil)
        /// صفّ بحلقة (اكتمال البيانات، سلامة الشجرة، نوع في تقرير الموافقات، وصول الإشعارات، تطابق الاسم)
        static let small = Size(side: 46, line: 5, value: .ringSmall, caption: nil)
        /// بطاقة (المسجّلون، القبول، الجنس، الحالة الاجتماعية، تسجيل الأجهزة)
        static let medium = Size(side: 76, line: 7, value: .hubPulse, caption: .micro)
        /// حلقات «إحصاء الأفراد» في المربّع اللي ينسحب (الدفعة ١٣ «إلى داخله نكبر»): درجة فوق المتوسطة، وثلاث تتّسع في
        /// عرض آيفون ٣٩٣ — والرقم بخط رقم الرأس `hubKPI`
        static let census = Size(side: 88, line: 8, value: .hubKPI, caption: .micro)
        /// «إحصاء الأفراد» مع XXXL — أصغر قليلاً (الأسماء والأعداد أكبر)
        static let censusCompact = Size(side: 80, line: 8, value: .hubKPI, caption: .micro)
        /// المتوسطة بجانب النص من أحجام إمكانية الوصول (بلا رقم داخلها — الرقم بجانبها)
        static let mediumStacked = Size(side: 52, line: 6, value: nil, caption: nil)
        /// بطل الصفحة (ملخّص إحصاءات العائلة، رصيد رسائل الدخول)
        static let large = Size(side: 104, line: 10, value: .hubKPI, caption: .caption)
        /// سُمك الشريط الموحّد (= خطّ المتوسطة)، والفراغ بين الأجزاء في الحلقة والشريط
        static let barHeight: CGFloat = 7
        static let segmentGap: CGFloat = 2
        /// المسار الفارغ قبل وصول الأرقام، و«الباقي» الخافت (رمادي المتوفين نصف شفاف — لون معنى، لا أحمر)
        static var emptyTrack: SwiftUI.Color { DS.Color.textTertiary.opacity(DS.Opacity.cardStroke) }
        static var restTrack: SwiftUI.Color { DS.Color.deceased.opacity(0.5) }
        /// المسار فوق الرأس الكحلي
        static var bandTrack: SwiftUI.Color { DS.Hub.glassLine }
        /// الحركة: الحلقة تمتلئ والرقم يعدّ معاً مرة عند الظهور الأول (تباطؤ ٠٫٧ ث بعد ٠٫١ ث)، وعند تغيّر واضح فقط
        static let fill = Animation.easeOut(duration: 0.7)
        static let fillDelay: Double = 0.1
        static let change = Animation.easeOut(duration: 0.5)
        /// تغيّر «واضح»: ١٠ نقاط مئوية في الحلقة، أو ٢٠٪ من الرقم — أقلّ منه يتبدّل بلا حركة (لا حركة مع كل تحديث)
        static let notableShare: Double = 0.1
        static let notableCount: Double = 0.2
    }

    /// نبضة «حالة النظام» العاجلة (أحمر): هالة حول النقطة تتّسع وتتلاشى — على الساعة الهادئة المشتركة (`FTAmbientClock`)
    enum Pulse {
        static let period: Double = 1.6
        static let scale: CGFloat = 2.4
        static let opacity: Double = 0.6
        static let dot: CGFloat = 8
    }

    /// لحظة النجاح الخفيفة (`DSMomentToast`): كبسولة أعلى الشاشة بمجسّم اللحظة مصغّراً + سطر، ثم تختفي وحدها
    enum MomentToast {
        static let art: CGFloat = 40
        static let artWidth: CGFloat = 56
        /// مجسّم اللحظة يُرسم ١٦٠×١١٢ — يُصغَّر إلى `art`
        static let artScale: CGFloat = 0.36
        /// تبقى ظاهرة، ثم تتلاشى في `fadeOut`؛ وتنزل من `rise` فوق مكانها
        static let hold: Double = 1.8
        static let fadeOut: Double = 0.5
        static let rise: CGFloat = 80
        /// مهلة بعد الموافقة المتفائلة قبل اللحظة (تظهر أخطاء الفحص المحلي أولاً، وتُغلق نافذة التفاصيل)
        static let settle: Double = 0.35
        static let topInset: CGFloat = DS.Spacing.sm
        static let padding: CGFloat = DS.Spacing.md
        static let minHeight: CGFloat = 52
    }
}

extension DS.Hub {
    /// سطر «اليوم» الذكي تحت التحية (ذكرى اليوم، وفاة لم يُعلن عنها، الطلبات، الجدد، يوم هادئ)
    static let greetingLine = SwiftUI.Color.white.opacity(0.86)
    /// «المربّع اللي ينسحب» (`AdminTodaySwipeCard`): أقل سحب يبدأ به، المسافة التي تقلب الصفحة، المقاومة عند الطرفين،
    /// ونقطتا الصفحة (العادية، الحالية كبسولة، وارتفاع شريطهما داخل المربّع في أسفله — الدفعة ١٣ «خلهم داخل المربع»)
    static let swipeMinimum: CGFloat = 12
    static let swipeDistance: CGFloat = 60
    static let swipeResistance: CGFloat = 0.3
    /// الرمية: السرعة × هذا = المسافة الإضافية المتوقّعة (ث)
    static let swipeThrow: CGFloat = 0.2
    static let pageDot: CGFloat = 6
    static let pageDotActive: CGFloat = 16
    static let pageDotsHeight: CGFloat = 20
    /// حشوة صفحتي المربّع (الجانبان والأعلى، والأسفل بلا نقاط) والفراغ بين العنوان وما تحته — أضيق من بطاقات اللوحة
    /// (الدفعة ١٣ «نصغره شوي»)
    static let swipePadding: CGFloat = DS.Spacing.md
    static let swipeGap: CGFloat = DS.Spacing.xs
}

extension DS.TextRole {
    /// الرقم داخل الحلقة الصغيرة — Footnote (١٣) عريض
    static let ringSmall = DS.TextRole(.footnote, weight: .bold)
}
