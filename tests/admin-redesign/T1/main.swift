// فحص قواعد بطاقة العضو في الشجرة «أ» (T1، ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/t1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeMemberCardLogic.swift tests/admin-redesign/T1/main.swift \
//     && /private/tmp/claude-501/t1-logic
//
// ما يُفحص: زرّ الأسفل حسب الدور · مربّعات «طلب تعديل» حسب الشخص وصدق سطرها · نصّ زرّ القرابة · سطر الحقائق ·
// ملخّصات المجموعات · الخصوصية («طلبك عنه» طلباتك فقط، الرقم المخفي، لا صورة للمرأة).
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true
typealias L = TreeMemberCardLogic

// MARK: ١) زرّ الأسفل حسب الدور

check(L.bottomButton(isSelf: false, canEditMembers: true, isDeleted: false), .admin, "owner/admin/monitor → «الإدارة»")
check(L.bottomButton(isSelf: true, canEditMembers: true, isDeleted: false), .admin, "staff on own card → «الإدارة» (v3 locks)")
check(L.bottomButton(isSelf: false, canEditMembers: false, isDeleted: false), .requestEdit, "member/supervisor → «طلب تعديل»")
check(L.bottomButton(isSelf: true, canEditMembers: false, isDeleted: false), .editMine, "own card → «تعديل بياناتي»")
check(L.bottomButton(isSelf: false, canEditMembers: true, isDeleted: true), .none, "deleted account → no button")
check(L.BottomButton.admin.title, "الإدارة", "admin title")
check(L.BottomButton.requestEdit.title, "طلب تعديل", "request title")
check(L.BottomButton.editMine.title, "تعديل بياناتي", "mine title")

// MARK: ٢) من هو الشخص

let me = UUID(), other = UUID()
check(L.person(isSelf: true, viewerId: me, fatherId: nil), .me, "self")
check(L.person(isSelf: false, viewerId: me, fatherId: me), .myChild, "my son")
check(L.person(isSelf: false, viewerId: me, fatherId: other), .other, "someone else")
check(L.person(isSelf: false, viewerId: nil, fatherId: nil), .other, "no viewer → other")

// MARK: ٣) المربّعات حسب الشخص

func kinds(_ t: [L.Tile]) -> [L.TileKind] { t.map(\.kind) }
let otherMan = L.tiles(person: .other, isFemale: false, isDeceased: false)
check(kinds(otherMan), [.name, .birth, .death, .photo, .addSon, .remove], "other man: six tiles")
check(otherMan.allSatisfy { $0.honesty == .afterApproval }, true, "other man: all «بعد موافقة الإدارة»")
check(kinds(otherMan).contains(.myPhone), false, "ح١: no phone tile for someone else")
let deadMan = L.tiles(person: .other, isFemale: false, isDeceased: true)
check(kinds(deadMan), [.name, .birth, .deathDate, .photo, .addSon, .remove], "deceased man: death date instead of death")
let otherWoman = L.tiles(person: .other, isFemale: true, isDeceased: false)
check(kinds(otherWoman).contains(.photo), false, "ح٢: no photo tile for a woman")
check(kinds(otherWoman), [.name, .birth, .death], "woman: name, birth, death (no add/remove in the men's tree)")
let mine = L.tiles(person: .me, isFemale: false, isDeceased: false)
check(kinds(mine), [.myData, .myPhone, .addMyChild], "yourself: my data, my phone, add child")
check(mine.map(\.honesty), [.firstThreeNow, .withCode, .afterApproval], "yourself: honest lines")
check(kinds(L.tiles(person: .me, isFemale: true, isDeceased: false)), [.myData, .myPhone], "woman yourself: no add child here")
let child = L.tiles(person: .myChild, isFemale: false, isDeceased: false)
check(kinds(child), [.childData, .death, .addSon, .remove], "my son: his data, death, add son, remove")
check(child.first?.honesty, .savedNow, "my son's data «يُحفظ فوراً»")
check(L.Honesty.afterApproval.text, "بعد موافقة الإدارة", "honest line: after approval")
check(L.Honesty.savedNow.text, "يُحفظ فوراً", "honest line: saved now")
check(L.Honesty.firstThreeNow.text, "أول 3 تعديلات فوراً", "honest line: first three")
check(L.TileKind.remove.title, "حذف من الشجرة", "remove = «حذف من الشجرة» (hide path)")
check(L.TileKind.remove.editAction, "delete", "remove uses the existing delete (hide) action")
check(L.TileKind.name.editAction, "edit_name", "name → edit_name")
check(L.TileKind.myData.editAction, nil, "my data is not a tree_edit request")
check(L.hasPending(.birth, myActions: ["edit_birth"]), true, "tile with my pending request → «طلبك ينتظر»")
check(L.hasPending(.name, myActions: ["edit_birth"]), false, "other tile not pending")
check(L.hasPending(.childData, myActions: ["edit_birth"]), false, "non-request tile never pending")

