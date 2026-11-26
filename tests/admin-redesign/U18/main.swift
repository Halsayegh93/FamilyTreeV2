// فحص منطق «إشعارات الإدارة» (Views/Features/Admin/AdminNoticeLogic.swift، الوحدة U18) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u18-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminNoticeLogic.swift tests/admin-redesign/U18/main.swift && /tmp/u18-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminNoticeLogic
typealias F = L.Filter

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuwait")!
let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10))!
let todayLate = cal.date(byAdding: .hour, value: 3, to: today)!
let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
let lastWeek = cal.date(byAdding: .day, value: -6, to: today)!

// ٨ صفوف: حالتان مشتقتان، طلب معلّق، تنبيه أمني، تغييران، نشاط فريق، نظام
let facts: [L.Fact] = [
    L.Fact(category: .changes, needsAction: false, unread: true, date: today),            // 0 اليوم
    L.Fact(category: .action, needsAction: true, pinned: true, date: todayLate),          // 1 مشتقة
    L.Fact(category: .action, needsAction: true, unread: true, date: yesterday),          // 2 طلب معلّق (أمس)
    L.Fact(category: .system, needsAction: false, date: yesterday),                       // 3 رصيد منخفض (أمس)
    L.Fact(category: .team, needsAction: false, unread: true, date: todayLate),           // 4 اليوم (أحدث)
    L.Fact(category: .action, needsAction: true, pinned: true, date: today),              // 5 مشتقة ثانية
    L.Fact(category: .changes, needsAction: true, unread: true, date: lastWeek),          // 6 ابن مضاف «راجعه»
    L.Fact(category: .action, needsAction: false, date: lastWeek),                        // 7 طلب عولج
]

// MARK: الفلاتر
let c = L.counts(facts)
check(c[.all], 8, "all = every row")
check(c[.action], 4, "needs action = derived + pending + review child")
check(c[.changes], 2, "member changes")
check(c[.team], 1, "team activity")
check(c[.system], 1, "system")
check(L.chipCount(.all, counts: c, ready: true), nil, "no count on «الكل»")
check(L.chipCount(.action, counts: c, ready: true), 4, "count on «يحتاج إجراء»")
check(L.chipCount(.action, counts: c, ready: false), nil, "no count before data")
check(L.chipCount(.action, counts: [.action: 0], ready: true), nil, "no zero count")
check(L.chipCount(.system, counts: c, ready: true), nil, "only «يحتاج إجراء» carries a count (mock 11)")
check(L.chipCount(.changes, counts: c, ready: true), nil, "no count on «تغييرات الأعضاء»")

// MARK: الأقسام
let s = L.sections(facts, calendar: cal)
check(s.count, 4, "now + today + yesterday + last week")
check(s.first?.kind, .now, "«يحتاج إجراء الآن» first")
check(s.first?.indices, [1, 5, 2, 6], "derived first (newest first), then pending notices newest first")
check(s[1].kind, .day(cal.startOfDay(for: today)), "then today")
check(s[1].indices, [4, 0], "today newest first, action rows not repeated")
check(s[2].indices, [3], "yesterday without the pending request")
check(s[3].indices, [7], "last week: handled request only")
let flat = s.flatMap(\.indices)
check(Set(flat).count, facts.count, "every row in exactly one section")
check(flat.count, facts.count, "no row repeated")
check(L.sections([L.Fact(category: .team, needsAction: false, date: today)], calendar: cal).first?.kind,
      .day(cal.startOfDay(for: today)), "no «now» section when nothing needs action")
check(L.sections([], calendar: cal).isEmpty, true, "no rows = no sections")
check(L.keepsDerived(published: false), false, "derived hidden until «اليوم» published them this session")

// filter = needs action → one section only
let actionOnly = facts.filter { L.matches($0, .action) }
check(L.sections(actionOnly, calendar: cal).map(\.kind), [.now], "needs-action filter shows only «now»")

