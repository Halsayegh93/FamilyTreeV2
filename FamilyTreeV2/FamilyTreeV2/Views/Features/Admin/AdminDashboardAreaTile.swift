import SwiftUI

/// Original dashboard card styling, shortened to fit three sections per row.
struct AdminDashboardAreaTile: View {
    let area: AdminArea
    let detail: String
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                AdminIconSquare(symbol: area.icon, tint: area.fill, side: 28,
                                radius: DS.Radius.sm, filled: true, glyph: DS.Glyph.md)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if warning {
                    Image(systemName: "exclamationmark.circle.fill")
                        .dsGlyph(DS.Glyph.xs)
                        .foregroundColor(DS.Color.warning.dsReadableGlyph)
                        .accessibilityHidden(true)
                }
            }
            Text(area.title)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .topLeading)
        .dsCard(padding: DS.Spacing.sm, radius: DS.Hub.tileRadius)
        .contentShape(RoundedRectangle(cornerRadius: DS.Hub.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(area.title)
        .accessibilityValue(detail)
    }
}
