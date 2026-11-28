// فحص إصلاحات جولة المحاكي (F1، ٢٠٢٦-١١-٢٦) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/f1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTeamArea.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminNoticeLogic.swift tests/admin-redesign/F1/main.swift && /tmp/f1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true
typealias Logic = AdminTodayLogic
let now = Date(timeIntervalSince1970: 1_800_000_000)
let metrics = Logic.metricsWord(inApp: 170)?.state

// MARK: ١) التحميل لا يُرسم فشلاً (spec A.12)

// الأعضاء: علامة فشل باقية من جلب سابق وجلب «اليوم» جارٍ = هيكل (كان «تعذّر التحميل» ثم «170 في التطبيق»)
let fetching = Logic.membersHealth(hasMembers: false, loadedAt: nil, fetch: AdminStoreHealth.failed(lastGood: nil).beginning())
check(fetching, .loading, "members: retry after an old failure is loading")
check(AdminTileLine.make(state: metrics, health: .combined([fetching, .loading]), readOnly: false).kind, .skeleton,
      "stats tile while members load → skeleton, not «تعذّر التحميل»")
check(Logic.membersHealth(hasMembers: false, loadedAt: nil, fetch: .idle), .idle, "members: before the first fetch → idle")
check(Logic.membersHealth(hasMembers: true, loadedAt: now, fetch: .failed(lastGood: nil)), .loaded(at: now),
      "members: members in hand → loaded whatever the fetch said")
// نهاية الجلب
check(Logic.membersFetchEnded(hasMembers: true, loadFailed: true, at: now), .loaded(at: now), "fetch ended with members")
check(Logic.membersFetchEnded(hasMembers: false, loadFailed: true), .failed(lastGood: nil), "fetch ended in failure")
check(Logic.membersFetchEnded(hasMembers: false, loadFailed: false), .idle, "fetch cancelled → idle (skeleton)")
check(AdminTileLine.make(state: metrics, health: .combined([Logic.membersFetchEnded(hasMembers: false, loadFailed: true)]),
                         readOnly: false).text, "تعذّر التحميل", "a real members failure still says «تعذّر التحميل»")

// قوائم الحسابات: الجلب أُلغي (المخزن رجع لحاله) أو آخر ما زال جارياً — ليس فشلاً
check(Logic.accountsHealth(after: .loading, store: .idle, storeLoaded: false), .loading, "accounts: cancelled first load → loading")
check(Logic.accountsHealth(after: .loading, store: .loading, storeLoaded: false), .loading, "accounts: another fetch running → loading")
check(Logic.accountsHealth(after: .loading, store: .loaded(at: now), storeLoaded: true, at: now), .loaded(at: now), "accounts: loaded")
check(Logic.accountsHealth(after: .loading, store: .failed(lastGood: nil), storeLoaded: false), .failed(lastGood: nil),
      "accounts: real failure, nothing before → failed")
check(Logic.accountsHealth(after: .loaded(at: now), store: .failed(lastGood: now), storeLoaded: true), .failed(lastGood: now),
      "accounts: failure after a good load keeps the word + «آخر تحديث»")
check(Logic.accountsHealth(after: .loaded(at: now), store: .idle, storeLoaded: true, at: now), .loaded(at: now),
      "accounts: cancelled refresh over data stays loaded")
for h in [AdminStoreHealth.idle, .loading] {
    check(AdminTileLine.make(state: metrics, health: h, readOnly: false).kind, .skeleton, "idle/loading tile → skeleton (\(h))")
    check(AdminTileLine.make(state: nil, health: h, readOnly: false).kind, .skeleton, "idle/loading tile, no word yet → skeleton")
}

// MARK: ٢) «خارج العائلة» = الأحياء وحدهم

check(AdminCensusText.outsideLivingSub, "أحياء", "outside row: «أحياء» only, no «و87 متوفى»")

// MARK: ٣) «بانتظار قرارك» = شريحة «الوارد» نفسها؛ طلبات الخصوصية حقيقة وحدها (T2)

