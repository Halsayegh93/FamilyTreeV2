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
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
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
