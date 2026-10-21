import SwiftUI
enum L10n { static func t(_ ar: String, _ en: String) -> String { ar } }
final class LanguageManager { static let shared = LanguageManager(); var layoutDirection: LayoutDirection { .rightToLeft } }
struct AdminReportsView {
    static func fieldTitle(_ f: AdminReportField, kind: AdminReportKind) -> String {
        switch f {
        case .name: return kind == .register ? L10n.t("الاسم الكامل", "Full name") : L10n.t("الاسم", "Name")
        case .branch: return L10n.t("الفرع", "Branch")
        case .birth: return L10n.t("الميلاد", "Birth")
        case .age: return L10n.t("العمر", "Age")
        case .status: return L10n.t("الحالة", "Status")
        case .death: return L10n.t("تاريخ الوفاة", "Death date")
        case .phone: return L10n.t("الهاتف", "Phone")
        case .registration: return L10n.t("التسجيل في التطبيق", "App registration")
        case .anniversary: return L10n.t("الذكرى القادمة", "Next anniversary")
        case .ageAtDeath: return L10n.t("العمر عند الوفاة", "Age at death")
        case .people: return L10n.t("إحصاء الأفراد", "Head count")
        case .ages: return L10n.t("الأعمار", "Ages")
        case .branches: return L10n.t("الفروع", "Branches")
        case .registered: return L10n.t("المسجّلون", "Registered")
        }
    }
}
