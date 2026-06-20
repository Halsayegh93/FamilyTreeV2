import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) var dismiss

    private let initialMember: FamilyMember
    @State private var currentMemberId: UUID

    /// بيانات العضو الحية من memberVM — تتحدث تلقائياً عند أي تعديل (dictionary lookup سريع)
    private var member: FamilyMember {
        memberVM.member(byId: currentMemberId) ?? initialMember
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

    @State private var showActionSheet = false
    @State private var pendingEditAction: TreeEditAction? = nil
    @State private var showReportConfirm = false
    @State private var reportReason = ""
    @State private var reportSent = false
    @State private var childrenExpanded = false

    // MARK: - Cached State (تحسب مرة عند تغيير العضو لتفادي إعادة الحساب O(n) في كل rebuild)

    @State private var cachedFather: FamilyMember? = nil
    @State private var cachedChildren: [FamilyMember] = []
    @State private var cachedPendingRequests: [AdminRequest] = []
    @State private var cachedBasicInfoRows: [InfoRowData] = []

    private var isViewingSelf: Bool {
        member.id == authVM.currentUser?.id
    }

    /// العضو نشط داخل المنظومة — يستخدم helper مشترك في FamilyMember+UI
    private var isMemberActive: Bool { member.isInSystem }

    private var canSeePendingRequests: Bool {
        authVM.canModerate ||
        cachedPendingRequests.contains { $0.requesterId == authVM.currentUser?.id }
    }

    private func recomputeCache() {
        let m = member
        cachedFather = m.fatherId.flatMap { memberVM.member(byId: $0) }
        cachedChildren = memberVM.allMembers
            .filter { $0.fatherId == m.id && $0.isCountable }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
        cachedPendingRequests = adminRequestVM.treeEditRequests.filter { $0.memberId == m.id }
        cachedBasicInfoRows = computeBasicInfoRows(for: m)
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

                            quickActionsRow
                                .padding(.horizontal, DS.Spacing.lg)

                            basicInfoCard
                                .padding(.horizontal, DS.Spacing.lg)

                            familyCard
                                .padding(.horizontal, DS.Spacing.lg)

                            bioCard
                                .padding(.horizontal, DS.Spacing.lg)

                            pendingRequestsCard
                                .padding(.horizontal, DS.Spacing.lg)

                            actionButtonsSection
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.md)

                            Spacer(minLength: 60)
                        }
                    }
                }

                floatingCloseButton
            }
            .onAppear { recomputeCache() }
            .onChange(of: currentMemberId) { _ in recomputeCache() }
            .onChange(of: memberVM.membersVersion) { _ in recomputeCache() }
            .onChange(of: adminRequestVM.treeEditRequests.count) { _ in recomputeCache() }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .sheet(isPresented: $showAdminControl) {
                if authVM.canEditMembers {
                    // ملاحظة: لا نضع .id(membersVersion) هنا — كان يُعيد بناء
                    // الـsheet بالكامل عند كل upsertMemberLocally (مثلاً
                    // عند إضافة ابن)، فيُفقد scroll position ويرجع للأعلى.
                    // الـsheet يتحدث طبيعياً عبر @EnvironmentObject memberVM.
                    AdminMemberDetailSheet(member: member)
                }
            }
            .sheet(isPresented: $showActionSheet) {
                MemberActionSheet(member: member) { action in
                    pendingEditAction = action
                }
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
        .alert(L10n.t("إبلاغ عن عضو", "Report Member"), isPresented: $showReportConfirm) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
            Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                let target = member
                let reason = reportReason
                reportReason = ""
                Task {
                    let ok = await notificationVM.reportContent(
                        contentKind: L10n.t("ملف عضو", "member profile"),
                        contentLabel: target.fullName,
                        contentId: target.id,
                        reason: reason
                    )
                    if ok { await MainActor.run { reportSent = true } }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { reportReason = "" }
        } message: {
            Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة ملف هذا العضو.",
                       "Enter a reason; it will be sent to the admins to review this member's profile."))
        }
        .alert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { }
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة.", "Thank you, your report reached the admins."))
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

                ZStack {
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

                    // علامة وفاة (نفس نمط الأبناء)
                    if member.isDeceased == true {
                        Circle()
                            .fill(DS.Color.background)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "heart.slash.fill")
                                    .font(DS.Font.scaled(18, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            )
                            .offset(x: 48, y: 48)
                    } else if isMemberActive {
                        // دائرة خضراء للأعضاء النشطين (داخل المنظومة)
                        Circle()
                            .fill(DS.Color.background)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .fill(DS.Color.secondary)
                                    .frame(width: 16, height: 16)
                                    .shadow(color: DS.Color.secondary.opacity(0.5), radius: 4, x: 0, y: 1)
                            )
                            .offset(x: 48, y: 48)
                    }
                }
            }

            Text(member.fullName)
                .font(DS.Font.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsRow: some View {
        let showKinship = !isViewingSelf && !member.isDeleted
        let showPhotoAdd = member.isDeceased == true
            && (member.avatarUrl == nil || (member.avatarUrl ?? "").isEmpty)
            && !isViewingSelf

        if showKinship || showPhotoAdd {
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
        let rows = cachedBasicInfoRows
        if !rows.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("المعلومات الأساسية", "Basic Info"),
                        icon: "person.text.rectangle.fill",
                        iconColor: DS.Color.primary
                    )

                    // للمتوفى مع ميلاد + وفاة فقط → تخطيط جنب بعض (يمين/يسار)
                    let isDeceasedTwoCol = member.isDeceased == true
                        && rows.count == 2
                        && rows.contains(where: { $0.icon == "calendar" })
                        && rows.contains(where: { $0.icon == "heart.slash.fill" })

                    if isDeceasedTwoCol {
                        HStack(spacing: 0) {
                            if let birthRow = rows.first(where: { $0.icon == "calendar" }) {
                                infoTile(row: birthRow)
                            }
                            Rectangle()
                                .fill(DS.Color.textTertiary.opacity(0.2))
                                .frame(width: 1, height: 64)
                            if let deathRow = rows.first(where: { $0.icon == "heart.slash.fill" }) {
                                infoTile(row: deathRow)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                    } else {
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
    }

    /// خانة إيقونة + قيمة + label عمودياً — للتخطيط الأفقي ثنائي الأعمدة
    private func infoTile(row: InfoRowData) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(row.color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: row.icon)
                    .font(DS.Font.scaled(15, weight: .semibold))
                    .foregroundColor(row.color)
            }
            Text(row.label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            Text(row.value)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
    }

    private struct InfoRowData {
        let icon: String
        let label: String
        let value: String
        let color: Color
    }

    private func computeBasicInfoRows(for m: FamilyMember) -> [InfoRowData] {
        var rows: [InfoRowData] = []
        let isSelf = m.id == authVM.currentUser?.id
        let canMod = authVM.canModerate
        let isDeceased = m.isDeceased == true

        if let birth = m.birthDate, !birth.isEmpty {
            let shouldHide = (m.isBirthDateHidden == true) && !isSelf && !canMod
            // للمتوفى: السنة فقط بدل التاريخ الكامل
            let displayValue = shouldHide
                ? L10n.t("مخفي", "Hidden")
                : (isDeceased ? Self.yearOnly(birth) : birth)
            rows.append(.init(
                icon: "calendar",
                label: L10n.t("الميلاد", "Birth"),
                value: displayValue,
                color: shouldHide ? DS.Color.textTertiary : DS.Color.primary
            ))
        }

        if !isDeceased,
           let phone = m.phoneNumber, !phone.isEmpty {
            let shouldHide = (m.isPhoneHidden == true) && !isSelf && !canMod
            rows.append(.init(
                icon: "phone.fill",
                label: L10n.t("الهاتف", "Phone"),
                value: shouldHide ? L10n.t("مخفي", "Hidden") : KuwaitPhone.display(phone),
                color: shouldHide ? DS.Color.textTertiary : DS.Color.success
            ))
        }

        if isDeceased,
           let death = m.deathDate, !death.isEmpty {
            rows.append(.init(
                icon: "heart.slash.fill",
                label: L10n.t("الوفاة", "Death"),
                value: Self.yearOnly(death),
                color: DS.Color.textTertiary
            ))
        }

        return rows
    }

    /// استخراج السنة فقط من تاريخ بصيغة "yyyy-MM-dd" أو "yyyy/MM/dd" — fallback للنص الأصلي.
    private static func yearOnly(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return trimmed }
        let prefix = String(trimmed.prefix(4))
        return prefix.allSatisfy(\.isNumber) ? prefix : trimmed
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
        if cachedFather != nil || !cachedChildren.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("العائلة", "Family"),
                        icon: "person.2.fill",
                        iconColor: DS.Color.success
                    )

                    VStack(spacing: 0) {
                        if let father = cachedFather {
                            Button {
                                // الشيت يبقى مفتوح — يتحدث محتواه + الشجرة تتزامن خلفه
                                let fatherId = father.id
                                currentMemberId = fatherId
                                NotificationCenter.default.post(
                                    name: .openMemberInTree,
                                    object: nil,
                                    userInfo: ["memberId": fatherId]
                                )
                            } label: {
                                familyRow(
                                    icon: "person.fill",
                                    label: L10n.t("الأب", "Father"),
                                    value: father.firstName,
                                    color: DS.Color.success
                                )
                            }
                            .buttonStyle(.plain)

                            if !cachedChildren.isEmpty {
                                Divider().padding(.leading, 56)
                            }
                        }

                        if !cachedChildren.isEmpty {
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    childrenExpanded.toggle()
                                }
                            } label: {
                                childrenRow(
                                    label: L10n.t("الأبناء", "Children"),
                                    value: childrenCountText,
                                    color: DS.Color.info,
                                    expanded: childrenExpanded
                                )
                            }
                            .buttonStyle(.plain)

                            if childrenExpanded {
                                childrenInlineGrid
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
        }
    }

    /// شبكة الأبناء inline — اسم أول فقط مع avatar مدوّر، 3 أعمدة
    private var childrenInlineGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3)
        return LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
            ForEach(cachedChildren) { child in
                Button {
                    // الشيت يبقى مفتوح — يتحدث محتواه + الشجرة تتزامن خلفه
                    let childId = child.id
                    currentMemberId = childId
                    NotificationCenter.default.post(
                        name: .openMemberInTree,
                        object: nil,
                        userInfo: ["memberId": childId]
                    )
                } label: {
                    childTileFirstName(child)
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.xs)
    }

    private func childTileFirstName(_ child: FamilyMember) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                if let url = child.avatarUrl, let imgUrl = URL(string: url) {
                    CachedAsyncImage(url: imgUrl) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(DS.Color.primary.opacity(0.12))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.primary.opacity(0.18), lineWidth: 1))
                } else {
                    ZStack {
                        Circle()
                            .fill(DS.Color.primary.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Text(String(child.firstName.prefix(1)))
                            .font(DS.Font.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                    }
                    .overlay(Circle().stroke(DS.Color.primary.opacity(0.18), lineWidth: 1))
                }

                if child.isDeceased == true {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "heart.slash.fill")
                                .font(DS.Font.scaled(10, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                        )
                        .offset(x: 22, y: 22)
                }
            }

            Text(child.firstName)
                .font(DS.Font.caption1)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// صف الأبناء مع chevron قابل للتوسعة
    private func childrenRow(label: String, value: String, color: Color, expanded: Bool) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "person.3.fill")
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
            Image(systemName: "chevron.down")
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    private var childrenCountText: String {
        let n = cachedChildren.count
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
        if canSeePendingRequests && !cachedPendingRequests.isEmpty {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    DSSectionHeader(
                        title: L10n.t("طلبات معلقة", "Pending Requests"),
                        icon: "clock.badge.exclamationmark.fill",
                        trailing: "\(cachedPendingRequests.count)",
                        iconColor: DS.Color.warning
                    )

                    VStack(spacing: 0) {
                        ForEach(cachedPendingRequests.indices, id: \.self) { index in
                            pendingRequestRow(cachedPendingRequests[index])
                            if index < cachedPendingRequests.count - 1 {
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
            case .editBirth: return DS.Color.warning
            case .deceased: return DS.Color.textTertiary
            case .addDeathDate: return DS.Color.textTertiary
            case .addPhoto: return DS.Color.primary
            case .delete: return DS.Color.error
            case .other: return DS.Color.accent
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

                    // إبلاغ عن العضو — متاح لغير صاحب الملف (سياسة Apple)
                    Button {
                        showReportConfirm = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(DS.Font.scaled(14, weight: .semibold))
                            Text(L10n.t("إبلاغ عن هذا العضو", "Report this member"))
                                .font(DS.Font.calloutBold)
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.textTertiary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
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
