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
            // خلفية تدرج لونين
            LinearGradient(
                colors: [DS.Color.primary, DS.Color.accentDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                // اللوقو مع حلقات متحركة
                ZStack {
                    // حلقة دائرية تدور
                    Circle()
                        .trim(from: 0.0, to: 0.65)
                        .stroke(
                            AngularGradient(
                                colors: [Color.white.opacity(0.0), Color.white.opacity(0.35), Color.white.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 175, height: 175)
                        .rotationEffect(.degrees(ringRotation))

                    // حلقة ثانية عكسية
                    Circle()
                        .trim(from: 0.0, to: 0.4)
                        .stroke(
                            AngularGradient(
                                colors: [Color.white.opacity(0.0), Color.white.opacity(0.25), Color.white.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 165, height: 165)
                        .rotationEffect(.degrees(ring2Rotation))

                    // حلقة نبض خارجية
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)

                    // Glow ring
                    Circle()
                        .fill(Color.white.opacity(glowOpacity * 0.1))
                        .frame(width: 150, height: 150)
                        .blur(radius: 15)

                    // Shimmer overlay
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.18), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .offset(x: shimmerOffset)
                        .mask(
                            RoundedRectangle(cornerRadius: 32, style: .continuous).frame(width: 140, height: 140)
                        )

                    // أيقونة التطبيق — نفس شكل الأيقونة بالضبط
                    Image("AppIconImage")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: DS.Color.primary.opacity(0.3), radius: 20, y: 8)
                }
                .dsGlowShadow()
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // النصوص
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                        .font(DS.Font.title1)
                        .fontWeight(.black)
                        .foregroundColor(.white)

                    Text(L10n.t("شجرة العائلة", "Family Tree"))
                        .font(DS.Font.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
                .opacity(textOpacity)

                Spacer()

                // مؤشر التحميل
                VStack(spacing: DS.Spacing.md) {
                    // Custom dot loader instead of ProgressView
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .scaleEffect(dotCount == i + 1 ? 1.3 : 0.7)
                                .opacity(dotCount == i + 1 ? 1.0 : 0.3)
                                .animation(DS.Anim.bouncy, value: dotCount)
                        }
                    }

                    Text(L10n.t("جاري التحقق", "Verifying") + String(repeating: ".", count: dotCount))
                        .font(DS.Font.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
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
