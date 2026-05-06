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
    }

    class Coordinator {
        var hostingController: UIHostingController<AnyView>?
    }
}
