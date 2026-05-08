import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss

    private let initialMember: FamilyMember
    @State private var currentMemberId: UUID

    /// بيانات العضو الحية من memberVM — تتحدث تلقائياً عند أي تعديل
    private var member: FamilyMember {
        memberVM.allMembers.first(where: { $0.id == currentMemberId }) ?? initialMember
    }

    init(member: FamilyMember) {
        self.initialMember = member
        _currentMemberId = State(initialValue: member.id)
    }

    @State private var showAdminControl = false
    @State private var avatarPreviewScale: CGFloat = 1.0
    @State private var lastAvatarPreviewScale: CGFloat = 1.0
    @State private var showAvatarPreview = false

    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var rawPickedImage: UIImage? = nil
    @State private var showCropper = false
    @State private var isSubmittingPhotoSuggestion = false
    @State private var showPhotoSuggestionSuccess = false

    @State private var showDeleteBioAlert = false
    @State private var appeared = false

    @State private var showActionSheet = false
    @State private var pendingEditAction: TreeEditAction? = nil
    @State private var showChildrenSheet = false

    // MARK: - Computed properties

    private var isViewingSelf: Bool {
        member.id == authVM.currentUser?.id
    }

    private var father: FamilyMember? {
        guard let fatherId = member.fatherId else { return nil }
        return memberVM.allMembers.first(where: { $0.id == fatherId })
    }

    private var children: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.fatherId == member.id && $0.status != .frozen && !($0.isHiddenFromTree) }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var pendingRequestsForMember: [AdminRequest] {
        adminRequestVM.treeEditRequests.filter { $0.memberId == member.id }
    }

    private var canSeePendingRequests: Bool {
        authVM.canModerate ||
        pendingRequestsForMember.contains { $0.requesterId == authVM.currentUser?.id }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DS.Color.background.ignoresSafeArea()

                if member.isDeleted {
                    deletedMemberView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DS.Spacing.lg) {
                            compactHeroSection
                                .padding(.top, DS.Spacing.xxxl)
                                .opacity(appeared ? 1 : 0)
                                .scaleEffect(appeared ? 1 : 0.95)

                            quickActionsRow
                                .padding(.horizontal, DS.Spacing.lg)
                                .opacity(appeared ? 1 : 0)

                            basicInfoCard
                                .padding(.horizontal, DS.Spacing.lg)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 15)

                            familyCard
                                .padding(.horizontal, DS.Spacing.lg)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)

                            bioCard
                                .padding(.horizontal, DS.Spacing.lg)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 25)

                            pendingRequestsCard
                                .padding(.horizontal, DS.Spacing.lg)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 30)

                            actionButtonsSection
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.md)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 35)

                            Spacer(minLength: 60)
                        }
                        .onAppear {
                            guard !appeared else { return }
                            withAnimation(DS.Anim.smooth.delay(0.05)) { appeared = true }
                        }
                    }
                }

                floatingCloseButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .sheet(isPresented: $showAdminControl) {
                if authVM.canEditMembers {
                    AdminMemberDetailSheet(member: member)
                        .id(memberVM.membersVersion)
                }
            }
            .sheet(isPresented: $showActionSheet) {
                MemberActionSheet(member: member) { action in
                    pendingEditAction = action
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showChildrenSheet) {
                childrenListSheet
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $pendingEditAction) { action in
                TreeEditRequestView(member: member, action: action)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberDeleted)) { notification in
            if let deletedId = notification.object as? UUID, deletedId == member.id {
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showAvatarPreview) {
            avatarPreviewOverlay
        }
        .onChange(of: photoPickerItem) { newItem in
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
            L10n.t("تم إرسال الاقتراح ✓", "Suggestion Sent ✓"),
            isPresented: $showPhotoSuggestionSuccess
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { }
        } message: {
            Text(L10n.t(
                "وصل اقتراح الصورة للإدارة وسيظهر في الملف الشخصي بعد الموافقة.",
                "Your photo suggestion was sent to admins. It will appear on the profile after approval."
            ))
        }
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
            Text(L10n.t("هل تريد حذف السيرة الذاتية؟", "Delete biography?"))
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
            Text(L10n.t("البيانات غير متوفرة", "Data unavailable"))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero Section (Compact circular)

    private var compactHeroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 170, height: 170)
                    .blur(radius: 28)
                    .opacity(0.35)

                avatarContent
                    .frame(width: 130, height: 130)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [DS.Color.primary, DS.Color.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                    )
                    .dsGlowShadow()
                    .onTapGesture { showAvatarPreview = true }
            }

            VStack(spacing: DS.Spacing.xs) {
                Text(member.fullName)
                    .font(DS.Font.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, DS.Spacing.lg)

                HStack(spacing: DS.Spacing.xs) {
                    DSRoleBadge(
                        title: member.roleName,
                        color: (member.isDeceased == true ? DS.Color.textTertiary : member.roleColor).opacity(0.7)
                    )

                    if member.isDeceased == true {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.slash")
                                .font(DS.Font.scaled(10, weight: .semibold))
                            Text(L10n.t("متوفى", "Deceased"))
                                .font(DS.Font.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(DS.Color.textTertiary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsRow: some View {
        let showKinship = !isViewingSelf && !member.isDeleted
        let showPhotoAdd = member.isDeceased == true
            && (member.avatarUrl == nil || (member.avatarUrl ?? "").isEmpty)
            && !isViewingSelf
        let showFavorite = !isViewingSelf && !member.isDeleted

        if showKinship || showPhotoAdd || showFavorite {
            HStack(spacing: DS.Spacing.sm) {
                if showKinship {
                    quickPill(
                        icon: "point.3.connected.trianglepath.dotted",
                        label: L10n.t("صلة القرابة", "Kinship"),
                        color: DS.Color.warning,
                        action: showKinshipPath
                    )
                }

                if showPhotoAdd {
                    if isSubmittingPhotoSuggestion {
                        ProgressView()
                            .tint(DS.Color.primary)
                            .frame(height: 28)
                    } else {
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "camera.badge.ellipsis")
                                    .font(DS.Font.scaled(11, weight: .semibold))
                                Text(L10n.t("إضافة صورة", "Add Photo"))
                                    .font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs + 2)
                            .background(DS.Color.primary.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }

                if showFavorite {
                    Button { FavoritesManager.shared.toggle(member.id) } label: {
                        let isFav = FavoritesManager.shared.isFavorite(member.id)
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(DS.Font.scaled(11, weight: .semibold))
                            Text(L10n.t(isFav ? "مفضل" : "مفضلة", isFav ? "Favorited" : "Favorite"))
                                .font(DS.Font.scaled(12, weight: .bold))
                        }
                        .foregroundColor(isFav ? DS.Color.error : DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs + 2)
                        .background((isFav ? DS.Color.error : DS.Color.textSecondary).opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    private func quickPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .semibold))
                Text(label)
                    .font(DS.Font.scaled(12, weight: .bold))
            }
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs + 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Basic Info Card

    @ViewBuilder
    private var basicInfoCard: some View {
        let rows = basicInfoRows
        if !rows.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("المعلومات الأساسية", "Basic Info"),
                        icon: "person.text.rectangle.fill",
                        iconColor: DS.Color.primary
                    )

                    VStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { index in
                            let row = rows[index]
                            infoRow(icon: row.icon, label: row.label, value: row.value, color: row.color)
                            if index < rows.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
        }
    }

    private struct InfoRowData {
        let icon: String
        let label: String
        let value: String
        let color: Color
    }

    private var basicInfoRows: [InfoRowData] {
        var rows: [InfoRowData] = []

        if let birth = member.birthDate, !birth.isEmpty {
            let shouldHide = (member.isBirthDateHidden == true) && !isViewingSelf && !authVM.canModerate
            rows.append(.init(
                icon: "calendar",
                label: L10n.t("الميلاد", "Birth"),
                value: shouldHide ? L10n.t("مخفي", "Hidden") : birth,
                color: shouldHide ? DS.Color.textTertiary : DS.Color.primary
            ))
        }

        if member.isDeceased != true,
           let phone = member.phoneNumber, !phone.isEmpty {
            let shouldHide = (member.isPhoneHidden == true) && !isViewingSelf && !authVM.canModerate
            rows.append(.init(
                icon: "phone.fill",
                label: L10n.t("الهاتف", "Phone"),
                value: shouldHide ? L10n.t("مخفي", "Hidden") : KuwaitPhone.display(phone),
                color: shouldHide ? DS.Color.textTertiary : DS.Color.success
            ))
        }

        if let gender = member.gender, !gender.isEmpty {
            let isMale = gender == "male"
            rows.append(.init(
                icon: isMale ? "person.fill" : "person.fill.badge.plus",
                label: L10n.t("الجنس", "Gender"),
                value: isMale ? L10n.t("ذكر", "Male") : L10n.t("أنثى", "Female"),
                color: DS.Color.info
            ))
        }

        if member.isMarried == true && member.isDeceased != true {
            rows.append(.init(
                icon: "heart.circle.fill",
                label: L10n.t("الحالة", "Status"),
                value: L10n.t("متزوج", "Married"),
                color: DS.Color.error
            ))
        }

        if member.isDeceased == true,
           let death = member.deathDate, !death.isEmpty {
            rows.append(.init(
                icon: "heart.slash.fill",
                label: L10n.t("الوفاة", "Death"),
                value: death,
                color: DS.Color.textTertiary
            ))
        }

        return rows
    }

    private func infoRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
            Spacer()
            Text(value)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    // MARK: - Family Card

    @ViewBuilder
    private var familyCard: some View {
        if father != nil || !children.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("العائلة", "Family"),
                        icon: "person.2.fill",
                        iconColor: DS.Color.success
                    )

                    VStack(spacing: 0) {
                        if let father = father {
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    currentMemberId = father.id
                                    appeared = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(DS.Anim.smooth) { appeared = true }
                                }
                            } label: {
                                familyRow(
                                    icon: "person.fill",
                                    label: L10n.t("الأب", "Father"),
                                    value: father.fullName,
                                    color: DS.Color.success
                                )
                            }
                            .buttonStyle(.plain)

                            if !children.isEmpty {
                                Divider().padding(.leading, 56)
                            }
                        }

                        if !children.isEmpty {
                            Button {
                                showChildrenSheet = true
                            } label: {
                                familyRow(
                                    icon: "person.3.fill",
                                    label: L10n.t("الأبناء", "Children"),
                                    value: childrenCountText,
                                    color: DS.Color.info
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
        }
    }

    private var childrenCountText: String {
        let n = children.count
        if L10n.isArabic {
            if n == 1 { return "ابن واحد" }
            if n == 2 { return "ابنان" }
            if n <= 10 { return "\(n) أبناء" }
            return "\(n) ابن"
        }
        return n == 1 ? "1 child" : "\(n) children"
    }

    private func familyRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
            Spacer()
            Text(value)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    // MARK: - Bio Card

    @ViewBuilder
    private var bioCard: some View {
        if let bioStations = member.bio, !bioStations.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("السيرة", "Biography"),
                        icon: "book.fill",
                        trailing: "\(bioStations.count) " + L10n.t("محطة", "stations"),
                        iconColor: DS.Color.primary
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(bioStations.enumerated()), id: \.element.id) { index, station in
                            bioStationRow(index: index, total: bioStations.count, station: station)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)

                    if authVM.isAdmin || isViewingSelf {
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
                            .padding(.vertical, DS.Spacing.sm)
                            .background(DS.Color.error.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.md)
                    }
                }
            }
        }
    }

    private func bioStationRow(index: Int, total: Int, station: FamilyMember.BioStation) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 10, height: 10)
                }

                if index < total - 1 {
                    Rectangle()
                        .fill(DS.Color.primary.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if let year = station.year, !year.isEmpty {
                    Text(year)
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(DS.Color.primary.opacity(0.10))
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
            .padding(.bottom, index < total - 1 ? DS.Spacing.md : DS.Spacing.sm)

            Spacer()
        }
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: - Pending Requests Card

    @ViewBuilder
    private var pendingRequestsCard: some View {
        if canSeePendingRequests && !pendingRequestsForMember.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("طلبات معلقة", "Pending Requests"),
                        icon: "clock.badge.exclamationmark.fill",
                        trailing: "\(pendingRequestsForMember.count)",
                        iconColor: DS.Color.warning
                    )

                    VStack(spacing: 0) {
                        ForEach(pendingRequestsForMember.indices, id: \.self) { index in
                            pendingRequestRow(pendingRequestsForMember[index])
                            if index < pendingRequestsForMember.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
        }
    }

    private func pendingRequestRow(_ request: AdminRequest) -> some View {
        let action = request.treeEditPayload?.resolvedAction
        let actionLabelAr = action?.arabicLabel ?? "—"
        let actionLabelEn = action?.englishLabel ?? "—"
        let icon = action?.iconName ?? "questionmark.circle"
        let color: Color = {
            switch action {
            case .add: return DS.Color.success
            case .editName: return DS.Color.info
            case .editPhone: return DS.Color.primary
            case .deceased: return DS.Color.textTertiary
            case .delete: return DS.Color.error
            case .none: return DS.Color.warning
            }
        }()

        return HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(actionLabelAr, actionLabelEn))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("قيد المراجعة", "Under review"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
            Spacer()
            Text(L10n.t("معلق", "Pending"))
                .font(DS.Font.caption2)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.warning)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(DS.Color.warning.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    // MARK: - Action Buttons (bottom)

    @ViewBuilder
    private var actionButtonsSection: some View {
        if !member.isDeleted {
            VStack(spacing: DS.Spacing.sm) {
                if !isViewingSelf {
                    Button {
                        showActionSheet = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "pencil.and.list.clipboard")
                                .font(DS.Font.scaled(15, weight: .semibold))
                            Text(L10n.t("طلب تعديل لهذا العضو", "Request edit for this member"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.gradientPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .dsSubtleShadow()
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }

                if authVM.canEditMembers {
                    Button {
                        showAdminControl = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "pencil")
                                .font(DS.Font.scaled(15, weight: .semibold))
                            Text(L10n.t("تعديل مباشر (إدارة)", "Direct Edit (Admin)"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.primary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.35), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    // MARK: - Floating Close Button

    private var floatingCloseButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.5))
                        .dsSubtleShadow()
                }
                .accessibilityLabel(L10n.t("إغلاق", "Close"))
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            Spacer()
        }
    }

    // MARK: - Children Sheet

    private var childrenListSheet: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(children) { child in
                            Button {
                                showChildrenSheet = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(DS.Anim.snappy) {
                                        currentMemberId = child.id
                                        appeared = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(DS.Anim.smooth) { appeared = true }
                                    }
                                }
                            } label: {
                                childRow(child)
                            }
                            .buttonStyle(DSScaleButtonStyle())
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationTitle(L10n.t("أبناء \(member.firstName)", "\(member.firstName)'s Children"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { showChildrenSheet = false }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private func childRow(_ child: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                if let url = child.avatarUrl, let imgUrl = URL(string: url) {
                    CachedAsyncImage(url: imgUrl) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(DS.Color.primary.opacity(0.12))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(DS.Color.primary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Text(String(child.firstName.prefix(1)))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(child.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let birth = child.birthDate, !birth.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(DS.Font.scaled(10))
                        Text(birth)
                            .font(DS.Font.caption1)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                }
            }

            Spacer()

            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Kinship Path

    private func showKinshipPath() {
        guard let currentUser = authVM.currentUser else { return }
        let lookup = memberVM._memberById
        let result = KinshipCalculator.calculate(from: currentUser, to: member, lookup: lookup)

        var pathIds = result.pathA.map(\.id) + result.pathB.map(\.id)
        if let ancestor = result.commonAncestor {
            pathIds.append(ancestor.id)
        }

        dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(
                name: .showKinshipPath,
                object: nil,
                userInfo: [
                    "memberId": member.id,
                    "relationship": result.relationship,
                    "pathIds": pathIds
                ]
            )
        }
    }

    // MARK: - Avatar Content

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
                    colors: [DS.Color.primary.opacity(0.20), DS.Color.accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(50))
                        .foregroundColor(DS.Color.primary.opacity(0.5))
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
                        MagnificationGesture()
                            .onChanged { value in
                                let nextScale = lastAvatarPreviewScale * value
                                avatarPreviewScale = min(max(nextScale, 1), 4)
                            }
                            .onEnded { value in
                                lastAvatarPreviewScale = min(max(lastAvatarPreviewScale * value, 1), 4)
                                avatarPreviewScale = lastAvatarPreviewScale
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
            .accessibilityLabel(L10n.t("إغلاق", "Close"))
        }
    }
}
