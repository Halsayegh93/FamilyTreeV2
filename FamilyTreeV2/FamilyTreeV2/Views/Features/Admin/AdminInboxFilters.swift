import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - «الوارد»: الفلاتر وقطع الجذر (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U8 — spec C.2)
//
// لا مسار أقسام ولا صفوف شرائح بعد اليوم (spec E.7/E.8): «رسائل الأعضاء» و«بانتظار المراجعة» و«طلبات الخصوصية» و«المنجز»
// صفوف أبواب تفتح صفحاتها، والفلاتر الأربعة («الحالة» · «المجموعة» · «النوع» · «المصدر») في ورقة «الفلاتر» الواحدة (U5)،
// وسطر أرقام الرأس «5 بانتظار قرارك ‹ · 2 عاجل ‹ · 1 متأخر ‹» يضبط «الحالة» بلمسة. F3: اختيار متعدّد في كل مجموعة، وتطبيق
// فوري، وشريحة لكل اختيار.
// هنا:
//   ١) المنطق الخالص (Foundation) — حالة الفلاتر بقيم عقد الهبوط (`AdminInboxLanding`)، المطابقة والأعداد، مخازن القوائم
//      وحالها (فشل جزئي/كلي/قديم)، وقرار «الطلب المطلوب» (`focusId`)، ونصوص الأعداد بالعربية الصحيحة.
//   ٢) قطع الواجهة: رأس الجذر داخل القائمة، صفّ الطلب (صورة + نوعه على ركنها · الاسم والوقت · ما يطلبه · سطر الحالة)،
//      صفّ الباب، وشريط التحديد.
//
// فحص المنطق بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u8-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminInboxFilters.swift tests/admin-redesign/U8/main.swift && /tmp/u8-logic

// MARK: - المنطق الخالص

