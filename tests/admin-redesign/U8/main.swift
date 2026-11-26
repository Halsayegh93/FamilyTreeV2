// فحص منطق «الوارد» (Views/Features/Admin/AdminInboxFilters.swift، الوحدة U8) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u8-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxFilters.swift tests/admin-redesign/U8/main.swift && /tmp/u8-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

typealias L = AdminInboxLogic
typealias F = L.Filters

// ٨ طلبات: ٣ في المسار (منها عاجل ينتظرني، ومتأخر لا ينتظرني، وعادي ينتظرني) و٥ بلا مسار
let facts: [L.Fact] = [
    L.Fact(kind: .joinRequests, source: .registration, inFlow: true, waiting: true, urgent: true),
    L.Fact(kind: .treeAdd, source: .womenTree, inFlow: true, late: true),
    L.Fact(kind: .children, source: .familyTree, inFlow: true, waiting: true),
    L.Fact(kind: .news, source: .content),
    L.Fact(kind: .reports, source: .content),
    L.Fact(kind: .photos, source: .familyTree),
    L.Fact(kind: .treeEditName, source: .profile),
    L.Fact(kind: .phone, source: .profile),
]

// MARK: الحالة والمسار
check(L.count(facts, F(), workflowOn: true), 8, "all = every request")
check(L.count(facts, F(status: .waiting), workflowOn: true), 2, "workflow on: waiting = the ones waiting for me")
check(L.count(facts, F(status: .waiting), workflowOn: false), 8, "workflow off: every request awaits a decision")
check(L.count(facts, F(status: .urgent), workflowOn: true), 1, "urgent")
check(L.count(facts, F(status: .late), workflowOn: true), 1, "late (or escalated)")
check(L.count(facts, F(status: .urgent), workflowOn: false), 1, "urgent needs a flow snapshot (none when off in real data)")

// MARK: أرقام الرأس = القائمة التي تفتحها (T2)
let header = L.headerCounts(facts, workflowOn: true)
check(header, L.HeaderCounts(waiting: 2, urgent: 1, late: 1), "header counts")
check(L.count(facts, F(status: .waiting), workflowOn: true), header.waiting, "tapping «بانتظار قرارك» lands on the same count")
check(L.count(facts, F(status: .late), workflowOn: true), header.late, "tapping «متأخر» lands on the same count")

// MARK: المجموعة والنوع والمصدر
check(L.count(facts, F(group: .tree), workflowOn: true), 3, "tree group: tree add + child + tree name edit")
check(L.count(facts, F(group: .members), workflowOn: true), 2, "members group: join + phone")
check(L.count(facts, F(group: .content), workflowOn: true), 3, "content group: news + report + photo")
check(L.count(facts, F(kind: .children), workflowOn: true), 1, "kind")
check(F(kind: .children).group, .tree, "a kind brings its group")
check(L.count(facts, F(source: .profile), workflowOn: true), 2, "source")
check(L.count(facts, F(status: .waiting, group: .tree), workflowOn: true), 1, "status × group combine")
check(L.count(facts, F(group: .content, source: .content), workflowOn: true), 2, "group × source combine")

// MARK: تطبيع بعد الاختيار
var f = F(kind: .children)
f.group = .content
L.normalize(&f)
check(f.kind, nil, "kind outside the chosen group resets")
f = F(kind: .children)
f.group = nil
L.normalize(&f)
check(f.kind, nil, "no group → no kind")
f = F(kind: .treeAdd)
L.normalize(&f)
check(f.kind, .treeAdd, "kind inside its group stays")
check(F().isEmpty, true, "fresh filters are empty")
check(F(status: .urgent).isEmpty, false, "a status is a filter")

// MARK: الهبوط ← الفلاتر (العقد U2 مقصوصاً على أنواع الدور)
let monitorKinds: Set<String> = ["joinRequests", "nameChange", "phone", "deceased", "children", "treeAdd", "treeEditName",
                                 "treeEditPhone", "treeEditBirth", "treeDeceased", "treeAddDeathDate", "treeAddPhoto",
                                 "treeDelete", "treeOther", "photos"]
check(F(landing: AdminInboxLanding(pushKind: "child_add").clamped(toKinds: monitorKinds)), F(kind: .children),
      "push child_add → kind children (+ its group)")
check(F(landing: AdminInboxLanding(pushKind: "news_report").clamped(toKinds: monitorKinds)), F(),
      "monitor + report push → unfiltered inbox (not an empty list it can't own)")
check(F(landing: AdminInboxLanding(pushKind: "tree_edit").clamped(toKinds: monitorKinds)), F(group: .tree),
      "tree_edit push without id → tree group")
check(F(landing: AdminInboxLanding(pushKind: "something_new")), F(), "unknown kind → unfiltered")
check(F(landing: AdminInboxLanding(status: .urgent, source: .womenTree)), F(status: .urgent, source: .womenTree),
      "status + source land as-is")

