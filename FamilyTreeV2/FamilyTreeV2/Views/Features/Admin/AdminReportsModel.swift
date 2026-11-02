import Foundation

// MARK: - تقارير العائلة الرسمية (PDF) — البيانات وبناء التقرير
//
// «مكتبة التقارير» (طلب المالك ٢٠٢٦-١١-٠٢ — الاتجاه «أ» مع «كتاب الفرع» من «ج»): رفّ تقارير بأقسام
// العائلة · التواصل · الذكرى · البيانات، وكل تقرير يفتح صفحة تصفيته (`AdminReportFilterPage`)، و«كتاب الفرع» بثلاث
// خطوات (`AdminReportBookWizard`). الأربعة القديمة كما هي بخصوصيتها: «سجل العائلة» · «دليل الهواتف» · «سجل الراحلين» ·
// «الملخّص»، والجديدة: «شجرة فرع مطبوعة» · «تقرير فرع شامل» · «المسجّلون في التطبيق» · «المقيّدون هذا الشهر» ·
// «تقويم الذكرى» · «الناقصة بياناتهم».
// الصفحة تأخذ لقطة من الأعضاء على الخيط الرئيسي (`AdminReportInput.make` — أسماء العرض، تنسيق الهاتف، أسماء الفروع،
// والتجميع من أدوات صفحة الأعضاء `AdminGrouping` ← `AdminReportGroupPlan`)، ثم يُبنى التقرير (`AdminReportBuilder`)
// ويُرسم (`AdminReportPDF`) خارج الخيط الرئيسي — لا تجميد مع ~٢٧٠٠ عضو.
// التعريفات نفسها في اللوحة: الرجال = الشجرة بلا طلبات الانضمام، النساء = إناث شجرة النساء، «عضو مسجّل» = له حساب
// دخول (`AdminAccountsStore`)، الفروع = أبناء رأس الشجرة المباشرون (`BranchPickerSheet.familyRoot`)، والذكرى من
// `DeceasedMemorial` (الميلادي فقط).
// الخصوصية: الهاتف كما وصل من `members_masked`، ومن أخفى رقمه يظهر «مخفي» دائماً — حتى للإدارة (الملف يُشارك خارج
// التطبيق)، ولا تُستنتج دولته منه. الهواتف في «دليل الهواتف» وحده — «كتاب الفرع» وقائمة الحضور بلا هواتف. تاريخ
// الميلاد المخفي يظهر «مخفي» كذلك، ويدخل الإحصاءات المجمّعة فقط. تاريخ وفاة غير مكتمل = «لا يوجد تاريخ كامل للوفاة».
// نصوص الملف عربية دائماً بالمسميات الرسمية (عضو مسجّل، مقيّد في الشجرة، حساب موقوف، بلا رقم هاتف).
// TODO(تقارير مجدولة): تقرير شهري يُرسل تلقائياً يحتاج دالة سيرفر وجدولة وموافقة المالك — غير مبني هنا.

// MARK: - نوع التقرير ورفّه

nonisolated enum AdminReportKind: String, CaseIterable, Identifiable, Sendable {
    case register, tree, branchReport, phones, registered, memorial, calendar, stats, newThisMonth, incomplete
    /// «كتاب الفرع» — من المعالج فقط (ليس صفّاً في الرفّ)
    case book

    var id: String { rawValue }

    /// أقسام الرفّ بترتيبها
    enum Shelf: String, CaseIterable, Sendable {
        case family, contact, memory, data
    }

    var shelf: Shelf {
        switch self {
        case .register, .tree, .branchReport, .book: return .family
        case .phones, .registered: return .contact
        case .memorial, .calendar: return .memory
        case .stats, .newThisMonth, .incomplete: return .data
        }
    }

    /// صفوف الرفّ (بلا الكتاب)
    static let library: [AdminReportKind] = allCases.filter { $0 != .book }

    /// شارة «جديد» في الرفّ
    var isNew: Bool {
        switch self {
        case .register, .phones, .memorial, .stats: return false
        default: return true
        }
    }

    /// عنوان الملف (عربي دائماً)
    var pdfTitle: String {
        switch self {
        case .register: return "سجل العائلة"
        case .tree: return "شجرة الفرع"
        case .branchReport: return "تقرير فرع شامل"
        case .phones: return "دليل الهواتف"
        case .registered: return "المسجّلون في التطبيق"
        case .memorial: return "سجل الراحلين"
        case .calendar: return "تقويم الذكرى"
        case .stats: return "الملخّص الإحصائي"
        case .newThisMonth: return "المقيّدون في الشجرة"
        case .incomplete: return "الناقصة بياناتهم"
        case .book: return "كتاب الفرع"
        }
    }

    /// بداية اسم الملف المشارَك
    var fileStem: String {
        switch self {
        case .register: return "سجل-العائلة"
        case .tree: return "شجرة-الفرع"
        case .branchReport: return "تقرير-فرع"
        case .phones: return "دليل-الهواتف"
        case .registered: return "المسجلون"
        case .memorial: return "سجل-الراحلين"
        case .calendar: return "تقويم-الذكرى"
        case .stats: return "الملخص"
        case .newThisMonth: return "المقيدون"
        case .incomplete: return "الناقصة-بياناتهم"
        case .book: return "كتاب-الفرع"
        }
    }

    // MARK: ما تعرضه صفحة التصفية لكل نوع

    var usesBranch: Bool { self != .stats && self != .book }
    var usesLife: Bool { self == .register || self == .newThisMonth || self == .incomplete }
    var usesRegistration: Bool { self == .register || self == .registered }
    var usesAge: Bool { self == .register || self == .registered || self == .phones }
    var usesPeriod: Bool { self == .newThisMonth }
    var usesMissing: Bool { self == .incomplete }
    var usesPhonesFilter: Bool { self == .phones }
    var usesMemorialFilter: Bool { self == .memorial }
    /// التجميع متاح (السجلات والقوائم)
    var usesGrouping: Bool { [.register, .phones, .registered, .newThisMonth, .incomplete, .branchReport].contains(self) }

    /// البيانات المتاحة للنوع بترتيبها الافتراضي (= ترتيب الأعمدة من اليمين)
    var fields: [AdminReportField] {
        switch self {
        case .register: return [.name, .branch, .father, .birth, .age, .status, .death, .registration, .country, .phone]
        case .phones: return [.name, .branch, .phone, .status, .country]
        case .memorial: return [.name, .death, .anniversary, .ageAtDeath, .branch]
        case .stats: return [.people, .ages, .branches, .registered]
        case .registered: return [.name, .branch, .registration, .father, .birth, .age, .country]
        case .newThisMonth: return [.name, .created, .branch, .father, .birth, .status, .registration]
        case .incomplete: return [.name, .missing, .branch, .father, .birth, .status]
        case .branchReport: return [.name, .birth, .age, .status, .death, .registration]
        case .tree, .calendar, .book: return []
        }
    }

    /// لا تُزال: الاسم في كل جدول، والرقم في دليل الهواتف، وما يقوم عليه التقرير
    var lockedFields: Set<AdminReportField> {
        switch self {
        case .register, .memorial, .branchReport: return [.name]
        case .phones: return [.name, .phone]
        case .registered: return [.name, .registration]
        case .newThisMonth: return [.name, .created]
        case .incomplete: return [.name, .missing]
        case .stats, .tree, .calendar, .book: return []
        }
    }

    /// الافتراضي = ما كان يُطبع قبل الاختيار
    var defaultFields: Set<AdminReportField> {
        switch self {
        case .register: return [.name, .birth, .age, .status]
        case .phones: return [.name, .phone, .status]
        case .memorial: return [.name, .death, .anniversary]
        case .stats: return [.people, .ages, .branches, .registered]
        case .registered: return [.name, .branch, .registration]
        case .newThisMonth: return [.name, .created, .father, .birth]
        case .incomplete: return [.name, .missing, .father]
        case .branchReport: return [.name, .birth, .age, .status]
        case .tree, .calendar, .book: return []
        }
    }

    /// المختار مرتّباً: المقفل أولاً بترتيب النوع، ثم المختار بترتيبه المحفوظ — nil = الافتراضي
    func orderedFields(_ saved: [AdminReportField]?) -> [AdminReportField] {
        let base = saved ?? fields.filter(defaultFields.contains)
        var out = fields.filter(lockedFields.contains)
        for f in base where fields.contains(f) && !out.contains(f) { out.append(f) }
        return out
    }

    /// للأقسام (الملخّص): مجموعة بلا ترتيب
    func resolvedFields(_ chosen: Set<AdminReportField>?) -> Set<AdminReportField> {
        (chosen ?? defaultFields).intersection(fields).union(lockedFields)
    }
}

/// ما يُطبع في التقرير — أعمدة الجداول أو أقسام الملخّص. الاختيار وترتيبه يُحفظان لكل نوع ولكل مستخدم.
nonisolated enum AdminReportField: String, CaseIterable, Identifiable, Sendable {
    // أعمدة
    case name, branch, father, birth, age, status, death, phone, registration, country, created, missing
    case anniversary, ageAtDeath
    // أقسام الملخّص
    case people, ages, branches, registered

    var id: String { rawValue }
}

