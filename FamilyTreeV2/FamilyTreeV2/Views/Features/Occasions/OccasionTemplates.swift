import SwiftUI
import CoreGraphics

// MARK: - بوستات المناسبات — نموذج ١ (صورة دائرية فوق) ونموذج ٢ (صورة جانبية داخل إطار سداسي)
//
// نسخة مطابقة لتعريفات الموقع: familytree-web/src/lib/occasions/templates.ts
// أي تعديل على النصوص أو الألوان أو المقاسات لازم ينعكس في الثنين.
// ملاحظة: الألوان هنا ألوان «التصميم المعتمد» للبوست نفسه (مثل ملفات الصور)،
// وليست ألوان واجهة — لذلك ما تمر على DS.Color.

// MARK: المقاسات وأماكن النشر

enum OccasionSize: String, CaseIterable, Identifiable {
    case post, story, square

    var id: String { rawValue }

    /// المقاس بالبكسل (الرسم يتم بنقطة = بكسل، والتصدير بـ scale = 1)
    var canvas: CGSize {
        switch self {
        case .post: return CGSize(width: 1080, height: 1350)
        case .story: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        }
    }

    var title: String {
        switch self {
        case .post: return L10n.t("منشور", "Post")
        case .story: return L10n.t("ستوري", "Story")
        case .square: return L10n.t("مربع", "Square")
        }
    }

    var ratio: String {
        switch self {
        case .post: return "4:5"
        case .story: return "9:16"
        case .square: return "1:1"
        }
    }
}

struct OccasionPlacement: Identifiable, Hashable {
    let id: String
    let title: String
    /// اسم قصير للشريحة في شاشة النوع («إنستقرام منشور»، «ستوري»…)
    let short: String
    let size: OccasionSize

    /// مكان النشر → المقاس. الستوري بهوامش أمان ٢٥٠ بكسل فوق وتحت (انستقرام، واتساب، سناب، تيك توك).
    static var all: [OccasionPlacement] {
        [
            OccasionPlacement(id: "ig_post", title: L10n.t("انستقرام — منشور", "Instagram post"),
                              short: L10n.t("إنستقرام منشور", "IG post"), size: .post),
            OccasionPlacement(id: "ig_story", title: L10n.t("انستقرام — ستوري", "Instagram story"),
                              short: L10n.t("إنستقرام ستوري", "IG story"), size: .story),
            OccasionPlacement(id: "wa_status", title: L10n.t("واتساب — حالة", "WhatsApp status"),
                              short: L10n.t("واتساب حالة", "WA status"), size: .story),
            OccasionPlacement(id: "wa_chat", title: L10n.t("واتساب — محادثة", "WhatsApp chat"),
                              short: L10n.t("واتساب محادثة", "WA chat"), size: .post),
            OccasionPlacement(id: "snap", title: L10n.t("سناب شات", "Snapchat"),
                              short: L10n.t("سناب", "Snap"), size: .story),
            OccasionPlacement(id: "tiktok", title: L10n.t("تيك توك", "TikTok"),
                              short: L10n.t("تيك توك", "TikTok"), size: .story),
            OccasionPlacement(id: "x", title: "X", short: "X", size: .post),
            OccasionPlacement(id: "fb_post", title: L10n.t("فيسبوك — منشور", "Facebook post"),
                              short: L10n.t("فيسبوك منشور", "FB post"), size: .post),
            OccasionPlacement(id: "fb_story", title: L10n.t("فيسبوك — ستوري", "Facebook story"),
                              short: L10n.t("فيسبوك ستوري", "FB story"), size: .story),
            OccasionPlacement(id: "square", title: L10n.t("مربع — لكل المنصات", "Square — any platform"),
                              short: L10n.t("مربع", "Square"), size: .square),
        ]
    }
}

// MARK: النموذج

enum OccasionModel: String, CaseIterable, Identifiable {
    /// نموذج ١: صورة دائرية فوق، الاسم كبير، وسطر المناسبة داخل كبسولة متدرجة
    case m1
    /// نموذج ٢: صورة جانبية داخل إطار سداسي والنص بجانبها
    case m2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .m1: return L10n.t("نموذج ١", "Model 1")
        case .m2: return L10n.t("نموذج ٢", "Model 2")
        }
    }

    var subtitle: String {
        switch self {
        case .m1: return L10n.t("صورة دائرية فوق", "Round photo on top")
        case .m2: return L10n.t("صورة سداسية جانبية", "Hexagon photo beside")
        }
    }

    var icon: String {
        switch self {
        case .m1: return "circle.circle"
        case .m2: return "hexagon"
        }
    }
}

