// فحص منطق «الفريق والأمان» (Views/Features/Admin/AdminTeamArea.swift، الوحدة U16) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u16-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTeamArea.swift tests/admin-redesign/U16/main.swift && /tmp/u16-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminTeamLogic
let at = Date(timeIntervalSince1970: 1_800_000_000)

/// كل شيء وصل وسليم
func healthy() -> L.Facts {
    var f = L.Facts()
    f.sms = .loaded(at: at); f.smsLevel = .good; f.balance = 1240; f.daysLeft = 18
    f.settings = .loaded(at: at); f.registrationOpen = true
    f.bans = .loaded(at: at); f.bannedCount = 12
    f.devices = .loaded(at: at); f.devicesTotal = 443; f.devicesReach = 443; f.devicesFailed = 0
    return f
}

// MARK: رأس بطاقة الحالة — T1: لا «سليم» قبل البيانات، والفشل «تعذّر التحميل»
var f = healthy()
check(L.issueCount(f), 0, "all loaded and fine → 0 issues")
check(L.headWord(issues: 0).text, "سليم", "0 issues → «سليم»")
check(L.headWord(issues: 0).tone, .ok, "«سليم» is ok tone")
check(L.headHealth(f).look, .word, "all loaded → the word shows")

var loading = L.Facts()
check(L.headHealth(loading).look, .skeleton, "nothing loaded → skeleton (never «سليم»)")
check(L.issueCount(loading), 0, "nothing loaded counts nothing")

var smsFailed = healthy()
smsFailed.sms = .failed(lastGood: nil); smsFailed.balance = nil
check(L.headHealth(smsFailed).look, .unknown, "SMS failed with no data → head pill «تعذّر التحميل»")
check(L.smsLine(smsFailed), "تعذّر جلب الرصيد", "SMS failed → row line «تعذّر جلب الرصيد»")
check(L.devicesLine(smsFailed), "تصل 443 جهازاً من 443", "the other rows stay")

var smsStale = healthy()
smsStale.sms = .failed(lastGood: at); smsStale.smsLevel = .low
check(L.headHealth(smsStale).look, .staleWord(since: at), "SMS failed after a good load → word + «آخر تحديث»")
check(L.issueCount(smsStale), 1, "stale low balance still counts")

var denied = healthy()
denied.sms = .denied
check(L.headHealth(denied).look, .word, "a denied store does not turn the head Unknown")

var hidden = healthy()
hidden.seesSms = false; hidden.sms = .failed(lastGood: nil)
check(L.headHealth(hidden).look, .word, "a row the role can't see never fails the head")

// Autoplan note 4: الرصيد منخفض/عاجل · مريبة لم تُقرأ · التسجيل متوقف · أجهزة فاشلة
var two = healthy()
two.smsLevel = .low; two.suspicious = 3
check(L.issueCount(two), 2, "low balance + 3 suspicious = 2 rows need you")
check(L.headWord(issues: 2).text, "شيئان يحتاجانك", "2 → «شيئان يحتاجانك»")
check(L.headWord(issues: 2).tone, .warn, "needs-you is warn")
check(L.headWord(issues: 1).text, "شيء يحتاجك", "1 → «شيء يحتاجك»")
check(L.headWord(issues: 4).text, "4 أشياء تحتاجك", "4 → «4 أشياء تحتاجك»")
var four = healthy()
four.smsLevel = .urgent; four.suspicious = 1; four.registrationOpen = false; four.devicesFailed = 31; four.devicesReach = 412
check(L.issueCount(four), 4, "all four facts count once each")
var suspiciousHidden = two
suspiciousHidden.seesSms = false
check(L.issueCount(suspiciousHidden), 0, "SMS rows hidden for the role → not counted")
var closedNotLoaded = healthy()
closedNotLoaded.settings = .loading; closedNotLoaded.registrationOpen = false
check(L.issueCount(closedNotLoaded), 0, "registration «stopped» before settings load is not counted (default value)")

// بيانات في الذاكرة من صفحة أخرى: كلمة فوراً، لا هيكل
check(L.seeded(.idle, hasData: true, now: at), .loaded(at: at), "idle + data in memory → word")
check(L.seeded(.idle, hasData: false, now: at), .idle, "idle without data stays idle")
check(L.seeded(.failed(lastGood: nil), hasData: true, now: at), .failed(lastGood: nil), "a real failure is never hidden")

