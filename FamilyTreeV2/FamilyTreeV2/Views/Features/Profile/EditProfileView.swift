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

/// مربّع «تم تجاوز حد التعديلات» — على الهيكل الموحّد (`DSCenterCard` برأسه المضغوط + صفّ الأزرار)
private struct EditLimitPopup: View {
    let onClose: () -> Void

    var body: some View {
        DSCenterCard(onBackgroundTap: nil, title: L10n.t("تم تجاوز حد التعديلات", "Edit limit reached"),
                     icon: "exclamationmark.triangle.fill") {
            Text(L10n.t(
                "عدّلت هذه البيانات ٣ مرات، وهو الحد المسموح.\nأُرسل تعديلك للإدارة، وسيُطبَّق بعد موافقتها.",
                "You've edited this 3 times, which is the limit.\nYour edit was sent to the admins and will apply once approved."
            ))
            .font(DSBox.alertBodyFont)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            DSBoxButtons {
                Button(L10n.t("حسناً", "OK"), action: onClose)
            }
            .padding(.top, DS.Spacing.xs)
        }
    }
}

struct EditProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) var dismiss
    /// لون القسم («حسابي»، وتعديل السجل من الإدارة/الشجرة) — كحلي «الإطار» يتبعه
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

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
    @State private var showBioBox = false
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
    /// أُرسل طلب واحد على الأقل للإدارة عند الحفظ → رسالة «تم إرسال الطلب»
    @State private var requestsSent = false
    /// الطلب بسبب تجاوز حد الـ٣ تعديلات
    @State private var requestsDueToLimit = false
    /// ملخّص ما بعد الحفظ (طلب المالك): ما تغيّر فعلاً، وما أُرسل للإدارة
    @State private var savedItems: [String] = []
    @State private var sentItems: [String] = []
    /// تأكيد قبل الحفظ بما سيُرسل للإدارة (طلب المالك)
    @State private var showAdminConfirm = false
    @State private var adminConfirmMessage = ""
    @State private var isSaving = false

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

    /// «إلغاء»: يسأل قبل تجاهل التعديلات غير المحفوظة
    private func cancelTapped() {
        if hasUnsavedChanges { showDiscardAlert = true } else { dismiss() }
    }

    var body: some View {
        // مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة وحركتها (طلب المالك
        // ٢٠٢٦-٠٩-٢٦): رأس متدرّج، أقسام تدخل تباعاً، و«حفظ» / «إلغاء» أسفله.
        DSComposer(
            title: editScreenTitle,
            subtitle: L10n.t("بياناتك كما تظهر لأفراد العائلة", "Your details as the family sees them"),
            icon: "person.crop.circle.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: !isSaveDisabled,
            isBusy: memberVM.isLoading || isSaving,
            note: network.isConnected ? nil : L10n.t("لا يمكن الحفظ بدون اتصال", "Can't save while offline"),
            onSubmit: saveChangesAction,
            onCancel: cancelTapped
        ) {
            // 1. الصورة الشخصية
            VStack(spacing: DS.Spacing.xs) {
                imagePickerHeader
                    .cooldownGuarded(.avatar, cooldown: cooldown) { showEditLimitAlert = true }
                Label(
                    pendingAvatarDelete
                        ? L10n.t("ستُحذف الصورة عند الحفظ", "Photo will be removed on save")
                        : L10n.t("اضغط على الصورة لتغييرها", "Tap the photo to change it"),
                    systemImage: pendingAvatarDelete ? "trash.fill" : "camera.fill"
                )
                .dsFont(.subtitle)
                .foregroundColor(chromeInk)
            }
            .dsStaggerIn(0)

            // 2. المعلومات الشخصية — نفس أقسام وحقول مربّعات الإضافة (تصميم موحّد)
            DSComposerSection(title: L10n.t("المعلومات الشخصية", "Personal Info"),
                              icon: "person.text.rectangle", tint: DS.Color.primary, index: 1) {
                VStack(spacing: DS.Spacing.sm) {
                    nameFieldWithChangeRequest
                    familyPickerRow
                    modernPhoneField
                    birthDateRow
                    maritalRow
                }
            }

            // 3. السيرة الذاتية
            bioStationsSection
                .cooldownGuarded(.bio, cooldown: cooldown) { showEditLimitAlert = true }
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
        // مربّع طويل من الأسفل: لا يُسحب وفيه تعديلات غير محفوظة («إلغاء» يسأل أولاً)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .task { await familyNamesVM.fetch() }
            .onAppear {
                setupData()
            }
            .dsCenterBox(isPresented: $showBioBox) {
                BioEditCard(
                    initial: bioStations,
                    goesToAdmins: !cooldown.canEdit(.bio),
                    remaining: cooldown.remainingEdits(.bio),
                    onCancel: { showBioBox = false },
                    onDone: { updated in
                        showBioBox = false
                        bioStations = updated   // يُحفظ عند الضغط على «حفظ»
                    }
                )
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
                L10n.t("إرسال للإدارة", "Send to Admins"),
                isPresented: $showAdminConfirm
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("إرسال", "Send")) { performSave(confirmed: true) }
            } message: {
                Text(adminConfirmMessage)
            }
            .dsAlert(
                savedItems.isEmpty ? L10n.t("تم إرسال الطلب", "Request Sent")
                                   : L10n.t("تم حفظ التغييرات", "Changes Saved"),
                isPresented: $showRequestSentAlert,
                moment: savedItems.isEmpty ? .sentForApproval : .success
            ) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(saveSummary)
            }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// الحالة الاجتماعية — صف داخل «المعلومات الشخصية» تحت تاريخ الميلاد (طلب المالك)
    private var maritalRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "heart.fill", tint: DS.Color.primary)
                .accessibilityHidden(true)   // زخرفة
            Text(L10n.t("الحالة الاجتماعية", "Marital Status"))
                .dsFieldFont(.label)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)
            Spacer(minLength: DS.Spacing.xs)
            HStack(spacing: DS.Spacing.xsm) {
                maritalChip(L10n.t("أعزب", "Single"), selected: !isMarried, color: DS.Color.primary) { setMarried(false) }
                // «متزوج» بلون التطبيق الأساسي (الكحلي) — طلب المالك
                maritalChip(L10n.t("متزوج", "Married"), selected: isMarried, color: DS.Color.primary) { setMarried(true) }
            }
        }
        .dsRowBox()
    }

    /// اختيار أعزب/متزوج — الشريحة الواحدة (المختار ممتلئ بتعبئة القسم)
    private func maritalChip(_ title: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        DSChipButton(title, tint: color, isSelected: selected, action: action)
            // لا تُقصّ الكلمة داخل المربّع الأضيق
            .fixedSize()
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
                    DSFieldIcon(name: "person.fill", tint: DS.Color.primary)
                        .accessibilityHidden(true)   // زخرفة

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("الاسم الكامل", "Full Name"))
                            .dsFieldFont(.label)
                            .foregroundColor(DS.Color.fieldLabel)
                        // آخر الاسم = العائلة المختارة — يتحدّث فوراً عند تغيير العائلة
                        // الاسم الكامل كله يظهر بلا قصّ (طلب المالك)
                        // المعدَّل يظهر مكان القديم بلا ملاحظة، والكلمة المتغيّرة
                        // داخل مربّع مميّز (حسن ← «حسين») — يُرسل عند الحفظ (طلب المالك)
                        nameWordsView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // نفس زر العائلة (طلب المالك) — الاسم والعائلة يتغيّران بطلب
                    requestChip
                }
                .dsRowBox()
                .contentShape(Rectangle())
                .cooldownGuarded(.fullName, cooldown: cooldown) { showEditLimitAlert = true }
            }
            .buttonStyle(.plain)

        }
    }

    /// كلمات الاسم، والمتغيّر منها (عن الاسم المحفوظ) في مربّع مميّز
    private var nameWordsView: some View {
        let old = FamilyNameCatalog.words(fullName, family: familyName)
        let new = FamilyNameCatalog.words(pendingNameRequest ?? fullName,
                                          family: pendingFamilyRequest ?? familyName)
        let changed = ChangedWords.flags(old: old, new: new)
        return ChangedWordsFlow(spacing: DS.Spacing.xs) {
            ForEach(Array(new.enumerated()), id: \.offset) { i, word in
                ChangedWordText(word: word, changed: changed[i])
            }
        }
    }

    /// العائلة ثابتة في الملف (طلب المالك): تتغيّر فقط بطلب يعتمده المالك/المدير/المراقب.
    private var familyPickerRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSFieldIcon(name: "person.2.fill", tint: DS.Color.primary)
                .accessibilityHidden(true)   // زخرفة

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("العائلة", "Family"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                // المعدَّل يظهر مكان القديم بلا ملاحظة (طلب المالك)
                if let chosen = pendingFamilyRequest {
                    ChangedWordText(word: chosen, changed: true)
                } else {
                    Text(familyName.isEmpty ? L10n.t("لم تُحدَّد", "Not set") : familyName)
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(familyName.isEmpty ? DS.Color.textTertiary : DS.Color.fieldValue)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // قائمة العوائل في مربّع بمنتصف الشاشة (طلب المالك)
            Button { openFamilyPicker() } label: { requestChip }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("تغيير العائلة", "Change family"))
        }
        .dsRowBox()
    }

    /// زر التعديل الموحّد — أيقونة فقط بلا كلمة (طلب المالك) — قرص مجسّم بدل الرمز المسطّح
    private var requestChip: some View {
        DSStateIcon("pencil", tint: DS.Color.primary, size: DS.Icon.row)
            // مساحة ضغط ٤٤ نقطة (حد أبل): الحشو يوسّع منطقة الضغط داخل هامش الصف،
            // والسالب يعيد الحجم كما كان — الدائرة وارتفاع الصف بلا تغيير
            .padding((DS.Icon.tapTarget - DS.Icon.row) / 2)
            .contentShape(Rectangle())
            .padding(-(DS.Icon.tapTarget - DS.Icon.row) / 2)
            .accessibilityLabel(L10n.t("تعديل", "Edit"))
    }

    private func openNamePopup() {
        var id: UUID?
        let close: () -> Void = { if let i = id { DSPopupPresenter.shared.hide(i) } }
        id = DSPopupPresenter.shared.show(
            NameRequestCard(current: pendingNameRequest ?? fullName, onCancel: close) { newName in
                close()
                pendingNameRequest = newName == fullName ? nil : newName   // يُرسل عند الحفظ
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
        // عائلته الأصلية أولاً (للرجوع لها)، ثم المختارة الآن، ثم بقية العوائل
        let pinned = [familyName, pendingFamilyRequest ?? ""].filter { !$0.isEmpty }
        let options = pinned + familyNamesVM.activeNames.filter { !pinned.contains($0) }
        // اختيار العائلة الحالية = إلغاء الطلب
        let close: () -> Void = {
            if let id = familyPopupID { DSPopupPresenter.shared.hide(id); familyPopupID = nil }
        }
        familyPopupID = DSPopupPresenter.shared.show(
            FamilyRequestCard(options: options, current: familyName,
                              chosen: pendingFamilyRequest ?? familyName, onCancel: close) { chosen in
                close()
                pendingFamilyRequest = chosen == familyName ? nil : chosen   // يُرسل عند الحفظ
            }
        )
    }

    /// السيرة: مربّع عمل بمنتصف الشاشة (`dsCenterBox`) — لا نافذة المربّعات: «تجاهل التغييرات؟»
    /// يُعرض في تلك النافذة نفسها فكان سيُغلق المربّع
    private func openBioPopup() { showBioBox = true }

    private func isValidEmail(_ s: String) -> Bool {
        // فحص بسيط: name@host.tld
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    /// الرقم ثابت في الملف (طلب المالك): يتغيّر بطلب بعد إثبات الرقم الجديد برمز تحقق
    private var modernPhoneField: some View {
        HStack(spacing: DS.Spacing.md) {
            DSFieldIcon(name: "phone.fill", tint: DS.Color.sea)
                .accessibilityHidden(true)   // زخرفة

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("رقم الهاتف", "Phone Number"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(appliedPhoneDisplay ?? KuwaitPhone.display(member.phoneNumber))
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.fieldValue)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                if let pending = pendingPhoneRequest {
                    Text(L10n.t("طلب «\(pending)» بانتظار موافقة الإدارة", "«\(pending)» awaiting approval"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let pending = pendingPhoneForAdmins {
                    Text(L10n.t("طلب «\(pending.display)» يُرسل للإدارة عند الحفظ",
                                "«\(pending.display)» will be sent to the admins on save"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let verified = pendingPhoneVerified {
                    Text(L10n.t("الرقم «\(verified.display)» يُطبَّق عند الحفظ",
                                "«\(verified.display)» applies on save"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openPhonePopup() } label: { requestChip }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(pendingPhoneRequest != nil)
                .accessibilityLabel(L10n.t("تغيير رقم الهاتف", "Change phone number"))
        }
        .dsRowBox()
    }

    /// تاريخ الميلاد — صف للقراءة يفتح مربّعاً بمنتصف الشاشة (طلب المالك)
    private var birthDateRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSFieldIcon(name: "calendar", tint: DS.Color.palm)
                .accessibilityHidden(true)   // زخرفة

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(birthDateProvided ? birthDateText(birthDate) : L10n.t("لم يُحدَّد", "Not set"))
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(birthDateProvided ? DS.Color.fieldValue : DS.Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openBirthDatePopup() } label: { requestChip }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("تعديل تاريخ الميلاد", "Edit birth date"))
        }
        .dsRowBox()
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
        DSComposerSection(
            title: L10n.t("السيرة الذاتية", "Biography"),
            icon: "text.quote",
            tint: DS.Color.accent,
            trailing: bioStations.isEmpty ? L10n.t("اختياري", "Optional")
                                          : "\(bioStations.count) \(L10n.t("حدث", "entries"))",
            index: 2
        ) {
            VStack(spacing: DS.Spacing.sm) {
                if bioStations.isEmpty {
                    // فارغ: خانة الإضافة المشتركة بإطار متقطّع (مثل إضافات المربّعات)
                    Button { openBioPopup() } label: {
                        DSAddChipLabel(icon: "plus", title: L10n.t("أضف حدثاً لسيرتك", "Add to your biography"),
                                       tint: DS.Color.accent, fullWidth: true)
                    }
                    .buttonStyle(DSPressStyle())
                } else {
                    // معاينة المحطات — في صندوق بنفس إطار الحقول
                    VStack(spacing: 0) {
                        ForEach(Array(bioStations.prefix(3).enumerated()), id: \.element.id) { index, station in
                            if index > 0 { DSDivider() }
                            stationPreviewRow(station)
                        }
                        if bioStations.count > 3 {
                            DSDivider()
                            Text(L10n.t("و \(bioStations.count - 3) أحداث أخرى...", "and \(bioStations.count - 3) more..."))
                                .dsFont(.subtitle)
                                .foregroundColor(DS.Color.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, DS.Spacing.sm)
                        }
                    }
                    // نفس صندوق صفوف المربّعات
                    .dsRowBox()

                    // أزرار التعديل والحذف — الزرّ الواحد (الإجراء بتعبئة القسم، الحذف أحمر)
                    HStack(spacing: DSBox.buttonSpacing) {
                        DSButton(L10n.t("تعديل", "Edit"), icon: "pencil") { openBioPopup() }
                        DSButton(L10n.t("حذف", "Delete"), icon: "trash", role: .destructive) {
                            showDeleteBioAlert = true
                        }
                    }
                }
            }
        }
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
                    .dsFont(.badge)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(DS.Color.primary.dsChromeFill(in: section))
                    .clipShape(Capsule())
                    .fixedSize()
            } else {
                Circle()
                    .fill(chromeInk.opacity(DS.Opacity.tintStroke))
                    .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                if !station.title.isEmpty {
                    Text(station.title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                if !station.details.isEmpty {
                    Text(station.details)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    /// نفس شروط الحفظ السابقة: اسم غير فارغ، هاتف وبريد صالحان، واتصال
    private var isSaveDisabled: Bool {
        let newStoredPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
        let isPhoneValid = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newStoredPhone != nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmailValid = trimmedEmail.isEmpty || isValidEmail(trimmedEmail)
        return fullName.isEmpty || memberVM.isLoading || !isPhoneValid || !isEmailValid || !network.isConnected
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
        // DateHelper: ميلادي بأرقام لاتينية — كان formatter الجهاز يقرأ التاريخ خطأ بالتقويم الهجري
        if let date = DateHelper.parse(member.birthDate) {
            self.birthDate = date
            self.birthDateProvided = true
        } else {
            self.birthDateProvided = false
        }
        if let date = DateHelper.parse(member.deathDate) { self.deathDate = date }
        self.isPhoneHidden = member.isPhoneHidden ?? false
        self.email = member.email ?? ""
    }

    // MARK: - Save Changes (broken into helpers)

    /// «حفظ»: إن كان فيه شيء سيذهب للإدارة يظهر تأكيد يعدّده أولاً (طلب المالك)
    private func saveChangesAction() {
        let normalizedPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? ""
        guard phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !normalizedPhone.isEmpty else { return }
        let message = adminConfirmText(changes: detectChangedFields(normalizedPhone: normalizedPhone))
        if let message {
            adminConfirmMessage = message
            showAdminConfirm = true
        } else {
            performSave(confirmed: false)
        }
    }

    /// نص التأكيد: ما يُرسل للإدارة بقيمه الجديدة، وما يُحفظ مباشرة — nil إن لم يُرسل شيء
    private func adminConfirmText(changes: ChangedFields) -> String? {
        var sent: [String] = []
        if let name = pendingNameRequest {
            let full = FamilyNameCatalog.words(name, family: pendingFamilyRequest ?? familyName).joined(separator: " ")
            sent.append(L10n.t("الاسم: \(full)", "Name: \(full)"))
        }
        if let family = pendingFamilyRequest {
            sent.append(L10n.t("العائلة: \(family)", "Family: \(family)"))
        }
        if let verified = pendingPhoneVerified, !cooldown.canEdit(.phoneNumber) {
            sent.append(L10n.t("رقم الهاتف: \(verified.display)", "Phone: \(verified.display)"))
        } else if let forAdmins = pendingPhoneForAdmins {
            sent.append(L10n.t("رقم الهاتف: \(forAdmins.display)", "Phone: \(forAdmins.display)"))
        }
        let marital = isMarried ? L10n.t("متزوج", "Married") : L10n.t("أعزب", "Single")
        if changes.marriedNeedsApproval {
            sent.append(L10n.t("الحالة الاجتماعية: \(marital)", "Marital status: \(marital)"))
        }
        if changes.birthNeedsApproval { sent.append(L10n.t("تاريخ الميلاد", "Birth date")) }
        if changes.phoneHiddenNeedsApproval { sent.append(L10n.t("إظهار الرقم", "Phone visibility")) }
        if changes.bioNeedsApproval { sent.append(L10n.t("السيرة الذاتية", "Bio")) }
        if localPreviewImage != nil, !cooldown.canEdit(.avatar) { sent.append(L10n.t("الصورة", "Photo")) }
        guard !sent.isEmpty else { return nil }

        var saved: [String] = []
        if changes.marriedChanged { saved.append(L10n.t("الحالة الاجتماعية", "Marital status")) }
        if changes.birthChanged { saved.append(L10n.t("تاريخ الميلاد", "Birth date")) }
        if changes.phoneHiddenChanged { saved.append(L10n.t("إظهار الرقم", "Phone visibility")) }
        if changes.bioChanged { saved.append(L10n.t("السيرة الذاتية", "Bio")) }
        if localPreviewImage != nil, cooldown.canEdit(.avatar) { saved.append(L10n.t("الصورة", "Photo")) }
        if pendingPhoneVerified != nil, cooldown.canEdit(.phoneNumber) { saved.append(L10n.t("رقم الهاتف", "Phone")) }

        var text = L10n.t("سيتم إرسال هذه التغييرات للإدارة، وتتغيّر بعد موافقتها:",
                          "These changes will be sent to the admins and apply after approval:")
        text += "\n" + sent.map { "• \($0)" }.joined(separator: "\n")
        if !saved.isEmpty {
            text += L10n.t("\n\nويُحفظ الآن: ", "\n\nSaved now: ") + saved.joined(separator: L10n.t("، ", ", "))
        }
        return text
    }

    /// الحفظ الفعلي — الطلبات والحفظ تعمل بالتوازي (أسرع)، ثم إغلاق
    private func performSave(confirmed: Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let normalizedPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? ""
            savedItems = []; sentItems = []
            let changes = detectChangedFields(normalizedPhone: normalizedPhone)
            // مستقلة عن بعضها — كل واحدة تكتب أعمدة أو جداول مختلفة
            async let pending: Void = applyPendingChanges()   // الصورة والاسم والعائلة والرقم
            async let requests: Void = submitAdminRequests(changes: changes, normalizedPhone: normalizedPhone)
            async let bio: Void = saveBioIfChanged(changes: changes)
            async let mail: Void = saveEmailIfChanged()
            async let data: Bool = submitMemberData(changes: changes)
            _ = await (pending, requests, bio, mail)
            let success = await data
            isSaving = false

            if success {
                recordCooldowns(changes: changes)
                collectSummary(changes: changes)
                if changes.anyNeedsApproval { requestsDueToLimit = true }
                // طلب الاسم/الرقم فشل (applyPendingChanges رفع الخطأ) — تبقى الشاشة مفتوحة برسالة الخطأ،
                // لا إغلاق ولا ملخّص يخفيها
                if showSaveError { return }
                // بعد التأكيد لا رسالة ثانية؛ غير ذلك ملخّص ما تغيّر (طلب المالك)
                if !confirmed && (!savedItems.isEmpty || !sentItems.isEmpty) {
                    showRequestSentAlert = true
                } else {
                    dismiss()
                }
            } else {
                showSaveError = true
            }
        }
    }

    /// حقول النموذج في الملخّص — الصورة والاسم والعائلة والرقم تُضاف في applyPendingChanges
    private func collectSummary(changes: ChangedFields) {
        func add(_ item: String, changed: Bool, sent: Bool) {
            if changed { savedItems.append(item) }
            if sent { sentItems.append(item) }
        }
        add(L10n.t("الحالة الاجتماعية", "Marital status"), changed: changes.marriedChanged, sent: changes.marriedNeedsApproval)
        add(L10n.t("تاريخ الميلاد", "Birth date"), changed: changes.birthChanged, sent: changes.birthNeedsApproval)
        add(L10n.t("إظهار الرقم", "Phone visibility"), changed: changes.phoneHiddenChanged, sent: changes.phoneHiddenNeedsApproval)
        add(L10n.t("السيرة الذاتية", "Bio"), changed: changes.bioChanged, sent: changes.bioNeedsApproval)
    }

    private var saveSummary: String {
        let sep = L10n.t("، ", ", ")
        var lines: [String] = []
        if !savedItems.isEmpty {
            lines.append(L10n.t("تغيّر: ", "Changed: ") + savedItems.joined(separator: sep))
        }
        if !sentItems.isEmpty {
            lines.append(L10n.t("أُرسل للإدارة: ", "Sent to admins: ") + sentItems.joined(separator: sep)
                         + L10n.t("\nيتغيّر بعد موافقتها.", "\nApplies after approval."))
        }
        return lines.joined(separator: "\n")
    }

    /// ما يُجمَع في الشاشة يُنفَّذ هنا فقط (طلب المالك): حذف/رفع الصورة، وطلبات
    /// الاسم والعائلة، وتغيير الرقم بعد إثباته برمز تحقق.
    @MainActor private func applyPendingChanges() async {
        // 1) الصورة
        if pendingAvatarDelete {
            await memberVM.deleteAvatar(for: member.id)
            pendingAvatarDelete = false
            if localPreviewImage == nil { savedItems.append(L10n.t("الصورة", "Photo")) }
        }
        if let newImage = localPreviewImage {
            if cooldown.canEdit(.avatar) {
                let uploaded = await memberVM.uploadAvatar(image: newImage, for: member.id)
                if uploaded {
                    cooldown.recordEdit(.avatar)
                    savedItems.append(L10n.t("الصورة", "Photo"))
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
                    if ok {
                        requestsSent = true; requestsDueToLimit = true
                        sentItems.append(L10n.t("الصورة", "Photo"))
                    } else { showSaveError = true }
                } else {
                    showSaveError = true
                }
            }
        }

        // 2) الاسم — طلب دائماً
        if let newName = pendingNameRequest {
            if await adminRequestVM.requestNameChange(memberId: member.id, newName: newName) {
                requestsSent = true
                sentItems.append(L10n.t("الاسم", "Name"))
                pendingNameRequest = nil
            } else {
                showSaveError = true
            }
        }

        // 3) العائلة — طلب دائماً
        if let newFamily = pendingFamilyRequest {
            if await adminRequestVM.requestFamilyChange(memberId: member.id, newFamily: newFamily) {
                requestsSent = true
                sentItems.append(L10n.t("العائلة", "Family"))
            }
        }

        // 4) الرقم — أول ٣ مرات يُحفظ مباشرة بعد رمز التحقق، وبعدها طلب للإدارة
        if let verified = pendingPhoneVerified {
            if cooldown.canEdit(.phoneNumber) {
                // يُحسب التعديل ويظهر «تغيّر» فقط لو حُفظ فعلاً (رقم محظور/لعضو آخر/انقطاع = خطأ)
                if await memberVM.updateMemberPhone(memberId: member.id,
                                                    country: verified.country,
                                                    localPhone: verified.digits) {
                    cooldown.recordEdit(.phoneNumber)
                    appliedPhoneDisplay = verified.display
                    savedItems.append(L10n.t("رقم الهاتف", "Phone number"))
                } else {
                    showSaveError = true
                }
            } else {
                if await adminRequestVM.requestPhoneNumberChange(memberId: member.id,
                                                                 newPhoneNumber: verified.e164) {
                    pendingPhoneRequest = verified.display
                    requestsSent = true
                    requestsDueToLimit = true
                    sentItems.append(L10n.t("رقم الهاتف", "Phone number"))
                } else {
                    showSaveError = true
                }
            }
            pendingPhoneVerified = nil
        }

        // 5) رقم عليه حساب آخر — لا يُحفظ ذاتياً، يُرسل للإدارة دائماً
        if let pending = pendingPhoneForAdmins {
            if await adminRequestVM.requestPhoneNumberChange(memberId: member.id,
                                                             newPhoneNumber: pending.storage) {
                pendingPhoneRequest = pending.display
                requestsSent = true
                sentItems.append(L10n.t("رقم الهاتف", "Phone number"))
                pendingPhoneForAdmins = nil
            } else {
                showSaveError = true
            }
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
        savedItems.append(L10n.t("البريد الإلكتروني", "Email"))
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
        if isMarried != (member.isMarried ?? false) { return true }
        if isPhoneHidden != (member.isPhoneHidden ?? false) { return true }
        if isDeceased && !(member.isDeceased ?? false) { return true }
        let oldBirthStr = member.birthDate ?? ""
        if birthDateProvided && DateHelper.format(birthDate) != oldBirthStr { return true }
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
        let oldStoredPhone = KuwaitPhone.normalizeForStorageFromInput(member.phoneNumber) ?? ""
        let oldBirthStr = member.birthDate ?? ""
        let newBirthStr = DateHelper.format(birthDate)

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
            _ = await adminRequestVM.submitTreeEditRequest(payload: .make(
                action: .editBirth,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newBirthDate: DateHelper.format(birthDate),
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
            // التاريخ المحفوظ فقط — كان الافتراضي (اليوم) يُكتب لمتوفى بلا تاريخ
            deathDate: member.isDeceased ?? false ? DateHelper.parse(member.deathDate) : nil,
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
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
    let options: [String]
    /// عائلته المحفوظة — تُعلَّم «عائلتك»
    let current: String
    /// المختارة الآن (الطلب المعلّق أو عائلته)
    let chosen: String
    let onCancel: () -> Void
    let onSend: (String) -> Void
    @State private var selected: String?
    /// ارتفاع القائمة الفعلي — يُقاس فيطول مع «حجم النص» في الجهاز (كان تقديراً ثابتاً ٤٤ للصفّ)
    @State private var listHeight: CGFloat = 0

    var body: some View {
        DSCenterCard(onBackgroundTap: onCancel, title: L10n.t("طلب تغيير العائلة", "Request family change"),
                     icon: "person.3.fill") {

            if options.isEmpty {
                // لا عوائل معتمدة بعد (أو تعذّر الجلب) — كان المربّع فارغاً بين الرأس والأزرار
                DSEmptyView(L10n.t("لا توجد عوائل بعد", "No families yet"), style: .inline)
            } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(options, id: \.self) { name in
                        Button { selected = name } label: {
                            HStack {
                                Text(name)
                                    .dsFont(.rowTitle)
                                    .foregroundColor(DS.Color.textPrimary)
                                if name == current {
                                    DSStatusChip(text: L10n.t("عائلتك", "Yours"), tint: DS.Color.textSecondary, size: .mini)
                                }
                                Spacer()
                                Image(systemName: selected == name ? "checkmark.circle.fill" : "circle")
                                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                                    .foregroundColor(selected == name ? chromeInk : DS.Color.textTertiary)
                                    .accessibilityHidden(true)   // الاختيار يُقرأ من حالة الزر
                            }
                            .frame(minHeight: DSBox.fieldMinHeight)
                            // صندوق صفوف المربّعات، والمختار بإطار بلونه
                            .dsRowBox()
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(chromeInk.opacity(selected == name ? DS.Opacity.selectedStroke : 0),
                                              lineWidth: DS.Border.widthBold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == name ? .isSelected : [])
                    }
                }
                .readHeight($listHeight)
            }
            // على قدر المحتوى (طلب المالك) — التمرير فقط لو زادت عن ثلثي الشاشة
            .frame(height: min(listHeight, UIScreen.main.bounds.height * 0.62))
            }

            // صفّ أزرار الهيكل الموحّد (نفس ترتيب وشكل كل المربّعات)
            DSBoxButtons {
                Button(L10n.t("إرسال", "Send")) { if let s = selected { onSend(s) } }
                    .disabled(!canChoose)
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel, action: onCancel)
            }
        }
        .onAppear { if selected == nil { selected = chosen } }
    }

    /// لا فائدة من «إرسال» على نفس المختارة الآن
    private var canChoose: Bool { selected != nil && selected != chosen }
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
        DSCenterCard(onBackgroundTap: onCancel, title: L10n.t("طلب تغيير الاسم", "Request name change"),
                     icon: "person.text.rectangle.fill") {

            // حقل التنبيهات الموحّد
            TextField(L10n.t("اسمك الرباعي", "Your full name"), text: $name, axis: .vertical)
                .lineLimit(1...3)
                .dsAlertField()

            DSBoxButtons {
                Button(L10n.t("إرسال", "Send")) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != current, !sending else { return }
                    sending = true
                    onSend(trimmed)
                }
                .disabled(!canSend)
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel, action: onCancel)
            }
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
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
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
    /// «تقليل الحركة» (توصية أبل): الصفحتان تتبدّلان بتلاشٍ فقط بلا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                numberPage
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
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
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSBoxTitleRow(title: t("تغيير رقم الهاتف", "Change phone number"), icon: "phone.fill")
                Text(t("الحالي: \(KuwaitPhone.display(member.phoneNumber))",
                       "Current: \(KuwaitPhone.display(member.phoneNumber))"))
                    .dsFont(.pageSubtitle)
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
            DSStateIcon("lock.shield.fill", tint: DS.Color.primary, size: DS.Icon.state)
                .accessibilityHidden(true)   // زخرفة

            VStack(spacing: DS.Spacing.xs) {
                Text(t("رمز التحقق", "Verification Code"))
                    .dsFont(.title)
                    .foregroundColor(DS.Color.textPrimary)
                Text(t("أرسلنا رمزاً من ٦ أرقام إلى", "We sent a 6-digit code to"))
                    .dsFont(.pageSubtitle)
                    .foregroundColor(DS.Color.textSecondary)
                Text(KuwaitPhone.display(authPhone))
                    .dsFont(.rowTitle)
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
                    .dsFont(.pageSubtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
            } else {
                Button {
                    code = ""
                    Task { await sendCode() }
                } label: {
                    Text(t("إعادة إرسال الرمز", "Resend code"))
                        .dsFont(.sectionTitle)
                        .foregroundColor(chromeInk)
                        // مساحة ضغط ~٤٤ نقطة (حد أبل) داخل الفراغ حول النص — مكانه وحجمه كما هما
                        .padding(.vertical, DS.Spacing.md)
                        .padding(.horizontal, DS.Spacing.sm)
                        .contentShape(Rectangle())
                        .padding(.vertical, -DS.Spacing.md)
                        .padding(.horizontal, -DS.Spacing.sm)
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
                .dsFont(.caption)
                .foregroundColor(DS.Color.success)
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .dsFont(.caption)
                .foregroundColor(DS.Color.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// الزرّان: الإجراء في جهة و«إلغاء/رجوع» يسار (قاعدة التطبيق)
    private func buttons(primary: String, enabled: Bool,
                         secondary: String, secondaryAction: @escaping () -> Void,
                         action: @escaping () -> Void) -> some View {
        // صفّ أزرار الهيكل الموحّد
        DSBoxButtons {
            Button(action: action) {
                if isBusy {
                    ProgressView().tint(DS.Color.textOnPrimary)
                } else {
                    Text(primary)
                }
            }
            .disabled(!enabled)
            Button(secondary, role: .cancel, action: secondaryAction)
                .disabled(isBusy)
        }
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
            let waitSeconds = OTPWaitText.seconds(in: "\(error) \(error.localizedDescription)")
            if reason.contains("already been registered") || reason.contains("already registered")
                || reason.contains("phone_exists") {
                // الرقم على حساب دخول آخر: السيرفر يحرّره إن كان حساباً يتيماً (بلا عضو)،
                // ثم نطلب الرمز من جديد — الرقم لا ينتقل إلا بعد التحقق (طلب المالك)
                await releaseAndRetry(authNumber: authNumber)
            } else if let waitSeconds {
                // «انتظر N ثانية» من نص الحجب (٢٠٢٦-١٠-٢٠) — وعدّاد إعادة الإرسال يبدأ منها
                self.error = OTPWaitText.message(seconds: waitSeconds, arabic: L10n.isArabic)
                if codeSent { secondsLeft = waitSeconds }
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

/// مربّع «السيرة الذاتية» — مربّع عمل كامل (طلب المالك ٢٠٢٦-١٠-٠٧ «ما لها تصميم مربّع عمل»): رأس
/// `DSComposer` + قسم الأحداث + «حفظ»/«إلغاء» الموحّدان، و«تجاهل التغييرات؟» عند الإلغاء بعد تعديل.
/// التعديل هنا محلي فقط: لا شيء يُحفظ إلا بالضغط على «حفظ» في شاشة التعديل.
/// مشترك: تعديل البيانات + التعديل المباشر (طلب المالك) — يُفتح بـ `dsCenterBox`
struct BioEditCard: View {
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
    let initial: [FamilyMember.BioStation]
    let goesToAdmins: Bool
    let remaining: Int
    let onCancel: () -> Void
    let onDone: ([FamilyMember.BioStation]) -> Void

    @State private var stations: [FamilyMember.BioStation] = []
    @State private var loaded = false

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    /// مفتاح المقارنة نفسه المستخدم في شاشة التعديل (السنة|العنوان|التفاصيل)
    private func key(_ list: [FamilyMember.BioStation]) -> String {
        list.map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
    }

    var body: some View {
        DSComposer(
            title: t("السيرة الذاتية", "Biography"),
            subtitle: t("محطات من حياتك تظهر في ملفك", "Milestones shown on your profile"),
            icon: "scroll.fill",
            tint: DS.Color.actionNavy,
            actionTitle: t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: true,
            note: goesToAdmins ? t("يحتاج موافقة الإدارة", "Needs admin approval") : nil,
            hasUnsavedChanges: loaded && key(stations) != key(initial),
            onSubmit: {
                onDone(stations.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
                                      || !$0.details.trimmingCharacters(in: .whitespaces).isEmpty })
            },
            onCancel: onCancel
        ) {
            DSComposerSection(title: t("الأحداث", "Entries"), icon: "list.bullet",
                              trailing: stations.isEmpty ? t("اختياري", "Optional")
                                                         : "\(stations.count) \(t("حدث", "entries"))",
                              index: 0) {
                if stations.isEmpty {
                    // الحالة الفاضية الواحدة (مضغوطة داخل القسم)
                    DSEmptyView(t("لا توجد أحداث بعد.", "No entries yet."), icon: "scroll.fill", style: .inline)
                } else {
                    ForEach($stations) { $station in
                        stationCard($station)
                    }
                }

                // «إضافة حدث» — بمقاس أزرار `DSBox` الواحدة، مصبوغ بلون القسم
                Button {
                    withAnimation(DS.Anim.snappy) {
                        stations.append(FamilyMember.BioStation(title: "", details: ""))
                    }
                } label: {
                    // خانة الإضافة المشتركة بعرض السطر (إطار متقطّع بلون القسم)
                    DSAddChipLabel(icon: "plus", title: t("إضافة حدث", "Add entry"), tint: chromeInk, fullWidth: true)
                }
                .buttonStyle(DSPressStyle())
            }
        }
        .onAppear {
            guard !loaded else { return }
            stations = initial
            loaded = true
        }
    }

    /// حدث واحد: السنة والعنوان والتفاصيل مع زر حذف
    private func stationCard(_ station: Binding<FamilyMember.BioStation>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                TextField(t("السنة", "Year"), text: Binding(
                    get: { station.wrappedValue.year ?? "" },
                    set: { station.wrappedValue.year = $0.isEmpty ? nil : String($0.filter(\.isNumber).prefix(4)) }
                ))
                .dsFieldFont(.chip)
                .foregroundColor(DS.Color.textSecondary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                // صندوق السنة بارتفاع الشريحة الواحدة
                .frame(width: DS.Icon.sizeLg, height: DSBox.chipHeightCompact)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.mutedBackground))

                TextField(t("العنوان", "Title"), text: station.title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)

                Button {
                    withAnimation(DS.Anim.snappy) {
                        stations.removeAll { $0.id == station.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "trash")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.error)
                        .frame(width: DS.Icon.discSmall, height: DS.Icon.discSmall)
                        .background(Circle().fill(DS.Color.error.opacity(DS.Opacity.tintFill)))
                        // مساحة ضغط ٤٤ نقطة (حد أبل) داخل هامش البطاقة — الدائرة ومكانها كما هما
                        .padding((DS.Icon.tapTarget - DS.Icon.discSmall) / 2)
                        .contentShape(Rectangle())
                        .padding(-(DS.Icon.tapTarget - DS.Icon.discSmall) / 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("حذف الحدث", "Delete entry"))
            }

            TextField(t("التفاصيل (اختياري)", "Details (optional)"), text: station.details, axis: .vertical)
                .dsFieldFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1...3)
        }
        .padding(.vertical, DS.Spacing.xs)
        // نفس صندوق صفوف المربّعات (`dsRowBox` — أبعاده من `DSBox`)
        .dsRowBox()
    }
}



// MARK: - الكلمات المتغيّرة في الاسم (طلب المالك)

/// أي كلمات الاسم الجديد لم تكن في القديم — بمطابقة أطول تسلسل مشترك، فإضافة
/// كلمة في الوسط لا تعلّم كل ما بعدها.
enum ChangedWords {
    static func flags(old: [String], new: [String]) -> [Bool] {
        let n = old.count, m = new.count
        guard n > 0, m > 0 else { return Array(repeating: true, count: m) }
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var changed = Array(repeating: true, count: m)
        var i = 0, j = 0
        while i < n && j < m {
            if old[i] == new[j] { changed[j] = false; i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return changed
    }
}

/// كلمة من الاسم — المتغيّرة في كبسولة خضراء خفيفة جداً بنص أخضر، بلا إطار (طلب المالك)
struct ChangedWordText: View {
    let word: String
    let changed: Bool

    var body: some View {
        Text(word)
            .dsFont(.body)  // نفس حجم ووزن النص العادي (طلب المالك)
            .foregroundColor(changed ? DS.Color.changedFg : DS.Color.fieldValue)
            .padding(.horizontal, changed ? DS.Spacing.sm : 0)
            .background {
                if changed { Capsule().fill(DS.Color.changedBg) }
            }
            .accessibilityLabel(changed ? L10n.t("\(word) (متغيّر)", "\(word) (changed)") : word)
    }
}

/// صفّ كلمات ينكسر لسطر جديد عند امتلاء العرض
struct ChangedWordsFlow: Layout {
    var spacing: CGFloat = DS.Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0, totalHeight: CGFloat = 0
        // الكلمات في السطر الواحد على خط أساس واحد تقريباً (المربّع أطول قليلاً)
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        for size in sizes {
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }
        // توسيط عمودي داخل كل سطر
        var rowStart = 0
        for k in 0...positions.count {
            if k == positions.count || (k > rowStart && positions[k].y != positions[rowStart].y) {
                let h = (rowStart..<k).map { sizes[$0].height }.max() ?? 0
                for r in rowStart..<k { positions[r].y += (h - sizes[r].height) / 2 }
                rowStart = k
            }
        }
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
