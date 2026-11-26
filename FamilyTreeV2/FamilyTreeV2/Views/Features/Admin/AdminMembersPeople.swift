import Foundation

// MARK: - «مَن» داخل «تصفية» العائلة (الوحدة F5، طلب المالك ٢٠٢٦-١١-٢٦)
//
// المالك: «المربعات العلوية في العائلة رجل و امراءة و خارج العائلة خلهم اسبط و خلهم داخل التصفية». فصار:
//  - مربّعات الرأس الثلاثة حُذفت، وصارت المجموعة الأولى في «تصفية» «مَن» — اختيار متعدّد: «رجال» (شجرة الرجال كما كانت
//    القائمة) · «نساء» (نساء العائلة من شجرة النساء — قاعدة مربّع «امرأة» و`AdminWomenPanel` نفسها) · «خارج العائلة»
//    (زوجات من عوائل ثانية، بنات البنات، أزواج البنات، أبناء البنات — الأحياء وحدهم، قاعدة المربّع القديم نفسها).
//  - الصفحة تُفتح على {رجال} شريحةً عادية تُزال (F3: الافتراضي شريحة). بلا اختيار = الثلاث، و«الكل» يمسح المجموعة.
//  - أكثر من فئة = أقسام بالترتيب «الرجال · N» · «النساء · N» · «خارج العائلة · N»؛ والرجال بالفروع كما كانوا بلا بحث.
//  - بقية المجموعات لكل فئة حيث تنطبق: «الحساب» (الرجال بحساب الدخول، النساء وخارج العائلة بالربط بحساب) · «الحالة»
//    (الكل؛ خارج العائلة أحياء فقط) · «الفرع» (الرجال بفرعهم، النساء بفرع الأب، خارج العائلة بفرع قريبهم من العائلة:
//    الزوج، أو أبو الأم/الزوجة — من لا يُعرف قريبه لا يدخل فرعاً). المجموعة التي لا تنطبق على المختار تختفي من الورقة
//    (وتُمسح اختياراتها — لا تبقى شريحة لا تُزال): «الحالة» مع {خارج العائلة} وحدها، و«القائمة» (روابط الرجال القديمة)
//    بلا «رجال».
//  - من لا يرى صفحة «نساء العائلة» (المراقب — للمالك والمدير وحدهما) لا يرى «مَن»: القائمة رجال كما كانت.
//  - T2: كل عدد (الورقة، الشرائح، «النتيجة الآن»، سطر النتيجة، السطر المطويّ) من النطاق نفسه الذي تُرسم منه الأقسام —
//    `count` و`sections` يقرآن الـ`Scope` نفسه بشرط `matches` نفسه.
// منطق خالص (Foundation + طقم التصفية) يُفحص بلا محاكي — الأمر في رأس tests/admin-redesign/F5/main.swift.

enum AdminPeopleLogic {
    typealias Population = AdminMembersLanding.Population
    typealias Account = AdminMembersLanding.Account
    typealias Life = AdminMembersLanding.Life
    typealias Tally = AdminMembersLogic.Tally

    /// ما تُفتح عليه الصفحة: الرجال (القائمة كما كانت) — شريحة «رجال» تُزال
    static let pageDefault: Set<Population> = [.men]

    // MARK: الحالة

    /// تصفية «العائلة» (F3 + F5): «مَن» · «الحساب» · «الحالة» اختيار متعدّد (فارغة = «الكل»؛ «مَن» الفارغة = الثلاث)،
    /// «الفرع» اختيار واحد (منتقٍ شجري)، و«القائمة» فلتر إضافي من رابط قديم (القيمة الخام لـ`AdminMemberSub`، للرجال)
    struct Filters: Equatable {
        var people: Set<Population>
        var accounts: Set<Account>
        var lives: Set<Life>
        var branch: UUID?
        var sub: String?

        init(people: Set<Population> = AdminPeopleLogic.pageDefault, accounts: Set<Account> = [], lives: Set<Life> = [],
             branch: UUID? = nil, sub: String? = nil) {
            self.people = people
            self.accounts = accounts.subtracting([.all])
            self.lives = lives.subtracting([.all])
            self.branch = branch
            self.sub = sub
        }

