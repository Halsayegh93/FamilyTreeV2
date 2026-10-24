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

// MARK: - ربط طلب الانضمام بسجلّ في الشجرة (طلب المالك ٢٠٢٦-١٠-٢٤: «تطلع اسماء ماله شغل بالربط»)
//
// صارم ومرتّب — يُستعمل في «الوارد» ← طلب الانضمام ← «في الشجرة» (`AdminAllRequestsView.orderedMatchList`):
// ١) الاسم الأول يطابق بعد التطبيع، ثم الأب ثم الجد… بالترتيب. الاسم المركّب وحدة واحدة: سلسلة الشجرة
//    (`PersonName.chainUnits`) ونصّ المتقدّم (`PersonName.units`)؛ وما بين القوسين لقب لا يُقارن («ابراهيم(العطار)» = «ابراهيم»).
// ٢) العائلة في آخر الاسم ضجيج لا دليل: «المحمدعلي»/«محمدعلي» وعوائل القائمة والعائلة المختارة.
// ٣) لا يُقترح إلا من طابق الاسم الأول والأب على الأقل، ويُعرض السبب («الاسم الأول + الأب + الجد»).
// ٤) الترتيب بعمق التطابق، ثم قرب تاريخ الميلاد إن عُرف للطرفين. (من له حساب أو متوفى يُستبعد قبل الاستدعاء)
extension NameMatcher {

    /// أقلّ عمق للاقتراح: الاسم الأول + الأب
    static let minLinkDepth = 2

    /// مفتاح وحدة للربط: بلا ما بين القوسين، ثم التطبيع نفسه (`tokens`) ملصوقاً — «عبد الله» = «عبدالله»
    static func linkKey(_ unit: String) -> String {
        var plain = ""
        var depth = 0
        for ch in unit {
            if ch == "(" || ch == "[" { depth += 1 }
            else if ch == ")" || ch == "]" { depth = max(0, depth - 1) }
            else if depth == 0 { plain.append(ch) }
        }
        return tokens(plain).joined()
    }

    /// مفاتيح الضجيج في آخر الاسم: عوائل القائمة + «المحمدعلي» و«محمدعلي» + عائلة مختارة إن وُجدت
    static func linkNoise(_ extra: String? = nil) -> Set<String> {
        var keys = familyKeys()
        keys.insert(linkKey("محمدعلي"))
        if let extra {
            let k = linkKey(extra)
            if !k.isEmpty { keys.insert(k) }
        }
        return keys
    }

    /// سلسلة الربط: مفاتيح الوحدات (بلا الروابط) وبلا الضجيج في آخرها
    static func linkChain(_ units: [String], noise: Set<String>) -> [String] {
        var keys = units.map { linkKey($0) }.filter { !$0.isEmpty }
        while let last = keys.last, noise.contains(last) { keys.removeLast() }
        return keys
    }

    /// عمق التطابق من البداية بالترتيب — الاسم المركّب قد يُكتب كلمتين في طرف وكلمة في الآخر
    static func linkDepth(_ a: [String], _ b: [String]) -> Int {
        var i = 0, j = 0, depth = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { i += 1; j += 1 }
            else if i + 1 < a.count, a[i] + a[i + 1] == b[j] { i += 2; j += 1 }
            else if j + 1 < b.count, a[i] == b[j] + b[j + 1] { i += 1; j += 2 }
            else { break }
            depth += 1
        }
        return depth
    }

    /// سبب الاقتراح: «الاسم الأول + الأب + الجد»
    static func linkReason(depth: Int) -> String {
        var parts = [L10n.t("الاسم الأول", "First name")]
        if depth >= 2 { parts.append(L10n.t("الأب", "father")) }
        if depth >= 3 { parts.append(L10n.t("الجد", "grandfather")) }
        if depth == 4 { parts.append(L10n.t("جد الأب", "great-grandfather")) }
        if depth > 4 { parts.append(L10n.t("\(depth - 3) أجداد", "\(depth - 3) more ancestors")) }
        return parts.joined(separator: " + ")
    }

    /// تاريخ الميلاد للمقارنة: «yyyy-MM-dd» أو السنة وحدها
    static func linkBirth(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        if raw.count >= 10, let d = f.date(from: String(raw.prefix(10))) { return d }
        f.dateFormat = "yyyy"
        return f.date(from: String(raw.prefix(4)))
    }

    struct LinkSuggestion {
        let member: FamilyMember
        /// كم جزءاً من السلسلة تطابق بالترتيب (٢ = الأول + الأب)
        let depth: Int
        /// أجزاء سلسلة المتقدّم (بلا العائلة)
        let total: Int
        /// فرق الميلاد بالأيام — nil إن جُهل أحدهما
        let birthGapDays: Int?
        /// وجده بحث السيرفر أيضاً (`search_members_by_name` أو لقطة التسجيل)
        let isServer: Bool
    }

    /// المقترحون للربط مرتّبين — `candidates` سجلّات الشجرة المسموح بها (الاستبعاد عند المستدعي)
    static func linkSuggestions(for applicant: FamilyMember, among candidates: [FamilyMember],
                                serverIds: Set<UUID> = [], limit: Int = 20) -> [LinkSuggestion] {
        let noise = linkNoise(applicant.familyName)
        let chainA = linkChain(applicant.nameUnits, noise: noise)
        guard chainA.count >= minLinkDepth, let firstA = chainA.first else { return [] }
        let birthA = linkBirth(applicant.birthDate)
        var out: [LinkSuggestion] = []
        for m in candidates {
            // فحص سريع بالاسم الأول قبل بناء السلسلة (آلاف السجلّات)
            let full = m.fullName.trimmingCharacters(in: .whitespaces)
            let first = full.hasPrefix(m.firstName) ? m.firstName : PersonName.firstUnit(full)
            let firstKey = linkKey(first)
            guard firstKey == firstA || firstA.hasPrefix(firstKey) || firstKey.hasPrefix(firstA) else { continue }
            let chainB = linkChain(m.nameUnits, noise: m.familyName.map { noise.union([linkKey($0)]) } ?? noise)
            let depth = linkDepth(chainA, chainB)
            guard depth >= minLinkDepth else { continue }
            let gap: Int? = birthA.flatMap { a in
                linkBirth(m.birthDate).map { Int(abs(a.timeIntervalSince($0)) / 86_400) }
            }
            out.append(LinkSuggestion(member: m, depth: depth, total: chainA.count, birthGapDays: gap,
                                      isServer: serverIds.contains(m.id)))
        }
        out.sort { a, b in
            if a.depth != b.depth { return a.depth > b.depth }
            switch (a.birthGapDays, b.birthGapDays) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if a.isServer != b.isServer { return a.isServer }
            return a.member.fullName.localizedStandardCompare(b.member.fullName) == .orderedAscending
        }
        return Array(out.prefix(limit))
    }
}
