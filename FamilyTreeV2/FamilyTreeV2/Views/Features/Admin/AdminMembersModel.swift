import SwiftUI
import Combine
import Supabase

// MARK: - «العائلة» = صفحة الأعضاء الواحدة: الحالات الرسمية وإشاراتها (طلب المالك ٢٠٢٦-١٠-٢٠ — PROPOSAL §١ و§١٤)
//
// حالة كل عضو بالمسميات الرسمية، من إشارات العميل الموجودة وحدها (بلا دالة سيرفر جديدة):
//   • متوفى                     = `is_deceased`
//   • طلب انضمام قيد المراجعة   = الدور `pending` — لا يظهر في القائمة؛ رقم يفتح «الوارد» (القرار هناك)
//   • حساب موقوف                = `status = frozen` (حيّ) — يُحسب ضمن «مسجّلون»
//   • عضو مسجّل                 = حيّ له حساب دخول (رابط auth): ظهر في `app_usage_members` بفئة
//                                 active / idle / login_no_device (كلها `has_login` على السيرفر)، أو موقوف
//   • مقيّد في الشجرة            = حيّ بلا حساب دخول — له رقم ولم يسجّل الدخول بعد (never_logged)، أو بلا رقم
// «مفعّل / بانتظار التفعيل» (`status` active/pending) تقسيم تاريخي من دفعات الاستيراد — لا يُعرض ولا تُبنى عليه شريحة.
// قبل وصول قوائم الحسابات: الحالة nil للأحياء غير الموقوفين، وأعداد «مسجّلون/مقيّدون» «—» (لا أصفار مضلِّلة).

/// الحالة الرسمية للعضو
enum AdminMemberStatus: Equatable {
    case registered, treeOnly, frozen, deceased, pendingJoin

    var title: String {
        switch self {
        case .pendingJoin: return L10n.t("طلب انضمام قيد المراجعة", "Join request under review")
        case .registered: return L10n.t("عضو مسجّل", "Registered member")
        case .treeOnly:   return L10n.t("مقيّد في الشجرة", "In the tree only")
        case .frozen:     return L10n.t("حساب موقوف", "Suspended account")
        case .deceased:   return L10n.t("متوفى", "Deceased")
        }
    }

    var tint: Color {
        switch self {
        case .registered: return DS.Color.success
        case .treeOnly:   return DS.Color.slate
        case .frozen:     return DS.Color.error
        case .deceased:   return DS.Color.deceased
        case .pendingJoin: return DS.Color.info
        }
    }

    var icon: String {
        switch self {
        case .pendingJoin: return "person.badge.clock"
        case .registered: return "checkmark.seal.fill"
        case .treeOnly:   return "person.fill"
        case .frozen:     return "hand.raised.fill"
        case .deceased:   return "leaf.fill"
        }
    }
}

/// نقص في بيانات العضو — وزرّ استكماله (أزرار «محطة التفعيل» السابقة نفسها)
enum AdminMemberGap: String, CaseIterable, Identifiable {
    case noBirth, noGender, noPhoto, deathIncomplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noBirth:         return L10n.t("بلا تاريخ ميلاد", "No birth date")
        case .noGender:        return L10n.t("الجنس غير محدّد", "Gender not set")
        case .noPhoto:         return L10n.t("عضو مسجّل بلا صورة", "Registered, no photo")
        case .deathIncomplete: return L10n.t("تاريخ الوفاة غير مكتمل", "Death date incomplete")
        }
    }

    /// الشارة المختصرة في صفّ القائمة
    var tag: String {
        switch self {
        case .noBirth:         return L10n.t("بلا تاريخ ميلاد", "No birth date")
        case .noGender:        return L10n.t("الجنس غير محدّد", "No gender")
        case .noPhoto:         return L10n.t("بلا صورة", "No photo")
        case .deathIncomplete: return L10n.t("تاريخ الوفاة غير مكتمل", "Death date incomplete")
        }
    }

    var fixTitle: String {
        switch self {
        case .noBirth:         return L10n.t("إضافة تاريخ الميلاد", "Add birth date")
        case .noGender:        return L10n.t("تحديد الجنس", "Set gender")
        case .noPhoto:         return L10n.t("إضافة صورة", "Add photo")
        case .deathIncomplete: return L10n.t("استكمال تاريخ الوفاة", "Complete death date")
        }
    }

    var icon: String {
        switch self {
        case .noBirth:         return "calendar.badge.plus"
        case .noGender:        return "person.fill.questionmark"
        case .noPhoto:         return "photo"
        case .deathIncomplete: return "calendar.badge.clock"
        }
    }
}