nonisolated enum AdminInboxLogic {
    typealias Status = AdminInboxLanding.Status
    typealias Group = AdminInboxLanding.Group
    typealias Kind = AdminInboxLanding.Kind
    typealias Source = AdminInboxLanding.Source

    /// حالة تصفية «الوارد» — بقيم عقد الهبوط نفسها (`RequestTab`/`RequestSection`/`ApprovalListFilter`/`AdminRequestSourceKind`
    /// بالقيم الخام ذاتها). اختيار متعدّد في كل مجموعة (F3): فارغة = «الكل»، وأي عدد = ما يطابق أيّها (OR)، والمجموعات معاً
    /// (AND). «النوع» يضيّق مجموعته وحدها: نوع مختار من «الشجرة» لا يخفي «أعضاء» المختارة معها.
    struct Filters: Equatable {
        var statuses: Set<Status>
        var groups: Set<Group>
        /// أنواع داخل المجموعات المختارة — كل نوع يجرّ مجموعته معه
        var kinds: Set<Kind>
        var sources: Set<Source>

        /// اختيار واحد لكل مجموعة (الهبوط، رقم الرأس، `initialFilter`) — «الكل»/nil = لا اختيار
        init(status: Status = .all, group: Group? = nil, kind: Kind? = nil, source: Source? = nil) {
            self.init(statuses: status == .all ? [] : [status],
                      groups: group.map { [$0] } ?? [],
                      kinds: kind.map { [$0] } ?? [],
                      sources: source.map { [$0] } ?? [])
        }

        init(statuses: Set<Status>, groups: Set<Group> = [], kinds: Set<Kind> = [], sources: Set<Source> = []) {
            self.statuses = statuses.subtracting([.all])
            self.groups = groups.union(kinds.map(\.group))
            self.kinds = kinds
            self.sources = sources
        }

        /// من الهبوط (بعد قصّه على أنواع الدور) — كل حقل فيه اختيار واحد يظهر شريحةً تُزال
        init(landing: AdminInboxLanding) {
            self.init(status: landing.status ?? .all, group: landing.group, kind: landing.kind, source: landing.source)
        }

        var isEmpty: Bool { self == Filters() }

        /// عدد الاختيارات (شريحة لكل واحد)
        var pickCount: Int { statuses.count + groups.count + kinds.count + sources.count }
    }

    /// ما يحتاجه الفلتر من الطلب — يُحسب مرة لكل رسم
    struct Fact: Equatable {
        var kind: Kind
        var source: Source? = nil
        /// له لقطة في مسار الموافقات
        var inFlow: Bool = false
        /// ينتظر قرار المشاهد (المسار)
        var waiting: Bool = false
        var urgent: Bool = false
        /// متأخر أو متصعّد
        var late: Bool = false
    }

    /// «بانتظار قرارك»: المسار شغّال = ما ينتظرك فيه؛ مطفأ = كل طلب في مجالك (نفس رقم «اليوم»). «عاجل»/«متأخر» من المسار وحده
    static func matches(_ fact: Fact, status: Status, workflowOn: Bool) -> Bool {
        switch status {
        case .all:     return true
        case .waiting: return workflowOn ? fact.waiting : true
        case .urgent:  return fact.urgent
        case .late:    return fact.late
        }
    }

    /// المجموعات معاً (AND)، وداخل كل مجموعة أيّ المختار (OR). «النوع» يضيّق مجموعته وحدها
    static func matches(_ fact: Fact, _ filters: Filters, workflowOn: Bool) -> Bool {
        guard filters.statuses.isEmpty
                || filters.statuses.contains(where: { matches(fact, status: $0, workflowOn: workflowOn) }) else { return false }
        guard matchesKind(fact.kind, groups: filters.groups, kinds: filters.kinds) else { return false }
        guard filters.sources.isEmpty || fact.source.map(filters.sources.contains) == true else { return false }
        return true
    }

    /// «المجموعة» و«النوع»: الطلب في إحدى المجموعات المختارة، وإن اختير نوع من مجموعته فهو أحد المختار منها
    static func matchesKind(_ kind: Kind, groups: Set<Group>, kinds: Set<Kind>) -> Bool {
        let group = kind.group
        if !groups.isEmpty && !groups.contains(group) { return false }
        let narrowed = kinds.filter { $0.group == group }
        return narrowed.isEmpty || narrowed.contains(kind)
    }

    static func count(_ facts: [Fact], _ filters: Filters, workflowOn: Bool) -> Int {
        facts.reduce(0) { $0 + (matches($1, filters, workflowOn: workflowOn) ? 1 : 0) }
    }

    /// بعد كل اختيار: نوع لم تعد مجموعته مختارة يُزال (إزالة شريحة «الشجرة» تزيل أنواعها)
    static func normalize(_ filters: inout Filters) {
        filters.kinds = filters.kinds.filter { filters.groups.contains($0.group) }
    }

    /// عدد خيار واحد في الورقة = النتيجة لو اختير وحده في مجموعته مع بقية الاختيارات (F3: «الأعداد تتبع بقية المجموعات»).
    /// المجموعة: هي وحدها مع أنواعها المختارة؛ النوع: هو وحده بين أنواع مجموعته
    static func probe(_ filters: Filters, status: Status) -> Filters {
        var next = filters
        next.statuses = status == .all ? [] : [status]
        return next
    }

    static func probe(_ filters: Filters, group: Group) -> Filters {
        var next = filters
        next.groups = [group]
        next.kinds = filters.kinds.filter { $0.group == group }
        return next
    }

    /// النوع: هو وحده بين أنواع مجموعته، والمجموعات الأخرى وأنواعها باقية (F4 V2) — فالعدد = النتيجة بعد لمسه حين لا أخ له
    /// مختاراً. كان يضع `groups = [kind.group]` فيُسقط «أعضاء» المختارة معها والعدد أقل من النتيجة بعد اللمس
    static func probe(_ filters: Filters, kind: Kind) -> Filters {
        var next = filters
        next.groups.insert(kind.group)
        next.kinds = filters.kinds.filter { $0.group != kind.group }.union([kind])
        return next
    }

    /// طلبات النوع وحده (مع «الحالة» و«المصدر») — هل له صفّ في الورقة. `probe` يعدّ المجموعات الأخرى معه فلا يصلح لهذا
    static func only(_ filters: Filters, kind: Kind) -> Filters {
        var next = filters
        next.groups = [kind.group]
        next.kinds = [kind]
        return next
    }

    /// سبب «لا نتائج» (F4 V7): البحث أولاً كصفحة «تواريخ الوفاة» — حين لا يطابق البحث وحده شيئاً فـ«مسح البحث» هو الحل ولو
    /// كانت تصفية؛ وحين يجد البحث ما تخفيه التصفية فـ«تعديل التصفية»
    enum EmptyCause: Equatable { case search, filters }

    static func emptyCause(searching: Bool, searchedCount: Int, filtersActive: Bool) -> EmptyCause {
        guard searching else { return .filters }
        return searchedCount == 0 || !filtersActive ? .search : .filters
    }

    static func probe(_ filters: Filters, source: Source) -> Filters {
        var next = filters
        next.sources = [source]
        return next
    }

    /// أرقام سطر الرأس — من كل طلبات المجال بلا بحث ولا فلاتر، فلمسة الرقم تفتح قائمة بالعدد نفسه (T2)
    struct HeaderCounts: Equatable {
        var waiting = 0
        var urgent = 0
        var late = 0
    }

    static func headerCounts(_ facts: [Fact], workflowOn: Bool) -> HeaderCounts {
        HeaderCounts(waiting: count(facts, Filters(status: .waiting), workflowOn: workflowOn),
                     urgent: count(facts, Filters(status: .urgent), workflowOn: workflowOn),
                     late: count(facts, Filters(status: .late), workflowOn: workflowOn))
    }

    // MARK: المخازن (قوائم «الوارد») وحالها

    /// القوائم التي يجلبها «الوارد» — كل واحدة جلب مستقل (نموذج العرض يبتلع خطأه، فالفشل = انتهى الجلب والجهاز غير متصل،
    /// أو `-tmpFailStores inbox`)
    enum Store: String, CaseIterable, Hashable {
        case joins, names, phones, deceased, children, treeEdits, news, reports, photos, diwaniyas, projects, archive, policy

        var title: String {
            switch self {
            case .joins:     return L10n.t("طلبات الانضمام", "join requests")
            case .names:     return L10n.t("طلبات تغيير الاسم", "name changes")
            case .phones:    return L10n.t("طلبات تغيير الرقم", "phone changes")
            case .deceased:  return L10n.t("بلاغات الوفاة", "death reports")
            case .children:  return L10n.t("طلبات إضافة الأبناء", "child additions")
            case .treeEdits: return L10n.t("طلبات الشجرة", "tree requests")
            case .news:      return L10n.t("الأخبار", "news")
            case .reports:   return L10n.t("البلاغات", "reports")
            case .photos:    return L10n.t("الصور المقترحة", "suggested photos")
            case .diwaniyas: return L10n.t("الديوانيات", "diwaniyas")
            case .projects:  return L10n.t("المشاريع", "projects")
            case .archive:   return L10n.t("المكتبة", "library")
            case .policy:    return L10n.t("طلبات الخصوصية", "privacy requests")
            }
        }

        /// الأنواع التي تملأها هذه القائمة (الخصوصية بابها مستقل)
        var kinds: [Kind] {
            switch self {
            case .joins:     return [.joinRequests]
            case .names:     return [.nameChange]
            case .phones:    return [.phone]
            case .deceased:  return [.deceased]
            case .children:  return [.children]
            case .treeEdits: return [.treeAdd, .treeEditName, .treeEditPhone, .treeEditBirth, .treeDeceased,
                                     .treeAddDeathDate, .treeAddPhoto, .treeDelete, .treeOther]
            case .news:      return [.news]
            case .reports:   return [.reports]
            case .photos:    return [.photos]
            case .diwaniyas: return [.diwaniya]
            case .projects:  return [.projects]
            case .archive:   return [.archive]
            case .policy:    return []
            }
        }

        /// جانب المحتوى — `-tmpFailStores inbox` يُفشله وحده: المالك يرى سطر «تعذّر تحميل …» فوق طلبات الشجرة، والمشرف
        /// (المحتوى كله مجاله) بطاقة الخطأ، والمراقب سطر «الصور المقترحة»
        var isContent: Bool {
            switch self {
            case .news, .reports, .photos, .diwaniyas, .projects, .archive: return true
            default: return false
            }
        }

        /// تخصّ الدور: أحد أنواعها في مجاله (والخصوصية دائماً — بابها يظهر بعدده)
        func isRelevant(to kinds: Set<Kind>) -> Bool {
            self == .policy || self.kinds.contains(where: kinds.contains)
        }
    }

    /// ما يُرسم مكان القائمة من حال مخازنها
    enum Phase: Equatable {
        /// أول تحميل ولا شيء في اليد — هيكل الصفوف
        case loading
        case loaded
        /// بعضها فشل بلا بيانات والباقي وصل: الصفوف + سطر «تعذّر تحميل …» + «أعد المحاولة»
        case partial([Store])
        /// كلها فشلت بلا بيانات: بطاقة الخطأ (لا «لا طلبات» أبداً)
        case failed
        /// فشل تحديث بعد تحميل ناجح: الصفوف القديمة + «آخر تحديث 9:12» + «أعد المحاولة»
        case stale(since: Date, stores: [Store])
        /// قوائم تُعاد («أعد المحاولة») وغيرها في اليد: الصفوف باقية + سطر صغير «جارٍ تحميل …» — لا هيكل فوق بيانات (F2)
        case refreshing([Store])
    }

    static func isSettled(_ health: AdminStoreHealth) -> Bool {
        switch health {
        case .idle, .loading: return false
        default:              return true
        }
    }

    /// الحال الواحد من مخازن الدور (`relevant`). أثناء إعادة المحاولة تبقى الصفوف الموجودة (لا هيكل فوق بيانات)
    static func phase(_ health: [Store: AdminStoreHealth], relevant: [Store]) -> Phase {
        guard !relevant.isEmpty else { return .loaded }
        let states = relevant.map { health[$0] ?? .idle }
        let anyData = states.contains { $0.hasData }
        let settled = zip(relevant, states).filter { isSettled($0.1) }
        if settled.count < relevant.count && !anyData && !settled.contains(where: { $0.1 == .failed(lastGood: nil) }) {
            return .loading
        }
        let failedNow = settled.filter { $0.1 == .failed(lastGood: nil) }.map(\.0)
        if !failedNow.isEmpty {
            return failedNow.count == relevant.count ? .failed : .partial(failedNow)
        }
        let stale = settled.compactMap { pair -> (Store, Date)? in
            if case .failed(let d?) = pair.1 { return (pair.0, d) }
            return nil
        }
        if let oldest = stale.map(\.1).min() { return .stale(since: oldest, stores: stale.map(\.0)) }
        // هنا ما لم يصل بعد يُجلب وغيره في اليد (أول سطر أعلاه يأخذ «لا شيء في اليد») — الصفوف تبقى (F2)
        let running = zip(relevant, states).filter { !isSettled($0.1) }.map(\.0)
        return running.isEmpty ? .loaded : .refreshing(running)
    }

    /// حال قائمة بعد انتهاء جلبها. أُلغي الجلب (غادر «الوارد»: دفع صفحة، رجوع) = ما كانت عليه قبله — `idle` يبقى هيكلاً
    /// يُعاد جلبه في الظهور التالي، والفشل يبقى بـ«أعد المحاولة» — لا «وصلت» لجلب لم يكتمل (F2)
    static func ended(before: AdminStoreHealth?, running: AdminStoreHealth?, success: Bool, cancelled: Bool,
                      at date: Date = Date()) -> AdminStoreHealth {
        if cancelled { return before ?? .idle }
        return (running ?? .loading).ending(success: success, at: date)
    }

    /// الطلب المطلوب (`focusId` — إشعار، «اليوم»، «إشعارات الإدارة»): يُبحث في كل الطلبات المعلّقة بلا فلاتر المستخدم
    enum FocusOutcome: Equatable {
        /// وُجد: يُفتح مربّعه فوق «الوارد»
        case open
        /// طلب خصوصية/قرابة: تُدفع صفحتها عليه
        case policy
        /// ما زال شيء يُحمَّل
        case wait
        /// لم يوجد وكل القوائم وصلت: «هذا الطلب عولج من قبل» (هادئة)
        case handledBefore
        /// لم يوجد وقائمة فشلت (قد يكون فيها): «تعذّر التحميل» + «أعد المحاولة» — لا كلمة هادئة
        case failed
    }

    static func focusOutcome(inPending: Bool, inPolicy: Bool, health: [Store: AdminStoreHealth],
                             relevant: [Store]) -> FocusOutcome {
        if inPending { return .open }
        if inPolicy { return .policy }
        let states = relevant.map { health[$0] ?? .idle }
        if states.contains(where: { !isSettled($0) }) { return .wait }
        let allLoaded = states.allSatisfy { if case .loaded = $0 { return true } else { return false } }
        return allLoaded ? .handledBefore : .failed
    }
}

