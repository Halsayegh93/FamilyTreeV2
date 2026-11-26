import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - عقود لوحة الإدارة المشتركة (إعادة التصميم ٢٠٢٦-١١-٢٦، الوحدة U2)
//
// ما تكتب عليه كل وحدات الصفحات، في مكان واحد:
//  ١) الهبوط (Landing): ماذا يفتح عليه جذر القسم حين يُفتح من رقم أو مربّع أو إشعار — «الوارد» على «عاجل»، «العائلة» على
//     «لهم حساب + الأحياء»، «الإحصاءات» على قسم «في التطبيق»… يُخزَّن في `AdminAreaRouter.landings[hop]` بعدّاد الانتقال
//     الذي تحمله `.area(_, hop)` نفسها (لا حالات جديدة في `AdminReviewDestination`)، ويُقرأ مرة واحدة بـ`take`.
//  ٢) `AdminStoreHealth`: حال كل مخزن تقرأ منه كلمة حالة أو حبّة أو عدد شريحة أو رقم رأس — وقواعد رسمها. كلمة هادئة
//     («سليم»، «يعمل للجميع»، «لا جديد») لا تظهر إلا بعد وصول بياناتها؛ الفشل «تعذّر التحميل» لا كلمة هادئة.
//  ٣) `AuthViewModel.adminCanEdit(_:)`: «يعدّل» في جدول السيرفر — تُضرب (AND) مع صلاحية الدور في كل أمر.
//  ٤) `AdminHeaderItem`: بيانات سطر أرقام الرأس (`AdminHeaderLine` في AdminHubKit.swift).
//
// الجزء الأول منطق خالص (Foundation فقط) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u2-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     tests/admin-redesign/U2/main.swift && /tmp/u2-logic
// والجزء الثاني (SwiftUI والتطبيق) خلف `#if !ADMIN_LOGIC_TEST`.

#if ADMIN_LOGIC_TEST
/// بديل `L10n` في فحص المنطق وحده (التطبيق يستعمل `AppL10n.swift`)
nonisolated enum L10n {
    nonisolated(unsafe) static var isArabic = true
    static func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }
}
#endif

// MARK: - ١) الهبوط

/// قسم من «الإحصاءات» يُمرَّر إليه عند الفتح (spec C.1/C.6/C.12: «في التطبيق 170» و«خارج العائلة 50» يفتحان القسم الذي
/// يقسمهما، فأول رقم يُرى هناك = الرقم المضغوط)
nonisolated enum AdminStatsAnchor: String, CaseIterable, Hashable {
    /// «العائلة» (الحلقات الثلاث + أحياء/متوفون)
    case family
    /// «الراحلون»
    case departed
    /// «في التطبيق»
    case inApp
    /// «جديد في الشجرة»
    case growth
    /// «الأعمار»
    case ages
    /// «الأدوار»
    case roles
    /// «الشجرة»
    case tree
    /// «خارج العائلة»
    case outside
    /// «الموافقات» (المالك والمدير، والمسار مفعّل)
    case approvals
}

/// قسم من «المناسبات والإعلانات» يُمرَّر إليه (سطر الرأس ومربّع «اليوم»: «وفاة لم تُعلن» · «مجدول» · «ذكرى»)
nonisolated enum AdminOccasionsAnchor: String, CaseIterable, Hashable {
    /// «ينتظر إعلاناً» (وفيات لم يُعلن عنها، وأفراح من الأخبار)
    case awaiting
    /// «مجدول»
    case scheduled
    /// «عند فتح التطبيق»
    case launch
    /// «ذكرى الراحلين»
    case memorials
    /// بطاقة الأبواب («المنشور»، «تصل الإشعارات إلى…»)
    case doors
}

