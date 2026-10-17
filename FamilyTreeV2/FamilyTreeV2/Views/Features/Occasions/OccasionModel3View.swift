import SwiftUI
import UIKit

// MARK: - رسم بوست المناسبة — نموذج ٣ (المعتمد منذ 17/10/2026)
//
// نفس OccasionPostM3.tsx في الموقع، وبنفس أرقام ملف التصميم «منشورات مناسبات المحمدعلي» (صفحة نموذج ٣):
// التهاني: الآية بالمخطوطة كبيرة فوق ونسخة عملاقة منها خافتة خلفها ونجوم حولها، والصورة بقوس دائري الرأس
// بحاشية رملية وخطين ذهبيين تطلع من بطاقة رملية، والشعار ختماً نافراً عند زاوية البطاقة، والشعار الكريمي تحت.
// إعلان الوفاة («اللوح المفتوح»): النص على الأرضية الداكنة مباشرة، والعزاءان بخط رفيع بينهما بلا زخارف فوقهما ولا تحتهما.
// مشاركة العزاء: بطاقة بيضاء تحمل الآية والنص على أرضية رصاصية.
//
// التصميم بإحداثيات ثابتة 1080×1350 (من فوق يسار مثل position: absolute)؛ الستوري والمربع نفس التصميم داخل
// إطار (OccasionM3.frame). لما يطول النص يصغر نص البطاقة أو الإعلان كله بنسبة وحدة لين يدخل مكانه.
// الملفات من occasion-kit/m3 (المخطوطات PNG، الختم النافر) والشعار logo/flat-cream.png — تنزل من الموقع.

// MARK: - البيانات (نفس familytree-web/src/lib/occasions/m3.ts)

enum OccasionM3 {
    static let width: CGFloat = 1080
    static let height: CGFloat = 1350
    /// البطاقة: هامش 44 حولها، وتنتهي عند 1200 (تحتها الشعار)
    static let margin: CGFloat = 44
    static let cardBottom: CGFloat = 1200
    static var cardWidth: CGFloat { width - 2 * margin }
    /// حد نص إعلان الوفاة من تحت: فوق الشعار (يبدأ 1240) بـ 14
    static let deathLimit: CGFloat = 1226
    /// الإعلان بدون صورة: النص أكبر (مكان الصورة له)
    static let deathTextK: CGFloat = 1.12

    // ألوان الهوية في البطاقة
    static let sand = Color(hex: "#FCF7EC")
    static let navy = Color(hex: "#172536")
    static let gold = Color(hex: "#B89A5A")
    /// خطّا الشعار في التهاني ومشاركة العزاء
    static let goldLight = Color(hex: "#DCC28A")
    static let ink2 = Color(hex: "#3E4A5A")
    static let muted = Color(hex: "#56606B")
    static let solaceInk = Color(hex: "#1B2026")

