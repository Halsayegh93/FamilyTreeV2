// فحص منطق كرت العضو v3 «ب» (Views/Features/Admin/AdminMemberCardLogic.swift، الوحدة V3) — بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/v3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberCardLogic.swift tests/admin-redesign/V3/main.swift \
//     && /private/tmp/claude-501/v3-logic
//
// ما يُفحص (build-card-v3.md «Done when»): قواعد فتح المجموعات وطيّها · ربط الطلب بشارة الصفّ · قاعدة «مرحلة الموافقة» ·
// كلمة «غير مسجّل» · ظهور أزرار الرأس. ومعها: من الطلبات «عنه»، عدّ الأبناء والزوجات، رقاقة الطلبات، «الصلة بالعائلة».
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias C = AdminMemberCardLogic
typealias G = AdminMemberCardLogic.Group
typealias R = AdminMemberCardLogic.Row
typealias A = AdminMemberSheetLogic.HeaderAction
typealias Q = AdminMemberCardLogic.RequestAction
typealias Lin = AdminMemberCardLogic.Lineage

// MARK: ١) المجموعات: مفتوحة أول مرة، الاختيار محفوظ، وما فيه طلب أو «تحت التعديل» لا ينطوي

check(C.isOpen(stored: nil, locked: false), true, "first time (nothing stored) → open")
check(C.isOpen(stored: false, locked: false), false, "folded before → stays folded")
check(C.isOpen(stored: true, locked: false), true, "opened before → open")
check(C.isOpen(stored: false, locked: true), true, "folded before but holds a request → open anyway")
check(C.locked(.data, requestRows: [.birth], pendingRows: []), true, "a request on «الميلاد» locks «البيانات»")
check(C.locked(.family, requestRows: [.birth], pendingRows: []), false, "…but not «العائلة»")
check(C.locked(.family, requestRows: [], pendingRows: [.visibility]), true, "a pending save («تحت التعديل») locks its group")
check(C.locked(.account, requestRows: [], pendingRows: []), false, "nothing pending → can fold")
check(C.canFold(.data, requestRows: [.photo], pendingRows: []), false, "locked group has no fold control")
check(C.canFold(.data, requestRows: [], pendingRows: []), true, "free group folds")
check(R.birth.group, G.data, "الميلاد ∈ البيانات")
check(R.gender.group, G.data, "الجنس ∈ البيانات")
check(R.spouses.group, G.family, "الزوجات ∈ العائلة")
check(R.lineage.group, G.family, "الصلة بالعائلة ∈ العائلة")
check(R.visibility.group, G.family, "الظهور ∈ العائلة")
check(R.phone.group, G.account, "الهاتف ∈ الحساب")
check(R.lastSeen.group, G.account, "آخر دخول ∈ الحساب")
let viewer = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
check(C.storageKey(.family, viewer: viewer), "admin.memberCard.open.family.11111111-2222-3333-4444-555555555555",
      "choice remembered per viewer and group")
check(C.storageKey(.data, viewer: nil), "admin.memberCard.open.data.anon", "no viewer → shared anon key")

// MARK: ٢) الطلب ← شارة «طلب» على الصفّ الذي سيغيّره

check(C.row(type: "tree_edit", action: "edit_birth", womenKind: nil), R.birth, "birth edit → «الميلاد»")
check(C.row(type: "tree_edit", action: "edit_name", womenKind: nil), R.name, "name edit → «الاسم»")
check(C.row(type: "tree_edit", action: "add_photo", womenKind: nil), R.photo, "photo add → «الصورة»")
check(C.row(type: "tree_edit", action: "deceased", womenKind: nil), R.death, "death report (tree) → «الوفاة»")
check(C.row(type: "tree_edit", action: "add_death_date", womenKind: nil), R.death, "death date → «الوفاة»")
check(C.row(type: "tree_edit", action: "edit_phone", womenKind: nil), R.phone, "phone edit → «الهاتف»")
check(C.row(type: "tree_edit", action: "add", womenKind: nil), R.children, "add (child) → «الأبناء والبنات»")
check(C.row(type: "tree_edit", action: "add", womenKind: "edit_birth"), R.birth,
      "women-tree request sent as «add» but really a birth edit → «الميلاد»")
