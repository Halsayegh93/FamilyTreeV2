// فحص قواعد بطاقة العضو «AB» (Views/Features/Tree/MemberCardLogic.swift، الوحدة L1، ٢٠٢٦-١١-٢٧) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/l1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/MemberCardLogic.swift tests/admin-redesign/L1/main.swift \
//     && /private/tmp/claude-501/l1-logic
//
// ما يُفحص (proposal.md البنود ١–٩): خانات «طلب تعديل» لكل شخص (لا رقم لغيرك، لا صورة لأنثى، بنت أقل من 13 بلا
// «الزوج/أبناء») · السطر الصادق والحذف بكلامه · خانة «طلبك قيد المراجعة» · «طلبك عنه» حسب الدور · رقم المرأة ·
// رسالة الإرسال بلا «قريباً» · العمر «5 سنوات».
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true
typealias L = MemberCardLogic

// MARK: ١) خانات شجرة العائلة: لا «تعديل رقم» لغيرك، ولا «إضافة صورة» لأنثى

let man = L.familyKinds(isFemale: false, isDeceased: false)
check(man, ["add", "edit_name", "edit_birth", "add_photo", "deceased", "delete"], "living man: old order without edit_phone")
check(man.contains("edit_phone"), false, "no phone request for someone else")
check(L.familyKinds(isFemale: false, isDeceased: true), ["add", "edit_name", "edit_birth", "add_death_date", "add_photo", "delete"],
      "deceased man: death date instead of death")
check(L.familyKinds(isFemale: true, isDeceased: false).contains("add_photo"), false, "no photo request for a woman")
check(L.familyKinds(isFemale: true, isDeceased: true).contains("add_photo"), false, "no photo request for a deceased woman")
check(L.familyKinds(isFemale: true, isDeceased: true).contains("edit_phone"), false, "no phone request for a woman")

// MARK: ٢) السطر الصادق والحذف بكلامه

check(L.familyHonesty("edit_birth").text, "يُطبَّق عند الموافقة", "family edits apply on approval")
check(L.familyHonesty("add").text, "يُطبَّق عند الموافقة", "family son applies on approval")
check(L.familyHonesty("delete").text, "يُخفى ويبقى في السجل", "family delete = hidden, kept")
check(L.womenHonesty("req.delete", isFemale: true, hasHusband: false, hasFatherWives: false).text,
      "يُحذف بموافقة المالك أو المدير", "women delete = owner or admin")
check(L.womenHonesty("req.other", isFemale: true, hasHusband: false, hasFatherWives: false).text,
      "تنفّذه الإدارة بيدها", "women «other» is manual")
check(L.womenHonesty("req.editBirth", isFemale: true, hasHusband: false, hasFatherWives: false), .afterApproval, "women birth auto")
check(L.womenHonesty("husband", isFemale: true, hasHusband: false, hasFatherWives: false), .adminDoes, "husband is manual")
check(L.womenHonesty("wife", isFemale: false, hasHusband: false, hasFatherWives: false), .adminDoes, "wife is manual")
check(L.womenHonesty("child", isFemale: true, hasHusband: false, hasFatherWives: false), .adminDoes, "child of unmarried woman manual")
check(L.womenHonesty("child", isFemale: true, hasHusband: true, hasFatherWives: false), .afterApproval, "child of married woman auto")
check(L.womenHonesty("addMother", isFemale: true, hasHusband: false, hasFatherWives: true), .afterApproval, "mother from father's wives auto")
check(L.womenHonesty("addMother", isFemale: true, hasHusband: false, hasFatherWives: false), .adminDoes, "new mother manual")
check(L.Honesty.hidesKeepsRecord.isWarning, true, "delete line in warning colour")
check(L.Honesty.afterApproval.isWarning, false, "normal line not warning")

// MARK: ٣) شجرة النساء: بنت أقل من 13 بلا «الزوج» و«أبناء»

let hawra = L.womenRequestIds(isFemale: true, hasHusband: false, hasMother: true, isFatherNode: false, isDeceased: false, age: 5)
check(hawra, ["req.editName", "req.editBirth", "req.deceased", "req.other", "req.delete"], "girl aged 5: no husband, no children")
let noBirth = L.womenRequestIds(isFemale: true, hasHusband: false, hasMother: true, isFatherNode: false, isDeceased: false, age: nil)
check(noBirth.contains("child") && noBirth.contains("husband"), true, "no birth date → husband and children stay")
let adult = L.womenRequestIds(isFemale: true, hasHusband: false, hasMother: false, isFatherNode: false, isDeceased: false, age: 30)
check(adult, ["child", "husband", "addMother", "req.editName", "req.editBirth", "req.deceased", "req.other", "req.delete"], "adult woman")
check(L.womenRequestIds(isFemale: true, hasHusband: false, hasMother: true, isFatherNode: false, isDeceased: false, age: 13).contains("husband"),
      true, "13 is not under 13")
