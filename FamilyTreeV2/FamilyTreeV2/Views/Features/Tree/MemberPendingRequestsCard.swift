import SwiftUI

// MARK: - «طلبات معلّقة» في تفاصيل العضو — شجرة الرجال وشجرة النساء
//
// طلب المالك ٢٠٢٦-١١-٢٦: «الطلبات في تفاصيل العضو نفس وضعها القديم بس تكون ارتباط واضح بالوارد».
// البطاقة والصفوف كما كانت في `MemberDetailsView` (العنوان، الأيقونة واللون حسب الإجراء، «قيد المراجعة»).
// الجديد: لمن يقرّر طلبات الشجرة (`canModerateTree`) كل صفّ زرّ يغلق المربّع ويفتح الطلب نفسه في «الوارد»
// (`.openAdminReviewForKind` + `request_id` ← `AdminAllRequestsView(focusId:)`، وفوقه سطر «الوارد ‹ القسم ‹ النوع»)،
// وفي طرفه «في الوارد ‹» بدل «معلّق»، وتحت الصفوف سطر يقول ذلك. صاحب الطلب والمشرف يرونها كما كانت (بلا رابط).

enum MemberPendingRequestsLink {
    /// يغلق المربّع (فوق تبويب الشجرة) ثم يفتح «الوارد» على الطلب — نفس طريق «افتح الطلب» في مركز الإشعارات:
    /// التبويب أولاً (قد لا يكون مبنياً بعد)، ثم الطلب بعد أن يستمع «اليوم»
    static func open(_ request: AdminRequest, dismiss: () -> Void) {
        dismiss()
        let info: [String: Any] = ["kind": request.requestType, "request_id": request.id.uuidString]
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) {
            NotificationCenter.default.post(name: .openAdminRequests, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: .openAdminReviewForKind, object: nil, userInfo: info)
            }
        }
    }
}

// البطاقة نفسها صارت `MemberCardRequestsSection` (MemberCardAB.swift، شكل «AB» ٢٠٢٦-١١-٢٧): «طلبك عنه» للعضو والمشرف،
// والقائمة كاملة لمن يقرّر طلبات الشجرة بهذا الرابط.
