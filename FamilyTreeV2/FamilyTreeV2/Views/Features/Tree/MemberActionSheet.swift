import SwiftUI

/// بوتم شيت يظهر خيارات طلب التعديل لعضو محدد:
/// إضافة ابن / تعديل اسم / تعديل رقم / تسجيل وفاة / حذف.
struct MemberActionSheet: View {
    let member: FamilyMember
    let onSelect: (TreeEditAction) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availableActions: [TreeEditAction] {
        if member.isDeceased == true {
            return [.add, .editName, .delete]
        }
        return [.add, .editName, .editPhone, .deceased, .delete]
    }

    private func color(for action: TreeEditAction) -> Color {
        switch action {
        case .add: return DS.Color.success
        case .editName: return DS.Color.info
        case .editPhone: return DS.Color.primary
        case .deceased: return DS.Color.textTertiary
        case .delete: return DS.Color.error
        }
    }

    private func label(for action: TreeEditAction) -> String {
        let firstName = member.firstName
        switch action {
        case .add:
            return L10n.t("إضافة ابن لـ \(firstName)", "Add son to \(firstName)")
        case .editName:
            return L10n.t("تعديل اسم \(firstName)", "Edit \(firstName)'s name")
        case .editPhone:
            return L10n.t("تعديل رقم \(firstName)", "Edit \(firstName)'s phone")
        case .deceased:
            return L10n.t("تسجيل وفاة \(firstName)", "Mark \(firstName) deceased")
        case .delete:
            return L10n.t("طلب حذف \(firstName)", "Request to delete \(firstName)")
        }
    }

    private func subtitle(for action: TreeEditAction) -> String {
        switch action {
        case .add:
            return L10n.t("إضافة ابن جديد تحت هذا العضو", "Add a new son under this member")
        case .editName:
            return L10n.t("طلب تعديل الاسم الكامل", "Request a full name correction")
        case .editPhone:
            return L10n.t("طلب تعديل رقم الهاتف", "Request a phone number change")
        case .deceased:
            return L10n.t("تسجيل وفاة مع تاريخ", "Record death with date")
        case .delete:
            return L10n.t("إخفاء العضو من الشجرة", "Hide member from the tree")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        memberHeader
                            .padding(.top, DS.Spacing.md)

                        VStack(spacing: DS.Spacing.sm) {
                            ForEach(availableActions, id: \.rawValue) { action in
                                actionRow(for: action)
                            }
                        }
                        .padding(.top, DS.Spacing.sm)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationTitle(L10n.t("اختر نوع الطلب", "Choose Request Type"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private var memberHeader: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Text(String(member.firstName.prefix(1)))
                    .font(DS.Font.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("طلب تعديل لـ", "Edit request for"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func actionRow(for action: TreeEditAction) -> some View {
        let tint = color(for: action)
        return Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelect(action)
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: action.iconName)
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label(for: action))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(for: action))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