    static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a)
    }

    /// مكان التصميم في كل مقاس: الستوري في الوسط (هوامش الأمان ٢٥٠ تبقى فاضية)، والمربع مصغّر ×0.8 في الوسط
    static func frame(_ size: OccasionSize) -> (x: CGFloat, y: CGFloat, k: CGFloat) {
        switch size {
        case .post: return (0, 0, 1)
        case .story: return (0, 285, 1)
        case .square: return (108, 0, 0.8)
        }
    }

    /// ظل الشخص لين ما تنختار صورة (نفس occasion-kit/m3/avatar)
    struct Avatar {
        let bg: Color
        let fg: Color

        static let gold = Avatar(bg: Color(hex: "#EFE3C8"), fg: Color(hex: "#D9C59B"))
        static let sea = Avatar(bg: Color(hex: "#DCE9EC"), fg: Color(hex: "#B5CFD6"))
        static let sadu = Avatar(bg: Color(hex: "#F1DEDF"), fg: Color(hex: "#DDB8BC"))
        static let palm = Avatar(bg: Color(hex: "#DDEAE2"), fg: Color(hex: "#B6D0C1"))
        static let navy = Avatar(bg: Color(hex: "#DEE5EE"), fg: Color(hex: "#B9C7D8"))
        static let grey = Avatar(bg: Color(hex: "#E3E5E8"), fg: Color(hex: "#C3C8CE"))
    }

    /// ألوان المناسبة: الأرضية (تدرّج fill ← deep بزاوية 225°)، light للنجوم والخطوط، acc لسطر المقدمة والكبسولة، chip أرضية الكبسولة
    struct Theme {
        let fill: Color
        let deep: Color
        let light: Color
        let acc: Color
        let chip: Color
        let avatar: Avatar
    }

    static func theme(_ templateID: String) -> Theme {
        switch templateID {
        case "newborn":
            return Theme(fill: Color(hex: "#2C5460"), deep: Color(hex: "#112E3A"), light: Color(hex: "#9AC6D2"), acc: Color(hex: "#2C5D69"),
                         chip: rgba(44, 93, 105, 0.12), avatar: .sea)
        case "newbornGirl":
            return Theme(fill: Color(hex: "#693940"), deep: Color(hex: "#382028"), light: Color(hex: "#EAAAAF"), acc: Color(hex: "#7B414A"),
                         chip: rgba(123, 65, 74, 0.12), avatar: .sadu)
        case "recovery":
            return Theme(fill: Color(hex: "#2C5846"), deep: Color(hex: "#10302B"), light: Color(hex: "#9ACBB1"), acc: Color(hex: "#2C614B"),
                         chip: rgba(44, 97, 75, 0.12), avatar: .palm)
        case "graduation":
            return Theme(fill: Color(hex: "#324561"), deep: Color(hex: "#17263C"), light: Color(hex: "#A9C4E4"), acc: Color(hex: "#172536"),
                         chip: rgba(23, 37, 54, 0.09), avatar: .navy)
        default:
            return Theme(fill: Color(hex: "#806631"), deep: Color(hex: "#40351E"), light: Color(hex: "#E2CF9E"), acc: Color(hex: "#725D31"),
                         chip: rgba(184, 154, 90, 0.20), avatar: .gold)
        }
    }

    /// إعلان الوفاة: الأرضية من #2B3038 إلى occ-obituary، والشامبين occ-obituary-gold
    enum Death {
        static let fill = Color(hex: "#2B3038")
        static let deep = Color(hex: "#14171C")
        static let champ = Color(hex: "#E9D5A6")
        static let lead = Color(hex: "#C9CED5")
        static let grey = Color(hex: "#AEB4BC")
        static let dua = Color(hex: "#D5D9DE")
        /// الظل الداكن خلف النص
        static let pool = Color(red: 4 / 255, green: 5 / 255, blue: 6 / 255)
    }

    /// مشاركة العزاء: بطاقة بيضاء على الرصاصي
    enum Solace {
        static let fill = Color(hex: "#4D5B67")
        static let deep = Color(hex: "#2B353E")
    }

    // MARK: المخطوطات (occasion-kit/m3/verse/<file>.png — نسخة من SVG الموقع)

    struct Img {
        let file: String
        let w: CGFloat
        let h: CGFloat

        init(_ file: String, _ w: CGFloat, _ h: CGFloat) {
            self.file = file
            self.w = w
            self.h = h
        }
    }

    /// الآية عملاقة خافتة خلف الآية — أعرض من المنشور فتنقص أطرافها
    struct Echo {
        let file: String
        let w: CGFloat
        let h: CGFloat
        let top: CGFloat
        let opacity: Double
    }

    struct HappyVerse {
        let label: String
        let photo: Img
        let noPhoto: Img
        let echo: Echo
        let echoNP: Echo
    }

    /// «وبشر الصابرين…» صغيرة فوق «إنا لله وإنا إليه راجعون» كبيرة، ونسختها العملاقة
    struct SabrVerse {
        let lead: Img
        let inna: Img
        let echo: Echo
    }

    static let leadLabel = "وَبَشِّرِ الصَّابِرِينَ الَّذِينَ إِذَا أَصَابَتْهُم مُّصِيبَةٌ قَالُوا"
    static let innaLabel = "إِنَّا لِلَّهِ وَإِنَّا إِلَيْهِ رَاجِعُونَ"

    static func happyVerse(_ templateID: String) -> HappyVerse {
        switch templateID {
        case "newborn", "newbornGirl":
            return HappyVerse(
                label: "وَالَّذِينَ يَقُولُونَ رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا",
                photo: Img("baby-cream", 645, 300), noPhoto: Img("baby-cream", 795, 370),
                echo: Echo(file: "baby1-white", w: 3100, h: 344, top: -57, opacity: 0.09),
                echoNP: Echo(file: "baby1-white", w: 3348, h: 372, top: -35, opacity: 0.09))
        case "recovery":
            return HappyVerse(
                label: "وَإِذَا مَرِضْتُ فَهُوَ يَشْفِينِ",
                photo: Img("sick-cream", 755, 300), noPhoto: Img("sick-cream", 931, 370),
                echo: Echo(file: "sick-white", w: 1660, h: 660, top: -190, opacity: 0.06),
                echoNP: Echo(file: "sick-white", w: 1793, h: 712, top: -180, opacity: 0.06))
        case "graduation":
            return HappyVerse(
                label: "وَقُل رَّبِّ زِدْنِي عِلْمًا",
                photo: Img("grad-cream", 574, 300), noPhoto: Img("grad-cream", 707, 370),
                echo: Echo(file: "grad-white", w: 1260, h: 659, top: -199, opacity: 0.06),
                echoNP: Echo(file: "grad-white", w: 1361, h: 712, top: -190, opacity: 0.06))
        default:
            return HappyVerse(
                label: "وَمِنْ آيَاتِهِ أَنْ خَلَقَ لَكُم مِّنْ أَنفُسِكُمْ أَزْوَاجًا لِّتَسْكُنُوا إِلَيْهَا وَجَعَلَ بَيْنَكُم مَّوَدَّةً وَرَحْمَةً",
                photo: Img("wed2-cream", 591, 300), noPhoto: Img("wed2-cream", 728, 370),
                echo: Echo(file: "wed1-white", w: 2260, h: 447, top: -98, opacity: 0.09),
                echoNP: Echo(file: "wed1-white", w: 2441, h: 483, top: -80, opacity: 0.09))
        }
    }

    static let deathPhotoVerse = SabrVerse(lead: Img("sabrAB-champ", 420, 96), inna: Img("death-champ", 660, 180),
                                           echo: Echo(file: "death-white", w: 1500, h: 409, top: -94, opacity: 0.07))
    static let deathNoPhotoVerse = SabrVerse(lead: Img("sabrAB-champ", 520, 119), inna: Img("death-champ", 900, 245),
                                             echo: Echo(file: "death-white", w: 1600, h: 436, top: -83, opacity: 0.07))
    static let solaceVerse = SabrVerse(lead: Img("sabrAB-navytone", 500, 115), inna: Img("death-navytone", 800, 218),
                                       echo: Echo(file: "sabr1-navytone", w: 2400, h: 381, top: -70, opacity: 0.06))

    // MARK: سطور الأسماء (الحجم بإحداثيات التصميم، العرض المتاح، ارتفاع السطر) — نفس M3_NAME في الموقع

    enum Names {
        struct Spec {
            let size: CGFloat
            let width: CGFloat
            let lineHeight: CGFloat
        }

        static let happy = Spec(size: 84, width: 880, lineHeight: 1.25)
        static let happyNoPhoto = Spec(size: 100, width: 880, lineHeight: 1.25)
        /// الوفاة: الحجم × deathTextK في الإعلان بدون صورة
        static let death = Spec(size: 80, width: 960, lineHeight: 1.2)
        static let deathRelation = Spec(size: 26, width: 840, lineHeight: 1.45)
        static let solaceTo = Spec(size: 60, width: 880, lineHeight: 1.3)
        static let solaceName = Spec(size: 56, width: 880, lineHeight: 1.3)
    }

    // MARK: النجوم والمعيّنات حول الآية (مواضعها من ملف التصميم؛ مشاركة العزاء بإحداثيات البطاقة 992×1156)

    struct Star {
        enum Kind { case sparkle, outline, diamond }

        let kind: Kind
        let x: CGFloat
        let y: CGFloat
        /// نصف القطر المرسوم
        let r: CGFloat
        let opacity: Double

        init(_ kind: Kind, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ opacity: Double) {
            self.kind = kind
            self.x = x
            self.y = y
            self.r = r
            self.opacity = opacity
        }
    }

    struct Stars {
        /// شفافية الطبقة كلها
        let opacity: Double
        let items: [Star]
    }

    enum StarSets {
        static let happy = OccasionM3.Stars(opacity: 0.5, items: [
            OccasionM3.Star(.sparkle, 80.3, 299.1, 12.0, 0.73),
            OccasionM3.Star(.outline, 92.6, 69.9, 5.0, 0.73),
            OccasionM3.Star(.diamond, 1035.3, 45.6, 3.0, 0.96),
            OccasionM3.Star(.sparkle, 846.2, 404.4, 4.0, 0.81),
            OccasionM3.Star(.outline, 930.5, 192.6, 12.0, 0.69),
            OccasionM3.Star(.diamond, 893.6, 539.6, 4.8, 0.75),
            OccasionM3.Star(.sparkle, 83.1, 405.8, 8.0, 0.98),
            OccasionM3.Star(.outline, 1011.2, 399.8, 6.0, 0.83),
            OccasionM3.Star(.diamond, 46.5, 500.9, 3.0, 0.64),
            OccasionM3.Star(.sparkle, 193.7, 444.6, 12.0, 0.85),
            OccasionM3.Star(.outline, 49.1, 173.7, 5.0, 0.67),
            OccasionM3.Star(.diamond, 1014.8, 266.0, 3.6, 0.99),
            OccasionM3.Star(.sparkle, 994.5, 563.4, 5.0, 0.46),
            OccasionM3.Star(.outline, 248.4, 543.9, 12.0, 0.86),
            OccasionM3.Star(.diamond, 380.9, 30.0, 3.6, 0.69),
            OccasionM3.Star(.sparkle, 280.5, 28.4, 4.0, 0.50),
        ])
        static let happyNP = OccasionM3.Stars(opacity: 0.5, items: [
            OccasionM3.Star(.sparkle, 80.3, 317.4, 8.0, 0.87),
            OccasionM3.Star(.outline, 92.6, 73.2, 12.0, 0.99),
            OccasionM3.Star(.diamond, 1035.3, 47.3, 3.0, 0.61),
            OccasionM3.Star(.sparkle, 846.2, 429.6, 10.0, 0.80),
            OccasionM3.Star(.outline, 60.8, 411.6, 4.0, 0.90),
            OccasionM3.Star(.diamond, 930.5, 203.9, 7.2, 0.94),
            OccasionM3.Star(.sparkle, 893.6, 573.6, 12.0, 0.69),
            OccasionM3.Star(.outline, 1011.2, 424.6, 12.0, 0.90),
            OccasionM3.Star(.diamond, 46.5, 532.4, 3.0, 0.95),
            OccasionM3.Star(.sparkle, 193.7, 472.4, 10.0, 0.76),
            OccasionM3.Star(.outline, 49.1, 183.7, 4.0, 0.90),
            OccasionM3.Star(.diamond, 1014.8, 282.1, 6.0, 0.89),
            OccasionM3.Star(.sparkle, 994.5, 599.0, 12.0, 0.83),
            OccasionM3.Star(.outline, 248.4, 578.2, 12.0, 0.80),
            OccasionM3.Star(.diamond, 280.5, 29.0, 2.4, 0.47),
            OccasionM3.Star(.sparkle, 764.6, 535.1, 5.0, 0.80),
        ])
        static let death = OccasionM3.Stars(opacity: 0.5, items: [
            OccasionM3.Star(.diamond, 80.3, 177.3, 3.6, 0.80),
            OccasionM3.Star(.outline, 92.6, 48.1, 6.0, 0.60),
            OccasionM3.Star(.diamond, 1035.3, 34.4, 4.8, 0.48),
            OccasionM3.Star(.diamond, 930.5, 117.3, 2.4, 0.68),
            OccasionM3.Star(.outline, 1011.2, 234.1, 8.0, 0.80),
            OccasionM3.Star(.diamond, 46.5, 291.0, 7.2, 0.64),
            OccasionM3.Star(.diamond, 584.9, 28.4, 3.6, 0.51),
            OccasionM3.Star(.outline, 389.8, 29.0, 6.0, 0.86),
            OccasionM3.Star(.diamond, 938.1, 319.9, 6.0, 0.98),
            OccasionM3.Star(.diamond, 771.0, 26.0, 4.8, 0.70),
            OccasionM3.Star(.outline, 280.5, 24.8, 5.0, 0.52),
            OccasionM3.Star(.diamond, 147.3, 325.2, 2.4, 0.90),
        ])
        static let deathNP = OccasionM3.Stars(opacity: 0.5, items: [
            OccasionM3.Star(.diamond, 59.0, 184.8, 3.0, 0.79),
            OccasionM3.Star(.outline, 1035.3, 37.7, 10.0, 0.83),
            OccasionM3.Star(.diamond, 1011.2, 282.4, 7.2, 0.97),
            OccasionM3.Star(.diamond, 20.2, 77.5, 3.6, 0.86),
            OccasionM3.Star(.outline, 46.5, 352.2, 5.0, 0.64),
            OccasionM3.Star(.diamond, 1013.2, 158.6, 2.4, 0.50),
            OccasionM3.Star(.diamond, 1037.3, 375.8, 3.0, 0.80),
        ])
        static let solace = OccasionM3.Stars(opacity: 0.45, items: [
            OccasionM3.Star(.diamond, 75.2, 233.1, 6.0, 0.70),
            OccasionM3.Star(.outline, 86.5, 58.1, 4.0, 0.66),
            OccasionM3.Star(.diamond, 949.4, 39.6, 6.0, 0.79),
            OccasionM3.Star(.diamond, 636.1, 437.1, 6.0, 0.98),
            OccasionM3.Star(.outline, 76.1, 342.7, 4.0, 0.99),
            OccasionM3.Star(.diamond, 927.3, 310.0, 3.0, 0.98),
            OccasionM3.Star(.diamond, 828.2, 437.1, 2.4, 0.50),
            OccasionM3.Star(.outline, 522.8, 431.0, 6.0, 0.47),
            OccasionM3.Star(.diamond, 930.6, 207.8, 3.0, 0.60),
            OccasionM3.Star(.diamond, 518.4, 27.9, 3.0, 0.90),
            OccasionM3.Star(.outline, 229.0, 420.1, 6.0, 0.67),
            OccasionM3.Star(.diamond, 707.5, 28.2, 6.0, 0.96),
        ])
    }

    // MARK: القياس (بخط البوست — قبل ما يتحمّل الخط كل شي سطر واحد)

    /// عدد السطور بلف عادي (الكلمات تنفصل بالمسافة العادية فقط) — نفس wrapCount في الموقع
    static func lines(_ text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, _ width: CGFloat) -> Int {
        guard let font = UIFont(name: weight.postScriptName, size: size) else { return 1 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func fitsLine(_ s: String) -> Bool { (s as NSString).size(withAttributes: attrs).width <= width + 0.01 }
        var count = 0
        for para in text.components(separatedBy: "\n") {
            var cur = ""
            for word in para.split(separator: " ").map(String.init) {
                if cur.isEmpty {
                    cur = word
                    continue
                }
                let candidate = cur + " " + word
                if fitsLine(candidate) {
                    cur = candidate
                } else {
                    count += 1
                    cur = word
                }
            }
            if !cur.isEmpty { count += 1 }
        }
        return max(count, 1)
    }

    /// يدخل بسطر واحد بهالحجم؟ (قبل ما يتحمّل الخط: نعم)
    static func fits(_ text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, _ width: CGFloat) -> Bool {
        guard let w = OccasionNames.measure(text, weight: weight, size: size) else { return true }
        return w <= width + 0.01
    }

    /// سطر الاسم ياخذ سطرين؟ (لو ما دخل حتى بأصغر حجم) — يرجع ١ أو ٢، نفس oneLineRows في الموقع
    static func nameRows(_ text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, _ width: CGFloat) -> CGFloat {
        let t = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return fits(t, weight, size * OccasionNames.minScale, width) ? 1 : 2
    }

    /// سطر واحد مثل OneLine في الموقع: أكبر حجم (بأعشار البكسل) يدخل فيه، ولا ينزل عن minScale؛ nil = ما دخل حتى عنده
    static func oneLineSize(_ text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, _ width: CGFloat) -> CGFloat? {
        guard let full = OccasionNames.measure(text, weight: weight, size: size), full > width + 0.01 else { return size }
        let minSize = size * OccasionNames.minScale
        var s = max(minSize, (size * (width / full) * 10).rounded(.down) / 10)
        while s > minSize && !fits(text, weight, s, width) { s = max(minSize, s - 0.5) }
        return fits(text, weight, s, width) ? s : nil
    }

    /// يلف النص على العرض بالكلمات: عادي (أكثر كلمات في كل سطر)، أو متوازن مثل text-wrap: balance في المتصفح
    /// (أضيق عرض يعطي نفس عدد السطور). كل فقرة (\n) تبدأ سطراً جديداً.
    static func wrap(_ text: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, _ width: CGFloat, balance: Bool) -> [String] {
        let paragraphs = text.components(separatedBy: "\n")
        guard let font = UIFont(name: weight.postScriptName, size: size) else { return paragraphs }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func greedy(_ words: [String], _ limit: CGFloat) -> [String] {
            var out: [String] = []
            var cur = ""
            for word in words {
                if cur.isEmpty {
                    cur = word
                    continue
                }
                let candidate = cur + " " + word
                if (candidate as NSString).size(withAttributes: attrs).width <= limit + 0.01 {
                    cur = candidate
                } else {
                    out.append(cur)
                    cur = word
                }
            }
            if !cur.isEmpty { out.append(cur) }
            return out
        }
        var lines: [String] = []
        for paragraph in paragraphs {
            let words = paragraph.split(separator: " ").map(String.init)
            var best = greedy(words, width)
            if balance && best.count > 1 {
                let count = best.count
                var lo: CGFloat = 0
                var hi = width
                for _ in 0..<12 {
                    let mid = (lo + hi) / 2
                    let attempt = greedy(words, mid)
                    if attempt.count <= count {
                        hi = mid
                        best = attempt
                    } else {
                        lo = mid
                    }
                }
            }
            lines += best
        }
        return lines
    }

    /// أكبر نسبة (من ١ نزولاً لـ minScale) يدخل فيها النص مكانه — نفس fitScale في الموقع
    static func fit(_ height: (CGFloat) -> CGFloat, available: CGFloat, minScale: CGFloat) -> CGFloat {
        var s: CGFloat = 1
        while s > minScale {
            if height(s) <= available { return s }
            s = ((s - 0.02) * 100).rounded() / 100
        }
        return minScale
    }
}