/// «العائلة» تُفتح بفلاتر (spec C.7: الحساب · الحالة · الفرع). nil في أي حقل = افتراض الصفحة نفسها.
/// الرابط العميق من مجموع يضبط «الحالة» = الكل صراحةً (Autoplan note 3).
nonisolated struct AdminMembersLanding: Hashable {
    /// نفس قيم `AdminAccountFilter` (all · with · without)
    nonisolated enum Account: String, CaseIterable, Hashable { case all, with, without }
    /// نفس قيم `AdminLifeFilter` (all · alive · deceased)
    nonisolated enum Life: String, CaseIterable, Hashable { case all, alive, deceased }
    /// قائمة مراجعة تُدفع فوق الجذر (الرجوع يعود للجذر) — نفس قيم `AdminMemberReview`
    /// («4 مشكلات في الشجرة» في «اليوم» ← «العائلة» ثم «مشكلات» فوقها)
    nonisolated enum Review: String, CaseIterable, Hashable { case living, death, gaps, problems, notOpened, inactive }

    var account: Account? = nil
    var life: Life? = nil
    /// رأس الفرع (`BranchPickerSheet.familyRoot`) — nil = كل الفروع
    var branch: UUID? = nil
    var review: Review? = nil

    /// الحقول الصريحة (من `init` الصفحة) تغلب الهبوط
    func overridden(by explicit: AdminMembersLanding) -> AdminMembersLanding {
        AdminMembersLanding(account: explicit.account ?? account, life: explicit.life ?? life,
                            branch: explicit.branch ?? branch, review: explicit.review ?? review)
    }
}

/// «نساء العائلة» تُفتح بفلاتر (spec C.9: الحالة · الفرع). nil = افتراض الصفحة («الحيّات»)
nonisolated struct AdminWomenLanding: Hashable {
    nonisolated enum Status: String, CaseIterable, Hashable {
        /// الكل (من مجموع: حلقة «النساء 262»)
        case all
        /// الحيّات — افتراض الصفحة
        case living
        /// مسجّلات («نساء لهن حساب»)
        case registered
        case married
        /// متوفيات
        case deceased
    }
    nonisolated enum Branch: String, CaseIterable, Hashable {
        case all
        /// «فرع خارج العائلة»
        case outside
    }

    var status: Status? = nil
    var branch: Branch? = nil

    func overridden(by explicit: AdminWomenLanding) -> AdminWomenLanding {
        AdminWomenLanding(status: explicit.status ?? status, branch: explicit.branch ?? branch)
    }
}

/// «الوارد» يُفتح بفلاتر (spec C.2: الحالة · المجموعة · النوع · المصدر)
nonisolated struct AdminInboxLanding: Hashable {
    /// نفس قيم `ApprovalListFilter` (all · waiting · urgent · late)
    nonisolated enum Status: String, CaseIterable, Hashable { case all, waiting, urgent, late }
    /// نفس قيم `AdminAllRequestsView.RequestSection`
    nonisolated enum Group: String, CaseIterable, Hashable { case members, tree, content }
    /// نفس قيم `AdminAllRequestsView.RequestTab` (عدا all) — القائمة البيضاء للأنواع
    nonisolated enum Kind: String, CaseIterable, Hashable {
        case joinRequests, nameChange, phone, deceased
        case children, treeAdd, treeEditName, treeEditPhone, treeEditBirth, treeDeceased, treeAddDeathDate,
             treeAddPhoto, treeDelete, treeOther
        case news, reports, photos, diwaniya, projects, archive

        var group: Group {
            switch self {
            case .joinRequests, .nameChange, .phone, .deceased: return .members
            case .children, .treeAdd, .treeEditName, .treeEditPhone, .treeEditBirth, .treeDeceased,
                 .treeAddDeathDate, .treeAddPhoto, .treeDelete, .treeOther: return .tree
            case .news, .reports, .photos, .diwaniya, .projects, .archive: return .content
            }
        }
    }
    /// نفس قيم `AdminRequestSourceKind`
    nonisolated enum Source: String, CaseIterable, Hashable {
        case familyTree, womenTree, profile, registration, contact, content, admin, other
    }

    var status: Status? = nil
    var group: Group? = nil
    var kind: Kind? = nil
    var source: Source? = nil

    /// من نوع الإشعار (`NotificationKind` أو `request_type`) — قائمة بيضاء: نوع غير معروف = «الوارد» بلا فلتر
    init(pushKind: String) {
        switch pushKind {
        case "join_request", "link_request": kind = .joinRequests
        case "name_change":                   kind = .nameChange
        case "phone_change":                  kind = .phone
        case "deceased_report":               kind = .deceased
        case "child_add":                     kind = .children
        case "photo_suggestion":              kind = .photos
        case "news_report", "content_report": kind = .reports
        case "news_add":                      kind = .news
        case "diwaniya_pending":              kind = .diwaniya
        case "project_pending":               kind = .projects
        case "archive_pending":               kind = .archive
        // طلب شجرة بلا معرّف: كل أنواع الشجرة
        case "tree_edit":                     group = .tree
        default: break
        }
        if let kind { group = kind.group }
    }

    init(status: Status? = nil, group: Group? = nil, kind: Kind? = nil, source: Source? = nil) {
        self.status = status
        self.group = kind?.group ?? group
        self.kind = kind
        self.source = source
    }

    /// يُقصّ على أنواع الدور (`tabsForRole` في «الوارد» — قيمها الخام): نوع خارج مجاله يُسقط مع مجموعته (جاءت منه)،
    /// ومجموعة بلا نوع ظاهر لدوره تُسقط — فيفتح «الوارد» بلا فلتر لا على قائمة فارغة لا يملكها. الحالة والمصدر يبقيان
    func clamped(toKinds allowed: Set<String>) -> AdminInboxLanding {
        var out = self
        if let kind, !allowed.contains(kind.rawValue) {
            out.kind = nil
            out.group = nil
        }
        if let group = out.group, out.kind == nil,
           !Kind.allCases.contains(where: { $0.group == group && allowed.contains($0.rawValue) }) {
            out.group = nil
        }
        return out
    }

    func overridden(by explicit: AdminInboxLanding) -> AdminInboxLanding {
        // نوع صريح يجرّ مجموعته معه
        let kind = explicit.kind ?? (explicit.group == nil ? self.kind : nil)
        return AdminInboxLanding(status: explicit.status ?? status, group: explicit.group ?? group,
                                 kind: kind, source: explicit.source ?? source)
    }

    /// لا فلتر فيه
    var isEmpty: Bool { status == nil && group == nil && kind == nil && source == nil }
}

