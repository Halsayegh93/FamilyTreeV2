import SwiftUI

// MARK: - DeepLinkKinshipView
// يعرض صلة القرابة لما أحد يفتح deep link من الباركود

struct DeepLinkKinshipView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    private var kinshipResult: KinshipCalculator.KinshipResult? {
        guard let currentUser = authVM.currentUser else { return nil }
        return KinshipCalculator.calculate(
            from: currentUser,
            to: member,
            lookup: memberVM._memberById
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                // أيقونة
                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Circle()
                        .fill(DS.Color.primary.opacity(0.2))
                        .frame(width: 80, height: 80)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }

                // اسم العضو
                VStack(spacing: DS.Spacing.sm) {
                    Text(member.firstName)
                        .font(DS.Font.title1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(KinshipCalculator.lineageText(for: member, lookup: memberVM._memberById))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xxl)
                }

                // صلة القرابة
                if let result = kinshipResult {
                    DSCard(padding: DS.Spacing.lg) {
                        VStack(spacing: DS.Spacing.md) {
                            Text(L10n.t("صلة القرابة", "Kinship"))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.textTertiary)

                            Text(result.relationship)
                                .font(DS.Font.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(DS.Color.gradientPrimary)
                                .multilineTextAlignment(.center)

                            if let ancestor = result.commonAncestor,
                               ancestor.id != member.id,
                               ancestor.id != authVM.currentUser?.id {
                                HStack(spacing: DS.Spacing.sm) {
                                    Image(systemName: "person.3.fill")
                                        .font(DS.Font.caption1)
                                    Text(L10n.t("الجد المشترك: \(ancestor.firstName)", "Common ancestor: \(ancestor.firstName)"))
                                        .font(DS.Font.caption1)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(DS.Color.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                } else {
                    Text(L10n.t("سجّل دخول لمعرفة صلة القرابة", "Sign in to see kinship"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textTertiary)
                }

                Spacer()
            }
            .background(DS.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.t("صلة القرابة", "Kinship"))
                        .font(DS.Font.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(22))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
    }
}
