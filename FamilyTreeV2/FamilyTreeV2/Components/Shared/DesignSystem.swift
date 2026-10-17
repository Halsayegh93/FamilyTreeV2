import SwiftUI

// MARK: - Design Tokens — المحمدعلي Family App
// الهوية الموحدة: ألوان دليل المصمم — كحلي #172536 + ذهبي #B89A5A + كريمي #F2EBDD | Light & Dark Mode
// القيم من نظام التصميم «المحمدعلي» (tokens.json) — نفس قيم الموقع. ألوان الأقسام الداعمة
// (أخضر غابي، عنّابي، ألوان الأخبار والأدوار) باقية كما هي.
enum DS {

    // MARK: Colors
    enum Color {
        // Brand — كحلي المصمم (navy)، أفتح في الداكن ليبقى مقروءاً
        static let primary       = SwiftUI.Color.adaptive(light: "#172536", dark: "#7FA8D6") // navy
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

        // MARK: Feature Gradients — موحد: هيدرات الأقسام على band
        static let gradientHome     = gradientBand
        static let gradientTree     = gradientBand
        static let gradientDiwaniya = gradientBand
        static let gradientProfile  = gradientBand
        static let gradientAdmin    = gradientBand

        // MARK: Feature Tints — لون واحد موحد
        static let tintHome     = primary
        static let tintTree     = primary
        static let tintDiwaniya = primary
        static let tintProfile  = primary
        static let tintAdmin    = primary

        // Surfaces — الكروت لازم تبان فوق الخلفية
        // الهوية: خلفية رملية والكروت بيضاء فوقها
        static let background       = SwiftUI.Color.adaptive(light: "#FFFFFF", dark: "#000000") // أبيض صافي / أسود صافي
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
        static let newsAnnouncement = primary
        static let newsCongrats     = accent
        static let newsReminder     = newsWedding
        static let newsInvitation   = SwiftUI.Color.adaptive(light: "#7C3E4C", dark: "#ECA8B2") // عنّابي

        // Status Colors
        /// المتوفّى — رصاصي العائلة (slate) للنص والأيقونات والحلقات؛ كان #A0A0A0 والأبيض فوقه ٢٫٦:١
        static let deceased         = slate
        /// تعبئة المتوفّى تحت نص/أيقونة بيضاء — slateFill الثابت (الأبيض فوقه ٧:١)
        static let deceasedFill     = slateFill
        static let currentLocation  = SwiftUI.Color.adaptive(light: "#2C623B", dark: "#9ACDA1") // أخضر
        static let likeAction       = newsWedding // وردي
        /// لون الإناث في شجرة النساء — وردي تراثي موحّد (بدل القيم المرمّزة يدوياً في WomenTreeView/WomenClassicTreeView)
        static let female           = SwiftUI.Color.adaptive(light: "#92526F", dark: "#F4B1CB") // وردي
        /// الأنثى المتوفّاة في شجرة النساء — وردي أغمق يميّزها عن الحيّة دون أن يفقد هويتها
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

    // MARK: Typography — IBM Plex Sans Arabic لكل الواجهة، مع دعم Dynamic Type
    // الهوية: خط واحد للواجهة كلها (التطبيق والموقع والـ PDF) بأوزان 400/500/600/700.
    // رموز SF Symbols وحدها على خط النظام — عبر icon().
    enum Font {
        // MARK: IBM Plex Sans Arabic — خط الهوية
        /// أسماء PostScript للأوزان المضافة في Resources/Fonts
        enum Plex {
            static let regular  = "IBMPlexSansArabic-Regular"
            static let medium   = "IBMPlexSansArabic-Medium"
            static let semibold = "IBMPlexSansArabic-SemiBold"
            static let bold     = "IBMPlexSansArabic-Bold"

            /// وزن الواجهة المطلوب ← ملف الخط: الخفيف والعادي → Regular (400)، medium → Medium (500)،
            /// semibold → SemiBold (600)، bold وheavy وblack → Bold (700)
            static func name(for weight: SwiftUI.Font.Weight) -> String {
                switch weight {
                case .black, .heavy, .bold: return bold
                case .semibold:             return semibold
                case .medium:               return medium
                default:                    return regular
                }
            }
        }

