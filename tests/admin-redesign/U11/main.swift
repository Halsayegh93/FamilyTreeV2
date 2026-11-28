// فحص منطق جذر «العائلة» (الوحدة U11) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u11-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift tests/admin-redesign/U11/main.swift && /tmp/u11-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias M = AdminMembersLogic

// MARK: - الفلتران (T2: «لهم حساب» = حساب دخول فقط)

check(M.matches(deceased: false, hasLogin: true, account: .with, life: .alive), true, "living with login = «لهم حساب · الأحياء»")
check(M.matches(deceased: false, hasLogin: false, account: .with, life: .all), false,
      "T2: frozen member without a login is NOT «لهم حساب»")
check(M.matches(deceased: false, hasLogin: false, account: .without, life: .all), true,
      "T2: frozen member without a login is «بلا حساب»")
check(M.matches(deceased: true, hasLogin: true, account: .with, life: .alive), false, "deceased fails «الأحياء»")
check(M.matches(deceased: true, hasLogin: false, account: .without, life: .deceased), true, "deceased without login")
for d in [false, true] {
    for h in [false, true] {
        let w = M.matches(deceased: d, hasLogin: h, account: .with, life: .all)
        let wo = M.matches(deceased: d, hasLogin: h, account: .without, life: .all)
        check(w != wo, true, "every member is in exactly one of «لهم حساب»/«بلا حساب» (dead=\(d) login=\(h))")
    }
}

// mock 5: ٢٬٣٦٢ = ١٢٣ لهم حساب (أحياء) + ٢٬٢٣٩ بلا حساب
var t = M.Tally()
for _ in 0..<123 { t.add(deceased: false, hasLogin: true) }
for _ in 0..<1_839 { t.add(deceased: false, hasLogin: false) }
for _ in 0..<400 { t.add(deceased: true, hasLogin: false) }
check(t.total, 2_362, "tally total")
check(t.count(account: .all, life: .all), 2_362, "«الكل» = everyone")
check(t.count(account: .with, life: .all), 123, "«لهم حساب» = 123 (= family registered men)")
check(t.count(account: .without, life: .all), 2_239, "«بلا حساب» = 2,239")
check(t.count(account: .with, life: .all) + t.count(account: .without, life: .all), t.total, "with + without = all")
check(t.count(account: .with, life: .alive), 123, "«لهم حساب · الأحياء» = 123 (mock 4)")
check(t.count(account: .with, life: .deceased), 0, "«لهم حساب · المتوفون» = 0 (grey, still selectable)")
check(t.count(account: .all, life: .alive) + t.count(account: .all, life: .deceased), t.total, "alive + deceased = all")
check(t.shown(account: .with, life: .all, accountsReady: false), nil, "account counts are «—» before the accounts load")
check(t.shown(account: .all, life: .alive, accountsReady: false), 1_962, "life counts show before the accounts load")

// MARK: - الروابط القديمة: كل قيمة فلتر أو قائمة تُدفع

check(M.isDefault(chip: "all", sub: "all", womenOutside: false), true, "defaults → the stored landing applies")
check(M.isDefault(chip: "registered", sub: "all", womenOutside: false), false, "explicit chip wins over a landing")
check(M.isDefault(chip: "all", sub: "all", womenOutside: true), false, "explicit womenOutside wins over a landing")

check(M.opening(chip: "all", sub: "all", womenOutside: false), M.Opening(), "«الكل» = no filters")
check(M.opening(chip: "registered", sub: "all", womenOutside: false), M.Opening(account: .with, life: .alive),
      "registered → «لهم حساب · الأحياء»")
check(M.opening(chip: "treeOnly", sub: "all", womenOutside: false), M.Opening(account: .without, life: .alive),
      "treeOnly → «بلا حساب · الأحياء»")
check(M.opening(chip: "deceased", sub: "all", womenOutside: false), M.Opening(life: .deceased), "deceased → «المتوفون»")
check(M.opening(chip: "problems", sub: "all", womenOutside: false).push, .review(.problems), "problems → review list pushed")
check(M.opening(chip: "verifyLiving", sub: "all", womenOutside: false).push, .review(.living), "verifyLiving → «هل ما زالوا أحياء؟»")
check(M.opening(chip: "gaps", sub: "noBirth", womenOutside: false).push, .review(.gaps), "gaps → «بيانات ناقصة»")
check(M.opening(chip: "treeOnly", sub: "notSignedIn", womenOutside: false),
      M.Opening(account: .without, life: .alive, push: .review(.notOpened)),
      "AdminUsageDevicesKit «ما دخلوا أبداً» → «لم يفتحوا التطبيق بعد» over «بلا حساب»")
check(M.opening(chip: "registered", sub: "noPush", womenOutside: false), M.Opening(sub: "noPush"),
      "AdminUsageDevicesKit «دخلوا بدون جهاز» → removable «لا تصله الإشعارات» filter alone")
