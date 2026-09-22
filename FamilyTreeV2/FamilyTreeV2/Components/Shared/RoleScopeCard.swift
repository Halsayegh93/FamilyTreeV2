import SwiftUI

// MARK: - بطاقة مجال الدور (طلب المالك)
//
// تُظهر لصاحب الدور ولمن يمنحه: ما مجال هذا الدور، وما يقدر عليه وما لا يقدر.
// تُستخدم عند تعيين دور لعضو، وكبانر «مجالك» أعلى لوحة الإدارة.

struct RoleScopeCard: View {
    let guide: RoleGuide
    /// المختصر: المجال وأول سطرين فقط — للأماكن الضيقة
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle().fill(guide.color.opacity(0.18)).frame(width: 32, height: 32)
                    Image(systemName: guide.icon)
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(guide.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(guide.title)
                        .font(DS.Font.plex(13, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(guide.mandate)
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(compact ? Array(guide.can.prefix(2)) : guide.can, id: \.self) { text in
                    scopeLine(text, icon: "checkmark.circle.fill", color: DS.Color.success)
                }
                ForEach(compact ? Array(guide.cannot.prefix(1)) : guide.cannot, id: \.self) { text in
                    scopeLine(text, icon: "xmark.circle.fill", color: DS.Color.textTertiary.opacity(0.8))
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(guide.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(guide.color.opacity(0.22), lineWidth: 1)
        )
    }

    private func scopeLine(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(DS.Font.plex(11.5, weight: .medium))
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
