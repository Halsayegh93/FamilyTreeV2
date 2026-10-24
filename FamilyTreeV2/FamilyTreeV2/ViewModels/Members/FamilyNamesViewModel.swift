import Foundation
import Combine
import Supabase

/// قائمة العوائل التي تضعها الإدارة، ويختار منها العضو عائلته.
/// الاسم يُخزَّن نصّاً في `profiles.family_name` — فلو حُذف من القائمة لاحقاً
/// يبقى اسم العضو كما هو ولا يضيع.
nonisolated struct FamilyNameOption: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

/// كتالوج أسماء العوائل المعروفة — يُستخدم لمعرفة إن كانت آخر كلمة في الاسم
/// اسم عائلة (فتُستبدل بالعائلة المختارة) أو اسماً من سلسلة النسب (فتبقى).
/// يُحدَّث عند جلب القائمة ويُحفَظ محلياً ليعمل قبل الجلب وبلا شبكة.
nonisolated enum FamilyNameCatalog {
    private static let key = "familyNamesCatalog.v1"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: Set<String>? = nil

    /// مفتاح مقارنة: بلا مسافات فقط. لا نحذف «ال» عمداً — «محمدعلي» قد يكون
    /// اسم جدّ في السلسلة لا عائلة «المحمدعلي»، فلا نلمسه.
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
    }

    static var known: Set<String> {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let loaded = Set((UserDefaults.standard.stringArray(forKey: key) ?? []).map(normalize))
        cache = loaded
        return loaded
    }

    static func update(_ names: [String]) {
        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        UserDefaults.standard.set(clean, forKey: key)
        lock.lock(); cache = Set(clean.map(normalize)); lock.unlock()
    }

    /// هل الكلمة اسم عائلة؟ (العائلة المختارة نفسها، أو عائلة من القائمة)
    static func isFamilyWord(_ word: String, chosen: String?) -> Bool {
        let w = normalize(word)
        guard !w.isEmpty else { return false }
        if let chosen, normalize(chosen) == w { return true }
        return known.contains(w)
    }

    // MARK: لقب العائلة بين قوسين (طلب المالك ٢٠٢٦-١٠-٢٤ — عائلة العطار)
    // فرع العطار في الشجرة: «علي يوسف حسين ابراهيم(العطار) المحمدعلي». من اختار «العطار» يظهر
    // «علي يوسف حسين العطار»: صاحب اللقب وما بعده يُحذف وتُختم السلسلة بالعائلة. لأي عائلة بين قوسين.

    /// مفتاح مقارنة اللقب: بلا مسافات ولا تشكيل ولا تطويل، وأ إ آ ٱ ← ا، ة ← ه، ى ← ي
    static func nicknameKey(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640: continue           // تشكيل، ألف خنجرية، تطويل
            case 0x0623, 0x0625, 0x0622, 0x0671: out.append("\u{0627}")  // أ إ آ ٱ ← ا
            case 0x0629: out.append("\u{0647}")                          // ة ← ه
            case 0x0649: out.append("\u{064A}")                          // ى ← ي
            default:
                if !CharacterSet.whitespacesAndNewlines.contains(scalar) { out.append(scalar) }
            }
        }
        return String(out)
    }

    private static let nicknameBrackets: [Character: Character] = ["(": ")", "[": "]", "（": "）"]

    /// الوحدات قبل صاحب لقب العائلة «(العائلة)» — nil إن لم يكن في الاسم لقب بهذه العائلة.
    /// صاحب اللقب: الوحدة التي يبدأ القوس داخلها («ابراهيم(العطار)»)، أو التي قبله إن جاء القوس وحده
    /// («ابراهيم (العطار)» نصّاً حرّاً). لو كان الشخص نفسه صاحب اللقب يبقى اسمه الأول بلا القوس.
    static func unitsBeforeNickname(_ units: [String], family: String?) -> [String]? {
        guard let family else { return nil }
        let key = nicknameKey(family)
        guard !key.isEmpty, units.contains(where: { $0.contains(where: { nicknameBrackets[$0] != nil }) }) else {
            return nil
        }
        // الحروف مع رقم وحدتها — المسافة بين وحدتين تُحسب للسابقة، فالقوس أول وحدته = جاء وحده
        var chars: [(ch: Character, unit: Int)] = []
        for (i, unit) in units.enumerated() {
            if i > 0 { chars.append((" ", i - 1)) }
            chars.append(contentsOf: unit.map { ($0, i) })
        }
        var i = 0
        while i < chars.count {
            guard let close = nicknameBrackets[chars[i].ch],
                  let end = chars[(i + 1)...].firstIndex(where: { $0.ch == close }) else { i += 1; continue }
            let inside = String(chars[(i + 1)..<end].map(\.ch))
            guard nicknameKey(inside) == key else { i = end + 1; continue }
            let unit = chars[i].unit
            // ما قبل القوس داخل وحدته (فارغ = القوس أول الوحدة، فاللقب لما قبلها)
            let before = String(chars[..<i].filter { $0.unit == unit }.map(\.ch))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let owner = before.isEmpty ? unit - 1 : unit
            if owner < 0 { return nil }
            if owner == 0 { return [before.isEmpty ? units[0] : before] }
            return Array(units.prefix(owner))
        }
        return nil
    }

    /// كلمات الاسم مع جعل العائلة المختارة آخر كلمة.
    static func words(_ name: String, family: String?) -> [String] {
        var parts = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard let fam = family?.trimmingCharacters(in: .whitespacesAndNewlines), !fam.isEmpty else {
            return parts
        }
        let famWords = fam.split(whereSeparator: \.isWhitespace).map(String.init)
        // لقب العائلة بين قوسين في السلسلة → ما قبل صاحبه + العائلة (بالوحدات حتى لا تنقسم «عبد الله»)
        if name.contains(where: { nicknameBrackets[$0] != nil }),
           let head = unitsBeforeNickname(PersonName.units(name), family: fam) {
            return head.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) } + famWords
        }
        // العائلة موجودة أصلاً في الآخر (ولو كانت أكثر من كلمة) → كما هي
        if parts.count >= famWords.count, Array(parts.suffix(famWords.count)) == famWords { return parts }
        // آخر كلمة اسم عائلة آخر (أو نفس العائلة بصيغة مختلفة) → تُستبدل
        if parts.count > 1, let last = parts.last, isFamilyWord(last, chosen: fam) { parts.removeLast() }
        return parts + famWords
    }

    /// نفس `words` لكن على وحدات الاسم (PersonName — «زين العابدين» وحدة واحدة): للعرض والاختصار.
    static func units(_ units: [String], family: String?) -> [String] {
        var parts = units
        guard let fam = family?.trimmingCharacters(in: .whitespacesAndNewlines), !fam.isEmpty else {
            return parts
        }
        let famWords = fam.split(whereSeparator: \.isWhitespace).map(String.init)
        // لقب العائلة بين قوسين في السلسلة → ما قبل صاحبه + العائلة
        if let head = unitsBeforeNickname(parts, family: fam) { return head + famWords }
        let words = parts.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        // العائلة موجودة أصلاً في الآخر (ولو كانت أكثر من كلمة) → كما هي
        if words.count >= famWords.count, Array(words.suffix(famWords.count)) == famWords { return parts }
        // آخر وحدة اسم عائلة آخر (أو نفس العائلة بصيغة مختلفة) → تُستبدل
        if parts.count > 1, let last = parts.last, isFamilyWord(last, chosen: fam) { parts.removeLast() }
        return parts + famWords
    }

    /// الاسم المكتوب بلا العائلة في آخره — حتى لا تتكرّر عند إضافتها
    static func stripTrailingFamily(_ name: String, chosen: String?) -> String {
        var parts = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count > 1, let last = parts.last, isFamilyWord(last, chosen: chosen) { parts.removeLast() }
        return parts.joined(separator: " ")
    }
}

