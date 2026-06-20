import SwiftUI

/// بوتم شيت يظهر خيارات طلب التعديل لعضو محدد:
/// إضافة ابن / تعديل اسم / تعديل رقم / تسجيل وفاة / حذف.
struct MemberActionSheet: View {
    let member: FamilyMember
    let onSelect: (TreeEditAction) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availableActions: [TreeEditAction] {
        if member.isDeceased == true {
            return [.add, .editName, .editBirth, .addDeathDate, .addPhoto, .delete, .other]
        }
        return [.add, .editName, .editPhone, .editBirth, .addPhoto, .deceased, .delete, .other]
    }

    private func color(for action: TreeEditAction) -> Color {
        switch action {
        case .add: return DS.Color.success
        case .editName: return DS.Color.info
        case .editPhone: return DS.Color.primary
        case .editBirth: return DS.Color.warning
        case .deceased: return DS.Color.textTertiary
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return DS.Color.primary
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        }
    }

    private func shortLabel(for action: TreeEditAction) -> String {
        switch action {
        case .add: return L10n.t("إضافة ابن", "Add Son")
        case .editName: return L10n.t("تعديل اسم", "Edit Name")
        case .editPhone: return L10n.t("تعديل رقم", "Edit Phone")
        case .editBirth: return L10n.t("تعديل ميلاد", "Edit Birth")
        case .deceased: return L10n.t("تسجيل وفاة", "Deceased")
        case .addDeathDate: return L10n.t("تاريخ وفاة", "Death Date")
        case .addPhoto: return L10n.t("إضافة صورة", "Add Photo")
        case .delete: return L10n.t("حذف", "Delete")
        case .other: return L10n.t("طلب آخر", "Other")
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

                        // الطلبات كأزرار دائرية في شبكة (٣ بالصف) بدل قائمة عمودية.
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: DS.Spacing.md),
                                count: 3
                            ),
                            spacing: DS.Spacing.lg
                        ) {
                            ForEach(availableActions, id: \.rawValue) { action in
                                actionCircle(for: action)
                            }
                        }
                        .padding(.top, DS.Spacing.md)
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

    private func actionCircle(for action: TreeEditAction) -> some View {
        let tint = color(for: action)
        return Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelect(action)
            }
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .overlay(Circle().stroke(tint.opacity(0.28), lineWidth: 1))
                        .frame(width: 64, height: 64)
                    Image(systemName: action.iconName)
                        .font(DS.Font.scaled(24, weight: .semibold))
                        .foregroundColor(tint)
                }
                Text(shortLabel(for: action))
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
