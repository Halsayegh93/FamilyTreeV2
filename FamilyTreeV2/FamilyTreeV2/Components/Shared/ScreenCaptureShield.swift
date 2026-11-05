import SwiftUI
import UIKit

/// يُخفي المحتوى من لقطة الشاشة وتسجيلها ومن البثّ (طلب المالك ٢٠٢٦-١٠-٢٩ «حتى لقطة الشاشة تكون صعبة»):
/// المحتوى يُرسم داخل طبقة حقل كلمة السر الآمن (`isSecureTextEntry`) التي يحذفها النظام من أي التقاط،
/// فيظهر في اللقطة فراغ. لا يمنع التصوير بجهاز آخر.
/// إن لم تُوجد الطبقة الآمنة (تغيّر داخلي في نظام قادم) يُعرض المحتوى عادياً — لا شاشة فارغة.
struct ScreenCaptureShield<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> ShieldContainerView {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        context.coordinator.host = host
        return ShieldContainerView(content: host.view)
    }

    func updateUIView(_ uiView: ShieldContainerView, context: Context) {
        context.coordinator.host?.rootView = content
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShieldContainerView, context: Context) -> CGSize? {
        guard let host = context.coordinator.host else { return nil }
        let fitting = CGSize(width: proposal.width ?? UIView.layoutFittingExpandedSize.width,
                             height: proposal.height ?? UIView.layoutFittingExpandedSize.height)
        return host.sizeThatFits(in: fitting)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var host: UIHostingController<Content>?
    }
}

/// الحاوية: تأخذ الطبقة الآمنة من حقل كلمة سر وتضع المحتوى داخلها
final class ShieldContainerView: UIView {
    /// يبقى الحقل حيّاً — الطبقة الآمنة تُدار منه
    private let secureField = UITextField()

    init(content: UIView) {
        super.init(frame: .zero)
        secureField.isSecureTextEntry = true
        let canvas = secureField.subviews.first {
            NSStringFromClass(type(of: $0)).contains("CanvasView")
        } ?? secureField.subviews.first
        let holder: UIView
        if let canvas {
            canvas.subviews.forEach { $0.removeFromSuperview() }
            canvas.isUserInteractionEnabled = true
            holder = canvas
        } else {
            Log.warning("[SHIELD] لم تُوجد الطبقة الآمنة — يُعرض المحتوى بلا حماية")
            holder = UIView()
        }
        pin(holder, in: self)
        pin(content, in: holder)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func pin(_ child: UIView, in parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

extension View {
    /// يحمي المحتوى من لقطة الشاشة حين `enabled`
    @ViewBuilder
    func screenCaptureShielded(_ enabled: Bool) -> some View {
        if enabled {
            ScreenCaptureShield { self }
        } else {
            self
        }
    }
}

/// سياسة لقطة الشاشة في المكتبة من السيرفر (`app_config` — تتغيّر بلا بناء تطبيق):
/// `library_screen_protection`: `members` (الافتراضي) | `all` | `off` — من تُحجب عنه لقطة الشاشة.
/// الحفظ والمشاركة صار لكل عنصر (`family_archive.allow_share`)، والعنصر المسموح بمشاركته لا تُحجب لقطته
/// (طلب المالك ٢٠٢٦-١٠-٢٩ «منع التقاط الشاشة على اللي ما عنده زر مشاركة»).
enum LibraryProtection {
    @MainActor
    static func shieldsCapture(isAdmin: Bool, allowShare: Bool) -> Bool {
        if allowShare { return false }
        switch AppConfigValues.shared.string("library_screen_protection") ?? "members" {
        case "off": return false
        case "all": return true
        default: return !isAdmin
        }
    }
}
