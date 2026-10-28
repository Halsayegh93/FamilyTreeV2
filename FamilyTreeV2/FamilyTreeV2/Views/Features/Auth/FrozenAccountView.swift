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
                            .dsLandscapeReadable()
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
        // تأكيد الحذف — مربّع التطبيق الموحّد بالمنتصف بدل القائمة السفلية
        .dsAlert(t("حذف الحساب", "Delete Account"),
                 isPresented: $confirmDeletion) {
            Button(t("إلغاء", "Cancel"), role: .cancel) {}
            Button(t("إرسال طلب الحذف", "Send deletion request"), role: .destructive) {
                Task {
                    deletingAccount = true
                    await authVM.requestAccountDeletion()
                    deletingAccount = false
                }
            }
        } message: {
            Text(t(
                "سيُرسل طلب حذف حسابك إلى إدارة التطبيق، ويُنفَّذ خلال سبعة أيام كحد أقصى. يُحذف رقمك وبريدك وصورتك ومنشوراتك وتعليقاتك، ويبقى اسمك وموقعك في شجرة العائلة.",
                "Your deletion request will be sent to the app administration and carried out within seven days at most. Your number, email, photo, posts and comments are deleted; your name and place in the family tree remain."
            ))
        }
        .task {
            await authVM.loadSuspension()
            await authVM.loadAccountDeletionRequest()
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
                DSStateIcon("lock.shield.fill", tint: DS.Color.warning, size: DS.Icon.stateHero)
                .scaleEffect(reduceMotion ? 1 : iconScale)
                .opacity(iconOpacity)

                // العنوان والوصف
                VStack(spacing: DS.Spacing.md) {
                    Text(t("الحساب مجمّد", "Account Frozen"))
                        .dsFont(.emptyTitle)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(t(
                        "تم تجميد حسابك من قبل الإدارة.\nللاستفسار تواصل مع مدير العائلة.",
                        "Your account has been frozen by admin.\nPlease contact the family admin for details."
                    ))
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)

                    // سبب الإيقاف من الإدارة (`my_suspension`) ومهلة الاعتراض (الشروط ٢٠٢٦-١٠-٢٨)
                    if let reason = authVM.suspensionReason {
                        DSNoteCard(reason, title: t("سبب الإيقاف", "Reason"), icon: "info.circle.fill", tint: DS.Color.warning)
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                    Text(t("يمكنك الاعتراض على هذا القرار عبر البريد info@almohali.com خلال سبعة أيام.",
                           "You can appeal this decision by emailing info@almohali.com within seven days."))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xxl)

                    // اسم المستخدم إذا متوفر
                    if let user = authVM.currentUser {
                        HStack(spacing: DS.Spacing.sm) {
                            DSStateIcon("person.fill", tint: DS.Color.warning, size: DS.Icon.row)
                            Text(user.displayFullName)
                                .dsFont(.rowTitle)
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
                    if let pending = authVM.pendingDeletionRequest {
                        Text(t("طلب حذف حسابك قيد المعالجة منذ \(pending.dateText)",
                               "Your account deletion request is being processed since \(pending.dateText)"))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.lg)
                            .dsStaggerIn(3)
                    } else {
                        // الزرّ الواحد بدور الحذف — طلبٌ تنفّذه الإدارة خلال سبعة أيام
                        DSButton(t("حذف الحساب", "Delete account"),
                                 icon: "trash", role: .destructive, isLoading: deletingAccount) {
                            confirmDeletion = true
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .dsStaggerIn(3)
                    }
                    if let error = authVM.deleteAccountError {
                        Text(error).dsFont(.subtitle).foregroundStyle(DS.Color.textSecondary)
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
