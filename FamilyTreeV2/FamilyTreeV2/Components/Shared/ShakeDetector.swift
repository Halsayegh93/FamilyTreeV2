import SwiftUI
import UIKit

/// كاشف هزّ الجهاز — يُستخدم لكشف/إخفاء أسماء النساء في «عائلتي».
/// يعتمد على `motionEnded` من UIKit عبر متحكّم شفّاف يصبح first responder.
struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeViewController {
        let controller = ShakeViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ controller: ShakeViewController, context: Context) {
        controller.onShake = onShake
    }

    final class ShakeViewController: UIViewController {
        var onShake: (() -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            resignFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else { return }
            onShake?()
        }
    }
}

extension View {
    /// ينفّذ الإجراء عند هزّ الجهاز
    nonisolated func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeDetector(onShake: action).frame(width: 0, height: 0))
    }
}
