import Foundation

// MARK: - «ذكرى الراحلين» (طلب المالك ٢٠٢٦-١٠-١٩) — تصنيف تاريخ الوفاة وموعد الذكرى بالتقويم الميلادي فقط
//
// نفس المواصفة في الآيفون والأندرويد والموقع (memorial/SPEC.md) — أي تعديل هنا لازم ينعكس هناك:
// • exact     — التاريخ موجود، السنة ≥ 1700، وليس ١ يناير.
//               (حالة معروفة ومقبولة: وفاة حقيقية في ١ يناير تُحسب «السنة فقط» وتظهر في «ناقص تاريخه» ليؤكّدها الإداري)
// • yearOnly  — السنة ≥ 1700 واليوم ١ يناير (أغلب السجلات محفوظة YYYY-01-01 = السنة فقط)
// • hijriLike — السنة < 1700 = سنة هجرية مكتوبة كميلادية («التاريخ مكتوب بالهجري»)
// • missing   — متوفى بلا تاريخ
// الذكرى للـ exact فقط: نفس اليوم والشهر في السنة الميلادية (٢٩ فبراير ← ٢٨ في السنة غير الكبيسة)،
// daysUntil = 0…365، و«الذكرى الـN» = سنة الذكرى − سنة الوفاة.

nonisolated enum DeceasedMemorial {

    enum DateKind: Equatable, Sendable {
        case exact(year: Int, month: Int, day: Int)
        case yearOnly(year: Int)
        case hijriLike(year: Int)
        case missing
    }

    /// أول سنة تُعتبر ميلادية — قبلها السنة هجرية مكتوبة كميلادية
    static let minGregorianYear = 1700
    /// «الذكرى القريبة» في الصفحة
    static let upcomingDays = 30
    /// شارة لوحة الإدارة و«هالأسبوع»
    static let weekDays = 7

    /// التقويم الميلادي دائماً (مهما كان تقويم الجهاز)
    static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    // MARK: التصنيف

    /// death_date كما في القاعدة ("yyyy-MM-dd" وأحياناً بوقت بعده) — سنة وحدها تُعامل ١ يناير
    static func classify(_ deathDate: String?) -> DateKind {
        guard let raw = deathDate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return .missing }
        let parts = raw.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first, let year = Int(first), year > 0 else { return .missing }
        let month = parts.count > 1 ? Int(parts[1]) : 1
        let day = parts.count > 2 ? Int(parts[2]) : 1
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return .missing }
        if year < minGregorianYear { return .hijriLike(year: year) }
        if month == 1 && day == 1 { return .yearOnly(year: year) }
        return .exact(year: year, month: month, day: day)
    }

    // MARK: الذكرى

    struct Anniversary: Equatable, Sendable {
        /// يوم الذكرى القادم (بداية اليوم)
        let date: Date
        /// ٠ = اليوم … ٣٦٥
        let daysUntil: Int
        /// «الذكرى الـN»
        let years: Int
        let month: Int
        let day: Int
    }

    /// الذكرى القادمة (اليوم أو بعده) — للـ exact فقط. وفاة اليوم نفسه (N = 0) أو بتاريخ مستقبلي ما لها ذكرى
    static func anniversary(_ kind: DateKind, today: Date = Date(), calendar cal: Calendar = gregorian) -> Anniversary? {
        guard case let .exact(deathYear, month, day) = kind else { return nil }
        let start = cal.startOfDay(for: today)
        let thisYear = cal.component(.year, from: start)

        func occurrence(_ year: Int) -> (date: Date, day: Int)? {
            // اليوم بحدود الشهر: ٢٩ فبراير ← ٢٨ في السنة غير الكبيسة (وأي يوم أكبر من الشهر ← آخره)
            guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)),
                  let days = cal.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
            let d = min(day, days.upperBound - 1)
            guard let date = cal.date(from: DateComponents(year: year, month: month, day: d)) else { return nil }
            return (cal.startOfDay(for: date), d)
        }

        var year = thisYear
        guard var next = occurrence(year) else { return nil }
        if next.date < start {
            year += 1
            guard let following = occurrence(year) else { return nil }
            next = following
        }
        let years = year - deathYear
        guard years >= 1 else { return nil }
        let daysUntil = cal.dateComponents([.day], from: start, to: next.date).day ?? 0
        return Anniversary(date: next.date, daysUntil: max(0, daysUntil), years: years, month: month, day: next.day)
    }

    // MARK: النصوص (أرقام لاتينية مثل باقي تواريخ التطبيق)

    static let arabicMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
                               "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
    static let englishMonths = ["January", "February", "March", "April", "May", "June",
                                "July", "August", "September", "October", "November", "December"]

    /// «25 أكتوبر»
    static func dayMonth(day: Int, month: Int, arabic: Bool) -> String {
        guard (1...12).contains(month) else { return "\(day)" }
        return "\(day) \((arabic ? arabicMonths : englishMonths)[month - 1])"
    }

    /// «الذكرى الـ12 · 25 أكتوبر»
    static func anniversaryLine(_ a: Anniversary, arabic: Bool) -> String {
        arabic ? "الذكرى الـ\(a.years) · \(dayMonth(day: a.day, month: a.month, arabic: true))"
               : "Anniversary #\(a.years) · \(dayMonth(day: a.day, month: a.month, arabic: false))"
    }

    /// «اليوم» / «بكرة» / «بعد يومين» / «بعد 5 أيام» / «بعد 12 يوماً»
    static func whenLabel(_ daysUntil: Int, arabic: Bool) -> String {
        guard arabic else {
            switch daysUntil {
            case 0: return "Today"
            case 1: return "Tomorrow"
            default: return "In \(daysUntil) days"
            }
        }
        switch daysUntil {
        case 0: return "اليوم"
        case 1: return "بكرة"
        case 2: return "بعد يومين"
        case 3...10: return "بعد \(daysUntil) أيام"
        default: return "بعد \(daysUntil) يوماً"
        }
    }

    /// ملاحظة «ناقص تاريخه»: «السنة فقط: 1995» / «مكتوب بالهجري: 1418» / «بدون تاريخ»
    static func missingNote(_ kind: DateKind, arabic: Bool) -> String {
        switch kind {
        case .yearOnly(let y): return arabic ? "السنة فقط: \(y)" : "Year only: \(y)"
        case .hijriLike(let y): return arabic ? "مكتوب بالهجري: \(y)" : "Written as Hijri: \(y)"
        case .missing: return arabic ? "بدون تاريخ" : "No date"
        case .exact: return ""
        }
    }

    /// ترتيب «ناقص تاريخه»: الهجري أولاً، ثم «السنة فقط» الأحدث أولاً، ثم بدون تاريخ
    static func missingRank(_ kind: DateKind) -> (group: Int, year: Int) {
        switch kind {
        case .hijriLike(let y): return (0, -y)
        case .yearOnly(let y): return (1, -y)
        case .missing: return (2, 0)
        case .exact: return (3, 0)
        }
    }

    // MARK: بداية عجلة «تكميل التاريخ»

    /// السنة فقط ← ١ يناير منها؛ الهجري ← أول السنة الهجرية بالميلادي (أم القرى)؛ بدون ← اليوم
    static func pickerStart(_ kind: DateKind, today: Date = Date(), calendar cal: Calendar = gregorian) -> Date {
        let date: Date?
        switch kind {
        case .exact(let y, let m, let d): date = cal.date(from: DateComponents(year: y, month: m, day: d))
        case .yearOnly(let y): date = cal.date(from: DateComponents(year: y, month: 1, day: 1))
        case .hijriLike(let y):
            var hijri = Calendar(identifier: .islamicUmmAlQura)
            hijri.timeZone = cal.timeZone
            date = hijri.date(from: DateComponents(year: y, month: 1, day: 1))
        case .missing: date = nil
        }
        guard let date, date <= today else { return today }
        return date
    }
}
