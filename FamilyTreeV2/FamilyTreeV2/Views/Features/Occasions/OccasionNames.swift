import SwiftUI

// MARK: - الأسماء في البوست: كل اسم سطر واحد
//
// كل عنصر اسم (الاسم، العائلة في مشاركة العزاء، اسم الشخص في سطر القرابة) ينرسم بسطر واحد بحجم التصميم.
// إذا الصيغة الحالية ما تدخل العمود بـ ٨٥٪ من الحجم أو أكثر، تنختار تلقائياً أطول صيغة أقصر تدخل
// (سداسي ← خماسي ← رباعي ← ثلاثي)؛ وإذا حتى الثلاثي ما دخل يصغر لين يدخل (أقل شي ٦٠٪).
// الصيغة = أول (ن-١) أسماء + الأخير (العائلة) — نفس قاعدة أسماء الشجرة، وللاسم المكتوب بعد.

enum OccasionNames {
    /// أقل نسبة من حجم التصميم تُقبل فيها الصيغة (أقل منها نختصر الاسم)
    static let fitScale: CGFloat = 0.85
    /// أصغر حجم للاسم (أو العنوان القصير) إذا ما دخل حتى بأقصر صيغة
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

    /// كلمات الاسم — «عبد/أبو + الاسم» و«المحمد علي» تنحسب اسم واحد (ما ينفصلون بالبوست أصلاً)
    static func words(_ name: String) -> [String] {
        let raw = name.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [String] = []
        var i = 0
        while i < raw.count {
            let w = raw[i]
            if i + 1 < raw.count, ["عبد", "أبو", "ابو", "بو"].contains(w) || (w == "المحمد" && raw[i + 1] == "علي") {
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

    /// الاسم المكتوب: أقصى شي سداسي
    static func capped(_ name: String) -> String {
        shorten(words(name), to: maxWords).joined(separator: " ")
    }

    // MARK: سطور القرابة

    /// كلمات القرابة واللقب اللي تسبق الاسم في سطر القرابة («ابن المرحوم …»)
    private static let relationWords: Set<String> = [
        "ابن", "ابنة", "بنت", "زوج", "زوجة", "حرم", "أرملة", "والد", "والدة", "شقيق", "شقيقة", "أخ", "أخت",
        "حفيد", "حفيدة", "المرحوم", "المرحومة", "الحاج", "الحاجة", "المغفور", "له", "لها",
    ]

    /// سطر قرابة فيه اسم شخص واحد («ابن المرحوم صالح حسن المحمدعلي»، «زوج: فاطمة أحمد») → (البادئة، كلمات الاسم).
    /// القوائم («والد كل من: علي، حسين») والسطور بدون بادئة قرابة ترجع nil وتبقى تلتف مثل التصميم.
    static func relationName(_ line: String) -> (prefix: String, words: [String])? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("،"), !t.contains(","), !t.contains("كل من") else { return nil }
        var tokens = t.split(whereSeparator: \.isWhitespace).map(String.init)
        var prefix: [String] = []
        if let colon = tokens.firstIndex(where: { $0.hasSuffix(":") }), colon < 3 {
            prefix = Array(tokens[...colon])
            tokens.removeFirst(colon + 1)
        }
        while tokens.count > 1, let first = tokens.first, relationWords.contains(first) {
            prefix.append(first)
            tokens.removeFirst()
        }
        guard !prefix.isEmpty, !tokens.isEmpty else { return nil }
        return (prefix.joined(separator: " ") + " ", words(tokens.joined(separator: " ")))
    }
}

/// عنصر اسم في البوست (سطر واحد)
struct OccasionNameElement: Identifiable {
    /// مفتاح النص في البوست (name / to / relation / rel1…)
    let key: String
    /// عنوانه في الشاشة («الاسم»، «اسم الفقيد»، «اسم العائلة»…)
    let title: String
    /// نص قبل الاسم وبعده (مثل «عائلة » و« الكرام»)
    var prefix: String = ""
    let words: [String]
    var suffix: String = ""

    var id: String { key }

    func name(_ n: Int) -> String { OccasionNames.shorten(words, to: n).joined(separator: " ") }
    func line(_ n: Int) -> String { prefix + name(n) + suffix }

    /// الصيغ المتاحة من الأطول للأقصر (سداسي … ثلاثي)؛ الاسم القصير له صيغة وحدة
    var counts: [Int] {
        let top = min(words.count, OccasionNames.maxWords)
        guard top > OccasionNames.minWords else { return top > 0 ? [top] : [] }
        return Array(stride(from: top, through: OccasionNames.minWords, by: -1))
    }
}

/// صيغة اسم وهل تدخل بسطر واحد
struct OccasionNameOption: Identifiable {
    /// عدد الأسماء بهالصيغة
    let count: Int
    /// الاسم بهالصيغة (بدون البادئة)
    let name: String
    /// السطر كامل في البوست
    let line: String
    /// نسبة الحجم اللي يحتاجها حتى يدخل (1 = بحجم التصميم)
    let scale: CGFloat

    var id: Int { count }
    var label: String { OccasionNames.formatLabel(count) }
    var fits: Bool { scale >= OccasionNames.fitScale }
    /// يدخل بسطر واحد ولو بخط أصغر (أقل شي ٦٠٪) — يقدر المستخدم يختاره بنفسه
    var usable: Bool { scale >= OccasionNames.minScale }
}

/// الصيغة اللي انختارت لعنصر اسم
struct OccasionNameResolution: Identifiable {
    let element: OccasionNameElement
    /// من الأطول للأقصر
    let options: [OccasionNameOption]
    let chosen: Int
    /// الصيغة المطلوبة (الأطول افتراضياً، أو اللي اختارها المستخدم)
    let requested: Int

    var id: String { element.key }
    var option: OccasionNameOption { options[chosen] }
    /// اختُصر تلقائياً لأن المطلوب ما يدخل
    var autoShortened: Bool { option.count < min(requested, options.first?.count ?? requested) }
    /// حتى أقصر صيغة ما دخلت بحجم التصميم كامل — الخط أصغر
    var shrunk: Bool { option.scale < 1 }

    /// تلقائياً: أطول صيغة ≤ المطلوب تدخل بـ ٨٥٪ أو أكثر؛ وإلا أقصر صيغة (تصغر لين تدخل).
    /// اختيار المستخدم (explicit) ينفّذ كما هو إذا يدخل بسطر واحد ولو بخط أصغر — طلب المالك ٢٠٢٦-١٠-١٣
    /// «ليش ما يشتغل خيار طول الاسم ثلاثي رباعي خماسي؟» (كان يرجع للأقصر بصمت)
    init(_ element: OccasionNameElement, slot: OccasionNameSlot?, requested: Int, explicit: Bool = false) {
        self.element = element
        self.requested = requested
        let list = element.counts.map { n in
            let line = element.line(n)
            let scale = slot.map {
                OccasionTextLayout.fitScale(OccasionText.postText(line), weight: $0.weight, size: $0.size, maxWidth: $0.width)
            } ?? 1
            return OccasionNameOption(count: n, name: element.name(n), line: line, scale: scale)
        }
        options = list
        let allowed = list.indices.filter { list[$0].count <= requested }
        if explicit, let exact = list.indices.first(where: { list[$0].count == requested && list[$0].usable }) {
            chosen = exact
        } else {
            chosen = allowed.first { list[$0].fits } ?? max(0, list.count - 1)
        }
    }
}
