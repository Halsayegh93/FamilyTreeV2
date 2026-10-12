import SwiftUI
import CoreGraphics

// MARK: - بوستات المناسبات — نموذج ٢ (صورة جانبية داخل إطار سداسي)
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
    let hasPhoto: Bool

    /// الملفات المطلوبة من occasion-kit لهذا القالب والمقاس
    func assetPaths(for size: OccasionSize) -> [String] {
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
}

/// النصوص نفسها تطلع من الاختيارات (OccasionChoices / OccasionCompose) — هنا شكل القالب فقط
extension OccasionTemplate {
    static var all: [OccasionTemplate] {
        [
            OccasionTemplate(id: "wedding", title: L10n.t("عقد قران", "Wedding"), icon: "heart.circle.fill", kind: .happy,
                             theme: .gold, verse: .wed, verseTopPost: 40, verseTopSquare: 10, hasPhoto: true),
            OccasionTemplate(id: "newborn", title: L10n.t("قدوم مولود", "Newborn boy"), icon: "gift.fill", kind: .happy,
                             theme: .sky, verse: .babySky, verseTopPost: 60, verseTopSquare: 20, hasPhoto: true),
            OccasionTemplate(id: "newbornGirl", title: L10n.t("قدوم مولودة", "Newborn girl"), icon: "sparkles", kind: .happy,
                             theme: .rose, verse: .babyRose, verseTopPost: 60, verseTopSquare: 20, hasPhoto: true),
            OccasionTemplate(id: "recovery", title: L10n.t("أجر وعافية", "Get well"), icon: "cross.case.fill", kind: .happy,
                             theme: .green, verse: .sick, verseScale: 0.86, hasPhoto: true),
            OccasionTemplate(id: "graduation", title: L10n.t("تهنئة تخرج", "Graduation"), icon: "graduationcap.fill", kind: .happy,
                             theme: .navy, verse: .grad, verseScale: 0.86, hasPhoto: true),
            OccasionTemplate(id: "death", title: L10n.t("إعلان وفاة — مع صورة", "Obituary — photo"), icon: "moon.stars.fill",
                             kind: .death, hasPhoto: true),
            OccasionTemplate(id: "deathText", title: L10n.t("إعلان وفاة — بدون صورة", "Obituary — details"), icon: "doc.text.fill",
                             kind: .deathText, hasPhoto: false),
            OccasionTemplate(id: "solace", title: L10n.t("مشاركة عزاء", "Condolences"), icon: "hands.sparkles.fill",
                             kind: .solace, verse: .sabr, hasPhoto: false),
        ]
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
                               intro: 34, name: 50, occ: 44, sub: 46, dua: 28, duaW: 500, lh: 184, lineW: 250, divTop: 22, divBottom: 18)
        case .square:
            return HappyLayout(pad: OccasionInsets(top: 34, side: 44, bottom: 22), verseMul: 0.78, k: 0.8, pleft: -70, cw: 560,
                               intro: 31, name: 46, occ: 40, sub: 42, dua: 25, duaW: 500, lh: 138, lineW: 230, divTop: 16, divBottom: 12)
        case .story:
            return HappyLayout(pad: OccasionInsets(top: 250, side: 44, bottom: 250), verseMul: 1.04, k: 1, pleft: -96, cw: 540,
                               intro: 36, name: 54, occ: 46, sub: 48, dua: 29, duaW: 500, lh: 200, lineW: 250, divTop: 24, divBottom: 20)
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
                               l1: 32, l2: 38, name: 58, rel: 27, relW: 480, cols: 1, dua: 26, lh: 150, lineW: 250, divTop: 12, divBottom: 14)
        case .square:
            return DeathLayout(pad: OccasionInsets(top: 24, side: 48, bottom: 16), leadMul: 0.56, verseMul: 0.56, k: 0.66, pleft: -64, cw: 580,
                               l1: 28, l2: 33, name: 50, rel: 24, relW: 460, cols: 0.9, dua: 23, lh: 112, lineW: 220, divTop: 10, divBottom: 12)
        case .story:
            return DeathLayout(pad: OccasionInsets(top: 250, side: 48, bottom: 250), leadMul: 0.78, verseMul: 0.8, k: 0.9, pleft: -78, cw: 560,
                               l1: 34, l2: 40, name: 60, rel: 28, relW: 480, cols: 1.04, dua: 27, lh: 170, lineW: 250, divTop: 14, divBottom: 16)
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
                                   l1: 32, l2: 38, name: 74, relF: 26, relLH: 1.55, fun: 30, con: 28, cols: 1, dua: 25, lh: 140, lineW: 250, divBottom: 10)
        case .square:
            return DeathTextLayout(pad: OccasionInsets(top: 22, side: 48, bottom: 14), leadMul: 0.5, verseMul: 0.52,
                                   l1: 26, l2: 30, name: 56, relF: 22, relLH: 1.45, fun: 26, con: 24, cols: 0.85, dua: 22, lh: 100, lineW: 220, divBottom: 8)
        case .story:
            return DeathTextLayout(pad: OccasionInsets(top: 250, side: 48, bottom: 250), leadMul: 0.72, verseMul: 0.74,
                                   l1: 34, l2: 40, name: 80, relF: 28, relLH: 1.6, fun: 32, con: 30, cols: 1.04, dua: 27, lh: 160, lineW: 250, divBottom: 12)
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
            return SolaceLayout(pad: OccasionInsets(top: 50, side: 48, bottom: 28), verseMul: 0.9, title: 84, from: 42, sub: 30, to: 68,
                                lead: 30, name: 62, dua: 28, lh: 170, lineW: 250)
        case .square:
            return SolaceLayout(pad: OccasionInsets(top: 34, side: 48, bottom: 18), verseMul: 0.8, title: 72, from: 38, sub: 28, to: 58,
                                lead: 28, name: 52, dua: 25, lh: 128, lineW: 230)
        case .story:
            return SolaceLayout(pad: OccasionInsets(top: 250, side: 48, bottom: 250), verseMul: 1, title: 96, from: 48, sub: 34, to: 76,
                                lead: 34, name: 70, dua: 31, lh: 220, lineW: 250)
        }
    }
}
