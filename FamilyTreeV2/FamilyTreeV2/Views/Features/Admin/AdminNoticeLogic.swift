import Foundation

// MARK: - منطق «إشعارات الإدارة» الخالص (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U18 — spec C.15)
//
// ما لا يحتاج SwiftUI ولا السيرفر، في مكان واحد يُفحص بلا محاكي:
//   • الفلاتر الخمسة (بُعد واحد = شرائح تلتفّ، spec A.9) وأعدادها
//   • الأقسام: «يحتاج إجراء الآن» أولاً (الحالات المشتقة ثم إشعارات تنتظر قراراً)، ثم الأيام الأحدث أولاً
//   • ما ترسمه الصفحة مكان القائمة من حال المخزن (`AdminStoreHealth`): هيكل · خطأ + «أعد المحاولة» · فارغ · فارغ بالفلتر
//   • نتيجة جلب `AdminNoticeStore`: نجح، أو سبب الفشل الذي يُسجَّل
//   • نصوص العدد («12 غير مقروء»، «مقروء (3)»، «حذف 3 إشعارات؟»)
//
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u18-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminNoticeLogic.swift tests/admin-redesign/U18/main.swift && /tmp/u18-logic

/// فئة إشعار الإدارة (`AdminNotices.category`): `changes` = «تغييرات الأعضاء» (`member_change`)، `team` = «نشاط الفريق»،
/// `system` = «النظام»، `action` = طلب أو تنبيه أمني
nonisolated enum AdminNoticeCategory: String, Hashable {
    case action, team, system, changes
}

