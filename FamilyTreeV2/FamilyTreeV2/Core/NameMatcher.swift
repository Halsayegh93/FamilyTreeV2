import Foundation

// MARK: - مطابقة الأسماء العربية (طلب المالك ٢٠٢٦-١٠-٢٤: «عند ربط الاسم و عرض الاسماء المتشابهة ابي تقريب الاسم اكثر نظم الالية»)
//
// تُستعمل في «الوارد» ← طلب الانضمام ← المطابقات في الشجرة (`AdminAllRequestsView.orderedMatchList`). دوال صافية:
// ١) التطبيع: `ArabicTextNormalizer` (التشكيل، أ إ آ ٱ ← ا، ة ← ه، ى ← ي) + التطويل يُحذف + ئ ← ي، ؤ ← و،
//    وكل ما ليس حرفاً (شَرطة، نقطة، فاصلة) مسافة.
// ٢) الوحدات: «عبد/ابو/بو» تلتصق بما بعدها بلا مسافة («عبد الله» = «عبدالله»)، «المحمد علي» = «المحمدعلي»،
//    والكلمة التي تبدأ بـ«ال» (غير الأخيرة) تلتصق بما قبلها («زين العابدين» وحدة) — نفس قاعدة `PersonName.units`.
//    الروابط «بن/ابن/بنت» تُحذف.
// ٣) اسم العائلة في الآخر يُحذف: قائمة `family_names` (`FamilyNameCatalog.known`) + «المحمدعلي».
// ٤) المقارنة بالترتيب: الأول مع الأول، الأب مع الأب، الجد مع الجد… بوزن ٥ · ٤ · ٣ · ٢ ثم ١ لكل ما بعدها،
//    والنتيجة = مجموع أوزان المتطابق ÷ مجموع أوزان أجزاء اسم المتقدّم (أجزاء الشجرة الزائدة لا تُنقص).
// ٥) فرق حرف واحد مقبول (بنصف الثقة تقريباً — ٠٫٧٥) للكلمات من ٤ أحرف فأكثر بنفس الحرف الأول؛ والزيادة/النقص
//    بحرف من ٥ أحرف فأكثر فقط — حتى لا تتطابق «محمد/احمد» ولا «محمد/محمود» ولا «حسن/حسين».
// ٦) يُعرض المرشّح حين تتطابق أول ٣ أجزاء بالترتيب (أو كلها إن كانت أقل) — قاعدة المالك السابقة: «علي طارق علي حسين»
//    لا يجد «علي طارق موسى».
enum NameMatcher {

    struct Result: Equatable {
        /// ٠…١ — موزونة بالترتيب
        let score: Double
        /// أجزاء اسم المتقدّم المتطابقة (مطبَّعة)
        let matched: [String]
        /// منها بفرق حرف واحد
        let fuzzy: Int
        /// عدد أجزاء اسم المتقدّم (بلا العائلة والروابط)
        let total: Int
        /// المتطابق متتالياً من البداية
        let prefix: Int

        var percent: Int { Int((score * 100).rounded()) }

        /// يكفي للعرض: أول ٣ أجزاء بالترتيب (أو كلها إن كانت أقل)
        var isStrong: Bool { total > 0 && prefix >= min(3, total) }

        static let none = Result(score: 0, matched: [], fuzzy: 0, total: 0, prefix: 0)
    }

    static let connectors: Set<String> = ["بن", "ابن", "بنت"]
    static let joinNext: Set<String> = ["عبد", "ابو", "بو"]
    /// اسم العائلة الثابت (إضافة لقائمة `family_names`)
    static let fixedFamilies: [String] = ["المحمدعلي", "المحمد علي"]

    // MARK: التطبيع والوحدات

    private static var tokenCache: [String: [String]] = [:]