// MARK: - النصوص (المكان الواحد)

nonisolated enum AdminInboxText {
    /// اختيار المعدود بالعربية: ١ مفرد، ٢ مثنى، ٣–١٠ جمع، ١١–٩٩ تمييز منصوب، وغيرها مفرد
    static func arabic(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        switch n % 100 {
        case 3...10:  return few
        case 11...99: return many
        default:      return one
        }
    }

    /// «12 طلباً» — المعدود بعد الرقم
    static func requestsNoun(_ n: Int) -> String {
        L10n.t(arabic(n, one: "طلب", two: "طلبان", few: "طلبات", many: "طلباً"), n == 1 ? "request" : "requests")
    }

    /// «3 طلبات» كاملة
    static func requests(_ n: Int) -> String {
        "\(n) \(requestsNoun(n))"
    }

    /// سطر «رسائل الأعضاء»: «7 جديدة · 2 بانتظار الرد» — nil حين لا جديد ولا منتظر (لا كلمة هادئة قبل التحقق)
    static func messagesLine(unread: Int, awaiting: Int) -> String? {
        var parts: [String] = []
        if unread > 0 { parts.append(L10n.t("\(unread) جديدة", "\(unread) new")) }
        if awaiting > 0 { parts.append(L10n.t("\(awaiting) بانتظار الرد", "\(awaiting) awaiting reply")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «طلبات الخصوصية»: «2 بانتظار الرد»
    static func policyLine(_ n: Int) -> String {
        L10n.t("\(n) بانتظار الرد", "\(n) awaiting a reply")
    }

    /// «بانتظار المراجعة»: «3 طلبات مقبولة تنتظر مراجعتك»
    static func postReviewLine(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 approved request awaits your review" : "\(n) approved requests await your review" }
        if n == 1 { return "طلب مقبول ينتظر مراجعتك" }
        if n == 2 { return "طلبان مقبولان ينتظران مراجعتك" }
        return "\(n) " + arabic(n, one: "طلب مقبول ينتظر مراجعتك", two: "", few: "طلبات مقبولة تنتظر مراجعتك",
                                many: "طلباً مقبولاً ينتظر مراجعتك")
    }

    /// سطر الفشل الجزئي: «تعذّر تحميل الصور المقترحة» · «تعذّر تحميل: الأخبار، البلاغات»
    static func failedLine(_ stores: [AdminInboxLogic.Store]) -> String {
        let names = stores.map(\.title)
        if names.count == 1 { return L10n.t("تعذّر تحميل \(names[0])", "Couldn't load \(names[0])") }
        return L10n.t("تعذّر تحميل: ", "Couldn't load: ") + names.joined(separator: L10n.t("، ", ", "))
    }

    /// سطر إعادة المحاولة فوق الصفوف الباقية: «جارٍ تحميل الصور المقترحة…» · «جارٍ تحميل: الأخبار، البلاغات…»
    static func refreshingLine(_ stores: [AdminInboxLogic.Store]) -> String {
        let names = stores.map(\.title)
        if names.count == 1 { return L10n.t("جارٍ تحميل \(names[0])…", "Loading \(names[0])…") }
        return L10n.t("جارٍ تحميل: ", "Loading: ") + names.joined(separator: L10n.t("، ", ", ")) + "…"
    }

    /// «الموافقة على كل طلبات إضافة ابن (6)»
    static func approveAllChildren(_ n: Int) -> String {
        L10n.t("الموافقة على كل طلبات إضافة ابن (\(n))", "Approve all child additions (\(n))")
    }

    /// سؤال الموافقة الجماعية (spec A.14: السؤال بالفعل)
    static func bulkApproveQuestion(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "Approve 1 request?" : "Approve \(n) requests?" }
        if n == 1 { return "قبول الطلب؟" }
        if n == 2 { return "قبول الطلبين؟" }
        return "قبول \(requests(n))؟"
    }

    static func bulkRejectQuestion(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "Reject 1 request?" : "Reject \(n) requests?" }
        if n == 1 { return "رفض الطلب؟" }
        if n == 2 { return "رفض الطلبين؟" }
        return "رفض \(requests(n))؟"
    }

    /// «3 محدّد»
    static func selected(_ n: Int) -> String {
        L10n.t("\(n) محدّد", "\(n) selected")
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - صفّ الطلب (spec C.2 البند ٦، mock 2)

/// ما يرسمه صفّ واحد في بطاقة يومه — يبنيه «الوارد» و«المنجز» من الطلب
struct AdminInboxRowModel {
    /// لون سطر الحالة: «بانتظار قرارك» بالذهبي النصّي، والمرحلة والباقي رمادي
    enum StateTone { case mine, neutral }

    struct Pill {
        let title: String
        let tone: AdminPillTone
    }

    /// مقدّم الطلب (أو صاحب المحتوى)
    var name: String
    /// صورة المرسل أو أول حرف من اسمه
    var avatarName: String
    var avatarURL: String?
    var avatarTint: Color = DS.Color.brand
    /// نوع الطلب على ركن الصورة — رمز أبيض على تعبئة ثابتة
    var typeIcon: String
    var typeFill: Color
    /// «8:40 ص» (اليوم في عنوان المجموعة)
    var time: String
    /// ما يطلبه: «يطلب إضافة ابن: محمد»
    var ask: String
    var pills: [Pill] = []
    var stateWord: String? = nil
    var stateTone: StateTone = .neutral
    /// وصل خلال يوم ولم يُفتح على هذا الجهاز (`InboxSeenStore`) — نقطة ذهبية بجانب الوقت
    var isNew: Bool = false

    /// جملة القارئ الصوتي
    var spoken: String {
        ([name, ask] + pills.map(\.title) + [stateWord, time.isEmpty ? nil : time, isNew ? L10n.t("جديد", "New") : nil])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: L10n.t("، ", ", "))
    }
}

/// الصفّ: صورة ٤٠ وعلى ركنها رمز النوع ← الاسم (١٥ متوسط) وفي طرفه الوقت (١٣ رمادي) ← ما يطلبه (١٥) ← سطر الحالة
/// (حبّة «عاجل»/«متأخر» + كلمة المرحلة). جزء من بطاقة يومه (`dsGroupedRow`)
struct AdminInboxRow: View {
    let model: AdminInboxRowModel
    let position: DSGroupPosition
    var selecting: Bool = false
    var picked: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: DSNoticeMetrics.gap) {
            if selecting {
                DSNoticeSelectCircle(picked: picked, tint: AppSection.admin.ink)
                    .frame(height: DS.Icon.avatar)
            }
            avatar
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // من أحجام إمكانية الوصول: الوقت تحت الاسم (لا يضغط الاسم)
                if typeSize.isAccessibilitySize {
                    nameText
                    timeLabel
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        nameText
                        Spacer(minLength: DS.Spacing.xs)
                        timeLabel
                    }
                }
                if !model.ask.isEmpty {
                    Text(model.ask)
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.pills.isEmpty || model.stateWord != nil {
                    stateLine.padding(.top, DS.Spacing.xxs)
                }
            }
        }
        .padding(.horizontal, DSNoticeMetrics.paddingH)
        .padding(.vertical, DSNoticeMetrics.paddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .dsGroupedRow(position, radius: DS.Hub.cardRadius,
                      dividerInset: DSNoticeMetrics.dividerInset(icon: DS.Icon.avatar, selecting: selecting),
                      highlight: selecting && picked ? AppSection.admin.ink.opacity(DS.Opacity.tintFill) : nil)
    }

    private var nameText: some View {
        Text(model.name)
            .dsFont(.rowTitle)
            .foregroundColor(DS.Color.textPrimary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var timeLabel: some View {
        if model.isNew || !model.time.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                if model.isNew { DSGoldDot(size: DSNoticeMetrics.unreadDot) }
                if !model.time.isEmpty {
                    Text(verbatim: model.time)
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }
    }

    /// الحبّات ثم كلمة المرحلة — تلتفّ لسطر ثانٍ إن ضاق (لا قصّ)
    private var stateLine: some View {
        DSChipFlow(spacing: DS.Spacing.sm, lineSpacing: DS.Spacing.xs) {
            ForEach(Array(model.pills.enumerated()), id: \.offset) { _, pill in
                AdminStatePill(title: pill.title, tone: pill.tone)
            }
            if let word = model.stateWord {
                Text(word)
                    .dsFont(model.stateTone == .mine ? .chip : .subtitle)
                    .foregroundColor(model.stateTone == .mine ? DS.Color.accent : DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: DS.Hub.filterChipHeight - DS.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// صورة المرسل وعلى ركنها رمز النوع بتعبئته (رمز أبيض بحلقة بلون السطح) — نفس صفوف «رسائل الأعضاء»
    private var avatar: some View {
        DSMemberAvatar(name: model.avatarName, avatarUrl: model.avatarURL, size: DS.Icon.avatar,
                       roleColor: model.avatarTint)
            .overlay(alignment: .bottomTrailing) {
                Image(dsSymbol: model.typeIcon)
                    .dsGlyph(DSNoticeMetrics.kindBadgeGlyph, weight: .bold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DSNoticeMetrics.kindBadge, height: DSNoticeMetrics.kindBadge)
                    .background(Circle().fill(model.typeFill))
                    .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Border.widthBold))
                    .offset(x: L10n.isArabic ? -DS.Spacing.xs : DS.Spacing.xs, y: DS.Spacing.xs)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - صفّ الباب

/// صفّ يفتح صفحة (spec A.6): مربّع ٣٠ ممتلئ · العنوان ١٥ · سطر ١٣ رمادي · قيمة ١٥ شبه عريضة · سهم. ضغطته تظليل لا تصغير
struct AdminInboxDoorRow: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var hint: String = L10n.t("يفتح الصفحة", "Opens the page")
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AdminListRow(icon: icon, tint: tint, title: title, subtitle: subtitle) {
                if let value { AdminRowValue(text: value) }
            }
        }
        .buttonStyle(AdminRowPressStyle())
        .accessibilityHint(hint)
    }
}

// MARK: - سطر إعادة المحاولة (F2)

/// «جارٍ تحميل الصور المقترحة…» فوق الصفوف الباقية أثناء «أعد المحاولة» — ١٣ رمادي برمز ↻ ثابت، مكان بطاقة الفشل؛
/// لا هيكل يخفي ما في اليد ولا دوّارة عارية
struct AdminInboxRefreshLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.clockwise")
                .dsGlyph(DS.Glyph.sm)
        }
        .dsFont(.subtitle)
        .foregroundColor(DS.Color.textTertiary)
        .padding(.horizontal, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - رأس الجذر داخل القائمة

/// رأس «الوارد» (spec A.3/C.2) بقطع رأس الأقسام نفسها: «‹ الإدارة» ← «الوارد ⌄» (قائمة الأقسام) + ⚙︎ و«تحديد» ← سطر المجال
/// ← «للاطلاع» بقفل ← سطر الأرقام. يُرسم في أول خلية من `List` (يتمرّر مع الصفوف)، فالرجوع يُمرَّر من خارج القائمة
/// (`dismiss` داخل خلية `List` لا يُخرج الصفحة — مثل `AdminPageBand`)
struct AdminInboxBand<Trailing: View>: View {
    let backTitle: String?
    let onBack: () -> Void
    var subtitle: String? = nil
    var readOnly: Bool = false
    var items: [AdminHeaderItem] = []
    /// مربّعات «الطلبات · المنجزة · الرسائل» تحت سطر الأرقام (`AdminInboxTileRow`)
    var tiles: AnyView? = nil
    /// سطر البحث و«تصفية» على الكحلي تحت المربّعات (`AdminMembersFilterBar` — شكل «العائلة»)
    var accessory: AnyView? = nil
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminHeaderLead(backTitle: backTitle, onBack: backTitle == nil ? nil : onBack, subtitle: subtitle) {
                // العنوان قائمة الأقسام (خلف `AnyView` — حارس المكدس)
                AnyView(AdminAreaTitleMenu(title: AdminArea.inbox.title))
            } trailing: {
                trailing()
            }
            if readOnly {
                AdminBandChip(text: AdminPageHeader.readOnlyText, icon: "lock.fill")
            }
            if !items.isEmpty {
                AnyView(AdminHeaderLine(items: items))
            }
            if let tiles {
                tiles.padding(.top, DS.Hub.inboxTilesTop)
            }
            if let accessory {
                accessory.padding(.top, DS.Spacing.md)
            }
        }
        .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
        .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
        .padding(.top, DS.Hub.headerTop)
        .padding(.bottom, tiles != nil || accessory != nil ? DS.Hub.headerBottom
                          : (items.isEmpty ? DS.Hub.headerBottom : DS.Hub.headerBottomLine))
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminBandBackground(landscape: landscape)
        .dsLightStatusBar()
    }
}

// MARK: - شريط التحديد

/// وضع «تحديد» (spec C.2): أسفل الشاشة، أبيض بخطّ رفيع فوقه — «3 محدّد» · «تحديد الكل»، ثم «قبول (3)» الكحلي و«رفض (3)»
/// الأحمر الخفيف (لمن يملكه). كلاهما يسأل قبل التنفيذ
struct AdminInboxSelectionBar: View {
    let count: Int
    let allPicked: Bool
    let canPickAll: Bool
    let canReject: Bool
    let busy: Bool
    let onToggleAll: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                Text(verbatim: AdminInboxText.selected(count))
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onToggleAll) {
                    Text(allPicked ? L10n.t("إلغاء تحديد الكل", "Deselect all") : L10n.t("تحديد الكل", "Select all"))
                        .dsFont(.button)
                        .foregroundColor(AppSection.admin.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .disabled(!canPickAll)
            }
            let buttons = Group {
                DSButton(count > 0 ? L10n.t("قبول (\(count))", "Approve (\(count))") : L10n.t("قبول", "Approve"),
                         icon: "checkmark", action: onApprove)
                    .disabled(count == 0 || busy)
                if canReject {
                    Button(action: onReject) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "xmark").dsGlyph(DS.Glyph.md, weight: .semibold)
                            Text(count > 0 ? L10n.t("رفض (\(count))", "Reject (\(count))") : L10n.t("رفض", "Reject"))
                        }
                        .modifier(DSSoftDestructiveFace(enabled: count > 0 && !busy))
                    }
                    .buttonStyle(DSPressStyle())
                    .disabled(count == 0 || busy)
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: DS.Spacing.sm) { buttons }
            } else {
                HStack(spacing: DS.Spacing.sm) { buttons }
            }
        }
        .dsPageMargin()
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Hub.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { AdminRowDivider() }
    }
}

