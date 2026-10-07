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
    @Environment(\.dsLandscape) private var landscape

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
                    FT5STrial.waiting()
                    // وضع العرض: أصغر (`DS.Landscape.stateHero`) — الرسمة بمقاسها الثابت فتُصغَّر بالمقياس
                    .scaleEffect(landscape ? DS.Landscape.stateHero / DS.Icon.heroArt : 1)
                    .frame(width: landscape ? DS.Landscape.stateHero : DS.Icon.heroArt,
                           height: landscape ? DS.Landscape.stateHero : DS.Icon.heroArt)
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
                // وضع العرض: البطاقة والأزرار بعمود قراءة متوسّط
                .dsLandscapeReadable()
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

    // MARK: - Info Card — البطاقة الواحدة
    private var infoCard: some View {
        VStack(spacing: DS.Spacing.lg) {
            // اسم التطبيق
            VStack(spacing: DS.Spacing.xs) {
                Text(L10n.t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                    .dsFont(.title)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("شجرة العائلة", "Family Tree"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
            }

            DSDivider()

            // العنوان
            Text(L10n.t("طلبك قيد المراجعة", "Request Under Review"))
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)

            // الوصف
            Text(L10n.t(
                "تم إرسال بياناتك للإدارة.\nيرجى الانتظار حتى يتم التفعيل.",
                "Info submitted.\nPlease wait for activation."
            ))
            .dsFont(.body)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .lineSpacing(DS.Spacing.xs)

            // شارة الحالة — كبسولة الحالة المشتركة (نقطتها تنبض بهدوء)
            DSStatusChip(text: L10n.t("قيد الانتظار", "Pending"), icon: "circle.fill", tint: DS.Color.primary)
                .scaleEffect(pulseScale > 1.05 ? 1.04 : 1.0)

        }
        .padding(DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.xs)
        .dsCard(padding: nil)
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

            // حذف الحساب — الزرّ الواحد بدور الحذف (نفس الإعدادات)
            DSButton(L10n.t("حذف الحساب", "Delete Account"), icon: "trash", role: .destructive,
                     isLoading: deletingAccount) {
                confirmDeletion = true
            }
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
