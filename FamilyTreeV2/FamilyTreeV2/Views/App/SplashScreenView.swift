import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var authVM: AuthViewModel
    /// شعار التطبيق — الحلقات حوله نِسَب منه
    private let logo = DS.Icon.appLogo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    /// النقاط المتحركة تحت «جاري التحقق» (١ → ٢ → ٣)
    @State private var dotCount = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var ringRotation: Double = 0
    @State private var ring2Rotation: Double = 0
    @State private var shimmerOffset: CGFloat = -200
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            // خلفية بسيطة صافية
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                // اللوقو مع حلقات متحركة — المقاسات نِسَب من شعار التطبيق (`DS.Icon.appLogo`)
                ZStack {
                    // حلقة دائرية تدور
                    Circle()
                        .trim(from: 0.0, to: 0.65)
                        .stroke(
                            AngularGradient(
                                colors: [DS.Color.primary.opacity(0.0), DS.Color.primary.opacity(DS.Opacity.tintStroke), DS.Color.primary.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: logo * 1.55, height: logo * 1.55)
                        .rotationEffect(.degrees(ringRotation))

                    // حلقة ثانية عكسية
                    Circle()
                        .trim(from: 0.0, to: 0.4)
                        .stroke(
                            AngularGradient(
                                colors: [DS.Color.accent.opacity(0.0), DS.Color.accent.opacity(DS.Opacity.tintFillStrong), DS.Color.accent.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: logo * 1.45, height: logo * 1.45)
                        .rotationEffect(.degrees(ring2Rotation))

                    // حلقة نبض خارجية
                    Circle()
                        .stroke(DS.Color.primary.opacity(DS.Opacity.tintFill), lineWidth: 2.5)
                        .frame(width: logo * 1.4, height: logo * 1.4)
                        .scaleEffect(pulseScale)

                    // Glow ring
                    Circle()
                        .fill(DS.Color.primary.opacity(glowOpacity * DS.Opacity.tintFillSoft))
                        .frame(width: logo * 1.3, height: logo * 1.3)
                        .blur(radius: 15)

                    // دائرة خارجية
                    Circle()
                        .fill(DS.Color.primary.opacity(DS.Opacity.tintFillSoft))
                        .frame(width: logo * 1.2, height: logo * 1.2)

                    // الدائرة الرئيسية
                    Circle()
                        .fill(DS.Color.gradientRoyal)
                        .frame(width: logo, height: logo)
                        .dsGlowShadow()

                    // Shimmer overlay
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, DS.Color.overlayIcon, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: logo, height: logo)
                        .offset(x: shimmerOffset)
                        .mask(
                            Circle().frame(width: logo, height: logo)
                        )

                    Image("AppIconImage")
                        .resizable()
                        .scaledToFill()
                        .frame(width: logo, height: logo)
                        .clipShape(Circle())
                }
                .dsGlowShadow()
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // النصوص — مع فاصل تراثي ذهبي
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                        .dsFont(.heroTitle)
                        .foregroundColor(DS.Color.textPrimary)

                    // فاصل ذهبي تراثي
                    HStack(spacing: DS.Spacing.xsm) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.secondary.opacity(0), DS.Color.secondary.opacity(DS.Opacity.dimmed)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: DS.Spacing.xxxxl, height: DS.Border.width)
                        Image(systemName: "diamond.fill")
                            .dsGlyph(DS.Glyph.splashDot)
                            .foregroundColor(DS.Color.secondary)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.secondary.opacity(DS.Opacity.dimmed), DS.Color.secondary.opacity(0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: DS.Spacing.xxxxl, height: DS.Border.width)
                    }

                    Text(L10n.t("شجرة العائلة", "Family Tree"))
                        .dsFont(.title)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .opacity(textOpacity)

                Spacer()

                // التحقق علق (بلا اتصال أو الخادم لا يرد) → رسالة و«إعادة المحاولة» بدل الدوران بلا نهاية (ج-٦)
                if authVM.launchCheckStalled {
                    connectionProblem
                        .opacity(textOpacity)
                } else {
                    // شاشة البداية تحتفظ بالنقاط الثلاث المتحركة — هوية الدخول (طلب المالك ٢٠٢٦-١٠-٠٧ «أبي النقاط»)؛
                    // باقي التحميل في التطبيق موحّد على `DSPageLoader`
                    VStack(spacing: DS.Spacing.md) {
                        HStack(spacing: DS.Spacing.xsm) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(DS.Color.primary)
                                    .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                                    // «تقليل الحركة»: بلا نبض حجمي — يبقى التبديل على الشفافية فقط
                                    .scaleEffect(reduceMotion ? 1.0 : (dotCount == i + 1 ? 1.3 : 0.7))
                                    .opacity(dotCount == i + 1 ? 1.0 : DS.Opacity.divider)   // ٠٫٣ كما كانت
                                    .animation(reduceMotion ? .easeInOut(duration: 0.25) : DS.Anim.bouncy, value: dotCount)
                            }
                        }
                        Text(L10n.t("جاري التحقق", "Verifying") + String(repeating: ".", count: dotCount))
                            .dsFont(.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(width: 140)
                            .animation(.none, value: dotCount)
                    }
                    .opacity(textOpacity)
                }

                Spacer()
                    .frame(height: DS.Spacing.xxxxl + DS.Spacing.xl)
            }
        }
        .onAppear {
            // احترام "تقليل الحركة": ظهور ناعم بالشفافية فقط — بلا سبرنق/نبض/دوران/لمعان
            guard !reduceMotion else {
                logoScale = 1.0
                withAnimation(.easeIn(duration: 0.3)) {
                    logoOpacity = 1.0
                    textOpacity = 1.0
                    glowOpacity = 1.0
                }
                return
            }

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

    /// التحقق علق (ج-٦): بلا اتصال والجلسة تحتاج تجديداً، أو الخادم لا يرد — التطبيق يعيد المحاولة
    /// تلقائياً كل لحظات ويكمل وحده عند عودة الاتصال، وهذا الزر يعيدها فوراً.
    private var connectionProblem: some View {
        // الحالة الواحدة (مضغوطة): مجسّم بلون التنبيه + عنوان + سطر + الزرّ الواحد
        DSEmptyView(L10n.t("تعذّر الاتصال", "Can't Connect"),
                    message: L10n.t("تأكّد من اتصالك بالإنترنت — يكمل التطبيق تلقائياً عند عودة الاتصال.",
                                    "Check your internet connection — the app continues automatically once you're back online."),
                    icon: "wifi.exclamationmark", tint: DS.Color.warning,
                    actionTitle: L10n.t("إعادة المحاولة", "Try Again"), actionIcon: "arrow.clockwise",
                    compact: true) {
            Task { await authVM.retryLaunchCheck() }
        }
    }
}
