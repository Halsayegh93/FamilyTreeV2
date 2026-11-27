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

check(C.requestActions(type: "tree_edit", stage: nil, workflowOn: false, canApprove: true, canReject: true),
      [Q.approve, .reject, .openInbox], "plain request, full rights → موافقة · رفض · فتح في الوارد")
// قيم `ApprovalStage` الحقيقية (`admin_requests.stage`): review · info · approve · execute
for stage in ["review", "info", "approve", "execute"] {
    check(C.requestActions(type: "tree_edit", stage: stage, workflowOn: false, canApprove: true, canReject: true),
          [Q.openInbox], "request in stage «\(stage)» → only «فتح في الوارد»")
}
check(C.requestActions(type: "tree_edit", stage: nil, workflowOn: true, canApprove: true, canReject: true),
      [Q.openInbox], "approvals path switched on → decide in the inbox only")
check(C.requestActions(type: "tree_edit", stage: nil, workflowOn: false, canApprove: false, canReject: true),
      [Q.reject, .openInbox], "may reject but not approve → no «موافقة»")
check(C.requestActions(type: "tree_edit", stage: nil, workflowOn: false, canApprove: false, canReject: false),
      [Q.openInbox], "outside the role's domain → open in the inbox only")
check(C.requestActions(type: "tree_edit", stage: "", workflowOn: false, canApprove: true, canReject: true),
      [Q.approve, .reject, .openInbox], "empty stage string = no stage")
// الشريط يقرّر خمسة أنواع فقط (`boxDecidableTypes` — نفس مربّع الإشعار)، والباقي «فتح في الوارد» وحده
check(C.boxDecidableTypes, Set(["tree_edit", "deceased_report", "name_change", "photo_suggestion", "news_report"]),
      "box-decidable types = the five the notification box decides")
for type in ["tree_edit", "deceased_report", "name_change", "photo_suggestion"] {
    check(C.requestActions(type: type, stage: nil, workflowOn: false, canApprove: true, canReject: true),
          [Q.approve, .reject, .openInbox], "\(type) → decided here")
}
for type in ["phone_change", "lineage_request", "child_add", "family_change", "relative_add", "join_request"] {
    check(C.requestActions(type: type, stage: nil, workflowOn: false, canApprove: true, canReject: true),
          [Q.openInbox], "\(type) → «فتح في الوارد» only, even for someone who may approve")
}
// م١: على ورقتك لا شريط ولا شارة «طلب» (الطلبات عنك يعالجها غيرك)
check(C.showsRequests(isSelf: true, seesRequests: true), false, "own card → no requests about you")
check(C.showsRequests(isSelf: false, seesRequests: true), true, "someone else's card → requests about them")
check(C.showsRequests(isSelf: false, seesRequests: false), false, "viewer who doesn't decide tree requests → none")

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
check(C.childrenSummary(sons: 0, daughters: 0), nil, "no children → nil (the summary and the row use `childrenValue`)")
// م١٠: الملخّص والصفّ بكلمة واحدة
check(C.childrenValue(sons: 0, daughters: 0), "لا أبناء مسجّلون", "no children → «لا أبناء مسجّلون» (summary and row)")
check(C.childrenValue(sons: 1, daughters: 2), "ابن وبنتان", "children → the count wording")
check(C.childrenValue(sons: 0, daughters: 0, arabic: false), "No children recorded", "English")
check(C.spousesSummary(count: 1, female: false), "زوجة", "one wife")
check(C.spousesSummary(count: 2, female: false), "زوجتان", "two wives")
check(C.spousesSummary(count: 3, female: false), "3 زوجات", "three wives")
check(C.spousesSummary(count: 1, female: true), "زوج", "a woman's husband")
check(C.spousesSummary(count: 0, female: false), nil, "none → nil")
check(C.requestsChip(count: 1), "طلب عنه", "chip: one request")
check(C.requestsChip(count: 2), "طلبان عنه", "chip: two requests")
check(C.requestsChip(count: 4), "4 طلبات عنه", "chip: four")
check(C.requestsChip(count: 0), nil, "chip: none → no chip")