        /// الروابط القديمة والهبوط: كل اختيار شريحة تُزال (`AdminMembersLogic.picks`)، و«مَن» الغائبة = {رجال}
        init(_ o: AdminMembersLogic.Opening) {
            self.init(people: o.people ?? AdminPeopleLogic.pageDefault, accounts: AdminMembersLogic.picks(o.account),
                      lives: AdminMembersLogic.picks(o.life), branch: o.branch, sub: o.sub)
        }
    }

    /// الفئات الظاهرة بترتيب الأقسام: بلا اختيار = الثلاث؛ ومن لا يرى صفحة النساء = الرجال وحدهم
    static func effective(_ people: Set<Population>, seesOthers: Bool) -> [Population] {
        guard seesOthers else { return [.men] }
        return Population.allCases.filter { people.isEmpty || people.contains($0) }
    }

    /// أكثر من فئة = أقسام بعناوينها
    static func showsSections(_ people: Set<Population>, seesOthers: Bool) -> Bool {
        effective(people, seesOthers: seesOthers).count > 1
    }

    /// «الحالة» لا تنطبق على {خارج العائلة} وحدها (أحياء فقط بقاعدة المالك)
    static func showsLife(_ people: Set<Population>, seesOthers: Bool) -> Bool {
        effective(people, seesOthers: seesOthers) != [.outside]
    }

    /// «القائمة» (قوائم الرجال من الروابط القديمة) تنطبق ما دام الرجال في القائمة
    static func showsList(_ people: Set<Population>, seesOthers: Bool) -> Bool {
        effective(people, seesOthers: seesOthers).contains(.men)
    }

    /// بعد كل لمسة: اختيارات المجموعة المخفية تُمسح — لا شريحة تبقى بلا مجموعة تزيلها، ولا عدد يخالف القائمة
    static func normalize(_ s: inout Filters, seesOthers: Bool) {
        if !showsLife(s.people, seesOthers: seesOthers) { s.lives = [] }
        if !showsList(s.people, seesOthers: seesOthers) { s.sub = nil }
    }

    /// ترتيب الرجال: بالفروع بلا تصفية غير «مَن» ولا بحث (كما كان)، أبجدياً، أو الأقرب للبحث. النساء وخارج العائلة
    /// أبجدياً (أو بالأقرب) دائماً
    static func order(_ s: Filters, seesOthers: Bool, searching: Bool) -> AdminMembersLogic.Order {
        if searching { return .relevance }
        let filtered = !s.accounts.isEmpty || !s.lives.isEmpty || s.branch != nil || s.sub != nil
        let menOnTop = effective(s.people, seesOthers: seesOthers).first == .men
        return filtered || !menOnTop ? .alphabetical : .branches
    }

    // MARK: النصوص

    /// اسم الخيار في «مَن» وشريحته وسطر الوصف
    static func title(_ p: Population) -> String {
        switch p {
        case .men:     return L10n.t("رجال", "Men")
        case .women:   return L10n.t("نساء", "Women")
        case .outside: return L10n.t("خارج العائلة", "Outside the family")
        }
    }

    /// عنوان القسم: «الرجال · 2,729»
    static func sectionTitle(_ p: Population) -> String {
        switch p {
        case .men:     return L10n.t("الرجال", "Men")
        case .women:   return L10n.t("النساء", "Women")
        case .outside: return L10n.t("خارج العائلة", "Outside the family")
        }
    }

    static var groupTitle: String { L10n.t("مَن", "Who") }

    static func title(_ a: Account) -> String {
        switch a {
        case .all:     return AdminFilterText.all
        case .with:    return L10n.t("لهم حساب", "Have an account")
        case .without: return L10n.t("بلا حساب", "No account")
        }
    }

    static func title(_ l: Life) -> String {
        switch l {
        case .all:      return AdminFilterText.all
        case .alive:    return L10n.t("الأحياء", "Living")
        case .deceased: return L10n.t("المتوفون", "Deceased")
        }
    }

    /// سطر الوصف الذهبي تحت «العائلة ⌄»: ما تعرضه القائمة — الفئات المختارة («رجال · نساء») ثم الفرع، أو «كل العائلة»
    static func caption(_ s: Filters, seesOthers: Bool, branch: String?) -> String {
        var parts: [String] = []
        let shown = effective(s.people, seesOthers: seesOthers)
        if seesOthers && shown.count < Population.allCases.count { parts += shown.map { title($0) } }
        let name = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { parts.append(name) }
        return parts.isEmpty ? AdminMembersLogic.caption(branch: nil) : parts.joined(separator: " · ")
    }