@MainActor
final class FamilyNamesViewModel: ObservableObject {
    @Published var options: [FamilyNameOption] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseConfig.client
    private let table = "family_names"
    private var didLoad = false

    /// أسماء العوائل الفعّالة فقط — للاختيار في التسجيل وتعديل الملف
    var activeNames: [String] {
        options.filter(\.isActive).map(\.name)
    }

    func fetch(force: Bool = false) async {
        guard force || !didLoad else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [FamilyNameOption] = try await supabase.from(table)
                .select()
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute().value
            options = rows
            didLoad = true
            FamilyNameCatalog.update(rows.map(\.name))
        } catch {
            // الجدول قد لا يكون مُهاجَراً بعد — لا نُفشل الشاشة، لكن نُظهر السبب
            // بدل قائمة فارغة صامتة يستحيل تشخيصها من الجهاز.
            errorMessage = error.localizedDescription
            Log.warning("[FamilyNames] تعذّر الجلب: \(error.localizedDescription)")
        }
    }

    // MARK: - إدارة القائمة (للمالك والمدير — RLS تتكفّل بالتحقق)

    @discardableResult
    func add(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !options.contains(where: { $0.name == trimmed }) else {
            errorMessage = L10n.t("هذه العائلة موجودة مسبقاً.", "This family already exists.")
            return false
        }
        do {
            let payload: [String: AnyEncodable] = [
                "name": AnyEncodable(trimmed),
                "sort_order": AnyEncodable((options.map(\.sortOrder).max() ?? 0) + 1)
            ]
            try await supabase.from(table).insert(payload).execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّرت الإضافة. \(error.localizedDescription)",
                                  "Add failed. \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func rename(id: UUID, to newName: String) async -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await supabase.from(table)
                .update(["name": AnyEncodable(trimmed)])
                .eq("id", value: id.uuidString)
                .execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّر التعديل.", "Rename failed.")
            return false
        }
    }

    /// تعطيل بدل حذف — أعضاء اختاروها سابقاً يحتفظون باسمهم
    @discardableResult
    func setActive(id: UUID, _ active: Bool) async -> Bool {
        do {
            try await supabase.from(table)
                .update(["is_active": AnyEncodable(active)])
                .eq("id", value: id.uuidString)
                .execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّر التحديث.", "Update failed.")
            return false
        }
    }

    @discardableResult
    func delete(id: UUID) async -> Bool {
        do {
            try await supabase.from(table).delete().eq("id", value: id.uuidString).execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّر الحذف.", "Delete failed.")
            return false
        }
    }
}
