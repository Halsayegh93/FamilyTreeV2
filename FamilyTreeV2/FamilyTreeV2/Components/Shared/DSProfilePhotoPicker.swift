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
    /// ظهور الصورة للأعضاء (صورة صاحب الحساب فقط) — nil = بلا قسم «الخصوصية» في مربّع خيارات الصورة
    var photoHidden: Bool? = nil
    /// حفظ ظهور الصورة (نفس نداء الإعدادات `updatePhotoHidden`) — يرجع true عند النجاح
    var onSavePhotoHidden: ((Bool) async -> Bool)? = nil

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
        // «خيارات الصورة» — مربّع أوامر موحّد بدل قائمة النظام (طلب المالك ٢٠٢٦-١١-١٠ «التصاميم مو موحدة»)
        .dsCenterBox(isPresented: $showChangeOptions, onBackgroundTap: { showChangeOptions = false }) {
            photoOptionsBox
        }
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
    }

    // MARK: - مربّع «خيارات الصورة»

    /// الأوامر نفسها التي كانت في قائمة النظام: تعديل (قصّ) · تغيير · حذف — و«الخصوصية» لصورة صاحب الحساب
    private var photoOptionsBox: some View {
        let local = selectedImage != nil
        let existing = !local ? existingURL.flatMap(URL.init(string:)) : nil
        let canEdit = local ? lastRawImage != nil : (existing != nil && enableCrop)
        let canDelete = local || (existing != nil && onDeleteExisting != nil)
        return DSPhotoOptionsBox(
            canEdit: canEdit,
            deleteAction: canDelete ? {
                afterClose {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if local {
                        withAnimation(DS.Anim.bouncy) {
                            selectedImage = nil
                            pickerItem = nil
                            lastRawImage = nil
                        }
                    } else {
                        onDeleteExisting?()
                    }
                }
            } : nil,
            photoHidden: photoHidden,
            onSavePhotoHidden: onSavePhotoHidden,
            onEdit: {
                afterClose {
                    if local {
                        if let raw = lastRawImage { rawPickedImage = raw; showCropper = true }
                    } else if let existing {
                        downloadAndEdit(from: existing)
                    }
                }
            },
            onChange: { afterClose { showPicker = true } },
            onClose: { showChangeOptions = false }
        )
    }

    /// يغلق المربّع ثم ينفّذ الأمر بعد خروجه — نافذة واحدة في كل مرّة (المنتقي والقصّ نوافذ أخرى)
    private func afterClose(_ action: @escaping () -> Void) {
        showChangeOptions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration + 0.15, execute: action)
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


/// مربّع «خيارات الصورة» — نفس مربّعات الأوامر في الملف (الأم، الزوجة): صفوف أوامر (`DSCommandRow`)،
/// و«حذف الصورة» سطراً أحمر هادئاً أسفل المربّع، و(لصورة صاحب الحساب) قسم «الخصوصية» بـ«حفظ» / «إلغاء»
struct DSPhotoOptionsBox: View {
    let canEdit: Bool
    let deleteAction: (() -> Void)?
    let photoHidden: Bool?
    let onSavePhotoHidden: ((Bool) async -> Bool)?
    let onEdit: () -> Void
    let onChange: () -> Void
    let onClose: () -> Void

    @ObservedObject private var network = NetworkMonitor.shared
    @State private var hidden = false
    @State private var loaded = false
    @State private var isSaving = false
    @State private var failed = false

    private var hasPrivacy: Bool { photoHidden != nil && onSavePhotoHidden != nil }
    private var privacyChanged: Bool { hasPrivacy && hidden != (photoHidden ?? false) }

    var body: some View {
        DSComposer(
            title: L10n.t("خيارات الصورة", "Photo Options"),
            subtitle: hasPrivacy ? L10n.t("الصورة وظهورها للأعضاء", "The photo and who sees it")
                                 : L10n.t("الصورة الشخصية", "Profile photo"),
            icon: "camera.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            showsAction: hasPrivacy,
            canSubmit: privacyChanged && !isSaving && network.isConnected,
            isBusy: isSaving,
            note: hasPrivacy && !network.isConnected ? L10n.t("لا يمكن الحفظ بدون اتصال", "Can't save while offline") : nil,
            hasUnsavedChanges: privacyChanged,
            extraActions: deleteAction.map { action in
                [DSComposerAction(id: "delete-photo", title: L10n.t("حذف", "Delete"), icon: "trash",
                                  role: .destructive, action: action)]
            } ?? [],
            extraInline: true,
            onSubmit: save,
            onCancel: onClose
        ) {
            VStack(spacing: DSBox.sectionSpacing) {
                if hasPrivacy {
                    // مربّع بقسمين: كل قسم بعنوانه الموحّد
                    DSComposerSection(title: L10n.t("الصورة", "Photo"), icon: "camera.fill",
                                      tint: DS.Color.primary, index: 0) { commands }
                } else {
                    commands
                }
                if hasPrivacy {
                    DSComposerSection(title: L10n.t("الخصوصية", "Privacy"), icon: "lock.fill",
                                      tint: DS.Color.primary, index: 1) {
                        DSVisibilityPicker(
                            hidden: $hidden,
                            shownLine: L10n.t("تظهر صورتك لأعضاء العائلة.", "Your photo is shown to family members."),
                            hiddenLine: L10n.t("لا تظهر صورتك للأعضاء، وتبقى ظاهرة لك وللإدارة.",
                                               "Members won't see your photo; you and the admins still do."),
                            rowTitle: L10n.t("الصورة الشخصية", "Profile photo"), feminine: true)
                    }
                }
                if failed {
                    DSNoteCard(L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save, please try again."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
        .onAppear { if !loaded { loaded = true; hidden = photoHidden ?? false } }
    }

    private var commands: some View {
        VStack(spacing: DS.Spacing.sm) {
            if canEdit {
                DSCommandRow(title: L10n.t("تعديل الصورة", "Edit Photo"), icon: "crop",
                             hint: L10n.t("قص الصورة الحالية", "Crop the current photo"), action: onEdit)
            }
            DSCommandRow(title: L10n.t("تغيير الصورة", "Change Photo"), icon: "photo.on.rectangle",
                         hint: L10n.t("اختيار صورة من الجهاز", "Pick a photo from the device"), action: onChange)
        }
    }

    private func save() {
        guard let onSavePhotoHidden, !isSaving, NetworkMonitor.shared.requireOnline() else { return }
        isSaving = true
        failed = false
        Task {
            let ok = await onSavePhotoHidden(hidden)
            isSaving = false
            if ok { onClose() } else { failed = true }
        }
    }
}
