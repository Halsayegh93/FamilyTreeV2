// فحص إصلاحات مراجعة الكود + فصل الإدارة عن العضو (الوحدة F4، ٢٠٢٦-١١-٢٦) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/f4-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminFilterKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxFilters.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxView.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminWomenPanel.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminReviewHubPage.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminNoticeLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayBandLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/PhotoNudgeLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift \
//     tests/admin-redesign/F4/filters.swift tests/admin-redesign/F4/main.swift \
//     && /private/tmp/claude-501/f4-logic
//
// ما يُفحص: التصفية (V2 · V3 · V5 · V7 · V39 — filters.swift) · قائمة الصور سابعة (V13) · «الراحلون» يهبط على رقمه (V16)
// · العدد والمعدود (V21/V22/V32) · مفتاح ذاكرة القوائم (V30) · الدمج بعد الجلب (V31) · «ذكّره» الصادق (V15) · بيانات قديمة
// (V11) · «إلغاء التنبيه» (V10) · متوفى بطلب مفتوح (V24) · المشرف بلا حال (S-4) · «إجراءات الإدارة» (القسم A) · السابق/التالي
// أثناء العمل (V27) · «في الشجرة» للمرسوم فقط (V33).
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true

runF4FilterTests()

// MARK: - V13: «مسجّلون بلا صورة» قائمة سابعة

typealias H = AdminReviewHubLogic
check(H.List.allCases.count, 7, "V13: seven review lists")
check(H.List.photos.title, "مسجّلون بلا صورة", "V13: photo list title")
check(H.accounts.last, H.List.photos, "V13: photo list sits in «الحسابات» after the usage lists")
check(H.treeAndData + H.accounts, H.List.allCases, "V13: the two cards still cover every list once")
check(H.List.photos.isUsage, true, "V13: photo list waits for the accounts like the usage lists")
var sixZero = Dictionary(uniqueKeysWithValues: H.List.allCases.map { ($0, 0) })
sixZero[.photos] = nil
check(H.isAllClear(sixZero), false, "V13: not «all clear» before the photo count arrives")
sixZero[.photos] = 4
check(H.isAllClear(sixZero), false, "V13: photo list with members keeps the review row")
sixZero[.photos] = 0
check(H.isAllClear(sixZero), true, "V13: all seven zero → all clear")
check(H.summary([.photos: 4]), "مسجّلون بلا صورة", "V13: summary names the photo list")
check(AdminTodayBandLogic.reviewListsWord(counts: [0, 0, 0, 0, 0, 0, 4])?.state.text, "قائمة واحدة للمراجعة",
      "V13: Today word counts the photo list")
check(AdminTodayBandLogic.reviewListsWord(counts: [0, 0, 0, 0, 0, 0, nil]), nil,
      "V13: no «سليمة» before the photo count")
check(AdminTodayBandLogic.reviewListsWord(counts: [0, 0, 0, 0, 0, 0, 0])?.state.text, "سليمة", "V13: all seven zero → «سليمة»")
let membersCard = AdminMembersLogic.reviewState(
    H.List.allCases.map { AdminMembersLogic.ReviewList($0.title, $0 == .photos ? 4 : 0, forms: $0.forms) }, accountsFailed: false)
check(membersCard, .card(AdminMembersLogic.ReviewCard(first: "4 مسجّلين بلا صورة", second: nil, lists: 1)),
      "V13: «العائلة» card shows the photo list («N قوائم» = 1)")

// MARK: - V30: مفتاح ذاكرة القوائم يشمل فئة كل حساب

let a = UUID(), b = UUID()
let key1 = H.CacheKey(membersVersion: 3, members: 10, accountsLoaded: true, accounts: [a: "active", b: "idle"],
                      daughterSons: [], verified: [])
let key2 = H.CacheKey(membersVersion: 3, members: 10, accountsLoaded: true, accounts: [a: "idle", b: "active"],
                      daughterSons: [], verified: [])
let key3 = H.CacheKey(membersVersion: 3, members: 10, accountsLoaded: true, accounts: [a: "active", b: "idle"],
                      daughterSons: [], verified: [])
