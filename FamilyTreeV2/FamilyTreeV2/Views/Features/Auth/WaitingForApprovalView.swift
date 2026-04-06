import SwiftUI

struct WaitingForApprovalView: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Animation states
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.6
    @State private var ringRotation: Double = 0
    @State private var dotPhase: CGFloat = 0
    @State private var cardAppeared = false
    @State private var contentOpacity: CGFloat = 0
    @State private var iconBounce: CGFloat = 0
    @State private var buttonsAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.primary.opacity(0.06), DS.Color.background],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    Spacer().frame(height: DS.Spacing.xxxxl)

                    // أيقونة الانتظار مع الحركة
                    waitingIcon
                        .opacity(contentOpacity)
                        .scaleEffect(contentOpacity)

                    // نقاط التحميل
                    animatedDots
                        .opacity(contentOpacity)

                    // بطاقة المعلومات
                    infoCard
                        .opacity(cardAppeared ? 1 : 0)
                        .offset(y: cardAppeared ? 0 : 30)

                    // الأزرار
                    actionButtons
                        .opacity(buttonsAppeared ? 1 : 0)
                        .offset(y: buttonsAppeared ? 0 : 20)

                    Spacer().frame(height: DS.Spacing.xxl)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Waiting Icon
    private var waitingIcon: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                // حلقة دوارة
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        DS.Color.gradientPrimary,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(ringRotation))

                // أيقونة التطبيق
                Image("AppIconImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: DS.Color.primary.opacity(0.2), radius: 12, y: 6)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("شجرة العائلة", "Family Tree"))
                    .font(DS.Font.title1)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)

                Text(L10n.t("عائلة المحمد علي", "Al-Muhammad Ali Family"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
    }

    // MARK: - Animated Dots
    private var animatedDots: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DS.Color.warning.opacity(dotPhase == CGFloat(index) ? 1.0 : 0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(dotPhase == CGFloat(index) ? 1.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: dotPhase
                    )
            }
        }
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - Info Card
    private var infoCard: some View {
        VStack(spacing: DS.Spacing.lg) {
            // العنوان
            Text(L10n.t("طلبك قيد المراجعة", "Request Under Review"))
                .font(DS.Font.title2)
                .foregroundColor(DS.Color.textPrimary)

            // الوصف
            Text(L10n.t(
                "تم إرسال بياناتك إلى إدارة شجرة العائلة.\nيرجى الانتظار حتى يتم تفعيل الحساب.",
                "Your information has been submitted.\nPlease wait for account activation."
            ))
            .font(DS.Font.body)
            .foregroundColor(DS.Color.textPrimary.opacity(0.75))
            .multilineTextAlignment(.center)
            .lineSpacing(4)

            // شارة الحالة
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(DS.Color.warning)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseScale > 1.05 ? 1.2 : 1.0)
                Text(L10n.t("قيد الانتظار", "Pending"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.warning)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.warning.opacity(0.08))
            .cornerRadius(DS.Radius.full)

            DSDivider()

            // ملاحظة الإشعار
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "bell.badge.fill")
                    .font(DS.Font.scaled(14, weight: .medium))
                    .foregroundColor(DS.Color.primary)

                Text(L10n.t(
                    "سيصلك إشعار فور الموافقة على طلبك",
                    "You'll be notified once your request is approved"
                ))
                .font(DS.Font.footnote)
                .foregroundColor(DS.Color.textSecondary)
            }
        }
        .padding(DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.warning.opacity(0.15), lineWidth: 1)
        )
        .dsSubtleShadow()
        .padding(.horizontal, DS.Spacing.xl)
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            DSPrimaryButton(
                L10n.t("تحديث حالة الطلب", "Refresh Status"),
                icon: "arrow.clockwise",
                isLoading: authVM.isLoading
            ) {
                Task { await authVM.checkUserProfile() }
            }
            .padding(.horizontal, DS.Spacing.xl)

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
                .background(DS.Color.error.opacity(0.06))
                .cornerRadius(DS.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    // MARK: - Animations
    private func startAnimations() {
        // ظهور المحتوى
        withAnimation(DS.Anim.elastic.delay(0.2)) {
            contentOpacity = 1.0
        }

        // ظهور البطاقة
        withAnimation(DS.Anim.elastic.delay(0.5)) {
            cardAppeared = true
        }

        // ظهور الأزرار
        withAnimation(DS.Anim.smooth.delay(0.7)) {
            buttonsAppeared = true
        }

        // دوران الحلقة
        withAnimation(
            .linear(duration: 3.0)
                .repeatForever(autoreverses: false)
        ) {
            ringRotation = 360
        }

        // نبض الحلقة
        withAnimation(
            .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.12
            pulseOpacity = 0.0
        }

        // حركة الأيقونة
        withAnimation(
            .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
                .delay(0.3)
        ) {
            iconBounce = -4
        }

        // نقاط التحميل
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            dotPhase = 2
        }
    }
}