// MARK: - الرسم

extension OccasionPostView {
    @ViewBuilder
    var m3Post: some View {
        switch template.kind {
        case .happy:
            if template.showsPhoto(withPhoto) { m3HappyPost } else { m3HappyNoPhotoPost }
        case .death: m3DeathPost
        case .deathText: m3DeathTextPost
        case .solace: m3SolacePost
        }
    }

    // MARK: التهاني — الصورة: قوس 300×330 عند 440، ونصفه فوق البطاقة (تبدأ 605)

    private var m3HappyPost: some View {
        let th = OccasionM3.theme(template.id)
        let v = OccasionM3.happyVerse(template.id)
        let archTop: CGFloat = 440
        let aw: CGFloat = 300
        let ah: CGFloat = 330
        let cardTop = archTop + ah / 2
        return m3Canvas(fill: th.fill, deep: th.deep) {
            OccasionM3StarsView(stars: OccasionM3.StarSets.happy, color: th.light)
                .frame(width: OccasionM3.width, height: OccasionM3.height, alignment: .topLeading)
            m3Echo(v.echo)
            m3Glow(cx: OccasionM3.width / 2, cy: archTop + 120, r: 330, color: .white, opacity: 0.16)
            m3Zone(height: archTop - 58, padTop: 30, gap: 26, strip: th.light) {
                m3Calli(v.photo, label: v.label)
            }
            m3Arches(top: archTop, aw: aw, ah: ah, color: th.light, fading: false)
            // النص بين أسفل الصورة (+20) وأسفل البطاقة (‎-40): 370، والتصميم نفسه يتجاوزه بقليل — 393
            m3Card(top: cardTop, padTop: ah / 2 + 20, layers: {
                m3Seal("sand", cardHeight: OccasionM3.cardBottom - cardTop)
            }) {
                m3HappyBody(th, big: false, available: 393)
            }
            m3ArchPhoto(top: archTop, aw: aw, ah: ah, avatar: th.avatar)
                .accessibilityLabel(L10n.t("صورة صاحب المناسبة", "Photo"))
            m3Footer(top: 1229, line: OccasionM3.goldLight)
        }
    }

