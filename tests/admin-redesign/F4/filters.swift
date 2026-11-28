import Foundation

// فحص إصلاحات التصفية من مراجعة الكود (الوحدة F4 — القسم C: V2 · V3 · V5 · V7 · V39) — بلا محاكي.
// ملف بلا أوامر في المستوى الأعلى: `main.swift` (F4) يعرّف `failures` و`check` ويضبط `L10n.isArabic = true` ثم يستدعي
// `runF4FilterTests()`. الملفات:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o <out> \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminFilterKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxFilters.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxView.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminWomenPanel.swift \
//     tests/admin-redesign/F4/filters.swift tests/admin-redesign/F4/main.swift

func runF4FilterTests() {
    f4InboxKindCounts()
    f4ChipRemoval()
    f4WomenOutsideFold()
    f4EmptyCause()
    f4StateNoun()
}

// MARK: - V2: عدد «النوع» = النتيجة بعد لمسه (بقية الاختيارات باقية)

private typealias F4L = AdminInboxLogic
private typealias F4IF = AdminInboxLogic.Filters

/// ٨ طلبات: أعضاء (انضمام عاجل · رقم · وفاة عاجل) · الشجرة (ابن · إضافة متأخر · ابن متأخر) · محتوى (خبر · صورة)
private let f4Inbox: [F4L.Fact] = [
    F4L.Fact(kind: .joinRequests, source: .registration, inFlow: true, waiting: true, urgent: true),
    F4L.Fact(kind: .children, source: .profile, inFlow: true, waiting: true),
    F4L.Fact(kind: .treeAdd, source: .familyTree, inFlow: true, late: true),
    F4L.Fact(kind: .phone, source: .profile, inFlow: true, waiting: true),
    F4L.Fact(kind: .news, source: .content, inFlow: true),
    F4L.Fact(kind: .children, source: .familyTree, inFlow: true, waiting: true, late: true),
    F4L.Fact(kind: .deceased, source: .familyTree, inFlow: true, waiting: true, urgent: true),
    F4L.Fact(kind: .photos, source: .content, inFlow: true, waiting: true),
]

private func f4n(_ f: F4IF) -> Int { F4L.count(f4Inbox, f, workflowOn: true) }

/// ما تفعله لمسة صفّ «النوع» في الورقة: يُضاف النوع ثم الإصلاح
private func f4Tap(_ s: F4IF, kind: F4L.Kind) -> F4IF {
    var next = s
    next.kinds.insert(kind)
    F4L.normalize(&next)
    return next
}

private func f4InboxKindCounts() {
    // «الشجرة» و«أعضاء» مختارتان بلا نوع: عدد «ابن» = 2 ابن + 3 أعضاء = النتيجة بعد لمسه
    let twoGroups = F4IF(statuses: [], groups: [.tree, .members])
    check(f4n(F4L.probe(twoGroups, kind: .children)), f4n(f4Tap(twoGroups, kind: .children)),
          "V2 kind count = result after tapping it, other group kept")
    check(f4n(F4L.probe(twoGroups, kind: .children)), 5, "V2 kind count with «أعضاء» picked = 2 children + 3 members")
    // نوع مختار من «أعضاء» يبقى يضيّق مجموعته: «ابن» = 2 ابن + 1 رقم
    let withMemberKind = F4IF(statuses: [], groups: [.tree, .members], kinds: [.phone])
    check(f4n(F4L.probe(withMemberKind, kind: .children)), f4n(f4Tap(withMemberKind, kind: .children)),
          "V2 kind count keeps the other group's kinds")
    check(f4n(F4L.probe(withMemberKind, kind: .children)), 3, "V2 kind count: 2 children + the picked phone request")
    // مع الحالة: «متأخر» × (الشجرة نوع ابن | أعضاء) = ابن متأخر واحد
    let lateTwo = F4IF(statuses: [.late], groups: [.tree, .members])
    check(f4n(F4L.probe(lateTwo, kind: .children)), f4n(f4Tap(lateTwo, kind: .children)),
          "V2 kind count follows status and keeps the other group")
    // الخيار نفسه مختار: عدد شريحته = النتيجة الحالية
    let picked = F4IF(statuses: [], groups: [.tree, .members], kinds: [.children])
    check(f4n(F4L.probe(picked, kind: .children)), f4n(picked), "V2 a picked kind's chip count = the current result")
    // أخوه في المجموعة نفسها: وحده في مجموعته (قاعدة الطقم «لو اختير وحده في مجموعته»)
    check(f4n(F4L.probe(picked, kind: .treeAdd)), 1 + 3, "V2 sibling kind: alone in its own group, others kept")
    // وجود النوع (صفّ يظهر في الورقة): طلباته هو وحده — لا تكفي طلبات المجموعة الأخرى
    check(f4n(F4L.only(twoGroups, kind: .treeEditName)), 0, "V2 a kind with no requests stays hidden though «أعضاء» has some")
    check(f4n(F4L.only(twoGroups, kind: .children)), 2, "V2 a kind's own requests")
    check(f4n(F4L.only(lateTwo, kind: .children)), 1, "V2 a kind's own requests follow status")
}

