import Foundation

// MARK: - «انتظر N ثانية» عند حجب طلب رمز الدخول (٢٠٢٦-١٠-٢٠)
//
// الانتظار بين رمزين صار يضبطه المالك (٦٠–٦٠٠ ث، `app_settings.sms_wait_seconds`). الحجب يصل خطأ Auth (٤٢٩ عادةً)
// بنص فيه الثواني — من دالتنا: «Please wait 120 seconds before requesting another code»، ومن Supabase نفسه:
// «For security purposes, you can only request this after 42 seconds.». يُقرأ النص بغض النظر عن الحالة، قبل فرع
// «429 / rate / too many» العام؛ بلا رقم ← الرسالة العامة كما كانت. الدقائق تُقرَّب للأعلى (٦١ ث ← دقيقتين).
// مستقل عن واجهة التطبيق (`arabic:` بدل `L10n`) حتى يُفحص بسكربت سويفت وحده.

enum OTPWaitText {
    private static let pattern = try? NSRegularExpression(pattern: #"(?:wait|after)\s+(\d+)\s+seconds?"#,
                                                          options: [.caseInsensitive])

    /// الثواني المذكورة في نص الخطأ — nil إن لم يُذكر رقم (أو صفر)
    static func seconds(in text: String) -> Int? {
        guard let pattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let digits = Range(match.range(at: 1), in: text),
              let n = Int(text[digits]), n > 0 else { return nil }
        return min(n, 86_400)
    }

    /// «انتظر 50 ثانية» · «انتظر دقيقة» · «انتظر دقيقتين» · «انتظر 3 دقائق» (أقل من ٦٠ بالثواني، وإلا دقائق مقرّبة للأعلى)
    static func waitPhrase(seconds n: Int, arabic: Bool) -> String {
        if n < 60 {
            return arabic ? "انتظر " + secondsArabic(n) : "Wait " + (n == 1 ? "1 second" : "\(n) seconds")
        }
        let m = (n + 59) / 60
        return arabic ? "انتظر " + minutesArabic(m) : "Wait " + (m == 1 ? "1 minute" : "\(m) minutes")
    }

    /// الرسالة الكاملة لشاشة طلب الرمز
    static func message(seconds n: Int, arabic: Bool) -> String {
        waitPhrase(seconds: n, arabic: arabic) + (arabic ? " قبل طلب رمز جديد." : " before requesting a new code.")
    }

    /// من نص الخطأ مباشرة — nil = لا رقم (تبقى الرسالة العامة)
    static func message(from text: String, arabic: Bool) -> String? {
        seconds(in: text).map { message(seconds: $0, arabic: arabic) }
    }

    /// مدة بلا تقريب للعرض («دقيقة»، «دقيقتين»، «5 دقائق»، «90 ثانية») — للحدود في صفحة الرسائل
    static func exactDuration(seconds n: Int, arabic: Bool) -> String {
        if n >= 60, n % 60 == 0 {
            let m = n / 60
            return arabic ? minutesArabic(m) : (m == 1 ? "a minute" : "\(m) minutes")
        }
        return arabic ? secondsArabic(n) : (n == 1 ? "1 second" : "\(n) seconds")
    }

    /// العدد والمعدود: ١ ثانية واحدة · ٢ ثانيتين · ٣–١٠ ثوانٍ · ١١+ ثانية
    static func secondsArabic(_ n: Int) -> String {
        switch n {
        case 1: return "ثانية واحدة"
        case 2: return "ثانيتين"
        case 3...10: return "\(n) ثوانٍ"
        default: return "\(n) ثانية"
        }
    }

    /// ١ دقيقة · ٢ دقيقتين · ٣–١٠ دقائق · ١١+ دقيقة
    static func minutesArabic(_ m: Int) -> String {
        switch m {
        case 1: return "دقيقة"
        case 2: return "دقيقتين"
        case 3...10: return "\(m) دقائق"
        default: return "\(m) دقيقة"
        }
    }
}
