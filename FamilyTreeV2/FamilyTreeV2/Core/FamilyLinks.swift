import Foundation

// MARK: - روابط العائلة الرسمية (Guideline 1.5 / 5.1.1)
//
// الموقع وسياسة الخصوصية وشروط الاستخدام والبريد الرسمي — نفس ما هو منشور على
// almohali.com. تُفتح من «الخصوصية والشروط» و«عن التطبيق» في الإعدادات.

enum FamilyLinks {
    /// الموقع الرسمي للعائلة
    static let website = URL(string: "https://almohali.com")!
    /// كما يُعرض للمستخدم (بلا https)
    static let websiteDisplay = "almohali.com"

    /// سياسة الخصوصية — بلغة التطبيق
    static var privacyPolicy: URL {
        URL(string: L10n.isArabic ? "https://almohali.com/privacy/ar" : "https://almohali.com/privacy")!
    }

    /// شروط الاستخدام — بلغة التطبيق
    static var termsOfUse: URL {
        URL(string: L10n.isArabic ? "https://almohali.com/terms/ar" : "https://almohali.com/terms")!
    }

    /// البريد الرسمي المنشور على الموقع
    static let supportEmail = "info@almohali.com"
    static var supportEmailURL: URL { URL(string: "mailto:\(supportEmail)")! }
}