    // MARK: التهاني بدون صورة: الآية أكبر، والبطاقة تبدأ أعلى، والاسم أكبر

    private var m3HappyNoPhotoPost: some View {
        let th = OccasionM3.theme(template.id)
        let v = OccasionM3.happyVerse(template.id)
        let zoneHeight: CGFloat = 470
        let cardTop = zoneHeight + 24
        return m3Canvas(fill: th.fill, deep: th.deep) {
            OccasionM3StarsView(stars: OccasionM3.StarSets.happyNP, color: th.light)
                .frame(width: OccasionM3.width, height: OccasionM3.height, alignment: .topLeading)
            m3Echo(v.echoNP)
            m3Zone(height: zoneHeight, padTop: 30, gap: 28, strip: th.light) {
                m3Calli(v.noPhoto, label: v.label)
            }
            m3Card(top: cardTop, padTop: 56, layers: {
                m3Seal("sand", cardHeight: OccasionM3.cardBottom - cardTop)
            }) {
                m3HappyBody(th, big: true, available: OccasionM3.cardBottom - cardTop - 96)
            }
            m3Footer(top: 1229, line: OccasionM3.goldLight)
        }
    }

    /// نص البطاقة: المقدمة، الاسم، كبسولة المناسبة — ثم السدو والدعاء. big = بدون صورة.
    /// يصغر كله بنسبة وحدة لما يطول (كبسولة بسطرين، دعاء طويل) — نفس HappyBody في الموقع
    private func m3HappyBody(_ th: OccasionM3.Theme, big: Bool, available: CGFloat) -> some View {
        let chip = [value("occasion"), value("sub")]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let introPx: CGFloat = big ? 34 : 30
        let chipPx: CGFloat = big ? 38 : 35
        let namePx = (big ? OccasionM3.Names.happyNoPhoto : OccasionM3.Names.happy).size
        let blockGap: CGFloat = big ? 4 : 0
        let name = value("name")
        let dua = value("dua")
        func chipLines(_ s: CGFloat) -> Int { chip.isEmpty ? 0 : min(2, OccasionM3.lines(chip, .extrabold, chipPx * s, 812)) }
        func duaLines(_ s: CGFloat) -> Int { min(3, OccasionM3.lines(dua, .regular, 30 * s, 820)) }
        func height(_ s: CGFloat) -> CGFloat {
            var block: [CGFloat] = []
            if has("intro") { block.append(introPx * s * 1.4) }
            if has("name") {
                let rows: CGFloat = OccasionM3.nameRows(name, .extrabold, namePx * s, 880)
                block.append(rows * namePx * s * 1.25)
            }
            if !chip.isEmpty {
                let rows = CGFloat(chipLines(s))
                block.append(30 + rows * chipPx * s * 1.45)
            }
            let gaps = CGFloat(max(0, block.count - 1)) * blockGap
            var total: CGFloat = block.reduce(0, +) + gaps
            if has("dua") {
                let rows = CGFloat(duaLines(s))
                total += 28 + 13 + 28 + rows * 30 * s * 1.6
            }
            return total
        }
        let s = OccasionM3.fit(height, available: available, minScale: 0.72)
        let multiChip = chipLines(s) > 1
        return VStack(spacing: 28) {
            VStack(spacing: blockGap) {
                if has("intro") {
                    m3OneLine(value("intro"), .semibold, introPx * s, width: 880, color: th.acc, lineHeight: 1.4)
                }
                if has("name") {
                    m3NameLine("name", color: OccasionM3.navy, scale: s)
                }
                if !chip.isEmpty {
                    m3Lines(chip, .extrabold, chipPx * s, lineHeight: 1.45, width: 812, color: th.acc, maxLines: 2)
                        .padding(.horizontal, 34)
                        .padding(.top, 5)
                        .padding(.bottom, 11)
                        .background {
                            if multiChip {
                                RoundedRectangle(cornerRadius: 36, style: .circular).fill(th.chip)
                            } else {
                                Capsule().fill(th.chip)
                            }
                        }
                        .padding(.top, 14)
                }
            }
            if has("dua") {
                OccasionM3Sadu(color: OccasionM3.gold, width: 300, big: 13, small: 9, opLine: 0.8, opSmall: 0.55)
                m3Lines(dua, .regular, 30 * s, lineHeight: 1.6, width: 820, color: OccasionM3.ink2, maxLines: 3)
            }
        }
    }

    // MARK: إعلان وفاة — مع صورة («اللوح المفتوح»)

    private var m3DeathPost: some View {
        let D = OccasionM3.Death.self
        let v = OccasionM3.deathPhotoVerse
        let top: CGFloat = 416
        let aw: CGFloat = 244
        let ah: CGFloat = 284
        return m3Canvas(fill: D.fill, deep: D.deep) {
            OccasionM3StarsView(stars: OccasionM3.StarSets.death, color: D.champ)
                .frame(width: OccasionM3.width, height: OccasionM3.height, alignment: .topLeading)
            m3Echo(v.echo)
            m3Zone(height: 350, padTop: 22, gap: 20, strip: D.champ) {
                m3SabrBlock(v, gap: 12)
            }
            m3Glow(cx: OccasionM3.width / 2, cy: top + 130, r: 330, color: D.champ, opacity: 0.15)
            m3GroundLayers(poolTop: 640)
            m3Arches(top: top, aw: aw, ah: ah, color: D.champ, fading: true)
            m3DeathInfo(top: top + ah + 12, k0: 1, gap0: 1, rels: ["relation"])
            m3ArchPhoto(top: top, aw: aw, ah: ah, avatar: .grey)
                .accessibilityLabel(L10n.t("صورة الفقيد", "Photo of the deceased"))
            m3Footer(top: 1240, line: D.champ)
        }
    }

    // MARK: إعلان وفاة — بدون صورة: الآية أكبر، والنص يبدأ أعلى وبخط أكبر (× deathTextK)

    private var m3DeathTextPost: some View {
        let D = OccasionM3.Death.self
        let v = OccasionM3.deathNoPhotoVerse
        let infoTop: CGFloat = 540
        return m3Canvas(fill: D.fill, deep: D.deep) {
            OccasionM3StarsView(stars: OccasionM3.StarSets.deathNP, color: D.champ)
                .frame(width: OccasionM3.width, height: OccasionM3.height, alignment: .topLeading)
            m3Echo(v.echo)
            m3Zone(height: 420, padTop: 30, gap: 28, strip: D.champ) {
                m3SabrBlock(v, gap: 14)
            }
            m3Glow(cx: OccasionM3.width / 2, cy: infoTop + 170, r: 380, color: D.champ, opacity: 0.10)
            m3GroundLayers(poolTop: infoTop - 40)
            m3DeathInfo(top: infoTop, k0: OccasionM3.deathTextK, gap0: 1.5, rels: ["rel1", "rel2", "rel3"])
            m3Footer(top: 1240, line: D.champ)
        }
    }

