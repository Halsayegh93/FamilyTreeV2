import SwiftUI

struct HomeHeaderView: View {
    let userFullName: String
    var onLogout: () -> Void
    var onNotificationTap: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack {
            // أزرار — bold glass circles
            HStack(spacing: DS.Spacing.md) {
                // Logout
                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(DS.Font.scaled(17, weight: .bold))
                        .foregroundColor(DS.Color.error)
                        .frame(width: DS.Icon.size, height: DS.Icon.size)
                        .background(DS.Color.error.opacity(0.10))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.error.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(DSBoldButtonStyle())

                // Notifications
                Button(action: onNotificationTap) {
                    Image(systemName: "bell.badge.fill")
                        .font(DS.Font.scaled(17, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: DS.Icon.size, height: DS.Icon.size)
                        .background(DS.Color.primary.opacity(0.10))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.primary.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(DSBoldButtonStyle())
            }

            Spacer()

            // التحية والاسم — bold
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("مرحباً بك،", "Welcome,"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Text(userFullName)
                    .font(DS.Font.title2)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
            }
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.lg)
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.1)) {
                appeared = true
            }
        }
    }
}