        /// خط IBM Plex Sans Arabic مع دعم Dynamic Type — يُستخدم للعناوين وهوية الاسم
        static func plex(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(Plex.name(for: weight), size: size, relativeTo: textStyle(for: size))
        }

        /// IBM Plex Sans Arabic بحجم ثابت لا يتبع Dynamic Type — لنصوص لوحة الشجرة داخل عُقد بمقاس ثابت
        /// (بدل .system(size:) في تلك الأماكن)
        static func plexFixed(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(Plex.name(for: weight), fixedSize: size)
        }

        /// اختيار TextStyle المناسب للحجم — يضمن تكيّف الخط المخصّص مع Dynamic Type
        static func textStyle(for size: CGFloat) -> SwiftUI.Font.TextStyle {
            switch size {
            case ...12:  return .caption
            case 13:     return .footnote
            case 14...15: return .subheadline
            case 16:     return .callout
            case 17:     return .body
            case 18...19: return .headline
            case 20...21: return .title3
            case 22...27: return .title2
            default:     return .title
            }
        }

        // العناوين — IBM Plex Sans Arabic (الصوت الطباعي للهوية)، مع دعم Dynamic Type
        static let hero        = SwiftUI.Font.custom(Plex.bold, size: 34, relativeTo: .largeTitle)
        static let largeTitle  = SwiftUI.Font.custom(Plex.bold, size: 34, relativeTo: .largeTitle)
        static let title1      = SwiftUI.Font.custom(Plex.bold, size: 28, relativeTo: .title)
        static let title2      = SwiftUI.Font.custom(Plex.bold, size: 22, relativeTo: .title2)
        static let title3      = SwiftUI.Font.custom(Plex.semibold, size: 20, relativeTo: .title3)
        static let headline    = SwiftUI.Font.custom(Plex.semibold, size: 17, relativeTo: .headline)
        // نص المحتوى — IBM Plex Sans Arabic أيضاً (الهوية: خط واحد لكل الواجهة)، مع Dynamic Type
        static let body        = SwiftUI.Font.custom(Plex.regular, size: 17, relativeTo: .body)
        static let bodyBold    = SwiftUI.Font.custom(Plex.semibold, size: 17, relativeTo: .body)
        static let callout     = SwiftUI.Font.custom(Plex.regular, size: 16, relativeTo: .callout)
        static let calloutBold = SwiftUI.Font.custom(Plex.bold, size: 16, relativeTo: .callout)
        static let subheadline = SwiftUI.Font.custom(Plex.regular, size: 15, relativeTo: .subheadline)
        static let footnote    = SwiftUI.Font.custom(Plex.regular, size: 13, relativeTo: .footnote)
        // الهوية: caption بوزن 500 وcaption-2 بوزن 600 (حقول وعدّادات وشارات أدوار)
        static let caption1    = SwiftUI.Font.custom(Plex.medium, size: 12, relativeTo: .caption)
        static let caption2    = SwiftUI.Font.custom(Plex.semibold, size: 11, relativeTo: .caption2)

        /// نمط النص المقابل للحجم — يحدّد منحنى Dynamic Type لـ scaled() وicon().
        /// نفس الجدول السابق لكل الأحجام الصحيحة (١١ وأقل caption2 … ٣٦ وأكثر largeTitle)،
        /// والحدود بـ ..< حتى تأخذ الأحجام الكسرية (13.5 مثلاً) النمط الأقرب بدل largeTitle.
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

        /// خط الواجهة المرن — IBM Plex Sans Arabic بالحجم المطلوب ويكبر ويصغر مع Dynamic Type
        /// (relativeTo: نمط النص المقابل للحجم). يُستخدم بدل .system(size:weight:) لكل نص.
        /// الأوزان حسب Plex.name(for:). `design` باقٍ في التوقيع للتوافق فقط ويُتجاهل — خط واحد للواجهة.
        /// لرموز SF Symbols استخدم icon().
        static func scaled(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
            .custom(Plex.name(for: weight), size: size, relativeTo: scaledTextStyle(for: size))
        }