/// التجميع (نفس خيارات صفحة الأعضاء — `AdminMemberGrouping`)
nonisolated enum AdminReportGrouping: String, CaseIterable, Identifiable, Sendable {
    case branch, father, birthDecade, alphabet, country

    var id: String { rawValue }

    /// اسمه على الغلاف (عربي دائماً)
    var pdfLabel: String {
        switch self {
        case .branch: return "حسب الفرع"
        case .father: return "حسب الأب"
        case .birthDecade: return "حسب عقد الميلاد"
        case .alphabet: return "أبجدياً"
        case .country: return "حسب الدولة"
        }
    }
}

/// أقسام «كتاب الفرع» بترتيبها في الملف
nonisolated enum AdminReportBookSection: String, CaseIterable, Identifiable, Sendable {
    case cover, tree, register, memorial, form, attendance, cards
    /// «الأعداد» — في «تقرير فرع شامل» فقط
    case numbers

    var id: String { rawValue }

    /// ما يعرضه المعالج (بلا «الأعداد»)
    static let wizard: [AdminReportBookSection] = [.cover, .tree, .register, .memorial, .form, .attendance, .cards]
    /// الافتراضي في المعالج
    static let wizardDefault: Set<AdminReportBookSection> = [.cover, .tree, .register, .memorial]
    /// «تقرير فرع شامل»
    static let branchReport: Set<AdminReportBookSection> = [.cover, .numbers, .tree, .register, .memorial]

    /// عنوان القسم في الملف وفهرسه
    var pdfTitle: String {
        switch self {
        case .cover: return "الغلاف"
        case .tree: return "شجرة الفرع"
        case .register: return "سجل الأفراد"
        case .memorial: return "الراحلون وذكراهم"
        case .form: return "استمارة استكمال البيانات"
        case .attendance: return "قائمة الحضور"
        case .cards: return "بطاقات الأفراد"
        case .numbers: return "الأعداد"
        }
    }
}

nonisolated struct AdminReportFilter: Equatable, Sendable {
    enum Life: String, CaseIterable, Sendable { case all, living, deceased }
    /// التسجيل في التطبيق (الأحياء): مسجّل · مقيّد · موقوف
    enum Registration: String, CaseIterable, Sendable { case all, registered, treeOnly, frozen }
    enum Phones: String, CaseIterable, Sendable { case all, registered, noPhone }
    enum Memorial: String, CaseIterable, Sendable { case all, incomplete }
    /// «المقيّدون»: الفترة من `created_at` بتوقيت الكويت
    enum Period: String, CaseIterable, Sendable { case thisMonth, lastMonth, last90 }
    /// «الناقصة بياناتهم»: ما ينقص
    enum Missing: String, CaseIterable, Sendable { case any, birth, death, photo, father }

    /// فئات العمر — «الفئات العمرية» في الملخّص. العمر = اليوم للحي، وعند الوفاة للمتوفى؛ الميلاد المخفي أو الناقص
    /// = «غير معروف» (لا يُستنتج عمر من أخفى ميلاده)
    enum Age: String, CaseIterable, Sendable {
        case all, under18, from18to30, from31to50, from51to70, over70, unknown

        static let bands: [Age] = [.under18, .from18to30, .from31to50, .from51to70, .over70]

        static func band(_ years: Int?) -> Age {
            guard let years else { return .unknown }
            switch years {
            case ..<18: return .under18
            case 18...30: return .from18to30
            case 31...50: return .from31to50
            case 51...70: return .from51to70
            default: return .over70
            }
        }

        var label: String {
            switch self {
            case .all: return "كل الأعمار"
            case .under18: return "أقل من 18"
            case .from18to30: return "18–30"
            case .from31to50: return "31–50"
            case .from51to70: return "51–70"
            case .over70: return "فوق 70"
            case .unknown: return "غير معروف"
            }
        }
    }

    /// سقف شريط العمر — «100+» = بلا حدّ أعلى
    static let ageCap = 100

    /// ما جاء من صفحة الأعضاء («⋯ ← تصدير» بالشريحة والبحث) — لسجل العائلة فقط
    struct Scope: Equatable, Sendable {
        let ids: Set<UUID>
        let title: String
    }

    /// فرع بأي مستوى (هو ونسله) — nil = العائلة كاملة
    var branch: UUID? = nil
    var life: Life = .all
    var registration: Registration = .all
    var phones: Phones = .all
    var memorial: Memorial = .all
    var period: Period = .thisMonth
    var missing: Missing = .any
    /// مدى العمر الحرّ — المدى الكامل = بلا تصفية؛ غيره يستثني «غير معروف»
    var ageMin: Int = 0
    var ageMax: Int = AdminReportFilter.ageCap
    var grouping: AdminReportGrouping = .branch
    var scope: Scope? = nil

    var ageLimited: Bool { ageMin > 0 || ageMax < Self.ageCap }

    /// «18–50 سنة» · «من 18 سنة» · «حتى 50 سنة»
    var ageLabel: String {
        switch (ageMin > 0, ageMax < Self.ageCap) {
        case (true, true): return "\(ageMin)–\(ageMax) سنة"
        case (true, false): return "من \(ageMin) سنة"
        case (false, true): return "حتى \(ageMax) سنة"
        default: return ""
        }
    }

    func ageMatches(_ years: Int?) -> Bool {
        guard ageLimited else { return true }
        guard let years else { return false }
        return years >= ageMin && (ageMax >= Self.ageCap || years <= ageMax)
    }
}

// MARK: - التجميع (يُحسب على الخيط الرئيسي من `AdminGrouping`)

/// أقسام التقرير بالترتيب: عنوان، مسار (للفرع المتداخل)، عمق، والأعضاء — الملف يأخذ منها من في التصفية فقط
nonisolated struct AdminReportGroupPlan: Sendable {
    struct Section: Sendable {
        let title: String
        /// «فرع محمد ‹ فرع عبدالله» — المستويات فوق هذا القسم (التجميع بالفرع)
        let path: String?
        let depth: Int
        let ids: [UUID]
    }

    let grouping: AdminReportGrouping
    let sections: [Section]

    static let empty = AdminReportGroupPlan(grouping: .branch, sections: [])
}

// MARK: - اللقطة (تُؤخذ على الخيط الرئيسي)

nonisolated struct AdminReportPerson: Sendable {
    let id: UUID
    let fatherId: UUID?
    /// الاسم الكامل للعرض (مع العائلة المختارة)
    let name: String
    let firstName: String
    let sortOrder: Int
    let birth: String?
    let birthHidden: Bool
    let deceased: Bool
    let death: String?
    let deathUnknown: Bool
    let frozen: Bool
    /// المعيار القانوني للعدّ (`FamilyMember.isCountable`)
    let countable: Bool
    /// الرقم منسّقاً للعرض — nil = لا رقم في السجل (أو غير ظاهر)
    let phone: String?
    let phoneHidden: Bool
    /// الدولة من مفتاح الهاتف — nil لمن أخفى رقمه أو بلا رقم
    let country: String?
    /// تاريخ القيد في الشجرة (`created_at`)
    let createdAt: Date?
    let hasPhoto: Bool
    /// اسم الأب المختصر (عمود «الأب»)
    let fatherName: String?
    /// النسب: «بن فلان بن فلان» (بطاقات الأفراد)
    let lineage: String
}

nonisolated struct AdminReportWoman: Sendable {
    let deceased: Bool
    let birth: String?
}