// MARK: الصفوف
check(L.smsLine(healthy()), "1,240 نقطة · تكفي نحو 18 يوماً", "SMS line, Latin digits with separators")
var noDays = healthy(); noDays.daysLeft = nil
check(L.smsLine(noDays), "1,240 نقطة", "no rate → points only")
var noBalance = healthy(); noBalance.balance = nil
check(L.smsLine(noBalance), "لا قراءة للرصيد بعد", "loaded without a balance")
check(L.smsLine(L.Facts()), "—", "loading → «—»")
check(L.smsWord(.good).text, "جيد", "good pill")
check(L.smsWord(.low).tone, .warn, "low is warn")
check(L.smsWord(.urgent).tone, .error, "urgent is error")
check(L.suspiciousWord(3).text, "3 جديدة", "suspicious pill")
check(L.registrationWord(open: true).text, "مسموح", "open → «مسموح»")
check(L.registrationWord(open: false).text, "متوقف", "closed → «متوقف»")
check(L.registrationWord(open: false).tone, .warn, "closed is warn")
check(L.registrationLine(healthy()), "12 رقماً ممنوعاً", "12 banned")
var bansFailed = healthy(); bansFailed.bans = .failed(lastGood: nil)
check(L.registrationLine(bansFailed), "تعذّر جلب الأرقام الممنوعة", "bans failed")
check(L.bannedLine(0), "لا أرقام ممنوعة", "0 banned")
check(L.bannedLine(1), "رقم واحد ممنوع", "1 banned")
check(L.bannedLine(2), "رقمان ممنوعان", "2 banned")
check(L.bannedLine(3), "3 أرقام ممنوعة", "3 banned")
check(L.bannedLine(100), "100 رقم ممنوع", "100 banned")
check(L.bannedLine(1240), "1,240 رقماً ممنوعاً", "1,240 banned")
check(L.bannedLabel(5), "أرقام ممنوعة", "header label 5")
check(L.bannedLabel(12), "رقماً ممنوعاً", "header label 12")
check(L.bannedLabel(0), "أرقام ممنوعة", "header label 0")

var reach = healthy(); reach.devicesReach = 412; reach.devicesFailed = 31
check(L.devicesWord(reach).text, "93٪", "reach percent rounded down")
check(L.devicesWord(reach).tone, .warn, "failed registrations → warn")
check(L.devicesWord(healthy()).tone, .ok, "no failures → ok")
check(L.devicesLine(reach), "تصل 412 جهازاً من 443 · 31 لا تصلها", "devices line with failures")
var noDevices = healthy(); noDevices.devicesTotal = 0; noDevices.devicesReach = 0
check(L.devicesWord(noDevices).text, "لا أجهزة", "no devices pill")
check(L.devicesLine(noDevices), "لا أجهزة مسجّلة بعد", "no devices line")
var fewDevices = healthy(); fewDevices.devicesTotal = 5; fewDevices.devicesReach = 5
check(L.devicesLine(fewDevices), "تصل 5 أجهزة من 5", "3–10 plural")

// MARK: فريق الإدارة
check(L.teamHeadline(7), "7 في الإدارة", "team headline")
let rows = L.teamRows(owners: 2, admins: 5, monitors: 0, supervisors: 0)
check(rows.map(\.label), ["المالكان", "المديرون", "المراقبون والمشرفون"], "zero roles merge into one last row")
check(rows.map(\.value), ["2", "5", "لا أحد بعد"], "row values")
check(rows.map(\.muted), [false, false, true], "the empty row is muted")
let one = L.teamRows(owners: 1, admins: 2, monitors: 1, supervisors: 4)
check(one.map(\.label), ["المالك", "المديران", "المراقب", "المشرفون"], "singular, dual, plural labels")
check(one.count, 4, "no empty row when every role has someone")

// MARK: الاستخدام
check(L.usageHeadline(active: 96), "96 نشطون", "usage headline")
check(L.usageHeadline(active: 0), "لا أحد نشط", "no active")
check(L.usageBaseLine(accounts: 171), "من 171 حساباً", "usage base line")
check(L.usageBaseLine(accounts: 2), "من حسابين", "usage base line, two")
check(L.usageBaseLine(accounts: 0), "لا حسابات بعد", "usage base line, none")

// MARK: الأعداد
check(L.days(0), "أقل من يوم", "0 days")
check(L.days(1), "يوم واحد", "1 day")
check(L.days(2), "يومين", "2 days")
check(L.days(5), "5 أيام", "5 days")
check(L.days(18), "18 يوماً", "18 days")
check(L.days(100), "100 يوم", "100 days")

// English
L10n.isArabic = false
check(L.headWord(issues: 2).text, "2 things need you", "English head word")
check(L.bannedLine(3), "3 blocked numbers", "English banned line")
check(L.teamRows(owners: 2, admins: 0, monitors: 0, supervisors: 1).map(\.label), ["Owners", "Supervisor", "Admins and monitors"],
      "English merged empty row")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
