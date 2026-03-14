import SwiftUI
import PhotosUI
import Photos

/// Reusable profile photo picker component with crop integration.
/// Handles empty state, loading, preview, existing URL, and optional cropping.
struct DSProfilePhotoPicker: View {
    /// The selected/cropped UIImage (binding to parent)
    @Binding var selectedImage: UIImage?
    /// Optional existing avatar URL to display when no local image is selected
    var existingURL: String? = nil
    /// Whether to show the crop editor after selection
    var enableCrop: Bool = true
    /// Crop shape (circle or square)
    var cropShape: ImageCropperView.CropShape = .circle
    /// Section title
    var title: String = L10n.t("الصورة الشخصية", "Profile Photo")
    /// Trailing text (e.g. "Optional")
    var trailing: String? = L10n.t("اختياري", "Optional")
    /// Whether to show delete button for existing URL photos
    var showDeleteForExisting: Bool = false
    /// Called when user wants to delete the existing photo
    var onDeleteExisting: (() -> Void)? = nil
    /// When true, empty state shows only a tappable circle with camera overlay (no button below)
    var compactEmptyState: Bool = false

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var isLoading = false
    @State private var rawPickedImage: UIImage? = nil
    @State private var showCropper = false
    @State private var showPermissionDenied = false
    @State private var showPicker = false
    @State private var showChangeOptions = false
    /// Stores the last raw (uncropped) image so user can re-edit crop
    @State private var lastRawImage: UIImage? = nil

    private let avatarSize: CGFloat = 110

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            if showCropper, let _ = rawPickedImage {
                // Inline crop indicator
                VStack(spacing: DS.Spacing.md) {
                    ProgressView().tint(DS.Color.primary)
                        .frame(width: avatarSize, height: avatarSize)
                    Text(L10n.t("جاري فتح المحرر...", "Opening editor..."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
            } else if let image = selectedImage {
                selectedImagePreview(image)
            } else if isLoading {
                loadingState
            } else if let urlStr = existingURL, let url = URL(string: urlStr) {
                existingImagePreview(url)
            } else {
                emptyState
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            loadImage(from: newItem)
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $showCropper) {
            if let rawImage = rawPickedImage {
                ImageCropperView(
                    image: rawImage,
                    cropShape: cropShape,
                    onCrop: { cropped in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        // Save the raw image for re-editing later
                        if lastRawImage == nil {
                            lastRawImage = rawImage
                        }
                        withAnimation(DS.Anim.bouncy) {
                            selectedImage = cropped
                        }
                        showCropper = false
                        rawPickedImage = nil
                    },
                    onCancel: {
                        showCropper = false
                        rawPickedImage = nil
                    }
                )
            }
        }
        .alert(
            L10n.t("الوصول للصور مطلوب", "Photo Access Required"),
            isPresented: $showPermissionDenied
        ) {
            Button(L10n.t("فتح الإعدادات", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "يحتاج التطبيق إذن الوصول لمكتبة الصور لاختيار صورة. يرجى السماح من الإعدادات.",
                "The app needs access to your photo library to select a photo. Please allow access in Settings."
            ))
        }
        .onAppear {
            requestPhotoPermission()
        }
    }

    // MARK: - Photo Permission

    private func requestPhotoPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
        }
    }