// MARK: م١٠ التأنيث: «غير مسجّلة» بعد المؤنث، و«عنها» على ورقة المرأة
check(C.notRecorded(), "غير مسجّل", "masculine default")
check(C.notRecorded(feminine: true), "غير مسجّلة", "feminine → «غير مسجّلة»")
check(C.value(nil, feminine: true), "غير مسجّلة", "«الأم» / «الزوجة» / «السيرة» / «الوفاة» with no value")
check(C.value("سهيله", feminine: true), "سهيله", "value kept as is")
check(C.part(nil, label: "السيرة", feminine: true), "السيرة غير مسجّلة", "summary: «السيرة غير مسجّلة»")
check(C.part(nil, label: "الزوجة", feminine: true), "الزوجة غير مسجّلة", "summary: «الزوجة غير مسجّلة»")
check(C.part(nil, label: "الأب"), "الأب غير مسجّل", "summary: «الأب غير مسجّل» stays masculine")
check(C.notRecorded(arabic: false, feminine: true), "Not recorded", "English has no gender")
check(C.aboutWord(female: false), "عنه", "«عنه» for a man")
check(C.aboutWord(female: true), "عنها", "«عنها» for a woman")
check(C.requestsChip(count: 1, female: true), "طلب عنها", "chip on a woman's card")
check(C.requestsChip(count: 2, female: true), "طلبان عنها", "two on a woman's card")
check(C.requestsTitle(count: 0, female: true), "طلبات عنها", "strip title, none")
check(C.requestsTitle(count: 3, female: false), "طلبات عنه · 3", "strip title with the count")
check(C.noRequests(female: true), "لا طلبات عنها الآن.", "empty strip on a woman's card")
check(C.noRequests(female: false), "لا طلبات عنه الآن.", "empty strip on a man's card")
check(C.lineageTitle(female: true), "صلتها بالعائلة", "«صلتها بالعائلة»")
check(C.lineageTitle(female: false), "صلته بالعائلة", "«صلته بالعائلة»")
// الصورة: الكلمتان القديمتان
check(C.photoValue(hasPhoto: true, unavailable: false), "موجودة", "photo → «موجودة»")
check(C.photoValue(hasPhoto: false, unavailable: false), "بلا صورة", "no photo → «بلا صورة»")
check(C.photoValue(hasPhoto: false, unavailable: true), "لا توجد صورة لهذا العضو", "marked unavailable → «لا توجد صورة لهذا العضو»")
// الحساب: كلمة الرأس نفسها، و«لم يسجّل الدخول بعد» بدل «آخر دخول غير مسجّل»
check(C.lastSeen(nil, hasAccount: false, female: false), "لم يسجّل الدخول بعد", "never signed in (man)")
check(C.lastSeen(nil, hasAccount: false, female: true), "لم تسجّل الدخول بعد", "never signed in (woman)")
check(C.lastSeen("2/11/2026", hasAccount: true, female: false), "2/11/2026", "last sign-in date")
check(C.lastSeen(nil, hasAccount: true, female: false), "غير معروف", "account, date unknown → «غير معروف»")
check(C.accountSummary(statusWord: "بدون حساب", lastSeen: nil, hasAccount: false, female: false),
      "بدون حساب · لم يسجّل الدخول بعد", "summary follows the header word")
check(C.accountSummary(statusWord: "مسجّل", lastSeen: "2/11/2026", hasAccount: true, female: false),
      "مسجّل · آخر دخول 2/11/2026", "registered summary")
check(C.noAccountWord(), "بدون حساب", "one word for «no account» across the card (= header)")

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
                    isPendingJoin: false, isMale: true), .automatic, "outside husband → computed from the links (ت٥)")
check(C.lineageSave(choice: .outsideWife, current: .family, isProfile: false, hasPendingLineageRequest: false,
                    isPendingJoin: false, isMale: false), .automatic, "outside wife → computed from the links (ت٥)")
// م٣: داخل مسار الموافقات = «فتح في الوارد» بدل القرار من هنا
check(C.lineageSave(choice: .daughterSon, current: nil, isProfile: true, hasPendingLineageRequest: true,
                    requestInWorkflow: true, isPendingJoin: false, isMale: true), .openInbox,
      "pending lineage request inside the approvals path → open in the inbox")