/// هبوط جذر قسم — قيمة واحدة لكل انتقال (`AdminAreaRouter.landings[hop]`)
nonisolated enum AdminLanding: Hashable {
    case stats(AdminStatsAnchor)
    case members(AdminMembersLanding)
    case women(AdminWomenLanding)
    case inbox(AdminInboxLanding)
    case occasions(AdminOccasionsAnchor)
}

/// مفتاح نوعيّ لـ`AdminAreaRouter.take(.inbox, hop:)` — يرجع نوع الهبوط الصحيح أو nil
nonisolated struct AdminLandingKey<Value> {
    let extract: (AdminLanding) -> Value?
}

nonisolated extension AdminLandingKey where Value == AdminStatsAnchor {
    static var stats: Self { .init { if case .stats(let v) = $0 { return v } else { return nil } } }
}
nonisolated extension AdminLandingKey where Value == AdminMembersLanding {
    static var members: Self { .init { if case .members(let v) = $0 { return v } else { return nil } } }
}
nonisolated extension AdminLandingKey where Value == AdminWomenLanding {
    static var women: Self { .init { if case .women(let v) = $0 { return v } else { return nil } } }
}
nonisolated extension AdminLandingKey where Value == AdminInboxLanding {
    static var inbox: Self { .init { if case .inbox(let v) = $0 { return v } else { return nil } } }
}
nonisolated extension AdminLandingKey where Value == AdminOccasionsAnchor {
    static var occasions: Self { .init { if case .occasions(let v) = $0 { return v } else { return nil } } }
}

/// مخزن الهبوطات بعدّاد الانتقال — منطق خالص يحمله `AdminAreaRouter.landings`
nonisolated struct AdminLandingStore {
    private(set) var byHop: [Int: AdminLanding] = [:]

    subscript(hop: Int) -> AdminLanding? {
        get { byHop[hop] }
        set { byHop[hop] = newValue }
    }

    /// هبوط انتقال جديد: يمسح كل ما سبقه (لا يبقى هبوط قديم ينتظر)
    mutating func land(_ landing: AdminLanding?, hop: Int) {
        byHop.removeAll()
        if let landing { byHop[hop] = landing }
    }

    /// يُقرأ مرة واحدة ويُمسح — ولو كان لقسم آخر (قديم لا يُستعمل)
    mutating func take<Value>(_ key: AdminLandingKey<Value>, hop: Int?) -> Value? {
        guard let hop, let landing = byHop.removeValue(forKey: hop) else { return nil }
        return key.extract(landing)
    }

    mutating func clear() { byHop.removeAll() }

    var isEmpty: Bool { byHop.isEmpty }
}

// MARK: - ٢) حال المخزن