check(C.row(type: "tree_edit", action: "add", womenKind: "wife"), R.spouses, "women-tree wife add → «الزوجة»")
check(C.row(type: "tree_edit", action: "delete", womenKind: nil), nil, "delete → no row badge (strip only)")
check(C.row(type: "tree_edit", action: "other", womenKind: nil), nil, "other → strip only")
check(C.row(type: "photo_suggestion", action: nil, womenKind: nil), R.photo, "photo suggestion → «الصورة»")
check(C.row(type: "deceased_report", action: nil, womenKind: nil), R.death, "deceased report → «الوفاة»")
check(C.row(type: "name_change", action: nil, womenKind: nil), R.name, "name change → «الاسم»")
check(C.row(type: "family_change", action: nil, womenKind: nil), R.name, "family name change → «الاسم»")
check(C.row(type: "phone_change", action: nil, womenKind: nil), R.phone, "phone change → «الهاتف»")
check(C.row(type: "child_add", action: nil, womenKind: nil), R.children, "child add → «الأبناء والبنات»")
check(C.row(type: "lineage_request", action: nil, womenKind: nil), R.lineage, "lineage request → «الصلة بالعائلة»")
check(C.row(type: "contact_message", action: nil, womenKind: nil), nil, "unrelated type → nothing")
check(C.badgeRows([.init(type: "photo_suggestion", action: nil, womenKind: nil),
                   .init(type: "tree_edit", action: "edit_birth", womenKind: nil),
                   .init(type: "tree_edit", action: "delete", womenKind: nil)]),
      Set([R.photo, .birth]), "two badges from three requests (delete has none)")

// MARK: من الطلبات «عنه»
let me = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
let other = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
let daughterNode = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
check(C.isAbout(personId: me, nodeId: me, requestMemberId: me, targetMemberId: nil, womenNodeId: nil), true,
      "member_id = him → about him")
check(C.isAbout(personId: me, nodeId: me, requestMemberId: other, targetMemberId: me.uuidString.lowercased(),
                womenNodeId: nil), true, "details.targetMemberId = him (lowercase from the server) → about him")
check(C.isAbout(personId: me, nodeId: me, requestMemberId: me, targetMemberId: nil, womenNodeId: daughterNode), false,
      "anchored on him but about his daughter's node → shown on her card, not his")
check(C.isAbout(personId: other, nodeId: daughterNode, requestMemberId: me, targetMemberId: nil,
                womenNodeId: daughterNode), true, "women-tree request about her node → on her card")
check(C.isAbout(personId: me, nodeId: me, requestMemberId: other, targetMemberId: nil, womenNodeId: nil), false,
      "someone else → not about him")

// MARK: ٣) قاعدة «مرحلة الموافقة»: داخل المسار = «فتح في الوارد» وحده

check(C.requestActions(stage: nil, workflowOn: false, canApprove: true, canReject: true),
      [Q.approve, .reject, .openInbox], "plain request, full rights → موافقة · رفض · فتح في الوارد")
check(C.requestActions(stage: "specialist_review", workflowOn: false, canApprove: true, canReject: true),
      [Q.openInbox], "request inside an approval stage → only «فتح في الوارد»")
check(C.requestActions(stage: nil, workflowOn: true, canApprove: true, canReject: true),
      [Q.openInbox], "approvals path switched on → decide in the inbox only")
check(C.requestActions(stage: nil, workflowOn: false, canApprove: false, canReject: true),
      [Q.reject, .openInbox], "may reject but not approve → no «موافقة»")
check(C.requestActions(stage: nil, workflowOn: false, canApprove: false, canReject: false),
      [Q.openInbox], "outside the role's domain → open in the inbox only")
