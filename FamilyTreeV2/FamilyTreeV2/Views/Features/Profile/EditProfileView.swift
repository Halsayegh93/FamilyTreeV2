import SwiftUI
import PhotosUI

// MARK: - Cooldown Guard Modifier

/// Reusable modifier that applies `.disabled` + `.opacity` based on cooldown state
private struct CooldownGuardModifier: ViewModifier {
    let canEdit: Bool

    func body(content: Content) -> some View {
        content
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.5)
    }
}

private extension View {
    func cooldownGuarded(_ field: EditableField, cooldown: ProfileEditCooldown) -> some View {
        modifier(CooldownGuardModifier(canEdit: cooldown.canEdit(field)))
    }
}

struct EditProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss

    @State var member: FamilyMember

    // متغيرات الحالة
    @State private var fullName: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = Date()
    @State private var isMarried: Bool = false
    @State private var isDeceased: Bool = false
    @State private var deathDate: Date = Date()
    @State private var isPhoneHidden: Bool = false
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
    @State private var showAvatarCooldownAlert = false
    @State private var showDiscardAlert = false

    private let cooldown = ProfileEditCooldown.shared



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
                    VStack(spacing: DS.Spacing.md) {

                        // 1. قسم الصورة الشخصية (تصميم دائري مع ظل فخم)
                        VStack(spacing: DS.Spacing.xs) {
                            imagePickerHeader
                                .cooldownGuarded(.avatar, cooldown: cooldown)
                            cooldownLabel(.avatar)
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
                                    modernPhoneField
                                        .cooldownGuarded(.phoneNumber, cooldown: cooldown)
                                    cooldownLabel(.phoneNumber)

                                    DSDivider()
                                    modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
                                        .cooldownGuarded(.birthDate, cooldown: cooldown)
                                    cooldownLabel(.birthDate)
                                }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 3. حالة الزواج والوفاة
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("الحالة الاجتماعية", "Status"),
                                icon: "heart.text.square",
                                iconColor: DS.Color.neonPink
                            )

                                    VStack(spacing: 0) {
                                        HStack(spacing: DS.Spacing.md) {
                                            DSIcon("heart.fill", color: DS.Color.neonPink)
                                            Toggle(L10n.t("متزوج", "Married"), isOn: $isMarried)
                                                .font(DS.Font.callout)
                                                .foregroundColor(DS.Color.textPrimary)
                                                .tint(DS.Color.primary)
                                        }
                                        .padding(.horizontal, DS.Spacing.lg)
                                        .padding(.vertical, DS.Spacing.xs)
                                        .cooldownGuarded(.isMarried, cooldown: cooldown)

                                        cooldownLabel(.isMarried)
                                    }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 4. المحطات الحياتية
                        bioStationsSection
                            .cooldownGuarded(.bio, cooldown: cooldown)

                        // 5. زر الحفظ (تصميم عائم)
                        saveButton

                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
            .navigationTitle(editScreenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
            }
            .alert(
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
            .onAppear {
                setupData()
            }
            .onChange(of: localPreviewImage) { newImage in
                guard let newImage else { return }
                if cooldown.canEdit(.avatar) {
                    Task {
                        await memberVM.uploadAvatar(image: newImage, for: member.id)
                        cooldown.recordEdit(.avatar)
                    }
                } else {
                    localPreviewImage = nil
                    showAvatarCooldownAlert = true
                }
            }
            .alert(
                L10n.t("غير متاح حالياً", "Not Available"),
                isPresented: $showAvatarCooldownAlert
            ) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "غير متاح تعديل الصورة حالياً",
                    "Photo edit not available now"
                ))
            }
            .alert(L10n.t("خطأ", "Error"), isPresented: $showSaveError) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t("تعذر الحفظ. حاول مرة أخرى.", "Save failed. Try again."))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
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
                if cooldown.canEdit(.fullName) {
                    newNameRequest = fullName
                    showNameChangeSheet = true
                }
            } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("person.fill", color: DS.Color.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("الاسم الكامل", "Full Name"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                        Text(fullName)
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                    }

                    Spacer()

                    if cooldown.canEdit(.fullName) {
                        Image(systemName: "pencil.circle.fill")
                            .font(DS.Font.scaled(16, weight: .medium))
                            .foregroundColor(DS.Color.primary)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
                .cooldownGuarded(.fullName, cooldown: cooldown)
            }
            .buttonStyle(.plain)
            .disabled(!cooldown.canEdit(.fullName))
            .sheet(isPresented: $showNameChangeSheet) {
                nameChangeRequestSheet
            }

            cooldownLabel(.fullName)
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
                        cooldown.recordEdit(.fullName)
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
                ToolbarItem(placement: .navigationBarLeading) {
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

    private var modernPhoneField: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSIcon("phone.fill", color: DS.Color.success)

            Text(L10n.t("رقم الهاتف", "Phone Number"))
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)

            Spacer()

            PhoneNumberTextField(
                text: $phoneNumber,
                placeholder: "9xxxxxxx",
                font: .monospacedDigitSystemFont(ofSize: 15, weight: .regular),
                keyboardType: .phonePad,
                textAlignment: .left,
                maxLength: selectedPhoneCountry.maxDigits
            )
            .frame(height: DS.Spacing.xxxl - 2)
            .frame(maxWidth: DS.Spacing.xxxl * 4 + DS.Spacing.sm)

            Text("\(selectedPhoneCountry.flag) \(selectedPhoneCountry.dialingCode)")
                .font(DS.Font.scaled(13, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func modernDatePicker(label: String, selection: Binding<Date>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.md) {
                DSIcon(icon, color: DS.Color.accent)
                Text(label)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
            }
            StableWheelDatePicker(selection: selection, in: ...Date())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var bioStationsSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("المحطات الحياتية", "Life Stations"),
                icon: "text.quote",
                trailing: bioStations.isEmpty ? nil : "\(bioStations.count) \(L10n.t("محطة", "stations"))",
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
                            Text(L10n.t("أضف محطة حياتية", "Add life station"))
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
                            Text(L10n.t("و \(bioStations.count - 3) محطات أخرى...", "and \(bioStations.count - 3) more..."))
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

            cooldownLabel(.bio)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .sheet(isPresented: $showBioEditor) {
            BioStationsEditorSheet(stations: $bioStations)
        }
        .alert(
            L10n.t("حذف المحطات", "Delete Stations"),
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
            Text(L10n.t("سيتم حذف جميع المحطات الحياتية.", "All life stations will be deleted."))
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

    private var saveButton: some View {
        let newStoredPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
        let isPhoneValid = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newStoredPhone != nil

        return DSPrimaryButton(
            L10n.t("حفظ التغييرات", "Save Changes"),
            isLoading: memberVM.isLoading,
            action: saveChangesAction
        )
        .disabled(fullName.isEmpty || memberVM.isLoading || !isPhoneValid)
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Cooldown Label

    @ViewBuilder
    private func cooldownLabel(_ field: EditableField) -> some View {
        if !cooldown.canEdit(field) {
            // مقفل — يعرض الوقت المتبقي
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(DS.Font.caption2)
                Text(L10n.t(
                    "مقفل — \(cooldown.formattedRemaining(field))",
                    "Locked — \(cooldown.formattedRemaining(field))"
                ))
                .font(DS.Font.caption2)
            }
            .foregroundColor(DS.Color.warning)
            .padding(.horizontal, DS.Spacing.xl + DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if cooldown.remainingEdits(field) == 1 {
            // تحذير — آخر تعديل قبل القفل
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DS.Font.caption2)
                Text(L10n.t("آخر تعديل متاح — بعده يُقفل 24 ساعة", "Last edit — field locks for 24h after"))
                    .font(DS.Font.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(DS.Color.warning)
            .padding(.horizontal, DS.Spacing.xl + DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Logic (الوظائف)

    private func setupData() {
        self.fullName = member.fullName
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        self.selectedPhoneCountry = detectedPhone.country
        self.phoneNumber = detectedPhone.localDigits
        self.isMarried = member.isMarried ?? false
        self.isDeceased = member.isDeceased ?? false
        // تحميل المحطات الحياتية
        self.bioStations = member.bio ?? []
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let b = member.birthDate, let date = f.date(from: b) { self.birthDate = date }
        if let d = member.deathDate, let date = f.date(from: d) { self.deathDate = date }
        self.isPhoneHidden = member.isPhoneHidden ?? false
    }

    // MARK: - Save Changes (broken into helpers)

    private func saveChangesAction() {
        Task {
            let normalizedPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? ""
            guard phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !normalizedPhone.isEmpty else { return }

            let changes = detectChangedFields(normalizedPhone: normalizedPhone)
            await submitAdminRequests(changes: changes, normalizedPhone: normalizedPhone)
            await saveBioIfChanged(changes: changes)

            let success = await submitMemberData()
            if success {
                recordCooldowns(changes: changes)
                dismiss()
            } else {
                showSaveError = true
            }
        }
    }

    /// Holds which fields changed so cooldowns can be recorded after a successful save
    private struct ChangedFields {
        let birthChanged: Bool
        let marriedChanged: Bool
        let phoneHiddenChanged: Bool
        let phoneChanged: Bool
        let bioChanged: Bool
        let deceasedChanged: Bool
    }

    private var hasUnsavedChanges: Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if isMarried != (member.isMarried ?? false) { return true }
        if isPhoneHidden != (member.isPhoneHidden ?? false) { return true }
        if isDeceased && !(member.isDeceased ?? false) { return true }
        let oldBirthStr = member.birthDate ?? ""
        if f.string(from: birthDate) != oldBirthStr { return true }
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

        return ChangedFields(
            birthChanged: newBirthStr != oldBirthStr && cooldown.canEdit(.birthDate),
            marriedChanged: isMarried != (member.isMarried ?? false) && cooldown.canEdit(.isMarried),
            phoneHiddenChanged: isPhoneHidden != (member.isPhoneHidden ?? false) && cooldown.canEdit(.isPhoneHidden),
            phoneChanged: !normalizedPhone.isEmpty && (normalizedPhone != oldStoredPhone) && cooldown.canEdit(.phoneNumber),
            bioChanged: oldBioKey != newBioKey && cooldown.canEdit(.bio),
            deceasedChanged: isDeceased && !(member.isDeceased ?? false)
        )
    }

    private func submitAdminRequests(changes: ChangedFields, normalizedPhone: String) async {
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

    private func submitMemberData() async -> Bool {
        await memberVM.updateMemberData(
            memberId: member.id,
            fullName: fullName,
            phoneNumber: member.phoneNumber ?? "",
            birthDate: birthDate,
            isMarried: isMarried,
            isDeceased: member.isDeceased ?? false,
            deathDate: member.isDeceased ?? false ? deathDate : nil,
            isPhoneHidden: isPhoneHidden
        )
    }

    private func recordCooldowns(changes: ChangedFields) {
        if changes.birthChanged { cooldown.recordEdit(.birthDate) }
        if changes.marriedChanged { cooldown.recordEdit(.isMarried) }
        if changes.phoneHiddenChanged { cooldown.recordEdit(.isPhoneHidden) }
        if changes.bioChanged { cooldown.recordEdit(.bio) }
        if changes.phoneChanged { cooldown.recordEdit(.phoneNumber) }
    }

}

struct GalleryPhotoViewer: View {
    let photoURL: String
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.overlayDark.ignoresSafeArea()
                .onTapGesture { onClose() }

            if let url = URL(string: photoURL) {
                CachedAsyncPhaseImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastZoomScale * value
                                            zoomScale = min(max(newScale, 1), 4)
                                        }
                                        .onEnded { value in
                                            lastZoomScale = min(max(lastZoomScale * value, 1), 4)
                                            zoomScale = lastZoomScale
                                            if zoomScale <= 1 {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    zoomScale = 1
                                                    lastZoomScale = 1
                                                    offset = .zero
                                                    lastOffset = .zero
                                                }
                                            }
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            if zoomScale > 1 {
                                                offset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if zoomScale > 1 {
                                        zoomScale = 1
                                        lastZoomScale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        zoomScale = 2
                                        lastZoomScale = 2
                                    }
                                }
                            }
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .font(DS.Font.scaled(42))
                            .foregroundColor(DS.Color.overlayTextMuted)
                    } else {
                        ProgressView()
                            .tint(DS.Color.textOnPrimary)
                    }
                }
                .padding()
            }

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(30))
                        .foregroundStyle(DS.Color.textOnPrimary, DS.Color.hierarchicalSecondary)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(DS.Font.scaled(30))
                        .foregroundStyle(DS.Color.error, DS.Color.hierarchicalSecondary)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.lg)
        }
    }
}
