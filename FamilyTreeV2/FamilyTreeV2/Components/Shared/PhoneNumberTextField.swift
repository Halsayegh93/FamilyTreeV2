import SwiftUI
import UIKit

/// حقل إدخال أرقام الهاتف — يستخدم UIKit مباشرة لتجنب مشكلة
/// SwiftUI RTL + LTR TextField التي تخفي النص عند أول كتابة
struct PhoneNumberTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = .systemFont(ofSize: 17, weight: .regular)
    var keyboardType: UIKeyboardType = .numberPad
    var textAlignment: NSTextAlignment = .left
    var maxLength: Int = 15

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.placeholder = placeholder
        tf.font = font
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
        uiView.font = font
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

    private var fieldHeight: CGFloat { compact ? 44 : 56 }
    private var innerHeight: CGFloat { compact ? 30 : 40 }
    private var numberFontSize: CGFloat { compact ? 15 : 18 }
    private var flagFontSize: CGFloat { compact ? 15 : 18 }
    private var codeFontSize: CGFloat { compact ? 13 : 15 }

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
                        .font(DS.Font.scaled(codeFontSize, weight: .bold))
                        .foregroundStyle(DS.Color.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(DS.Font.scaled(compact ? 9 : 10, weight: .bold))
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }

            // فاصل رأسي
            RoundedRectangle(cornerRadius: 1)
                .fill(DS.Color.textTertiary.opacity(0.3))
                .frame(width: 1, height: compact ? 20 : 24)
                .padding(.horizontal, DS.Spacing.sm)

            // رقم العضو — يتمدّد لملء المساحة على الجهة المقابلة
            PhoneNumberTextField(
                text: $digits,
                placeholder: placeholder,
                font: .systemFont(ofSize: numberFontSize, weight: .semibold),
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

/// صف نموذج موحّد — أيقونة + اسم الحقل على الجهة الأمامية ثم المحتوى،
/// بنفس الارتفاع والحجم في كل النماذج (إضافة/تعديل الأبناء + تعديل حسابي).
struct DSFormRow<Trailing: View>: View {
    let icon: String
    var iconColor: Color = DS.Color.primary
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColor)
            Text(label)
                .font(DS.Font.footnote)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
        .frame(height: dsFormRowHeight)
        .padding(.horizontal, DS.Spacing.lg)
    }
}

/// صف نموذج باسم الحقل **فوق** الحقل (عنوان صغير ثم الحقل تحته) — للحقول
/// النصية (الاسم/الهاتف/البريد).
struct DSLabeledFieldRow<Field: View>: View {
    let icon: String
    var iconColor: Color = DS.Color.primary
    let label: String
    @ViewBuilder var field: () -> Field

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                field()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }
}

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
