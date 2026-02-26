import SwiftUI

struct NewsCardView: View {
    let authorName: String
    let role: String
    let roleColor: Color
    let time: String
    let type: String
    let content: String

    var imageUrl: String? = nil
    var pollOptions: [String]? = nil
    @State private var selectedPollOption: Int? = nil

    var body: some View {
        VStack(alignment: L10n.isArabic ? .leading : .trailing, spacing: DS.Spacing.md) {
            
            // 1. Header (Avatar, Name, Role, Badge)
            headerView

            // 2. News Content
            Text(content)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary.opacity(0.95))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.xs)

            // 3. Cover Image (Below Text)
            coverImageView
                .cornerRadius(DS.Radius.xl) // Rounded inner image for aesthetics
                .padding(.top, DS.Spacing.xs)

            // 4. Poll Options
            pollSectionView

            // Glass divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, DS.Spacing.sm)

            // 5. Footer (Time + Interactions)
            footerView
        }
        .padding(DS.Spacing.xl)
        .background(
            ZStack {
                // Base background color
                DS.Color.surface.opacity(0.4)
                
                // Frosted Glass Effect
                RoundedRectangle(cornerRadius: DS.Radius.xxl)
                    .fill(.regularMaterial)
                
                // Gradient overlay for that "iOS 26" futuristic aesthetic
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(DS.Radius.xxl)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xxl)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        // Advanced dynamic shadow
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
        .shadow(color: roleColor.opacity(0.15), radius: 30, x: 0, y: 15)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - Subviews
extension NewsCardView {
    
    @ViewBuilder
    private var coverImageView: some View {
        if let imgStr = imageUrl, let url = URL(string: imgStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else if phase.error != nil {
                    ZStack {
                        DS.Color.surfaceElevated.opacity(0.5)
                        Image(systemName: "photo.fill")
                            .font(.largeTitle)
                            .foregroundColor(DS.Color.textTertiary.opacity(0.5))
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                } else {
                    ZStack {
                        DS.Color.surfaceElevated.opacity(0.5)
                        ProgressView()
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: DS.Spacing.md) {
            // Avatar with glass overlay
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [roleColor, roleColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Text(String(authorName.first ?? "U"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            )
            .shadow(color: roleColor.opacity(0.4), radius: 8, x: 0, y: 4)

            // Name and Role
            VStack(alignment: L10n.isArabic ? .leading : .trailing, spacing: 2) {
                Text(authorName)
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)

                Text(role)
                    .font(DS.Font.caption1)
                    .foregroundColor(roleColor)
            }

            Spacer()

            // Futuristic Badge
            badgeView
        }
    }

    private var badgeView: some View {
        Text(type)
            .font(DS.Font.caption1)
            .fontWeight(.bold)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    tagColor.opacity(0.15)
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .foregroundColor(tagColor)
            .shadow(color: tagColor.opacity(0.2), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private var pollSectionView: some View {
        if let options = pollOptions, !options.isEmpty {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(0..<options.count, id: \.self) { index in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedPollOption = index
                        }
                    }) {
                        HStack {
                            Text(options[index])
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer()
                            if selectedPollOption == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(DS.Color.gradientPrimary)
                            } else {
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                                    .background(Circle().fill(.ultraThinMaterial))
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(DS.Spacing.md)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: DS.Radius.md).fill(.ultraThinMaterial)
                                if selectedPollOption == index {
                                    DS.Color.primary.opacity(0.15)
                                } else {
                                    Color.white.opacity(0.1)
                                }
                            }
                        )
                        .cornerRadius(DS.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(selectedPollOption == index ? DS.Color.primary.opacity(0.5) : Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                    }
                }
            }
            .padding(.top, DS.Spacing.xs)
        }
    }

    private var footerView: some View {
        HStack {
            // Time
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock.fill")
                Text(time)
            }
            .font(DS.Font.caption2)
            .foregroundColor(DS.Color.textSecondary)

            Spacer()

            // Interactions
            HStack(spacing: DS.Spacing.sm) {
                actionPill(icon: "heart.fill", text: "١٢", tint: Color.red)
                actionPill(icon: "bubble.right.fill", text: "٥", tint: DS.Color.primary)
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                Color.white.opacity(0.2)
                            }
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
            }
        }
    }

    private func actionPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(DS.Font.subheadline)
                .fontWeight(.bold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, DS.Spacing.md)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Color.white.opacity(0.15) // Highlighted glass
                tint.opacity(0.12)
            }
        )
        .foregroundColor(tint)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: tint.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    private var tagColor: Color {
        switch type {
        case "تنبيه", "Urgent": return DS.Color.error
        case "مناسبة", "Event": return DS.Color.success
        case "تصويت", "Poll": return DS.Color.warning
        default: return DS.Color.primary
        }
    }
}
