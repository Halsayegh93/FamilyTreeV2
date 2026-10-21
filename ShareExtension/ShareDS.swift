import SwiftUI
import UIKit

// MARK: - مرآة «المكان الواحد» داخل امتداد المشاركة
//
// الامتداد هدف مستقل لا يستورد وحدة التطبيق (ولا تُبنى ملفات DS هناك بمفردها — تعتمد على
// مكتبة المجسّمات والبيئة والأقسام). فهنا نسخة صغيرة من القيم التي يحتاجها مربّع الرفع فقط.
// ⚠️ مصدر الحقيقة في التطبيق — أي تغيير هناك يُنقل هنا:
//   • الألوان: `Components/Shared/AppSection.swift` ← `.home` «البحري الخفيف» (٢٠٢٦-١٠-٠٧)،
//     ونصوص/أسطح `DS.Color` في `Components/Shared/DesignSystem.swift`
//   • الخط وأدوار النص: `DS.Font.plex` / `DS.TextRole` (Cairo — الخطوط نفسها من
//     `FamilyTreeV2/Resources/Fonts`، مضمومة لهدف الامتداد في المشروع + `UIAppFonts`)
//   • المربّع والبطاقة والأزرار: `DSBox`، `DS.Card` / `.dsCard()`، `DSBoxButtonStyle`،
//     `DSComposerHeader`، `DSComposerSection`، `DSComposerField`، `DSOptionTiles`، `FT5SGlyph.button`
enum ShareDS {

    // MARK: الألوان
    enum Palette {
        // الرئيسية «البحري الخفيف» — (فاتح، داكن) كما في `AppSection.home`
        static let deep    = adaptive("#244771", "#1E3856")
        static let fill    = adaptive("#3A6DA6", "#2A4E78")
        static let light   = adaptive("#3E74B2", "#305988")
        static let ink     = adaptive("#326297", "#91B5DE")

        // `DS.Color`
        static let background    = Color(.systemBackground)
        static let surface       = Color(.secondarySystemBackground)
        static let textPrimary   = adaptive("#0A0E18", "#F0F4FF")
        static let textSecondary = adaptive("#5A6070", "#8A90A0")
        static let textTertiary  = adaptive("#6B7280", "#8A93A0")
        static let fieldLabel    = adaptive("#03070F", "#FFFFFF")
        static let fieldValue    = adaptive("#414958", "#C4CAD6")
        static let error         = adaptive("#D32F2F", "#EF5350")
        static let success       = adaptive("#157F3C", "#45BC72")
        static let warning       = adaptive("#9A6A0A", "#F0B040")
        /// زرّ الإلغاء الرمادي (`DS.Color.mutedBackground.opacity(0.8)`)
        static let cancelFill    = Color.gray.opacity(0.2 * 0.8)

        static func adaptive(_ light: String, _ dark: String) -> Color {
            Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        }
    }

    // MARK: الخط — Cairo بأدوار النص (`DS.TextRole`)
    // = مقاسات Apple الافتراضية (حجم النص «كبير») مقيّدة بنمطها — تتبع «حجم النص» في الجهاز
    // (طلب المالك ٢٠٢٦-١٠-٠٨ «حجم الخط الافتراضي في الآيفون»)
    struct TextRole {
        let size: CGFloat
        let weight: Font.Weight
        let style: Font.TextStyle

        init(_ style: Font.TextStyle, weight: Font.Weight = .regular) {
            self.size = Typeface.appleSize(style)
            self.weight = weight
            self.style = style
        }

        static let title           = TextRole(.headline, weight: .bold)      // عنوان رأس المربّع — ١٧
        static let subtitle        = TextRole(.subheadline)                  // وصف رأس المربّع — ١٥
        static let headline        = TextRole(.headline, weight: .bold)      // ١٧
        static let body            = TextRole(.body)                         // ١٧
        static let rowTitle        = TextRole(.body, weight: .semibold)      // ١٧
        static let callout         = TextRole(.callout)                      // ١٦
        static let chip            = TextRole(.subheadline, weight: .semibold) // ١٥
        static let caption         = TextRole(.caption, weight: .semibold)   // ١٢
        static let footnote        = TextRole(.footnote)                     // ١٣
        static let boxSectionTitle = TextRole(.footnote, weight: .bold)      // ١٣
        static let fieldLabel      = TextRole(.footnote, weight: .heavy)     // `DSBox.fieldLabelSize` — ١٣
        static let fieldValue      = TextRole(.body)                         // `DSBox.fieldValueSize` — ١٧
        static let button          = TextRole(.body, weight: .semibold)      // ١٧
    }

