// فحص سلوك «تصفية» (الوحدة F3، طلب المالك ٢٠٢٦-١١-٢٦) — طقم الإدارة (`AdminFilterKit.swift`) ومنطق الصفحات بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/f3-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminFilterKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxFilters.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxView.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminWomenPanel.swift tests/admin-redesign/F3/main.swift \
//     && /private/tmp/claude-501/f3-logic
//
// ما يُفحص (f3-filters.md «Done when»): OR داخل المجموعة و AND بين المجموعات · إزالة شريحة تُبقي الباقي · «الكل» يمسح
// مجموعته · الأعداد تتبع المجموعات الأخرى · روابط الدفع والهبوط تضع الشرائح.
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true

// MARK: - «الوارد» — المنطق

typealias L = AdminInboxLogic
typealias IF = L.Filters

// ٨ طلبات: أعضاء (انضمام عاجل · رقم · وفاة عاجل) · الشجرة (ابن · إضافة متأخر · ابن متأخر) · محتوى (خبر · صورة)
let inbox: [L.Fact] = [
    L.Fact(kind: .joinRequests, source: .registration, inFlow: true, waiting: true, urgent: true),   // 0
    L.Fact(kind: .children, source: .profile, inFlow: true, waiting: true),                          // 1
    L.Fact(kind: .treeAdd, source: .familyTree, inFlow: true, late: true),                           // 2
    L.Fact(kind: .phone, source: .profile, inFlow: true, waiting: true),                             // 3
    L.Fact(kind: .news, source: .content, inFlow: true),                                             // 4
    L.Fact(kind: .children, source: .familyTree, inFlow: true, waiting: true, late: true),           // 5
    L.Fact(kind: .deceased, source: .familyTree, inFlow: true, waiting: true, urgent: true),         // 6
    L.Fact(kind: .photos, source: .content, inFlow: true, waiting: true),                            // 7
]
func n(_ f: IF) -> Int { L.count(inbox, f, workflowOn: true) }

// OR داخل المجموعة
check(n(IF()), 8, "inbox: nothing picked = everything")
check(n(IF(statuses: [.urgent])), 2, "inbox: urgent alone")
check(n(IF(statuses: [.late])), 2, "inbox: late alone")
check(n(IF(statuses: [.urgent, .late])), 4, "inbox OR: urgent or late = 2 + 2")
check(n(IF(statuses: [], groups: [.members, .content])), 5, "inbox OR: members or content = 3 + 2")
check(n(IF(statuses: [], sources: [.profile, .content])), 4, "inbox OR: two sources")
// AND بين المجموعات
check(n(IF(statuses: [.urgent, .late], groups: [.tree])), 2, "inbox AND: (urgent|late) × tree = the two late tree requests")
check(n(IF(statuses: [.waiting], groups: [.tree], sources: [.familyTree])), 1, "inbox AND: three groups together")
check(n(IF(statuses: [.urgent], groups: [.content])), 0, "inbox AND: a zero combination stays countable")
// «النوع» يضيّق مجموعته وحدها: ابن من «الشجرة» لا يخفي «أعضاء» المختارة معها
check(n(IF(statuses: [], groups: [.tree], kinds: [.children])), 2, "inbox kind: children inside tree")
check(n(IF(statuses: [], groups: [.tree, .members], kinds: [.children])), 5,
      "inbox kind narrows its own group only: 2 children + 3 members")
check(n(IF(statuses: [], kinds: [.children, .news])), 3, "inbox kinds from two groups: OR, each brings its group")
check(IF(statuses: [], kinds: [.children, .news]).groups, [.tree, .content], "inbox: a picked kind brings its group")
// «بانتظار قرارك» والمسار مطفأ = كل طلب (كما كان)
check(L.count(inbox, IF(statuses: [.waiting, .urgent]), workflowOn: false), 8, "inbox: workflow off, waiting = all")

// الأعداد تتبع المجموعات الأخرى: عدد الخيار = النتيجة لو اختير وحده في مجموعته مع بقية الاختيارات
let treeOnly = IF(statuses: [], groups: [.tree])
check(n(L.probe(treeOnly, status: .late)), 2, "count follows group: late within tree = 2")
check(n(L.probe(treeOnly, status: .urgent)), 0, "count follows group: urgent within tree = 0 (grey, still pickable)")
check(n(L.probe(IF(), status: .urgent)), 2, "count without other picks: urgent = 2")
check(n(L.probe(IF(statuses: [.waiting]), status: .urgent)), 2,
      "count of an option ignores its own group's picks (urgent alone, not urgent ∩ waiting)")
