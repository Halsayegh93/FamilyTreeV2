import SwiftUI

// MARK: - أزرار الرجوع والإغلاق الموحّدة
//
// طلب المالك ٢٠٢٦-١٠-٠٥: «ازرار الرجوع و الالغاء علامة X مو متناسقة الالوان».
// شكل واحد لكل سياق — لا ألوان تُختار في كل شاشة:
// • `.onColor` فوق رأس ملوّن (تدرّج القسم، رأس المربّع): رمز أبيض ١٨ عريض على دائرة الهيدر
//   الزجاجية `dsHeaderGlassCircle()` قطرها ٤٤ — نفس أزرار `MainHeaderView` (المضغوط ٣٦/١٥ للأفقي).
// • `.surface` فوق سطح فاتح/داكن (مربّعات، أوراق، صفحات): رمز بلون النص ١٤ عريض على دائرة رمادية
//   خافتة زجاجية قطرها ٣٨ بإطار شعري.
// • `.onMedia` فوق صورة أو كاميرا (عارض الصور): رمز أبيض ١٤ عريض على دائرة داكنة زجاجية ٣٨.
// مساحة الضغط ٤٤×٤٤ دائماً (توصية أبل). الرجوع سهم نحو بداية السطر: يمين في العربية ويسار في الإنجليزية.
// الحذف والرفض ليسا إغلاقاً — يبقيان بألوان معانيهما (الأحمر)، ومسح نص الحقل يبقى × الرمادي الصغير.

/// سياق زر الرجوع/الإغلاق — يحدّد الألوان والمقاس معاً
enum DSNavButtonContext {
    /// فوق سطح فاتح/داكن: بطاقات، مربّعات، أوراق، صفحات
    case surface
    /// فوق رأس ملوّن: تدرّج القسم، رأس المربّع
    case onColor
    /// فوق صورة أو كاميرا: عارض الصور، الماسح
    case onMedia
}

/// شكل الزر وحده (الرمز ودائرته) — لمن يحتاج زر رأس بنفس الهوية ورمز آخر
struct DSNavButtonLabel: View {
    let symbol: String
    var context: DSNavButtonContext = .surface
    /// الوضع الأفقي في الرؤوس الملوّنة — دائرة ٣٦ ورمز ١٥ (مثل MainHeaderView)
    var compact: Bool = false
    /// داخل شريط أدوات النظام: في iOS 26+ يرسم النظام الدائرة الزجاجية فيبقى الرمز وحده
    var inToolbar: Bool = false

    var body: some View {
        if inToolbar {
            if #available(iOS 26.0, *) {
                glyph
            } else {
                circled
            }
        } else {
            circled
        }
    }

    private var glyphSize: CGFloat {
        switch context {
        case .onColor: return compact ? 15 : 18
        case .surface, .onMedia: return 14
        }
    }

    private var diameter: CGFloat {
        switch context {
        case .onColor: return compact ? 36 : 44
        case .surface, .onMedia: return 38
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(DS.Font.scaled(glyphSize, weight: .bold))
            .foregroundColor(context == .surface ? DS.Color.textPrimary : DS.Color.textOnPrimary)
            // الدائرة ثابتة المقاس — الرمز لا يتجاوزها مع الخطوط الكبيرة جداً
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var circled: some View {
        switch context {
        case .onColor:
            glyph
                .frame(width: diameter, height: diameter)
                .dsHeaderGlassCircle()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        case .surface:
            glyph
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(DS.Color.mutedBackground))
                // زجاج تحت الرمادي: يبقى واضحاً فوق المحتوى المتحرّك تحته
                .dsGlass(Circle())
                .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        case .onMedia:
            glyph
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(DS.Color.overlayDark.opacity(0.4)))
                .dsGlass(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

/// زر الإغلاق الموحّد (×)
struct DSCloseButton: View {
    var context: DSNavButtonContext = .surface
    var compact: Bool = false
    var inToolbar: Bool = false
    /// نص القارئ الصوتي
    var label: String = L10n.t("إغلاق", "Close")
    let action: () -> Void

    var body: some View {
        DSNavButton(symbol: "xmark", context: context, compact: compact,
                    inToolbar: inToolbar, label: label, action: action)
    }
}

/// زر الرجوع الموحّد — السهم نحو بداية السطر (مثل رؤوس الصفحات الفرعية)
struct DSBackButton: View {
    /// رمز الرجوع حسب اللغة — يمين في العربية، يسار في الإنجليزية
    static var symbol: String { L10n.isArabic ? "chevron.right" : "chevron.left" }

    var context: DSNavButtonContext = .surface
    var compact: Bool = false
    /// نص القارئ الصوتي
    var label: String = L10n.t("رجوع", "Back")
    let action: () -> Void

    var body: some View {
        DSNavButton(symbol: Self.symbol, context: context, compact: compact,
                    inToolbar: false, label: label, action: action)
    }
}

private struct DSNavButton: View {
    let symbol: String
    let context: DSNavButtonContext
    let compact: Bool
    let inToolbar: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        let content = DSNavButtonLabel(symbol: symbol, context: context,
                                       compact: compact, inToolbar: inToolbar)
        if inToolbar {
            // شريط الأدوات بنمطه الافتراضي — حتى لا يُفقد زجاج النظام في iOS 26+
            Button(action: action) { content }
                .accessibilityLabel(label)
        } else if context == .onColor {
            // نفس ضغطة أزرار الرأس الملوّن المجاورة (MainHeaderView)
            Button(action: action) { content }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel(label)
        } else {
            Button(action: action) { content }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(label)
        }
    }
}
