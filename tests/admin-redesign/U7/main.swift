// فحص منطق «اليوم» (Views/Features/Admin/AdminTodayLogic.swift، الوحدة U7) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u7-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayLogic.swift tests/admin-redesign/U7/main.swift && /tmp/u7-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias Logic = AdminTodayLogic

// MARK: سطر التحية الذكي — الأولوية تبدأ بالعاجل (spec C.1)

var input = Logic.SmartInput()
input.loading = true
input.urgent = 2
check(Logic.smartLine(input), nil, "loading → no line (reserved, no fake «quiet day»)")

input = Logic.SmartInput(urgent: 2, waiting: 5, memorialToday: ["فلان"], unannounced: ["علان"], joinedThisWeek: 3)
let urgentLine = Logic.smartLine(input)
check(urgentLine?.text, "طلبان عاجلان في الوارد", "urgent wins over memorial, unannounced and waiting")
check(urgentLine?.link, AdminTodayLink(home: .inbox, landing: .inbox(AdminInboxLanding(status: .urgent))),
      "urgent line opens the inbox on «عاجل»")
check(Logic.urgentLine(1), "طلب عاجل في الوارد", "one urgent")
check(Logic.urgentLine(3), "3 طلبات عاجلة في الوارد", "3 urgent")
check(Logic.urgentLine(12), "12 طلباً عاجلاً في الوارد", "12 urgent")

input.urgent = 0
let memorial = Logic.smartLine(input)
check(memorial?.text, "اليوم ذكرى وفاة فلان", "memorial today is second")
check(memorial?.link, AdminTodayLink(home: .occasions, landing: .occasions(.memorials)), "memorial opens occasions on memorials")
input.memorialToday = ["فلان", "علان", "زيد"]
check(Logic.smartLine(input)?.text, "اليوم ذكرى وفاة فلان و2 آخرين", "three memorials")

input.memorialToday = []
let unannounced = Logic.smartLine(input)
check(unannounced?.text, "لم يُعلَن بعد عن وفاة علان", "unannounced is third")
check(unannounced?.link, AdminTodayLink(home: .occasions, landing: .occasions(.awaiting)), "unannounced opens «ينتظر إعلاناً»")
input.unannounced = ["أ", "ب", "ج"]
check(Logic.smartLine(input)?.text, "3 وفيات لم يُعلَن عنها بعد", "three unannounced")

input.unannounced = []
let waiting = Logic.smartLine(input)
check(waiting?.text, "5 طلبات بانتظار قرارك", "waiting is fourth")
check(waiting?.link, AdminTodayLink(home: .inbox, landing: .inbox(AdminInboxLanding(status: .waiting))), "waiting opens «بانتظار قرارك»")
input.waiting = 1
check(Logic.smartLine(input)?.text, "طلب واحد بانتظار قرارك", "one waiting")

input.waiting = 0
let joined = Logic.smartLine(input)
check(joined?.text, "انضمّ 3 أعضاء هذا الأسبوع", "joined this week is fifth")
check(joined?.link, AdminTodayLink(home: .family, landing: .members(.joinedThisWeek)),
      "joined opens «العائلة» on exactly who joined this week (owner 2026-11-27)")
check(AdminMembersLanding.joinedThisWeek,
      AdminMembersLanding(account: .all, life: .all, population: [.men], sub: "newThisWeek"),
      "joined landing = {رجال} + the «newThisWeek» list, no other filter")
input.joinedThisWeek = 1
check(Logic.smartLine(input)?.text, "انضمّ عضو جديد هذا الأسبوع", "one joined")

input.joinedThisWeek = nil
let quiet = Logic.smartLine(input)
check(quiet?.text, "ما في طلبات — يوم هادئ", "quiet day")
check(quiet?.link, nil, "quiet line opens nothing")

// بيت مخفي لدورك: السطر يُقرأ ولا يفتح
var hidden = Logic.SmartInput(memorialToday: ["فلان"])
hidden.opens = [.inbox]
check(Logic.smartLine(hidden)?.text, "اليوم ذكرى وفاة فلان", "hidden home keeps the line")
check(Logic.smartLine(hidden)?.link, nil, "hidden home → no link")

// MARK: «الوارد» — حقيقتان على الأكثر، والهبوط على فلتر الأولى

let inboxTwo = Logic.inboxWord(urgent: 2, waiting: 5, late: 1, fourth: .messages, fourthCount: 7)
check(inboxTwo.state.text, "2 عاجل · 5 بانتظارك", "two facts: urgent then waiting (short form)")
check(inboxTwo.state.tone, .urgent, "joined tone = strongest")
check(inboxTwo.landing, .inbox(AdminInboxLanding(status: .urgent)), "lands on the first fact's filter")

