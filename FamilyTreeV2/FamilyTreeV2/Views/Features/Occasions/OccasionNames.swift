import SwiftUI
import UIKit

// MARK: - الأسماء في البوست: كل اسم سطر واحد — نفس منطق الموقع (familytree-web/src/lib/occasions/names.ts)
//
// كل عنصر اسم (الاسم، العائلة في مشاركة العزاء، اسم الشخص في سطر القرابة) ينرسم بسطر واحد بحجم التصميم.
// إذا الصيغة المطلوبة ما تدخل العمود بـ ٨٥٪ من الحجم أو أكثر، تنختار تلقائياً أطول صيغة أقصر تدخل
// (سداسي ← خماسي ← رباعي ← ثلاثي)؛ وإذا حتى الثلاثي ما دخل يصغر لين يدخل (أقل شي ٦٠٪).
// الصيغة = أول (ن-١) أسماء + الأخير (العائلة).

/// مواصفات سطر اسم في البوست: الوزن، حجم التصميم، العرض المتاح، ارتفاع السطر
struct OccasionNameSlot {
    let weight: OccasionKit.FontWeight
    let size: CGFloat
    let width: CGFloat
    let lineHeight: CGFloat
}

/// عنصر اسم في البوست (سطر واحد)
struct OccasionNameElement {
    /// مفتاح النص في البوست (name / to / relation / rel1…)
    let key: String
    /// عنوانه في الشاشة («الاسم»، «اسم الفقيد»، «اسم العائلة»…)
    let title: String
    /// نص قبل الاسم وبعده (مثل «عائلة » و« الكرام»)
    let prefix: String
    let words: [String]
    let suffix: String

    func name(_ n: Int) -> String { OccasionNames.shorten(words, to: n).joined(separator: " ") }
    func line(_ n: Int) -> String { prefix + name(n) + suffix }
}

/// صيغة اسم وهل تدخل بسطر واحد
struct OccasionNameOption {
    let count: Int
    /// الاسم بهالصيغة (بدون البادئة)
    let name: String
    /// السطر كامل في البوست
    let line: String
    /// نسبة الحجم اللي يحتاجها حتى يدخل (1 = بحجم التصميم)
    let scale: CGFloat
    let label: String
    let fits: Bool
}

/// الصيغة اللي انختارت لعنصر اسم
struct OccasionNameResolution {
    let element: OccasionNameElement
    /// من الأطول للأقصر
    let options: [OccasionNameOption]
    let option: OccasionNameOption
    /// الصيغة المطلوبة (الأطول افتراضياً، أو اللي اختارها المستخدم)
    let requested: Int
    /// اختُصر تلقائياً لأن المطلوب ما يدخل
    let autoShortened: Bool
    /// حتى أقصر صيغة ما دخلت بحجم التصميم كامل — الخط أصغر
    let shrunk: Bool
}

enum OccasionNames {
    /// أقل نسبة من حجم التصميم تُقبل فيها الصيغة (أقل منها نختصر الاسم)
    static let fitThreshold: CGFloat = 0.85
    /// أصغر حجم للاسم إذا ما دخل حتى بأقصر صيغة
    static let minScale: CGFloat = 0.6
    /// أطول صيغة: سداسي
    static let maxWords = 6
    /// أقصر صيغة تنختصر لها الأسماء: ثلاثي
    static let minWords = 3

    /// «ثلاثي / رباعي / خماسي / سداسي» حسب عدد الأسماء
    static func formatLabel(_ count: Int) -> String {
        switch count {
        case ...1: return L10n.t("اسم واحد", "1 name")
        case 2: return L10n.t("ثنائي", "2 names")
        case 3: return L10n.t("ثلاثي", "3 names")
        case 4: return L10n.t("رباعي", "4 names")
        case 5: return L10n.t("خماسي", "5 names")
        default: return L10n.t("سداسي", "6 names")
        }
    }

    // MARK: الكلمات والصيغ

    private static let joinNext: Set<String> = ["عبد", "أبو", "ابو", "بو"]

    /// كلمات الاسم — «عبد/أبو + الاسم» و«المحمد علي» تنحسب اسم واحد (ما ينفصلون بالبوست أصلاً)
    static func words(_ name: String) -> [String] {
        let raw = name.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [String] = []
        var i = 0
        while i < raw.count {
            let w = raw[i]
            if i + 1 < raw.count && (joinNext.contains(w) || (w == "المحمد" && raw[i + 1] == "علي")) {
                out.append(w + " " + raw[i + 1])
                i += 2
            } else {
                out.append(w)
                i += 1
            }
        }
        return out
    }

