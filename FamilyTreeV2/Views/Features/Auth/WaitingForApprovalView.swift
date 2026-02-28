import SwiftUI

struct WaitingForApprovalView: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Animation states
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.6
    @State private var iconRotation: Double = 0
    @State private var dotOffset: CGFloat = 0
    @State private var cardAppeared = false
    @State private var contentOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // Decorative gradient background
            decorativeBackground

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                // Animated waiting icon with gradient circle and pulse
                waitingIcon
                    .opacity(contentOpacity)

                // Animated progress dots
                animatedDots
                    .opacity(contentOpacity)

                // Info card with gradient accent
                infoCard
                    .opacity(cardAppeared ? 1 : 0)
                    .offset(y: cardAppeared ? 0 : 30)

                Spacer()

                // Action buttons
                actionButtons
                    .opacity(contentOpacity)
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Decorative Background
    private var decorativeBackground: some View {
        ZStack {
            // Blue gradient from top — مطابق للـ Figma
            LinearGradient(
                colors: [
                    DS.Color.primary.opacity(0.12),
                    DS.Color.accent.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            // Decorative circles
            Circle()
                .fill(DS.Color.primary.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .offset(x: -120, y: -300)

            Circle()
                .fill(DS.Color.accent.opacity(0.05))
                .frame(width: 200, height: 200)
                .blur(radius: 30)
                .offset(x: 150, y: -200)

            Circle()
                .fill(DS.Color.primary.opacity(0.04))
                .frame(width: 180, height: 180)
                .blur(radius: 30)
                .offset(x: -100, y: 400)

            Circle()
                .fill(DS.Color.gridDiwaniya.opacity(0.04))
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                .offset(x: 160, y: 300)
        }
    }

    // MARK: - Waiting Icon
    private var waitingIcon: some View {
        ZStack {
            // Animated pulse rings
            Circle()
                .stroke(DS.Color.gradientPrimary, lineWidth: 2)
                .frame(width: 160, height: 160)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            Circle()
                .stroke(DS.Color.gradientPrimary, lineWidth: 1.5)
                .frame(width: 140, height: 140)
                .scaleEffect(pulseScale * 0.9)
                .opacity(pulseOpacity * 0.7)

            // Outer glow ring
            Circle()
                .fill(DS.Color.warning.opacity(0.08))
                .frame(width: 130, height: 130)

            // Gradient circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DS.Color.warning, DS.Color.warning.opacity(0.7), DS.Color.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 110)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))

            Image(systemName: "clock.badge.checkmark.fill")
                .font(DS.Font.scaled(48, weight: .bold))
                .foregroundColor(.white)
        }
        .dsGlowShadow()
    }

    // MARK: - Animated Dots
    private var animatedDots: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotOffset == CGFloat(index) ? 1.4 : 0.8)
                    .opacity(dotOffset == CGFloat(index) ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: dotOffset
                    )
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: - Info Card
    private var infoCard: some View {
        VStack(spacing: 0) {
            // Gradient accent bar on top
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.gradientPrimary)
                .frame(height: 4)
                .padding(.horizontal, DS.Spacing.xxxl)

            DSCard {
                VStack(spacing: DS.Spacing.md) {
                    Text(L10n.t("طلبك قيد المراجعة", "Request Under Review"))
                        .font(DS.Font.title2)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(L10n.t(
                        "تم إرسال بياناتك إلى إدارة شجرة العائلة. يرجى الانتظار حتى يتم تفعيل الحساب من المدير أو المشرف.",
                        "Your information has been submitted. Please wait for an admin or supervisor to activate your account."
                    ))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)

                    // Status badge
                    HStack(spacing: DS.Spacing.xs) {
                        Circle()
                            .fill(DS.Color.warning)
                            .frame(width: 8, height: 8)
                        Text(L10n.t("قيد الانتظار", "Pending"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.warning)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.warning.opacity(0.10))
                    .cornerRadius(DS.Radius.full)
                }
                .padding(DS.Spacing.xl)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(DS.Color.gradientPrimary, lineWidth: 1)
                    .opacity(0.2)
            )
        }
        .padding(.horizontal, DS.Spacing.xl)
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            // Refresh button with gradient
            DSPrimaryButton(
                L10n.t("تحديث حالة الطلب", "Refresh Status"),
                icon: "arrow.clockwise",
                isLoading: authVM.isLoading
            ) {
                Task { await authVM.checkUserProfile() }
            }
            .padding(.horizontal, DS.Spacing.xl)

            // Sign out button with border stroke style
            Button(action: {
                Task { await authVM.signOut() }
            }) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(DS.Font.scaled(14, weight: .semibold))
                    Text(L10n.t("تسجيل الخروج", "Sign Out"))
                }
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.error)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(DS.Color.error.opacity(0.08))
                .cornerRadius(DS.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.error.opacity(0.3), lineWidth: 1.5)
                )
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    // MARK: - Animations
    private func startAnimations() {
        // Content fade in
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            contentOpacity = 1.0
        }

        // Card slide up
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.4)) {
            cardAppeared = true
        }

        // Pulse animation
        withAnimation(
            .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
            pulseOpacity = 0.0
        }

        // Dot animation trigger
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            dotOffset = 2
        }
    }
}