// MARK: ٤) زرّ القرابة

check(L.kinship(isSelf: false, viewerHasNode: true, isDeleted: false, relationship: "ابن خالك", isBlood: true,
                distA: 2, distB: 2, ancestorName: "طاهر"),
      .button(title: "ابن خالك", line: nil), "near kin: words only")
check(L.kinship(isSelf: false, viewerHasNode: true, isDeleted: false, relationship: "من أقاربك", isBlood: true,
                distA: 8, distB: 7, ancestorName: "المحمدعلي"),
      .button(title: "من أقاربك", line: "يلتقي معك في جدّكما المحمدعلي"), "ت٤: distant kin gets the meeting line")
check(L.kinship(isSelf: false, viewerHasNode: true, isDeleted: false, relationship: "من أقاربك", isBlood: true,
                distA: 8, distB: 7, ancestorName: nil),
      .button(title: "من أقاربك", line: nil), "distant without ancestor name: no line")
check(L.kinship(isSelf: true, viewerHasNode: true, isDeleted: false, relationship: "أنت", isBlood: false,
                distA: 0, distB: 0, ancestorName: nil), .mine, "own card: no kinship button")
check(L.kinship(isSelf: false, viewerHasNode: false, isDeleted: false, relationship: "", isBlood: false,
                distA: 0, distB: 0, ancestorName: nil), .locked, "ت٥: viewer without a node → locked")
check(L.lockedKinshipText, "تظهر القرابة بعد ربط حسابك", "locked text")
check(L.mineText, "هذه بطاقتك كما يراها أقاربك", "own card line")

// MARK: ٥) سطر الحقائق والعمر

check(L.age(birth: "1985-09-10", death: nil, deceased: false, nowYear: 2026), 41, "alive age from year")
check(L.age(birth: "1908-01-01", death: nil, deceased: true, nowYear: 2026), nil, "deceased without death date: no age")
check(L.age(birth: "1890-01-01", death: nil, deceased: false, nowYear: 2026), nil, "130+ years: no age")
check(L.age(birth: nil, death: nil, deceased: false, nowYear: 2026), nil, "no birth: no age")
check(L.factsLine(age: 41, deceased: false, female: false, sons: 3), "41 سنة · 3 أبناء", "alive: age · sons")
check(L.factsLine(age: nil, deceased: true, female: false, sons: 4), "متوفى · 4 أبناء", "ت٩: deceased without date → «متوفى» only")
check(L.factsLine(age: nil, deceased: true, female: true, sons: 0), "متوفاة", "deceased woman")
check(L.factsLine(age: 76, deceased: true, female: false, sons: 1), "متوفى عن 76 سنة · ابن واحد", "deceased with dates")
check(L.factsLine(age: 2, deceased: false, female: false, sons: 2), "سنتان · ابنان", "dual forms")
check(L.factsLine(age: 33, deceased: false, female: false, sons: 11), "33 سنة · 11 ابناً", "11+ sons")
check(L.factsLine(age: nil, deceased: false, female: false, sons: 0), "", "nothing → empty")

// MARK: ٦) ملخّصات المجموعات

