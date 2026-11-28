import Foundation

// MARK: - «الأخطاء» بالعربي (طلب المالك ٢٠٢٦-١١-٢٧: «يصير يعطيني sentry المشكلة بالعربي؟»)
//
// عنوان Sentry يصل بالإنجليزية. هنا: عنوان عربي + سطر واحد بسيط لكل نوع معروف، والعنوان الأصلي يبقى صغيراً تحته للمرجع.
// خالص (Foundation فقط) ليُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/e1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminErrorTitles.swift tests/admin-redesign/E1/main.swift \
//     && /private/tmp/claude-501/e1-logic

nonisolated struct AdminErrorArabic: Equatable {
    enum Kind: String, Equatable {
        case hang, killed, crash, network, web, unknown
    }

    let kind: Kind
    /// العنوان بالعربي («التطبيق علّق 6–7 ثوانٍ»). للنوع غير المعروف = العنوان الأصلي كما هو
    let title: String
    /// سطر واحد بسيط تحته
    let line: String
    /// يُعرض العنوان الأصلي صغيراً تحته؟ (لا، إن كان هو العنوان نفسه)
    var showsOriginal: Bool { kind != .unknown }

    /// `title` من Sentry، و`platform` = ios · android · web · other
    static func describe(_ rawTitle: String, platform: String = "") -> AdminErrorArabic {
        let original = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = original.lowercased()
        let head = Self.head(original)

        // ١) تعليق: «App Hang Fully Blocked / Non Fully Blocked: App hanging between X and Y seconds» · «App Hanging: … at least N ms» · أندرويد ANR
        if lower.hasPrefix("app hang") || lower.contains("app hanging") || lower.hasPrefix("applicationnotresponding") || lower.hasPrefix("anr ") || lower.hasPrefix("anr:") {
            return AdminErrorArabic(kind: .hang, title: hangTitle(lower), line: "الشاشة توقفت عن الاستجابة")
        }

        // ٢) النظام أغلق التطبيق
        if lower.hasPrefix("watchdogtermination") || lower.contains("watchdog terminated") {
            return AdminErrorArabic(kind: .killed, title: "النظام أغلق التطبيق",
                                    line: "غالباً استهلاك ذاكرة كبير، أو أُعيد تثبيت النسخة نفسها أثناء عملها")
        }

        // ٣) خطأ اتصال بالسيرفر (قبل «الموقع» — «TypeError: Failed to fetch» اتصال لا خطأ صفحة)
        if networkMarkers.contains(where: { lower.contains($0) }) || firstMatch(#"\bhttp ?[1-5][0-9]{2}\b"#, in: lower) != nil {
            return AdminErrorArabic(kind: .network, title: "خطأ اتصال بالسيرفر", line: networkLine(lower))
        }

        // ٤) توقّف مفاجئ (iOS وأندرويد)
        if let why = crashReason(head: head, lower: lower) {
            return AdminErrorArabic(kind: .crash, title: "توقّف التطبيق فجأة", line: why)
        }

        // ٥) خطأ في الموقع: «Error: …» أو أخطاء JavaScript من الموقع
        if head == "Error" || (platform == "web" && (head.hasSuffix("Error") || head == "UnhandledRejection")) {
            return AdminErrorArabic(kind: .web, title: "خطأ في الموقع", line: "صفحة في الموقع لم تعمل كما يجب")
        }

        return AdminErrorArabic(kind: .unknown, title: original.isEmpty ? "—" : original, line: "خطأ غير مصنّف")
    }

    // MARK: التفاصيل

    /// ما قبل أول «: » («EXC_BAD_ACCESS» · «Fatal error» · «Error»)
    static func head(_ title: String) -> String {
        guard let r = title.range(of: ": ") else { return title.trimmingCharacters(in: .whitespaces) }
        return String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// ما بعد أول «: »
    static func reason(_ title: String) -> String {
        guard let r = title.range(of: ": ") else { return "" }
        return String(title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// «التطبيق علّق 6–7 ثوانٍ» · «التطبيق علّق ثانيتين أو أكثر» · «التطبيق علّق»
    static func hangTitle(_ lower: String) -> String {
        if let m = firstMatch(#"between ([0-9]+(?:\.[0-9]+)?) and ([0-9]+(?:\.[0-9]+)?) seconds"#, in: lower), m.count == 2,
           let a = Double(m[0]), let b = Double(m[1]) {
            return "التطبيق علّق \(seconds(a))–\(seconds(b)) \(secondsWord(b))"
        }
        if let m = firstMatch(#"at least ([0-9]+) ?ms"#, in: lower), let ms = Double(m.first ?? "") {
            let s = ms / 1000
            return "التطبيق علّق \(seconds(s)) \(secondsWord(s)) أو أكثر"
        }
        return "التطبيق علّق"
    }

    /// 5.0 → «5» · 2.5 → «2.5»
    static func seconds(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// ٣–١٠ «ثوانٍ»، غيرها «ثانية» (١، ٢، ١١ فأكثر، والكسور)
    static func secondsWord(_ v: Double) -> String {
        (v == v.rounded() && v >= 3 && v <= 10) ? "ثوانٍ" : "ثانية"
    }

    private static let networkMarkers = [
        "urlerror", "nsurlerrordomain", "failed to fetch", "networkerror", "network error", "network connection",
        "timed out", "timeout", "could not connect", "cannot connect", "not connected to the internet",
        "httperror", "http error", "status code", "statuscode", "functionsrelayerror", "fetcherror",
        "postgresterror", "socketexception", "unknownhostexception", "sockettimeoutexception", "connectexception",
        "load failed"
    ]

    static func networkLine(_ lower: String) -> String {
        if lower.contains("timed out") || lower.contains("timeout") { return "السيرفر تأخّر في الرد" }
        if lower.contains("not connected to the internet") || lower.contains("network connection") || lower.contains("unknownhost") {
            return "الجهاز لم يكن متصلاً بالإنترنت أو انقطع الاتصال"
        }
        return "طلب للسيرفر لم يكتمل"
    }

    /// سبب التوقّف بكلام بسيط — nil إن لم يكن توقّفاً
    static func crashReason(head: String, lower: String) -> String? {
        let h = head.lowercased()
        if lower.contains("unexpectedly found nil") { return "قيمة فارغة لم تكن متوقّعة في الكود" }
        if lower.contains("index out of range") { return "طلب عنصر خارج حدود القائمة" }
        if h == "fatal error" { return "خطأ برمجي أوقف التطبيق" }
        if h.hasPrefix("exc_bad_access") || h == "sigsegv" || h == "sigbus" { return "قراءة من ذاكرة غير صالحة" }
        if h == "sigabrt" || h.hasPrefix("exc_crash") { return "أوقف التطبيق نفسه بسبب خطأ داخلي" }
        if h.hasPrefix("exc_breakpoint") || h == "sigtrap" { return "شرط في الكود لم يتحقّق فأوقف التطبيق" }
        if h == "sigkill" { return "النظام أوقف التطبيق" }
        if h.hasSuffix("nsinvalidargumentexception") { return "قيمة غير صالحة مُرّرت للنظام" }
        if h.hasSuffix("nsrangeexception") { return "طلب عنصر خارج حدود القائمة" }
        if h.hasSuffix("nsinternalinconsistencyexception") { return "حالة غير متوقّعة داخل الشاشة" }
        if h.hasSuffix("nullpointerexception") { return "قيمة فارغة لم تكن متوقّعة في الكود" }
        if h.hasSuffix("outofmemoryerror") { return "نفدت الذاكرة" }
        if h.hasSuffix("illegalstateexception") || h.hasSuffix("illegalargumentexception") { return "حالة غير متوقّعة داخل التطبيق" }
        if h.hasPrefix("exc_") || h.hasPrefix("sig") || h.hasSuffix("exception") { return "السبب: \(head)" }
        return nil
    }

    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }
}