    enum Typeface {
        static let regular  = AppTypeface.regular
        static let medium   = AppTypeface.medium
        static let semibold = AppTypeface.semibold
        static let bold     = AppTypeface.bold

        static func name(_ weight: Font.Weight) -> String {
            AppTypeface.name(for: weight)
        }

        /// = `DS.Font.plex` (مع Dynamic Type)
        static func plex(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom(name(weight), size: size, relativeTo: textStyle(for: size))
        }

        /// = `DS.Font.opticalScale` — مطابقة خط الآيفون بالعين (خط الهوية أكبر بصرياً بنفس الرقم)
        static let opticalScale: CGFloat = 0.9

        /// = `DS.Font.role` — حجم Apple الافتراضي للدور × معامل المطابقة، مقيّداً بنمطه
        static func role(_ role: TextRole) -> Font {
            .custom(name(role.weight), size: role.size * opticalScale, relativeTo: role.style)
        }

        /// = `DS.Font.appleSize`
        static func appleSize(_ style: Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle:  return 34
            case .title:       return 28
            case .title2:      return 22
            case .title3:      return 20
            case .headline:    return 17
            case .body:        return 17
            case .callout:     return 16
            case .subheadline: return 15
            case .footnote:    return 13
            case .caption:     return 12
            case .caption2:    return 11
            @unknown default:  return 17
            }
        }

        /// = `DS.Font.textStyle(for:)`
        static func textStyle(for size: CGFloat) -> Font.TextStyle {
            switch size {
            case ..<11.5: return .caption2
            case ..<12.5: return .caption
            case ..<14:   return .footnote
            case ..<15.5: return .subheadline
            case ..<16.5: return .callout
            case ..<18.5: return .body
            case ..<21:   return .title3
            case ..<25:   return .title2
            case ..<31:   return .title
            default:      return .largeTitle
            }
        }
    }

    // MARK: المقاسات (`DS.Spacing` / `DS.Radius` / `DS.Opacity` / `DS.Glyph` / `DS.Icon`)
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat  = 4
        static let xsm: CGFloat = 6
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 12
        static let lg: CGFloat  = 16
    }

    enum Radius {
        static let md: CGFloat = 12
    }

    enum Opacity {
        static let tintFillSoft: Double   = 0.08
        static let tintFill: Double       = 0.12
        static let border: Double         = 0.12
        static let cardStroke: Double     = 0.10
        static let fieldStroke: Double    = 0.15
        static let focusStroke: Double    = 0.65
        static let selectedStroke: Double = 0.55
        static let disabled: Double       = 0.45   // `DSActionFill.disabledOpacity`
    }

    enum Glyph {
        static let xs: CGFloat = 10.5
        static let sm: CGFloat = 12
        static let md: CGFloat = 14
        static let lg: CGFloat = 16
    }

    enum Icon {
        /// قرص الخيار (`DS.Icon.sizeSm`)
        static let option: CGFloat = 38
        /// قرص صفّ الملف (`DS.Icon.row`)
        static let row: CGFloat = 32
        /// قرص الحالة (نجاح/فشل — `DS.Icon.state`)
        static let state: CGFloat = 52
    }

    // MARK: المربّع (`DSBox`)
    enum Box {
        static let headerHeight: CGFloat = 80
        static let headerIcon: CGFloat = 40          // `DSBox.composerIcon`
        static let headerWatermark: CGFloat = 118
        static let headerWatermarkOpacity: Double = 0.22
        static let headerWatermarkAngle: Double = -18
        static let headerDarkScrim: Double = 0.3
        static let headerSubtitleOpacity: Double = 0.86
        static let contentPadding: CGFloat = 11
        static let contentTop: CGFloat = 8
        static let contentBottom: CGFloat = 6
        static let sectionSpacing: CGFloat = 8
        static let sectionPadding: CGFloat = 8       // = `DS.Card.padding`
        static let sectionRadius: CGFloat = 12       // = `DS.Card.radius`
        /// زاويتا المربّع العلويتان (مثل شيت النظام / `DSBox.radius`)
        static let cardRadius: CGFloat = 24
        static let sectionInnerSpacing: CGFloat = 7
        static let sectionIcon: CGFloat = 16
        static let fieldIcon: CGFloat = 22
        static let fieldVerticalPadding: CGFloat = 4
        static let fieldHorizontalPadding: CGFloat = 7
        static let fieldMinHeight: CGFloat = 36
        static let iconRadius: CGFloat = 8           // `DS.Icon.discRadiusSmall`
        static let buttonHeight: CGFloat = 44
        static let buttonRadius: CGFloat = 12
        static let buttonSpacing: CGFloat = 7
        static let buttonLabelMinScale: CGFloat = 0.7
        static let footerHorizontal: CGFloat = 11
        static let footerTop: CGFloat = 6
        static let footerBottom: CGFloat = 8
        static let pressScale: CGFloat = 0.97
        /// الدوّارة داخل الزرّ (`DS.Spinner.buttonScale`)
        static let spinnerScale: CGFloat = 0.85
        /// هامش أسفل الأزرار فوق شريط الهوم حين لا تظهر لوحة المفاتيح (كان ٢٠ في الامتداد)
        static let homeBarClearance: CGFloat = 20

        static var sectionShape: RoundedRectangle { RoundedRectangle(cornerRadius: sectionRadius, style: .continuous) }
        static var buttonShape: RoundedRectangle { RoundedRectangle(cornerRadius: buttonRadius, style: .continuous) }
    }

    // MARK: لمسة الطين على البطاقات (`DS.Card` + `TrialCardSkin`)
    enum Card {
        static let strokeWidth: CGFloat = 1
        static let highlightLight: Double = 0.9
        static let highlightDark: Double = 0.12
        static let highlightWidth: CGFloat = 1.5
        static let shadowLight: Double = 0.10
        static let shadowDark: Double = 0.35
        static let shadowRadius: CGFloat = 6
        static let shadowY: CGFloat = 3
    }

    // MARK: الحركة (`DSMotion.press`)
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.72)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

