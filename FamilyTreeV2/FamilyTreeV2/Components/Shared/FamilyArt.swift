import SwiftUI

// MARK: - رسومات العائلة المتحرّكة
//
// المشاهد الكبيرة في FTTileScenes.swift (مربّعات الرئيسية والصفحات الفاضية) وFTPlaceScenes.swift
// (بطاقة الترحيب، تحميل الشجرة، الانتظار، الإشعارات الفاضية، الدخول). هنا الأغلفة الصغيرة المشتركة.
// «تقليل الحركة»: الرسم ثابت كما هو بلا أي حركة.

// MARK: - الصفحات الفاضية

/// رسمة الحالة الفارغة — لوحة واحدة هادئة (طلب المالك ٢٠٢٦-١٠-٠٥ «أبسط وأقوى وباعتدال»): شعار القسم
/// المصمت (الدلّة، الدكان، الكتاب…) أو رمز الصفحة داخل قرص بلون القسم، يتنفّس ببطء. `FTEmptyScenes`
/// (Components/Shared/FTTileScenes.swift).
struct EmptyStateArt: View {
    let icon: String
    let tint: Color
    /// مشهد القسم بدل الأيقونة (الديوانيات تُعرف من رمزها تلقائياً)
    var kind: FTTileScenes.Kind? = nil

    private var special: FTTileScenes.Kind? {
        if let kind { return kind }
        if icon.hasPrefix("sofa") || icon.contains("mappin") || icon.contains("map") || icon.contains("tent")
            || icon.contains("cup") { return .diwaniya }
        return nil
    }

    private var placeName: String? {
        switch special {
        case .tree?: return "tree"
        case .diwaniya?: return "diwaniya"
        case .library?: return "library"
        case .projects?: return "projects"
        case .contact?: return "contact"
        case nil: return nil
        }
    }

    var body: some View {
        // رسم «مجسّمات» (يرجع دائماً — بلا بديل)
        FT5STrial.empty(place: placeName, icon: icon, tint: tint)
            .frame(width: DS.Icon.emptyArt, height: DS.Icon.emptyArt)
            .accessibilityHidden(true)
    }
}