// MARK: - V3: ✕ شريحة مجموعة تزيل أنواعها — التلميح والإعلان يسمّيان كل ما يُزال

private func f4ChipRemoval() {
    let title: [F4L.Group: String] = [.members: "أعضاء", .tree: "الشجرة", .content: "المحتوى"]
    let kindTitle: [F4L.Kind: String] = [.children: "إضافة ابن", .treeAdd: "إضافة للشجرة", .phone: "تغيير رقم"]
    let set = AdminFilterSet<F4IF>(normalize: F4L.normalize, resultCount: { f4n($0) }) { s in
        [
            .choices("group", title: "المجموعة", values: \.groups,
                     options: F4L.Group.allCases.map { AdminFilterOption($0, title[$0]!) }),
            .choices("kind", title: "النوع", values: \.kinds,
                     options: [F4L.Kind.children, .treeAdd, .phone].map { AdminFilterOption($0, kindTitle[$0]!) }),
        ]
    }
    let state = F4IF(statuses: [], groups: [.tree, .members], kinds: [.children, .treeAdd, .phone])
    let items = set.snapshot(state).items
    check(items.map(\.title), ["أعضاء", "الشجرة", "إضافة ابن", "إضافة للشجرة", "تغيير رقم"], "V3 fixture chips")
    if let tree = items.first(where: { $0.title == "الشجرة" }) {
        check(set.removedTitles(by: tree, among: items, in: state), ["الشجرة", "إضافة ابن", "إضافة للشجرة"],
              "V3 ✕ «الشجرة» names every chip it removes")
    }
    if let child = items.first(where: { $0.title == "إضافة ابن" }) {
        check(set.removedTitles(by: child, among: items, in: state), ["إضافة ابن"], "V3 ✕ a kind removes only itself")
    }
    if let members = items.first(where: { $0.title == "أعضاء" }) {
        check(set.removedTitles(by: members, among: items, in: state), ["أعضاء", "تغيير رقم"],
              "V3 ✕ «أعضاء» takes its picked kind too")
    }
    // النصوص — مكانها الواحد
    check(AdminFilterText.joined(["الشجرة"]), "الشجرة", "V3 one name")
    check(AdminFilterText.joined(["الشجرة", "إضافة ابن"]), "الشجرة وإضافة ابن", "V3 two names joined with «و»")
    check(AdminFilterText.joined(["الشجرة", "إضافة ابن", "إضافة للشجرة"]), "الشجرة وإضافة ابن وإضافة للشجرة",
          "V3 three names")
    check(AdminFilterText.removed(["الشجرة", "إضافة ابن"], result: "3 طلبات"),
          "أُزيل الشجرة وإضافة ابن. النتيجة الآن: 3 طلبات", "V3 announcement names every removed chip")
    check(AdminFilterText.removed(["عاجل"], result: "طلبان"), AdminFilterText.removed("عاجل", result: "طلبان"),
          "V3 one removed chip = the old announcement")
    check(AdminFilterText.removalHint(["إضافة ابن"]), AdminFilterText.removeHint, "V3 hint: alone = «يزيل هذا الاختيار وحده»")
    check(AdminFilterText.removalHint(["الشجرة", "إضافة ابن"]), "يزيل الشجرة وإضافة ابن", "V3 hint names every chip")
}

// MARK: - V5: المطويّ «المتوفون من خارج العائلة» يحترم بقية «الحالة»

