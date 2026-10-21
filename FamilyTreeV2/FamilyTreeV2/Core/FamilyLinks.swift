import Foundation

// MARK: - روابط العائلة الرسمية (Guideline 1.5 / 5.1.1)
//
// الموقع وسياسة الخصوصية وشروط الاستخدام والبريد الرسمي — نفس ما هو منشور على
// almohali.com. تُفتح من «الخصوصية والشروط» و«عن التطبيق» ومربّع الموافقة على الشروط.

enum FamilyLinks {
    /// الموقع الرسمي للعائلة
    static var website: URL { URL(string: RemoteSettings.text("site_url", "https://almohali.com")) ?? URL(string: "https://almohali.com")! }
    /// كما يُعرض للمستخدم (بلا https)
    static var websiteDisplay: String { website.host ?? "almohali.com" }

    /// سياسة الخصوصية — بلغة التطبيق
    static var privacyPolicy: URL {
        URL(string: RemoteSettings.text(L10n.isArabic ? "privacy_url" : "privacy_url_en", L10n.isArabic ? "https://almohali.com/privacy" : "https://almohali.com/privacy/en")) ?? URL(string: "https://almohali.com/privacy")!
    }

    /// شروط الاستخدام — بلغة التطبيق
    static var termsOfUse: URL {
        URL(string: RemoteSettings.text(L10n.isArabic ? "terms_url" : "terms_url_en", L10n.isArabic ? "https://almohali.com/terms" : "https://almohali.com/terms/en")) ?? URL(string: "https://almohali.com/terms")!
    }

    /// البريد الرسمي المنشور على الموقع
    static var supportEmail: String { RemoteSettings.text("support_email", "info@almohali.com") }
    static var supportEmailURL: URL { URL(string: "mailto:\(supportEmail)")! }
}