/// حال مخزن تُقرأ منه كلمة أو حبّة أو عدد أو رقم رأس (Autoplan note 2). كل مخزن يحصل على محوّل في ملف صاحبه.
/// قاعدة المحوّل: التحديث بعد تحميل ناجح لا يرجع لـ`loading` (الكلمة تبقى) — `beginning()`/`ending(success:)` تفعل ذلك.
nonisolated enum AdminStoreHealth: Hashable {
    /// لم يبدأ الجلب
    case idle
    /// أول جلب جارٍ (أو إعادة محاولة بعد فشل بلا بيانات)
    case loading
    /// وصلت البيانات
    case loaded(at: Date)
    /// فشل الجلب — `lastGood` = وقت آخر بيانات صالحة (nil = لا شيء أبداً)
    case failed(lastGood: Date?)
    /// الدور لا يملك هذا المخزن (42501، أو خارج الجدول) — مخفي أو للاطلاع، بلا «أعد المحاولة»
    case denied

    /// كيف يُرسم ما يقرأ من المخزن
    nonisolated enum Look: Hashable {
        /// هيكل بشكل الكلمة النهائية (`.redacted`، «—»)
        case skeleton
        /// الكلمة
        case word
        /// الكلمة + «آخر تحديث 9:12»
        case staleWord(since: Date)
        /// «تعذّر التحميل» + إعادة المحاولة (لا كلمة هادئة أبداً)
        case unknown
        /// لا شيء (أو للاطلاع) — بلا إعادة محاولة
        case hidden
    }

    var look: Look {
        switch self {
        case .idle, .loading:         return .skeleton
        case .loaded:                 return .word
        case .failed(let d?):         return .staleWord(since: d)
        case .failed(lastGood: nil):  return .unknown
        case .denied:                 return .hidden
        }
    }

    /// وقت آخر بيانات صالحة
    var lastGood: Date? {
        switch self {
        case .loaded(let d): return d
        case .failed(let d): return d
        default:             return nil
        }
    }

    /// في يده بيانات تُعرض (حديثة أو قديمة)
    var hasData: Bool { lastGood != nil }

    /// «أعد المحاولة» مسموح (الفشل فقط — لا للمرفوض)
    var canRetry: Bool { if case .failed = self { return true } else { return false } }

    /// بدء جلب: أول مرة أو بعد فشل بلا بيانات = هيكل؛ ما عنده بيانات يبقى كما هو حتى ينتهي
    func beginning() -> AdminStoreHealth {
        switch self {
        case .idle, .failed(lastGood: nil): return .loading
        default:                            return self
        }
    }

    /// نهاية جلب: نجح = `loaded(at:)`، فشل = `failed` بآخر وقت صالح
    func ending(success: Bool, at date: Date = Date()) -> AdminStoreHealth {
        success ? .loaded(at: date) : .failed(lastGood: lastGood)
    }

    /// حال كلمة تقرأ من عدّة مخازن (رأس بطاقة الحالة، مربّع قسم): المرفوض لا يُحسب؛ فشل بلا بيانات يغلب، ثم
    /// تحميل أول، ثم القديم (بأقدم وقت)، وإلا وصلت كلها (بأقدم وقت)
    static func combined(_ list: [AdminStoreHealth]) -> AdminStoreHealth {
        let live = list.filter { $0 != .denied }
        guard !live.isEmpty else { return list.isEmpty ? .idle : .denied }
        if live.contains(.failed(lastGood: nil)) { return .failed(lastGood: nil) }
        if live.contains(where: { $0 == .idle || $0 == .loading }) { return .loading }
        let stale = live.compactMap { h -> Date? in if case .failed(let d) = h { return d } else { return nil } }
        if let oldest = stale.min() { return .failed(lastGood: oldest) }
        return .loaded(at: live.compactMap(\.lastGood).min() ?? Date())
    }
}