check(L.familySummary(fatherName: "عبدالمحسن", sons: 3), "الأب عبدالمحسن · 3 أبناء", "family summary")
check(L.familySummary(fatherName: nil, sons: 0), nil, "no family → no group")
check(L.dataSummary(birth: "10/09/1985", death: nil, deceased: false, female: false), "ميلاد 10/09/1985", "data: birth")
check(L.dataSummary(birth: nil, death: nil, deceased: true, female: false), "متوفى", "data: deceased without dates")
check(L.dataSummary(birth: "1908", death: "1990", deceased: true, female: true), "ميلاد 1908 · وفاة 1990", "data: both")
check(L.dataSummary(birth: nil, death: nil, deceased: false, female: false), "الميلاد غير مسجّل", "data: nothing")
check(L.maskedPhone("+965 9999 1234"), "+965 •••• ••••", "masked phone keeps the country code only")
check(L.maskedPhone("99991234"), "•••• ••••", "masked local phone")
check(L.contactSummary(female: false, masked: "+965 •••• ••••"), "رقمه +965 •••• ••••", "contact summary (his)")
check(L.contactSummary(female: true, masked: "+965 •••• ••••"), "رقمها +965 •••• ••••", "contact summary (hers)")

// MARK: ٧) الخصوصية — «طلبك عنه» طلباتك فقط

let target = UUID(), someoneElse = UUID(), women = UUID()
let reqs: [L.RequestRef] = [
    .init(id: UUID(), memberId: target, requesterId: me, womenNode: nil),
    .init(id: UUID(), memberId: target, requesterId: someoneElse, womenNode: nil),
    .init(id: UUID(), memberId: other, requesterId: me, womenNode: nil),
    .init(id: UUID(), memberId: target, requesterId: me, womenNode: women)
]
check(L.mine(reqs, memberId: target, viewer: me), [reqs[0].id], "م١٠: only my request about him")
check(L.mine(reqs, memberId: target, viewer: nil), [], "no viewer → none")
check(L.showsAllRequests(canModerateTree: true), true, "tree deciders see every request about him")
check(L.showsAllRequests(canModerateTree: false), false, "supervisor/member never see others' requests")
check(L.myRequestTitle(female: false), "طلبك عنه", "his")
check(L.myRequestTitle(female: true), "طلبك عنها", "hers")
check(L.showsPhoto(isFemale: true), false, "women: no photo")
check(L.showsPhoto(isFemale: false), true, "men: photo")


// MARK: ٨) إصلاحات نقد «المنتقد» بعد البناء (built-critique.md)

// م١: «حذف من الشجرة» بقاعدة `showsDeleteRequest` القديمة — لا لمسجّل ولا لمن هو في الإدارة ولا لمنتظر
check(L.canRequestRemoval(hasLogin: false, isStaff: false, isPending: false), true, "م١: plain tree member → remove allowed")
check(L.canRequestRemoval(hasLogin: true, isStaff: false, isPending: false), false, "م١: registered member → no remove")
check(L.canRequestRemoval(hasLogin: false, isStaff: true, isPending: false), false, "م١: staff (owner/admin/monitor/supervisor) → no remove")
check(L.canRequestRemoval(hasLogin: false, isStaff: false, isPending: true), false, "م١: pending → no remove")
check(L.staffRoles, ["owner", "admin", "monitor", "supervisor"], "م١: staff roles as the old rule")
check(kinds(L.tiles(person: .other, isFemale: false, isDeceased: false, canRemove: false)),
      [.name, .birth, .death, .photo, .addSon], "م١: other man with login → no remove tile")
check(kinds(L.tiles(person: .myChild, isFemale: false, isDeceased: false, canRemove: false)),
      [.childData, .death, .addSon], "م١: my son not removable → no remove tile")
check(kinds(L.tiles(person: .other, isFemale: false, isDeceased: false, canRemove: true)),
      [.name, .birth, .death, .photo, .addSon, .remove], "م١: removable other keeps remove")

