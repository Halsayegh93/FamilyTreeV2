import SwiftUI
import UIKit

/// One font family shared by app interfaces, PDFs and the share extension.
/// Alexandria static weights are generated from the OFL variable font.
enum AppTypeface {
    nonisolated static let ultraLight = "Alexandria-Thin"
    nonisolated static let thin = "Alexandria-ExtraLight"
    nonisolated static let light = "Alexandria-Light"
    nonisolated static let regular = "Alexandria-Regular"
    nonisolated static let medium = "Alexandria-Medium"
    nonisolated static let semibold = "Alexandria-SemiBold"
    nonisolated static let bold = "Alexandria-Bold"
    nonisolated static let heavy = "Alexandria-ExtraBold"
    nonisolated static let black = "Alexandria-Black"

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