private extension UIColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - المكوّنات (نسخ مصغّرة من مكوّنات التطبيق)

extension View {
    func shareFont(_ role: ShareDS.TextRole) -> some View { font(ShareDS.Typeface.role(role)) }

    func shareGlyph(_ size: CGFloat) -> some View { font(.system(size: size, weight: .bold)) }

    /// = `.dsCard()`: سطح + إطار شعري + لمسة الطين
    func shareCard(padding: CGFloat? = ShareDS.Box.sectionPadding, fill: Color = ShareDS.Palette.surface) -> some View {
        modifier(ShareCardModifier(padding: padding, fill: fill))
    }

    /// = `.trialCardSkin(radius:)`: لمعة علوية + ظلّ بلون غامق القسم
    func shareClaySkin(radius: CGFloat) -> some View { modifier(ShareClaySkin(radius: radius)) }
}

struct ShareClaySkin: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .overlay(
                shape.stroke(LinearGradient(colors: [.white.opacity(dark ? ShareDS.Card.highlightDark : ShareDS.Card.highlightLight), .clear],
                                            startPoint: .top, endPoint: .center),
                             lineWidth: ShareDS.Card.highlightWidth)
                    .padding(ShareDS.Card.highlightWidth / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .shadow(color: ShareDS.Palette.deep.opacity(dark ? ShareDS.Card.shadowDark : ShareDS.Card.shadowLight),
                    radius: ShareDS.Card.shadowRadius, x: 0, y: ShareDS.Card.shadowY)
    }
}

struct ShareCardModifier: ViewModifier {
    var padding: CGFloat?
    var fill: Color

    func body(content: Content) -> some View {
        let shape = ShareDS.Box.sectionShape
        return content
            .padding(padding ?? 0)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(ShareDS.Palette.textTertiary.opacity(ShareDS.Opacity.cardStroke),
                                        lineWidth: ShareDS.Card.strokeWidth))
            .shareClaySkin(radius: ShareDS.Box.sectionRadius)
    }
}

/// = `FT5SGlyph.button` (قرص «الطين الصقيل»): وجه بلون القسم وظهر أغمق تحته، لمعة علوية، ورمز أبيض
struct ShareClayDisc: View {
    let icon: String
    var tint: Color = ShareDS.Palette.fill
    var size: CGFloat = ShareDS.Icon.row
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let face = size * 0.84
        let depth = max(1.5, size * 0.06)
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(dark ? 0.5 : 0.2))
                .frame(width: face * 0.76, height: face * 0.16)
                .blur(radius: face * 0.05)
                .offset(y: face / 2 + depth - face * 0.04)
            Circle().fill(tint).frame(width: face, height: face).offset(y: depth)
            Circle().fill(Color.black.opacity(dark ? 0.34 : 0.26)).frame(width: face, height: face).offset(y: depth)
            Circle()
                .fill(tint)
                .overlay(
                    Ellipse()
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .center))
                        .frame(width: face, height: face)
                        .offset(x: -face * 0.25, y: -face * 0.6)
                )
                .clipShape(Circle())
                .frame(width: face, height: face)
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .offset(y: -depth / 2)
        .accessibilityHidden(true)
    }
}

