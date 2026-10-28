import SwiftUI

// MARK: - بوابة القسم (طلب المالك ٢٠٢٦-١٠-٢٤: «التطبيق» و«الفريق والأمان» للمالك فقط، و«المؤشرات» ليست للمراقب)
//
// الشرط الواحد `AdminArea.isVisible(for:)`. الأقسام الظاهرة وقائمة العنوان والبحث تقرأ منه فلا تعرض ما ليس لدورك؛
// والبوابة للمداخل الأخرى (مسار محفوظ، إشعار قديم، رابط): صفحة القسم أو صفحة داخلية منه تُفتح لمن يملكها فقط،
// ولغيره رأس القسم ورسالة هادئة بلا أي بيانات (لا يُبنى محتوى الصفحة ولا تُجلب بياناتها).

struct AdminAreaGate: View {
    let area: AdminArea
    let page: () -> AnyView
    @EnvironmentObject private var authVM: AuthViewModel

    init(area: AdminArea, page: @escaping () -> AnyView) {
        self.area = area
        self.page = page
    }

    var body: some View {
        if area.isVisible(for: authVM) {
            page()
        } else {
            AnyView(AdminAreaLockedPage(area: area))
        }
    }
}

/// رأس القسم ثم «هذا القسم للمالك فقط» — بلا بيانات
private struct AdminAreaLockedPage: View {
    let area: AdminArea

    private var message: String {
        switch area {
        case .team, .app:
            return L10n.t("هذا القسم للمالك فقط.", "This section is for the owner only.")
        default:
            return L10n.t("هذا القسم غير متاح لدورك.", "This section isn't available for your role.")
        }
    }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: area.title)
        } content: {
            AdminPageStateCard(.empty(message, message: L10n.t("صلاحياتك في «صلاحياتي» أسفل «اليوم».",
                                                              "Your permissions are under “My permissions” on Today."),
                                      tint: DS.Color.textTertiary))
        }
    }
}