check(n(L.probe(IF(statuses: [.urgent]), group: .members)), 2, "group count follows status: urgent members = 2")
check(n(L.probe(IF(statuses: [], groups: [.tree, .members], kinds: [.children]), group: .tree)), 2,
      "group count keeps its own kinds: tree narrowed to children = 2")
check(n(L.probe(IF(statuses: [.late], groups: [.tree]), kind: .children)), 1, "kind count follows status: late children = 1")

// التطبيع: إزالة المجموعة تزيل أنواعها
var nf = IF(statuses: [], groups: [.tree, .members], kinds: [.children, .phone])
nf.groups.remove(.tree)
L.normalize(&nf)
check(nf.kinds, [.phone], "inbox: removing «الشجرة» drops its kinds, keeps the members kind")

// MARK: - الطقم: شرائح، إزالة واحدة، «الكل»، الأعداد

let statusTitle: [L.Status: String] = [.all: "كل الطلبات", .waiting: "بانتظار قرارك", .urgent: "عاجل", .late: "متأخر"]
let groupTitle: [L.Group: String] = [.members: "أعضاء", .tree: "الشجرة", .content: "محتوى ونشاط"]
let kindTitle: [L.Kind: String] = [.children: "أبناء", .treeAdd: "إضافة", .joinRequests: "طلبات الانضمام", .phone: "جوال",
                                   .deceased: "وفاة", .news: "أخبار", .photos: "صور مقترحة"]

/// نفس بناء «الوارد» (`AdminAllRequestsView.inboxFilterSet`) بأسماء ثابتة — الحالة · المجموعة · النوع (بعد المجموعة) · المصدر
let inboxSet = AdminFilterSet<IF>(noun: AdminInboxText.requestsNoun, normalize: L.normalize,
                                  resultCount: { n($0) }) { s in
    var groups: [AdminFilterGroup<IF>] = []
    groups.append(.choices("status", title: "الحالة", values: \.statuses, allTitle: statusTitle[.all]!,
                           options: [L.Status.waiting, .urgent, .late].map {
                               AdminFilterOption($0, statusTitle[$0]!, count: n(L.probe(s, status: $0)))
                           }))
    groups.append(.choices("group", title: "المجموعة", values: \.groups,
                           options: L.Group.allCases.map { AdminFilterOption($0, groupTitle[$0]!, count: n(L.probe(s, group: $0))) }))
    if !s.groups.isEmpty {
        let kinds = L.Kind.allCases.filter { s.groups.contains($0.group) && kindTitle[$0] != nil }
        groups.append(.choices("kind", title: "النوع", values: \.kinds,
                               options: kinds.map { AdminFilterOption($0, kindTitle[$0]!, count: n(L.probe(s, kind: $0))) }))
    }
    groups.append(.choices("source", title: "المصدر", values: \.sources,
                           options: [L.Source.registration, .profile, .familyTree, .content].map {
                               AdminFilterOption($0, $0.rawValue, count: n(L.probe(s, source: $0)))
                           }))
    return groups
}

func chips(_ s: IF) -> [String] { inboxSet.snapshot(s).items.map(\.title) }
func chip(_ s: IF, _ title: String) -> AdminFilterSnapshot<IF>.Item? { inboxSet.snapshot(s).items.first { $0.title == title } }
func group(_ s: IF, _ id: String) -> AdminFilterGroup<IF>? { inboxSet.groups(s).first { $0.id == id } }

// شريحة لكل خيار مختار، بعددها
let picked = IF(statuses: [.waiting, .urgent], groups: [.tree])
check(chips(picked), ["بانتظار قرارك", "عاجل", "الشجرة"], "chips: one per picked option, in sheet order")
check(inboxSet.activeCount(picked), 3, "«تصفية» badge = number of picks")
check(chip(picked, "عاجل")?.count, "0", "chip shows its count (urgent within tree = 0)")
check(chip(picked, "الشجرة")?.count, "2", "group chip count follows the status picks (waiting|urgent in tree = 2)")
check(inboxSet.snapshot(picked).result, 2, "result: (waiting|urgent) × tree = 2")
check(chips(IF()), [], "no picks: no chips")
check(inboxSet.activeCount(IF()), 0, "no picks: badge hidden")

