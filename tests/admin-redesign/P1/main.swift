// فحص منطق «نبّهه يضيف صورة» + التذكير (Views/Features/Admin/PhotoNudgeLogic.swift، الوحدة P1) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/p1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/PhotoNudgeLogic.swift tests/admin-redesign/P1/main.swift \
//     && /private/tmp/claude-501/p1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = PhotoNudgeLogic

var kuwait = Calendar(identifier: .gregorian)
kuwait.timeZone = TimeZone(identifier: "Asia/Kuwait")!
let now = ISO8601DateFormatter().date(from: "2026-11-26T15:00:00Z")!   // 18:00 الكويت
func ago(days: Double = 0, seconds: Double = 0) -> Date { now.addingTimeInterval(-(days * 86_400 + seconds)) }

let me = UUID(), other = UUID()
let owner = L.Viewer(id: me, canEdit: true, isOwner: true, canBulk: true)
let admin = L.Viewer(id: me, canEdit: true, isOwner: false, canBulk: true)
let monitor = L.Viewer(id: me, canEdit: true, isOwner: false, canBulk: false)
let readOnly = L.Viewer(id: me, canEdit: false, isOwner: false, canBulk: false)   // المشرف / «للاطلاع»

func member(id: UUID = other, deceased: Bool = false, login: Bool = true, photo: Bool = false, female: Bool = false,
            isOwner: Bool = false, active: Bool = true) -> L.Member {
    L.Member(id: id, isDeceased: deceased, hasLogin: login, hasPhoto: photo, isFemale: female, isOwner: isOwner, isActive: active)
}
func open(_ notified: Date?, sent: Int? = 0, reason: String = "", hide: Bool = false) -> L.Open {
    L.Open(notifiedAt: notified, requestedAt: notified ?? ago(days: 9), remindersSent: sent, reason: reason, hidePhoto: hide)
}

// MARK: - الصورة

check(L.hasPhoto(avatar: nil, photo: nil), false, "photo: both empty → none")
check(L.hasPhoto(avatar: "  ", photo: ""), false, "photo: spaces → none (same as server btrim)")
check(L.hasPhoto(avatar: nil, photo: "https://x/p.jpg"), true, "photo: photo_url alone counts")
check(L.hasPhoto(avatar: "https://x/a.jpg", photo: nil), true, "photo: avatar_url counts")

// MARK: - من يرى «نبّهه يضيف صورة»

check(L.canNudge(admin, member()), true, "who: admin → registered, living, no photo → button")
check(L.canNudge(monitor, member()), true, "who: monitor gets the per-member button too")
check(L.canNudge(readOnly, member()), false, "who: supervisor / read-only → no button")
check(L.canNudge(admin, member(login: false)), false, "who: no account → no button")
check(L.canNudge(admin, member(deceased: true)), false, "who: deceased → no button")
check(L.canNudge(admin, member(photo: true)), false, "who: has a photo → not «نبّهه» (that's «طلب تغيير»)")
check(L.canNudge(admin, member(female: true)), false, "who: woman → no button (no photos for women; server says female_no_photo)")
check(L.canNudge(admin, member(id: me)), false, "who: yourself → no button")
check(L.canNudge(admin, member(isOwner: true)), false, "who: owner protected from admin")
check(L.canNudge(monitor, member(isOwner: true)), false, "who: owner protected from monitor")
check(L.canNudge(owner, member(isOwner: true)), true, "who: owner may notify the other owner")
check(L.canAskChange(admin, member(photo: true)), true, "who: has photo → «طلب تغيير الصورة»")
check(L.canAskChange(admin, member(photo: false)), false, "who: no photo → no change request")
check(L.canAct(admin, member(active: false)), true, "who: frozen member keeps the sheet button (server single path doesn't check status)")

// MARK: - حالات الصفّ

check(L.row(viewer: admin, member: member(), open: nil, maxReminders: 3, now: now, calendar: kuwait), .nudge,
      "row: no photo, no request → «نبّهه يضيف صورة»")
check(L.row(viewer: admin, member: member(photo: true), open: nil, maxReminders: 3, now: now, calendar: kuwait), .askChange,
      "row: has photo, no request → «طلب تغيير الصورة»")
