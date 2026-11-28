import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
import Supabase
import Combine
#endif

// MARK: - «صلاحيات الأعضاء حسب الفئة» (طلب المالك ٢٠٢٦-١١-٢٧)
//
// «بالادارة في الفريق والامان … بشكل عام مو مخصوص … زوج البنت شنو يقدر يشوف، بنت البنت شنو تقدر تشوف». جدول واحد على
// السيرفر: `app_config.member_category_access` (json) = {الفئة: {مفتاح الشاشة: true|false}}، يُقرأ عبر `app_config()`
// (`AppConfigValues`) ويغيّره المالك وحده بـ`set_app_config` (فحص `trg_app_config_member_access_guard`).
// • الفئة يحدّدها السيرفر من الحساب نفسه (`my_member_category()`)، لا تُختار لكل شخص — القاعدة نفسها في `category(_:)`.
// • الإدارة الأربعة وغير المفعّل خارج الجدول (يرون كل شيء).
// • مفتاح أو فئة أو خانة غائبة = الافتراضي = ما هو عليه اليوم: كل شيء ظاهر، و«عضو بصلاحيات محدودة» بلا الخمسة
//   (`outside_member_locked_sections` القديم احتياطاً — لا يتعطّل ما دام الجدول لا يذكر الخانة).
// • الأم المطفأة تخفي كل أبنائها (الشاشة ← ما بداخلها)، وقيم الأبناء نفسها تبقى فترجع حين تُشغَّل الأم.
// • الإبلاغ والحظر ليسا في الجدول أبداً (قاعدة المالك «اجباري على الكل ظاهر» + شرط Apple) — مفتاح فيه report/block
//   يُرمى هنا ويرفضه السيرفر. و«حسابي» نفسه لا يُخفى (حذف الحساب والإعدادات والخروج) — ما بداخله فقط.
// • المخفي غائب ببساطة — لا رسالة ولا قفل.
// السيرفر يفرض المهم: سياسات القراءة (الديوانيات، المشاريع، المكتبة، شجرة النساء عبر `lineage_locked`) ورقم الهاتف في
// `members_masked` (`member_details.contact`)، وسياسات الإدراج للنشر والتعليق والإعجاب والتصويت والإضافة.
//
// الجزء الأول منطق خالص يُفحص بلا محاكي (`tests/admin-redesign/P2/main.swift`).

/// فئة العضو — المفاتيح كما يرجعها `my_member_category()` على السيرفر
nonisolated enum MemberCategory: String, CaseIterable, Hashable {
    case familyMan = "family_man"
    case familyWoman = "family_woman"
    case daughterSon = "daughter_son"
    case daughterDaughter = "daughter_daughter"
    case limited
    /// «لم يستكمل التسجيل» (بند ١٣، المالك ٢٠٢٦-١١-٢٧): صفّ نسب بلا `completed_at` ولا `limited_at` — افتراضه افتراض ابن البنت
    case incomplete
    case outsideSpouse = "outside_spouse"

    var titleAr: String {
        switch self {
        case .familyMan: return "عضو من العائلة"
        case .familyWoman: return "نساء العائلة"
        case .daughterSon: return "ابن بنت"
        case .daughterDaughter: return "بنت بنت"
        case .limited: return "عضو بصلاحيات محدودة"
        case .incomplete: return "لم يستكمل التسجيل"
        case .outsideSpouse: return "زوج أو زوجة من خارج العائلة"
        }
    }
    var titleEn: String {
        switch self {
        case .familyMan: return "Family member"
        case .familyWoman: return "Family women"
        case .daughterSon: return "Daughter's son"
        case .daughterDaughter: return "Daughter's daughter"
        case .limited: return "Limited member"
        case .incomplete: return "Registration not completed"
        case .outsideSpouse: return "Spouse from outside the family"
        }
    }
    /// من يدخل الفئة — سطر تحت العنوان في صفحتها
    var whoAr: String {
        switch self {
        case .familyMan: return "رجال العائلة أصحاب الحسابات"
        case .familyWoman: return "بنات العائلة أصحاب الحسابات"
        case .daughterSon: return "أبناء البنات من خارج العائلة"
        case .daughterDaughter: return "بنات البنات من خارج العائلة"
        case .limited: return "من أجاب «لا» على «هل الأم من العائلة؟»"
        case .incomplete: return "أبناء وبنات البنات قبل استكمال التسجيل"
        case .outsideSpouse: return "أزواج البنات والزوجات من عائلات أخرى"
        }
    }
    var whoEn: String {
        switch self {
        case .familyMan: return "Men of the family with an account"
        case .familyWoman: return "Women of the family with an account"
        case .daughterSon: return "Sons of the family's daughters"
        case .daughterDaughter: return "Daughters of the family's daughters"
        case .limited: return "Answered “No” to “Is your mother from the family?”"
        case .incomplete: return "Daughters' sons and daughters before completing registration"
        case .outsideSpouse: return "Daughters' husbands and wives from other families"
        }
    }
    var symbol: String {
        switch self {
        case .familyMan: return "person.fill"
        case .familyWoman: return "person.fill"
        case .daughterSon: return "figure.and.child.holdinghands"
        case .daughterDaughter: return "figure.and.child.holdinghands"
        case .limited: return "lock.fill"
        case .incomplete: return "hourglass"
        case .outsideSpouse: return "heart.fill"
        }
    }
}