// إزالة شريحة واحدة تُبقي الباقي
if let urgent = chip(picked, "عاجل") {
    let after = inboxSet.applying(urgent.remove, to: picked)
    check(after.statuses, [.waiting], "✕ «عاجل»: «بانتظار قرارك» stays")
    check(after.groups, [.tree], "✕ «عاجل»: the group chip stays")
    check(chips(after), ["بانتظار قرارك", "الشجرة"], "✕ removes exactly one chip")
} else {
    check(false, true, "the «عاجل» chip exists")
}
let deep = IF(statuses: [], groups: [.tree, .members], kinds: [.children])
check(chips(deep), ["أعضاء", "الشجرة", "أبناء"], "chips: groups then their kinds")
if let tree = chip(deep, "الشجرة") {
    let after = inboxSet.applying(tree.remove, to: deep)
    check(after, IF(statuses: [], groups: [.members]), "✕ «الشجرة» also drops its kind; «أعضاء» stays")
}
if let kid = chip(deep, "أبناء") {
    check(inboxSet.applying(kid.remove, to: deep), IF(statuses: [], groups: [.tree, .members]),
          "✕ the kind leaves both groups")
}

// صفّ في الورقة: يضيف ثم يزيل (اختيار متعدّد)
if let statusGroup = group(IF(), "status") {
    check(statusGroup.selection == .multiple, true, "status group is multi-select")
    let late = statusGroup.rows.first { $0.title == "متأخر" }!
    let once = inboxSet.applying(late.select, to: IF(statuses: [.urgent]))
    check(once.statuses, [.urgent, .late], "tap an option: added next to the others (OR)")
    check(inboxSet.applying(late.select, to: once).statuses, [.urgent], "tap it again: removed alone")
    check(late.isSelected(once), true, "row shows selected")
}

// «الكل» يمسح مجموعته وحدها، وعدده النتيجة بلاها
let mixed = IF(statuses: [.urgent, .late], groups: [.tree], sources: [.familyTree])
if let statusGroup = group(mixed, "status") {
    check(statusGroup.allTitle, "كل الطلبات", "«الكل» is the group's first row")
    check(statusGroup.isActive(mixed), true, "group with picks is on («الكل» not ticked)")
    let cleared = inboxSet.applying(statusGroup.clear, to: mixed)
    check(cleared, IF(statuses: [], groups: [.tree], sources: [.familyTree]), "«الكل» clears only its group")
    check(statusGroup.isActive(cleared), false, "after «الكل»: the group is off («الكل» ticked)")
    check(inboxSet.allCount(statusGroup, in: mixed), 2, "«الكل» count = result without this group (tree × familyTree)")
}

// الأعداد في الورقة تتبع المجموعات الأخرى
let statusRows = { (s: IF) in group(s, "status")!.rows.map(\.count) }
check(statusRows(IF()), [6, 2, 2], "status counts with nothing else picked")
check(statusRows(IF(statuses: [], groups: [.tree])), [2, 0, 2], "status counts follow «الشجرة»")
check(statusRows(IF(statuses: [.urgent], groups: [.tree])), [2, 0, 2], "status counts ignore the status picks themselves")
check(group(IF(statuses: [.urgent]), "group")!.rows.map(\.count), [2, 0, 0], "group counts follow «عاجل»")
check(group(IF(), "kind") == nil, true, "«النوع» appears only after a group is picked")
check(group(IF(statuses: [], groups: [.content]), "kind")!.rows.map(\.title), ["أخبار", "صور مقترحة"],
      "«النوع» lists the kinds of the picked groups")

// MARK: - روابط الدفع والهبوط تضع الشرائح

let monitorKinds: Set<String> = Set(L.Kind.allCases.map(\.rawValue))
let pushChild = IF(landing: AdminInboxLanding(pushKind: "child_add").clamped(toKinds: monitorKinds))
check(chips(pushChild), ["الشجرة", "أبناء"], "push child_add (.openAdminReviewForKind) → «الشجرة» + «أبناء» chips")
check(n(pushChild), 2, "push child_add lands on the children requests")
let fromToday = IF(status: .waiting)   // `AdminAllRequestsView(initialFilter: .waiting)` — «بانتظار قرارك» من «اليوم»
check(chips(fromToday), ["بانتظار قرارك"], "initialFilter: .waiting → a normal removable chip")
if let waitingChip = chip(fromToday, "بانتظار قرارك") {
    check(inboxSet.applying(waitingChip.remove, to: fromToday), IF(), "the default chip removes like any other")
}
check(chips(IF(landing: AdminInboxLanding(status: .urgent, source: .profile))), ["عاجل", "profile"],
      "landing status + source → two chips")
