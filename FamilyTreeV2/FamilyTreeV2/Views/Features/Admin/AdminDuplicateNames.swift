import Foundation

// MARK: - «المكرر والأخطاء» — المنطق الخالص (طلب المالك ٢٠٢٦-١١-٢٧ «ابيك في قسم العائلة توريني قسم المكرر او الاخطاء»)
//
// ١) «أسماء مكررة»: شخصان أو أكثر تحت الأب نفسه بالاسم الأول نفسه بعد التطبيع (`ArabicTextNormalizer.normalizeLetters`:
//    التشكيل، أ/إ/آ/ٱ ← ا، ى ← ي، «ة» آخر الكلمة ← «ه») وبلا مسافات («عبد الله» = «عبدالله»). شجرة الرجال: `profiles`
//    بـ`father_id`؛ شجرة النساء: `women_members` بـ`parent_id` بلا عقد الرجال المنسوخة (معرّفها في `profiles`).
//    «ليسا مكرّرين» يخفي المجموعة محلياً بتوقيعها (الأب + المعرّفات) — إن أُضيف ثالث بالاسم نفسه تعود.
// ٢) «أرقام بدون أسماء»: حسابات دخلت برمز الدخول ولم تكمل نموذج التسجيل — شرط الحذف التلقائي على السيرفر (`isNameless`).
// فحصه بلا محاكي: tests/admin-redesign/N1.

nonisolated enum AdminDuplicateNames {

    // MARK: أسماء مكررة

    struct Person: Equatable {
        let id: UUID
        /// الأب (`father_id`) أو الأصل في شجرة النساء (`parent_id`)
        let parent: UUID?
        let firstName: String
    }

    struct Group: Equatable, Identifiable {
        let parent: UUID
        /// الاسم كما كُتب عند أول شخص في المجموعة
        let name: String
        /// المعرّفات بترتيب الدخل
        let ids: [UUID]

        var id: String { signature }
        /// مفتاح «ليسا مكرّرين» — لا يتغيّر بترتيب المعرّفات
        var signature: String { Self.signature(parent: parent, ids: ids) }

        static func signature(parent: UUID, ids: [UUID]) -> String {
            let sorted = ids.map { $0.uuidString.lowercased() }.sorted()
            return "\(parent.uuidString.lowercased())|\(sorted.joined(separator: ","))"
        }
    }

    /// مفتاح المقارنة: الحروف موحّدة وبلا مسافات
    static func key(_ name: String) -> String {
        let letters = ArabicTextNormalizer.normalizeLetters(name.trimmingCharacters(in: .whitespacesAndNewlines))
        return String(letters.filter { !$0.isWhitespace }).lowercased()
    }

    /// المجموعات المكررة بترتيب ثابت (المفتاح ثم الأب)
    /// - excluding: معرّفات لا تدخل (عقد الرجال المنسوخة في شجرة النساء)
    /// - dismissed: توقيعات «ليسا مكرّرين»
    static func groups(_ people: [Person], excluding: Set<UUID> = [], dismissed: Set<String> = []) -> [Group] {
        struct Bucket { var name: String; var ids: [UUID] }
        var buckets: [String: Bucket] = [:]
        var order: [(parent: UUID, key: String)] = []
        for person in people where !excluding.contains(person.id) {
            guard let parent = person.parent else { continue }
            let k = key(person.firstName)
            guard !k.isEmpty else { continue }
            let slot = "\(parent.uuidString)|\(k)"
            if buckets[slot] == nil {
                buckets[slot] = Bucket(name: person.firstName.trimmingCharacters(in: .whitespacesAndNewlines), ids: [])
                order.append((parent, k))
            }
            buckets[slot]?.ids.append(person.id)
        }
        return order
            .sorted { $0.key != $1.key ? $0.key < $1.key : $0.parent.uuidString < $1.parent.uuidString }
            .compactMap { entry -> Group? in
                guard let b = buckets["\(entry.parent.uuidString)|\(entry.key)"], b.ids.count > 1 else { return nil }
                let g = Group(parent: entry.parent, name: b.name, ids: b.ids)
                return dismissed.contains(g.signature) ? nil : g
            }
    }

    // MARK: أرقام بدون أسماء

    /// نفس شرط الحذف التلقائي على السيرفر (`private.cleanup_nameless_signups`) بما يعرفه التطبيق:
    /// الاسم الكامل والأول فارغان، «معلّق»، الدور عضو/معلّق، بلا أب، ليس حساب المراجعة، وله حساب دخول.
    /// (طلبات الإدارة وصفّ النسب وعقدة شجرة النساء يفحصها السيرفر وحده.)
    struct Candidate: Equatable {
        let id: UUID
        let fullName: String
        let firstName: String
        /// الحالة «معلّق»
        let pending: Bool
        /// الدور `member` أو `pending`
        let memberRole: Bool
        let hasFather: Bool
        /// حساب مراجعة أبل (`review_account_ids`)
        let isReview: Bool
        /// له حساب دخول (دخل برمز الدخول)
        let hasLogin: Bool
        let created: Date?
    }

    static func isNameless(_ r: Candidate) -> Bool {
        r.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && r.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && r.pending && r.memberRole && !r.hasFather && !r.isReview && r.hasLogin
    }

    /// من دخل ولم يكمل التسجيل — الأحدث أولاً، وبلا تاريخ في الآخر
    static func nameless(_ rows: [Candidate]) -> [UUID] {
        rows.enumerated()
            .filter { _, r in isNameless(r) }
            .sorted { a, b in
                switch (a.element.created, b.element.created) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.offset < b.offset
                }
            }
            .map(\.element.id)
    }

    static let kuwait = TimeZone(identifier: "Asia/Kuwait") ?? .current

    private static let months = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
                                 "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]

    /// «سُجّل في 25 نوفمبر» بتوقيت الكويت
    static func registeredLine(_ date: Date?) -> String? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kuwait
        let c = cal.dateComponents([.day, .month], from: date)
        guard let d = c.day, let m = c.month, (1...12).contains(m) else { return nil }
        return "سُجّل في \(d) \(months[m - 1])"
    }

    /// «أُضيف في 25 نوفمبر 2025» بتوقيت الكويت — يفرّق بين شخصين في «أسماء مكررة»
    static func addedLine(_ date: Date?) -> String? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kuwait
        let c = cal.dateComponents([.day, .month, .year], from: date)
        guard let d = c.day, let m = c.month, let y = c.year, (1...12).contains(m) else { return nil }
        return "أُضيف في \(d) \(months[m - 1]) \(y)"
    }

    /// «له 3 أبناء» · «له ابن واحد» · «له ابنان» · «بلا أبناء» (للمرأة «لها»)
    static func childrenLine(_ n: Int, female: Bool) -> String {
        let has = female ? "لها" : "له"
        switch n {
        case ..<1: return "بلا أبناء"
        case 1: return "\(has) ابن واحد"
        case 2: return "\(has) ابنان"
        case 3...10: return "\(has) \(n) أبناء"
        default: return "\(has) \(n) ابناً"
        }
    }

    // MARK: المدخل

    /// رقم مدخل «المكرر والأخطاء»: المجموعات المكررة + أصحاب مشكلات الشجرة + الأرقام بدون أسماء
    /// + «متزوجة بلا زوج مربوط» (nil = لم يصل بعد)
    static func entryCount(duplicates: Int, problems: Int?, nameless: Int, marriedNoHusband: Int = 0) -> Int {
        duplicates + (problems ?? 0) + nameless + marriedNoHusband
    }
}