nonisolated struct AdminReportInput: Sendable {
    /// أعضاء الشجرة بلا طلبات الانضمام ولا الأسماء الفارغة
    let people: [AdminReportPerson]
    let rootId: UUID?
    /// إناث شجرة النساء — nil = لم تُحمَّل
    let women: [AdminReportWoman]?
    /// لهم حساب دخول — nil = لم تصل القوائم
    let registered: Set<UUID>?
    /// أسماء الفروع المخصّصة (رأس الفرع ← الاسم) — لكل المستويات
    let branchNames: [UUID: String]
    let generatedBy: String
    let date: Date

    @MainActor
    static func make(members: [FamilyMember], women: [FamilyMember]?, registered: Set<UUID>?,
                     branchName: (UUID) -> String?, generatedBy: String, date: Date = Date()) -> AdminReportInput {
        var byId: [UUID: FamilyMember] = [:]
        byId.reserveCapacity(members.count)
        for m in members { byId[m.id] = m }
        var people: [AdminReportPerson] = []
        people.reserveCapacity(members.count)
        var names: [UUID: String] = [:]
        // سجلّ بلا اسم (رقم دخول بلا اسم) ليس فرداً في العائلة — `displayFullName` يلحق به اسم العائلة فلا يُكتشف بعده
        for m in members where m.role != .pending && m.hasName {
            let name = m.displayFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let raw = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hidden = m.isPhoneHidden == true
            let country: String? = hidden || raw.isEmpty ? nil : AdminAnnounceKit.iso(m).flatMap { code in
                KuwaitPhone.supportedCountries.first { $0.isoCode == code }?.nameArabic
            }
            let father = m.fatherId.flatMap { byId[$0] }
            let grand = father?.fatherId.flatMap { byId[$0] }
            let lineage = [father, grand].compactMap { $0 }
                .map { "بن \($0.firstName.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .joined(separator: " ")
            let photo = [m.avatarUrl, m.photoURL].contains { !($0 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            people.append(AdminReportPerson(
                id: m.id, fatherId: m.fatherId, name: name,
                firstName: m.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: m.sortOrder, birth: m.birthDate, birthHidden: m.isBirthDateHidden == true,
                deceased: m.isDeceased == true, death: m.deathDate, deathUnknown: m.deathDateUnknown == true,
                frozen: m.status == .frozen, countable: m.isCountable,
                phone: raw.isEmpty ? nil : KuwaitPhone.display(raw), phoneHidden: hidden,
                country: country, createdAt: ApprovalWorkflow.date(m.createdAt), hasPhoto: photo,
                fatherName: father.map { $0.shortFullName.isEmpty ? $0.firstName : $0.shortFullName },
                lineage: lineage))
            if let n = branchName(m.id) { names[m.id] = n }
        }
        let root = BranchPickerSheet.familyRoot(in: members)
        let womenFacts = women.map { list in
            list.filter { $0.isFemale && $0.hasName }.map { AdminReportWoman(deceased: $0.isDeceased == true, birth: $0.birthDate) }
        }
        return AdminReportInput(people: people, rootId: root?.id, women: womenFacts, registered: registered,
                                branchNames: names, generatedBy: generatedBy, date: date)
    }
}

// MARK: - التقرير المبني (ما يرسمه `AdminReportPDF`)

nonisolated enum AdminReportTone: Sendable {
    case normal, muted, warning, men, women, total, registered, treeOnly
    /// خانة فارغة تُعبّأ باليد: خطّ منقّط بعد النص (إن وُجد)
    case blank
    /// مربّع ☐ يُعلَّم باليد
    case checkbox
}

nonisolated struct AdminReportTile: Sendable {
    let value: String
    let label: String
}

nonisolated struct AdminReportRing: Sendable {
    let title: String
    let living: Int
    let deceased: Int
    let tone: AdminReportTone
    /// false = البيانات غير متاحة (شجرة النساء لم تُحمَّل)
    var available: Bool = true
}

/// عمود/شريط: جزء أول (أحياء/مسجّل) وجزء ثانٍ (متوفون) ونصّه
nonisolated struct AdminReportBar: Sendable {
    let label: String
    let first: Int
    var second: Int = 0
    let caption: String
}

nonisolated struct AdminReportSplit: Sendable {
    let firstLabel: String
    let first: Int
    let secondLabel: String
    let second: Int
}

nonisolated struct AdminReportTable: Sendable {
    struct Column: Sendable {
        let title: String
        /// نسبة من عرض الصفحة (تُطبَّع) — للجداول بلا عمود `fill` فقط
        var weight: Double = 0
        /// أرقام الهاتف: اتجاه يسار←يمين داخل الخلية
        var ltr: Bool = false
        /// يلتفّ لأكثر من سطر (الأسماء) — غيره سطر واحد مقاس عرضه
        var wraps: Bool = false
        var centered: Bool = false
        /// يأخذ ما بقي من العرض (الاسم) — وكل عمود غيره بعرض أطول محتواه (`AdminReportPDF.plan`)
        var fill: Bool = false
        /// أقلّ عرض (خانة تُعبّأ باليد)
        var minWidth: Double = 0
    }

    struct Row: Sendable {
        let cells: [String]
        /// لون خلية بعينها (المتوفى خافت، «السنة فقط» كهرماني) أو خانة تُعبّأ (`blank`/`checkbox`)
        var tones: [Int: AdminReportTone] = [:]
    }

    let columns: [Column]
    var rows: [Row]
    /// صفّ المجموع (عريض)
    var footer: Row? = nil
    /// سطر المجموع تحت الجدول («المجموع: 7 أفراد — مسجّلون 5 · …»)
    var summary: String? = nil
    /// صفوف أعلى (استمارة تُعبّأ باليد)
    var roomy: Bool = false
}

/// «شجرة الفروع» المصغّرة: المؤسس ← فروعه الكبرى وعدد أفراد كل فرع
nonisolated struct AdminReportMiniTree: Sendable {
    struct Node: Sendable {
        let title: String
        let caption: String?
        let count: Int
        var isRest: Bool = false
    }

    let founder: String
    let founderCaption: String
    let nodes: [Node]
}

/// صفحة من «شجرة الفرع المطبوعة»: عقد بمستويات (الأولى الرأس) — الرسم يوزّعها على عرض الصفحة
nonisolated struct AdminReportTreeChart: Sendable {
    struct Node: Sendable {
        let title: String
        /// «1918 – 1989» أو «46 فرداً»
        let caption: String?
        let deceased: Bool
        /// له نسل خارج هذه الصفحة (صفحته الخاصة، أو مختصر)
        let continued: Bool
        let children: [Int]
    }

    let title: String
    let subtitle: String?
    /// nodes[0] = الرأس
    let nodes: [Node]
}

/// بطاقة فرد (بطاقات الأفراد)
nonisolated struct AdminReportCard: Sendable {
    let name: String
    let lineage: String
    let lines: [String]
    let deceased: Bool
}

nonisolated enum AdminReportBlock: Sendable {
    case tiles([AdminReportTile])
    /// عنوان لوحة إحصاء
    case heading(String, subtitle: String?, panel: Bool)
    /// شريط كريمي لمجموعة (بيت، فرع، شهر…) — `toc`: يدخل الفهرس
    case band(String, subtitle: String?, toc: Bool)
    /// قسم كبير يبدأ صفحة جديدة ويدخل الفهرس (أقسام الكتاب، أشهر التقويم)
    case section(String, subtitle: String?)
    case pageBreak
    case table(AdminReportTable)
    case note(String, tone: AdminReportTone)
    case rings([AdminReportRing])
    case bars([AdminReportBar], firstLabel: String, secondLabel: String?, firstTone: AdminReportTone)
    case split(AdminReportSplit)
    case miniTree(AdminReportMiniTree)
    /// صفحة شجرة كاملة (تبدأ صفحة جديدة)
    case treeChart(AdminReportTreeChart)
    /// صفّ من بطاقتين
    case cardRow([AdminReportCard])
    /// خطوط توقيع/تعبئة بأسمائها تحتها («اسم من عبّأها · التاريخ · استلمها»)
    case signatures([String])
    /// سطر صغير رمادي
    case caption(String)
}

nonisolated struct AdminReportDoc: Sendable {
    let kind: AdminReportKind
    /// سطر النطاق («فرع محمد ‹ فرع عبدالله · أحياء») — فارغ = بلا تصفية
    let scope: String
    /// عدد الأفراد في التقرير (سطر العدد وصفحة الغلاف)
    let count: Int
    /// فقرة الغلاف: ما يحويه التقرير
    let intro: String
    let blocks: [AdminReportBlock]
    let generatedBy: String
    let date: Date
    /// «حسب الأب» على الغلاف
    var grouping: String? = nil
    /// false = بلا غلاف (الكتاب بلا «غلاف»)
    var cover: Bool = true
    /// عنوان الملف — nil = عنوان النوع
    var customTitle: String? = nil

    var title: String { customTitle ?? kind.pdfTitle }

    /// «سجل العائلة · فرع عبدالله · أحياء — 184 فرداً»
    var summaryLine: String {
        let head = scope.isEmpty ? title : "\(title) · \(scope)"
        return "\(head) — \(AdminReportText.people(count))"
    }
}

// MARK: - نصوص (أرقام لاتينية مثل باقي التطبيق)

nonisolated enum AdminReportText {
    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        return f
    }()

    static func num(_ n: Int) -> String { grouping.string(from: NSNumber(value: n)) ?? "\(n)" }

    /// المعدود وحده بعد رقم مرسوم منفصلاً: «أفراد» (3–10) · «فرداً» (11–99) · «فرد»
    static func peopleNoun(_ n: Int) -> String {
        switch n % 100 {
        case 3...10: return "أفراد"
        case 11...99: return "فرداً"
        default: return "فرد"
        }
    }

    /// «فرد واحد» · «فردان» · «3 أفراد» · «11 فرداً» · «100 فرد» · «2,344 فرداً»
    static func people(_ n: Int) -> String {
        if n == 1 { return "فرد واحد" }
        if n == 2 { return "فردان" }
        switch n % 100 {
        case 3...10: return "\(num(n)) أفراد"
        case 11...99: return "\(num(n)) فرداً"
        default: return "\(num(n)) فرد"
        }
    }

    /// «12 فرعاً» …
    static func branches(_ n: Int) -> String {
        if n == 1 { return "فرع واحد" }
        if n == 2 { return "فرعان" }
        switch n % 100 {
        case 3...10: return "\(num(n)) فروع"
        case 11...99: return "\(num(n)) فرعاً"
        default: return "\(num(n)) فرع"
        }
    }

    /// «صفحة واحدة» · «صفحتان» · «3 صفحات» · «12 صفحة»
    static func pages(_ n: Int) -> String {
        if n == 1 { return "صفحة واحدة" }
        if n == 2 { return "صفحتان" }
        switch n % 100 {
        case 3...10: return "\(num(n)) صفحات"
        default: return "\(num(n)) صفحة"
        }
    }

    /// «اليوم» · «غداً» · «بعد يومين» · «بعد 5 أيام» · «بعد 12 يوماً» · «بعد 100 يوم»
    static func inDays(_ n: Int) -> String {
        switch n {
        case 0: return "اليوم"
        case 1: return "غداً"
        case 2: return "بعد يومين"
        default:
            switch n % 100 {
            case 3...10: return "بعد \(n) أيام"
            case 11...99: return "بعد \(n) يوماً"
            default: return "بعد \(n) يوم"
            }
        }
    }

    static func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "0٪" }
        return "\(Int((Double(part) / Double(total) * 100).rounded()))٪"
    }

    /// تاريخ من القاعدة: «12 مارس 1995» · السنة فقط «1995» · هجري مكتوب كميلادي «1418 هـ» · لا شيء = nil
    static func date(_ raw: String?) -> String? {
        switch DeceasedMemorial.classify(raw) {
        case .exact(let y, let m, let d): return "\(DeceasedMemorial.dayMonth(day: d, month: m, arabic: true)) \(y)"
        case .yearOnly(let y): return "\(y)"
        case .hijriLike(let y): return "\(y) هـ"
        case .missing: return nil
        }
    }

    /// تاريخ الوفاة كما يُطبع: الكامل فقط، وغيره «لا يوجد تاريخ كامل للوفاة» (القاعدة نفسها في «المناسبات»)
    static func deathDate(_ raw: String?) -> String {
        if case let .exact(y, m, d) = DeceasedMemorial.classify(raw) {
            return "\(DeceasedMemorial.dayMonth(day: d, month: m, arabic: true)) \(y)"
        }
        return noFullDeathDate
    }

    static func date(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(DeceasedMemorial.dayMonth(day: c.day ?? 1, month: c.month ?? 1, arabic: true)) \(c.year ?? 0)"
    }

    /// سنة ميلادية تُطبع في الشجرة (الكامل والسنة وحدها؛ لا الهجري)
    static func year(_ raw: String?) -> Int? {
        switch DeceasedMemorial.classify(raw) {
        case .exact(let y, _, _), .yearOnly(let y): return y
        default: return nil
        }
    }

    /// الكويت دائماً (ملف رسمي) — التقويم الميلادي
    static var kuwait: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kuwait") ?? .current
        return c
    }

    /// «الثلاثاء 20 أكتوبر 2026»
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar@numbers=latn")
        f.calendar = kuwait
        f.timeZone = kuwait.timeZone
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: date)
    }

    /// «2:35 م»
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar@numbers=latn")
        f.calendar = kuwait
        f.timeZone = kuwait.timeZone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// العمر بالسنوات: اليوم للحي، وعند الوفاة للمتوفى (السنة وحدها تُحسب بالسنوات) — nil إن تعذّر
    static func age(birth: String?, deceased: Bool, death: String?, deathUnknown: Bool, today: Date,
                    calendar cal: Calendar) -> Int? {
        let born = DeceasedMemorial.classify(birth)
        let end: DeceasedMemorial.DateKind
        if deceased {
            guard !deathUnknown else { return nil }
            end = DeceasedMemorial.classify(death)
        } else {
            let c = cal.dateComponents([.year, .month, .day], from: today)
            end = .exact(year: c.year ?? 0, month: c.month ?? 1, day: c.day ?? 1)
        }
        let years: Int
        switch (born, end) {
        case let (.exact(by, bm, bd), .exact(ey, em, ed)):
            years = ey - by - ((em, ed) < (bm, bd) ? 1 : 0)
        case let (.exact(by, _, _), .yearOnly(ey)), let (.yearOnly(by), .exact(ey, _, _)), let (.yearOnly(by), .yearOnly(ey)):
            years = ey - by
        default:
            return nil
        }
        return (0..<130).contains(years) ? years : nil
    }

    static let familyName = "عائلة المحمدعلي"
    static let confidential = "سرّي — لعائلة المحمدعلي فقط"
    static let registered = "عضو مسجّل"
    static let treeOnly = "مقيّد في الشجرة"
    static let frozen = "حساب موقوف"
    static let hidden = "مخفي"
    static let noPhone = "بلا رقم هاتف"
    static let deathIncomplete = "تاريخ الوفاة غير مكتمل"
    static let noFullDeathDate = "لا يوجد تاريخ كامل للوفاة"
}

