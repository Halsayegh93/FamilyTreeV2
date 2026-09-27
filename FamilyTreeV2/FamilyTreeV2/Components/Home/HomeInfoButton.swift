import SwiftUI

/// علامة المعلومات بجانب جرس الرئيسية — تفتح مربّع «التعليمات» (دليل سريع لكل قسم،
/// وفي آخره «عن التطبيق»: الاسم والإصدار والمنفّذ) — طلب المالك ٢٠٢٦-٠٩-٢٧
struct HomeInfoButton: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showGuide = false

    var body: some View {
        Button {
            showGuide = true
        } label: {
            // نفس حجم الجرس (22) وعرض أضيق ليقترب منه
            Image(systemName: "info.circle")
                .font(DS.Font.scaled(22, weight: .semibold))
                .foregroundStyle(DS.Color.textOnPrimary)
                .frame(width: 32, height: 44)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(L10n.t("التعليمات", "Instructions"))
        .dsCenterBox(isPresented: $showGuide, onBackgroundTap: { showGuide = false }) {
            AppGuideBox()
                .environmentObject(authVM)
        }
    }
}

/// يجعل خلفية fullScreenCover شفافة (يعمل من iOS 16) — مستخدم في مربّع «تجاوز حد التعديلات»
struct ClearPresentationBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
