import SwiftUI

// MARK: - «مكانه في الشجرة» في «إشعارات الإدارة» (§7، طلب المالك ٢٠٢٦-١١-١٣ «خلّه يبيّن بعد في إشعارات الإدارة»)
//
// نفس القسم والمعاينة: إشعار تغيير تمّ (`AdminNoticeDetailBox`) بصيغة الماضي، وإشعار طلب (`NotificationDetailBox`) من
// الطلب نفسه بزمن نتيجته — وإلا تعريف بالعضو المعني. كل منهما نوع صغير مستقل (حارس المكدس)، والقسم بشكل المربّع
// المسطّح (عنوان صغير بلا بطاقة) مثل بقية أقسام مربّع الإشعار.

/// إشعار تغيير تمّ (إضافة، تعديل، حذف) — بعد بطاقة الشخص وقبل «تغييرات الإدارة/العضو»
struct TreePlaceNoticeSection: View {
    let notification: AppNotification
    @EnvironmentObject private var memberVM: MemberViewModel

    var body: some View {
        if let place = TreePlace.notice(notification) {
            TreePlaceSection(place: place, men: memberVM.allMembers, backTitle: TreePlaceText.backToNotice)
                .environment(\.dsFlatComposerSections, true)
        }
    }
}

/// إشعار طلب (للإدارة): من الطلب المحمّل بزمن نتيجته، أو من حمولة التغيير، وإلا تعريف بالعضو المعني.
/// زرّ المعاينة الرئيسي = «موافقة» المربّع نفسه حين يظهر فيه (طلب معلّق تملك قراره)، وإلا «العودة إلى الإشعار» وحده
struct TreePlaceRequestNoticeSection: View {
    let notification: AppNotification
    let request: AdminRequest?
    /// إشعار طلب (له معرّف طلب — لا الانضمام/الربط)
    let isRequestNotice: Bool
    let subjectMember: FamilyMember?
    var primary: TreePlacePrimary? = nil
    @EnvironmentObject private var memberVM: MemberViewModel

    private var place: TreePlace? {
        let data = TreePlaceData(men: memberVM.allMembers, women: WomenStore.cache)
        if let request { return TreePlace.fromRequest(request, data: data) }
        if let p = TreePlace.notice(notification) { return p }
        guard isRequestNotice, let m = subjectMember else { return nil }
        return TreePlace.subject(memberId: m.id, kindLabel: notification.title, data: data)
    }

    var body: some View {
        if let place {
            TreePlaceSection(place: place, men: memberVM.allMembers, primary: primary,
                             backTitle: TreePlaceText.backToNotice)
                .environment(\.dsFlatComposerSections, true)
        }
    }
}
