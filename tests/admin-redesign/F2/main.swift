// فحص إصلاحات مراجعة الكود (F2، ٢٠٢٦-١١-٢٦) — بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/f2-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayLogic.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxFilters.swift tests/admin-redesign/F2/main.swift && /tmp/f2-logic
import Foundation

var failures = 0
func check<T: Equatable>(_ got: T, _ want: T, _ label: String) {
    if got == want { print("PASS \(label)") } else { print("FAIL \(label): got \(got) want \(want)"); failures += 1 }
}

L10n.isArabic = true
typealias L = AdminInboxLogic
let now = Date(timeIntervalSince1970: 1_800_000_000)
let earlier = now.addingTimeInterval(-600)
let relevant: [L.Store] = [.joins, .children, .photos, .policy]
func health(_ pairs: [(L.Store, AdminStoreHealth)]) -> [L.Store: AdminStoreHealth] {
    Dictionary(uniqueKeysWithValues: pairs)
}

// MARK: ١) أول جلب أُلغي (دفع «الرسائل»/صفحة الخصوصية فوق «الوارد») لا يُعدّ «وصل»

check(L.ended(before: nil, running: .loading, success: true, cancelled: true), .idle,
      "cancelled first load → idle (skeleton, reloaded on the next appear), not «loaded»")
check(L.ended(before: .failed(lastGood: nil), running: .loading, success: true, cancelled: true), .failed(lastGood: nil),
      "cancelled retry → still failed (retry stays)")
check(L.ended(before: .failed(lastGood: nil), running: .loading, success: true, cancelled: true).canRetry, true,
      "cancelled retry keeps «أعد المحاولة»")
check(L.ended(before: .loaded(at: earlier), running: .loaded(at: earlier), success: false, cancelled: true),
      .loaded(at: earlier), "cancelled refresh over data → keeps the data, no failure word")
check(L.ended(before: nil, running: .loading, success: true, cancelled: false, at: now), .loaded(at: now), "finished → loaded")
check(L.ended(before: nil, running: .loading, success: false, cancelled: false), .failed(lastGood: nil), "real failure → failed")
check(L.ended(before: .loaded(at: earlier), running: .loaded(at: earlier), success: false, cancelled: false),
      .failed(lastGood: earlier), "refresh failed after data → stale with its time")

// كل القوائم رجعت `idle` بعد الإلغاء: هيكل — لا «لا طلبات الآن» ولا «المنجز 0»
let afterCancel = health(relevant.map { ($0, L.ended(before: nil, running: .loading, success: true, cancelled: true)) })
check(L.phase(afterCancel, relevant: relevant), .loading, "after a cancelled first load the list is a skeleton")
check(L.focusOutcome(inPending: false, inPolicy: false, health: afterCancel, relevant: relevant), .wait,
      "focus waits after a cancel (never «عولج من قبل»)")

// MARK: ٢) «أعد المحاولة» لا يخفي الصفوف الموجودة

// فشل جزئي ثم «أعد المحاولة»: القائمة الفاشلة تُعاد وحدها والباقي في اليد
let partial = health([(.joins, .loaded(at: now)), (.children, .loaded(at: now)), (.photos, .failed(lastGood: nil)),
                      (.policy, .loaded(at: now))])
check(L.phase(partial, relevant: relevant), .partial([.photos]), "before retry: partial line")
var retrying = partial
retrying[.photos] = retrying[.photos]!.beginning()
check(retrying[.photos], .loading, "retry starts the failed list")
check(L.phase(retrying, relevant: relevant), .refreshing([.photos]), "while retrying: rows stay + small refresh line")
check(L.phase(retrying, relevant: relevant) == .loading, false, "never the skeleton over data")
// أكثر من قائمة تُعاد
var two = partial
two[.photos] = .loading
two[.children] = .loading
check(L.phase(two, relevant: relevant), .refreshing([.children, .photos]), "two lists reloading → both named, order kept")
// لا شيء في اليد: الهيكل صحيح (لا صفوف تُخفى)
check(L.phase(health(relevant.map { ($0, AdminStoreHealth.failed(lastGood: nil).beginning()) }), relevant: relevant),
      .loading, "retry after a total failure → skeleton (nothing to hide)")
// قديم + يُعاد: يبقى «آخر تحديث» ورقمه
check(L.phase(health([(.joins, .failed(lastGood: earlier)), (.children, .loading), (.photos, .loaded(at: now)),
                      (.policy, .loaded(at: now))]), relevant: relevant), .stale(since: earlier, stores: [.joins]),
      "stale + reloading → stale (rows + time)")
// الطلب المطلوب ينتظر أثناء إعادة المحاولة
check(L.focusOutcome(inPending: false, inPolicy: false, health: retrying, relevant: relevant), .wait,
      "focus waits while a list is reloading")
// النصّ
check(AdminInboxText.refreshingLine([.photos]), "جارٍ تحميل الصور المقترحة…", "refresh line: one list")
check(AdminInboxText.refreshingLine([.news, .reports]), "جارٍ تحميل: الأخبار، البلاغات…", "refresh line: two lists")
check(AdminInboxText.refreshingLine([.photos]).contains("تعذّر"), false, "loading never says «تعذّر»")

// MARK: ٣) «المناسبات» و«الإحصاءات»: جلب الأعضاء محلياً (كما في «اليوم» F1)

typealias T = AdminTodayLogic
// علامة الفشل باقية من جلب سابق، و«أعد المحاولة» بدأ: هيكل لا «تعذّر التحميل»
let oldFailure = T.membersFetchEnded(hasMembers: false, loadFailed: true)
check(oldFailure, .failed(lastGood: nil), "members failed → «تعذّر التحميل ↻»")
let retryMembers = oldFailure.beginning()
check(T.membersHealth(hasMembers: false, loadedAt: nil, fetch: retryMembers), .loading, "members retry → loading")
check(T.membersHealth(hasMembers: false, loadedAt: nil, fetch: retryMembers).look, .skeleton, "members retry → skeleton look")
check(T.membersHealth(hasMembers: false, loadedAt: nil, fetch: .idle).look, .skeleton, "before the page's first fetch → skeleton")
// جلب أُلغي (غادر الصفحة) والعلامة القديمة قائمة: `loadFailed && !Task.isCancelled` = false ← هيكل
check(T.membersFetchEnded(hasMembers: false, loadFailed: true && !true), .idle, "cancelled members fetch → idle, not failed")
check(T.membersHealth(hasMembers: true, loadedAt: now, fetch: .failed(lastGood: nil)), .loaded(at: now),
      "members in hand → loaded whatever the old flag says")
// «الإحصاءات»: `membersFailed` يقصّ الأقسام على «العائلة» — فقط بعد فشل حقيقي
check(T.membersHealth(hasMembers: false, loadedAt: nil, fetch: retryMembers) == .failed(lastGood: nil), false,
      "stats keep their sections while members reload")

// MARK: English

L10n.isArabic = false
check(AdminInboxText.refreshingLine([.photos]), "Loading suggested photos…", "en: refresh line")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
