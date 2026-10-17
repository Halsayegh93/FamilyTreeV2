import SwiftUI
import CoreGraphics

// MARK: - بوستات المناسبات — نموذج ١ (صورة دائرية فوق)، نموذج ٢ (صورة جانبية داخل إطار سداسي)،
// ونموذج ٣ (المعتمد: الآية بالمخطوطة فوق والصورة بقوس يطلع من بطاقة — بياناته في OccasionModel3View.swift)
//
// نسخة مطابقة لتعريفات الموقع: familytree-web/src/lib/occasions/templates.ts
// أي تعديل على النصوص أو الألوان أو المقاسات لازم ينعكس في الثنين.
// كل قالب له نسختين: مع صورة وبدون صورة (التهاني يختارها المستخدم؛ الوفاة قالبين؛ مشاركة العزاء بدون صورة).
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
    let size: OccasionSize

    /// مكان النشر → المقاس. الستوري بهوامش أمان ٢٥٠ بكسل فوق وتحت (انستقرام، واتساب، سناب، تيك توك).
    static var all: [OccasionPlacement] {
        [
            OccasionPlacement(id: "ig_post", title: L10n.t("انستقرام — منشور", "Instagram post"), size: .post),
            OccasionPlacement(id: "ig_story", title: L10n.t("انستقرام — ستوري", "Instagram story"), size: .story),
            OccasionPlacement(id: "wa_status", title: L10n.t("واتساب — حالة", "WhatsApp status"), size: .story),
            OccasionPlacement(id: "wa_chat", title: L10n.t("واتساب — محادثة", "WhatsApp chat"), size: .post),
            OccasionPlacement(id: "snap", title: L10n.t("سناب شات", "Snapchat"), size: .story),
            OccasionPlacement(id: "tiktok", title: L10n.t("تيك توك", "TikTok"), size: .story),
            OccasionPlacement(id: "x", title: "X", size: .post),
            OccasionPlacement(id: "fb_post", title: L10n.t("فيسبوك — منشور", "Facebook post"), size: .post),
            OccasionPlacement(id: "fb_story", title: L10n.t("فيسبوك — ستوري", "Facebook story"), size: .story),
            OccasionPlacement(id: "square", title: L10n.t("مربع — لكل المنصات", "Square — any platform"), size: .square),
        ]
    }
}

// MARK: النموذج

/// نموذج ١ (صورة دائرية فوق، اسم كبير، كبسولة متدرجة)، نموذج ٢ (صورة جانبية داخل إطار سداسي)،
/// أو نموذج ٣ (المعتمد منذ 17/10/2026: صورة بقوس فوق بطاقة رملية)
enum OccasionModel: String, CaseIterable, Identifiable {
    case m1, m2, m3

    var id: String { rawValue }

    /// النموذج المعتمد حالياً (تفتح عليه الشاشة) — نفس DEFAULT_MODEL في الموقع
    static let standard: OccasionModel = .m3

    var title: String {
        switch self {
        case .m1: return L10n.t("نموذج ١", "Design 1")
        case .m2: return L10n.t("نموذج ٢", "Design 2")
        case .m3: return L10n.t("نموذج ٣", "Design 3")
        }
    }

    /// شكل الصورة في النموذج
    var subtitle: String {
        switch self {
        case .m1: return L10n.t("صورة دائرية فوق", "Round photo on top")
        case .m2: return L10n.t("صورة سداسية جانبية", "Hexagon photo at the side")
        case .m3: return L10n.t("صورة بقوس فوق بطاقة", "Arched photo over a card")
        }
    }

    /// رسمة النموذج في الاختيار: دائرة (١)، سداسي (٢)، رأس مقوّس (٣) — مثل رسمات الموقع
    var symbol: String {
        switch self {
        case .m1: return "circle.circle"
        case .m2: return "hexagon"
        case .m3: return "rectangle.roundedtop"
        }
    }
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

/// نموذج ١ للتهاني (ملفات التصميم Wedding/Main/BabyGirl/Recovery/Graduation) — نفس M1_THEMES في الموقع
struct OccasionM1Theme {
    /// occasion-kit/m1/bg/<bg>.jpg (2160×2700)
    let bg: String
    /// occasion-kit/m1/frame/<frame>.png (800×800)
    let frame: String
    let root: Color
    let intro: Color
    /// تدرّج الكبسولة: linear-gradient(100deg, …)
    let pill: [Gradient.Stop]
    let pillText: Color
    /// ظل الكبسولة: 0 14px 28px (pillA1) و 0 2px 5px (pillA2)
    let pillShadow: Color
    let pillA1: Double
    let pillA2: Double
    /// عرض المخطوطة وإزاحتها من فوق في المنشور (النسخة مع صورة)
    let verseWidth: CGFloat
    let verseTop: CGFloat