let inboxOne = Logic.inboxWord(urgent: 0, waiting: 5, late: 0, fourth: .messages, fourthCount: 0)
check(inboxOne.state.text, "5 بانتظار قرارك", "one fact keeps the long form")
check(inboxOne.state.tone, .attention, "waiting tone")
check(inboxOne.landing, .inbox(AdminInboxLanding(status: .waiting)), "waiting landing")

let inboxMessages = Logic.inboxWord(urgent: 0, waiting: 0, late: 0, fourth: .messages, fourthCount: 7)
check(inboxMessages.state.text, "7 رسائل جديدة", "messages (owner/admin fourth)")
check(inboxMessages.landing, nil, "messages have no list filter")
check(Logic.messagesText(1), "رسالة جديدة", "one message")
check(Logic.messagesText(2), "رسالتان جديدتان", "two messages")
check(Logic.messagesText(11), "11 رسالة جديدة", "11 messages")

let inboxReports = Logic.inboxWord(urgent: 0, waiting: 4, late: 0, fourth: .reports, fourthCount: 3)
check(inboxReports.state.text, "4 بانتظارك · 3 بلاغات", "supervisor: waiting then reports")
let reportsOnly = Logic.inboxWord(urgent: 0, waiting: 0, late: 0, fourth: .reports, fourthCount: 3)
check(reportsOnly.landing, .inbox(AdminInboxLanding(kind: .reports)), "reports land on the reports kind")

let monitor = Logic.inboxWord(urgent: 0, waiting: 0, late: 0, fourth: .treeIssues, fourthCount: 4)
check(monitor.state, AdminTileState.good("لا جديد"), "monitor: tree issues live on the family tile, not here")

let late = Logic.inboxWord(urgent: 0, waiting: 0, late: 2, fourth: .messages, fourthCount: 0)
check(late.state.text, "2 متأخر", "late")
check(late.landing, .inbox(AdminInboxLanding(status: .late)), "late landing")

let calm = Logic.inboxWord(urgent: 0, waiting: 0, late: 0, fourth: .messages, fourthCount: 0)
check(calm.state, AdminTileState.good("لا جديد"), "nothing → «لا جديد» ✓")
check(calm.landing, nil, "calm → no landing")

// T1: الكلمة الهادئة لا تظهر قبل وصول المخزن أو بعد فشله (يرسمها `AdminTileLine`)
check(AdminTileLine.make(state: calm.state, health: .failed(lastGood: nil), readOnly: false).text, "تعذّر التحميل",
      "failed inbox store never says «لا جديد»")
check(AdminTileLine.make(state: calm.state, health: .loading, readOnly: false).kind, .skeleton, "loading → skeleton")

// MARK: «العائلة»

let family = Logic.familyWord(treeIssues: 4)
check(family.state, AdminTileState.attention("4 مشكلات في الشجرة"), "tree issues word")
check(family.landing, .members(AdminMembersLanding(review: .problems)), "tree issues push the «مشكلات» list over the root")
check(Logic.familyWord(treeIssues: 1).state.text, "مشكلة واحدة في الشجرة", "one problem")
check(Logic.familyWord(treeIssues: 2).state.text, "مشكلتان في الشجرة", "two problems")
check(Logic.familyWord(treeIssues: 15).state.text, "15 مشكلة في الشجرة", "15 problems")
check(Logic.familyWord(treeIssues: 0).state, AdminTileState.good("سليمة"), "healthy tree")
check(Logic.familyWord(treeIssues: 0).landing, nil, "healthy → no landing")

// MARK: «المناسبات»

