import SwiftUI
import PhotosUI

// ═══════════════════════════════════════════════════════════════════════════
// معرض الصور — ألبومات مجمّعة تحت رؤوس السنوات، كل ألبوم داخله صور.
// التصفّح للجميع، الإنشاء/الرفع/الحذف للإدارة فقط (owner + admin).
// ═══════════════════════════════════════════════════════════════════════════

struct PhotoGalleryView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var galleryVM = GalleryViewModel()

    @State private var showingCreateAlbum = false

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: DS.Spacing.sm),
        GridItem(.flexible(), spacing: DS.Spacing.sm)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.background.ignoresSafeArea()

            if galleryVM.isLoading && galleryVM.albums.isEmpty {
                ProgressView().tint(DS.Color.primary)
            } else if galleryVM.albumsGroupedByYear.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: DS.Spacing.lg, pinnedViews: []) {
                        ForEach(galleryVM.albumsGroupedByYear, id: \.year) { group in
                            Section {
                                LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                                    ForEach(group.albums) { album in
                                        NavigationLink(value: album) {
                                            GalleryAlbumCard(
                                                album: album,
                                                coverURL: galleryVM.coverURL(for: album),
                                                photoCount: galleryVM.photoCount(in: album.id)
                                            )
                                        }
                                        .buttonStyle(DSScaleButtonStyle())
                                    }
                                }
                            } header: {
                                yearHeader(for: group.year)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxxxl)
                }
                .refreshable { await galleryVM.fetchAll() }
            }

            // زر إنشاء ألبوم — للإدارة فقط
            if authVM.isAdmin {
                HStack {
                    Spacer()
                    DSFloatingButton(label: L10n.t("ألبوم جديد", "New Album"), color: DS.Color.secondary) {
                        showingCreateAlbum = true
                    }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
        .task {
            galleryVM.configure(authVM: authVM)
            if galleryVM.albums.isEmpty { await galleryVM.fetchAll() }
        }
        .navigationDestination(for: GalleryAlbum.self) { album in
            GalleryAlbumDetailView(galleryVM: galleryVM, album: album)
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showingCreateAlbum) {
            GalleryAlbumFormSheet(galleryVM: galleryVM, existingAlbum: nil)
                .presentationDetents([.fraction(0.42)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Year Header

    private func yearHeader(for year: Int?) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: year == nil ? "calendar.badge.exclamationmark" : "calendar")
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.primary)
            Text(year.map(String.init) ?? L10n.t("غير مؤرّخ", "Undated"))
                .font(DS.Font.scaled(16, weight: .black))
                .foregroundColor(DS.Color.textPrimary)
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد ألبومات بعد", "No albums yet"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
            if authVM.isAdmin {
                Text(L10n.t("اضغط «ألبوم جديد» لإنشاء أول ألبوم",
                           "Tap “New Album” to create your first album"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

// MARK: - Album Card

private struct GalleryAlbumCard: View {
    let album: GalleryAlbum
    let coverURL: String?
    let photoCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                // الغلاف
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.10))
                    if let cover = coverURL, let url = URL(string: cover) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(DS.Color.primary)
                        }
                    } else {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(DS.Color.primary.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                // عدّاد الصور
                HStack(spacing: 3) {
                    Image(systemName: "photo.fill").font(DS.Font.scaled(8, weight: .bold))
                    Text("\(photoCount)").font(DS.Font.scaled(10, weight: .black))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if album.isHidden {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash.fill").font(DS.Font.scaled(8, weight: .bold))
                        Text(L10n.t("مخفي", "Hidden")).font(DS.Font.scaled(9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(DS.Color.textTertiary))
                    .padding(6)
                }
            }

            // عنوان + سنة
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                if let year = album.year {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar").font(DS.Font.scaled(9, weight: .bold))
                        Text(String(year)).font(DS.Font.scaled(10, weight: .bold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(DS.Color.primary.opacity(0.12)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 210, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.08), lineWidth: 1)
        )
        .opacity(album.isHidden ? 0.7 : 1.0)
        .dsSubtleShadow()
    }
}

// MARK: - Album Detail (شبكة الصور)

struct GalleryAlbumDetailView: View {
    @ObservedObject var galleryVM: GalleryViewModel
    let album: GalleryAlbum
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddPhotos = false
    @State private var showingEditAlbum = false
    @State private var viewerIndex: Int? = nil
    @State private var photoToDelete: GalleryPhoto? = nil
    @State private var showDeleteAlbumAlert = false

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    /// نسخة محدّثة من الألبوم من الـVM (لعكس تعديل العنوان/السنة فوراً).
    private var currentAlbum: GalleryAlbum {
        galleryVM.albums.first(where: { $0.id == album.id }) ?? album
    }

    private var albumPhotos: [GalleryPhoto] {
        galleryVM.photos(in: album.id)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if albumPhotos.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: 3) {
                            ForEach(Array(albumPhotos.enumerated()), id: \.element.id) { index, photo in
                                Button {
                                    viewerIndex = index
                                } label: {
                                    photoThumb(photo)
                                }
                                .buttonStyle(DSScaleButtonStyle())
                                .contextMenu {
                                    if authVM.isAdmin {
                                        Button(role: .destructive) {
                                            photoToDelete = photo
                                        } label: {
                                            Label(L10n.t("حذف الصورة", "Delete Photo"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.top, 3)
                        .padding(.bottom, DS.Spacing.xxxxl)
                    }
                    .refreshable { await galleryVM.fetchPhotos() }
                }
            }

            if authVM.isAdmin {
                HStack {
                    Spacer()
                    DSFloatingButton(label: L10n.t("إضافة صور", "Add Photos"), color: DS.Color.secondary) {
                        showingAddPhotos = true
                    }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAddPhotos) {
            GalleryAddPhotosSheet(galleryVM: galleryVM, albumId: album.id)
        }
        .sheet(isPresented: $showingEditAlbum) {
            GalleryAlbumFormSheet(galleryVM: galleryVM, existingAlbum: currentAlbum)
                .presentationDetents([.fraction(0.42)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { IndexBox(value: $0) } },
            set: { viewerIndex = $0?.value }
        )) { box in
            GalleryPhotoViewer(photos: albumPhotos, initialIndex: box.value)
        }
        .alert(L10n.t("حذف الصورة", "Delete Photo"), isPresented: Binding(
            get: { photoToDelete != nil },
            set: { if !$0 { photoToDelete = nil } }
        )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let p = photoToDelete { Task { await galleryVM.deletePhoto(p) } }
                photoToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { photoToDelete = nil }
        } message: {
            Text(L10n.t("حذف هذه الصورة نهائياً؟", "Permanently delete this photo?"))
        }
        .alert(L10n.t("حذف الألبوم", "Delete Album"), isPresented: $showDeleteAlbumAlert) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task {
                    await galleryVM.deleteAlbum(currentAlbum)
                    await MainActor.run { dismiss() }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("حذف هذا الألبوم وكل صوره نهائياً؟",
                       "Permanently delete this album and all its photos?"))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIconButton(
                icon: "chevron.backward",
                iconColor: DS.Color.textPrimary,
                fillColor: DS.Color.surface,
                borderColor: DS.Color.primary.opacity(0.08),
                borderWidth: 1
            ) {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(currentAlbum.title)
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = currentAlbum.year {
                        Text(String(year))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Text(L10n.t("\(albumPhotos.count) صورة", "\(albumPhotos.count) photos"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()

            if authVM.isAdmin {
                Menu {
                    Button {
                        showingEditAlbum = true
                    } label: {
                        Label(L10n.t("تعديل الألبوم", "Edit Album"), systemImage: "pencil")
                    }
                    Button {
                        Task { await galleryVM.toggleHidden(currentAlbum) }
                    } label: {
                        Label(
                            currentAlbum.isHidden
                                ? L10n.t("إظهار للجميع", "Show to all")
                                : L10n.t("إخفاء من الأعضاء", "Hide from members"),
                            systemImage: currentAlbum.isHidden ? "eye.fill" : "eye.slash.fill"
                        )
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAlbumAlert = true
                    } label: {
                        Label(L10n.t("حذف الألبوم", "Delete Album"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(DS.Font.scaled(16, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(DS.Color.surface)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.background)
    }

    private func photoThumb(_ photo: GalleryPhoto) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let url = URL(string: photo.photoUrl) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            DS.Color.primary.opacity(0.08)
                            ProgressView().tint(DS.Color.primary)
                        }
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد صور في هذا الألبوم بعد",
                       "No photos in this album yet"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            if authVM.isAdmin {
                Text(L10n.t("اضغط «إضافة صور» لرفع الصور",
                           "Tap “Add Photos” to upload"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding()
    }
}

/// غلاف لعرض مؤشّر الصورة في fullScreenCover(item:).
private struct IndexBox: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - Full-screen Photo Viewer

struct GalleryPhotoViewer: View {
    let photos: [GalleryPhoto]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(photos: [GalleryPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    if let url = URL(string: photo.photoUrl) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView().tint(.white)
                        }
                        .tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .padding(.trailing, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                }
                Spacer()
                // العدّاد + التعليق
                VStack(spacing: 4) {
                    if photos.indices.contains(index),
                       let caption = photos[index].caption, !caption.isEmpty {
                        Text(caption)
                            .font(DS.Font.scaled(13, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    Text("\(index + 1) / \(photos.count)")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .environment(\.layoutDirection, .leftToRight) // منع انعكاس اتجاه الـ paging في RTL
    }
}

// MARK: - Album Form Sheet (إنشاء/تعديل)

struct GalleryAlbumFormSheet: View {
    @ObservedObject var galleryVM: GalleryViewModel
    /// nil = إنشاء ألبوم جديد، غير nil = تعديل.
    let existingAlbum: GalleryAlbum?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var yearText: String
    @State private var isSaving = false
    @State private var errorBanner: String? = nil

    init(galleryVM: GalleryViewModel, existingAlbum: GalleryAlbum?) {
        self.galleryVM = galleryVM
        self.existingAlbum = existingAlbum
        _title = State(initialValue: existingAlbum?.title ?? "")
        _yearText = State(initialValue: existingAlbum?.year.map(String.init) ?? "")
    }

    private var isEditing: Bool { existingAlbum != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("تفاصيل الألبوم", "Album Details"),
                            icon: "photo.stack.fill",
                            iconColor: DS.Color.primary
                        )
                        VStack(spacing: 0) {
                            DSLabeledFieldRow(icon: "textformat", iconColor: DS.Color.primary,
                                              label: L10n.t("المسمّى *", "Title *")) {
                                TextField(L10n.t("مثلاً: عرس فلان", "e.g. Wedding"), text: $title)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                            DSDivider()
                            DSLabeledFieldRow(icon: "calendar", iconColor: DS.Color.success,
                                              label: L10n.t("السنة (اختياري)", "Year (optional)")) {
                                TextField("2024", text: $yearText)
                                    .keyboardType(.numberPad)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                        }
                    }

                    if let errorBanner {
                        Text(errorBanner)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.error)
                    }

                    DSPrimaryButton(
                        isEditing ? L10n.t("حفظ", "Save") : L10n.t("إنشاء الألبوم", "Create Album"),
                        icon: isEditing ? "checkmark" : "plus",
                        isLoading: isSaving
                    ) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(isEditing ? L10n.t("تعديل الألبوم", "Edit Album")
                                       : L10n.t("ألبوم جديد", "New Album"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .foregroundColor(DS.Color.error)
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.fraction(0.42)])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        let year = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            isSaving = true
            let ok: Bool
            if let existing = existingAlbum {
                ok = await galleryVM.updateAlbum(existing, title: title, year: year)
            } else {
                ok = await galleryVM.createAlbum(title: title, year: year) != nil
            }
            isSaving = false
            if ok { dismiss() } else { errorBanner = galleryVM.errorMessage }
        }
    }
}

// MARK: - Add Photos Sheet

struct GalleryAddPhotosSheet: View {
    @ObservedObject var galleryVM: GalleryViewModel
    let albumId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isLoadingImages = false
    @State private var errorBanner: String? = nil

    private var canUpload: Bool { !images.isEmpty && !galleryVM.isUploading }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 30,
                        matching: .images
                    ) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(DS.Font.scaled(26, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                            Text(images.isEmpty
                                 ? L10n.t("اختر صوراً", "Select photos")
                                 : L10n.t("تغيير الاختيار (\(images.count))", "Change selection (\(images.count))"))
                                .font(DS.Font.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(DS.Color.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1.5)
                        )
                    }

                    if isLoadingImages {
                        HStack(spacing: DS.Spacing.sm) {
                            ProgressView().tint(DS.Color.primary)
                            Text(L10n.t("جاري تحضير الصور...", "Preparing photos..."))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }

                    // معاينة مصغّرة
                    if !images.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                            }
                        }
                    }

                    if galleryVM.isUploading {
                        VStack(spacing: DS.Spacing.xs) {
                            ProgressView(value: galleryVM.uploadProgress)
                                .progressViewStyle(.linear)
                                .tint(DS.Color.primary)
                            Text(L10n.t("جاري الرفع...", "Uploading..."))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }

                    if let errorBanner {
                        Text(errorBanner)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.error)
                    }

                    DSPrimaryButton(
                        L10n.t("رفع \(images.count) صورة", "Upload \(images.count)"),
                        icon: "icloud.and.arrow.up.fill",
                        isLoading: galleryVM.isUploading
                    ) { upload() }
                        .disabled(!canUpload)
                        .opacity(canUpload ? 1 : 0.5)

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("إضافة صور", "Add Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .foregroundColor(DS.Color.error)
                        .disabled(galleryVM.isUploading)
                }
            }
            .onChange(of: pickerItems) { items in
                loadImages(from: items)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { images = []; return }
        isLoadingImages = true
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    loaded.append(img)
                }
            }
            await MainActor.run {
                images = loaded
                isLoadingImages = false
            }
        }
    }

    private func upload() {
        let toUpload = images
        Task {
            let count = await galleryVM.addPhotos(albumId: albumId, images: toUpload)
            if count > 0 {
                dismiss()
            } else if let err = galleryVM.errorMessage {
                errorBanner = err
            }
        }
    }
}