// MARK: - وقت الصفّ

/// «8:40 ص» — وقت الصفّ في بطاقة يومه (التاريخ في عنوان اليوم)، أرقام لاتينية كبقية اللوحة. بلا تاريخ = فارغ
enum AdminInboxClock {
    static func text(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        return (L10n.isArabic ? ar : en).string(from: date)
    }

    private static let ar = formatter("ar@numbers=latn")
    private static let en = formatter("en_US")

    private static func formatter(_ locale: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: locale)
        f.dateFormat = "h:mm a"
        return f
    }
}

// MARK: - تعبئات رمز النوع

enum AdminInboxTypeFill {
    /// تعبئة ثابتة تحت الرمز الأبيض (لا تفتح في الداكن) — من عائلة الكحلي والذهبي بمعنى النوع
    static func fill(for tint: Color) -> Color {
        if tint == DS.Color.palm { return DS.Color.palmFill }
        if tint == DS.Color.sea { return DS.Color.seaFill }
        if tint == DS.Color.sadu { return DS.Color.saduFill }
        if tint == DS.Color.slate || tint == DS.Color.deceased { return DS.Color.slateFill }
        if tint == DS.Color.accent { return DS.Color.goldFill }
        if tint == DS.Color.error { return DS.Color.errorFill }
        if tint == DS.Color.female { return DS.Color.femaleFill }
        return DS.Color.primaryFill
    }
}

#endif
