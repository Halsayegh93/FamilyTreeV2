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

/// مقاس زر الرأس — مكان واحد (طلب المالك ٢٠٢٦-١٠-٠٧ «شريط الأدوات في الشجرة في السابق كان حجمه أفضل»)
enum DSNavButtonSize {
    /// المقاس الأساسي: فوق الرأس الملوّن ٤٤ (المضغوط ٣٦)، وفوق السطح ٣٨ — داخل إطار ٤٤×٤٤
    case regular
    /// شريط أدوات فوق السطح (شريط الشجرة العلوي): دائرة ٣٤ ورمز ١٤
    case toolbar
    /// الأصغر: الشريط الجانبي للشجرة (الأفقي) ٢٧ ورمز ١٢؛ وفوق سطح ملوّن «×» صغير بلا قرص (بانر صلة القرابة)
    case mini
}

/// شكل الزر وحده (الرمز ودائرته) — لمن يحتاج زر رأس بنفس الهوية ورمز آخر
struct DSNavButtonLabel: View {
    let symbol: String
    var context: DSNavButtonContext = .surface
    /// الوضع الأفقي في الرؤوس الملوّنة — دائرة ٣٦ ورمز ١٥ (مثل MainHeaderView)؛ فوق السطح = `.toolbar`
    var compact: Bool = false
    /// داخل شريط أدوات النظام: في iOS 26+ يرسم النظام الدائرة الزجاجية فيبقى الرمز وحده
    var inToolbar: Bool = false
    /// `.toolbar` / `.mini`: الدائرة أصغر، والتخطيط بمقاسها المرئي (مساحة الضغط ٤٤ لا تزيد الارتفاع)
    var size: DSNavButtonSize = .regular
    /// لون رمز السطح — nil = لون النص (شريط الشجرة: حبر قسمها)
    var tint: Color? = nil

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

    /// المقاس الفعلي: `compact` فوق السطح/الصورة = `.toolbar` (فوق الرأس الملوّن يبقى المضغوط ٣٦)
    private var resolvedSize: DSNavButtonSize {
        if size == .regular, compact, context != .onColor { return .toolbar }
        return size
    }

    // المقاسات من `DSBox.nav*` — مكان واحد لأزرار الرجوع والإغلاق والإجراء
    private var glyphSize: CGFloat {
        switch resolvedSize {
        case .toolbar: return DSBox.navGlyphToolbar
        case .mini: return context == .onColor ? DSBox.navGlyphMiniOnColor : DSBox.navGlyphMini
        case .regular:
            switch context {
            case .onColor: return compact ? DSBox.navGlyphCompact : DSBox.navGlyph
            case .surface, .onMedia: return DSBox.navGlyphSurface
            }
        }
    }

    private var diameter: CGFloat {
        switch resolvedSize {
        case .toolbar: return DSBox.navButtonToolbar
        case .mini: return DSBox.navButtonMini
        case .regular:
            switch context {
            case .onColor: return compact ? DSBox.navButtonCompact : DSBox.navButtonOnColor
            case .surface, .onMedia: return DSBox.navButtonSurface
            }
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(DS.Font.scaled(glyphSize, weight: .bold))
            .foregroundColor(context == .surface ? (tint ?? DS.Color.textPrimary) : DS.Color.textOnPrimary)
            // الدائرة ثابتة المقاس — الرمز لا يتجاوزها مع الخطوط الكبيرة جداً
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// إطار الضغط: المقاس الأساسي داخل ٤٤×٤٤؛ الأصغر بمقاسه المرئي ومساحة ضغط ٤٤ لا تدخل التخطيط
    @ViewBuilder
    private func tapFrame<V: View>(_ v: V) -> some View {
        if resolvedSize == .regular {
            v.frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        } else {
            v.dsTapArea(width: diameter, height: diameter)
        }
    }

    @ViewBuilder
    private var circled: some View {
        switch context {
        case .onColor:
            if resolvedSize == .mini {
                // «×» صغير داخل دائرة ممتلئة شفافة فوق اللون (كان `xmark.circle.fill` ١٨ في بانر صلة القرابة)
                Image(systemName: Self.filledCircle(symbol))
                    .font(DS.Font.scaled(glyphSize, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary.opacity(DSBox.navGlyphMiniOnColorOpacity))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .dsTapArea(width: glyphSize, height: glyphSize)
            } else {
                tapFrame(glyph
                    .frame(width: diameter, height: diameter)
                    .dsHeaderGlassCircle())
            }
        case .surface:
            tapFrame(glyph
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(DS.Color.mutedBackground))
                // زجاج تحت الرمادي: يبقى واضحاً فوق المحتوى المتحرّك تحته
                .dsGlass(Circle())
                .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.5)))
        case .onMedia:
            tapFrame(glyph
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(DS.Color.overlayDark.opacity(0.4)))
                .dsGlass(Circle()))
        }
    }

    /// نفس الرمز داخل دائرة ممتلئة (`xmark` ← `xmark.circle.fill`) إن وُجد
    private static func filledCircle(_ symbol: String) -> String {
        let filled = symbol + ".circle.fill"
        return UIImage(systemName: filled) != nil ? filled : symbol
    }
}

