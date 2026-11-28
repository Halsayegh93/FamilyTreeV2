// فحص منطق «طلبات رمز الدخول» و«رسائل رمز الدخول» (الوحدة S1، طلبا المالك ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/s1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminSmsLogic.swift tests/admin-redesign/S1/main.swift \
//     && /private/tmp/claude-501/s1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias S = SmsSuspiciousLogic
typealias P = SmsPageLogic

// MARK: - ١) معنى «مريبة» بكلام بسيط

check(S.meaningLine, "طلب هذا الرقم رمز الدخول 5 مرات أو أكثر خلال ساعة", "row meaning line is the owner's plain sentence")
check(S.pageMeaning.contains("5 مرات أو أكثر خلال ساعة"), true, "page-top line says the same rule")

// MARK: - ٢) ربط التنبيه برقمه (نصّ الإشعار ينتهي بالرقم: كاملاً للمالك، مخفياً للمدير)

let ownerBody = "رقم غير مسجّل طلب رمز الدخول 5 مرات خلال ساعة — +965 99887766"
let adminBody = "فلان طلب رمز الدخول 6 مرات خلال ساعة — +965 9988••66"
let lockBody = "انطلب رمز الدخول 6 مرات خلال 10 دقائق لرقم واحد، فتقفل 60 دقيقة بلا رسائل. الرقم في «طلبات رمز الدخول»."

check(S.key(noticeBody: ownerBody), S.PhoneKey(first4: "9988", last2: "66", full: "99887766"), "full number at the end of the owner's notice")
check(S.key(noticeBody: adminBody), S.PhoneKey(first4: "9988", last2: "66", full: nil), "masked number at the end of an admin's notice")
check(S.key(noticeBody: lockBody), nil, "lock notice carries no number")
check(S.key(noticeBody: ownerBody + "  "), S.PhoneKey(first4: "9988", last2: "66", full: "99887766"), "trailing spaces are ignored")

check(S.key(phoneE164: "+96599887766", shown: "+965 99887766"), S.PhoneKey(first4: "9988", last2: "66", full: "99887766"),
      "owner row: key from phone_e164")
check(S.key(phoneE164: nil, shown: "+965 9988••66"), S.PhoneKey(first4: "9988", last2: "66", full: nil),
      "admin row: key from the masked number")
check(S.key(phoneE164: nil, shown: "—"), nil, "no number → no key")

let full = S.PhoneKey(first4: "9988", last2: "66", full: "99887766")
let masked = S.PhoneKey(first4: "9988", last2: "66", full: nil)
let otherFull = S.PhoneKey(first4: "9988", last2: "66", full: "99881166")
check(S.sameNumber(full, full), true, "same full number matches")
check(S.sameNumber(full, otherFull), false, "two full numbers with the same mask do not match")
check(S.sameNumber(full, masked), true, "full matches its own mask")

let n1 = UUID(), n2 = UUID(), n3 = UUID(), n4 = UUID(), n5 = UUID()
let notices = [
    S.Notice(id: n1, body: ownerBody, read: false),
    S.Notice(id: n2, body: ownerBody, read: true),                                   // قُرئ من قبل
    S.Notice(id: n3, body: lockBody, read: false),                                   // بلا رقم
    S.Notice(id: n4, body: "… — +965 55554444", read: false),                         // رقم آخر
    S.Notice(id: n5, body: "فلان طلب رمز الدخول 5 مرات خلال ساعة — +965 99887766", read: false)
]
check(S.relatedUnreadIds(notices, phoneE164: "+96599887766", shown: "+965 99887766"), [n1, n5],
      "«تم الاطلاع» on a row marks only that number's unread notices")
check(S.relatedUnreadIds(notices, phoneE164: nil, shown: "—"), [], "a row without a number marks nothing")
check(S.unreadIds(notices), [n1, n3, n4, n5], "«تم الاطلاع على الكل» marks every unread notice, the lock one too")

check(S.unreadWord(1), "تنبيه جديد", "1 unread")
check(S.unreadWord(2), "تنبيهان جديدان", "2 unread")
check(S.unreadWord(3), "3 تنبيهات جديدة", "3 unread")
check(S.unreadWord(11), "11 تنبيهاً جديداً", "11 unread")
check(S.unreadWord(100), "100 تنبيه جديد", "100 unread")

// MARK: - ٣) لمن الرقم؟ (`find_profiles_by_phone` + اسم الشجرة، وحساب الدخول من `last_sign_in_at`)

