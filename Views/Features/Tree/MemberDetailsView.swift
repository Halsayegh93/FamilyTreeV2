import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let member: FamilyMember
    @State private var showAdminControl = false
    @State private var showAvatarPicker = false
    @State private var selectedAvatarItem: PhotosPickerItem? = nil
    @State private var localAvatarPreviewImage: UIImage? = nil
    @State private var avatarURL: String? = nil

    @State private var showDeleteAvatarAlert = false
    @State private var selectedTab = 0 // 0: البيانات، 1: الصور
    @State private var avatarPreviewScale: CGFloat = 1.0
    @State private var lastAvatarPreviewScale: CGFloat = 1.0
    @State private var pendingCropImage: UIImage? = nil
    @State private var fullScreenMode: FullScreenMode? = nil
    
    private enum FullScreenMode: Identifiable {
        case avatarPreview
        case cropper
        
        var id: Int {
            switch self {
            case .avatarPreview: return 0
            case .cropper: return 1
            }
        }
    }

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

                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {

                        if member.isDeleted {
                            // عرض رسالة للعضو المحذوف
                            VStack(spacing: DS.Spacing.xxl) {
                                Spacer(minLength: 80)
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 100, height: 100)
                                    Image(systemName: "person.slash.fill")
                                        .font(DS.Font.scaled(36))
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
                        } else {
                            personalInfoTab

                            photosTab
                        }

                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarHidden(true)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear {
                avatarURL = member.avatarUrl
            }
            .onChange(of: selectedAvatarItem) { _, newValue in
                handleAvatarImageChange(newValue)
            }
            .sheet(isPresented: $showAdminControl) {
                AdminMemberDetailSheet(member: member)
            }
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
        .fullScreenCover(item: $fullScreenMode) { mode in
            switch mode {
            case .avatarPreview:
                avatarPreviewOverlay
            case .cropper:
                cropperView
            }
        }
        .alert(L10n.t("حذف صورة البروفايل", "Delete Profile Photo"), isPresented: $showDeleteAvatarAlert) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await deleteAvatarPhoto() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t("هل تريد حذف صورة البروفايل لهذا العضو؟", "Delete profile photo for this member?"))
        }
    }

    // MARK: - التبويبات

    private var personalInfoTab: some View {
        VStack(spacing: DS.Spacing.md) {
            headerSection

            HStack(spacing: DS.Spacing.md) {
                if let birth = member.birthDate, !birth.isEmpty {
                    let shouldHideBirth = (member.isBirthDateHidden == true) && (member.id != authVM.currentUser?.id) && !isAdminOrSupervisor
                    if !shouldHideBirth {
                        modernCompactCard(icon: "calendar", title: L10n.t("الميلاد", "Birth"), value: birth, color: DS.Color.primary)
                    }
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
            .padding(.top, DS.Spacing.xxxxl)
        }
    }

    // MARK: - قسم الصور المحدث
    private var photosTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(
                title: L10n.t("المعرض", "Gallery"),
                icon: "photo.on.rectangle.angled"
            )
            .padding(.horizontal)

            DSCard(padding: 0) {
                NavigationLink(destination: PersonalGalleryView(member: member, isEditable: isAdminOrSupervisor)) {
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("photo.on.rectangle.angled", color: DS.Color.neonBlue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("معرض الصور الشخصي", "Personal Gallery"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("عرض صور العضو", "View member photos"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }

                        Spacer()

                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
                .buttonStyle(DSBoldButtonStyle())
            }
            .padding(.horizontal)
        }
    }

    // MARK: - المكونات الفرعية

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // صورة هيدر كبيرة بدون فراغ علوي
            Button {
                fullScreenMode = .avatarPreview
            } label: {
                GeometryReader { geo in
                    avatarContent
                        .frame(width: geo.size.width, height: 280)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.15), .clear, .clear, DS.Color.background.opacity(0.5), DS.Color.background],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(height: 280)
            }
            .buttonStyle(.plain)

            // أزرار فوق الصورة
            VStack {
                HStack {
                    // زر التعديل
                    if isAdminOrSupervisor, !member.isDeleted {
                        Button { showAdminControl = true } label: {
                            Image(systemName: "pencil")
                                .font(DS.Font.scaled(14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        }
                    }

                    Spacer()

                    // زر الإغلاق
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, 54)

                Spacer()
            }
            .frame(height: 280)

            // الاسم في كبسولة زجاجية
            VStack(spacing: DS.Spacing.sm) {
                Text(member.fullName)
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.sm + 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

                HStack(spacing: DS.Spacing.sm) {
                    Text(member.roleName)
                        .font(DS.Font.scaled(11, weight: .heavy))
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

                    if isManager {
                        Button {
                            showAvatarPicker = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(DS.Font.scaled(12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(DS.Color.gradientPrimary)
                                .clipShape(Circle())
                        }

                        if avatarURL != nil || localAvatarPreviewImage != nil || member.avatarUrl != nil {
                            Button(role: .destructive) {
                                showDeleteAvatarAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(DS.Color.error)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
            }
            .offset(y: 36)
        }
    }

    @ViewBuilder
    private var cropperView: some View {
        if let img = pendingCropImage {
            ImageCropperView(
                image: img,
                cropShape: .square,
                onCrop: { cropped in
                    confirmAvatarCrop(cropped)
                },
                onCancel: { fullScreenMode = nil }
            )
        } else {
            Color.black.ignoresSafeArea()
                .onAppear { fullScreenMode = nil }
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
                    .overlay(Image(systemName: "person.fill").font(DS.Font.scaled(35)).foregroundColor(DS.Color.primary))
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
                fullScreenMode = nil
            }

            Button {
                avatarPreviewScale = 1
                lastAvatarPreviewScale = 1
                fullScreenMode = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Font.scaled(30))
                    .foregroundColor(.white.opacity(0.92))
                    .padding()
            }
            .buttonStyle(.plain)
        }
    }

    private func modernCompactCard(icon: String, title: String, value: String, color: Color) -> some View {
        DSCard(padding: 0) {
            VStack(spacing: DS.Spacing.xs) {
                DSIcon(icon, color: color)
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
            .padding(.vertical, DS.Spacing.md)
        }
    }

    private func handleAvatarImageChange(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
            let resized = await downsampleInBackground(data)
            guard let resized else { return }
            pendingCropImage = resized
            try? await Task.sleep(nanoseconds: 400_000_000)
            fullScreenMode = .cropper
        }
    }
    
    private func confirmAvatarCrop(_ croppedImage: UIImage) {
        fullScreenMode = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            self.localAvatarPreviewImage = croppedImage
        }
        Task {
            await authVM.uploadAvatar(image: croppedImage, for: member.id)
        }
    }

    private func downsampleInBackground(_ data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let maxPixels: CGFloat = 1600
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    continuation.resume(returning: UIImage(data: data))
                    return
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: UIImage(data: data))
                    return
                }
                let result = UIImage(cgImage: cgImage)
                continuation.resume(returning: result)
            }
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