/// نصوص حال المخزن (المكان الواحد)
nonisolated enum AdminStoreHealthText {
    /// قبل وصول الرقم — لا صفر مضلِّل (spec A.10)
    static let placeholder = "—"
    static var failed: String { L10n.t("تعذّر التحميل", "Couldn't load") }
    static var retry: String { L10n.t("أعد المحاولة", "Try again") }
    static var loading: String { L10n.t("جارٍ التحميل", "Loading") }

    /// «آخر تحديث 9:12» · «آخر تحديث أمس 9:12» · «آخر تحديث 24/11» — أرقام لاتينية
    static func updated(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = format(date, "h:mm", calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.t("آخر تحديث \(time)", "Updated \(time)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return L10n.t("آخر تحديث أمس \(time)", "Updated yesterday \(time)")
        }
        let day = format(date, "d/M", calendar: calendar)
        return L10n.t("آخر تحديث \(day)", "Updated \(day)")
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

/// الأرقام: لاتينية بفاصل الآلاف («2,991») — spec A.10
nonisolated enum AdminNumberText {
    static func grouped(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}

/// العدد والمعدود بالعربية (F4، V21/V22/V32) — صيغ المعدود الخمس، والرقم لاتيني بفاصل الآلاف:
/// ١ `one` كاملة («تاريخ وفاة واحد ناقص») · ٢ `two` كاملة («تاريخا وفاة ناقصان») · ٣–١٠ «N few» · ١١–٩٩ «N many»
/// · ١٠٠ وما ينتهي بـ٠٠–٠٢ «N single». (١٠١ و١٠٢ بالرقم أيضاً — لا «واحد» بعد المئة)
nonisolated struct AdminCountForms: Equatable {
    let one: String
    let two: String
    let few: String
    let many: String
    let single: String

    func text(_ n: Int) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        let digits = AdminNumberText.grouped(n)
        switch n % 100 {
        case 3...10:  return "\(digits) \(few)"
        case 11...99: return "\(digits) \(many)"
        default:      return "\(digits) \(single)"
        }
    }
}

// MARK: - ٤) سطر أرقام الرأس — شكل العنصر (منطق خالص)

/// ما يرسمه عنصر في سطر الرأس: الصفر والتحميل والفشل لا تظهر رقماً عادياً أبداً
nonisolated struct AdminHeaderItemLook: Hashable {
    /// «2,729» أو «—»
    var text: String
    /// باهت (`DS.Hub.lineZero`): الصفر، والتحميل، والفشل
    var dim: Bool
    /// يفتح شيئاً (سهم + ضغطة)
    var opens: Bool
    /// فشل بلا بيانات: رمز إعادة المحاولة والضغطة تعيد الجلب
    var retry: Bool
    /// بيانات قديمة بعد فشل — «آخر تحديث» في آخر السطر
    var staleSince: Date?
    /// مرفوض لهذا الدور — لا يُرسم
    var hidden: Bool

    /// - value: العدد (nil = لم يصل)
    /// - text: نصّ بدل العدد حين لا يكون عدداً عادياً («93٪»، «≈ 2,489») — يُعرض بعد الوصول فقط
    /// - health: nil = من القيمة نفسها (لا قيمة = تحميل)
    /// - opens: له ضغطة
    static func make(value: Int?, text: String? = nil, health: AdminStoreHealth?, opens: Bool) -> AdminHeaderItemLook {
        let state = health ?? ((value != nil || text != nil) ? .loaded(at: .distantPast) : .loading)
        var look = AdminHeaderItemLook(text: AdminStoreHealthText.placeholder, dim: true, opens: false,
                                       retry: false, staleSince: nil, hidden: false)
        switch state.look {
        case .hidden:
            look.hidden = true
            return look
        case .skeleton:
            return look
        case .unknown:
            look.retry = true
            return look
        case .word, .staleWord:
            if case .staleWord(let since) = state.look { look.staleSince = since }
            guard value != nil || text != nil else {
                // وصل المخزن بلا هذا الرقم: «—» بلا ضغطة
                return look
            }
            look.text = text ?? AdminNumberText.grouped(value ?? 0)
            let zero = value == 0
            look.dim = zero
            look.opens = opens && !zero
            return look
        }
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - الموجّه: الهبوط بعدّاد الانتقال

extension AdminAreaRouter {
    /// الهبوطات المنتظرة بعدّاد الانتقال (`.area(_, hop)`). تُمسح مع كل `navigate` (قائمة العنوان)، وكل `land` جديد،
    /// وعند إعادة الضغط على التبويب. «اليوم» يمسحها عند مغادرة التبويب، و`AdminAreaGate` في فرع الرفض (`clearLandings()`).
    static var landings = AdminLandingStore() {
        didSet { if !landings.isEmpty { watchTabReselect() } }
    }

    /// «اليوم» (U7) قبل دفع `.area(area, hop)`: هبوط هذا الانتقال وحده (يمسح ما قبله)
    static func land(_ landing: AdminLanding?, hop: Int) {
        landings.land(landing, hop: hop)
    }

    /// جذر القسم يقرأ هبوطه مرة واحدة (في `.task`/`onAppear`، ويحفظه في `@State`) — `take(.inbox, hop: hop)`.
    /// معاملات `init` الصريحة تغلبه (`overridden(by:)`)
    static func take<Value>(_ key: AdminLandingKey<Value>, hop: Int?) -> Value? {
        landings.take(key, hop: hop)
    }

    /// يمسح كل الهبوطات (مغادرة التبويب، رفض البوابة)
    static func clearLandings() {
        guard !landings.isEmpty else { return }
        landings.clear()
    }

    /// إعادة الضغط على تبويب (أي تبويب) تمسح الهبوطات — مراقب واحد يُركَّب عند أول هبوط
    private static var tabReselectWatch: NSObjectProtocol?

    private static func watchTabReselect() {
        guard tabReselectWatch == nil else { return }
        tabReselectWatch = NotificationCenter.default.addObserver(forName: .didReselectTab, object: nil,
                                                                  queue: .main) { _ in
            Task { @MainActor in AdminAreaRouter.clearLandings() }
        }
    }
}

extension AdminLanding {
    /// القسم الذي يملك هذا الهبوط («نساء العائلة» صفحة تحت «العائلة»)
    var area: AdminArea {
        switch self {
        case .stats:     return .metrics
        case .members:   return .family
        case .women:     return .family
        case .inbox:     return .inbox
        case .occasions: return .occasions
        }
    }
}

private struct AdminAreaHopKey: EnvironmentKey { static let defaultValue: Int? = nil }

extension EnvironmentValues {
    /// عدّاد الانتقال الذي فُتحت به صفحة القسم (`.area(_, hop)`) — مفتاح هبوطها في `AdminAreaRouter.take`
    var adminAreaHop: Int? {
        get { self[AdminAreaHopKey.self] }
        set { self[AdminAreaHopKey.self] = newValue }
    }
}

extension View {
    /// على وجهة `.area(area, hop)` في `page(for:)`: الصفحة تعرف عدّاد انتقالها
    func adminAreaHop(_ hop: Int?) -> some View {
        environment(\.adminAreaHop, hop)
    }
}

// MARK: - ٣) «يعدّل» في جدول السيرفر

extension AuthViewModel {
    /// القسم «يشوف ويعدّل» لدورك في جدول السيرفر (`adminAccess(area).canEdit`). كل أمر في صفحات اللوحة يضربها مع صلاحية
    /// الدور (`canApprove`، `canEditMembers`…) — فالقسم «للاطلاع» لا يرسم أزرار تعديل ولو ملكها الدور
    func adminCanEdit(_ area: AdminArea) -> Bool {
        adminAccess(area).canEdit
    }

    /// الخانة «يشوف ويعدّل» في الجدول (`adminAccess(item).canEdit`)
    func adminCanEdit(_ item: AdminRoleItem) -> Bool {
        adminAccess(item).canEdit
    }
}

// MARK: - ٤) عنصر سطر الرأس

/// رقم في سطر الرأس (`AdminHeaderLine`): العدد · الاسم · حال مخزنه · ما يفتحه. الصفر والتحميل والفشل لا تظهر رقماً
/// عادياً أبداً (`AdminHeaderItemLook`). `AdminPageKPI` يبقى نموذج `AdminPage` ويتحوّل إلى هذا في U3.
struct AdminHeaderItem: Identifiable {
    let id: String
    /// العدد — nil = لم يصل («—»)
    var value: Int?
    /// نصّ بدل العدد حين لا يكون عدداً عادياً («93٪») — nil = العدد بفاصل الآلاف
    var text: String? = nil
    /// الاسم بالذهبي («بانتظار قرارك»، «امرأة»)
    let label: String
    /// حال المخزن الذي يقرأ منه — nil = من القيمة (لا قيمة = تحميل)
    var health: AdminStoreHealth? = nil
    /// ما يفتحه — `.none` = رقم بلا سهم
    var tap: AdminPageTap = .none
    /// إعادة جلب هذا المخزن وحده (حين فشل بلا بيانات)
    var retry: (() -> Void)? = nil
    /// جملة القارئ الصوتي بدل «العدد الاسم» (spec A.17)
    var spoken: String? = nil

    init(id: String? = nil, value: Int?, text: String? = nil, label: String, health: AdminStoreHealth? = nil,
         tap: AdminPageTap = .none, retry: (() -> Void)? = nil, spoken: String? = nil) {
        self.id = id ?? label
        self.value = value
        self.text = text
        self.label = label
        self.health = health
        self.tap = tap
        self.retry = retry
        self.spoken = spoken
    }

    var look: AdminHeaderItemLook {
        AdminHeaderItemLook.make(value: value, text: text, health: health, opens: tap.isTappable)
    }
}

#endif