check(C.requestActions(stage: "", workflowOn: false, canApprove: true, canReject: true),
      [Q.approve, .reject, .openInbox], "empty stage string = no stage")

// MARK: ٤) «غير مسجّل»

check(C.value(nil), "غير مسجّل", "nil → «غير مسجّل»")
check(C.value("   "), "غير مسجّل", "blank → «غير مسجّل», never blank")
check(C.value(" 27/12/1963 "), "27/12/1963", "value trimmed")
check(C.value(nil, arabic: false), "Not recorded", "English wording")
check(C.part(nil, label: "السيرة"), "السيرة غير مسجّل", "summary part with no value → «السيرة غير مسجّل»")
check(C.part("ذكر", label: "الجنس"), "ذكر", "summary part with value → the value")
check(C.summary(["ميلاد 27/12/1963", "ذكر", "صورة", "السيرة غير مسجّل"]),
      "ميلاد 27/12/1963 · ذكر · صورة · السيرة غير مسجّل", "summary joined with « · »")
check(C.summary(["", "ذكر"]), "ذكر", "empty parts dropped")
check(C.childrenSummary(sons: 1, daughters: 2), "ابن وبنتان", "1 son, 2 daughters")
check(C.childrenSummary(sons: 5, daughters: 2), "5 أبناء وبنتان", "5 sons, 2 daughters")
check(C.childrenSummary(sons: 2, daughters: 0), "ابنان", "2 sons")
check(C.childrenSummary(sons: 0, daughters: 1), "بنت", "1 daughter")
check(C.childrenSummary(sons: 11, daughters: 3), "11 ابناً و3 بنات", "11 sons, 3 daughters")
check(C.childrenSummary(sons: 0, daughters: 0), nil, "no children → nil (row says «غير مسجّل»)")
check(C.spousesSummary(count: 1, female: false), "زوجة", "one wife")
check(C.spousesSummary(count: 2, female: false), "زوجتان", "two wives")
check(C.spousesSummary(count: 3, female: false), "3 زوجات", "three wives")
check(C.spousesSummary(count: 1, female: true), "زوج", "a woman's husband")
check(C.spousesSummary(count: 0, female: false), nil, "none → nil")
check(C.requestsChip(count: 1), "طلب عنه", "chip: one request")
check(C.requestsChip(count: 2), "طلبان عنه", "chip: two requests")
check(C.requestsChip(count: 4), "4 طلبات عنه", "chip: four")
check(C.requestsChip(count: 0), nil, "chip: none → no chip")

// MARK: ٥) أزرار الرأس

check(C.headerActions(canEdit: true, isProfile: true, reachable: true, inBox: false, isDeceased: false,
                      visiblePhone: "+96550001234"), [A.fullProfile, .tree, .call, .whatsapp], "all four")
check(C.headerActions(canEdit: true, isProfile: true, reachable: true, inBox: true, isDeceased: false,
                      visiblePhone: "+96550001234"), [A.fullProfile, .call, .whatsapp],
      "card inside another box → no «في الشجرة»")
check(C.headerActions(canEdit: true, isProfile: true, reachable: false, inBox: false, isDeceased: false,
                      visiblePhone: nil), [A.fullProfile], "not reachable, no visible phone → «الملف الكامل» only")
check(C.headerActions(canEdit: true, isProfile: true, reachable: true, inBox: false, isDeceased: false,
                      visiblePhone: "+965 •••• 4417"), [A.fullProfile, .tree], "masked phone → no call/WhatsApp")
check(C.headerActions(canEdit: true, isProfile: false, reachable: false, inBox: false, isDeceased: false,
                      visiblePhone: nil), [A](), "women-tree node (no profile) → no full editor, no tree jump")
check(C.headerActions(canEdit: false, isProfile: true, reachable: true, inBox: false, isDeceased: true,
                      visiblePhone: "+96550001234"), [A.tree], "read-only viewer, deceased → «في الشجرة» only")