check(M.opening(chip: "registered", sub: "inactive", womenOutside: false).push, .review(.inactive), "inactive → «لم يدخلوا منذ 21 يوماً»")
check(M.opening(chip: "deceased", sub: "deathIncomplete", womenOutside: false).push, .deathDates,
      "deathIncomplete → the death-dates page (its one home)")
check(M.opening(chip: "all", sub: "newThisWeek", womenOutside: false), M.Opening(sub: "newThisWeek"), "newThisWeek → filter")
check(M.opening(chip: "unknown", sub: "x", womenOutside: false), M.Opening(), "unknown chip → root, no filter")
check(M.opening(chip: "registered", sub: "all", womenOutside: true), M.Opening(people: [.outside]),
      "womenOutside → «العائلة» on {خارج العائلة} (F5 — no page pushed)")

// MARK: - الهبوط

let branch = UUID()
check(M.opening(landing: AdminMembersLanding(account: .with, life: .alive)), M.Opening(account: .with, life: .alive),
      "landing «لهم حساب + الأحياء»")
check(M.opening(landing: AdminMembersLanding(account: .all, life: .all)), M.Opening(), "landing from a total = «الكل»")
check(M.opening(landing: AdminMembersLanding(branch: branch)).branch, branch, "landing keeps the branch")
check(M.opening(landing: AdminMembersLanding(review: .problems)).push, .review(.problems), "landing review pushes its list")
check(M.opening(landing: AdminMembersLanding(review: .death)).push, .deathDates, "landing death → death-dates page")
let stored = AdminMembersLanding(account: .with, life: .alive)
check(M.opening(landing: stored.overridden(by: AdminMembersLanding(life: .deceased))),
      M.Opening(account: .with, life: .deceased), "explicit landing field wins over the stored one")

// MARK: - سطر «آخر دخول»

L10n.isArabic = true
check(M.lastSeen(days: 0), "آخر دخول اليوم", "today")
check(M.lastSeen(days: 1), "آخر دخول أمس", "yesterday")
check(M.lastSeen(days: 2), "آخر دخول قبل يومين", "two days")
check(M.lastSeen(days: 3), "آخر دخول قبل 3 أيام", "3 days (mock 4)")
check(M.lastSeen(days: 14), "آخر دخول قبل 14 يوماً", "14 days")
check(M.lastSeen(days: 31), nil, "older → the caller writes the date")

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuwait")!
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 0, minute: 30))!
let lateYesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 23, minute: 50))!
check(M.daysSince(lateYesterday, now: now, calendar: cal), 1, "calendar days, not 24h blocks")
check(M.daysSince(now.addingTimeInterval(3_600), now: now, calendar: cal), 0, "a future stamp is today")

// MARK: - الترتيب في سطر الملخّص

check(M.Order.make(filtered: false, searching: false), .alphabetical, "no filter, no search → A–Z (no branch sections, owner 2026-11-27)")
check(M.Order.make(filtered: true, searching: false), .alphabetical, "filters → A–Z (mock 4 «أبجدياً»)")
check(M.Order.make(filtered: true, searching: true), .relevance, "search → best match")
check(M.Order.alphabetical.title, "أبجدياً", "order word")

// MARK: - «انضمّ N هذا الأسبوع» (المالك ٢٠٢٦-١١-٢٧): الحبّة والقائمة بقاعدة واحدة

check(M.opening(landing: AdminMembersLanding.joinedThisWeek).sub, "newThisWeek", "the joined landing carries its list")
check(M.opening(landing: AdminMembersLanding.joinedThisWeek).people, [.men], "the joined landing is the men list")
check(AdminMembersLanding(sub: "newThisWeek").overridden(by: AdminMembersLanding(account: .with)).sub, "newThisWeek",
      "explicit fields keep the stored list")
let weekAgo = Date(timeIntervalSince1970: 1_000_000)
let fresh = weekAgo.addingTimeInterval(3_600), old = weekAgo.addingTimeInterval(-3_600)
check(M.joinedThisWeek(deceased: false, countable: true, daughterSon: false, created: fresh, weekAgo: weekAgo), true,
      "a living tree man added this week counts")
check(M.joinedThisWeek(deceased: false, countable: true, daughterSon: true, created: fresh, weekAgo: weekAgo), false,
      "a daughter's son is not in the men list → not in the pill either (pill = list)")
check(M.joinedThisWeek(deceased: true, countable: true, daughterSon: false, created: fresh, weekAgo: weekAgo), false,
      "deceased → no")
check(M.joinedThisWeek(deceased: false, countable: false, daughterSon: false, created: fresh, weekAgo: weekAgo), false,
      "not countable (woman account, frozen, hidden, no name) → no")
check(M.joinedThisWeek(deceased: false, countable: true, daughterSon: false, created: old, weekAgo: weekAgo), false,
      "older than a week → no")
check(M.joinedThisWeek(deceased: false, countable: true, daughterSon: false, created: nil, weekAgo: weekAgo), false,
      "no date → no")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
