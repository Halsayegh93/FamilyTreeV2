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
{"title": "الخصوصية والاستخدام", "subtitle": "سياسة الخصوصية وشروط الاستخدام", "updated": "2026-10-27", "sections": [{"key": "privacy", "title": "بياناتك وخصوصيتك", "items": [{"id": "collect", "title": "ما نجمعه", "lines": ["رقم هاتفك لتسجيل الدخول فقط.", "اسمك وقرابتك وتاريخ الميلاد أو الوفاة لبناء الشجرة.", "وما تختار إضافته بنفسك: صورتك، نبذتك، ديوانيتك، مشروعك."]}, {"id": "why", "title": "لماذا نجمعه", "lines": ["لتعرف العائلة بعضها، ولتعمل الشجرة والأخبار والإشعارات.", "لا إعلانات، ولا بيع لبياناتك، ولا مشاركتها لأي غرض تجاري."]}, {"id": "who", "title": "من يرى بياناتك", "lines": ["أعضاء العائلة المعتمدون فقط داخل التطبيق.", "ويمكنك إخفاء رقمك وبعض معلوماتك من الإعدادات."]}, {"id": "otp", "title": "رمز الدخول", "lines": ["يصلك برسالة نصية (SMS) لمرة واحدة، ولا نرسل عبرها أي محتوى آخر."]}, {"id": "providers", "title": "الخدمات التي نعتمد عليها", "lines": ["نحفظ البيانات والصور على خوادم Supabase.", "والإشعارات عبر Apple و Google، ورسائل الدخول عبر KWT SMS.", "وكلها تستخدم البيانات بقدر تشغيل الخدمة فقط."]}, {"id": "security", "title": "الحماية", "lines": ["اتصال مشفّر، وصلاحيات محددة لكل دور في الإدارة، وحدّ لعدد الأجهزة وحماية من تكرار طلب الرمز."]}, {"id": "delete", "title": "حذف حسابك", "lines": ["من الإعدادات في أي وقت؛ نحذف بياناتك الشخصية خلال ٣٠ يوماً.", "ويبقى اسمك في الشجرة فقط إذا كان ضرورياً لربط العائلة."]}]}, {"key": "terms", "title": "قواعد الاستخدام", "items": [{"id": "eligibility", "title": "لمن التطبيق؟", "lines": ["لأبناء عائلة المحمدعلي ومن توافق عليه الإدارة؛ كل تسجيل يُراجَع قبل التفعيل."]}, {"id": "account", "title": "حسابك مسؤوليتك", "lines": ["لا تشارك رمز الدخول مع أحد، وأبلغنا إن لاحظت دخولاً غريباً."]}, {"id": "respect", "title": "الاحترام أولاً", "lines": ["لا محتوى مسيء، ولا انتحال لشخصية أحد، ولا جمع لبيانات الأعضاء خارج التطبيق."]}, {"id": "content", "title": "ما تضيفه", "lines": ["يبقى ملكك ويظهر للعائلة داخل التطبيق.", "وللإدارة أن تراجعه أو تخفيه إذا خالف هذه القواعد."]}, {"id": "accuracy", "title": "دقة الشجرة", "lines": ["نحرص عليها؛ وإن وجدت خطأً فاطلب تصحيحه من التطبيق."]}, {"id": "updates", "title": "التحديثات", "lines": ["قد نعدّل هذه القواعد، ونعلن التغييرات المهمة داخل التطبيق."]}, {"id": "contact", "title": "التواصل", "lines": ["عبر «تواصل مع الإدارة» في التطبيق، أو البريد الرسمي info@almohali.com."]}]}]}
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
