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
        return iso8601.date(from: string) ?? displayFormatter.date(from: string)
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

    /// الآن كـ ISO8601
    static var now: String {
        iso8601.string(from: Date())
    }

    /// الآن كـ "yyyy-MM-dd"
    static var today: String {
        format(Date())
    }
}