extension View {
    /// مساحة ضغط ٤٤ (حدّ أبل) حول عنصر أصغر — **بلا** أن تكبّر التخطيط: تتمدّد الحشوة للضغط ثم تُلغى للتخطيط
    func dsTapArea(width: CGFloat, height: CGFloat) -> some View {
        let h = max(0, (DS.Icon.tapTarget - height) / 2)
        let w = max(0, (DS.Icon.tapTarget - width) / 2)
        return self
            .padding(.vertical, h)
            .padding(.horizontal, w)
            .contentShape(Rectangle())
            .padding(.vertical, -h)
            .padding(.horizontal, -w)
    }
}

/// زر الإغلاق الموحّد (×)
struct DSCloseButton: View {
    var context: DSNavButtonContext = .surface
    var compact: Bool = false
    var inToolbar: Bool = false
    var size: DSNavButtonSize = .regular
    /// نص القارئ الصوتي
    var label: String = L10n.t("إغلاق", "Close")
    let action: () -> Void

    var body: some View {
        DSNavButton(symbol: "xmark", context: context, compact: compact,
                    inToolbar: inToolbar, size: size, label: label, action: action)
    }
}

/// زر الرجوع الموحّد — السهم نحو بداية السطر (مثل رؤوس الصفحات الفرعية)
struct DSBackButton: View {
    /// رمز الرجوع حسب اللغة — يمين في العربية، يسار في الإنجليزية
    static var symbol: String { L10n.isArabic ? "chevron.right" : "chevron.left" }

    var context: DSNavButtonContext = .surface
    var compact: Bool = false
    var size: DSNavButtonSize = .regular
    /// نص القارئ الصوتي
    var label: String = L10n.t("رجوع", "Back")
    let action: () -> Void

    var body: some View {
        DSNavButton(symbol: Self.symbol, context: context, compact: compact,
                    inToolbar: false, size: size, label: label, action: action)
    }
}

/// زرّ إجراء في الرأس الملوّن (تحديد، إضافة، تصفية…) — نفس دائرة الرجوع/الإغلاق الزجاجية وضغطتها.
/// يوضع في `trailing:` لرأس الصفحة الفرعية (`DSSubPageHeader`) أو `MainHeaderView`.
struct DSHeaderButton: View {
    let symbol: String
    /// نص القارئ الصوتي
    let label: String
    var context: DSNavButtonContext = .onColor
    var compact: Bool = false
    /// `.toolbar` (شريط أدوات الشجرة) / `.mini` (شريطها الجانبي) — انظر `DSNavButtonSize`
    var size: DSNavButtonSize = .regular
    /// لون رمز السطح — nil = لون النص
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        DSNavButton(symbol: symbol, context: context, compact: compact,
                    inToolbar: false, size: size, tint: tint, label: label, action: action)
    }
}

private struct DSNavButton: View {
    let symbol: String
    let context: DSNavButtonContext
    let compact: Bool
    let inToolbar: Bool
    var size: DSNavButtonSize = .regular
    var tint: Color? = nil
    let label: String
    let action: () -> Void

    var body: some View {
        let content = DSNavButtonLabel(symbol: symbol, context: context,
                                       compact: compact, inToolbar: inToolbar, size: size, tint: tint)
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
