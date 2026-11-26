import SwiftUI

// MARK: - بوابة القسم (طلب المالك ٢٠٢٦-١٠-٢٤؛ إعادة التصميم ٢٠٢٦-١١-٢٦، الوحدة U19)
//
// الشرط الواحد `AdminArea.isVisible(for:)`. الأقسام الظاهرة وقائمة العنوان والبحث تقرأ منه فلا تعرض ما ليس لدورك؛
// والبوابة للمداخل الأخرى (مسار محفوظ، إشعار قديم، رابط): صفحة القسم أو صفحة داخلية منه تُفتح لمن يملكها فقط،
// ولغيره رأس القسم ورسالة هادئة بلا أي بيانات (لا يُبنى محتوى الصفحة ولا تُجلب بياناتها).
// الرسالة (`AdminGateLogic`، AdminCatalogLogic.swift): «هذا القسم للمالك فقط» لقسم مقصور على المالك بسقف جدول الأدوار
// («التطبيق»)، وغيره «هذا القسم ليس ضمن صلاحياتك» («الفريق والأمان» يراه المدير). الرفض يمسح الهبوطات المنتظرة
// (`AdminAreaRouter.clearLandings()`) فلا يُعاد هبوط مرفوض لاحقاً.

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

/// رأس القسم ثم سبب الرفض — بلا بيانات
private struct AdminAreaLockedPage: View {
    let area: AdminArea

    /// من سقف جدول الأدوار (`AdminRoleItem.isOwnerOnly`) لا من الدور: «التطبيق» للمالك وحده، والباقي يُفتح لأدوار أخرى
    private var message: AdminGateLogic.Message {
        AdminGateLogic.message(areaKey: area.rawValue,
                               allItemKeys: AdminRoleItem.allCases.map(\.rawValue),
                               ownerOnlyItemKeys: Set(AdminRoleItem.allCases.filter(\.isOwnerOnly).map(\.rawValue)))
    }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: area.title)
        } content: {
            AdminPageStateCard(.empty(message.title, message: message.hint, tint: DS.Color.textTertiary))
        }
        // هبوط هذا الانتقال (فلتر، قسم يُمرَّر إليه) لا يبقى منتظراً بعد الرفض
        .onAppear { AdminAreaRouter.clearLandings() }
    }
}