/// ألوان وملفات نموذج ١ للتهاني (من ملفات التصميم: Wedding/Main/BabyGirl/Recovery/Graduation)
struct OccasionM1Theme {
    /// إطار صورة «وفاة — مع صورة» بنموذج ١: الإطار الذهبي (نفس عقد القران) — يمشي مع الذهبي في وفاة نموذج ٢
    static let deathFrame = "wed"

    /// occasion-kit/m1/bg/<bg>.jpg (2160×2700)
    let bg: String
    /// occasion-kit/m1/frame/<frame>.png (800×800)
    let frame: String
    let root: Color
    let intro: Color
    /// تدرّج الكبسولة: linear-gradient(100deg, …)
    let pill: [Gradient.Stop]
    let pillText: Color
    /// لون ظل الكبسولة وشفافيته (box-shadow: 0 14px 28px a1, 0 2px 5px a2)
    let pillShadow: Color
    let pillShadowA1: Double
    let pillShadowA2: Double
    /// عرض المخطوطة وإزاحتها من فوق في المنشور
    let verseWidth: CGFloat
    let verseTop: CGFloat

    private static func stops(_ list: [(String, CGFloat)]) -> [Gradient.Stop] {
        list.map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) }
    }

    static let wed = OccasionM1Theme(
        bg: "wed", frame: "wed", root: Color(hex: "#FCF7EC"), intro: Color(hex: "#8A6A22"),
        pill: stops([("#B4862A", 0), ("#D8AF4C", 0.20), ("#F3DFA0", 0.45), ("#CDA040", 0.68), ("#E6C877", 0.86), ("#B4862A", 1)]),
        pillText: Color(hex: "#172536"), pillShadow: Color(red: 122 / 255, green: 94 / 255, blue: 34 / 255),
        pillShadowA1: 0.34, pillShadowA2: 0.30, verseWidth: 932, verseTop: 120)
    static let baby = OccasionM1Theme(
        bg: "baby", frame: "baby", root: Color(hex: "#F5FAFE"), intro: Color(hex: "#1F6FA3"),
        pill: stops([("#4F9FD3", 0), ("#74B9E6", 0.22), ("#C6E6F8", 0.46), ("#62ADDD", 0.68), ("#9FD2F0", 0.86), ("#4F9FD3", 1)]),
        pillText: Color(hex: "#172536"), pillShadow: Color(red: 23 / 255, green: 86 / 255, blue: 127 / 255),
        pillShadowA1: 0.30, pillShadowA2: 0.26, verseWidth: 972, verseTop: 120)
    static let girl = OccasionM1Theme(
        bg: "girl", frame: "girl", root: Color(hex: "#FDF5F3"), intro: Color(hex: "#9A4E5B"),
        pill: stops([("#B96F79", 0), ("#D4959C", 0.20), ("#F6D8D3", 0.45), ("#C9848D", 0.68), ("#EBBEBA", 0.86), ("#B96F79", 1)]),
        pillText: Color(hex: "#172536"), pillShadow: Color(red: 125 / 255, green: 63 / 255, blue: 73 / 255),
        pillShadowA1: 0.30, pillShadowA2: 0.26, verseWidth: 972, verseTop: 120)
    static let sick = OccasionM1Theme(
        bg: "sick", frame: "sick", root: Color(hex: "#F6FBF8"), intro: Color(hex: "#216C4F"),
        pill: stops([("#1F6548", 0), ("#2B7D5C", 0.22), ("#4A9E7C", 0.46), ("#236F51", 0.68), ("#3A8E6B", 0.86), ("#1F6548", 1)]),
        pillText: Color(hex: "#FFFFFF"), pillShadow: Color(red: 22 / 255, green: 76 / 255, blue: 56 / 255),
        pillShadowA1: 0.34, pillShadowA2: 0.28, verseWidth: 852, verseTop: 0)
    static let grad = OccasionM1Theme(
        bg: "grad", frame: "grad", root: Color(hex: "#FCF7EC"), intro: Color(hex: "#8A6A22"),
        pill: stops([("#0F1E36", 0), ("#1B3558", 0.22), ("#3A5F90", 0.46), ("#152B4C", 0.68), ("#274876", 0.86), ("#0F1E36", 1)]),
        pillText: Color(hex: "#F3DFA0"), pillShadow: Color(red: 11 / 255, green: 22 / 255, blue: 40 / 255),
        pillShadowA1: 0.36, pillShadowA2: 0.30, verseWidth: 692, verseTop: 0)
}

