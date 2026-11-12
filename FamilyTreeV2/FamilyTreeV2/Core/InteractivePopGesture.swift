import UIKit
import SwiftUI

/// يعيد تفعيل إيماءة «السحب للرجوع» الأصلية في الشاشات التي تُخفي شريط التنقّل.
///
/// **الخلفية:** الشاشات ذات الهيدر المخصّص تستخدم `.toolbar(.hidden, for: .navigationBar)`
/// حتى لا يظهر عنوانان. لكن UIKit يربط `interactivePopGestureRecognizer` بزر الرجوع،
/// فإخفاء الشريط يُلغي الإيماءة — والمستخدم يفقد الرجوع بالسحب في كل تلك الشاشات.
///
/// الحل: نتولّى نحن مندوب الإيماءة ونسمح لها ما دام في المكدّس أكثر من شاشة.
///
/// **الاتجاه (طلب المالك ٢٠٢٦-١١-١١ «الرجوع بالسحب في أقسام الإدارة مو مضبوط»):** واجهة التطبيق بلغة التطبيق
/// (`LanguageManager` — العربية من اليمين) بينما UIKit يتبع لغة الجهاز؛ في جهاز لغته إنجليزية كان السحب للرجوع من
/// الحافة اليسرى وانتقال الصفحات بعكس سهم الرجوع. نثبّت اتجاه شريط التنقّل نفسه على لغة التطبيق، فيكون الرجوع
/// بالسحب من الحافة اليمنى في العربية — جهة سهم الرجوع — وتنزلق الصفحات بالاتجاه نفسه.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    /// اتجاه التطبيق المختار (لا اتجاه الجهاز)
    private var appIsRTL: Bool { LanguageManager.shared.layoutDirection == .rightToLeft }

    open override func viewDidLoad() {
        let attribute: UISemanticContentAttribute = appIsRTL ? .forceRightToLeft : .forceLeftToRight
        view.semanticContentAttribute = attribute
        navigationBar.semanticContentAttribute = attribute
        super.viewDidLoad()
        applyPopGesture()
    }

    /// SwiftUI قد يعيد ضبط الإيماءة عند الدفع — نعيد تثبيتها حين تظهر الشاشات
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyPopGesture()
    }

    private func applyPopGesture() {
        guard let pop = interactivePopGestureRecognizer else { return }
        if pop.delegate !== self { pop.delegate = self }
        pop.isEnabled = true
        if let edgePan = pop as? UIScreenEdgePanGestureRecognizer {
            edgePan.edges = appIsRTL ? .right : .left
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // شاشة واحدة فقط = لا يوجد ما نرجع إليه
        guard viewControllers.count > 1 else { return false }

        // تقييد البداية بحافة الشاشة: بدون هذا الشرط تبدأ الإيماءة من أي مكان
        // فتتحرّك الصفحة أفقياً أثناء التمرير العادي في وسط الشاشة.
        guard let view = gestureRecognizer.view else { return true }
        let x = gestureRecognizer.location(in: view).x
        let edge: CGFloat = 30
        return appIsRTL ? x > view.bounds.width - edge : x < edge
    }

    /// السماح بالتزامن مع تمرير القوائم حتى لا تتعطّل إحداهما
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// الرجوع من الحافة يسبق سحب صفوف القوائم (أزرار السحب) — يبدأ من الحافة فقط، فلا يؤخّر غيره في وسط الشاشة
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === interactivePopGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer
    }
}
