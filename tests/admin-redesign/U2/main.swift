// فحص منطق عقود لوحة الإدارة (Views/Features/Admin/AdminContracts.swift، الوحدة U2) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u2-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift tests/admin-redesign/U2/main.swift && /tmp/u2-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuwait")!
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 21, minute: 41))!
let earlier = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 9, minute: 12))!
let yesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9, minute: 12))!
let older = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9, minute: 12))!

// MARK: حال المخزن ← الرسم
check(AdminStoreHealth.idle.look, .skeleton, "idle → skeleton")
check(AdminStoreHealth.loading.look, .skeleton, "loading → skeleton")
check(AdminStoreHealth.loaded(at: earlier).look, .word, "loaded → word")
check(AdminStoreHealth.failed(lastGood: nil).look, .unknown, "failed without data → unknown (never a calm word)")
check(AdminStoreHealth.failed(lastGood: earlier).look, .staleWord(since: earlier), "failed after a good load → word + time")
check(AdminStoreHealth.denied.look, .hidden, "denied → hidden")
check(AdminStoreHealth.denied.canRetry, false, "denied never retries")
check(AdminStoreHealth.failed(lastGood: nil).canRetry, true, "failed retries")

// MARK: انتقالات المحوّل
check(AdminStoreHealth.idle.beginning(), .loading, "first fetch → loading")
check(AdminStoreHealth.loaded(at: earlier).beginning(), .loaded(at: earlier), "refresh keeps the word")
check(AdminStoreHealth.failed(lastGood: nil).beginning(), .loading, "retry without data → skeleton")
check(AdminStoreHealth.failed(lastGood: earlier).beginning(), .failed(lastGood: earlier), "retry with old data keeps it")
check(AdminStoreHealth.loading.ending(success: false, at: now), .failed(lastGood: nil), "first fetch fails → unknown")
check(AdminStoreHealth.loaded(at: earlier).ending(success: false, at: now), .failed(lastGood: earlier), "refresh fails → stale")
check(AdminStoreHealth.failed(lastGood: earlier).ending(success: true, at: now), .loaded(at: now), "retry succeeds")

// MARK: عدّة مخازن
check(AdminStoreHealth.combined([.loaded(at: now), .failed(lastGood: nil), .loading]), .failed(lastGood: nil),
      "combined: a failed store with nothing wins")
check(AdminStoreHealth.combined([.loaded(at: now), .loading]), .loading, "combined: still loading")
check(AdminStoreHealth.combined([.loaded(at: now), .failed(lastGood: older), .failed(lastGood: earlier)]),
      .failed(lastGood: older), "combined: stale with the oldest time")
check(AdminStoreHealth.combined([.loaded(at: now), .loaded(at: earlier), .denied]), .loaded(at: earlier),
      "combined: denied ignored, oldest load")
check(AdminStoreHealth.combined([.denied]), .denied, "combined: all denied")
check(AdminStoreHealth.combined([]), .idle, "combined: none")

// MARK: النصوص
L10n.isArabic = true
check(AdminStoreHealthText.updated(earlier, now: now, calendar: cal), "آخر تحديث 9:12", "stamp today")
check(AdminStoreHealthText.updated(yesterday, now: now, calendar: cal), "آخر تحديث أمس 9:12", "stamp yesterday")
check(AdminStoreHealthText.updated(older, now: now, calendar: cal), "آخر تحديث 24/11", "stamp older")
L10n.isArabic = false
check(AdminStoreHealthText.updated(earlier, now: now, calendar: cal), "Updated 9:12", "stamp english")
L10n.isArabic = true
check(AdminNumberText.grouped(2991), "2,991", "thousands")
check(AdminNumberText.grouped(170), "170", "hundreds")
check(AdminNumberText.grouped(1_234_567), "1,234,567", "millions")
check(AdminNumberText.grouped(0), "0", "zero")

