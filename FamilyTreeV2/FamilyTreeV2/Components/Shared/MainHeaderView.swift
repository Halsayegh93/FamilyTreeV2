import SwiftUI

struct MainHeaderView<TrailingContent: View>: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Binding var selectedTab: Int
    @Binding var showingNotifications: Bool
    
    @State private var isAnimating = false
    @State private var showSignOutConfirm = false

    /// الوضع الأفقي (ارتفاع قصير) — هيدر مضغوط حتى يظهر كاملاً بلا اقتصاص
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الهيدر يظهر كاملاً في الوضعين — لا نضغطه أفقياً (طلب المالك)
    private var isLandscape: Bool { false }
    /// أفقي فعلاً — للهوامش الجانبية فقط (النوتش)
    private var physicallyLandscape: Bool { vSizeClass == .compact }

    // Customization properties
    let customTitle: String?
    let customSubtitle: String?
    let customIcon: String?
    let backgroundGradient: LinearGradient?
    let hasDropShadow: Bool
    let showNotificationBell: Bool
    let subtitleAbove: Bool
    /// عرض العنوان الفرعي ككبسولة زجاجية (مثل عدد الأفراد في الشجرة)
    let subtitleChip: Bool
    let trailingContent: TrailingContent

    init(
        selectedTab: Binding<Int>,
        showingNotifications: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        backgroundGradient: LinearGradient? = nil,
        hasDropShadow: Bool = true,
        showNotificationBell: Bool = false,
        subtitleAbove: Bool = false,
        subtitleChip: Bool = false,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self._selectedTab = selectedTab
        self._showingNotifications = showingNotifications
        self.customTitle = title
        self.customSubtitle = subtitle
        self.customIcon = icon
        self.backgroundGradient = backgroundGradient
        self.hasDropShadow = hasDropShadow
        self.showNotificationBell = showNotificationBell
        self.subtitleAbove = subtitleAbove
        self.subtitleChip = subtitleChip
        self.trailingContent = trailingContent()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                if let customTitle = customTitle {
                    HStack(spacing: isLandscape ? DS.Spacing.sm : DS.Spacing.md) {
                        if let icon = customIcon {
                            leadingIcon(symbol: icon)
                                .scaleEffect(isAnimating ? 1.0 : 0.8)
                                .opacity(isAnimating ? 1.0 : 0.0)
                        }

                        if isLandscape {
                            // الوضع الأفقي: العنوان والعنوان الفرعي على سطر واحد (ارتفاع أقل)
                            HStack(spacing: DS.Spacing.sm) {
                                Text(customTitle)
                                    .font(DS.Font.scaled(17, weight: .black))
                                    .foregroundColor(DS.Color.textOnPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)

                                if let customSubtitle = customSubtitle, !customSubtitle.isEmpty {
                                    if subtitleChip {
                                        Text(customSubtitle)
                                            .font(DS.Font.scaled(11, weight: .bold))
                                            .foregroundColor(DS.Color.textOnPrimary)
                                            .lineLimit(1)
                                            .padding(.horizontal, DS.Spacing.sm)
                                            .padding(.vertical, 2)
                                            .background(DS.Color.overlayIcon, in: Capsule())
                                            .overlay(Capsule().stroke(DS.Color.overlayIconBorder, lineWidth: 1))
                                    } else {
                                        Text(customSubtitle)
                                            .font(DS.Font.scaled(11, weight: .medium))
                                            .foregroundColor(DS.Color.overlayText)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                }
                            }
                            .offset(x: isAnimating ? 0 : 15)
                            .opacity(isAnimating ? 1.0 : 0.0)
                        } else {
                        VStack(alignment: .leading, spacing: 2) {
                            if subtitleAbove, let customSubtitle = customSubtitle, !customSubtitle.isEmpty {
                                Text(customSubtitle)
                                    .font(DS.Font.scaled(14, weight: .semibold))
                                    .foregroundColor(DS.Color.overlayText)
                            }
                            Text(customTitle)
                                .font(DS.Font.scaled(subtitleAbove ? 24 : 21, weight: .black))
                                .foregroundColor(DS.Color.textOnPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if !subtitleAbove, let customSubtitle = customSubtitle, !customSubtitle.isEmpty {
                                if subtitleChip {
                                    // كبسولة زجاجية بنفس لغة أيقونات الهيدر (خلفية شفافة + إطار خفيف)
                                    Text(customSubtitle)
                                        .font(DS.Font.scaled(12, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .padding(.horizontal, DS.Spacing.sm + 2)
                                        .padding(.vertical, 3)
                                        .background(DS.Color.overlayIcon, in: Capsule())
                                        .overlay(Capsule().stroke(DS.Color.overlayIconBorder, lineWidth: 1))
                                        .padding(.top, 2)
                                } else {
                                    Text(customSubtitle)
                                        .font(DS.Font.scaled(13, weight: .medium))
                                        .foregroundColor(DS.Color.overlayText)
                                }
                            }
                        }
                        .offset(x: isAnimating ? 0 : 15)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        }
                    }
                } else {
                    Button(action: { selectedTab = 3 }) {
                        HStack(spacing: isLandscape ? DS.Spacing.sm : DS.Spacing.md) {
                            leadingInitial
                                .scaleEffect(isAnimating ? 1.0 : 0.8)
                                .opacity(isAnimating ? 1.0 : 0.0)

                            VStack(alignment: .leading, spacing: isLandscape ? 0 : 3) {
                                Text(L10n.t("مرحباً بك", "Welcome Back"))
                                    .font(DS.Font.scaled(isLandscape ? 10 : 12, weight: .semibold))
                                    .foregroundColor(DS.Color.overlayText)
                                Text(authVM.currentUser?.displayName ?? "Member")
                                    .font(DS.Font.scaled(isLandscape ? 17 : 21, weight: .bold))
                                    .foregroundColor(DS.Color.textOnPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(isLandscape ? 0.7 : 1.0)
                            }
                            .offset(x: isAnimating ? 0 : 15)
                            .opacity(isAnimating ? 1.0 : 0.0)
                        }
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityHint(L10n.t("افتح الملف الشخصي", "Open profile"))
                }

                Spacer()

                HStack(spacing: isLandscape ? DS.Spacing.sm : DS.Spacing.md) {
                    trailingContent

                    if customTitle == nil {
                        Button(action: { showSignOutConfirm = true }) {
                            headerIconView(icon: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityLabel(L10n.t("تسجيل الخروج", "Sign Out"))
                    }

                    if customTitle == nil || showNotificationBell {
                        NavigationLink(destination: NotificationsCenterView()) {
                            ZStack(alignment: .topTrailing) {
                                headerIconView(
                                    icon: notificationVM.unreadNotificationsCount > 0 ? "bell.badge.fill" : "bell.fill"
                                )

                                if notificationVM.unreadNotificationsCount > 0 {
                                    Text(notificationVM.unreadNotificationsCount > 99 ? "99+" : "\(notificationVM.unreadNotificationsCount)")
                                        .font(DS.Font.scaled(10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(DS.Color.error)
                                        .clipShape(Capsule())
                                        .offset(x: 6, y: -4)
                                }
                            }
                        }
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityLabel(notificationVM.unreadNotificationsCount > 0
                            ? L10n.t("\(notificationVM.unreadNotificationsCount) إشعار غير مقروء", "\(notificationVM.unreadNotificationsCount) unread notifications")
                            : L10n.t("الإشعارات", "Notifications"))
                    }
                }
                .scaleEffect(isAnimating ? 1.0 : 0.5)
                .opacity(isAnimating ? 1.0 : 0.0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.horizontal, physicallyLandscape ? DS.Spacing.xs : 0)
            .padding(.bottom, isLandscape ? DS.Spacing.xs : DS.Spacing.sm)
            .padding(.top, isLandscape ? DS.Spacing.xs : 0)
            .frame(minHeight: isLandscape ? 46 : 70, alignment: .bottom)

            Rectangle()
                .fill(DS.Color.headerBorder)
                .frame(height: 1)
                .opacity(0.55)
        }
        .background(headerBackground)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .confirmationDialog(
            L10n.t("تسجيل الخروج", "Sign Out"),
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.t("تسجيل الخروج", "Sign Out"), role: .destructive) {
                Task { await authVM.signOut() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد الخروج من حسابك على هذا الجهاز؟", "Do you want to sign out of your account on this device?"))
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2)) {
                isAnimating = true
            }
        }
    }

    private var headerBackground: some View {
        ZStack {
            (backgroundGradient ?? DS.Color.gradientPrimary)
            DS.Color.headerVeil
        }
        .ignoresSafeArea(edges: .top)
        .shadow(color: hasDropShadow ? DS.Shadow.card.color : .clear, radius: DS.Shadow.card.radius, x: DS.Shadow.card.x, y: DS.Shadow.card.y)
    }

    private var leadingInitial: some View {
        ZStack {
            Circle()
                .fill(DS.Color.overlayIcon)
                .frame(width: isLandscape ? 38 : 52, height: isLandscape ? 38 : 52)
                .overlay(
                    Circle().stroke(DS.Color.overlayIconBorder, lineWidth: 1.5)
                )
            Text(String(authVM.currentUser?.fullName.first ?? "U"))
                .font(DS.Font.scaled(isLandscape ? 16 : 20, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
        }
    }

    private func leadingIcon(symbol: String) -> some View {
        ZStack {
            Circle()
                .fill(DS.Color.overlayIcon)
                .frame(width: isLandscape ? 38 : 52, height: isLandscape ? 38 : 52)
                .overlay(
                    Circle().stroke(DS.Color.overlayIconBorder, lineWidth: 1.5)
                )
            Image(systemName: symbol)
                .font(DS.Font.scaled(isLandscape ? 16 : 20, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
        }
    }

    private func headerIconView(icon: String) -> some View {
        ZStack {
            Circle()
                .fill(DS.Color.overlayIcon)
                .frame(width: isLandscape ? 36 : 44, height: isLandscape ? 36 : 44)
                .overlay(
                    Circle().stroke(DS.Color.overlayIconBorder, lineWidth: 1.5)
                )
            Image(systemName: icon)
                .font(DS.Font.scaled(isLandscape ? 15 : 18, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
        }
        .contentShape(Circle())
    }
}

// MARK: - Bounce Animation ButtonStyle
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
