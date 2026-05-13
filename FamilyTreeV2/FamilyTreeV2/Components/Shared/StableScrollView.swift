import SwiftUI

/// UIScrollView wrapper يحفظ موضع السكرول عند تغيّر المحتوى.
/// يحل مشكلة iOS 16 حيث SwiftUI ScrollView يرجع للأعلى عند تغيّر @State.
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
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let savedOffset = scrollView.contentOffset
        context.coordinator.hostingController?.rootView = AnyView(content)
        scrollView.layoutIfNeeded()
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
        let clampedY = min(savedOffset.y, maxY)
        if clampedY > 0 {
            scrollView.contentOffset = CGPoint(x: 0, y: clampedY)
        }

        // إعادة تطبيق الـoffset في الـrunloop التالي عشان نتعامل مع
        // sheet dismiss و keyboard hide حيث iOS يُعيد layout بعد updateUIView.
        // بدون هذا، قفل sheet إضافة الابن يرجّع الشاشة للأعلى.
        if savedOffset.y > 0 {
            DispatchQueue.main.async {
                let lateMaxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
                let lateClamped = min(savedOffset.y, lateMaxY)
                if abs(scrollView.contentOffset.y - lateClamped) > 1, lateClamped > 0 {
                    scrollView.setContentOffset(CGPoint(x: 0, y: lateClamped), animated: false)
                }
            }
        }
    }

    @MainActor
    final class Coordinator {
        var hostingController: UIHostingController<AnyView>?
        deinit {
            // explicit deinit يجبر المترجم على عدم محاولة inline تلقائية
            // (workaround لكراش EarlyPerfInliner في Release builds)
        }
    }
}