check(key1 == key2, false, "V30: two members swapping categories (same count) changes the key")
check(key1 == key3, true, "V30: same members, same categories → same key (no rebuild)")
// بلاغ ٢٠٢٦-١١-٢٧: ابن البنت يدخل «مسجّلون بلا صورة» من قراءة الدخول الإضافية — وصولها يعيد العدّ في «اليوم»
var key4 = key3
key4.outside = [a]
check(key4 == key3, false, "outside logins arriving (daughter's son) change the key → «مسجّلون بلا صورة» recounted")

// MARK: - V16: «الراحلون 502» يهبط حيث يُرى 502 أولاً

check(AdminTodayBandLogic.departedWord(502)?.landing, .stats(.family),
      "V16: «الراحلون 502» lands on «العائلة» (its «متوفون» row shows 502 first)")

// MARK: - V21/V22: العدد والمعدود

typealias M = AdminMembersLogic
check(M.livingUnit(1), "حيّ واحد", "V21: 1 → «حيّ واحد»")
check(M.livingUnit(2), "حيّان", "V21: 2 → «حيّان»")
check(M.livingUnit(5), "أحياء", "V21: 5 → «أحياء»")
check(M.livingUnit(50), "حياً", "V21: 50 → «حياً»")
check(M.livingUnit(100), "حيّ", "V21: 100 → «حيّ»")
let death = H.List.death
check(M.reviewLine(M.ReviewList(death.title, 1, forms: death.forms)), "تاريخ وفاة واحد ناقص", "V22: 1 death date")
check(M.reviewLine(M.ReviewList(death.title, 2, forms: death.forms)), "تاريخا وفاة ناقصان", "V22: 2 death dates")
check(M.reviewLine(M.ReviewList(death.title, 363, forms: death.forms)), "363 تاريخ وفاة ناقصاً", "V22: 363 (ends in 63 → «ناقصاً»)")
check(M.reviewLine(M.ReviewList(death.title, 100, forms: death.forms)), "100 تاريخ وفاة ناقص", "V22: 100")
check(M.reviewLine(M.ReviewList(death.title, 5, forms: death.forms)), "5 تواريخ وفاة ناقصة", "V22: 5 death dates")
check(M.reviewLine(M.ReviewList(death.title, 11, forms: death.forms)), "11 تاريخ وفاة ناقصاً", "V22: 11 death dates")
check(M.reviewLine(M.ReviewList(H.List.problems.title, 1, forms: H.List.problems.forms)), "مشكلة واحدة في الشجرة",
      "V22: 1 tree problem")
check(M.reviewLine(M.ReviewList(H.List.gaps.title, 2, forms: H.List.gaps.forms)), "بيانات ناقصة (2)",
      "V22: list without counted forms → «title (n)» for 1–2")
check(M.reviewLine(M.ReviewList(H.List.gaps.title, 12, forms: H.List.gaps.forms)), "12 بيانات ناقصة",
      "V22: list without counted forms keeps number-first from 3")
check(M.reviewLine(M.ReviewList(H.List.living.title, 41, forms: H.List.living.forms)), "هل ما زالوا أحياء؟ 41",
      "V22: question stays first")

// MARK: - V32: نصوص التذكير والمعدّلات

typealias L = PhotoNudgeLogic
check(L.everyDaysText(1), "كل يوم", "V32: every day")
check(L.everyDaysText(2), "كل يومين", "V32: every 2 days")
check(L.everyDaysText(3), "كل 3 أيام", "V32: every 3 days")
check(L.everyDaysText(11), "كل 11 يوماً", "V32: every 11 days")
check(L.everyDaysText(30), "كل 30 يوماً", "V32: every 30 days")
check(L.timesText(1), "مرة واحدة", "V32: once")
check(L.timesText(2), "حتى مرتين", "V32: up to twice")
check(L.timesText(3), "حتى 3 مرات", "V32: up to 3 times")
check(L.timesText(10), "حتى 10 مرات", "V32: up to 10 times")
check(L.nudgeExplanation(remindDays: 2, maxReminders: 2), "يصله إشعار، ثم تذكير كل يومين حتى مرتين", "V32: explanation 2/2")
check(L.nudgeExplanation(remindDays: 11, maxReminders: 3), "يصله إشعار، ثم تذكير كل 11 يوماً حتى 3 مرات",
      "V32: explanation 11/3")
