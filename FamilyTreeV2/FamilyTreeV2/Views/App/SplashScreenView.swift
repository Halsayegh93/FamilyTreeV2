import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var titleOffset: CGFloat = 30
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var versionOpacity: Double = 0


    var body: some View {
        ZStack {
            // MARK: - Background
            DS.Color.background.ignoresSafeArea()

            // MARK: - Content
            VStack(spacing: DS.Spacing.lg) {
                Spacer()

                // Logo — Minimalist
                ZStack {
                    Circle()
                        .fill(DS.Color.surface)
                        .frame(width: 120, height: 120)
                        
                    Text("🌳")
                        .font(DS.Font.scaled(70))
                }
                .dsSubtleShadow()
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // App Name
                Text(L10n.t("شجرة العائلة", "Family Tree"))
                    .font(DS.Font.largeTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .offset(y: titleOffset)
                    .opacity(titleOpacity)

                // Family Name
                Text(L10n.t("عائلة المحمد علي", "Al-Muhammad Ali Family"))
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textSecondary)
                    .opacity(subtitleOpacity)

                Spacer()

                // Version
                Text(L10n.t("الإصدار", "Version") + " \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                    .font(DS.Font.scaled(12))
                    .foregroundColor(DS.Color.textTertiary)
                    .opacity(versionOpacity)
                    .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .onAppear {
            // Staggered animations
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            withAnimation(.easeOut(duration: 0.7).delay(0.3)) {
                titleOffset = 0
                titleOpacity = 1.0
            }

            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                subtitleOpacity = 1.0
            }

            withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
                versionOpacity = 1.0
            }

            // Transition to app after 2.2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeInOut(duration: 0.5)) {
                    isActive = true
                }
            }
        }
    }

    var shouldTransition: Bool {
        isActive
    }
}
