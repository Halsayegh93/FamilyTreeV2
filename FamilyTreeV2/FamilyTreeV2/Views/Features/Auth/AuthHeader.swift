import SwiftUI

/// الهيدر الموحّد لشاشات المصادقة (الدخول/الرمز/التسجيل/الانتظار) — نفس
/// هوية هيدرات بقية الواجهات: تدرّج + طبقة veil + أيقونة ٥٢ + عنوان ووصف
/// + شريط سدو.
extension View {
    @ViewBuilder
    func authHeader(
        icon: String,
        title: String,
        subtitle: String,
        actionIcon: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Color.overlayIcon)
                        .overlay(Circle().strokeBorder(DS.Color.overlayIconBorder, lineWidth: 1.5))
                    Image(systemName: icon)
                        .font(DS.Font.scaled(20, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Font.plex(19, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(DS.Font.plex(12, weight: .medium))
                        .foregroundColor(DS.Color.overlayText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }

                Spacer(minLength: DS.Spacing.xs)

                if let actionIcon, let action {
                    Button(action: action) {
                        Image(systemName: actionIcon)
                            .font(DS.Font.scaled(17, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(DS.Color.overlayIcon))
                            .overlay(Circle().strokeBorder(DS.Color.overlayIconBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(BounceButtonStyle())
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)
            .frame(minHeight: 70, alignment: .bottom)

            // شريط سدو — نفس بقية الهيدرات
            HStack(spacing: 5) {
                Rectangle().fill(DS.Color.textOnPrimary.opacity(0.16)).frame(height: 1)
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(DS.Color.textOnPrimary.opacity(i == 2 ? 0.55 : 0.30))
                        .frame(width: i == 2 ? 6 : 4, height: i == 2 ? 6 : 4)
                        .rotationEffect(.degrees(45))
                }
                Rectangle().fill(DS.Color.textOnPrimary.opacity(0.16)).frame(height: 1)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                DS.Color.gradientPrimary
                DS.Color.headerVeil
            }
            .ignoresSafeArea(edges: .top)
        )
    }

}
