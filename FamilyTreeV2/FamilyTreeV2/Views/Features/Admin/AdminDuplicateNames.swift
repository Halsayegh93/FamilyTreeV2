import Foundation

// MARK: - «المكرر والأخطاء» — المنطق الخالص (طلب المالك ٢٠٢٦-١١-٢٧ «ابيك في قسم العائلة توريني قسم المكرر او الاخطاء»)
//
// ١) «أسماء مكررة»: شخصان أو أكثر تحت الأب نفسه بالاسم الأول نفسه بعد التطبيع (`ArabicTextNormalizer.normalizeLetters`:
//    التشكيل، أ/إ/آ/ٱ ← ا، ى ← ي، «ة» آخر الكلمة ← «ه») وبلا مسافات («عبد الله» = «عبدالله»). شجرة الرجال: `profiles`
//    بـ`father_id`؛ شجرة النساء: `women_members` بـ`parent_id` بلا عقد الرجال المنسوخة (معرّفها في `profiles`).
//    «ليسا مكرّرين» يخفي المجموعة محلياً بتوقيعها (الأب + المعرّفات) — إن أُضيف ثالث بالاسم نفسه تعود.
// ٢) «أرقام بدون أسماء»: حسابات دخلت برمز الدخول ولم تكمل نموذج التسجيل (بلا اسم، «معلّق»، لها حساب دخول).
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

    struct Candidate: Equatable {
        let id: UUID
        let name: String
        /// الحالة «معلّق»
        let pending: Bool
        /// له حساب دخول (دخل برمز الدخول)
        let hasLogin: Bool
        let created: Date?
    }

    /// من دخل ولم يكمل التسجيل — الأحدث أولاً، وبلا تاريخ في الآخر
    static func nameless(_ rows: [Candidate]) -> [UUID] {
        rows.enumerated()
            .filter { _, r in
                let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return (name.isEmpty || name == "بدون اسم") && r.pending && r.hasLogin
            }
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

    // MARK: المدخل

    /// رقم مدخل «المكرر والأخطاء»: المجموعات المكررة + أصحاب مشكلات الشجرة + الأرقام بدون أسماء (nil = لم يصل بعد)
    static func entryCount(duplicates: Int, problems: Int?, nameless: Int) -> Int {
        duplicates + (problems ?? 0) + nameless
    }
}
