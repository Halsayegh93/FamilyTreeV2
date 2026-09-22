import SwiftUI

/// علامة المعلومات بجانب جرس الرئيسية — تفتح مربّع «عن التطبيق»:
/// اسم منفّذ التطبيق ورقم الإصدار مع زر إغلاق. (انتقلت من صفحة التواصل — طلب المالك)
struct HomeInfoButton: View {
    @State private var popupID: UUID?

    var body: some View {
        Button {
            // نفس مربّع الرسائل الموحّد (مثل «تم تجاوز حد التعديلات») — بلا ×، إغلاق فقط
            popupID = DSPopupPresenter.shared.show(
                AppInfoCard(onClose: { if let id = popupID { DSPopupPresenter.shared.hide(id) } })
            )
        } label: {
            // نفس حجم الجرس (22) وعرض أضيق ليقترب منه
            Image(systemName: "info.circle")
                .font(DS.Font.scaled(22, weight: .semibold))
                .foregroundStyle(DS.Color.textOnPrimary)
                .frame(width: 32, height: 44)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(L10n.t("عن التطبيق", "About the app"))
    }
}

/// مربّع «عن التطبيق» بتصميم الرسائل الموحّد: الأيقونة والاسم والإصدار والمنفّذ + زر «إغلاق»
struct AppInfoCard: View {
    let onClose: () -> Void

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        DSCenterCard(onBackgroundTap: onClose) {
            VStack(spacing: DS.Spacing.md) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)

                VStack(spacing: 4) {
                    Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"))
                        .font(DS.Font.plex(17, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                        .font(DS.Font.plex(13, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                }

                VStack(spacing: 3) {
                    Text("عمل هذا التطبيق")
                        .font(DS.Font.plex(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                    Text("حسن الصايغ")
                        .font(DS.Font.plex(16, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text("Made by Hasan Al-Sayegh")
                        .font(DS.Font.plex(13, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Button(action: onClose) {
                Text(L10n.t("إغلاق", "Close"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.primary))
            }
            .buttonStyle(DSScaleButtonStyle())
            .padding(.top, DS.Spacing.xs)
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
