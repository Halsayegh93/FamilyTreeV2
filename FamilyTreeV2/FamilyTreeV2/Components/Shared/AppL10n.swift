import Foundation

enum L10n {
    static var isArabic: Bool {
        LanguageManager.shared.selectedLanguage == "ar"
    }

    static func t(_ ar: String, _ en: String) -> String {
        isArabic ? ar : en
    }
}
