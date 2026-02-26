import SwiftUI

struct UIComponents {

    struct Theme {
        static let ruler:        CGFloat = DS.Icon.size
        static let spacing:      CGFloat = DS.Spacing.xs
        static let cornerRadius: CGFloat = DS.Radius.md
        static let cardRadius:   CGFloat = DS.Radius.xl
        static let iconOpacity:  CGFloat = DS.Icon.opacity
    }

    // 1. البطاقة الموحدة — Professional solid card
    struct UnifiedCard<Content: View>: View {
        let content: Content
        init(@ViewBuilder content: () -> Content) { self.content = content() }
        var body: some View {
            VStack(spacing: 0) { content }
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
                .dsCardShadow()
        }
    }

    // 2. حقل الإدخال الموحد — Bold Glass style
    struct UnifiedTextField: View {
        @Environment(\.layoutDirection) private var layoutDirection
        var label: String
        var placeholder: String
        @Binding var text: String
        var icon: String
        var keyboard: UIKeyboardType = .default

        var body: some View {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .foregroundColor(DS.Color.primary)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: Theme.ruler, height: Theme.ruler)
                    .background(DS.Color.primary.opacity(DS.Icon.opacity))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                TextField(placeholder, text: $text)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .keyboardType(keyboard)
                    .accentColor(DS.Color.primary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    // 3. صف البيانات — Bold Glass icon style
    struct DataRow: View {
        var title: String
        var value: String
        var icon: String
        var color: Color

        var body: some View {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: Theme.ruler, height: Theme.ruler)
                    .background(color.opacity(DS.Icon.opacity))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Text(title).font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                    Text(value).font(DS.Font.calloutBold)
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    // 4. صف الإجراءات — Bold Glass style
    struct ActionRow: View {
        var title: String
        var icon: String
        var color: Color

        var body: some View {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: Theme.ruler, height: Theme.ruler)
                    .background(color.opacity(DS.Icon.opacity))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                Text(title).font(DS.Font.calloutBold)
                Spacer()
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    // 5. عنوان القسم — Bold Glass icon circle
    struct SectionHeader: View {
        var title: String
        var icon: String

        var body: some View {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 34, height: 34)
                    .background(DS.Color.primary.opacity(DS.Icon.opacity))
                    .clipShape(Circle())

                Text(title).font(DS.Font.headline).foregroundColor(DS.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }
}