// MARK: عنصر سطر الرأس — لا صفر ولا تحميل ولا فشل كرقم عادي
let loading = AdminHeaderItemLook.make(value: nil, health: nil, opens: true)
check(loading.text, "—", "no value → —")
check(loading.opens, false, "loading opens nothing")
check(loading.dim, true, "loading dim")
let zero = AdminHeaderItemLook.make(value: 0, health: .loaded(at: now), opens: true)
check(zero.text, "0", "zero shown")
check(zero.opens, false, "zero opens nothing")
check(zero.dim, true, "zero dim")
let five = AdminHeaderItemLook.make(value: 2729, health: .loaded(at: now), opens: true)
check(five.text, "2,729", "number grouped")
check(five.opens, true, "number opens")
check(five.dim, false, "number bright")
check(AdminHeaderItemLook.make(value: 5, health: .loaded(at: now), opens: false).opens, false, "no tap → no chevron")
let failed = AdminHeaderItemLook.make(value: 7, health: .failed(lastGood: nil), opens: true)
check(failed.text, "—", "failed → — (old value not trusted)")
check(failed.retry, true, "failed → retry")
check(failed.opens, false, "failed opens nothing")
let stale = AdminHeaderItemLook.make(value: 7, health: .failed(lastGood: earlier), opens: true)
check(stale.text, "7", "stale keeps the number")
check(stale.staleSince, earlier, "stale carries the time")
check(stale.opens, true, "stale still opens")
check(AdminHeaderItemLook.make(value: 3, health: .denied, opens: true).hidden, true, "denied hidden")
check(AdminHeaderItemLook.make(value: nil, text: "93٪", health: .loaded(at: now), opens: true).text, "93٪", "text override")
check(AdminHeaderItemLook.make(value: 12, text: "93٪", health: .loading, opens: true).text, "—", "text waits for load")

// MARK: الهبوط — القائمة البيضاء والقصّ
check(AdminInboxLanding(pushKind: "child_add"), AdminInboxLanding(group: .tree, kind: .children), "push child_add")
check(AdminInboxLanding(pushKind: "news_report"), AdminInboxLanding(kind: .reports), "push news_report")
check(AdminInboxLanding(pushKind: "content_report").kind, .reports, "push content_report")
check(AdminInboxLanding(pushKind: "tree_edit"), AdminInboxLanding(group: .tree), "push tree_edit → tree group")
check(AdminInboxLanding(pushKind: "admin_request").isEmpty, true, "generic push → unfiltered")
check(AdminInboxLanding(pushKind: "drop table").isEmpty, true, "unknown kind → unfiltered")
check(AdminInboxLanding(pushKind: "join_request").group, .members, "join → members")

let monitorKinds: Set<String> = ["all", "joinRequests", "nameChange", "phone", "deceased", "children", "treeAdd",
                                 "treeEditName", "treeEditPhone", "treeEditBirth", "treeDeceased", "treeAddDeathDate",
                                 "treeAddPhoto", "treeDelete", "treeOther", "photos"]
let supervisorKinds: Set<String> = ["all", "news", "reports", "diwaniya", "projects", "archive"]
check(AdminInboxLanding(pushKind: "news_report").clamped(toKinds: monitorKinds).isEmpty, true,
      "monitor gets a report push → inbox unfiltered")
check(AdminInboxLanding(pushKind: "news_report").clamped(toKinds: supervisorKinds).kind, .reports,
      "supervisor keeps reports")
check(AdminInboxLanding(pushKind: "tree_edit").clamped(toKinds: supervisorKinds).group, nil,
      "supervisor: tree group dropped")
check(AdminInboxLanding(pushKind: "tree_edit").clamped(toKinds: monitorKinds).group, .tree, "monitor keeps tree group")
check(AdminInboxLanding(status: .urgent, kind: .reports).clamped(toKinds: monitorKinds),
      AdminInboxLanding(status: .urgent), "clamp keeps the status")

// الصريح يغلب
let landed = AdminInboxLanding(status: .urgent, kind: .children, source: .familyTree)
check(landed.overridden(by: AdminInboxLanding(status: .late)), AdminInboxLanding(status: .late, kind: .children, source: .familyTree),
      "explicit status wins")
check(landed.overridden(by: AdminInboxLanding(group: .content)).kind, nil, "explicit group drops the landed kind")
check(AdminMembersLanding(account: .with, life: .alive).overridden(by: AdminMembersLanding(life: .all)),
      AdminMembersLanding(account: .with, life: .all), "members explicit life wins")
check(AdminWomenLanding(status: .registered).overridden(by: AdminWomenLanding()).status, .registered,
      "women landing kept when nothing explicit")

// المخزن: مرة واحدة، ويمسح ما قبله، والنوع الخطأ يُمسح
var store = AdminLandingStore()
store.land(.inbox(AdminInboxLanding(status: .urgent)), hop: 3)
check(store.take(.stats, hop: 3), nil, "wrong area → nil")
check(store.isEmpty, true, "wrong area still consumed")
store.land(.inbox(AdminInboxLanding(status: .urgent)), hop: 4)
store.land(.stats(.inApp), hop: 5)
check(store[4], nil, "a new land clears the old hop")
check(store.take(.stats, hop: 5), .inApp, "take stats")
check(store.take(.stats, hop: 5), nil, "take is one-shot")
store.land(.members(AdminMembersLanding(review: .problems)), hop: 6)
check(store.take(.members, hop: nil), nil, "no hop → nil")
store.clear()
check(store.isEmpty, true, "clear")
check(AdminInboxLanding.Kind.allCases.count, 20, "whitelist = RequestTab minus all")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