    /// المعدود بعد الرقم: «رجل» (كما كان) · «امرأة/امرأتان/نساء/امرأةً» · «فرد/فردان/أفراد/فرداً» حين تختلط الفئات أو
    /// تكون خارج العائلة (رجال ونساء)
    static func noun(_ s: Filters, seesOthers: Bool, _ n: Int) -> String {
        switch effective(s.people, seesOthers: seesOthers) {
        case [.men]:
            return L10n.t("رجل", "men")
        case [.women]:
            return L10n.t(AdminFilterText.noun(n, one: "امرأة", two: "امرأتان", few: "نساء", many: "امرأةً"),
                          n == 1 ? "woman" : "women")
        default:
            return L10n.t(AdminFilterText.noun(n, one: "فرد", two: "فردان", few: "أفراد", many: "فرداً"),
                          n == 1 ? "person" : "people")
        }
    }

    // MARK: القائمة والأعداد (مصدر واحد — T2)

    /// صفّ في القائمة كما يحتاجه الفلتر
    struct Person: Equatable {
        let population: Population
        let deceased: Bool
        /// الرجل: حساب دخول؛ المرأة وخارج العائلة: مربوط بحساب
        let hasAccount: Bool
        /// من يقرّر «الفرع»: الرجل نفسه، أبو المرأة، قريب الخارجي من العائلة — nil = لا يُعرف (لا يدخل فرعاً)
        let anchor: UUID?

        init(population: Population, deceased: Bool, hasAccount: Bool, anchor: UUID?) {
            self.population = population
            self.deceased = deceased
            self.hasAccount = hasAccount
            self.anchor = anchor
        }
    }

    /// صفوف فئة بعد البحث والفرع و«القائمة» (قبل «الحساب» و«الحالة») وعدّها ٢×٢
    struct Part: Equatable {
        var rows: [Int] = []
        var tally = Tally()
    }

    typealias Scope = [Population: Part]

    /// النطاق من المرشّحين (بعد البحث و«القائمة»، بترتيب العرض): يُقسم بالفئة، ويُصفّى بالفرع (`branch` = أعضاء الفرع
    /// المختار — nil = كل الفروع)، و«خارج العائلة» أحياء فقط دائماً
    static func scope(_ persons: [Person], candidates: [Int], branch: Set<UUID>?) -> Scope {
        var out: Scope = [:]
        for i in candidates where persons.indices.contains(i) {
            let p = persons[i]
            if p.population == .outside && p.deceased { continue }
            if let branch {
                guard let anchor = p.anchor, branch.contains(anchor) else { continue }
            }
            out[p.population, default: Part()].rows.append(i)
            out[p.population, default: Part()].tally.add(deceased: p.deceased, hasLogin: p.hasAccount)
        }
        return out
    }

    /// «الحساب» و«الحالة» على صفّ — الشرط الواحد للقائمة والعدّ (`Tally.count(accounts:lives:)`)
    static func matches(_ p: Person, accounts: Set<Account>, lives: Set<Life>) -> Bool {
        AdminMembersLogic.matches(deceased: p.deceased, hasLogin: p.hasAccount, accounts: accounts, lives: lives)
    }

    struct Section: Equatable {
        let population: Population
        let rows: [Int]
    }

    /// الأقسام بترتيبها (فئة واحدة = قسم واحد بلا عنوان). الرجال بفلتر «الحساب» قبل وصول قوائم الحسابات بلا صفوف — الصفحة
    /// تعرض «جارٍ تحميل الحسابات» مكانها
    static func sections(_ scope: Scope, persons: [Person], _ s: Filters, seesOthers: Bool,
                         accountsReady: Bool) -> [Section] {
        effective(s.people, seesOthers: seesOthers).map { p in
            if p == .men && !s.accounts.isEmpty && !accountsReady { return Section(population: p, rows: []) }
            let rows = (scope[p]?.rows ?? []).filter { matches(persons[$0], accounts: s.accounts, lives: s.lives) }
            return Section(population: p, rows: rows)
        }
    }

