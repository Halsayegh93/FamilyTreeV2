import SwiftUI
import PhotosUI
import Photos

struct FamilyPhotoAlbumsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var allPhotos: [MemberGalleryPhoto] = []
    @State private var isLoading = true
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedPhoto: MemberGalleryPhoto? = nil
    @State private var selectedPhotoIndex: Int = 0
    @State private var showPhotoViewer = false
    @State private var loadError = false
    @State private var viewMode: ViewMode = .grid

    // Photo upload states
    @State private var selectedGalleryItems: [PhotosPickerItem] = []
    @State private var pendingImages: [UIImage] = []
    @State private var showPendingPreview = false
    @State private var pendingPreviewIndex = 0
    @State private var isUploading = false
    @State private var showPermissionDenied = false
    @State private var showDeletePhotoAlert = false
    @State private var pendingDeletePhoto: MemberGalleryPhoto? = nil
    @State private var pendingCaptions: [String] = []
    @State private var isEditingCaption = false
    @State private var editingCaptionText: String = ""
    @State private var isSheetLoading = true

    enum ViewMode: String, CaseIterable {
        case grid, albums

        var label: String {
            switch self {
            case .grid: return L10n.t("الكل", "All")
            case .albums: return L10n.t("ألبومات", "Albums")
            }
        }

        var icon: String {
            switch self {
            case .grid: return "square.grid.3x3.fill"
            case .albums: return "person.2.square.stack.fill"
            }
        }
    }

    // MARK: - Computed

    private var membersWithPhotos: [(member: FamilyMember, photos: [MemberGalleryPhoto])] {
        let grouped = Dictionary(grouping: allPhotos, by: { $0.memberId })
        return grouped.compactMap { (memberId, photos) in
            guard let member = memberVM.member(byId: memberId) else { return nil }
            return (member: member, photos: photos.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") })
        }
        .sorted { $0.photos.count > $1.photos.count }
    }

    private var filteredPhotos: [MemberGalleryPhoto] {
        if let memberId = selectedMemberId {
            return allPhotos.filter { $0.memberId == memberId }
        }
        return allPhotos
    }

    /// Group photos by month for section headers
    private var photosByMonth: [(title: String, photos: [MemberGalleryPhoto])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        formatter.dateFormat = "MMMM yyyy"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        let grouped = Dictionary(grouping: filteredPhotos) { photo -> String in
            guard let dateStr = photo.createdAt,
                  let date = isoFormatter.date(from: dateStr) ?? isoFallback.date(from: dateStr) else {
                return L10n.t("غير محدد", "Unknown")
            }
            return formatter.string(from: date)
        }

        return grouped.map { (title: $0.key, photos: $0.value) }
            .sorted { first, second in
                guard let d1 = first.photos.first?.createdAt,
                      let d2 = second.photos.first?.createdAt else { return false }
                return d1 > d2
            }
    }

    /// Admin/supervisor can delete any photo, owner can delete their own
    private var canDeleteCurrentPhoto: Bool {
        guard let currentPhoto = filteredPhotos[safe: selectedPhotoIndex] else { return false }
        if authVM.canModerate { return true }
        if let currentUser = authVM.currentUser, currentPhoto.memberId == currentUser.id { return true }
        return false
    }

    /// Only the photo owner can edit caption
    private var isCurrentPhotoOwner: Bool {
        guard let currentPhoto = filteredPhotos[safe: selectedPhotoIndex],
              let currentUser = authVM.currentUser else { return false }
        return currentPhoto.memberId == currentUser.id
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if loadError {
                errorStateView
            } else if allPhotos.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    // Top bar with mode picker and stats
                    topBar
                    
                    // Member filter chip
                    if selectedMemberId != nil && viewMode == .grid {
                        memberFilterChip
                    }

                    // Content
                    if viewMode == .grid {
                        photoGridView
                    } else {
                        albumsListView
                    }
                }
            }

            // Upload progress overlay
            if isUploading {
                VStack {
                    Spacer()
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView()
                            .tint(.white)
                        Text(L10n.t("جاري رفع الصور...", "Uploading photos..."))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.primary)
                    .clipShape(Capsule())
                    .dsCardShadow()
                    .padding(.bottom, 80)
                }
            }

            // FAB for adding photos
            if !allPhotos.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        addPhotoButton
                            .padding(.trailing, DS.Spacing.xl)
                            .padding(.bottom, DS.Spacing.xl)
                    }
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
        .task {
            await loadPhotos()
        }
        .sheet(isPresented: $showPhotoViewer) {
            if let photo = selectedPhoto {
                familyPhotoViewer(photo: photo)
            }
        }
        .alert(L10n.t("حذف الصورة؟", "Delete photo?"), isPresented: $showDeletePhotoAlert) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let photo = pendingDeletePhoto {
                    pendingDeletePhoto = nil
                    Task { await deletePhoto(photo) }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingDeletePhoto = nil }
        }
        .photosPicker(isPresented: Binding(
            get: { false },
            set: { _ in }
        ), selection: $selectedGalleryItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: selectedGalleryItems) { _, items in
            handleGalleryImagesChange(items)
        }
        .sheet(isPresented: $showPendingPreview) {
            pendingPreviewSheet
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
                "يحتاج التطبيق إذن الوصول لمكتبة الصور لاختيار صور. يرجى السماح من الإعدادات.",
                "The app needs access to your photo library to select photos. Please allow access in Settings."
            ))
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                // View mode picker
                HStack(spacing: 2) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                viewMode = mode
                                if mode == .albums { selectedMemberId = nil }
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: mode.icon)
                                    .font(DS.Font.scaled(12, weight: .semibold))
                                Text(mode.label)
                                    .font(DS.Font.scaled(13, weight: .bold))
                            }
                            .foregroundColor(viewMode == mode ? .white : DS.Color.textSecondary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.sm)
                            .background(viewMode == mode ? DS.Color.primary : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                Spacer()

                // Photo count
                Text("\(allPhotos.count) " + L10n.t("صورة", "photos"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .background(DS.Color.background)
    }

    // MARK: - Member Filter Chip

    private var memberFilterChip: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let memberId = selectedMemberId,
               let member = memberVM.member(byId: memberId) {
                HStack(spacing: DS.Spacing.sm) {
                    memberAvatar(member, size: 22)
                    Text(member.fullName)
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                        .lineLimit(1)
                    Text("(\(filteredPhotos.count))")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Button {
                        withAnimation(DS.Anim.snappy) { selectedMemberId = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(16))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.primary.opacity(0.08))
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - Photo Grid (Native Phone Style)

    private var photoGridView: some View {
        let columns = [
            GridItem(.flexible(), spacing: 1.5),
            GridItem(.flexible(), spacing: 1.5),
            GridItem(.flexible(), spacing: 1.5)
        ]

        return Group {
            if filteredPhotos.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "photo")
                        .font(DS.Font.scaled(32))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("لا توجد صور لهذا العضو", "No photos for this member"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, DS.Spacing.xxxxl)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 1.5) {
                        ForEach(filteredPhotos) { photo in
                            nativePhotoCell(photo)
                        }
                    }
                    .padding(.bottom, 100) // Space for FAB
                }
            }
        }
    }

    private func nativePhotoCell(_ photo: MemberGalleryPhoto) -> some View {
        Button {
            selectedPhoto = photo
            if let idx = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
                selectedPhotoIndex = idx
            }
            showPhotoViewer = true
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    CachedAsyncPhaseImage(url: URL(string: photo.photoURL)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            ZStack {
                                DS.Color.surface
                                Image(systemName: "photo")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        } else {
                            ZStack {
                                DS.Color.surface
                                VStack(spacing: DS.Spacing.xs) {
                                    ProgressView()
                                        .tint(DS.Color.primary)
                                    Text(L10n.t("جاري التحميل", "Loading"))
                                        .font(DS.Font.caption2)
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            }
                        }
                    }
                )
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if authVM.canModerate {
                        Button {
                            pendingDeletePhoto = photo
                            showDeletePhotoAlert = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(DS.Color.textOnPrimary)
                                .frame(width: 26, height: 26)
                                .background(DS.Color.error.opacity(0.85))
                                .clipShape(Circle())
                        }
                        .padding(DS.Spacing.xs)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Albums List

    private var albumsListView: some View {
        ScrollView(showsIndicators: false) {
            let columns = [
                GridItem(.flexible(), spacing: DS.Spacing.lg),
                GridItem(.flexible(), spacing: DS.Spacing.lg)
            ]

            LazyVGrid(columns: columns, spacing: DS.Spacing.lg) {
                ForEach(membersWithPhotos, id: \.member.id) { item in
                    albumThumbnail(member: item.member, photos: item.photos)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, 100)
        }
    }

    private func albumThumbnail(member: FamilyMember, photos: [MemberGalleryPhoto]) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) {
                selectedMemberId = member.id
                viewMode = .grid
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // Album cover — 2x2 grid preview
                let coverPhotos = Array(photos.prefix(4))
                let gridColumns = [GridItem(.flexible(), spacing: 1.5), GridItem(.flexible(), spacing: 1.5)]

                GeometryReader { geo in
                    LazyVGrid(columns: gridColumns, spacing: 1.5) {
                        ForEach(0..<4, id: \.self) { idx in
                            if idx < coverPhotos.count {
                                CachedAsyncPhaseImage(url: URL(string: coverPhotos[idx].photoURL)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        DS.Color.surface
                                    }
                                }
                                .frame(
                                    width: (geo.size.width - 1.5) / 2,
                                    height: (geo.size.width - 1.5) / 2
                                )
                                .clipped()
                            } else {
                                DS.Color.surface
                                    .frame(
                                        width: (geo.size.width - 1.5) / 2,
                                        height: (geo.size.width - 1.5) / 2
                                    )
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                // Member info below cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.fullName)
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Text("\(photos.count)")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo Viewer

    private func familyPhotoViewer(photo: MemberGalleryPhoto) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSheetLoading {
                    Spacer()
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(DS.Color.primary)
                        Text(L10n.t("جاري تحميل الصورة...", "Loading photo..."))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                } else {
                // Photo display
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, p in
                        Group {
                            if let url = URL(string: p.photoURL) {
                                CachedAsyncPhaseImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                            .padding(.horizontal, DS.Spacing.sm)
                                    } else if phase.error != nil {
                                        VStack(spacing: DS.Spacing.md) {
                                            Image(systemName: "photo.trianglebadge.exclamationmark")
                                                .font(DS.Font.scaled(40))
                                                .foregroundColor(DS.Color.textTertiary)
                                            Text(L10n.t("تعذر تحميل الصورة", "Failed to load photo"))
                                                .font(DS.Font.callout)
                                                .foregroundColor(DS.Color.textSecondary)
                                        }
                                    } else {
                                        VStack(spacing: DS.Spacing.sm) {
                                            ProgressView()
                                                .scaleEffect(1.2)
                                                .tint(DS.Color.primary)
                                            Text(L10n.t("جاري تحميل الصورة...", "Loading photo..."))
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textSecondary)
                                        }
                                    }
                                }
                            } else {
                                Color.clear
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: filteredPhotos.count > 1 ? .automatic : .never))

                // Caption + member info
                if let currentPhoto = filteredPhotos[safe: selectedPhotoIndex],
                   let member = memberVM.member(byId: currentPhoto.memberId) {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        // Caption — editable for owner
                        if isEditingCaption {
                            HStack(spacing: DS.Spacing.sm) {
                                TextField(L10n.t("أضف تعليق...", "Add a caption..."), text: $editingCaptionText)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                Button {
                                    Task {
                                        let newCaption = editingCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let success = await memberVM.updateGalleryPhotoCaption(
                                            photoId: currentPhoto.id,
                                            caption: newCaption.isEmpty ? nil : newCaption
                                        )
                                        if success { await loadPhotos() }
                                        isEditingCaption = false
                                    }
                                } label: {
                                    Text(L10n.t("حفظ", "Save"))
                                        .font(DS.Font.scaled(13, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .padding(.horizontal, DS.Spacing.md)
                                        .padding(.vertical, DS.Spacing.xs)
                                        .background(DS.Color.primary)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, DS.Spacing.xl)
                        } else if let caption = currentPhoto.caption, !caption.isEmpty {
                            HStack(spacing: DS.Spacing.sm) {
                                Text(caption)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .multilineTextAlignment(.leading)
                                if isCurrentPhotoOwner {
                                    Button {
                                        editingCaptionText = caption
                                        isEditingCaption = true
                                    } label: {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(DS.Font.scaled(18))
                                            .foregroundColor(DS.Color.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, DS.Spacing.xl)
                        } else if isCurrentPhotoOwner {
                            Button {
                                editingCaptionText = ""
                                isEditingCaption = true
                            } label: {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "text.bubble")
                                        .font(DS.Font.scaled(14))
                                    Text(L10n.t("أضف تعليق", "Add caption"))
                                        .font(DS.Font.scaled(13, weight: .semibold))
                                }
                                .foregroundColor(DS.Color.textTertiary)
                            }
                            .padding(.horizontal, DS.Spacing.xl)
                        }

                        // Member info
                        HStack(spacing: DS.Spacing.sm) {
                            memberAvatar(member, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.fullName)
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(1)
                                if filteredPhotos.count > 1 {
                                    Text("\(selectedPhotoIndex + 1) / \(filteredPhotos.count)")
                                        .font(DS.Font.caption2)
                                        .foregroundColor(DS.Color.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.xl)
                    }
                    .padding(.vertical, DS.Spacing.md)
                }
                } // end else (not loading)
            }
            .background(DS.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) {
                        showPhotoViewer = false
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if canDeleteCurrentPhoto {
                        Button {
                            if let currentPhoto = filteredPhotos[safe: selectedPhotoIndex] {
                                pendingDeletePhoto = currentPhoto
                                showPhotoViewer = false
                                Task {
                                    try? await Task.sleep(nanoseconds: 400_000_000)
                                    showDeletePhotoAlert = true
                                }
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "trash")
                                    .font(DS.Font.scaled(13, weight: .semibold))
                                Text(L10n.t("حذف", "Delete"))
                                    .font(DS.Font.scaled(13, weight: .bold))
                            }
                            .foregroundColor(DS.Color.error)
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
        .presentationDetents([.fraction(0.65), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            isSheetLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(DS.Anim.smooth) {
                    isSheetLoading = false
                }
            }
        }
        .onChange(of: selectedPhotoIndex) { _, newIndex in
            isEditingCaption = false
            if let photo = filteredPhotos[safe: newIndex] {
                selectedPhoto = photo
            }
        }
    }

    // MARK: - Add Photo Button (FAB)

    @State private var showPhotoPicker = false

    private var addPhotoButton: some View {
        Button {
            checkPhotoPermission {
                showPhotoPicker = true
            }
        } label: {
            Image(systemName: "plus")
                .font(DS.Font.scaled(22, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: 56, height: 56)
                .background(DS.Color.gradientPrimary)
                .clipShape(Circle())
                .dsCardShadow()
        }
        .buttonStyle(DSBoldButtonStyle())
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedGalleryItems, maxSelectionCount: 5, matching: .images)
    }

    // MARK: - Pending Preview Sheet

    private var pendingPreviewSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                                        if idx < pendingCaptions.count {
                                            pendingCaptions.remove(at: idx)
                                        }
                                        if pendingPreviewIndex >= pendingImages.count {
                                            pendingPreviewIndex = max(0, pendingImages.count - 1)
                                        }
                                        if pendingImages.isEmpty { showPendingPreview = false }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(DS.Font.scaled(24, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .shadow(color: DS.Color.shadowDense, radius: 4, x: 0, y: 2)
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
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.shadowOverlay)
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
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }

                // Caption input per photo
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.bubble")
                        .font(DS.Font.scaled(16, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                    TextField(
                        L10n.t("تعليق الصورة \(pendingPreviewIndex + 1)...", "Caption for photo \(pendingPreviewIndex + 1)..."),
                        text: Binding(
                            get: { pendingCaptions[safe: pendingPreviewIndex] ?? "" },
                            set: { newValue in
                                if pendingPreviewIndex < pendingCaptions.count {
                                    pendingCaptions[pendingPreviewIndex] = newValue
                                }
                            }
                        )
                    )
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .id(pendingPreviewIndex)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .padding(.horizontal, DS.Spacing.lg)

                Spacer()

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
                        pendingCaptions = []
                        showPendingPreview = false
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    // MARK: - Helper Views

    private func memberAvatar(_ member: FamilyMember, size: CGFloat) -> some View {
        Group {
            if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                CachedAsyncPhaseImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsCircle(member, size: size)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialsCircle(member, size: size)
            }
        }
    }

    private func initialsCircle(_ member: FamilyMember, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(DS.Color.primary.opacity(0.15))
                .frame(width: size, height: size)
            Text(String(member.firstName.prefix(1)))
                .font(DS.Font.scaled(size * 0.45, weight: .bold))
                .foregroundColor(DS.Color.primary)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
            Text(L10n.t("جاري تحميل الصور...", "Loading photos..."))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(DS.Color.primary.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.Font.scaled(44, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }
            
            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("لا توجد صور حالياً", "No photos yet"))
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("كن أول من يضيف صوراً لمعرض العائلة", "Be the first to add photos to the family gallery"))
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxxl)
            }

            // Add photos button
            Button {
                checkPhotoPermission { showPhotoPicker = true }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(DS.Font.scaled(18, weight: .bold))
                    Text(L10n.t("إضافة صور", "Add Photos"))
                        .font(DS.Font.calloutBold)
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.gradientPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(DSBoldButtonStyle())
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedGalleryItems, maxSelectionCount: 5, matching: .images)
            
            Spacer()
        }
    }

    private var errorStateView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(DS.Font.scaled(40))
                .foregroundColor(DS.Color.warning)
            Text(L10n.t("تعذر تحميل الصور", "Failed to load photos"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)
            DSSecondaryButton(L10n.t("إعادة المحاولة", "Retry"), icon: "arrow.clockwise") {
                Task { await loadPhotos() }
            }
            .frame(width: 200)
        }
    }

    // MARK: - Data

    private func loadPhotos() async {
        isLoading = true
        loadError = false
        let photos = await memberVM.fetchAllGalleryPhotos()
        await MainActor.run {
            allPhotos = photos
            isLoading = false
        }
    }

    // MARK: - Photo Upload Logic

    private func checkPhotoPermission(action: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            action()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
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

    private func handleGalleryImagesChange(_ items: [PhotosPickerItem]) {
        Task {
            guard !items.isEmpty else { return }
            var loaded: [UIImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImg = UIImage(data: data) else { continue }
                loaded.append(uiImg)
            }
            await MainActor.run {
                pendingImages = loaded
                pendingPreviewIndex = 0
                pendingCaptions = Array(repeating: "", count: loaded.count)
                if !loaded.isEmpty { showPendingPreview = true }
                self.selectedGalleryItems = []
            }
        }
    }

    private func uploadPendingImages() {
        guard let currentUser = authVM.currentUser else { return }
        let captions = pendingCaptions
        Task {
            await MainActor.run { isUploading = true; showPendingPreview = false }
            for (index, image) in pendingImages.enumerated() {
                let captionText = (captions[safe: index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let caption: String? = captionText.isEmpty ? nil : captionText
                _ = await memberVM.uploadMemberGalleryPhotoMulti(image: image, for: currentUser.id, caption: caption)
            }
            await MainActor.run {
                pendingImages = []
                pendingCaptions = []
                isUploading = false
            }
            await loadPhotos()
        }
    }

    private func deletePhoto(_ photo: MemberGalleryPhoto) async {
        let success = await memberVM.deleteMemberGalleryPhotoMulti(photoId: photo.id, photoURL: photo.photoURL)
        if success {
            await loadPhotos()
        }
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
