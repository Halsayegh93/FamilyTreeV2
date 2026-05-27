import SwiftUI

/// UIScrollView wrapper يحفظ موضع السكرول عند تغيّر المحتوى.
/// يحل مشكلة iOS 16+ حيث SwiftUI ScrollView يرجع للأعلى عند تغيّر @State،
/// وحالة sheet dismiss حيث iOS يُعيد contentOffset إلى 0.
///
/// الحلّ: نتتبّع آخر موقع scroll **من المستخدم** فقط (drag/decelerate) — مو
/// أي تحديث برمجي لـcontentOffset يفعله iOS. بعد كل تحديث محتوى أو
/// layout pass، نُعيد تطبيق آخر موقع مستخدم.
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
        // تحديث rootView (SwiftUI يحتاج هذا لتمرير تغييرات state)
        context.coordinator.hostingController?.rootView = AnyView(content)
        // إعادة تطبيق آخر موقع مستخدم — مرّة واحدة فقط على الـ runloop التالي
        // (يكفي للتعامل مع sheet dismiss / keyboard، ويخفف الضغط من 2× إلى 1×)
        DispatchQueue.main.async {
            context.coordinator.restoreOffset()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        weak var scrollView: UIScrollView?

        /// آخر موقع scroll من المستخدم — مصدر الحقيقة. لا يتأثّر بإعادة
        /// ضبط contentOffset التي يفعلها iOS (sheet dismiss، keyboard، إلخ).
        private var lastUserOffset: CGFloat = 0

        /// يتحوّل true أثناء drag/decelerate من المستخدم. نُحدِّث lastUserOffset
        /// فقط في هذه الحالة، فلا نلتقط تحديثات contentOffset البرمجية.
        private var isUserScrolling = false

        func restoreOffset() {
            guard let sv = scrollView, lastUserOffset > 0 else { return }
            sv.layoutIfNeeded()
            let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
            let target = min(lastUserOffset, maxY)
            if target > 0, abs(sv.contentOffset.y - target) > 1 {
                sv.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            }
        }

        // MARK: UIScrollViewDelegate

        nonisolated func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            Task { @MainActor in self.isUserScrolling = true }
        }

        nonisolated func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // لو ما فيه تباطؤ، خلّص user scrolling فوراً وحدّث الـoffset
            let offset = scrollView.contentOffset.y
            if !decelerate {
                Task { @MainActor in
                    self.lastUserOffset = offset
                    self.isUserScrolling = false
                }
            }
        }

        nonisolated func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            let offset = scrollView.contentOffset.y
            Task { @MainActor in
                self.lastUserOffset = offset
                self.isUserScrolling = false
            }
        }

        nonisolated func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // نحدِّث lastUserOffset فقط إذا المستخدم فعلاً يسحب أو يتباطأ —
            // نتجاهل أي تحديث برمجي من iOS (مثلاً بعد sheet dismiss).
            let offset = scrollView.contentOffset.y
            let dragging = scrollView.isDragging
            let decelerating = scrollView.isDecelerating
            Task { @MainActor in
                guard self.isUserScrolling || dragging || decelerating else { return }
                self.lastUserOffset = offset
            }
        }

        deinit {
            // explicit deinit يجبر المترجم على عدم محاولة inline تلقائية
            // (workaround لكراش EarlyPerfInliner في Release builds)
        }
    }
}
