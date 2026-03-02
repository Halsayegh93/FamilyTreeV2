import SwiftUI
import PhotosUI

struct PersonalGalleryView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    let member: FamilyMember
    let isEditable: Bool

    @State private var galleryPhotos: [MemberGalleryPhoto] = []
    @State private var selectedGalleryItems: [PhotosPickerItem] = []
    @State private var showGalleryPicker: Bool = false
    @State private var selectedPreviewPhoto: MemberGalleryPhoto? = nil
    @State private var showGalleryViewer = false
    @State private var pendingDeletePhoto: MemberGalleryPhoto? = nil
    @State private var showDeletePhotoAlert = false
    @State private var isViewingLegacyPhoto = false
    @State private var legacyGalleryPhotoURL: String? = nil
    @State private var showDeleteLegacyPhotoAlert = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    galleryGrid
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.xl)
                }
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(L10n.t("معرض الصور", "Gallery"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
        .onAppear {
            Task { await refreshGalleryPhotos() }
        }
        .photosPicker(isPresented: $showGalleryPicker, selection: $selectedGalleryItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: selectedGalleryItems) { _, items in
            handleGalleryImagesChange(items)
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
                        AsyncImage(url: URL(string: photo.photoURL)) { phase in
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
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
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
                        AsyncImage(url: URL(string: url)) { phase in
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
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
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
        guard let photo else {
            Log.warning("حذف صورة: photo is nil")
            return
        }
        Log.info("حذف صورة: \(photo.id) — \(photo.photoURL)")
        let success = await authVM.deleteMemberGalleryPhotoMulti(photoId: photo.id, photoURL: photo.photoURL)
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
