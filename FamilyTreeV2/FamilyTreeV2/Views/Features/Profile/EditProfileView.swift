import SwiftUI
import PhotosUI

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
    @State private var bioText: String = ""
    @State private var showDeleteBioAlert = false
    @State private var showSaveError = false
    @State private var showNameChangeSheet = false
    @State private var newNameRequest: String = ""
    @State private var isSubmittingName = false
    @State private var showAvatarCooldownAlert = false

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
                                .opacity(cooldown.canEdit(.avatar) ? 1 : 0.5)
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
                                        .disabled(!cooldown.canEdit(.phoneNumber))
                                        .opacity(cooldown.canEdit(.phoneNumber) ? 1 : 0.5)
                                    cooldownLabel(.phoneNumber)

                                    DSDivider()
                                    modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
                                        .disabled(!cooldown.canEdit(.birthDate))
                                        .opacity(cooldown.canEdit(.birthDate) ? 1 : 0.5)
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
                                        .disabled(!cooldown.canEdit(.isMarried))
                                        .opacity(cooldown.canEdit(.isMarried) ? 1 : 0.5)

                                        cooldownLabel(.isMarried)
                                    }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 4. السيرة الذاتية
                        aiBioSection
                            .disabled(!cooldown.canEdit(.bio))
                            .opacity(cooldown.canEdit(.bio) ? 1 : 0.5)

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
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .onAppear {
                setupData()
            }
            .onChange(of: localPreviewImage) { _, newImage in
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
                .opacity(cooldown.canEdit(.fullName) ? 1 : 0.5)
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
            .frame(height: 30)
            .frame(maxWidth: 130)

            Text("\(selectedPhoneCountry.flag) \(selectedPhoneCountry.dialingCode)")
                .font(DS.Font.scaled(13, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func modernDatePicker(label: String, selection: Binding<Date>, icon: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: DS.Color.accent)

            Text(label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)

            Spacer()

            DatePicker("", selection: selection, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var aiBioSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("السيرة الذاتية", "Bio"),
                icon: "text.quote",
                iconColor: DS.Color.accent
            )

            VStack(spacing: DS.Spacing.md) {
                // حقل كتابة السيرة
                TextEditor(text: $bioText)
                    .font(DS.Font.callout)
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(minHeight: 120, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.inactiveBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, DS.Spacing.lg)

                // عداد الحروف + توضيح
                HStack {
                    Text(L10n.t(
                        "اكتب نبذة عن نفسك",
                        "Write about yourself"
                    ))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)

                    Spacer()

                    Text("\(bioText.count)/500")
                        .font(DS.Font.caption2)
                        .foregroundColor(bioText.count > 500 ? DS.Color.error : DS.Color.textTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, DS.Spacing.lg + DS.Spacing.xs)

                // زر حذف السيرة (إذا فيه نص)
                if !bioText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        showDeleteBioAlert = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "trash")
                                .font(DS.Font.scaled(13, weight: .semibold))
                            Text(L10n.t("حذف السيرة", "Delete Biography"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.error.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }
            }
            .padding(.bottom, DS.Spacing.md)
            .onChange(of: bioText) {
                if bioText.count > 500 {
                    bioText = String(bioText.prefix(500))
                }
            }

            cooldownLabel(.bio)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .alert(
            L10n.t("حذف السيرة", "Delete Biography"),
            isPresented: $showDeleteBioAlert
        ) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                bioText = ""
                let memberId = member.id
                member.bio = nil
                Task { await memberVM.updateMemberBio(memberId: memberId, bio: []) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t(
                "هل تريد حذف السيرة الذاتية؟",
                "Delete biography?"
            ))
        }
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
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(DS.Font.caption2)
                Text(L10n.t(
                    "غير متاح حالياً",
                    "Not available now"
                ))
                .font(DS.Font.caption2)
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
        // تحميل السيرة الذاتية الحالية
        if let bioStations = member.bio, !bioStations.isEmpty {
            self.bioText = bioStations.map { station in
                [station.year, station.title, station.details]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " - ")
            }.joined(separator: "\n")
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let b = member.birthDate, let date = f.date(from: b) { self.birthDate = date }
        if let d = member.deathDate, let date = f.date(from: d) { self.deathDate = date }
        self.isPhoneHidden = member.isPhoneHidden ?? false
    }

    private func saveChangesAction() {
        Task {
            let normalizedPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? ""
            let oldStoredPhone = KuwaitPhone.normalizeForStorageFromInput(member.phoneNumber) ?? ""
            guard phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !normalizedPhone.isEmpty else { return }

            // تحديد الحقول المتغيرة
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let oldBirthStr = member.birthDate ?? ""
            let newBirthStr = f.string(from: birthDate)
            let birthChanged = newBirthStr != oldBirthStr && cooldown.canEdit(.birthDate)
            let marriedChanged = isMarried != (member.isMarried ?? false) && cooldown.canEdit(.isMarried)
            let phoneHiddenChanged = isPhoneHidden != (member.isPhoneHidden ?? false) && cooldown.canEdit(.isPhoneHidden)
            let isPhoneChanged = !normalizedPhone.isEmpty && (normalizedPhone != oldStoredPhone) && cooldown.canEdit(.phoneNumber)
            let isDeceasedChanged = (isDeceased && !(member.isDeceased ?? false))

            // السيرة
            let trimmedBio = bioText.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldBioText = (member.bio ?? []).map { [$0.title, $0.details].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ") }.joined(separator: "\n")
            let bioChanged = trimmedBio != oldBioText && cooldown.canEdit(.bio)

            if isDeceasedChanged {
                await adminRequestVM.requestDeceasedStatus(memberId: member.id, deathDate: deathDate)
            }

            if isPhoneChanged {
                await adminRequestVM.requestPhoneNumberChange(memberId: member.id, newPhoneNumber: normalizedPhone)
            }

            // حفظ السيرة الذاتية
            if bioChanged {
                if !trimmedBio.isEmpty {
                    let station = FamilyMember.BioStation(title: "", details: trimmedBio)
                    await memberVM.updateMemberBio(memberId: member.id, bio: [station])
                    member.bio = [station]
                } else {
                    await memberVM.updateMemberBio(memberId: member.id, bio: [])
                    member.bio = nil
                }
            }

            let success = await memberVM.updateMemberData(
                memberId: member.id,
                fullName: fullName,
                phoneNumber: member.phoneNumber ?? "",
                birthDate: birthDate,
                isMarried: isMarried,
                isDeceased: member.isDeceased ?? false,
                deathDate: member.isDeceased ?? false ? deathDate : nil,
                isPhoneHidden: isPhoneHidden
            )

            if success {
                // تسجيل cooldown للحقول المتغيرة فقط
                if birthChanged { cooldown.recordEdit(.birthDate) }
                if marriedChanged { cooldown.recordEdit(.isMarried) }
                if phoneHiddenChanged { cooldown.recordEdit(.isPhoneHidden) }
                if bioChanged { cooldown.recordEdit(.bio) }
                if isPhoneChanged { cooldown.recordEdit(.phoneNumber) }
                dismiss()
            } else {
                showSaveError = true
            }
        }
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
                                    MagnifyGesture()
                                        .onChanged { value in
                                            let newScale = lastZoomScale * value.magnification
                                            zoomScale = min(max(newScale, 1), 4)
                                        }
                                        .onEnded { _ in
                                            lastZoomScale = zoomScale
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
