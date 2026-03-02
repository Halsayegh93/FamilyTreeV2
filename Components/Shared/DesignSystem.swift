import SwiftUI

// MARK: - Design Tokens — المحمدعلي Family App
// Theme: Royal & Modern | Colors: Royal Blue + Gold | Light & Dark Mode
enum DS {

    // MARK: Colors
    enum Color {
        // Brand — Royal Blue + Gold (adaptive for dark mode)
        static let primary       = SwiftUI.Color.adaptive(light: "#1B3A8C", dark: "#5B8FE6") // Royal Blue
        static let primaryDark   = SwiftUI.Color.adaptive(light: "#0E2460", dark: "#3A6CD4") // Deep Navy
        static let primaryLight  = SwiftUI.Color.adaptive(light: "#4F74C9", dark: "#7FAEF0") // Light Royal
        static let accent        = SwiftUI.Color(hex: "#C8962E") // Rich Gold
        static let accentDark    = SwiftUI.Color(hex: "#9A7321") // Deep Gold
        static let accentLight   = SwiftUI.Color(hex: "#E6C06A") // Soft Gold

        // Supporting Accents — ألوان مساندة فخمة
        static let neonBlue     = SwiftUI.Color.adaptive(light: "#3B5FBF", dark: "#6B9FE8") // Sapphire
        static let neonPurple   = SwiftUI.Color.adaptive(light: "#7B68AE", dark: "#A08DD0") // Amethyst
        static let neonCyan     = SwiftUI.Color(hex: "#E8D5A3") // Champagne Gold
        static let neonPink     = SwiftUI.Color(hex: "#D4A38C") // Rose Gold

