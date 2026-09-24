import SwiftUI

/// حقل رمز التحقق — ستة مربّعات فوق حقل مخفي يحافظ على الملء التلقائي من
/// الرسائل (نفس شكل صفحة الدخول). يقبل الأرقام العربية ويحوّلها، ويستدعي
/// `onComplete` عند اكتمال الستة أرقام.
struct DSOTPField: View {
    @Binding var code: String
    var onComplete: (String) -> Void = { _ in }

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                // مخفي بصرياً لا وظيفياً — يبقى مستقبِلاً للوحة المفاتيح
                .opacity(0.001)
                .frame(height: 56)
                .accessibilityLabel(L10n.t("رمز التحقق", "Verification Code"))

            HStack(spacing: DS.Spacing.xs + 2) {
                ForEach(0..<6, id: \.self) { box(at: $0) }
            }
            // الرمز يُملأ من اليسار لليمين حتى مع واجهة عربية
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .onChange(of: code) { newValue in
            let limited = String(KuwaitPhone.normalizeDigits(newValue).filter(\.isNumber).prefix(6))
            if newValue != limited { code = limited; return }
            if limited.count == 6 {
                focused = false
                onComplete(limited)
            }
        }
    }

    private func box(at index: Int) -> some View {
        let chars = Array(code)
        let digit = index < chars.count ? String(chars[index]) : ""
        let isActive = focused && index == min(chars.count, 5)
        let isFilled = !digit.isEmpty

        return Text(digit)
            .font(DS.Font.plex(22, weight: .bold))
            .foregroundColor(DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(
                        isActive ? DS.Color.primary
                        : isFilled ? DS.Color.primary.opacity(0.35)
                        : DS.Color.inactiveBorder,
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .overlay {
                if isActive && !isFilled {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(DS.Color.primary)
                        .frame(width: 2, height: 20)
                        .opacity(0.8)
                }
            }
            .animation(DS.Anim.quick, value: isActive)
            .animation(DS.Anim.quick, value: isFilled)
    }
}