    /// نص الإعلان على الأرضية مباشرة: المقدمة، اللقب، الاسم، القرابة (كبسولة؛ بطاقة لو أكثر من سطر)،
    /// ثم التشييع والعزاء والعزاءان، ثم الدعاء. فوق العزاءين وتحتهما مسافة فقط (كان فيها فاصلا سدو، أُزيلا بطلب المستخدم
    /// 17/10/2026 مع بقاء المسافة نفسها). k0 = حجم التصميم، gap0 = نسبة المسافات.
    /// يصغر الكل بنسبة وحدة لين يدخل فوق الشعار — نفس DeathInfo في الموقع
    private func m3DeathInfo(top: CGFloat, k0: CGFloat, gap0: CGFloat, rels: [String]) -> some View {
        let D = OccasionM3.Death.self
        let relKeys = rels.filter { has($0) }
        let venues = m3Venues()
        let fc = ["funeral", "condolence"].filter { has($0) }
        let section = !venues.isEmpty || !fc.isEmpty
        let duas = ["dua1", "dua2"].filter { has($0) }
        let two = venues.count == 2
        let relWidth = OccasionM3.Names.deathRelation.width
        let nameSpec = OccasionM3.Names.death
        func dims(_ s: CGFloat) -> OccasionM3DeathDims { OccasionM3DeathDims(k0: k0, gap0: gap0, s: s, twoVenues: two) }
        func relLines(_ key: String, _ d: OccasionM3DeathDims) -> CGFloat {
            if isNameLine(key) { return OccasionM3.nameRows(value(key), .semibold, d.rel, relWidth) }
            return CGFloat(min(4, OccasionM3.lines(value(key), .semibold, d.rel, relWidth)))
        }
        func multiRel(_ d: OccasionM3DeathDims) -> Bool { relKeys.count > 1 || relKeys.contains { relLines($0, d) > 1 } }
        func venueHeight(_ v: OccasionM3Venue, _ d: OccasionM3DeathDims) -> CGFloat {
            let placeRows = CGFloat(min(2, OccasionM3.lines(v.place, .semibold, d.vPlace, d.venueW)))
            var h: CGFloat = d.vTitle * 1.4 + 2 + placeRows * d.vPlace * 1.4
            if !v.line.isEmpty {
                let lineRows = CGFloat(min(2, OccasionM3.lines(v.line, .regular, d.vLine, d.venueW)))
                h += 2 + lineRows * d.vLine * 1.4
            }
            return h
        }
        func height(_ s: CGFloat) -> CGFloat {
            let d = dims(s)
            var h: CGFloat = 0
            if has("lead") { h += d.lead * 1.4 }
            if has("title") { h += d.lead * 1.4 }
            if has("name") {
                let px: CGFloat = (nameSpec.size * k0).rounded() * s
                let rows: CGFloat = OccasionM3.nameRows(value("name"), .extrabold, px, nameSpec.width)
                h += rows * px * nameSpec.lineHeight
            }
            if !relKeys.isEmpty {
                let rows: CGFloat = relKeys.reduce(CGFloat(0)) { acc, key in acc + relLines(key, d) }
                let pad: CGFloat = multiRel(d) ? 21 : 11
                h += 6 + pad + rows * d.rel * 1.45
            }
            if section {
                h += d.ruleTop + 13 + d.ruleMid + d.ruleMid + 13 + d.ruleEnd
                for key in fc {
                    let rows = CGFloat(min(3, OccasionM3.lines(value(key), .semibold, d.fc, 900)))
                    h += rows * d.fc * 1.45
                }
                if !fc.isEmpty && !venues.isEmpty { h += d.ruleMid }
                if !venues.isEmpty {
                    let tallest: CGFloat = venues.map { venueHeight($0, d) }.max() ?? 0
                    h += max(two ? d.sep : 0, tallest)
                }
            } else {
                h += d.ruleTop + 13 + d.ruleEnd
            }
            for key in duas {
                let rows = CGFloat(min(2, OccasionM3.lines(value(key), .regular, d.dua, 960)))
                h += rows * d.dua * 1.55
            }
            return h
        }
        let s = OccasionM3.fit(height, available: OccasionM3.deathLimit - top, minScale: 0.76)
        let d = dims(s)
        let multi = multiRel(d)
        return VStack(spacing: 0) {
            if has("lead") { m3OneLine(value("lead"), .semibold, d.lead, width: 960, color: D.lead, lineHeight: 1.4) }
            if has("title") { m3OneLine(value("title"), .semibold, d.lead, width: 960, color: D.champ, lineHeight: 1.4) }
            if has("name") { m3NameLine("name", color: D.champ, scale: s) }
            if !relKeys.isEmpty {
                VStack(spacing: 0) {
                    ForEach(relKeys, id: \.self) { key in
                        if isNameLine(key) {
                            m3NameLine(key, color: D.champ, scale: s)
                        } else {
                            m3Lines(value(key), .semibold, d.rel, lineHeight: 1.45, width: relWidth, color: D.champ, maxLines: 4)
                        }
                    }
                }
                .padding(.horizontal, multi ? 32 : 28)
                .padding(.top, multi ? 8 : 3)
                .padding(.bottom, multi ? 13 : 8)
                .background {
                    if multi {
                        RoundedRectangle(cornerRadius: 30, style: .circular).fill(D.champ.opacity(0.12))
                    } else {
                        Capsule().fill(D.champ.opacity(0.12))
                    }
                }
                .padding(.top, 6)
            }
            m3RuleSpace()
                .padding(.top, d.ruleTop)
                .padding(.bottom, section ? d.ruleMid : d.ruleEnd)
            if section {
                if !fc.isEmpty {
                    VStack(spacing: 0) {
                        if has("funeral") {
                            m3Lines(value("funeral"), .semibold, d.fc, lineHeight: 1.45, width: 900, color: D.champ, maxLines: 3)
                        }
                        if has("condolence") {
                            m3Lines(value("condolence"), .semibold, d.fc, lineHeight: 1.45, width: 900, color: .white, maxLines: 3)
                        }
                    }
                    .padding(.bottom, venues.isEmpty ? 0 : d.ruleMid)
                }
                if !venues.isEmpty {
                    // من اليسار: النساء، الفاصل، الرجال (في التصميم RTL: الرجال يمين)
                    HStack(spacing: 0) {
                        if two {
                            m3Venue(venues[1], d)
                            m3VenueSeparator(height: d.sep)
                        }
                        m3Venue(venues[0], d)
                    }
                    .frame(maxWidth: d.rowW)
                }
                m3RuleSpace()
                    .padding(.top, d.ruleMid)
                    .padding(.bottom, d.ruleEnd)
            }
            ForEach(duas, id: \.self) { key in
                m3Lines(value(key), .regular, d.dua, lineHeight: 1.55, width: 960, color: D.dua, maxLines: 2)
            }
        }
        .frame(width: 960)
        .offset(x: 60, y: top)
    }

    /// العزاءان: «عزاء الرجال / النساء» والمكان، والمنطقة · الأوقات
    private func m3Venues() -> [OccasionM3Venue] {
        var out: [OccasionM3Venue] = []
        for (side, title) in [("men", "عزاء الرجال"), ("women", "عزاء النساء")] {
            guard has("\(side)Place") else { continue }
            let line = [value("\(side)Area"), value("\(side)Times")]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            out.append(OccasionM3Venue(title: title, place: value("\(side)Place"), line: line))
        }
        return out
    }