    private func checkPermissionAndProceed(action: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            action()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        action()
                    } else {
                        showPermissionDenied = true
                    }
                }
            }
        default:
            showPermissionDenied = true
        }
    }

    // MARK: - Selected Image Preview

    private func selectedImagePreview(_ image: UIImage) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                // المعاينة بنفس شكل القص
                if cropShape == .circle {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.primary.opacity(0.15), lineWidth: 2.5))
                        .dsGlowShadow()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.15), lineWidth: 2.5)
                        )
                        .dsGlowShadow()
                }

                // أيقونة الكاميرا
                Button {
                    showChangeOptions = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 32, height: 32)
                        .background(DS.Color.primary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.background, lineWidth: 2.5))
                }
            }

            // أزرار تعديل وتغيير وحذف
            HStack(spacing: DS.Spacing.md) {
                // تعديل الصورة (إعادة القص)
                if enableCrop, lastRawImage != nil {
                    Button {
                        rawPickedImage = lastRawImage
                        showCropper = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "crop")
                                .font(DS.Font.scaled(12, weight: .bold))
                            Text(L10n.t("تعديل", "Edit"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.info)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.info.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }

                // تغيير الصورة (اختيار جديدة)
                Button {
                    checkPermissionAndProceed { showPicker = true }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(L10n.t("تغيير", "Change"))
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }

                // حذف الصورة
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(DS.Anim.bouncy) {
                        selectedImage = nil
                        pickerItem = nil
                        lastRawImage = nil
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "trash.fill")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(L10n.t("حذف", "Delete"))
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(DS.Color.error)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.error.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            L10n.t("خيارات الصورة", "Photo Options"),
            isPresented: $showChangeOptions,
            titleVisibility: .visible
        ) {
            Button(L10n.t("تعديل الصورة", "Edit Photo")) {
                if let raw = lastRawImage {
                    rawPickedImage = raw
                    showCropper = true
                }
            }
            .disabled(lastRawImage == nil)
            
            Button(L10n.t("تغيير الصورة", "Change Photo")) {
                checkPermissionAndProceed { showPicker = true }
            }
            
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - Existing Image Preview

    @State private var isDownloadingForEdit = false

    private func existingImagePreview(_ url: URL) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncPhaseImage(url: url) { phase in
                    if let image = phase.image {
                        if cropShape == .circle {
                            image.resizable().scaledToFill()
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(DS.Color.primary.opacity(0.15), lineWidth: 2.5))
                                .dsGlowShadow()
                        } else {
                            image.resizable().scaledToFill()
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                        .stroke(DS.Color.primary.opacity(0.15), lineWidth: 2.5)
                                )
                                .dsGlowShadow()
                        }
                    } else if phase.error != nil {
                        emptyCirclePlaceholder
                    } else {
                        ProgressView().tint(DS.Color.primary)
                            .frame(width: avatarSize, height: avatarSize)
                    }
                }

                // أيقونة الكاميرا
                Button {
                    showChangeOptions = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 32, height: 32)
                        .background(DS.Color.primary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.background, lineWidth: 2.5))
                }
            }

            // أزرار تعديل وتغيير وحذف
            HStack(spacing: DS.Spacing.md) {
                // تعديل الصورة (تحميل من URL ثم قص)
                if enableCrop {
                    Button {
                        downloadAndEdit(from: url)
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            if isDownloadingForEdit {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(DS.Color.info)
                            } else {
                                Image(systemName: "crop")
                                    .font(DS.Font.scaled(12, weight: .bold))
                            }
                            Text(L10n.t("تعديل", "Edit"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.info)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.info.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .disabled(isDownloadingForEdit)
                }

                // تغيير الصورة (اختيار جديدة)
                Button {
                    checkPermissionAndProceed { showPicker = true }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(L10n.t("تغيير", "Change"))
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }

                if let onDeleteExisting {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onDeleteExisting()
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "trash.fill")
                                .font(DS.Font.scaled(12, weight: .bold))
                            Text(L10n.t("حذف", "Delete"))
                                .font(DS.Font.scaled(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.error.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            L10n.t("خيارات الصورة", "Photo Options"),
            isPresented: $showChangeOptions,
            titleVisibility: .visible
        ) {
            if enableCrop {
                Button(L10n.t("تعديل الصورة", "Edit Photo")) {
                    downloadAndEdit(from: url)
                }
            }
            
            Button(L10n.t("تغيير الصورة", "Change Photo")) {
                checkPermissionAndProceed { showPicker = true }
            }
            
            if onDeleteExisting != nil {
                Button(L10n.t("حذف الصورة", "Delete Photo"), role: .destructive) {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onDeleteExisting?()
                }
            }
            
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
    }

    /// تحميل الصورة من URL ثم فتح محرر القص
    private func downloadAndEdit(from url: URL) {
        guard !isDownloadingForEdit else { return }
        isDownloadingForEdit = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    isDownloadingForEdit = false
                    if let uiImage = UIImage(data: data) {
                        lastRawImage = uiImage
                        rawPickedImage = uiImage
                        showCropper = true
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloadingForEdit = false
                    Log.error("فشل تحميل الصورة للتعديل: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView().tint(DS.Color.primary)
                .frame(width: avatarSize, height: avatarSize)
            Text(L10n.t("جاري تحميل الصورة...", "Loading photo..."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            if compactEmptyState {
                // وضع مختصر: الدائرة مع كاميرا — بدون زر تحتها
                Button {
                    checkPermissionAndProceed { showPicker = true }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        emptyCirclePlaceholder

                        // أيقونة الكاميرا
                        Image(systemName: "camera.fill")
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(width: 32, height: 32)
                            .background(DS.Color.primary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.Color.background, lineWidth: 2.5))
                    }
                }
                .buttonStyle(DSScaleButtonStyle())

                if let trailing {
                    Text(trailing)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
            } else {
                // الوضع العادي: دائرة + زر اختيار
                emptyCirclePlaceholder

                Button {
                    checkPermissionAndProceed { showPicker = true }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(L10n.t("اختر صورة", "Choose Photo"))
                            .font(DS.Font.scaled(13, weight: .bold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(DSBoldButtonStyle())

                if let trailing {
                    Text(trailing)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty Placeholder

    private var emptyCirclePlaceholder: some View {
        ZStack {
            if cropShape == .circle {
                Circle()
                    .fill(DS.Color.primary.opacity(0.06))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(Circle().stroke(DS.Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 2, dash: [8])))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.primary.opacity(0.06))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .stroke(DS.Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
            }

            Image(systemName: cropShape == .circle ? "person.fill" : "photo.fill")
                .font(DS.Font.scaled(40, weight: .light))
                .foregroundColor(DS.Color.primary.opacity(0.25))
        }
    }

    // MARK: - Image Loading

    private func loadImage(from item: PhotosPickerItem) {
        Task {
            await MainActor.run { isLoading = true }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                await MainActor.run { isLoading = false }
                return
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            await MainActor.run {
                isLoading = false
                lastRawImage = uiImage
                if enableCrop {
                    rawPickedImage = uiImage
                    showCropper = true
                } else {
                    withAnimation(DS.Anim.bouncy) {
                        selectedImage = uiImage
                    }
                }
            }
        }
    }
}

// MARK: - Multi-Photo Picker for News

/// Reusable multi-photo picker with Instagram-style carousel and optional crop.
struct DSMultiPhotoPicker: View {
    @Binding var selectedImages: [UIImage]
    var maxCount: Int = 5
    /// Whether to enable cropping for each photo
    var enableCrop: Bool = true
    var cropShape: ImageCropperView.CropShape = .square

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var currentIndex = 0
    @State private var cropQueue: [UIImage] = []
    @State private var cropQueueProcessedCount = 0
    @State private var showCropper = false
    @State private var currentCropImage: UIImage? = nil
    @State private var showPicker = false
    @State private var showPermissionDenied = false

    var body: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الصور", "Photos"),
                icon: "photo.fill",
                trailing: selectedImages.isEmpty ? nil : "\(selectedImages.count)/\(maxCount)",
                iconColor: DS.Color.info
            )

            if selectedImages.isEmpty && !isLoading {
                emptyState
            } else if isLoading {
                loadingState
            } else {
                carouselPreview
                thumbnailStrip
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            loadImages(from: items)
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: maxCount, matching: .images)
        .alert(
            L10n.t("الوصول للصور مطلوب", "Photo Access Required"),
            isPresented: $showPermissionDenied
        ) {
            Button(L10n.t("فتح الإعدادات", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "يحتاج التطبيق إذن الوصول لمكتبة الصور لاختيار صور. يرجى السماح من الإعدادات.",
                "The app needs access to your photo library to select photos. Please allow access in Settings."
            ))
        }
        .onAppear {
            requestPhotoPermission()
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let cropImage = currentCropImage {
                ImageCropperView(
                    image: cropImage,
                    cropShape: cropShape,
                    onCrop: { cropped in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        selectedImages.append(cropped)
                        cropQueueProcessedCount += 1
                        processNextCropItem()
                    },
                    onCancel: {
                        // Skip this image
                        cropQueueProcessedCount += 1
                        processNextCropItem()
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Button {
            checkPermissionAndProceed { showPicker = true }
        } label: {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.Font.scaled(36, weight: .light))
                    .foregroundColor(DS.Color.primary.opacity(0.5))
                Text(L10n.t("اختر صور (اختياري)", "Choose Photos (optional)"))
                    .font(DS.Font.callout)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Color.primary)
                Text(L10n.t("حتى \(maxCount) صور", "Up to \(maxCount) photos"))
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xxl)
            .background(DS.Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                    .foregroundColor(DS.Color.primary.opacity(0.15))
            )
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView().tint(DS.Color.primary)
            Text(L10n.t("جاري تحميل الصور...", "Loading photos..."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Carousel Preview

    private var carouselPreview: some View {
        ZStack(alignment: .top) {
            TabView(selection: $currentIndex) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .tag(idx)
                }
            }
            .aspectRatio(4/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .clipped()
            .tabViewStyle(.page(indexDisplayMode: .never))
            .padding(.horizontal, DS.Spacing.md)

            // العداد + زر الحذف فوق الصورة
            VStack {
                HStack {
                    // زر حذف الصورة
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(DS.Anim.bouncy) {
                            guard currentIndex < selectedImages.count else { return }
                            selectedImages.remove(at: currentIndex)
                            if currentIndex >= selectedImages.count {
                                currentIndex = max(0, selectedImages.count - 1)
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "trash.fill")
                                .font(DS.Font.scaled(12, weight: .bold))
                            Text(L10n.t("حذف", "Delete"))
                                .font(DS.Font.scaled(12, weight: .bold))
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs + 2)
                        .background(DS.Color.error.opacity(0.85))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // عداد الصور
                    if selectedImages.count > 1 {
                        Text("\(currentIndex + 1)/\(selectedImages.count)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.shadowOverlay)
                            .clipShape(Capsule())
                    }
                }
                .padding(DS.Spacing.md)
                .padding(.horizontal, DS.Spacing.md)

                Spacer()
            }
        }
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                    Button {
                        withAnimation { currentIndex = idx }
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(currentIndex == idx ? DS.Color.primary : Color.clear, lineWidth: 2.5)
                            )
                            .opacity(currentIndex == idx ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                }

                if selectedImages.count < maxCount {
                    Button {
                        checkPermissionAndProceed { showPicker = true }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(16, weight: .bold))
                            Text(L10n.t("إضافة", "Add"))
                                .font(DS.Font.scaled(9, weight: .medium))
                        }
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 56, height: 56)
                        .background(DS.Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Image Loading

    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            await MainActor.run { isLoading = true }
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            await MainActor.run {
                isLoading = false
                if enableCrop && !loaded.isEmpty {
                    cropQueue = loaded
                    cropQueueProcessedCount = 0
                    selectedImages = []
                    processNextCropItem()
                } else {
                    withAnimation(DS.Anim.bouncy) {
                        selectedImages = loaded
                        currentIndex = 0
                    }
                }
            }
        }
    }

    private func processNextCropItem() {
        if cropQueueProcessedCount < cropQueue.count {
            currentCropImage = cropQueue[cropQueueProcessedCount]
            showCropper = true
        } else {
            showCropper = false
            currentCropImage = nil
            cropQueue = []
            cropQueueProcessedCount = 0
            currentIndex = 0
        }
    }

    // MARK: - Photo Permission

    private func requestPhotoPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
        }
    }

    private func checkPermissionAndProceed(action: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            action()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        action()
                    } else {
                        showPermissionDenied = true
                    }
                }
            }
        default:
            showPermissionDenied = true
        }
    }
}