nonisolated enum AdminNoticeLogic {
    // MARK: الفلاتر

    /// شرائح الصفحة — بُعد واحد، خمسة خيارات (spec A.9 الاستعمال ١)
    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case all, action, changes, team, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:     return L10n.t("الكل", "All")
            case .action:  return L10n.t("يحتاج إجراء", "Needs action")
            case .changes: return L10n.t("تغييرات الأعضاء", "Member changes")
            case .team:    return L10n.t("نشاط الفريق", "Team activity")
            case .system:  return L10n.t("النظام", "System")
            }
        }
    }

    /// ما يحتاجه المنطق من الصفّ
    struct Fact: Equatable {
        var category: AdminNoticeCategory
        /// يحتاج إجراء الآن (حالة مشتقة، طلب ما زال معلّقاً، تنبيه أمني غير مقروء، ابن مضاف «راجعه»)
        var needsAction: Bool
        /// حالة مشتقة الآن (ليست إشعاراً) — أول «يحتاج إجراء الآن»
        var pinned: Bool = false
        var unread: Bool = false
        var date: Date
    }

    static func matches(_ fact: Fact, _ filter: Filter) -> Bool {
        switch filter {
        case .all:     return true
        case .action:  return fact.needsAction
        case .changes: return fact.category == .changes
        case .team:    return fact.category == .team
        case .system:  return fact.category == .system
        }
    }

    static func counts(_ facts: [Fact]) -> [Filter: Int] {
        var out: [Filter: Int] = [:]
        for fact in facts {
            for filter in Filter.allCases where matches(fact, filter) { out[filter, default: 0] += 1 }
        }
        return out
    }

    /// العدد على الشريحة: «يحتاج إجراء 4» وحدها (spec C.15، mock 11) — الباقي فلاتر بلا عدد، و«غير مقروء» سطر تحتها.
    /// لا صفر، ولا عدد قبل وصول البيانات
    static func chipCount(_ filter: Filter, counts: [Filter: Int], ready: Bool) -> Int? {
        guard ready, filter == .action, let n = counts[filter], n > 0 else { return nil }
        return n
    }

    // MARK: الأقسام

    enum SectionKind: Hashable {
        /// «يحتاج إجراء الآن»
        case now
        /// يوم (بدايته)
        case day(Date)
    }

    struct Section: Equatable {
        let kind: SectionKind
        /// مواقع الصفوف في القائمة المعطاة، بترتيب العرض
        let indices: [Int]

        var id: String {
            switch kind {
            case .now:          return "now"
            case .day(let d):   return "day.\(Int(d.timeIntervalSince1970))"
            }
        }
    }

    /// «يحتاج إجراء الآن» أولاً (المشتقة ثم الأحدث)، ثم كل يوم بقسمه — الأحدث أولاً. الصفّ في قسم واحد فقط
    static func sections(_ facts: [Fact], calendar: Calendar = .current) -> [Section] {
        let order = facts.indices.sorted { a, b in
            if facts[a].pinned != facts[b].pinned { return facts[a].pinned }
            if facts[a].date != facts[b].date { return facts[a].date > facts[b].date }
            return a < b
        }
        var list: [Section] = []
        let now = order.filter { facts[$0].needsAction || facts[$0].pinned }
        if !now.isEmpty { list.append(Section(kind: .now, indices: now)) }
        var days: [Date] = []
        var byDay: [Date: [Int]] = [:]
        for i in order where !(facts[i].needsAction || facts[i].pinned) {
            let day = calendar.startOfDay(for: facts[i].date)
            if byDay[day] == nil { days.append(day) }
            byDay[day, default: []].append(i)
        }
        for day in days { list.append(Section(kind: .day(day), indices: byDay[day] ?? [])) }
        return list
    }

    /// الحالات المشتقة («وفاة لم يُعلن عنها»…) تظهر فقط بعد أن نشرها «اليوم» في هذه الجلسة — لا قديم أبداً (spec C.15)
    static func keepsDerived(published: Bool) -> Bool { published }

    // MARK: حال الصفحة

    /// في اليد إشعارات تُعرض: جلب ناجح (أو قديم بعد فشل)، أو إشعارات وصلت من جلب سابق في التطبيق
    static func ready(health: AdminStoreHealth, hasNotices: Bool) -> Bool {
        health.hasData || hasNotices
    }

    /// ما يُرسم مكان القائمة
    enum Body: Equatable {
        /// هيكل صفوف بشكل القائمة
        case skeleton
        /// «تعذّر تحميل الإشعارات» + «أعد المحاولة» (لا شيء في اليد)
        case failed
        /// «لا إشعارات»
        case empty
        /// «لا شيء في هذا الفلتر» / «لا نتائج»
        case filteredEmpty(searching: Bool)
        case list
    }

    static func body(ready: Bool, health: AdminStoreHealth, total: Int, shown: Int, searching: Bool) -> Body {
        guard ready else { return health.canRetry ? .failed : .skeleton }
        if total == 0 { return health.canRetry ? .failed : .empty }
        if shown == 0 { return .filteredEmpty(searching: searching) }
        return .list
    }

    /// «تعذّر تحديث الإشعارات» فوق القائمة: التحديث فشل والقديم باقٍ تحته
    static func showsRefreshError(ready: Bool, health: AdminStoreHealth, total: Int) -> Bool {
        ready && total > 0 && health.canRetry
    }

    /// الشرائح والبحث: مع التحميل (تمسك المكان) ومع وجود إشعارات — لا فوق «لا إشعارات» ولا فوق خطأ بلا بيانات
    static func showsFilters(ready: Bool, health: AdminStoreHealth, total: Int) -> Bool {
        ready ? total > 0 : !health.canRetry
    }

    // MARK: الجلب

    /// لماذا فشل جلب الإشعارات — يُسجَّل بسببه
    enum LoadFailure: Equatable {
        /// `-tmpFailStores notices` (T0)
        case injected
        /// جدول الإشعارات غير موجود
        case featureMissing
        /// الجهاز غير متصل
        case offline
        /// انتهى الجلب بلا بيانات والجهاز متصل (نموذج العرض سجّل الخطأ نفسه `[NOTIF]`)
        case server

        var cause: String {
            switch self {
            case .injected:       return "injected failure (-tmpFailStores notices)"
            case .featureMissing: return "notifications table missing"
            case .offline:        return "device offline"
            case .server:         return "fetch returned no data (see [NOTIF] error)"
            }
        }

        /// سبب متوقّع لا يُبلَّغ عنه السيرفر (`Log.warning` بدل `Log.error`)
        var isExpected: Bool { self == .injected || self == .offline }
    }

    /// - delivered: نموذج العرض كتب قائمة الإشعارات أثناء الجلب (= نجح)
    static func loadFailure(injected: Bool, featureAvailable: Bool, delivered: Bool, online: Bool) -> LoadFailure? {
        if injected { return .injected }
        if !featureAvailable { return .featureMissing }
        if delivered { return nil }
        return online ? .server : .offline
    }

    // MARK: النصوص

    /// زرّ الرجوع باسم ما فُتحت منه كما مرّره (جرس «اليوم» يمرّر «الإدارة» من مصدره — F1، mock 11: «‹ الإدارة»)؛
    /// وبلا فاتح «الإدارة»
    static func backTitle(_ opener: String?) -> String {
        guard let opener, !opener.isEmpty else { return L10n.t("الإدارة", "Admin") }
        return opener
    }

    /// «12 غير مقروء» — الرقم لاتيني بفاصل الآلاف
    static func unreadTail() -> String { L10n.t("غير مقروء", "unread") }

    /// «مقروء (3)» · «حذف (3)» — شريط التحديد
    static func countedVerb(_ verb: String, _ n: Int) -> String {
        "\(verb) (\(AdminNumberText.grouped(n)))"
    }

    /// المعدود بعد الرقم: ١ «إشعار»، ٢ «إشعاران»، ٣–١٠ «إشعارات»، ١١–٩٩ «إشعاراً»
    static func noticesNoun(_ n: Int) -> String {
        if n == 1 { return L10n.t("إشعار", "notification") }
        if n == 2 { return L10n.t("إشعاران", "notifications") }
        switch n % 100 {
        case 3...10:  return L10n.t("إشعارات", "notifications")
        case 11...99: return L10n.t("إشعاراً", "notifications")
        default:      return L10n.t("إشعار", "notifications")
        }
    }

    /// «حذف الإشعار؟» · «حذف إشعارين؟» · «حذف 3 إشعارات؟» — السؤال بالفعل (spec A.14)
    static func deleteQuestion(_ n: Int) -> String {
        switch n {
        case 1:  return L10n.t("حذف الإشعار؟", "Delete the notification?")
        case 2:  return L10n.t("حذف إشعارين؟", "Delete 2 notifications?")
        default:
            let number = AdminNumberText.grouped(n)
            return L10n.t("حذف \(number) \(noticesNoun(n))؟", "Delete \(number) notifications?")
        }
    }
}
