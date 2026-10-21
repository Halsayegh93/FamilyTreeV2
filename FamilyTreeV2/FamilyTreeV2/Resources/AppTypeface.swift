import SwiftUI
import UIKit

/// One font family shared by app interfaces, PDFs and the share extension.
/// Cairo static weights are generated from the OFL variable font.
enum AppTypeface {
    // Cairo starts at 200; ultraLight and thin use its lightest native weight.
    nonisolated static let ultraLight = "Cairo-ExtraLight"
    nonisolated static let thin = "Cairo-ExtraLight"
    nonisolated static let light = "Cairo-Light"
    nonisolated static let regular = "Cairo-Regular"
    nonisolated static let medium = "Cairo-Medium"
    nonisolated static let semibold = "Cairo-SemiBold"
    nonisolated static let bold = "Cairo-Bold"
    nonisolated static let heavy = "Cairo-ExtraBold"
    nonisolated static let black = "Cairo-Black"

    /// Minimum base size for interface labels; diagram artwork and PDFs use their own scale.
    nonisolated static let minimumInterfaceSize: CGFloat = 11
    nonisolated static func interfaceSize(_ size: CGFloat) -> CGFloat {
        max(minimumInterfaceSize, size)
    }

    nonisolated static func name(for weight: SwiftUI.Font.Weight) -> String {
        switch weight {
        case .thin: return thin
        case .ultraLight: return ultraLight
        case .light: return light
        case .medium: return medium
        case .semibold: return semibold
        case .bold: return bold
        case .heavy: return heavy
        case .black: return black
        default: return regular
        }
    }

    nonisolated static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name: String
        switch weight {
        case .thin: name = thin
        case .ultraLight: name = ultraLight
        case .light: name = light
        case .regular: name = regular
        case .medium: name = medium
        case .semibold: name = semibold
        case .bold: name = bold
        case .heavy: name = heavy
        case .black: name = black
        default: name = regular
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
