// فحص منطق مربّعات المجموعات (Views/Features/Admin/AdminGroupTiles.swift، طلب المالك ٢٠٢٦-١١-٢٨) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/gt1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminGroupTiles.swift tests/admin-redesign/GT1/main.swift && /tmp/gt1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminGroupTilesLogic

check(L.columns, 3, "three per row")

// MARK: «التطبيق والنظام» — الترتيب المعتمد
check(L.appTiles(seesSms: true, seesDevices: true),
      [.visible, .rules, .lists, .operations, .sms, .devices, .errors, .system], "owner: eight tiles in the approved order")
check(L.appTiles(seesSms: false, seesDevices: true).contains(.sms), false, "no team.sms → no sign-in messages tile")
check(L.appTiles(seesSms: true, seesDevices: false).contains(.devices), false, "no team.devices → no devices tile")
check(L.appTiles(seesSms: false, seesDevices: false).count, 6, "without both: six tiles")
check(AdminAppTile.allCases.filter(\.isGroupPage), [.visible, .rules, .lists, .operations, .system],
      "group pages (switches inside); sms/devices/errors open their existing page")

// MARK: «الفريق والصلاحيات»
check(L.teamTiles(seesTeam: true, isOwner: true, seesRegistration: true), [.team, .memberAccess, .registration],
      "owner: three tiles")
check(L.teamTiles(seesTeam: true, isOwner: false, seesRegistration: false), [.team], "admin (read): admin team only")
check(L.teamTiles(seesTeam: false, isOwner: false, seesRegistration: false), [], "monitor: nothing (empty state)")

// MARK: القارئ الصوتي «الاسم، الحال»
check(L.spoken(title: "التشغيل", number: nil, status: "يعمل للجميع ✓"), "التشغيل، يعمل للجميع ✓", "title, status")
check(L.spoken(title: "الراحلون", number: "502", status: " "), "الراحلون، 502", "blank status dropped")
check(L.spoken(title: "القوائم", number: nil, status: nil), "القوائم", "title alone")

if failures == 0 { print("ALL PASS") } else { print("\(failures) FAILURES"); exit(1) }