let a = UUID(), b = UUID()
check(S.owner(matches: [], attemptProfile: nil, hasAccount: false), .nobody, "no profile, no account → not anyone's in the family")
check(S.owner(matches: [], attemptProfile: nil, hasAccount: true), .namelessAccount,
      "an account without a profile → nameless account")
check(S.owner(matches: [S.Match(id: a, role: "member", status: "pending", name: nil)], attemptProfile: nil, hasAccount: true),
      .namelessAccount, "a pending profile without a name → nameless account")
check(S.owner(matches: [S.Match(id: a, role: "member", status: "active", name: "حسن محمد علي")], attemptProfile: nil, hasAccount: true),
      .member(name: "حسن محمد علي", standing: .registered, others: 0), "named member who signed in → registered member")
check(S.owner(matches: [S.Match(id: a, role: "member", status: "active", name: "حسن محمد")], attemptProfile: nil, hasAccount: false),
      .member(name: "حسن محمد", standing: .noAccount, others: 0), "named tree member who never signed in → no account")
check(S.owner(matches: [S.Match(id: a, role: "member", status: "frozen", name: "حسن")], attemptProfile: nil, hasAccount: true),
      .member(name: "حسن", standing: .frozen, others: 0), "frozen profile → stopped account")
check(S.owner(matches: [S.Match(id: a, role: "pending", status: "pending", name: "حسن")], attemptProfile: nil, hasAccount: true),
      .member(name: "حسن", standing: .pendingJoin, others: 0), "pending role with a name → join request under review")
check(S.owner(matches: [S.Match(id: a, role: "member", status: "active", name: "  "),
                        S.Match(id: b, role: "member", status: "active", name: "سلمان")], attemptProfile: nil, hasAccount: true),
      .member(name: "سلمان", standing: .registered, others: 1), "the named profile wins, the other is counted")
check(S.owner(matches: [], attemptProfile: S.Match(id: a, role: nil, status: "active", name: "حسن"), hasAccount: true),
      .member(name: "حسن", standing: .registered, others: 0), "no phone match → the attempt's own profile")
check(S.owner(matches: [S.Match(id: b, role: "member", status: "active", name: "سلمان")],
              attemptProfile: S.Match(id: b, role: nil, status: "active", name: "سلمان"), hasAccount: true),
      .member(name: "سلمان", standing: .registered, others: 0), "the attempt profile is not counted twice")

check(S.standingText(.registered), "عضو مسجّل", "official word: registered member")
check(S.standingText(.noAccount), "بلا حساب", "no account")
check(S.standingText(.pendingJoin), "طلب انضمام قيد المراجعة", "official word: join request")
check(S.standingText(.frozen), "حساب موقوف", "official word: stopped account")
check(S.ownerTitle(.nobody), "ليس رقماً لأحد في العائلة", "nobody title")
check(S.ownerTitle(.namelessAccount), "حساب بلا اسم — لم يكمل التسجيل", "nameless title")
check(S.ownerDetail(.member(name: "حسن", standing: .registered, others: 0)), "عضو مسجّل", "member detail")
check(S.ownerDetail(.member(name: "حسن", standing: .registered, others: 1)), "عضو مسجّل · وعضو آخر بنفس الرقم", "one more")
check(S.ownerDetail(.member(name: "حسن", standing: .noAccount, others: 3)), "بلا حساب · و3 أعضاء آخرون بنفس الرقم", "three more")
check(S.ownerDetail(.nobody), nil, "nobody: no detail line")

check(S.isOwnersNumber(matches: [S.Match(id: a, role: "owner", status: "active", name: "حسن")]), true, "an owner's number")
check(S.isOwnersNumber(matches: [S.Match(id: a, role: "admin", status: "active", name: "حسن")]), false, "an admin is not an owner")

// MARK: - ٤) الأزرار الظاهرة

check(S.actions(phoneE164: "+96599887766", canCall: true, canBan: true, isBanned: false, ownersNumber: false, relatedUnread: 2),
      S.Actions(call: true, ban: .available, seen: .button(count: 2)), "owner row with unread notices: all three buttons")
check(S.actions(phoneE164: "+96599887766", canCall: true, canBan: true, isBanned: false, ownersNumber: false, relatedUnread: 0),
      S.Actions(call: true, ban: .available, seen: .done), "nothing unread → «تم الاطلاع ✓» state, no button")
check(S.actions(phoneE164: "+96599887766", canCall: true, canBan: false, isBanned: false, ownersNumber: false, relatedUnread: 1).ban,
      .hidden, "no canManageBannedPhones → no block button")