        // Gradients — تدرجات ملكية
        static let gradientPrimary = LinearGradient(
            colors: [primaryLight, primary, primaryDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientAccent = LinearGradient(
            colors: [accentLight, accent, accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientWarm = LinearGradient(
            colors: [accentLight, accent],
            startPoint: .leading, endPoint: .trailing
        )
        static let gradientCool = LinearGradient(
            colors: [SwiftUI.Color(hex: "#D4E4F7"), primaryLight],
            startPoint: .leading, endPoint: .trailing
        )
        static let gradientDark = LinearGradient(
            colors: [SwiftUI.Color(hex: "#1A1A2E"), SwiftUI.Color(hex: "#0F0F1A"), SwiftUI.Color(hex: "#060610")],
            startPoint: .top, endPoint: .bottom
        )
        static let gradientAuth = LinearGradient(
            colors: [SwiftUI.Color(hex: "#0A1628"), primaryDark, SwiftUI.Color(hex: "#1A1235"), SwiftUI.Color(hex: "#050A18")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientFire = LinearGradient(
            colors: [SwiftUI.Color(hex: "#B85C1E"), SwiftUI.Color(hex: "#8B3A13")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientOcean = LinearGradient(
            colors: [primary, SwiftUI.Color(hex: "#162D6B")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientNeon = LinearGradient(
            colors: [primaryLight, neonBlue],
            startPoint: .leading, endPoint: .trailing
        )
        static let gradientRoyal = LinearGradient(
            colors: [primaryDark, primary, accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientGold = LinearGradient(
            colors: [accentLight, accent, accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        // Surfaces
        static let background       = SwiftUI.Color(.systemGroupedBackground)
        static let surface          = SwiftUI.Color(.secondarySystemGroupedBackground)
        static let surfaceElevated  = SwiftUI.Color(.tertiarySystemGroupedBackground)

        // Text
        static let textPrimary   = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        static let textTertiary  = SwiftUI.Color(.tertiaryLabel)
        static let textOnPrimary = SwiftUI.Color.white
        static let textGold      = SwiftUI.Color(hex: "#C8962E")

        // Semantic
        static let success = SwiftUI.Color(hex: "#1B7A42") // Emerald Green
        static let warning = SwiftUI.Color(hex: "#D4960A") // Golden Warning
        static let error   = SwiftUI.Color(hex: "#B5302A") // Crimson Red
        static let info    = SwiftUI.Color.adaptive(light: "#2E5CAD", dark: "#6A9EE0") // Royal Info

        // Role Colors — ألوان الأدوار
        static func role(_ roleColor: SwiftUI.Color) -> SwiftUI.Color { roleColor }
        static let adminRole      = SwiftUI.Color(hex: "#7B68AE") // Amethyst Purple
        static let supervisorRole = SwiftUI.Color(hex: "#C8962E") // Gold
        static let memberRole     = SwiftUI.Color.adaptive(light: "#1B3A8C", dark: "#5B8FE6") // Royal Blue
        static let pendingRole    = SwiftUI.Color.gray

        // News Type Colors — ألوان أنواع الأخبار
        static let newsWedding  = SwiftUI.Color(hex: "#D4A38C") // Rose Gold
        static let newsBirth    = SwiftUI.Color(hex: "#4AADA8") // Teal
        static let newsDeath    = SwiftUI.Color(hex: "#8A8A8E") // Muted Gray
        static let newsVote     = SwiftUI.Color(hex: "#C8962E") // Gold

        // Status Colors
        static let deceased         = SwiftUI.Color(hex: "#8A8A8E")
        static let currentLocation  = SwiftUI.Color(hex: "#34C759") // Active Green
        static let likeAction       = SwiftUI.Color(hex: "#E8425A") // Like Red

        // Quick Access Grid Colors
        static let gridTree      = SwiftUI.Color.adaptive(light: "#0E2460", dark: "#3A6CD4") // Deep Navy
        static let gridAlerts    = SwiftUI.Color(hex: "#B5302A") // Crimson
        static let gridDiwaniya  = SwiftUI.Color.adaptive(light: "#1B3A8C", dark: "#5B8FE6") // Royal Blue
        static let gridContact   = SwiftUI.Color(hex: "#C8962E") // Gold
    }

    // MARK: Typography — خطوط حديثة ونظيفة مع دعم Dynamic Type
    enum Font {
        static let hero        = SwiftUI.Font.system(.largeTitle, design: .default).weight(.black)
        static let largeTitle  = SwiftUI.Font.system(.largeTitle, design: .default).weight(.bold)
        static let title1      = SwiftUI.Font.system(.title, design: .default).weight(.bold)
        static let title2      = SwiftUI.Font.system(.title2, design: .default).weight(.bold)
        static let title3      = SwiftUI.Font.system(.title3, design: .default).weight(.semibold)
        static let headline    = SwiftUI.Font.system(.headline, design: .default).weight(.bold)
        static let body        = SwiftUI.Font.system(.body, design: .default)
        static let bodyBold    = SwiftUI.Font.system(.body, design: .default).weight(.semibold)
        static let callout     = SwiftUI.Font.system(.callout, design: .default)
        static let calloutBold = SwiftUI.Font.system(.callout, design: .default).weight(.bold)
        static let subheadline = SwiftUI.Font.system(.subheadline, design: .default)
        static let footnote    = SwiftUI.Font.system(.footnote, design: .default)
        static let caption1    = SwiftUI.Font.system(.caption, design: .default)
        static let caption2    = SwiftUI.Font.system(.caption2, design: .default)

        /// خط مرن يدعم Dynamic Type - يُستخدم بدل .system(size:weight:)
        static func scaled(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            let style: SwiftUI.Font.TextStyle
            switch size {
            case ...10: style = .caption2
            case 11: style = .caption2
            case 12: style = .caption
            case 13: style = .footnote
            case 14...15: style = .subheadline
            case 16: style = .callout
            case 17: style = .body
            case 18...19: style = .headline
            case 20...21: style = .title3
            case 22...27: style = .title2
            case 28...35: style = .title
            default: style = .largeTitle
            }
            return SwiftUI.Font.system(style, design: .default).weight(weight)
        }
    }

    // MARK: Spacing
    enum Spacing {
        static let xs:    CGFloat = 4
        static let sm:    CGFloat = 8
        static let md:    CGFloat = 12
        static let lg:    CGFloat = 16
        static let xl:    CGFloat = 20
        static let xxl:   CGFloat = 24
        static let xxxl:  CGFloat = 32
        static let xxxxl: CGFloat = 40
    }

    // MARK: Radius — حواف حديثة ناعمة
    enum Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let xxl:  CGFloat = 24
        static let xxxl: CGFloat = 28
        static let full: CGFloat = 999
    }

    // MARK: Icon
    enum Icon {
        static let size:   CGFloat = 46
        static let sizeSm: CGFloat = 38
        static let sizeLg: CGFloat = 58
        static let opacity: CGFloat = 0.15
    }

    // MARK: Shadow — ظلال عصرية أنيقة
    enum Shadow {
        static let card     = ShadowStyle(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
        static let subtle   = ShadowStyle(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        static let glow     = ShadowStyle(color: SwiftUI.Color(hex: "#1B3A8C").opacity(0.18), radius: 16, x: 0, y: 6)
        static let glowAccent = ShadowStyle(color: SwiftUI.Color(hex: "#C8962E").opacity(0.15), radius: 14, x: 0, y: 5)
        static let neon     = ShadowStyle(color: SwiftUI.Color(hex: "#C8962E").opacity(0.20), radius: 16, x: 0, y: 4)
        static let none     = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
    }

    struct ShadowStyle {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: Animation — أنيميشن حديثة وسلسة
    enum Anim {
        static let bouncy    = Animation.spring(response: 0.4, dampingFraction: 0.65, blendDuration: 0)
        static let snappy    = Animation.spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0)
        static let smooth    = Animation.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0)
        static let elastic   = Animation.spring(response: 0.45, dampingFraction: 0.55, blendDuration: 0)
        static let quick     = Animation.easeOut(duration: 0.18)
        static let medium    = Animation.easeInOut(duration: 0.32)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// لون متكيف مع الوضع الفاتح والداكن
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

// MARK: - View Extensions
extension View {
    func dsCardShadow() -> some View {
        self.shadow(color: DS.Shadow.card.color,
                    radius: DS.Shadow.card.radius,
                    x: DS.Shadow.card.x,
                    y: DS.Shadow.card.y)
    }

    func dsSubtleShadow() -> some View {
        self.shadow(color: DS.Shadow.subtle.color,
                    radius: DS.Shadow.subtle.radius,
                    x: DS.Shadow.subtle.x,
                    y: DS.Shadow.subtle.y)
    }

    func dsGlowShadow() -> some View {
        self.shadow(color: DS.Shadow.glow.color,
                    radius: DS.Shadow.glow.radius,
                    x: DS.Shadow.glow.x,
                    y: DS.Shadow.glow.y)
    }

    func dsNeonShadow() -> some View {
        self.shadow(color: DS.Shadow.neon.color,
                    radius: DS.Shadow.neon.radius,
                    x: DS.Shadow.neon.x,
                    y: DS.Shadow.neon.y)
    }

    func dsAccentGlow() -> some View {
        self.shadow(color: DS.Shadow.glowAccent.color,
                    radius: DS.Shadow.glowAccent.radius,
                    x: DS.Shadow.glowAccent.x,
                    y: DS.Shadow.glowAccent.y)
    }

    func dsGradientBackground() -> some View {
        self.background(DS.Color.gradientPrimary)
    }

    /// كرت صلب نظيف — Professional solid card
    func glassCard(radius: CGFloat = DS.Radius.xl) -> some View {
        self
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SwiftUI.Color.gray.opacity(0.12), lineWidth: 1)
            )
            .dsCardShadow()
    }

    /// خلفية صلبة — Professional solid background
    func glassBackground(radius: CGFloat = DS.Radius.lg) -> some View {
        self
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SwiftUI.Color.gray.opacity(0.10), lineWidth: 1)
            )
    }

    /// شكل كبسولة صلب — Professional solid pill
    func glassPill() -> some View {
        self
            .background(DS.Color.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(SwiftUI.Color.gray.opacity(0.10), lineWidth: 1))
    }

    /// Bold press effect
    func dsBoldPress(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(DS.Anim.bouncy, value: isPressed)
    }
}

// MARK: - Reusable Components

/// كرت موحد — Professional solid card
struct DSCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = DS.Spacing.lg

    init(padding: CGFloat = DS.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(padding)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )
            .dsCardShadow()
    }
}

/// كرت مع تدرج لوني جريء + glass overlay
struct DSGradientCard<Content: View>: View {
    let gradient: LinearGradient
    let content: Content

    init(gradient: LinearGradient = DS.Color.gradientPrimary, @ViewBuilder content: () -> Content) {
        self.gradient = gradient
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                ZStack {
                    gradient
                    SwiftUI.Color.white.opacity(0.06)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(SwiftUI.Color.white.opacity(0.30), lineWidth: 0.7)
            )
            .dsGlowShadow()
    }
}

/// كرت مع حدود ملونة — Accent border card
struct DSGlowCard<Content: View>: View {
    let glowColor: SwiftUI.Color
    let content: Content

    init(glowColor: SwiftUI.Color = DS.Color.primary, @ViewBuilder content: () -> Content) {
        self.glowColor = glowColor
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(glowColor.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(color: glowColor.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

/// نص بتدرج لوني
struct DSGradientText: View {
    let text: String
    var font: SwiftUI.Font = DS.Font.title1
    var gradient: LinearGradient = DS.Color.gradientPrimary

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(gradient)
    }
}

/// باج متحرك مع نبض
struct DSPulseBadge: View {
    let count: Int
    var color: SwiftUI.Color = DS.Color.error

    @State private var isPulsing = false

    var body: some View {
        Text("\(count)")
            .font(DS.Font.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

/// زر رئيسي — Bold gradient مع bounce effect
struct DSPrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void
    var useGradient: Bool = true
    var color: Color = DS.Color.primary

    init(_ title: String, icon: String? = nil, isLoading: Bool = false, useGradient: Bool = true, color: Color = DS.Color.primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.useGradient = useGradient
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        if let icon { Image(systemName: icon).font(DS.Font.scaled(16, weight: .bold)) }
                        Text(title).fontWeight(.bold)
                    }
                }
            }
            .font(DS.Font.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Group {
                    if useGradient {
                        AnyView(DS.Color.gradientPrimary)
                    } else {
                        AnyView(isLoading ? color.opacity(0.7) : color)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(SwiftUI.Color.white.opacity(0.25), lineWidth: 0.7)
            )
            .dsGlowShadow()
        }
        .buttonStyle(DSBoldButtonStyle())
        .disabled(isLoading)
    }
}

/// زر ثانوي — Bold glass + حدود
struct DSSecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var color: Color = DS.Color.primary

    init(_ title: String, icon: String? = nil, color: Color = DS.Color.primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if let icon { Image(systemName: icon).font(DS.Font.scaled(14, weight: .bold)) }
                Text(title).fontWeight(.bold)
            }
            .font(DS.Font.calloutBold)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(color.opacity(0.30), lineWidth: 1.2)
            )
        }
        .buttonStyle(DSBoldButtonStyle())
    }
}

/// حقل إدخال — Bold Glass style مع glow focus
struct DSTextField: View {
    @Environment(\.layoutDirection) private var layoutDirection
    var label: String
    var placeholder: String
    @Binding var text: String
    var icon: String
    var iconColor: Color = DS.Color.primary
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                if !label.isEmpty {
                    Text(label)
                        .font(DS.Font.caption1)
                        .foregroundColor(isFocused ? iconColor : DS.Color.textSecondary)
                        .animation(DS.Anim.quick, value: isFocused)
                }
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(DS.Font.body)
                        .keyboardType(keyboard)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .font(DS.Font.body)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.leading)
                        .focused($isFocused)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(isFocused ? iconColor.opacity(0.5) : Color.gray.opacity(0.15), lineWidth: isFocused ? 1.5 : 1)
                .animation(DS.Anim.quick, value: isFocused)
        )
        .shadow(color: isFocused ? iconColor.opacity(0.15) : .clear, radius: 12, x: 0, y: 4)
        .animation(DS.Anim.quick, value: isFocused)
    }
}

/// أيقونة — Bold circle مع gradient tint
struct DSIcon: View {
    let name: String
    var color: Color = DS.Color.primary
    var size: CGFloat = DS.Icon.size
    var iconSize: CGFloat = 17

    init(_ name: String, color: Color = DS.Color.primary, size: CGFloat = DS.Icon.size, iconSize: CGFloat = 17) {
        self.name = name
        self.color = color
        self.size = size
        self.iconSize = iconSize
    }

    var body: some View {
        Image(systemName: name)
            .font(DS.Font.scaled(iconSize, weight: .bold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(DS.Icon.opacity))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

/// صف بيانات — Bold Glass style
struct DSDataRow: View {
    var title: String
    var value: String
    var icon: String
    var color: Color = DS.Color.primary

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Text(value)
                    .font(DS.Font.calloutBold)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}

/// صف إجراء مع badge — Bold Glass style
struct DSActionRow: View {
    var title: String
    var subtitle: String? = nil
    var icon: String
    var color: Color = DS.Color.primary
    var badge: Int? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()

            if let badge, badge > 0 {
                DSPulseBadge(count: badge)
            }

            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}

/// عنوان قسم — Bold
struct DSSectionHeader: View {
    var title: String
    var icon: String? = nil
    var trailing: String? = nil
    var iconColor: Color = DS.Color.primary

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    if let icon {
                        Image(systemName: icon)
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(iconColor)
                    }
                    Text(title)
                        .font(DS.Font.scaled(13, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(iconColor.opacity(0.08))
                .clipShape(Capsule())

                if let trailing {
                    Text(trailing)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.primary)
                        .fontWeight(.bold)
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            DSDivider()
        }
    }
}

/// هيدر شيت — Bold Glass style
struct DSSheetHeader: View {
    var title: String
    var cancelTitle: String = L10n.t("إلغاء", "Cancel")
    var confirmTitle: String = L10n.t("حفظ", "Save")
    var isLoading: Bool = false
    var confirmDisabled: Bool = false
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, DS.Spacing.sm)

            HStack {
                Button(cancelTitle, action: onCancel)
                    .font(DS.Font.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textSecondary)

                Spacer()

                Text(title)
                    .font(DS.Font.headline)

                Spacer()

                Button(action: onConfirm) {
                    if isLoading {
                        ProgressView().tint(DS.Color.primary)
                    } else {
                        Text(confirmTitle)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(confirmDisabled ? DS.Color.textTertiary : DS.Color.primary)
                    }
                }
                .disabled(confirmDisabled || isLoading)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)

            Divider().opacity(0.3)
        }
        .background(DS.Color.surface)
    }
}

/// فاصل
struct DSDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, DS.Spacing.lg)
            .opacity(0.3)
    }
}

/// شارة دور — Bold Glass pill
struct DSRoleBadge: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(DS.Font.caption2)
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.7))
    }
}

