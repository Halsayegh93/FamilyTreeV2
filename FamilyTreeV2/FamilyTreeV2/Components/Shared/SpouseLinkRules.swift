import Foundation

// MARK: - «الوارد»: طلب ربط الزوج أو الزوجة من العائلة (العيّنة spouse2.html القسم ٣، المالك ٢٠٢٦-١١-٢٨ «نفّذ كل شي»)
//
// العضو من خارج العائلة كتب «اسم الزوجة/الزوج الرباعي» في «استكمال التسجيل» ← `submit_spouse_link` ← طلب `lineage_request`
// بـ kind = `outside_spouse` (ترحيل 20261128150000). الإدارة ترى البطاقة: الاسم · الصلة · الاسم المكتوب · اقتراحات من الشجرة
// (`spouse_link_suggestions`) بزرّ «ربط» (`link_outside_spouse`)، وإن لم توجد: «الزوجة غير مضافة بالتطبيق» + (الوالد موجود)
// «إضافة «فلانة» تحت والدها وربط الزوج» (`add_daughter_and_link_spouse`) + «اختيار من الشجرة يدوياً» + «طلب معلومات من العضو»
// (`ask_join_completion` بحقل spouse_name). والعكس للزوجة من خارج العائلة: الزوج من رجال العائلة («ربط» يضيفها زوجة له).
// منطق خالص يُفحص بلا محاكي: `tests/admin-redesign/SP1/main.swift`.