let occ = Logic.occasionsWord(unannounced: 1, scheduledToday: 2, nextMemorial: "بعد 3 أيام")
check(occ.state, AdminTileState.attention("وفاة لم تُعلن"), "unannounced first")
check(occ.landing, .occasions(.awaiting), "unannounced landing")
check(Logic.occasionsWord(unannounced: 2, scheduledToday: 0, nextMemorial: nil).state.text, "وفاتان لم تُعلنا", "two unannounced")
check(Logic.occasionsWord(unannounced: 3, scheduledToday: 0, nextMemorial: nil).state.text, "3 وفيات لم تُعلن", "three unannounced")
let scheduled = Logic.occasionsWord(unannounced: 0, scheduledToday: 2, nextMemorial: "بعد 3 أيام")
check(scheduled.state, AdminTileState.neutral("مجدول اليوم 2"), "scheduled today second")
check(scheduled.landing, .occasions(.scheduled), "scheduled landing")
let memorialWord = Logic.occasionsWord(unannounced: 0, scheduledToday: 0, nextMemorial: "بعد 3 أيام")
check(memorialWord.state, AdminTileState.neutral("ذكرى بعد 3 أيام"), "next memorial within a week")
check(memorialWord.landing, .occasions(.memorials), "memorial landing")
check(Logic.occasionsWord(unannounced: 0, scheduledToday: 0, nextMemorial: nil).state,
      AdminTileState.neutral("لا شيء قريب"), "nothing coming up")

// MARK: «الإحصاءات» — الرقم = عنوان قسمه (T2)

check(Logic.metricsWord(inApp: 170)?.state, AdminTileState.neutral("170 في التطبيق"), "in-app word")
check(Logic.metricsWord(inApp: 170)?.landing, .stats(.inApp), "in-app opens the «في التطبيق» section")
check(Logic.metricsWord(inApp: 2_489)?.state.text, "2,489 في التطبيق", "thousands separator")
check(Logic.metricsWord(inApp: nil), nil, "no accounts yet → no word")

// MARK: «الفريق والأمان» (المالك)

check(Logic.teamWord(suspicious: 3, smsLevel: .low, devicesFailed: 2, registrationOpen: false).state,
      AdminTileState.urgent("3 محاولات مريبة"), "suspicious attempts first")
check(Logic.teamWord(suspicious: 0, smsLevel: .urgent, devicesFailed: 0, registrationOpen: true).state,
      AdminTileState.urgent("الرصيد منخفض جداً"), "urgent balance")
check(Logic.teamWord(suspicious: 0, smsLevel: .low, devicesFailed: 2, registrationOpen: true).state,
      AdminTileState.attention("الرصيد منخفض"), "low balance")
check(Logic.teamWord(suspicious: 0, smsLevel: .good, devicesFailed: 3, registrationOpen: true).state,
      AdminTileState.attention("3 أجهزة لا تصلها الإشعارات"), "failed devices (Autoplan note 4)")
check(Logic.teamWord(suspicious: 0, smsLevel: .good, devicesFailed: 1, registrationOpen: true).state.text,
      "جهاز لا تصله الإشعارات", "one failed device")
check(Logic.teamWord(suspicious: 0, smsLevel: .good, devicesFailed: 0, registrationOpen: false).state,
      AdminTileState.attention("التسجيل متوقف"), "registration stopped")
check(Logic.teamWord(suspicious: 0, smsLevel: .good, devicesFailed: 0, registrationOpen: nil).state,
      AdminTileState.good("سليم"), "all good")
// T1: «سليم» لا يظهر وقد فشل مخزن الرصيد
check(AdminTileLine.make(state: Logic.teamWord(suspicious: 0, smsLevel: .unknown, devicesFailed: 0, registrationOpen: true).state,
                         health: AdminStoreHealth.combined([.failed(lastGood: nil), .loaded(at: Date())]), readOnly: false).text,
      "تعذّر التحميل", "failed SMS store → «تعذّر التحميل», never «سليم»")

// MARK: «التطبيق» (المالك)

check(Logic.appWord(maintenance: true, notificationsPaused: true).state, AdminTileState.urgent("الصيانة مفعّلة"), "maintenance")
check(Logic.appWord(maintenance: false, notificationsPaused: true).state, AdminTileState.attention("الإشعارات موقوفة"), "paused")
check(Logic.appWord(maintenance: false, notificationsPaused: false).state, AdminTileState.good("يعمل للجميع"), "open")

// MARK: «للاطلاع» على سطر القسم المقروء فقط (المدير على «الفريق والأمان») — F2: عين بعد الكلمة، لا ذيل يلفّ السطر

check(AdminTileLine.make(state: nil, health: nil, readOnly: true).text, "للاطلاع", "read-only area with no word")
let readMetrics = AdminTileLine.make(state: Logic.metricsWord(inApp: 170)?.state, health: .loaded(at: Date()),
                                     readOnly: true)
check(readMetrics.text, "170 في التطبيق", "read-only metrics: the word alone, one line")
check(readMetrics.readOnlyMark, true, "read-only metrics: eye after the word")
check(readMetrics.spoken, "170 في التطبيق، للاطلاع", "read-only metrics: VoiceOver says «للاطلاع»")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
