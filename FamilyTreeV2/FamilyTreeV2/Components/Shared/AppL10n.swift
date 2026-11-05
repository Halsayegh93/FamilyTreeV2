import Foundation

nonisolated enum L10n {
    /// نقرأ اللغة من UserDefaults مباشرة (nonisolated) بدل المرور على
    /// `LanguageManager.shared.selectedLanguage` المعزول بـ MainActor (بسبب
    /// @AppStorage). هذا يسمح باستدعاء L10n من أي سياق (Codable init, models…)
    /// بدون تحذيرات/أخطاء عزل التزامن، ونفس المفتاح "selectedLanguage" يعطي نفس القيمة.
    static var isArabic: Bool {
        (UserDefaults.standard.string(forKey: "selectedLanguage") ?? "ar") == "ar"
    }

    static func t(_ ar: String, _ en: String) -> String {
        isArabic ? ar : en
    }

    /// نصّ يُحفظ في السيرفر ويقرؤه غير المرسل (الإشعارات): لغة واحدة، لا لغة جهاز المرسل.
    /// كان عضو تطبيقه بالإنجليزية يرسل للإدارة «Child Add Request». الإنجليزي يبقى مرجعاً في مكان النداء.
    static func stored(_ ar: String, _ en: String) -> String { ar }
}
