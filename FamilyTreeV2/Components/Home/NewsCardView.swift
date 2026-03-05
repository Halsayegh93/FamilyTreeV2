import SwiftUI

struct NewsCardView: View {
    @Environment(\.colorScheme) private var colorScheme

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
                .cornerRadius(DS.Radius.xl)
                .padding(.top, DS.Spacing.xs)

            // 4. Poll Options
            pollSectionView

            // Glass divider
            Rectangle()
                .fill(DS.Color.glassDivider(colorScheme))
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
                        DS.Color.glassMedium(colorScheme),
                        Color.clear
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
                        colors: [DS.Color.glassBorderBright(colorScheme), DS.Color.glassSubtle(colorScheme)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        // Dynamic shadow
        .dsCardShadow()
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - Subviews
extension NewsCardView {
    
    @ViewBuilder
    private var coverImageView: some View {
        if let imgStr = imageUrl, let url = URL(string: imgStr) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } placeholder: {
                ZStack {
                    DS.Color.surfaceElevated.opacity(0.5)
                    ProgressView()
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
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
                    .frame(width: 44, height: 44)

                Text(String(authorName.first ?? "U"))
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(DS.Color.glassBorderBright(colorScheme), lineWidth: 1.5)
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

    private func displayNameForType(_ type: String) -> String {
        switch type {
        case "خبر": return L10n.t("خبر", "News")
        case "زواج": return L10n.t("زواج", "Wedding")
        case "مولود": return L10n.t("مولود", "Newborn")
        case "وفاة": return L10n.t("وفاة", "Obituary")
        case "تصويت": return L10n.t("تصويت", "Poll")
        case "إعلان": return L10n.t("إعلان", "Announcement")
        case "تهنئة": return L10n.t("تهنئة", "Congrats")
        case "تذكير": return L10n.t("تذكير", "Reminder")
        case "دعوة": return L10n.t("دعوة", "Invitation")
        default: return type
        }
    }

    private var badgeView: some View {
        Text(displayNameForType(type))
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
                    .stroke(LinearGradient(colors: [DS.Color.glassBorderBright(colorScheme), DS.Color.glassSubtle(colorScheme)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
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
                                    .font(DS.Font.scaled(22))
                                    .foregroundStyle(DS.Color.gradientPrimary)
                            } else {
                                Circle()
                                    .stroke(DS.Color.glassBorder(colorScheme), lineWidth: 1.5)
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
                                    DS.Color.glassSubtle(colorScheme)
                                }
                            }
                        )
                        .cornerRadius(DS.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(selectedPollOption == index ? DS.Color.primary.opacity(0.5) : DS.Color.glassMedium(colorScheme), lineWidth: 1)
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
                actionPill(icon: "heart.fill", text: "١٢", tint: DS.Color.likeAction)
                actionPill(icon: "bubble.right.fill", text: "٥", tint: DS.Color.primary)
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                DS.Color.glassSubtle(colorScheme)
                            }
                        )
                        .overlay(Circle().stroke(DS.Color.glassBorder(colorScheme), lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
            }
        }
    }

    private func actionPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Font.scaled(13, weight: .semibold))
            Text(text)
                .font(DS.Font.subheadline)
                .fontWeight(.bold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, DS.Spacing.md)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                DS.Color.glassDivider(colorScheme)
                tint.opacity(0.12)
            }
        )
        .foregroundColor(tint)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DS.Color.glassBorder(colorScheme), lineWidth: 1.5)
        )
        .shadow(color: tint.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    private var tagColor: Color {
        switch type {
        case "تنبيه", "خبر", "News", "Urgent": return DS.Color.primary
        case "مناسبة", "Event": return DS.Color.success
        case "زواج", "Wedding": return DS.Color.newsWedding
        case "مولود", "Newborn": return DS.Color.newsBirth
        case "وفاة", "Obituary": return DS.Color.newsDeath
        case "تصويت", "Poll": return DS.Color.newsVote
        case "إعلان", "Announcement": return DS.Color.newsAnnouncement
        case "تهنئة", "Congrats": return DS.Color.newsCongrats
        case "تذكير", "Reminder": return DS.Color.newsReminder
        case "دعوة", "Invitation": return DS.Color.newsInvitation
        default: return DS.Color.primary
        }
    }
}
