import SwiftUI

struct FrozenAccountView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: DS.Spacing.xxl) {

                Spacer()

                // أيقونة التجميد
                ZStack {
                    Circle()
                        .fill(DS.Color.warning.opacity(0.15))
                        .frame(width: 110, height: 110)

                    Image(systemName: "lock.shield.fill")
                        .font(DS.Font.scaled(48, weight: .bold))
                        .foregroundStyle(DS.Color.warning)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // العنوان والوصف
                VStack(spacing: DS.Spacing.md) {
                    Text(t("الحساب مجمّد", "Account Frozen"))
                        .font(DS.Font.title2)
                        .fontWeight(.black)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(t(
                        "تم تجميد حسابك من قبل الإدارة.\nللاستفسار تواصل مع مدير العائلة.",
                        "Your account has been frozen by admin.\nPlease contact the family admin for details."
                    ))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)

                    // اسم المستخدم إذا متوفر
                    if let user = authVM.currentUser {
                        HStack(spacing: DS.Spacing.sm) {
                            DSIcon("person.fill", color: DS.Color.warning, size: 32, iconSize: 14)
                            Text(user.fullName)
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                        .padding(.top, DS.Spacing.sm)
                    }
                }
                .opacity(textOpacity)

                Spacer()

                // زر تحديث الحالة
                DSPrimaryButton(
                    t("تحديث الحالة", "Refresh Status"),
                    icon: "arrow.clockwise"
                ) {
                    Task {
                        await authVM.checkUserProfile()
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)

                // زر تسجيل الخروج
                DSSecondaryButton(
                    t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right"
                ) {
                    Task {
                        await authVM.signOut()
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            withAnimation(DS.Anim.elastic.delay(0.2)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(DS.Anim.smooth.delay(0.5)) {
                textOpacity = 1.0
            }
        }
    }
}