        /// خط رموز SF Symbols — خط النظام بنمط النص المقابل للحجم مع الوزن (نفس ما كان scaled() يرجعه،
        /// فلا يتغيّر مقاس الأيقونات)، ويكبر ويصغر مع Dynamic Type.
        /// لـ Image(systemName:) فقط؛ النص يبقى على scaled()/plex().
        static func icon(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            SwiftUI.Font.system(scaledTextStyle(for: size), design: .default).weight(weight)
        }

        /// الخط الكبير (display) بحجم مخصّص — لاسم العائلة والعناوين الكبيرة: نفس scaled() على Plex.
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            scaled(size, weight: weight)
        }
    }

    // MARK: Spacing
    enum Spacing {
        static let xs:    CGFloat = 4
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

    /// زر دائري فوق الهيدر الملوّن — زجاج iOS 27 اللامع (طلب المالك):
    /// زجاج «clear» تفاعلي بلون الهيدر الكحلي، فيلمع ويبقى من لون الهيدر.
    /// الأنظمة الأقدم: دائرة بلون الهيدر وإطار أبيض خفيف.
    @ViewBuilder
    func dsHeaderGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.tint(DS.Color.headerControlFill.opacity(0.55)).interactive(), in: Circle())
        } else {
            self
                .background(Circle().fill(DS.Color.headerControlFill))
                .overlay(Circle().strokeBorder(SwiftUI.Color.white.opacity(0.18), lineWidth: 1))
        }
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

    func dsSubtleShadow() -> some View {
        self.shadow(color: DS.Shadow.subtle.color,
                    radius: DS.Shadow.subtle.radius,
                    x: DS.Shadow.subtle.x,
                    y: DS.Shadow.subtle.y)
    }

    func dsGlowShadow() -> some View {
        self.shadow(color: DS.Shadow.glow.color,
                    radius: DS.Shadow.glow.radius,
                    x: DS.Shadow.glow.x,
                    y: DS.Shadow.glow.y)
    }

    func dsNeonShadow() -> some View {
        self.shadow(color: DS.Shadow.neon.color,
                    radius: DS.Shadow.neon.radius,
                    x: DS.Shadow.neon.x,
                    y: DS.Shadow.neon.y)
    }

    func dsAccentGlow() -> some View {
        self.shadow(color: DS.Shadow.glowAccent.color,
                    radius: DS.Shadow.glowAccent.radius,
                    x: DS.Shadow.glowAccent.x,
                    y: DS.Shadow.glowAccent.y)
    }

    func dsGradientBackground() -> some View {
        self.background(DS.Color.gradientBand)
    }

    /// كرت — سطح أبيض بحد خفيف (الهوية: بدون زجاج). الاسم باقٍ للتوافق.
    func glassCard(radius: CGFloat = DS.Radius.xl) -> some View {
        self
            .background(DS.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DS.Color.cardBorder, lineWidth: 1)
            )
            .dsCardShadow()
    }

    /// خلفية — سطح أبيض بحد خفيف (الهوية: بدون زجاج). الاسم باقٍ للتوافق.
    func glassBackground(radius: CGFloat = DS.Radius.lg) -> some View {
        self
            .background(DS.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DS.Color.cardBorder, lineWidth: 1)
            )
    }

    /// شكل كبسولة زجاجية — Liquid Glass pill
    func glassPill() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(SwiftUI.Color.white.opacity(0.15), lineWidth: 0.5))
    }

    /// Bold press effect
    func dsBoldPress(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(DS.Anim.bouncy, value: isPressed)
    }
}

// MARK: - Reusable Components

/// كرت موحد — سطح أبيض، حد line، زوايا xl، ظل خفيف (الهوية)
struct DSCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = DS.Spacing.lg

    init(padding: CGFloat = DS.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.cardBackground)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(DS.Color.cardBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            // منطقة اللمس = حدود البطاقة فقط
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .dsCardShadow()
    }
}

/// كرت مع تدرج لوني جريء + glass overlay
struct DSGradientCard<Content: View>: View {
    let gradient: LinearGradient
    let content: Content

