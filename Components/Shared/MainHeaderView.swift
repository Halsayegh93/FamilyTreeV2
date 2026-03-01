import SwiftUI

struct MainHeaderView<TrailingContent: View>: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    @Binding var showingNotifications: Bool
    
    @State private var isAnimating = false
    
    // Customization properties
    let customTitle: String?
    let customSubtitle: String?
    let customIcon: String?
    let backgroundGradient: LinearGradient?
    let hasDropShadow: Bool
    let trailingContent: TrailingContent
    
    init(
        selectedTab: Binding<Int>,
        showingNotifications: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        backgroundGradient: LinearGradient? = nil,
        hasDropShadow: Bool = true,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self._selectedTab = selectedTab
        self._showingNotifications = showingNotifications
        self.customTitle = title
        self.customSubtitle = subtitle
        self.customIcon = icon
        self.backgroundGradient = backgroundGradient
        self.hasDropShadow = hasDropShadow
        self.trailingContent = trailingContent()
    }
    
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // Header Content
            if let customTitle = customTitle {
                // Custom Header (E.g. Tree, Diwaniyas, Admin)
                HStack(spacing: DS.Spacing.md) {
                    if let icon = customIcon {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                )
                            Image(systemName: icon)
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0.0)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customTitle)
                            .font(DS.Font.title3)
                            .foregroundColor(.white)
                        if let customSubtitle = customSubtitle, !customSubtitle.isEmpty {
                            Text(customSubtitle)
                                .font(DS.Font.scaled(13, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }
                    .offset(x: isAnimating ? 0 : 15)
                    .opacity(isAnimating ? 1.0 : 0.0)
                }
            } else {
                // Default Profile Header (For Home)
                Button(action: { selectedTab = 3 }) {
                    HStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                )
                            Text(String(authVM.currentUser?.fullName.first ?? "U"))
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("مرحباً 👋", "Hello 👋"))
                                .font(DS.Font.scaled(13, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.85))
                            Text(authVM.currentUser?.firstName ?? "Member")
                                .font(DS.Font.title3)
                                .foregroundColor(.white)
                        }
                        .offset(x: isAnimating ? 0 : 15)
                        .opacity(isAnimating ? 1.0 : 0.0)
                    }
                }
                .buttonStyle(BounceButtonStyle())
            }

            Spacer()

            // Actions
            HStack(spacing: DS.Spacing.md) {
                trailingContent
                
                if customTitle == nil {
                    if authVM.currentUser?.role == .admin || authVM.currentUser?.role == .supervisor {
                        Button(action: { selectedTab = 4 }) {
                            headerIconView(icon: "shield.fill", color: .white)
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                    Button(action: { showingNotifications = true }) {
                        ZStack(alignment: .topTrailing) {
                            headerIconView(
                                icon: authVM.unreadNotificationsCount > 0 ? "bell.badge.fill" : "bell.fill",
                                color: .white
                            )
                            
                            if authVM.unreadNotificationsCount > 0 {
                                Text(authVM.unreadNotificationsCount > 99 ? "99+" : "\(authVM.unreadNotificationsCount)")
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
                }
            }
            .scaleEffect(isAnimating ? 1.0 : 0.5)
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
        .background(
            (backgroundGradient ?? DS.Color.gradientPrimary)
                .ignoresSafeArea(edges: .top)
                .shadow(color: hasDropShadow ? .black.opacity(0.15) : .clear, radius: 8, x: 0, y: 4)
        )
        .sheet(isPresented: $showingNotifications) {
            NotificationsCenterView()
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2)) {
                isAnimating = true
            }
        }
    }
    
    private func headerIconView(icon: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            Image(systemName: icon)
                .font(DS.Font.scaled(18, weight: .bold))
                .foregroundColor(color)
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
