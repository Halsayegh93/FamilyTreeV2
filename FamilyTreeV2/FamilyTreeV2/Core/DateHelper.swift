import Foundation

/// أدوات التاريخ الموحدة — بدل إنشاء formatter كل مرة
enum DateHelper {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // ميلادي دائماً — لا يتأثر بتقويم الجهاز (هجري/بوذي)، واليوم بتوقيت الجهاز
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// ISO8601 → Date
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return DateParsing.isoRequiringFraction(string) ?? displayFormatter.date(from: string)
    }

    /// Date → "yyyy-MM-dd"
    static func format(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    /// Date → "منذ 5 دقائق"
    static func relativeTime(from date: Date) -> String {
        relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// ISO8601 string → "منذ 5 دقائق"
    static func relativeTime(from string: String?) -> String {
        guard let date = parse(string) else { return "" }
        return relativeTime(from: date)
    }

    // MARK: - العرض الموحّد (قرار المالك ٢٠٢٦-١١-١٠)
    // كل تاريخ معروض بصيغة واحدة: يوم/شهر/سنة بخانتين — «25/03/1993» — ميلادي وبأرقام لاتينية
    // كأرقام الهواتف والعدّادات في التطبيق. للعرض فقط: صيغ السيرفر والإدخال كما هي.
    // يُحاط بعزل LTR (U+2066…U+2069) فلا ينقلب الترتيب داخل نص عربي.

    private static let displayDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    private static func clockFormatter(_ locale: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: locale)
        f.dateFormat = "h:mm a"
        return f
    }
    private static let clockAr = clockFormatter("ar@numbers=latn")
    private static let clockEn = clockFormatter("en_US")

    /// أيام السيرفر بلا وقت: «yyyy-MM-dd» أو «yyyy/MM/dd» (وخانة واحدة مقبولة)
    private static let dayParsers: [DateFormatter] = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-M-d", "yyyy/M/d"].map {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    private static func isolatedLTR(_ s: String) -> String { "\u{2066}\(s)\u{2069}" }

    /// Date → «25/03/1993»
    static func displayDate(_ date: Date) -> String {
        isolatedLTR(displayDayFormatter.string(from: date))
    }

    /// نص السيرفر (يوم «yyyy-MM-dd» أو ISO8601 بوقت) → «25/03/1993».
    /// فارغ → nil · غير مفهوم → النص كما هو (لا يضيع شيء من العرض).
    static func displayDate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.count > 10, let d = DateParsing.iso(raw) {
            return displayDate(d)
        }
        let day = String(raw.prefix(10))
        for f in dayParsers { if let d = f.date(from: day) { return displayDate(d) } }
        return raw
    }

    /// Date → «25/03/1993 · 9:10 م» — للطوابع التي تحتاج الوقت مع التاريخ
    static func displayDateTime(_ date: Date) -> String {
        let clock = (L10n.isArabic ? clockAr : clockEn).string(from: date)
        return isolatedLTR(displayDayFormatter.string(from: date)) + " · " + clock
    }

    /// نص ISO8601 → «25/03/1993 · 9:10 م» · غير مفهوم → النص كما هو
    static func displayDateTime(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let d = DateParsing.iso(raw) else { return displayDate(raw) }
        return displayDateTime(d)
    }

    /// الآن كـ ISO8601
    static var now: String {
        iso8601.string(from: Date())
    }

    /// الآن كـ "yyyy-MM-dd"
    static var today: String {
        format(Date())
    }
}
