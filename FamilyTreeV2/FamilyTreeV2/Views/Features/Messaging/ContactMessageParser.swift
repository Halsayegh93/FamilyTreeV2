import Foundation

/// يستخرج حقول الرسالة من admin_requests.details النصي.
///   التصنيف: ...
///   الرسالة: ...
///   وسيلة التواصل: ...
/// يستفيد من new_value كقيمة category مفضّلة (مخزّنة مستقلاً).
enum ContactMessageParser {
    struct Parsed {
        var category: String?
        var message: String?
        var preferredContact: String?
    }

    static func parse(_ msg: AdminRequest) -> Parsed {
        var p = Parsed()
        p.category = msg.newValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let details = msg.details else { return p }
        let lines = details.split(separator: "\n").map { String($0) }
        for line in lines {
            if line.hasPrefix("التصنيف:") {
                if p.category == nil || p.category?.isEmpty == true {
                    p.category = line.replacingOccurrences(of: "التصنيف:", with: "").trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasPrefix("الرسالة:") {
                p.message = line.replacingOccurrences(of: "الرسالة:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("وسيلة التواصل:") {
                p.preferredContact = line.replacingOccurrences(of: "وسيلة التواصل:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // إذا ما فيه "الرسالة:" prefix، اعتبر كل النص رسالة
        if p.message == nil || p.message?.isEmpty == true {
            p.message = details
        }

        return p
    }
}
