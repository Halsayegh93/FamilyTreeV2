import SwiftUI
import UIKit

/// حقل إدخال أرقام الهاتف — يستخدم UIKit مباشرة لتجنب مشكلة
/// SwiftUI RTL + LTR TextField التي تخفي النص عند أول كتابة
struct PhoneNumberTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = AppTypeface.uiFont(size: DS.TextRole.body.textSize, weight: .regular)
    var textStyle: UIFont.TextStyle = .body
    var keyboardType: UIKeyboardType = .numberPad
    var textAlignment: NSTextAlignment = .left
    var maxLength: Int = 15

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.placeholder = placeholder
        // يتبع «حجم النص» في الجهاز (يكبر ويصغر معه)
        tf.adjustsFontForContentSizeCategory = true
        tf.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        tf.keyboardType = keyboardType
        tf.textAlignment = textAlignment
        tf.textColor = UIColor(DS.Color.textPrimary)
        tf.tintColor = UIColor(DS.Color.primary)
        tf.semanticContentAttribute = .forceLeftToRight
        tf.textContentType = .telephoneNumber
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // The country can change while this UIKit field remains alive.
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        uiView.placeholder = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PhoneNumberTextField

        init(_ parent: PhoneNumberTextField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let range = Range(range, in: current) else { return false }
            let updated = current.replacingCharacters(in: range, with: string)

            // تنظيف: بس أرقام
            let digits = KuwaitPhone.normalizeDigits(updated).filter(\.isNumber)
            let limited = String(digits.prefix(parent.maxLength))

            parent.text = limited
            textField.text = limited
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// حقل هاتف موحّد لكل التطبيق — رقم العضو (يتمدّد) + كود الدولة على الجهة المقابلة
/// (يسار العدد في تخطيط LTR الداخلي = يمين الشاشة). اضغط الكود لاختيار الدولة.
///
/// يُستخدم في كل مكان يطلب رقم هاتف لضمان نفس النظام والتصميم.
struct DSPhoneField: View {
    @Binding var country: KuwaitPhone.Country
    @Binding var digits: String
    var placeholder: String = ""
    /// لتفعيل توهّج الحدّ عند التركيز (اختياري — يُمرَّر من الشاشة).
    var isFocused: Bool = false
    /// نسخة مصغّرة — ارتفاع وخطوط أصغر (مثلاً داخل فورم حسابي).
    var compact: Bool = false
    /// بدون إطار/خلفية — للاستخدام داخل صف على سطر واحد.
    var bordered: Bool = true

    /// نسبة «حجم النص» في الجهاز — الحقل يطول مع الخط الأكبر (ولا يقصر عن مقاسه تحت الافتراضي)
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    private var fieldHeight: CGFloat { (compact ? 44 : 56) * max(1, textScale) }
    private var innerHeight: CGFloat { (compact ? 30 : 40) * max(1, textScale) }
    /// أرقام الهاتف: سقف النص ١٧ (Body) — المضغوط ١٥ (طلب المالك ٢٠٢٦-١٠-٠٨؛ كانت ١٨)
    private var numberFontSize: CGFloat { compact ? DS.TextRole.subtitle.textSize : DS.TextRole.body.textSize }
    private var flagFontSize: CGFloat { compact ? 15 : 18 }

    var body: some View {
        HStack(spacing: 0) {
            // كود الدولة — على الجهة الأمامية، يفتح قائمة الدول
            Menu {
                ForEach(KuwaitPhone.supportedCountries) { c in
                    Button {
                        country = c
                    } label: {
                        Text("\(c.flag) \(c.nameArabic) (\(c.dialingCode))")
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Text(country.flag).font(DS.Font.scaled(flagFontSize))
                    Text(country.dialingCode)
                        .dsFont(compact ? .chip : .bodySemibold)
                        .foregroundStyle(DS.Color.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(DS.Font.icon(compact ? 9 : 10, weight: .bold))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                // مساحة ضغط ٤٤ نقطة (حد أبل) بلا تغيير ارتفاع الحقل
                .frame(minHeight: 44)
                .padding(.vertical, -((44 - (compact ? 20 : 24)) / 2))
                .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("رمز الدولة \(country.nameArabic) \(country.dialingCode)",
                                       "Country code \(country.dialingCode)"))

            // فاصل رأسي
            Capsule()
                .fill(DS.Color.textTertiary.opacity(DS.Opacity.divider))
                .frame(width: DS.Border.width, height: compact ? DS.Icon.countBadge : DS.Spacing.xxl)
                .padding(.horizontal, DS.Spacing.sm)

            // رقم العضو — يتمدّد لملء المساحة على الجهة المقابلة
            PhoneNumberTextField(
                text: $digits,
                placeholder: placeholder,
                font: AppTypeface.uiFont(size: numberFontSize, weight: .semibold),
                textStyle: compact ? .subheadline : .body,
                keyboardType: .numberPad,
                maxLength: country.maxDigits
            )
            .frame(maxWidth: .infinity)
            .frame(height: innerHeight)
        }
        .environment(\.layoutDirection, .leftToRight)
        .modifier(DSPhoneFieldChrome(
            bordered: bordered,
            isFocused: isFocused,
            height: fieldHeight,
            horizontalPadding: compact ? DS.Spacing.sm : DS.Spacing.md
        ))
    }
}

/// ارتفاع موحّد لصفوف النماذج (الاسم/الهاتف/التاريخ/متوفى/البريد).
let dsFormRowHeight: CGFloat = 52

/// مفتاح قياس ارتفاع محتوى الشيت لجعل الشيت بارتفاع المحتوى فقط.
struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// يطبّق الإطار/الخلفية للحقل المؤطّر، أو لا شيء للحقل بدون إطار (سطر واحد).
private struct DSPhoneFieldChrome: ViewModifier {
    let bordered: Bool
    let isFocused: Bool
    let height: CGFloat
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        if bordered {
            content
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(
                            isFocused ? DS.Color.primary.opacity(0.5) : DS.Color.inactiveBorder,
                            lineWidth: isFocused ? 1.5 : 1
                        )
                        .animation(DS.Anim.quick, value: isFocused)
                )
        } else {
            content
        }
    }
}
