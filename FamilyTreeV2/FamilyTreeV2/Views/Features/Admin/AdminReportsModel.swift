import Foundation

// MARK: - تقارير العائلة الرسمية (PDF) — البيانات وبناء التقرير (طلب المالك ٢٠٢٦-١٠-٢٠ «رسمي بهوية العائلة»)
//
// أربعة تقارير: «سجل العائلة بالفروع» · «ملخّص إحصائي للعائلة» · «المتوفون وذكراهم» · «دليل الهواتف».
// الصفحة (`AdminReportsView`) تأخذ لقطة من الأعضاء على الخيط الرئيسي (`AdminReportInput.make` — أسماء العرض،
// تنسيق الهاتف، أسماء الفروع)، ثم يُبنى التقرير (`AdminReportBuilder`) ويُرسم (`AdminReportPDF`) خارج الخيط الرئيسي —
// لا تجميد مع ~٢٧٠٠ عضو.
// التعريفات نفسها في اللوحة: الرجال = الشجرة بلا طلبات الانضمام، النساء = إناث شجرة النساء، «عضو مسجّل» = له حساب
// دخول (`AdminAccountsStore`)، الفروع = أبناء رأس الشجرة المباشرون (`BranchPickerSheet.familyRoot`)، والذكرى من
// `DeceasedMemorial` (الميلادي فقط).
// الخصوصية: الهاتف كما وصل من `members_masked`، ومن أخفى رقمه يظهر «مخفي» دائماً — حتى للإدارة (الملف يُشارك خارج
// التطبيق). تاريخ الميلاد المخفي يظهر «مخفي» كذلك، ويدخل الإحصاءات المجمّعة فقط.
// نصوص الملف عربية دائماً (كالتصدير السابق) بالمسميات الرسمية (عضو مسجّل، مقيّد في الشجرة، حساب موقوف، بلا رقم هاتف،
// تاريخ الوفاة غير مكتمل).

// MARK: - نوع التقرير والتصفية

nonisolated enum AdminReportKind: String, CaseIterable, Identifiable, Sendable {
    case register, stats, memorial, phones

    var id: String { rawValue }

    /// عنوان الملف (عربي دائماً)
    var pdfTitle: String {
        switch self {
        case .register: return "سجل العائلة بالفروع"
        case .stats: return "ملخّص إحصائي للعائلة"
        case .memorial: return "المتوفون وذكراهم"
        case .phones: return "دليل الهواتف"
        }
    }

    /// بداية اسم الملف المشارَك
    var fileStem: String {
        switch self {
        case .register: return "سجل-العائلة"
        case .stats: return "ملخص-احصائي"
        case .memorial: return "المتوفون-وذكراهم"
        case .phones: return "دليل-الهواتف"
        }
    }

    /// البيانات المتاحة للنوع بترتيب شرائح «البيانات:» (= ترتيب الأعمدة من اليمين)
    var fields: [AdminReportField] {
        switch self {
        case .register: return [.name, .branch, .birth, .age, .status, .death, .phone, .registration]
        case .phones: return [.name, .branch, .phone, .status]
        case .memorial: return [.name, .death, .anniversary, .ageAtDeath, .branch]
        case .stats: return [.people, .ages, .branches, .registered]
        }
    }

    /// لا تُزال: الاسم في كل جدول، والرقم في دليل الهواتف
    var lockedFields: Set<AdminReportField> {
        switch self {
        case .register, .memorial: return [.name]
        case .phones: return [.name, .phone]
        case .stats: return []
        }
    }

    /// الافتراضي = ما كان يُطبع قبل الاختيار
    var defaultFields: Set<AdminReportField> {
        switch self {
        case .register: return [.name, .birth, .age, .status]
        case .phones: return [.name, .phone, .status]
        case .memorial: return [.name, .death, .anniversary]
        case .stats: return [.people, .ages, .branches, .registered]
        }
    }

    /// المختار مصحّحاً: ما لا يخص النوع يُترك، والمقفل دائماً — nil = الافتراضي
    func resolvedFields(_ chosen: Set<AdminReportField>?) -> Set<AdminReportField> {
        (chosen ?? defaultFields).intersection(fields).union(lockedFields)
    }
}

