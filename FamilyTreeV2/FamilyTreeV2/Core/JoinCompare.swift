import Foundation

// MARK: - مقارنة طلب الانضمام بسجلّ الشجرة (طلب المالك ٢٠٢٦-١١-٠٥: «الشجرة أولاً» + «المقارنة»)
//
// منطق صافٍ بلا واجهة: سطر لكل بيان (الاسم الأول، الأب، الجد، الميلاد، حساب الدخول)، والجملة الواضحة قبل الربط.
// الأسماء من `nameUnits` دائماً — `first_name` عند طالب الانضمام فيه كل ما كتبه.
enum JoinCompare {

    /// في الشجرة سجلات بتاريخ وهمي (2026-01-26): سنة الميلاد هذه «تاريخ غير مؤكد»، والسيرفر يقدّم تاريخ الطلب عليها
    /// (`merge_member_into_tree`: `coalesce(v_new.birth_date, v_tree.birth_date)`)
    static let placeholderBirthYear = "2026"
    /// حدّ `merge_member_into_tree`: دون ١٣ لا حساب، ومن ١٣ إلى ١٧ موافقة ولي الأمر
    static let minimumAccountAge = 13
    static let adultAge = 18

    enum Verdict: Equatable {
        case match, close, differ, unknown
    }

    enum Field: Hashable {
        case firstName, father, grandfather, birth, login

        var title: String {
            switch self {
            case .firstName: return L10n.t("الاسم الأول", "First name")
            case .father: return L10n.t("الأب", "Father")
            case .grandfather: return L10n.t("الجد", "Grandfather")
            case .birth: return L10n.t("تاريخ الميلاد", "Birth date")
            case .login: return L10n.t("حساب دخول", "Login")
            }
        }
    }

    struct Line: Identifiable, Equatable {
        let field: Field
        let verdict: Verdict
        let detail: String
        /// قيمتا الطرفين للتحذيرات — nil حين تنقص
        var request: String? = nil
        var tree: String? = nil
        var id: Field { field }
    }

    // MARK: الاسم — الأول والأب والجد بالترتيب

    /// وحدة مع مفتاحها، بلا الفارغ وبلا العائلة في الآخر (نفس `NameMatcher.linkChain`)
    private static func keyed(_ units: [String], noise: Set<String>) -> [(raw: String, key: String)] {
        var out = units.map { (raw: $0, key: NameMatcher.linkKey($0)) }.filter { !$0.key.isEmpty }
        while let last = out.last, noise.contains(last.key) { out.removeLast() }
        return out
    }

    /// ثلاثة أسطر: الاسم الأول، الأب، الجد. الاسم المركّب قد يُكتب كلمتين في طرف وكلمة في الآخر (مثل `linkDepth`)؛
    /// وبعد اختلاف جزء تستمر المقارنة موضعاً بموضع، فيظهر الجد صحيحاً ولو اختلف الأب
    static func nameLines(requestUnits: [String], treeUnits: [String], noise: Set<String>) -> [Line] {
        let a = keyed(requestUnits, noise: noise)
        let b = keyed(treeUnits, noise: noise)
        var i = 0, j = 0
        var lines: [Line] = []
        for field in [Field.firstName, .father, .grandfather] {
            switch (i < a.count, j < b.count) {
            case (false, false):
                lines.append(Line(field: field, verdict: .unknown, detail: L10n.t("غير مذكور", "Not given")))
            case (false, true):
                lines.append(Line(field: field, verdict: .unknown,
                                  detail: L10n.t("غير مذكور في الطلب · \(b[j].raw)", "Not in the request · \(b[j].raw)"),
                                  tree: b[j].raw))
                j += 1
            case (true, false):
                lines.append(Line(field: field, verdict: .unknown,
                                  detail: L10n.t("ناقص في الشجرة · \(a[i].raw)", "Missing in the tree · \(a[i].raw)"),
                                  request: a[i].raw))
                i += 1
            case (true, true):
                if a[i].key == b[j].key {
                    lines.append(Line(field: field, verdict: .match, detail: b[j].raw, request: a[i].raw, tree: b[j].raw))
                    i += 1; j += 1
                } else if i + 1 < a.count, a[i].key + a[i + 1].key == b[j].key {
                    lines.append(Line(field: field, verdict: .match, detail: b[j].raw, request: a[i].raw, tree: b[j].raw))
                    i += 2; j += 1
                } else if j + 1 < b.count, a[i].key == b[j].key + b[j + 1].key {
                    let raw = b[j].raw + " " + b[j + 1].raw
                    lines.append(Line(field: field, verdict: .match, detail: raw, request: a[i].raw, tree: raw))
                    i += 1; j += 2
                } else {
                    let close = NameMatcher.isTypo(a[i].key, b[j].key)
                    lines.append(Line(field: field, verdict: close ? .close : .differ,
                                      detail: bothSides(request: a[i].raw, tree: b[j].raw),
                                      request: a[i].raw, tree: b[j].raw))
                    i += 1; j += 1
                }
            }
        }
        return lines
    }