// MARK: الألوان

enum OccasionAvatar: String {
    case light, blue, rose, mint, dark

    var colors: (bg: Color, fg: Color) {
        switch self {
        case .light: return (Color(hex: "#F1EADB"), Color(hex: "#DCCFB4"))
        case .blue: return (Color(hex: "#E9F2F9"), Color(hex: "#C6DCEC"))
        case .rose: return (Color(hex: "#F7EAE7"), Color(hex: "#E6CBC7"))
        case .mint: return (Color(hex: "#EAF4EF"), Color(hex: "#C6E0D3"))
        case .dark: return (Color(hex: "#2B323B"), Color(hex: "#3F4955"))
        }
    }
}

struct OccasionTheme {
    let root: Color
    /// اسم الخلفية في occasion-kit/bg/<bg>-<size>.jpg
    let bg: String
    /// اسم الإطار في occasion-kit/frame/<frame>.png
    let frame: String
    let avatar: OccasionAvatar
    let intro: Color
    let acc: Color
    let sub: Color
    let line: Color
    let shadow: Color

    static let gold = OccasionTheme(root: Color(hex: "#FCF7EC"), bg: "wed", frame: "gold", avatar: .light,
                                    intro: Color(hex: "#8A6A22"), acc: Color(hex: "#9C7726"), sub: Color(hex: "#172536"),
                                    line: Color(hex: "#C9A24A"), shadow: Color(red: 122 / 255, green: 94 / 255, blue: 34 / 255))
    static let sky = OccasionTheme(root: Color(hex: "#F5FAFE"), bg: "baby", frame: "sky", avatar: .blue,
                                   intro: Color(hex: "#1F6FA3"), acc: Color(hex: "#1F6FA3"), sub: Color(hex: "#175288"),
                                   line: Color(hex: "#5FA8DA"), shadow: Color(red: 23 / 255, green: 86 / 255, blue: 127 / 255))
    static let rose = OccasionTheme(root: Color(hex: "#FDF5F3"), bg: "girl", frame: "rose", avatar: .rose,
                                    intro: Color(hex: "#9A4E5B"), acc: Color(hex: "#A45361"), sub: Color(hex: "#8C404E"),
                                    line: Color(hex: "#D0909A"), shadow: Color(red: 125 / 255, green: 63 / 255, blue: 73 / 255))
    static let green = OccasionTheme(root: Color(hex: "#F6FBF8"), bg: "sick", frame: "green", avatar: .mint,
                                     intro: Color(hex: "#216C4F"), acc: Color(hex: "#216C4F"), sub: Color(hex: "#164C38"),
                                     line: Color(hex: "#4A9E7C"), shadow: Color(red: 22 / 255, green: 76 / 255, blue: 56 / 255))
    static let navy = OccasionTheme(root: Color(hex: "#FCF7EC"), bg: "grad", frame: "navygold", avatar: .light,
                                    intro: Color(hex: "#8A6A22"), acc: Color(hex: "#1B3558"), sub: Color(hex: "#8A6A22"),
                                    line: Color(hex: "#C9A24A"), shadow: Color(red: 11 / 255, green: 22 / 255, blue: 40 / 255))
}

/// إعلان الوفاة: ذهبي فاتح (شامبين) على الأسود
enum OccasionDeathPalette {
    static let root = Color(hex: "#14171C")
    static let gold = Color(hex: "#E9D5A6")
    static let goldLine = Color(red: 233 / 255, green: 213 / 255, blue: 166 / 255).opacity(0.75)
    static let grey = Color(hex: "#C9CED5")
    static let soft = Color(hex: "#D5D9DE")
    static let dua = Color(hex: "#C5CAD1")
}

// MARK: المخطوطات (المقاس الطبيعي عند scale = 1)

struct OccasionVerse {
    let file: String
    let width: CGFloat
    let height: CGFloat
    let label: String

