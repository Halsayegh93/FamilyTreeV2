import Foundation

/// البحث الدقيق الواحد في التطبيق (طلب المالك ٢٠٢٦-١٠-٢٥ «كل بحث في التطبيق يكون دقيق»).
///
/// القاعدة: النص والبحث يُقسَمان كلمات (بعد `ArabicTextNormalizer.normalizeForSearch`).
/// - النصوص العامة (`matches`): كل كلمة من البحث تطابق **بداية** كلمة من النص وبالترتيب — «محمد علي» تطابق
///   «محمد عبدالله علي …» ولا تطابق «عبدالمحمد».
/// - أسماء الأشخاص (`filter` / `score` / `chainMatch`): الكلمات **متتالية** في السلسلة (الاسم ← الأب ← الجد) فتضيق
///   القائمة مع كل كلمة، والفراغ داخل المركّب لا يهمّ («محمدحسين» = «محمد حسين»).
/// «عبد» تُلصق بما بعدها في الطرفين («عبد الله» = «عبدالله»، و«عبد ال» تطابق «عبدالله»).
/// الترتيب: الاسم الأول المطابق تماماً أولاً، ثم الأبكر مطابقةً. الهاتف: أرقام فقط بعد توحيد الأرقام العربية.
enum NameSearch {

    /// ذاكرة الكلمات لكل نص — البحث يعيد تطبيع آلاف الأسماء مع كل حرف (كان سبب البطء في «أبوها»)؛ NSCache آمن بين الخيوط
    private static let wordsCache: NSCache<NSString, NSArray> = {
        let c = NSCache<NSString, NSArray>(); c.countLimit = 20_000; return c
    }()

    /// كلمات النص للبحث — موحّدة، بلا رموز، و«عبد» ملصقة بما بعدها
    static func words(_ text: String) -> [String] {
        if let hit = wordsCache.object(forKey: text as NSString) as? [String] { return hit }
        let out = computeWords(text)
        wordsCache.setObject(out as NSArray, forKey: text as NSString)
        return out
    }

    private static func computeWords(_ text: String) -> [String] {
        let normalized = ArabicTextNormalizer.normalizeForSearch(text)
        let parts = normalized
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
        var out: [String] = []
        var i = 0
        while i < parts.count {
            if parts[i] == "عبد", i + 1 < parts.count {
                out.append(parts[i] + parts[i + 1]); i += 2
            } else {
                out.append(parts[i]); i += 1
            }
        }
        return out
    }

    /// موضع أول كلمة طابقت (٠ = الكلمة الأولى) — nil = لا تطابق
    static func matchPosition(queryWords q: [String], candidateWords c: [String]) -> Int? {
        guard !q.isEmpty else { return nil }
        var from = 0
        var first: Int?
        for word in q {
            guard let hit = c[from...].firstIndex(where: { $0.hasPrefix(word) }) else { return nil }
            if first == nil { first = hit }
            from = hit + 1
            if from > c.count { return nil }
        }
        return first
    }

    static func matches(query: String, candidate: String) -> Bool {
        matchPosition(queryWords: words(query), candidateWords: words(candidate)) != nil
    }

    /// يطابق أي نص من النصوص (الاسم، العنوان، المعاينة…)
    static func matches(query: String, any candidates: [String]) -> Bool {
        let q = words(query)
        return candidates.contains { matchPosition(queryWords: q, candidateWords: words($0)) != nil }
    }

    /// مطابقة سلسلة الاسم (طلب المالك ٢٠٢٦-١١-٠٧ «الاسم الصحيح يطلع آخر» و«ليش ما تتقلص الأسماء»):
    /// كلمات البحث **متتالية** في سلسلة الاسم (الاسم ← الأب ← الجد …) بلا فجوات، والكلمة الأخيرة قد تكون بداية كلمة
    /// (ما زال يكتب). الفراغ داخل الأسماء المركّبة لا يهمّ: «محمدحسين» = «محمد حسين» في الطرفين (تُقارَن الحروف متّصلة).
    /// يرجع موضع البداية ودرجة (الأصغر أولاً): الموضع × ٢، + ١ لو الكلمة الأخيرة ناقصة («علي محمد» على «علي محمدحسين»).
    /// `fromStart`: البداية من الاسم الأول فقط.
    static func chainMatch(queryWords q: [String], candidateWords c: [String], fromStart: Bool = false) -> (pos: Int, rank: Int)? {
        guard !q.isEmpty, !c.isEmpty else { return nil }
        let joined = q.joined()
        let total = joined.utf16.count
        let starts = fromStart ? 0..<1 : 0..<c.count
        for s in starts {
            let head = c[s]
            // فحص سريع: الكلمة الأولى في السلسلة بداية البحث أو البحث بدايتها
            guard joined.hasPrefix(head) || head.hasPrefix(joined) else { continue }
            var text = ""
            var cBounds: Set<Int> = []
            var j = s
            while text.utf16.count < total, j < c.count {
                text += c[j]; cBounds.insert(text.utf16.count); j += 1
            }
            guard text.utf16.count >= total, text.hasPrefix(joined) else { continue }
            // حدود الكلمات الداخلية لا تُحسب: «محمد حسين» و«محمدحسين» سواء
            let wholeLast = cBounds.contains(total)
            return (s, s * 2 + (wholeLast ? 0 : 1))
        }
        return nil
    }

    /// درجة الترتيب لسلاسل الأسماء (الأصغر أولاً) — nil = لا تطابق. بقاعدة `chainMatch`: السلسلة التامة من الاسم الأول
    /// ← ٠، ثم الناقصة، ثم من موضع أبعد
    static func score(queryWords q: [String], candidateWords c: [String], fromStart: Bool = false) -> Int? {
        chainMatch(queryWords: q, candidateWords: c, fromStart: fromStart)?.rank
    }

    /// يصفّي ويرتّب أسماء الأشخاص: المطابق فقط (سلسلة متتالية — كل كلمة إضافية تضيّق القائمة)، والأقرب أولاً
    /// (والترتيب الأصلي عند التساوي). `fromFirstName`: السلسلة تبدأ من الاسم الأول نفسه («علي حسين» = علي بن حسين —
    /// لا أبناؤه ولا أحفاده الذين في أسمائهم «علي»)؛ لمنتقيات الشخص مثل «أبوها»
    static func filter<T>(_ items: [T], query: String, fromFirstName: Bool = false, text: (T) -> String) -> [T] {
        let q = words(query)
        guard !q.isEmpty else { return items }
        return items.enumerated()
            .compactMap { i, item -> (Int, Int, T)? in
                score(queryWords: q, candidateWords: words(text(item)), fromStart: fromFirstName).map { (i, $0, item) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map(\.2)
    }

    // MARK: الهاتف

    /// أرقام فقط (العربية والفارسية ← لاتينية)
    static func digits(_ text: String) -> String {
        String(text.compactMap { ch -> Character? in
            guard let v = ch.wholeNumberValue, ch.isNumber else { return nil }
            return Character(String(v))
        })
    }

    /// بحث رقم: ٣ أرقام على الأقل، والرقم يحويها (بعد التوحيد)
    static func phoneMatches(query: String, phone: String?) -> Bool {
        let q = digits(query)
        guard q.count >= 3, let phone else { return false }
        return digits(phone).contains(q)
    }

    /// البحث أرقام فقط؟ (يُبحث بالهاتف لا بالاسم)
    static func isPhoneQuery(_ query: String) -> Bool {
        let t = query.filter { !$0.isWhitespace && $0 != "+" }
        return !t.isEmpty && t.allSatisfy(\.isNumber)
    }
}
