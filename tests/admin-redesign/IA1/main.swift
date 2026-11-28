// فحص ترتيب أقسام الإدارة (ترتيب المالك ٢٠٢٦-١١-٢٨ `admin-ia`/`admin-sections` — AdminCatalogLogic.swift) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/ia1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCatalogLogic.swift tests/admin-redesign/IA1/main.swift && /tmp/ia1-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias Tool = AdminCatalogTool
typealias G = AdminAreaGroup

// MARK: الأسماء — ستة أقسام بألوانها، اسمان جديدان
check(AdminAreaNames.title("team"), "الفريق والنظام", "merged 2026-11-28: «الفريق والصلاحيات» + «التطبيق والنظام» → «الفريق والنظام»")
check(AdminAreaNames.title("app"), "الفريق والنظام", "app pages carry the merged name (back titles)")
check(AdminAreaNames.title("inbox"), "الوارد", "«الوارد» unchanged")
check(AdminAreaNames.title("family"), "العائلة", "«العائلة» unchanged")
check(AdminAreaNames.title("occasions"), "المناسبات والإعلانات", "«المناسبات والإعلانات» unchanged")
check(AdminAreaNames.title("metrics"), "الإحصاءات", "«الإحصاءات» unchanged")

// MARK: الانتقالات الأربع
check(Tool.accessUsage.areaKey, "metrics", "«الاستخدام» → «الإحصاءات»")
check(Tool.accessSms.areaKey, "app", "«رسائل رمز الدخول (KWT SMS)» → «التطبيق والنظام»")
check(Tool.accessDevices.areaKey, "app", "«الأجهزة والإشعارات» → «التطبيق والنظام»")
check(Tool.accessRegistration.areaKey, "team", "«التسجيل والمنع» stays in «الفريق والصلاحيات»")
check(Tool.teamMembers.areaKey, "team", "«فريق الإدارة» stays in «الفريق والصلاحيات»")
check(Tool.allCases.filter { $0.areaKey == "team" }, [.teamMembers, .accessRegistration], "team: people and permissions only")
// البيوت لم تتغيّر — البحث والروابط تفتح الصفحة نفسها في بيتها الجديد
check(Tool.accessSms.home, .sms, "SMS opens the same page")
check(Tool.accessDevices.home, .devices, "devices opens the same page")
check(Tool.accessUsage.home, .usage, "usage opens the same page")

// MARK: البحث: الاسم القديم يجد البيت الجديد
func homes(_ q: String) -> Set<AdminCatalogHome> { Set(AdminCatalogLogic.tools(matching: q).map(\.home)) }
check(homes("الفريق والأمان").contains(.moderators), true, "old «الفريق والأمان» finds the team")
check(homes("التطبيق والنظام").contains(.appRoot), true, "«التطبيق والنظام» finds the app root")
check(homes("kwt"), [.sms], "«kwt» still finds the SMS page")
check(homes("الفريق والصلاحيات").contains(.moderators), true, "old «الفريق والصلاحيات» finds the team")
check(homes("الفريق والنظام").contains(.moderators), true, "new «الفريق والنظام» finds the team")
check(homes("الفريق والنظام").contains(.appRoot), true, "new «الفريق والنظام» finds the system root")
check(homes("التطبيق").contains(.appRoot), true, "old «التطبيق» finds the system root")

// MARK: الدمج — الأقسام في القوائم لكل دور (٢٠٢٦-١١-٢٨)
let all6 = ["inbox", "family", "occasions", "metrics", "team", "app"]
check(AdminAreaLayout.listedAreas(visible: all6), ["inbox", "family", "occasions", "metrics", "team"], "owner: five sections")
check(AdminAreaLayout.listedAreas(visible: ["inbox", "family", "occasions", "metrics", "team"]),
      ["inbox", "family", "occasions", "metrics", "team"], "admin: five (team read-only)")
check(AdminAreaLayout.listedAreas(visible: ["inbox", "family", "occasions", "metrics"]),
      ["inbox", "family", "occasions", "metrics"], "monitor: no merged tile")
check(AdminAreaLayout.listedAreas(visible: ["inbox", "occasions"]), ["inbox", "occasions"], "supervisor: no merged tile")
check(AdminAreaLayout.listedAreas(visible: ["inbox", "app"]), ["inbox", "team"], "app alone → merged tile shows")
check(AdminAreaLayout.mergedGroups(seesTeam: true, seesApp: true), [.team, .system], "owner: «الفريق» then «النظام»")
check(AdminAreaLayout.mergedGroups(seesTeam: true, seesApp: false), [.team], "admin: «الفريق» only, «النظام» hidden")
check(AdminAreaLayout.mergedGroups(seesTeam: false, seesApp: false), [], "monitor/supervisor: nothing")
check(AdminAreaLayout.pageArea("app"), "team", "old app links open the merged page")
check(AdminAreaLayout.pageArea("metrics"), "metrics", "«الإحصاءات» stays its own section")

// MARK: ترتيب المجموعات داخل كل قسم
check(AdminAreaLayout.groups("family"), [.review, .members], "العائلة: يحتاج مراجعتك ← الأعضاء")
check(AdminAreaLayout.groups("occasions"), [.upcoming, .grief, .joys, .published],
      "المناسبات: القادم ← عزاء وذكرى ← أفراح العائلة ← المنشور")
check(AdminAreaLayout.groups("metrics"), [.family, .inApp, .approvals, .details],
      "الإحصاءات: العائلة ← في التطبيق ← الموافقات ← التفاصيل")
check(AdminAreaLayout.groups("team"), [.team, .people], "الفريق والصلاحيات: الفريق ← الأعضاء")
check(AdminAreaLayout.groups("app"), [.visible, .lists, .operations, .system],
      "التطبيق والنظام: الأقسام الظاهرة ← القوائم ← التشغيل ← النظام")
check(AdminAreaLayout.groups("inbox"), [], "«الوارد» unchanged (no groups)")
check(G.upcoming.title, "القادم", "group title")
check(G.system.title, "النظام", "group title")

// MARK: كل أداة في مجموعة من مجموعات قسمها
for tool in Tool.allCases {
    guard let g = AdminAreaLayout.group(of: tool) else { continue }
    check(AdminAreaLayout.groups(tool.areaKey).contains(g), true, "\(tool.rawValue): group belongs to its area")
}
check(AdminAreaLayout.group(of: .accessUsage), .inApp, "usage under «في التطبيق»")
check(AdminAreaLayout.group(of: .accessSms), .system, "SMS under «النظام»")
check(AdminAreaLayout.group(of: .accessDevices), .system, "devices under «النظام»")
check(AdminAreaLayout.group(of: .appErrors), .system, "errors under «النظام»")
check(AdminAreaLayout.group(of: .appForceUpdate), .operations, "force update under «التشغيل»")

// MARK: البوابة — الصلاحيات لم تتغيّر: «التطبيق والنظام» للمالك فقط، و«الفريق والصلاحيات» ليس كذلك
let itemKeys = ["team.members", "team.usage", "team.sms", "team.registration", "team.devices", "app.settings"]
let ownerOnly: Set<String> = ["team.sms", "team.registration", "team.devices", "app.settings"]
check(AdminGateLogic.message(areaKey: "app", allItemKeys: itemKeys, ownerOnlyItemKeys: ownerOnly), .ownerOnly,
      "app area: owner only")
check(AdminGateLogic.message(areaKey: "team", allItemKeys: itemKeys, ownerOnlyItemKeys: ownerOnly), .notInRole,
      "team area: not owner-only (the manager reads the team)")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
