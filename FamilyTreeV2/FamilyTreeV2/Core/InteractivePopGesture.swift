import UIKit

/// يعيد تفعيل إيماءة «السحب للرجوع» الأصلية في الشاشات التي تُخفي شريط التنقّل.
///
/// **الخلفية:** الشاشات ذات الهيدر المخصّص تستخدم `.toolbar(.hidden, for: .navigationBar)`
/// حتى لا يظهر عنوانان. لكن UIKit يربط `interactivePopGestureRecognizer` بزر الرجوع،
/// فإخفاء الشريط يُلغي الإيماءة — والمستخدم يفقد الرجوع بالسحب في كل تلك الشاشات.
///
/// الحل: نتولّى نحن مندوب الإيماءة ونسمح لها ما دام في المكدّس أكثر من شاشة.
extension UINavigationController: UIGestureRecognizerDelegate {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // شاشة واحدة فقط = لا يوجد ما نرجع إليه
        guard viewControllers.count > 1 else { return false }

        // تقييد البداية بحافة الشاشة: بدون هذا الشرط تبدأ الإيماءة من أي مكان
        // فتتحرّك الصفحة أفقياً أثناء التمرير العادي في وسط الشاشة.
        guard let view = gestureRecognizer.view else { return true }
        let x = gestureRecognizer.location(in: view).x
        let edge: CGFloat = 30
        let isRTL = UIView.userInterfaceLayoutDirection(for: view.semanticContentAttribute) == .rightToLeft
        return isRTL ? x > view.bounds.width - edge : x < edge
    }

    /// السماح بالتزامن مع تمرير القوائم حتى لا تتعطّل إحداهما
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