    private func m3Venue(_ v: OccasionM3Venue, _ d: OccasionM3DeathDims) -> some View {
        let D = OccasionM3.Death.self
        return VStack(spacing: 2) {
            HStack(spacing: 8) {
                OccasionM3Pin()
                    .fill(D.champ, style: FillStyle(eoFill: true))
                    .frame(width: 24, height: 24)
                Text(v.title)
                    .font(.custom(OccasionKit.FontWeight.extrabold.postScriptName, fixedSize: d.vTitle))
                    .foregroundColor(D.champ)
                    .occasionLineBox(.extrabold, size: d.vTitle, lineHeight: 1.4)
                    .fixedSize()
            }
            // الدبوس يمين العنوان مثل التصميم
            .environment(\.layoutDirection, .rightToLeft)
            m3Lines(v.place, .semibold, d.vPlace, lineHeight: 1.4, width: d.venueW, color: .white, maxLines: 2)
            if !v.line.isEmpty {
                m3Lines(v.line, .regular, d.vLine, lineHeight: 1.4, width: d.venueW, color: D.grey, maxLines: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// خط رفيع بين العزاءين يتلاشى من طرفيه
    private func m3VenueSeparator(height: CGFloat) -> some View {
        let c = OccasionM3.Death.champ
        return LinearGradient(stops: [
            .init(color: c.opacity(0), location: 0), .init(color: c.opacity(0.45), location: 0.3),
            .init(color: c.opacity(0.45), location: 0.7), .init(color: c.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(width: 2, height: height)
    }

    /// ظل داكن خفيف خلف النص، والشعار ختماً غائراً عند الزاوية اليسرى السفلى من المنشور (في الستوري: زاوية الستوري)
    private func m3GroundLayers(poolTop: CGFloat) -> some View {
        let f = OccasionM3.frame(size)
        let sealTop = (canvas.height - f.y) / f.k - (466 - 115)
        let pool = OccasionM3.Death.pool
        return ZStack(alignment: .topLeading) {
            EllipticalGradient(stops: [
                .init(color: pool.opacity(0.55), location: 0), .init(color: pool.opacity(0.25), location: 0.45),
                .init(color: pool.opacity(0), location: 0.72),
            ], center: .center, startRadiusFraction: 0, endRadiusFraction: CGFloat(2).squareRoot() / 2)
            .frame(width: 1200, height: 640)
            .offset(x: -60, y: poolTop)
            m3Image("m3/wm/emboss-dark.png", w: 620, h: 466)
                .offset(x: -190, y: sealTop)
        }
        .accessibilityHidden(true)
    }

    // MARK: مشاركة عزاء: البطاقة البيضاء تحمل الآية أيضاً، والأرضية الرصاصية إطار حولها، والشعار تحتها

    private var m3SolacePost: some View {
        let S = OccasionM3.Solace.self
        let v = OccasionM3.solaceVerse
        let top = OccasionM3.margin
        let cardHeight = OccasionM3.cardBottom - top
        let ink = OccasionM3.solaceInk
        let muted = OccasionM3.muted
        var items: [AnyView] = [
            AnyView(m3SabrBlock(v, gap: 10)),
            AnyView(OccasionM3Sadu(color: OccasionM3.gold, width: 420, big: 14, small: 10, opLine: 0.8, opSmall: 0.6)),
            // «تتقدم عائلة المحمدعلي» أساس الفكرة: كبير (60) وملاصق للعنوان في مجموعة واحدة، مثل الموقع
            AnyView(VStack(spacing: 0) {
                m3Fixed("مشاركة عزاء", .extrabold, 68, color: ink, lineHeight: 1.25)
                if has("from") { m3OneLine(value("from"), .extrabold, 60, width: 880, color: OccasionM3.navy, lineHeight: 1.4) }
            }),
            AnyView(VStack(spacing: 0) {
                m3Fixed("بأحر التعازي وأصدق المواساة إلى", .regular, 27, color: muted, lineHeight: 1.45)
                if has("to") { m3NameLine("to", color: ink, scale: 1) }
            }),
            AnyView(VStack(spacing: 0) {
                if has("lead") { m3OneLine(value("lead"), .regular, 27, width: 880, color: muted, lineHeight: 1.45) }
                if has("name") { m3NameLine("name", color: ink, scale: 1) }
            }),
        ]
        if has("dua") {
            items.append(AnyView(m3Lines(value("dua"), .regular, 25, lineHeight: 1.6, width: 820, color: OccasionM3.ink2, maxLines: 3)))
        } else {
            items.append(AnyView(Color.clear.frame(height: 0)))
        }
        return m3Canvas(fill: S.fill, deep: S.deep) {
            m3Card(top: top, padTop: 40, background: .white, spaceBetween: true, layers: {
                OccasionM3StarsView(stars: OccasionM3.StarSets.solace, color: OccasionM3.gold)
                    .frame(width: OccasionM3.cardWidth, height: cardHeight, alignment: .topLeading)
                m3Echo(v.echo, frameWidth: OccasionM3.cardWidth)
                m3Seal("white", cardHeight: cardHeight)
            }) {
                OccasionSpacedColumn(items: items)
            }
            m3Footer(top: 1229, line: OccasionM3.goldLight)
        }
    }

    // MARK: قطع نموذج ٣

    /// المقاس كامل بالأرضية المتدرجة، والتصميم (1080×1350) داخل الإطار
    private func m3Canvas<Content: View>(fill: Color, deep: Color, @ViewBuilder _ content: () -> Content) -> some View {
        let f = OccasionM3.frame(size)
        return ZStack(alignment: .topLeading) {
            OccasionCSSGradient(angle: 225, stops: [Gradient.Stop(color: fill, location: 0), Gradient.Stop(color: deep, location: 1)])
                .frame(width: canvas.width, height: canvas.height)
            ZStack(alignment: .topLeading) {
                content()
            }
            .frame(width: OccasionM3.width, height: OccasionM3.height, alignment: .topLeading)
            .scaleEffect(f.k, anchor: .topLeading)
            .offset(x: f.x, y: f.y)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    /// صورة من occasion-kit بمقاس محدد (أو فراغ لين تتحمّل)
    private func m3Image(_ path: String, w: CGFloat, h: CGFloat, opacity: Double = 1) -> some View {
        Group {
            if let ui = image(path) {
                Image(uiImage: ui).resizable().frame(width: w, height: h).opacity(opacity)
            } else {
                Color.clear.frame(width: w, height: h)
            }
        }
    }

    /// الآية بالمخطوطة
    private func m3Calli(_ v: OccasionM3.Img, label: String) -> some View {
        m3Image("m3/verse/\(v.file).png", w: v.w, h: v.h).accessibilityLabel(label)
    }

    /// «وبشر الصابرين…» صغيرة فوق «إنا لله وإنا إليه راجعون» كبيرة
    private func m3SabrBlock(_ v: OccasionM3.SabrVerse, gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            m3Calli(v.lead, label: OccasionM3.leadLabel)
            m3Calli(v.inna, label: OccasionM3.innaLabel)
        }
    }

    /// الآية عملاقة خافتة — في وسط الإطار (أو البطاقة) وتنقصها حوافه
    private func m3Echo(_ e: OccasionM3.Echo, frameWidth: CGFloat = OccasionM3.width) -> some View {
        m3Image("m3/verse/\(e.file).png", w: e.w, h: e.h, opacity: e.opacity)
            .offset(x: ((frameWidth - e.w) / 2).rounded(.down), y: e.top)
            .accessibilityHidden(true)
    }

    /// ضوء دائري خافت (radial-gradient(circle, … 0%, transparent 70%))
    private func m3Glow(cx: CGFloat, cy: CGFloat, r: CGFloat, color: Color, opacity: Double) -> some View {
        EllipticalGradient(stops: [.init(color: color.opacity(opacity), location: 0), .init(color: color.opacity(0), location: 0.7)],
                           center: .center, startRadiusFraction: 0, endRadiusFraction: CGFloat(2).squareRoot() / 2)
            .frame(width: 2 * r, height: 2 * r)
            .offset(x: cx - r, y: cy - r)
            .accessibilityHidden(true)
    }

    /// الجزء العلوي: الآية وتحتها شريط السدو، في الوسط بين padTop وheight
    private func m3Zone<Block: View>(height: CGFloat, padTop: CGFloat, gap: CGFloat, strip: Color,
                                     @ViewBuilder _ block: () -> Block) -> some View {
        VStack(spacing: gap) {
            block()
            OccasionM3Sadu(color: strip, width: 560, opLine: 0.7)
        }
        .frame(width: OccasionM3.width, height: height - padTop)
        .offset(y: padTop)
    }

    /// مكان فاصل السدو اللي كان فوق العزاءين وتحتهما (ارتفاعه 13) — بقي مسافة فارغة مثل الموقع
    private func m3RuleSpace() -> some View {
        Color.clear.frame(height: 13)
    }

    /// خطّا القوس حول الصورة (باب داخل باب). fading = إعلان الوفاة: يتلاشيان نحو أسفل الصورة (ما فيه بطاقة تحتها)
    private func m3Arches(top: CGFloat, aw: CGFloat, ah: CGFloat, color: Color, fading: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            m3ArchLine(top: top, aw: aw, ah: ah, off: 18, opacity: 1, lineWidth: 3, color: color, fading: fading)
            m3ArchLine(top: top, aw: aw, ah: ah, off: 46, opacity: 0.45, lineWidth: 2, color: color, fading: fading)
        }
        .accessibilityHidden(true)
    }

    private func m3ArchLine(top: CGFloat, aw: CGFloat, ah: CGFloat, off: CGFloat, opacity: Double, lineWidth: CGFloat,
                            color: Color, fading: Bool) -> some View {
        let w = aw + 2 * off
        let h = fading ? ah + off - 6 : ah
        let x = ((OccasionM3.width - aw) / 2).rounded(.down) - off
        let shape = OccasionM3ArchLine(lineWidth: lineWidth)
        let fade = LinearGradient(stops: [
            .init(color: color, location: 0), .init(color: color, location: 0.52), .init(color: color.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        return Group {
            if fading {
                shape.stroke(fade, lineWidth: lineWidth)
            } else {
                shape.stroke(color, lineWidth: lineWidth)
            }
        }
        .frame(width: w, height: h)
        .opacity(opacity)
        .offset(x: x, y: top - off)
    }

    /// الصورة بقوس دائري الرأس وحاشية رملية 10
    private func m3ArchPhoto(top: CGFloat, aw: CGFloat, ah: CGFloat, avatar: OccasionM3.Avatar) -> some View {
        let r = (aw / 2).rounded(.down)
        let pad: CGFloat = 10
        return ZStack(alignment: .topLeading) {
            OccasionM3ArchShape(topRadius: r, bottomRadius: 30).fill(OccasionM3.sand)
            OccasionM3PhotoFill(photo: photo, avatar: avatar, width: aw - 2 * pad, height: ah - 2 * pad)
                .clipShape(OccasionM3ArchShape(topRadius: r - pad, bottomRadius: 21))
                .offset(x: pad, y: pad)
        }
        .frame(width: aw, height: ah, alignment: .topLeading)
        .offset(x: ((OccasionM3.width - aw) / 2).rounded(.down), y: top)
    }

    /// البطاقة: layers طبقات خلف النص مقصوصة بحوافها (الختم، النجوم…)، والنص في المساحة بين الحشوتين
    private func m3Card<Layers: View, Content: View>(top: CGFloat, padTop: CGFloat, padBottom: CGFloat = 40,
                                                     background: Color = OccasionM3.sand, spaceBetween: Bool = false,
                                                     @ViewBuilder layers: () -> Layers,
                                                     @ViewBuilder content: () -> Content) -> some View {
        let w = OccasionM3.cardWidth
        let h = OccasionM3.cardBottom - top
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 40, style: .circular)
                .fill(background)
                .shadow(color: .black.opacity(0.30), radius: 35, x: 0, y: 30)
            ZStack(alignment: .topLeading) {
                layers()
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .circular))
            .accessibilityHidden(true)
            Group {
                if spaceBetween {
                    // مشاركة العزاء: العناصر موزّعة على الارتفاع كله (justify-content: space-between)
                    content().frame(width: w - 112, height: h - padTop - padBottom)
                } else {
                    // في الوسط إذا عنده مساحة؛ وإذا طال يبدأ من فوق ويكمل في الحشوة السفلية (ما يطلع على الصورة) — مثل الموقع
                    OccasionM3CenterBox(height: h - padTop - padBottom) { content() }
                        .frame(width: w - 112)
                }
            }
            .offset(x: 56, y: padTop)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .offset(x: OccasionM3.margin, y: top)
    }

    /// الشعار ختماً نافراً بلون البطاقة عند زاويتها اليسرى السفلى، مقصوصاً بحافتها
    private func m3Seal(_ face: String, cardHeight: CGFloat) -> some View {
        m3Image("m3/wm/emboss-\(face).png", w: 620, h: 466, opacity: 0.9)
            .offset(x: -150, y: cardHeight - 466 + 135)
    }

    /// الشعار الكريمي في الأسفل بين خطين
    private func m3Footer(top: CGFloat, line: Color) -> some View {
        HStack(spacing: 30) {
            LinearGradient(colors: [line.opacity(0), line], startPoint: .leading, endPoint: .trailing)
                .frame(width: 200, height: 2)
                .opacity(0.8)
            Group {
                if let ui = image("logo/flat-cream.png") {
                    Image(uiImage: ui)
                        .resizable()
                        .frame(width: 92 * ui.size.width / max(ui.size.height, 1), height: 92)
                        .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))
                } else {
                    Color.clear.frame(width: 92 * 1200 / 895, height: 92)
                }
            }
            LinearGradient(colors: [line, line.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 200, height: 2)
                .opacity(0.8)
        }
        .frame(width: OccasionM3.width, height: 92)
        .offset(y: top)
    }

    // MARK: النص

    /// نص ثابت بسطر واحد (عناوين التصميم)
    /// سطور جاهزة: كل سطر Text وحده بارتفاع سطر التصميم بالضبط (box)، والعمود على قد أعرض سطر
    /// (مثل max-width في CSS — فأرضية الكبسولة على قد النص). احتياط: لو اختلف القياس شوي، السطر يصغر ١٠٪ بدل ما ينقص.
    private func m3Stack(_ lines: [String], _ weight: OccasionKit.FontWeight, _ fs: CGFloat, box: CGFloat, color: Color,
                         width: CGFloat) -> some View {
        OccasionM3MaxWidth(width: width) {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.custom(weight.postScriptName, fixedSize: fs))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        // التخطيط LTR، لكن النص نفسه عربي — اتجاهه RTL حتى تطلع النقاط والأقواس بمكانها
                        .environment(\.layoutDirection, .rightToLeft)
                        .occasionLineBox(weight, size: fs, lineHeight: box / max(fs, 1))
                }
            }
        }
    }

    /// نص ثابت بسطر واحد (عناوين التصميم)
    private func m3Fixed(_ string: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, color: Color, lineHeight: CGFloat) -> some View {
        m3Stack([string], weight, size, box: lineHeight * size, color: color, width: OccasionM3.width)
    }

    /// سطر واحد مثل OneLine في الموقع: يصغر بقدر ما يدخل (أقل شي ٦٠٪)؛ إذا ما دخل حتى عنده: الأسماء (balance) سطرين
    /// متوازنين بأصغر حجم، والباقي يلتف بحجم التصميم. ارتفاع السطر يبقى بحجم التصميم (lineHeight × size).
    private func m3OneLine(_ string: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, width: CGFloat, color: Color,
                           lineHeight: CGFloat, balance: Bool = false) -> some View {
        let t = string.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines: [String]
        let fs: CGFloat
        if let fitted = OccasionM3.oneLineSize(t, weight, size, width) {
            lines = [t]
            fs = fitted
        } else if balance {
            fs = size * OccasionNames.minScale
            lines = OccasionM3.wrap(t, weight, fs, width, balance: true)
        } else {
            fs = size
            lines = OccasionM3.wrap(t, weight, fs, width, balance: false)
        }
        return m3Stack(lines, weight, fs, box: lineHeight * size, color: color, width: width)
    }

    /// نص بسطور (متوازنة مثل text-wrap: balance)؛ إذا زاد عن maxLines يصغر الخط شوي شوي (أقل شي ٧٠٪) — مثل Lines في الموقع
    private func m3Lines(_ string: String, _ weight: OccasionKit.FontWeight, _ size: CGFloat, lineHeight: CGFloat, width: CGFloat,
                         color: Color, maxLines: Int) -> some View {
        var fs = size
        let minSize = (size * 0.7).rounded(.down)
        let step = max(1, (size * 0.02).rounded())
        while fs > minSize && OccasionM3.lines(string, weight, fs, width) > maxLines {
            fs = max(minSize, fs - step)
        }
        let lines = OccasionM3.wrap(string, weight, fs, width, balance: true)
        return m3Stack(lines, weight, fs, box: lineHeight * fs, color: color, width: width)
    }

    /// سطر اسم (من nameSlots) مضروب في scale — لما يصغر نص البطاقة كله
    private func m3NameLine(_ key: String, color: Color, scale: CGFloat) -> some View {
        let slot = template.nameSlots(model: model, size: size, withPhoto: withPhoto)[key]
            ?? OccasionNameSlot(weight: .extrabold, size: 56, width: 540, lineHeight: 1.25)
        return m3OneLine(value(key), slot.weight, slot.size * scale, width: slot.width, color: color,
                         lineHeight: slot.lineHeight, balance: true)
    }
}

// MARK: - قطع مشتركة لنموذج ٣

/// عزاء (الرجال / النساء): العنوان، المكان، والمنطقة · الأوقات
struct OccasionM3Venue {
    let title: String
    let place: String
    let line: String
}

/// مقاسات نص إعلان الوفاة بنسبة s (مقرّبة لأقرب بكسل مثل ملف التصميم)
struct OccasionM3DeathDims {
    let lead: CGFloat
    let rel: CGFloat
    let fc: CGFloat
    let vTitle: CGFloat
    let vPlace: CGFloat
    let vLine: CGFloat
    let dua: CGFloat
    let sep: CGFloat
    let rowW: CGFloat
    let venueW: CGFloat
    let ruleTop: CGFloat
    let ruleMid: CGFloat
    let ruleEnd: CGFloat

    init(k0: CGFloat, gap0: CGFloat, s: CGFloat, twoVenues: Bool) {
        let k = k0 * s
        let g = gap0 * s
        lead = (28 * k).rounded()
        rel = (26 * k).rounded()
        fc = (26 * k).rounded()
        vTitle = (26 * k).rounded()
        vPlace = (27 * k).rounded()
        vLine = (22 * k).rounded()
        dua = (24 * k).rounded()
        sep = (104 * k).rounded()
        let row = (840 * min(k, 1.06)).rounded()
        rowW = row
        venueW = twoVenues ? row / 2 - 16 : row - 40
        ruleTop = (18 * g).rounded()
        ruleMid = (14 * g).rounded()
        ruleEnd = (16 * g).rounded()
    }
}

/// النجوم والمعيّنات المتناثرة (مواضعها ثابتة من ملف التصميم)
struct OccasionM3StarsView: View {
    let stars: OccasionM3.Stars
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stars.items.indices, id: \.self) { i in
                let star = stars.items[i]
                if star.kind == .outline {
                    OccasionM3StarShape(star: star).stroke(color, lineWidth: 2).opacity(star.opacity)
                } else {
                    OccasionM3StarShape(star: star).fill(color).opacity(star.opacity)
                }
            }
        }
        .opacity(stars.opacity)
        .accessibilityHidden(true)
    }
}

/// نجمة رباعية (sparkle) أو معيّن — بنفس مسارات ملف التصميم
struct OccasionM3StarShape: Shape {
    let star: OccasionM3.Star

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + star.x
        let y = rect.minY + star.y
        let r = star.r
        var p = Path()
        if star.kind == .sparkle {
            let k = r * 0.18
            p.move(to: CGPoint(x: x, y: y - r))
            p.addCurve(to: CGPoint(x: x + r, y: y), control1: CGPoint(x: x + k, y: y - k * 1.6), control2: CGPoint(x: x + k * 1.6, y: y - k))
            p.addCurve(to: CGPoint(x: x, y: y + r), control1: CGPoint(x: x + k * 1.6, y: y + k), control2: CGPoint(x: x + k, y: y + k * 1.6))
            p.addCurve(to: CGPoint(x: x - r, y: y), control1: CGPoint(x: x - k, y: y + k * 1.6), control2: CGPoint(x: x - k * 1.6, y: y + k))
            p.addCurve(to: CGPoint(x: x, y: y - r), control1: CGPoint(x: x - k * 1.6, y: y - k), control2: CGPoint(x: x - k, y: y - k * 1.6))
        } else {
            p.move(to: CGPoint(x: x, y: y - r))
            p.addLine(to: CGPoint(x: x + r, y: y))
            p.addLine(to: CGPoint(x: x, y: y + r))
            p.addLine(to: CGPoint(x: x - r, y: y))
        }
        p.closeSubpath()
        return p
    }
}