check(chips(IF(landing: AdminInboxLanding(pushKind: "tree_edit"))), ["الشجرة"], "tree_edit push → the group chip")

// MARK: - «رسائل الأعضاء»

typealias M = AdminInboxMessageLogic
let messages: [M.Fact] = [
    M.Fact(unread: true, pending: true, handled: false, today: true, kind: "شكوى"),
    M.Fact(unread: true, pending: false, handled: true, today: false, kind: "استفسار"),
    M.Fact(unread: false, pending: true, handled: false, today: false, kind: "اقتراح"),
    M.Fact(unread: false, pending: false, handled: true, today: false, kind: "شكوى"),
    M.Fact(unread: false, pending: true, handled: false, today: true, kind: "استفسار"),
]
check(M.count(messages, M.Filters(statuses: [.unread, .handled])), 3, "messages OR: unread or handled")
check(M.count(messages, M.Filters(statuses: [], kinds: ["شكوى", "اقتراح"])), 3, "messages OR: two kinds")
check(M.count(messages, M.Filters(statuses: [.today], kinds: ["شكوى", "استفسار"])), 2, "messages AND: today × (two kinds)")
check(M.Filters(status: .unread), M.Filters(statuses: [.unread]), "messages: header «غير مقروءة» = one pick")
check(M.Filters(status: .all, kind: M.allKinds).isEmpty, true, "messages: «الكل» = no pick")

// MARK: - «العائلة»

typealias A = AdminMembersLogic
// ٢,٣٦٢ رجلاً كما في mock 5: ١٢٣ لهم حساب (أحياء)، ١,٨٥٧ أحياء بلا حساب، ٣٨٢ متوفى بلا حساب
let tally = A.Tally(aliveLogin: 123, aliveNoLogin: 1_857, deadLogin: 0, deadNoLogin: 382)
check(tally.count(accounts: [.with, .without], lives: []), 2_362, "family OR: both accounts = everyone")
check(tally.count(accounts: [], lives: [.alive, .deceased]), 2_362, "family OR: both statuses = everyone")
check(tally.count(accounts: [.without], lives: [.deceased]), 382, "family AND: no account × deceased")
check(tally.count(accounts: [.with], lives: [.alive, .deceased]), 123, "family AND: with account × (alive|deceased)")
check(tally.count(accounts: [.with], lives: [.alive]), tally.count(account: .with, life: .alive),
      "family: one pick each = the old single filters")
check(tally.shown(accounts: [.with], lives: [], accountsReady: false), nil, "family: account counts wait for the lists («—»)")
check(tally.shown(accounts: [], lives: [.alive], accountsReady: false), 1_980, "family: status alone needs no account lists")
check(A.matches(deceased: true, hasLogin: false, accounts: [.with, .without], lives: [.deceased]), true,
      "family matches: both accounts × deceased")

struct FamilyPicks: Equatable {
    var accounts: Set<A.Account> = []
    var lives: Set<A.Life> = []
}
let accountTitle: [A.Account: String] = [.with: "لهم حساب", .without: "بلا حساب"]
let lifeTitle: [A.Life: String] = [.alive: "الأحياء", .deceased: "المتوفون"]
/// نفس بناء «العائلة» (`AdminMembersPage.filterSet`) على جدول ٢×٢ واحد
let familySet = AdminFilterSet<FamilyPicks>(resultCount: { tally.count(accounts: $0.accounts, lives: $0.lives) }) { s in
    [
        .choices("account", title: "الحساب", values: \.accounts, options: [A.Account.with, .without].map {
            AdminFilterOption($0, accountTitle[$0]!, count: tally.count(accounts: [$0], lives: s.lives))
        }),
        .choices("life", title: "الحالة", values: \.lives, options: [A.Life.alive, .deceased].map {
            AdminFilterOption($0, lifeTitle[$0]!, count: tally.count(accounts: s.accounts, lives: [$0]))
        }),
    ]
}
let deadOnly = FamilyPicks(lives: [.deceased])
check(familySet.groups(deadOnly)[0].rows.map(\.count), [0, 382], "family counts follow «الحالة»: accounts among the deceased")
check(familySet.allCount(familySet.groups(deadOnly)[0], in: deadOnly), 382, "family «الكل» in «الحساب» = deceased total")
let registered = A.opening(chip: "registered", sub: "all", womenOutside: false)
let fromLink = FamilyPicks(accounts: A.picks(registered.account), lives: A.picks(registered.life))
check(familySet.snapshot(fromLink).items.map(\.title), ["لهم حساب", "الأحياء"], "old link «مسجّلون» → two chips")
check(familySet.snapshot(fromLink).items.map(\.count), ["123", "123"], "link chips carry their counts")
if let alive = familySet.snapshot(fromLink).items.last {
    check(familySet.applying(alive.remove, to: fromLink), FamilyPicks(accounts: [.with]), "✕ «الأحياء» keeps «لهم حساب»")
}
let landed = A.opening(landing: AdminMembersLanding(account: .without))
check(A.picks(landed.account), [.without], "landing account → one pick")
check(A.picks(landed.life), [], "landing without status → no status chip")
check(A.picks(A.Account.all), [], "«الكل» from a link = no pick")