    static let wed = OccasionVerse(file: "wed", width: 932, height: 241, label: "وَمِنْ آيَاتِهِ أَنْ خَلَقَ لَكُم مِّنْ أَنفُسِكُمْ أَزْوَاجًا لِّتَسْكُنُوا إِلَيْهَا وَجَعَلَ بَيْنَكُم مَّوَدَّةً وَرَحْمَةً")
    static let babySky = OccasionVerse(file: "baby-sky", width: 972, height: 171, label: "وَالَّذِينَ يَقُولُونَ رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا")
    static let babyRose = OccasionVerse(file: "baby-rose", width: 972, height: 171, label: "وَالَّذِينَ يَقُولُونَ رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا")
    static let sick = OccasionVerse(file: "sick", width: 852, height: 382, label: "وَإِذَا مَرِضْتُ فَهُوَ يَشْفِينِ")
    static let grad = OccasionVerse(file: "grad", width: 692, height: 400, label: "وَقُل رَّبِّ زِدْنِي عِلْمًا")
    static let sabrLead = OccasionVerse(file: "sabr-lead", width: 652, height: 205, label: "وَبَشِّرِ الصَّابِرِينَ الَّذِينَ إِذَا أَصَابَتْهُم مُّصِيبَةٌ قَالُوا")
    static let inna = OccasionVerse(file: "inna", width: 872, height: 289, label: "إِنَّا لِلَّهِ وَإِنَّا إِلَيْهِ رَاجِعُونَ")
    static let sabr = OccasionVerse(file: "sabr", width: 952, height: 210, label: "وَبَشِّرِ الصَّابِرِينَ الَّذِينَ إِذَا أَصَابَتْهُم مُّصِيبَةٌ قَالُوا إِنَّا لِلَّهِ وَإِنَّا إِلَيْهِ رَاجِعُونَ")
}

// MARK: القوالب

enum OccasionKind {
    case happy, death, deathText, solace
}

enum OccasionGender: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? L10n.t("مذكّر", "Masculine") : L10n.t("مؤنّث", "Feminine") }
}

struct OccasionTemplate: Identifiable {
    let id: String
    let title: String
    /// SF Symbol
    let icon: String
    let kind: OccasionKind
    var theme: OccasionTheme? = nil
    var verse: OccasionVerse? = nil
    /// إزاحة المخطوطة من فوق (منشور، مربع) — الستوري صفر لأن هامش الأمان يكفي
    var verseTopPost: CGFloat = 0
    var verseTopSquare: CGFloat = 0
    var verseScale: CGFloat = 1
    /// نموذج ٢: فيه صورة؟
    let hasPhoto: Bool
    /// نموذج ١ للتهاني (nil = ما له تصميم نموذج ١)
    var m1Theme: OccasionM1Theme? = nil

    /// له تصميم «نموذج ١»؟ — نموذج ١ للوفاة (Condolence): «بدون صورة» = التصميم كما هو، و«مع صورة» = نفسه
    /// بصورة دائرية بإطار نموذج ١ الذهبي فوق الاسم (طلب المالك ٢٠٢٦-١٠-١٣ «النموذج الأول بدون صورة» ثم «وين نموذج الأول مع صورة؟»)
    var hasM1: Bool {
        switch kind {
        case .happy: return m1Theme != nil
        case .death, .deathText, .solace: return true
        }
    }

    /// النموذج اللي ينرسم فعلاً (القالب اللي ما له نموذج ١ يرجع لنموذج ٢)
    func effectiveModel(_ model: OccasionModel) -> OccasionModel {
        model == .m1 && hasM1 ? .m1 : .m2
    }

    /// فيه صورة بهذا النموذج؟ (نموذج ١: التهاني و«وفاة — مع صورة»؛ العزاء بدون صورة)
    func hasPhoto(_ model: OccasionModel) -> Bool {
        effectiveModel(model) == .m1 ? (kind == .happy || kind == .death) : hasPhoto
    }

    /// الملفات المطلوبة من occasion-kit لهذا القالب والنموذج والمقاس
    func assetPaths(for size: OccasionSize, model: OccasionModel = .m2) -> [String] {
        if effectiveModel(model) == .m1 { return m1AssetPaths }
        var paths: [String] = []
        switch kind {
        case .happy:
            if let theme {
                paths += ["bg/\(theme.bg)-\(size.rawValue).jpg", "frame/\(theme.frame).png"]
            }
            if let verse { paths.append("verse/\(verse.file).png") }
            paths.append("logo/navy.png")
        case .death:
            paths += ["bg/death-\(size.rawValue).jpg", "frame/goldnight.png", "verse/sabr-lead.png", "verse/inna.png", "logo/white.png"]
        case .deathText:
            paths += ["bg/death-\(size.rawValue).jpg", "verse/sabr-lead.png", "verse/inna.png", "logo/white.png"]
        case .solace:
            paths += ["bg/solace-\(size.rawValue).jpg", "verse/sabr.png", "logo/navy.png"]
        }
        return paths
    }

