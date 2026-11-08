import SwiftUI

// MARK: - «المؤشرات» = تقرير الشهر في صفحة القسم (الاتجاه «أ»، موافقة المالك ٢٠٢٦-١١-٠٧)
//
// كانت مربّعات تفتح صفحات (العائلة · الاستخدام · الموافقات). صارت الصفحة نفسها الخلاصة: بطاقة «العائلة» وبطاقة
// «الموافقات» (آخر ٣٠ يوماً)، وكل بطاقة تنتهي بزرّ إلى بيتها الكامل («إحصاءات العائلة» `AdminAnalyticsView` ·
// «تقرير الموافقات» `ApprovalsReportView`). «الاستخدام» خرج من هذا القسم إلى «الفريق والأمان».
// البطاقات في `AdminInsightsReport.swift`، كل واحدة خلف `AnyView` (حارس المكدس)، وروابطها خلف `AdminLazyPage`.
// الظهور من جدول «مين يشوف وش» على السيرفر (`AdminRoleMatrix`، ٢٠٢٦-١١-٠٧): «العائلة» للمالك والمدير والمراقب (أرقام
// الشجرة من مجاله)، و«الموافقات» للمالك والمدير حين يكون مسار الموافقات مفعّلاً.

struct AdminMetricsAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    private var showsApprovals: Bool { adminRequestVM.approvalsWorkflowOn && authVM.adminSees(.metricsApprovals) }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: AdminArea.metrics.title, subtitle: subtitle, isAreaRoot: true)
        } content: {
            if !authVM.adminSees(.metricsFamily) && !showsApprovals {
                DSEmptyView(L10n.t("لا مؤشرات لدورك هنا", "No insights for your role here"), style: .card)
            } else {
                if authVM.adminSees(.metricsFamily) {
                    AnyView(AdminInsightsFamilyCard())
                }
                if showsApprovals {
                    AnyView(AdminInsightsApprovalsCard())
                }
            }
        }
        // ما يُدفع من أزرار البطاقات يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.metrics.title)
    }

    private var subtitle: String {
        showsApprovals ? L10n.t("العائلة والموافقات · آخر 30 يوم", "Family and approvals · last 30 days")
                       : L10n.t("العائلة", "The family")
    }
}
