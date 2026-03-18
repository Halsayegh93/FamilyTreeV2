import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss

    private let memberId: UUID
    private let initialMember: FamilyMember

    /// بيانات العضو الحية من memberVM — تتحدث تلقائياً عند أي تعديل
    private var member: FamilyMember {
        memberVM.allMembers.first(where: { $0.id == memberId }) ?? initialMember
    }

    init(member: FamilyMember) {
        self.memberId = member.id
        self.initialMember = member
    }

    @State private var showAdminControl = false
    @State private var avatarPreviewScale: CGFloat = 1.0
    @State private var lastAvatarPreviewScale: CGFloat = 1.0
    @State private var showAvatarPreview = false

    // طلب إضافة صورة
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var rawPickedImage: UIImage? = nil
    @State private var showCropper = false
    @State private var isSubmittingPhotoSuggestion = false
    @State private var showPhotoSuggestionSuccess = false

    @State private var showDeleteBioAlert = false
    @State private var appeared = false

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
                            // صورة هيرو + اسم + بادجات
                            heroPhotoSection
                                .opacity(appeared ? 1 : 0)
                                .scaleEffect(appeared ? 1 : 0.95)

                            // كبسولات المعلومات
                            statsRow
                                .padding(.top, DS.Spacing.lg)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 15)

                            // قسم السيرة
                            bioTimelineSection
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)

                            Spacer(minLength: 60)
                        }
                        .onAppear {
                            guard !appeared else { return }
                            withAnimation(DS.Anim.smooth.delay(0.05)) { appeared = true }
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
        .onReceive(NotificationCenter.default.publisher(for: .memberDeleted)) { notification in
            // إغلاق تفاصيل العضو تلقائياً بعد حذفه
            if let deletedId = notification.object as? UUID, deletedId == member.id {
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showAvatarPreview) {
            avatarPreviewOverlay
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    rawPickedImage = uiImage
                    showCropper = true
                }
                photoPickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let rawPickedImage {
                ImageCropperView(
                    image: rawPickedImage,
                    cropShape: .circle,
                    onCrop: { croppedImage in
                        showCropper = false
                        self.rawPickedImage = nil
                        isSubmittingPhotoSuggestion = true
                        Task {
                            let success = await adminRequestVM.submitPhotoSuggestion(
                                image: croppedImage,
                                for: member.id
                            )
                            isSubmittingPhotoSuggestion = false
                            if success {
                                showPhotoSuggestionSuccess = true
                            }
                        }
                    },
                    onCancel: {
                        showCropper = false
                        self.rawPickedImage = nil
                    }
                )
            }
        }
        .alert(
            L10n.t("تم الإرسال", "Submitted"),
            isPresented: $showPhotoSuggestionSuccess
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { }
        } message: {
            Text(L10n.t(
                "تم إرسال اقتراح الصورة للإدارة وسيتم مراجعته",
                "Photo suggestion sent to admin for review"
            ))
        }
    }

    // MARK: - عضو محذوف

    private var deletedMemberView: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer(minLength: 80)
            ZStack {
                Circle()
                    .fill(DS.Color.textTertiary.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.slash.fill")
                    .font(DS.Font.scaled(36))
                    .foregroundColor(DS.Color.textTertiary)
            }
            Text(L10n.t("هذا العضو حذف حسابه", "This member deleted their account"))
                .font(DS.Font.title3)
                .foregroundColor(DS.Color.textSecondary)
            Text(L10n.t("البيانات الشخصية لم تعد متوفرة", "Personal data is no longer available"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - صورة هيرو + اسم

    private var heroPhotoSection: some View {
        VStack(spacing: 0) {
            // الصورة مع تدريج
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
                        colors: [DS.Color.overlayDark.opacity(0.45), DS.Color.overlayDark.opacity(0.1), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    Spacer()
                }
                .allowsHitTesting(false)

                // تدريج من تحت
                LinearGradient(
                    colors: [.clear, DS.Color.background.opacity(0.5), DS.Color.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            .frame(height: heroHeight)

            // الاسم تحت الصورة
            Text(member.fullName)
                .font(DS.Font.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.top, DS.Spacing.sm)

            // رتبة الحساب + متوفى
            HStack(spacing: DS.Spacing.sm) {
                DSRoleBadge(
                    title: member.roleName,
                    color: member.isDeceased == true ? DS.Color.textTertiary : member.roleColor
                )

                if member.isDeceased == true {
                    Text(L10n.t("رحمه الله", "Rest in peace"))
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.textTertiary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, DS.Spacing.sm)

            // طلب إضافة صورة — يظهر فقط إذا العضو ما عنده صورة ومو صاحب الحساب
            if member.id != authVM.currentUser?.id && !member.isDeleted,
               member.avatarUrl == nil || (member.avatarUrl ?? "").isEmpty {
                if isSubmittingPhotoSuggestion {
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView().tint(DS.Color.primary)
                        Text(L10n.t("جاري الإرسال...", "Submitting..."))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                    }
                    .padding(.top, DS.Spacing.md)
                } else {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(DS.Font.scaled(13, weight: .semibold))
                            Text(L10n.t("طلب إضافة صورة", "Request Add Photo"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.primary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .padding(.top, DS.Spacing.md)
                }
            }
        }
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
                    color: shouldHide ? DS.Color.textTertiary : DS.Color.primary
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
                    color: shouldHide ? DS.Color.textTertiary : DS.Color.success
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
                    color: DS.Color.textTertiary
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
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                Text(value)
                    .font(DS.Font.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
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
                        .padding(.vertical, DS.Spacing.xs)
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
                    Task { await memberVM.updateMemberBio(memberId: memberId, bio: []) }
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

    // MARK: - أزرار عائمة

    private var floatingNavButtons: some View {
        VStack {
            HStack {
                // زر التعديل
                if isAdminOrSupervisor, !member.isDeleted {
                    Button { showAdminControl = true } label: {
                        Image(systemName: "pencil")
                            .font(DS.Font.scaled(14, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: DS.Color.shadowMediumDark, radius: 6, y: 2)
                    }
                }

                Spacer()

                // زر الإغلاق
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: DS.Color.shadowMediumDark, radius: 6, y: 2)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)

            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
        .padding(.top, DS.Spacing.xxxxl)
    }

    // MARK: - المكونات الفرعية

    private var avatarContent: some View {
        ZStack {
            if let url = member.avatarUrl, let imageUrl = URL(string: url) {
                CachedAsyncImage(url: imageUrl) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().tint(DS.Color.primary)
                }
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
            DS.Color.overlayDark.opacity(0.92).ignoresSafeArea()

            GeometryReader { _ in
                avatarContent
                    .frame(width: 300, height: 300)
                    .background(DS.Color.primary.opacity(0.15))
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
                    .foregroundColor(DS.Color.overlayTextFull)
                    .padding()
            }
            .buttonStyle(.plain)
        }
    }

}

