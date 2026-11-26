// فحص منطق فهرس الأدوات وبوابة القسم (Views/Features/Admin/AdminCatalogLogic.swift، الوحدة U19) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u19-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCatalogLogic.swift tests/admin-redesign/U19/main.swift && /tmp/u19-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias Tool = AdminCatalogTool
typealias Home = AdminCatalogHome

// MARK: كل المعرّفات القديمة باقية (inventory §4 «AdminToolCatalog (search ids)»)

let oldIds = ["inbox.requests", "inbox.messages", "inbox.settings",
              "family.members", "family.register", "family.export",
              "occasions.create",
              "metrics.family", "metrics.approvals",
              "today.notices",
              "team.members",
              "access.sms", "access.registration", "access.usage",
              "app.sections", "app.categories", "app.names", "app.forceUpdate", "app.errors"]
for id in oldIds {
    check(Tool(rawValue: id) != nil, true, "old id kept: \(id)")
}
check(Tool.allCases.count, oldIds.count + 1, "only one id added (access.devices)")
check(Tool(rawValue: "access.devices")?.home, .devices, "new id access.devices opens «الأجهزة والإشعارات»")

// MARK: القسم والبيت

let areas: Set<String> = ["inbox", "family", "occasions", "metrics", "team", "app"]
for tool in Tool.allCases {
    check(areas.contains(tool.areaKey), true, "\(tool.rawValue): area is one of the six")
}
// بيت واحد لكل أداة، ولا أداتان لبيت واحد (صفّان في البحث يفتحان الشيء نفسه)
check(Set(Tool.allCases.map(\.home)).count, Tool.allCases.count, "one tool per home")
check(Set(Tool.allCases.map(\.home)), Set(Home.allCases), "every home has its tool")

check(Tool.metricsFamily.home, .statsRoot, "metrics.family opens the «الإحصاءات» root")
check(Tool.metricsApprovals.home, .approvalsReport, "metrics.approvals opens ApprovalsReportView")
check(Tool.inboxMessages.home, .messagesPage, "inbox.messages opens the messages page")
check(Tool.inboxRequests.home, .inboxRoot, "inbox.requests opens the inbox root")
check(Tool.familyMembers.home, .familyRoot, "family.members opens the family root")
check(Tool.accessUsage.home, .usage, "access.usage opens «الاستخدام» (AdminActiveMembersView, spec C.13)")
check(Tool.todayNotices.home, .adminNotices, "today.notices opens «إشعارات الإدارة»")
check(Tool.appErrors.home, .errors, "app.errors opens AdminErrorsPage")
check(Tool.metricsFamily.areaKey, "metrics", "metrics.family belongs to «الإحصاءات» (hidden area hides it)")
check(Tool.todayNotices.areaKey, "inbox", "today.notices follows the inbox (every moderator)")

// MARK: الكلمات — الجديدة، والقديمة تجد بيتها الجديد

func found(_ q: String) -> Set<Tool> { Set(AdminCatalogLogic.tools(matching: q)) }
func homes(_ q: String) -> Set<Home> { Set(found(q).map(\.home)) }

check(homes("المؤشرات").contains(.statsRoot), true, "«المؤشرات» (old name) finds the «الإحصاءات» root")
check(homes("المؤشرات").isSubset(of: [.statsRoot, .approvalsReport]), true, "«المؤشرات» finds stats homes only")
check(homes("الرسائل"), [.messagesPage], "«الرسائل» finds the messages page only")
check(homes("المنجزة"), [.inboxRoot], "«المنجزة» finds the inbox root (door «المنجز»)")
check(homes("المنجز").contains(.inboxRoot), true, "«المنجز» finds the inbox root")
check(homes("شجرة النساء").contains(.familyRoot), true, "«شجرة النساء» finds the family root («نساء العائلة»)")
check(homes("مراجعة").isSuperset(of: [.inboxRoot, .familyRoot]), true, "«مراجعة» finds the inbox and «يحتاج مراجعتك»")
check(homes("يحتاج مراجعتك"), [.familyRoot], "«يحتاج مراجعتك» finds the family root")
check(homes("إحصاء الأفراد"), [.statsRoot], "old «إحصاء الأفراد» finds the stats root")
check(homes("إحصاءات").contains(.statsRoot), true, "«إحصاءات» finds the stats root")
check(homes("تقرير الموافقات"), [.approvalsReport], "«تقرير الموافقات» finds the approvals report")
check(homes("الاستخدام"), [.usage], "«الاستخدام» finds usage only (not the devices page)")
check(homes("إشعار تجريبي"), [.devices], "«إشعار تجريبي» finds the devices page")
check(homes("الأجهزة ووصول الإشعارات"), [.devices], "old «الأجهزة ووصول الإشعارات» finds the devices page")
check(homes("سجل التعديلات"), [.adminNotices], "old «سجل التعديلات» finds «إشعارات الإدارة»")
check(homes("وضع الصيانة"), [.appRoot], "«وضع الصيانة» finds the app root")
check(homes("حالة النظام"), [.appRoot], "old «حالة النظام» finds the app root (status card)")
check(homes("حظر").contains(.registrationBans), true, "old «حظر» finds «التسجيل والمنع»")
check(homes("مشكلات الشجرة"), [.familyRoot], "old «مشكلات الشجرة» finds the family root")
check(homes("طلبات رمز الدخول"), [.sms], "«طلبات رمز الدخول» finds the SMS page")
check(homes("يحتاج انتباهك"), [.inboxRoot], "old «يحتاج انتباهك» finds the inbox root")
check(homes("kwt"), [.sms], "«kwt» finds the SMS page")
check(homes("سنتري"), [.errors], "«سنتري» finds the errors page")
check(found("   ").isEmpty, true, "blank query finds nothing")
// النصوص الظاهرة تُطابق أيضاً (العنوان، الوصف، المكان)
check(AdminCatalogLogic.tools(matching: "إحصاءات العائلة", among: [.metricsFamily],
                              texts: { _ in ["إحصاءات العائلة", "الإحصاءات"] }), [.metricsFamily],
      "title text matches too")