// MARK: - «متزوجة بلا زوج مربوط» (طلب المالك ٢٠٢٦-١١-٢٨)
//
// بنات العائلة في شجرة النساء (`women_members` لها أصل `parent_id`) مكتوب أنها متزوجة (`is_married`) ولا زوج مربوط
// (`husband_id` فارغ) — الصفّ يفتح مربّع المرأة نفسه حيث يُربط الزوج. فحصه: tests/admin-redesign/N2.
nonisolated enum AdminMarriedNoHusband {
    struct Woman: Equatable {
        let id: UUID
        /// الأصل في شجرة النساء (`parent_id`)
        let parent: UUID?
        let mother: UUID?
        let isFemale: Bool
        let isMarried: Bool
        let husband: UUID?
        let firstName: String
        let fullName: String
    }

    /// المعرّفات بترتيب الدخل — بنت عائلة (لها أصل) أنثى متزوجة بلا زوج
    /// - excluding: عقد الرجال المنسوخة (معرّفها في `profiles`)
    static func ids(_ women: [Woman], excluding: Set<UUID> = []) -> [UUID] {
        women.filter { $0.isFemale && $0.isMarried && $0.husband == nil && $0.parent != nil && !excluding.contains($0.id) }
            .map(\.id)
    }

    /// أبناؤها: من أصله أو أمّه هي — مرة لكل ابن
    static func childCount(_ id: UUID, in women: [Woman]) -> Int {
        women.filter { $0.id != id && ($0.parent == id || $0.mother == id) }.count
    }

    /// «شهد بنت صلاح عبدالحميد» — من النسب، وإلا من كلمات الاسم الكامل (الثانية والثالثة)
    static func displayName(first: String, father: String?, grandfather: String?, fullName: String) -> String {
        let words = fullName.split(whereSeparator: \.isWhitespace).map(String.init)
        let name = first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (words.first ?? "")
                                                                                  : first.trimmingCharacters(in: .whitespacesAndNewlines)
        var lineage: [String]
        if let f = father?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            lineage = [f]
            if let g = grandfather?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { lineage.append(g) }
        } else {
            lineage = Array(words.dropFirst().prefix(2))
        }
        guard !lineage.isEmpty else { return name }
        return "\(name) بنت " + lineage.joined(separator: " ")
    }
}
