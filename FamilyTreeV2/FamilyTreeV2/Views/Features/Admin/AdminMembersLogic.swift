import Foundation

// MARK: - «العائلة» — المنطق الخالص (إعادة تصميم الإدارة U11، spec C.6/C.7، اختيار المالك «ب»)
//
// ما تقرّره صفحة «العائلة» بلا واجهة، في مكان واحد يُفحص بلا محاكي:
//  ١) فلترا «الحساب» و«الحالة» على عضو (T2): «لهم حساب» = له حساب دخول فقط — الموقوف بلا حساب كان يُعدّ هنا فيختلف
//     الرقم عن «المسجّلين» (رجال الشجرة الأحياء لهم حساب). والعدّ لكل خيار من جدول ٢×٢ واحد (`Tally`).
//  ٢) ما تُفتح عليه الصفحة: معاملات `init` القديمة (`chip:`/`sub:`/`womenOutside:`) والهبوط (`AdminMembersLanding`) ←
//     فلاتر الصفحة، أو قائمة تُدفع فوق الجذر (الرجوع يعود للجذر).
//  ٣) سطر «آخر دخول» في صفّ العضو.
//
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u11-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersLogic.swift tests/admin-redesign/U11/main.swift && /tmp/u11-logic

nonisolated enum AdminMembersLogic {
    typealias Account = AdminMembersLanding.Account
    typealias Life = AdminMembersLanding.Life
    typealias Review = AdminMembersLanding.Review

    // MARK: ١) الفلتران

    /// «الحالة» ثم «الحساب» على عضو واحد. `hasLogin` = له حساب دخول (في قوائم «استخدام التطبيق»)
    static func matches(deceased: Bool, hasLogin: Bool, account: Account, life: Life) -> Bool {
        switch life {
        case .all:      break
        case .alive:    if deceased { return false }
        case .deceased: if !deceased { return false }
        }
        switch account {
        case .all:     return true
        case .with:    return hasLogin
        case .without: return !hasLogin
        }
    }

    /// عدّ القائمة بعد البحث والفرع (قبل «الحساب» و«الحالة») — كل خيار في الورقة رقمه من هنا، فالأرقام تتبع بقية الاختيارات
    struct Tally: Equatable {
        var aliveLogin = 0
        var aliveNoLogin = 0
        var deadLogin = 0
        var deadNoLogin = 0

        init(aliveLogin: Int = 0, aliveNoLogin: Int = 0, deadLogin: Int = 0, deadNoLogin: Int = 0) {
            self.aliveLogin = aliveLogin
            self.aliveNoLogin = aliveNoLogin
            self.deadLogin = deadLogin
            self.deadNoLogin = deadNoLogin
        }

        mutating func add(deceased: Bool, hasLogin: Bool) {
            switch (deceased, hasLogin) {
            case (false, true):  aliveLogin += 1
            case (false, false): aliveNoLogin += 1
            case (true, true):   deadLogin += 1
            case (true, false):  deadNoLogin += 1
            }
        }

        var total: Int { aliveLogin + aliveNoLogin + deadLogin + deadNoLogin }

        /// العدد لاختيارين — نفس `matches`
        func count(account: Account, life: Life) -> Int {
            var n = 0
            if matches(deceased: false, hasLogin: true, account: account, life: life) { n += aliveLogin }
            if matches(deceased: false, hasLogin: false, account: account, life: life) { n += aliveNoLogin }
            if matches(deceased: true, hasLogin: true, account: account, life: life) { n += deadLogin }
            if matches(deceased: true, hasLogin: false, account: account, life: life) { n += deadNoLogin }
            return n
        }

        /// العدد للعرض: خيار «الحساب» لا يُعرف قبل وصول قوائم الحسابات («—»)
        func shown(account: Account, life: Life, accountsReady: Bool) -> Int? {
            if account != .all && !accountsReady { return nil }
            return count(account: account, life: life)
        }
    }

    // MARK: ٢) ما تُفتح عليه الصفحة

    /// قائمة تُدفع فوق جذر «العائلة» (الرجوع يعود للجذر)
    enum Push: Equatable {
        /// قائمة مراجعة (`AdminReviewListPage(review:)`)
        case review(Review)
        /// «تواريخ وفاة ناقصة» — بيتها الواحد `DeathDatesCampaignPage` (spec E.19)
        case deathDates
        /// «نساء العائلة» بهبوطه (رقم «خارج العائلة»)
        case women(AdminWomenLanding)
    }

    struct Opening: Equatable {
        var account: Account = .all
        var life: Life = .all
        /// رأس الفرع — nil = كل الفروع
        var branch: UUID? = nil
        /// فلتر إضافي من رابط قديم لا تقابله قائمة مراجعة (القيمة الخام لـ`AdminMemberSub`) — يظهر شريحةً تُلغى
        var sub: String? = nil
        var push: Push? = nil

        init(account: Account = .all, life: Life = .all, branch: UUID? = nil, sub: String? = nil, push: Push? = nil) {
            self.account = account
            self.life = life
            self.branch = branch
            self.sub = sub
            self.push = push
        }
    }

    /// معاملات `init` على افتراضها — الهبوط المخزَّن يُطبَّق (المعاملات الصريحة تغلبه)
    static func isDefault(chip: String, sub: String, womenOutside: Bool) -> Bool {
        chip == "all" && sub == "all" && !womenOutside
    }

    /// الروابط القديمة (`chip:`/`sub:`، القيم الخام لـ`AdminMemberChip`/`AdminMemberSub`): كل قيمة فلتر، أو قائمتها تُدفع
    /// فوق الجذر بفلتر الشريحة سياقاً تحتها. «تحقق من الأحياء»/«ناقصة»/«مشكلات» قوائم مراجعة؛ «لم يسجّل الدخول بعد» =
    /// قائمة «لم يفتحوا التطبيق بعد» نفسها، و«غير نشط» = «لم يدخلوا منذ 21 يوماً»، و«تاريخ الوفاة غير مكتمل» صفحة
    /// تواريخ الوفاة. الشرائح الفرعية الباقية فلتر إضافي وحده (بلا «الحساب»/«الحالة» — قائمتها كاملة بذاتها).
    static func opening(chip: String, sub: String, womenOutside: Bool) -> Opening {
        if womenOutside {
            // من مجموع («خارج العائلة» في «اليوم») ← «الحالة» = الكل (Autoplan note 3)
            return Opening(push: .women(AdminWomenLanding(status: .all, branch: .outside)))
        }
        switch chip {
        case "registered":
            switch sub {
            case "inactive":                    return Opening(account: .with, life: .alive, push: .review(.inactive))
            case "usingApp", "noPush", "frozen": return Opening(sub: sub)
            default:                            return Opening(account: .with, life: .alive)
            }
        case "treeOnly":
            switch sub {
            case "notSignedIn": return Opening(account: .without, life: .alive, push: .review(.notOpened))
            case "noPhone":     return Opening(sub: sub)
            default:            return Opening(account: .without, life: .alive)
            }
        case "deceased":
            switch sub {
            case "deathIncomplete": return Opening(life: .deceased, push: .deathDates)
            case "deathComplete":   return Opening(sub: sub)
            default:                return Opening(life: .deceased)
            }
        case "verifyLiving": return Opening(push: .review(.living))
        case "gaps":         return Opening(push: .review(.gaps))
        case "problems":     return Opening(push: .review(.problems))
        case "all":
            return sub == "newThisWeek" ? Opening(sub: sub) : Opening()
        default:
            return Opening()
        }
    }

    /// الهبوط (`AdminMembersLanding`): الحقل الغائب = افتراض الصفحة (بلا فلتر)؛ «تواريخ الوفاة» صفحتها الواحدة
    static func opening(landing: AdminMembersLanding) -> Opening {
        var o = Opening(account: landing.account ?? .all, life: landing.life ?? .all, branch: landing.branch)
        switch landing.review {
        case .death?:  o.push = .deathDates
        case let r?:   o.push = .review(r)
        case nil:      break
        }
        return o
    }

    // MARK: ٣) سطر الصفّ

    /// أيام التقويم بين آخر دخول واليوم (٠ = اليوم)
    static func daysSince(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// أطول من هذا يُكتب التاريخ نفسه
    static let lastSeenRelativeDays = 30

    /// «آخر دخول اليوم» · «أمس» · «قبل يومين» · «قبل 5 أيام» · «قبل 12 يوماً» — nil بعد ٣٠ يوماً (يكتب المستدعي التاريخ)
    static func lastSeen(days: Int) -> String? {
        switch days {
        case ..<1:  return L10n.t("آخر دخول اليوم", "Last seen today")
        case 1:     return L10n.t("آخر دخول أمس", "Last seen yesterday")
        case 2:     return L10n.t("آخر دخول قبل يومين", "Last seen 2 days ago")
        case 3...10: return L10n.t("آخر دخول قبل \(days) أيام", "Last seen \(days) days ago")
        case 11...lastSeenRelativeDays: return L10n.t("آخر دخول قبل \(days) يوماً", "Last seen \(days) days ago")
        default:    return nil
        }
    }

    /// سطر الملخّص تحت الشريط: الترتيب الظاهر — بالفروع (بلا فلتر ولا بحث)، أبجدياً، أو الأقرب للبحث
    enum Order: Equatable {
        case branches, alphabetical, relevance

        static func make(filtered: Bool, searching: Bool) -> Order {
            if searching { return .relevance }
            return filtered ? .alphabetical : .branches
        }

        var title: String {
            switch self {
            case .branches:     return L10n.t("بالفروع", "by branch")
            case .alphabetical: return L10n.t("أبجدياً", "A–Z")
            case .relevance:    return L10n.t("الأقرب أولاً", "best match")
            }
        }
    }

    // MARK: ٤) جذر «العائلة» v2 (V2-2، اتجاه «أ»)

    /// سطر الوصف الذهبي تحت «العائلة ⌄»: «كل العائلة»، أو اسم الفرع حين تكون التصفية على فرع
    static func caption(branch: String?) -> String {
        let name = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L10n.t("كل العائلة", "The whole family") : name
    }

    /// سطر النتيجة تحت الرأس («783 رجل · أبجدياً») يظهر مع التصفية أو البحث فقط — بلاهما الرقم نفسه في مربّع «رجل» بالرأس
    static func showsResultLine(filtered: Bool, searching: Bool) -> Bool {
        filtered || searching
    }

    /// كلمة «حياً» الصغيرة بعد رقم «خارج العائلة» (الأحياء وحدهم — طلب المالك ٢٠٢٦-١١-٢٦)
    static var livingUnit: String { L10n.t("حياً", "living") }

    // الاسم في صفّ العضو: أول كلمتين عريضتان والباقي عادي، سطر واحد يُقصّ في آخره

    struct NameParts: Equatable {
        /// أول كلمتين («ابراهيم احمد»)
        let lead: String
        /// الباقي («ابراهيم حسين حسن …») — فارغ للاسم القصير
        let rest: String
    }

    static func nameParts(_ full: String) -> NameParts {
        let words = full.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let lead = words.prefix(2).joined(separator: " ")
        let rest = words.dropFirst(2).joined(separator: " ")
        return NameParts(lead: lead, rest: rest)
    }

    // بطاقة «يحتاج مراجعتك»: سطران وحبّة «5 قوائم» (قوائم لا أشخاص)

    /// قائمة من قوائم «يحتاج مراجعتك» بترتيب صفحتها (`AdminReviewHubLogic.List`) — العدد nil = لم يصل
    struct ReviewList: Equatable {
        let title: String
        let count: Int?
        /// تتصدّر البطاقة متى كان فيها أحد: «تواريخ وفاة ناقصة» — حملة المالك البارزة، ورقمها انتقل إلى هنا من مربّع
        /// «المناسبات» (V2-1 البند ٤)
        let leads: Bool

        init(_ title: String, _ count: Int?, leads: Bool = false) {
            self.title = title
            self.count = count
            self.leads = leads
        }
    }

    struct ReviewCard: Equatable {
        /// السطر الأول بعدده: «363 تواريخ وفاة ناقصة»
        let first: String
        /// القائمة التالية بترتيب الصفحة، بلا عدد («هل ما زالوا أحياء؟») — nil = قائمة واحدة فيها أحد
        let second: String?
        /// عدد القوائم التي فيها أحد («5 قوائم») — nil = لم تصل كل الأرقام (هيكل)
        let lists: Int?
    }

    enum ReviewState: Equatable {
        /// كل القوائم صفر (أو فشلت قوائم الحسابات والباقي صفر)
        case hidden
        /// لم يصل ما يكفي للسطر الأول — هيكل بشكل البطاقة
        case loading
        case card(ReviewCard)
    }

    /// عدد القوائم التي فيها أحد — رقم حبّة «5 قوائم» هنا وكلمة «5 قوائم للمراجعة» على مربّع «العائلة» في «اليوم»
    static func reviewListCount(_ counts: [Int?]) -> Int {
        counts.filter { ($0 ?? 0) > 0 }.count
    }

    /// السطر الأول: القائمة المتصدّرة (`leads`) إن كان فيها أحد، وإلا أول قائمة فيها أحد بترتيب الصفحة — لا الأكبر عدداً:
    /// «لم يفتحوا التطبيق بعد» بالآلاف كانت ستتصدّر دائماً. والثاني أول قائمة بعده بترتيب الصفحة.
    /// - accountsFailed: قوائم «الحسابات» فشلت بلا بيانات — لن تصل، فيُحكم بما وصل
    static func reviewState(_ lists: [ReviewList], accountsFailed: Bool) -> ReviewState {
        let complete = lists.allSatisfy { $0.count != nil }
        let settled = complete || accountsFailed
        let busy = lists.enumerated().filter { ($0.element.count ?? 0) > 0 }
        guard let fallback = busy.first else { return settled ? .hidden : .loading }
        let top = busy.first { $0.element.leads } ?? fallback
        let next = busy.first { $0.offset != top.offset }?.element
        return .card(ReviewCard(first: reviewLine(top.element), second: next?.title,
                                lists: settled ? busy.count : nil))
    }

    /// «363 تواريخ وفاة ناقصة» — والسؤال يبقى أولاً «هل ما زالوا أحياء؟ 41» (رقم قبل سؤال لا يُقرأ)
    static func reviewLine(_ list: ReviewList) -> String {
        guard let n = list.count, n > 0 else { return list.title }
        let number = AdminNumberText.grouped(n)
        let asks = list.title.hasSuffix("؟") || list.title.hasSuffix("?")
        return asks ? "\(list.title) \(number)" : "\(number) \(list.title)"
    }

    /// «قائمة واحدة» · «قائمتان» · «5 قوائم» · «11 قائمةً» · «100 قائمة»
    static func listsText(_ n: Int) -> String {
        switch n {
        case 1: return L10n.t("قائمة واحدة", "1 list")
        case 2: return L10n.t("قائمتان", "2 lists")
        default:
            let number = AdminNumberText.grouped(n)
            switch n % 100 {
            case 3...10:  return L10n.t("\(number) قوائم", "\(number) lists")
            case 11...99: return L10n.t("\(number) قائمةً", "\(number) lists")
            default:      return L10n.t("\(number) قائمة", "\(number) lists")
            }
        }
    }
}