check(L.row(viewer: readOnly, member: member(), open: open(ago(days: 1)), maxReminders: 3, now: now, calendar: kuwait), .hidden,
      "row: read-only viewer → no row at all")
// F4 (V24): المتوفى بطلب مفتوح يُرى ويُلغى (بلا تذكير) — بلا طلب لا صفّ
check(L.row(viewer: admin, member: member(deceased: true), open: nil, maxReminders: 3, now: now, calendar: kuwait), .hidden,
      "row: deceased without a request → hidden")
if case .pending(let p) = L.row(viewer: admin, member: member(deceased: true), open: open(ago(days: 1)), maxReminders: 3,
                                now: now, calendar: kuwait) {
    check(p.canRemind || !p.canCancel, false, "row: deceased with an open request → cancel only (F4, V24)")
} else {
    check(false, true, "row: deceased with an open request → pending (F4, V24)")
}
check(L.row(viewer: admin, member: member(female: true), open: nil, maxReminders: 3, now: now, calendar: kuwait), .hidden,
      "row: woman without photo → hidden")
check(L.row(viewer: admin, member: member(login: false), open: nil, maxReminders: 3, now: now, calendar: kuwait), .hidden,
      "row: no account → hidden")

let fiveDays = L.row(viewer: admin, member: member(), open: open(ago(days: 5), sent: 1), maxReminders: 3, now: now, calendar: kuwait)
check(fiveDays, .pending(L.Pending(isAdd: true, line: "نُبّه قبل 5 أيام · ذُكّر 1 من 3 · بانتظار صورته", reason: nil,
                                   canRemind: true, remindAt: nil, canCancel: true)),
      "row: open add request → «نُبّه قبل 5 أيام · ذُكّر 1 من 3 · بانتظار صورته» + «ذكّره الحين» + «إلغاء التنبيه»")

let justSent = L.row(viewer: admin, member: member(), open: open(ago(seconds: 20)), maxReminders: 3, now: now, calendar: kuwait)
if case .pending(let p) = justSent {
    check(p.line, "نُبّه اليوم · بانتظار صورته", "row: just notified, no reminders yet → no «ذُكّر»")
    check(p.canRemind, false, "row: «ذكّره الحين» hidden for 1 minute after a send")
    check(p.remindAt, ago(seconds: 20).addingTimeInterval(60), "row: «ذكّره الحين» comes back 60 s after the notice")
    check(p.canCancel, true, "row: «إلغاء التنبيه» stays during the minute")
} else { check("\(justSent)", "pending", "row: just sent is pending") }

let afterMinute = L.row(viewer: admin, member: member(), open: open(ago(seconds: 61)), maxReminders: 3, now: now, calendar: kuwait)
if case .pending(let p) = afterMinute { check(p.canRemind, true, "row: after a minute «ذكّره الحين» returns") }

let change = L.row(viewer: admin, member: member(photo: true),
                   open: open(ago(days: 2), sent: 0, reason: "الصورة غير واضحة", hide: true), maxReminders: 3, now: now, calendar: kuwait)
check(change, .pending(L.Pending(isAdd: false, line: "نُبّه قبل يومين · بانتظار صورته الجديدة", reason: "الصورة غير واضحة",
                                 canRemind: true, remindAt: nil, canCancel: true)),
      "row: open change request → waiting for a new photo + its reason")

let ownerTarget = L.row(viewer: admin, member: member(isOwner: true), open: open(ago(days: 4)), maxReminders: 3, now: now, calendar: kuwait)
if case .pending(let p) = ownerTarget {
    check(p.canRemind, false, "row: request on the owner (made by another owner) → admin can't remind")
    check(p.remindAt, nil, "row: … and no timer to bring it back")
    check(p.canCancel, true, "row: … but sees it and can cancel (server allows cancel to staff)")
}
let oldServer = L.row(viewer: admin, member: member(), open: L.Open(notifiedAt: nil, requestedAt: ago(days: 3), remindersSent: nil,
                                                                   reason: "", hidePhoto: false), maxReminders: 3, now: now, calendar: kuwait)
