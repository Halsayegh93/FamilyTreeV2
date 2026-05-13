import SwiftUI

/// UIScrollView wrapper يحفظ موضع السكرول عند تغيّر المحتوى.
/// يحل مشكلة iOS 16 حيث SwiftUI ScrollView يرجع للأعلى عند تغيّر @State،
/// وكذلك عندما يُغلق sheet داخلي ويُعيد iOS layout للـscrollView.
///
/// الحلّ: نتتبّع آخر موقع scroll من المستخدم (عبر UIScrollViewDelegate)،
/// نحفظه في الـCoordinator، ثم نُعيد تطبيقه في كل layout pass — لأن iOS
/// قد يُعيد contentOffset إلى 0 بعد أحداث معيّنة (sheet dismiss، keyboard)
/// مما يجعل قراءة scrollView.contentOffset في updateUIView غير موثوقة.
struct StableScrollView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .scrollableAxes
        scrollView.delegate = context.coordinator

        let hosting = UIHostingController(rootView: AnyView(content))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosting.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        context.coordinator.hostingController = hosting
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = AnyView(content)
        // أعد تطبيق الـoffset المحفوظ من الـCoordinator (مصدر الحقيقة)
        // مرتين: الأولى فوراً، والثانية في الـrunloop التالي عشان نتغلّب
        // على layout passes اللي يفعلها iOS بعد sheet dismiss / keyboard hide.
        context.coordinator.restoreOffset()
        DispatchQueue.main.async {
            context.coordinator.restoreOffset()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        weak var scrollView: UIScrollView?

        /// آخر موقع scroll من المستخدم — هذا مصدر الحقيقة، مو scrollView.contentOffset
        /// (لأن iOS قد يُعيده إلى 0 بدون علمنا).
        private var lastUserOffset: CGFloat = 0
        /// نتجاهل scrollViewDidScroll إذا كنا نُعيد ضبط الـoffset برمجياً (عشان لا
        /// نسجّله كأنه scroll من المستخدم).
        private var isRestoring = false

        /// يُعيد تطبيق lastUserOffset على scrollView مع clamping لحدود المحتوى.
        func restoreOffset() {
            guard let sv = scrollView, lastUserOffset > 0 else { return }
            sv.layoutIfNeeded()
            let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
            let target = min(lastUserOffset, maxY)
            // فقط لو الفرق ملحوظ (>1 نقطة) عشان لا ندخل في حلقة
            if target > 0, abs(sv.contentOffset.y - target) > 1 {
                isRestoring = true
                sv.setContentOffset(CGPoint(x: 0, y: target), animated: false)
                isRestoring = false
            }
        }

        // MARK: UIScrollViewDelegate

        nonisolated func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // تُستدعى من UIKit بدون إشارة @MainActor — نقفز للـMainActor
            let offset = scrollView.contentOffset.y
            Task { @MainActor in
                guard !self.isRestoring else { return }
                self.lastUserOffset = offset
            }
        }

        deinit {
            // explicit deinit يجبر المترجم على عدم محاولة inline تلقائية
            // (workaround لكراش EarlyPerfInliner في Release builds)
        }
    }
}