    init(gradient: LinearGradient = DS.Color.gradientBand, @ViewBuilder content: () -> Content) {
        self.gradient = gradient
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                gradient
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(SwiftUI.Color.white.opacity(0.30), lineWidth: 0.7)
            )
            .dsGlowShadow()
    }
}

/// كرت مع حدود ملونة — Accent border card
struct DSGlowCard<Content: View>: View {
    let glowColor: SwiftUI.Color
    let content: Content

    init(glowColor: SwiftUI.Color = DS.Color.primary, @ViewBuilder content: () -> Content) {
        self.glowColor = glowColor
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(glowColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: glowColor.opacity(0.12), radius: 10, x: 0, y: 3)
    }
}

/// نص بتدرج لوني
struct DSGradientText: View {
    let text: String
    var font: SwiftUI.Font = DS.Font.title1
    var gradient: LinearGradient = DS.Color.gradientPrimary

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(gradient)
    }
}

/// باج متحرك مع نبض
struct DSPulseBadge: View {
    let count: Int
    var color: SwiftUI.Color = DS.Color.error

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var displayText: String { count > 99 ? "99+" : "\(count)" }

    var body: some View {
        Text(displayText)
            .font(DS.Font.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(DS.Color.errorFill)
            .clipShape(Capsule())
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .animation(
                DS.Anim.respectingMotion(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), reduceMotion: reduceMotion),
                value: isPulsing
            )
            // يحترم "تقليل الحركة": يبقى الباج ثابتاً بلا نبض متكرر
            .onAppear { isPulsing = !reduceMotion }
    }
}

/// زر رئيسي — Bold gradient مع bounce effect
struct DSPrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void
    var useGradient: Bool = true
    var color: Color = DS.Color.primary

    init(_ title: String, icon: String? = nil, isLoading: Bool = false, useGradient: Bool = true, color: Color = DS.Color.primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.useGradient = useGradient
        self.color = color
        self.action = action
    }

    /// تعبئة الزر بدون التدرّج — الكحلي المتكيّف يأخذ primaryFill حتى يبقى النص الأبيض مقروءاً في الداكن
    private var flatFill: Color { color == DS.Color.primary ? DS.Color.primaryFill : color }

    private var debouncedAction: () -> Void {
        let key = "DSPrimary_\(title)"
        let original = action
        return {
            if TapDebouncer.shared.canFire(key) { original() }
        }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DS.Spacing.sm) {
                if isLoading {
                    ProgressView().tint(DS.Color.textOnPrimary)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(DS.Font.icon(16, weight: .bold))
                    }
                    Text(title)
                        .fontWeight(.bold)
                    Spacer(minLength: 0)
                    Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                        .font(DS.Font.icon(14, weight: .black))
                        .opacity(0.9)
                }
            }
            .font(DS.Font.headline)
            .foregroundColor(DS.Color.textOnPrimary)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            // minHeight بدل الارتفاع الثابت — يسمح للنص بالنمو بدل القص في أحجام Dynamic Type الكبيرة
            .frame(minHeight: 58)
            .background(
                // الهوية: تعبئة بلون واحد بدون لمعة زجاجية
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(
                        useGradient
                            ? AnyShapeStyle(DS.Color.gradientPrimary)
                            : AnyShapeStyle(isLoading ? flatFill.opacity(0.7) : flatFill)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(SwiftUI.Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: color.opacity(useGradient ? 0.22 : 0.16), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(DSBoldButtonStyle())
        .disabled(isLoading)
    }
}

/// زر ثانوي — سطح أبيض بحد line-strong ونص كحلي (الهوية)
struct DSSecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var color: Color = DS.Color.primary

    init(_ title: String, icon: String? = nil, color: Color = DS.Color.primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    private var debouncedAction: () -> Void {
        let key = "DSSecondary_\(title)"
        let original = action
        return {
            if TapDebouncer.shared.canFire(key) { original() }
        }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DS.Spacing.sm) {
                if let icon { Image(systemName: icon).font(DS.Font.icon(14, weight: .bold)) }
                Text(title).fontWeight(.bold)
            }
            .font(DS.Font.calloutBold)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            // minHeight بدل الارتفاع الثابت — يسمح للنص بالنمو بدل القص في أحجام Dynamic Type الكبيرة
            .frame(minHeight: 52)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.cardBorderStrong, lineWidth: 1)
            )
        }
        .buttonStyle(DSBoldButtonStyle())
    }
}

