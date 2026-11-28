// فحص منطق «رسائل الأعضاء» (Views/Features/Admin/AdminInboxView.swift، الوحدة U10) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u10-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxView.swift tests/admin-redesign/U10/main.swift && /tmp/u10-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminInboxMessageLogic
typealias F = L.Filters

func fact(unread: Bool = false, pending: Bool = true, today: Bool = false, kind: String = "استفسار") -> L.Fact {
    L.Fact(unread: unread, pending: pending, handled: !pending, today: today, kind: kind)
}

// ١٠ رسائل: ٤ غير مقروءة، ٦ بانتظار الرد، ٣ اليوم، ٤ معالَجة
let facts: [L.Fact] = [
    fact(unread: true, pending: true, today: true, kind: "شكوى"),
    fact(unread: true, pending: true, today: true, kind: "استفسار"),
    fact(unread: true, pending: false, today: false, kind: "اقتراح"),
    fact(unread: true, pending: true, today: false, kind: "اعتراض"),
    fact(unread: false, pending: true, today: true, kind: "استفسار"),
    fact(unread: false, pending: true, today: false, kind: "أخرى"),
    fact(unread: false, pending: true, today: false, kind: "استفسار"),
    fact(unread: false, pending: false, today: false, kind: "شكوى"),
    fact(unread: false, pending: false, today: false, kind: "اعتراض"),
    fact(unread: false, pending: false, today: false, kind: "اعتراض"),
]

// MARK: «الحالة»
check(L.count(facts, F()), 10, "no filter = every message")
check(L.count(facts, F(status: .unread)), 4, "unread")
check(L.count(facts, F(status: .awaiting)), 6, "awaiting reply = pending status")
check(L.count(facts, F(status: .today)), 3, "new today")
check(L.count(facts, F(status: .handled)), 4, "handled (kept from the old page filter)")
check(L.count(facts, F(status: .awaiting)) + L.count(facts, F(status: .handled)), 10,
      "awaiting + handled cover every message")

// MARK: «النوع» مع «الحالة»
check(L.count(facts, F(kind: "استفسار")), 3, "kind alone")
check(L.count(facts, F(status: .unread, kind: "استفسار")), 1, "status AND kind")
check(L.count(facts, F(status: .today, kind: "اقتراح")), 0, "a zero combination stays countable")
check(L.count(facts, F(kind: "غير موجود")), 0, "unknown kind = nothing (filtered-empty card, not a crash)")

// MARK: رقم الرأس = أول رقم تحت الشريط (T2): الضغط يضبط «الحالة» وحدها
let unreadHeader = facts.filter(\.unread).count
check(L.count(facts, F(status: .unread)), unreadHeader, "«N غير مقروءة» opens a list of N")
let awaitingHeader = facts.filter(\.pending).count
check(L.count(facts, F(status: .awaiting)), awaitingHeader, "«N بانتظار الرد» opens a list of N")

// MARK: صفوف «النوع» في الورقة
let fixed = ["استفسار", "اقتراح", "شكوى", "أخرى"]
check(L.kindOrder(fixed: fixed, facts: facts), fixed + ["اعتراض"], "four fixed kinds, then extras present")
check(L.kindOrder(fixed: fixed, facts: []), fixed, "the four kinds show even with no messages (zero = grey)")
let extras = [fact(kind: "ب"), fact(kind: "أ"), fact(kind: "أ"), fact(kind: "ج")]
check(L.kindOrder(fixed: fixed, facts: extras), fixed + ["أ", "ب", "ج"], "extras: most first, ties by first seen")

// MARK: «مسح الفلاتر»
check(F() == F(status: .all, kind: L.allKinds), true, "reset = all statuses, all kinds")
check(F(status: .unread) == F(), false, "a status filter is not the reset state")

// MARK: النصوص (عربية)
check(L.noun(1), "رسالة", "1 رسالة")
check(L.noun(2), "رسالتان", "2 رسالتان")
check(L.noun(7), "رسائل", "7 رسائل")
check(L.noun(12), "رسالة", "12 رسالة")
check(L.noun(100), "رسالة", "100 رسالة")
check(L.noun(103), "رسائل", "103 رسائل")
check(L.newPhrase(1), "رسالة جديدة", "one new: no number")
check(L.newPhrase(2), "رسالتان جديدتان", "two new: dual, no number")
check(L.newPhrase(7), "7 رسائل جديدة", "7 new")
check(L.newPhrase(15), "15 رسالة جديدة", "15 new")
check(L.deleteQuestion(1), "حذف الرسالة؟", "delete one asks with the verb")
check(L.deleteQuestion(2), "حذف الرسالتين؟", "delete two")
check(L.deleteQuestion(5), "حذف 5 رسائل؟", "delete five")
check(L.Status.unread.title, "غير مقروءة", "status title")

// MARK: English
L10n.isArabic = false
check(L.noun(1), "message", "en singular")
check(L.noun(3), "messages", "en plural")
check(L.newPhrase(3), "3 new messages", "en new phrase")
check(L.deleteQuestion(4), "Delete 4 messages?", "en delete question")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
