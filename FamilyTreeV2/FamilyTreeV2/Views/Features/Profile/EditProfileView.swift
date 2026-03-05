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
    // AI Bio
    @State private var aiVM: AIViewModel? = nil
    @State private var showBioResult = false
    @State private var showDeleteBioAlert = false
    @State private var showSaveError = false



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

                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxxl) {

                        // 1. قسم الصورة الشخصية (تصميم دائري مع ظل فخم)
                        imagePickerHeader

                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                                icon: "person.text.rectangle"
                            )

                                VStack(spacing: 0) {
                                    modernTextField(label: L10n.t("الاسم الكامل", "Full Name"), text: $fullName, icon: "person.fill", placeholder: L10n.t("أدخل الاسم الرباعي", "Enter full name"))
                                    DSDivider()
                                    modernPhoneField

                                    DSDivider()
                                    modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
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

                                    HStack(spacing: DS.Spacing.md) {
                                        DSIcon("heart.fill", color: DS.Color.neonPink)
                                        Toggle(L10n.t("متزوج", "Married"), isOn: $isMarried)
                                            .font(DS.Font.callout)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .tint(DS.Color.primary)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.sm)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 4. السيرة الذاتية بالذكاء الاصطناعي
                        aiBioSection

                        // 5. زر الحفظ (تصميم عائم)
                        saveButton

                    }
                    .padding(.vertical, DS.Spacing.xxl)
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
                if aiVM == nil, let userId = authVM.currentUser?.id.uuidString {
                    aiVM = AIViewModel(userId: userId)
                }
            }
            .onChange(of: localPreviewImage) { _, newImage in
                guard let newImage else { return }
                Task { await memberVM.uploadAvatar(image: newImage, for: member.id) }
            }
            .alert(L10n.t("خطأ", "Error"), isPresented: $showSaveError) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t("تعذر حفظ التغييرات. حاول مرة أخرى.", "Failed to save changes. Please try again."))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - المكونات المصممة (Custom Components)

    private var imagePickerHeader: some View {
        DSProfilePhotoPicker(
            selectedImage: $localPreviewImage,
            existingURL: member.avatarUrl
        )
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func modernTextField(label: String, text: Binding<String>, icon: String, placeholder: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: DS.Color.primary)

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
        .padding(.vertical, DS.Spacing.md)
    }

    private var modernPhoneField: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("phone.fill", color: DS.Color.success)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("رقم الجوال", "Phone Number"))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)

                HStack(spacing: DS.Spacing.sm) {
                    Menu {
                        ForEach(KuwaitPhone.supportedCountries) { country in
                            Button {
                                selectedPhoneCountry = country
                            } label: {
                                Text("\(country.flag) \(country.nameArabic) \(country.dialingCode)")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedPhoneCountry.flag)
                            Text(selectedPhoneCountry.dialingCode)
                                .font(DS.Font.callout)
                            Image(systemName: "chevron.down")
                                .font(DS.Font.scaled(10, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DS.Color.surface)
                        .cornerRadius(DS.Radius.sm)
                    }

                    TextField("9xxxxxxx", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .onChange(of: phoneNumber) { _, newValue in
                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                }
                .onChange(of: selectedPhoneCountry) { _, newCountry in
                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    private func modernDatePicker(label: String, selection: Binding<Date>, icon: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: DS.Color.info)
            Text(label)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            DatePicker("", selection: selection, in: ...Date(), displayedComponents: .date).labelsHidden()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var aiBioSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("السيرة الذاتية", "Bio"),
                icon: "sparkles",
                iconColor: DS.Color.neonCyan
            )

            VStack(spacing: DS.Spacing.md) {
                // Current bio stations
                if let bioStations = member.bio, !bioStations.isEmpty {
                    ForEach(bioStations) { station in
                        HStack(alignment: .top, spacing: DS.Spacing.md) {
                            if let year = station.year, !year.isEmpty {
                                Text(year)
                                    .font(DS.Font.caption1)
                                    .fontWeight(.bold)
                                    .foregroundColor(DS.Color.primary)
                                    .frame(width: 44)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.title)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                                if !station.details.isEmpty {
                                    Text(station.details)
                                        .font(DS.Font.caption1)
                                        .foregroundColor(DS.Color.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }

                    // زر حذف السيرة
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
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.error.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    DSDivider()
                }

                // Generated bio preview
                if showBioResult, let vm = aiVM, !vm.generatedBioStations.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.warning)
                            Text(L10n.t("سيرة مقترحة بالذكاء الاصطناعي", "AI Suggested Bio"))
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.warning)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        ForEach(vm.generatedBioStations) { station in
                            HStack(alignment: .top, spacing: DS.Spacing.md) {
                                if let year = station.year, !year.isEmpty {
                                    Text(year)
                                        .font(DS.Font.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(DS.Color.neonCyan)
                                        .frame(width: 44)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.title)
                                        .font(DS.Font.calloutBold)
                                        .foregroundColor(DS.Color.textPrimary)
                                    if !station.details.isEmpty {
                                        Text(station.details)
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textSecondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Accept button
                        Button {
                            Task {
                                await memberVM.updateMemberBio(
                                    memberId: member.id,
                                    bio: vm.generatedBioStations
                                )
                                member.bio = vm.generatedBioStations
                                showBioResult = false
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(L10n.t("اعتماد السيرة", "Apply Bio"))
                            }
                            .font(DS.Font.calloutBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(DS.Color.gradientPrimary)
                            .cornerRadius(DS.Radius.lg)
                        }
                        .buttonStyle(DSBoldButtonStyle())
                        .padding(.horizontal, DS.Spacing.lg)
                    }
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.warning.opacity(0.05))
                    .cornerRadius(DS.Radius.md)
                }

                // Error message
                if let error = aiVM?.bioError {
                    Text(error)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.error)
                        .padding(.horizontal, DS.Spacing.lg)
                }

                // Generate button
                Button {
                    Task {
                        guard let vm = aiVM else { return }
                        await vm.generateBio(memberId: member.id.uuidString)
                        if !vm.generatedBioStations.isEmpty {
                            withAnimation(DS.Anim.bouncy) { showBioResult = true }
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if aiVM?.isBioLoading == true {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(L10n.t("إنشاء سيرة ذاتية بالذكاء الاصطناعي", "Generate Bio with AI"))
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DS.Color.primary.opacity(0.1))
                    .cornerRadius(DS.Radius.lg)
                }
                .buttonStyle(DSBoldButtonStyle())
                .disabled(aiVM?.isBioLoading == true)
                .padding(.horizontal, DS.Spacing.lg)
            }
            .padding(.bottom, DS.Spacing.md)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .alert(
            L10n.t("حذف السيرة", "Delete Biography"),
            isPresented: $showDeleteBioAlert
        ) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
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

    // MARK: - Logic (الوظائف)

    private func setupData() {
        self.fullName = member.fullName
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        self.selectedPhoneCountry = detectedPhone.country
        self.phoneNumber = detectedPhone.localDigits
        self.isMarried = member.isMarried ?? false
        self.isDeceased = member.isDeceased ?? false
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

            // 1. فحص إذا تم تغيير رقم الهاتف
            let isPhoneChanged = !normalizedPhone.isEmpty && (normalizedPhone != oldStoredPhone)

            // 2. فحص إذا تم تغيير حالة الوفاة
            let isDeceasedChanged = (isDeceased && !(member.isDeceased ?? false))

            if isDeceasedChanged {
                await adminRequestVM.requestDeceasedStatus(memberId: member.id, deathDate: deathDate)
            }

            if isPhoneChanged {
                await adminRequestVM.requestPhoneNumberChange(memberId: member.id, newPhoneNumber: normalizedPhone)
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
            Color.black.ignoresSafeArea()
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
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .padding()
            }

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(30))
                        .foregroundStyle(.white, .black.opacity(0.35))
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(DS.Font.scaled(30))
                        .foregroundStyle(DS.Color.error, .black.opacity(0.35))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}
