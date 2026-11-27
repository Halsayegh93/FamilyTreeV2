import SwiftUI

struct WaitingForApprovalView: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Animation states
    @State private var contentOpacity: CGFloat = 0
    @State private var showContactSheet = false
    /// «حذف حسابي» (متطلّب أبل) — تأكيد ثم `delete-account` ثم الخروج
    @State private var showDeleteConfirm = false
    @State private var showDeleteResult = false
    /// «تقليل الحركة» (توصية أبل): بلا دوران ولا نبض ولا قفز متكرر
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // «قيد المراجعة» مربّع صغير في منتصف الشاشة (boxes.png، R1 ٢٠٢٦-١١-٢٧) — نفس صدفة التسجيل
    var body: some View {
        SignupBoxShell(subtitle: L10n.t(SignupOriginRules.Ar.chooseTitle, "Registration")) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                SignupBoxTitle(icon: "clock.fill", title: L10n.t(SignupOriginRules.Ar.waitingTitle, "Your request was received"))
                DSStatusChip(text: L10n.t(SignupOriginRules.Ar.waitingChip, "Under review"), icon: "circle.fill",
                             tint: DS.Color.warning, size: .mini)
                Text(L10n.t(SignupOriginRules.Ar.waitingBody,
                            "Your request was received and will be reviewed by the admins. You'll be notified once it's approved."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // «بنت بنت العائلة» (B1): احتياط لمن سجّلت قبل «من خارج العائلة» ولم تجد والدها في الشجرة (السيرفر يقرّر الظهور)
                DaughterLineageCard()
                actionButtons
            }
        }
        .opacity(contentOpacity)
        .onAppear { startAnimations() }
        // مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك) — العنوان و«إلغاء» داخل المربّع
        .dsCenterBox(isPresented: $showContactSheet) {
            MemberContactFormView()
                .environmentObject(authVM)
        }
        .dsAlert(L10n.t("حذف الحساب", "Delete My Account"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف نهائي", "Delete"), role: .destructive) { performDelete() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t("سيُحذف حسابك وطلب انضمامك وبياناتك نهائياً، ولا يمكن التراجع. هل تريد المتابعة؟",
                        "Your account, join request and data will be permanently deleted. This can't be undone. Continue?"))
        }
        .dsAlert(deleteResultTitle, isPresented: $showDeleteResult) {
            Button(L10n.t("حسناً", "OK")) { authVM.deleteAccountError = nil }
        } message: {
            Text(deleteResultMessage)
        }
    }

    private var deleteResultTitle: String {
        authVM.deleteAccountError == nil ? L10n.t("تم إرسال طلب الحذف", "Deletion Requested")
                                         : L10n.t("تعذّر الحذف", "Couldn't Delete")
    }

    private var deleteResultMessage: String {
        authVM.deleteAccountError ?? L10n.t("ستحذف الإدارة حسابك خلال سبعة أيام.",
                                            "The admins will delete your account within seven days.")
    }

    private func performDelete() {
        Task {
            let deleted = await authVM.deletePendingAccount()
            // نجح = خرج المستخدم؛ وإلا خطأ أو تحويل لطلب حذف → رسالة
            if !deleted, authVM.deleteAccountError != nil || authVM.pendingDeletionRequest != nil {
                showDeleteResult = true
            }
        }
    }

    // MARK: - Action Buttons
    /// زر رئيسي «تحديث حالة الطلب»، وتحته مربّعان جنب بعض «تعديل البيانات» و«تواصل مع الإدارة»، و«تسجيل الخروج»
    /// رابط هادئ آخر الصفحة (طلب المالك ٢٠٢٦-١٠-١٩). «حذف حسابي» رابط أحمر هادئ تحته (متطلّب أبل ٢٠٢٦-١٠-٢٩).
    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                actionTile(L10n.t(SignupOriginRules.Ar.refresh, "Refresh Status"), icon: "arrow.clockwise") {
                    Task { await authVM.checkUserProfile() }
                }
                .disabled(authVM.isLoading)
                actionTile(L10n.t(SignupOriginRules.Ar.editRequest, "Edit Request"), icon: "pencil") {
                    authVM.status = .authenticatedNoProfile
                }
                actionTile(L10n.t(SignupOriginRules.Ar.contactAdmin, "Contact Admin"), icon: "envelope") {
                    showContactSheet = true
                }
            }

            HStack(spacing: DS.Spacing.lg) {
                Button {
                    Task { await authVM.signOut() }
                } label: {
                    Label(L10n.t(SignupOriginRules.Ar.signOut, "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())

                Button {
                    showDeleteConfirm = true
                } label: {
                    Label(L10n.t(SignupOriginRules.Ar.deleteAccount, "Delete My Account"), systemImage: "trash")
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.error)
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .disabled(authVM.isLoading)
            }
            .frame(maxWidth: .infinity)
        }
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
    /// ظهور المربّع بتلاشٍ قصير (بلا نبض متكرر — قاعدة «لا repeatForever»)
    private func startAnimations() {
        withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.elastic.delay(0.1)) {
            contentOpacity = 1.0
        }
    }
}
