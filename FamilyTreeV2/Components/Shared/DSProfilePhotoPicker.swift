import SwiftUI
import PhotosUI

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
    var cropShape: ImageCropperView.CropShape = .square
    /// Section title
    var title: String = L10n.t("الصورة الشخصية", "Profile Photo")
    /// Trailing text (e.g. "Optional")
    var trailing: String? = L10n.t("اختياري", "Optional")
    /// Whether to show delete button for existing URL photos
    var showDeleteForExisting: Bool = false
    /// Called when user wants to delete the existing photo
    var onDeleteExisting: (() -> Void)? = nil

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var isLoading = false
    @State private var rawPickedImage: UIImage? = nil
    @State private var showCropper = false

    var body: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: title,
                icon: "camera.fill",
                trailing: trailing,
                iconColor: DS.Color.neonPurple
            )

            if showCropper, let _ = rawPickedImage {
                // Inline crop indicator — actual cropper is fullScreenCover
                VStack(spacing: DS.Spacing.md) {
                    ProgressView().tint(DS.Color.primary)
                        .frame(width: 140, height: 140)
                    Text(L10n.t("جاري فتح المحرر...", "Opening editor..."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.lg)
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
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            loadImage(from: newItem)
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let rawImage = rawPickedImage {
                ImageCropperView(
                    image: rawImage,
                    cropShape: cropShape,
                    onCrop: { cropped in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
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
    }

    // MARK: - Selected Image Preview

    private func selectedImagePreview(_ image: UIImage) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.primary.opacity(0.2), lineWidth: 2))
                .dsGlowShadow()

            photoActionBar(onDelete: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(DS.Anim.bouncy) {
                    selectedImage = nil
                    pickerItem = nil
                }
            })
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
    }

    // MARK: - Existing Image Preview

    private func existingImagePreview(_ url: URL) -> some View {
        VStack(spacing: DS.Spacing.md) {
            CachedAsyncPhaseImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.primary.opacity(0.2), lineWidth: 2))
                        .dsGlowShadow()
                } else if phase.error != nil {
                    emptyState
                } else {
                    ProgressView().tint(DS.Color.primary)
                        .frame(width: 140, height: 140)
                }
            }

            photoActionBar(onDelete: showDeleteForExisting ? {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onDeleteExisting?()
            } : nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView().tint(DS.Color.primary)
                .frame(width: 140, height: 140)
            Text(L10n.t("جاري تحميل الصورة...", "Loading photo..."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "person.crop.rectangle.badge.plus")
                    .font(DS.Font.scaled(36, weight: .light))
                    .foregroundColor(DS.Color.primary.opacity(0.5))
                Text(L10n.t("اختر صورة شخصية", "Choose a profile photo"))
                    .font(DS.Font.callout)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Color.primary)
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

    // MARK: - Unified Action Bar

    private func photoActionBar(onDelete: (() -> Void)? = nil) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // زر تغيير الصورة
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(DS.Font.scaled(13, weight: .semibold))
                    Text(L10n.t("تغيير", "Change"))
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                }
                .foregroundColor(DS.Color.primary)
            }

            Spacer()

            // زر حذف الصورة
            if let onDelete {
                Button(action: onDelete) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "trash")
                            .font(DS.Font.scaled(13, weight: .semibold))
                        Text(L10n.t("حذف", "Delete"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(DS.Color.error)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.sm)
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
        PhotosPicker(selection: $pickerItems, maxSelectionCount: maxCount, matching: .images) {
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
                    imageThumb(image: image, index: idx)
                        .tag(idx)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .tabViewStyle(.page(indexDisplayMode: .never))

            if selectedImages.count > 1 {
                HStack {
                    Spacer()
                    Text("\(currentIndex + 1)/\(selectedImages.count)")
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(DS.Spacing.md)
                }
            }
        }
    }

    private func imageThumb(image: UIImage, index: Int) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .clipped()

            // شريط حذف الصورة
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(DS.Anim.bouncy) {
                    selectedImages.remove(at: index)
                    if currentIndex >= selectedImages.count {
                        currentIndex = max(0, selectedImages.count - 1)
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "trash")
                        .font(DS.Font.scaled(13, weight: .semibold))
                    Text(L10n.t("حذف الصورة", "Delete Photo"))
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                }
                .foregroundColor(DS.Color.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
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
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: maxCount, matching: .images) {
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
}