    /// نموذج ١: خلفية وحدة لكل قالب (مقاس المنشور؛ الستوري والمربع يكبّرونها لين تغطي)
    private var m1AssetPaths: [String] {
        switch kind {
        case .happy:
            guard let th = m1Theme else { return [] }
            var paths = ["m1/bg/\(th.bg).jpg", "m1/frame/\(th.frame).png"]
            if let verse { paths.append("verse/\(verse.file).png") }
            paths.append("logo/navy.png")
            return paths
        case .deathText:
            return ["m1/bg/death.jpg", "verse/sabr-lead.png", "verse/inna.png", "logo/white.png"]
        case .death:
            return ["m1/bg/death.jpg", "m1/frame/\(OccasionM1Theme.deathFrame).png", "verse/sabr-lead.png", "verse/inna.png", "logo/white.png"]
        case .solace:
            return ["m1/bg/solace.jpg", "verse/sabr.png", "logo/navy.png"]
        }
    }
}

/// النصوص نفسها تطلع من الاختيارات (OccasionChoices / OccasionCompose) — هنا شكل القالب فقط
extension OccasionTemplate {
    static var all: [OccasionTemplate] {
        [
            OccasionTemplate(id: "wedding", title: L10n.t("عقد قران", "Wedding"), icon: "heart.circle.fill", kind: .happy,
                             theme: .gold, verse: .wed, verseTopPost: 40, verseTopSquare: 10, hasPhoto: true, m1Theme: .wed),
            OccasionTemplate(id: "newborn", title: L10n.t("قدوم مولود", "Newborn boy"), icon: "gift.fill", kind: .happy,
                             theme: .sky, verse: .babySky, verseTopPost: 60, verseTopSquare: 20, hasPhoto: true, m1Theme: .baby),
            OccasionTemplate(id: "newbornGirl", title: L10n.t("قدوم مولودة", "Newborn girl"), icon: "sparkles", kind: .happy,
                             theme: .rose, verse: .babyRose, verseTopPost: 60, verseTopSquare: 20, hasPhoto: true, m1Theme: .girl),
            OccasionTemplate(id: "recovery", title: L10n.t("أجر وعافية", "Get well"), icon: "cross.case.fill", kind: .happy,
                             theme: .green, verse: .sick, verseScale: 0.86, hasPhoto: true, m1Theme: .sick),
            OccasionTemplate(id: "graduation", title: L10n.t("تهنئة تخرج", "Graduation"), icon: "graduationcap.fill", kind: .happy,
                             theme: .navy, verse: .grad, verseScale: 0.86, hasPhoto: true, m1Theme: .grad),
            OccasionTemplate(id: "death", title: L10n.t("إعلان وفاة — مع صورة", "Obituary — photo"), icon: "moon.stars.fill",
                             kind: .death, hasPhoto: true),
            OccasionTemplate(id: "deathText", title: L10n.t("إعلان وفاة — بدون صورة", "Obituary — details"), icon: "doc.text.fill",
                             kind: .deathText, hasPhoto: false),
            OccasionTemplate(id: "solace", title: L10n.t("مشاركة عزاء", "Condolences"), icon: "hands.sparkles.fill",
                             kind: .solace, verse: .sabr, hasPhoto: false),
        ]
    }
}

// MARK: قائمة الأنواع (أول شاشة) وعنوان شاشة كل نوع

/// لون مربع النوع في القائمة — من ألوان التصميم نفسه
struct OccasionTileStyle {
    let fill: Color
    let ring: Color
    let symbol: Color
}

extension OccasionTemplate {
    /// اسم النوع في مربع القائمة
    var tileTitle: String {
        switch id {
        case "wedding": return L10n.t("زواج / عقد قران", "Wedding")
        case "newborn": return L10n.t("مولود", "Newborn boy")
        case "newbornGirl": return L10n.t("مولودة", "Newborn girl")
        case "graduation": return L10n.t("تخرّج", "Graduation")
        case "death": return L10n.t("وفاة — مع صورة", "Obituary — photo")
        case "deathText": return L10n.t("وفاة — بدون صورة", "Obituary — details")
        default: return title
        }
    }

    /// عنوان شاشة النوع
    var screenTitle: String {
        switch id {
        case "wedding": return L10n.t("تهنئة عقد قران", "Wedding congratulations")
        case "newborn": return L10n.t("تهنئة بمولود", "Newborn boy congratulations")
        case "newbornGirl": return L10n.t("تهنئة بمولودة", "Newborn girl congratulations")
        case "graduation": return L10n.t("تهنئة تخرّج", "Graduation congratulations")
        case "death": return L10n.t("إعلان وفاة — مع صورة", "Obituary — with photo")
        case "deathText": return L10n.t("إعلان وفاة — بدون صورة", "Obituary — without photo")
        default: return title
        }
    }