if case .pending(let p) = oldServer {
    check(p.line, "نُبّه قبل 3 أيام · بانتظار صورته", "row: old server (no notified_at/reminders_sent) → requested_at, no «ذُكّر»")
}

// MARK: - النصوص

check(L.notifiedText(days: 0), "نُبّه اليوم", "text: today")
check(L.notifiedText(days: 1), "نُبّه أمس", "text: yesterday")
check(L.notifiedText(days: 2), "نُبّه قبل يومين", "text: two days (dual)")
check(L.notifiedText(days: 5), "نُبّه قبل 5 أيام", "text: 3–10 days")
check(L.notifiedText(days: 12), "نُبّه قبل 12 يوماً", "text: 11+ days")
check(L.remindersText(sent: 0, max: 3), nil, "text: no reminders → nothing")
check(L.remindersText(sent: 2, max: 3), "ذُكّر 2 من 3", "text: «ذُكّر 2 من 3»")
check(L.remindersText(sent: 4, max: 3), "ذُكّر 4", "text: manual reminders past the cap → «ذُكّر 4»")
check(L.remindersText(sent: 1, max: 0), "ذُكّر 1", "text: reminders off → no «من 0»")
check(L.daysSince(ISO8601DateFormatter().date(from: "2026-11-25T20:59:00Z")!, now: now, calendar: kuwait), 1,
      "days: calendar days in Kuwait (23:59 yesterday = 1 day)")
check(L.daysSince(ISO8601DateFormatter().date(from: "2026-11-25T21:01:00Z")!, now: now, calendar: kuwait), 0,
      "days: 00:01 today Kuwait = today")
check(L.shortLine(nil, maxReminders: 3, now: now, calendar: kuwait), "لم يُنبَّه بعد", "list line: not notified yet")
check(L.shortLine(open(ago(days: 6), sent: 3), maxReminders: 3, now: now, calendar: kuwait), "نُبّه قبل 6 أيام · ذُكّر 3 من 3",
      "list line: same short line as the sheet, without «بانتظار»")
check(L.nudgeExplanation(remindDays: 3, maxReminders: 3), "يصله إشعار، ثم تذكير كل 3 أيام حتى 3 مرات", "explain: from the owner's settings")
check(L.nudgeExplanation(remindDays: 1, maxReminders: 1), "يصله إشعار، ثم تذكير كل يوم مرة واحدة", "explain: singulars")
check(L.nudgeExplanation(remindDays: 0, maxReminders: 3), "يصله إشعار يطلب منه إضافة صورته", "explain: reminders off")

// MARK: - قائمة «مسجّلون بلا صورة» (نفس قاعدة السيرفر)

check(L.isListed(member(), viewerId: me, viewerIsOwner: false), true, "list: registered, living, active, male, no photo")
check(L.isListed(member(photo: true), viewerId: me, viewerIsOwner: false), false, "list: has photo → out")
check(L.isListed(member(login: false), viewerId: me, viewerIsOwner: false), false, "list: no account → out")
check(L.isListed(member(deceased: true), viewerId: me, viewerIsOwner: false), false, "list: deceased → out")
check(L.isListed(member(active: false), viewerId: me, viewerIsOwner: false), false, "list: frozen / pending → out")
check(L.isListed(member(female: true), viewerId: me, viewerIsOwner: false), false, "list: woman → out")
check(L.isListed(member(id: me), viewerId: me, viewerIsOwner: false), false, "list: yourself → out")
check(L.isListed(member(isOwner: true), viewerId: me, viewerIsOwner: false), false, "list: owner hidden from admin/monitor")
check(L.isListed(member(isOwner: true), viewerId: me, viewerIsOwner: true), true, "list: owner listed for the other owner")