/// ما يُطبع في التقرير — شرائح «البيانات:» (طلب المالك ٢٠٢٦-١٠-٢٠ «ابى انا اضيف البيانات او اشيل البيانات بشكل بسيط»):
/// أعمدة الجداول (السجل، الهواتف، المتوفون) أو أقسام الملخّص. الاختيار يُحفظ لكل نوع ولكل مستخدم (`AdminReportsView`).
nonisolated enum AdminReportField: String, CaseIterable, Identifiable, Sendable {
    // أعمدة
    case name, branch, birth, age, status, death, phone, registration, anniversary, ageAtDeath
    // أقسام الملخّص
    case people, ages, branches, registered

    var id: String { rawValue }
}

nonisolated struct AdminReportFilter: Equatable, Sendable {
    enum Life: String, CaseIterable, Sendable { case all, living, deceased }
    enum Phones: String, CaseIterable, Sendable { case all, registered, noPhone }
    enum Memorial: String, CaseIterable, Sendable { case all, incomplete }
    /// فئة العمر (سجل العائلة) — نفس فئات «الفئات العمرية» في الملخّص. العمر = اليوم للحي، وعند الوفاة للمتوفى؛
    /// تاريخ الميلاد المخفي أو الناقص = «غير معروف» (لا يُستنتج عمر من أخفى ميلاده)
    enum Age: String, CaseIterable, Sendable {
        case all, under18, from18to30, from31to50, from51to70, over70, unknown

        /// الفئات المحسوبة (بلا «الكل» و«غير معروف»)
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

        /// اسم الفئة في الملف (عربي دائماً): «أقل من 18» · «18–30» … · «غير معروف»
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

        /// في سطر النطاق: «18–30 سنة» · «العمر غير معروف»
        var scopeLabel: String {
            switch self {
            case .all: return ""
            case .unknown: return "العمر غير معروف"
            default: return "\(label) سنة"
            }
        }
    }

    /// ما جاء من صفحة الأعضاء («⋯ ← تصدير» بالشريحة والبحث) — لسجل العائلة فقط
    struct Scope: Equatable, Sendable {
        let ids: Set<UUID>
        let title: String
    }

    /// فرع (أي عضو: هو ونسله) — سجل العائلة
    var branch: UUID? = nil
    var life: Life = .all
    var phones: Phones = .all
    var memorial: Memorial = .all
    /// سجل العائلة
    var age: Age = .all
    var scope: Scope? = nil
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
    /// أسماء الفروع المخصّصة (رأس الفرع ← الاسم)
    let branchNames: [UUID: String]
    let generatedBy: String
    let date: Date

    @MainActor
    static func make(members: [FamilyMember], women: [FamilyMember]?, registered: Set<UUID>?,
                     branchName: (UUID) -> String?, generatedBy: String, date: Date = Date()) -> AdminReportInput {
        var people: [AdminReportPerson] = []
        people.reserveCapacity(members.count)
        // سجلّ بلا اسم (رقم دخول بلا اسم) ليس فرداً في العائلة — `displayFullName` يلحق به اسم العائلة فلا يُكتشف بعده
        for m in members where m.role != .pending && m.hasName {
            let name = m.displayFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let raw = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            people.append(AdminReportPerson(
                id: m.id, fatherId: m.fatherId, name: name,
                firstName: m.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: m.sortOrder, birth: m.birthDate, birthHidden: m.isBirthDateHidden == true,
                deceased: m.isDeceased == true, death: m.deathDate, deathUnknown: m.deathDateUnknown == true,
                frozen: m.status == .frozen, countable: m.isCountable,
                phone: raw.isEmpty ? nil : KuwaitPhone.display(raw), phoneHidden: m.isPhoneHidden == true))
        }
        let root = BranchPickerSheet.familyRoot(in: members)
        var names: [UUID: String] = [:]
        if let root {
            for m in members where m.fatherId == root.id {
                if let n = branchName(m.id) { names[m.id] = n }
            }
        }
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
    }

    struct Row: Sendable {
        let cells: [String]
        /// لون خلية بعينها (المتوفى خافت، «السنة فقط» كهرماني)
        var tones: [Int: AdminReportTone] = [:]
    }

    let columns: [Column]
    var rows: [Row]
    /// صفّ المجموع (عريض)
    var footer: Row? = nil
}

