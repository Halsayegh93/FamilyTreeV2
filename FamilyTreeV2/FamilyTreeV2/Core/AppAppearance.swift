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
            // المربّعات المفتوحة فوق النافذة (الإعدادات ← المظهر) لا ترث تغيير النافذة: تبقى على وضعها
            // القديم (الجهاز داكن واختار «فاتح» ⇒ بقيت داكنة — بلاغ المالك ٢٠٢٦-١٠-١٠). فيُضبط كلٌّ منها
            // صراحةً — و«حسب الجهاز» يُضبط على وضع الجهاز الفعلي (ترك الضبط فارغاً أبقاها على القديم)
            let boxStyle = style == .unspecified ? scene.traitCollection.userInterfaceStyle : style
            for window in scene.windows {
                let presented = presentedChain(of: window)
                guard window.overrideUserInterfaceStyle != style
                        || presented.contains(where: { $0.overrideUserInterfaceStyle != boxStyle }) else { continue }
                let change = {
                    window.overrideUserInterfaceStyle = style
                    presented.forEach { $0.overrideUserInterfaceStyle = boxStyle }
                }
                if animated {
                    UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve,
                                      animations: change)
                } else {
                    change()
                }
            }
        }
    }

    /// سلسلة المربّعات المعروضة فوق النافذة (مربّع فوق مربّع)
    @MainActor
    private static func presentedChain(of window: UIWindow) -> [UIViewController] {
        var chain: [UIViewController] = []
        var next = window.rootViewController?.presentedViewController
        while let vc = next {
            chain.append(vc)
            next = vc.presentedViewController
        }
        return chain
    }
}