/// مشكلة في موضع العضو بالشجرة (كانت صفحة «صحة الشجرة») — وزرّ إصلاحها
enum AdminMemberProblem: String, CaseIterable, Identifiable {
    case orphan, noName, brokenParent, hidden, dupPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orphan:       return L10n.t("غير مرتبط بأب", "Not linked to a father")
        case .noName:       return L10n.t("بلا اسم", "No name")
        case .brokenParent: return L10n.t("ارتباط أب غير صالح", "Invalid father link")
        case .hidden:       return L10n.t("مخفي من الشجرة", "Hidden from the tree")
        case .dupPhone:     return L10n.t("رقم هاتف مكرر", "Duplicate phone")
        }
    }

    var fixTitle: String {
        switch self {
        case .orphan:       return L10n.t("ربط بالأب", "Link father")
        case .noName:       return L10n.t("تعديل الاسم", "Edit name")
        case .brokenParent: return L10n.t("تصحيح ارتباط الأب", "Fix father link")
        case .hidden:       return L10n.t("إظهار في الشجرة", "Show in the tree")
        case .dupPhone:     return L10n.t("مسح الرقم المكرر", "Clear the duplicate number")
        }
    }

    var icon: String {
        switch self {
        case .orphan:       return "person.line.dotted.person"
        case .noName:       return "pencil"
        case .brokenParent: return "link.badge.plus"
        case .hidden:       return "eye"
        case .dupPhone:     return "phone.badge.waveform"
        }
    }
}

// MARK: - الشرائح

/// شرائح صفحة الأعضاء (بدل الصفحات السبع القديمة)
enum AdminMemberChip: String, CaseIterable, Identifiable {
    case all, registered, treeOnly, deceased, verifyLiving, gaps, problems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:          return L10n.t("الكل", "All")
        case .registered:   return L10n.t("مسجّلون", "Registered")
        case .treeOnly:     return L10n.t("مقيّدون في الشجرة", "In the tree only")
        case .deceased:     return L10n.t("متوفون", "Deceased")
        case .verifyLiving: return L10n.t("تحقق من الأحياء", "Check the living")
        case .gaps:         return L10n.t("بيانات ناقصة", "Missing data")
        case .problems:     return L10n.t("مشكلات الشجرة", "Tree problems")
        }
    }

    /// الشرائح الفرعية (الأولى «الكل») — «تحقق من الأحياء» بلا فرعية (القائمة بأقسام الميلاد)
    var subs: [AdminMemberSub] {
        switch self {
        case .all:          return [.all, .newThisWeek]
        case .registered:   return [.all, .usingApp, .inactive, .noPush, .frozen]
        case .treeOnly:     return [.all, .notSignedIn, .noPhone]
        case .deceased:     return [.all, .deathComplete, .deathIncomplete]
        case .verifyLiving: return []
        case .gaps:         return [.all, .noBirth, .noGender, .noPhoto]
        case .problems:     return [.all, .orphan, .noName, .brokenParent, .hidden, .dupPhone]
        }
    }
}

// MARK: - «تحقق من الأحياء» (طلب المالك ٢٠٢٦-١٠-٢٠ — الدفعة ١٢)
//
// «حيّ» في التطبيق يعني فقط «لا وفاة مسجّلة»: عند كبار السن أسماء كثيرة بلا تاريخ وفاة (أغلبهم بلا تاريخ ميلاد) فعدد الأحياء
// مبالغ فيه. الاختيار (داخلي فقط): العمق من رأس الشجرة بسلسلة الآباء (الرأس = ١)، والعمق «قديم» إذا كان وسيط سنوات الميلاد
// المعروفة فيه (أحياءً ومتوفين، ٣ على الأقل) قبل ١٩٦٠ — وكل ما فوقه قديم أيضاً؛ المرشّحون = غير المتوفين فيه. يُستثنى الواضح
// أنه حيّ: أعضاء الإدارة، الحساب الموقوف، ومن له حساب دخول (حين تصل قوائمه). «حي ✓» مراجعة محلية فقط
// (`AdminLivingVerifiedStore`) — لا عمود على السيرفر.
// لا مفهوم «الجيل» في واجهة الإدارة (طلب المالك ٢٠٢٦-١٠-٢٠ «الجيل ما ابي نهائيا»): القائمة بأقسام الميلاد — «بلا تاريخ ميلاد»
// ثم «مواليد قبل 1940» ثم الباقون، كلٌّ الأقدم أولاً؛ العمق مفتاح ترتيب خفي فقط (لا يُعرض ولا يُقرأ).

