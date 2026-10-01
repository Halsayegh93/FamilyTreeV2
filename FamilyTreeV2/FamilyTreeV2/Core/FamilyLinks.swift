import Foundation

// MARK: - روابط العائلة الرسمية (Guideline 1.5 / 5.1.1)
//
// الموقع وسياسة الخصوصية وشروط الاستخدام والبريد الرسمي — نفس ما هو منشور على
// almohali.com. تُفتح من «الخصوصية والشروط» و«عن التطبيق» ومربّع الموافقة على الشروط.

enum FamilyLinks {
    /// الموقع الرسمي للعائلة
    static let website = URL(string: "https://almohali.com")!
    /// كما يُعرض للمستخدم (بلا https)
    static let websiteDisplay = "almohali.com"

    /// سياسة الخصوصية — بلغة التطبيق
    static var privacyPolicy: URL {
        URL(string: L10n.isArabic ? "https://almohali.com/privacy" : "https://almohali.com/privacy/en")!
    }

    /// شروط الاستخدام — بلغة التطبيق
    static var termsOfUse: URL {
        URL(string: L10n.isArabic ? "https://almohali.com/terms" : "https://almohali.com/terms/en")!
    }

    /// البريد الرسمي المنشور على الموقع
    static let supportEmail = "info@almohali.com"
    static var supportEmailURL: URL { URL(string: "mailto:\(supportEmail)")! }
}
