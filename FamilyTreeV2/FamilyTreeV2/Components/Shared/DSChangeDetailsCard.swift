import SwiftUI

/// Admin-only card that renders a structured "what changed" summary for an
/// admin-edit notification. Shown inside `NotificationsCenterView` detail sheet.
struct DSChangeDetailsCard: View {
    let details: AppNotification.NotificationDetails

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            header
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)

            VStack(spacing: DS.Spacing.md) {
                ForEach(Array(details.changes.enumerated()), id: \.element.id) { index, change in
                    changeRow(change)
                    if index < details.changes.count - 1 {
                        divider
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 0.5)
        )
        .dsSubtleShadow()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "pencil.line")
                .font(DS.Font.scaled(11, weight: .bold))
            Text(L10n.t("ما الذي تغيّر", "What Changed"))
                .font(DS.Font.scaled(11, weight: .bold))
                .textCase(.uppercase)
        }
        .foregroundColor(DS.Color.textTertiary)
    }

    // MARK: - Row

    @ViewBuilder
    private func changeRow(_ change: AppNotification.NotificationDetails.ChangeEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppNotification.NotificationDetails.localizedFieldName(change.field))
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            if AppNotification.NotificationDetails.isOpaqueField(change.field) {
                opaqueSummary(for: change)
            } else {
                beforeLine(change.before)
                afterLine(change.after)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beforeLine(_ value: String?) -> some View {
        valueLine(
            label: L10n.t("قبل:", "Before:"),
            value: displayValue(value),
            color: DS.Color.error.opacity(0.85)
        )
    }

    private func afterLine(_ value: String?) -> some View {
        valueLine(
            label: L10n.t("بعد:", "After:"),
            value: displayValue(value),
            color: DS.Color.success
        )
    }

    private func valueLine(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Rectangle()
                .fill(color.opacity(0.55))
                .frame(width: 2.5)
                .clipShape(Capsule())

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(color)

                Text(value)
                    .font(DS.Font.scaled(13, weight: .medium))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
        }
    }

    private func opaqueSummary(for change: AppNotification.NotificationDetails.ChangeEntry) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Rectangle()
                .fill(DS.Color.primary.opacity(0.55))
                .frame(width: 2.5)
                .clipShape(Capsule())

            Text(opaqueSummaryLabel(for: change.field))
                .font(DS.Font.scaled(13, weight: .medium))
                .foregroundColor(DS.Color.textPrimary)

            Spacer(minLength: 0)
        }
    }

    private func opaqueSummaryLabel(for field: String) -> String {
        switch field {
        case "avatar_url":
            return L10n.t("تم تحديث الصورة الشخصية", "Profile photo was updated")
        case "father_id":
            return L10n.t("تم تحديث ولي الأمر", "Father reference was updated")
        default:
            return L10n.t("تم التحديث", "Updated")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.1))
            .frame(height: 0.5)
    }

    // MARK: - Helpers

    private func displayValue(_ raw: String?) -> String {
        guard let v = raw, !v.isEmpty else { return L10n.t("—", "—") }
        return v
    }
}

#if DEBUG
#Preview("DSChangeDetailsCard — multi changes") {
    DSChangeDetailsCard(details: .init(changes: [
        .init(field: "full_name", before: "حسن محمد العلي", after: "حسن محمد الصايغ"),
        .init(field: "birth_date", before: "1990-01-01", after: "1990-05-15"),
        .init(field: "avatar_url", before: nil, after: "https://example.com/x.jpg"),
        .init(field: "phone_number", before: "+96599887766", after: "+96599112233")
    ]))
    .padding()
    .background(DS.Color.background)
}
#endif
