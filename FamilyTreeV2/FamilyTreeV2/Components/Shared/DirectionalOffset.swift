import SwiftUI

enum DirectionalOffset {
    static func signedX(_ x: CGFloat) -> CGFloat {
        L10n.isArabic ? abs(x) : -abs(x)
    }
}

extension View {
    /// Arabic uses +X, English uses -X.
    func languageHorizontalOffset(_ x: CGFloat, y: CGFloat = 0) -> some View {
        offset(x: DirectionalOffset.signedX(x), y: y)
    }
}
