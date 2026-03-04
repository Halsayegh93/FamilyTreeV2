import SwiftUI

struct FamilyPhotoAlbumsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var allPhotos: [MemberGalleryPhoto] = []
    @State private var isLoading = true
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedPhoto: MemberGalleryPhoto? = nil
    @State private var showPhotoViewer = false
    @State private var viewMode: ViewMode = .grid

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
            guard let member = authVM.allMembers.first(where: { $0.id == memberId }) else { return nil }
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

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                if isLoading {
                    loadingView
                } else if allPhotos.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DS.Spacing.xl) {
                            statsBar
                            viewModePicker
                            
                            if viewMode == .grid {
                                if selectedMemberId != nil {
                                    memberFilterChip
                                }
                                photoGridView
                            } else {
                                albumsListView
                            }
                        }
                        .padding(.bottom, DS.Spacing.xxxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("صور العائلة", "Family Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .foregroundColor(DS.Color.primary)
                }
            }
            .environment(\.layoutDirection, langManager.layoutDirection)
            .task { await loadPhotos() }
            .fullScreenCover(isPresented: $showPhotoViewer) {
                if let photo = selectedPhoto {
                    familyPhotoViewer(photo: photo)
                }
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: DS.Spacing.lg) {
            statPill(
                icon: "photo.fill",
                value: "\(allPhotos.count)",
                label: L10n.t("صورة", "photos")
            )
            statPill(
                icon: "person.2.fill",
                value: "\(membersWithPhotos.count)",
                label: L10n.t("عضو", "members")
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(DS.Color.primary)
            Text(value)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(DS.Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - View Mode Picker

    private var viewModePicker: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(DS.Anim.snappy) {
                        viewMode = mode
                        if mode == .albums { selectedMemberId = nil }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: mode.icon)
                            .font(DS.Font.scaled(13, weight: .semibold))
                        Text(mode.label)
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(viewMode == mode ? .white : DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(viewMode == mode ? DS.Color.gradientPrimary : LinearGradient(colors: [DS.Color.surface], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(viewMode == mode ? Color.clear : DS.Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(DSScaleButtonStyle())
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Member Filter Chip

    private var memberFilterChip: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let memberId = selectedMemberId,
               let member = authVM.allMembers.first(where: { $0.id == memberId }) {
                HStack(spacing: DS.Spacing.sm) {
                    memberAvatar(member, size: 24)
                    Text(member.fullName)
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.primary)
                    Text("(\(filteredPhotos.count))")
                        .font(DS.Font.caption2)
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
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.primary.opacity(0.08))
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Photo Grid

    private var photoGridView: some View {
        let columns = [
            GridItem(.flexible(), spacing: DS.Spacing.xs),
            GridItem(.flexible(), spacing: DS.Spacing.xs),
            GridItem(.flexible(), spacing: DS.Spacing.xs)
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
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.xxxxl)
            } else {
                LazyVGrid(columns: columns, spacing: DS.Spacing.xs) {
                    ForEach(filteredPhotos) { photo in
                        photoCell(photo)
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
            }
        }
    }

    private func photoCell(_ photo: MemberGalleryPhoto) -> some View {
        Button {
            selectedPhoto = photo
            showPhotoViewer = true
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    AsyncImage(url: URL(string: photo.photoURL)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
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
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    // Member name overlay at bottom
                    VStack {
                        Spacer()
                        if selectedMemberId == nil,
                           let member = authVM.allMembers.first(where: { $0.id == photo.memberId }) {
                            Text(member.firstName)
                                .font(DS.Font.scaled(10, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.6)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Albums List

    private var albumsListView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ForEach(membersWithPhotos, id: \.member.id) { item in
                albumCard(member: item.member, photos: item.photos)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func albumCard(member: FamilyMember, photos: [MemberGalleryPhoto]) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) {
                selectedMemberId = member.id
                viewMode = .grid
            }
        } label: {
            VStack(spacing: 0) {
                // Album cover — show first 4 photos in grid
                let coverPhotos = Array(photos.prefix(4))
                let gridColumns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(coverPhotos) { photo in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                AsyncImage(url: URL(string: photo.photoURL)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        DS.Color.surface
                                    }
                                }
                            )
                            .clipped()
                    }
                    
                    // Fill empty slots
                    if coverPhotos.count < 4 {
                        ForEach(0..<(4 - coverPhotos.count), id: \.self) { _ in
                            DS.Color.surface
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))

                // Member info
                HStack(spacing: DS.Spacing.sm) {
                    memberAvatar(member, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.fullName)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                        Text("\(photos.count) " + L10n.t("صورة", "photos"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(DS.Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Photo Viewer

    private func familyPhotoViewer(photo: MemberGalleryPhoto) -> some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
                .onTapGesture { showPhotoViewer = false }

            if let url = URL(string: photo.photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if phase.error != nil {
                        VStack(spacing: DS.Spacing.md) {
                            Image(systemName: "photo.trianglebadge.exclamationmark")
                                .font(DS.Font.scaled(40))
                                .foregroundColor(.white.opacity(0.5))
                            Text(L10n.t("تعذر تحميل الصورة", "Failed to load photo"))
                                .font(DS.Font.callout)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
            }

            // Top bar
            HStack {
                Button { showPhotoViewer = false } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Spacer()

                if let member = authVM.allMembers.first(where: { $0.id == photo.memberId }) {
                    HStack(spacing: DS.Spacing.sm) {
                        memberAvatar(member, size: 28)
                        Text(member.firstName)
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xl)
        }
    }

    // MARK: - Helper Views

    private func memberAvatar(_ member: FamilyMember, size: CGFloat) -> some View {
        Group {
            if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
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
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(DS.Font.scaled(50))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد صور حالياً", "No photos yet"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
            Text(L10n.t("يمكن لأفراد العائلة إضافة صور من ملفاتهم الشخصية", "Family members can add photos from their profiles"))
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxxxl)
        }
    }

    // MARK: - Data

    private func loadPhotos() async {
        isLoading = true
        let photos = await authVM.fetchAllGalleryPhotos()
        await MainActor.run {
            allPhotos = photos
            isLoading = false
        }
    }
}