check(AdminCatalogLogic.tools(matching: "زيارات", among: [.metricsFamily], texts: { _ in ["الإحصاءات"] }), [],
      "unrelated word finds nothing")

// MARK: رسالة البوابة (سقف جدول الأدوار — Core/AdminRoleMatrix.swift: `AdminRoleItem` و`isOwnerOnly`)

let itemKeys = ["today.attention", "today.census", "today.system_status", "today.megaphone",
                "inbox.messages", "inbox.photos", "inbox.approval_settings",
                "occasions.upcoming", "occasions.announce", "occasions.cards", "occasions.published",
                "metrics.family", "metrics.approvals",
                "team.members", "team.usage", "team.sms", "team.registration", "team.devices",
                "app.settings"]
let ownerOnly: Set<String> = ["team.sms", "team.registration", "team.devices", "app.settings"]
func gate(_ area: String) -> AdminGateLogic.Message {
    AdminGateLogic.message(areaKey: area, allItemKeys: itemKeys, ownerOnlyItemKeys: ownerOnly)
}

check(AdminGateLogic.itemKeys(of: "team", in: itemKeys).count, 5, "team has five items")
check(AdminGateLogic.itemKeys(of: "app", in: itemKeys), ["app.settings"], "app has app.settings only")

// الأقسام التي يرفضها الجدول الافتراضي لكل دور (spec B.3) — الرسالة من سقف القسم لا من الدور
let refused: [(role: String, area: String, want: AdminGateLogic.Message)] = [
    ("admin", "app", .ownerOnly),
    ("monitor", "app", .ownerOnly),
    ("monitor", "team", .notInRole),
    ("supervisor", "app", .ownerOnly),
    ("supervisor", "team", .notInRole),
    ("supervisor", "family", .notInRole),
    ("supervisor", "metrics", .notInRole),
    // جدول السيرفر قد يخفي غيرها
    ("admin", "occasions", .notInRole),
    ("monitor", "inbox", .notInRole),
]
for r in refused {
    check(gate(r.area), r.want, "gate \(r.role) refused «\(r.area)»")
}
// قسم كل خاناته للمالك = للمالك فقط؛ وقسم بلا خانات ليس «للمالك فقط»
check(AdminGateLogic.message(areaKey: "x", allItemKeys: ["x.a", "x.b"], ownerOnlyItemKeys: ["x.a", "x.b"]),
      .ownerOnly, "area whose items are all owner-capped → owner only")
check(AdminGateLogic.message(areaKey: "x", allItemKeys: ["x.a", "x.b"], ownerOnlyItemKeys: ["x.a"]),
      .notInRole, "one open item → not owner only")

L10n.isArabic = true
check(AdminGateLogic.Message.ownerOnly.title, "هذا القسم للمالك فقط.", "owner-only text")
check(AdminGateLogic.Message.notInRole.title, "هذا القسم ليس ضمن صلاحياتك.", "not-in-role text")
check(AdminGateLogic.Message.notInRole.hint.contains("صلاحياتي"), true, "hint names «صلاحياتي»")
L10n.isArabic = false
check(AdminGateLogic.Message.notInRole.title, "This section isn't part of your permissions.", "English text")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