check(S.actions(phoneE164: "+96599887766", canCall: true, canBan: true, isBanned: true, ownersNumber: false, relatedUnread: 1).ban,
      .alreadyBanned, "already blocked → says so, no second block")
check(S.actions(phoneE164: "+96599887766", canCall: true, canBan: true, isBanned: false, ownersNumber: true, relatedUnread: 1).ban,
      .hidden, "an owner's number is never offered for blocking")
check(S.actions(phoneE164: nil, canCall: true, canBan: true, isBanned: false, ownersNumber: false, relatedUnread: 1),
      S.Actions(call: false, ban: .hidden, seen: .button(count: 1)), "masked number: no call, no block — only «تم الاطلاع»")
check(S.actions(phoneE164: "+96599887766", canCall: false, canBan: true, isBanned: false, ownersNumber: false, relatedUnread: 1).call,
      false, "no tel URL → no call")

// MARK: - ٥) أعلى الصفحة

check(S.banner(unread: 0, suspiciousInPeriod: 0), .none, "nothing suspicious → no banner")
check(S.banner(unread: 3, suspiciousInPeriod: 1), .unread(3), "unread notices → banner with «تم الاطلاع على الكل»")
check(S.banner(unread: 2, suspiciousInPeriod: 0), .unread(2), "unread lock notices alone still show the banner")
check(S.banner(unread: 0, suspiciousInPeriod: 2), .quiet(suspicious: 2), "all seen, numbers still flagged → quiet banner")

// MARK: - ٦) تأكيد المنع يقول ما سيحدث

let plain = S.banMessage(phone: "+965 99887766", owner: .nobody)
check(plain.contains("لن يستطيع صاحب الرقم +965 99887766 التسجيل أو الدخول إلى التطبيق"), true, "says what blocking does")
check(plain.contains("«التسجيل والمنع»"), true, "says where to undo it")
let member = S.banMessage(phone: "+965 99887766", owner: .member(name: "حسن محمد", standing: .registered, others: 0))
check(member.hasPrefix("هذا رقم حسن محمد"), true, "names the member first")
check(member.contains("يُوقَف حسابه"), true, "warns the member's account is stopped too (freeze_member_on_ban)")
check(S.banReason, "محاولات دخول مريبة", "the reason saved with the block")

// MARK: - ٧) صفحة «رسائل رمز الدخول» v2: الأقسام بترتيبها

check(P.sections(canView: false, hasOverview: true), [], "not the owner → no sections (locked card)")
check(P.sections(canView: true, hasOverview: true),
      [.sending, .trend, .recent, .settings, .protection, .alerts, .tools, .attempts, .how],
      "owner: numbers · chart · recent · settings · protection · alerts · tools · requests · how it works")
check(P.sections(canView: true, hasOverview: false),
      [.sending, .settings, .protection, .alerts, .tools, .attempts, .how],
      "overview failed: the chart and recent sends wait, the rest stays")

check(P.tools(isOwner: true), [.testSend, .validate], "owner tools: test message + check a number")
check(P.tools(isOwner: false), [.validate], "the test message is owner-only")

check(P.settingsEditable(canManageSettings: true, limitsEditable: true), true, "owner + server columns → edit")
check(P.settingsEditable(canManageSettings: true, limitsEditable: false), false, "older server → read only")
check(P.settingsEditable(canManageSettings: true, limitsEditable: nil), false, "before the overview → read only")
check(P.settingsEditable(canManageSettings: false, limitsEditable: true), false, "not the owner → read only")

check(P.gaugeProgress(balance: nil), nil, "no reading → empty ring")
check(P.gaugeProgress(balance: 17), 0.17, "17 points of 100")
check(P.gaugeProgress(balance: 640), 1.0, "above 100 → full ring")
check(P.gaugeProgress(balance: -3), 0.0, "never below zero")

check(P.attemptsValue(unread: 0), nil, "no unread suspicious → no pill on the requests row")
check(P.attemptsValue(unread: 2), "2 جديدة", "unread suspicious → «2 جديدة»")

// MARK: - الإنجليزية

L10n.isArabic = false
check(S.meaningLine, "This number asked for a sign-in code 5 or more times within an hour", "English meaning line")
check(S.unreadWord(1), "1 new alert", "English unread 1")
check(S.unreadWord(4), "4 new alerts", "English unread 4")
check(S.standingText(.registered), "Registered member", "English registered")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