    private static func bothSides(request: String, tree: String) -> String {
        L10n.t("الطلب «\(request)» · الشجرة «\(tree)»", "Request «\(request)» · Tree «\(tree)»")
    }

    /// التاريخ معزول باتجاه LTR — بدونه ينقلب في السطر العربي (05-03-1998)
    static func isolated(_ text: String) -> String { "\u{2066}" + text + "\u{2069}" }

    // MARK: الميلاد

    struct Birth: Equatable {
        let line: Line
        /// ما يُحفظ بعد الربط أو سبب التنبيه
        let note: String?
        /// سنة 2026 في الشجرة
        let treeIsPlaceholder: Bool
    }

    static func clean(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func birth(request: String?, tree: String?) -> Birth {
        let r = isolatedDate(request), t = isolatedDate(tree)
        let rawTree = clean(tree)
        let keeps = L10n.t("يُعتمد تاريخ مقدّم الطلب \(r).", "The applicant's date \(r) is what is kept.")
        if rawTree.hasPrefix(placeholderBirthYear) {
            let note = r.isEmpty
                ? L10n.t("لا يوجد تاريخ في الطلب، وتاريخ الشجرة وهمي.", "No date in the request, and the tree date is a placeholder.")
                : keeps
            return Birth(line: Line(field: .birth, verdict: .unknown,
                                    detail: L10n.t("تاريخ غير مؤكد", "Unconfirmed date"), request: r.isEmpty ? nil : r),
                         note: note, treeIsPlaceholder: true)
        }
        if r.isEmpty && t.isEmpty {
            return Birth(line: Line(field: .birth, verdict: .unknown, detail: L10n.t("ناقص في الطرفين", "Missing on both sides")),
                         note: nil, treeIsPlaceholder: false)
        }
        if r.isEmpty {
            return Birth(line: Line(field: .birth, verdict: .unknown,
                                    detail: L10n.t("غير مذكور في الطلب · \(t)", "Not in the request · \(t)"), tree: t),
                         note: nil, treeIsPlaceholder: false)
        }
        if t.isEmpty {
            return Birth(line: Line(field: .birth, verdict: .unknown,
                                    detail: L10n.t("ناقص في الشجرة · \(r)", "Missing in the tree · \(r)"), request: r),
                         note: keeps, treeIsPlaceholder: false)
        }
        let rawRequest = clean(request)
        if rawRequest.prefix(10) == rawTree.prefix(10) {
            return Birth(line: Line(field: .birth, verdict: .match, detail: t, request: r, tree: t),
                         note: nil, treeIsPlaceholder: false)
        }
        let sameYear = rawRequest.prefix(4) == rawTree.prefix(4)
        return Birth(line: Line(field: .birth, verdict: sameYear ? .close : .differ,
                                detail: L10n.t("الطلب \(r) · الشجرة \(t)", "Request \(r) · Tree \(t)"), request: r, tree: t),
                     note: keeps, treeIsPlaceholder: false)
    }

    private static func isolatedDate(_ raw: String?) -> String {
        let text = String(clean(raw).prefix(10))
        return text.isEmpty ? "" : isolated(text)
    }

    /// العمر بالسنوات الكاملة — nil إن جُهل التاريخ
    static func ageYears(_ raw: String?, now: Date = Date()) -> Int? {
        guard let date = NameMatcher.linkBirth(raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.dateComponents([.year], from: date, to: now).year
    }

    // MARK: حساب الدخول

    /// `hasLogin` nil = قائمة الحسابات لم تصل بعد (السيرفر يفحص عند الربط على أي حال)
    static func loginLine(hasLogin: Bool?, hasPhone: Bool) -> Line {
        switch (hasLogin, hasPhone) {
        case (true?, _):
            return Line(field: .login, verdict: .differ, detail: L10n.t("عنده حساب", "Has a login"))
        case (nil, _):
            return Line(field: .login, verdict: .unknown, detail: L10n.t("لم يُتحقق بعد", "Not checked yet"))
        case (false?, true):
            return Line(field: .login, verdict: .close, detail: L10n.t("له رقم ولم يدخل", "Has a number, never signed in"))
        case (false?, false):
            return Line(field: .login, verdict: .match, detail: L10n.t("ما عنده", "None"))
        }
    }

    // MARK: التنبيهات

    /// تنبيه لكل اختلاف قبل الربط — أولها الأسماء ثم الميلاد
    static func warnings(nameLines: [Line], birth: Birth) -> [String] {
        var out: [String] = []
        for line in nameLines where line.verdict == .differ || line.verdict == .close {
            let request = line.request ?? "", tree = line.tree ?? ""
            let title = line.field.title
            out.append(L10n.t("\(title) مختلف: في الطلب «\(request)» وفي الشجرة «\(tree)».",
                              "\(title) differs: «\(request)» in the request, «\(tree)» in the tree."))
        }
        if birth.line.verdict == .differ || birth.line.verdict == .close {
            let request = birth.line.request ?? "", tree = birth.line.tree ?? ""
            out.append(L10n.t("تاريخ الميلاد مختلف: في الطلب \(request) وفي الشجرة \(tree)، ويُعتمد تاريخ الطلب.",
                              "Birth date differs: \(request) in the request, \(tree) in the tree; the request's date is kept."))
        }
        return out
    }

    // MARK: الجملة قبل الربط

    private static let maxBrothersNamed = 6

    /// «أحمد وفهد» / «أحمد وفهد و3 غيرهم» — يقبل القائمة فارغة
    static func namesList(_ names: [String]) -> String {
        let shown = Array(names.prefix(maxBrothersNamed))
        let rest = names.count - shown.count
        var text: String
        if L10n.isArabic {
            text = shown.dropLast().joined(separator: "، ")
            if let last = shown.last { text += text.isEmpty ? last : " و\(last)" }
            if rest > 0 { text += " و\(rest) غيرهم" }
        } else {
            text = shown.joined(separator: ", ")
            if rest > 0 { text += " and \(rest) more" }
        }
        return text
    }

    private static func familyLine(father: String?, brothers: [String]) -> String {
        let fatherText = father.map { L10n.t("أبوه: \($0).", "His father: \($0).") }
            ?? L10n.t("لا أب له في الشجرة.", "No father in the tree.")
        let brothersText = brothers.isEmpty
            ? L10n.t("لا إخوة له مسجّلون تحت أبيه.", "No brothers recorded under his father.")
            : L10n.t("إخوته: \(namesList(brothers)).", "His brothers: \(namesList(brothers)).")
        return fatherText + " " + brothersText
    }

    /// مَن يدخل على أي سجل، وأبوه، وإخوته
    static func linkSentence(applicant: String, record: String, father: String?, brothers: [String]) -> String {
        L10n.t("«\(applicant)» يدخل التطبيق على سجل «\(record)» الموجود في الشجرة.",
               "«\(applicant)» will sign in to the tree record «\(record)».") + " " + familyLine(father: father, brothers: brothers)
    }

    /// نفس الجملة حين يُنشأ له سجل جديد تحت الأب
    static func newRecordSentence(applicant: String, newName: String, father: String, brothers: [String]) -> String {
        L10n.t("يُضاف سجل جديد «\(newName)» في الشجرة، ويدخل «\(applicant)» التطبيق عليه.",
               "A new record «\(newName)» is added to the tree, and «\(applicant)» will sign in to it.")
            + " " + familyLine(father: father, brothers: brothers)
    }

    /// الجملة + التنبيهات — نصّ مربّع التأكيد
    static func confirmText(sentence: String, warnings: [String]) -> String {
        guard !warnings.isEmpty else { return sentence }
        return sentence + "\n\n" + L10n.t("انتبه:", "Careful:") + "\n" + warnings.joined(separator: "\n")
    }
}