    /// عدد النتيجة لحالة (من نطاقها) — nil = فئة لم تُحمَّل بعد، أو «الحساب» للرجال قبل قوائم الحسابات («—» لا صفر)
    static func count(_ scope: Scope, _ s: Filters, seesOthers: Bool, ready: Set<Population>,
                      accountsReady: Bool) -> Int? {
        var total = 0
        for p in effective(s.people, seesOthers: seesOthers) {
            guard ready.contains(p) else { return nil }
            let tally = scope[p]?.tally ?? Tally()
            guard let n = tally.shown(accounts: s.accounts, lives: s.lives,
                                      accountsReady: p == .men ? accountsReady : true) else { return nil }
            total += n
        }
        return total
    }

    // MARK: ورقة «تصفية»

    /// مجموعات «العائلة»: مَن ← الحساب ← الحالة ← الفرع ← القائمة (من رابط). عدد كل خيار = النتيجة لو اختير وحده في
    /// مجموعته مع بقية الاختيارات (`result` للحالة المجرّبة). المجموعة التي لا تنطبق على الفئات المختارة لا تُرسم.
    /// - current: الحالة المرسومة (معدود سطر النتيجة) — كل حالة أخرى معدودها من `stateNoun`
    /// - result: عدد النتيجة لأي حالة (يشمل البحث — نفس ما يُرى)
    /// - branchPicker: منتقي الفرع داخل الورقة (`BranchPickerSheet`)
    static func filterSet(current: Filters = Filters(), seesOthers: Bool, result: @escaping (Filters) -> Int?,
                          branchTitle: @escaping (UUID) -> String, subTitle: @escaping (String) -> String,
                          branchPicker: @escaping (_ current: UUID?, _ pick: @escaping (UUID?) -> Void)
                              -> AdminFilterDestination) -> AdminFilterSet<Filters> {
        // الخيار وحده في مجموعته مع بقية الاختيارات كما هي (بلا إصلاح): «خارج العائلة» مع «المتوفون» = 0 — ما يضيفه فعلاً
        func probe(_ s: Filters, _ change: (inout Filters) -> Void) -> Int? {
            var next = s
            change(&next)
            return result(next)
        }
        var set = AdminFilterSet<Filters>(
            noun: { n in noun(current, seesOthers: seesOthers, n) },
            normalize: { normalize(&$0, seesOthers: seesOthers) },
            resultCount: result,
            groups: { s in
                var groups: [AdminFilterGroup<Filters>] = []
                if seesOthers {
                    groups.append(.choices("people", title: groupTitle, values: \.people, options: Population.allCases.map { p in
                        AdminFilterOption(p, title(p), count: probe(s) { $0.people = [p] })
                    }))
                }
                groups.append(.choices("account", title: L10n.t("الحساب", "Account"), values: \.accounts,
                                       options: [Account.with, .without].map { a in
                    AdminFilterOption(a, title(a), count: probe(s) { $0.accounts = [a] })
                }))
                if showsLife(s.people, seesOthers: seesOthers) {
                    groups.append(.choices("life", title: L10n.t("الحالة", "Status"), values: \.lives,
                                           options: [Life.alive, .deceased].map { l in
                        AdminFilterOption(l, title(l), count: probe(s) { $0.lives = [l] })
                    }))
                }
                groups.append(.picker("branch", title: L10n.t("الفرع", "Branch"), value: \.branch, all: nil,
                                      allTitle: L10n.t("كل الفروع", "All branches"), valueTitle: s.branch.map(branchTitle),
                                      chooseTitle: L10n.t("اختر فرعاً", "Pick a branch"),
                                      count: s.branch == nil ? nil : result(s), ownsHeader: true,
                                      destination: branchPicker))
                if let sub = s.sub, showsList(s.people, seesOthers: seesOthers) {
                    groups.append(.single("list", title: L10n.t("القائمة", "List"), value: \.sub, neutral: nil, options: [
                        AdminFilterOption<String?>(nil, AdminFilterText.all, count: probe(s) { $0.sub = nil }),
                        AdminFilterOption<String?>(sub, subTitle(sub), count: result(s)),
                    ]))
                }
                return groups
            })
        set.stateNoun = { s, n in noun(s, seesOthers: seesOthers, n) }
        return set
    }
}