/// شريط السدو: خمسة معيّنات بين خطين يتلاشيان نحو الخارج (ارتفاعه = المعيّن الكبير)
struct OccasionM3Sadu: View {
    let color: Color
    let width: CGFloat
    var big: CGFloat = 16
    var small: CGFloat = 11
    var opLine: Double = 0.55
    var opSmall: Double = 0.6

    var body: some View {
        let gap: CGFloat = 12
        let lineW = max(0, (width - 4 * small - big - 6 * gap) / 2)
        return HStack(spacing: gap) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing)
                .frame(width: lineW, height: 2)
                .opacity(opLine)
            ForEach(0..<5, id: \.self) { i in
                OccasionM3Diamond()
                    .fill(color)
                    .frame(width: i == 2 ? big : small, height: i == 2 ? big : small)
                    .opacity(i == 2 ? 1 : opSmall)
            }
            LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: lineW, height: 2)
                .opacity(opLine)
        }
        .frame(width: width, height: big)
        .accessibilityHidden(true)
    }
}

/// مربع مدوّر ٤٥° (معيّن السدو): الضلع = عرض الإطار، فقطره أطول منه مثل rotate(45deg) في الموقع
struct OccasionM3Diamond: Shape {
    func path(in r: CGRect) -> Path {
        let h = r.width / CGFloat(2).squareRoot()
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.midY - h))
        p.addLine(to: CGPoint(x: r.midX + h, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.midY + h))
        p.addLine(to: CGPoint(x: r.midX - h, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// خط القوس: جانبان مستقيمان ورأس نصف دائري — على منتصف الخط (مثل border بلا أسفل وborder-radius بنصف العرض)
struct OccasionM3ArchLine: Shape {
    let lineWidth: CGFloat

    func path(in r: CGRect) -> Path {
        let radius = r.width / 2
        let c = lineWidth / 2
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + radius), radius: radius - c,
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        return p
    }
}

/// شكل الصورة: رأس دائري (topRadius) وزوايا سفلية صغيرة (bottomRadius)
struct OccasionM3ArchShape: Shape {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in r: CGRect) -> Path {
        let t = min(topRadius, r.width / 2, r.height / 2)
        let b = min(bottomRadius, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + t))
        p.addArc(center: CGPoint(x: r.minX + t, y: r.minY + t), radius: t, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - t, y: r.minY + t), radius: t, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
        p.addArc(center: CGPoint(x: r.maxX - b, y: r.maxY - b), radius: b, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + b, y: r.maxY - b), radius: b, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// الصورة تغطي المساحة مع التكبير والموضع (مثل object-fit: cover)، أو ظل شخص (نفس occasion-kit/m3/avatar 400×480)
struct OccasionM3PhotoFill: View {
    let photo: OccasionPhoto
    let avatar: OccasionM3.Avatar
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        content
            .frame(width: width, height: height, alignment: .topLeading)
            .grayscale(photo.gray ? 1 : 0)
    }

    @ViewBuilder
    private var content: some View {
        if let ui = photo.image, ui.size.width > 0, ui.size.height > 0 {
            let s = max(width / ui.size.width, height / ui.size.height) * max(photo.zoom, 1)
            let dw = ui.size.width * s
            let dh = ui.size.height * s
            ZStack(alignment: .topLeading) {
                Color(hex: "#E9E4DA")
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: (width - dw) * photo.x / 100, y: (height - dh) * photo.y / 100)
            }
        } else {
            let s = max(width / 400, height / 480) * max(photo.zoom, 1)
            let dx = (width - 400 * s) * photo.x / 100
            let dy = (height - 480 * s) * photo.y / 100
            ZStack(alignment: .topLeading) {
                avatar.bg
                Path { p in
                    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * s, y: dy + y * s) }
                    p.addEllipse(in: CGRect(x: dx + 126 * s, y: dy + 131 * s, width: 148 * s, height: 148 * s))
                    p.move(to: pt(58, 480))
                    p.addCurve(to: pt(200, 318), control1: pt(58, 372), control2: pt(124, 318))
                    p.addCurve(to: pt(342, 480), control1: pt(276, 318), control2: pt(342, 372))
                    p.closeSubpath()
                }
                .fill(avatar.fg)
            }
        }
    }
}