enum AdminLivingCheck {
    /// قبل هذه السنة = قسم «مواليد قبل 1940» (عمره فوق ٨٥)
    static let oldBirthYear = 1940
    /// العمق قديم إذا وسيط مواليده قبل هذه السنة
    static let oldDepthMedian = 1960
    static let minKnownBirths = 3

    /// أقسام القائمة بالترتيب
    enum Group: Int, CaseIterable, Comparable {
        case noBirth, beforeOld, rest

        static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .noBirth:   return L10n.t("بلا تاريخ ميلاد", "No birth date")
            case .beforeOld: return L10n.t("مواليد قبل \(AdminLivingCheck.oldBirthYear)", "Born before \(AdminLivingCheck.oldBirthYear)")
            case .rest:      return L10n.t("مواليد \(AdminLivingCheck.oldBirthYear) وما بعدها", "Born \(AdminLivingCheck.oldBirthYear) or later")
            }
        }
    }

    struct Info: Equatable {
        /// العمق من رأس الشجرة — مفتاح ترتيب خفي (الأقدم أولاً في «بلا تاريخ ميلاد») لا يُعرض
        let depth: Int
        let birthYear: Int?
        var group: Group {
            guard let birthYear else { return .noBirth }
            return birthYear < AdminLivingCheck.oldBirthYear ? .beforeOld : .rest
        }
    }

    /// سنة الميلاد من «yyyy-MM-dd» (أو سنة فقط)
    static func birthYear(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4,
              let y = Int(raw.prefix(4)), y > 1000 else { return nil }
        return y
    }

    /// عمق كل عضو متصل برأس الشجرة (الرأس = ١) — صعود بسلسلة الآباء مع حفظ النتائج.
    /// الرأس بلا طلبات الانضمام (المنضم المعلّق بلا أب أيضاً فلا يُؤخذ رأساً)
    static func depths(_ all: [FamilyMember]) -> [UUID: Int] {
        guard let root = BranchPickerSheet.familyRoot(in: all.filter { $0.role != .pending }) else { return [:] }
        var father: [UUID: UUID] = [:]
        for m in all { if let f = m.fatherId { father[m.id] = f } }
        var memo: [UUID: Int?] = [root.id: 1]
        func gen(_ id: UUID) -> Int? {
            if let known = memo[id] { return known }
            var chain: [UUID] = []
            var cur = id
            var base: Int? = nil
            while chain.count < 200 {
                if let known = memo[cur] { base = known; break }
                chain.append(cur)
                guard let f = father[cur] else { break }
                cur = f
            }
            // الأعمق أولاً في السلسلة: آخرها أقرب للرأس
            for (i, c) in chain.reversed().enumerated() { memo[c] = base.map { $0 + i + 1 } }
            return memo[id] ?? nil
        }
        var out: [UUID: Int] = [:]
        out.reserveCapacity(all.count)
        for m in all where m.role != .pending {
            if let g = gen(m.id) { out[m.id] = g }
        }
        return out
    }

    /// أعمق عمق «قديم» (وسيط مواليده المعروفة قبل ١٩٦٠) — nil = لا كبار سن بعد
    static func oldestCutoff(_ all: [FamilyMember], depths: [UUID: Int]) -> Int? {
        var years: [Int: [Int]] = [:]
        for m in all where m.role != .pending {
            guard let d = depths[m.id], let y = birthYear(m.birthDate) else { continue }
            years[d, default: []].append(y)
        }
        var cutoff: Int? = nil
        for (d, list) in years where list.count >= minKnownBirths {
            let sorted = list.sorted()
            let median = sorted[(sorted.count - 1) / 2]
            if median < oldDepthMedian { cutoff = max(cutoff ?? 0, d) }
        }
        return cutoff
    }

    /// المرشّحون للمراجعة (قبل استبعاد ما راجعه المستخدم على جهازه) — `hasLogin` nil = قوائم الحسابات لم تصل
    static func candidates(_ all: [FamilyMember], hasLogin: ((UUID) -> Bool)? = nil) -> [UUID: Info] {
        let depth = depths(all)
        guard let cutoff = oldestCutoff(all, depths: depth) else { return [:] }
        let staff: Set<FamilyMember.UserRole> = [.owner, .admin, .monitor, .supervisor]
        var out: [UUID: Info] = [:]
        for m in all where m.role != .pending && m.isDeceased != true && m.status != .frozen && !staff.contains(m.role) {
            guard let d = depth[m.id], d <= cutoff else { continue }
            if let hasLogin, hasLogin(m.id) { continue }
            out[m.id] = Info(depth: d, birthYear: birthYear(m.birthDate))
        }
        return out
    }

    /// ترتيب القائمة: القسم («بلا تاريخ ميلاد» ← «قبل 1940» ← الباقون)، ثم الأقدم أولاً (سنة الميلاد، أو العمق الخفي لمن
    /// بلا تاريخ) — nil = متساويان (يبقى ترتيب الاسم)
    static func ordered(_ a: Info, _ b: Info) -> Bool? {
        if a.group != b.group { return a.group < b.group }
        if let x = a.birthYear, let y = b.birthYear, x != y { return x < y }
        if a.depth != b.depth { return a.depth < b.depth }
        return nil
    }
}

