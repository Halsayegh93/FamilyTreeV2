import SwiftUI

struct WaitingForApprovalView: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Animation states
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.6
    @State private var contentOpacity: CGFloat = 0
    @State private var showContactSheet = false
    /// حذف الحساب متاح لمن ينتظر الموافقة أيضاً (Guideline 5.1.1(v))
    @State private var confirmDeletion = false
    @State private var deletingAccount = false
    /// «تقليل الحركة» (توصية أبل): بلا دوران ولا نبض ولا قفز متكرر
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // الهيدر الموحّد — نفس بقية الواجهات
                authHeader(
                    icon: "hourglass",
                    title: L10n.t("قيد المراجعة", "Under Review"),
                    subtitle: L10n.t("طلبك وصل الإدارة وينتظر الموافقة",
                                     "Your request reached the admins")
                )

                ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    Spacer().frame(height: DS.Spacing.sm)

                    // ساعة رملية مصمتة على قرص بلون الإدارة، وخيط رمل ذهبي تنساب فيه لمعة كل ٤ ث
                    // (طلب المالك ٢٠٢٦-١٠-٠٥ «أبسط وأقوى وباعتدال») — بدل الأيقونة والنقاط
                    TrialArt(make: { ArtDispatch.waiting($0) }) {   // TMP-ART-TRIAL
                        FTSceneCanvas { ctx, size, t, dark in
                            FTPlaceScenes.drawWaitingMajlis(in: &ctx, size: size, t: t, dark: dark)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .opacity(contentOpacity)

                    // بعد الأيقونة تدخل البطاقة ثم الأزرار واحداً بعد الآخر (dsStaggerIn)
                    // بطاقة المعلومات
                    infoCard
                        .dsStaggerIn(0)

                    // الأزرار
                    actionButtons

                    Spacer().frame(height: DS.Spacing.xxl)
                }
                // الأقسام تبدأ بعد الأيقونة (نفس «بعد الرأس» في المربّعات)
                .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear {
            startAnimations()
        }
        // مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك) — العنوان و«إلغاء» داخل المربّع
        .dsCenterBox(isPresented: $showContactSheet) {
            MemberContactFormView()
                .environmentObject(authVM)
        }
        .dsAlert(L10n.t("حذف الحساب", "Delete Account"), isPresented: $confirmDeletion) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                Task {
                    deletingAccount = true
                    _ = await authVM.deleteAccount()
                    deletingAccount = false
                }
            }
        } message: {
            Text(L10n.t("سيُحذف حسابك وطلب انضمامك وبياناتك نهائياً. لا يمكن التراجع عن هذا الإجراء.",
                        "Your account, join request and data will be permanently deleted. This cannot be undone."))
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: .init(
            get: { authVM.deleteAccountError != nil },
            set: { if !$0 { authVM.deleteAccountError = nil } }
        )) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(authVM.deleteAccountError ?? "")
        }
    }

    // MARK: - Info Card
    private var infoCard: some View {
        VStack(spacing: DS.Spacing.lg) {
            // اسم التطبيق
            VStack(spacing: DS.Spacing.xs) {
                Text(L10n.t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("شجرة العائلة", "Family Tree"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            DSDivider()

            // العنوان
            Text(L10n.t("طلبك قيد المراجعة", "Request Under Review"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textPrimary)

            // الوصف
            Text(L10n.t(
                "تم إرسال بياناتك للإدارة.\nيرجى الانتظار حتى يتم التفعيل.",
                "Info submitted.\nPlease wait for activation."
            ))
            .font(DS.Font.body)
            .foregroundColor(DS.Color.textPrimary.opacity(0.75))
            .multilineTextAlignment(.center)
            .lineSpacing(4)

            // شارة الحالة
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(DS.Color.primary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseScale > 1.05 ? 1.2 : 1.0)
                Text(L10n.t("قيد الانتظار", "Pending"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.primary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.primary.opacity(0.08))
            .cornerRadius(DS.Radius.full)

        }
        .padding(DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.15), lineWidth: 1)
        )
        .dsSubtleShadow()
        .padding(.horizontal, DS.Spacing.xl)
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            DSPrimaryButton(
                L10n.t("تحديث حالة الطلب", "Refresh Status"),
                icon: "arrow.clockwise",
                isLoading: authVM.isLoading
            ) {
                Task { await authVM.checkUserProfile() }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .dsStaggerIn(1)

            DSSecondaryButton(
                L10n.t("تعديل البيانات", "Edit Info"),
                icon: "pencil"
            ) {
                authVM.status = .authenticatedNoProfile
            }
            .padding(.horizontal, DS.Spacing.xl)
            .dsStaggerIn(2)

            DSSecondaryButton(
                L10n.t("تواصل مع الإدارة", "Contact Admin"),
                icon: "envelope.fill"
            ) {
                showContactSheet = true
            }
            .padding(.horizontal, DS.Spacing.xl)
            .dsStaggerIn(3)

            DSSecondaryButton(
                L10n.t("تسجيل الخروج", "Sign Out"),
                icon: "rectangle.portrait.and.arrow.right",
                color: DS.Color.error
            ) {
                Task { await authVM.signOut() }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .dsStaggerIn(4)

            // حذف الحساب — زر هادئ في الأسفل (نفس أسلوب الإعدادات)
            Button { confirmDeletion = true } label: {
                HStack(spacing: DS.Spacing.xs) {
                    if deletingAccount {
                        ProgressView().tint(DS.Color.error)
                    } else {
                        Image(systemName: "trash")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .accessibilityHidden(true)   // زخرفة — النص يكفي
                    }
                    Text(L10n.t("حذف الحساب", "Delete Account"))
                        .font(DS.Font.plex(14, weight: .bold))
                }
                .foregroundColor(DS.Color.error)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(DS.Color.error.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(deletingAccount)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xl)
            .dsStaggerIn(5)
        }
    }

    // MARK: - Animations
    private func startAnimations() {
        // ظهور المحتوى — «تقليل الحركة»: تلاشٍ قصير بدل النابض
        // (البطاقة والأزرار تدخل تباعاً بعدها عبر dsStaggerIn)
        withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.elastic.delay(0.2)) {
            contentOpacity = 1.0
        }

        // تقليل الحركة: تبقى شارة «قيد الانتظار» ثابتة (المشهد يتوقف وحده)
        guard !reduceMotion else { return }

        // نبض الحلقة
        withAnimation(
            .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.12
            pulseOpacity = 0.0
        }

    }
}
