import SwiftUI

struct FrozenAccountView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var showContactSheet = false
    @State private var confirmDeletion = false
    @State private var deletingAccount = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — نلف المحتوى بـScrollView حتى لا يُقتص
    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            Group {
                if isLandscape {
                    ScrollView(showsIndicators: false) {
                        frozenContent
                            .padding(.vertical, DS.Spacing.lg)
                    }
                } else {
                    frozenContent
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            // الأيقونة أولاً («تقليل الحركة»: تلاشٍ قصير بلا تكبير)، ثم النص والأزرار تباعاً (dsStaggerIn)
            withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.elastic.delay(0.2)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
        .confirmationDialog(t("حذف الحساب وبياناته نهائياً؟", "Permanently delete your account and personal data?"), isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button(t("حذف الحساب", "Delete account"), role: .destructive) {
                Task {
                    deletingAccount = true
                    _ = await authVM.deleteAccount()
                    deletingAccount = false
                }
            }
        }
        // مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك) — العنوان و«إلغاء» داخل المربّع
        .dsCenterBox(isPresented: $showContactSheet) {
            MemberContactFormView()
                .environmentObject(authVM)
        }
    }

    /// محتوى شاشة التجميد — نفسه في الوضعين
    private var frozenContent: some View {
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
                .scaleEffect(reduceMotion ? 1 : iconScale)
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
                            Text(user.displayFullName)
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                        .padding(.top, DS.Spacing.sm)
                    }
                }
                .dsStaggerIn(0)

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
                .dsStaggerIn(1)

                // زر التواصل مع الإدارة
                DSSecondaryButton(
                    t("تواصل مع الإدارة", "Contact Admin"),
                    icon: "envelope.fill"
                ) {
                    showContactSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)
                .dsStaggerIn(2)

                if !authVM.isOwner {
                    Button(role: .destructive) { confirmDeletion = true } label: {
                        HStack {
                            if deletingAccount { ProgressView() }
                            Text(t("حذف الحساب / استكمال الحذف", "Delete account / resume deletion"))
                        }
                    }
                    .disabled(deletingAccount)
                    .dsStaggerIn(3)
                    if let error = authVM.deleteAccountError {
                        Text(error).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary)
                    }
                }

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
                .dsStaggerIn(authVM.isOwner ? 3 : 4)
            }
            // بعد الأيقونة: النص ← الأزرار واحداً بعد الآخر (نفس «بعد الرأس» في المربّعات)
            .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
    }
}
