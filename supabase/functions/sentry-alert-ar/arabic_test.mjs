// فحص تنبيه الأخطاء بالعربي (arabic.ts) بلا Deno ولا شبكة — نفس حالات الآيفون (tests/admin-redesign/E1/main.swift)
// + قراءة أشكال Sentry الثلاثة + الإيميل.
// التشغيل (Node 22.6+؛ ٢٤ بلا علم): node supabase/functions/sentry-alert-ar/arabic_test.mjs
import {
  describeError as D, releaseAr, parseSentryPayload, buildAlertEmail, kuwaitTime, timesAr, devicesAr, issueLink, tagsOf,
} from "./arabic.ts";

let pass = 0, fail = 0;
const eq = (got, want, label) => {
  if (JSON.stringify(got) === JSON.stringify(want)) { pass++; console.log("✓", label); }
  else { fail++; console.log("✗", label, "\n   got ", got, "\n   want", want); }
};

// ١) التعليق
const hang = D("App Hang Fully Blocked: App hanging between 6.0 and 7.0 seconds.", "ios");
eq(hang.kind, "hang", "hang kind");
eq(hang.title, "التطبيق علّق 6–7 ثوانٍ", "hang title X–Y");
eq(hang.line, "الشاشة توقفت عن الاستجابة", "hang line");
eq(hang.showsOriginal, true, "hang keeps original");
eq(D("App Hang Non Fully Blocked: App hanging between 2 and 3 seconds.").title, "التطبيق علّق 2–3 ثوانٍ", "non fully blocked");
eq(D("App Hang Fully Blocked: App hanging between 4.5 and 5.0 seconds.").title, "التطبيق علّق 4.5–5 ثوانٍ", "fraction kept");
eq(D("App Hang Fully Blocked: App hanging between 10 and 12 seconds.").title, "التطبيق علّق 10–12 ثانية", "11+ ثانية");
eq(D("App Hanging: App hanging for at least 2000 ms.").title, "التطبيق علّق 2 ثانية أو أكثر", "at least ms");
eq(D("App Hang Fully Blocked").title, "التطبيق علّق", "hang without numbers");
eq(D("ApplicationNotResponding: ANR for at least 5000 ms.", "android").kind, "hang", "android ANR");
// ٢) النظام أغلق التطبيق
const wd = D("WatchdogTermination: The OS watchdog terminated your app, possibly because it overused RAM.", "ios");
eq([wd.kind, wd.title], ["killed", "النظام أغلق التطبيق"], "watchdog");
eq(wd.line, "غالباً استهلاك ذاكرة كبير، أو أُعيد تثبيت النسخة نفسها أثناء عملها", "watchdog line");
// ٣) التوقّف
eq(D("EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x10").title, "توقّف التطبيق فجأة", "bad access title");
eq(D("EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x10").line, "قراءة من ذاكرة غير صالحة", "bad access line");
eq(D("SIGABRT").kind, "crash", "SIGABRT bare");
eq(D("SIGABRT: Abort trap").line, "أوقف التطبيق نفسه بسبب خطأ داخلي", "SIGABRT line");
eq(D("Fatal error: Unexpectedly found nil while unwrapping an Optional value").line, "قيمة فارغة لم تكن متوقّعة في الكود", "fatal nil");
eq(D("Fatal error: Index out of range").line, "طلب عنصر خارج حدود القائمة", "fatal index");
eq(D("Fatal error: something else").line, "خطأ برمجي أوقف التطبيق", "fatal generic");
eq(D("NSInvalidArgumentException: -[__NSCFNumber length]: unrecognized selector").line, "قيمة غير صالحة مُرّرت للنظام", "NSInvalidArgument");
eq(D("EXC_BREAKPOINT: Swift runtime failure").line, "شرط في الكود لم يتحقّق فأوقف التطبيق", "breakpoint");
eq(D("java.lang.NullPointerException: Attempt to invoke virtual method", "android").line, "قيمة فارغة لم تكن متوقّعة في الكود", "android NPE");
eq(D("NSGenericException: whatever").line, "السبب: NSGenericException", "unknown exception → reason");
// ٤) الاتصال
eq(D("URLError: The request timed out.").kind, "network", "URLError kind");
eq(D("URLError: The request timed out.").line, "السيرفر تأخّر في الرد", "timeout line");
eq(D("NSURLErrorDomain: The Internet connection appears to be offline (not connected to the internet)").line,
   "الجهاز لم يكن متصلاً بالإنترنت أو انقطع الاتصال", "offline line");
eq(D("FunctionsError: httpError(code: 500)").kind, "network", "functions http");
eq(D("TypeError: Failed to fetch", "web").kind, "network", "web fetch = network");
eq(D("Error: HTTP 502 Bad Gateway", "web").kind, "network", "web HTTP = network");
// ٥) الموقع
eq([D("Error: Minified React error #418", "web").kind, D("Error: Minified React error #418", "web").title], ["web", "خطأ في الموقع"], "web Error:");
eq(D("TypeError: Cannot read properties of undefined (reading 'id')", "web").kind, "web", "web TypeError");
// ٦) غير مصنّف
const other = D("Something odd happened", "ios");
eq([other.kind, other.title, other.line, other.showsOriginal], ["unknown", "Something odd happened", "خطأ غير مصنّف", false], "unknown");
eq(D("   ").title, "—", "empty title");