    /// وصف قصير تحت اسم النوع
    var subtitle: String {
        switch id {
        case "wedding": return L10n.t("تهنئة بالزواج أو عقد القران", "Marriage or wedding contract")
        case "newborn": return L10n.t("تهنئة بقدوم مولود", "A baby boy arrived")
        case "newbornGirl": return L10n.t("تهنئة بقدوم مولودة", "A baby girl arrived")
        case "recovery": return L10n.t("دعاء بالشفاء والسلامة", "Get-well wishes")
        case "graduation": return L10n.t("تهنئة بالتخرج أو الشهادة", "Graduation or degree")
        case "death": return L10n.t("إعلان وفاة بصورة الفقيد", "Obituary with a photo")
        case "deathText": return L10n.t("القرابة والتشييع والعزاء كاملة", "Relatives, funeral and condolences")
        default: return L10n.t("تعزية لعائلة أخرى", "Condolences to another family")
        }
    }

    var tileStyle: OccasionTileStyle {
        switch kind {
        case .happy:
            return OccasionTileStyle(fill: theme?.acc ?? Color(hex: "#9C7726"), ring: .clear, symbol: .white)
        case .death, .deathText:
            return OccasionTileStyle(fill: OccasionDeathPalette.root, ring: OccasionDeathPalette.gold.opacity(0.7),
                                     symbol: OccasionDeathPalette.gold)
        case .solace:
            return OccasionTileStyle(fill: Color(hex: "#4A5560"), ring: .clear, symbol: .white)
        }
    }
}

// MARK: مقاسات التخطيط لكل نوع × مقاس (نفس أرقام الموقع)

struct OccasionInsets {
    let top: CGFloat
    let side: CGFloat
    let bottom: CGFloat
}

struct HappyLayout {
    let pad: OccasionInsets
    let verseMul: CGFloat, k: CGFloat, pleft: CGFloat, cw: CGFloat
    let intro: CGFloat, name: CGFloat, occ: CGFloat, sub: CGFloat, dua: CGFloat, duaW: CGFloat
    let lh: CGFloat, lineW: CGFloat, divTop: CGFloat, divBottom: CGFloat

    static func of(_ s: OccasionSize) -> HappyLayout {
        switch s {
        case .post:
            return HappyLayout(pad: OccasionInsets(top: 52, side: 44, bottom: 30), verseMul: 1, k: 1, pleft: -96, cw: 540,
                               intro: 34, name: 56, occ: 44, sub: 46, dua: 28, duaW: 500, lh: 184, lineW: 250, divTop: 22, divBottom: 18)
        case .square:
            return HappyLayout(pad: OccasionInsets(top: 34, side: 44, bottom: 22), verseMul: 0.78, k: 0.8, pleft: -70, cw: 560,
                               intro: 31, name: 51, occ: 40, sub: 42, dua: 25, duaW: 500, lh: 138, lineW: 230, divTop: 16, divBottom: 12)
        case .story:
            return HappyLayout(pad: OccasionInsets(top: 250, side: 44, bottom: 250), verseMul: 1.04, k: 1, pleft: -96, cw: 540,
                               intro: 36, name: 59, occ: 46, sub: 48, dua: 29, duaW: 500, lh: 200, lineW: 250, divTop: 24, divBottom: 20)
        }
    }
}

struct DeathLayout {
    let pad: OccasionInsets
    let leadMul: CGFloat, verseMul: CGFloat, k: CGFloat, pleft: CGFloat, cw: CGFloat
    let l1: CGFloat, l2: CGFloat, name: CGFloat, rel: CGFloat, relW: CGFloat, cols: CGFloat, dua: CGFloat
    let lh: CGFloat, lineW: CGFloat, divTop: CGFloat, divBottom: CGFloat
    var duaLH: CGFloat = 1.65

    static func of(_ s: OccasionSize) -> DeathLayout {
        switch s {
        case .post:
            return DeathLayout(pad: OccasionInsets(top: 34, side: 48, bottom: 22), leadMul: 0.72, verseMul: 0.73, k: 0.8, pleft: -72, cw: 560,
                               l1: 32, l2: 38, name: 64, rel: 27, relW: 480, cols: 1, dua: 26, lh: 150, lineW: 250, divTop: 12, divBottom: 14)
        case .square:
            return DeathLayout(pad: OccasionInsets(top: 24, side: 48, bottom: 16), leadMul: 0.56, verseMul: 0.56, k: 0.66, pleft: -64, cw: 580,
                               l1: 28, l2: 33, name: 56, rel: 24, relW: 460, cols: 0.9, dua: 23, lh: 112, lineW: 220, divTop: 10, divBottom: 12, duaLH: 1.6)
        case .story:
            return DeathLayout(pad: OccasionInsets(top: 250, side: 48, bottom: 250), leadMul: 0.78, verseMul: 0.8, k: 0.9, pleft: -78, cw: 560,
                               l1: 34, l2: 40, name: 68, rel: 28, relW: 480, cols: 1.04, dua: 27, lh: 170, lineW: 250, divTop: 14, divBottom: 16)
        }
    }
}

