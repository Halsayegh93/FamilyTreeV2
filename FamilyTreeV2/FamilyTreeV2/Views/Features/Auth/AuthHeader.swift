import SwiftUI

/// رأس شاشات المصادقة (خطوة الرمز، الانتظار) — صار الرأس الملوّن الموحّد للصفحات الفرعية
/// (`DSSubPageHeader`: تدرّج القسم + مجسّم + عنوان ووصف + زرّ الرجوع الموحّد) بدل نسخة يدوية
/// رابعة بأيقونة مسطّحة وشريط سدو قديم. خارج التبويبات القسم = الرئيسية (كحلي العلامة).
extension View {
    func authHeader(
        icon: String,
        title: String,
        subtitle: String,
        /// وجود زرّ الإجراء — الرجوع الموحّد في بداية السطر (خطوة الرمز)
        actionIcon: String? = nil,
        /// نص القارئ الصوتي — زرّ الرجوع الموحّد يقرأ «رجوع»
        actionLabel: String = L10n.t("رجوع", "Back"),
        action: (() -> Void)? = nil
    ) -> some View {
        DSSubPageHeader(title: title, subtitle: subtitle, icon: icon,
                        nav: (actionIcon != nil && action != nil) ? .back : .none,
                        onBack: action)
    }
}