    /// وحدات الاسم المطبَّعة (قبل حذف العائلة) — محفوظة لكل نص
    static func tokens(_ name: String) -> [String] {
        if let hit = tokenCache[name] { return hit }
        var t = ArabicTextNormalizer.normalizeForSearch(name)
        t = t.replacingOccurrences(of: "\u{0640}", with: "")            // تطويل
            .replacingOccurrences(of: "\u{0626}", with: "\u{064A}")    // ئ ← ي
            .replacingOccurrences(of: "\u{0624}", with: "\u{0648}")    // ؤ ← و
        let raw = String(t.map { $0.isLetter ? $0 : " " })
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !connectors.contains($0) }
        var out: [String] = []
        var i = 0
        while i < raw.count {
            let w = raw[i]
            let isLast = i == raw.count - 1
            if !isLast && (joinNext.contains(w) || (w == "المحمد" && raw[i + 1] == "علي")) {
                out.append(w + raw[i + 1])
                i += 2
            } else if !isLast, w.count > 2, w.hasPrefix("ال"), !out.isEmpty {
                out[out.count - 1] += w
                i += 1
            } else {
                out.append(w)
                i += 1
            }
        }
        if tokenCache.count > 8000 { tokenCache.removeAll(keepingCapacity: true) }
        tokenCache[name] = out
        return out
    }

    /// أسماء العوائل مطبَّعة بنفس الطريقة (قائمة الإدارة + «المحمدعلي»)
    static func familyKeys() -> Set<String> {
        var keys = Set<String>()
        for name in Array(FamilyNameCatalog.known) + fixedFamilies {
            let k = tokens(name).joined()
            if !k.isEmpty { keys.insert(k) }
        }
        return keys
    }

    /// سلسلة الاسم للمقارنة: الوحدات بلا اسم العائلة في آخرها
    static func chain(_ name: String, families: Set<String>) -> [String] {
        var parts = tokens(name)
        while parts.count > 1, let last = parts.last, families.contains(last) { parts.removeLast() }
        return parts
    }

    // MARK: المقارنة

    /// وزن الموضع: الأول ٥، الأب ٤، الجد ٣، ثم ٢، ثم ١ لكل ما بعدها
    static func weight(_ index: Int) -> Double { Double(max(1, 5 - index)) }

    /// ١ تطابق، ٠٫٧٥ فرق حرف واحد، ٠ مختلف
    static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        return isTypo(a, b) ? 0.75 : 0
    }

    /// فرق حرف واحد: ٤ أحرف فأكثر وبنفس الحرف الأول، والزيادة/النقص من ٥ أحرف فأكثر
    static func isTypo(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        let shorter = min(x.count, y.count)
        guard shorter >= 4, abs(x.count - y.count) <= 1, x.first == y.first else { return false }
        if x.count != y.count && shorter < 5 { return false }
        return editDistance(x, y) <= 1
    }

    /// مسافة التعديل (Levenshtein)
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    /// مقارنة سلسلتين بالترتيب — `applicant` اسم المتقدّم، `candidate` اسم عضو الشجرة
    static func compare(_ applicant: [String], _ candidate: [String]) -> Result {
        guard !applicant.isEmpty, !candidate.isEmpty else { return .none }
        var got = 0.0, total = 0.0
        var matched: [String] = []
        var fuzzy = 0, prefix = 0
        var inPrefix = true
        for i in applicant.indices {
            let w = weight(i)
            total += w
            let s = i < candidate.count ? similarity(applicant[i], candidate[i]) : 0
            if s > 0 {
                got += w * s
                matched.append(applicant[i])
                if s < 1 { fuzzy += 1 }
                if inPrefix { prefix += 1 }
            } else {
                inPrefix = false
            }
        }
        return Result(score: total > 0 ? got / total : 0, matched: matched, fuzzy: fuzzy,
                      total: applicant.count, prefix: prefix)
    }

    /// مقارنة نصّين كاملين (بحذف العائلة من الطرفين)
    static func compare(applicant: String, candidate: String, families: Set<String>) -> Result {
        compare(chain(applicant, families: families), chain(candidate, families: families))
    }

    /// الترتيب: النتيجة الأعلى، ثم الأطول تطابقاً من البداية
    static func ranksBefore(_ a: Result, _ b: Result) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.prefix > b.prefix
    }
}