/// «حي ✓» — مراجعة محلية لكل مستخدم على جهازه (UserDefaults — نفس مخزن `@AppStorage`)، بلا عمود على السيرفر.
/// يخفي العضو من «تحقق من الأحياء» ومن عدّ «أحياء (تقديري)» على هذا الجهاز فقط.
@MainActor
final class AdminLivingVerifiedStore: ObservableObject {
    static let shared = AdminLivingVerifiedStore()

    @Published private(set) var ids: Set<UUID> = []
    private var user: String?

    private static func key(_ user: String) -> String { "admin.livingVerified.\(user)" }

    /// مستخدم الجهاز الحالي — تُقرأ مراجعاته (تُستدعى من «اليوم» وصفحة الأعضاء)
    func activate(user id: UUID?) {
        let u = id?.uuidString.lowercased() ?? ""
        guard u != user else { return }
        user = u
        let raw = UserDefaults.standard.string(forKey: Self.key(u)) ?? ""
        let loaded = Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        if loaded != ids { ids = loaded }
    }

    func markAlive(_ id: UUID) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        save()
    }

    /// «إعادة إظهار من راجعتهم»
    func reset() {
        guard !ids.isEmpty else { return }
        ids = []
        save()
    }

    private func save() {
        guard let user else { return }
        UserDefaults.standard.set(ids.map(\.uuidString).sorted().joined(separator: ","), forKey: Self.key(user))
    }
}

/// الشرائح الفرعية — بالمسميات الرسمية
enum AdminMemberSub: String, Identifiable {
    case all
    case newThisWeek
    case usingApp, inactive, noPush, frozen
    case notSignedIn, noPhone
    case deathComplete, deathIncomplete
    case noBirth, noGender, noPhoto
    case orphan, noName, brokenParent, hidden, dupPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:             return L10n.t("الكل", "All")
        case .newThisWeek:     return L10n.t("قُيّدوا هذا الأسبوع", "Added this week")
        case .usingApp:        return L10n.t("يستخدم التطبيق", "Using the app")
        case .inactive:        return L10n.t("غير نشط", "Inactive")
        case .noPush:          return L10n.t("لا تصله الإشعارات", "No notifications")
        case .frozen:          return L10n.t("حساب موقوف", "Suspended")
        case .notSignedIn:     return L10n.t("له رقم — لم يسجّل الدخول بعد", "Has a number — not signed in yet")
        case .noPhone:         return L10n.t("بلا رقم هاتف", "No phone")
        case .deathComplete:   return L10n.t("تاريخ الوفاة مكتمل", "Death date complete")
        case .deathIncomplete: return AdminMemberGap.deathIncomplete.title
        case .noBirth:         return AdminMemberGap.noBirth.title
        case .noGender:        return AdminMemberGap.noGender.title
        case .noPhoto:         return AdminMemberGap.noPhoto.title
        case .orphan:          return AdminMemberProblem.orphan.title
        case .noName:          return AdminMemberProblem.noName.title
        case .brokenParent:    return AdminMemberProblem.brokenParent.title
        case .hidden:          return AdminMemberProblem.hidden.title
        case .dupPhone:        return AdminMemberProblem.dupPhone.title
        }
    }
}

// MARK: - حسابات الدخول (من `app_usage_members` الموجودة — للإدارة الأربعة `is_moderator()`)

/// حساب دخول عضو: فئة استخدامه وآخر ظهور وتاريخ إنشاء الحساب
struct AdminAccountInfo: Equatable {
    let usage: AppUsageCategory
    let lastSeen: Date?
    let created: Date?
}

