import SwiftUI
import Combine
import Photos

// MARK: - Photo Library Service

struct PhotoAlbum: Identifiable {
    let id: String
    let title: String
    let collection: PHAssetCollection?
    let count: Int
}

@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var thumbnails: [(asset: PHAsset, image: UIImage)] = []
    @Published var albums: [PhotoAlbum] = []
    @Published var selectedAlbum: PhotoAlbum?
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading = false

    private let imageManager = PHCachingImageManager()
    private let thumbnailSize: CGSize = {
        let scale = UIScreen.main.scale
        let cellWidth = UIScreen.main.bounds.width / 4
        let size = cellWidth * scale
        return CGSize(width: size, height: size)
    }()

    func requestAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status

        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    self?.authorizationStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        self?.loadAlbums()
                        self?.fetchPhotos()
                    }
                }
            }
        } else if status == .authorized || status == .limited {
            loadAlbums()
            fetchPhotos()
        }
    }

    func loadAlbums() {
        var list: [PhotoAlbum] = []

        // كل الصور
        let allCount = PHAsset.fetchAssets(with: .image, options: nil).count
        let allAlbum = PhotoAlbum(id: "all", title: L10n.t("الكل", "All Photos"), collection: nil, count: allCount)
        list.append(allAlbum)

        // ألبومات ذكية (المفضلة، سكرينشوت، سيلفي، إلخ)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            guard assets.count > 0 else { return }
            let title = collection.localizedTitle ?? ""
            list.append(PhotoAlbum(id: collection.localIdentifier, title: title, collection: collection, count: assets.count))
        }

        // ألبومات المستخدم
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            guard assets.count > 0 else { return }
            let title = collection.localizedTitle ?? ""
            list.append(PhotoAlbum(id: collection.localIdentifier, title: title, collection: collection, count: assets.count))
        }

        albums = list
        selectedAlbum = allAlbum
    }

    func fetchPhotos(from album: PhotoAlbum? = nil) {
        isLoading = true
        thumbnails = []

        if let album { selectedAlbum = album }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // بدون حد — يشوف كل الصور

        let result: PHFetchResult<PHAsset>
        if let collection = (album ?? selectedAlbum)?.collection {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: .image, options: options)
        }

        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        // placeholder بالترتيب
        thumbnails = assets.map { (asset: $0, image: UIImage()) }

        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
        requestOptions.isSynchronous = false

        for (index, asset) in assets.enumerated() {
            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { [weak self] image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard let image, !isDegraded else { return }
                Task { @MainActor [weak self] in
                    guard let self, index < self.thumbnails.count else { return }
                    self.thumbnails[index] = (asset: asset, image: image)
                    if index == assets.count - 1 {
                        self.isLoading = false
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isLoading = false
        }
    }

    func loadPreviewImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        let targetSize = CGSize(width: 1000, height: 1000)

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image else { return }
            Task { @MainActor in
                completion(image)
            }
        }
    }

    func loadFullImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let targetSize = CGSize(width: min(asset.pixelWidth, 1500), height: min(asset.pixelHeight, 1500))

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            Task { @MainActor in
                completion(image)
            }
        }
    }
}

// MARK: - AddStorySheet

struct AddStorySheet: View {
    @EnvironmentObject var storyVM: StoryViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @StateObject private var photoService = PhotoLibraryService()

    @State private var selectedImage: UIImage? = nil
    @State private var selectedAsset: PHAsset? = nil
    @State private var caption: String = ""
    @State private var showCropper = false
    @State private var rawPickedImage: UIImage? = nil
    @State private var showSuccess = false
    @State private var isLoadingPhoto = false