/// = `DSComposerHeader`: رأس المربّع الملوّن — تدرّج القسم (الأساسي ← الفاتح)، أيقونة على قرص زجاجي،
/// عنوان أبيض ووصفه، ونسخة كبيرة مائلة شفافة من الأيقونة في الطرف الآخر
struct ShareBoxHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Image(systemName: icon)
                .font(.system(size: ShareDS.Box.headerWatermark * 0.62, weight: .bold))
                .foregroundColor(.white)
                .frame(width: ShareDS.Box.headerWatermark, height: ShareDS.Box.headerWatermark)
                .rotationEffect(.degrees(ShareDS.Box.headerWatermarkAngle))
                .opacity(ShareDS.Box.headerWatermarkOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: ShareDS.Spacing.lg + ShareDS.Spacing.xxs, y: ShareDS.Spacing.md + ShareDS.Spacing.xxs)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(spacing: ShareDS.Spacing.md) {
                ShareGlassDisc(icon: icon, side: ShareDS.Box.headerIcon)
                VStack(alignment: .leading, spacing: ShareDS.Spacing.xxs) {
                    Text(title)
                        .shareFont(.title)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .shareFont(.subtitle)
                        .foregroundColor(.white.opacity(ShareDS.Box.headerSubtitleOpacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ShareDS.Spacing.lg)
        }
        .frame(height: ShareDS.Box.headerHeight)
        .clipped()
        .background {
            LinearGradient(colors: [ShareDS.Palette.fill, ShareDS.Palette.light],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { if scheme == .dark { Color.black.opacity(ShareDS.Box.headerDarkScrim) } }
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)، \(subtitle)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// = `DSBoxIconDisc(onTint: true)`: قرص زجاجي أبيض خفيف فوق الرأس الملوّن
struct ShareGlassDisc: View {
    let icon: String
    let side: CGFloat

    var body: some View {
        let disc = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        ZStack {
            disc.fill(Color.white.opacity(0.16))
            disc.strokeBorder(Color.white.opacity(0.22), lineWidth: ShareDS.Card.strokeWidth)
            Image(systemName: icon)
                .shareGlyph(side * 0.42)
                .foregroundColor(.white)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// = `DSComposerSection`: بطاقة قسم داخل المربّع — قرص صغير + عنوان، ثم المحتوى
struct ShareSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ShareDS.Box.sectionInnerSpacing) {
            HStack(spacing: ShareDS.Box.sectionInnerSpacing) {
                ShareClayDisc(icon: icon, size: ShareDS.Box.sectionIcon)
                Text(title)
                    .shareFont(.boxSectionTitle)
                    .foregroundColor(ShareDS.Palette.fieldLabel)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shareCard()
    }
}

/// = `DSComposerField` داخل المربّع: قرص أيقونة + عنوان صغير فوق النص، وإطار يتلوّن عند الكتابة
struct ShareField: View {
    let icon: String
    let label: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        let ink = ShareDS.Palette.ink
        let shape = RoundedRectangle(cornerRadius: ShareDS.Radius.md, style: .continuous)
        return HStack(spacing: ShareDS.Spacing.sm) {
            Image(systemName: icon)
                .shareGlyph(ShareDS.Glyph.xs)
                .foregroundColor(focused ? .white : ink)
                .frame(width: ShareDS.Box.fieldIcon, height: ShareDS.Box.fieldIcon)
                .background(RoundedRectangle(cornerRadius: ShareDS.Box.iconRadius, style: .continuous)
                    .fill(focused ? ShareDS.Palette.fill : ink.opacity(ShareDS.Opacity.tintFill)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ShareDS.Spacing.xxs) {
                Text(label)
                    .shareFont(.fieldLabel)
                    .foregroundColor(focused ? ink : ShareDS.Palette.fieldLabel)
                TextField(placeholder, text: $text)
                    .shareFont(.fieldValue)
                    .foregroundColor(ShareDS.Palette.textPrimary)
                    .focused($focused)
            }
        }
        .padding(.horizontal, ShareDS.Box.fieldHorizontalPadding)
        .padding(.vertical, ShareDS.Box.fieldVerticalPadding)
        .frame(minHeight: ShareDS.Box.fieldMinHeight)
        .background(shape.fill(ShareDS.Palette.background))
        .overlay(shape.strokeBorder(focused ? ink.opacity(ShareDS.Opacity.focusStroke)
                                            : ShareDS.Palette.textTertiary.opacity(ShareDS.Opacity.fieldStroke),
                                    lineWidth: focused ? ShareDS.Card.highlightWidth : ShareDS.Card.strokeWidth))
        .shareClaySkin(radius: ShareDS.Radius.md)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

/// خيار في `ShareOptionTiles`
struct ShareOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let icon: String
}

/// = `DSOptionTiles`: شبكة اختيار واحد — قرص + اسم؛ المختار سطح بلونه الخفيف وإطاره وقرصه مجسّم ممتلئ
struct ShareOptionTiles<ID: Hashable>: View {
    let options: [ShareOption<ID>]
    @Binding var selection: ID
    var columns: Int = 4

    var body: some View {
        let cols = max(1, columns)
        VStack(spacing: ShareDS.Spacing.sm) {
            ForEach(Array(stride(from: 0, to: options.count, by: cols)), id: \.self) { start in
                let end = min(start + cols, options.count)
                HStack(spacing: ShareDS.Spacing.sm) {
                    ForEach(options[start..<end]) { tile($0) }
                    ForEach(0..<(cols - (end - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: ShareDS.Card.strokeWidth)
                    }
                }
            }
        }
    }

    private func tile(_ option: ShareOption<ID>) -> some View {
        let selected = selection == option.id
        let ink = ShareDS.Palette.ink
        let shape = RoundedRectangle(cornerRadius: ShareDS.Radius.md, style: .continuous)
        return Button {
            guard selection != option.id else { return }
            withAnimation(ShareDS.snappy) { selection = option.id }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: ShareDS.Spacing.xsm) {
                Group {
                    if selected {
                        ShareClayDisc(icon: option.icon, tint: ShareDS.Palette.fill, size: ShareDS.Icon.option)
                    } else {
                        Image(systemName: option.icon)
                            .shareGlyph(ShareDS.Glyph.lg)
                            .foregroundColor(ink)
                            .frame(width: ShareDS.Icon.option, height: ShareDS.Icon.option)
                            .background(Circle().fill(ink.opacity(ShareDS.Opacity.tintFill)))
                    }
                }
                .accessibilityHidden(true)
                Text(option.title)
                    .shareFont(.chip)
                    .foregroundColor(selected ? ink : ShareDS.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ShareDS.Spacing.sm)
            .background(shape.fill(selected ? ink.opacity(ShareDS.Opacity.tintFillSoft) : ShareDS.Palette.background))
            .overlay(shape.strokeBorder(selected ? ink.opacity(ShareDS.Opacity.selectedStroke)
                                                 : ShareDS.Palette.textTertiary.opacity(ShareDS.Opacity.border),
                                        lineWidth: selected ? ShareDS.Card.highlightWidth : ShareDS.Card.strokeWidth))
            .shareClaySkin(radius: ShareDS.Radius.md)
            .contentShape(shape)
        }
        .buttonStyle(SharePressStyle())
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// = `DSPressStyle`
struct SharePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ShareDS.Box.pressScale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(ShareDS.press, value: configuration.isPressed)
    }
}

/// = `DSBoxButtonStyle` (٤٤): الإجراء بتدرّج القسم ونص أبيض، الإلغاء رمادي — ضغطة واحدة
struct ShareButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil

    func makeBody(configuration: Configuration) -> some View {
        ShareButtonBody(configuration: configuration, role: role)
    }
}

private struct ShareButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: ButtonRole?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let cancel = role == .cancel
        configuration.label
            .shareFont(.button)
            .foregroundColor(cancel ? ShareDS.Palette.textPrimary : .white)
            .lineLimit(1)
            .minimumScaleFactor(ShareDS.Box.buttonLabelMinScale)
            .frame(maxWidth: .infinity)
            .frame(minHeight: ShareDS.Box.buttonHeight)
            .background {
                if cancel {
                    ShareDS.Box.buttonShape.fill(ShareDS.Palette.cancelFill)
                } else {
                    ShareDS.Box.buttonShape.fill(LinearGradient(colors: [ShareDS.Palette.deep, ShareDS.Palette.fill, ShareDS.Palette.light],
                                                                startPoint: .bottomTrailing, endPoint: .topLeading))
                }
            }
            .contentShape(ShareDS.Box.buttonShape)
            .opacity(isEnabled ? 1 : ShareDS.Opacity.disabled)
            .scaleEffect(configuration.isPressed ? ShareDS.Box.pressScale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(ShareDS.press, value: configuration.isPressed)
    }
}