/// من له حساب دخول — ثلاث قوائم من `app_usage_members` (active · idle · login_no_device). الفشل يُبقي آخر قيمة
@MainActor
final class AdminAccountsStore: ObservableObject {
    static let shared = AdminAccountsStore()

    @Published private(set) var accounts: [UUID: AdminAccountInfo] = [:]
    /// وصلت القوائم مرة على الأقل (قبلها لا تُعرض حالة «مسجّل/مقيّد»)
    @Published private(set) var loaded = false
    /// سجلّات بلا اسم (رقم دخول بلا اسم) في كل فئة — تُطرح من أرقام `app_usage_stats` (`AppUsageStats.excludingNameless`)
    /// لأنها ليست أفراداً في العائلة. بعد أن يستبعدها السيرفر نفسه تصير أصفاراً فلا يتغيّر شيء
    private(set) var namelessByCategory: [AppUsageCategory: Int] = [:]
    private var lastFetch: Date?

    static let categories: [AppUsageCategory] = [.active, .idle, .loginNoDevice]

    func info(_ id: UUID) -> AdminAccountInfo? { accounts[id] }

    func refresh(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 60 { return }
        async let active = Self.fetch(.active)
        async let idle = Self.fetch(.idle)
        async let noDevice = Self.fetch(.loginNoDevice)
        let lists = await (active, idle, noDevice)
        guard let a = lists.0, let i = lists.1, let n = lists.2 else { return }
        apply([.active: a, .idle: i, .loginNoDevice: n])
        lastFetch = Date()
    }

    /// يبني الخريطة من القوائم (يستعملها التحميل)
    func apply(_ lists: [AppUsageCategory: [AppUsageMember]]) {
        var map: [UUID: AdminAccountInfo] = [:]
        var nameless: [AppUsageCategory: Int] = [:]
        for category in Self.categories {
            for row in lists[category] ?? [] {
                map[row.memberId] = AdminAccountInfo(usage: category, lastSeen: row.lastSeen, created: row.accountCreated)
                if AdminMemberFacts.isBlank(row.fullName) || row.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) == "بدون اسم" {
                    nameless[category, default: 0] += 1
                }
            }
        }
        namelessByCategory = nameless
        if map != accounts { accounts = map }
        loaded = true
    }

    private static func fetch(_ category: AppUsageCategory) async -> [AppUsageMember]? {
        do {
            return try await SupabaseConfig.client
                .rpc("app_usage_members", params: ["p_category": category.rawValue])
                .execute()
                .value
        } catch {
            Log.fetchError("تعذر جلب حسابات الدخول (\(category.rawValue))", error)
            return nil
        }
    }
}

// MARK: - حقائق العضو الواحد (ورقة العضو و«اليوم» يقرآنها — نفس شروط الفهرس)

