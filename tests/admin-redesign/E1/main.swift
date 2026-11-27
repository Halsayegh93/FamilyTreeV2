// فحص «الأخطاء» بالعربي (Views/Features/Admin/AdminErrorTitles.swift، الوحدة E1) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/e1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminErrorTitles.swift tests/admin-redesign/E1/main.swift \
//     && /private/tmp/claude-501/e1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias A = AdminErrorArabic

// ١) التعليق
let hang = A.describe("App Hang Fully Blocked: App hanging between 6.0 and 7.0 seconds.", platform: "ios")
check(hang.kind, .hang, "hang kind")
check(hang.title, "التطبيق علّق 6–7 ثوانٍ", "hang title X–Y")
check(hang.line, "الشاشة توقفت عن الاستجابة", "hang line")
check(hang.showsOriginal, true, "hang keeps original underneath")
check(A.describe("App Hang Non Fully Blocked: App hanging between 2 and 3 seconds.").title, "التطبيق علّق 2–3 ثوانٍ", "non fully blocked")
check(A.describe("App Hang Fully Blocked: App hanging between 4.5 and 5.0 seconds.").title, "التطبيق علّق 4.5–5 ثوانٍ", "fraction kept")
check(A.describe("App Hang Fully Blocked: App hanging between 10 and 12 seconds.").title, "التطبيق علّق 10–12 ثانية", "11+ uses ثانية")
check(A.describe("App Hanging: App hanging for at least 2000 ms.").title, "التطبيق علّق 2 ثانية أو أكثر", "at least ms")
check(A.describe("App Hang Fully Blocked").title, "التطبيق علّق", "hang without numbers")
check(A.describe("ApplicationNotResponding: ANR for at least 5000 ms.", platform: "android").kind, .hang, "android ANR")

// ٢) النظام أغلق التطبيق
let wd = A.describe("WatchdogTermination: The OS watchdog terminated your app, possibly because it overused RAM.", platform: "ios")
check(wd.kind, .killed, "watchdog kind")
check(wd.title, "النظام أغلق التطبيق", "watchdog title")
check(wd.line, "غالباً استهلاك ذاكرة كبير، أو أُعيد تثبيت النسخة نفسها أثناء عملها", "watchdog line")

// ٣) التوقّف المفاجئ
check(A.describe("EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x0000000000000010").title, "توقّف التطبيق فجأة", "bad access title")
check(A.describe("EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x10").line, "قراءة من ذاكرة غير صالحة", "bad access line")
check(A.describe("SIGABRT").kind, .crash, "SIGABRT bare")
check(A.describe("SIGABRT: Abort trap").line, "أوقف التطبيق نفسه بسبب خطأ داخلي", "SIGABRT line")
check(A.describe("Fatal error: Unexpectedly found nil while unwrapping an Optional value").line,
      "قيمة فارغة لم تكن متوقّعة في الكود", "fatal nil")
check(A.describe("Fatal error: Index out of range").line, "طلب عنصر خارج حدود القائمة", "fatal index")
check(A.describe("Fatal error: something else").line, "خطأ برمجي أوقف التطبيق", "fatal generic")
check(A.describe("NSInvalidArgumentException: -[__NSCFNumber length]: unrecognized selector").kind, .crash, "NSInvalidArgument kind")
check(A.describe("NSInvalidArgumentException: -[__NSCFNumber length]: unrecognized selector").line,
      "قيمة غير صالحة مُرّرت للنظام", "NSInvalidArgument line")
check(A.describe("EXC_BREAKPOINT: Swift runtime failure").line, "شرط في الكود لم يتحقّق فأوقف التطبيق", "breakpoint line")
check(A.describe("java.lang.NullPointerException: Attempt to invoke virtual method", platform: "android").line,
      "قيمة فارغة لم تكن متوقّعة في الكود", "android NPE")
check(A.describe("NSGenericException: whatever").line, "السبب: NSGenericException", "unknown exception → reason")

// ٤) الاتصال
check(A.describe("URLError: The request timed out.").kind, .network, "URLError kind")
check(A.describe("URLError: The request timed out.").title, "خطأ اتصال بالسيرفر", "network title")
check(A.describe("URLError: The request timed out.").line, "السيرفر تأخّر في الرد", "timeout line")
check(A.describe("NSURLErrorDomain: The Internet connection appears to be offline (not connected to the internet)").line,
      "الجهاز لم يكن متصلاً بالإنترنت أو انقطع الاتصال", "offline line")
check(A.describe("FunctionsError: httpError(code: 500)").kind, .network, "functions http")
check(A.describe("TypeError: Failed to fetch", platform: "web").kind, .network, "web fetch = network, not web")
check(A.describe("Error: HTTP 502 Bad Gateway", platform: "web").kind, .network, "web HTTP = network")

// ٥) الموقع
let web = A.describe("Error: Minified React error #418", platform: "web")
check(web.kind, .web, "web Error:")
check(web.title, "خطأ في الموقع", "web title")
check(A.describe("TypeError: Cannot read properties of undefined (reading 'id')", platform: "web").kind, .web, "web TypeError")

// ٦) غير مصنّف
let other = A.describe("Something odd happened", platform: "ios")
check(other.kind, .unknown, "unknown kind")
check(other.title, "Something odd happened", "unknown keeps title")
check(other.line, "خطأ غير مصنّف", "unknown line")
check(other.showsOriginal, false, "unknown doesn't repeat original")
check(A.describe("   ").title, "—", "empty title")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