/// بطاقة إحصاء — Bold Glass card
struct DSStatCard: View {
    var title: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(26, weight: .bold))
                .foregroundColor(color)
                .frame(width: DS.Icon.sizeLg, height: DS.Icon.sizeLg)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            Text(value)
                .font(DS.Font.title1)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Text(title)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

/// زر عائم — Bold glass capsule مع gradient
struct DSFloatingButton: View {
    var icon: String
    var label: String? = nil
    var color: Color = DS.Color.primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(20, weight: .black))
                if let label {
                    Text(label).font(DS.Font.calloutBold)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, label != nil ? DS.Spacing.xl : DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md + 2)
            .background(DS.Color.gradientPrimary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(SwiftUI.Color.white.opacity(0.25), lineWidth: 0.7))
            .dsGlowShadow()
        }
        .buttonStyle(DSBoldButtonStyle())
    }
}

// MARK: - Decorative Background — خلفية زخرفية موحدة
struct DSDecorativeBackground: View {
    var primaryGradient: LinearGradient = DS.Color.gradientPrimary
    var accentGradient: LinearGradient = DS.Color.gradientAccent

    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(primaryGradient)
                .frame(width: 240, height: 240)
                .blur(radius: 100)
                .opacity(0.14)
                .offset(x: geo.size.width * 0.35, y: -220)