    private static func stops(_ list: [(String, CGFloat)]) -> [Gradient.Stop] {
        list.map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) }
    }

    static let wed = OccasionM1Theme(
        bg: "wed", frame: "wed", root: Color(hex: "#FCF7EC"), intro: Color(hex: "#8A6A22"),
        pill: stops([("#B4862A", 0), ("#D8AF4C", 0.2), ("#F3DFA0", 0.45), ("#CDA040", 0.68), ("#E6C877", 0.86), ("#B4862A", 1)]),
        pillText: Color(hex: "#172536"), pillShadow: Color(red: 122 / 255, green: 94 / 255, blue: 34 / 255), pillA1: 0.34, pillA2: 0.3,
        verseWidth: 932, verseTop: 120)
    static let baby = OccasionM1Theme(
        bg: "baby", frame: "baby", root: Color(hex: "#F5FAFE"), intro: Color(hex: "#1F6FA3"),
        pill: stops([("#4F9FD3", 0), ("#74B9E6", 0.22), ("#C6E6F8", 0.46), ("#62ADDD", 0.68), ("#9FD2F0", 0.86), ("#4F9FD3", 1)]),
        pillText: Color(hex: "#172536"), pillShadow: Color(red: 23 / 255, green: 86 / 255, blue: 127 / 255), pillA1: 0.3, pillA2: 0.26,
        verseWidth: 972, verseTop: 120)
    static let girl = OccasionM1Theme(
        bg: "girl", frame: "girl", root: Color(hex: "#FDF5F3"), intro: Color(hex: "#9A4E5B"),
        pill: stops([("#B96F79", 0), ("#D4959C", 0.2), ("#F6D8D3", 0.45), ("#C9848D", 0.68), ("#EBBEBA", 0.86), ("#B96F79", 1)]),
        pillText: Color(hex: "#172536"), pillShadow: Color(red: 125 / 255, green: 63 / 255, blue: 73 / 255), pillA1: 0.3, pillA2: 0.26,
        verseWidth: 972, verseTop: 120)
    static let sick = OccasionM1Theme(
        bg: "sick", frame: "sick", root: Color(hex: "#F6FBF8"), intro: Color(hex: "#216C4F"),
        pill: stops([("#1F6548", 0), ("#2B7D5C", 0.22), ("#4A9E7C", 0.46), ("#236F51", 0.68), ("#3A8E6B", 0.86), ("#1F6548", 1)]),
        pillText: Color(hex: "#FFFFFF"), pillShadow: Color(red: 22 / 255, green: 76 / 255, blue: 56 / 255), pillA1: 0.34, pillA2: 0.28,
        verseWidth: 852, verseTop: 0)
    static let grad = OccasionM1Theme(
        bg: "grad", frame: "grad", root: Color(hex: "#FCF7EC"), intro: Color(hex: "#8A6A22"),
        pill: stops([("#0F1E36", 0), ("#1B3558", 0.22), ("#3A5F90", 0.46), ("#152B4C", 0.68), ("#274876", 0.86), ("#0F1E36", 1)]),
        pillText: Color(hex: "#F3DFA0"), pillShadow: Color(red: 11 / 255, green: 22 / 255, blue: 40 / 255), pillA1: 0.36, pillA2: 0.3,
        verseWidth: 692, verseTop: 0)
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
    // نفس المخطوطات على سطرين — للنسخ اللي بدون صورة (المساحة أكبر فالآية أكبر)
    static let wed2 = OccasionVerse(file: "wed-2", width: 932, height: 510, label: wed.label)
    static let babySky2 = OccasionVerse(file: "baby-sky-2", width: 812, height: 418, label: babySky.label)
    static let babyRose2 = OccasionVerse(file: "baby-rose-2", width: 812, height: 418, label: babyRose.label)
}

