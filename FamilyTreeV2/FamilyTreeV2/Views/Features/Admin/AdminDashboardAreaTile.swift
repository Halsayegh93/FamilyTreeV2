import SwiftUI

/// Compact section navigation: icon and two-line title, with live detail available to VoiceOver.
struct AdminDashboardAreaTile: View {
    let area: AdminArea
    let detail: String
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: area.icon)
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(area.fill.dsReadableGlyph)
                    .frame(width: 24, height: 24)
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
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width)
            .allowsHitTesting(false))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(area.title)
        .accessibilityValue(detail)
    }
}
