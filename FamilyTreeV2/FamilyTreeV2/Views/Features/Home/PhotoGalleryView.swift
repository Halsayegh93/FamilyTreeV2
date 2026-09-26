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

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — أعمدة أكثر لاستغلال العرض
    private var isLandscape: Bool { vSizeClass == .compact }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: 190, maximum: .infinity), spacing: DS.Spacing.sm, alignment: .top)]
        }
        return [
            GridItem(.flexible(), spacing: DS.Spacing.sm),
            GridItem(.flexible(), spacing: DS.Spacing.sm)
        ]
    }

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
                    DSFloatingButton(label: L10n.t("ألبوم جديد", "New Album"), color: DS.Color.primary) {
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
        // مربّع بمنتصف الشاشة بدل الورقة السفلية (طلب المالك)
        .dsCenterBox(isPresented: $showingCreateAlbum) {
            GalleryAlbumFormSheet(galleryVM: galleryVM, existingAlbum: nil)
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
                    Image(systemName: "photo.fill").font(DS.Font.scaled(11, weight: .bold))
                    Text("\(photoCount)").font(DS.Font.scaled(11, weight: .black))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .dsGlass(Capsule())
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if album.isHidden {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash.fill").font(DS.Font.scaled(11, weight: .bold))
                        Text(L10n.t("مخفي", "Hidden")).font(DS.Font.scaled(11, weight: .bold))
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
                        Image(systemName: "calendar").font(DS.Font.scaled(11, weight: .bold))
                        Text(String(year)).font(DS.Font.scaled(11, weight: .bold))
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
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddPhotos = false
    @State private var showingEditAlbum = false
    @State private var viewerIndex: Int? = nil
    @State private var photoToDelete: GalleryPhoto? = nil
    @State private var showDeleteAlbumAlert = false
    /// الإبلاغ عن صورة (Guideline 1.2) — نفس رسائل «إبلاغ» الموحّدة
    @State private var photoToReport: GalleryPhoto? = nil
    @State private var reportReason = ""
    @State private var reportSent = false

    /// الإبلاغ لغير صاحب الصورة
    private func canReport(_ photo: GalleryPhoto) -> Bool {
        !AccountIdentity.isMine(photo.uploadedBy, currentUser: authVM.currentUser)
    }

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — صور أكثر بالصف
    private var isLandscape: Bool { vSizeClass == .compact }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: 110, maximum: .infinity), spacing: 3, alignment: .top)]
        }
        return [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3)
        ]
    }

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
                                    if canReport(photo) {
                                        Button {
                                            photoToReport = photo
                                        } label: {
                                            Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                                        }
                                    }
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
                    DSFloatingButton(label: L10n.t("إضافة صور", "Add Photos"), color: DS.Color.primary) {
                        showingAddPhotos = true
                    }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // مربّعات بمنتصف الشاشة بدل الأوراق السفلية (طلب المالك)
        .dsCenterBox(isPresented: $showingAddPhotos) {
            GalleryAddPhotosSheet(galleryVM: galleryVM, albumId: album.id)
        }
        .dsCenterBox(isPresented: $showingEditAlbum) {
            GalleryAlbumFormSheet(galleryVM: galleryVM, existingAlbum: currentAlbum)
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { IndexBox(value: $0) } },
            set: { viewerIndex = $0?.value }
        )) { box in
            GalleryPhotoViewer(photos: albumPhotos, initialIndex: box.value,
                               canReport: { canReport($0) },
                               onReport: { photoToReport = $0 })
        }
        .dsAlert(L10n.t("إبلاغ عن صورة", "Report Photo"), isPresented: Binding(
            get: { photoToReport != nil },
            set: { if !$0 { photoToReport = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                .dsAlertField()
            Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                let target = photoToReport
                let reason = reportReason
                let albumTitle = currentAlbum.title
                photoToReport = nil
                reportReason = ""
                if let target {
                    Task {
                        let ok = await notificationVM.reportContent(
                            contentKind: L10n.t("صورة في ألبوم", "album photo"),
                            contentLabel: target.caption.flatMap { $0.isEmpty ? nil : $0 } ?? albumTitle,
                            contentId: target.id,
                            reason: reason
                        )
                        if ok { await MainActor.run { reportSent = true } }
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { photoToReport = nil; reportReason = "" }
        } message: {
            Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذه الصورة.",
                        "Enter a reason; it will be sent to the admins to review this photo."))
        }
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.",
                        "Thank you — your report reached the admins and will be reviewed within 24 hours."))
        }
        .dsAlert(L10n.t("حذف الصورة", "Delete Photo"), isPresented: Binding(
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
        .dsAlert(L10n.t("حذف الألبوم", "Delete Album"), isPresented: $showDeleteAlbumAlert) {
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
    /// الإبلاغ عن الصورة المعروضة (Guideline 1.2) — لغير صاحبها
    var canReport: (GalleryPhoto) -> Bool = { _ in false }
    var onReport: (GalleryPhoto) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(photos: [GalleryPhoto], initialIndex: Int,
         canReport: @escaping (GalleryPhoto) -> Bool = { _ in false },
         onReport: @escaping (GalleryPhoto) -> Void = { _ in }) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.canReport = canReport
        self.onReport = onReport
        _index = State(initialValue: initialIndex)
    }

    private var currentPhoto: GalleryPhoto? {
        photos.indices.contains(index) ? photos[index] : nil
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
                    // إبلاغ عن الصورة المعروضة
                    if let photo = currentPhoto, canReport(photo) {
                        Button {
                            onReport(photo)
                        } label: {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.black.opacity(0.4)))
                                .dsGlass(Circle())
                                .frame(width: 44, height: 44)   // مساحة ضغط ٤٤ (توصية أبل)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.t("إبلاغ عن الصورة", "Report photo"))
                        .padding(.leading, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                            .dsGlass(Circle())
                    }
                    .accessibilityLabel(L10n.t("إغلاق", "Close"))
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
        _initialTitle = State(initialValue: existingAlbum?.title ?? "")
        _initialYear = State(initialValue: existingAlbum?.year.map(String.init) ?? "")
    }

    private var isEditing: Bool { existingAlbum != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// القيم التي فُتح بها المربّع (فارغة للألبوم الجديد) — تُلتقط مرة واحدة، فتحديث
    /// الألبوم من الخادم أثناء التعديل لا يغيّر المقارنة
    @State private var initialTitle: String
    @State private var initialYear: String

    /// كتابة لم تُحفظ — «إلغاء» يسأل قبل التجاهل (توصية أبل)
    private var hasUnsavedChanges: Bool {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trim(title) != trim(initialTitle) || trim(yearText) != trim(initialYear)
    }

    /// لون المعرض — ذهبي مربّعات المكتبة
    private let tint = DS.Color.composerLibrary

    var body: some View {
        // نفس هيكل مربّعات الإضافة (طلب المالك): رأس ملوّن + قسم + «حفظ» كحلي يمين و«إلغاء» يسار
        DSComposer(
            title: isEditing ? L10n.t("تعديل الألبوم", "Edit Album") : L10n.t("ألبوم جديد", "New Album"),
            subtitle: isEditing ? (existingAlbum?.title ?? "")
                                : L10n.t("مجموعة صور تحت مسمّى وسنة اختيارية", "Photos under a title and an optional year"),
            icon: "photo.stack.fill",
            tint: tint,
            actionTitle: isEditing ? L10n.t("حفظ", "Save") : L10n.t("إنشاء الألبوم", "Create Album"),
            actionIcon: isEditing ? "checkmark" : "plus",
            canSubmit: canSave,
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { save() },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("تفاصيل الألبوم", "Album Details"),
                              icon: "photo.stack.fill", tint: tint, index: 0) {
                DSComposerField(icon: "textformat", label: L10n.t("المسمّى *", "Title *"),
                                placeholder: L10n.t("مثلاً: عرس فلان", "e.g. Wedding"),
                                text: $title, tint: tint)
                DSComposerField(icon: "calendar", label: L10n.t("السنة (اختياري)", "Year (optional)"),
                                placeholder: "2024", text: $yearText, tint: tint,
                                keyboard: .numberPad, ltr: true)
            }

            if let errorBanner {
                Label(errorBanner, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    /// صور مختارة لم تُرفع — «إلغاء» يسأل قبل التجاهل (توصية أبل)
    private var hasUnsavedChanges: Bool { !images.isEmpty || isLoadingImages }

    /// لون المعرض — ذهبي مربّعات المكتبة
    private let tint = DS.Color.composerLibrary
    /// أعمدة المعاينة — صفوف عادية لا LazyVGrid (الشبكة الكسولة تُبلِّغ ارتفاعاً ناقصاً فيُقصّ المربّع)
    private let previewColumns = 4

    /// اسم الألبوم تحت عنوان المربّع
    private var albumTitle: String? {
        galleryVM.albums.first(where: { $0.id == albumId })?.title
    }

    var body: some View {
        // نفس هيكل مربّعات الإضافة (طلب المالك): رأس ملوّن + قسم الصور + «رفع» كحلي يمين و«إلغاء» يسار،
        // وشريط تقدّم الرفع فوق الأزرار
        DSComposer(
            title: L10n.t("إضافة صور", "Add Photos"),
            subtitle: albumTitle ?? L10n.t("معرض الصور", "Photo Gallery"),
            icon: "photo.on.rectangle.angled",
            tint: tint,
            actionTitle: L10n.t("رفع \(images.count) صورة", "Upload \(images.count)"),
            actionIcon: "icloud.and.arrow.up.fill",
            canSubmit: canUpload,
            isBusy: galleryVM.isUploading,
            note: galleryVM.isUploading ? L10n.t("جاري الرفع...", "Uploading...") : nil,
            progress: galleryVM.isUploading ? galleryVM.uploadProgress : nil,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { upload() },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("الصور", "Photos"), icon: "photo.fill", tint: tint,
                              trailing: images.isEmpty ? nil : L10n.t("\(images.count) صورة", "\(images.count) photos"),
                              index: 0) {
                pickerCard

                if isLoadingImages {
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView().tint(tint)
                        Text(L10n.t("جاري تحضير الصور...", "Preparing photos..."))
                            .font(DS.Font.plex(12))
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                }

                // معاينة مصغّرة
                if !images.isEmpty {
                    previewGrid
                        .transition(.opacity)
                }
            }

            if let errorBanner {
                Label(errorBanner, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: images.count)
        .animation(.easeInOut(duration: 0.2), value: isLoadingImages)
        .onChange(of: pickerItems) { items in
            loadImages(from: items)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// زر الاختيار — نفس بطاقات «المصدر» في مربّع المكتبة (إطار متقطّع بلون القسم)
    private var pickerCard: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 30,
            matching: .images
        ) {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(tint.opacity(0.14))
                    Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)   // زخرفة — نص الزر يُقرأ
                Text(images.isEmpty
                     ? L10n.t("اختر صوراً", "Select photos")
                     : L10n.t("تغيير الاختيار (\(images.count))", "Change selection (\(images.count))"))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// الصور المختارة في صفوف من أربعة — مربّعات متساوية بعرض القسم
    private var previewGrid: some View {
        let items = Array(images.enumerated())
        return VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: items.count, by: previewColumns)), id: \.self) { start in
                let row = Array(items[start..<min(start + previewColumns, items.count)])
                HStack(spacing: 6) {
                    ForEach(row, id: \.offset) { _, img in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                    ForEach(0..<(previewColumns - row.count), id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
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