/// الشاشات وما بداخلها — المفتاح ثابت (`الشاشة.الداخل`) وهو نفسه في `private.member_access_keys()` على السيرفر.
/// الترتيب = ترتيب العرض في صفحة المالك.
nonisolated enum MemberScreen: String, CaseIterable, Hashable {
    case news
    case newsAdd = "news.add"
    case newsComment = "news.comment"
    case newsLike = "news.like"
    case newsPolls = "news.polls"

    case tree
    case treeSearch = "tree.search"
    case treeMyLocation = "tree.my_location"
    case treeKinship = "tree.kinship"

    case womenTree = "women_tree"
    case womenTreeDetails = "women_tree.details"
    case womenTreeEditRequest = "women_tree.edit_request"

    case memberDetails = "member_details"
    case memberDetailsEditRequest = "member_details.edit_request"
    case memberDetailsKinship = "member_details.kinship"
    case memberDetailsContact = "member_details.contact"
    case memberDetailsMyRequests = "member_details.my_requests"
    case memberDetailsFamily = "member_details.family"

    case diwaniyas
    case diwaniyasAdd = "diwaniyas.add"

    case projects
    case projectsAdd = "projects.add"

    case library
    case libraryAdd = "library.add"

    case contact

    case notifications

    case profile
    case profileMyFamily = "profile.my_family"
    case profileEditInfo = "profile.edit_info"
    case profileChangePhone = "profile.change_phone"
    case profileQR = "profile.qr"
    /// «الطلبات المرسلة» (= «طلباتي»، 20261128151000)
    case profileMyRequests = "profile.my_requests"
    /// الصورة الشخصية (معاينتها وتغييرها)
    case profilePhoto = "profile.photo"

    /// الشاشة الأم (nil = شاشة)
    var parent: MemberScreen? {
        guard let dot = rawValue.firstIndex(of: ".") else { return nil }
        return MemberScreen(rawValue: String(rawValue[..<dot]))
    }
    var children: [MemberScreen] { Self.allCases.filter { $0.parent == self } }
    static var screens: [MemberScreen] { allCases.filter { $0.parent == nil } }

    /// «حسابي» نفسه لا يُخفى (حذف الحساب والإعدادات والخروج) — ما بداخله فقط له مفتاح
    var isLocked: Bool { self == .profile }

    var titleAr: String {
        switch self {
        case .news: return "الأخبار"
        case .newsAdd: return "نشر خبر"
        case .newsComment: return "التعليق"
        case .newsLike: return "الإعجاب"
        case .newsPolls: return "الاستطلاعات"
        case .tree: return "شجرة العائلة"
        case .treeSearch: return "البحث"
        case .treeMyLocation: return "«موقعك»"
        case .treeKinship: return "صلة القرابة"
        case .womenTree: return "شجرة النساء"
        case .womenTreeDetails: return "تفاصيل المرأة"
        case .womenTreeEditRequest: return "طلب تعديل"
        case .memberDetails: return "تفاصيل العضو"
        case .memberDetailsEditRequest: return "طلب تعديل"
        case .memberDetailsKinship: return "صلة القرابة"
        case .memberDetailsContact: return "الهاتف والاتصال وواتساب"
        case .memberDetailsMyRequests: return "«طلبك عنه»"
        case .memberDetailsFamily: return "العائلة (الأب والأبناء)"
        case .diwaniyas: return "الديوانيات"
        case .diwaniyasAdd: return "إضافة ديوانية"
        case .projects: return "المشاريع"
        case .projectsAdd: return "إضافة مشروع"
        case .library: return "المكتبة"
        case .libraryAdd: return "إضافة للمكتبة"
        case .contact: return "التواصل مع الإدارة"
        case .notifications: return "الإشعارات"
        case .profile: return "حسابي"
        case .profileMyFamily: return "«عائلتي» (إضافة ابن أو بنت)"
        case .profileEditInfo: return "تعديل بياناتي"
        case .profileChangePhone: return "تغيير الرقم"
        case .profileQR: return "رمز العضو ومسحه"
        case .profileMyRequests: return "«الطلبات المرسلة»"
        case .profilePhoto: return "الصورة الشخصية"
        }
    }
    var titleEn: String {
        switch self {
        case .news: return "News"
        case .newsAdd: return "Post news"
        case .newsComment: return "Comments"
        case .newsLike: return "Likes"
        case .newsPolls: return "Polls"
        case .tree: return "Family tree"
        case .treeSearch: return "Search"
        case .treeMyLocation: return "“Me”"
        case .treeKinship: return "Kinship"
        case .womenTree: return "Women's tree"
        case .womenTreeDetails: return "Woman's details"
        case .womenTreeEditRequest: return "Request a change"
        case .memberDetails: return "Member details"
        case .memberDetailsEditRequest: return "Request edit"
        case .memberDetailsKinship: return "Kinship"
        case .memberDetailsContact: return "Phone, call and WhatsApp"
        case .memberDetailsMyRequests: return "“Your requests about them”"
        case .memberDetailsFamily: return "Family (father and children)"
        case .diwaniyas: return "Diwaniyas"
        case .diwaniyasAdd: return "Add a diwaniya"
        case .projects: return "Projects"
        case .projectsAdd: return "Add a project"
        case .library: return "Library"
        case .libraryAdd: return "Add to the library"
        case .contact: return "Contact the admins"
        case .notifications: return "Notifications"
        case .profile: return "My profile"
        case .profileMyFamily: return "“My family” (add a son or daughter)"
        case .profileEditInfo: return "Edit my details"
        case .profileChangePhone: return "Change number"
        case .profileQR: return "Member code and scan"
        case .profileMyRequests: return "“Sent requests”"
        case .profilePhoto: return "Profile photo"
        }
    }
    var symbol: String {
        switch self {
        case .news: return "newspaper.fill"
        case .tree: return "tree.fill"
        case .womenTree: return "person.2.fill"
        case .memberDetails: return "person.text.rectangle.fill"
        case .diwaniyas: return "sofa.fill"
        case .projects: return "storefront.fill"
        case .library: return "books.vertical.fill"
        case .contact: return "envelope.fill"
        case .notifications: return "bell.fill"
        case .profile: return "person.crop.circle.fill"
        default: return parent?.symbol ?? "circle"
        }
    }
    /// سطر تحت الخيار حين يفرضه السيرفر أيضاً
    var serverNoteAr: String? {
        switch self {
        case .memberDetailsContact: return "الرقم يُخفى من السيرفر أيضاً"
        case .diwaniyas, .projects, .library, .womenTree: return "يُمنع من السيرفر أيضاً"
        default: return nil
        }
    }
}

