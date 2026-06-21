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

    @State private var showDeleteBioAlert = false

    @State private var showActionSheet = false
    @State private var pendingEditAction: TreeEditAction? = nil
    @State private var showReportConfirm = false
    @State private var reportReason = ""
    @State private var reportSent = false
    @State private var familyExpanded = false
    @State private var showAddWife = false
    @State private var newWifeName = ""
    @State private var showAssignChildren = false
    @State private var assignSelection: Set<UUID> = []

    // MARK: - Cached State (تحسب مرة عند تغيير العضو لتفادي إعادة الحساب O(n) في كل rebuild)

    @State private var cachedFather: FamilyMember? = nil
    @State private var cachedMother: FamilyMember? = nil
    @State private var cachedHusband: FamilyMember? = nil
    @State private var cachedWives: [FamilyMember] = []
    @State private var cachedChildren: [FamilyMember] = []
    @State private var cachedPendingRequests: [AdminRequest] = []

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
        cachedMother = m.motherId.flatMap { memberVM.member(byId: $0) }
        cachedHusband = m.husbandId.flatMap { memberVM.member(byId: $0) }
        cachedWives = memberVM.allMembers
            .filter { $0.husbandId == m.id && $0.isFemale }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
        // الأنثى: أبناؤها = من motherId = هي. الذكر: من fatherId = هو.
        cachedChildren = memberVM.allMembers
            .filter {
                (m.isFemale ? $0.motherId == m.id : $0.fatherId == m.id) && $0.isCountable
            }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
        cachedPendingRequests = adminRequestVM.treeEditRequests.filter { $0.memberId == m.id }
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

                            overviewCard
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
            .sheet(item: $pendingEditAction) { action in
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
        // «إضافة صورة» انتقل إلى «طلب تعديل لهذا العضو» (addPhoto) ويظهر في
        // طلبات المراجعة كبقية طلبات الشجرة — فلم يعد زراً مباشراً هنا.
        let showKinship = !isViewingSelf && !member.isDeleted
        let age = ageText

        if age != nil || showKinship {
            HStack(spacing: DS.Spacing.sm) {
                Spacer(minLength: 0)
                if let age = age {
                    agePill(age)
                }
                if showKinship {
                    quickPill(
                        icon: "point.3.connected.trianglepath.dotted",
                        label: L10n.t("صلة القرابة", "Kinship"),
                        color: DS.Color.warning,
                        action: showKinshipPath
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// شارة العمر بجانب «صلة القرابة».
    private func agePill(_ age: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(L10n.t("العمر", "Age"))
                .font(DS.Font.scaled(12, weight: .bold))
            Text(age)
                .font(DS.Font.scaled(12, weight: .bold))
        }
        .foregroundColor(DS.Color.primary)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs + 2)
        .background(DS.Color.primary.opacity(0.12))
        .clipShape(Capsule())
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

    private struct StatItem: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        let color: Color
    }

    private func computeStats(isDeceased: Bool, birthYear: String?, deathYear: String?) -> [StatItem] {
        var s: [StatItem] = []
        if let byStr = birthYear, let by = Int(byStr) {
            let end: Int? = isDeceased
                ? Int(deathYear ?? "")
                : Calendar.current.component(.year, from: Date())
            if let end = end, end >= by, end - by < 130 {
                s.append(.init(
                    value: "\(end - by)",
                    label: isDeceased ? L10n.t("العمر عند الوفاة", "Age at death") : L10n.t("العمر", "Age"),
                    color: DS.Color.textPrimary
                ))
            }
            s.append(.init(value: byStr, label: L10n.t("سنة الميلاد", "Birth year"), color: DS.Color.textPrimary))
        }
        if isDeceased {
            if let dy = deathYear {
                s.append(.init(value: dy, label: L10n.t("سنة الوفاة", "Death year"), color: DS.Color.error))
            } else {
                s.append(.init(value: L10n.t("متوفّى", "Deceased"), label: L10n.t("الحالة", "Status"), color: DS.Color.textSecondary))
            }
        } else {
            s.append(.init(value: L10n.t("نشِط", "Active"), label: L10n.t("الحالة", "Status"), color: DS.Color.success))
        }
        return s
    }

    /// بطاقة موحّدة: المعلومات الأساسية + العائلة في مربع واحد.
    @ViewBuilder
    private var overviewCard: some View {
        let isDeceased = member.isDeceased == true
        let isSelf = member.id == authVM.currentUser?.id
        let canMod = authVM.canModerate
        let birth = (member.birthDate ?? "").trimmingCharacters(in: .whitespaces)
        let death = (member.deathDate ?? "").trimmingCharacters(in: .whitespaces)
        let phone = (member.phoneNumber ?? "").trimmingCharacters(in: .whitespaces)
        let birthHidden = (member.isBirthDateHidden == true) && !isSelf && !canMod
        let phoneHidden = (member.isPhoneHidden == true) && !isSelf && !canMod
        let birthYear: String? = (!birth.isEmpty && !birthHidden) ? Self.yearOnly(birth) : nil
        let deathYear: String? = !death.isEmpty ? Self.yearOnly(death) : nil

        let chips = buildChips(
            isDeceased: isDeceased, birthYear: birthYear, deathYear: deathYear,
            phone: phone, phoneHidden: phoneHidden
        )
        let hasFamily = cachedFather != nil || cachedMother != nil
            || cachedHusband != nil || !cachedWives.isEmpty || !cachedChildren.isEmpty

        if !chips.isEmpty || hasFamily {
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    // دوائر صغيرة: الميلاد · الوفاة · الهاتف.
                    if !chips.isEmpty {
                        HStack(alignment: .top, spacing: DS.Spacing.md) {
                            ForEach(chips) { c in circleView(c) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.md)
                    }

                    // العائلة — مدمجة داخل نفس المربع.
                    if hasFamily {
                        if !chips.isEmpty {
                            DSDivider()
                                .padding(.bottom, DS.Spacing.sm)
                        }
                        familyInline
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, chips.isEmpty ? DS.Spacing.lg : 0)
                            .padding(.bottom, DS.Spacing.md)
                    }
                }
            }
        }
    }

    /// العائلة المدمجة: عنقود (الزوجة | الأب | الأم) + الأبناء (يظهرون/يختفون).
    /// مسموح بتحديد أبناء الزوجة: العضو أنثى + لها زوج + (مدير أو هي نفسها).
    private var canAssignChildren: Bool {
        member.isFemale && member.husbandId != nil
            && (authVM.canEditMembers || isViewingSelf)
    }

    /// أبناء زوج الزوجة (المرشّحون لتحديد أمّهم).
    private var husbandChildren: [FamilyMember] {
        guard let hid = member.husbandId else { return [] }
        return memberVM.allMembers
            .filter { $0.fatherId == hid && $0.isCountable }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    private var familyInline: some View {
        VStack(spacing: DS.Spacing.md) {
            relationsCluster

            if canAssignChildren {
                Button {
                    assignSelection = Set(husbandChildren.filter { $0.motherId == member.id }.map(\.id))
                    showAssignChildren = true
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "checklist")
                            .font(DS.Font.scaled(13, weight: .semibold))
                        Text(L10n.t("تحديد أبنائها", "Assign her children"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.primary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .sheet(isPresented: $showAssignChildren) { assignChildrenSheet }
            }

            // الأبناء — بالمنتصف مع سهم، يظهرون/يختفون
            if !cachedChildren.isEmpty {
                Button {
                    withAnimation(DS.Anim.snappy) { familyExpanded.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(L10n.t("الأبناء", "Children"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                        Image(systemName: "chevron.down")
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(DS.Color.primary)
                            .rotationEffect(.degrees(familyExpanded ? 180 : 0))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())

                if familyExpanded {
                    childrenCenteredWrap
                }
            }
        }
    }

    /// عنقود العلاقات: الزوجة/الزوجات (يسار) | الأم (يمين) بينهما خط عمودي.
    /// يعرض البيانات الحقيقية (motherId / husbandId)؛ ومكان محجوز (+) عند الغياب.
    private var relationsCluster: some View {
        let circle: CGFloat = 48
        return HStack(alignment: .top, spacing: DS.Spacing.xl) {
            // RTL: الأم يميناً.
            if let mother = cachedMother {
                relReal(member: mother, label: L10n.t("الأم", "Mother"), size: circle)
            } else {
                relPlaceholder(label: L10n.t("الأم", "Mother"), color: DS.Color.warning, size: circle)
            }
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.30))
                .frame(width: 1.5, height: circle)
            // الأنثى: تعرض «الزوج». الذكر: تعرض «الزوجة/الزوجات» (يسار).
            if member.isFemale {
                if let husband = cachedHusband {
                    relReal(member: husband, label: L10n.t("الزوج", "Husband"), size: circle)
                } else {
                    relPlaceholder(label: L10n.t("الزوج", "Husband"), color: DS.Color.accent, size: circle)
                }
            } else if cachedWives.isEmpty {
                relPlaceholder(label: L10n.t("الزوجة", "Wife"), color: DS.Color.accent, size: circle,
                               action: canAddWife ? { showAddWife = true } : nil)
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    ForEach(cachedWives) { wife in
                        relReal(member: wife, label: L10n.t("الزوجة", "Wife"), size: circle)
                    }
                    if canAddWife {
                        Button { showAddWife = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(DS.Font.scaled(22))
                                .foregroundColor(DS.Color.accent)
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .alert(L10n.t("إضافة زوجة", "Add Wife"), isPresented: $showAddWife) {
            TextField(L10n.t("اسم الزوجة", "Wife name"), text: $newWifeName)
            Button(L10n.t("إضافة", "Add")) {
                let name = newWifeName
                newWifeName = ""
                Task {
                    _ = await memberVM.addWife(husband: member, firstName: name)
                    recomputeCache()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { newWifeName = "" }
        }
    }

    /// مسموح بإضافة زوجة: العضو رجل + (مدير يعدّل أو هو نفسه).
    private var canAddWife: Bool {
        !member.isFemale && (authVM.canEditMembers || isViewingSelf)
    }

    /// شيت تحديد أبناء الزوجة — اختيار متعدّد من أبناء زوجها، ثم ضبط mother_id.
    private var assignChildrenSheet: some View {
        NavigationStack {
            List {
                ForEach(husbandChildren) { child in
                    Button {
                        if assignSelection.contains(child.id) {
                            assignSelection.remove(child.id)
                        } else {
                            assignSelection.insert(child.id)
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            Image(systemName: assignSelection.contains(child.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(assignSelection.contains(child.id)
                                                 ? DS.Color.primary : DS.Color.textTertiary)
                            Text(child.firstName)
                                .foregroundColor(DS.Color.textPrimary)
                            if child.isFemale {
                                Text(L10n.t("بنت", "Daughter"))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle(L10n.t("أبناء ", "Children of ") + member.firstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { showAssignChildren = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("حفظ", "Save")) {
                        let sel = assignSelection
                        let candidates = husbandChildren
                        showAssignChildren = false
                        Task {
                            for c in candidates {
                                let wantHer = sel.contains(c.id)
                                let isHer = c.motherId == member.id
                                if wantHer && !isHer {
                                    await memberVM.setMother(childId: c.id, motherId: member.id)
                                } else if !wantHer && isHer {
                                    await memberVM.setMother(childId: c.id, motherId: nil)
                                }
                            }
                            recomputeCache()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .presentationDetents([.medium, .large])
    }

    /// عنصر علاقة حقيقي (الأم/الزوجة) — صورة + تسمية + اسم، قابل للضغط.
    private func relReal(member m: FamilyMember, label: String, size: CGFloat) -> some View {
        Button { openMemberInTree(m.id) } label: {
            VStack(spacing: 5) {
                Group {
                    if m.isFemale {
                        FemaleAvatarView().frame(width: size, height: size)
                    } else if let urlStr = m.avatarUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(DS.Color.primary.opacity(0.12))
                        }
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(DS.Color.primary.opacity(0.12)).frame(width: size, height: size)
                            Text(String(m.firstName.prefix(1)))
                                .font(DS.Font.headline).fontWeight(.bold).foregroundColor(DS.Color.primary)
                        }
                    }
                }
                Text(label)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                Text(m.firstName)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// مكان محجوز لعلاقة (الأم/الزوجة): دائرة متقطّعة فيها زر إضافة (+) + تسمية.
    /// لو [action] متوفّر → قابل للضغط لإضافة العلاقة.
    @ViewBuilder
    private func relPlaceholder(label: String, color: Color, size: CGFloat,
                               action: (() -> Void)? = nil) -> some View {
        let content = VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.06))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().strokeBorder(
                            color.opacity(0.40),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                    )
                Image(systemName: "plus")
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(color.opacity(0.6))
            }
            Text(label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 70)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(DSScaleButtonStyle())
        } else {
            content
        }
    }

    private var sonsList: [FamilyMember] { cachedChildren.filter { !$0.isFemale } }
    private var daughtersList: [FamilyMember] { cachedChildren.filter { $0.isFemale } }

    /// لو فيه زوجات وبعض الأبناء معرّف أمّهم → تجميع تحت كل أم؛
    /// غير ذلك → الأبناء يمين والبنات يسار (بلا تسميات).
    @ViewBuilder
    private var childrenCenteredWrap: some View {
        if !cachedWives.isEmpty && cachedChildren.contains(where: { $0.motherId != nil }) {
            childrenByMother
        } else if sonsList.isEmpty || daughtersList.isEmpty {
            childrenWrap(cachedChildren, perRow: 5)
        } else {
            // RTL: الأبناء يميناً (أول)، خط عمودي، ثم البنات يساراً.
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                childrenWrap(sonsList, perRow: 3)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(0.25))
                    .frame(width: 1)
                childrenWrap(daughtersList, perRow: 3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// الأبناء مجمّعين تحت كل أم (زوجة) + مجموعة «أبناء آخرون».
    private var childrenByMother: some View {
        let wifeIds = Set(cachedWives.map { $0.id })
        let others = cachedChildren.filter { $0.motherId == nil || !wifeIds.contains($0.motherId!) }
        return VStack(spacing: DS.Spacing.lg) {
            ForEach(cachedWives) { wife in
                let kids = cachedChildren.filter { $0.motherId == wife.id }
                if !kids.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(L10n.t("أبناء ", "Children of ") + wife.firstName)
                            .font(DS.Font.caption1).fontWeight(.semibold)
                            .foregroundColor(DS.Color.textSecondary)
                        childrenWrap(kids, perRow: 5)
                    }
                }
            }
            if !others.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("أبناء آخرون", "Other children"))
                        .font(DS.Font.caption1).fontWeight(.semibold)
                        .foregroundColor(DS.Color.textSecondary)
                    childrenWrap(others, perRow: 5)
                }
            }
        }
    }

    /// شبكة أبناء تلتفّ على عدة صفوف.
    private func childrenWrap(_ members: [FamilyMember], perRow: Int) -> some View {
        let rows: [[FamilyMember]] = stride(from: 0, to: members.count, by: perRow).map {
            Array(members[$0..<min($0 + perRow, members.count)])
        }
        return VStack(spacing: DS.Spacing.md) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: DS.Spacing.md) {
                    ForEach(rows[r]) { child in
                        Button { openMemberInTree(child.id) } label: {
                            childTileFirstName(child)
                                .frame(width: 50)
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct ChipData: Identifiable {
        let id = UUID()
        let text: String
        let label: String
        let color: Color
        var ltr: Bool = false
        var big: Bool = false
    }

    private func buildChips(isDeceased: Bool, birthYear: String?, deathYear: String?, phone: String, phoneHidden: Bool) -> [ChipData] {
        var c: [ChipData] = []
        if let by = birthYear {
            c.append(.init(text: by, label: L10n.t("الميلاد", "Birth"), color: DS.Color.primary))
        }
        // العمر انتقل إلى شريط «صلة القرابة» أعلى البطاقة.
        if isDeceased, let dy = deathYear {
            c.append(.init(text: dy, label: L10n.t("الوفاة", "Death"), color: DS.Color.error))
        }
        if !isDeceased, !phone.isEmpty {
            c.append(.init(
                text: phoneHidden ? L10n.t("مخفي", "Hidden") : KuwaitPhone.display(phone),
                label: L10n.t("الهاتف", "Phone"),
                color: DS.Color.primaryDark, ltr: !phoneHidden, big: true
            ))
        }
        return c
    }

    /// عمر العضو كنص (يحترم إخفاء الميلاد) — يُعرض بجانب «صلة القرابة».
    private var ageText: String? {
        let isSelf = member.id == authVM.currentUser?.id
        let canMod = authVM.canModerate
        let birth = (member.birthDate ?? "").trimmingCharacters(in: .whitespaces)
        let birthHidden = (member.isBirthDateHidden == true) && !isSelf && !canMod
        guard !birth.isEmpty, !birthHidden, let by = Int(Self.yearOnly(birth)) else { return nil }
        let isDeceased = member.isDeceased == true
        let death = (member.deathDate ?? "").trimmingCharacters(in: .whitespaces)
        let end = isDeceased ? Int(Self.yearOnly(death)) : Calendar.current.component(.year, from: Date())
        guard let end = end, end >= by, end - by < 130 else { return nil }
        return "\(end - by)"
    }

    /// خانة معلومة بدون أيقونة: قيمة ملوّنة بارزة + تسمية صغيرة.
    private func circleView(_ c: ChipData) -> some View {
        VStack(spacing: 3) {
            Text(c.text)
                .font(c.big ? DS.Font.headline : DS.Font.callout)
                .fontWeight(.bold)
                .foregroundColor(c.color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .environment(\.layoutDirection, c.ltr ? .leftToRight : LanguageManager.shared.layoutDirection)
            Text(c.label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
        }
        // الهاتف عريض ومقيّد؛ الميلاد/الوفاة بحجم محتواهما ليقتربا من بعض.
        .frame(maxWidth: c.big ? 150 : nil)
    }

    /// خانة إحصائية: رقم بارز + تسمية صغيرة.
    private func statCell(_ s: StatItem) -> some View {
        VStack(spacing: 3) {
            Text(s.value)
                .font(DS.Font.title3)
                .fontWeight(.semibold)
                .foregroundColor(s.color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(s.label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    /// استخراج السنة فقط من تاريخ بصيغة "yyyy-MM-dd" أو "yyyy/MM/dd" — fallback للنص الأصلي.
    private static func yearOnly(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return trimmed }
        let prefix = String(trimmed.prefix(4))
        return prefix.allSatisfy(\.isNumber) ? prefix : trimmed
    }


    // MARK: - Family (inline inside overview card)

    private func openMemberInTree(_ id: UUID) {
        // الشيت يبقى مفتوح — يتحدث محتواه + الشجرة تتزامن خلفه.
        currentMemberId = id
        NotificationCenter.default.post(
            name: .openMemberInTree, object: nil, userInfo: ["memberId": id]
        )
    }


    private func childTileFirstName(_ child: FamilyMember) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                if child.isFemale {
                    // قاعدة: الأنثى بلا صورة شخصية — صورة أنثى مرسومة.
                    FemaleAvatarView()
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.primary.opacity(0.18), lineWidth: 1))
                } else if let url = child.avatarUrl, let imgUrl = URL(string: url) {
                    CachedAsyncImage(url: imgUrl) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(DS.Color.primary.opacity(0.12))
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.primary.opacity(0.18), lineWidth: 1))
                } else {
                    ZStack {
                        Circle()
                            .fill(DS.Color.primary.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Text(String(child.firstName.prefix(1)))
                            .font(DS.Font.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                    }
                    .overlay(Circle().stroke(DS.Color.primary.opacity(0.18), lineWidth: 1))
                }

                if child.isDeceased == true {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "heart.slash.fill")
                                .font(DS.Font.scaled(8, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                        )
                        .offset(x: 15, y: 15)
                }
            }

            Text(child.firstName)
                .font(DS.Font.caption2)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
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
            HStack(alignment: .top, spacing: DS.Spacing.xxl) {
                if !isViewingSelf {
                    circleActionButton(
                        icon: "pencil.and.list.clipboard",
                        label: L10n.t("طلب تعديل", "Request Edit"),
                        tint: DS.Color.primary,
                        filled: true
                    ) { showActionSheet = true }

                    // إبلاغ عن العضو — متاح لغير صاحب الملف (سياسة Apple)
                    circleActionButton(
                        icon: "exclamationmark.bubble",
                        label: L10n.t("إبلاغ", "Report"),
                        tint: DS.Color.warning
                    ) { showReportConfirm = true }
                }

                if authVM.canEditMembers {
                    circleActionButton(
                        icon: "pencil",
                        label: L10n.t("تعديل مباشر", "Direct Edit"),
                        tint: DS.Color.primary
                    ) { showAdminControl = true }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// زر دائري بأيقونة + تسمية قصيرة (بديل الأزرار الممتدة في الأسفل).
    private func circleActionButton(
        icon: String,
        label: String,
        tint: Color,
        filled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    if filled {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 62, height: 62)
                            .dsSubtleShadow()
                        Image(systemName: icon)
                            .font(DS.Font.scaled(22, weight: .semibold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    } else {
                        Circle()
                            .fill(tint.opacity(0.12))
                            .frame(width: 62, height: 62)
                            .overlay(Circle().stroke(tint.opacity(0.30), lineWidth: 1.5))
                        Image(systemName: icon)
                            .font(DS.Font.scaled(22, weight: .semibold))
                            .foregroundColor(tint)
                    }
                }
                Text(label)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .buttonStyle(DSScaleButtonStyle())
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
            if member.isFemale {
                // قاعدة: الأنثى بلا صورة شخصية — صورة أنثى مرسومة.
                FemaleAvatarView()
            } else if let url = member.avatarUrl, let imageUrl = URL(string: url) {
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
                    Image(systemName: member.fallbackSymbol)
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