/// حقل إدخال — سطح أبيض بحد line-strong، وعند التركيز حد بلون الأيقونة (الهوية)
struct DSTextField: View {
    @Environment(\.layoutDirection) private var layoutDirection
    var label: String
    var placeholder: String
    @Binding var text: String
    var icon: String
    var iconColor: Color = DS.Color.primary
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var required: Bool = false
    var hint: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                if !label.isEmpty {
                    HStack(spacing: 2) {
                        Text(label)
                            .foregroundColor(isFocused ? iconColor : DS.Color.textSecondary)
                        if required {
                            Text("*")
                                .foregroundColor(DS.Color.error)
                        }
                        if let hint {
                            Text(hint)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                    .font(DS.Font.caption1)
                    .animation(DS.Anim.quick, value: isFocused)
                }
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(DS.Font.body)
                        .keyboardType(keyboard)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .font(DS.Font.body)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.leading)
                        .focused($isFocused)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(isFocused ? iconColor : DS.Color.cardBorderStrong, lineWidth: isFocused ? 1.5 : 1)
                .animation(DS.Anim.quick, value: isFocused)
        )
        .shadow(color: isFocused ? iconColor.opacity(0.1) : .clear, radius: 8, x: 0, y: 3)
        .animation(DS.Anim.quick, value: isFocused)
    }
}

/// أيقونة — Bold circle مع gradient tint
struct DSIcon: View {
    let name: String
    var color: Color = DS.Color.primary
    var size: CGFloat = DS.Icon.size
    var iconSize: CGFloat = 17

    init(_ name: String, color: Color = DS.Color.primary, size: CGFloat = DS.Icon.size, iconSize: CGFloat = 17) {
        self.name = name
        self.color = color
        self.size = size
        self.iconSize = iconSize
    }

    var body: some View {
        Image(systemName: name)
            .font(DS.Font.icon(iconSize, weight: .bold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            // الهوية: مربّع الأيقونة بلون قسمه ١٥٪ — تعبئة صلبة بلا تدرّج
            .background(color.opacity(DS.Icon.opacity))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

/// صف بيانات — Bold Glass style
struct DSDataRow: View {
    var title: String
    var value: String
    var icon: String
    var color: Color = DS.Color.primary

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Text(value)
                    .font(DS.Font.calloutBold)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}

/// صف إجراء مع badge — Bold Glass style
struct DSActionRow: View {
    var title: String
    var subtitle: String? = nil
    var icon: String
    var color: Color = DS.Color.primary
    var badge: Int? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()

            if let badge, badge > 0 {
                DSPulseBadge(count: badge)
            }

            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.icon(13, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}

/// عنوان قسم — Bold
struct DSSectionHeader: View {
    var title: String
    var icon: String? = nil
    var trailing: String? = nil
    var iconColor: Color = DS.Color.primary

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    if let icon {
                        Image(systemName: icon)
                            .font(DS.Font.icon(12, weight: .bold))
                            .foregroundColor(iconColor)
                    }
                    Text(title)
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(iconColor.opacity(0.08))
                .clipShape(Capsule())

                if let trailing {
                    // تلميح ثانوي — لا ينافس عنوان القسم في اللون ولا الحجم
                    Text(trailing)
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            DSDivider()
        }
    }
}

/// هيدر شيت — Bold Glass style
struct DSSheetHeader: View {
    var title: String
    var cancelTitle: String = L10n.t("إلغاء", "Cancel")
    var confirmTitle: String = L10n.t("حفظ", "Save")
    var isLoading: Bool = false
    var confirmDisabled: Bool = false
    var showBackground: Bool = true
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, DS.Spacing.sm)

            HStack {
                Button(cancelTitle, action: onCancel)
                    .font(DS.Font.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textSecondary)

                Spacer()

                Text(title)
                    .font(DS.Font.headline)

                Spacer()

                Button(action: onConfirm) {
                    if isLoading {
                        ProgressView().tint(DS.Color.primary)
                    } else {
                        Text(confirmTitle)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(confirmDisabled ? DS.Color.textTertiary : DS.Color.primary)
                    }
                }
                .disabled(confirmDisabled || isLoading)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)

            Divider().opacity(0.3)
        }
        .background(showBackground ? DS.Color.surface : Color.clear)
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

/// بطاقة إحصاء — Bold Glass card
struct DSStatCard: View {
    var title: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.icon(26, weight: .bold))
                .foregroundColor(color)
                .frame(width: DS.Icon.sizeLg, height: DS.Icon.sizeLg)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            Text(value)
                .font(DS.Font.title1)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Text(title)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .glassCard()
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
    /// تدرّج التعبئة — افتراضياً نفس تدرّج الهيدر
    var gradient: LinearGradient = DS.Color.gradientPrimary
    var action: () -> Void

    @State private var appeared = false

    private var debouncedAction: () -> Void {
        let key = "DSFloating_\(icon ?? "")_\(label ?? "")"
        let original = action
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DS.Spacing.sm) {
                if let icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(DS.Font.icon(20, weight: .black))
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
            .frame(width: label == nil ? 56 : nil, height: label == nil ? 56 : nil)
        }
        // شفّاف عادةً، ولونه الطبيعي عند الضغط (طلب المالك)
        .buttonStyle(FloatingButtonStyle(gradient: gradient, color: color))
        .scaleEffect(appeared ? 1 : 0.3)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !appeared else { return }
            withAnimation(DS.Anim.elastic.delay(0.4)) { appeared = true }
        }
    }
}

