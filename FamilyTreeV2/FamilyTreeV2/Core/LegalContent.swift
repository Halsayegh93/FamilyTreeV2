import Foundation
import Combine
import Supabase

/// «الخصوصية والاستخدام» (طلب المالك ٢٠٢٦-١٠-٢٧): النص على السيرفر (`app_config_public()` ← `values.legal_content`،
/// يُقرأ قبل الدخول ويعدّله المالك بلا بناء تطبيق). آخر نسخة تُحفظ على الجهاز، وبلا اتصال أو بنص تالف = النص المدمج.
struct LegalContent: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let lines: [String]
    }
    struct Section: Codable, Equatable, Identifiable {
        let key: String
        let title: String
        let items: [Item]
        var id: String { key }
    }
    let title: String
    let subtitle: String
    let updated: String
    let sections: [Section]

    /// رمز كل نقطة بمعرّفها — المعرّف الجديد بلا رمز = نقطة عامة
    static func icon(for id: String) -> String {
        switch id {
        case "collect": return "tray.full.fill"
        case "why": return "heart.text.square.fill"
        case "who": return "eye.fill"
        case "otp": return "message.fill"
        case "providers": return "server.rack"
        case "security": return "lock.shield.fill"
        case "delete": return "trash.fill"
        case "eligibility": return "person.3.fill"
        case "account": return "key.fill"
        case "respect": return "hand.raised.fill"
        case "content": return "photo.on.rectangle.angled"
        case "accuracy": return "checkmark.seal.fill"
        case "updates": return "arrow.triangle.2.circlepath"
        case "contact": return "envelope.fill"
        default: return "circle.fill"
        }
    }

    /// النص المدمج (نفس الترحيل 20261027120000_legal_content)
    static let builtIn: LegalContent = {
        let json = #"""
{"title": "الخصوصية والاستخدام", "subtitle": "سياسة الخصوصية وشروط الاستخدام", "updated": "2026-10-27", "sections": [{"key": "privacy", "title": "بياناتك وخصوصيتك", "items": [{"id": "collect", "title": "ما نجمعه", "lines": ["رقمك واسمك وقرابتك، وما تضيفه بنفسك."]}, {"id": "why", "title": "لماذا", "lines": ["لتعمل الشجرة والأخبار والإشعارات، بلا إعلانات ولا بيع."]}, {"id": "who", "title": "من يراها", "lines": ["أعضاء العائلة المعتمدون فقط، ولك إخفاء رقمك."]}, {"id": "otp", "title": "رمز الدخول", "lines": ["رسالة نصية لمرة واحدة، لا غير."]}, {"id": "security", "title": "الحماية", "lines": ["اتصال مشفّر، وخوادم Supabase لحفظ البيانات."]}, {"id": "delete", "title": "حذف حسابك", "lines": ["من الإعدادات، وتُحذف بياناتك خلال ٣٠ يوماً."]}]}, {"key": "terms", "title": "قواعد الاستخدام", "items": [{"id": "eligibility", "title": "لمن التطبيق", "lines": ["لعائلة المحمدعلي ومن توافق عليه الإدارة."]}, {"id": "account", "title": "حسابك", "lines": ["لا تشارك رمز الدخول مع أحد."]}, {"id": "respect", "title": "الاحترام", "lines": ["لا إساءة ولا انتحال ولا نشر لبيانات الأعضاء."]}, {"id": "content", "title": "ما تضيفه", "lines": ["ملكك، وللإدارة إخفاؤه إن خالف القواعد."]}, {"id": "contact", "title": "التواصل", "lines": ["«تواصل مع الإدارة» في التطبيق، أو info@almohali.com"]}]}]}
"""#
        return (try? JSONDecoder().decode(LegalContent.self, from: Data(json.utf8)))
            ?? LegalContent(title: "الخصوصية والاستخدام", subtitle: "سياسة الخصوصية وشروط الاستخدام", updated: "", sections: [])
    }()
}

@MainActor
final class LegalContentStore: ObservableObject {
    static let shared = LegalContentStore()
    private static let cacheKey = "legalContent.v1"

    @Published private(set) var content: LegalContent

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(LegalContent.self, from: data), !cached.sections.isEmpty {
            content = cached
        } else {
            content = .builtIn
        }
    }

    /// جلب النسخة الحية — أي خطأ يُبقي المحفوظ
    func refresh() async {
        struct Envelope: Decodable {
            struct Values: Decodable { let legal_content: LegalContent? }
            let values: Values?
        }
        guard let env: Envelope = try? await SupabaseConfig.client.rpc("app_config_public").execute().value,
              let fresh = env.values?.legal_content, !fresh.sections.isEmpty else { return }
        content = fresh
        if let data = try? JSONEncoder().encode(fresh) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }
}
