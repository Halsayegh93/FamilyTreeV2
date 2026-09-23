import SwiftUI
import Supabase
import PhotosUI

// MARK: - Cooldown Guard Modifier

/// لا قفل للحقول بعد الآن (طلب المالك): الحقل يبقى قابلاً للتعديل دائماً،
/// وما تجاوز حد الـ٣ تعديلات يُرسَل للإدارة عند الحفظ بدل تطبيقه مباشرة.
private extension View {
    func cooldownGuarded(_ field: EditableField, cooldown: ProfileEditCooldown, onLocked: @escaping () -> Void) -> some View {
        self
    }
}

/// مربّع «تم تجاوز حد التعديلات» — النص كله يميناً في العربية
private struct EditLimitPopup: View {
    let onClose: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(DS.Color.warning)
                    Text(L10n.t("تم تجاوز حد التعديلات", "Edit limit reached"))
                        .font(DS.Font.plex(17, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                }
                Text(L10n.t(
                    "عدّلت هذه البيانات ٣ مرات، وهو الحد المسموح.\nأُرسل تعديلك للإدارة، وسيُطبَّق بعد موافقتها.",
                    "You've edited this 3 times, which is the limit.\nYour edit was sent to the admins and will apply once approved."
                ))
                .font(DS.Font.plex(14, weight: .regular))
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                Button(action: close) {
                    Text(L10n.t("حسناً", "OK"))
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DSActionFill.style(), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(DSScaleButtonStyle())
                .padding(.top, DS.Spacing.xs)
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 340)
            .background(DS.Color.background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
            .padding(.horizontal, DS.Spacing.xl)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { withAnimation(DS.Anim.snappy) { appeared = true } }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }
}

struct EditProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) var dismiss

    @State var member: FamilyMember

    // متغيرات الحالة
    @State private var fullName: String = ""
    /// عائلة العضو المختارة من قائمة الإدارة
    @State private var familyName: String = ""
    /// العائلة ثابتة — تتغيّر بطلب للإدارة فقط (طلب المالك)
    @State private var pendingFamilyRequest: String?
    /// الرقم ثابت — يتغيّر بطلب مع إثبات الرقم برمز تحقق (طلب المالك)
    @State private var pendingPhoneRequest: String?
    @State private var appliedPhoneDisplay: String?
    /// لا شيء يُطبَّق قبل «حفظ» (طلب المالك) — الإلغاء يرجّع كل شيء
    @State private var pendingAvatarDelete = false
    @State private var showAvatarDeleteConfirm = false
    @State private var pendingNameRequest: String?
    @State private var pendingPhoneVerified: (e164: String, country: KuwaitPhone.Country, digits: String, display: String)?
    /// رقم لم يُتحقق منه ذاتياً (عليه حساب آخر) — يُرسل للإدارة عند «حفظ»
    @State private var pendingPhoneForAdmins: (storage: String, display: String)?
    @State private var showPhoneChangeSheet = false
    @State private var familyPopupID: UUID?
    @State private var bioPopupID: UUID?
    @State private var isSavingFamily = false
    @StateObject private var familyNamesVM = FamilyNamesViewModel()
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = Date()
    /// هل يملك العضو تاريخ ميلاد فعلي (أو حدّده المستخدم الآن)؟ — نتجنّب كتابة
    /// "اليوم" المفبرك لمن لا تاريخ له، لأن ذلك يُفعّل trigger السيرفر بلا داعٍ.
    @State private var birthDateProvided: Bool = false
    @State private var isMarried: Bool = false
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var isPhoneHidden: Bool = false
    @State private var email: String = ""
    @State private var emailFieldFocused: Bool = false
    @FocusState private var isEmailFocused: Bool
    // متغيرات الصورة
    @State private var localPreviewImage: UIImage? = nil
    // Bio
    @State private var bioStations: [FamilyMember.BioStation] = []
    @State private var showDeleteBioAlert = false
    @State private var showSaveError = false
    @State private var showNameChangeSheet = false
    @State private var newNameRequest: String = ""
    @State private var isSubmittingName = false
    /// مربّع «تم تجاوز حد التعديل» — يظهر عند محاولة تعديل حقل مقفل
    @State private var showEditLimitAlert = false
    /// بعد الحفظ: إغلاق الشاشة عند الضغط على «حسناً» في مربّع تجاوز الحد
    @State private var dismissAfterLimitAlert = false
    @State private var showDiscardAlert = false
    /// يظهر تأكيد «قيد المراجعة» بعد إرسال طلب تغيير (رقم/وفاة) للإدارة قبل الإغلاق.
    @State private var showRequestSentAlert = false

    private let cooldown = ProfileEditCooldown.shared

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — النموذج يتوزع على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }



    private var editScreenTitle: String {
        if member.id == authVM.currentUser?.id {
            return L10n.t("تعديل البيانات", "Edit Profile")
        }
        return L10n.t("تعديل بيانات الابن", "Edit Child Info")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background with decorative circles
                DS.Color.background.ignoresSafeArea()


                ScrollView(showsIndicators: false) {
                    if isLandscape {
                        // الوضع الأفقي: عمودان — يمين (الصورة + الحالة) ويسار (البيانات + المحطات + الحفظ)
                        HStack(alignment: .top, spacing: DS.Spacing.md) {
                            VStack(spacing: DS.Spacing.md) {
                                avatarPickerBlock
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: DS.Spacing.md) {
                                personalInfoCard
                                bioStationsSection
                                    .cooldownGuarded(.bio, cooldown: cooldown) { showEditLimitAlert = true }
                                offlineNotice
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    } else {
                    VStack(spacing: DS.Spacing.md) {

                        // 1. قسم الصورة الشخصية (تصميم دائري مع ظل فخم)
                        VStack(spacing: DS.Spacing.xs) {
                            imagePickerHeader
                                .cooldownGuarded(.avatar, cooldown: cooldown) { showEditLimitAlert = true }
                            Label(
                                L10n.t("اضغط على الصورة لتغييرها", "Tap the photo to change it"),
                                systemImage: "camera.fill"
                            )
                            .font(DS.Font.plex(12.5))
                            .foregroundColor(DS.Color.primary)
                        }

                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                                icon: "person.text.rectangle",
                                iconColor: DS.Color.primary
                            )

                                VStack(spacing: 0) {
                                    nameFieldWithChangeRequest
                                    DSDivider()
                                    familyPickerRow
                                    DSDivider()
                                    modernPhoneField

                                    DSDivider()
                                    birthDateRow

                                    DSDivider()
                                    maritalRow

                                }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 3. السيرة الذاتية
                        bioStationsSection
                            .cooldownGuarded(.bio, cooldown: cooldown) { showEditLimitAlert = true }

                        // 5. تنبيه عدم الاتصال — زر الحفظ صار أعلى الشاشة (طلب المالك)
                        offlineNotice

                    }
                    .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
            .navigationTitle(editScreenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        if hasUnsavedChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .foregroundColor(DS.Color.error)
                }
                // زر الحفظ أعلى الشاشة (طلب المالك)
                ToolbarItem(placement: DSToolbar.confirmPlacement) {
                    if memberVM.isLoading {
                        ProgressView()
                    } else {
                        Button(L10n.t("حفظ", "Save"), action: saveChangesAction)
                            .font(DS.Font.plex(14.5, weight: .bold))
                            .foregroundColor(isSaveDisabled ? DS.Color.textTertiary : DS.Color.primary)
                            .disabled(isSaveDisabled)
                    }
                }
            }
            .dsAlert(
                L10n.t("تجاهل التعديلات؟", "Discard Changes?"),
                isPresented: $showDiscardAlert
            ) {
                Button(L10n.t("تجاهل", "Discard"), role: .destructive) { dismiss() }
                Button(L10n.t("إكمال التعديل", "Keep Editing"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "لديك تعديلات غير محفوظة. هل تريد تجاهلها؟",
                    "You have unsaved changes. Discard them?"
                ))
            }
        .task { await familyNamesVM.fetch() }
            .onAppear {
                setupData()
            }
            .fullScreenCover(isPresented: $showEditLimitAlert) {
                EditLimitPopup {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { showEditLimitAlert = false }
                    if dismissAfterLimitAlert {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { dismiss() }
                    }
                }
                .background(ClearPresentationBackground())
            }
            .transaction { t in
                // بلا انزلاق من الأسفل — المربّع يظهر بنفسه في المنتصف
                if showEditLimitAlert { t.disablesAnimations = true }
            }
            .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showSaveError) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t("تعذر الحفظ. حاول مرة أخرى.", "Save failed. Try again."))
            }
            .dsAlert(
                L10n.t("تم إرسال طلب التغيير للإدارة", "Change Request Sent"),
                isPresented: $showRequestSentAlert
            ) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(L10n.t(
                    "طلبك الآن قيد المراجعة، وستصلك النتيجة بعد موافقة الإدارة.",
                    "Your request is now pending review — you'll be notified once the admins respond."
                ))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - كتل التخطيط (تُستخدم في الوضع الأفقي)

    /// قسم الصورة الشخصية — نفس محتوى الوضع العمودي
    private var avatarPickerBlock: some View {
        VStack(spacing: DS.Spacing.xs) {
            imagePickerHeader
                .cooldownGuarded(.avatar, cooldown: cooldown) { showEditLimitAlert = true }
            Label(
                pendingAvatarDelete
                    ? L10n.t("ستُحذف الصورة عند الحفظ", "Photo will be removed on save")
                    : L10n.t("اضغط على الكاميرا لخيارات الصورة", "Tap the camera for photo options"),
                systemImage: pendingAvatarDelete ? "trash.fill" : "camera.fill"
            )
            .font(DS.Font.plex(12.5))
            .foregroundColor(DS.Color.primary)
        }
    }

    /// بطاقة المعلومات الشخصية — نفس محتوى الوضع العمودي
    private var personalInfoCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                icon: "person.text.rectangle",
                iconColor: DS.Color.primary
            )

            VStack(spacing: 0) {
                nameFieldWithChangeRequest
                DSDivider()
                familyPickerRow
                DSDivider()
                modernPhoneField

                DSDivider()
                birthDateRow

                DSDivider()
                maritalRow

            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    /// الحالة الاجتماعية — صف داخل «المعلومات الشخصية» تحت تاريخ الميلاد (طلب المالك)
    private var maritalRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("heart.fill", color: DS.Color.primary)
            Text(L10n.t("الحالة الاجتماعية", "Marital Status"))
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
            Spacer(minLength: DS.Spacing.sm)
            HStack(spacing: 6) {
                maritalChip(L10n.t("أعزب", "Single"), selected: !isMarried, color: DS.Color.primary) { setMarried(false) }
                // «متزوج» بلون التطبيق الأساسي (الكحلي) — طلب المالك
                maritalChip(L10n.t("متزوج", "Married"), selected: isMarried, color: DS.Color.primary) { setMarried(true) }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func maritalChip(_ title: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.scaled(13, weight: selected ? .bold : .medium))
                .foregroundColor(selected ? .white : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 32)
                .background(Capsule().fill(selected ? color : DS.Color.mutedBackground.opacity(0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - المكونات المصممة (Custom Components)

    private var imagePickerHeader: some View {
        // أيقونة الكاميرا وحدها تحمل الأوامر (بلا أزرار مكرّرة تحت الصورة — طلب المالك)
        DSProfilePhotoPicker(
            selectedImage: $localPreviewImage,
            existingURL: pendingAvatarDelete ? nil : member.avatarUrl,
            enableCrop: true,
            cropShape: .circle,
            trailing: nil,
            showDeleteForExisting: member.avatarUrl != nil && !pendingAvatarDelete,
            onDeleteExisting: { showAvatarDeleteConfirm = true },
            compactEmptyState: true,
            useOverlayActionsOnly: true
        )
        .padding(.horizontal, DS.Spacing.lg)
        .dsAlert(L10n.t("حذف الصورة", "Delete photo"), isPresented: $showAvatarDeleteConfirm) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                pendingAvatarDelete = true
                localPreviewImage = nil
            }
        } message: {
            Text(L10n.t("تُحذف صورتك عند الحفظ. تقدر تتراجع بالضغط على «إلغاء».",
                        "Your photo is removed when you save. Cancel to keep it."))
        }
    }

    // MARK: - Name with Change Request
    private var nameFieldWithChangeRequest: some View {
        VStack(spacing: 0) {
            Button {
                // تغيير الاسم يُرسل للإدارة دائماً — بلا عدّاد
                openNamePopup()
            } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("person.fill", color: DS.Color.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("الاسم الكامل", "Full Name"))
                            .font(DS.Font.plex(12.5, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                        // آخر الاسم = العائلة المختارة — يتحدّث فوراً عند تغيير العائلة
                        // الاسم الكامل كله يظهر بلا قصّ (طلب المالك)
                        Text(FamilyNameCatalog.words(fullName, family: familyName).joined(separator: " "))
                            .font(DS.Font.plex(14.5))
                            .foregroundColor(DS.Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let pending = pendingNameRequest {
                            Text(L10n.t("طلب «\(pending)» يُرسل عند الحفظ", "«\(pending)» will be sent on save"))
                                .font(DS.Font.plex(11))
                                .foregroundColor(DS.Color.warning)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // نفس زر العائلة (طلب المالك) — الاسم والعائلة يتغيّران بطلب
                    requestChip
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
                .contentShape(Rectangle())
                .cooldownGuarded(.fullName, cooldown: cooldown) { showEditLimitAlert = true }
            }
            .buttonStyle(.plain)

        }
    }

    /// العائلة ثابتة في الملف (طلب المالك): تتغيّر فقط بطلب يعتمده المالك/المدير/المراقب.
    private var familyPickerRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("person.2.fill", color: DS.Color.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("العائلة", "Family"))
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(familyName.isEmpty ? L10n.t("لم تُحدَّد", "Not set") : familyName)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(familyName.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                    .lineLimit(1)
                if let pending = pendingFamilyRequest {
                    // سطر واحد (طلب المالك)
                    Text(L10n.t("طلب «\(pending)» بانتظار موافقة الإدارة", "«\(pending)» awaiting approval"))
                        .font(DS.Font.plex(11))
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // قائمة العوائل في مربّع بمنتصف الشاشة (طلب المالك)
            Button { openFamilyPicker() } label: { requestChip }
                .buttonStyle(DSScaleButtonStyle())
            .disabled(pendingFamilyRequest != nil)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    /// زر التعديل الموحّد — أيقونة فقط بلا كلمة (طلب المالك)
    private var requestChip: some View {
        Image(systemName: "pencil")
            .font(DS.Font.scaled(13, weight: .bold))
            .foregroundColor(DS.Color.primary)
            .frame(width: 32, height: 32)
            .background(Circle().fill(DS.Color.primary.opacity(0.10)))
            .accessibilityLabel(L10n.t("تعديل", "Edit"))
    }

    private func openNamePopup() {
        var id: UUID?
        let close: () -> Void = { if let i = id { DSPopupPresenter.shared.hide(i) } }
        id = DSPopupPresenter.shared.show(
            NameRequestCard(current: fullName, onCancel: close) { newName in
                close()
                pendingNameRequest = newName   // يُرسل عند الحفظ
            }
        )
    }

    private func openPhonePopup() {
        var id: UUID?
        let close: () -> Void = { if let i = id { DSPopupPresenter.shared.hide(i) } }
        id = DSPopupPresenter.shared.show(
            PhoneRequestCard(
                member: member,
                // التحقق يتم الآن، والحفظ/الطلب عند الضغط على «حفظ»
                onVerified: { e164, country, digits, display in
                    close()
                    pendingPhoneForAdmins = nil
                    pendingPhoneVerified = (e164, country, digits, display)
                },
                onNeedsAdmins: { storage, display in
                    close()
                    pendingPhoneVerified = nil
                    pendingPhoneForAdmins = (storage, display)
                },
                onCancel: close
            )
        )
    }

    private func openFamilyPicker() {
        let options = familyNamesVM.activeNames.filter { $0 != familyName }
        let close: () -> Void = {
            if let id = familyPopupID { DSPopupPresenter.shared.hide(id); familyPopupID = nil }
        }
        familyPopupID = DSPopupPresenter.shared.show(
            FamilyRequestCard(options: options, current: familyName, onCancel: close) { chosen in
                close()
                pendingFamilyRequest = chosen   // يُرسل عند الحفظ
            }
        )
    }

    private func openBioPopup() {
        let close: () -> Void = {
            if let id = bioPopupID { DSPopupPresenter.shared.hide(id); bioPopupID = nil }
        }
        bioPopupID = DSPopupPresenter.shared.show(
            BioEditCard(
                initial: bioStations,
                goesToAdmins: !cooldown.canEdit(.bio),
                remaining: cooldown.remainingEdits(.bio),
                onCancel: close,
                onDone: { updated in
                    close()
                    bioStations = updated   // يُحفظ عند الضغط على «حفظ»
                }
            )
        )
    }

    private func modernReadOnlyField(label: String, value: String, icon: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: DS.Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(value)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer()

            Image(systemName: "lock.fill")
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func modernTextField(label: String, text: Binding<String>, icon: String, placeholder: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: DS.Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                TextField(placeholder, text: text)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var emailField: some View {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvalid = !trimmed.isEmpty && !isValidEmail(trimmed)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSLabeledFieldRow(icon: "envelope.fill", iconColor: DS.Color.info,
                              label: L10n.t("البريد الإلكتروني", "Email")) {
                TextField("name@example.com", text: $email)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.textPrimary)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($isEmailFocused)
                    .environment(\.layoutDirection, .leftToRight)
            }

            if isInvalid {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Font.plex(11))
                    Text(L10n.t("صيغة البريد الإلكتروني غير صحيحة", "Invalid email format"))
                        .font(DS.Font.plex(11))
                }
                .foregroundColor(DS.Color.error)
                .padding(.horizontal, DS.Spacing.xl + DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
            } else if !trimmed.isEmpty {
                Text(L10n.t("يُستخدم لإشعارات الإدارة فقط — لا يظهر للآخرين", "Used for admin notifications only — not visible to others"))
                    .font(DS.Font.plex(11))
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.xl + DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xs)
            }
        }
    }

    private func isValidEmail(_ s: String) -> Bool {
        // فحص بسيط: name@host.tld
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    /// الرقم ثابت في الملف (طلب المالك): يتغيّر بطلب بعد إثبات الرقم الجديد برمز تحقق
    private var modernPhoneField: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("phone.fill", color: DS.Color.success)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("رقم الهاتف", "Phone Number"))
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(appliedPhoneDisplay ?? KuwaitPhone.display(member.phoneNumber))
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.textPrimary)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                if let pending = pendingPhoneRequest {
                    Text(L10n.t("طلب «\(pending)» بانتظار موافقة الإدارة", "«\(pending)» awaiting approval"))
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let pending = pendingPhoneForAdmins {
                    Text(L10n.t("طلب «\(pending.display)» يُرسل للإدارة عند الحفظ",
                                "«\(pending.display)» will be sent to the admins on save"))
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let verified = pendingPhoneVerified {
                    Text(L10n.t("الرقم «\(verified.display)» يُطبَّق عند الحفظ",
                                "«\(verified.display)» applies on save"))
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openPhonePopup() } label: { requestChip }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(pendingPhoneRequest != nil)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    /// تاريخ الميلاد — صف للقراءة يفتح مربّعاً بمنتصف الشاشة (طلب المالك)
    private var birthDateRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("calendar", color: DS.Color.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(birthDateProvided ? birthDateText(birthDate) : L10n.t("لم يُحدَّد", "Not set"))
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(birthDateProvided ? DS.Color.textPrimary : DS.Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openBirthDatePopup() } label: { requestChip }
                .buttonStyle(DSScaleButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func birthDateText(_ date: Date) -> String { DSDateText.display(date) }

    private func openBirthDatePopup() {
        dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                            initial: birthDateProvided ? birthDate : nil,
                            allowClear: false) { picked in
            guard let picked else { return }
            birthDate = picked
            birthDateProvided = true   // يُحفظ عند الضغط على «حفظ»
        }
    }

    private var bioStationsSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("السيرة الذاتية", "Biography"),
                icon: "text.quote",
                trailing: bioStations.isEmpty ? nil : "\(bioStations.count) \(L10n.t("حدث", "entries"))",
                iconColor: DS.Color.accent
            )

            VStack(spacing: DS.Spacing.sm) {
                if bioStations.isEmpty {
                    // Empty state
                    Button { openBioPopup() } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(DS.Font.scaled(18))
                                .foregroundColor(DS.Color.primary)
                            Text(L10n.t("أضف حدثاً لسيرتك", "Add to your biography"))
                                .font(DS.Font.plex(14.5))
                                .foregroundColor(DS.Color.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.lg)
                    }
                    .buttonStyle(.plain)
                } else {
                    // معاينة المحطات
                    VStack(spacing: 0) {
                        ForEach(Array(bioStations.prefix(3).enumerated()), id: \.element.id) { index, station in
                            if index > 0 { DSDivider() }
                            stationPreviewRow(station)
                        }
                        if bioStations.count > 3 {
                            DSDivider()
                            Text(L10n.t("و \(bioStations.count - 3) أحداث أخرى...", "and \(bioStations.count - 3) more..."))
                                .font(DS.Font.plex(12))
                                .foregroundColor(DS.Color.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.sm)
                        }
                    }

                    // أزرار التعديل والحذف
                    HStack(spacing: DS.Spacing.sm) {
                        Button { openBioPopup() } label: {
                            Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                                .font(DS.Font.plex(14.5, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(DS.Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button { showDeleteBioAlert = true } label: {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                .font(DS.Font.plex(14.5, weight: .bold))
                                .foregroundColor(DS.Color.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(DS.Color.error.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }
            }
            .padding(.bottom, DS.Spacing.md)

        }
        .padding(.horizontal, DS.Spacing.lg)
        .dsAlert(
            L10n.t("حذف السيرة", "Delete Biography"),
            isPresented: $showDeleteBioAlert
        ) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                // لا يُحفظ إلا عند «حفظ» — «إلغاء» يرجّع السيرة كما كانت
                bioStations = []
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t("ستُحذف السيرة الذاتية كاملة عند الحفظ.",
                        "The whole biography will be deleted when you save."))
        }
    }

    private func stationPreviewRow(_ station: FamilyMember.BioStation) -> some View {
        HStack(spacing: DS.Spacing.md) {
            if let year = station.year, !year.isEmpty {
                Text(year)
                    .font(DS.Font.plex(11))
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(DS.Color.primary)
                    .clipShape(Capsule())
                    .fixedSize()
            } else {
                Circle()
                    .fill(DS.Color.primary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !station.title.isEmpty {
                    Text(station.title)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                if !station.details.isEmpty {
                    Text(station.details)
                        .font(DS.Font.plex(12.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    /// نفس شروط الحفظ السابقة: اسم غير فارغ، هاتف وبريد صالحان، واتصال
    private var isSaveDisabled: Bool {
        let newStoredPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
        let isPhoneValid = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newStoredPhone != nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmailValid = trimmedEmail.isEmpty || isValidEmail(trimmedEmail)
        return fullName.isEmpty || memberVM.isLoading || !isPhoneValid || !isEmailValid || !network.isConnected
    }

    @ViewBuilder
    private var offlineNotice: some View {
        if !network.isConnected {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "wifi.slash")
                    .font(DS.Font.plex(11))
                Text(L10n.t("لا يمكن الحفظ بدون اتصال", "Can't save while offline"))
                    .font(DS.Font.plex(12))
            }
            .foregroundColor(DS.Color.error)
            .padding(.horizontal, DS.Spacing.lg)
        }
    }


    // MARK: - Logic (الوظائف)

    /// تغيير حالة الزواج + حفظ فوري في القاعدة (لا يعتمد على زر الحفظ العام).
    /// الحالة الاجتماعية: الضغط يغيّر الزر فقط — تُحفظ عند «حفظ» ويُحسب الحد
    /// عندها (طلب المالك)، مثل بقية الحقول
    private func setMarried(_ value: Bool) {
        guard value != isMarried else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.quick) { isMarried = value }
    }


    private func setupData() {
        self.fullName = member.fullName
        self.familyName = member.familyName ?? ""
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        self.selectedPhoneCountry = detectedPhone.country
        self.phoneNumber = detectedPhone.localDigits
        self.isMarried = member.isMarried ?? false
        self.isDeceased = member.isDeceased ?? false
        // تحميل المحطات الحياتية
        self.bioStations = member.bio ?? []
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let b = member.birthDate, let date = f.date(from: b) {
            self.birthDate = date
            self.birthDateProvided = true
        } else {
            self.birthDateProvided = false
        }
        if let d = member.deathDate, let date = f.date(from: d) { self.deathDate = date }
        self.isPhoneHidden = member.isPhoneHidden ?? false
        self.email = member.email ?? ""
    }

    // MARK: - Save Changes (broken into helpers)

    private func saveChangesAction() {
        Task {
            let normalizedPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? ""
            guard phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !normalizedPhone.isEmpty else { return }

            let changes = detectChangedFields(normalizedPhone: normalizedPhone)
            await applyPendingChanges()          // الصورة والاسم والعائلة والرقم — عند الحفظ فقط
            await submitAdminRequests(changes: changes, normalizedPhone: normalizedPhone)
            await saveBioIfChanged(changes: changes)
            await saveEmailIfChanged()

            let success = await submitMemberData(changes: changes)
            if success {
                recordCooldowns(changes: changes)
                // تجاوز حد التعديلات: مربّع رسالة في منتصف الشاشة ثم إغلاق
                if changes.anyNeedsApproval {
                    dismissAfterLimitAlert = true
                    showEditLimitAlert = true
                    return
                }
                // الرقم/الوفاة يُرسلان كطلب موافقة (لا يُحفظان فوراً مثل بقية الحقول) —
                // أظهر تأكيد «قيد المراجعة» بدل الإغلاق الصامت، ثم أغلق عند الضغط على حسناً.
                if changes.phoneChanged || changes.deceasedChanged {
                    showRequestSentAlert = true
                } else {
                    dismiss()
                }
            } else {
                showSaveError = true
            }
        }
    }

    /// ما يُجمَع في الشاشة يُنفَّذ هنا فقط (طلب المالك): حذف/رفع الصورة، وطلبات
    /// الاسم والعائلة، وتغيير الرقم بعد إثباته برمز تحقق.
    @MainActor private func applyPendingChanges() async {
        // 1) الصورة
        if pendingAvatarDelete {
            await memberVM.deleteAvatar(for: member.id)
            pendingAvatarDelete = false
        }
        if let newImage = localPreviewImage {
            if cooldown.canEdit(.avatar) {
                let uploaded = await memberVM.uploadAvatar(image: newImage, for: member.id)
                if uploaded {
                    cooldown.recordEdit(.avatar)
                } else {
                    localPreviewImage = nil
                    showSaveError = true
                }
            } else {
                // تجاوز حد الـ٣ تعديلات: تُرفع كاقتراح وتُرسل للإدارة
                localPreviewImage = nil
                if let url = await adminRequestVM.uploadPhotoSuggestion(newImage) {
                    let ok = await adminRequestVM.submitTreeEditRequest(payload: .make(
                        action: .addPhoto,
                        targetMemberId: member.id.uuidString,
                        targetMemberName: member.fullName,
                        newPhotoUrl: url,
                        notes: L10n.t("تعديل صورة بعد تجاوز حد التعديلات", "Photo edit after reaching the edit limit")
                    ))
                    if !ok { showSaveError = true }
                } else {
                    showSaveError = true
                }
            }
        }

        // 2) الاسم — طلب دائماً
        if let newName = pendingNameRequest {
            await adminRequestVM.requestNameChange(memberId: member.id, newName: newName)
            pendingNameRequest = nil
        }

        // 3) العائلة — طلب دائماً
        if let newFamily = pendingFamilyRequest {
            if await adminRequestVM.requestFamilyChange(memberId: member.id, newFamily: newFamily) {
                // تبقى معروضة كـ«بانتظار الموافقة»
            }
        }

        // 4) الرقم — أول ٣ مرات يُحفظ مباشرة بعد رمز التحقق، وبعدها طلب للإدارة
        if let verified = pendingPhoneVerified {
            if cooldown.canEdit(.phoneNumber) {
                await memberVM.updateMemberPhone(memberId: member.id,
                                                 country: verified.country,
                                                 localPhone: verified.digits)
                cooldown.recordEdit(.phoneNumber)
                appliedPhoneDisplay = verified.display
            } else {
                await adminRequestVM.requestPhoneNumberChange(memberId: member.id,
                                                              newPhoneNumber: verified.e164)
                pendingPhoneRequest = verified.display
            }
            pendingPhoneVerified = nil
        }

        // 5) رقم عليه حساب آخر — لا يُحفظ ذاتياً، يُرسل للإدارة دائماً
        if let pending = pendingPhoneForAdmins {
            await adminRequestVM.requestPhoneNumberChange(memberId: member.id,
                                                          newPhoneNumber: pending.storage)
            pendingPhoneRequest = pending.display
            pendingPhoneForAdmins = nil
        }
    }

    private func saveEmailIfChanged() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let oldEmail = (member.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized != oldEmail else { return }
        // فحص الصيغة قبل الإرسال — فاضي مسموح (للحذف)
        guard normalized.isEmpty || isValidEmail(normalized) else { return }
        await memberVM.updateMemberEmail(memberId: member.id, email: normalized.isEmpty ? nil : normalized)
        member.email = normalized.isEmpty ? nil : normalized
    }

    /// Holds which fields changed so cooldowns can be recorded after a successful save
    private struct ChangedFields {
        let birthChanged: Bool
        /// تاريخ الميلاد تغيّر بعد تجاوز حد الـ٣ تعديلات → يُرسل للإدارة بدل الحفظ
        let birthNeedsApproval: Bool
        let marriedChanged: Bool
        /// الحالة الاجتماعية تغيّرت بعد تجاوز حد الـ٣ → تُرسل للإدارة عند الحفظ
        let marriedNeedsApproval: Bool
        let phoneHiddenChanged: Bool
        let phoneHiddenNeedsApproval: Bool
        let phoneChanged: Bool
        let bioChanged: Bool
        let bioNeedsApproval: Bool
        let deceasedChanged: Bool

        /// أي حقل تجاوز حد الـ٣ وأُرسل للإدارة
        var anyNeedsApproval: Bool {
            birthNeedsApproval || phoneHiddenNeedsApproval || bioNeedsApproval || marriedNeedsApproval
        }
    }

    /// «تعديلات غير محفوظة» يشمل فقط الحقول التي تُحفظ عبر زر «حفظ التغييرات» أو
    /// تُرسل كطلب موافقة عند الإغلاق. يُستثنى منها ما يُحفظ فوراً (الصورة + الحالة
    /// الاجتماعية) حتى لا يظهر تنبيه «تجاهل التعديلات؟» لتغييرات ثبتت أصلاً.
    private var hasUnsavedChanges: Bool {
        if pendingPhoneVerified != nil || pendingPhoneForAdmins != nil
            || pendingNameRequest != nil || pendingFamilyRequest != nil
            || pendingAvatarDelete { return true }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if isMarried != (member.isMarried ?? false) { return true }
        if isPhoneHidden != (member.isPhoneHidden ?? false) { return true }
        if isDeceased && !(member.isDeceased ?? false) { return true }
        let oldBirthStr = member.birthDate ?? ""
        if birthDateProvided && f.string(from: birthDate) != oldBirthStr { return true }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let oldEmail = (member.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedEmail != oldEmail { return true }
        let oldBioKey = (member.bio ?? []).map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
        let newBioKey = bioStations.map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
        if oldBioKey != newBioKey { return true }
        // phone quick check
        let rawLocal = phoneNumber.filter(\.isNumber)
        let originalLocal = KuwaitPhone.detectCountryAndLocal(member.phoneNumber).localDigits.filter(\.isNumber)
        if rawLocal != originalLocal && !rawLocal.isEmpty { return true }
        return false
    }

    private func detectChangedFields(normalizedPhone: String) -> ChangedFields {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let oldStoredPhone = KuwaitPhone.normalizeForStorageFromInput(member.phoneNumber) ?? ""
        let oldBirthStr = member.birthDate ?? ""
        let newBirthStr = f.string(from: birthDate)

        // مقارنة المحطات بمحتواها
        let oldBioKey = (member.bio ?? []).map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
        let newBioKey = bioStations.map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")

        let birthDiffers = birthDateProvided && newBirthStr != oldBirthStr
        let phoneHiddenDiffers = isPhoneHidden != (member.isPhoneHidden ?? false)
        let bioDiffers = oldBioKey != newBioKey
        let marriedDiffers = isMarried != (member.isMarried ?? false)
        return ChangedFields(
            birthChanged: birthDiffers && cooldown.canEdit(.birthDate),
            birthNeedsApproval: birthDiffers && !cooldown.canEdit(.birthDate),
            marriedChanged: marriedDiffers && cooldown.canEdit(.isMarried),
            marriedNeedsApproval: marriedDiffers && !cooldown.canEdit(.isMarried),
            // الرقم يُرسل للإدارة دائماً؛ إخفاء الرقم والنبذة: ٣ تعديلات ثم موافقة الإدارة
            phoneHiddenChanged: phoneHiddenDiffers && cooldown.canEdit(.isPhoneHidden),
            phoneHiddenNeedsApproval: phoneHiddenDiffers && !cooldown.canEdit(.isPhoneHidden),
            // الرقم لا يُعدّل من النموذج — يتغيّر بطلب مستقل مع رمز تحقق
            phoneChanged: false,
            bioChanged: bioDiffers && cooldown.canEdit(.bio),
            bioNeedsApproval: bioDiffers && !cooldown.canEdit(.bio),
            deceasedChanged: isDeceased && !(member.isDeceased ?? false)
        )
    }

    private func submitAdminRequests(changes: ChangedFields, normalizedPhone: String) async {
        if changes.marriedNeedsApproval {
            _ = await adminRequestVM.submitTreeEditRequest(payload: .make(
                action: .other,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: isMarried ? "true" : "false",
                reason: "profile_marital",
                notes: L10n.t("طلب تغيير الحالة الاجتماعية إلى: \(isMarried ? "متزوج" : "غير متزوج")",
                              "Marital status change to: \(isMarried ? "Married" : "Single")")
            ))
        }
        if changes.bioNeedsApproval {
            let stations = bioStations.filter { !$0.title.isEmpty || !$0.details.isEmpty }
            let json = (try? String(data: JSONEncoder().encode(stations), encoding: .utf8)) ?? "[]"
            let lines = stations.map { "• \($0.year.map { "\($0) — " } ?? "")\($0.title)" }.joined(separator: "\n")
            _ = await adminRequestVM.submitTreeEditRequest(payload: .make(
                action: .other,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: json,
                reason: "profile_bio",
                notes: L10n.t("طلب تعديل النبذة:\n", "Bio edit request:\n") + (lines.isEmpty ? L10n.t("(حذف النبذة)", "(clear bio)") : lines)
            ))
        }
        if changes.phoneHiddenNeedsApproval {
            _ = await adminRequestVM.submitTreeEditRequest(payload: .make(
                action: .other,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: isPhoneHidden ? "true" : "false",
                reason: "profile_phone_hidden",
                notes: isPhoneHidden ? L10n.t("طلب إخفاء رقم الهاتف", "Request to hide phone number")
                                     : L10n.t("طلب إظهار رقم الهاتف", "Request to show phone number")
            ))
        }
        if changes.birthNeedsApproval {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            _ = await adminRequestVM.submitTreeEditRequest(payload: .make(
                action: .editBirth,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newBirthDate: f.string(from: birthDate),
                notes: L10n.t("تعديل بعد تجاوز حد التعديلات", "Edit after reaching the edit limit")
            ))
        }
        if changes.deceasedChanged {
            await adminRequestVM.requestDeceasedStatus(memberId: member.id, deathDate: deathDate)
        }
        if changes.phoneChanged {
            await adminRequestVM.requestPhoneNumberChange(memberId: member.id, newPhoneNumber: normalizedPhone)
        }
    }

    private func saveBioIfChanged(changes: ChangedFields) async {
        guard changes.bioChanged else { return }
        let stationsToSave = bioStations.filter { !$0.title.isEmpty || !$0.details.isEmpty }
        await memberVM.updateMemberBio(memberId: member.id, bio: stationsToSave)
        member.bio = stationsToSave.isEmpty ? nil : stationsToSave
    }

    private func submitMemberData(changes: ChangedFields) async -> Bool {
        await memberVM.updateMemberData(
            memberId: member.id,
            fullName: fullName,
            phoneNumber: member.phoneNumber ?? "",
            // تجاوز الحد → لا يُكتب التاريخ الآن (أُرسل للإدارة)
            birthDate: birthDateProvided && !changes.birthNeedsApproval ? birthDate : nil,
            // تجاوز الحد → تبقى القيمة القديمة حتى موافقة الإدارة
            isMarried: changes.marriedNeedsApproval ? (member.isMarried ?? false) : isMarried,
            isDeceased: member.isDeceased ?? false,
            deathDate: member.isDeceased ?? false ? deathDate : nil,
            // تجاوز الحد → تبقى القيمة القديمة حتى موافقة الإدارة
            isPhoneHidden: changes.phoneHiddenNeedsApproval ? (member.isPhoneHidden ?? false) : isPhoneHidden
        )
    }

    private func recordCooldowns(changes: ChangedFields) {
        // الاسم والرقم طلبات دائماً — العدّاد لبقية الحقول
        if changes.birthChanged { cooldown.recordEdit(.birthDate) }
        if changes.phoneHiddenChanged { cooldown.recordEdit(.isPhoneHidden) }
        if changes.bioChanged { cooldown.recordEdit(.bio) }
        if changes.marriedChanged { cooldown.recordEdit(.isMarried) }
    }

}


/// مربّع «طلب تغيير العائلة» بمنتصف الشاشة (طلب المالك): العوائل المعتمدة، اختيار
/// واحدة، ثم «إرسال» — الطلب يعتمده المالك/المدير/المراقب.
private struct FamilyRequestCard: View {
    let options: [String]
    let current: String
    let onCancel: () -> Void
    let onSend: (String) -> Void
    @State private var selected: String?

    var body: some View {
        DSCenterCard(onBackgroundTap: onCancel) {
            VStack(spacing: 4) {
                Text(L10n.t("طلب تغيير العائلة", "Request family change"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(current.isEmpty
                     ? L10n.t("اختر عائلتك — يتغيّر بعد موافقة الإدارة", "Pick your family — applied after approval")
                     : L10n.t("الحالية: \(current) — يتغيّر بعد موافقة الإدارة", "Current: \(current) — applied after approval"))
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(options, id: \.self) { name in
                        Button { selected = name } label: {
                            HStack {
                                Text(name)
                                    .font(DS.Font.plex(14, weight: .semibold))
                                    .foregroundColor(DS.Color.textPrimary)
                                Spacer()
                                Image(systemName: selected == name ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected == name ? DS.Color.primary : DS.Color.textTertiary)
                            }
                            .padding(.horizontal, DS.Spacing.md)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .fill(selected == name ? DS.Color.primary.opacity(0.10) : DS.Color.mutedBackground.opacity(0.6))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack(spacing: DS.Spacing.sm) {
                Button { if let s = selected { onSend(s) } } label: {
                    Text(L10n.t("إرسال", "Send"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DSActionFill.style(enabled: selected != nil), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .disabled(selected == nil)
                Button(action: onCancel) {
                    Text(L10n.t("إلغاء", "Cancel"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.mutedBackground.opacity(0.8)))
                }
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }
}


/// طلب تغيير رقم الهاتف (طلب المالك): الرقم ثابت في الملف — يُدخل الرقم الجديد،
/// يُثبته برمز تحقق يصله عليه، ثم يذهب الطلب للإدارة للموافقة.

/// مربّع «طلب تغيير الاسم» بمنتصف الشاشة (طلب المالك) — نفس شكل مربّع العائلة
private struct NameRequestCard: View {
    let current: String
    let onCancel: () -> Void
    let onSend: (String) -> Void
    @State private var name: String = ""
    @State private var sending = false

    var body: some View {
        DSCenterCard(onBackgroundTap: onCancel) {
            VStack(spacing: 4) {
                Text(L10n.t("طلب تغيير الاسم", "Request name change"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("يُرسل للإدارة، ويتغيّر بعد موافقتها.",
                            "Sent to the admins; applied after approval."))
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            TextField(L10n.t("اسمك الرباعي", "Your full name"), text: $name, axis: .vertical)
                .font(DS.Font.plex(15))
                .lineLimit(1...3)
                .padding(DS.Spacing.md)
                .background(DS.Color.mutedBackground.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            HStack(spacing: DS.Spacing.sm) {
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != current, !sending else { return }
                    sending = true
                    onSend(trimmed)
                } label: {
                    Text(L10n.t("إرسال", "Send"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DSActionFill.style(enabled: canSend), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .disabled(!canSend)
                Button(action: onCancel) {
                    Text(L10n.t("إلغاء", "Cancel"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.mutedBackground.opacity(0.8)))
                }
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .onAppear { if name.isEmpty { name = current } }
    }

    private var canSend: Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != current && !sending
    }
}

/// مربّع «طلب تغيير الرقم» بمنتصف الشاشة (طلب المالك): الرقم الجديد ثم رمز التحقق.
/// أول ٣ تغييرات تُحفظ مباشرة بعد الرمز، وبعدها يُرسل الطلب للإدارة.
private struct PhoneRequestCard: View {
    let member: FamilyMember
    /// التحقق فقط — الحفظ أو الطلب يتم عند الضغط على «حفظ» في الشاشة
    let onVerified: (String, KuwaitPhone.Country, String, String) -> Void
    /// الرقم عليه حساب آخر — يُرسل للإدارة بلا رمز (عند «حفظ»)
    let onNeedsAdmins: (String, String) -> Void
    let onCancel: () -> Void

    private let cooldown = ProfileEditCooldown.shared

    @State private var country: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var digits: String = ""
    @State private var code: String = ""
    @State private var codeSent = false
    /// مؤقّت صلاحية الرمز / إعادة الإرسال (ثوانٍ)
    @State private var secondsLeft = 0
    /// الرقم مرتبط بحساب آخر في المصادقة — لا يمكن التحقق ذاتياً، يُرسل للإدارة
    @State private var needsAdmins = false
    @State private var isBusy = false
    @State private var error: String?
    @State private var info: String?

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }
    /// صيغة التخزين في قاعدة البيانات (الكويت: ٨ أرقام، ويكمّلها مُطبِّع السيرفر)
    private var storagePhone: String? { KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: digits) }
    /// الصيغة الدولية الكاملة للمصادقة (لازم رمز الدولة وإلا رفضها مزوّد الرسائل)
    private var authPhone: String? {
        let local = KuwaitPhone.normalizeDigits(digits).filter(\.isNumber)
        guard local.count >= 6 else { return nil }
        return "\(country.dialingCode)\(local)"
    }
    private var goesToAdmins: Bool { !cooldown.canEdit(.phoneNumber) }

    var body: some View {
        DSCenterCard(onBackgroundTap: isBusy ? nil : onCancel) {
            if codeSent {
                otpPage
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                numberPage
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(DS.Anim.snappy, value: codeSent)
        .task(id: secondsLeft) {
            guard secondsLeft > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { secondsLeft -= 1 }
        }
    }

    // MARK: الصفحة ١ — الرقم الجديد
    private var numberPage: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("تغيير رقم الهاتف", "Change phone number"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(t("الحالي: \(KuwaitPhone.display(member.phoneNumber))",
                       "Current: \(KuwaitPhone.display(member.phoneNumber))"))
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
            }

            DSPhoneField(country: $country, digits: $digits,
                         placeholder: "9xxxxxxx", compact: true, bordered: true)
                .onChange(of: digits) { _ in
                    if needsAdmins { needsAdmins = false; error = nil }
                }

            messages

            buttons(primary: needsAdmins ? t("إرسال للإدارة", "Send to admins") : t("إرسال الرمز", "Send code"),
                    enabled: canProceed,
                    secondary: t("إلغاء", "Cancel"),
                    secondaryAction: onCancel) {
                if needsAdmins {
                    if let phone = storagePhone, let authNumber = authPhone {
                        onNeedsAdmins(phone, KuwaitPhone.display(authNumber))
                    }
                } else {
                    Task { await sendCode() }
                }
            }
        }
    }

    // MARK: الصفحة ٢ — إدخال رمز التحقق
    private var otpPage: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(DS.Font.plex(24, weight: .bold))
                .foregroundColor(DS.Color.primary)
                .frame(width: 56, height: 56)
                .background(DS.Color.primary.opacity(0.12), in: Circle())

            VStack(spacing: 4) {
                Text(t("رمز التحقق", "Verification Code"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(t("أرسلنا رمزاً من ٦ أرقام إلى", "We sent a 6-digit code to"))
                    .font(DS.Font.plex(12.5, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                Text(KuwaitPhone.display(authPhone))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .multilineTextAlignment(.center)

            DSOTPField(code: $code) { _ in
                Task { await confirm() }
            }
            .disabled(isBusy)

            // المؤقّت / إعادة الإرسال
            if secondsLeft > 0 {
                Text(t("إعادة الإرسال بعد \(secondsLeft / 60):\(String(format: "%02d", secondsLeft % 60))",
                       "Resend in \(secondsLeft / 60):\(String(format: "%02d", secondsLeft % 60))"))
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
            } else {
                Button {
                    code = ""
                    Task { await sendCode() }
                } label: {
                    Text(t("إعادة إرسال الرمز", "Resend code"))
                        .font(DS.Font.plex(12.5, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
                .disabled(isBusy)
            }

            messages

            buttons(primary: t("تأكيد", "Confirm"),
                    enabled: !isBusy && code.count == 6,
                    secondary: t("تغيير الرقم", "Change number"),
                    secondaryAction: {
                        code = ""; error = nil; info = nil
                        codeSent = false
                    }) {
                Task { await confirm() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var messages: some View {
        if let info {
            Label(info, systemImage: "checkmark.circle.fill")
                .font(DS.Font.plex(11.5, weight: .medium))
                .foregroundColor(DS.Color.success)
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(DS.Font.plex(11.5, weight: .medium))
                .foregroundColor(DS.Color.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// الزرّان: الإجراء في جهة و«إلغاء/رجوع» يسار (قاعدة التطبيق)
    private func buttons(primary: String, enabled: Bool,
                         secondary: String, secondaryAction: @escaping () -> Void,
                         action: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: action) {
                Group {
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text(primary).font(DS.Font.plex(14, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(DSActionFill.style(enabled: enabled), in: RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .disabled(!enabled)

            Button(action: secondaryAction) {
                Text(secondary)
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.mutedBackground.opacity(0.8)))
            }
            .disabled(isBusy)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private var canProceed: Bool {
        if needsAdmins { return !isBusy }
        return !isBusy && (codeSent ? code.count == 6 : digits.count >= 6)
    }

    /// يرسل رمزاً للرقم الجديد (تغيير رقم الحساب في المصادقة — الجلسة تبقى كما هي)
    @MainActor private func sendCode() async {
        guard let phone = storagePhone, let authNumber = authPhone else {
            error = t("رقم غير صالح.", "Invalid number."); return
        }
        if KuwaitPhone.e164(phone) == KuwaitPhone.e164(member.phoneNumber)
            || phone == (member.phoneNumber ?? "") {
            error = t("هذا رقمك الحالي.", "That's your current number."); return
        }
        isBusy = true; error = nil; info = nil
        defer { isBusy = false }
        do {
            struct Row: Decodable { let id: UUID }
            let rows: [Row] = try await SupabaseConfig.client
                .rpc("find_profiles_by_phone", params: ["p_phone": phone])
                .execute().value
            if rows.contains(where: { $0.id != member.id }) {
                error = t("هذا الرقم مسجّل لعضو آخر.", "This number belongs to another member.")
                return
            }
            try await SupabaseConfig.client.auth.update(user: UserAttributes(phone: authNumber))
            code = ""
            info = nil
            secondsLeft = 60
            codeSent = true   // يتحوّل المربّع لصفحة «رمز التحقق»
        } catch {
            Log.error("[PhoneChange] إرسال الرمز: \(error.localizedDescription)")
            let reason = error.localizedDescription.lowercased()
            if reason.contains("already been registered") || reason.contains("already registered")
                || reason.contains("phone_exists") {
                // الرقم على حساب دخول آخر: السيرفر يحرّره إن كان حساباً يتيماً (بلا عضو)،
                // ثم نطلب الرمز من جديد — الرقم لا ينتقل إلا بعد التحقق (طلب المالك)
                await releaseAndRetry(authNumber: authNumber)
            } else if reason.contains("security purposes") || reason.contains("rate limit")
                        || reason.contains("too many") {
                self.error = t("محاولات كثيرة — انتظر دقيقة ثم أعد المحاولة.",
                               "Too many attempts — wait a minute and try again.")
            } else {
                self.error = t("تعذّر إرسال الرمز: ", "Couldn't send the code: ")
                    + error.localizedDescription
            }
        }
    }

    /// يحرّر الرقم من حساب دخول يتيم ثم يعيد طلب الرمز. حساب عضو حقيقي → للإدارة.
    @MainActor private func releaseAndRetry(authNumber: String) async {
        do {
            let result: String = try await SupabaseConfig.client
                .rpc("release_orphan_auth_phone", params: ["p_phone": authNumber])
                .execute().value
            switch result {
            case "released", "free":
                try await SupabaseConfig.client.auth.update(user: UserAttributes(phone: authNumber))
                code = ""
                info = nil
                error = nil
                secondsLeft = 60
                codeSent = true
            case "linked":
                needsAdmins = true
                error = t("هذا الرقم لعضو آخر في التطبيق. أرسل الطلب للإدارة لتتحقق منه.",
                          "This number belongs to another member. Send the request to the admins.")
            default:
                error = t("رقم غير صالح.", "Invalid number.")
            }
        } catch {
            Log.error("[PhoneChange] تحرير الرقم: \(error.localizedDescription)")
            needsAdmins = true
            self.error = t("تعذّر تحرير الرقم. أرسل الطلب للإدارة.",
                           "Couldn't free the number. Send the request to the admins.")
        }
    }

    @MainActor private func confirm() async {
        guard let phone = storagePhone, let authNumber = authPhone else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            try await SupabaseConfig.client.auth.verifyOTP(
                phone: authNumber,
                token: code.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .phoneChange
            )
            // يُخزَّن بصيغة القاعدة، ويُعرض بالصيغة الدولية الكاملة
            onVerified(phone, country, digits, KuwaitPhone.display(authNumber))
        } catch {
            Log.error("[PhoneChange] تأكيد الرمز: \(error.localizedDescription)")
            self.error = t("الرمز غير صحيح أو انتهت صلاحيته.", "The code is wrong or expired.")
            code = ""   // يفرّغ المربّعات لإعادة الكتابة
        }
    }
}

/// مربّع «السيرة الذاتية» بمنتصف الشاشة (طلب المالك) — نفس شكل بقية المربّعات.
/// التعديل هنا محلي فقط: لا شيء يُحفظ إلا بالضغط على «حفظ» في شاشة التعديل.
/// مشترك: تعديل البيانات + التعديل المباشر (طلب المالك)
struct BioEditCard: View {
    let initial: [FamilyMember.BioStation]
    let goesToAdmins: Bool
    let remaining: Int
    let onCancel: () -> Void
    let onDone: ([FamilyMember.BioStation]) -> Void

    @State private var stations: [FamilyMember.BioStation] = []

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        DSCenterCard(onBackgroundTap: onCancel) {
            Text(t("السيرة الذاتية", "Biography"))
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            if stations.isEmpty {
                Text(t("لا توجد أحداث بعد.", "No entries yet."))
                    .font(DS.Font.plex(12.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.Spacing.md)
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach($stations) { $station in
                            stationCard($station)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Button {
                withAnimation(DS.Anim.snappy) {
                    stations.append(FamilyMember.BioStation(title: "", details: ""))
                }
            } label: {
                Label(t("إضافة حدث", "Add entry"), systemImage: "plus.circle.fill")
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.primary.opacity(0.10)))
            }
            .buttonStyle(DSScaleButtonStyle())

            HStack(spacing: DS.Spacing.sm) {
                Button {
                    onDone(stations.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
                                          || !$0.details.trimmingCharacters(in: .whitespaces).isEmpty })
                } label: {
                    Text(t("حفظ", "Save"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DSActionFill.style(), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                Button(action: onCancel) {
                    Text(t("إلغاء", "Cancel"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.mutedBackground.opacity(0.8)))
                }
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .onAppear { stations = initial }
    }

    /// حدث واحد: السنة والعنوان والتفاصيل مع زر حذف
    private func stationCard(_ station: Binding<FamilyMember.BioStation>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                TextField(t("السنة", "Year"), text: Binding(
                    get: { station.wrappedValue.year ?? "" },
                    set: { station.wrappedValue.year = $0.isEmpty ? nil : String($0.filter(\.isNumber).prefix(4)) }
                ))
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 58, height: 30)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.mutedBackground.opacity(0.7)))

                TextField(t("العنوان", "Title"), text: station.title)
                    .font(DS.Font.plex(13.5, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)

                Button {
                    withAnimation(DS.Anim.snappy) {
                        stations.removeAll { $0.id == station.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.error)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Color.error.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            TextField(t("التفاصيل (اختياري)", "Details (optional)"), text: station.details, axis: .vertical)
                .font(DS.Font.plex(12.5, weight: .regular))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1...3)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.mutedBackground.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