// MARK: - Decorative Background — خلفية نظيفة بدون وهج
struct DSDecorativeBackground: View {
    var primaryGradient: LinearGradient = DS.Color.gradientPrimary
    var accentGradient: LinearGradient = DS.Color.gradientAccent

    var body: some View {
        EmptyView()
    }
}

// MARK: - Setting Icon — أيقونة الإعدادات
struct DSSettingIcon: View {
    var name: String
    var color: Color
    var size: CGFloat = DS.Icon.sizeSm

    var body: some View {
        ZStack {
            // تعبئة صلبة — والكحلي المتكيّف يأخذ primaryFill حتى يبقى الرمز الأبيض مقروءاً في الداكن
            Circle()
                .fill(color == DS.Color.primary ? DS.Color.primaryFill : color)
                .frame(width: size, height: size)

            Image(systemName: name)
                .font(DS.Font.icon(size * 0.42, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
        }
    }
}

// MARK: - Card Accent Line — خط زخرفي فوق البطاقة
struct DSCardAccentLine<S: ShapeStyle>: View {
    var style: S

    init(gradient: LinearGradient) where S == LinearGradient {
        self.style = gradient
    }

    init(color: Color) where S == Color {
        self.style = color
    }

    init() where S == LinearGradient {
        self.style = DS.Color.gradientPrimary
    }

    var body: some View {
        Rectangle()
            .fill(style)
            .frame(height: 4)
            .cornerRadius(DS.Radius.full)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.xs)
    }
}

// MARK: - Approve / Reject Buttons — أزرار الموافقة والرفض
struct DSApproveRejectButtons: View {
    var approveTitle: String
    var rejectTitle: String
    var isLoading: Bool = false
    var approveGradient: LinearGradient = DS.Color.gradientPrimary
    var showReject: Bool = true
    /// عند true تكون الأزرار بحواف دائرية كاملة (capsule) بدل المستطيل المُدوّر
    var useCapsule: Bool = false
    /// طلب تأكيد قبل تنفيذ الموافقة/الرفض (افتراضياً مُفعّل لكل الأماكن).
    var confirmBeforeAction: Bool = true
    var onApprove: () -> Void
    var onReject: () -> Void