private func f4WomenOutsideFold() {
    typealias W = AdminWomenLogic
    let outside: [W.Fact] = [
        W.Fact(outside: true),
        W.Fact(registered: true, outside: true),
        W.Fact(deceased: true, outside: true),
        W.Fact(deceased: true, registered: true, outside: true),
        W.Fact(deceased: true, married: true, outside: true),
    ]
    func fold(_ statuses: Set<W.Status>) -> Int {
        outside.filter { W.inOutsideDeceased($0, W.Filters(statuses: statuses, branch: .outside)) }.count
    }
    check(fold([]), 3, "V5 «الكل»: every outside deceased folded")
    check(fold([.living]), 3, "V5 «الحيّات»: every outside deceased folded (unchanged)")
    check(fold([.registered]), 1, "V5 «مسجّلات» alone: only the registered deceased folded (was hidden)")
    check(fold([.married]), 1, "V5 «متزوجات» alone: only the married deceased folded (was hidden)")
    check(fold([.registered, .married]), 2, "V5 «مسجّلات» or «متزوجات»: their deceased (OR)")
    check(fold([.living, .registered]), 3, "V5 «الحيّات» still brings the whole fold (OR)")
    check(fold([.deceased, .registered]), 0, "V5 «متوفيات» picked: the deceased are in the list, no fold")
    // كل متوفى ظاهر مرة واحدة: في القائمة أو في المطويّ، ولا أحد يختفي بـ«مسجّلات»
    for statuses: Set<W.Status> in [[.registered], [.married], [.registered, .married], [.living, .married]] {
        let s = W.Filters(statuses: statuses, branch: .outside)
        let shown = outside.filter { W.inList($0, s) || W.inOutsideDeceased($0, s) }.count
        let matching = outside.filter { f in
            statuses.contains { W.matches(f, status: $0) } || (statuses.contains(.living) && f.deceased)
        }.count
        check(shown, matching, "V5 \(statuses.map(\.rawValue).sorted()): every matching outside row shows once")
        check(outside.filter { W.inList($0, s) && W.inOutsideDeceased($0, s) }.count, 0,
              "V5 \(statuses.map(\.rawValue).sorted()): never in both places")
    }
}

// MARK: - V7: بطاقة «لا نتائج» تسأل عن البحث أولاً

private func f4EmptyCause() {
    typealias C = AdminInboxLogic.EmptyCause
    check(F4L.emptyCause(searching: true, searchedCount: 0, filtersActive: true), C.search,
          "V7 nothing matches the search itself → «مسح البحث» even with filters on")
    check(F4L.emptyCause(searching: true, searchedCount: 0, filtersActive: false), C.search, "V7 search alone → search")
    check(F4L.emptyCause(searching: true, searchedCount: 4, filtersActive: true), C.filters,
          "V7 the search finds some, the filter hides them → «تعديل التصفية»")
    check(F4L.emptyCause(searching: false, searchedCount: 9, filtersActive: true), C.filters, "V7 no search → filter")
}

// MARK: - V39: المعدود من الحالة المعدودة لا من الفرع المحفوظ

private func f4StateNoun() {
    typealias W = AdminWomenLogic
    let facts: [W.Fact] = [W.Fact(), W.Fact(outside: true), W.Fact(registered: true, outside: true)]
    let family = W.Filters(statuses: [], branch: .family)
    let outsideState = W.Filters(statuses: [], branch: .outside)
    check(W.countsPeople(family), false, "V39 family branch counts women")
    check(W.countsPeople(outsideState), true, "V39 outside branch counts people (men and women)")
    // الطقم بني والفرع «كل الفروع» (كما يُبنى في الرسم) ثم يُعدّ حالة «فرع خارج العائلة» بعد لمسة
    var set = AdminFilterSet<W.Filters>(noun: { n in n == 1 ? "امرأة" : "نساء" },
                                        resultCount: { W.count(facts, $0) }) { _ in [] }
    set.stateNoun = { s, n in W.countsPeople(s) ? (n == 2 ? "فردان" : "أفراد") : (n == 1 ? "امرأة" : "نساء") }
    check(set.resultPhrase(for: outsideState), "2 فردان", "V39 phrase uses the counted state's noun")
    check(set.resultPhrase(for: family), "1 امرأة", "V39 family state keeps the women noun")
    check(set.noun(for: outsideState, 2), "فردان", "V39 noun(for:) follows the state")
    let plain = AdminFilterSet<W.Filters>(noun: { _ in "نتيجة" }, resultCount: { _ in nil }) { _ in [] }
    check(plain.resultPhrase(for: family), "—", "V39 not loaded = «—»")
    check(plain.noun(for: family, 3), "نتيجة", "V39 no state noun = the plain noun")
}