/// التهاني بدون صورة: المخطوطة (سطرين لما تتوفر) وعرضها وإزاحتها من فوق في المنشور لكل نموذج — من ملفات التصميم *-NP
struct OccasionNoPhotoSpec {
    let verse: OccasionVerse
    let m1Width: CGFloat
    let m1Top: CGFloat
    let m2Width: CGFloat
    let m2Top: CGFloat
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
    /// فيه صورة؟ (التهاني: النسخة الافتراضية — المستخدم يقدر يختار «بدون صورة»)
    let hasPhoto: Bool
    /// نموذج ١ للتهاني (بدونه = ما له تصميم نموذج ١)
    var m1: OccasionM1Theme? = nil
    /// التهاني بدون صورة
    var noPhoto: OccasionNoPhotoSpec? = nil

    /// له تصميم «نموذج ١»؟
    var hasModel1: Bool { kind == .happy ? m1 != nil : true }

    /// النموذج اللي ينرسم فعلاً (نموذج ٣ لكل القوالب؛ القالب اللي ما له نموذج ١ يرجع لنموذج ٢)
    func effectiveModel(_ model: OccasionModel) -> OccasionModel {
        if model == .m3 { return .m3 }
        return model == .m1 && hasModel1 ? .m1 : .m2
    }

    /// النماذج المتاحة لهذا القالب (لاختيار النموذج في الشاشة)
    var models: [OccasionModel] { OccasionModel.allCases.filter { $0 != .m1 || hasModel1 } }

    /// المستخدم يختار «مع صورة / بدون صورة»؟ (التهاني فقط — الوفاة قالبين، ومشاركة العزاء بدون صورة)
    var photoOptional: Bool { kind == .happy && noPhoto != nil }

    /// فيه صورة؟ withPhoto = اختيار المستخدم للتهاني (نفسه في النموذجين)
    func showsPhoto(_ withPhoto: Bool) -> Bool { photoOptional ? withPhoto : hasPhoto }