    @State private var showApproveConfirm = false
    @State private var showRejectConfirm = false

    private var cornerRadius: CGFloat { useCapsule ? DS.Radius.full : DS.Radius.md }

    private var debouncedApprove: () -> Void {
        let key = "DSApprove_\(approveTitle)"
        let original = onApprove
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }
    private var debouncedReject: () -> Void {
        let key = "DSReject_\(rejectTitle)"
        let original = onReject
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    private func approveTapped() {
        if confirmBeforeAction { showApproveConfirm = true } else { debouncedApprove() }
    }
    private func rejectTapped() {
        if confirmBeforeAction { showRejectConfirm = true } else { debouncedReject() }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if showReject {
            Button(action: rejectTapped) {
                Text(rejectTitle)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.error.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(DS.Color.error.opacity(0.3), lineWidth: 1.5)
                    )
            }
            }

            Button(action: approveTapped) {
                ZStack {
                    if isLoading {
                        ProgressView().tint(DS.Color.textOnPrimary)
                    } else {
                        Text(approveTitle)
                            .font(DS.Font.calloutBold)
                    }
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(approveGradient)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .dsGlowShadow()
            }
        }
        .dsAlert(L10n.t("تأكيد الموافقة", "Confirm Approval"), isPresented: $showApproveConfirm) {
            Button(approveTitle) { debouncedApprove() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد المتابعة؟", "Do you want to proceed?"))
        }
        .dsAlert(L10n.t("تأكيد الرفض", "Confirm Rejection"), isPresented: $showRejectConfirm) {
            Button(rejectTitle, role: .destructive) { debouncedReject() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد المتابعة؟", "Do you want to proceed?"))
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
                Image(systemName: icon)
                    .font(DS.Font.icon(iconSize, weight: .bold))
                    .foregroundColor(iconColor)
            }
            .contentShape(Circle())
        }
        .buttonStyle(DSBoldButtonStyle())
    }
}

// MARK: - Destructive Button — زر هدام (للحذف)
/// زر الإجراءات الهدامة — الحذف، الإلغاء النهائي
struct DSDestructiveButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, icon: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    private var debouncedAction: () -> Void {
        let key = "DSDestructive_\(title)"
        let original = action
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DS.Spacing.sm) {
                if isLoading {
                    ProgressView().tint(DS.Color.error)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(DS.Font.icon(15, weight: .bold))
                    }
                    Text(title).fontWeight(.bold)
                }
            }
            .font(DS.Font.calloutBold)
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DS.Color.error.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.error.opacity(0.3), lineWidth: 1.2)
            )
        }
        .buttonStyle(DSBoldButtonStyle())
        .disabled(isLoading)
    }
}

// MARK: - Text Button — زر نصي بسيط (رابط)
/// زر نصي — "إعادة المحاولة"، "إلغاء"، "إعادة الإرسال"
struct DSTextButton: View {
    let title: String
    let icon: String?
    var color: Color = DS.Color.primary
    let action: () -> Void

    init(_ title: String, icon: String? = nil, color: Color = DS.Color.primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    private var debouncedAction: () -> Void {
        let key = "DSText_\(title)"
        let original = action
        return { if TapDebouncer.shared.canFire(key) { original() } }
    }

    var body: some View {
        Button(action: debouncedAction) {
            HStack(spacing: DS.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(DS.Font.icon(13, weight: .semibold))
                }
                Text(title).fontWeight(.semibold)
            }
            .font(DS.Font.callout)
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
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

// MARK: - Backwards Compatibility

struct UnifiedTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )
            .multilineTextAlignment(.leading)
    }
}

struct UnifiedButtonStyle: ButtonStyle {
    /// تعبئة تحت نص أبيض — primaryFill (كحلي، #2B5F90 في الداكن) لا primary
    var color: Color = DS.Color.primaryFill
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.headline)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(configuration.isPressed ? color.opacity(0.85) : color)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Production Components

/// صورة عضو دائرية — قابلة لإعادة الاستخدام (بدل 57 تكرار)
struct DSMemberAvatar: View {
    let name: String
    let avatarUrl: String?
    var size: CGFloat = 44
    var roleColor: Color = DS.Color.primary

