import SwiftUI
import UIKit

/// Shared by the application, PDF renderer and share extension.
/// Licensed font files are provisioned locally with tools/prepare-urw-fonts.py.
enum AppTypeface {
    nonisolated static let regular = "URWGeometricArabic-Regular"
    nonisolated static let medium = "URWGeometricArabic-SemiBold"
    nonisolated static let semibold = "URWGeometricArabic-SemiBold"
    nonisolated static let bold = "URWGeometricArabic-ExtraBold"

    nonisolated static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name = weight >= .bold ? bold : weight >= .medium ? semibold : regular
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
