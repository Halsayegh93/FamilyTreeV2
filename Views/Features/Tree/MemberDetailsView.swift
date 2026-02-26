import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let member: FamilyMember
    @State private var showAdminControl = false
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem? = nil
    @State private var localPreviewImage: UIImage? = nil
    @State private var showAvatarPicker = false
    @State private var selectedAvatarItem: PhotosPickerItem? = nil
    @State private var localAvatarPreviewImage: UIImage? = nil
    @State private var avatarURL: String? = nil
    @State private var galleryPhotoURL: String? = nil
    @State private var showDeleteGalleryPhotoAlert = false
    @State private var showDeleteAvatarAlert = false
    @State private var selectedTab = 0 // 0: البيانات، 1: الصور
    @State private var showAvatarPreview = false
    @State private var avatarPreviewScale: CGFloat = 1.0
    @State private var lastAvatarPreviewScale: CGFloat = 1.0

    var isAdminOrSupervisor: Bool {
        let role = authVM.currentUser?.role
        return role == .admin || role == .supervisor
    }

    var isManager: Bool {
        authVM.currentUser?.role == .admin
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                // Decorative gradient circles
                GeometryReader { geo in
                    Circle()
                        .fill(DS.Color.primary.opacity(0.08))
                        .frame(width: 260, height: 260)
                        .blur(radius: 60)
                        .offset(x: -80, y: -60)

                    Circle()
                        .fill(DS.Color.accent.opacity(0.08))
                        .frame(width: 200, height: 200)
                        .blur(radius: 50)
                        .offset(x: geo.size.width - 120, y: geo.size.height - 200)
                }
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {

                        if member.isDeleted {
                            // عرض رسالة للعضو المحذوف
                            VStack(spacing: DS.Spacing.xxl) {
                                Spacer(minLength: 80)
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 100, height: 100)
                                    Image(systemName: "person.slash.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.gray)
                                }
                                Text(L10n.t("هذا العضو حذف حسابه", "This member deleted their account"))
                                    .font(DS.Font.headline)
                                    .foregroundColor(DS.Color.textSecondary)
                                Text(L10n.t("البيانات الشخصية لم تعد متوفرة", "Personal data is no longer available"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textTertiary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else if selectedTab == 0 {
                            personalInfoTab
                                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .opacity))
                        } else {
                            photosTab
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, DS.Spacing.xl)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // زر التعديل (يسار)
                ToolbarItem(placement: .topBarLeading) {
                    if isAdminOrSupervisor, !member.isDeleted {
                        Button { showAdminControl = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(DS.Spacing.sm)
                                .background(DS.Color.gradientPrimary)
                                .clipShape(Circle())
                                .dsGlowShadow()
                        }
                    }
                }

                // مفتاح الأقسام في المنتصف
                ToolbarItem(placement: .principal) {
                    if member.isDeleted {
                        Text(L10n.t("عضو محذوف", "Deleted Member"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(.gray)
                    } else {
                        Picker("", selection: $selectedTab) {
                            Text(L10n.t("البيانات", "Info")).tag(0)
                            Text(L10n.t("الصور", "Photos")).tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .tint(DS.Color.primary)
                    }
                }

                // زر الإغلاق (يمين)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                            .padding(DS.Spacing.sm)
                            .background(DS.Color.surfaceElevated)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .sheet(isPresented: $showAdminControl) {
                AdminMemberDetailSheet(member: member)
            }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedImageItem, matching: .images)
            .onChange(of: selectedImageItem) { _, newValue in
                handleImageChange(newValue)
            }
            .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
            .onChange(of: selectedAvatarItem) { _, newValue in
                handleAvatarImageChange(newValue)
            }
            .onAppear {
                galleryPhotoURL = member.photoURL
                avatarURL = member.avatarUrl
            }
            .alert(L10n.t("حذف الصورة", "Delete Photo"), isPresented: $showDeleteGalleryPhotoAlert) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task { await deleteGalleryPhoto() }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("هل تريد حذف صورة المعرض لهذا العضو؟", "Delete gallery photo for this member?"))
            }
            .alert(L10n.t("حذف صورة البروفايل", "Delete Profile Photo"), isPresented: $showDeleteAvatarAlert) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task { await deleteAvatarPhoto() }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t("هل تريد حذف صورة البروفايل لهذا العضو؟", "Delete profile photo for this member?"))
            }
            .fullScreenCover(isPresented: $showAvatarPreview) {
                avatarPreviewOverlay
            }
        }
    }

    // MARK: - التبويبات

    private var personalInfoTab: some View {
        VStack(spacing: DS.Spacing.xxl) {
            headerSection

            HStack(spacing: DS.Spacing.md) {
                if let birth = member.birthDate, !birth.isEmpty {
                    modernCompactCard(icon: "calendar", title: L10n.t("الميلاد", "Birth"), value: birth, color: DS.Color.primary)
                }

                if member.isDeceased == true {
                    let deathValue = (member.deathDate?.isEmpty == false) ? (member.deathDate ?? L10n.t("رحمه الله", "Rest in peace")) : L10n.t("رحمه الله", "Rest in peace")
                    modernCompactCard(icon: "heart.fill", title: L10n.t("الوفاة", "Death"), value: deathValue, color: .gray)
                } else if let phone = member.phoneNumber, !phone.isEmpty {
                    let shouldHidePhone = (member.isPhoneHidden == true) && (member.id != authVM.currentUser?.id) && !isAdminOrSupervisor // optionally allow admin to view
                    if !shouldHidePhone {
                        modernCompactCard(icon: "phone.fill", title: L10n.t("الهاتف", "Phone"), value: KuwaitPhone.display(phone), color: DS.Color.success)
                    } else {
                        modernCompactCard(icon: "phone.fill", title: L10n.t("الهاتف", "Phone"), value: L10n.t("مخفي", "Hidden"), color: .gray)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - قسم الصور المحدث
    private var photosTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack {
                Text(L10n.t("المعرض والوثائق", "Gallery & Documents"))
                    .font(DS.Font.calloutBold)
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {

                // زر إضافة صورة
                if isAdminOrSupervisor {
                    Button(action: { showImagePicker = true }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.xl)
                                .fill(DS.Color.surface)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.xl)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [DS.Color.primary, DS.Color.accent],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )

                            VStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(DS.Color.gradientPrimary)
                                Text(L10n.t("إضافة صورة", "Add Photo"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.primary)
                            }
                        }
                        .dsCardShadow()
                    }
                }

                // عرض الصور الحالية
                if let uiImage = localPreviewImage {
                    imageTile(
                        content: AnyView(
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        ),
                        title: L10n.t("الصورة الجديدة", "New Photo")
                    )
                }

                if let urlStr = galleryPhotoURL ?? member.photoURL, let url = URL(string: urlStr) {
                    imageTile(
                        content: AnyView(
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    ZStack {
                                        DS.Color.surface
                                        ProgressView().tint(DS.Color.primary)
                                    }
                                }
                            }
                        ),
                        title: L10n.t("صورة المعرض", "Gallery Photo")
                    )
                }
            }
            .padding(.horizontal)

            if let _ = galleryPhotoURL ?? member.photoURL, isAdminOrSupervisor {
                HStack {
                    Button(role: .destructive) {
                        showDeleteGalleryPhotoAlert = true
                    } label: {
                        Label(L10n.t("حذف صورة المعرض", "Delete Gallery Photo"), systemImage: "trash")
                            .font(DS.Font.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(DS.Color.error)
                    Spacer()
                }
                .padding(.horizontal)
            }

            if (galleryPhotoURL ?? member.photoURL) == nil && localPreviewImage == nil {
                emptyState(text: L10n.t("لا توجد صور حالياً", "No photos yet"), icon: "photo.on.rectangle")
                    .padding(.top, DS.Spacing.md)
            }

            if !isAdminOrSupervisor {
                emptyState(text: L10n.t("المعرض سيتم تحديثه قريباً", "Gallery coming soon"), icon: "sparkles")
                    .padding(.top, DS.Spacing.xl)
            }
        }
    }

    // MARK: - المكونات الفرعية

    private var headerSection: some View {
        VStack(spacing: DS.Spacing.lg) {
            Button {
                showAvatarPreview = true
            } label: {
                avatarContent
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(DS.Color.gradientPrimary, lineWidth: 3.5)
                    )
                    .dsGlowShadow()
            }
            .buttonStyle(.plain)

            if isManager {
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        showAvatarPicker = true
                    } label: {
                        Label(L10n.t("تغيير صورة البروفايل", "Change Profile Photo"), systemImage: "camera.fill")
                            .font(DS.Font.caption1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Color.primary)

                    if avatarURL != nil || localAvatarPreviewImage != nil || member.avatarUrl != nil {
                        Button(role: .destructive) {
                            showDeleteAvatarAlert = true
                        } label: {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                .font(DS.Font.caption1)
                        }
                        .buttonStyle(.bordered)
                        .tint(DS.Color.error)
                    }
                }
            }

            VStack(spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, DS.Spacing.xxxl)

                Text(member.roleName)
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, DS.Spacing.md).padding(.vertical, 5)
                    .background(
                        Group {
                            if member.isDeceased == true {
                                Color.gray.opacity(0.1)
                            } else {
                                LinearGradient(
                                    colors: [DS.Color.primary.opacity(0.12), DS.Color.accent.opacity(0.12)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                    )
                    .foregroundColor(member.isDeceased == true ? .gray : DS.Color.primary)
                    .clipShape(Capsule())
            }
        }
    }

    private var avatarContent: some View {
        ZStack {
            if let localAvatarPreviewImage {
                Image(uiImage: localAvatarPreviewImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = avatarURL ?? member.avatarUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { img in
                    img.resizable().scaledToFill()
                } placeholder: { ProgressView().tint(DS.Color.primary) }
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Color.primary.opacity(0.15), DS.Color.accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Image(systemName: "person.fill").font(.system(size: 35)).foregroundColor(DS.Color.primary))
            }
        }
    }

    private var avatarPreviewOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.92).ignoresSafeArea()

            GeometryReader { _ in
                avatarContent
                    .frame(width: 300, height: 300)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.gradientPrimary, lineWidth: 4))
                    .dsGlowShadow()
                    .scaleEffect(avatarPreviewScale, anchor: .center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let nextScale = lastAvatarPreviewScale * value
                                avatarPreviewScale = min(max(nextScale, 1), 4)
                            }
                            .onEnded { _ in
                                lastAvatarPreviewScale = avatarPreviewScale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            avatarPreviewScale = 1
                            lastAvatarPreviewScale = 1
                        }
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                avatarPreviewScale = 1
                lastAvatarPreviewScale = 1
                showAvatarPreview = false
            }

            Button {
                avatarPreviewScale = 1
                lastAvatarPreviewScale = 1
                showAvatarPreview = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.92))
                    .padding()
            }
            .buttonStyle(.plain)
        }
    }

    private func modernCompactCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.10))
                .clipShape(Circle())
            VStack(spacing: 2) {
                Text(value)
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
        .glassCard(radius: DS.Radius.xl)
    }

    private func emptyState(text: String, icon: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.06))
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(DS.Color.accent.opacity(0.06))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(DS.Color.gradientPrimary)
            }
            Text(text)
                .font(DS.Font.subheadline)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxxxl)
    }

    private func imageTile(content: AnyView, title: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .fill(DS.Color.surface)
                .aspectRatio(1, contentMode: .fit)
                .overlay(content.clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl)))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))

            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.xs + 2)
                .padding(.vertical, 3)
                .background(DS.Color.gradientPrimary)
                .clipShape(Capsule())
                .padding(DS.Spacing.xs + 2)
        }
        .dsCardShadow()
    }

    private func handleImageChange(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.localPreviewImage = uiImage
                }
            }

            let uploadedURL = await authVM.uploadMemberGalleryPhoto(image: uiImage, for: member.id)
            await MainActor.run {
                if let uploadedURL {
                    self.galleryPhotoURL = uploadedURL
                }
            }
        }
    }

    private func deleteGalleryPhoto() async {
        let success = await authVM.deleteMemberGalleryPhoto(for: member.id)
        guard success else { return }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.galleryPhotoURL = nil
                self.localPreviewImage = nil
            }
        }
    }

    private func handleAvatarImageChange(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.localAvatarPreviewImage = uiImage
                }
            }
            await authVM.uploadAvatar(image: uiImage, for: member.id)
        }
    }

    private func deleteAvatarPhoto() async {
        await authVM.deleteAvatar(for: member.id)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.avatarURL = nil
                self.localAvatarPreviewImage = nil
            }
        }
    }
}
