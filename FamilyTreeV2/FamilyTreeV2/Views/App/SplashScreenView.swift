import SwiftUI

/// شاشة البداية — الشعار المسطّح الكريمي في الوسط، على الكحلي في الفاتح وعلى الأسود الصافي في الداكن.
/// الهوية: الشعار بلا دائرة ولا ظل ولا توهّج، ويظهر بتلاشٍ وتكبير خفيف قصير — بلا نبض ولا دوران ولا لمعان.
struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoScale: CGFloat = 0.94
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dotCount = 0

    /// ارتفاع الشعار — والمسافة الآمنة حوله ربع ارتفاعه (الهوية)
    private let logoHeight: CGFloat = 120

    var body: some View {
        ZStack {
            // كحلي المصمم #172536 في الفاتح، وأسود صافٍ في الداكن — بلون شاشة الإقلاع نفسه
            DS.Color.splashBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // الشعار المسطّح — logo-cream على الكحلي والأسود
                Image("FamilyLogoCream")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: logoHeight)
                    .padding(logoHeight / 4)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))

                // الاسم — مع فاصل ذهبي
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali family"))
                        .font(DS.Font.title1)
                        .foregroundColor(DS.Color.textOnPrimary)

                    // فاصل ذهبي: خطّان رفيعان يتلاشيان للخارج حول معيّن صغير
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.accentLight.opacity(0), DS.Color.accentLight.opacity(0.7)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: 40, height: 1)
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(DS.Color.accentLight)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.accentLight.opacity(0.7), DS.Color.accentLight.opacity(0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: 40, height: 1)
                    }

                    // النص الثانوي ذهبي على الخلفية الداكنة (الهوية)
                    Text(L10n.t("شجرة العائلة", "Family tree"))
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.accentLight)
                }
                .opacity(textOpacity)

                Spacer()

                // مؤشر التحميل — نقاط هادئة تتبدّل بالشفافية فقط
                VStack(spacing: DS.Spacing.md) {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(DS.Color.accentLight)
                                .frame(width: 8, height: 8)
                                .opacity(dotCount == i + 1 ? 1.0 : 0.3)
                                .animation(.easeInOut(duration: 0.25), value: dotCount)
                        }
                    }

                    Text(L10n.t("جاري التحقق", "Verifying") + String(repeating: ".", count: dotCount))
                        .font(DS.Font.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Color.accentLight)
                        .frame(width: 140)
                        .animation(.none, value: dotCount)
                }
                .opacity(textOpacity)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            // احترام "تقليل الحركة": ظهور بالشفافية فقط
            guard !reduceMotion else {
                logoScale = 1.0
                withAnimation(.easeIn(duration: 0.3)) {
                    logoOpacity = 1.0
                    textOpacity = 1.0
                }
                return
            }

            // ظهور هادئ قصير: تلاشٍ مع تكبير خفيف
            withAnimation(.easeOut(duration: 0.45)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                textOpacity = 1.0
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