struct DeathTextLayout {
    let pad: OccasionInsets
    let leadMul: CGFloat, verseMul: CGFloat
    let l1: CGFloat, l2: CGFloat, name: CGFloat, relF: CGFloat, relLH: CGFloat, fun: CGFloat, con: CGFloat
    let cols: CGFloat, dua: CGFloat, lh: CGFloat, lineW: CGFloat, divBottom: CGFloat

    static func of(_ s: OccasionSize) -> DeathTextLayout {
        switch s {
        case .post:
            return DeathTextLayout(pad: OccasionInsets(top: 30, side: 48, bottom: 20), leadMul: 0.64, verseMul: 0.64,
                                   l1: 32, l2: 38, name: 84, relF: 26, relLH: 1.55, fun: 30, con: 28, cols: 1, dua: 25, lh: 140, lineW: 250, divBottom: 10)
        case .square:
            return DeathTextLayout(pad: OccasionInsets(top: 22, side: 48, bottom: 14), leadMul: 0.5, verseMul: 0.52,
                                   l1: 26, l2: 30, name: 68, relF: 22, relLH: 1.45, fun: 26, con: 24, cols: 0.85, dua: 22, lh: 100, lineW: 220, divBottom: 8)
        case .story:
            return DeathTextLayout(pad: OccasionInsets(top: 250, side: 48, bottom: 250), leadMul: 0.72, verseMul: 0.74,
                                   l1: 34, l2: 40, name: 89, relF: 28, relLH: 1.6, fun: 32, con: 30, cols: 1.04, dua: 27, lh: 160, lineW: 250, divBottom: 12)
        }
    }
}

struct SolaceLayout {
    let pad: OccasionInsets
    let verseMul: CGFloat, title: CGFloat, from: CGFloat, sub: CGFloat, to: CGFloat, lead: CGFloat, name: CGFloat, dua: CGFloat
    let lh: CGFloat, lineW: CGFloat

    static func of(_ s: OccasionSize) -> SolaceLayout {
        switch s {
        case .post:
            return SolaceLayout(pad: OccasionInsets(top: 50, side: 48, bottom: 28), verseMul: 0.9, title: 84, from: 42, sub: 30, to: 72,
                                lead: 30, name: 66, dua: 28, lh: 170, lineW: 250)
        case .square:
            return SolaceLayout(pad: OccasionInsets(top: 34, side: 48, bottom: 18), verseMul: 0.8, title: 72, from: 38, sub: 28, to: 62,
                                lead: 28, name: 57, dua: 25, lh: 128, lineW: 230)
        case .story:
            return SolaceLayout(pad: OccasionInsets(top: 224, side: 48, bottom: 196), verseMul: 1, title: 96, from: 48, sub: 34, to: 82,
                                lead: 34, name: 76, dua: 31, lh: 230, lineW: 250)
        }
    }
}

/// نموذج ١: كل الأرقام من ملفات التصميم مضروبة في k (المنشور k = 1 هو التصميم نفسه)
struct M1Layout {
    let pad: OccasionInsets
    let k: CGFloat
    /// نسبة إزاحة المخطوطة من فوق (التصميم ١٢٠ للعقد والمولود)
    let verseTopMul: CGFloat

    /// التهاني (Wedding/Main/BabyGirl/Recovery/Graduation)
    static func happy(_ s: OccasionSize) -> M1Layout {
        switch s {
        case .post: return M1Layout(pad: OccasionInsets(top: 34, side: 50, bottom: 26), k: 1, verseTopMul: 1)
        case .story: return M1Layout(pad: OccasionInsets(top: 250, side: 50, bottom: 250), k: 1, verseTopMul: 0)
        case .square: return M1Layout(pad: OccasionInsets(top: 24, side: 50, bottom: 18), k: 0.78, verseTopMul: 0.15)
        }
    }