check(L.afterDaysText(7), "بعد 7 أيام", "V32: stepper «7 أيام»")
check(L.afterDaysText(14), "بعد 14 يوماً", "V32: stepper «14 يوماً»")
check(L.afterDaysText(2), "بعد يومين", "V32: stepper «يومين»")
check(L.afterDaysText(1), "بعد يوم", "V32: stepper «يوم»")
check(L.afterDaysText(100), "بعد 100 يوم", "V32: stepper «100 يوم»")
check(L.remindersLimitText(1), "تذكير واحد", "V32: 1 reminder")
check(L.remindersLimitText(2), "حتى تذكيرين", "V32: 2 reminders")
check(L.remindersLimitText(5), "حتى 5 تذكيرات", "V32: 5 reminders")
check(L.remindersLimitText(10), "حتى 10 تذكيرات", "V32: 10 reminders")

// MARK: - V31: الجلب لا يمحو ما كُتب بعد بدئه

let m1 = UUID(), m2 = UUID(), m3 = UUID()
let current: [UUID: Int] = [m1: 1, m2: 2]
let fetched: [UUID: Int] = [m1: 10, m3: 30]
// m2 كُتب بعد بدء الجلب (نبّه للتو) — m1 وm3 لم يُكتبا
check(L.merged(fetched: fetched, current: current, writtenSince: [m2]), [m1: 10, m2: 2, m3: 30],
      "V31: a nudge written after the fetch started survives")
check(L.merged(fetched: fetched, current: [m1: 1], writtenSince: [m3]), [m1: 10],
      "V31: a cancel written after the fetch started (absent now) stays absent")
check(L.merged(fetched: fetched, current: current, writtenSince: []), fetched,
      "V31: no local writes → the fetch replaces (closed elsewhere = removed)")

// MARK: - V15 / V11: «ذكّره الحين» الصادق والبيانات القديمة

let t0 = Date(timeIntervalSince1970: 1_000)
check(L.reminderLanded(before: t0, after: t0), false, "V15: notified_at unchanged → not sent")
check(L.reminderLanded(before: t0, after: t0.addingTimeInterval(65)), true, "V15: notified_at moved → sent")
check(L.reminderLanded(before: nil, after: t0), true, "V15: first notice → sent")
check(L.reminderLanded(before: t0, after: nil), true, "V15: can't re-read → trust the server's acceptance")
check(L.tooSoonText, "أُرسل له قبل أقل من دقيقة", "V15: the honest text")
check(L.failure(hint: "bad_reason", missingFunction: false, nudging: true), .stale, "V11: bad_reason while nudging = stale data")
check(L.staleText, "أضاف صورته — حدّثنا البيانات", "V11: stale text")
check(L.failure(hint: "bad_reason", missingFunction: false, nudging: false), .message("يرجى كتابة السبب (حتى ٢٠٠ حرف)."),
      "V11: bad_reason on the reason box stays «write the reason»")
check(L.failure(hint: nil, missingFunction: true, nudging: true), .message("هذه الميزة تحتاج تحديث السيرفر."),
      "V11: a missing function still says «server update»")
check(L.failure(hint: "photo_pending", missingFunction: false, nudging: true),
      .message("أرسل صورته وهي بانتظار الموافقة — راجعها من «الوارد»."), "V9 (app): photo awaiting approval")
check(L.failure(hint: "account_frozen", missingFunction: false, nudging: true),
      .message("حسابه موقوف أو غير مفعّل — لا يصله التنبيه."), "V12 (app): frozen account")

// MARK: - V10 / V24 / S-4: صفّ الصورة

let me = UUID(), other = UUID()
let admin = L.Viewer(id: me, canEdit: true, isOwner: false, canBulk: true)
let owner = L.Viewer(id: me, canEdit: true, isOwner: true, canBulk: true)
let supervisor = L.Viewer(id: me, canEdit: false, isOwner: false, canBulk: false, canReadStatus: false)
func member(id: UUID = other, deceased: Bool = false, photo: Bool = false, isOwner: Bool = false) -> L.Member {
    L.Member(id: id, isDeceased: deceased, hasLogin: true, hasPhoto: photo, isFemale: false, isOwner: isOwner, isActive: true)
}
let now = Date(timeIntervalSince1970: 10_000_000)
let openReq = L.Open(notifiedAt: now.addingTimeInterval(-3_600), requestedAt: nil, remindersSent: 0, reason: "", hidePhoto: false)
func cancelShown(_ r: L.Row) -> Bool? { if case .pending(let p) = r { return p.canCancel } else { return nil } }
func remindShown(_ r: L.Row) -> Bool? { if case .pending(let p) = r { return p.canRemind } else { return nil } }
check(cancelShown(L.row(viewer: admin, member: member(id: me), open: openReq, maxReminders: 3, now: now)), false,
      "V10: no «إلغاء التنبيه» on your own sheet")
