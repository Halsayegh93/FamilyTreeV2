import SwiftUI

// بوستات المناسبات من main (الهوية، ٢٠٢٦-١٠-١٧) مبنية على مكوّنين من الطقم القديم أزالهما التطبيق المحلي
// في ٢٠٢٦-١٠-٠٧ (`DSCard`، `DSSectionHeader`). منسوخان هنا كما هما في main حتى تبقى شاشة المناسبات بشكل main
// تماماً — لشاشات المناسبات فقط؛ باقي التطبيق يستعمل `.dsCard()` و`DSSectionTitle`.

/// كرت موحد — سطح أبيض، حد line، زوايا xl، ظل خفيف (الهوية)
struct DSCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = DS.Spacing.lg

    init(padding: CGFloat = DS.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.cardBackground)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(DS.Color.cardBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            // منطقة اللمس = حدود البطاقة فقط
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .dsCardShadow()
    }
}

/// عنوان قسم — Bold
struct DSSectionHeader: View {
    var title: String
    var icon: String? = nil
    var trailing: String? = nil
    var iconColor: Color = DS.Color.primary

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    if let icon {
                        Image(systemName: icon)
                            .font(DS.Font.icon(12, weight: .bold))
                            .foregroundColor(iconColor)
                    }
                    Text(title)
                        .dsFont(.chip)
                        .foregroundColor(iconColor)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(iconColor.opacity(0.08))
                .clipShape(Capsule())

                if let trailing {
                    // تلميح ثانوي — لا ينافس عنوان القسم في اللون ولا الحجم
                    Text(trailing)
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            DSDivider()
        }
    }
}
