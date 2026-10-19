import SwiftUI

struct WaitingForApprovalView: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Animation states
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.6
    @State private var contentOpacity: CGFloat = 0
    @State private var showContactSheet = false
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
                VStack(spacing: DS.Spacing.xl) {
                    Spacer().frame(height: DS.Spacing.sm)

                    // ساعة رملية مصمتة على قرص بلون الإدارة، وخيط رمل ذهبي تنساب فيه لمعة كل ٤ ث
                    // (طلب المالك ٢٠٢٦-١٠-٠٥ «أبسط وأقوى وباعتدال») — بدل الأيقونة والنقاط
                    FT5STrial.waiting()
                    // أصغر قليلاً (`DS.Icon.stateHero` — طلب المالك ٢٠٢٦-١٠-١٩)، ووضع العرض أصغر
                    // (`DS.Landscape.stateHero`) — الرسمة بمقاسها الثابت فتُصغَّر بالمقياس
                    .scaleEffect(heroSide / DS.Icon.heroArt)
                    .frame(width: heroSide, height: heroSide)
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
    }

    /// قطر رسمة الانتظار — أصغر قليلاً من مقاسها الأصلي، وأصغر في وضع العرض
    private var heroSide: CGFloat { landscape ? DS.Landscape.stateHero : DS.Icon.stateHero }

    // MARK: - Info Card — البطاقة الواحدة
    /// عنوان + سطر قصير + شارة الحالة فقط (طلب المالك ٢٠٢٦-١٠-١٩ «أبسط») — اسم العائلة
    /// و«شجرة العائلة» والفاصل انشالت من هنا (الرأس يكفي)
    private var infoCard: some View {
        VStack(spacing: DS.Spacing.md) {
            // العنوان
            Text(L10n.t("طلبك قيد المراجعة", "Request Under Review"))
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)

            // سطر واحد قصير
            Text(L10n.t("يُفعَّل حسابك فور الموافقة", "Your account activates once approved"))
                .dsFont(.body)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // شارة الحالة — كبسولة الحالة المشتركة (نقطتها تنبض بهدوء)
            DSStatusChip(text: L10n.t("قيد الانتظار", "Pending"), icon: "circle.fill", tint: DS.Color.primary)
                .scaleEffect(pulseScale > 1.05 ? 1.04 : 1.0)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
        .dsCard(padding: nil)
        .padding(.horizontal, DS.Spacing.xl)
    }

    // MARK: - Action Buttons
    /// زر رئيسي «تحديث حالة الطلب»، وتحته مربّعان جنب بعض «تعديل البيانات» و«تواصل مع الإدارة»، و«تسجيل الخروج»
    /// رابط هادئ آخر الصفحة (طلب المالك ٢٠٢٦-١٠-١٩). «حذف الحساب» انشال من هنا — بإعدادات الملف الشخصي (قرار المالك).
    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            DSPrimaryButton(
                L10n.t("تحديث حالة الطلب", "Refresh Status"),
                icon: "arrow.clockwise",
                isLoading: authVM.isLoading
            ) {
                Task { await authVM.checkUserProfile() }
            }
            .dsStaggerIn(1)

            HStack(spacing: DS.Spacing.sm) {
                actionTile(L10n.t("تعديل البيانات", "Edit Info"), icon: "pencil") {
                    authVM.status = .authenticatedNoProfile
                }
                actionTile(L10n.t("تواصل مع الإدارة", "Contact Admin"), icon: "envelope.fill") {
                    showContactSheet = true
                }
            }
            .dsStaggerIn(2)

            Button {
                Task { await authVM.signOut() }
            } label: {
                Label(L10n.t("تسجيل الخروج", "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .dsStaggerIn(3)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xl)
    }

    /// مربّع إجراء: قرص برمزه فوق والاسم تحته — بشكل مربّعات الخيارات (DSOptionTiles)
    private func actionTile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button(action: action) {
            VStack(spacing: DS.Spacing.xsm) {
                DSOptionTileIcon(icon: icon, selected: false)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(shape.fill(DS.Color.background))
            .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.border), lineWidth: DS.Border.width))
            .trialCardSkin(radius: DS.Radius.md, solid: true)
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(title)
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