check(cancelShown(L.row(viewer: owner, member: member(id: me, isOwner: true), open: openReq, maxReminders: 3, now: now)), false,
      "V10: … the owner on his own sheet too")
check(cancelShown(L.row(viewer: admin, member: member(isOwner: true), open: openReq, maxReminders: 3, now: now)), true,
      "V10: the owner's sheet keeps cancel for staff (as before — the spec hides it on your own sheet only)")
check(cancelShown(L.row(viewer: admin, member: member(), open: openReq, maxReminders: 3, now: now)), true,
      "V10: cancel stays for another member")
let deceasedRow = L.row(viewer: admin, member: member(deceased: true), open: openReq, maxReminders: 3, now: now)
check(cancelShown(deceasedRow), true, "V24 (app): deceased member's open request can still be cancelled")
check(remindShown(deceasedRow), false, "V24 (app): … but never reminded")
check(L.row(viewer: admin, member: member(deceased: true), open: nil, maxReminders: 3, now: now), .hidden,
      "V24 (app): deceased without a request → no row")
check(L.listLine(openReq, known: true, viewer: supervisor, maxReminders: 3, now: now), "—",
      "S-4: a role that can't read the requests sees «—», not «لم يُنبَّه بعد»")
check(L.listLine(nil, known: true, viewer: admin, maxReminders: 3, now: now), "لم يُنبَّه بعد", "S-4: staff still sees the status")
check(L.listLine(nil, known: false, viewer: admin, maxReminders: 3, now: now), "—", "S-4: before the requests arrive «—»")

// MARK: - القسم A: «إجراءات الإدارة» منفصلة

typealias S = AdminMemberSheetLogic
let allCommands = S.AccountCommands(suspend: true, ban: true, delete: true)
let card = S.adminCard(isSelf: false, living: true, photo: true, register: true, devices: true, commands: allCommands)
check(card?.items, [.photo, .register, .devices, .suspend, .ban, .delete], "A: every admin command, delete last")
check(S.adminCard(isSelf: true, living: true, photo: true, register: true, devices: true, commands: allCommands), nil,
      "A: own sheet → no «إجراءات الإدارة» card at all")
check(S.adminCard(isSelf: false, living: true, photo: false, register: false, devices: false,
                  commands: S.AccountCommands(suspend: false, ban: false, delete: false)), nil,
      "A: nothing to do → no empty card")
check(S.adminCard(isSelf: false, living: false, photo: true, register: true, devices: true, commands: allCommands)?.items,
      [.photo, .delete], "A: deceased → the photo request (to cancel) and delete only")

// MARK: - V27: لا «التالي» أثناء العمل

check(S.canStep(next: true, position: 0, count: 3, busy: true), false, "V27: next disabled while busy")
check(S.canStep(next: false, position: 2, count: 3, busy: true), false, "V27: previous disabled while busy")
check(S.canStep(next: true, position: 0, count: 3, busy: false), true, "V27: next enabled when idle")

// MARK: - V33: «في الشجرة» لمن يُرسم من الرأس فقط

let root = UUID(), son = UUID(), grandson = UUID(), orphan = UUID(), hiddenSon = UUID(), underHidden = UUID()
let fathers: [UUID: UUID] = [son: root, grandson: son, hiddenSon: root, underHidden: hiddenSon]
let hidden: Set<UUID> = [hiddenSon]
func reach(_ id: UUID, root r: UUID? = root) -> Bool {
    S.reachable(id, root: r, father: { fathers[$0] }, drawable: { !hidden.contains($0) })
}
check(reach(grandson), true, "V33: grandson of the root → shown")
check(reach(root), true, "V33: the root itself → shown")
check(reach(orphan), false, "V33: orphan (no father, not the root) → hidden")
check(reach(underHidden), false, "V33: under a hidden ancestor → hidden")
check(reach(son, root: nil), false, "V33: no root → hidden")
let loopA = UUID(), loopB = UUID()
check(S.reachable(loopA, root: root, father: { $0 == loopA ? loopB : loopA }, drawable: { _ in true }), false,
      "V33: a father loop never hangs")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