    /// إعلان وفاة (Condolence)
    static func death(_ s: OccasionSize) -> M1Layout {
        switch s {
        case .post: return M1Layout(pad: OccasionInsets(top: 40, side: 56, bottom: 24), k: 1, verseTopMul: 0)
        case .story: return M1Layout(pad: OccasionInsets(top: 250, side: 56, bottom: 250), k: 1, verseTopMul: 0)
        case .square: return M1Layout(pad: OccasionInsets(top: 26, side: 56, bottom: 16), k: 0.8, verseTopMul: 0)
        }
    }

    /// مشاركة عزاء (Solace) — التصميم نفسه ستوري 1080×1920
    static func solace(_ s: OccasionSize) -> M1Layout {
        switch s {
        case .story: return M1Layout(pad: OccasionInsets(top: 236, side: 60, bottom: 206), k: 1, verseTopMul: 0)
        case .post: return M1Layout(pad: OccasionInsets(top: 50, side: 60, bottom: 28), k: 0.88, verseTopMul: 0)
        case .square: return M1Layout(pad: OccasionInsets(top: 34, side: 60, bottom: 18), k: 0.75, verseTopMul: 0)
        }
    }
}

// MARK: سطور الأسماء (كل اسم سطر واحد)

/// مواصفات سطر اسم في البوست: الوزن، حجم التصميم، العرض المتاح، ارتفاع السطر
struct OccasionNameSlot {
    let weight: OccasionKit.FontWeight
    let size: CGFloat
    let width: CGFloat
    let lineHeight: CGFloat

    init(_ weight: OccasionKit.FontWeight, _ size: CGFloat, _ width: CGFloat, _ lineHeight: CGFloat) {
        self.weight = weight
        self.size = size
        self.width = width
        self.lineHeight = lineHeight
    }
}

extension OccasionTemplate {
    /// عناصر الأسماء لكل نموذج ومقاس — المصدر الوحيد لأرقامها: البوست يرسم منها، والشاشة تحسب منها
    /// أي صيغة اسم تدخل بسطر (OccasionNames). name = الاسم، to = العائلة في مشاركة العزاء،
    /// relation / relation2 (سطرا كبسولة القرابة) و rel1-3 = سطر قرابة فيه اسم شخص واحد (القوائم تلتف مثل التصميم).
    func nameSlots(model: OccasionModel, size s: OccasionSize) -> [String: OccasionNameSlot] {
        let w = s.canvas.width
        if effectiveModel(model) == .m1 {
            switch kind {
            case .happy:
                let L = M1Layout.happy(s)
                return ["name": OccasionNameSlot(.extrabold, 78 * L.k, w - 2 * L.pad.side, 1.24)]
            case .death, .deathText:
                let L = M1Layout.death(s)
                let cw = w - 2 * L.pad.side
                // الكبسولة: حشوة 46 من كل جهة + الإطار — سطور القرابة (مع صورة: relation/relation2، بدون: rel1-3)
                let rel = OccasionNameSlot(.semibold, 30 * L.k, cw - 94 * L.k, 1.4)
                let keys = kind == .death ? ["relation", "relation2"] : ["rel1", "rel2", "rel3"]
                var slots = ["name": OccasionNameSlot(.extrabold, 88 * L.k, cw, 1.22)]
                for key in keys { slots[key] = rel }
                return slots
            case .solace:
                let L = M1Layout.solace(s)
                let cw = w - 2 * L.pad.side
                return ["to": OccasionNameSlot(.extrabold, 82 * L.k, cw, 1.25),
                        "name": OccasionNameSlot(.extrabold, 72 * L.k, cw, 1.25)]
            }
        }
        switch kind {
        case .happy:
            let L = HappyLayout.of(s)
            return ["name": OccasionNameSlot(.extrabold, L.name, L.cw, 1.25)]
        case .death:
            let L = DeathLayout.of(s)
            let rel = OccasionNameSlot(.semibold, L.rel, L.relW, 1.4)
            return ["name": OccasionNameSlot(.extrabold, L.name, L.cw, 1.24), "relation": rel, "relation2": rel]
        case .deathText:
            let L = DeathTextLayout.of(s)
            let rowW = w - 2 * L.pad.side
            let rel = OccasionNameSlot(.regular, L.relF, min(900, rowW), L.relLH)
            return ["name": OccasionNameSlot(.extrabold, L.name, rowW, 1.22), "rel1": rel, "rel2": rel, "rel3": rel]
        case .solace:
            let L = SolaceLayout.of(s)
            let rowW = w - 2 * L.pad.side
            return ["to": OccasionNameSlot(.extrabold, L.to, rowW, 1.25),
                    "name": OccasionNameSlot(.extrabold, L.name, rowW, 1.25)]
        }
    }
}
