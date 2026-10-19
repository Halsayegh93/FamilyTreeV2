import SwiftUI
import PhotosUI

/// Reusable profile photo picker component with crop integration.
/// لا يحتاج إذن `Photos` — `PhotosPicker` (iOS 16+) يفتح اختياراً مستقلاً
/// ما يطلب وصول لمكتبة الصور بالكامل.
/// Handles empty state, loading, preview, existing URL, and optional cropping.
struct DSProfilePhotoPicker: View {
    @Environment(\.dsSection) private var dsSectionEnv
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
    /// When true, hides the pill buttons row under the photo. الإجراءات تظهر فقط
    /// عبر زر الكاميرا الصغير على زاوية الصورة (يفتح نفس قائمة الخيارات).
    var useOverlayActionsOnly: Bool = false
    /// قطر الصورة الدائرية/المربعة — الافتراضي 110 (يمكن تصغيره للعرض المدمج بصف واحد)
    var avatarSize: CGFloat = DS.Icon.profileAvatarRing

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var isLoading = false
    @State private var rawPickedImage: UIImage? = nil
    @State private var showCropper = false
    @State private var showPicker = false
    @State private var showChangeOptions = false
    /// Stores the last raw (uncropped) image so user can re-edit crop
    @State private var lastRawImage: UIImage? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            if showCropper, let _ = rawPickedImage {
                // Inline crop indicator
                // التحميل الواحد: مجسّم القسم يتنفّس + نص قصير (بمساحة الصورة نفسها)
                DSPageLoader(L10n.t("جاري فتح المحرر...", "Opening editor..."), fillsSpace: false)
                    .frame(maxWidth: .infinity, minHeight: avatarSize)
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
        .onChange(of: pickerItem) { newItem in
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
    }

    /// شارة الكاميرا فوق الصورة — تفتح خيارات الصورة (قرص بتعبئة القسم وحلقة بلون الخلفية)
    private var cameraBadge: some View {
        Image(systemName: "camera.fill")
            .dsGlyph(DS.Glyph.sm)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Icon.row, height: DS.Icon.row)
            .background(DS.Color.primary.dsChromeFill(in: dsSectionEnv))
            .clipShape(Circle())
            .overlay(Circle().stroke(DS.Color.background, lineWidth: DS.Border.ring))
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
                        .overlay(Circle().stroke(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.ring))
                        .dsGlowShadow()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .stroke(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.ring)
                        )
                        .dsGlowShadow()
                }

                // أيقونة الكاميرا — تفتح قائمة الخيارات (تعديل/تغيير/حذف)
                Button {
                    showChangeOptions = true
                } label: {
                    cameraBadge
                }
            }

            // أزرار تعديل وتغيير وحذف (مخفيّة في useOverlayActionsOnly)
            if !useOverlayActionsOnly {
            HStack(spacing: DS.Spacing.md) {
                // تعديل الصورة (إعادة القص)
                if enableCrop, lastRawImage != nil {
                    DSChipButton(L10n.t("تعديل", "Edit"), icon: "crop", tint: DS.Color.info) {
                        rawPickedImage = lastRawImage
                        showCropper = true
                    }
                }

                // تغيير الصورة (اختيار جديدة)
                DSChipButton(L10n.t("تغيير", "Change"), icon: "arrow.triangle.2.circlepath.camera") {
                    showPicker = true
                }

                // حذف الصورة
                DSChipButton(L10n.t("حذف", "Delete"), icon: "trash.fill", tint: DS.Color.error) {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(DS.Anim.bouncy) {
                        selectedImage = nil
                        pickerItem = nil
                        lastRawImage = nil
                    }
                }
            }
            } // إغلاق if !useOverlayActionsOnly
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
                showPicker = true
            }

            Button(L10n.t("حذف الصورة", "Delete Photo"), role: .destructive) {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(DS.Anim.bouncy) {
                    selectedImage = nil
                    pickerItem = nil
                    lastRawImage = nil
                }
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
                                .overlay(Circle().stroke(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.ring))
                                .dsGlowShadow()
                        } else {
                            image.resizable().scaledToFill()
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                        .stroke(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.ring)
                                )
                                .dsGlowShadow()
                        }
                    } else if phase.error != nil {
                        emptyCirclePlaceholder
                    } else {
                        ProgressView().tint(DS.Color.primary.dsChrome(in: dsSectionEnv))
                            .frame(width: avatarSize, height: avatarSize)
                    }
                }

                // أيقونة الكاميرا — تفتح قائمة الخيارات (تعديل/تغيير/حذف)
                Button {
                    showChangeOptions = true
                } label: {
                    cameraBadge
                }
            }

            // أزرار تعديل وتغيير وحذف (مخفيّة في useOverlayActionsOnly)
            if !useOverlayActionsOnly {
            HStack(spacing: DS.Spacing.md) {
                // تعديل الصورة (تحميل من URL ثم قص)
                if enableCrop {
                    DSChipButton(L10n.t("تعديل", "Edit"), icon: "crop", tint: DS.Color.info, isLoading: isDownloadingForEdit) {
                        downloadAndEdit(from: url)
                    }
                }

                // تغيير الصورة (اختيار جديدة)
                DSChipButton(L10n.t("تغيير", "Change"), icon: "arrow.triangle.2.circlepath.camera") {
                    showPicker = true
                }

                if let onDeleteExisting {
                    DSChipButton(L10n.t("حذف", "Delete"), icon: "trash.fill", tint: DS.Color.error) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onDeleteExisting()
                    }
                }
            }
            } // إغلاق if !useOverlayActionsOnly
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
                showPicker = true
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
                // الصور الخاصة: رابط موقَّع إن أمكن (وإلا الأصلي)
                let fetchURL = await StorageURLResolver.shared.displayURL(for: url)
                let (data, _) = try await URLSession.shared.data(from: fetchURL)
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
        // التحميل الواحد: مجسّم القسم يتنفّس + نص قصير (بمساحة الصورة نفسها)
        DSPageLoader(L10n.t("جاري تحميل الصورة...", "Loading photo..."), fillsSpace: false)
            .frame(maxWidth: .infinity, minHeight: avatarSize)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            // وضع overlay: زر كاميرا على الدائرة (يستخدم في الإدارة + compact)
            if compactEmptyState || useOverlayActionsOnly {
                Button {
                    showPicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        emptyCirclePlaceholder

                        // أيقونة الكاميرا
                        cameraBadge
                    }
                }
                .buttonStyle(DSScaleButtonStyle())

                if let trailing {
                    Text(trailing)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
            } else {
                // الوضع العادي: دائرة + زر اختيار تحتها
                emptyCirclePlaceholder

                DSChipButton(L10n.t("اختر صورة", "Choose Photo"), icon: "arrow.triangle.2.circlepath.camera") {
                    showPicker = true
                }

                if let trailing {
                    Text(trailing)
                        .dsFont(.footnote)
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
                    .fill(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(0.06))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(Circle().stroke(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(DS.Opacity.tintFill), style: StrokeStyle(lineWidth: DS.Border.width * 2, dash: [DS.Spacing.sm])))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(0.06))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .stroke(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(DS.Opacity.tintFill), style: StrokeStyle(lineWidth: DS.Border.width * 2, dash: [DS.Spacing.sm]))
                    )
            }

            Image(systemName: cropShape == .circle ? "person.fill" : "photo.fill")
                .font(DS.Glyph.font(DS.Glyph.placeholder, weight: .light))
                .foregroundColor(DS.Color.primary.dsChrome(in: dsSectionEnv).opacity(0.25))
        }
    }

    // MARK: - Image Loading

    private func loadImage(from item: PhotosPickerItem) {
        Task {
            await MainActor.run { isLoading = true }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                // تصفير الاختيار حتى يعمل onChange عند اختيار نفس الصورة مجدداً
                await MainActor.run {
                    isLoading = false
                    pickerItem = nil
                }
                return
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            await MainActor.run {
                isLoading = false
                pickerItem = nil
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