// الوقت والأعداد
eq(kuwaitTime("2026-11-27T09:05:00Z"), "27/11/2026 · 12:05 م", "Kuwait noon");
eq(kuwaitTime("2026-11-27T22:30:00Z"), "28/11/2026 · 1:30 ص", "Kuwait next day");
eq(kuwaitTime("bad"), null, "bad date");
eq([timesAr(1), timesAr(2), timesAr(5), timesAr(11)], ["مرة واحدة", "مرتين", "5 مرات", "11 مرة"], "times");
eq([devicesAr(1), devicesAr(2), devicesAr(3), devicesAr(40)], ["جهاز واحد", "جهازين", "3 أجهزة", "40 جهازاً"], "devices");
eq(tagsOf([["app", "ios"], { key: "release", value: "1.2 (300)" }]), { app: "ios", release: "1.2 (300)" }, "tags both shapes");

// ١) WebHooks القديم
const legacy = parseSentryPayload({
  id: "6012345678", project: "familytree", project_slug: "familytree", level: "fatal", culprit: "TreeView.body",
  message: "EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x10",
  url: "https://almohaliapp.sentry.io/issues/6012345678/?referrer=webhooks_plugin",
  event: { title: "EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x10", platform: "cocoa", release: "Hasan.FamilyTreeV2@2.4 (312)",
           environment: "production", timestamp: 1795770300, tags: [["app", "ios"], ["level", "fatal"]] },
});
eq([legacy.source, legacy.issueId, legacy.app, legacy.isSample], ["legacy", "6012345678", "ios", false], "legacy parsed");
eq(issueLink(legacy, "almohaliapp"), "https://almohaliapp.sentry.io/issues/6012345678/?referrer=arabic_alert", "legacy link");

// ٢) قاعدة تنبيه بإجراء webhook
const alert = parseSentryPayload({
  action: "triggered", installation: { uuid: "x" },
  data: { triggered_rule: "خطأ جديد", event: {
    issue_id: "6012345679", title: "App Hang Fully Blocked: App hanging between 6.0 and 7.0 seconds.",
    web_url: "https://almohaliapp.sentry.io/issues/6012345679/events/abc/", platform: "cocoa",
    release: "2.4 (312)", datetime: "2026-11-27T09:05:00Z", tags: [["app", "ios"]] } },
});
eq([alert.source, alert.issueId, alert.eventTime, alert.isSample], ["event_alert", "6012345679", "2026-11-27T09:05:00Z", false], "event_alert parsed");

// ٣) حدث issue
const iss = parseSentryPayload({ action: "created", data: { issue: {
  id: "6012345680", title: "TypeError: Failed to fetch", platform: "javascript", count: "4", userCount: 2,
  firstSeen: "2026-11-26T18:00:00Z", lastSeen: "2026-11-27T09:00:00Z", permalink: "https://almohaliapp.sentry.io/issues/6012345680/" } } });
eq([iss.source, iss.count, iss.userCount], ["issue", 4, 2], "issue parsed");

eq([releaseAr("Hasan.FamilyTreeV2@2.4+312"), releaseAr("Hasan.FamilyTreeV2@2.4 (312)"), releaseAr("2.4")], ["2.4 (312)", "2.4 (312)", "2.4"], "release");
// تجريبي / ليس خطأ
eq(parseSentryPayload({ id: "1", message: "This is an example Python exception", event: { tags: [["sample_event", "yes"]] } }).isSample, true, "sample flagged");
eq(parseSentryPayload({ message: "x", url: "https://almohaliapp.sentry.io/" }).isSample, true, "no issue id → sample");
eq(parseSentryPayload({ action: "critical", data: { metric_alert: {} } }), null, "metric alert ignored");
eq(parseSentryPayload("nope"), null, "garbage ignored");
eq(issueLink({ url: "https://evil.example/issues/1/", issueId: "1" }, "almohaliapp"), "https://almohaliapp.sentry.io/issues/1/?referrer=arabic_alert", "foreign url rejected");

// الإيميل
const full = { ...legacy, count: 12, userCount: 3, firstSeen: "2026-11-25T17:40:00Z", lastSeen: "2026-11-27T09:05:00Z" };
const mail = buildAlertEmail(full, "almohaliapp");
eq(mail.subject, "خطأ في تطبيق آيفون: توقّف التطبيق فجأة", "subject");
eq(mail.push, { title: "خطأ في آيفون: توقّف التطبيق فجأة", body: "قراءة من ذاكرة غير صالحة · 12 مرة" }, "push text");
eq(mail.text.includes("تكرّر: 12 مرة") && mail.text.includes("الأجهزة المتأثرة: 3 أجهزة") && mail.text.includes("أول ظهور: 25/11/2026 · 8:40 م"), true, "text rows");
eq(mail.html.includes('dir="rtl"') && mail.html.includes("افتح الخطأ") && mail.html.includes("EXC_BAD_ACCESS"), true, "html");
eq(buildAlertEmail({ ...iss }, "almohaliapp").subject, "خطأ في الموقع: خطأ اتصال بالسيرفر", "web subject");
eq(buildAlertEmail({ ...iss, count: 1 }, "almohaliapp").subject, "خطأ جديد في الموقع: خطأ اتصال بالسيرفر", "new subject");
eq(buildAlertEmail({ ...legacy, title: "<script>x</script>" }, "almohaliapp").html.includes("<script>"), false, "html escaped");

if (process.argv.includes("--print")) { console.log("\n" + mail.subject + "\n\n" + mail.text); }
console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