check(C.lineageSave(choice: .daughterSon, current: nil, isProfile: true, hasPendingLineageRequest: false,
                    isPendingJoin: true, joinInWorkflow: true, isMale: true), .openInbox,
      "pending join inside the approvals path → open in the inbox")
// ت٥: خيارات لا تنطبق على جنسه مخفية
check(C.lineageOptions(female: false), [Lin.family, .daughterSon, .outsideHusband], "a man: family · daughter's son · outside husband")
check(C.lineageOptions(female: true), [Lin.family, .outsideWife], "a woman: family · outside wife")

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

// MARK: ح٢ ورقتك: لا أوامر عائلة ولا إدارة على نفسك (الجنس، الزوجات، الأبناء، الظهور، الصلة، الأب)
check(C.familyAdmin(canEdit: true, memberId: me, viewerId: me), false, "own card → family commands locked")
check(C.familyAdmin(canEdit: true, memberId: other, viewerId: me), true, "someone else, may edit → family commands")
check(C.familyAdmin(canEdit: false, memberId: other, viewerId: me), false, "read-only viewer → none")
check(C.familyAdmin(canEdit: true, memberId: other, viewerId: nil), true, "viewer not known yet → permission alone")
// رقاقات الناقص على ورقتك: البيانات فقط (لا الجنس ولا الأب ولا الإظهار ولا الرقم)
typealias Mi = AdminMemberSheetLogic.Missing
check(AdminMemberSheetLogic.missingChips(gaps: [.noBirth, .noGender], problems: [.orphan, .hidden, .dupPhone],
                                         canEdit: true, ownCard: true), [Mi.noBirth],
      "own card → only the birth chip")
check(AdminMemberSheetLogic.missingChips(gaps: [.noBirth, .noGender], problems: [.orphan], canEdit: true),
      [Mi.noBirth, .noGender, .orphan], "someone else → every chip (unchanged)")

// MARK: ح١ نقل الجنس: من له حساب لا يُنقل (السيرفر لا يمنعه — النقل إلى أنثى يحذف ملفه)
check(C.appAccount(role: "member", isViewer: false, frozen: false, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: true, storeLoaded: true), true, "in the accounts store → has an account")
check(C.appAccount(role: "monitor", isViewer: false, frozen: false, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: false), true, "admin role → has an account (store not needed)")
check(C.appAccount(role: "pending", isViewer: false, frozen: false, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: true), true, "pending join → signed up, has a login")
check(C.appAccount(role: "member", isViewer: true, frozen: false, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: true), true, "yourself → has an account")
check(C.appAccount(role: "member", isViewer: false, frozen: true, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: true), true, "suspended account → has an account")
check(C.appAccount(role: "member", isViewer: false, frozen: false, looksRegistered: true, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: true), true, "accepted the terms / registration platform → login")
check(C.appAccount(role: "member", isViewer: false, frozen: false, looksRegistered: false, linkedLogin: true,
                   inAccountsStore: false, storeLoaded: true), true, "women's-tree node linked to a login → account")
check(C.appAccount(role: "member", isViewer: false, frozen: false, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: false), nil, "accounts store not loaded → unknown")
check(C.appAccount(role: "member", isViewer: false, frozen: false, looksRegistered: false, linkedLogin: false,
                   inAccountsStore: false, storeLoaded: true), false, "tree-only member → no account")
typealias GB = AdminMemberCardLogic.GenderMoveBlock
check(C.genderMoveBlock(toFemale: true, account: true, hasFather: true, sons: 0, daughters: 0, wives: 0,
                        hasHusband: false, fatherInFamily: true), GB.account, "young registered man, no kids → blocked")
check(C.genderMoveBlock(toFemale: true, account: nil, hasFather: true, sons: 0, daughters: 0, wives: 0,
                        hasHusband: false, fatherInFamily: true), GB.unverified, "store not loaded → «تعذّر التحقق»")
check(C.genderMoveBlock(toFemale: false, account: true, hasFather: true, sons: 0, daughters: 0, wives: 0,
                        hasHusband: false, fatherInFamily: true), GB.account, "a woman with an account → blocked too")
check(C.genderMoveBlock(toFemale: true, account: false, hasFather: false, sons: 0, daughters: 0, wives: 0,
                        hasHusband: false, fatherInFamily: false), GB.noFather, "no father → link him first")
