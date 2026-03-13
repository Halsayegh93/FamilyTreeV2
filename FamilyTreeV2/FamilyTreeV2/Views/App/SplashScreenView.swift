import SwiftUI

struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dotCount = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // خلفية
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                // اللوقو مع حلقة متحركة
                ZStack {
                    // حلقة نبض خارجية
                    Circle()
                        .stroke(DS.Color.primary.opacity(0.15), lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)

                    // دائرة خارجية
                    Circle()
                        .fill(DS.Color.primary.opacity(0.08))
                        .frame(width: 120, height: 120)

                    // الدائرة الرئيسية
                    Circle()
                        .fill(DS.Color.gradientRoyal)
                        .frame(width: 100, height: 100)

                    Image(systemName: "leaf.fill")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                }
                .dsGlowShadow()
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // النصوص
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("عائلة المحمد علي", "Al-Muhammad Ali Family"))
                        .font(DS.Font.title1)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(L10n.t("شجرة العائلة", "Family Tree"))
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .opacity(textOpacity)

                Spacer()

                // مؤشر التحميل
                VStack(spacing: DS.Spacing.md) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(DS.Color.primary)
                        .scaleEffect(1.2)

                    Text(L10n.t("جاري التحقق", "Verifying") + String(repeating: ".", count: dotCount))
                        .font(DS.Font.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: 140)
                }
                .opacity(textOpacity)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            // أنيميشن اللوقو
            withAnimation(DS.Anim.elastic) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // أنيميشن النص
            withAnimation(DS.Anim.smooth.delay(0.2)) {
                textOpacity = 1.0
            }

            // أنيميشن النبض المتكرر
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
        // أنيميشن النقاط المتحركة
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                dotCount = (dotCount % 3) + 1
            }
        }
    }
}
