import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
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
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var localPreviewImage: UIImage? = nil
    @State private var showPhotoPicker: Bool = false



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

                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(
                                title: L10n.t("المعلومات الشخصية", "Personal Info"),
                                icon: "person.text.rectangle"
                            )

                            DSCard(padding: 0) {
                                VStack(spacing: 0) {
                                    

                                    modernTextField(label: L10n.t("الاسم الكامل", "Full Name"), text: $fullName, icon: "person.fill", placeholder: L10n.t("أدخل الاسم الرباعي", "Enter full name"))
                                    DSDivider()
                                    modernPhoneField

                                    DSDivider()
                                    modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 3. حالة الزواج والوفاة
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(
                                title: L10n.t("الحالة الاجتماعية", "Status"),
                                icon: "heart.text.square"
                            )

                            DSCard(padding: 0) {
                                VStack(spacing: 0) {
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
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // 4. زر الحفظ (تصميم عائم)
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
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _ in handleImageChange(selectedItem) }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - المكونات المصممة (Custom Components)

    private var imagePickerHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            Button(action: { showPhotoPicker = true }) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        if let uiImage = localPreviewImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                        } else if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill().frame(width: 80, height: 80).clipped()
                                } else if phase.error != nil {
                                    Circle().fill(DS.Color.surface)
                                        .frame(width: 80, height: 80)
                                        .overlay(Image(systemName: "person.fill").font(DS.Font.scaled(30)).foregroundColor(DS.Color.textTertiary))
                                } else {
                                    ZStack {
                                        Circle().fill(DS.Color.surface)
                                        ProgressView()
                                    }
                                    .frame(width: 80, height: 80)
                                }
                            }
                        } else {
                            Circle().fill(DS.Color.surface)
                                .frame(width: 80, height: 80)
                                .overlay(Image(systemName: "person.fill").font(DS.Font.scaled(30)).foregroundColor(DS.Color.textTertiary))
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    // Gradient ring around avatar
                    .overlay(
                        Circle()
                            .stroke(DS.Color.gradientPrimary, lineWidth: 3)
                    )
                    .dsGlowShadow()

                    // Camera button with gradient background
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 28, height: 28)

                        Image(systemName: "camera.fill")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .overlay(Circle().stroke(DS.Color.surface, lineWidth: 2))
                    .languageHorizontalOffset(8, y: 8)
                }
            }
            Text(L10n.t("تغيير الصورة الشخصية", "Change Profile Photo"))
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.primary)
        }
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

    private var saveButton: some View {
        let newStoredPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
        let isPhoneValid = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newStoredPhone != nil

        return DSPrimaryButton(
            L10n.t("حفظ التغييرات", "Save Changes"),
            isLoading: authVM.isLoading,
            action: saveChangesAction
        )
        .disabled(fullName.isEmpty || authVM.isLoading || !isPhoneValid)
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
                await authVM.requestDeceasedStatus(memberId: member.id, deathDate: deathDate)
            }

            if isPhoneChanged {
                await authVM.requestPhoneNumberChange(memberId: member.id, newPhoneNumber: normalizedPhone)
            }

            await authVM.updateMemberData(
                memberId: member.id,
                fullName: fullName,
                phoneNumber: member.phoneNumber ?? "", // نرسل الرقم القديم لأنه لم يتغير أو تم طلب تغييره
                birthDate: birthDate,
                isMarried: isMarried,
                isDeceased: member.isDeceased ?? false, // نرسل الحالة القديمة لأنها لم تتغير أو تم طلبها
                deathDate: member.isDeceased ?? false ? deathDate : nil,
                isPhoneHidden: isPhoneHidden
            )
            dismiss()
        }
    }

    private func handleImageChange(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self), let uiImg = UIImage(data: data) else { return }
            await MainActor.run { withAnimation { self.localPreviewImage = uiImg } }
            await authVM.uploadAvatar(image: uiImg, for: member.id)
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
                AsyncImage(url: url) { phase in
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
