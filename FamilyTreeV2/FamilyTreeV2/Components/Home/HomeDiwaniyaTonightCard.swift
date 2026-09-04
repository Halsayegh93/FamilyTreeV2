import SwiftUI

/// بطاقة «الديوانيات الليلة» — تظهر في الرئيسية فقط في أيام الانعقاد.
/// اسم الديوانية وصاحبها وموعدها، مع زر الخريطة إن وُجد رابط.
struct HomeDiwaniyaTonightCard: View {
    let diwaniyas: [Diwaniya]
    let onOpenDiwaniyas: () -> Void

    var body: some View {
        if !diwaniyas.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(LinearGradient(colors: [DS.Color.tileContact, DS.Color.tileContactDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Image(systemName: "moon.stars.fill")
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(diwaniyas.count == 1
                             ? L10n.t("ديوانية الليلة", "Diwaniya tonight")
                             : L10n.t("ديوانيات الليلة", "Diwaniyas tonight"))
                            .font(DS.Font.scaled(14, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("يوم انعقاد", "Gathering day"))
                            .font(DS.Font.scaled(10.5, weight: .semibold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    Spacer()
                    Button(action: onOpenDiwaniyas) {
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(DS.Color.tileContact)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(DS.Color.tileContact.opacity(0.12)))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("الديوانيات", "Diwaniyas"))
                }

                ForEach(diwaniyas.prefix(3)) { d in
                    HStack(spacing: DS.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title)
                                .font(DS.Font.scaled(13, weight: .semibold))
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(d.ownerName)
                                if let s = d.scheduleText, !s.isEmpty {
                                    Text("·")
                                    Text(s).lineLimit(1)
                                }
                            }
                            .font(DS.Font.scaled(11, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if let urlStr = d.mapsUrl, let url = URL(string: urlStr) {
                            Link(destination: url) {
                                Image(systemName: "map")
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(DS.Color.tileContact))
                            }
                            .accessibilityLabel(L10n.t("الموقع على الخريطة", "Open in Maps"))
                        }
                    }
                    .padding(DS.Spacing.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.tileContact.opacity(0.07))
                    )
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.tileContact.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: DS.Color.tileContactDeep.opacity(0.12), radius: 14, x: 0, y: 6)
        }
    }
}
