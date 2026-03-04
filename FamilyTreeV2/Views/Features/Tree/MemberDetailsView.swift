import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let member: FamilyMember
    @State private var showAdminControl = false
    @State private var avatarPreviewScale: CGFloat = 1.0
    @State private var lastAvatarPreviewScale: CGFloat = 1.0
    @State private var showAvatarPreview = false

    // تعديل صورة الغلاف
    @State private var showCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem? = nil
    @State private var localCoverPreview: UIImage? = nil
    @State private var pendingCropImage: UIImage? = nil
    @State private var showCropper = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showDeleteBioAlert = false

    var isAdminOrSupervisor: Bool {
        let role = authVM.currentUser?.role
        return role == .admin || role == .supervisor
    }

    private let heroHeight: CGFloat = 320

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DS.Color.background.ignoresSafeArea()

                if member.isDeleted {
                    // عرض رسالة للعضو المحذوف
                    deletedMemberView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // صورة هيرو
                            heroPhotoSection

                            // أفاتار + اسم + بادجات
                            profileInfoSection

                            // كبسولات المعلومات
                            statsRow
                                .padding(.top, DS.Spacing.sm)

                            // قسم السيرة
                            bioTimelineSection

                            // قسم المعرض
                            gallerySection

                            Spacer(minLength: 60)
                        }
                    }

                    // أزرار عائمة فوق الصورة
                    floatingNavButtons
                }
            }
            .navigationBarHidden(true)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .sheet(isPresented: $showAdminControl) {
                AdminMemberDetailSheet(member: member)
            }
        }
        .fullScreenCover(isPresented: $showAvatarPreview) {
            avatarPreviewOverlay
        }
        .fullScreenCover(isPresented: $showCropper) {
            cropperView
        }
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedCoverItem, matching: .images)
        .onChange(of: selectedCoverItem) { _, newValue in
            handleCoverImageChange(newValue)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
    }

    // MARK: - عضو محذوف

    private var deletedMemberView: some View {
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
    }

    // MARK: - صورة هيرو

    private var heroPhotoSection: some View {
        ZStack(alignment: .bottom) {
            avatarContent
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    showAvatarPreview = true
                }

            // تدريج من فوق للـ status bar
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.45), Color.black.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
                Spacer()
            }
            .allowsHitTesting(false)

            // تدريج من تحت للانتقال للمحتوى
            LinearGradient(
                colors: [.clear, DS.Color.background.opacity(0.6), DS.Color.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .allowsHitTesting(false)

        
        }
        .frame(height: heroHeight)
    }

    // MARK: - اسم + بادجات + زر تعديل الغلاف

    private var profileInfoSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            // الاسم الكامل
            Text(member.fullName)
                .font(DS.Font.title2)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.xxl)

            // بادجات الرتبة + متوفى
            HStack(spacing: DS.Spacing.sm) {
                DSRoleBadge(
                    title: member.roleName,
                    color: member.isDeceased == true ? .gray : member.roleColor
                )

                if member.isDeceased == true {
                    Text(L10n.t("رحمه الله", "Rest in peace"))
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(.gray.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // زر تعديل الغلاف
            Button { showCoverPicker = true } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "camera.fill")
                        .font(DS.Font.scaled(12, weight: .bold))
                    Text(L10n.t("تعديل الغلاف", "Edit Cover"))
                        .font(DS.Font.scaled(12, weight: .semibold))
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.primary.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Color.primary.opacity(0.15), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - كبسولات المعلومات

    private var statsRow: some View {
        HStack(spacing: DS.Spacing.md) {
            // كبسولة الميلاد
            if let birth = member.birthDate, !birth.isEmpty {
                let shouldHide = (member.isBirthDateHidden == true)
                    && (member.id != authVM.currentUser?.id)
                    && !isAdminOrSupervisor
                infoPill(
                    icon: "calendar",
                    title: L10n.t("الميلاد", "Birth"),
                    value: shouldHide ? L10n.t("مخفي", "Hidden") : birth,
                    color: shouldHide ? .gray : DS.Color.primary
                )
            }

            // كبسولة الهاتف — للأحياء فقط
            if member.isDeceased != true,
               let phone = member.phoneNumber, !phone.isEmpty {
                let shouldHide = (member.isPhoneHidden == true)
                    && (member.id != authVM.currentUser?.id)
                    && !isAdminOrSupervisor
                infoPill(
                    icon: "phone.fill",
                    title: L10n.t("الهاتف", "Phone"),
                    value: shouldHide ? L10n.t("مخفي", "Hidden") : KuwaitPhone.display(phone),
                    color: shouldHide ? .gray : DS.Color.success
                )
            }

            // كبسولة الوفاة — للمتوفين
            if member.isDeceased == true {
                let deathValue = (member.deathDate?.isEmpty == false)
                    ? (member.deathDate ?? L10n.t("رحمه الله", "Rest in peace"))
                    : L10n.t("رحمه الله", "Rest in peace")
                infoPill(
                    icon: "heart.fill",
                    title: L10n.t("الوفاة", "Death"),
                    value: deathValue,
                    color: .gray
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func infoPill(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                Text(value)
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(color.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - تايملاين السيرة

    @ViewBuilder
    private var bioTimelineSection: some View {
        if let bioStations = member.bio, !bioStations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DSSectionHeader(
                    title: L10n.t("السيرة", "Biography"),
                    icon: "book.fill",
                    trailing: "\(bioStations.count) " + L10n.t("محطة", "stations"),
                    iconColor: DS.Color.primary
                )
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.md)

                VStack(spacing: 0) {
                    ForEach(Array(bioStations.enumerated()), id: \.element.id) { index, station in
                        HStack(alignment: .top, spacing: DS.Spacing.lg) {
                            // خط + نقطة التايملاين
                            VStack(spacing: 0) {
                                // نقطة متدرجة
                                ZStack {
                                    Circle()
                                        .fill(DS.Color.primary.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                    Circle()
                                        .fill(DS.Color.gradientPrimary)
                                        .frame(width: 12, height: 12)
                                }
                                
                                if index < bioStations.count - 1 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [DS.Color.primary.opacity(0.3), DS.Color.primary.opacity(0.1)],
                                                startPoint: .top, endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 24)

                            // كرت المحطة
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                if let year = station.year, !year.isEmpty {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Image(systemName: "calendar.circle.fill")
                                            .font(DS.Font.scaled(12, weight: .semibold))
                                            .foregroundColor(DS.Color.primary)
                                        Text(year)
                                            .font(DS.Font.scaled(12, weight: .bold))
                                            .foregroundColor(DS.Color.primary)
                                    }
                                    .padding(.horizontal, DS.Spacing.sm)
                                    .padding(.vertical, 3)
                                    .background(DS.Color.primary.opacity(0.08))
                                    .clipShape(Capsule())
                                }
                                
                                Text(station.title)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                                
                                if !station.details.isEmpty {
                                    Text(station.details)
                                        .font(DS.Font.subheadline)
                                        .foregroundColor(DS.Color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(DS.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                    .stroke(DS.Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.bottom, DS.Spacing.sm)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)

                // زر حذف السيرة — للمدير/المشرف أو صاحب الحساب
                if isAdminOrSupervisor || member.id == authVM.currentUser?.id {
                    Button {
                        showDeleteBioAlert = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "trash")
                                .font(DS.Font.scaled(13, weight: .semibold))
                            Text(L10n.t("حذف السيرة", "Delete Biography"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.error.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                }
            }
            .padding(.top, DS.Spacing.lg)
            .alert(
                L10n.t("حذف السيرة", "Delete Biography"),
                isPresented: $showDeleteBioAlert
            ) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    let memberId = member.id
                    Task { await authVM.updateMemberBio(memberId: memberId, bio: []) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t(
                    "هل تريد حذف السيرة الذاتية؟",
                    "Delete biography?"
                ))
            }
        }
    }

    // MARK: - قسم المعرض

    private var gallerySection: some View {
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
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(DS.Color.textTertiary.opacity(0.1))
                        .clipShape(Circle())
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.lg)
            }
            .buttonStyle(DSBoldButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
    }

    // MARK: - أزرار عائمة

    private var floatingNavButtons: some View {
        VStack {
            HStack {
                // زر التعديل
                if isAdminOrSupervisor, !member.isDeleted {
                    Button { showAdminControl = true } label: {
                        Image(systemName: "pencil")
                            .font(DS.Font.scaled(14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                    }
                }

                Spacer()

                // زر المشاركة
                if !member.isDeleted {
                    Button { shareProfile() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                    }
                }

                // زر الإغلاق
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)

            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
        .padding(.top, DS.Spacing.xxxxl)
    }

    // MARK: - مشاركة الملف الشخصي

    private func shareProfile() {
        var lines: [String] = []

        let name = member.fullName
        lines.append("👤 \(name)")
        lines.append("")

        if let birth = member.birthDate, !birth.isEmpty, member.isBirthDateHidden != true {
            lines.append("🎂 " + L10n.t("الميلاد", "Birthday") + ": \(birth)")
        }

        if member.isDeceased == true, let death = member.deathDate, !death.isEmpty {
            lines.append("🕊️ " + L10n.t("الوفاة", "Passed") + ": \(death)")
        }

        if let phone = member.phoneNumber, !phone.isEmpty,
           member.isPhoneHidden != true, member.isDeceased != true {
            lines.append("📱 " + KuwaitPhone.display(phone))
        }

        if let bio = member.bio, !bio.isEmpty {
            lines.append("")
            lines.append("📖 " + L10n.t("السيرة", "Biography") + ":")
            for station in bio {
                let yearStr = station.year.map { "(\($0)) " } ?? ""
                lines.append("  • \(yearStr)\(station.title)")
            }
        }

        // Father name
        if let fatherId = member.fatherId,
           let father = authVM.allMembers.first(where: { $0.id == fatherId }) {
            lines.append("")
            lines.append("👨 " + L10n.t("الأب", "Father") + ": \(father.fullName)")
        }

        // Children
        let children = authVM.allMembers.filter { $0.fatherId == member.id }
        if !children.isEmpty {
            lines.append("👶 " + L10n.t("الأبناء", "Children") + " (\(children.count)): " + children.map { $0.firstName }.joined(separator: ", "))
        }

        lines.append("")
        lines.append("— " + L10n.t("شجرة آل محمد علي", "Al-Mohammad Ali Family Tree"))

        let shareText = lines.joined(separator: "\n")
        shareItems = [shareText]
        showShareSheet = true
    }

    // MARK: - المكونات الفرعية

    private var avatarContent: some View {
        ZStack {
            if let localCoverPreview {
                Image(uiImage: localCoverPreview)
                    .resizable()
                    .scaledToFill()
            } else if let url = member.coverUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { img in
                    img.resizable().scaledToFill()
                } placeholder: { ProgressView().tint(DS.Color.primary) }
            } else if let url = member.avatarUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { img in
                    img.resizable().scaledToFill()
                } placeholder: { ProgressView().tint(DS.Color.primary) }
            } else {
                LinearGradient(
                    colors: [DS.Color.primary.opacity(0.15), DS.Color.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(50))
                        .foregroundColor(DS.Color.primary.opacity(0.4))
                )
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
                        MagnifyGesture()
                            .onChanged { value in
                                let nextScale = lastAvatarPreviewScale * value.magnification
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
                    .font(DS.Font.scaled(30))
                    .foregroundColor(.white.opacity(0.92))
                    .padding()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - تعديل صورة الغلاف

    @ViewBuilder
    private var cropperView: some View {
        if let img = pendingCropImage {
            ImageCropperView(
                image: img,
                cropShape: .square,
                onCrop: { cropped in
                    confirmCoverCrop(cropped)
                },
                onCancel: { showCropper = false }
            )
        } else {
            Color.black.ignoresSafeArea()
                .onAppear { showCropper = false }
        }
    }

    private func handleCoverImageChange(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
            let resized = await downsampleInBackground(data)
            guard let resized else { return }
            pendingCropImage = resized
            try? await Task.sleep(nanoseconds: 400_000_000)
            showCropper = true
        }
    }

    private func confirmCoverCrop(_ croppedImage: UIImage) {
        showCropper = false
        withAnimation(.easeInOut(duration: 0.2)) {
            self.localCoverPreview = croppedImage
        }
        Task {
            await authVM.uploadCover(image: croppedImage, for: member.id)
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
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
