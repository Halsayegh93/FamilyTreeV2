import SwiftUI
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
                        .font(DS.Font.calloutBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.primary))
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
    @State private var familyRequestTarget: String?
    @State private var pendingFamilyRequest: String?
    @State private var showFamilyRequestConfirm = false
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
    @State private var showBioEditor = false
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
                            .font(DS.Font.footnote)
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
                                        .cooldownGuarded(.phoneNumber, cooldown: cooldown) { showEditLimitAlert = true }

                                    DSDivider()
                                    modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
                                        .cooldownGuarded(.birthDate, cooldown: cooldown) { showEditLimitAlert = true }
                                        .onChange(of: birthDate) { _ in birthDateProvided = true }

                                    DSDivider()
                                    maritalRow

                                    DSDivider()
                                    emailField
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
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)
                }
                // زر الحفظ أعلى الشاشة (طلب المالك)
                ToolbarItem(placement: DSToolbar.confirmPlacement) {
                    if memberVM.isLoading {
                        ProgressView()
                    } else {
                        Button(L10n.t("حفظ", "Save"), action: saveChangesAction)
                            .font(DS.Font.calloutBold)
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
            .onChange(of: localPreviewImage) { newImage in
                guard let newImage else { return }
                if cooldown.canEdit(.avatar) {
                    Task {
                        let uploaded = await memberVM.uploadAvatar(image: newImage, for: member.id)
                        if uploaded {
                            cooldown.recordEdit(.avatar)
                        } else {
                            // فشل الرفع: رجّع المعاينة للصورة الحالية وأظهر الخطأ
                            localPreviewImage = nil
                            showSaveError = true
                        }
                    }
                } else {
                    // تجاوز حد الـ٣ تعديلات: الصورة تُرفع كاقتراح وتُرسل للإدارة،
                    // ولا تتغيّر صورة العضو إلا بعد الموافقة
                    localPreviewImage = nil
                    Task {
                        guard let url = await adminRequestVM.uploadPhotoSuggestion(newImage) else {
                            showSaveError = true
                            return
                        }
                        let ok = await adminRequestVM.submitTreeEditRequest(payload: .make(
                            action: .addPhoto,
                            targetMemberId: member.id.uuidString,
                            targetMemberName: member.fullName,
                            newPhotoUrl: url,
                            notes: L10n.t("تعديل صورة بعد تجاوز حد التعديلات", "Photo edit after reaching the edit limit")
                        ))
                        if ok { showEditLimitAlert = true } else { showSaveError = true }
                    }
                }
            }
            // مربّع في منتصف الشاشة، نصّه كله باتجاه اليمين (طلب المالك)
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
                L10n.t("اضغط على الصورة لتغييرها", "Tap the photo to change it"),
                systemImage: "camera.fill"
            )
            .font(DS.Font.footnote)
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
                    .cooldownGuarded(.phoneNumber, cooldown: cooldown) { showEditLimitAlert = true }

                DSDivider()
                modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
                    .cooldownGuarded(.birthDate, cooldown: cooldown) { showEditLimitAlert = true }
                    .onChange(of: birthDate) { _ in birthDateProvided = true }

                DSDivider()
                maritalRow

                DSDivider()
                emailField
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    /// الحالة الاجتماعية — صف داخل «المعلومات الشخصية» تحت تاريخ الميلاد (طلب المالك)
    private var maritalRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("heart.fill", color: DS.Color.primary)
            Text(L10n.t("الحالة الاجتماعية", "Marital Status"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
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
        DSProfilePhotoPicker(
            selectedImage: $localPreviewImage,
            existingURL: member.avatarUrl,
            enableCrop: true,
            cropShape: .circle,
            trailing: nil,
            showDeleteForExisting: member.avatarUrl != nil,
            onDeleteExisting: {
                Task {
                    await memberVM.deleteAvatar(for: member.id)
                }
            },
            compactEmptyState: true
        )
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Name with Change Request
    private var nameFieldWithChangeRequest: some View {
        VStack(spacing: 0) {
            Button {
                // تغيير الاسم يُرسل للإدارة دائماً — بلا عدّاد
                newNameRequest = fullName
                showNameChangeSheet = true
            } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("person.fill", color: DS.Color.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("الاسم الكامل", "Full Name"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        // آخر الاسم = العائلة المختارة — يتحدّث فوراً عند تغيير العائلة
                        Text(FamilyNameCatalog.words(fullName, family: familyName).joined(separator: " "))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "pencil.circle.fill")
                        .font(DS.Font.scaled(16, weight: .medium))
                        .foregroundColor(DS.Color.primary)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
                .contentShape(Rectangle())
                .cooldownGuarded(.fullName, cooldown: cooldown) { showEditLimitAlert = true }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showNameChangeSheet) {
                nameChangeRequestSheet
            }

        }
    }

    /// العائلة ثابتة في الملف (طلب المالك): تتغيّر فقط بطلب يعتمده المالك/المدير/المراقب.
    private var familyPickerRow: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("person.2.fill", color: DS.Color.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("العائلة", "Family"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Text(familyName.isEmpty ? L10n.t("لم تُحدَّد", "Not set") : familyName)
                    .font(DS.Font.callout)
                    .foregroundColor(familyName.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                    .lineLimit(1)
                if let pending = pendingFamilyRequest {
                    Text(L10n.t("طلب «\(pending)» بانتظار موافقة الإدارة", "«\(pending)» awaiting approval"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(familyNamesVM.activeNames.filter { $0 != familyName }, id: \.self) { option in
                    Button(option) {
                        familyRequestTarget = option
                        showFamilyRequestConfirm = true
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(L10n.t("طلب تغيير", "Request change"))
                        .font(DS.Font.scaled(13, weight: .bold))
                    Image(systemName: "paperplane.fill")
                        .font(DS.Font.scaled(11, weight: .semibold))
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 32)
                .background(Capsule().fill(DS.Color.primary.opacity(0.10)))
            }
            .disabled(pendingFamilyRequest != nil)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .dsAlert(L10n.t("طلب تغيير العائلة", "Request family change"),
                 isPresented: $showFamilyRequestConfirm,
                 presenting: familyRequestTarget) { target in
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("إرسال", "Send")) {
                Task {
                    if await adminRequestVM.requestFamilyChange(memberId: member.id, newFamily: target) {
                        pendingFamilyRequest = target
                    }
                }
            }
        } message: { target in
            Text(L10n.t("يُرسل طلب تغيير عائلتك إلى «\(target)» للإدارة، ويتغيّر بعد موافقتها.",
                        "A request to change your family to «\(target)» will be sent for approval."))
        }
    }

    private var nameChangeRequestSheet: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                // خانة الاسم قابلة للتعديل — سطر كبير يعرض الاسم كامل
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                        Text(L10n.t("الاسم", "Name"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    TextField(L10n.t("اسمك الرباعي", "Your full name"), text: $newNameRequest, axis: .vertical)
                        .font(DS.Font.body)
                        .lineLimit(1...2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DS.Spacing.md)
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal, DS.Spacing.lg)

                Text(L10n.t(
                    "سيتم إرسال طلب تغيير الاسم للإدارة للموافقة عليه.",
                    "A name change request will be sent to admin for approval."
                ))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)

                DSPrimaryButton(
                    L10n.t("إرسال الطلب", "Send Request"),
                    icon: "paperplane.fill",
                    isLoading: isSubmittingName
                ) {
                    guard !isSubmittingName else { return }
                    let trimmed = newNameRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != fullName else { return }
                    isSubmittingName = true
                    Task {
                        await adminRequestVM.requestNameChange(memberId: member.id, newName: trimmed)
                        isSubmittingName = false
                        showNameChangeSheet = false
                    }
                }
                .disabled(isSubmittingName ||
                          newNameRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          newNameRequest.trimmingCharacters(in: .whitespacesAndNewlines) == fullName)
                .padding(.horizontal, DS.Spacing.lg)
            }
            .padding(.top, DS.Spacing.lg)
            .navigationTitle(L10n.t("طلب تغيير الاسم", "Request Name Change"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    Button(L10n.t("إلغاء", "Cancel")) { showNameChangeSheet = false }
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .presentationDetents([.height(320)])
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func modernReadOnlyField(label: String, value: String, icon: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: DS.Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                Text(value)
                    .font(DS.Font.callout)
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
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                TextField(placeholder, text: text)
                    .font(DS.Font.callout)
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
                    .font(DS.Font.callout)
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
                        .font(DS.Font.caption2)
                    Text(L10n.t("صيغة البريد الإلكتروني غير صحيحة", "Invalid email format"))
                        .font(DS.Font.caption2)
                }
                .foregroundColor(DS.Color.error)
                .padding(.horizontal, DS.Spacing.xl + DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
            } else if !trimmed.isEmpty {
                Text(L10n.t("يُستخدم لإشعارات الإدارة فقط — لا يظهر للآخرين", "Used for admin notifications only — not visible to others"))
                    .font(DS.Font.caption2)
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

    private var modernPhoneField: some View {
        DSLabeledFieldRow(icon: "phone.fill", iconColor: DS.Color.success,
                          label: L10n.t("رقم الهاتف", "Phone Number")) {
            DSPhoneField(
                country: $selectedPhoneCountry,
                digits: $phoneNumber,
                placeholder: "9xxxxxxx",
                compact: true,
                bordered: false
            )
        }
    }

    private func modernDatePicker(label: String, selection: Binding<Date>, icon: String) -> some View {
        DSDateField(
            label: label,
            date: selection,
            icon: icon,
            range: ...Date(),
            labelAbove: true
        )
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
                    Button { showBioEditor = true } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(DS.Font.scaled(18))
                                .foregroundColor(DS.Color.primary)
                            Text(L10n.t("أضف حدثاً لسيرتك", "Add to your biography"))
                                .font(DS.Font.callout)
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
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.sm)
                        }
                    }

                    // أزرار التعديل والحذف
                    HStack(spacing: DS.Spacing.sm) {
                        Button { showBioEditor = true } label: {
                            Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(DS.Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button { showDeleteBioAlert = true } label: {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                .font(DS.Font.calloutBold)
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
        .sheet(isPresented: $showBioEditor) {
            BioStationsEditorSheet(stations: $bioStations)
        }
        .dsAlert(
            L10n.t("حذف السيرة", "Delete Biography"),
            isPresented: $showDeleteBioAlert
        ) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                bioStations = []
                let memberId = member.id
                member.bio = nil
                Task { await memberVM.updateMemberBio(memberId: memberId, bio: []) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t("سيتم حذف السيرة الذاتية كاملة.", "The whole biography will be deleted."))
        }
    }

    private func stationPreviewRow(_ station: FamilyMember.BioStation) -> some View {
        HStack(spacing: DS.Spacing.md) {
            if let year = station.year, !year.isEmpty {
                Text(year)
                    .font(DS.Font.caption2)
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
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                if !station.details.isEmpty {
                    Text(station.details)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
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
                    .font(DS.Font.caption2)
                Text(L10n.t("لا يمكن الحفظ بدون اتصال", "Can't save while offline"))
                    .font(DS.Font.caption1)
            }
            .foregroundColor(DS.Color.error)
            .padding(.horizontal, DS.Spacing.lg)
        }
    }


    // MARK: - Logic (الوظائف)

    /// تغيير حالة الزواج + حفظ فوري في القاعدة (لا يعتمد على زر الحفظ العام).
    private func setMarried(_ value: Bool) {
        guard value != isMarried else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        // تجاوز حد الـ٣ تعديلات → طلب للإدارة، والحالة تبقى كما هي حتى الموافقة
        guard cooldown.canEdit(.isMarried) else {
            Task {
                let ok = await adminRequestVM.submitTreeEditRequest(payload: .make(
                    action: .other,
                    targetMemberId: member.id.uuidString,
                    targetMemberName: member.fullName,
                    newName: value ? "true" : "false",
                    reason: "profile_marital",
                    notes: L10n.t("طلب تغيير الحالة الاجتماعية إلى: \(value ? "متزوج" : "غير متزوج")",
                                  "Marital status change to: \(value ? "Married" : "Single")")
                ))
                if ok { dismissAfterLimitAlert = false; showEditLimitAlert = true } else { showSaveError = true }
            }
            return
        }
        withAnimation(DS.Anim.quick) { isMarried = value }
        // حفظ فوري في القاعدة (is_married فقط — آمن، خارج مراقبة trigger النساء)
        Task {
            if await memberVM.setMaritalStatus(memberId: member.id, isMarried: value) {
                cooldown.recordEdit(.isMarried)
            }
        }
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
        let phoneHiddenChanged: Bool
        let phoneHiddenNeedsApproval: Bool
        let phoneChanged: Bool
        let bioChanged: Bool
        let bioNeedsApproval: Bool
        let deceasedChanged: Bool

        /// أي حقل تجاوز حد الـ٣ وأُرسل للإدارة
        var anyNeedsApproval: Bool { birthNeedsApproval || phoneHiddenNeedsApproval || bioNeedsApproval }
    }

    /// «تعديلات غير محفوظة» يشمل فقط الحقول التي تُحفظ عبر زر «حفظ التغييرات» أو
    /// تُرسل كطلب موافقة عند الإغلاق. يُستثنى منها ما يُحفظ فوراً (الصورة + الحالة
    /// الاجتماعية) حتى لا يظهر تنبيه «تجاهل التعديلات؟» لتغييرات ثبتت أصلاً.
    private var hasUnsavedChanges: Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        // ملاحظة: الحالة الاجتماعية (isMarried) تُحفظ فوراً في setMarried — لا تُحتسب هنا.
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
        return ChangedFields(
            birthChanged: birthDiffers && cooldown.canEdit(.birthDate),
            birthNeedsApproval: birthDiffers && !cooldown.canEdit(.birthDate),
            marriedChanged: isMarried != (member.isMarried ?? false),
            // الرقم يُرسل للإدارة دائماً؛ إخفاء الرقم والنبذة: ٣ تعديلات ثم موافقة الإدارة
            phoneHiddenChanged: phoneHiddenDiffers && cooldown.canEdit(.isPhoneHidden),
            phoneHiddenNeedsApproval: phoneHiddenDiffers && !cooldown.canEdit(.isPhoneHidden),
            phoneChanged: !normalizedPhone.isEmpty && (normalizedPhone != oldStoredPhone),
            bioChanged: bioDiffers && cooldown.canEdit(.bio),
            bioNeedsApproval: bioDiffers && !cooldown.canEdit(.bio),
            deceasedChanged: isDeceased && !(member.isDeceased ?? false)
        )
    }

    private func submitAdminRequests(changes: ChangedFields, normalizedPhone: String) async {
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
            isMarried: isMarried,
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
    }

}
