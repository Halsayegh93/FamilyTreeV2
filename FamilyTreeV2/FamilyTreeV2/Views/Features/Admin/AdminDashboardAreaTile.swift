import SwiftUI

/// Compact navigation cards keep the section name ahead of secondary statistics.
struct AdminDashboardAreaTile: View {
    let area: AdminArea
    let detail: String
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: area.icon)
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(area.fill.dsReadableGlyph)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(area.fill.opacity(DS.Opacity.tintFillSoft)))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                DSChevron(size: DS.Glyph.xs)
                    .foregroundColor(DS.Color.textTertiary)
            }
            Text(area.title)
                .dsFont(.hubRow)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .dsFont(.footnote)
                .foregroundColor(warning ? DS.Color.warning.dsReadableGlyph : DS.Color.textSecondary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(DS.Color.surface))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