check(C.genderMoveBlock(toFemale: true, account: false, hasFather: true, sons: 2, daughters: 1, wives: 1,
                        hasHusband: false, fatherInFamily: true), GB.linked(sons: 2, daughters: 1, wives: 1),
      "linked children or wives → unlink first")
check(C.genderMoveBlock(toFemale: false, account: false, hasFather: true, sons: 0, daughters: 0, wives: 0,
                        hasHusband: true, fatherInFamily: true), GB.linkedHusband, "a woman with a linked husband")
check(C.genderMoveBlock(toFemale: false, account: false, hasFather: true, sons: 0, daughters: 0, wives: 0,
                        hasHusband: false, fatherInFamily: false), GB.fatherOutside, "her father isn't a family man")
check(C.genderMoveBlock(toFemale: true, account: false, hasFather: true, sons: 0, daughters: 0, wives: 0,
                        hasHusband: false, fatherInFamily: true), nil, "tree-only son, no links → may move")
check(C.genderMoveLoses(toFemale: true).contains("الحساب"), false, "«يُحذف» no longer lists «الحساب»")
check(C.genderMoveLoses(toFemale: true), "الصورة · رقم الهاتف · السيرة · الدور", "what a move to female removes")

// MARK: ح٣ «فك الربط» للابن
check(C.sonUnlinkAllowed(childCount: 0), true, "a son without children → unlink (asks first, honest text)")
check(C.sonUnlinkAllowed(childCount: 3), false, "a son with children → disabled; change the father from his card")

// MARK: م٥ «ربط زوج من العائلة»: لا محارمها
let G0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a0")! // جدّها
let F0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")! // أبوها
let U0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")! // عمّها
let C0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a3")! // ابن عمّها
let B0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a4")! // أخوها
let N0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a5")! // ابن أخيها
let S0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a6")! // ابنها
let SS = UUID(uuidString: "00000000-0000-0000-0000-0000000000a7")! // ابن ابنها
let X0 = UUID(uuidString: "00000000-0000-0000-0000-0000000000a8")! // غريب
let fatherOf: [UUID: UUID] = [F0: G0, U0: G0, C0: U0, B0: F0, N0: B0, SS: S0]
let blocked = C.husbandBlocked(fatherId: F0, sonIds: [S0], fatherOf: fatherOf)
check(blocked, Set([G0, F0, U0, B0, N0, S0, SS]), "father chain, uncles, brothers and nephews, her sons and grandsons")
check(blocked.contains(C0), false, "her cousin may be her husband")
check(blocked.contains(X0), false, "an unrelated man may be her husband")
check(C.husbandBlocked(fatherId: nil, sonIds: [], fatherOf: fatherOf), Set<UUID>(), "no father, no sons → nobody blocked")
check(C.husbandEligible(isMale: true, isPending: false, hasName: true, isDeceased: false, age: 30, minAge: 18), true,
      "a living adult man")
check(C.husbandEligible(isMale: true, isPending: false, hasName: true, isDeceased: false, age: 12, minAge: 18), false,
      "a minor → hidden")
check(C.husbandEligible(isMale: true, isPending: false, hasName: true, isDeceased: true, age: 70, minAge: 18), false,
      "the deceased → hidden")
check(C.husbandEligible(isMale: true, isPending: false, hasName: true, isDeceased: false, age: nil, minAge: 18), true,
      "birth date unknown → not judged by age")
check(C.husbandEligible(isMale: true, isPending: true, hasName: true, isDeceased: false, age: 30, minAge: 18), false,
      "pending join → hidden")

// MARK: م٦ بعد نقل الجنس: الكرت يتبع المعرّف الجديد
let oldId = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!
let newId = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!
let newer = UUID(uuidString: "00000000-0000-0000-0000-0000000000b3")!
check(C.resolved(oldId, moved: [oldId: newId]), newId, "moved → the card shows the new record")
check(C.resolved(oldId, moved: [oldId: newId, newId: newer]), newer, "moved twice → the latest record")
check(C.resolved(X0, moved: [oldId: newId]), X0, "not moved → unchanged")
check(C.resolved(oldId, moved: [oldId: newId, newId: oldId]), newId, "a loop never hangs (stops before revisiting)")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