// MARK: «الصلة بالعائلة»

check(C.lineage(isDaughterSon: true, outsideFlag: false, isFemale: false, hasFamilyFather: false), Lin.daughterSon,
      "daughter's son")
check(C.lineage(isDaughterSon: false, outsideFlag: true, isFemale: false, hasFamilyFather: false), Lin.outsideHusband,
      "outside man → «زوج من خارج العائلة»")
check(C.lineage(isDaughterSon: false, outsideFlag: true, isFemale: true, hasFamilyFather: false), Lin.outsideWife,
      "outside woman → «زوجة من خارج العائلة»")
check(C.lineage(isDaughterSon: false, outsideFlag: false, isFemale: false, hasFamilyFather: true), Lin.family,
      "father in the family → «من العائلة»")
check(C.lineage(isDaughterSon: false, outsideFlag: false, isFemale: false, hasFamilyFather: false), nil,
      "nothing known → nil (row «غير مسجّل»)")
check(C.lineageSave(choice: .family, current: .family, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: true), .current, "same as now → nothing to save")
check(C.lineageSave(choice: .family, current: nil, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: true), .linkFather, "no lineage yet → «من العائلة» = link a father")
check(C.lineageSave(choice: .family, current: .daughterSon, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: true), .needsServer, "un-mark a daughter's son → needs the server")
check(C.lineageSave(choice: .daughterSon, current: nil, isProfile: true, hasPendingLineageRequest: true,
                    isPendingJoin: false, isMale: true), .decideRequest, "pending lineage request → decide it")
check(C.lineageSave(choice: .daughterSon, current: nil, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: true, isMale: true), .approveJoin, "pending join, man → accept as daughter's son")
check(C.lineageSave(choice: .daughterSon, current: .family, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: true), .needsServer, "family man → daughter's son needs the server")
check(C.lineageSave(choice: .outsideHusband, current: nil, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: true), .needsServer, "mark outside husband → needs the server")
check(C.lineageSave(choice: .outsideWife, current: .family, isProfile: false, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: false), .needsServer, "mark outside wife → needs the server")

// MARK: ترتيب الأبناء والبنات — قائمة واحدة، والحفظ لكل جدول بترتيبه
check(C.partitionChildren(["s1", "d1", "s2", "d2"], isSon: { $0.hasPrefix("s") }).sons, ["s1", "s2"],
      "sons keep their relative order")
check(C.partitionChildren(["d2", "s1", "d1", "s2"], isSon: { $0.hasPrefix("s") }).daughters, ["d2", "d1"],
      "daughters keep their relative order")

// MARK: «إجراءات الإدارة» v3: الهاتف أولاً، والشريط وحده يرسم البطاقة
typealias S = AdminMemberSheetLogic
let allCommands = S.AccountCommands(suspend: true, ban: true, delete: true)
let noCommands = S.AccountCommands(suspend: false, ban: false, delete: false)
check(S.adminCard(isSelf: false, living: true, photo: true, register: false, devices: true, commands: allCommands,
                  phone: true, requests: true)?.items, [.phone, .photo, .devices, .suspend, .ban, .delete],
      "phone (moved from «العضو») first, delete last")
check(S.adminCard(isSelf: false, living: true, photo: false, register: false, devices: false, commands: noCommands,
                  phone: false, requests: true)?.items, [S.AdminItem](), "requests strip alone → the card is drawn")
check(S.adminCard(isSelf: true, living: true, photo: true, register: true, devices: true, commands: allCommands,
                  phone: true, requests: true), nil, "own card → no admin card even with requests")
check(S.adminCard(isSelf: false, living: false, photo: true, register: true, devices: true, commands: allCommands,
                  phone: true, requests: false)?.items, [.photo, .delete], "deceased → no phone row")
check(S.adminCard(isSelf: false, living: true, photo: false, register: false, devices: false, commands: noCommands),
      nil, "old call (no phone, no strip) unchanged → no empty card")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