/// دبوس الموقع (نفس رسمة الموقع 24×24): قطرة وفيها فتحة
struct OccasionM3Pin: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var p = Path()
        p.move(to: pt(12, 2))
        p.addCurve(to: pt(5, 9), control1: pt(8.1, 2), control2: pt(5, 5.1))
        p.addCurve(to: pt(12, 22), control1: pt(5, 14.2), control2: pt(12, 22))
        p.addCurve(to: pt(19, 9), control1: pt(12, 22), control2: pt(19, 14.2))
        p.addCurve(to: pt(12, 2), control1: pt(19, 5.1), control2: pt(15.9, 2))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: r.minX + 9.5 * s, y: r.minY + 6.5 * s, width: 5 * s, height: 5 * s))
        return p
    }
}

/// يحد العرض المقترح (النص يلتف أو يصغر عنده) بدون ما يتمدد له — مثل max-width في CSS.
/// (frame(maxWidth:) يتمدد لكل العرض المقترح، فتطلع أرضية الكبسولة بعرض العمود)
struct OccasionM3MaxWidth: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(childProposal(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: childProposal(proposal))
    }

    private func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)
    }
}

/// نص البطاقة مثل عمود CSS بـ flex: 1 و justify-content: center: في الوسط إذا عنده مساحة،
/// وإذا طال عن المساحة يبدأ من فوقها ويكمل تحت (ما يطلع فوق على الصورة)
struct OccasionM3CenterBox: Layout {
    let height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let content = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: max(height, content))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let top = bounds.minY + max(0, (height - size.height) / 2)
        child.place(at: CGPoint(x: bounds.midX, y: top), anchor: .top,
                    proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}