// MARK: - «نساء العائلة» — «الحيّات» الافتراضية شريحة عادية

typealias W = AdminWomenLogic
let women: [W.Fact] = [
    W.Fact(registered: true, married: true),
    W.Fact(married: true),
    W.Fact(),
    W.Fact(deceased: true, married: true),
    W.Fact(deceased: true),
    W.Fact(registered: true, outside: true),
    W.Fact(deceased: true, outside: true),
]
check(W.pageDefault.statuses, [.living], "women open on «الحيّات»")
check(W.count(women, W.Filters(statuses: [.registered, .deceased])), 3, "women OR: registered or deceased")
check(W.count(women, W.Filters(statuses: [.living, .deceased])), 5, "women OR: living or deceased = every family woman")
check(W.count(women, W.Filters(statuses: [.married], branch: .outside)), 0, "women AND: married × outside")
check(W.count(women, W.Filters(statuses: [.living, .deceased], branch: .outside)), 2,
      "women outside with «متوفيات» picked: the deceased join the list")
check(women.filter { W.inOutsideDeceased($0, W.Filters(statuses: [.living, .registered], branch: .outside)) }.count, 1,
      "women outside without «متوفيات»: the deceased stay in their folded section")

let womenSet = AdminFilterSet<W.Filters>(resultCount: { W.count(women, $0) }) { s in
    [
        .choices("status", title: "الحالة", values: \.statuses,
                 options: W.Status.allCases.filter { $0 != .all }.map { status in
                     var probe = s
                     probe.statuses = [status]
                     return AdminFilterOption(status, status.title, count: W.count(women, probe))
                 }),
        .single("branch", title: "الفرع", value: \.branch, neutral: .family,
                options: W.Branch.allCases.map { AdminFilterOption($0, $0.title) }),
        .order("order", title: "الترتيب", value: \.order, standard: .alphabetical,
               options: W.Order.allCases.map { AdminFilterOption($0, $0.title) }),
    ]
}
check(womenSet.snapshot(W.pageDefault).items.map(\.title), ["الحيّات"], "women: the default shows as a normal chip")
if let living = womenSet.snapshot(W.pageDefault).items.first {
    let after = womenSet.applying(living.remove, to: W.pageDefault)
    check(after.statuses, [], "women: ✕ «الحيّات» → «الكل»")
    check(womenSet.snapshot(after).result, 5, "women: every family woman after removing the default")
}
check(womenSet.snapshot(W.Filters(statuses: [.living], branch: .outside)).items.map(\.title), ["الحيّات", "فرع خارج العائلة"],
      "women: the single-choice branch still gets its chip")
check(womenSet.snapshot(W.Filters(statuses: [], order: .newest)).items.count, 0, "order never makes a chip")
check(womenSet.snapshot(W.Filters(statuses: [], order: .newest)).orderTitle, "الأحدث", "order shows in the summary line")
check(womenSet.groups(W.pageDefault)[1].selection == .single, true, "women «الفرع» stays single-choice")
check(womenSet.groups(W.pageDefault)[2].selection == .single, true, "order stays single-choice")
check(W.filters(landing: AdminWomenLanding(status: .all, branch: .outside)), W.Filters(statuses: [], branch: .outside),
      "women landing from a total: «الكل» = no status chip")

// MARK: - النصوص

check(AdminFilterText.filters, "تصفية", "the formal name «تصفية»")
check(AdminFilterText.noResults, "لا نتائج بهذه التصفية", "empty title")
check(AdminFilterText.on(3), "تصفية، 3 مفعّلة", "VoiceOver on the button")
check(AdminFilterText.openHint, "يفتح التصفية", "VoiceOver hint")
check(inboxSet.resultPhrase(12), "12 طلباً", "result phrase with the right Arabic noun")
check(inboxSet.resultPhrase(nil), "—", "result not loaded = «—»")

print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
