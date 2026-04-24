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
    @State private var showPhotoPicker = false
    @State private var appeared = false

    // MARK: - Computed

    private var membersWithPhotos: [(member: FamilyMember, count: Int)] {
        let grouped = Dictionary(grouping: allPhotos, by: { $0.memberId })
        return grouped.compactMap { (memberId, photos) in
            guard let member = memberVM.member(byId: memberId) else { return nil }
            return (member: member, count: photos.count)
        }
        .sorted { $0.count > $1.count }
    }

    private var filteredPhotos: [MemberGalleryPhoto] {
        if let memberId = selectedMemberId {
            return allPhotos.filter { $0.memberId == memberId }
        }
        return allPhotos
    }

    private var canDeleteCurrentPhoto: Bool {
        guard let currentPhoto = filteredPhotos[safe: selectedPhotoIndex] else { return false }
        // المدير + المراقب + المالك يقدرون يحذفون أي صورة
        if authVM.canDeleteComments { return true }
        // صاحب الصورة يقدر يحذفها
        if let currentUser = authVM.currentUser, currentPhoto.memberId == currentUser.id { return true }
        return false
    }

    private var isCurrentPhotoOwner: Bool {
        guard let currentPhoto = filteredPhotos[safe: selectedPhotoIndex],
              let currentUser = authVM.currentUser else { return false }
        return currentPhoto.memberId == currentUser.id
    }

    // MARK: - Body

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
                    // عنوان + عدد الصور
                    HStack {
                        Text("\(filteredPhotos.count) " + L10n.t("صورة", "photos"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        Spacer()

                        // فلتر العضو لو موجود
                        if let memberId = selectedMemberId, let member = memberVM.member(byId: memberId) {
                            HStack(spacing: DS.Spacing.xs) {
                                Text(member.firstName)
                                    .font(DS.Font.scaled(12, weight: .bold))
                                    .foregroundColor(DS.Color.primary)
                                Button {
                                    withAnimation(DS.Anim.snappy) { selectedMemberId = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(DS.Font.scaled(14))
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                                .accessibilityLabel(L10n.t("إزالة الفلتر", "Clear filter"))
                            }
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .opacity(appeared ? 1 : 0)

                    // Photo grid
                    photoGridView
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                }
            }

            // Upload progress
            if isUploading {
                VStack {
                    Spacer()
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView().tint(DS.Color.textOnPrimary)
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

            // FAB
            if !allPhotos.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        addPhotoButton
                            .padding(.trailing, DS.Spacing.xl)
                            .padding(.bottom, DS.Spacing.lg)
                    }
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
        .task { await loadPhotos() }
        .onAppear {
            guard !appeared else { return }
            withAnimation(DS.Anim.smooth.delay(0.15)) { appeared = true }
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
        .onChange(of: selectedGalleryItems) { items in
            handleGalleryImagesChange(items)
        }
        .sheet(isPresented: $showPendingPreview) {
            pendingPreviewSheet
        }
        .alert(L10n.t("الوصول للصور مطلوب", "Photo Access Required"), isPresented: $showPermissionDenied) {
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

    // MARK: - Stories Bar

    private var storiesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.lg) {
                // "الكل" — أول عنصر
                storyCircle(
                    name: L10n.t("الكل", "All"),
                    avatarView: AnyView(
                        Image(systemName: "square.grid.3x3.fill")
                            .font(DS.Font.scaled(20, weight: .semibold))
                            .foregroundColor(selectedMemberId == nil ? DS.Color.textOnPrimary : DS.Color.primary)
                    ),
                    isSelected: selectedMemberId == nil,
                    count: allPhotos.count
                ) {
                    withAnimation(DS.Anim.snappy) { selectedMemberId = nil }
                }

                // أعضاء عندهم صور
                ForEach(membersWithPhotos, id: \.member.id) { item in
                    storyCircle(
                        name: item.member.firstName,
                        avatarView: AnyView(memberAvatar(item.member, size: 56)),
                        isSelected: selectedMemberId == item.member.id,
                        count: item.count
                    ) {
                        withAnimation(DS.Anim.snappy) {
                            selectedMemberId = selectedMemberId == item.member.id ? nil : item.member.id
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .background(DS.Color.background)
    }

    private func storyCircle(name: String, avatarView: AnyView, isSelected: Bool, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    // حلقة gradient للمختار
                    if isSelected {
                        Circle()
                            .stroke(DS.Color.gradientPrimary, lineWidth: 3)
                            .frame(width: 66, height: 66)
                    } else {
                        Circle()
                            .stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 66, height: 66)
                    }

                    // الصورة/الأيقونة
                    if name == L10n.t("الكل", "All") {
                        Circle()
                            .fill(isSelected ? DS.Color.gradientPrimary : LinearGradient(colors: [DS.Color.surface, DS.Color.surface], startPoint: .top, endPoint: .bottom))
                            .frame(width: 58, height: 58)
                            .overlay(avatarView)
                    } else {
                        avatarView
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                    }

                    // عدد الصور
                    if count > 0 {
                        Text("\(count)")
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.primary)
                            .clipShape(Capsule())
                            .offset(x: 20, y: 22)
                    }
                }

                Text(name)
                    .font(DS.Font.scaled(11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo Grid

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
                    .padding(.bottom, 100)
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
                                Image(systemName: "photo").foregroundColor(DS.Color.textTertiary)
                            }
                        } else {
                            ZStack {
                                DS.Color.surface
                                ProgressView().tint(DS.Color.primary)
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
                        .accessibilityLabel(L10n.t("حذف", "Delete"))
                    }
                }
                // بادج pending
                .overlay(alignment: .bottomLeading) {
                    if photo.isPending {
                        Text(L10n.t("معلق", "Pending"))
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Color.warning)
                            .clipShape(Capsule())
                            .padding(DS.Spacing.xs)
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
                        ProgressView().scaleEffect(1.3).tint(DS.Color.primary)
                        Text(L10n.t("جاري تحميل الصورة...", "Loading photo..."))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                } else {
                    TabView(selection: $selectedPhotoIndex) {
                        ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, p in
                            Group {
                                if let url = URL(string: p.photoURL) {
                                    CachedAsyncPhaseImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFit()
                                                .frame(maxWidth: .infinity)
                                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                                .padding(.horizontal, DS.Spacing.sm)
                                        } else if phase.error != nil {
                                            VStack(spacing: DS.Spacing.md) {
                                                Image(systemName: "photo.trianglebadge.exclamationmark")
                                                    .font(DS.Font.scaled(40)).foregroundColor(DS.Color.textTertiary)
                                                Text(L10n.t("تعذر تحميل الصورة", "Failed to load photo"))
                                                    .font(DS.Font.callout).foregroundColor(DS.Color.textSecondary)
                                            }
                                        } else {
                                            VStack(spacing: DS.Spacing.sm) {
                                                ProgressView().scaleEffect(1.2).tint(DS.Color.primary)
                                                Text(L10n.t("جاري تحميل الصورة...", "Loading photo..."))
                                                    .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                                            }
                                        }
                                    }
                                } else { Color.clear }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: filteredPhotos.count > 1 ? .automatic : .never))

                    // Caption + member info
                    if let currentPhoto = filteredPhotos[safe: selectedPhotoIndex],
                       let member = memberVM.member(byId: currentPhoto.memberId) {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            if isEditingCaption {
                                HStack(spacing: DS.Spacing.sm) {
                                    TextField(L10n.t("أضف تعليق...", "Add a caption..."), text: $editingCaptionText)
                                        .font(DS.Font.callout).foregroundColor(DS.Color.textPrimary)
                                    Button {
                                        Task {
                                            let newCaption = editingCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            let success = await memberVM.updateGalleryPhotoCaption(photoId: currentPhoto.id, caption: newCaption.isEmpty ? nil : newCaption)
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
                                    Text(caption).font(DS.Font.callout).foregroundColor(DS.Color.textPrimary).multilineTextAlignment(.leading)
                                    if isCurrentPhotoOwner {
                                        Button { editingCaptionText = caption; isEditingCaption = true } label: {
                                            Image(systemName: "pencil.circle.fill").font(DS.Font.scaled(18)).foregroundColor(DS.Color.textTertiary)
                                        }
                                        .accessibilityLabel(L10n.t("تعديل", "Edit"))
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.xl)
                            } else if isCurrentPhotoOwner {
                                Button { editingCaptionText = ""; isEditingCaption = true } label: {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Image(systemName: "text.bubble").font(DS.Font.scaled(14))
                                        Text(L10n.t("أضف تعليق", "Add caption")).font(DS.Font.scaled(13, weight: .semibold))
                                    }
                                    .foregroundColor(DS.Color.textTertiary)
                                }
                                .padding(.horizontal, DS.Spacing.xl)
                            }

                            HStack(spacing: DS.Spacing.sm) {
                                memberAvatar(member, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.shortFullName)
                                        .font(DS.Font.scaled(13, weight: .bold))
                                        .foregroundColor(DS.Color.textPrimary).lineLimit(1)
                                    if filteredPhotos.count > 1 {
                                        Text("\(selectedPhotoIndex + 1) / \(filteredPhotos.count)")
                                            .font(DS.Font.caption2).foregroundColor(DS.Color.textSecondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DS.Spacing.xl)
                        }
                        .padding(.vertical, DS.Spacing.md)
                    }
                }
            }
            .background(DS.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { showPhotoViewer = false }
                        .font(DS.Font.calloutBold).foregroundColor(DS.Color.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if canDeleteCurrentPhoto {
                        Button {
                            if let currentPhoto = filteredPhotos[safe: selectedPhotoIndex] {
                                pendingDeletePhoto = currentPhoto
                                showPhotoViewer = false
                                Task { try? await Task.sleep(nanoseconds: 400_000_000); showDeletePhotoAlert = true }
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "trash").font(DS.Font.scaled(13, weight: .semibold))
                                Text(L10n.t("حذف", "Delete")).font(DS.Font.scaled(13, weight: .bold))
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
                withAnimation(DS.Anim.smooth) { isSheetLoading = false }
            }
        }
        .onChange(of: selectedPhotoIndex) { newIndex in
            isEditingCaption = false
            if let photo = filteredPhotos[safe: newIndex] { selectedPhoto = photo }
        }
    }

    // MARK: - Add Photo Button (FAB)

    private var addPhotoButton: some View {
        DSFloatingButton(icon: "plus") {
            checkPhotoPermission { showPhotoPicker = true }
        }
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
                                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                                Button {
                                    withAnimation {
                                        pendingImages.remove(at: idx)
                                        if idx < pendingCaptions.count { pendingCaptions.remove(at: idx) }
                                        if pendingPreviewIndex >= pendingImages.count { pendingPreviewIndex = max(0, pendingImages.count - 1) }
                                        if pendingImages.isEmpty { showPendingPreview = false }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(DS.Font.scaled(24, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                        .dsCardShadow()
                                }
                                .padding(DS.Spacing.md)
                                .accessibilityLabel(L10n.t("إزالة الصورة", "Remove photo"))
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
                                .font(DS.Font.caption1).fontWeight(.bold)
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.shadowHeavy)
                                .clipShape(Capsule())
                                .padding(DS.Spacing.md)
                        }
                    }
                }

                if pendingImages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, image in
                                Button { withAnimation { pendingPreviewIndex = idx } } label: {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                            .stroke(pendingPreviewIndex == idx ? DS.Color.primary : Color.clear, lineWidth: 2.5))
                                        .opacity(pendingPreviewIndex == idx ? 1 : 0.6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.bubble").font(DS.Font.scaled(16, weight: .semibold)).foregroundColor(DS.Color.textTertiary)
                    TextField(
                        L10n.t("تعليق الصورة \(pendingPreviewIndex + 1)...", "Caption for photo \(pendingPreviewIndex + 1)..."),
                        text: Binding(
                            get: { pendingCaptions[safe: pendingPreviewIndex] ?? "" },
                            set: { if pendingPreviewIndex < pendingCaptions.count { pendingCaptions[pendingPreviewIndex] = $0 } }
                        )
                    )
                    .font(DS.Font.callout).foregroundColor(DS.Color.textPrimary).id(pendingPreviewIndex)
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
                ) { uploadPendingImages() }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .background(DS.Color.background)
            .navigationTitle(L10n.t("معاينة الصور", "Preview Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        pendingImages = []; pendingCaptions = []; showPendingPreview = false
                    }
                    .font(DS.Font.calloutBold).foregroundColor(DS.Color.error)
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
            Circle().fill(DS.Color.primary.opacity(0.15)).frame(width: size, height: size)
            Text(String(member.firstName.prefix(1)))
                .font(DS.Font.scaled(size * 0.45, weight: .bold))
                .foregroundColor(DS.Color.primary)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView().scaleEffect(1.2)
            Text(L10n.t("جاري تحميل الصور...", "Loading photos..."))
                .font(DS.Font.callout).foregroundColor(DS.Color.textSecondary)
        }
    }

    private var emptyStateView: some View {
        DSEmptyState(
            icon: "photo.on.rectangle.angled",
            title: L10n.t("لا توجد صور حالياً", "No photos yet"),
            subtitle: L10n.t("كن أول من يضيف صوراً", "Be first to add photos"),
            buttonTitle: L10n.t("إضافة صور", "Add Photos"),
            buttonAction: { checkPhotoPermission { showPhotoPicker = true } },
            style: .halo
        )
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedGalleryItems, maxSelectionCount: 5, matching: .images)
    }

    private var errorStateView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle").font(DS.Font.scaled(40)).foregroundColor(DS.Color.warning)
            Text(L10n.t("تعذر تحميل الصور", "Failed to load photos"))
                .font(DS.Font.title3).foregroundColor(DS.Color.textSecondary)
            DSSecondaryButton(L10n.t("إعادة المحاولة", "Retry"), icon: "arrow.clockwise") {
                Task { await loadPhotos() }
            }
            .frame(width: 200)
        }
    }

    // MARK: - Data

    private func loadPhotos() async {
        isLoading = true; loadError = false
        let photos = await memberVM.fetchAllGalleryPhotos()
        await MainActor.run { allPhotos = photos; isLoading = false }
    }

    private func checkPhotoPermission(action: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited: action()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    if newStatus == .authorized || newStatus == .limited { action() }
                    else { showPermissionDenied = true }
                }
            }
        default: showPermissionDenied = true
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
                pendingImages = loaded; pendingPreviewIndex = 0
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
                _ = await memberVM.uploadMemberGalleryPhotoMulti(image: image, for: currentUser.id, caption: captionText.isEmpty ? nil : captionText)
            }
            await MainActor.run { pendingImages = []; pendingCaptions = []; isUploading = false }
            await loadPhotos()
        }
    }

    private func deletePhoto(_ photo: MemberGalleryPhoto) async {
        let success = await memberVM.deleteMemberGalleryPhotoMulti(photoId: photo.id, photoURL: photo.photoURL)
        if success { await loadPhotos() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
