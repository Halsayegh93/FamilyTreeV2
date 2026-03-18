import SwiftUI

struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dotCount = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var ringRotation: Double = 0
    @State private var ring2Rotation: Double = 0
    @State private var shimmerOffset: CGFloat = -200
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            // خلفية
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                // اللوقو مع حلقات متحركة
                ZStack {
                    // حلقة دائرية تدور
                    Circle()
                        .trim(from: 0.0, to: 0.65)
                        .stroke(
                            AngularGradient(
                                colors: [DS.Color.primary.opacity(0.0), DS.Color.primary.opacity(0.3), DS.Color.primary.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 155, height: 155)
                        .rotationEffect(.degrees(ringRotation))

                    // حلقة ثانية عكسية
                    Circle()
                        .trim(from: 0.0, to: 0.4)
                        .stroke(
                            AngularGradient(
                                colors: [DS.Color.accent.opacity(0.0), DS.Color.accent.opacity(0.2), DS.Color.accent.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 145, height: 145)
                        .rotationEffect(.degrees(ring2Rotation))

                    // حلقة نبض خارجية
                    Circle()
                        .stroke(DS.Color.primary.opacity(0.12), lineWidth: 2.5)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)

                    // Glow ring
                    Circle()
                        .fill(DS.Color.primary.opacity(glowOpacity * 0.08))
                        .frame(width: 130, height: 130)
                        .blur(radius: 15)

                    // دائرة خارجية
                    Circle()
                        .fill(DS.Color.primary.opacity(0.08))
                        .frame(width: 120, height: 120)

                    // الدائرة الرئيسية
                    Circle()
                        .fill(DS.Color.gradientRoyal)
                        .frame(width: 100, height: 100)
                        .shadow(color: DS.Color.primary.opacity(0.3), radius: 20, y: 5)

                    // Shimmer overlay
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.15), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .offset(x: shimmerOffset)
                        .mask(
                            Circle().frame(width: 100, height: 100)
                        )

                    Image(systemName: "leaf.fill")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                }
                .dsGlowShadow()
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // النصوص
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("عائلة المحمد علي", "Al-Muhammad Ali Family"))
                        .font(DS.Font.title1)
                        .fontWeight(.black)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(L10n.t("شجرة العائلة", "Family Tree"))
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .opacity(textOpacity)

                Spacer()

                // مؤشر التحميل
                VStack(spacing: DS.Spacing.md) {
                    // Custom dot loader instead of ProgressView
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 8, height: 8)
                                .scaleEffect(dotCount == i + 1 ? 1.3 : 0.7)
                                .opacity(dotCount == i + 1 ? 1.0 : 0.3)
                                .animation(DS.Anim.bouncy, value: dotCount)
                        }
                    }

                    Text(L10n.t("جاري التحقق", "Verifying") + String(repeating: ".", count: dotCount))
                        .font(DS.Font.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: 140)
                        .animation(.none, value: dotCount)
                }
                .opacity(textOpacity)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            // أنيميشن اللوقو — elastic spring
            withAnimation(DS.Anim.elastic) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // أنيميشن النص — smooth delay
            withAnimation(DS.Anim.smooth.delay(0.2)) {
                textOpacity = 1.0
            }

            // Glow fade in
            withAnimation(DS.Anim.smooth.delay(0.3)) {
                glowOpacity = 1.0
            }

            // أنيميشن النبض المتكرر
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.18
            }

            // حلقات تدور
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                ring2Rotation = -360
            }

            // Shimmer sweep
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.5)) {
                shimmerOffset = 200
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