let a = UUID(), b = UUID(), c = UUID(), d = UUID()
let opens: [UUID: L.Open] = [b: open(ago(days: 2)), c: open(ago(days: 8)), d: open(ago(days: 6, seconds: 86_399))]
check(L.bulkCount(listed: [a, b, c, d], open: opens, now: now), 2, "bulk: skips members notified in the last 7 days (b, d)")
check(L.notifiedRecently(open(ago(days: 7, seconds: 1)), now: now), false, "bulk: 7 days + 1 s → notified again")
check(L.notifiedRecently(nil, now: now), false, "bulk: no request → included")
check(L.bulkButtonTitle(58), "نبّههم كلهم (58)", "bulk: button «نبّههم كلهم (N)»")
check(L.bulkConfirmMessage(58), "يوصل إشعار لـ 58 عضو", "bulk: confirm «يوصل إشعار لـ N عضو»")
check(L.bulkConfirmMessage(1), "يوصل إشعار لعضو واحد", "bulk: confirm for one")
check(L.bulkResult(58), "نُبّه 58 عضو", "bulk: result «نُبّه N عضو»")
check(L.bulkResult(2), "نُبّه عضوين", "bulk: result dual")
check(L.bulkResult(0), "لا أحد يحتاج تنبيهاً الآن", "bulk: result zero")

// MARK: - جانب العضو: مرة لكل إشعار

let rid = UUID()
let first = L.seenToken(requestId: rid, notifiedAtRaw: "2026-11-26T10:00:00+00:00", requestedAtRaw: "2026-11-26T10:00:00+00:00")
let reminder = L.seenToken(requestId: rid, notifiedAtRaw: "2026-11-29T15:00:00+00:00", requestedAtRaw: "2026-11-26T10:00:00+00:00")
check(L.showsRequestBox(token: first, seen: nil, fromTap: false), true, "member: first launch after the request → box")
check(L.showsRequestBox(token: first, seen: first, fromTap: false), false, "member: next launch, same notice → no box (not daily)")
check(L.showsRequestBox(token: reminder, seen: first, fromTap: false), true, "member: a reminder (notified_at changed) → box once more")
check(L.showsRequestBox(token: first, seen: first, fromTap: true), true, "member: tapping the notification always opens it")
check(L.seenToken(requestId: UUID(), notifiedAtRaw: nil, requestedAtRaw: "x") != first, true, "member: a new request → new token")
check(L.seenToken(requestId: rid, notifiedAtRaw: nil, requestedAtRaw: "2026-11-26T10:00:00+00:00").hasSuffix("|2026-11-26T10:00:00+00:00"),
      true, "member: old server → requested_at stands in for notified_at")
check(L.memberBox(hasPhoto: false), .add, "member: no photo → «أضف صورتك الشخصية»")
check(L.memberBox(hasPhoto: true), .change, "member: photo → «يرجى تغيير صورتك الشخصية»")

// «كمّل ملفك بصورة»
check(L.dayKey(now, calendar: kuwait), "2026-11-26", "popup: day key")
check(L.generalPopupAllowed(requestBoxDay: "2026-11-26", today: "2026-11-26"), false, "popup: never the same day as a request box")
check(L.generalPopupAllowed(requestBoxDay: "2026-11-25", today: "2026-11-26"), true, "popup: another day is fine")
check(L.generalPopupDue(lastShown: nil, days: 30, now: now, calendar: kuwait), true, "popup: never shown → due")
check(L.generalPopupDue(lastShown: ago(days: 1), days: 30, now: now, calendar: kuwait), false, "popup: any dismissal snoozes → not next launch")
check(L.generalPopupDue(lastShown: ago(days: 30), days: 30, now: now, calendar: kuwait), true, "popup: back after photo_reminder_days")
check(L.generalPopupDue(lastShown: nil, days: 0, now: now, calendar: kuwait), false, "popup: 0 days = off")

// MARK: - الإعدادات

check(L.remindDaysRange, 0...30, "config: remind days 0–30 (server min/max)")
check(L.maxRemindersRange, 0...10, "config: max reminders 0–10 (server min/max)")
check([L.defaultRemindDays, L.defaultMaxReminders], [3, 3], "config: defaults 3 · 3 (= server)")

L10n.isArabic = false
check(L.notifiedText(days: 5), "Notified 5 days ago", "english: notified line")
check(L.bulkConfirmMessage(3), "3 members will be notified", "english: confirm")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