    /// الملفات المطلوبة من occasion-kit لهذا القالب والمقاس والنموذج والنسخة
    func assetPaths(for size: OccasionSize, model: OccasionModel = .m2, withPhoto: Bool = true) -> [String] {
        let photo = showsPhoto(withPhoto)
        var paths: [String] = []
        if effectiveModel(model) == .m3 {
            // نموذج ٣: المخطوطات (PNG — نسخة من SVG الموقع)، الختم النافر، والشعار الكريمي
            switch kind {
            case .happy:
                let v = OccasionM3.happyVerse(id)
                paths += ["m3/verse/\((photo ? v.photo : v.noPhoto).file).png", "m3/verse/\((photo ? v.echo : v.echoNP).file).png",
                          "m3/wm/emboss-sand.png"]
            case .death, .deathText:
                let v = kind == .death ? OccasionM3.deathPhotoVerse : OccasionM3.deathNoPhotoVerse
                paths += ["m3/verse/\(v.lead.file).png", "m3/verse/\(v.inna.file).png", "m3/verse/\(v.echo.file).png", "m3/wm/emboss-dark.png"]
            case .solace:
                let v = OccasionM3.solaceVerse
                paths += ["m3/verse/\(v.lead.file).png", "m3/verse/\(v.inna.file).png", "m3/verse/\(v.echo.file).png", "m3/wm/emboss-white.png"]
            }
            paths.append("logo/flat-cream.png")
            return paths
        }
        if effectiveModel(model) == .m1 {
            // نموذج ١: خلفية وحدة لكل قالب تغطي أي مقاس (occasion-kit/m1)
            switch kind {
            case .happy:
                if let m1 {
                    paths.append("m1/bg/\(m1.bg).jpg")
                    if photo { paths.append("m1/frame/\(m1.frame).png") }
                }
                if let v = photo ? verse : (noPhoto?.verse ?? verse) { paths.append("verse/\(v.file).png") }
                paths.append("logo/navy.png")
            case .death:
                paths += ["m1/bg/death.jpg", "m1/frame/white.png", "verse/sabr-lead.png", "verse/inna.png", "logo/white.png"]
            case .deathText:
                paths += ["m1/bg/death.jpg", "verse/sabr-lead.png", "verse/inna.png", "logo/white.png"]
            case .solace:
                paths += ["m1/bg/solace.jpg", "verse/sabr.png", "logo/navy.png"]
            }
            return paths
        }
        switch kind {
        case .happy:
            if let theme {
                paths.append("bg/\(theme.bg)-\(size.rawValue).jpg")
                if photo { paths.append("frame/\(theme.frame).png") }
            }
            if let v = photo ? verse : (noPhoto?.verse ?? verse) { paths.append("verse/\(v.file).png") }
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
}

/// النصوص نفسها تطلع من الاختيارات (OccasionChoices / OccasionCompose) — هنا شكل القالب فقط
extension OccasionTemplate {
    static var all: [OccasionTemplate] {
        [
            OccasionTemplate(id: "wedding", title: L10n.t("عقد قران", "Wedding"), icon: "heart.circle.fill", kind: .happy,
                             theme: .gold, verse: .wed, verseTopPost: 40, verseTopSquare: 10, hasPhoto: true, m1: .wed,
                             noPhoto: OccasionNoPhotoSpec(verse: .wed2, m1Width: 876, m1Top: 40, m2Width: 857, m2Top: 20)),
            OccasionTemplate(id: "newborn", title: L10n.t("قدوم مولود", "Newborn boy"), icon: "gift.fill", kind: .happy,
                             theme: .sky, verse: .babySky, verseTopPost: 60, verseTopSquare: 20, hasPhoto: true, m1: .baby,
                             noPhoto: OccasionNoPhotoSpec(verse: .babySky2, m1Width: 844, m1Top: 50, m2Width: 812, m2Top: 30)),
            OccasionTemplate(id: "newbornGirl", title: L10n.t("قدوم مولودة", "Newborn girl"), icon: "sparkles", kind: .happy,
                             theme: .rose, verse: .babyRose, verseTopPost: 60, verseTopSquare: 20, hasPhoto: true, m1: .girl,
                             noPhoto: OccasionNoPhotoSpec(verse: .babyRose2, m1Width: 844, m1Top: 50, m2Width: 812, m2Top: 30)),
            OccasionTemplate(id: "recovery", title: L10n.t("أجر وعافية", "Get well"), icon: "cross.case.fill", kind: .happy,
                             theme: .green, verse: .sick, verseScale: 0.86, hasPhoto: true, m1: .sick,
                             noPhoto: OccasionNoPhotoSpec(verse: .sick, m1Width: 784, m1Top: 50, m2Width: 784, m2Top: 30)),
            OccasionTemplate(id: "graduation", title: L10n.t("تهنئة تخرج", "Graduation"), icon: "graduationcap.fill", kind: .happy,
                             theme: .navy, verse: .grad, verseScale: 0.86, hasPhoto: true, m1: .grad,
                             noPhoto: OccasionNoPhotoSpec(verse: .grad, m1Width: 637, m1Top: 50, m2Width: 623, m2Top: 30)),
            OccasionTemplate(id: "death", title: L10n.t("إعلان وفاة — مع صورة", "Obituary — photo"), icon: "moon.stars.fill",
                             kind: .death, hasPhoto: true),
            OccasionTemplate(id: "deathText", title: L10n.t("إعلان وفاة — بدون صورة", "Obituary — details"), icon: "doc.text.fill",
                             kind: .deathText, hasPhoto: false),
            OccasionTemplate(id: "solace", title: L10n.t("مشاركة عزاء", "Condolences"), icon: "hands.sparkles.fill",
                             kind: .solace, verse: .sabr, hasPhoto: false),
        ]
    }
}

// MARK: سطور الأسماء (كل اسم سطر واحد)

extension OccasionTemplate {
    /// عناصر الأسماء لكل نموذج ومقاس ونسخة — المصدر الوحيد لأرقامها: البوست يرسم منها، والشاشة تختار منها
    /// أي صيغة اسم تدخل بسطر (OccasionNames). name = الاسم، to = العائلة في مشاركة العزاء،
    /// relation / rel1-3 = سطر قرابة فيه اسم شخص واحد (القوائم تلتف مثل التصميم). نفس nameSlots في الموقع.
    func nameSlots(model: OccasionModel, size: OccasionSize, withPhoto: Bool) -> [String: OccasionNameSlot] {
        let w = size.canvas.width
        let photo = showsPhoto(withPhoto)
        func slot(_ weight: OccasionKit.FontWeight, _ s: CGFloat, _ width: CGFloat, _ lineHeight: CGFloat) -> OccasionNameSlot {
            OccasionNameSlot(weight: weight, size: s, width: width, lineHeight: lineHeight)
        }
        if effectiveModel(model) == .m3 {
            // نموذج ٣ يُرسم بمقاس التصميم في كل المقاسات (المربع مصغّر كله) — فالأسطر نفسها. نفس nameSlots في الموقع
            let N = OccasionM3.Names.self
            switch kind {
            case .happy:
                let n = photo ? N.happy : N.happyNoPhoto
                return ["name": slot(.extrabold, n.size, n.width, n.lineHeight)]
            case .death, .deathText:
                let k: CGFloat = kind == .death ? 1 : OccasionM3.deathTextK
                let name = slot(.extrabold, (N.death.size * k).rounded(), N.death.width, N.death.lineHeight)
                let rel = slot(.semibold, (N.deathRelation.size * k).rounded(), N.deathRelation.width, N.deathRelation.lineHeight)
                if kind == .death { return ["name": name, "relation": rel] }
                return ["name": name, "rel1": rel, "rel2": rel, "rel3": rel]
            case .solace:
                return ["to": slot(.extrabold, N.solaceTo.size, N.solaceTo.width, N.solaceTo.lineHeight),
                        "name": slot(.extrabold, N.solaceName.size, N.solaceName.width, N.solaceName.lineHeight)]
            }
        }
        if effectiveModel(model) == .m1 {
            switch kind {
            case .happy:
                let L = photo ? OccasionM1Layout.happy(size) : OccasionM1Layout.happyNoPhoto(size)
                return ["name": slot(.extrabold, (photo ? 78 : 92) * L.k, w - 2 * L.pad.side, 1.24)]
            case .death:
                let L = OccasionM1Layout.deathPhoto(size)
                let cw = w - 2 * L.pad.side
                // الكبسولة: حشوة 40 من كل جهة + الإطار
                return ["name": slot(.extrabold, 74 * L.k, cw, 1.22), "relation": slot(.semibold, 26 * L.k, cw - 82 * L.k, 1.4)]
            case .deathText:
                let L = OccasionM1Layout.deathText(size)
                let cw = w - 2 * L.pad.side
                // داخل البطاقة: حشوة 44 من كل جهة + الإطار
                let rel = slot(.regular, 26 * L.k, cw - 92 * L.k, 1.55)
                return ["name": slot(.extrabold, 80 * L.k, cw, 1.22), "rel1": rel, "rel2": rel, "rel3": rel]
            case .solace:
                let L = OccasionM1Layout.solace(size)
                let cw = w - 2 * L.pad.side
                return ["to": slot(.extrabold, 82 * L.k, cw, 1.25), "name": slot(.extrabold, 72 * L.k, cw, 1.25)]
            }
        }
        switch kind {
        case .happy:
            if !photo {
                let L = HappyNoPhotoLayout.of(size)
                return ["name": slot(.extrabold, L.name, L.cw, 1.25)]
            }
            let L = HappyLayout.of(size)
            return ["name": slot(.extrabold, L.name, L.cw, 1.25)]
        case .death:
            let L = DeathLayout.of(size)
            // الكبسولة: النص بعرض relW ناقص الحشوة (40 من كل جهة)
            return ["name": slot(.extrabold, L.name, L.cw, 1.24), "relation": slot(.semibold, L.rel, L.relW - 80, 1.4)]
        case .deathText:
            let L = DeathTextLayout.of(size)
            let rowW = w - 2 * L.pad.side
            let rel = slot(.regular, L.relF, min(900, rowW), L.relLH)
            return ["name": slot(.extrabold, L.name, rowW, 1.22), "rel1": rel, "rel2": rel, "rel3": rel]
        case .solace:
            let L = SolaceLayout.of(size)
            let rowW = w - 2 * L.pad.side
            return ["to": slot(.extrabold, L.to, rowW, 1.25), "name": slot(.extrabold, L.name, rowW, 1.25)]
        }
    }
}

// MARK: مقاسات التخطيط لكل نوع × مقاس (نفس أرقام الموقع — أحجام الأسماء من ملفات التصميم)

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

    static func of(_ s: OccasionSize) -> DeathLayout {
        switch s {
        case .post:
            return DeathLayout(pad: OccasionInsets(top: 34, side: 48, bottom: 22), leadMul: 0.72, verseMul: 0.73, k: 0.8, pleft: -72, cw: 560,
                               l1: 32, l2: 38, name: 64, rel: 27, relW: 480, cols: 1, dua: 26, lh: 150, lineW: 250, divTop: 12, divBottom: 14)
        case .square:
            return DeathLayout(pad: OccasionInsets(top: 24, side: 48, bottom: 16), leadMul: 0.56, verseMul: 0.56, k: 0.66, pleft: -64, cw: 580,
                               l1: 28, l2: 33, name: 56, rel: 24, relW: 460, cols: 0.9, dua: 23, lh: 112, lineW: 220, divTop: 10, divBottom: 12)
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

/// نموذج ٢ — التهاني بدون صورة (M2-*-NP): الآية فوق، النص في الوسط، الشعار بين خطين
struct HappyNoPhotoLayout {
    let pad: OccasionInsets
    let cw: CGFloat, verseMul: CGFloat, topMul: CGFloat
    let intro: CGFloat, name: CGFloat, occ: CGFloat, sub: CGFloat, dua: CGFloat, duaW: CGFloat
    let lh: CGFloat, lineW: CGFloat, divTop: CGFloat, divBottom: CGFloat

    static func of(_ s: OccasionSize) -> HappyNoPhotoLayout {
        switch s {
        case .post:
            return HappyNoPhotoLayout(pad: OccasionInsets(top: 58, side: 44, bottom: 30), cw: 940, verseMul: 1, topMul: 1,
                                      intro: 38, name: 84, occ: 52, sub: 54, dua: 31, duaW: 760, lh: 184, lineW: 250, divTop: 24, divBottom: 20)
        case .square:
            return HappyNoPhotoLayout(pad: OccasionInsets(top: 34, side: 44, bottom: 22), cw: 940, verseMul: 0.72, topMul: 0.3,
                                      intro: 32, name: 70, occ: 44, sub: 46, dua: 26, duaW: 740, lh: 136, lineW: 230, divTop: 16, divBottom: 12)
        case .story:
            return HappyNoPhotoLayout(pad: OccasionInsets(top: 250, side: 44, bottom: 250), cw: 940, verseMul: 1.04, topMul: 0,
                                      intro: 40, name: 88, occ: 54, sub: 56, dua: 32, duaW: 780, lh: 200, lineW: 250, divTop: 26, divBottom: 22)
        }
    }
}

/// نموذج ١: كل الأرقام من ملفات التصميم مضروبة في k (المنشور k = 1 هو التصميم نفسه) — نفس M1_*_LAYOUT في الموقع
struct OccasionM1Layout {
    let pad: OccasionInsets
    let k: CGFloat
    /// نسبة إزاحة المخطوطة من فوق
    let verseTopMul: CGFloat

    private static func make(_ top: CGFloat, _ side: CGFloat, _ bottom: CGFloat, k: CGFloat, verseTopMul: CGFloat = 0) -> OccasionM1Layout {
        OccasionM1Layout(pad: OccasionInsets(top: top, side: side, bottom: bottom), k: k, verseTopMul: verseTopMul)
    }

    /// التهاني مع صورة (Wedding/Main/BabyGirl/Recovery/Graduation)
    static func happy(_ s: OccasionSize) -> OccasionM1Layout {
        switch s {
        case .post: return make(34, 50, 26, k: 1, verseTopMul: 1)
        case .story: return make(250, 50, 250, k: 1)
        case .square: return make(24, 50, 18, k: 0.78, verseTopMul: 0.15)
        }
    }

    /// التهاني بدون صورة (Wedding-NP …): الآية أكبر، الاسم ٩٢، الكبسولة ٤٠، الدعاء ٣٠
    static func happyNoPhoto(_ s: OccasionSize) -> OccasionM1Layout {
        switch s {
        case .post: return make(44, 56, 26, k: 1, verseTopMul: 1)
        case .story: return make(250, 56, 250, k: 1.04)
        case .square: return make(26, 56, 18, k: 0.76, verseTopMul: 0.25)
        }
    }

    /// إعلان وفاة مع صورة (Condolence-Photo): الحلقة البيضاء بين الآية والاسم
    static func deathPhoto(_ s: OccasionSize) -> OccasionM1Layout {
        switch s {
        case .post: return make(30, 56, 20, k: 1)
        case .story: return make(250, 56, 250, k: 1.04)
        case .square: return make(20, 56, 12, k: 0.76)
        }
    }

    /// إعلان وفاة بدون صورة (Condolence) بالتفاصيل كاملة
    static func deathText(_ s: OccasionSize) -> OccasionM1Layout {
        switch s {
        case .post: return make(34, 56, 20, k: 1)
        case .story: return make(250, 56, 250, k: 1.04)
        case .square: return make(22, 56, 12, k: 0.76)
        }
    }

    /// مشاركة عزاء (Solace) — التصميم نفسه ستوري 1080×1920
    static func solace(_ s: OccasionSize) -> OccasionM1Layout {
        switch s {
        case .story: return make(236, 60, 206, k: 1)
        case .post: return make(50, 60, 28, k: 0.88)
        case .square: return make(34, 60, 18, k: 0.75)
        }
    }
}