            Circle()
                .fill(accentGradient)
                .frame(width: 180, height: 180)
                .blur(radius: 80)
                .opacity(0.10)
                .offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.4)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Setting Icon — أيقونة الإعدادات
struct DSSettingIcon: View {
    var name: String
    var color: Color
    var size: CGFloat = DS.Icon.sizeSm

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: name)
                .font(DS.Font.scaled(size * 0.42, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Card Accent Line — خط زخرفي فوق البطاقة
struct DSCardAccentLine<S: ShapeStyle>: View {
    var style: S

    init(gradient: LinearGradient) where S == LinearGradient {
        self.style = gradient
    }

    init(color: Color) where S == Color {
        self.style = color
    }

    init() where S == LinearGradient {
        self.style = DS.Color.gradientPrimary
    }

    var body: some View {
        Rectangle()
            .fill(style)
            .frame(height: 4)
            .cornerRadius(DS.Radius.full)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.xs)
    }
}

// MARK: - Approve / Reject Buttons — أزرار الموافقة والرفض
struct DSApproveRejectButtons: View {
    var approveTitle: String
    var rejectTitle: String
    var isLoading: Bool = false
    var approveGradient: LinearGradient = DS.Color.gradientPrimary
    var onApprove: () -> Void
    var onReject: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(action: onReject) {
                Text(rejectTitle)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.error.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.error.opacity(0.3), lineWidth: 1.5)
                    )
            }

            Button(action: onApprove) {
                ZStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(approveTitle)
                            .font(DS.Font.calloutBold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(approveGradient)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .dsGlowShadow()
            }
        }
    }
}

// MARK: - Bold Button Style
struct DSBoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Scale Button Style (Elegant)
struct DSScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Backwards Compatibility

struct UnifiedTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )
            .multilineTextAlignment(.leading)
    }
}

struct UnifiedButtonStyle: ButtonStyle {
    var color: Color = DS.Color.primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(configuration.isPressed ? color.opacity(0.85) : color)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