    var body: some View {
        ZStack {
            if let urlStr = avatarUrl, let url = URL(string: urlStr) {
                Circle()
                    .fill(roleColor)
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

/// حالة فارغة موحدة — أيقونة + عنوان + زر اختياري (بدل 31 تكرار)
struct DSEmptyState: View {
    enum Style { case simple, halo }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    var style: Style = .simple
    /// أيقونة زر الإجراء — "arrow.clockwise" لإعادة المحاولة مثلاً
    var buttonIcon: String = "plus.circle.fill"
    /// لون الأيقونة — استخدم DS.Color.success لحالات "كل شيء تمام"
    var tint: SwiftUI.Color = DS.Color.primary

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            iconArea
            VStack(spacing: DS.Spacing.sm) {
                Text(title)
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xxxl)
                }
            }
            if let buttonTitle, let buttonAction {
                Button(action: buttonAction) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: buttonIcon)
                        Text(buttonTitle)
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(buttonBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(DSScaleButtonStyle())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// خلفية زر الإجراء والدائرة الصلبة في نمط halo — النص والأيقونة فوقها بيضاء، فاللون المتكيّف
    /// يأخذ تعبئته الثابتة (primaryFill، errorFill، successFill، warningFill) حتى يبقى الأبيض مقروءاً في الداكن
    private var solidFill: SwiftUI.Color {
        if tint == DS.Color.primary { return DS.Color.primaryFill }
        if tint == DS.Color.error   { return DS.Color.errorFill }
        if tint == DS.Color.success { return DS.Color.successFill }
        if tint == DS.Color.warning { return DS.Color.warningFill }
        return tint
    }

    private var buttonBackground: SwiftUI.Color { solidFill }

    @ViewBuilder
    private var iconArea: some View {
        switch style {
        case .simple:
            ZStack {
                Circle()
                    .fill(tint.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(DS.Font.icon(36, weight: .medium))
                    .foregroundColor(tint.opacity(0.5))
            }
        case .halo:
            ZStack {
                Circle()
                    .fill(tint.opacity(0.06))
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 95, height: 95)
                Circle()
                    .fill(solidFill)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(DS.Font.icon(28, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
        }
    }
}

/// حالة خطأ موحّدة مع رسالة + زر إعادة المحاولة. تُبنى فوق DSEmptyState.
struct DSErrorState: View {
    var message: String? = nil
    var retryAction: (() -> Void)? = nil

    var body: some View {
        DSEmptyState(
            icon: "exclamationmark.triangle.fill",
            title: L10n.t("تعذّر تحميل البيانات", "Couldn't load data"),
            subtitle: message ?? L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
            buttonTitle: retryAction != nil ? L10n.t("إعادة المحاولة", "Retry") : nil,
            buttonAction: retryAction,
            style: .simple,
            buttonIcon: "arrow.clockwise",
            tint: DS.Color.error
        )
    }
}

// MARK: - Skeleton Loading

/// عنصر هيكلي (skeleton) بتأثير لمعان متحرك — يحل محل الـ spinner للإحساس بسرعة أكبر
struct DSSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = DS.Radius.sm

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DS.Color.mutedBackground)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, SwiftUI.Color.white.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: phase * geo.size.width * 1.7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// دائرة هيكلية — للصور الرمزية أثناء التحميل
struct DSSkeletonCircle: View {
    var size: CGFloat = 56

    var body: some View {
        DSSkeleton(width: size, height: size, cornerRadius: size / 2)
    }
}

/// صف هيكلي جاهز: دائرة + سطرين نص — مناسب لقوائم الأعضاء/الأخبار
struct DSSkeletonRow: View {
    var avatarSize: CGFloat = 48

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSSkeletonCircle(size: avatarSize)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSSkeleton(width: 140, height: 14)
                DSSkeleton(width: 90, height: 11)
            }
            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
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
                    Button(confirm, action: onConfirm)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(disabled ? DS.Color.textTertiary : DS.Color.primary)
                        .disabled(disabled)
                }
            }
        }
    }
}