let father = L.womenRequestIds(isFemale: false, hasHusband: false, hasMother: true, isFatherNode: true, isDeceased: true, age: 80)
check(father, ["child", "wife", "sister", "req.editName", "req.editBirth", "req.other", "req.delete"], "man node (my father, deceased)")
check(L.womenRequestIds(isFemale: false, hasHusband: false, hasMother: true, isFatherNode: false, isDeceased: false, age: 5).contains("child"),
      true, "young boy keeps children (rule is for girls)")
check(L.womenGridNote(isFemale: true, age: 5), "«أبناء» و«الزوج» لا يظهران: عمرها المسجّل 5 سنوات، أقل من 13.", "young-girl note")
check(L.womenGridNote(isFemale: true, age: 20), nil, "no note for adult")
check(L.womenGridNote(isFemale: true, age: nil), nil, "no note without birth")
check(L.familyGridNote(isFemale: false).contains("لا «تعديل رقم» لغيرك"), true, "family note explains phone")
check(L.familyGridNote(isFemale: false).contains("«إضافة صورة» للرجال فقط"), true, "family note explains photo")

// MARK: ٤) «طلبك قيد المراجعة» على الخانة

let me = UUID(), other = UUID(), person = UUID(), daughter = UUID()
let refs: [L.RequestRef] = [
    .init(id: UUID(), memberId: person, requesterId: me, womenNode: nil, kind: "edit_birth"),
    .init(id: UUID(), memberId: person, requesterId: other, womenNode: nil, kind: "edit_name"),
    .init(id: UUID(), memberId: person, requesterId: me, womenNode: daughter, kind: "edit_birth"),
    .init(id: UUID(), memberId: UUID(), requesterId: me, womenNode: nil, kind: "add"),
]
let mine = L.mineInFamily(refs, memberId: person, viewer: me)
check(mine.count, 1, "only my own request about him (not others', not his daughter's)")
check(L.pending(kind: "edit_birth", in: mine)?.id, refs[0].id, "birth tile opens my pending birth request")
check(L.pending(kind: "edit_name", in: mine), nil, "someone else's name request does not lock my tile")
check(L.pending(kind: nil, in: mine), nil, "unknown kind → no pending")
check(L.mineInFamily(refs, memberId: person, viewer: nil).count, 0, "no viewer → nothing")
let womenMine = L.mineInWomen(refs, nodeId: daughter, viewer: me)
check(womenMine.count, 1, "women card: my request on her node")
check(L.pending(kind: L.womenPendingKind("req.editBirth"), in: womenMine) != nil, true, "women birth tile pending")
check(L.womenPendingKind("req.other"), nil, "«other» has no kind to match")
check(L.pendingTileText, "طلبك قيد المراجعة · افتحه", "pending tile text")

// MARK: ٥) «طلبك عنه» حسب الدور

check(L.requestsSection(canModerateTree: false, allCount: 3, mineCount: 1), .mine, "member sees only his own")
check(L.requestsSection(canModerateTree: false, allCount: 3, mineCount: 0), .none, "member without own request sees nothing")
// المشرف لا يقرّر طلبات الشجرة (canModerateTree = false) — مثل العضو
check(L.requestsSection(canModerateTree: false, allCount: 5, mineCount: 0), .none, "supervisor: no full list")
check(L.requestsSection(canModerateTree: true, allCount: 2, mineCount: 0), .all, "owner/admin/monitor: full list")
check(L.requestsSection(canModerateTree: true, allCount: 0, mineCount: 0), .none, "nothing pending → no section")
check(L.myRequestTitle(female: false), "طلبك عنه", "title for him")
check(L.myRequestTitle(female: true), "طلبك عنها", "title for her")

// MARK: ٦) رقم المرأة

// العضو: لا صفّ ولا «مخفي»
check(L.phoneRow(hasPhone: false, isFemale: true, isPhoneHidden: true, isDeceased: false, viewerIsSelf: false, viewerIsStaff: false),
      .none, "member viewing a woman: no row, no «مخفي»")
check(L.phoneRow(hasPhone: true, isFemale: true, isPhoneHidden: false, isDeceased: false, viewerIsSelf: false, viewerIsStaff: false),
      .none, "woman's number never shown to a member even if a stale flag says visible")
