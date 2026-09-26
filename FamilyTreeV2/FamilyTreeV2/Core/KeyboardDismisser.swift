import UIKit

/// إخفاء لوحة المفاتيح بالضغط في أي مكان خارج حقل الكتابة — في كل شاشات
/// التطبيق ومربّعاته (طلب المالك ٢٠٢٦-٠٩-٢٦).
///
/// ضغطة واحدة على نافذة التطبيق (ونوافذ المربّعات المنبثقة) تُنهي الكتابة،
/// بلا إلغاء للمسة نفسها: الزر المضغوط يعمل كالمعتاد. الضغط على حقل كتابة
/// آخر لا يُحتسب، فينتقل التركيز له مباشرة.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private static let gestureName = "ds.keyboardDismiss"
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowAppeared(_:)),
                           name: UIWindow.didBecomeVisibleNotification, object: nil)
        center.addObserver(self, selector: #selector(windowAppeared(_:)),
                           name: UIWindow.didBecomeKeyNotification, object: nil)
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach(attach)
        }
    }

    @objc private func windowAppeared(_ note: Notification) {
        guard let window = note.object as? UIWindow else { return }
        attach(window)
    }

    private func attach(_ window: UIWindow) {
        // نوافذ النظام (لوحة المفاتيح وتأثيرات النص) لا تُلمس
        let cls = String(describing: type(of: window))
        if cls.contains("Keyboard") || cls.contains("TextEffects") { return }
        if window.gestureRecognizers?.contains(where: { $0.name == Self.gestureName }) == true { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.name = Self.gestureName
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // الضغط على حقل كتابة (أو ما بداخله) لا يُخفي اللوحة
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView || v is UISearchBar { return false }
            view = v.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
