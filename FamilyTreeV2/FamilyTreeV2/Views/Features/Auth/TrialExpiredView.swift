import SwiftUI

struct TrialExpiredView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private var expiryDateText: String? {
        guard let date = authVM.trialEndsAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xl) {
                Spacer()

                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(DS.Font.scaled(48, weight: .bold))
                    .foregroundColor(DS.Color.warning)

                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("انتهت الفترة التجريبية", "Trial Period Ended"))
                        .font(DS.Font.title2)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(
                        L10n.t(
                            "انتهت مدة التجربة (٧ أيام). يرجى التواصل مع الإدارة لتفعيل الحساب.",
                            "Your 7-day trial has ended. Please contact admin to activate your account."
                        )
                    )
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)

                    if let expiryDateText {
                        Text(L10n.t("تاريخ الانتهاء: \(expiryDateText)", "Ended on: \(expiryDateText)"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)

                VStack(spacing: DS.Spacing.md) {
                    DSPrimaryButton(L10n.t("تحديث الحالة", "Refresh Status"), icon: "arrow.clockwise") {
                        Task { await authVM.checkUserProfile() }
                    }

                    Button {
                        Task { await authVM.signOut() }
                    } label: {
                        Text(L10n.t("تسجيل الخروج", "Sign Out"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.error)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(DS.Color.error.opacity(0.08))
                            .cornerRadius(DS.Radius.lg)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.lg)
                                    .stroke(DS.Color.error.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(DSBoldButtonStyle())
                }
                .padding(.horizontal, DS.Spacing.xl)

                Spacer()
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }
}