// MARK: حال القوائم
let now = Date()
let earlier = now.addingTimeInterval(-600)
let relevant: [L.Store] = [.joins, .children, .photos, .policy]
func health(_ pairs: [(L.Store, AdminStoreHealth)]) -> [L.Store: AdminStoreHealth] {
    Dictionary(uniqueKeysWithValues: pairs)
}
check(L.phase([:], relevant: relevant), .loading, "nothing yet → loading")
check(L.phase(health([(.joins, .loaded(at: now)), (.children, .loading), (.photos, .loading), (.policy, .loading)]),
              relevant: relevant), .loading, "first load still running → loading")
check(L.phase(health([(.joins, .loaded(at: now)), (.children, .loaded(at: now)), (.photos, .loaded(at: now)),
                      (.policy, .loaded(at: now))]), relevant: relevant), .loaded, "all loaded")
check(L.phase(health([(.joins, .loaded(at: now)), (.children, .loaded(at: now)), (.photos, .failed(lastGood: nil)),
                      (.policy, .loaded(at: now))]), relevant: relevant), .partial([.photos]),
      "one list failed → partial line, the rest shows")
check(L.phase(health(relevant.map { ($0, AdminStoreHealth.failed(lastGood: nil)) }), relevant: relevant), .failed,
      "every list failed → error card (never «لا طلبات»)")
check(L.phase(health([(.joins, .loaded(at: now)), (.children, .failed(lastGood: earlier)), (.photos, .loaded(at: now)),
                      (.policy, .loaded(at: now))]), relevant: relevant), .stale(since: earlier, stores: [.children]),
      "refresh failed after a good load → keep rows + time")
check(L.phase(health([(.joins, .loaded(at: now)), (.children, .loading), (.photos, .failed(lastGood: nil)),
                      (.policy, .loaded(at: now))]), relevant: relevant), .partial([.photos]),
      "retrying while others have data → rows stay (no skeleton over data)")
check(L.Store.news.isRelevant(to: [.joinRequests, .children]), false, "a content list is not the monitor's")
check(L.Store.policy.isRelevant(to: []), true, "privacy list always counts (its door shows its number)")
check(L.Store.allCases.filter(\.isContent), [.news, .reports, .photos, .diwaniyas, .projects, .archive],
      "-tmpFailStores inbox fails the content side")

// MARK: الطلب المطلوب (focusMissing) — «عولج من قبل» فقط بعد وصول كل القوائم
let allLoaded = health(relevant.map { ($0, AdminStoreHealth.loaded(at: now)) })
check(L.focusOutcome(inPending: true, inPolicy: false, health: [:], relevant: relevant), .open, "found → open its box")
check(L.focusOutcome(inPending: false, inPolicy: true, health: allLoaded, relevant: relevant), .policy,
      "privacy request → its page")
check(L.focusOutcome(inPending: false, inPolicy: false, health: allLoaded, relevant: relevant), .handledBefore,
      "missing and every list loaded → calm «handled before»")
check(L.focusOutcome(inPending: false, inPolicy: false,
                     health: health([(.joins, .loaded(at: now)), (.children, .failed(lastGood: nil)),
                                     (.photos, .loaded(at: now)), (.policy, .loaded(at: now))]),
                     relevant: relevant), .failed, "missing and a list failed → «couldn't load» + retry")
check(L.focusOutcome(inPending: false, inPolicy: false,
                     health: health([(.joins, .loaded(at: now)), (.children, .failed(lastGood: earlier)),
                                     (.photos, .loaded(at: now)), (.policy, .loaded(at: now))]),
                     relevant: relevant), .failed, "missing and a refresh failed → not calm either")
check(L.focusOutcome(inPending: false, inPolicy: false,
                     health: health([(.joins, .loaded(at: now)), (.children, .loading)]), relevant: relevant), .wait,
      "still loading → wait")

// MARK: النصوص
L10n.isArabic = true
check(AdminInboxText.requests(1), "1 طلب", "1 طلب")
check(AdminInboxText.requests(2), "2 طلبان", "noun for 2")
check(AdminInboxText.requests(5), "5 طلبات", "3–10 plural")
check(AdminInboxText.requests(12), "12 طلباً", "11–99 accusative")
check(AdminInboxText.messagesLine(unread: 7, awaiting: 2), "7 جديدة · 2 بانتظار الرد", "messages door line")
check(AdminInboxText.messagesLine(unread: 0, awaiting: 0), nil, "no calm word on the messages door")
check(AdminInboxText.postReviewLine(1), "طلب مقبول ينتظر مراجعتك", "post review 1")
check(AdminInboxText.postReviewLine(3), "3 طلبات مقبولة تنتظر مراجعتك", "post review 3")
check(AdminInboxText.failedLine([.photos]), "تعذّر تحميل الصور المقترحة", "partial line, one list")
check(AdminInboxText.failedLine([.news, .reports]), "تعذّر تحميل: الأخبار، البلاغات", "partial line, two lists")
check(AdminInboxText.bulkApproveQuestion(3), "قبول 3 طلبات؟", "bulk approve question")
check(AdminInboxText.bulkRejectQuestion(2), "رفض الطلبين؟", "bulk reject question (dual)")
check(AdminInboxText.approveAllChildren(6), "الموافقة على كل طلبات إضافة ابن (6)", "approve all children")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