check(L.phoneRow(hasPhone: true, isFemale: true, isPhoneHidden: true, isDeceased: false, viewerIsSelf: false, viewerIsStaff: true),
      .shown(hiddenCaption: true), "staff (owner/admin/monitor/supervisor) see it with «مخفي عن الأعضاء»")
check(L.phoneRow(hasPhone: true, isFemale: true, isPhoneHidden: true, isDeceased: false, viewerIsSelf: true, viewerIsStaff: false),
      .shown(hiddenCaption: true), "she sees her own number with the caption")
check(L.phoneRow(hasPhone: false, isFemale: true, isPhoneHidden: true, isDeceased: false, viewerIsSelf: false, viewerIsStaff: true),
      .none, "staff, no number on file → no row")
check(L.phoneRow(hasPhone: true, isFemale: true, isPhoneHidden: true, isDeceased: true, viewerIsSelf: false, viewerIsStaff: true),
      .none, "deceased → no row")
// الرجل كما كان
check(L.phoneRow(hasPhone: false, isFemale: false, isPhoneHidden: true, isDeceased: false, viewerIsSelf: false, viewerIsStaff: false),
      .hiddenWord, "hidden man → «مخفي» for members (as before)")
check(L.phoneRow(hasPhone: true, isFemale: false, isPhoneHidden: true, isDeceased: false, viewerIsSelf: false, viewerIsStaff: true),
      .shown(hiddenCaption: false), "hidden man → staff see the number (as before)")
check(L.phoneRow(hasPhone: true, isFemale: false, isPhoneHidden: false, isDeceased: false, viewerIsSelf: false, viewerIsStaff: false),
      .shown(hiddenCaption: false), "visible man → everyone")

// MARK: ٧) رسالة الإرسال بلا وعد

check(L.sentMessage().contains("قريباً"), false, "no «soon» promise")
check(L.sentMessage(), "وصل طلبك للإدارة، ويُطبَّق عند موافقتهم. تتابعه أو تسحبه من الإشعارات ← الطلبات المرسلة.", "sent message")
check(L.sentMessage(manual: true).contains("بيدها"), true, "manual variant says by hand")

// MARK: ٨) العمر بعربي صحيح

check(L.yearsText(5), "5 سنوات", "5 → سنوات")
check(L.yearsText(10), "10 سنوات", "10 → سنوات")
check(L.yearsText(11), "11 سنة", "11 → سنة")
check(L.yearsText(1), "سنة واحدة", "1")
check(L.yearsText(2), "سنتان", "2")
check(L.yearsText(41), "41 سنة", "41")
check(L.age(birth: "2021-08-01", death: nil, deceased: false, nowYear: 2026), 5, "Hawra 2021 → 5")
check(L.age(birth: "1940-01-01", death: nil, deceased: true, nowYear: 2026), nil, "deceased without death year → no age")
check(L.age(birth: "1940-01-01", death: "2000", deceased: true, nowYear: 2026), 60, "deceased age to death year")
check(L.age(birth: nil, death: nil, deceased: false, nowYear: 2026), nil, "no birth → no age")
check(L.isYoungGirl(isFemale: false, age: 5), false, "boy is never a young girl")
L10n.isArabic = false
check(L.yearsText(5), "5 yrs", "English plural")
L10n.isArabic = true

// بند ١٥ (المالك ٢٠٢٦-١١-٢٧ «خله عن طريق زوجته أو ابنه المضاف مع طلب أو هو بنفسه»): صورة زوج البنت من خارج العائلة
let hp = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, hv = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
func photoTarget(male: Bool = true, outside: Bool = true, linked: UUID? = hp, viewer: UUID? = hv,
                 wife: Bool = false, son: Bool = false) -> UUID? {
    L.outsideHusbandPhotoTarget(nodeIsMale: male, nodeIsOutside: outside, linkedProfile: linked, viewer: viewer,
                                viewerIsWife: wife, viewerIsSon: son)
}
check(photoTarget(wife: true), hp, "his wife → photo request on his account")
check(photoTarget(son: true), hp, "his son → photo request on his account")
check(photoTarget(), nil, "anyone else → no photo tile")
check(photoTarget(male: false, wife: true), nil, "women never get photos")
check(photoTarget(outside: false, son: true), nil, "family man → his photo is in the family tree, not here")
check(photoTarget(linked: nil, wife: true), nil, "no account → nowhere to apply the photo (no tile)")
check(photoTarget(viewer: hp, wife: true), nil, "the husband himself → from his own profile")
check(L.womenHonesty("req.addPhoto", isFemale: false, hasHusband: false, hasFatherWives: false), .afterApproval,
      "photo applies on approval")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
