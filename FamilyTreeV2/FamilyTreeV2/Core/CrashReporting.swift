import Foundation
import Sentry

/// بلاغات الأعطال (Sentry) — تبدأ أول ما يفتح التطبيق (`FamilyTreeV2App.init`).
///
/// - المفتاح: إعداد البناء `SENTRY_DSN` ← مفتاح Info.plist بنفس الاسم. فارغ = مطفأ (لا شيء يُرسَل).
///   المفتاح ليس سرّاً: يسمح بإرسال البلاغات فقط، لا بقراءتها (مثل مفتاح Supabase العلني).
/// - الخصوصية (نفس مبدأ `AppDiagnostics`: نص السجلات لا يخرج من الجهاز): لا أرقام ولا أسماء ولا بريد،
///   لا صور شاشة ولا شجرة الواجهة، ولا نص الاستعلام في روابط الطلبات (قد يحمل رقم هاتف)،
///   وأي رقم طويل (هاتف) في نص العطل يُستبدل بـ«<رقم>» (نفس الأندرويد والموقع).
/// - التجربة (نسخة التطوير فقط): شغّل التطبيق بالوسيط `-SentryTestEvent` (أو ابنه بـ`SENTRY_SELFTEST`)
///   فيصل حدث تجريبي واحد.
nonisolated enum CrashReporting {
    private static let infoKey = "SENTRY_DSN"

    static func start() {
        guard let dsn = dsnFromBundle() else { return }

        let info = Bundle.main.infoDictionary ?? [:]
        let bundleId = Bundle.main.bundleIdentifier ?? "Hasan.FamilyTreeV2"
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "\(bundleId)@\(version)+\(build)"
            options.dist = build
            // مشروع Sentry واحد للمنصات الثلاث — العلامة تفرّقها (ios · android · web)
            options.initialScope = { scope in
                scope.setTag(value: "ios", key: "app")
                return scope
            }
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            // الخصوصية
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            // فشل طلبات الشبكة لا يُرسَل كبلاغ (رابطه قد يحمل بيانات)، والأعطال تُرسَل كما هي
            options.enableCaptureFailedRequests = false
            options.beforeBreadcrumb = { crumb in
                scrubQuery(in: crumb)
                if let message = crumb.message { crumb.message = maskNumbers(message) }
                return crumb
            }
            options.beforeSend = { event in
                event.exceptions?.forEach { exception in
                    if let value = exception.value { exception.value = maskNumbers(value) }
                }
                if let message = event.message {
                    event.message = SentryMessage(formatted: maskNumbers(message.formatted))
                }
                return event
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SentryTestEvent") || testBuild {
            SentrySDK.capture(message: "FamilyTreeV2 iOS — test event")
        }
        #endif
    }

    /// نسخة تجربة: البناء بـ `'OTHER_SWIFT_FLAGS=$(inherited) -DSENTRY_SELFTEST'` يرسل الحدث التجريبي
    /// بلا وسيط تشغيل (لمن يفتح التطبيق من أداة لا تمرّر الوسطاء).
    #if SENTRY_SELFTEST
    private static let testBuild = true
    #else
    private static let testBuild = false
    #endif

    private static func dsnFromBundle() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // «$(SENTRY_DSN)» حرفياً = إعداد البناء غير معرَّف
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// يحذف نص الاستعلام (`?…`) والجزء بعد `#` من روابط فتات الشبكة
    private static func scrubQuery(in crumb: Breadcrumb) {
        guard let data = crumb.data else { return }
        // nil = حذف المفتاح
        if data["http.query"] != nil { crumb.setData(value: nil, key: "http.query") }
        if data["http.fragment"] != nil { crumb.setData(value: nil, key: "http.fragment") }
        if let url = data["url"] as? String, let cut = url.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            crumb.setData(value: String(url[..<cut]), key: "url")
        }
    }

    /// سبعة أرقام فأكثر متتالية (مع + أو مسافات أو شرطات بينها) = رقم هاتف محتمل
    private static let longNumber = try? NSRegularExpression(pattern: #"\+?\d[\d\s-]{5,}\d"#)

    private static func maskNumbers(_ text: String) -> String {
        guard let longNumber else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return longNumber.stringByReplacingMatches(in: text, range: range, withTemplate: "<رقم>")
    }
}
