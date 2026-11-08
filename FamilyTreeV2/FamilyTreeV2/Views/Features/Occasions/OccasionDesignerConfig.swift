import SwiftUI

// MARK: - «تصميم إعلان» من السيرفر (طلب المالك ٢٠٢٦-١١-٠٨ «كل شي يكون من السيرفر»)
//
// مفتاح واحد `occasion_designer` (JSON) في `app_config()` — غائب أو فاضي = التطبيق كما هو. كل جزء اختياري:
//
// {
//   "order": ["wedding", "newborn", …],                       ← ترتيب الإعلانات (اللي ما يُذكر يجي بعدها بترتيبه)
//   "templates": {
//     "wedding": { "hidden": false, "title": "عقد قران",       ← إخفاء الإعلان أو تغيير اسمه
//                  "models": ["m3", "m4"] }                    ← النماذج المتاحة لهذا الإعلان فقط
//   },
//   "models": {
//     "m1": { "hidden": true },                                 ← إخفاء نموذج من كل الإعلانات
//     "m2": { "title": "نموذج ٢", "subtitle": "…" },
//     "m4": { "title": "نموذج ٤", "subtitle": "…", "layouts": { … } }   ← نموذج ٤ (OccasionModel4View.swift)
//   },
//   "lists": {                                                  ← نصوص الاختيارات (البيانات) — تحل محل المكتوبة في التطبيق
//     "openings.wedding": ["…"],                                ← بالإعلان
//     "duas.newborn.m": ["…"], "duas.newborn.f": ["…"],         ← بالإعلان والجنس (m/f)
//     "deathLeads.m": ["…"],                                    ← بالجنس
//     "cemeteries": ["…"],                                      ← عامة
//     "deathDuas.m": [["العنوان", "النص"], …]                    ← أزواج
//   }
// }
//
// البحث عن قائمة: name.template.gender ← name.template ← name.gender ← name. قائمة فاضية أو غير نصوص = تُتجاهل.
// نموذج ٤ ما يطلع إلا لو له "layouts" على السيرفر. ولو أُخفيت كل النماذج لإعلان، يبقى النموذج المعتمد (نموذج ٣).
enum OccasionDesignerConfig {
    static let key = "occasion_designer"

    private static var root: [String: Any] {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        return AppConfigValues.shared.values[key] as? [String: Any] ?? [:]
    }

    #if DEBUG
    /// تجربة على المحاكي بلا كتابة على السيرفر: متغيّر البيئة OCCASION_DESIGNER_TEST = نفس JSON السيرفر
    private static let debugOverride: [String: Any]? = {
        guard let raw = ProcessInfo.processInfo.environment["OCCASION_DESIGNER_TEST"],
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }()
    #endif

    // MARK: الإعلانات

    private static func templateEntry(_ id: String) -> [String: Any]? {
        (root["templates"] as? [String: Any])?[id] as? [String: Any]
    }

    static func isHidden(template id: String) -> Bool {
        templateEntry(id)?["hidden"] as? Bool ?? false
    }

    static func title(template id: String) -> String? {
        nonEmpty(templateEntry(id)?["title"])
    }

    /// الإعلانات الظاهرة بترتيب السيرفر (إن وُجد)
    static func ordered(_ all: [OccasionTemplate]) -> [OccasionTemplate] {
        let visible = all.filter { !isHidden(template: $0.id) }
        guard let order = root["order"] as? [String], !order.isEmpty else { return visible }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return visible.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset, $1.offset) }
            .map(\.element)
    }

    /// النماذج المسموحة لإعلان (nil = بلا قيد خاص به)
    static func allowedModels(template id: String) -> Set<String>? {
        guard let list = templateEntry(id)?["models"] as? [String], !list.isEmpty else { return nil }
        return Set(list)
    }

    // MARK: النماذج

    private static func modelEntry(_ id: String) -> [String: Any]? {
        (root["models"] as? [String: Any])?[id] as? [String: Any]
    }

    static func isHidden(model id: String) -> Bool {
        modelEntry(id)?["hidden"] as? Bool ?? false
    }

    static func title(model id: String) -> String? { nonEmpty(modelEntry(id)?["title"]) }
    static func subtitle(model id: String) -> String? { nonEmpty(modelEntry(id)?["subtitle"]) }

    /// تصميم نموذج ٤ (nil = ما رُفع بعد، فما يطلع)
    static var model4: OccasionModel4Spec? {
        guard let entry = modelEntry("m4"), !(entry["hidden"] as? Bool ?? false) else { return nil }
        return OccasionModel4Spec(entry)
    }

    // MARK: البيانات (نصوص الاختيارات)

    static func list(_ name: String, template: String? = nil, gender: OccasionGender? = nil) -> [String]? {
        guard let lists = root["lists"] as? [String: Any] else { return nil }
        for k in keys(name, template: template, gender: gender) {
            if let arr = lists[k] as? [Any] {
                let strings = arr.compactMap { $0 as? String }
                if !strings.isEmpty, strings.count == arr.count { return strings }
            }
        }
        return nil
    }

    /// قائمة أزواج [العنوان، النص] (أدعية إعلان العزاء)
    static func pairs(_ name: String, gender: OccasionGender) -> [(String, String)]? {
        guard let lists = root["lists"] as? [String: Any] else { return nil }
        for k in keys(name, template: nil, gender: gender) {
            if let arr = lists[k] as? [[Any]] {
                let out = arr.compactMap { p -> (String, String)? in
                    guard p.count == 2, let a = p[0] as? String, let b = p[1] as? String else { return nil }
                    return (a, b)
                }
                if !out.isEmpty, out.count == arr.count { return out }
            }
        }
        return nil
    }

    private static func keys(_ name: String, template: String?, gender: OccasionGender?) -> [String] {
        let g = gender.map { $0 == .male ? "m" : "f" }
        var out: [String] = []
        if let template, let g { out.append("\(name).\(template).\(g)") }
        if let template { out.append("\(name).\(template)") }
        if let g { out.append("\(name).\(g)") }
        out.append(name)
        return out
    }

    private static func nonEmpty(_ any: Any?) -> String? {
        guard let s = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