/// «شجرة الفروع» المصغّرة: المؤسس ← فروعه الكبرى وعدد أفراد كل فرع
nonisolated struct AdminReportMiniTree: Sendable {
    struct Node: Sendable {
        let title: String
        /// سطر صغير تحت العنوان (رأس الفرع، أو فرعه الأب إن كانت العقد فروع الفروع)
        let caption: String?
        let count: Int
        /// «وغيرها» — بقية الفروع مجموعة
        var isRest: Bool = false
    }

    let founder: String
    let founderCaption: String
    let nodes: [Node]
}

nonisolated enum AdminReportBlock: Sendable {
    case tiles([AdminReportTile])
    /// عنوان قسم (فرع) بخط ذهبي — أو عنوان لوحة إحصاء (`panel`)
    case heading(String, subtitle: String?, panel: Bool)
    case table(AdminReportTable)
    case note(String, tone: AdminReportTone)
    case rings([AdminReportRing])
    /// أشرطة أفقية بجزأين (الفروع، الأعمار) + مفتاح الألوان
    case bars([AdminReportBar], firstLabel: String, secondLabel: String?, firstTone: AdminReportTone)
    case split(AdminReportSplit)
    case miniTree(AdminReportMiniTree)
}

nonisolated struct AdminReportDoc: Sendable {
    let kind: AdminReportKind
    /// سطر النطاق («كل الفروع · أحياء») — فارغ = بلا تصفية
    let scope: String
    /// عدد الأفراد في التقرير (سطر المعاينة وصفحة الغلاف)
    let count: Int
    /// فقرة الغلاف: ما يحويه التقرير
    let intro: String
    let blocks: [AdminReportBlock]
    let generatedBy: String
    let date: Date

    var title: String { kind.pdfTitle }

    /// «سجل العائلة · كل الفروع · أحياء — 2,344 فرداً»
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

    static func date(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(DeceasedMemorial.dayMonth(day: c.day ?? 1, month: c.month ?? 1, arabic: true)) \(c.year ?? 0)"
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
    /// (لا تاريخ، هجري، وفاة بلا تاريخ، أو خارج 0…129)
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
    func count(under id: UUID) -> Int {
        var n = 0
        var stack = [id]
        var seen: Set<UUID> = []
        while let cur = stack.popLast() {
            guard seen.insert(cur).inserted else { continue }
            if byId[cur] != nil { n += 1 }
            stack.append(contentsOf: kids[cur] ?? [])
        }
        return n
    }

    func title(ofHead head: AdminReportPerson, names: [UUID: String]) -> String {
        names[head.id] ?? "فرع \(head.firstName.isEmpty ? head.name : head.firstName)"
    }

    /// فرع العضو كما يُطبع في عمود «الفرع» — بنفس عناوين مجموعات `groups`
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

    /// مجموعات بالفروع: رأس الشجرة ← الفروع بترتيبها ← «خارج الفروع» (بالاسم)
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

nonisolated enum AdminReportBuilder {

    /// `fields`: ما اختير في «البيانات:» — nil = الافتراضي
    static func build(_ kind: AdminReportKind, input: AdminReportInput, filter: AdminReportFilter,
                      fields: Set<AdminReportField>? = nil) -> AdminReportDoc {
        let tree = AdminReportTree(input.people, rootId: input.rootId)
        let chosen = kind.resolvedFields(fields)
        switch kind {
        case .register: return register(tree, input, filter, chosen)
        case .stats: return stats(tree, input, chosen)
        case .memorial: return memorial(tree, input, filter, chosen)
        case .phones: return phones(tree, input, filter, chosen)
        }
    }

    /// الهاتف كما يُطبع: من أخفاه «مخفي» دائماً، ولا رقم «—»
    private static func phoneText(_ p: AdminReportPerson) -> String {
        p.phoneHidden ? AdminReportText.hidden : (p.phone ?? "—")
    }

    /// حالة التسجيل في التطبيق: حساب موقوف · عضو مسجّل · مقيّد في الشجرة («—» إن لم تصل القوائم)
    private static func registrationText(_ p: AdminReportPerson, _ reg: Set<UUID>?) -> String {
        if p.frozen { return AdminReportText.frozen }
        guard let reg else { return "—" }
        return reg.contains(p.id) ? AdminReportText.registered : AdminReportText.treeOnly
    }

    /// عنوان الفرع المختار (شريحة الفرع وسطر النطاق)
    static func branchTitle(_ id: UUID, input: AdminReportInput) -> String {
        if let n = input.branchNames[id] { return n }
        let p = input.people.first { $0.id == id }
        return "فرع \(p.map { $0.firstName.isEmpty ? $0.name : $0.firstName } ?? "")"
    }

    // MARK: ١ سجل العائلة بالفروع

    private static func register(_ tree: AdminReportTree, _ input: AdminReportInput,
                                 _ filter: AdminReportFilter, _ fields: Set<AdminReportField>) -> AdminReportDoc {
        var pool = tree.pool
        var scopeParts: [String] = []
        if let scope = filter.scope {
            pool = pool.filter { scope.ids.contains($0.id) }
            scopeParts.append("من صفحة الأعضاء: \(scope.title)")
        }
        if let b = filter.branch {
            let ids = tree.subtree(b)
            pool = pool.filter { ids.contains($0.id) }
            scopeParts.append(branchTitle(b, input: input))
        } else if filter.scope == nil {
            scopeParts.append("كل الفروع")
        }
        switch filter.life {
        case .all: break
        case .living:
            pool = pool.filter { !$0.deceased }
            scopeParts.append("أحياء")
        case .deceased:
            pool = pool.filter(\.deceased)
            scopeParts.append("متوفون")
        }
        // العمر (مرة واحدة لكل فرد) — المخفي ميلاده بلا عمر
        let cal = AdminReportText.kuwait
        var ages: [UUID: Int] = [:]
        ages.reserveCapacity(pool.count)
        for p in pool where !p.birthHidden {
            if let a = AdminReportText.age(birth: p.birth, deceased: p.deceased, death: p.death,
                                           deathUnknown: p.deathUnknown, today: input.date, calendar: cal) {
                ages[p.id] = a
            }
        }
        if filter.age != .all {
            pool = pool.filter { AdminReportFilter.Age.band(ages[$0.id]) == filter.age }
            scopeParts.append(filter.age.scopeLabel)
        }

        let groups = tree.groups(pool, names: input.branchNames)
        let living = pool.filter { !$0.deceased }.count
        let branchCount = groups.filter { $0.head != nil }.count

        var blocks: [AdminReportBlock] = [
            .tiles([AdminReportTile(value: AdminReportText.num(pool.count), label: "الأفراد"),
                    AdminReportTile(value: AdminReportText.num(living), label: "أحياء"),
                    AdminReportTile(value: AdminReportText.num(pool.count - living), label: "متوفون"),
                    AdminReportTile(value: AdminReportText.num(branchCount), label: "الفروع")])
        ]

        // ملخّص الفروع
        var summary = AdminReportTable(columns: [
            .init(title: "الفرع", weight: 0.30, wraps: true),
            .init(title: "رأس الفرع", weight: 0.34, wraps: true),
            .init(title: "الأفراد", weight: 0.12, centered: true),
            .init(title: "أحياء", weight: 0.12, centered: true),
            .init(title: "متوفون", weight: 0.12, centered: true)
        ], rows: [])
        for g in groups {
            let alive = g.members.filter { !$0.deceased }.count
            summary.rows.append(.init(cells: [g.title, g.head?.name ?? "—", AdminReportText.num(g.members.count),
                                              AdminReportText.num(alive), AdminReportText.num(g.members.count - alive)]))
        }
        summary.footer = .init(cells: ["المجموع", "", AdminReportText.num(pool.count), AdminReportText.num(living),
                                       AdminReportText.num(pool.count - living)])
        if !groups.isEmpty {
            blocks.append(.heading("ملخّص الفروع", subtitle: nil, panel: true))
            blocks.append(.table(summary))
        } else {
            blocks.append(.note("لا يوجد أفراد يطابقون هذا النطاق.", tone: .muted))
        }

        // الأعمدة المختارة فقط («م» والاسم دائماً) — الاسم يأخذ ما بقي من العرض
        var columns: [AdminReportTable.Column] = [
            .init(title: "م", centered: true),
            .init(title: "الاسم الكامل", wraps: true, fill: true)
        ]
        if fields.contains(.branch) { columns.append(.init(title: "الفرع", wraps: true)) }
        if fields.contains(.birth) { columns.append(.init(title: "الميلاد")) }
        if fields.contains(.age) { columns.append(.init(title: "العمر", centered: true)) }
        if fields.contains(.status) { columns.append(.init(title: "الحالة", wraps: true)) }
        if fields.contains(.death) { columns.append(.init(title: "تاريخ الوفاة")) }
        if fields.contains(.phone) { columns.append(.init(title: "رقم الهاتف", ltr: true)) }
        if fields.contains(.registration) { columns.append(.init(title: "التسجيل", wraps: true)) }

        var seq = 0
        for g in groups {
            let alive = g.members.filter { !$0.deceased }.count
            var sub = "\(AdminReportText.people(g.members.count)) · أحياء \(AdminReportText.num(alive)) · متوفون \(AdminReportText.num(g.members.count - alive))"
            if let head = g.head { sub = "رأس الفرع: \(head.name) — " + sub }
            blocks.append(.heading(g.title, subtitle: sub, panel: false))
            var table = AdminReportTable(columns: columns, rows: [])
            table.rows.reserveCapacity(g.members.count)
            for p in g.members {
                seq += 1
                let death = p.deceased ? (p.deathUnknown ? nil : AdminReportText.date(p.death)) : nil
                let dim: AdminReportTone? = p.deceased ? .muted : nil
                var row = AdminReportRowBuilder()
                row.add("\(seq)")
                row.add(p.name)
                if fields.contains(.branch) { row.add(g.title) }
                if fields.contains(.birth) {
                    row.add(p.birthHidden ? AdminReportText.hidden : (AdminReportText.date(p.birth) ?? "—"))
                }
                if fields.contains(.age) { row.add(ages[p.id].map { "\($0)" } ?? "—", dim) }
                if fields.contains(.status) {
                    // بلا عمود «تاريخ الوفاة» يبقى التاريخ مع الحالة كما كان
                    if p.deceased {
                        let withDate = fields.contains(.death) ? nil : death.map { "متوفى · \($0)" }
                        row.add(withDate ?? "متوفى", dim)
                    } else {
                        row.add("حي")
                    }
                }
                if fields.contains(.death) {
                    row.add(p.deceased ? (death ?? (p.deathUnknown ? "غير معروف" : "—")) : "", dim)
                }
                if fields.contains(.phone) { row.add(phoneText(p), p.phoneHidden ? .muted : nil) }
                if fields.contains(.registration) {
                    row.add(p.deceased ? "—" : registrationText(p, input.registered), p.frozen && !p.deceased ? .warning : nil)
                }
                table.rows.append(row.row)
            }
            blocks.append(.table(table))
        }

        let intro = "يضمّ هذا السجل أفراد شجرة العائلة مرتّبين بالفروع — كل فرع تحت عنوانه ورأسه، والأفراد بترتيب الشجرة"
            + " (الأب ثم أبناؤه). يبدأ بملخّص أعداد كل فرع."
        return AdminReportDoc(kind: .register, scope: scopeParts.joined(separator: " · "), count: pool.count,
                              intro: intro, blocks: blocks, generatedBy: input.generatedBy, date: input.date)
    }

    // MARK: ٢ ملخّص إحصائي

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
        // ما يحويه (فقرة الغلاف) — الأقسام المختارة فقط
        var contents: [String] = []

        // إحصاء الأفراد
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

        // الفئات العمرية (الأحياء) — نفس فئات تصفية السجل؛ المخفي ميلاده يدخل هذا العدّ المجمّع فقط
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

        // الفروع: «شجرة الفروع» المصغّرة ثم الأفراد حسب الفرع
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

        // التسجيل في التطبيق
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

        // «أ، وب، وج»
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
    /// أكثر من ٨: أكبر ٧ بترتيب الشجرة + «وغيرها».
    private static func miniTree(_ tree: AdminReportTree, _ input: AdminReportInput) -> AdminReportMiniTree? {
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

    // MARK: ٣ المتوفون وذكراهم

    private static func memorial(_ tree: AdminReportTree, _ input: AdminReportInput,
                                 _ filter: AdminReportFilter, _ fields: Set<AdminReportField>) -> AdminReportDoc {
        let cal = AdminReportText.kuwait
        let dead = tree.pool.filter { $0.deceased && $0.countable }
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
            // بلا عمود الذكرى: الأحدث وفاةً أولاً
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
            // غير المعروف (المؤكَّد) آخراً، ثم ترتيب «ناقص تاريخه» نفسه
            if $0.0.deathUnknown != $1.0.deathUnknown { return !$0.0.deathUnknown }
            let a = DeceasedMemorial.missingRank($0.1), b = DeceasedMemorial.missingRank($1.1)
            return (a.group, a.year, $0.0.name) < (b.group, b.year, $1.0.name)
        }
        let soon = full.filter { ($0.next?.daysUntil ?? Int.max) <= DeceasedMemorial.upcomingDays }.count

        /// العمر عند الوفاة — من أخفى ميلاده بلا عمر
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
            if showsNext {
                blocks.append(.heading("الذكرى القادمة", subtitle: "تواريخ الوفاة المكتملة بالميلادي — الأقرب ذكرى أولاً",
                                       panel: false))
            } else {
                blocks.append(.heading("تاريخ الوفاة مكتمل", subtitle: "تواريخ الوفاة المكتملة بالميلادي — الأحدث وفاةً أولاً",
                                       panel: false))
            }
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
            if full.isEmpty {
                blocks.append(.note("لا توجد تواريخ وفاة مكتملة.", tone: .muted))
            } else {
                blocks.append(.table(table))
            }
        }

        blocks.append(.heading(AdminReportText.deathIncomplete,
                               subtitle: "السنة فقط، أو مكتوب بالهجري، أو بلا تاريخ — يُستكمل من ورقة العضو ← «استكمال تاريخ الوفاة»",
                               panel: false))
        // «الملاحظة» دائماً (هي ما ينقص)، و«تاريخ الوفاة» هنا = المسجَّل حالياً
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
        if partial.isEmpty {
            blocks.append(.note("كل تواريخ الوفاة مكتملة.", tone: .muted))
        } else {
            blocks.append(.table(table))
        }

        let count = filter.memorial == .all ? dead.count : partial.count
        let intro = "قائمة المتوفين من أفراد الشجرة لمن تاريخ وفاته مكتمل بالميلادي"
            + (showsNext ? " وموعد ذكراه القادمة (الأقرب أولاً)" : "")
            + "، ثم قسم «تاريخ الوفاة غير مكتمل» لمن سُجّلت سنة وفاته فقط أو كُتبت بالهجري أو لم تُسجَّل."
        return AdminReportDoc(kind: .memorial,
                              scope: filter.memorial == .all ? "كل المتوفين" : AdminReportText.deathIncomplete,
                              count: count, intro: intro, blocks: blocks,
                              generatedBy: input.generatedBy, date: input.date)
    }

    // MARK: ٤ دليل الهواتف

    private static func phones(_ tree: AdminReportTree, _ input: AdminReportInput,
                               _ filter: AdminReportFilter, _ fields: Set<AdminReportField>) -> AdminReportDoc {
        let living = tree.pool.filter { !$0.deceased }
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

        // «الحالة» هنا = التسجيل في التطبيق (عضو مسجّل · مقيّد في الشجرة · حساب موقوف) — كل القائمة أحياء
        let showsStatus = fields.contains(.status)
        var seq = 0
        var count = 0
        if filter.phones != .noPhone {
            if filter.phones == .registered && reg == nil {
                blocks.append(.note("تعذّر تحميل حالة التسجيل وقت إنشاء التقرير.", tone: .warning))
            }
            var columns: [AdminReportTable.Column] = [
                .init(title: "م", centered: true),
                .init(title: "الاسم الكامل", wraps: true, fill: true)
            ]
            if fields.contains(.branch) { columns.append(.init(title: "الفرع", wraps: true)) }
            columns.append(.init(title: "رقم الهاتف", ltr: true))
            if showsStatus { columns.append(.init(title: "الحالة", wraps: true)) }
            for g in tree.groups(listed, names: input.branchNames) {
                blocks.append(.heading(g.title, subtitle: g.head.map { "رأس الفرع: \($0.name) — \(AdminReportText.people(g.members.count))" }
                                       ?? AdminReportText.people(g.members.count), panel: false))
                var table = AdminReportTable(columns: columns, rows: [])
                for p in g.members {
                    seq += 1
                    var row = AdminReportRowBuilder()
                    row.add("\(seq)")
                    row.add(p.name)
                    if fields.contains(.branch) { row.add(g.title) }
                    row.add(phoneText(p), p.phoneHidden ? .muted : nil)
                    if showsStatus { row.add(registrationText(p, reg), p.frozen ? .warning : nil) }
                    table.rows.append(row.row)
                }
                blocks.append(.table(table))
                count += g.members.count
            }
        }
        if filter.phones != .registered {
            blocks.append(.heading(AdminReportText.noPhone, subtitle: "أحياء لا رقم لهم في السجل — \(AdminReportText.people(noPhone.count))",
                                   panel: false))
            if noPhone.isEmpty {
                blocks.append(.note("لكل الأحياء رقم هاتف.", tone: .muted))
            } else {
                // قائمة واحدة بلا عناوين فروع — فالفرع عمودها دائماً (كعناوين الفروع في القائمة الأولى)
                var columns: [AdminReportTable.Column] = [
                    .init(title: "م", centered: true),
                    .init(title: "الاسم الكامل", wraps: true, fill: true),
                    .init(title: "الفرع", wraps: true)
                ]
                if showsStatus { columns.append(.init(title: "الحالة", wraps: true)) }
                var table = AdminReportTable(columns: columns, rows: [])
                for g in tree.groups(noPhone, names: input.branchNames) {
                    for p in g.members {
                        seq += 1
                        var row = AdminReportRowBuilder()
                        row.add("\(seq)")
                        row.add(p.name)
                        row.add(g.title)
                        if showsStatus { row.add(registrationText(p, reg), p.frozen ? .warning : nil) }
                        table.rows.append(row.row)
                    }
                }
                blocks.append(.table(table))
            }
            count += noPhone.count
        }

        let scope: String
        switch filter.phones {
        case .all: scope = "كل الأحياء"
        case .registered: scope = "الأعضاء المسجّلون"
        case .noPhone: scope = AdminReportText.noPhone
        }
        let intro = "أرقام هواتف الأحياء من أفراد الشجرة مرتّبة بالفروع"
            + (showsStatus ? "، مع حالة كل فرد (عضو مسجّل في التطبيق أو مقيّد في الشجرة)" : "")
            + "، ثم قسم «بلا رقم هاتف». من أخفى رقمه يظهر «مخفي» احتراماً لخصوصيته."
        return AdminReportDoc(kind: .phones, scope: scope, count: count, intro: intro, blocks: blocks,
                              generatedBy: input.generatedBy, date: input.date)
    }
}
