import Foundation

// MARK: - «دمج» في «المكرر والأخطاء» — المنطق الخالص (موافقة المالك ٢٠٢٦-١١-٢٧، «حط زر دمج لكل اسم واحد»)
//
// زرّ «دمج» على كل شخص في مجموعة مكرّرة = هذا الاسم هو الذي يُحذف ويُدمج في الآخر (إن كانوا ثلاثة فأكثر يُسأل: في أيّهم؟).
// من له حساب دخول لا يُحذف — لا زرّ على صفّه. السيرفر يحرس الشيء نفسه (`merge_duplicate_members`،
// 20261127240000) ويحسب ما ينتقل بمعاينة (`p_dry_run`) قبل التأكيد.
// فحصه بلا محاكي: tests/admin-redesign/M3.

nonisolated enum AdminMergeRules {

    // MARK: من يُدمج في من

    /// هل يظهر «دمج» على هذا الصفّ؟ (المالك والمدير، ومن بلا حساب دخول، وقائمة الحسابات وصلت)
    static func canRemove(hasLogin: Bool, isStaff: Bool, accountsReady: Bool) -> Bool {
        accountsReady && !hasLogin && !isStaff
    }

    /// من يمكن الدمج فيه: الباقون في المجموعة بترتيبها (المُبقى قد يكون له حساب) — بلا أحد من الإدارة.
    /// فارغ = لا دمج (المحذوف له حساب أو لا أحد غيره)
    static func targets(group: [UUID], remove: UUID, hasLogin: Set<UUID>, staff: Set<UUID> = []) -> [UUID] {
        guard group.contains(remove), !hasLogin.contains(remove), !staff.contains(remove) else { return [] }
        return group.filter { $0 != remove && !staff.contains($0) }
    }

    /// ثلاثة فأكثر: يُسأل «يُدمج في أيّهم؟»، واثنان: الآخر مباشرة
    static func needsTargetChoice(_ targets: [UUID]) -> Bool { targets.count > 1 }

    // MARK: المعاينة («ينتقل: …»)

    struct Preview: Equatable {
        var tree: String = "men"
        var children = 0
        var daughters = 0
        var wives = 0
        var women = 0
        var filled: [String] = []
        var conflicts: [String] = []
        var notMoved: [String] = []

        var isWomenTree: Bool { tree == "women" }
    }

    /// نتيجة `merge_duplicate_members` (jsonb) — nil إن لم تكن كائناً
    static func preview(from data: Data) -> Preview? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func int(_ k: String) -> Int { (root[k] as? NSNumber)?.intValue ?? 0 }
        func strings(_ k: String) -> [String] { (root[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
        let conflicts = (root["conflicts"] as? [[String: Any]])?.compactMap { $0["field"] as? String } ?? []
        var seen = Set<String>()
        return Preview(tree: root["tree"] as? String ?? "men",
                       children: int("moved_children"), daughters: int("moved_daughters"),
                       wives: int("moved_wives"), women: int("moved_women"),
                       filled: strings("filled"), conflicts: conflicts.filter { seen.insert($0).inserted },
                       notMoved: strings("not_moved"))
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

    /// «ينتقل: 3 أبناء، الزوجة، تاريخ الميلاد» — أو «لا ينتقل شيء؛ الاسم مكرر فقط.»
    static func movesLine(_ p: Preview) -> String {
        var parts: [String] = []
        if let s = sons(p.children) { parts.append(s) }
        if !p.isWomenTree {
            if let d = daughters(p.daughters) { parts.append(d) }
            if let w = wives(p.wives) { parts.append(w) }
        }
        parts += p.filled.compactMap(fieldName)
        guard !parts.isEmpty else { return "لا ينتقل شيء؛ الاسم مكرر فقط." }
        return "ينتقل: " + parts.joined(separator: "، ")
    }

    /// «يختلفان في: تاريخ الميلاد. تبقى قيمة الاسم الباقي.» — nil بلا اختلاف
    static func conflictsLine(_ p: Preview) -> String? {
        let names = p.conflicts.compactMap(fieldName)
        guard !names.isEmpty else { return nil }
        return "يختلفان في: \(names.joined(separator: "، ")). تبقى قيمة الاسم الباقي."
    }

    /// «لا ينتقل: رقم الهاتف.» — nil إن لم يبقَ شيء
    static func notMovedLine(_ p: Preview) -> String? {
        let names = p.notMoved.compactMap(fieldName)
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
        case "family_links_protected": return "تعذّر الدمج لأن أحد أفراد العائلة ما زال مرتبطاً بالاسم المكرر. حاول مرة أخرى."
        default: return "تعذّر الدمج. تحقّق من الاتصال ثم حاول مرة أخرى."
        }
    }
}
