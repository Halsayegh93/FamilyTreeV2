import Foundation
import Supabase

/// فلتر الكلمات غير اللائقة على السيرفر (٢٠٢٦-١٠-٢٩): الأخبار والتعليقات والاستطلاعات، الديوانيات، المشاريع،
/// النبذة، المكتبة، تعليقات الصور والقصص — يرفض بـ P0001 و`hint = objectionable`. النص من
/// `app_config.blocked_words_message_general` (يغيّره المالك بلا بناء تطبيق)، وإلا البديل المكتوب هنا.
enum ObjectionableText {
    static let hint = "objectionable"

    /// هل رفض السيرفر النص لكلمة غير لائقة؟
    static func isObjectionable(_ error: Error) -> Bool {
        (error as? PostgrestError)?.hint == hint
    }

    /// الرسالة للمستخدم
    @MainActor static var message: String {
        AppConfigValues.shared.string("blocked_words_message_general")
            ?? L10n.t("النص يحتوي على كلمات غير لائقة، عدّله وحاول مرة أخرى.",
                      "The text contains inappropriate words. Edit it and try again.")
    }

    /// الرسالة إن كان الخطأ رفضاً للنص، وإلا nil — `errorMessage = ObjectionableText.message(for: error) ?? …`
    @MainActor static func message(for error: Error) -> String? {
        isObjectionable(error) ? message : nil
    }

    /// للشاشات التي لا تعرض خطأ الحفظ: رسالة مستقلّة إن كان رفضاً للنص. true = عُرضت
    @MainActor @discardableResult
    static func presentIfObjectionable(_ error: Error) -> Bool {
        guard isObjectionable(error) else { return false }
        DSStandaloneAlert.show(title: L10n.t("تعذّر الحفظ", "Couldn't Save"), message: message)
        return true
    }
}
