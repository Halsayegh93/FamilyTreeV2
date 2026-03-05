import SwiftUI
import PhotosUI

struct PersonalGalleryView: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    let member: FamilyMember
    let isEditable: Bool

    @State private var galleryPhotos: [MemberGalleryPhoto] = []
    @State private var selectedGalleryItems: [PhotosPickerItem] = []
    @State private var pendingImages: [UIImage] = []
    @State private var isLoadingSelection = false
    @State private var showGalleryPicker: Bool = false
    @State private var showPendingPreview = false
    @State private var pendingPreviewIndex = 0
    @State private var selectedPreviewPhoto: MemberGalleryPhoto? = nil
    @State private var showGalleryViewer = false
    @State private var pendingDeletePhoto: MemberGalleryPhoto? = nil
    @State private var showDeletePhotoAlert = false
    @State private var isViewingLegacyPhoto = false
    @State private var legacyGalleryPhotoURL: String? = nil
    @State private var showDeleteLegacyPhotoAlert = false
    @State private var isLoadingPhotos = true
    @State private var isUploading = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            if isLoadingPhotos {
                VStack(spacing: DS.Spacing.md) {
                    ProgressView()
                    Text(L10n.t("جاري تحميل الصور...", "Loading photos..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {
                        if isUploading {
                            HStack(spacing: DS.Spacing.sm) {
                                ProgressView()
                                Text(L10n.t("جاري رفع الصور...", "Uploading photos..."))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                            }
                            .padding(DS.Spacing.md)
                            .glassCard(radius: DS.Radius.md)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.sm)
                        }
                        galleryGrid
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, isUploading ? 0 : DS.Spacing.xl)
                    }
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("معرض الصور", "Gallery"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
        .task { await refreshGalleryPhotos() }
        .photosPicker(isPresented: $showGalleryPicker, selection: $selectedGalleryItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: selectedGalleryItems) { _, items in
            handleGalleryImagesChange(items)
        }
        .sheet(isPresented: $showPendingPreview) {
            galleryPendingPreviewSheet
        }
        .fullScreenCover(isPresented: $showGalleryViewer) {
            if let photo = selectedPreviewPhoto {
                GalleryPhotoViewer(
                    photoURL: photo.photoURL,
                    onClose: { showGalleryViewer = false },
                    onDelete: {
                        let photoToDelete = photo
                        let isLegacy = isViewingLegacyPhoto
                        showGalleryViewer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if isLegacy {
                                showDeleteLegacyPhotoAlert = true
                            } else {
                                pendingDeletePhoto = photoToDelete
                                showDeletePhotoAlert = true
                            }
                        }
                    }
                )
            }
        }
        .alert(L10n.t("حذف الصورة؟", "Delete photo?"), isPresented: $showDeletePhotoAlert) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                let photoToDelete = pendingDeletePhoto
                pendingDeletePhoto = nil
                Task { await deleteGalleryPhoto(photoToDelete) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingDeletePhoto = nil }
        }
        .alert(L10n.t("حذف الصورة القديمة؟", "Delete legacy photo?"), isPresented: $showDeleteLegacyPhotoAlert) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await deleteLegacyGalleryPhoto() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - Gallery Grid
    private var galleryGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSSectionHeader(
                    title: L10n.t("الصور", "Photos"),
                    icon: "photo.on.rectangle.angled"
                )

                if !galleryPhotos.isEmpty {
                    Text("\(galleryPhotos.count)")
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(DS.Color.primary)
                        .clipShape(Circle())
                }

                Spacer()

                if isEditable {
                    Button(action: { showGalleryPicker = true }) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(L10n.t("إضافة صور", "Add Photos"))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.gradientPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSBoldButtonStyle())
                    .padding(.trailing, DS.Spacing.lg)
                }
            }

            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

            if galleryPhotos.isEmpty && legacyGalleryPhotoURL == nil {
                DSCard(padding: DS.Spacing.xl) {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "photo.on.rectangle")
                            .font(DS.Font.scaled(40))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد صور حالياً", "No photos yet"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    ForEach(galleryPhotos) { photo in
                        galleryPhotoCell(photo: photo, showDelete: isEditable)
                    }

                    if galleryPhotos.isEmpty, let legacyURL = legacyGalleryPhotoURL {
                        legacyPhotoCell(url: legacyURL, showDelete: isEditable)
                    }
                }
            }
        }
    }

    // MARK: - Photo Cell
    private func galleryPhotoCell(photo: MemberGalleryPhoto, showDelete: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                isViewingLegacyPhoto = false
                selectedPreviewPhoto = photo
                showGalleryViewer = true
            } label: {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        CachedAsyncPhaseImage(url: URL(string: photo.photoURL)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else if phase.error != nil {
                                ZStack {
                                    DS.Color.surface
                                    Image(systemName: "photo")
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            } else {
                                ZStack { DS.Color.surface; ProgressView() }
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.primary.opacity(0.15), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            if showDelete {
                Button {
                    pendingDeletePhoto = photo
                    showDeletePhotoAlert = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DS.Color.error)
                        .dsSubtleShadow()
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legacyPhotoCell(url: String, showDelete: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if let legacyPhoto = legacyPreviewPhoto(url: url) {
                    isViewingLegacyPhoto = true
                    selectedPreviewPhoto = legacyPhoto
                    showGalleryViewer = true
                }
            } label: {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        CachedAsyncPhaseImage(url: URL(string: url)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack { DS.Color.surface; ProgressView() }
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.primary.opacity(0.15), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            if showDelete {
                Button {
                    showDeleteLegacyPhotoAlert = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DS.Color.error)
                        .dsSubtleShadow()
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Gallery Logic
    private func handleGalleryImagesChange(_ items: [PhotosPickerItem]) {
        Task {
            guard !items.isEmpty else { return }
            await MainActor.run { isLoadingSelection = true }
            var loaded: [UIImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImg = UIImage(data: data) else { continue }
                loaded.append(uiImg)
            }
            await MainActor.run {
                pendingImages = loaded
                pendingPreviewIndex = 0
                isLoadingSelection = false
                if !loaded.isEmpty { showPendingPreview = true }
                self.selectedGalleryItems = []
            }
        }
    }

    private func uploadPendingImages() {
        Task {
            await MainActor.run { isUploading = true; showPendingPreview = false }
            for image in pendingImages {
                _ = await memberVM.uploadMemberGalleryPhotoMulti(image: image, for: member.id)
            }
            await MainActor.run {
                pendingImages = []
                isUploading = false
            }
            await refreshGalleryPhotos()
        }
    }

    private func deleteGalleryPhoto(_ photo: MemberGalleryPhoto?) async {
        guard let photo else {
            Log.warning("حذف صورة: photo is nil")
            return
        }
        Log.info("حذف صورة: \(photo.id) — \(photo.photoURL)")
        let success = await memberVM.deleteMemberGalleryPhotoMulti(photoId: photo.id, photoURL: photo.photoURL)
        if !success {
            Log.error("فشل حذف الصورة: \(photo.id)")
            return
        }
        Log.info("تم حذف الصورة بنجاح: \(photo.id)")
        await MainActor.run {
            if self.selectedPreviewPhoto?.id == photo.id { self.selectedPreviewPhoto = nil }
        }
        await refreshGalleryPhotos()
    }

    private func refreshGalleryPhotos() async {
        let photos = await memberVM.fetchMemberGalleryPhotos(for: member.id)
        await MainActor.run {
            self.galleryPhotos = photos
            self.legacyGalleryPhotoURL = photos.isEmpty ? member.photoURL : nil
            self.isLoadingPhotos = false
        }
    }

    private func deleteLegacyGalleryPhoto() async {
        let success = await memberVM.deleteMemberGalleryPhoto(for: member.id)
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

    // MARK: - Pending Preview Sheet
    private var galleryPendingPreviewSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instagram-style carousel
                ZStack(alignment: .top) {
                    TabView(selection: $pendingPreviewIndex) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipped()

                                Button {
                                    withAnimation {
                                        pendingImages.remove(at: idx)
                                        if pendingPreviewIndex >= pendingImages.count {
                                            pendingPreviewIndex = max(0, pendingImages.count - 1)
                                        }
                                        if pendingImages.isEmpty { showPendingPreview = false }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(DS.Font.scaled(24, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                                }
                                .padding(DS.Spacing.md)
                            }
                            .tag(idx)
                        }
                    }
                    .aspectRatio(4/5, contentMode: .fit)
                    .clipped()
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    if pendingImages.count > 1 {
                        HStack {
                            Spacer()
                            Text("\(pendingPreviewIndex + 1)/\(pendingImages.count)")
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

                // Thumbnail strip
                if pendingImages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, image in
                                Button {
                                    withAnimation { pendingPreviewIndex = idx }
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                                .stroke(pendingPreviewIndex == idx ? DS.Color.primary : Color.clear, lineWidth: 2.5)
                                        )
                                        .opacity(pendingPreviewIndex == idx ? 1 : 0.6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                    }
                }

                Spacer()

                // Upload button
                DSPrimaryButton(
                    L10n.t("رفع \(pendingImages.count) صور", "Upload \(pendingImages.count) Photos"),
                    icon: "arrow.up.circle.fill"
                ) {
                    uploadPendingImages()
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .background(DS.Color.background)
            .navigationTitle(L10n.t("معاينة الصور", "Preview Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        pendingImages = []
                        showPendingPreview = false
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func legacyPreviewPhoto(url: String) -> MemberGalleryPhoto? {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return MemberGalleryPhoto(id: UUID(), memberId: member.id, photoURL: url, createdAt: nil)
    }
}