nonisolated enum SpouseLinkRules {
    typealias Relation = SignupOriginRules.Relation

    /// حمولة الطلب
    struct Details: Decodable, Equatable, Sendable {
        let relation: Relation
        let typedName: String
        let spouseName: String

        enum CodingKeys: String, CodingKey { case relation, typedName = "spouse_typed_name", spouseName = "spouse_name" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            relation = Relation(rawValue: (try? c.decode(String.self, forKey: .relation)) ?? "") ?? .wife
            typedName = (try? c.decode(String.self, forKey: .typedName)) ?? ""
            spouseName = (try? c.decode(String.self, forKey: .spouseName)) ?? typedName
        }

        static func parse(_ details: String?) -> Details? {
            guard SignupOriginRules.isSpouseLink(details: details), let data = details?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Details.self, from: data)
        }
    }

    /// مقترح من الشجرة: بنت (للزوجة) أو رجل (للزوج)
    struct Match: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let fullName: String
        let fatherId: UUID?
        /// يُربط؟ (البنت بلا زوج، أو زوجها من خارج العائلة بلا حساب)
        let canLink: Bool
        /// للزوج: عقدة زوجة له بلا حساب باسمها الأول — تُربط بدل إنشاء عقدة جديدة
        let wifeNodeId: UUID?
        var husbandName: String? = nil
        var hasAccount: Bool = false
        /// للزوج: زوجاته كلهن في شجرة النساء (20261128191000) — يختار المدير منهن قبل الربط
        var wives: [Wife] = []

        enum CodingKeys: String, CodingKey {
            case id, fullName = "full_name", fatherId = "father_id", canLink = "can_link", wifeNodeId = "wife_node_id",
                 husbandName = "husband_name", hasAccount = "has_account", wives
        }

        init(id: UUID, fullName: String, fatherId: UUID?, canLink: Bool, wifeNodeId: UUID?, wives: [Wife] = []) {
            self.id = id; self.fullName = fullName; self.fatherId = fatherId; self.canLink = canLink; self.wifeNodeId = wifeNodeId
            self.wives = wives
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            fullName = (try? c.decode(String.self, forKey: .fullName)) ?? ""
            fatherId = try? c.decode(UUID.self, forKey: .fatherId)
            canLink = (try? c.decode(Bool.self, forKey: .canLink)) ?? false
            wifeNodeId = try? c.decode(UUID.self, forKey: .wifeNodeId)
            husbandName = try? c.decode(String.self, forKey: .husbandName)
            hasAccount = (try? c.decode(Bool.self, forKey: .hasAccount)) ?? false
            wives = (try? c.decode([Wife].self, forKey: .wives)) ?? []
        }
    }

    /// زوجة للرجل في شجرة النساء (من الاقتراحات، أو من تفصيل خطأ `choose_wife`، أو من الشجرة المحمّلة)
    struct Wife: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let fullName: String
        var hasAccount: Bool = false
        var isDeceased: Bool = false
        /// اسمها الأول = الاسم الأول لصاحبة الطلب
        var nameMatch: Bool = false

        enum CodingKeys: String, CodingKey {
            case id, fullName = "full_name", hasAccount = "has_account", isDeceased = "is_deceased", nameMatch = "name_match"
        }

        init(id: UUID, fullName: String, hasAccount: Bool = false, isDeceased: Bool = false, nameMatch: Bool = false) {
            self.id = id; self.fullName = fullName; self.hasAccount = hasAccount; self.isDeceased = isDeceased
            self.nameMatch = nameMatch
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            fullName = (try? c.decode(String.self, forKey: .fullName)) ?? ""
            hasAccount = (try? c.decode(Bool.self, forKey: .hasAccount)) ?? false
            isDeceased = (try? c.decode(Bool.self, forKey: .isDeceased)) ?? false
            nameMatch = (try? c.decode(Bool.self, forKey: .nameMatch)) ?? false
        }
    }

    /// «زوجة أخرى غير مضافة» صراحةً لـ `link_outside_spouse` (تُنشأ عقدة جديدة) — بدونها يرفض السيرفر `choose_wife`
    static let newWifeNode = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// الزوجات اللاتي يُربط بهن (بلا حساب)، المطابقة بالاسم أولاً
    static func linkableWives(_ wives: [Wife]) -> [Wife] {
        let free = wives.filter { !$0.hasAccount }
        return free.filter(\.nameMatch) + free.filter { !$0.nameMatch }
    }

    /// قبل ربط الزوج: للرجل زوجة بلا حساب ← يختار المدير (أو «زوجة أخرى غير مضافة»)
    static func needsWifeChoice(_ relation: Relation, wives: [Wife]) -> Bool {
        relation == .husband && !linkableWives(wives).isEmpty
    }

    /// قائمة الزوجات من تفصيل خطأ `choose_wife` (DETAIL = jsonb)
    static func wives(fromErrorDetail detail: String?) -> [Wife] {
        guard let data = detail?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Wife].self, from: data)) ?? []
    }

    struct Father: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let fullName: String
        enum CodingKeys: String, CodingKey { case id, fullName = "full_name" }
        init(id: UUID, fullName: String) { self.id = id; self.fullName = fullName }
    }

    struct Suggestions: Decodable, Equatable, Sendable {
        var matches: [Match] = []
        var fathers: [Father] = []
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            matches = (try? c.decode([Match].self, forKey: .matches)) ?? []
            fathers = (try? c.decode([Father].self, forKey: .fathers)) ?? []
        }
        enum CodingKeys: String, CodingKey { case matches, fathers }
    }

    /// أزرار البطاقة بالترتيب (الأول هو الرئيسي)
    enum Action: Equatable, Hashable {
        case link(UUID)
        case addUnderFather(UUID)
        case pickManually
        case askInfo
    }

    static func actions(_ relation: Relation, matches: [Match], fathers: [Father]) -> [Action] {
        var out: [Action] = matches.filter(\.canLink).map { .link($0.id) }
        if out.isEmpty, relation == .wife, let f = fathers.first { out.append(.addUnderFather(f.id)) }
        return out + [.pickManually, .askInfo]
    }

    /// «الزوجة غير مضافة بالتطبيق»: لا مقترح يُربط
    static func notInApp(_ relation: Relation, matches: [Match]) -> Bool { !matches.contains(where: \.canLink) }

    static func firstName(_ s: String) -> String {
        SignupOriginRules.tidy(s).split(separator: " ").first.map(String.init) ?? ""
    }

    /// عنوان البطاقة: صاحب الطلب هو الزوج من خارج العائلة (كتب الزوجة) أو الزوجة من خارجها (كتبت الزوج)
    static func inboxTitle(_ relation: Relation) -> String { relation == .wife ? Ar.outsideHusband : Ar.outsideWife }

    enum Ar {
        static let outsideHusband = "زوج من خارج العائلة"
        static let outsideWife = "زوجة من خارج العائلة"
        static func typedLine(_ r: Relation) -> String { r == .wife ? "الزوجة: " : "الزوج: " }
        static func notInApp(_ r: Relation) -> String { r == .wife ? "الزوجة غير مضافة بالتطبيق" : "الزوج غير مضاف بالتطبيق" }
        static func notInAppBody(_ r: Relation) -> String {
            r == .wife ? "لا توجد بنت بهذا الاسم في شجرة النساء." : "لا يوجد رجل بهذا الاسم في شجرة العائلة."
        }
        static let fatherFound = "الوالد موجود في الشجرة"
        static func addUnderFather(_ first: String) -> String { "إضافة «\(first)» تحت والدها وربط الزوج" }
        static let pickManually = "اختيار من الشجرة يدوياً"
        static let askInfo = "طلب معلومات من العضو"
        static let link = "ربط"
        static let suggestions = "مقترحات من الشجرة"
        static func linkedTo(_ r: Relation) -> String { r == .wife ? "زوجها: " : "زوجته: " }
        static let hasOtherSpouse = "لها زوج مربوط آخر"
        static let askNotePlaceholder = "ملاحظة للعضو (اختيارية)"
        static let askSend = "إرسال الطلب"
        static let askTitle = "طلب معلومات من العضو"
        static let askBody = "يصل العضو إشعار بطلب تصحيح الاسم، ويعدّله من «استكمال التسجيل»."
        static let linked = "تم الربط"
        static let rejectWithReason = "رفض مع سبب"
        static let chooseWifeTitle = "اختيار الزوجة"
        static let chooseWifeBody = "للرجل زوجة في الشجرة. اختر الزوجة صاحبة الطلب، أو «زوجة أخرى غير مضافة»."
        static let otherWife = "زوجة أخرى غير مضافة"
        static let deceasedWife = "متوفاة"
        static let nameMatches = "الاسم الأول مطابق"

        static var all: [String] {
            [outsideHusband, outsideWife, typedLine(.wife), typedLine(.husband), notInApp(.wife), notInApp(.husband),
             notInAppBody(.wife), notInAppBody(.husband), fatherFound, addUnderFather("فاطمة"), pickManually, askInfo, link,
             suggestions, linkedTo(.wife), linkedTo(.husband), hasOtherSpouse, askNotePlaceholder, askSend, askTitle, askBody,
             linked, rejectWithReason, chooseWifeTitle, chooseWifeBody, otherWife, deceasedWife, nameMatches]
        }
    }
}
