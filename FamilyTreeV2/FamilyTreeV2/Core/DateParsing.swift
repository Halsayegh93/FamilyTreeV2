import Foundation

/// محلّلات ومنسّقات التواريخ المشتركة — تُنشأ مرة واحدة وتُستعمل من أي مكان.
///
/// لماذا (Sentry FAMILYTREE-A/-7/-9، ٢٠٢٦-١١-٢٧): الخيط الرئيسي علّق ٥–٧ ثوانٍ داخل
/// `-[NSISO8601DateFormatter updateFormatter]` ← إنشاء منطقة زمنية ICU، عند فك ~٢٬٩٠٠ صفّ (`app_usage_stats` في تبويب
/// الإدارة) وترتيب الطلبات والإشعارات. سببان: (١) `ISO8601DateFormatter()`/`DateFormatter()` يُنشأ لكل استدعاء، و(٢) حتى
/// المحلّل الثابت يمرّ بـ`updateFormatter` في كل `date(from:)` (~٩٠ ميكروثانية للنص). لذا `iso(_:)` يحلّل بـ
/// `Date.ISO8601FormatStyle` (قيمة Sendable، بلا ICU، أسرع ~١٠٠ مرة) ويرجع للمحلّلين القديمين فقط إن رفض النص —
/// والنتيجة مقصوصة لأجزاء الألف من الثانية كما كان `ISO8601DateFormatter` يرجعها (نفس القيمة حرفياً؛ يفحصها D1).
///
/// القاعدة: لا تغيّر خصائص هذه الكائنات بعد إنشائها (`formatOptions`، `dateFormat`، `timeZone`…) — القراءة
/// والتنسيق منها آمنان من عدة خيوط ما دامت ثابتة، والتعديل يكسر ذلك. صيغة جديدة = كائن ثابت جديد هنا.
nonisolated enum DateParsing {

    // MARK: ISO8601 (طوابع السيرفر timestamptz)

    /// «2026-11-27T10:00:00.123456+00:00» — بكسور الثواني
    nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// «2026-11-27T10:00:00Z» — بلا كسور (= إعداد `ISO8601DateFormatter()` الافتراضي، بتوقيت GMT)
    nonisolated(unsafe) static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// «2026-11-27» — `.withFullDate` بتوقيت GMT (سجلّ تعديل الإدارة)
    nonisolated(unsafe) static let isoFullDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// نص ISO من السيرفر ← Date: بكسور الثواني أولاً ثم بدونها. فارغ أو غير مفهوم ← nil.
    /// «Z» و«+00:00» كلاهما مقبول؛ اليوم وحده («2026-11-27») ليس ISO بوقت ← nil (استعمل `day`).
    static func iso(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = try? fastStyle.parse(raw) { return millis(d) }
        return isoFractional.date(from: raw) ?? isoPlain.date(from: raw)
    }

    /// مثل محلّل «بكسور الثواني» وحده: النص بلا كسور ← nil (لمن كان يستعمل `isoFractional` بلا بديل)
    static func isoRequiringFraction(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let t = raw.firstIndex(of: "T"), raw[t...].contains(".") else { return nil }
        if let d = try? fastStyle.parse(raw) { return millis(d) }
        return isoFractional.date(from: raw)
    }

    /// يقبل النص بكسور الثواني أو بدونها، و«Z» أو «±hh:mm»
    private static let fastStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// `ISO8601DateFormatter` يحفظ أجزاء الألف فقط (يقصّ الباقي) — نفس القيمة كي لا يتغيّر ترتيب ولا مقارنة
    private static func millis(_ d: Date) -> Date {
        let t = d.timeIntervalSince1970
        let whole = t.rounded(.down)
        // الكسر وحده (طرح دقيق) ثم القصّ — هامش نصف ميكروثانية لخطأ التمثيل في الاتجاهين
        let ms = ((t - whole) * 1000 + 0.0005).rounded(.down)
        return Date(timeIntervalSince1970: (whole * 1000 + ms) / 1000)
    }

    /// Date ← «2026-11-27T10:00:00Z» (بلا كسور — ما كان يكتبه `ISO8601DateFormatter().string(from:)`)
    static func isoString(_ date: Date = Date()) -> String {
        isoPlain.string(from: date)
    }

    /// Date ← «2026-11-27T10:00:00.123Z» (بكسور الثواني)
    static func isoFractionalString(_ date: Date = Date()) -> String {
        isoFractional.string(from: date)
    }

    // MARK: أيام «yyyy-MM-dd» (ميلاد، وفاة…)

    /// «yyyy-MM-dd» ميلادي بأرقام لاتينية، بتوقيت الجهاز
    static let dayLocal: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// «yyyy-MM-dd» بتوقيت UTC
    static let dayUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// «yyyy» بتوقيت UTC (السنة وحدها ← ١ يناير)
    static let yearUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy"
        return f
    }()

    /// «yyyy-MM-dd HH:mm:ss» بتوقيت UTC — صيغة SQL بلا «T»
    static let sqlDateTimeUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// أول عشر خانات «yyyy-MM-dd» ← Date بتوقيت الجهاز (منتصف الليل). أقصر أو غير مفهوم ← nil
    static func day(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        return dayLocal.date(from: String(raw.prefix(10)))
    }
}