// طلب خصوصية وحده (حالة الجولة): لا «طلب واحد بانتظار قرارك» (الوارد يقول 0)، ولا «لا جديد» كاذبة
let privacyOnly = Logic.inboxWord(urgent: 0, waiting: 0, late: 0, policy: 1, fourth: .messages, fourthCount: 0)
check(privacyOnly.state, AdminTileState.attention("طلب خصوصية"), "tile: one privacy request is its own fact")
check(privacyOnly.landing, nil, "privacy opens «الوارد» unfiltered (its door row is there)")
check(privacyOnly.state.text.contains("بانتظار قرارك"), false, "privacy never says «بانتظار قرارك»")
let mixed = Logic.inboxWord(urgent: 0, waiting: 3, late: 0, policy: 2, fourth: .messages, fourthCount: 7)
check(mixed.state.text, "3 طلبات · طلبا خصوصية", "waiting (inbox chip) then privacy; messages drop (two facts max)")
check(mixed.landing, .inbox(AdminInboxLanding(status: .waiting)), "lands on «بانتظار قرارك» = the same count")
check(Logic.inboxWord(urgent: 0, waiting: 0, late: 0, fourth: .messages, fourthCount: 0).state, AdminTileState.good("لا جديد"),
      "no policy argument → unchanged (compat)")
check(Logic.policyText(3), "3 طلبات خصوصية", "three privacy requests")
check(Logic.policyText(11), "11 طلب خصوصية", "eleven privacy requests")

var privacyLine = Logic.SmartInput()
privacyLine.policy = 1
check(Logic.smartLine(privacyLine)?.text, "طلب خصوصية بانتظار الرد", "smart line: privacy, not «بانتظار قرارك»")
check(Logic.smartLine(privacyLine)?.link, AdminTodayLink(home: .inbox), "smart line opens «الوارد» unfiltered")
privacyLine.waiting = 2
check(Logic.smartLine(privacyLine)?.text, "طلبان بانتظار قرارك", "waiting outranks privacy")
privacyLine.waiting = 0
privacyLine.opens = []
check(Logic.smartLine(privacyLine)?.link, nil, "inbox hidden for the role → line reads, opens nothing")

// MARK: ٤) قاعدة «الاستخدام» = كل الحسابات، لا «لهم حساب»

check(AdminTeamLogic.usageBaseLine(accounts: 171), "من 171 حساباً", "usage base: every account")
check(AdminTeamLogic.usageBaseLine(accounts: 5), "من 5 حسابات", "five accounts")
check(AdminTeamLogic.usageBaseLine(accounts: 1), "من حساب واحد", "one account")
check(AdminTeamLogic.usageBaseLine(accounts: 2), "من حسابين", "two accounts")
check(AdminTeamLogic.usageBaseLine(accounts: 1_200), "من 1,200 حساب", "thousands")
check(AdminTeamLogic.usageBaseLine(accounts: 0), "لا حسابات بعد", "none")
check(AdminTeamLogic.usageBaseLine(accounts: 171).contains("لهم حساب"), false, "never «لهم حساب» (that is the stats' 170)")

// MARK: ٥) رجوع «إشعارات الإدارة»: من المصدر، بلا ترجمة «اليوم»

check(AdminNoticeLogic.backTitle("الإدارة"), "الإدارة", "bell passes «الإدارة»")
check(AdminNoticeLogic.backTitle("اليوم"), "اليوم", "no hidden «اليوم» → «الإدارة» mapping")
check(AdminNoticeLogic.backTitle(nil), "الإدارة", "no opener → «الإدارة»")

// MARK: English

L10n.isArabic = false
check(Logic.policyText(1), "1 privacy request", "en: one privacy request")
check(AdminTeamLogic.usageBaseLine(accounts: 171), "of 171 accounts", "en: usage base")
check(AdminCensusText.outsideLivingSub, "Living", "en: outside row")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