    private let gridSpacing: CGFloat = 1.5
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 4)

    var body: some View {
        ZStack {
            DS.Color.overlayDark.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                albumPicker
                photoGrid
            }
        }
        .onAppear { photoService.requestAccess() }
        .fullScreenCover(isPresented: $showCropper) { cropperView }
        .overlay { successOverlay }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            .accessibilityLabel(L10n.t("إغلاق", "Close"))

            Spacer()

            Text(L10n.t("قصة جديدة", "New Story"))
                .font(DS.Font.scaled(20, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)

            Spacer()

            // Invisible balance
            Image(systemName: "xmark")
                .font(DS.Font.title3)
                .foregroundColor(.clear)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - Album Picker

    private var albumPicker: some View {
        HStack {
            Menu {
                ForEach(photoService.albums) { album in
                    Button {
                        photoService.fetchPhotos(from: album)
                    } label: {
                        HStack {
                            Text(album.title)
                            Spacer()
                            Text("\(album.count)")
                                .foregroundColor(DS.Color.textSecondary)
                            if album.id == photoService.selectedAlbum?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "photo.on.rectangle")
                        .font(DS.Font.scaled(13, weight: .semibold))
                    Text(photoService.selectedAlbum?.title ?? L10n.t("الكل", "All Photos"))
                        .font(DS.Font.scaled(13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(DS.Font.scaled(10, weight: .bold))
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.overlayFillSubtle)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        Group {
            if photoService.authorizationStatus == .denied || photoService.authorizationStatus == .restricted {
                permissionDeniedView
            } else if photoService.thumbnails.isEmpty && photoService.isLoading {
                loadingView
            } else {
                gridContent
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(photoService.thumbnails.indices, id: \.self) { index in
                    photoCell(index: index)
                }
            }
        }
    }

    private func photoCell(index: Int) -> some View {
        let item = photoService.thumbnails[index]
        let isSelected = selectedAsset == item.asset
        let hasImage = item.image.size.width > 0

        return Button {
            if hasImage { selectPhoto(item.asset, thumbnail: item.image) }
        } label: {
            ZStack {
                if hasImage {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    DS.Color.textSecondary.opacity(0.15)
                        .aspectRatio(1, contentMode: .fill)
                }

                if isSelected && isLoadingPhoto {
                    DS.Color.overlayDark.opacity(0.4)
                    ProgressView()
                        .tint(DS.Color.textOnPrimary)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(DS.Color.textOnPrimary, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPhoto)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(DS.Font.scaled(36, weight: .regular))
                .foregroundColor(DS.Color.overlayIconBorder)
            Text(L10n.t("يرجى السماح بالوصول للصور من الإعدادات", "Please allow photo access in Settings"))
                .font(DS.Font.scaled(13, weight: .medium))
                .foregroundColor(DS.Color.overlayHalf)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(L10n.t("فتح الإعدادات", "Open Settings"))
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(SwiftUI.Color.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .tint(DS.Color.textOnPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    // MARK: - Cropper with Caption

    @ViewBuilder
    private var cropperView: some View {
        if let rawImage = rawPickedImage {
            StoryCropperWrapper(
                image: rawImage,
                caption: $caption,
                needsApproval: !authVM.canModerate,
                onDone: { cropped in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectedImage = cropped
                    showCropper = false
                    rawPickedImage = nil
                    Task {
                        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        let success = await storyVM.uploadStory(
                            image: cropped,
                            caption: trimmedCaption.isEmpty ? nil : trimmedCaption
                        )
                        if success {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            showSuccess = true
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            dismiss()
                        }
                    }
                },
                onCancel: {
                    showCropper = false
                    rawPickedImage = nil
                }
            )
        }
    }

    // MARK: - Success Overlay

    @ViewBuilder
    private var successOverlay: some View {
        if showSuccess {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Font.scaled(60, weight: .regular))
                    .foregroundColor(DS.Color.success)
                Text(L10n.t("تم الرفع بنجاح", "Uploaded Successfully"))
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.shadowDense)
            .transition(.opacity)
        }
    }

    // MARK: - Actions

    private func selectPhoto(_ asset: PHAsset, thumbnail: UIImage) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedAsset = asset
        isLoadingPhoto = true

        // تحميل صورة واضحة (800px سريعة) ثم فتح القص
        photoService.loadPreviewImage(for: asset) { image in
            isLoadingPhoto = false
            guard let image else { return }
            rawPickedImage = image
            showCropper = true
        }
    }
}

// MARK: - Story Cropper Wrapper (قص + حقل نص)

struct StoryCropperWrapper: View {
    let image: UIImage
    @Binding var caption: String
    let needsApproval: Bool
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            ImageCropperView(
                image: image,
                cropShape: .square,
                onCrop: { cropped in onDone(cropped) },
                onCancel: { onCancel() }
            )

            // حقل الكتابة + الموافقة
            VStack(spacing: 0) {
                if needsApproval {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(DS.Font.caption1)
                        Text(L10n.t("القصة تحتاج موافقة الإدارة قبل النشر", "Story needs admin approval before publishing"))
                            .font(DS.Font.scaled(11, weight: .medium))
                    }
                    .foregroundColor(DS.Color.warning)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.textPrimary.opacity(0.55))
                }
                captionField
            }
            .padding(.bottom, 60)
        }
    }

    private var captionField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "text.bubble")
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.overlayHalf)

            TextField(
                L10n.t("اكتب نص للقصة...", "Add a caption..."),
                text: $caption
            )
            .font(DS.Font.scaled(14, weight: .regular))
            .foregroundColor(DS.Color.textOnPrimary)
            .tint(DS.Color.textOnPrimary)
            .focused($isCaptionFocused)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.textPrimary.opacity(0.55))
    }
}

