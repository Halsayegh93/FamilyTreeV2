import Foundation

// MARK: - «دمج» في «المكرر والأخطاء» — المنطق الخالص (موافقة المالك ٢٠٢٦-١١-٢٧، «حط زر دمج لكل اسم واحد»)
//
// زرّ «دمجه في الآخر» على كل شخص في مجموعة مكرّرة = هذا الاسم هو الذي يُحذف ويُدمج في الآخر (إن كانوا ثلاثة فأكثر يُسأل:
// في أيّهم؟). من له حساب دخول لا يُحذف — لا زرّ على صفّه، ولا زرّ حيث يرفض السيرفر (متوفى وحيّ، أو ميلادان بينهما أكثر من
// سنتين — `compatible`). السيرفر يحرس الشيء نفسه (`merge_duplicate_members`، 20261127240000 + 20261127270000) ويحسب ما
// ينتقل بمعاينة (`p_dry_run`) قبل التأكيد.
// فحصه بلا محاكي: tests/admin-redesign/M3.

nonisolated enum AdminMergeRules {

    // MARK: من يُدمج في من

    /// هل يظهر «دمج» على هذا الصفّ؟ (المالك والمدير، ومن بلا حساب دخول، وقائمة الحسابات وصلت)
    static func canRemove(hasLogin: Bool, isStaff: Bool, accountsReady: Bool) -> Bool {
        accountsReady && !hasLogin && !isStaff
    }

    /// نصّ الزرّ على الصفّ — «دمجه» = هذا الاسم يُحذف، لا «يبقى هذا»
    static let removeButtonTitle = "دمجه في الآخر"

    /// من يمكن الدمج فيه: الباقون في المجموعة بترتيبها (المُبقى قد يكون له حساب) — بلا أحد من الإدارة، وبلا من يرفضه
    /// السيرفر مع المحذوف (`compatible`؛ `facts` الغائب = لا يُعرف فيُسمح).
    /// فارغ = لا دمج (المحذوف له حساب أو لا أحد غيره يصلح)
    static func targets(group: [UUID], remove: UUID, hasLogin: Set<UUID>, staff: Set<UUID> = [],
                        facts: [UUID: Facts] = [:]) -> [UUID] {
        guard group.contains(remove), !hasLogin.contains(remove), !staff.contains(remove) else { return [] }
        return group.filter { id in
            guard id != remove, !staff.contains(id) else { return false }
            guard let r = facts[remove], let k = facts[id] else { return true }
            return compatible(r, k)
        }
    }

    // MARK: حراس السيرفر (20261127270000) — القاعدة نفسها لإخفاء الزرّ

    /// ما يقارنه السيرفر قبل الدمج
    struct Facts: Equatable {
        var deceased: Bool
        var birthYear: Int?
    }

    /// `hint` الرفض كما يرفعه السيرفر — الوفاة أولاً ثم الميلاد؛ nil = يُسمح
    static func refusalHint(_ a: Facts, _ b: Facts) -> String? {
        if a.deceased != b.deceased { return "deceased_mismatch" }
        if let x = a.birthYear, let y = b.birthYear, abs(x - y) > 2 { return "birth_mismatch" }
        return nil
    }

    static func compatible(_ a: Facts, _ b: Facts) -> Bool { refusalHint(a, b) == nil }

    /// سنة الميلاد من «yyyy-MM-dd» — nil بلا ميلاد صالح
    static func year(fromBirthDate raw: String?) -> Int? {
        guard let raw, raw.count >= 4, let y = Int(raw.prefix(4)), y > 1000 else { return nil }
        return y
    }

    /// ثلاثة فأكثر: يُسأل «يُدمج في أيّهم؟»، واثنان: الآخر مباشرة
    static func needsTargetChoice(_ targets: [UUID]) -> Bool { targets.count > 1 }

    // MARK: المعاينة («ينتقل: …»)

    struct Preview: Equatable {
        var tree: String = "men"
        var children = 0
        var daughters = 0
        var wives = 0
        /// شجرة النساء: من يشير لها زوجاً (`moved_husbands`)
        var husbands = 0
        var women = 0
        var filled: [String] = []
        var conflicts: [String] = []
        var notMoved: [String] = []
        /// صفوف بقيت مع المحذوف لتعارض فريد (للمُبقى صفّ مثلها) — `not_moved` كـ {table, count}
        var notMovedRows: [Rows] = []

        struct Rows: Equatable {
            let table: String
            let count: Int
        }

        var isWomenTree: Bool { tree == "women" }
    }

    /// نتيجة `merge_duplicate_members` (jsonb) — nil إن لم تكن كائناً
    static func preview(from data: Data) -> Preview? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func int(_ k: String) -> Int { (root[k] as? NSNumber)?.intValue ?? 0 }
        func strings(_ k: String) -> [String] { (root[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
        let rows: [Preview.Rows] = (root["not_moved"] as? [Any])?.compactMap { item in
            guard let o = item as? [String: Any], let t = o["table"] as? String,
                  let n = (o["count"] as? NSNumber)?.intValue, n > 0 else { return nil }
            return Preview.Rows(table: t, count: n)
        } ?? []
        let conflicts = (root["conflicts"] as? [[String: Any]])?.compactMap { $0["field"] as? String } ?? []
        var seen = Set<String>()
        return Preview(tree: root["tree"] as? String ?? "men",
                       children: int("moved_children"), daughters: int("moved_daughters"),
                       wives: int("moved_wives"), husbands: int("moved_husbands"), women: int("moved_women"),
                       filled: strings("filled"), conflicts: conflicts.filter { seen.insert($0).inserted },
                       notMoved: strings("not_moved"), notMovedRows: rows)
    }

    /// اسم الحقل بالعربية الرسمية
    static func fieldName(_ field: String) -> String? {
        switch field {
        case "birth_date": return "تاريخ الميلاد"
        case "death_date": return "تاريخ الوفاة"
        case "is_deceased": return "الوفاة"
        case "mother_id": return "الأم"
        case "husband_id": return "الزوج"
        case "family_name": return "اسم العائلة"
        case "avatar_url": return "الصورة"
        case "is_married": return "الحالة الاجتماعية"
        case "phone_number": return "رقم الهاتف"
        default: return nil
        }
    }

    static func sons(_ n: Int) -> String? {
        switch n {
        case ..<1: return nil
        case 1: return "ابن واحد"
        case 2: return "ابنان"
        case 3...10: return "\(n) أبناء"
        default: return "\(n) ابناً"
        }
    }

    static func daughters(_ n: Int) -> String? {
        switch n {
        case ..<1: return nil
        case 1: return "بنت واحدة"
        case 2: return "بنتان"
        case 3...10: return "\(n) بنات"
        default: return "\(n) بنتاً"
        }
    }

    static func wives(_ n: Int) -> String? {
        switch n {
        case ..<1: return nil
        case 1: return "الزوجة"
        case 2: return "زوجتان"
        default: return "\(n) زوجات"
        }
    }

    static func husbands(_ n: Int) -> String? {
        switch n {
        case ..<1: return nil
        case 1: return "الزوج"
        case 2: return "زوجان"
        default: return "\(n) أزواج"
        }
    }

    /// «ينتقل: 3 أبناء، بنت واحدة، الزوجة، تاريخ الميلاد» — أو «لا ينتقل شيء؛ الاسم مكرر فقط.»
    /// شجرة النساء: الأبناء والبنات منفصلون، والزوج (من يشير لها، أو زوجها الفارغ يُملأ) مرة واحدة
    static func movesLine(_ p: Preview) -> String {
        var parts: [String] = []
        if let s = sons(p.children) { parts.append(s) }
        if let d = daughters(p.daughters) { parts.append(d) }
        if p.isWomenTree {
            if let h = husbands(p.husbands) { parts.append(h) }
        } else if let w = wives(p.wives) {
            parts.append(w)
        }
        for name in p.filled.compactMap(fieldName) where !parts.contains(name) { parts.append(name) }
        guard !parts.isEmpty else { return "لا ينتقل شيء؛ الاسم مكرر فقط." }
        return "ينتقل: " + parts.joined(separator: "، ")
    }

    /// «يختلفان في: تاريخ الميلاد. تبقى قيمة الاسم الباقي.» — nil بلا اختلاف
    static func conflictsLine(_ p: Preview) -> String? {
        let names = p.conflicts.compactMap(fieldName)
        guard !names.isEmpty else { return nil }
        return "يختلفان في: \(names.joined(separator: "، ")). تبقى قيمة الاسم الباقي."
    }

    /// اسم الجدول بالعربية لما لم ينتقل من صفوفه (الجداول ذات المفتاح الفريد على العضو)
    static func tableName(_ table: String) -> String {
        switch table {
        case "news_poll_votes": return "تصويتات الاستطلاعات"
        case "family_story_views": return "مشاهدات القصص"
        case "admin_message_reads": return "قراءات الرسائل"
        case "app_usage_member_day": return "سجل الاستخدام"
        case "profile_edit_counts": return "عدّاد تعديلات الملف"
        case "member_blocks": return "الحظر بين الأعضاء"
        case "device_tokens": return "الأجهزة"
        case "device_revocations": return "سجل فكّ الأجهزة"
        case "web_sessions": return "جلسات الموقع"
        case "daughter_son_lineage": return "نسب ابن البنت"
        case "photo_change_requests": return "طلبات تغيير الصورة"
        case "branch_supervisors": return "مشرفو الفروع"
        case "guardian_consents": return "موافقات وليّ الأمر"
        case "death_marks": return "علامات الوفاة"
        case "death_announcements": return "إعلانات الوفاة"
        default: return "سجلات أخرى"
        }
    }

    /// «لا ينتقل: رقم الهاتف، تصويتات الاستطلاعات (2).» — nil إن لم يبقَ شيء
    static func notMovedLine(_ p: Preview) -> String? {
        let names = p.notMoved.compactMap(fieldName) + p.notMovedRows.map { "\(tableName($0.table)) (\($0.count))" }
        guard !names.isEmpty else { return nil }
        return "لا ينتقل: \(names.joined(separator: "، "))."
    }

    static let deleteNote = "يُحذف الاسم المكرر نهائياً."

    // MARK: الأخطاء

    /// رسالة رسمية لكل `hint` من السيرفر
    static func message(hint: String?) -> String {
        switch hint {
        case "not_allowed": return "الدمج متاح للمالك والمدير فقط."
        case "same_member": return "اختر اسمين مختلفين."
        case "not_found": return "أحد الاسمين لم يعد موجوداً. حدّث القائمة ثم حاول مرة أخرى."
        case "not_same_tree": return "لا يمكن دمج اسمين من شجرتين مختلفتين."
        case "different_father": return "لا يمكن الدمج؛ الاسمان ليسا تحت الأب نفسه."
        case "staff_member": return "لا يمكن دمج سجل أحد أعضاء الإدارة."
        case "remove_has_login": return "الاسم المراد حذفه مرتبط بحساب دخول، فلا يمكن حذفه. ادمج الاسم الآخر فيه بدلاً من ذلك."
        case "both_have_login": return "كلا الاسمين مرتبط بحساب دخول، فلا يمكن دمجهما."
        case "deceased_mismatch": return "لا يمكن دمج متوفى في حيّ — قد يكونان أخوين بنفس الاسم."
        case "birth_mismatch": return "لا يمكن الدمج؛ سنتا الميلاد متباعدتان، وقد يكونان أخوين بنفس الاسم."
        case "family_links_protected": return "تعذّر الدمج لأن أحد أفراد العائلة ما زال مرتبطاً بالاسم المكرر. حاول مرة أخرى."
        default: return "تعذّر الدمج. تحقّق من الاتصال ثم حاول مرة أخرى."
        }
    }

    /// فشل حفظ «ليسا مكرّرين» على السيرفر — تعود المجموعة ويظهر هذا
    static let dismissFailedMessage = "تعذّر حفظ «ليسا مكرّرين». تحقّق من الاتصال ثم حاول مرة أخرى."
}
