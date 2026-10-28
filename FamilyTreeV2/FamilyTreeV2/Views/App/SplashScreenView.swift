import SwiftUI

/// شاشة البداية — أيقونة التطبيق الدائرية (الشعار القديم) في الوسط: على الأبيض في الفاتح (طلب المالك ٢٠٢٦-١٠-١٧)،
/// وعلى الأسود الصافي في الداكن. تظهر بتلاشٍ وتكبير خفيف قصير — بلا نبض ولا دوران ولا لمعان.
/// من النسخة المحلية: صفحة «لا يوجد اتصال» (`OfflineHold`) و«تعذّر الاتصال» مع «إعادة المحاولة» مكان النقاط.
struct SplashScreenView: View {
    @EnvironmentObject var authVM: AuthViewModel
    /// بلا اتصال بالشبكة (`OfflineHold`): نفس الشاشة، ومكان النقاط صفحة «لا يوجد اتصال» بالأيقونة
    var waitingForNetwork = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var logoScale: CGFloat = 0.94
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    /// النقاط المتحركة تحت «جاري التحقق» (١ → ٢ → ٣)
    @State private var dotCount = 0

    var body: some View {
        ZStack {
            // أبيض في الفاتح (طلب المالك ٢٠٢٦-١٠-١٧، كان كريمي)، وأسود صافٍ في الداكن — بلون شاشة الإقلاع نفسه (LaunchBackground)
            DS.Color.splashBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // الشعار القديم (أيقونة التطبيق الدائرية) — طلب المالك ٢٠٢٦-١٠-١٧: يبقى داخل التطبيق حتى يتبدّل
                // مع الأيقونة الجديدة في تحديث واحد (الشعار المسطّح FamilyLogoNavy جاهز في الأصول)
                Image("AppIconImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: DS.Icon.appLogo, height: DS.Icon.appLogo)
                    .clipShape(Circle())
                    .dsGlowShadow()
                    .padding(DS.Icon.appLogo / 4)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))

                // الاسم — مع فاصل ذهبي
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali family"))
                        .dsFont(.heroTitle)
                        .foregroundColor(DS.Color.textPrimary)

                    // فاصل ذهبي: خطّان رفيعان يتلاشيان للخارج حول معيّن صغير
                    HStack(spacing: DS.Spacing.xsm) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.accentLight.opacity(0), DS.Color.accentLight.opacity(0.7)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: DS.Spacing.xxxxl, height: DS.Border.width)
                        Image(systemName: "diamond.fill")
                            .dsGlyph(DS.Glyph.splashDot)
                            .foregroundColor(DS.Color.accentLight)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DS.Color.accentLight.opacity(0.7), DS.Color.accentLight.opacity(0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: DS.Spacing.xxxxl, height: DS.Border.width)
                    }

                    // النص الثانوي ذهبي (الهوية): نص الذهبي الغامق على الكريمي، والذهبي على الأسود
                    Text(L10n.t("شجرة العائلة", "Family tree"))
                        .dsFont(.title)
                        .foregroundColor(DS.Color.accent)
                }
                .opacity(textOpacity)

                Spacer()

                // التحقق علق (بلا اتصال أو الخادم لا يرد) → رسالة و«إعادة المحاولة» بدل الدوران بلا نهاية (ج-٦)
                Group {
                    if waitingForNetwork {
                        // بلا اتصال: صفحة «لا يوجد اتصال» بالأيقونة (طلب المالك ٢٠٢٦-١٠-٠٨) — بلا زر، تكمل وحدها
                        DSEmptyView(L10n.t("لا يوجد اتصال", "No Connection"),
                                    message: L10n.t("يكمل التطبيق تلقائياً عند عودة الاتصال.",
                                                    "The app continues automatically once you're back online."),
                                    icon: "wifi.slash", tint: DS.Color.warning, compact: true)
                    } else if authVM.launchCheckStalled {
                        connectionProblem
                    } else {
                        // مؤشر التحميل — نقاط ذهبية هادئة تتبدّل بالشفافية فقط (الهوية)
                        VStack(spacing: DS.Spacing.md) {
                            HStack(spacing: DS.Spacing.xsm) {
                                ForEach(0..<3) { i in
                                    Circle()
                                        .fill(DS.Color.accentLight)
                                        .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                                        .opacity(dotCount == i + 1 ? 1.0 : DS.Opacity.divider)   // ٠٫٣
                                        .animation(.easeInOut(duration: 0.25), value: dotCount)
                                }
                            }
                            // العرض محجوز للنص بنقاطه الثلاث (يتبع حجم خط الجهاز) — لا يقفز النص مع النقاط
                            Text(statusText + "...")
                                .hidden()
                                .overlay(alignment: .leading) {
                                    Text(statusText + String(repeating: ".", count: dotCount))
                                }
                                .dsFont(.calloutMedium)
                                .foregroundColor(statusColor)
                                .animation(.none, value: dotCount)
                        }
                    }
                }
                // صفحات الحالة بألوان الوضع نفسه (الخلفية كريمية في الفاتح وسوداء في الداكن)
                .opacity(textOpacity)

                Spacer()
                    .frame(height: DS.Spacing.xxxxl + DS.Spacing.xl)
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

    private var statusText: String { L10n.t("جاري التحقق", "Verifying") }

    /// «جاري التحقق»: كحلي الحبر على الكريمي، والذهبي على الأسود (كما كان)
    private var statusColor: Color { colorScheme == .dark ? DS.Color.accentLight : DS.Color.textPrimary }

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