nonisolated enum MemberAccess {
    static let configKey = "member_category_access"
    /// الافتراضي على السيرفر (20261128151000): ما تراه الفئة حين لا يذكر الجدول الخانة — «لم يستكمل» و«مقيّد»
    static let defaultsKey = "member_category_access_defaults"
    /// المفتاح القديم لـ«الصلاحيات المحدودة» — احتياط حين لا يذكر الجدول الخانة
    static let legacyLimitedKey = "outside_member_locked_sections"
    static let legacyLimitedDefaults: [MemberScreen] = [.diwaniyas, .projects, .library, .womenTree, .memberDetails]

    /// الإبلاغ والحظر خارج الجدول دائماً (قاعدة المالك + Apple) — أي مفتاح فيه report أو block
    static func isProtectedKey(_ key: String) -> Bool {
        key.split(separator: ".").contains { part in part.contains("report") || part.contains("block") }
    }

    /// الإبلاغ والحظر ظاهران لكل فئة مهما كان الجدول — للتوثيق والفحص (لا شيء يقرأ الجدول لهما)
    static func alwaysVisibleSafety(category: MemberCategory?, matrix: Matrix) -> Bool { true }

    /// الجدول كما وصل — المعروف فقط (فئة معروفة × مفتاح معروف × قيمة منطقية)
    struct Matrix: Equatable {
        var rows: [MemberCategory: [MemberScreen: Bool]] = [:]

        init(rows: [MemberCategory: [MemberScreen: Bool]] = [:]) { self.rows = rows }

        init(json: Any?) {
            guard let root = json as? [String: Any] else { return }
            for (catKey, rowAny) in root {
                guard let cat = MemberCategory(rawValue: catKey), let row = rowAny as? [String: Any] else { continue }
                var out: [MemberScreen: Bool] = [:]
                for (k, v) in row {
                    guard !MemberAccess.isProtectedKey(k), let s = MemberScreen(rawValue: k), !s.isLocked,
                          let b = MemberAccess.bool(v) else { continue }
                    out[s] = b
                }
                if !out.isEmpty { rows[cat] = out }
            }
        }

        /// للحفظ (`set_app_config`)
        var json: [String: Any] {
            var out: [String: Any] = [:]
            for (cat, row) in rows where !row.isEmpty {
                out[cat.rawValue] = Dictionary(uniqueKeysWithValues: row.map { ($0.key.rawValue, $0.value) })
            }
            return out
        }
    }

    static func bool(_ v: Any) -> Bool? {
        // NSNumber من JSONSerialization: منطقي فقط (لا 0/1 رقماً)
        if let n = v as? NSNumber {
            #if canImport(ObjectiveC)
            guard CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            #endif
            return n.boolValue
        }
        return v as? Bool
    }

    /// الافتراضي: من السيرفر (`defaults`) إن ذكر الخانة، وإلا كل شيء ظاهر، والمحدود بلا قائمة القفل القديمة
    /// (nil = المفتاح غائب أو ليس قائمة)
    static func defaultValue(_ s: MemberScreen, category: MemberCategory, legacyLimited: [String]?,
                             defaults: Matrix = Matrix()) -> Bool {
        if let v = defaults.rows[category]?[s] { return v }
        guard category == .limited else { return true }
        let locked = legacyLimited ?? legacyLimitedDefaults.map(\.rawValue)
        return !locked.contains(s.rawValue)
    }

    /// قيمة الخانة نفسها (بلا أمّها)
    static func ownValue(_ s: MemberScreen, category: MemberCategory, matrix: Matrix, legacyLimited: [String]?,
                         defaults: Matrix = Matrix()) -> Bool {
        if s.isLocked { return true }
        return matrix.rows[category]?[s] ?? defaultValue(s, category: category, legacyLimited: legacyLimited, defaults: defaults)
    }

    /// يرى؟ — nil = الإدارة أو غير مفعّل (خارج الجدول). الأم المطفأة تخفي أبناءها
    static func sees(_ s: MemberScreen, category: MemberCategory?, matrix: Matrix, legacyLimited: [String]?,
                     defaults: Matrix = Matrix()) -> Bool {
        guard let category else { return true }
        var cur: MemberScreen? = s
        while let c = cur {
            if !ownValue(c, category: category, matrix: matrix, legacyLimited: legacyLimited, defaults: defaults) { return false }
            cur = c.parent
        }
        return true
    }

    /// المالك يغيّر خانة — يُكتب مفتاحها وحده في صفّ الفئة (الباقي يبقى بافتراضه)
    static func setting(_ s: MemberScreen, to value: Bool, category: MemberCategory, matrix: Matrix) -> Matrix {
        guard !s.isLocked else { return matrix }
        var m = matrix
        var row = m.rows[category] ?? [:]
        row[s] = value
        m.rows[category] = row
        return m
    }

    /// «إعادة الافتراضي» — صفّ الفئة يُحذف
    static func resetting(_ category: MemberCategory, matrix: Matrix) -> Matrix {
        var m = matrix
        m.rows[category] = nil
        return m
    }

    static func isCustom(category: MemberCategory, matrix: Matrix) -> Bool {
        !(matrix.rows[category]?.isEmpty ?? true)
    }

    /// كم مخفي: الشاشات المطفأة، والخيارات الداخلية المطفأة تحت شاشة ظاهرة
    static func hiddenCounts(category: MemberCategory, matrix: Matrix, legacyLimited: [String]?,
                             defaults: Matrix = Matrix()) -> (screens: Int, inner: Int) {
        var screens = 0, inner = 0
        for s in MemberScreen.allCases where !s.isLocked {
            let own = ownValue(s, category: category, matrix: matrix, legacyLimited: legacyLimited, defaults: defaults)
            if s.parent == nil {
                if !own { screens += 1 }
            } else if let p = s.parent, sees(p, category: category, matrix: matrix, legacyLimited: legacyLimited, defaults: defaults), !own {
                inner += 1
            }
        }
        return (screens, inner)
    }

    /// سطر بطاقة الفئة: «كل الشاشات» · «5 شاشات مخفية» · «شاشة مخفية · خياران مخفيان»
    static func summaryAr(category: MemberCategory, matrix: Matrix, legacyLimited: [String]?, defaults: Matrix = Matrix()) -> String {
        let c = hiddenCounts(category: category, matrix: matrix, legacyLimited: legacyLimited, defaults: defaults)
        if c.screens == 0 && c.inner == 0 { return "كل الشاشات" }
        var parts: [String] = []
        if c.screens > 0 { parts.append(count(c.screens, one: "شاشة مخفية", two: "شاشتان مخفيتان", few: "شاشات مخفية", many: "شاشة مخفية")) }
        if c.inner > 0 { parts.append(count(c.inner, one: "خيار مخفي واحد", two: "خياران مخفيان", few: "خيارات مخفية", many: "خياراً مخفياً")) }
        return parts.joined(separator: " · ")
    }

    static func summaryEn(category: MemberCategory, matrix: Matrix, legacyLimited: [String]?, defaults: Matrix = Matrix()) -> String {
        let c = hiddenCounts(category: category, matrix: matrix, legacyLimited: legacyLimited, defaults: defaults)
        if c.screens == 0 && c.inner == 0 { return "All screens" }
        var parts: [String] = []
        if c.screens > 0 { parts.append("\(c.screens) hidden screen" + (c.screens == 1 ? "" : "s")) }
        if c.inner > 0 { parts.append("\(c.inner) hidden option" + (c.inner == 1 ? "" : "s")) }
        return parts.joined(separator: " · ")
    }

    private static func count(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        switch n {
        case 1: return one
        case 2: return two
        case 3...10: return "\(n) \(few)"
        default: return "\(n) \(many)"
        }
    }

    // MARK: الفئة — نفس قاعدة `my_member_category()` على السيرفر (احتياط قبل الترحيل)

    struct Facts: Equatable {
        var isStaff: Bool
        var isActive: Bool
        /// `daughter_son_lineage.limited_at`
        var isLimited: Bool
        /// صفّ في `daughter_son_lineage`
        var hasLineageRow: Bool
        /// `daughter_son_lineage.completed_at` (اعتمدت الإدارة الأم) — بلا صفّ: لا معنى له
        var isCompleted: Bool = true
        /// حساب المراجعة (`review_account_ids()`) — يبقى في فئته اليوم ولو لم يستكمل
        var isReviewAccount: Bool = false
        /// عقدته في شجرة النساء لها أمّ، وأبوها غائب أو من خارج العائلة
        var isDaughterChildNode: Bool
        /// عقدته في شجرة النساء `is_outside_family`
        var isOutsideNode: Bool
        var isFemale: Bool
    }

    static func category(_ f: Facts) -> MemberCategory? {
        if f.isStaff || !f.isActive { return nil }
        if f.isLimited { return .limited }
        if f.hasLineageRow && !f.isCompleted && !f.isReviewAccount { return .incomplete }
        if f.hasLineageRow || f.isDaughterChildNode { return f.isFemale ? .daughterDaughter : .daughterSon }
        if f.isOutsideNode { return .outsideSpouse }
        return f.isFemale ? .familyWoman : .familyMan
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - القارئ في التطبيق

/// فئة الحساب الحالي من السيرفر (`my_member_category()`) — قبل الترحيل (PGRST202) من القاعدة نفسها محلياً
@MainActor
final class MemberAccessStore: ObservableObject {
    static let shared = MemberAccessStore()

    /// nil = الإدارة أو لم تصل بعد (= يرى كل شيء — لا يختفي شيء قبل أن نعرف)
    @Published private(set) var category: MemberCategory?
    /// وصلت من السيرفر (لا تُستبدل بالمحلية)
    private var fromServer = false
    private var rpcMissing = false
    private var loadedFor: UUID?
    private var configSub: AnyCancellable?

    init() {
        // الجدول يتغيّر مع `app_config()` — من يراقب هذا المخزن يُعاد رسمه معه
        configSub = AppConfigValues.shared.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    #if DEBUG
    /// `-tmpMemberCategory limited` — يجرّب ما تراه الفئة على المحاكي (نسخة التطوير فقط)
    private let debugOverride: MemberCategory? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tmpMemberCategory"), i + 1 < args.count else { return nil }
        return MemberCategory(rawValue: args[i + 1])
    }()
    #endif

    func refresh(userId: UUID?, force: Bool = false) async {
        #if DEBUG
        if let debugOverride { category = debugOverride; return }
        #endif
        guard let userId else { category = nil; fromServer = false; loadedFor = nil; return }
        if !force, loadedFor == userId, fromServer { return }
        loadedFor = userId
        guard !rpcMissing else { return }
        do {
            let raw: String? = try await SupabaseConfig.client.rpc("my_member_category").execute().value
            category = raw.flatMap(MemberCategory.init(rawValue:))
            fromServer = true
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            if (error as? PostgrestError)?.code == "PGRST202" { rpcMissing = true }
            else { Log.warning("[MemberAccess] my_member_category: \(error.localizedDescription)") }
        }
    }

    /// قبل الترحيل: الفئة من حقائق التطبيق (يُستدعى حين تتغيّر)
    func applyLocal(_ facts: MemberAccess.Facts) {
        #if DEBUG
        if debugOverride != nil { return }
        #endif
        guard !fromServer else { return }
        let next = MemberAccess.category(facts)
        if next != category { category = next }
    }

    var matrix: MemberAccess.Matrix { MemberAccess.Matrix(json: AppConfigValues.shared.values[MemberAccess.configKey]) }
    /// الافتراضي من السيرفر (`member_category_access_defaults`) — لا ثوابت في التطبيق
    var defaults: MemberAccess.Matrix { MemberAccess.Matrix(json: AppConfigValues.shared.values[MemberAccess.defaultsKey]) }

    var legacyLimited: [String]? {
        (AppConfigValues.shared.values[MemberAccess.legacyLimitedKey] as? [Any])?.compactMap { $0 as? String }
    }

    func sees(_ s: MemberScreen) -> Bool {
        MemberAccess.sees(s, category: category, matrix: matrix, legacyLimited: legacyLimited, defaults: defaults)
    }
}

extension Binding where Value == FamilyMember? {
    /// «تفاصيل العضو» مطفأة لفئة المشاهد: الضغط على غيره لا يفتح شيئاً (المخفي غائب — لا مربّع فارغ). بطاقته هو تفتح دائماً
    @MainActor func memberDetailsGate(selfId: UUID?) -> Binding<FamilyMember?> {
        let base = self
        return Binding(get: {
            guard let m = base.wrappedValue else { return nil }
            return m.id == selfId || MemberAccessStore.shared.sees(.memberDetails) ? m : nil
        }, set: { base.wrappedValue = $0 })
    }
}

extension AuthViewModel {
    /// الشاشة أو الخيار ظاهر لفئة هذا الحساب (الإدارة دائماً نعم)
    @MainActor func memberSees(_ s: MemberScreen) -> Bool {
        if canModerate { return true }
        return MemberAccessStore.shared.sees(s)
    }
}

#endif