    /// أول (n-1) أسماء + الأخير (العائلة)
    static func shorten(_ words: [String], to n: Int) -> [String] {
        guard words.count > n, n >= 2, let last = words.last else { return words }
        return Array(words.prefix(n - 1)) + [last]
    }

    /// الاسم المكتوب أو من الشجرة: أقصى شي سداسي
    static func capped(_ name: String) -> String {
        shorten(words(name), to: maxWords).joined(separator: " ")
    }

    // MARK: سطور القرابة

    /// كلمات القرابة واللقب اللي تسبق الاسم في سطر القرابة («ابن المرحوم …»)
    private static let relationWords: Set<String> = [
        "ابن", "ابنة", "بنت", "زوج", "زوجة", "حرم", "أرملة", "والد", "والدة", "شقيق", "شقيقة", "أخ", "أخت",
        "حفيد", "حفيدة", "المرحوم", "المرحومة", "الحاج", "الحاجة", "المغفور", "له", "لها",
    ]

    /// سطر قرابة فيه اسم شخص واحد («ابن المرحوم صالح حسن المحمدعلي»، «زوج: فاطمة أحمد») → البادئة وكلمات الاسم.
    /// القوائم («والد كل من: علي، حسين») والسطور بدون بادئة قرابة ترجع nil وتبقى تلتف مثل التصميم.
    static func relationName(_ line: String) -> (prefix: String, words: [String])? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.contains("،") || t.contains(",") || t.contains("كل من") { return nil }
        var tokens = t.split(whereSeparator: \.isWhitespace).map(String.init)
        var prefix: [String] = []
        if let colon = tokens.firstIndex(where: { $0.hasSuffix(":") }), colon < 3 {
            prefix += tokens[...colon]
            tokens = Array(tokens[(colon + 1)...])
        }
        while tokens.count > 1, relationWords.contains(tokens[0]) {
            prefix.append(tokens.removeFirst())
        }
        guard !prefix.isEmpty, !tokens.isEmpty else { return nil }
        return (prefix.joined(separator: " ") + " ", words(tokens.joined(separator: " ")))
    }

    // MARK: القياس واختيار الصيغة

    /// عرض النص بخط البوست — nil إذا الخط ما تحمّل بعد (كل شي يعتبر داخل لين يتحمّل)
    static func measure(_ text: String, weight: OccasionKit.FontWeight, size: CGFloat) -> CGFloat? {
        guard let font = UIFont(name: weight.postScriptName, size: size) else { return nil }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// نسبة الحجم اللي يحتاجها النص حتى يدخل بسطر واحد (1 = يدخل بحجم التصميم)
    static func scaleToFit(_ text: String, slot: OccasionNameSlot) -> CGFloat {
        let t = text.replacingOccurrences(of: "\n", with: " ")
        guard !t.isEmpty, slot.width > 0, let w = measure(t, weight: slot.weight, size: slot.size), w > 0 else { return 1 }
        return w <= slot.width + 0.01 ? 1 : slot.width / w
    }

    /// الصيغ المتاحة من الأطول للأقصر (سداسي … ثلاثي)؛ الاسم القصير له صيغة وحدة
    static func counts(_ e: OccasionNameElement) -> [Int] {
        let top = min(e.words.count, maxWords)
        if top <= minWords { return top > 0 ? [top] : [] }
        return Array((minWords...top).reversed())
    }

    /// أطول صيغة ≤ المطلوب تدخل بـ ٨٥٪ أو أكثر؛ وإلا أقصر صيغة (تصغر لين تدخل)
    static func resolve(_ e: OccasionNameElement, slot: OccasionNameSlot?, requested: Int) -> OccasionNameResolution? {
        let options: [OccasionNameOption] = counts(e).map { n in
            let line = e.line(n)
            let scale = slot.map { scaleToFit(OccasionText.postText(line), slot: $0) } ?? 1
            return OccasionNameOption(count: n, name: e.name(n), line: line, scale: scale, label: formatLabel(n), fits: scale >= fitThreshold)
        }
        guard let shortest = options.last else { return nil }
        let option = options.first { $0.count <= requested && $0.fits } ?? shortest
        let longest = options.first?.count ?? requested
        return OccasionNameResolution(element: e, options: options, option: option, requested: requested,
                                      autoShortened: option.count < min(requested, longest), shrunk: option.scale < 1)
    }
}
