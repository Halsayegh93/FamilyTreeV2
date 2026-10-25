import Foundation

/// البحث الدقيق الواحد في التطبيق (طلب المالك ٢٠٢٦-١٠-٢٥ «كل بحث في التطبيق يكون دقيق»).
///
/// القاعدة: النص والبحث يُقسَمان كلمات (بعد `ArabicTextNormalizer.normalizeForSearch`)، وكل كلمة من البحث يجب أن
/// تطابق **بداية** كلمة من النص، وبالترتيب نفسه — «محمد علي» تطابق «محمد عبدالله علي …» ولا تطابق «عبدالمحمد».
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

    /// درجة الترتيب (الأصغر أولاً) — nil = لا تطابق: الاسم الأول نفسه تماماً ← ٠، ثم بموضع المطابقة
    static func score(queryWords q: [String], candidateWords c: [String]) -> Int? {
        guard let pos = matchPosition(queryWords: q, candidateWords: c) else { return nil }
        let exactAtPos = c[pos] == q[0]
        if pos == 0 && exactAtPos { return 0 }
        return 1 + pos * 2 + (exactAtPos ? 0 : 1)
    }

    /// يصفّي ويرتّب: المطابق فقط، الاسم الأول التام أولاً ثم الأبكر (والترتيب الأصلي عند التساوي)
    static func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        let q = words(query)
        guard !q.isEmpty else { return items }
        return items.enumerated()
            .compactMap { i, item in score(queryWords: q, candidateWords: words(text(item))).map { (i, $0, item) } }
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
