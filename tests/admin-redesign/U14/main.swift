// فحص منطق «المناسبات والإعلانات» (Views/Features/Admin/AdminOccasionsLogic.swift، الوحدة U14) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u14-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminOccasionsLogic.swift tests/admin-redesign/U14/main.swift && /tmp/u14-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminOccasionsLogic

// MARK: الأدوار (افتراضي جدول السيرفر: المالك كل شي، المدير يعدّل والمنشور «يقرأ»، المراقب «للاطلاع»، المشرف البطاقات)
let owner = L.Access.make(isAdmin: true, canSendNotifications: true, cardKind: true, announceKind: true,
                          seesPublished: true, areaEdit: true, canEditMembers: true, familyEdit: true, ownerSystem: true)
let admin = L.Access.make(isAdmin: true, canSendNotifications: true, cardKind: true, announceKind: true,
                          seesPublished: true, areaEdit: true, canEditMembers: true, familyEdit: true, ownerSystem: false)
let monitor = L.Access.make(isAdmin: false, canSendNotifications: false, cardKind: false, announceKind: false,
                            seesPublished: false, areaEdit: false, canEditMembers: true, familyEdit: true, ownerSystem: false)
let supervisor = L.Access.make(isAdmin: false, canSendNotifications: false, cardKind: true, announceKind: false,
                               seesPublished: false, areaEdit: true, canEditMembers: false, familyEdit: false, ownerSystem: false)

check(L.sections(owner), [.joys, .grief, .launch, .announcements], "owner: the four sections in «أ» order")
check(owner.create && owner.card && owner.announceDeath && owner.stopLaunch && owner.editScheduled, true,
      "owner: every command")
check(owner.reach, true, "owner: device reach row")
check(owner.headerLine, true, "owner: header line")
check(admin.reach, false, "admin: no device reach (owner's home)")
check(admin.editScheduled, true, "admin: edit/cancel scheduled (published item «read» does not hide them)")

check(L.sections(monitor), [.grief], "monitor: «عزاء وذكرى» only")
check(monitor.readOnly, true, "monitor: read-only line")
check(monitor.create || monitor.card || monitor.announceDeath || monitor.stopLaunch || monitor.editScheduled, false,
      "monitor: no edit controls")
check(monitor.datesRow && monitor.datesOpens, true, "monitor: incomplete dates row opens «تواريخ الوفاة» (family edit)")
check(monitor.headerLine, false, "monitor: no header line")

check(L.sections(supervisor), [.joys, .grief], "supervisor: joys + memorials")
check(supervisor.create && supervisor.card, true, "supervisor: «＋ إنشاء» (cards) and «بطاقة»")
check(supervisor.deaths || supervisor.announceDeath, false, "supervisor: no unannounced deaths")
check(supervisor.datesRow, false, "supervisor: no incomplete dates row")

// «يعدّل» القسم يُضرب مع صلاحية الدور: مدير والقسم «للاطلاع»
let adminRead = L.Access.make(isAdmin: true, canSendNotifications: true, cardKind: true, announceKind: true,
                              seesPublished: true, areaEdit: false, canEditMembers: true, familyEdit: true, ownerSystem: false)
check(L.sections(adminRead), [.joys, .grief, .launch, .announcements], "admin + area read: sections still shown")
check(adminRead.create || adminRead.card || adminRead.announceDeath || adminRead.stopLaunch || adminRead.editScheduled,
      false, "admin + area read: every command hidden")
check(adminRead.readOnly, true, "admin + area read: read-only line")
// «إرسال إشعار» ممنوع في الجدول (occasions.announce none) والبطاقة متاحة: «＋ إنشاء» يبقى للبطاقة
let cardsOnly = L.Access.make(isAdmin: true, canSendNotifications: true, cardKind: true, announceKind: false,
                              seesPublished: false, areaEdit: true, canEditMembers: true, familyEdit: true, ownerSystem: false)
check(cardsOnly.create, true, "announce item none + cards: «＋ إنشاء» stays (cards)")
check(L.sections(cardsOnly).contains(.announcements), false, "published item none: no «الإعلانات»")
let nothing = L.Access.make(isAdmin: true, canSendNotifications: true, cardKind: false, announceKind: false,
                            seesPublished: true, areaEdit: true, canEditMembers: true, familyEdit: false, ownerSystem: false)
check(nothing.create, false, "no creator kind: no «＋ إنشاء»")
check(nothing.datesOpens, false, "family not editable: dates row shows the number without a chevron")

// MARK: الهبوط
check(L.section(for: .awaiting), .grief, "awaiting (unannounced death) → «عزاء وذكرى»")
check(L.section(for: .memorials), .grief, "memorials → «عزاء وذكرى»")
check(L.section(for: .scheduled), .announcements, "scheduled → «الإعلانات»")
check(L.section(for: .doors), .announcements, "doors → «الإعلانات»")
check(L.section(for: .launch), .launch, "launch → «الإعلانات عند الفتح»")
let all = L.sections(owner)
check(L.scrollTarget(explicit: nil, stored: .scheduled, shown: all), .announcements, "stored landing scrolls")
check(L.scrollTarget(explicit: .launch, stored: .scheduled, shown: all), .launch, "explicit beats stored")
check(L.scrollTarget(explicit: nil, stored: nil, shown: all), nil, "no landing: top")
check(L.scrollTarget(explicit: nil, stored: .scheduled, shown: L.sections(supervisor)), nil, "hidden section ignored")
check(L.scrollTarget(explicit: nil, stored: .memorials, shown: L.sections(monitor)), nil,
      "first section = top, no scroll (header stays)")
check(L.scrollTarget(explicit: nil, stored: .memorials, shown: L.sections(supervisor)), .grief,
      "supervisor memorials → scroll past joys")
check(Set(AdminOccasionsAnchor.allCases.map { L.section(for: $0) }).isSubset(of: Set(AdminOccasionsSection.allCases)), true,
      "every anchor has a section")

// MARK: «عرض الكل»
check(L.visibleCount(total: 7, limit: L.collapsedRows, expanded: false), 3, "collapsed: 3")
check(L.visibleCount(total: 7, limit: L.collapsedRows, expanded: true), 7, "expanded: all")
check(L.visibleCount(total: 2, limit: L.collapsedRows, expanded: false), 2, "fewer than the limit")
check(L.needsToggle(total: 3, limit: L.collapsedRows), false, "3 rows: no toggle")
check(L.needsToggle(total: 4, limit: L.collapsedRows), true, "4 rows: toggle")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