// MARK: حال الصفحة
let t0 = Date(timeIntervalSince1970: 1_000)
check(L.ready(health: .idle, hasNotices: false), false, "idle, nothing in hand")
check(L.ready(health: .idle, hasNotices: true), true, "notifications already fetched by the app")
check(L.ready(health: .failed(lastGood: t0), hasNotices: false), true, "stale data counts")
check(L.body(ready: false, health: .loading, total: 0, shown: 0, searching: false), .skeleton, "first load = skeleton")
check(L.body(ready: false, health: .failed(lastGood: nil), total: 0, shown: 0, searching: false), .failed,
      "failed with nothing = error + retry")
check(L.body(ready: false, health: .denied, total: 0, shown: 0, searching: false), .skeleton, "denied never retries")
check(L.body(ready: true, health: .loaded(at: t0), total: 0, shown: 0, searching: false), .empty, "empty")
check(L.body(ready: true, health: .loaded(at: t0), total: 5, shown: 0, searching: false), .filteredEmpty(searching: false),
      "filtered empty")
check(L.body(ready: true, health: .loaded(at: t0), total: 5, shown: 0, searching: true), .filteredEmpty(searching: true),
      "search empty")
check(L.body(ready: true, health: .loaded(at: t0), total: 5, shown: 3, searching: false), .list, "list")
check(L.showsRefreshError(ready: true, health: .failed(lastGood: t0), total: 5), true, "stale list keeps rows + error card")
check(L.showsRefreshError(ready: true, health: .loaded(at: t0), total: 5), false, "no error after success")
check(L.showsFilters(ready: false, health: .loading, total: 0), true, "filters hold their place while loading")
check(L.showsFilters(ready: false, health: .failed(lastGood: nil), total: 0), false, "no filters over the error card")
check(L.showsFilters(ready: true, health: .loaded(at: t0), total: 0), false, "no filters over «لا إشعارات»")

// MARK: الجلب
check(L.loadFailure(injected: true, featureAvailable: true, delivered: true, online: true), .injected, "injected wins")
check(L.loadFailure(injected: false, featureAvailable: false, delivered: true, online: true), .featureMissing,
      "missing table")
check(L.loadFailure(injected: false, featureAvailable: true, delivered: true, online: true), nil, "delivered = loaded")
check(L.loadFailure(injected: false, featureAvailable: true, delivered: false, online: false), .offline, "offline")
check(L.loadFailure(injected: false, featureAvailable: true, delivered: false, online: true), .server, "server error")
check(L.LoadFailure.offline.isExpected, true, "offline is a warning")
check(L.LoadFailure.server.isExpected, false, "server error is logged as an error")
// المحوّل: فشل بعد تحميل ناجح يُبقي البيانات بوقتها
var h = AdminStoreHealth.idle.beginning()
check(h, .loading, "first fetch = loading")
h = h.ending(success: true, at: t0)
check(h.beginning(), .loaded(at: t0), "refresh keeps the word")
check(h.ending(success: false), .failed(lastGood: t0), "failure after success keeps the time")

// MARK: النصوص
check(L.Filter.action.title, "يحتاج إجراء", "filter title")
check(L.countedVerb("مقروء", 3), "مقروء (3)", "selection bar count")
check(L.countedVerb("حذف", 1200), "حذف (1,200)", "grouped count")
check(L.deleteQuestion(1), "حذف الإشعار؟", "delete one")
check(L.deleteQuestion(2), "حذف إشعارين؟", "delete two")
check(L.deleteQuestion(5), "حذف 5 إشعارات؟", "delete five")
check(L.deleteQuestion(12), "حذف 12 إشعاراً؟", "delete twelve")
check(L.deleteQuestion(100), "حذف 100 إشعار؟", "delete a hundred")
check(L.unreadTail(), "غير مقروء", "unread tail")
check(L.backTitle("اليوم"), "الإدارة", "bell on «اليوم» → back reads the visible title «الإدارة»")
check(L.backTitle(nil), "الإدارة", "no opener → «الإدارة»")
check(L.backTitle("البحث"), "البحث", "other opener kept")

L10n.isArabic = false
check(L.deleteQuestion(4), "Delete 4 notifications?", "en delete question")
check(L.Filter.system.title, "System", "en filter")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