// MARK: - الشجرة (مرور واحد): الترتيب والفروع

nonisolated struct AdminReportTree {
    let pool: [AdminReportPerson]
    let rootId: UUID?
    /// أبناء رأس الشجرة بالترتيب
    let heads: [AdminReportPerson]
    /// العضو ← رأس فرعه
    let branchOf: [UUID: UUID]
    /// ترتيب الشجرة (عمق أولاً، الإخوة بترتيبهم) — عدده = أفراد الشجرة الموصولون برأسها
    let order: [UUID: Int]
    let byId: [UUID: AdminReportPerson]
    /// الأبناء مرتّبين (معرّفات)
    let kids: [UUID: [UUID]]

    init(_ people: [AdminReportPerson], rootId: UUID?) {
        pool = people
        self.rootId = rootId
        var byId: [UUID: AdminReportPerson] = [:]
        byId.reserveCapacity(people.count)
        var kids: [UUID: [AdminReportPerson]] = [:]
        for p in people {
            byId[p.id] = p
            if let f = p.fatherId { kids[f, default: []].append(p) }
        }
        func sorted(_ list: [AdminReportPerson]) -> [AdminReportPerson] {
            list.sorted { ($0.sortOrder, $0.firstName, $0.name) < ($1.sortOrder, $1.firstName, $1.name) }
        }
        for (k, v) in kids where v.count > 1 { kids[k] = sorted(v) }

        var branchOf: [UUID: UUID] = [:]
        var order: [UUID: Int] = [:]
        var heads: [AdminReportPerson] = []
        if let rootId {
            heads = kids[rootId] ?? []
            // عمق أولاً بمكدس (بلا تعاود) — الإخوة يُدفعون معكوسين فيخرج الأكبر ترتيباً أولاً
            var stack: [(UUID, UUID?)] = [(rootId, nil)]
            var visited: Set<UUID> = []
            var index = 0
            while let (id, head) = stack.popLast() {
                guard visited.insert(id).inserted else { continue }
                if byId[id] != nil {
                    order[id] = index
                    index += 1
                    if let head { branchOf[id] = head }
                }
                for c in (kids[id] ?? []).reversed() where !visited.contains(c.id) {
                    stack.append((c.id, head ?? (id == rootId ? c.id : nil)))
                }
            }
        }
        self.heads = heads
        self.branchOf = branchOf
        self.order = order
        self.byId = byId
        self.kids = kids.mapValues { $0.map(\.id) }
    }

    /// عدد العضو ونسله
    func count(under id: UUID) -> Int { subtree(id).count }

    func title(ofHead head: AdminReportPerson, names: [UUID: String]) -> String {
        names[head.id] ?? "فرع \(head.firstName.isEmpty ? head.name : head.firstName)"
    }

    /// فرع العضو كما يُطبع في عمود «الفرع» (الفرع الأول)
    func branchLabel(of p: AdminReportPerson, names: [UUID: String]) -> String {
        if p.id == rootId { return "رأس الشجرة" }
        guard let h = branchOf[p.id], let head = byId[h] else { return "خارج الفروع" }
        return title(ofHead: head, names: names)
    }

    /// العضو ونسله
    func subtree(_ id: UUID) -> Set<UUID> {
        var out: Set<UUID> = [id]
        var stack = [id]
        while let cur = stack.popLast() {
            for c in kids[cur] ?? [] where out.insert(c).inserted { stack.append(c) }
        }
        return out
    }

    /// «فرع محمد ‹ فرع عبدالله» — من ابن الرأس حتى العضو (لسطر النطاق)
    func path(to id: UUID, names: [UUID: String]) -> String {
        var chain: [UUID] = [id]
        var cur = id
        while let f = byId[cur]?.fatherId, f != rootId, byId[f] != nil, chain.count < BranchPickerSheet.maxTreeDepth {
            chain.append(f)
            cur = f
        }
        return chain.reversed().compactMap { byId[$0] }.map { title(ofHead: $0, names: names) }.joined(separator: " ‹ ")
    }

    /// مجموعات بالفروع الأولى: رأس الشجرة ← الفروع بترتيبها ← «خارج الفروع» (بالاسم)
    struct Group {
        let title: String
        let head: AdminReportPerson?
        let members: [AdminReportPerson]
    }

    func groups(_ members: [AdminReportPerson], names: [UUID: String]) -> [Group] {
        var byHead: [UUID: [AdminReportPerson]] = [:]
        var rootRow: [AdminReportPerson] = []
        var outside: [AdminReportPerson] = []
        for p in members {
            if p.id == rootId { rootRow.append(p) }
            else if let h = branchOf[p.id] { byHead[h, default: []].append(p) }
            else { outside.append(p) }
        }
        var out: [Group] = []
        if !rootRow.isEmpty { out.append(Group(title: "رأس الشجرة", head: nil, members: rootRow)) }
        for head in heads {
            guard let list = byHead[head.id], !list.isEmpty else { continue }
            out.append(Group(title: title(ofHead: head, names: names), head: head,
                             members: list.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }))
        }
        if !outside.isEmpty {
            out.append(Group(title: "خارج الفروع", head: nil,
                             members: outside.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
        }
        return out
    }

    /// أقسام التقرير من خطّة التجميع: من في `members` فقط، بترتيب الشجرة داخل الفرع/البيت، ومن لم يرد في الخطّة آخراً
    struct Section {
        let title: String
        let path: String?
        let depth: Int
        let members: [AdminReportPerson]
    }

    func sections(_ members: [AdminReportPerson], plan: AdminReportGroupPlan, names: [UUID: String]) -> [Section] {
        guard !plan.sections.isEmpty else {
            return groups(members, names: names).map { Section(title: $0.title, path: nil, depth: 0, members: $0.members) }
        }
        let byId = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var placed: Set<UUID> = []
        var out: [Section] = []
        let treeOrdered = plan.grouping == .branch || plan.grouping == .father
        for s in plan.sections {
            var list = s.ids.compactMap { byId[$0] }
            guard !list.isEmpty else { continue }
            if treeOrdered { list.sort { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) } }
            else { list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
            placed.formUnion(list.map(\.id))
            out.append(Section(title: s.title, path: s.path, depth: s.depth, members: list))
        }
        let rest = members.filter { !placed.contains($0.id) }
        if !rest.isEmpty {
            out.append(Section(title: "أخرى", path: nil, depth: 0,
                               members: rest.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
        }
        return out
    }
}

// MARK: - بناء التقارير

/// صفّ يُبنى عموداً عموداً (الأعمدة المختارة فقط) — اللون بفهرس العمود
nonisolated struct AdminReportRowBuilder {
    private(set) var cells: [String] = []
    private(set) var tones: [Int: AdminReportTone] = [:]

    mutating func add(_ text: String, _ tone: AdminReportTone? = nil) {
        if let tone { tones[cells.count] = tone }
        cells.append(text)
    }

    var row: AdminReportTable.Row { .init(cells: cells, tones: tones) }
}

/// ما يُطلب بناؤه — يُحسب مرة لكل تغيّر في الصفحة
nonisolated struct AdminReportRequest: Sendable {
    let kind: AdminReportKind
    let filter: AdminReportFilter
    /// الأعمدة بترتيبها (أو أقسام الملخّص)
    let fields: [AdminReportField]
    let plan: AdminReportGroupPlan
    /// أقسام الكتاب («كتاب الفرع» / «تقرير فرع شامل»)
    var book: Set<AdminReportBookSection> = []
}

nonisolated enum AdminReportBuilder {

    static func build(_ request: AdminReportRequest, input: AdminReportInput) -> AdminReportDoc {
        let tree = AdminReportTree(input.people, rootId: input.rootId)
        let r = request
        switch r.kind {
        case .register: return register(tree, input, r)
        case .stats: return stats(tree, input, Set(r.kind.resolvedFields(Set(r.fields))))
        case .memorial: return memorial(tree, input, r.filter, Set(r.fields))
        case .phones: return phones(tree, input, r)
        case .registered: return registered(tree, input, r)
        case .newThisMonth: return newMembers(tree, input, r)
        case .incomplete: return incomplete(tree, input, r)
        case .calendar: return calendar(tree, input, r.filter)
        case .tree: return treeOnly(tree, input, r.filter)
        case .branchReport: return book(tree, input, r, sections: AdminReportBookSection.branchReport)
        case .book: return book(tree, input, r, sections: r.book)
        }
    }

    // MARK: أدوات مشتركة

    /// الهاتف كما يُطبع: من أخفاه «مخفي» دائماً، ولا رقم «—»
    static func phoneText(_ p: AdminReportPerson) -> String {
        p.phoneHidden ? AdminReportText.hidden : (p.phone ?? "—")
    }

    /// حالة التسجيل في التطبيق: حساب موقوف · عضو مسجّل · مقيّد في الشجرة («—» إن لم تصل القوائم)
    static func registrationText(_ p: AdminReportPerson, _ reg: Set<UUID>?) -> String {
        if p.frozen { return AdminReportText.frozen }
        guard let reg else { return "—" }
        return reg.contains(p.id) ? AdminReportText.registered : AdminReportText.treeOnly
    }

    static func registration(_ p: AdminReportPerson, _ reg: Set<UUID>?) -> AdminReportFilter.Registration? {
        if p.frozen { return .frozen }
        guard let reg else { return nil }
        return reg.contains(p.id) ? .registered : .treeOnly
    }

    /// عنوان الفرع المختار (شريحة الفرع وسطر النطاق)
    static func branchTitle(_ id: UUID, input: AdminReportInput) -> String {
        if let n = input.branchNames[id] { return n }
        let p = input.people.first { $0.id == id }
        return "فرع \(p.map { $0.firstName.isEmpty ? $0.name : $0.firstName } ?? "")"
    }

    /// النطاق: الفرع المختار (هو ونسله) أو كل الشجرة، وسطره
    static func scoped(_ tree: AdminReportTree, _ input: AdminReportInput, _ filter: AdminReportFilter,
                       _ pool: [AdminReportPerson], parts: inout [String]) -> [AdminReportPerson] {
        var pool = pool
        if let b = filter.branch {
            let ids = tree.subtree(b)
            pool = pool.filter { ids.contains($0.id) }
            parts.append(tree.byId[b] != nil ? tree.path(to: b, names: input.branchNames) : branchTitle(b, input: input))
        } else {
            parts.append("العائلة كاملة")
        }
        return pool
    }

    /// الأعمار مرة واحدة لكل فرد — المخفي ميلاده بلا عمر
    static func ages(_ pool: [AdminReportPerson], _ input: AdminReportInput) -> [UUID: Int] {
        let cal = AdminReportText.kuwait
        var ages: [UUID: Int] = [:]
        ages.reserveCapacity(pool.count)
        for p in pool where !p.birthHidden {
            if let a = AdminReportText.age(birth: p.birth, deceased: p.deceased, death: p.death,
                                           deathUnknown: p.deathUnknown, today: input.date, calendar: cal) {
                ages[p.id] = a
            }
        }
        return ages
    }

    /// ما ينقص الفرد (الميلاد · تاريخ الوفاة · الصورة · الأب)
    static func missing(_ p: AdminReportPerson, tree: AdminReportTree) -> [AdminReportFilter.Missing] {
        var out: [AdminReportFilter.Missing] = []
        if !p.birthHidden, case .missing = DeceasedMemorial.classify(p.birth) { out.append(.birth) }
        if p.deceased, !p.deathUnknown {
            if case .exact = DeceasedMemorial.classify(p.death) {} else { out.append(.death) }
        }
        if !p.hasPhoto { out.append(.photo) }
        if p.id != tree.rootId, p.fatherId.flatMap({ tree.byId[$0] }) == nil { out.append(.father) }
        return out
    }

    static func missingLabel(_ m: AdminReportFilter.Missing) -> String {
        switch m {
        case .any: return "كل الناقص"
        case .birth: return "تاريخ الميلاد"
        case .death: return AdminReportText.noFullDeathDate
        case .photo: return "الصورة"
        case .father: return "الأب في الشجرة"
        }
    }

    // MARK: الأعمدة الموحّدة (السجل، المسجّلون، المقيّدون، الناقصة بياناتهم)

    static func column(_ f: AdminReportField) -> AdminReportTable.Column {
        switch f {
        case .name: return .init(title: "الاسم الكامل", wraps: true, fill: true)
        case .branch: return .init(title: "الفرع", wraps: true)
        case .father: return .init(title: "الأب", wraps: true)
        case .birth: return .init(title: "الميلاد")
        case .age: return .init(title: "العمر", centered: true)
        case .status: return .init(title: "الحالة", wraps: true)
        case .death: return .init(title: "تاريخ الوفاة", wraps: true)
        case .phone: return .init(title: "رقم الهاتف", ltr: true)
        case .registration: return .init(title: "التسجيل", wraps: true)
        case .country: return .init(title: "الدولة")
        case .created: return .init(title: "قُيّد في")
        case .missing: return .init(title: "الناقص", wraps: true)
        case .anniversary: return .init(title: "الذكرى القادمة")
        case .ageAtDeath: return .init(title: "العمر عند الوفاة", centered: true)
        case .people, .ages, .branches, .registered: return .init(title: "")
        }
    }

    struct CellContext {
        let tree: AdminReportTree
        let input: AdminReportInput
        let ages: [UUID: Int]
        let fields: [AdminReportField]
        var missing: [UUID: [AdminReportFilter.Missing]] = [:]
    }

    static func cell(_ f: AdminReportField, _ p: AdminReportPerson, _ ctx: CellContext) -> (String, AdminReportTone?) {
        let dim: AdminReportTone? = p.deceased ? .muted : nil
        switch f {
        case .name: return (p.name, nil)
        case .branch: return (ctx.tree.branchLabel(of: p, names: ctx.input.branchNames), nil)
        case .father: return (p.fatherName ?? "—", nil)
        case .birth: return (p.birthHidden ? AdminReportText.hidden : (AdminReportText.date(p.birth) ?? "—"), nil)
        case .age: return (ctx.ages[p.id].map { "\($0)" } ?? "—", dim)
        case .status:
            guard p.deceased else { return ("حي", nil) }
            // بلا عمود «تاريخ الوفاة» يبقى التاريخ مع الحالة — الكامل فقط
            if !ctx.fields.contains(.death), case let .exact(y, m, d) = DeceasedMemorial.classify(p.death) {
                return ("متوفى · \(DeceasedMemorial.dayMonth(day: d, month: m, arabic: true)) \(y)", dim)
            }
            return ("متوفى", dim)
        case .death:
            guard p.deceased else { return ("", nil) }
            return (p.deathUnknown ? "غير معروف" : AdminReportText.deathDate(p.death), dim)
        case .phone: return (phoneText(p), p.phoneHidden ? .muted : nil)
        case .registration:
            guard !p.deceased else { return ("—", nil) }
            return (registrationText(p, ctx.input.registered), p.frozen ? .warning : nil)
        case .country: return (p.country ?? "—", nil)
        case .created:
            return (p.createdAt.map { AdminReportText.date($0, calendar: AdminReportText.kuwait) } ?? "—", nil)
        case .missing:
            let list = ctx.missing[p.id] ?? missing(p, tree: ctx.tree)
            return (list.map(missingLabel).joined(separator: " · "), .warning)
        case .anniversary, .ageAtDeath, .people, .ages, .branches, .registered: return ("", nil)
        }
    }

    /// جداول الأقسام: شريط كريمي لكل مجموعة، ثم الجدول بالأعمدة المختارة، وسطر المجموع تحته
    static func memberSections(_ pool: [AdminReportPerson], ctx: CellContext, plan: AdminReportGroupPlan,
                               summary: ([AdminReportPerson]) -> String) -> [AdminReportBlock] {
        let sections = ctx.tree.sections(pool, plan: plan, names: ctx.input.branchNames)
        // الفهرس: المستوى الأول فقط، وبحدّ معقول
        let tops = sections.filter { $0.depth == 0 }.count
        let tocAll = tops <= AdminReportPDF.tocMaxEntries
        var columns: [AdminReportTable.Column] = [.init(title: "م", centered: true)]
        columns += ctx.fields.map(column)
        var blocks: [AdminReportBlock] = []
        var seq = 0
        for s in sections {
            let sub = [s.path, AdminReportText.people(s.members.count)].compactMap { $0 }.joined(separator: " · ")
            blocks.append(.band(s.title, subtitle: sub, toc: tocAll && s.depth == 0))
            var table = AdminReportTable(columns: columns, rows: [])
            table.rows.reserveCapacity(s.members.count)
            for p in s.members {
                seq += 1
                var row = AdminReportRowBuilder()
                row.add("\(seq)")
                for f in ctx.fields {
                    let (text, tone) = cell(f, p, ctx)
                    row.add(text, tone)
                }
                table.rows.append(row.row)
            }
            table.summary = summary(s.members)
            blocks.append(.table(table))
        }
        return blocks
    }

    /// «المجموع: 7 أفراد — أحياء 6 · متوفون 1»
    static func lifeSummary(_ list: [AdminReportPerson]) -> String {
        let alive = list.filter { !$0.deceased }.count
        var s = "المجموع: \(AdminReportText.people(list.count))"
        if alive != list.count { s += " — أحياء \(AdminReportText.num(alive)) · متوفون \(AdminReportText.num(list.count - alive))" }
        return s
    }

    /// «المجموع: 7 أفراد — مسجّلون 5 · مقيّدون 1 · موقوف 1»
    static func registrationSummary(_ list: [AdminReportPerson], _ reg: Set<UUID>?) -> String {
        let living = list.filter { !$0.deceased }
        var s = "المجموع: \(AdminReportText.people(list.count))"
        guard reg != nil else { return s }
        var c: [AdminReportFilter.Registration: Int] = [:]
        for p in living { if let r = registration(p, reg) { c[r, default: 0] += 1 } }
        s += " — مسجّلون \(AdminReportText.num(c[.registered] ?? 0)) · مقيّدون \(AdminReportText.num(c[.treeOnly] ?? 0))"
        if let f = c[.frozen], f > 0 { s += " · موقوف \(AdminReportText.num(f))" }
        return s
    }

    static func lifeAndAge(_ pool: [AdminReportPerson], _ filter: AdminReportFilter, ages: [UUID: Int],
                           usesLife: Bool, usesAge: Bool, parts: inout [String]) -> [AdminReportPerson] {
        var pool = pool
        if usesLife {
            switch filter.life {
            case .all: break
            case .living:
                pool = pool.filter { !$0.deceased }
                parts.append("أحياء")
            case .deceased:
                pool = pool.filter(\.deceased)
                parts.append("متوفون")
            }
        }
        if usesAge, filter.ageLimited {
            pool = pool.filter { filter.ageMatches(ages[$0.id]) }
            parts.append(filter.ageLabel)
        }
        return pool
    }

    static func registrationFilter(_ pool: [AdminReportPerson], _ filter: AdminReportFilter, _ reg: Set<UUID>?,
                                   parts: inout [String]) -> [AdminReportPerson] {
        guard filter.registration != .all else { return pool }
        let label: String
        switch filter.registration {
        case .registered: label = "مسجّلون"
        case .treeOnly: label = "مقيّدون في الشجرة"
        case .frozen: label = "حسابات موقوفة"
        case .all: label = ""
        }
        parts.append(label)
        return pool.filter { !$0.deceased && registration($0, reg) == filter.registration }
    }

    // MARK: ١ سجل العائلة

    private static func register(_ tree: AdminReportTree, _ input: AdminReportInput, _ r: AdminReportRequest) -> AdminReportDoc {
        let filter = r.filter
        var pool = tree.pool
        var parts: [String] = []
        if let scope = filter.scope {
            pool = pool.filter { scope.ids.contains($0.id) }
            parts.append("من صفحة الأعضاء: \(scope.title)")
            if filter.branch != nil { pool = scoped(tree, input, filter, pool, parts: &parts) }
        } else {
            pool = scoped(tree, input, filter, pool, parts: &parts)
        }
        let ages = ages(pool, input)
        pool = lifeAndAge(pool, filter, ages: ages, usesLife: true, usesAge: true, parts: &parts)
        pool = registrationFilter(pool, filter, input.registered, parts: &parts)

        let top = tree.groups(pool, names: input.branchNames)
        let living = pool.filter { !$0.deceased }.count
        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(pool.count), label: "الأفراد"),
                    AdminReportTile(value: AdminReportText.num(living), label: "أحياء"),
                    AdminReportTile(value: AdminReportText.num(pool.count - living), label: "متوفون"),
                    AdminReportTile(value: AdminReportText.num(top.filter { $0.head != nil }.count), label: "الفروع")])
        ]
        if pool.isEmpty {
            blocks.append(.note("لا يوجد أفراد يطابقون هذا النطاق.", tone: .muted))
        } else if top.count > 1 {
            var summary = AdminReportTable(columns: [
                .init(title: "الفرع", weight: 0.30, wraps: true),
                .init(title: "رأس الفرع", weight: 0.34, wraps: true),
                .init(title: "الأفراد", weight: 0.12, centered: true),
                .init(title: "أحياء", weight: 0.12, centered: true),
                .init(title: "متوفون", weight: 0.12, centered: true)
            ], rows: [])
            for g in top {
                let alive = g.members.filter { !$0.deceased }.count
                summary.rows.append(.init(cells: [g.title, g.head?.name ?? "—", AdminReportText.num(g.members.count),
                                                  AdminReportText.num(alive), AdminReportText.num(g.members.count - alive)]))
            }
            summary.footer = .init(cells: ["المجموع", "", AdminReportText.num(pool.count), AdminReportText.num(living),
                                           AdminReportText.num(pool.count - living)])
            blocks.append(.heading("ملخّص الفروع", subtitle: nil, panel: true))
            blocks.append(.table(summary))
        }
        let ctx = CellContext(tree: tree, input: input, ages: ages, fields: r.fields)
        let registrationShown = r.fields.contains(.registration)
        blocks += memberSections(pool, ctx: ctx, plan: r.plan) {
            registrationShown ? registrationSummary($0, input.registered) : lifeSummary($0)
        }
        let intro = "يضمّ هذا السجل أفراد شجرة العائلة \(r.plan.grouping.pdfLabel)، كل مجموعة تحت شريطها ومجموعها في ذيلها،"
            + " ويبدأ بملخّص أعداد الفروع."
        var doc = AdminReportDoc(kind: .register, scope: parts.joined(separator: " · "), count: pool.count,
                                 intro: intro, blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.grouping = r.plan.grouping.pdfLabel
        return doc
    }

    // MARK: ٢ الملخّص الإحصائي

    private static func stats(_ tree: AdminReportTree, _ input: AdminReportInput,
                              _ fields: Set<AdminReportField>) -> AdminReportDoc {
        let men = tree.pool
        let menAlive = men.filter { !$0.deceased }.count
        let women = input.women
        let womenAlive = women?.filter { !$0.deceased }.count ?? 0
        let womenTotal = women?.count ?? 0
        let total = men.count + womenTotal
        let totalAlive = menAlive + womenAlive

        var blocks: [AdminReportBlock] = []
        let registeredLiving = input.registered.map { set in men.filter { !$0.deceased && set.contains($0.id) }.count }
        blocks.append(.tiles([
            AdminReportTile(value: AdminReportText.num(total), label: women == nil ? "أفراد الشجرة" : "إجمالي الأفراد"),
            AdminReportTile(value: AdminReportText.num(totalAlive), label: "الأحياء"),
            AdminReportTile(value: AdminReportText.num(tree.heads.count), label: "الفروع"),
            AdminReportTile(value: registeredLiving.map(AdminReportText.num) ?? "—", label: "الأعضاء المسجّلون")
        ]))
        var contents: [String] = []

        if fields.contains(.people) {
            contents.append("أعداد الأفراد (الإجمالي والرجال والنساء، أحياء ومتوفون)")
            blocks.append(.heading("إحصاء الأفراد", subtitle: "أحياء ومتوفون — الرجال من الشجرة، والنساء من شجرة النساء",
                                   panel: true))
            blocks.append(.rings([
                AdminReportRing(title: "الإجمالي", living: totalAlive, deceased: total - totalAlive, tone: .total),
                AdminReportRing(title: "الرجال", living: menAlive, deceased: men.count - menAlive, tone: .men),
                AdminReportRing(title: "النساء", living: womenAlive, deceased: womenTotal - womenAlive, tone: .women,
                                available: women != nil)
            ]))
            if women == nil {
                blocks.append(.note("أرقام شجرة النساء لم تُحمَّل وقت إنشاء التقرير — الإجمالي للرجال فقط.", tone: .warning))
            }
        }

        if fields.contains(.ages) {
            contents.append("الفئات العمرية للأحياء")
            let cal = AdminReportText.kuwait
            var perBand: [AdminReportFilter.Age: Int] = [:]
            var noAge = 0
            var livingCount = 0
            let livingBirths = men.filter { !$0.deceased }.map(\.birth) + (women ?? []).filter { !$0.deceased }.map(\.birth)
            for b in livingBirths {
                livingCount += 1
                let band = AdminReportFilter.Age.band(AdminReportText.age(birth: b, deceased: false, death: nil, deathUnknown: false,
                                                                          today: input.date, calendar: cal))
                if band == .unknown { noAge += 1 } else { perBand[band, default: 0] += 1 }
            }
            var ageBars = AdminReportFilter.Age.bands.map { band in
                let n = perBand[band] ?? 0
                return AdminReportBar(label: band.label, first: n,
                                      caption: "\(AdminReportText.num(n)) · \(AdminReportText.percent(n, of: livingCount))")
            }
            if noAge > 0 {
                ageBars.append(AdminReportBar(label: "بلا تاريخ ميلاد", first: 0, second: noAge,
                                              caption: "\(AdminReportText.num(noAge)) · \(AdminReportText.percent(noAge, of: livingCount))"))
            }
            blocks.append(.heading("الفئات العمرية", subtitle: "الأحياء — العمر اليوم من تاريخ الميلاد (السنة وحدها تُحسب من أول السنة)",
                                   panel: true))
            blocks.append(.bars(ageBars, firstLabel: "لهم تاريخ ميلاد", secondLabel: noAge > 0 ? "بلا تاريخ ميلاد" : nil,
                                firstTone: .total))
        }

        if fields.contains(.branches) {
            contents.append("شجرة الفروع وأفراد كل فرع")
            if let mini = miniTree(tree, input) {
                blocks.append(.heading("شجرة الفروع", subtitle: "المؤسس وفروعه الكبرى — وتحت كل فرع عدد أفراده (هو ونسله)",
                                       panel: true))
                blocks.append(.miniTree(mini))
            }
            let groups = tree.groups(men, names: input.branchNames).filter { $0.head != nil }
            if !groups.isEmpty {
                blocks.append(.heading("الأفراد حسب الفرع", subtitle: "رجال الشجرة في كل فرع — أحياء ومتوفون", panel: true))
                blocks.append(.bars(groups.map { g in
                    let alive = g.members.filter { !$0.deceased }.count
                    return AdminReportBar(label: g.title, first: alive, second: g.members.count - alive,
                                          caption: "\(AdminReportText.num(g.members.count)) (\(AdminReportText.num(alive)) حياً)")
                }, firstLabel: "أحياء", secondLabel: "متوفون", firstTone: .men))
            }
        }

        if fields.contains(.registered) {
            contents.append("نسبة الأعضاء المسجّلين في التطبيق إلى المقيّدين في الشجرة")
            blocks.append(.heading("التسجيل في التطبيق", subtitle: "الأحياء من رجال الشجرة: من له حساب دخول ومن اسمه في الشجرة فقط",
                                   panel: true))
            if let registeredLiving {
                blocks.append(.split(AdminReportSplit(firstLabel: AdminReportText.registered, first: registeredLiving,
                                                      secondLabel: AdminReportText.treeOnly, second: menAlive - registeredLiving)))
            } else {
                blocks.append(.note("تعذّر تحميل حالة التسجيل وقت إنشاء التقرير.", tone: .warning))
            }
        }

        let list = contents.enumerated().map { $0.offset == 0 ? $0.element : "و" + $0.element }.joined(separator: "، ")
        let intro = list.isEmpty
            ? "ملخّص بالأرقام: إجمالي الأفراد والأحياء وعدد الفروع والأعضاء المسجّلين."
            : "ملخّص بالأرقام والرسوم: \(list)."
        return AdminReportDoc(kind: .stats, scope: "", count: total, intro: intro, blocks: blocks,
                              generatedBy: input.generatedBy, date: input.date)
    }

    /// أكثر عدد عقد في السطر (A4) — الزائد يُجمع في «وغيرها»
    static let miniTreeMaxNodes = 8

    /// المؤسس ← أبناؤه (رؤوس الفروع)، أو أحفاده (فروع الفروع) إن كان أبناؤه أقل من ثلاثة.
    static func miniTree(_ tree: AdminReportTree, _ input: AdminReportInput) -> AdminReportMiniTree? {
        guard let rootId = tree.rootId, let root = tree.byId[rootId], !tree.heads.isEmpty else { return nil }
        var nodes: [(order: Int, node: AdminReportMiniTree.Node)] = []
        if tree.heads.count >= 3 {
            for (i, h) in tree.heads.enumerated() {
                nodes.append((i, .init(title: tree.title(ofHead: h, names: input.branchNames),
                                       caption: input.branchNames[h.id] != nil ? h.firstName : nil,
                                       count: tree.count(under: h.id))))
            }
        } else {
            var i = 0
            for h in tree.heads {
                let branch = tree.title(ofHead: h, names: input.branchNames)
                for c in tree.kids[h.id] ?? [] {
                    guard let p = tree.byId[c] else { continue }
                    nodes.append((i, .init(title: "فرع \(p.firstName.isEmpty ? p.name : p.firstName)",
                                           caption: branch, count: tree.count(under: c))))
                    i += 1
                }
            }
        }
        guard !nodes.isEmpty else { return nil }
        if nodes.count > miniTreeMaxNodes {
            let keep = Set(nodes.sorted { $0.node.count > $1.node.count }.prefix(miniTreeMaxNodes - 1).map(\.order))
            let rest = nodes.filter { !keep.contains($0.order) }
            nodes = nodes.filter { keep.contains($0.order) }
            nodes.append((Int.max, .init(title: "وغيرها", caption: AdminReportText.branches(rest.count),
                                         count: rest.reduce(0) { $0 + $1.node.count }, isRest: true)))
        }
        return AdminReportMiniTree(founder: root.name,
                                   founderCaption: "رأس الشجرة · \(AdminReportText.people(tree.order.count))",
                                   nodes: nodes.map(\.node))
    }

    // MARK: ٣ سجل الراحلين

    static func memorial(_ tree: AdminReportTree, _ input: AdminReportInput,
                         _ filter: AdminReportFilter, _ fields: Set<AdminReportField>,
                         within: Set<UUID>? = nil) -> AdminReportDoc {
        let cal = AdminReportText.kuwait
        var parts: [String] = []
        var dead = tree.pool.filter { $0.deceased && $0.countable }
        if let within {
            dead = dead.filter { within.contains($0.id) }
        } else {
            dead = scoped(tree, input, filter, dead, parts: &parts)
        }
        let names = input.branchNames

        struct Full { let p: AdminReportPerson; let kind: DeceasedMemorial.DateKind; let next: DeceasedMemorial.Anniversary? }
        var full: [Full] = []
        var partial: [(AdminReportPerson, DeceasedMemorial.DateKind)] = []
        for p in dead {
            let kind = DeceasedMemorial.classify(p.death)
            if case .exact = kind, !p.deathUnknown {
                full.append(Full(p: p, kind: kind, next: DeceasedMemorial.anniversary(kind, today: input.date, calendar: cal)))
            } else {
                partial.append((p, kind))
            }
        }
        let showsNext = fields.contains(.anniversary)
        if showsNext {
            full.sort {
                let a = $0.next?.daysUntil ?? Int.max, b = $1.next?.daysUntil ?? Int.max
                return a != b ? a < b : $0.p.name < $1.p.name
            }
        } else {
            func key(_ k: DeceasedMemorial.DateKind) -> Int {
                if case let .exact(y, m, d) = k { return y * 10_000 + m * 100 + d }
                return 0
            }
            full.sort {
                let a = key($0.kind), b = key($1.kind)
                return a != b ? a > b : $0.p.name < $1.p.name
            }
        }
        partial.sort {
            if $0.0.deathUnknown != $1.0.deathUnknown { return !$0.0.deathUnknown }
            let a = DeceasedMemorial.missingRank($0.1), b = DeceasedMemorial.missingRank($1.1)
            return (a.group, a.year, $0.0.name) < (b.group, b.year, $1.0.name)
        }
        let soon = full.filter { ($0.next?.daysUntil ?? Int.max) <= DeceasedMemorial.upcomingDays }.count

        func ageAtDeath(_ p: AdminReportPerson) -> String {
            guard !p.birthHidden,
                  let a = AdminReportText.age(birth: p.birth, deceased: true, death: p.death, deathUnknown: p.deathUnknown,
                                              today: input.date, calendar: cal) else { return "—" }
            return "\(a)"
        }

        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(dead.count), label: "المتوفون"),
                    AdminReportTile(value: AdminReportText.num(full.count), label: "تاريخ مكتمل"),
                    AdminReportTile(value: AdminReportText.num(partial.count), label: "تاريخ غير مكتمل"),
                    AdminReportTile(value: AdminReportText.num(soon), label: "ذكرى خلال 30 يوماً")])
        ]
        var seq = 0
        if filter.memorial == .all {
            blocks.append(.band(showsNext ? "الذكرى القادمة" : "تاريخ الوفاة مكتمل",
                                subtitle: showsNext ? "الأقرب ذكرى أولاً — \(AdminReportText.people(full.count))"
                                                    : "الأحدث وفاةً أولاً — \(AdminReportText.people(full.count))",
                                toc: within == nil))
            var columns: [AdminReportTable.Column] = [
                .init(title: "م", centered: true),
                .init(title: "الاسم الكامل", wraps: true, fill: true)
            ]
            if fields.contains(.death) { columns.append(.init(title: "تاريخ الوفاة")) }
            if showsNext {
                columns += [.init(title: "الذكرى القادمة"), .init(title: "رقمها", centered: true), .init(title: "الموعد")]
            }
            if fields.contains(.ageAtDeath) { columns.append(.init(title: "العمر عند الوفاة", centered: true)) }
            if fields.contains(.branch) { columns.append(.init(title: "الفرع", wraps: true)) }
            var table = AdminReportTable(columns: columns, rows: [])
            for f in full {
                seq += 1
                var row = AdminReportRowBuilder()
                row.add("\(seq)")
                row.add(f.p.name)
                if fields.contains(.death) { row.add(AdminReportText.date(f.p.death) ?? "—") }
                if showsNext {
                    row.add(f.next.map { AdminReportText.date($0.date, calendar: cal) } ?? "—")
                    row.add(f.next.map { "\($0.years)" } ?? "—")
                    row.add(f.next.map { AdminReportText.inDays($0.daysUntil) } ?? "—",
                            (f.next?.daysUntil ?? Int.max) <= 7 ? .warning : nil)
                }
                if fields.contains(.ageAtDeath) { row.add(ageAtDeath(f.p)) }
                if fields.contains(.branch) { row.add(tree.branchLabel(of: f.p, names: names)) }
                table.rows.append(row.row)
            }
            table.summary = "المجموع: \(AdminReportText.people(full.count))"
            if full.isEmpty {
                blocks.append(.note("لا توجد تواريخ وفاة مكتملة.", tone: .muted))
            } else {
                blocks.append(.table(table))
            }
        }

        blocks.append(.band(AdminReportText.noFullDeathDate,
                            subtitle: "السنة فقط، أو مكتوب بالهجري، أو بلا تاريخ — \(AdminReportText.people(partial.count))",
                            toc: within == nil))
        var columns: [AdminReportTable.Column] = [
            .init(title: "م", centered: true),
            .init(title: "الاسم الكامل", wraps: true, fill: true)
        ]
        if fields.contains(.death) { columns.append(.init(title: "المسجَّل حالياً")) }
        if fields.contains(.ageAtDeath) { columns.append(.init(title: "العمر عند الوفاة", centered: true)) }
        if fields.contains(.branch) { columns.append(.init(title: "الفرع", wraps: true)) }
        columns.append(.init(title: "الملاحظة", wraps: true))
        var table = AdminReportTable(columns: columns, rows: [])
        for (p, kind) in partial {
            seq += 1
            let recorded: String
            let note: String
            var tone: AdminReportTone = .muted
            if p.deathUnknown {
                recorded = "—"
                note = "غير معروف (مؤكَّد من الإدارة)"
            } else {
                switch kind {
                case .yearOnly(let y):
                    recorded = "\(y)"
                    note = "السنة فقط — ينقصه اليوم والشهر"
                    tone = .warning
                case .hijriLike(let y):
                    recorded = "\(y)"
                    note = "مكتوب بالهجري — يحتاج تحويلاً للميلادي"
                    tone = .warning
                case .missing, .exact:
                    recorded = "—"
                    note = "بلا تاريخ"
                }
            }
            var row = AdminReportRowBuilder()
            row.add("\(seq)")
            row.add(p.name)
            if fields.contains(.death) { row.add(recorded) }
            if fields.contains(.ageAtDeath) { row.add(ageAtDeath(p)) }
            if fields.contains(.branch) { row.add(tree.branchLabel(of: p, names: names)) }
            row.add(note, tone)
            table.rows.append(row.row)
        }
        table.summary = "المجموع: \(AdminReportText.people(partial.count))"
        if partial.isEmpty {
            blocks.append(.note("كل تواريخ الوفاة مكتملة.", tone: .muted))
        } else {
            blocks.append(.table(table))
        }

        let count = filter.memorial == .all ? dead.count : partial.count
        parts.append(filter.memorial == .all ? "كل المتوفين" : AdminReportText.noFullDeathDate)
        let intro = "قائمة المتوفين من أفراد الشجرة لمن تاريخ وفاته مكتمل بالميلادي"
            + (showsNext ? " وموعد ذكراه القادمة (الأقرب أولاً)" : "")
            + "، ثم قسم «\(AdminReportText.noFullDeathDate)» لمن سُجّلت سنة وفاته فقط أو كُتبت بالهجري أو لم تُسجَّل."
        return AdminReportDoc(kind: .memorial, scope: parts.joined(separator: " · "), count: count, intro: intro,
                              blocks: blocks, generatedBy: input.generatedBy, date: input.date)
    }

    // MARK: ٤ دليل الهواتف

    private static func phones(_ tree: AdminReportTree, _ input: AdminReportInput, _ r: AdminReportRequest) -> AdminReportDoc {
        let filter = r.filter
        var parts: [String] = []
        var living = scoped(tree, input, filter, tree.pool.filter { !$0.deceased }, parts: &parts)
        let ages = ages(living, input)
        living = lifeAndAge(living, filter, ages: ages, usesLife: false, usesAge: true, parts: &parts)
        let reg = input.registered
        // له رقم = في السجل (أو أخفاه صاحبه — يظهر «مخفي» ولا يُطبع)
        let withPhone = living.filter { $0.phone != nil || $0.phoneHidden }
        let noPhone = living.filter { $0.phone == nil && !$0.phoneHidden }
        let hiddenCount = withPhone.filter(\.phoneHidden).count

        var listed = withPhone
        if filter.phones == .registered {
            listed = reg.map { set in withPhone.filter { set.contains($0.id) } } ?? []
        }

        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(living.count), label: "الأحياء"),
                    AdminReportTile(value: AdminReportText.num(withPhone.count), label: "لهم رقم"),
                    AdminReportTile(value: AdminReportText.num(hiddenCount), label: "أرقام مخفية"),
                    AdminReportTile(value: AdminReportText.num(noPhone.count), label: AdminReportText.noPhone)])
        ]
        if hiddenCount > 0 {
            blocks.append(.note("الأرقام التي أخفاها أصحابها تظهر «مخفي» ولا تُطبع في هذا الملف.", tone: .muted))
        }

        var count = 0
        let ctx = CellContext(tree: tree, input: input, ages: ages, fields: r.fields)
        if filter.phones != .noPhone {
            if filter.phones == .registered && reg == nil {
                blocks.append(.note("تعذّر تحميل حالة التسجيل وقت إنشاء التقرير.", tone: .warning))
            }
            // «الحالة» هنا = التسجيل في التطبيق — كل القائمة أحياء
            let fields = r.fields.map { $0 == .status ? AdminReportField.registration : $0 }
            let phoneCtx = CellContext(tree: tree, input: input, ages: ages, fields: fields)
            blocks += memberSections(listed, ctx: phoneCtx, plan: r.plan) { "المجموع: \(AdminReportText.people($0.count))" }
            count += listed.count
        }
        if filter.phones != .registered {
            blocks.append(.band(AdminReportText.noPhone, subtitle: "أحياء لا رقم لهم في السجل — \(AdminReportText.people(noPhone.count))",
                                toc: false))
            if noPhone.isEmpty {
                blocks.append(.note("لكل الأحياء رقم هاتف.", tone: .muted))
            } else {
                var columns: [AdminReportTable.Column] = [.init(title: "م", centered: true), column(.name), column(.branch)]
                let showsStatus = r.fields.contains(.status)
                if showsStatus { columns.append(column(.registration)) }
                var table = AdminReportTable(columns: columns, rows: [])
                var seq = 0
                for g in tree.groups(noPhone, names: input.branchNames) {
                    for p in g.members {
                        seq += 1
                        var row = AdminReportRowBuilder()
                        row.add("\(seq)")
                        row.add(p.name)
                        row.add(g.title)
                        if showsStatus {
                            let (t, tone) = cell(.registration, p, ctx)
                            row.add(t, tone)
                        }
                        table.rows.append(row.row)
                    }
                }
                table.summary = "المجموع: \(AdminReportText.people(noPhone.count))"
                blocks.append(.table(table))
            }
            count += noPhone.count
        }

        switch filter.phones {
        case .all: parts.append("كل الأحياء")
        case .registered: parts.append("الأعضاء المسجّلون")
        case .noPhone: parts.append(AdminReportText.noPhone)
        }
        let intro = "أرقام هواتف الأحياء من أفراد الشجرة \(r.plan.grouping.pdfLabel)"
            + "، ثم قسم «بلا رقم هاتف». من أخفى رقمه يظهر «مخفي» احتراماً لخصوصيته."
        var doc = AdminReportDoc(kind: .phones, scope: parts.joined(separator: " · "), count: count, intro: intro,
                                 blocks: blocks, generatedBy: input.generatedBy, date: input.date)
        doc.grouping = r.plan.grouping.pdfLabel
        return doc
    }
}