// م٢: ابنك وله حساب دخول → مربّعات الطلب لا «يُحفظ فوراً»
check(L.person(isSelf: false, viewerId: me, fatherId: me, childHasLogin: true), .other, "م٢: my son with a login → request tiles")
check(L.person(isSelf: false, viewerId: me, fatherId: me, childHasLogin: false), .myChild, "م٢: my son without login → «عائلتي»")
check(L.childHasLogin(looksRegistered: true, serverAnswer: false), true, "م٢: looks registered → login")
check(L.childHasLogin(looksRegistered: false, serverAnswer: true), true, "م٢: profile_has_login true → login")
check(L.childHasLogin(looksRegistered: false, serverAnswer: false), false, "م٢: server says no login → «عائلتي»")
check(L.childHasLogin(looksRegistered: false, serverAnswer: nil), true, "م٢: unknown yet → safe request path")
let sonWithLogin = L.tiles(person: L.person(isSelf: false, viewerId: me, fatherId: me, childHasLogin: true),
                           isFemale: false, isDeceased: false, canRemove: false)
check(sonWithLogin.contains { $0.honesty == .savedNow }, false, "م٢: no «يُحفظ فوراً» for a son with a login")
// ت٨: ابنك أنثى (سجلّ قديم) — لا «إضافة ابن»
check(kinds(L.tiles(person: .myChild, isFemale: true, isDeceased: false, canRemove: true)).contains(.addSon), false,
      "ت٨: female child → no add son")

// م٣: لا «صورتي» للمرأة
check(L.TileKind.myData.title(female: false), "اسمي وميلادي وصورتي", "م٣: man self tile mentions photo")
check(L.TileKind.myData.title(female: true), "اسمي وميلادي", "م٣: woman self tile without photo")
check(L.TileKind.name.title(female: true), "الاسم", "م٣: other titles unchanged")

// م٤: على بطاقتك «طلبك»
check(L.myRequestTitle(female: false, isSelf: true), "طلبك", "م٤: own card → «طلبك»")
check(L.myRequestTitle(female: true, isSelf: true), "طلبك", "م٤: own card (woman) → «طلبك»")
check(L.myRequestTitle(female: true, isSelf: false), "طلبك عنها", "م٤: about her unchanged")
check(L.requestSubtitle(name: "حسن", isSelf: true), "حسن", "م٤: own card subtitle = your name, no «عن»")
check(L.requestSubtitle(name: "حسن", isSelf: false), "عن حسن", "م٤: others keep «عن»")

// ت١: «تلتقي معك» للمرأة، و«جدّ العائلة» حين الجد رأس الشجرة
check(L.kinship(isSelf: false, viewerHasNode: true, isDeleted: false, relationship: "من أقاربك", isBlood: true,
                distA: 8, distB: 7, ancestorName: "طاهر", female: true, ancestorIsRoot: false),
      .button(title: "من أقاربك", line: "تلتقي معك في جدّكما طاهر"), "ت١: feminine meeting line")
check(L.kinship(isSelf: false, viewerHasNode: true, isDeleted: false, relationship: "من أقاربك", isBlood: true,
                distA: 8, distB: 7, ancestorName: "المحمدعلي", female: false, ancestorIsRoot: true),
      .button(title: "من أقاربك", line: "يلتقي معك في جدّ العائلة"), "ت١: tree root → «جدّ العائلة»")

// ت٢: من يرى كل الطلبات لا يرى طلبه مرتين
check(L.othersRequests(reqs, viewer: me).count, 1, "ت٢: all-requests list drops my own")
check(L.othersRequests(reqs, viewer: nil).count, reqs.count, "ت٢: no viewer → all")

// الرقم: كما كانت البطاقة القديمة — الرقم الظاهر يظهر للمتوفى أيضاً
check(L.showsPhoneRow(visible: "+965 9999 1234", deceased: true), true, "old rule: deceased visible phone still shown")
check(L.showsPhoneRow(visible: nil, deceased: false), false, "hidden phone → no row")

// English sanity
L10n.isArabic = false
check(L.BottomButton.requestEdit.title, "Request edit", "English request title")
check(L.factsLine(age: 41, deceased: false, female: false, sons: 3), "41 yrs · 3 sons", "English facts")
L10n.isArabic = true

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
