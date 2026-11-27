import Foundation

/// أدوات تواريخ الرئيسية — تحليل ISO، النص النسبي، وحدود «آخر N يوم»
enum HomeDates {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func parse(_ iso: String?) -> Date? {
        guard let s = iso, !s.isEmpty else { return nil }
        return DateParsing.iso(s)
    }

    static func relativeString(_ date: Date) -> String {
        relative.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func isWithinLastDays(_ date: Date, days: Int) -> Bool {
        guard let limit = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return false }
        return date >= limit
    }
}
