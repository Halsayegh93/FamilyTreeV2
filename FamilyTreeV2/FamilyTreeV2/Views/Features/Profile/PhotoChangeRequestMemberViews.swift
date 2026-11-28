import SwiftUI

// MARK: - «طلب تغيير الصورة» — جانب العضو من مركز الإشعارات (طلب المالك ٢٠٢٦-١١-١١)
//
// تفاصيل إشعار «طلب تغيير الصورة الشخصية» فيها «تغيير الصورة» ما دام الطلب مفتوحاً، ويفتح مربّع العضو نفسه
// (`PhotoReminderBox(request:)` — مسار تغيير الصورة الواحد) فوق مركز الإشعارات، لأنه قد يكون ورقة فوق التبويبات.
// عند الفتح وبالضغط على الإشعار من خارج التطبيق: `PhotoReminderGate`.

/// زرّ «تغيير الصورة» في مربّع تفاصيل الإشعار — لا يظهر بعد إغلاق الطلب أو إلغائه
struct PhotoChangeRequestNoticeButton: View {
    let onOpen: (PhotoChangeRequest) -> Void
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = PhotoChangeRequestStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if let pending = store.mine, !PhotoChangeRequestStore.isSentForApproval(pending.id) {
                // بلا صورة: طلب «أضف صورتك الشخصية» (P1)
                let adds = authVM.currentUser.map(PhotoReminder.hasNoPhoto) ?? false
                DSButton(adds ? L10n.t("أضف صورة", "Add a photo") : L10n.t("تغيير الصورة", "Change photo"),
                         icon: "camera.fill") {
                    // فُتح المربّع لهذا الإشعار = رآه (لا يظهر مرة ثانية عند الفتح)
                    if let user = authVM.currentUser { PhotoChangeRequestStore.markSeen(pending, userId: user.id) }
                    onOpen(pending)
                }
            }
        }
        .task {
            if let id = authVM.currentUser?.id { await store.refreshMine(userId: id) }
        }
    }
}

/// يعرض مربّع العضو فوق الصفحة التي يُطبَّق عليها (مركز الإشعارات)
struct PhotoChangeRequestPresenter: ViewModifier {
    @Binding var request: PhotoChangeRequest?
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel

    func body(content: Content) -> some View {
        content
            .dsCenterBox(item: $request) { pending in
                if let user = authVM.currentUser {
                    AnyView(PhotoReminderBox(member: user, request: pending, onClose: { request = nil })
                        .environmentObject(memberVM)
                        .environmentObject(adminRequestVM))
                }
            }
    }
}
