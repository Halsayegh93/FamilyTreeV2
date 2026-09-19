import SwiftUI

/// علامة المعلومات بجانب جرس الرئيسية — تفتح مربّع «عن التطبيق»:
/// اسم منفّذ التطبيق ورقم الإصدار مع زر إغلاق. (انتقلت من صفحة التواصل — طلب المالك)
struct HomeInfoButton: View {
    @State private var showInfo = false

    var body: some View {
        Button {
            // بلا انزلاق من الأسفل — المربّع يظهر بنفسه في منتصف الشاشة
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { showInfo = true }
        } label: {
            // نفس حجم الجرس (22) وعرض أضيق ليقترب منه
            Image(systemName: "info.circle")
                .font(DS.Font.scaled(22, weight: .semibold))
                .foregroundStyle(DS.Color.textOnPrimary)
                .frame(width: 32, height: 44)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(L10n.t("عن التطبيق", "About the app"))
        .fullScreenCover(isPresented: $showInfo) {
            AppInfoPopup {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { showInfo = false }
            }
            .background(ClearPresentationBackground())
        }
    }
}

/// مربّع في منتصف الشاشة فوق خلفية معتمة — يغلق بالزر أو بالضغط خارجه
private struct AppInfoPopup: View {
    let onClose: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            AppInfoSheet(onClose: close)
                .frame(maxWidth: 340)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
                .padding(.horizontal, DS.Spacing.xl)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(DS.Anim.snappy) { appeared = true } }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }
}

/// يجعل خلفية fullScreenCover شفافة (يعمل من iOS 16) — مشترك مع مربّعات الرسائل الوسطية
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

/// مربّع معلومات التطبيق — المنفّذ والإصدار وزر الإغلاق
struct AppInfoSheet: View {
    let onClose: () -> Void

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            HStack {
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(DS.Color.mutedBackground))
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("إغلاق", "Close"))
            }

            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)

            VStack(spacing: 4) {
                Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"))
                    .font(DS.Font.plex(18, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                    .font(DS.Font.plex(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }

            // المنفّذ في المنتصف بلا مربّع، وتحته السطر نفسه بالإنجليزية (طلب المالك)
            VStack(spacing: 3) {
                Text("عمل هذا التطبيق")
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                Text("حسن الصايغ")
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text("Made by Hasan Al-Sayegh")
                    .font(DS.Font.plex(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)

            Button { onClose() } label: {
                Text(L10n.t("إغلاق", "Close"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.primary.opacity(0.10))
                    )
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.lg)
        .background(DS.Color.background)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
