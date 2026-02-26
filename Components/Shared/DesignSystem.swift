import SwiftUI

// MARK: - Design Tokens — المحمدعلي Family App
// Theme: Elegant & Classic | Colors: Warm Gold + Deep Forest Green | Light & Dark Mode
enum DS {

    // MARK: Colors
    enum Color {
        // Brand — Modern Ocean Blue + Slate
        static let primary       = SwiftUI.Color(hex: "#2B7A9F") // Ocean Blue
        static let primaryDark   = SwiftUI.Color(hex: "#1E5474") // Deep Ocean
        static let primaryLight  = SwiftUI.Color(hex: "#78ACC3") // Light Ocean
        static let accent        = SwiftUI.Color(hex: "#516F80") // Slate Blue
        static let accentDark    = SwiftUI.Color(hex: "#344B59") // Dark Slate
        static let accentLight   = SwiftUI.Color(hex: "#8A9EA9") // Light Slate

        // Classic Accents — ألوان عصرية هادئة
        static let neonBlue     = SwiftUI.Color(hex: "#5D8AA8") // Air Force Blue
        static let neonPurple   = SwiftUI.Color(hex: "#89A6B1") // Soft Blue Grey
        static let neonCyan     = SwiftUI.Color(hex: "#A3C4D3") // Powder Blue
        static let neonPink     = SwiftUI.Color(hex: "#D3AEB1") // Soft Rose

        // Gradients — تدرجات أوشن وسليت
        static let gradientPrimary = LinearGradient(
            colors: [primaryLight, primary, primaryDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientAccent = LinearGradient(
            colors: [accentLight, accent, accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientWarm = LinearGradient(
            colors: [SwiftUI.Color(hex: "#D3AEB1"), SwiftUI.Color(hex: "#B88A8D")],
            startPoint: .leading, endPoint: .trailing
        )
        static let gradientCool = LinearGradient(
            colors: [neonCyan, primaryLight],
            startPoint: .leading, endPoint: .trailing
        )
        static let gradientDark = LinearGradient(
            colors: [SwiftUI.Color(hex: "#2E2E2E"), SwiftUI.Color(hex: "#1A1A1A"), SwiftUI.Color(hex: "#0D0D0D")],
            startPoint: .top, endPoint: .bottom
        )
        static let gradientAuth = LinearGradient(
            colors: [SwiftUI.Color(hex: "#11181C"), primaryDark, accentDark, SwiftUI.Color(hex: "#050B0D")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientFire = LinearGradient(
            colors: [SwiftUI.Color(hex: "#A0522D"), SwiftUI.Color(hex: "#8B4513")], // Kept warm for error states
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientOcean = LinearGradient(
            colors: [primary, accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let gradientNeon = LinearGradient(
            colors: [primaryLight, neonBlue],
            startPoint: .leading, endPoint: .trailing
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

        // Semantic — ألوان أقوى وأكثر رسمية
        static let success = SwiftUI.Color(hex: "#2F5C3E") // Deep green success
        static let warning = SwiftUI.Color(hex: "#B88E33") // Dull gold warning
        static let error   = SwiftUI.Color(hex: "#8C2A2A") // Classic dark red
        static let info    = SwiftUI.Color(hex: "#496885") // Slate blue

        // Role Colors
        static func role(_ roleColor: SwiftUI.Color) -> SwiftUI.Color { roleColor }

        // Quick Access Grid Colors
        static let gridTree      = SwiftUI.Color(hex: "#344B59") // Dark Slate
        static let gridAlerts    = SwiftUI.Color(hex: "#8C2A2A") // Red
        static let gridDiwaniya  = SwiftUI.Color(hex: "#2B7A9F") // Ocean Blue
        static let gridContact   = SwiftUI.Color(hex: "#516F80") // Slate Blue
    }

    // MARK: Typography — خطوط عصرية ونظيفة (Rounded)
    enum Font {
        static let hero        = SwiftUI.Font.system(size: 40, weight: .bold, design: .rounded)
        static let largeTitle  = SwiftUI.Font.system(size: 36, weight: .bold, design: .rounded)
        static let title1      = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2      = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        static let title3      = SwiftUI.Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline    = SwiftUI.Font.system(size: 17, weight: .bold, design: .rounded)
        static let body        = SwiftUI.Font.system(size: 17, weight: .regular, design: .rounded)
        static let bodyBold    = SwiftUI.Font.system(size: 17, weight: .semibold, design: .rounded)
        static let callout     = SwiftUI.Font.system(size: 16, weight: .regular, design: .rounded)
        static let calloutBold = SwiftUI.Font.system(size: 16, weight: .bold, design: .rounded)
        static let subheadline = SwiftUI.Font.system(size: 15, weight: .regular, design: .rounded)
        static let footnote    = SwiftUI.Font.system(size: 13, weight: .regular, design: .rounded)
        static let caption1    = SwiftUI.Font.system(size: 12, weight: .regular, design: .rounded)
        static let caption2    = SwiftUI.Font.system(size: 11, weight: .regular, design: .rounded)
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

    // MARK: Radius - حواف أقل حدة تناسب الطابع الكلاسيكي
    enum Radius {
        static let sm:   CGFloat = 6
        static let md:   CGFloat = 10
        static let lg:   CGFloat = 14
        static let xl:   CGFloat = 18
        static let xxl:  CGFloat = 22
        static let xxxl: CGFloat = 26
        static let full: CGFloat = 999
    }

    // MARK: Icon
    enum Icon {
        static let size:   CGFloat = 46
        static let sizeSm: CGFloat = 38
        static let sizeLg: CGFloat = 58
        static let opacity: CGFloat = 0.15
    }

    // MARK: Shadow — ظلال كلاسيكية راقية (غير متوهجة جداً)
    enum Shadow {
        static let card     = ShadowStyle(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        static let subtle   = ShadowStyle(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
        static let glow     = ShadowStyle(color: SwiftUI.Color(hex: "#C8A165").opacity(0.15), radius: 12, x: 0, y: 4)
        static let glowAccent = ShadowStyle(color: SwiftUI.Color(hex: "#213B2E").opacity(0.12), radius: 10, x: 0, y: 4)
        static let neon     = ShadowStyle(color: SwiftUI.Color(hex: "#D4AF37").opacity(0.15), radius: 12, x: 0, y: 3)
        static let none     = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
    }

    struct ShadowStyle {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: Animation — أنيميشن ديناميكية
    enum Anim {
        static let bouncy    = Animation.spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0)
        static let snappy    = Animation.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)
        static let smooth    = Animation.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)
        static let elastic   = Animation.spring(response: 0.45, dampingFraction: 0.55, blendDuration: 0)
        static let quick     = Animation.easeOut(duration: 0.2)
        static let medium    = Animation.easeInOut(duration: 0.35)
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
                        if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
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
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
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
            .font(.system(size: iconSize, weight: .bold))
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
                .font(.system(size: 13, weight: .bold))
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

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }
            Text(title)
                .font(DS.Font.footnote)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
                .textCase(.uppercase)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.primary)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xs)
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
                .font(.system(size: 26, weight: .bold))
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
                    .font(.system(size: 20, weight: .black))
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
