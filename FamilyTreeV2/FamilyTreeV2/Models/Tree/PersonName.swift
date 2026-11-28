import Foundation

// MARK: - الأسماء الأولى المركّبة (طلب المالك ٢٠٢٦-١٠-١٨: «زين العابدين»، «محمد باقر»، «علي الاكبر»)
//
// المرجع الموحّد للآيفون والأندرويد والموقع (names-fix/SPEC.md) — كل تقسيم لاسم شخص يمرّ من هنا:
// • القاعدة ١: first_name هو المرجع — لا يُستخرج من «أول كلمة» في الاسم الكامل إذا أمكن معرفته أدقّ.
// • القاعدة ٢: عضو في الشجرة ← نمشي السلسلة (هو ← أبوه ← جدّه …) بـ father_id، وكل اسم أول وحدة واحدة.
// • القاعدة ٣: نص حرّ (مكتوب أو بلا شجرة) ← `units(_:)`.
// البحث والمطابقة بالكلمات ما تتغيّر (خارج النطاق).

nonisolated enum PersonName {

    /// كلمات تلتصق بالكلمة اللي بعدها: «عبد الله»، «أبو الفضل»، «بو ناصر»
    static let joinNext: Set<String> = ["عبد", "أبو", "ابو", "بو"]

    /// المسافات الزايدة تنشال: «  زين   العابدين » ← «زين العابدين»
    static func clean(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: القاعدة ٣ — نص حرّ

    /// وحدات الاسم: الكلمات بعد الدمج —
    /// «عبد/أبو/ابو/بو» + اللي بعدها، «المحمد» + «علي»، وكلمة تبدأ بـ«ال» (مو الأخيرة) تلتصق باللي قبلها.
    /// «زين العابدين علي صلاح المحمدعلي» ← [زين العابدين، علي، صلاح، المحمدعلي]
    static func units(_ text: String) -> [String] {
        let raw = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [String] = []
        var i = 0
        while i < raw.count {
            let w = raw[i]
            let isLast = i == raw.count - 1
            if !isLast && (joinNext.contains(w) || (w == "المحمد" && raw[i + 1] == "علي")) {
                out.append(w + " " + raw[i + 1])
                i += 2
            } else if !isLast, w.hasPrefix("ال"), let prev = out.last {
                // الأخيرة (العائلة) ما تلتصق أبداً
                out[out.count - 1] = prev + " " + w
                i += 1
            } else {
                out.append(w)
                i += 1
            }
        }
        return out
    }

    /// أول وحدة من نص حرّ (القاعدة ٣) — «زين العابدين علي …» ← «زين العابدين»
    static func firstUnit(_ text: String) -> String {
        units(text).first ?? clean(text)
    }

    // MARK: القاعدة ٢ — سلسلة الشجرة

    /// عقدة في الشجرة: الاسم الأول والأب فقط (اللي تحتاجه السلسلة)
    struct Node: Sendable, Equatable {
        let firstName: String
        let fatherId: UUID?
        init(firstName: String, fatherId: UUID?) {
            self.firstName = firstName
            self.fatherId = fatherId
        }
    }

    /// وحدات اسم عضو من الشجرة: نمشي هو ← أبوه ← جدّه … ما دام السجل موجود؛ إذا الباقي يبدأ باسمه
    /// الأول + مسافة (أو يساويه) ناخذه وحدة واحدة. لما تنتهي السلسلة الباقي يتقسّم بالقاعدة ٣.
    /// آخر وحدة = اسم العائلة.
    static func chainUnits(fullName: String, firstName: String, fatherId: UUID?,
                           lookup: (UUID) -> Node?) -> [String] {
        var rest = clean(fullName)
        var out: [String] = []
        var first = clean(firstName)
        var next = fatherId
        var seen: Set<UUID> = []
        while !rest.isEmpty, !first.isEmpty {
            if rest == first {
                out.append(first)
                rest = ""
                break
            }
            guard rest.hasPrefix(first + " ") else { break }
            out.append(first)
            rest = String(rest.dropFirst(first.count + 1))
            // حماية من حلقة في father_id
            guard let fid = next, seen.insert(fid).inserted, let node = lookup(fid) else { break }
            first = clean(node.firstName)
            next = node.fatherId
        }
        return out + units(rest)
    }

    /// السلسلة من الشجرة المسجّلة حالياً (`PersonNameTree`)
    static func chainUnits(fullName: String, firstName: String, fatherId: UUID?) -> [String] {
        let tree = PersonNameTree.snapshot()
        return chainUnits(fullName: fullName, firstName: firstName, fatherId: fatherId) { tree[$0] }
    }

    // MARK: الاختصار

    /// أول (n-1) وحدات + الأخيرة (العائلة) — نفس منطق الاختصار القديم لكن على الوحدات
    static func shorten(_ units: [String], to n: Int) -> [String] {
        guard units.count > n, n >= 2, let last = units.last else { return units }
        return Array(units.prefix(n - 1)) + [last]
    }

    /// الثلاثي من نص حرّ: الأول + الثاني + العائلة؛ القصير يبقى كما هو
    static func threeParts(_ text: String) -> String {
        let u = units(text)
        guard u.count > 3 else { return text }
        return shorten(u, to: 3).joined(separator: " ")
    }

    /// أول ثلاث وحدات من السلسلة (الأول + الأب + الجد، بلا العائلة) — «علي محمدحسين عبدالله»؛ القصير كما هو
    static func firstThree(_ units: [String]) -> [String] { Array(units.prefix(3)) }

    /// الثلاثي المتتالي من نص حرّ (أسماء الإشعارات): «علي محمدحسين عبدالله موسى … الصايغ» ← «علي محمدحسين عبدالله»
    static func firstThree(_ text: String) -> String {
        let u = units(text)
        return u.count > 3 ? firstThree(u).joined(separator: " ") : clean(text)
    }

    // MARK: القاعدة ١ — الحفظ والتعديل

    /// هل الاسم الكامل يبدأ بالاسم الأول؟ (يساويه، أو يبدأ به + مسافة)
    static func startsWithFirstName(_ fullName: String, _ firstName: String) -> Bool {
        let full = clean(fullName)
        let first = clean(firstName)
        guard !first.isEmpty else { return false }
        return full == first || full.hasPrefix(first + " ")
    }

    /// الاسم الأول للحفظ: (أ) الحقل الصريح، (ب) الاسم الكامل ينتهي بـ« » + اسم الأب الكامل ← اللي قبله،
    /// (ج) أول وحدة بالقاعدة ٣.
    static func firstName(fullName: String, explicit: String? = nil, fatherFullName: String? = nil) -> String {
        if let e = explicit.map(clean), !e.isEmpty { return e }
        let full = clean(fullName)
        if let father = fatherFullName.map(clean), !father.isEmpty, full.hasSuffix(" " + father) {
            let head = clean(String(full.dropLast(father.count + 1)))
            if !head.isEmpty { return head }
        }
        return firstUnit(full)
    }

    /// باقي الاسم الكامل بعد الاسم الأول (سلسلة الآباء والعائلة):
    /// ينتهي باسم الأب الكامل ← هو؛ يبدأ بالاسم الأول القديم + مسافة ← اللي بعده؛ وإلا بعد أول وحدة.
    /// بلا اسم أول قديم (انمسح الحقل) ← النص كله سلسلة.
    static func chainAfterFirstName(_ fullName: String, firstName: String, fatherFullName: String? = nil) -> String {
        let full = clean(fullName)
        let old = clean(firstName)
        if let father = fatherFullName.map(clean), !father.isEmpty,
           full == father || full.hasSuffix(" " + father) {
            return father
        }
        if old.isEmpty { return full }
        if full == old { return "" }
        if full.hasPrefix(old + " ") { return String(full.dropFirst(old.count + 1)) }
        return units(full).dropFirst().joined(separator: " ")
    }

    /// تغيير الاسم الأول داخل الاسم الكامل: نستبدل البادئة (الاسم الأول القديم كاملاً) بالجديد،
    /// وإذا ما تطابقت نستبدل أول وحدة (القاعدة ٣). الاسم ما تغيّر ← الاسم الكامل كما هو بالضبط
    /// (حتى سجلّ أوله «زين» واسمه الكامل «زين العابدين …» ما ينقص عند حفظ حقل ثاني).
    static func replacingFirstName(in fullName: String, old: String, new: String,
                                   fatherFullName: String? = nil) -> String {
        if clean(new) == clean(old) { return fullName }
        let rest = chainAfterFirstName(fullName, firstName: old, fatherFullName: fatherFullName)
        return [clean(new), rest].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: اسم البنت تحت أبيها (طلب المالك ٢٠٢٦-١١-٢٨)
    // يُحفظ كاملاً «اسمها + اسم أبيها الكامل»، ويُعرض في الشجرة والملف بالاسم الأول وحده.

    /// حفظ من حقل «الاسم الأول» (تعديل البنت من الملف الشخصي): الاسم الأول المحفوظ والاسم الكامل.
    /// المكتوب ينتهي باسم الأب ← يُقصّ (لا تكرار)؛ والاسم الكامل بلا سلسلة ← يُكمَّل باسم الأب.
    static func daughterSave(typedFirst: String, storedFull: String, storedFirst: String,
                             fatherFullName: String?) -> (first: String, full: String) {
        let father = clean(fatherFullName ?? "")
        var first = clean(typedFirst)
        if !father.isEmpty, first.hasSuffix(" " + father) {
            let head = clean(String(first.dropLast(father.count + 1)))
            if !head.isEmpty { first = head }
        }
        let base = clean(replacingFirstName(in: storedFull, old: storedFirst, new: first,
                                            fatherFullName: father.isEmpty ? nil : father))
        if !father.isEmpty, !first.isEmpty, base.isEmpty || base == first {
            return (first, first + " " + father)
        }
        return (first, base.isEmpty ? first : base)
    }

    /// حفظ من حقل «الاسم الكامل» (إدارة السجل): كلمة واحدة أو الاسم الأول وحده ← يُكمَّل باسم الأب،
    /// وما فيه سلسلة يبقى كما كُتب (لا تكرار لاسم الأب).
    static func completedDaughterFullName(_ name: String, fatherFullName: String?,
                                          storedFirst: String? = nil) -> String {
        let n = clean(name)
        let father = clean(fatherFullName ?? "")
        guard !n.isEmpty, !father.isEmpty else { return n }
        if n == father || n.hasSuffix(" " + father) { return n }
        let prev = clean(storedFirst ?? "")
        if !n.contains(" ") || (!prev.isEmpty && n == prev) { return n + " " + father }
        return n
    }

    /// الاسمان المحفوظان من حقل «الاسم الكامل»: الكامل (مُكمَّل باسم الأب إن نقص) والأول —
    /// الأول المحفوظ إن بقي أول الاسم، وإلا ما قبل اسم الأب، وإلا أول وحدة (PersonName القاعدة ١)
    static func savedNames(_ fullName: String, storedFirst: String?,
                                       fatherFullName: String?) -> (first: String, full: String) {
        let full = completedDaughterFullName(fullName, fatherFullName: fatherFullName,
                                                        storedFirst: storedFirst)
        let prev = clean(storedFirst ?? "")
        let keepsPrev = !prev.isEmpty && (full == prev || full.hasPrefix(prev + " "))
        let first = firstName(fullName: full, explicit: keepsPrev ? prev : nil,
                                         fatherFullName: fatherFullName)
        return (first, full)
    }

    /// الاسم المعروض للبنت في الشجرة وقائمة البنات: الاسم الأول المحفوظ، وإلا أول وحدة من الكامل.
    static func displayFirst(firstName: String, fullName: String) -> String {
        let f = clean(firstName)
        return f.isEmpty ? firstUnit(fullName) : f
    }
}

// MARK: - الشجرة الحالية للقاعدة ٢
//
// `FamilyMember` ما يعرف الشجرة، فـ MemberViewModel يسجّل هنا قائمة الأعضاء كل ما تتغيّر (نسخ مصفوفة
// بلا كلفة)، والقاموس يُبنى مرة وحدة عند أول قراءة بعد التغيير — نفس أسلوب FamilyNameCatalog.
nonisolated enum PersonNameTree {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: [FamilyMember]? = nil
    nonisolated(unsafe) private static var nodes: [UUID: PersonName.Node] = [:]

    static func update(_ members: [FamilyMember]) {
        lock.lock(); pending = members; lock.unlock()
    }

    static func snapshot() -> [UUID: PersonName.Node] {
        lock.lock(); defer { lock.unlock() }
        if let list = pending {
            var map: [UUID: PersonName.Node] = [:]
            map.reserveCapacity(list.count)
            for m in list where map[m.id] == nil {
                map[m.id] = PersonName.Node(firstName: m.firstName, fatherId: m.fatherId)
            }
            nodes = map
            pending = nil
        }
        return nodes
    }
}
