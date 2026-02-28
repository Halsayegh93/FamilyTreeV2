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

    // Gallery photos states
    @State private var galleryPhotos: [MemberGalleryPhoto] = []
    @State private var selectedGalleryItems: [PhotosPickerItem] = []
    @State private var showGalleryPicker: Bool = false
    @State private var selectedPreviewPhoto: MemberGalleryPhoto? = nil
    @State private var showGalleryViewer = false
    @State private var pendingDeletePhoto: MemberGalleryPhoto? = nil
    @State private var isViewingLegacyPhoto = false
    @State private var legacyGalleryPhotoURL: String? = nil
    @State private var showDeleteLegacyPhotoAlert = false

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

                        VStack(spacing: DS.Spacing.xl) {
                            // 2. بطاقة المعلومات الأساسية
                            modernSection(title: L10n.t("المعلومات الشخصية", "Personal Info"), icon: "person.text.rectangle") {
                                VStack(spacing: 0) {
                                    modernTextField(label: L10n.t("الاسم الكامل", "Full Name"), text: $fullName, icon: "person.fill", placeholder: L10n.t("أدخل الاسم الرباعي", "Enter full name"))
                                    customDivider
                                    modernPhoneField
                                        
                                    if member.id == authVM.currentUser?.id {
                                        customDivider
                                        HStack {
                                            ZStack {
                                                Circle().fill(DS.Color.primary.opacity(0.1))
                                                    .frame(width: 32, height: 32)
                                                Image(systemName: "eye.slash.fill")
                                                    .font(DS.Font.scaled(12, weight: .semibold))
                                                    .foregroundColor(DS.Color.primary)
                                            }
                                            Toggle(L10n.t("إخفاء رقم الهاتف عن الآخرين", "Hide phone number from others"), isOn: $isPhoneHidden)
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textSecondary)
                                                .tint(DS.Color.primary)
                                        }
                                        .padding(.horizontal, DS.Spacing.lg)
                                        .padding(.vertical, DS.Spacing.sm)
                                    }
                                    customDivider
                                    modernDatePicker(label: L10n.t("تاريخ الميلاد", "Birth Date"), selection: $birthDate, icon: "calendar")
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.xl)

                        // 3. حالة الزواج والوفاة
                        VStack(spacing: DS.Spacing.xl) {
                            modernSection(title: L10n.t("الحالة الاجتماعية", "Status"), icon: "heart.text.square") {
                                VStack(spacing: 0) {
                                    HStack {
                                        ZStack {
                                            Circle().fill(DS.Color.primary.opacity(0.1))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: "heart.fill")
                                                .font(DS.Font.scaled(12, weight: .semibold))
                                                .foregroundColor(DS.Color.primary)
                                        }
                                        Toggle(L10n.t("متزوج", "Married"), isOn: $isMarried)
                                            .font(DS.Font.callout)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .tint(DS.Color.primary)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.sm)

                                    customDivider

                                    HStack {
                                        ZStack {
                                            Circle().fill(Color.gray.opacity(0.1))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: "leaf.fill")
                                                .font(DS.Font.scaled(12, weight: .semibold))
                                                .foregroundColor(.gray)
                                        }
                                        Toggle(L10n.t("متوفى", "Deceased"), isOn: $isDeceased)
                                            .font(DS.Font.callout)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .tint(.gray)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.sm)

                                    if isDeceased {
                                        customDivider
                                        modernDatePicker(label: L10n.t("تاريخ الوفاة", "Death Date"), selection: $deathDate, icon: "calendar.badge.clock")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.xl)

                        // 4. قسم صور المعرض
                        if member.id == authVM.currentUser?.id {
                            galleryPhotosSection
                                .padding(.horizontal, DS.Spacing.xl)
                        }

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
                Task { await refreshGalleryPhotos() }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _ in handleImageChange(selectedItem) }
            .photosPicker(isPresented: $showGalleryPicker, selection: $selectedGalleryItems, maxSelectionCount: 10, matching: .images)
            .onChange(of: selectedGalleryItems) { _, newItems in handleGalleryImagesChange(newItems) }
            .alert(L10n.t("حذف الصورة", "Delete Photo"), isPresented: Binding(
                get: { pendingDeletePhoto != nil },
                set: { if !$0 { pendingDeletePhoto = nil } }
            )) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingDeletePhoto = nil }
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task { await deleteGalleryPhoto(pendingDeletePhoto) }
                }
            } message: {
                Text(L10n.t("هل تريد حذف هذه الصورة من المعرض؟", "Delete this photo from gallery?"))
            }
            .alert(L10n.t("حذف الصورة", "Delete Photo"), isPresented: $showDeleteLegacyPhotoAlert) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task { await deleteLegacyGalleryPhoto() }
                }
            } message: {
                Text(L10n.t("هل تريد حذف الصورة القديمة من المعرض؟", "Delete legacy photo from gallery?"))
            }
            .fullScreenCover(isPresented: $showGalleryViewer) {
                if let selectedPreviewPhoto {
                    GalleryPhotoViewer(
                        photoURL: selectedPreviewPhoto.photoURL,
                        onClose: { showGalleryViewer = false },
                        onDelete: {
                            if isViewingLegacyPhoto {
                                showDeleteLegacyPhotoAlert = true
                            } else {
                                pendingDeletePhoto = selectedPreviewPhoto
                            }
                            showGalleryViewer = false
                        }
                    )
                }
            }
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

    private func modernSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(14, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
                Text(title)
                    .font(DS.Font.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xs)

            VStack(spacing: 0) {
                content()
            }
            .glassCard()
        }
    }

    private func modernTextField(label: String, text: Binding<String>, icon: String, placeholder: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle().fill(DS.Color.primary.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
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
            ZStack {
                Circle().fill(DS.Color.primary.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: "phone.fill")
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }

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
        HStack {
            ZStack {
                Circle().fill(DS.Color.primary.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
            }
            Text(label)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            DatePicker("", selection: selection, in: ...Date(), displayedComponents: .date).labelsHidden()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var saveButton: some View {
        let newStoredPhone = KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
        let oldStoredPhone = KuwaitPhone.normalizeForStorageFromInput(member.phoneNumber) ?? ""
        let isPhoneChanged = (newStoredPhone?.isEmpty == false) && ((newStoredPhone ?? "") != oldStoredPhone)
        let isDeceasedChanged = (isDeceased && !(member.isDeceased ?? false))
        let needsApproval = isPhoneChanged || isDeceasedChanged
        let isPhoneValid = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newStoredPhone != nil

        return Button(action: saveChangesAction) {
            HStack(spacing: DS.Spacing.sm) {
                if authVM.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(L10n.t("حفظ التغييرات", "Save Changes"))
                }
            }
            .font(DS.Font.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Group {
                    if fullName.isEmpty {
                        LinearGradient(colors: [Color.gray, Color.gray.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    } else if needsApproval {
                        LinearGradient(colors: [DS.Color.warning, DS.Color.warning.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                    } else {
                        DS.Color.gradientPrimary
                    }
                }
            )
            .cornerRadius(DS.Radius.lg)
            .dsGlowShadow()
        }
        .disabled(fullName.isEmpty || authVM.isLoading || !isPhoneValid)
        .padding(.horizontal, DS.Spacing.xl)
    }

    private var customDivider: some View {
        DSDivider()
            .padding(.leading, DS.Spacing.xxxl)
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

    // MARK: - Gallery Photos Section
    private var galleryPhotosSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.Font.scaled(14, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
                Text(L10n.t("صور المعرض", "Gallery Photos"))
                    .font(DS.Font.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xs)

            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {
                    Button(action: { showGalleryPicker = true }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .fill(DS.Color.surface)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                        .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                )
                            VStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "photo.badge.plus")
                                    .font(DS.Font.scaled(20))
                                    .foregroundColor(DS.Color.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(galleryPhotos) { photo in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                isViewingLegacyPhoto = false
                                selectedPreviewPhoto = photo
                                showGalleryViewer = true
                            } label: {
                                AsyncImage(url: URL(string: photo.photoURL)) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipped()
                                    } else {
                                        ZStack { DS.Color.surface; ProgressView() }
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fill)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            
                            // Inline Easy Delete Button
                            Button {
                                pendingDeletePhoto = photo
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(DS.Font.scaled(20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, DS.Color.error)
                                    .background(Circle().fill(.white).frame(width: 18, height: 18))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if galleryPhotos.isEmpty, let legacyURL = legacyGalleryPhotoURL {
                        ZStack(alignment: .topTrailing) {
                            Button {
                                if let legacyPhoto = legacyPreviewPhoto(url: legacyURL) {
                                    isViewingLegacyPhoto = true
                                    selectedPreviewPhoto = legacyPhoto
                                    showGalleryViewer = true
                                }
                            } label: {
                                AsyncImage(url: URL(string: legacyURL)) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipped()
                                    } else {
                                        ZStack { DS.Color.surface; ProgressView() }
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fill)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            
                            // Inline Easy Delete Button (Legacy)
                            Button {
                                showDeleteLegacyPhotoAlert = true
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(DS.Font.scaled(20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, DS.Color.error)
                                    .background(Circle().fill(.white).frame(width: 18, height: 18))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(DS.Spacing.lg)

                if galleryPhotos.isEmpty, legacyGalleryPhotoURL == nil {
                    Text(L10n.t("لا توجد صور حالياً", "No photos yet"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, DS.Spacing.lg)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Gallery Logic
    private func handleGalleryImagesChange(_ items: [PhotosPickerItem]) {
        Task {
            guard !items.isEmpty else { return }
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImg = UIImage(data: data) else { continue }
                _ = await authVM.uploadMemberGalleryPhotoMulti(image: uiImg, for: member.id)
            }
            await MainActor.run { self.selectedGalleryItems = [] }
            await refreshGalleryPhotos()
        }
    }

    private func deleteGalleryPhoto(_ photo: MemberGalleryPhoto?) async {
        guard let photo else { return }
        let success = await authVM.deleteMemberGalleryPhotoMulti(photoId: photo.id, photoURL: photo.photoURL)
        guard success else { return }
        await MainActor.run {
            self.pendingDeletePhoto = nil
            if self.selectedPreviewPhoto?.id == photo.id { self.selectedPreviewPhoto = nil }
        }
        await refreshGalleryPhotos()
    }

    private func refreshGalleryPhotos() async {
        let photos = await authVM.fetchMemberGalleryPhotos(for: member.id)
        await MainActor.run {
            self.galleryPhotos = photos
            self.legacyGalleryPhotoURL = photos.isEmpty ? member.photoURL : nil
        }
    }

    private func deleteLegacyGalleryPhoto() async {
        let success = await authVM.deleteMemberGalleryPhoto(for: member.id)
        guard success else { return }
        await MainActor.run {
            self.showDeleteLegacyPhotoAlert = false
            self.legacyGalleryPhotoURL = nil
            if self.isViewingLegacyPhoto {
                self.selectedPreviewPhoto = nil
                self.isViewingLegacyPhoto = false
            }
        }
    }

    private func legacyPreviewPhoto(url: String) -> MemberGalleryPhoto? {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return MemberGalleryPhoto(id: UUID(), memberId: member.id, photoURL: url, createdAt: nil)
    }
}

struct GalleryPhotoViewer: View {
    let photoURL: String
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var zoomScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = min(max(value, 1), 4)
                                    }
                                    .onEnded { _ in
                                        if zoomScale < 1 { zoomScale = 1 }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    zoomScale = zoomScale > 1 ? 1 : 2
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
                        .foregroundStyle(.red, .black.opacity(0.35))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}