enum AdminMemberFacts {
    static func isBlank(_ v: String?) -> Bool { (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// الأرقام وحدها بالإنجليزية — لوحة المفاتيح العربية تكتب «٥٠٠» والأرقام المخزّنة «500»
    static func asciiDigits(_ text: String) -> String {
        String(text.compactMap { $0.wholeNumberValue.map { Character(String($0)) } })
    }

    /// الحالة الرسمية — nil للحيّ غير الموقوف قبل وصول قوائم الحسابات
    static func status(_ m: FamilyMember, hasLogin: Bool?) -> AdminMemberStatus? {
        if m.role == .pending { return .pendingJoin }
        if m.isDeceased == true { return .deceased }
        if m.status == .frozen { return .frozen }
        guard let hasLogin else { return nil }
        return hasLogin ? .registered : .treeOnly
    }

    /// تاريخ وفاة غير مكتمل: فارغ (ولم يُعلَّم «غير معروف») أو سنة فقط أو هجري مكتوب كميلادي
    static func deathIncomplete(_ m: FamilyMember) -> Bool {
        guard m.isDeceased == true, m.deathDateUnknown != true else { return false }
        switch DeceasedMemorial.classify(m.deathDate) {
        case .exact: return false
        case .yearOnly, .hijriLike, .missing: return true
        }
    }

    /// النواقص — الميلاد والجنس للأحياء، والصورة للعضو المسجّل، وتاريخ الوفاة للمتوفى
    static func gaps(_ m: FamilyMember, registered: Bool) -> [AdminMemberGap] {
        guard m.role != .pending else { return [] }
        if m.isDeceased == true { return deathIncomplete(m) ? [.deathIncomplete] : [] }
        var list: [AdminMemberGap] = []
        if isBlank(m.birthDate) { list.append(.noBirth) }
        if isBlank(m.gender) { list.append(.noGender) }
        if registered && isBlank(m.avatarUrl) && m.avatarUnavailable != true { list.append(.noPhoto) }
        return list
    }

    /// سياق مشكلات الشجرة (مرور واحد على الأعضاء) — نفس شروط «صحة الشجرة» السابقة
    struct TreeContext {
        /// آباء لهم أبناء (غير معلّقين وغير موقوفين)
        let fatherIds: Set<UUID>
        /// المعرّفات الصالحة أباً (غير معلّقين وغير موقوفين)
        let activeIds: Set<UUID>
        /// أعضاء رقمهم مكرر (آخر ٨ أرقام)
        let dupPhoneIds: Set<UUID>

        init(_ all: [FamilyMember]) {
            var fathers = Set<UUID>(), active = Set<UUID>()
            var phones: [String: [UUID]] = [:]
            for m in all {
                if m.role != .pending && m.status != .frozen {
                    active.insert(m.id)
                    if let f = m.fatherId { fathers.insert(f) }
                }
                if let phone = m.phoneNumber, !phone.isEmpty {
                    let suffix = String(phone.filter(\.isNumber).suffix(8))
                    if suffix.count >= 8 { phones[suffix, default: []].append(m.id) }
                }
            }
            fatherIds = fathers
            activeIds = active
            dupPhoneIds = Set(phones.values.filter { $0.count > 1 }.flatMap { $0 })
        }
    }

    static func problems(_ m: FamilyMember, in ctx: TreeContext) -> [AdminMemberProblem] {
        guard m.role != .pending, m.status != .frozen else { return [] }
        var list: [AdminMemberProblem] = []
        if m.fatherId == nil && !ctx.fatherIds.contains(m.id) { list.append(.orphan) }
        let name = m.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "بدون اسم" { list.append(.noName) }
        if let fid = m.fatherId, !ctx.activeIds.contains(fid) { list.append(.brokenParent) }
        if m.isHiddenFromTree { list.append(.hidden) }
        if ctx.dupPhoneIds.contains(m.id) { list.append(.dupPhone) }
        return list
    }
}

// MARK: - الفهرس (يُبنى مرة لكل تغيّر في الأعضاء أو الحسابات)

struct AdminMembersIndex {
    struct Entry: Identifiable {
        let member: FamilyMember
        let status: AdminMemberStatus?
        let usage: AppUsageCategory?
        let gaps: [AdminMemberGap]
        let problems: [AdminMemberProblem]
        /// رأس الفرع (ابن مباشر لرأس الشجرة) — nil = خارج الفروع
        let branch: UUID?
        /// مرشّح «تحقق من الأحياء» (قسمه وسنة ميلاده) — nil = ليس منهم
        let living: AdminLivingCheck.Info?
        /// الاسم مُطبَّعاً للبحث، وأرقام الهاتف
        let needle: String
        let digits: String
        var id: UUID { member.id }
    }

    struct Branch: Identifiable {
        let id: UUID?
        let title: String
        let rows: [Int]
    }

    struct Key: Hashable {
        let chip: AdminMemberChip
        let sub: AdminMemberSub
    }

    var entries: [Entry] = []
    var lists: [Key: [Int]] = [:]
    var branches: [Branch] = []
    /// طلبات الانضمام (الدور `pending`)
    var pendingJoin = 0
    var accountsReady = false
    /// «اكتمال البيانات» (الأحياء: الميلاد والجنس، والمسجّلون: الصورة)
    var completeness: Double = 1
    /// «سلامة الشجرة»: من لا ملاحظة عليه من غير الموقوفين
    var clean = 0
    var checked = 0
    var built = false

    static let empty = AdminMembersIndex()

    func rows(_ chip: AdminMemberChip, _ sub: AdminMemberSub) -> [Int] { lists[Key(chip: chip, sub: sub)] ?? [] }
    func count(_ chip: AdminMemberChip, _ sub: AdminMemberSub = .all) -> Int { rows(chip, sub).count }

    /// العدد للعرض — nil قبل وصول ما يلزمه (الحسابات لشرائح المسجّلين والمقيّدين)
    func shownCount(_ chip: AdminMemberChip, _ sub: AdminMemberSub = .all) -> Int? {
        guard built else { return nil }
        if !accountsReady && (chip == .registered || chip == .treeOnly
                              || (chip == .gaps && sub == .noPhoto)) {
            return chip == .registered && sub == .frozen ? count(chip, sub) : nil
        }
        return count(chip, sub)
    }

    @MainActor
    static func build(members all: [FamilyMember], accounts: [UUID: AdminAccountInfo], accountsReady: Bool,
                      branchName: (UUID) -> String?) -> AdminMembersIndex {
        var index = AdminMembersIndex()
        index.accountsReady = accountsReady
        index.built = !all.isEmpty
        index.pendingJoin = all.filter { $0.role == .pending }.count
        let pool = all.filter { $0.role != .pending }.sorted {
            let a = $0.firstName.trimmingCharacters(in: .whitespaces)
            let b = $1.firstName.trimmingCharacters(in: .whitespaces)
            if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
            return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
        let ctx = AdminMemberFacts.TreeContext(all)
        let heads = branchHeads(all)
        // «تحقق من الأحياء»: من له حساب دخول حيّ قطعاً (حين تصل القوائم)
        let oldLiving = AdminLivingCheck.candidates(all, hasLogin: accountsReady ? { accounts[$0] != nil } : nil)

        var entries: [Entry] = []
        entries.reserveCapacity(pool.count)
        var lists: [Key: [Int]] = [:]
        func add(_ chip: AdminMemberChip, _ sub: AdminMemberSub, _ i: Int) { lists[Key(chip: chip, sub: sub), default: []].append(i) }
        var living = 0, registeredLiving = 0, gapCount = 0, checked = 0, withProblems = 0
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        for (i, m) in pool.enumerated() {
            let info = accounts[m.id]
            var status = AdminMemberFacts.status(m, hasLogin: accountsReady ? info != nil : nil)
            // حساب المرأة (دخول النساء) له دخول بطبيعته — لا يُعرض «مقيّداً في الشجرة» ولو غاب عن قوائم الاستخدام
            if m.isWomanAccount && status == .treeOnly { status = .registered }
            let registered = status == .registered || (status == .frozen && info != nil)
            let gaps = AdminMemberFacts.gaps(m, registered: registered)
            let problems = AdminMemberFacts.problems(m, in: ctx)
            entries.append(Entry(member: m, status: status, usage: info?.usage, gaps: gaps, problems: problems,
                                 branch: heads[m.id], living: oldLiving[m.id],
                                 needle: ArabicTextNormalizer.normalizeForSearch(m.familyName == nil ? m.fullName : m.fullName + " " + m.displayFullName),
                                 digits: AdminMemberFacts.asciiDigits(m.phoneNumber ?? "")))
            func addProblems() {
                guard !problems.isEmpty else { return }
                withProblems += 1
                add(.problems, .all, i)
                for p in problems {
                    switch p {
                    case .orphan: add(.problems, .orphan, i)
                    case .noName: add(.problems, .noName, i)
                    case .brokenParent: add(.problems, .brokenParent, i)
                    case .hidden: add(.problems, .hidden, i)
                    case .dupPhone: add(.problems, .dupPhone, i)
                    }
                }
            }
            // سجلّ بلا اسم (رقم دخول بلا اسم — `FamilyMember.hasName`) ليس فرداً في العائلة: لا يدخل «الكل» ولا الحالات
            // ولا النواقص ولا الفروع — بيته الوحيد «مشكلات الشجرة ← بلا اسم»
            guard m.hasName else {
                if m.status != .frozen { checked += 1 }
                addProblems()
                continue
            }
            // حساب امرأة: ليس من شجرة الرجال — بيته «مسجّلون» وحده (بشارة «أنثى» في الصفّ)، خارج «الكل» والفروع
            // والنواقص والمشكلات و«تحقق من الأحياء»؛ تُعدّ وتُرى بعقدتها في شجرة النساء
            if m.isWomanAccount {
                switch status {
                case .frozen:
                    add(.registered, .all, i)
                    add(.registered, .frozen, i)
                case .registered:
                    add(.registered, .all, i)
                    switch info?.usage {
                    case .active: add(.registered, .usingApp, i)
                    case .idle: add(.registered, .inactive, i)
                    default: add(.registered, .noPush, i)
                    }
                default:
                    break
                }
                continue
            }
            add(.all, .all, i)
            if oldLiving[m.id] != nil { add(.verifyLiving, .all, i) }
            switch status {
            case .deceased:
                add(.deceased, .all, i)
                add(.deceased, AdminMemberFacts.deathIncomplete(m) ? .deathIncomplete : .deathComplete, i)
            case .frozen:
                add(.registered, .all, i)
                add(.registered, .frozen, i)
            case .registered:
                add(.registered, .all, i)
                switch info?.usage {
                case .active: add(.registered, .usingApp, i)
                case .idle: add(.registered, .inactive, i)
                default: add(.registered, .noPush, i)
                }
            case .treeOnly:
                add(.treeOnly, .all, i)
                add(.treeOnly, AdminMemberFacts.isBlank(m.phoneNumber) ? .noPhone : .notSignedIn, i)
            case .pendingJoin, .none:
                break
            }
            if m.isDeceased != true && m.isCountable,
               let created = ApprovalWorkflow.date(m.createdAt), created >= weekAgo {
                add(.all, .newThisWeek, i)
            }
            if m.isDeceased != true {
                living += 1
                if registered { registeredLiving += 1 }
                let livingGaps = gaps.filter { $0 != .deathIncomplete }
                if !livingGaps.isEmpty { add(.gaps, .all, i) }
                for gap in livingGaps {
                    gapCount += 1
                    switch gap {
                    case .noBirth: add(.gaps, .noBirth, i)
                    case .noGender: add(.gaps, .noGender, i)
                    case .noPhoto: add(.gaps, .noPhoto, i)
                    case .deathIncomplete: break
                    }
                }
            }
            if m.status != .frozen { checked += 1 }
            addProblems()
        }
        // «تحقق من الأحياء»: بأقسام الميلاد، الأقدم أولاً في كلٍّ (ترتيب الاسم يبقى عند التساوي — `pool` مرتّب بالاسم)
        if let rows = lists[Key(chip: .verifyLiving, sub: .all)] {
            lists[Key(chip: .verifyLiving, sub: .all)] = rows.enumerated().sorted { a, b in
                guard let x = entries[a.element].living, let y = entries[b.element].living,
                      let before = AdminLivingCheck.ordered(x, y) else { return a.offset < b.offset }
                return before
            }.map(\.element)
        }
        index.entries = entries
        index.lists = lists
        let checks = living * 2 + registeredLiving
        index.completeness = checks > 0 ? max(0, min(1, 1 - Double(gapCount) / Double(checks))) : 1
        index.checked = checked
        index.clean = max(0, checked - withProblems)

        // الفروع: أبناء رأس الشجرة المباشرون، ثم «خارج الفروع» (الرأس نفسه ومن لا يتصل به)
        var byBranch: [UUID?: [Int]] = [:]
        for (i, e) in entries.enumerated() where e.member.hasName && !e.member.isWomanAccount { byBranch[e.branch, default: []].append(i) }
        let headMembers = Set(heads.values).compactMap { id in all.first { $0.id == id } }
            .sorted { ($0.sortOrder, $0.firstName) < ($1.sortOrder, $1.firstName) }
        var branches: [Branch] = headMembers.compactMap { head in
            guard let rows = byBranch[head.id], !rows.isEmpty else { return nil }
            let title = branchName(head.id) ?? L10n.t("فرع \(head.firstName)", "\(head.firstName) branch")
            return Branch(id: head.id, title: title, rows: rows)
        }
        if let rest = byBranch[nil], !rest.isEmpty {
            branches.append(Branch(id: nil, title: L10n.t("خارج الفروع", "Outside the branches"), rows: rest))
        }
        index.branches = branches
        return index
    }

    /// رأس فرع كل عضو: ابن مباشر لرأس الشجرة (`BranchPickerSheet.familyRoot`) — بالصعود في سلسلة الآباء مع حفظ النتائج
    private static func branchHeads(_ all: [FamilyMember]) -> [UUID: UUID] {
        guard let root = BranchPickerSheet.familyRoot(in: all) else { return [:] }
        var father: [UUID: UUID] = [:]
        for m in all { if let f = m.fatherId { father[m.id] = f } }
        var memo: [UUID: UUID?] = [:]
        func head(_ id: UUID) -> UUID? {
            if let known = memo[id] { return known }
            var chain: [UUID] = []
            var cur = id
            var result: UUID? = nil
            var steps = 0
            while steps < 200 {
                if let known = memo[cur] { result = known; break }
                guard let f = father[cur] else { result = nil; break }
                chain.append(cur)
                if f == root.id { result = cur; break }
                cur = f
                steps += 1
            }
            for c in chain { memo[c] = result }
            return result
        }
        var heads: [UUID: UUID] = [:]
        for m in all where m.id != root.id {
            if let h = head(m.id) { heads[m.id] = h }
        }
        return heads
    }
}
