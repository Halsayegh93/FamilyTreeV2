import UIKit

/// وضع المظهر (حسب الجهاز / فاتح / داكن) — مكان واحد يطبّقه على كل نوافذ التطبيق.
/// يُستدعى عند الإقلاع وفور تغيير الاختيار في «المظهر واللغة» فيتغيّر الوضع لحظياً
/// (طلب المالك ٢٠٢٦-١٠-٠٧) — يشمل النافذة الرئيسية والمربّعات والتنبيهات المفتوحة في نوافذ مستقلّة.
enum AppAppearance {
    static let storageKey = "appearanceMode"

    static func style(for mode: String?) -> UIUserInterfaceStyle {
        switch mode {
        case "light": return .light
        case "dark":  return .dark
        default:      return .unspecified
        }
    }

    /// يطبّق الوضع على كل النوافذ فوراً، بتلاشٍ قصير بدل القفزة
    @MainActor
    static func apply(_ mode: String? = UserDefaults.standard.string(forKey: storageKey), animated: Bool = true) {
        let style = style(for: mode)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                if animated {
                    UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
                        window.overrideUserInterfaceStyle = style
                    }
                } else {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}
