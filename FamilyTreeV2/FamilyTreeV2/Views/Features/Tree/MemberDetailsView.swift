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

    /// true = مربّع بمنتصف الشاشة قابل للتوسّع بدل الشيت (طلب المالك)
    private let centered: Bool

    init(member: FamilyMember, centered: Bool = false) {
        self.initialMember = member
        self.centered = centered
        _currentMemberId = State(initialValue: member.id)
    }

    @State private var showAdminControl = false
    @State private var avatarPreviewScale: CGFloat = 1.0
    @State private var lastAvatarPreviewScale: CGFloat = 1.0
    @State private var showAvatarPreview = false

    @State private var showDeleteBioAlert = false

    @State private var showEditActions = false
    @State private var pendingEditAction: TreeEditAction? = nil
    @State private var showReportConfirm = false
    @State private var reportReason = ""
    @State private var reportSent = false
    @State private var showChildrenSheet = false
    /// شريط العائلة (الأب والأبناء) مخفي بالبداية (طلب المالك)
    @State private var familyOpen = false
    /// حجم الشيت: متوسط = صورة+اسم+قرابة+عمر فقط، كبير = كل المعلومات.
    @State private var detent: PresentationDetent = .fraction(0.46)
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — الشيت يملأ الشاشة، نعرض كل التفاصيل بعمودين
    private var isLandscape: Bool { vSizeClass == .compact }

    // MARK: - Cached State (تحسب مرة عند تغيير العضو لتفادي إعادة الحساب O(n) في كل rebuild)

    @State private var cachedFather: FamilyMember? = nil
    @State private var cachedChildren: [FamilyMember] = []
    @State private var cachedPendingRequests: [AdminRequest] = []
    @State private var cachedBasicInfoRows: [InfoRowData] = []

    private var isViewingSelf: Bool {
        member.id == authVM.currentUser?.id
    }


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
        if centered {
            DSExpandableCenterPanel(
                isExpanded: Binding(
                    get: { detent == .large },
                    set: { detent = $0 ? .large : .fraction(0.46) }
                ),
                onClose: { dismiss() }
            ) {
                detailsStack
            }
        } else {
            detailsStack
        }
    }

    private var detailsStack: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DS.Color.background.ignoresSafeArea()

                if member.isDeleted {
                    deletedMemberView
                } else {
                    ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        if isLandscape {
                            // الوضع الأفقي: الشيت يملأ الشاشة — نعرض كل التفاصيل على عمودين
                            HStack(alignment: .top, spacing: DS.Spacing.md) {
                                VStack(spacing: DS.Spacing.md) {
                                    compactHeroSection
                                        .padding(.top, DS.Spacing.lg)

                                    quickActionsRow
                                        .padding(.horizontal, DS.Spacing.lg)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(spacing: DS.Spacing.md) {
                                    infoGrid
                                        .padding(.horizontal, DS.Spacing.lg)

                                    bioCard
                                        .padding(.horizontal, DS.Spacing.lg)

                                    pendingRequestsCard
                                        .padding(.horizontal, DS.Spacing.lg)

                                    actionButtonsSection
                                        .padding(.horizontal, DS.Spacing.lg)
                                }
                                .padding(.top, DS.Spacing.lg)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.bottom, DS.Spacing.xxxl)
                        } else {
                        VStack(spacing: DS.Spacing.md) {
                            // الرأس: الصورة والاسم والقرابة وزر التفاصيل — ارتفاعه = المربّع المصغّر
                            VStack(spacing: DS.Spacing.md) {
                                compactHeroSection
                                    .padding(.top, DS.Spacing.lg)

                                quickActionsRow
                                    .padding(.horizontal, DS.Spacing.lg)

                                if centered {
                                    detailsToggleButton
                                }
                            }
                            .id("detailsTop")
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: DSPanelCollapsedHeightKey.self,
                                                           value: geo.size.height + DS.Spacing.lg)
                                }
                            )

                            if centered {
                                // التفاصيل تبقى في مكانها ويُقصّ المربّع فوقها عند الإخفاء —
                                // فلا تختفي فجأة (طلب المالك): يتحرّك الارتفاع وحده
                                detailsBody
                                    .opacity(detent == .large ? 1 : 0)
                                    .allowsHitTesting(detent == .large)
                            } else if detent == .large {
                                detailsBody
                            } else {
                                // تلميح: اسحب لأعلى لعرض المزيد
                                Text(L10n.t("اسحب لأعلى لعرض التفاصيل", "Swipe up for details"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .padding(.top, DS.Spacing.md)
                            }

                            Spacer(minLength: centered ? DS.Spacing.lg : 60)
                        }
                        // المربّع بحجم محتواه (طلب المالك)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: SheetContentHeightKey.self,
                                                       value: geo.size.height)
                            }
                        )
                        }
                    }
                    .scrollDisabled(centered && detent != .large)
                    .onChange(of: detent) { newValue in
                        if centered, newValue != .large {
                            withAnimation(DS.Anim.smooth) { scrollProxy.scrollTo("detailsTop", anchor: .top) }
                        }
                    }
                    }
                }

                if centered { topCancelButton } else { floatingCloseButton }
            }
            .onAppear { recomputeCache() }
            .onChange(of: currentMemberId) { _ in recomputeCache() }
            .onChange(of: memberVM.membersVersion) { _ in recomputeCache() }
            .onChange(of: adminRequestVM.treeEditRequests.count) { _ in recomputeCache() }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            // ارتفاعات الشيت فقط في وضع الشيت — داخل المربّع تدفع الاختيار إلى «large»
            .modifier(SheetDetents(enabled: !centered, detent: $detent))
            // التعديل المباشر: لوح بمنتصف الشاشة بدل الورقة السفلية (طلب المالك)
            .fullScreenCover(isPresented: $showAdminControl) {
                if authVM.canEditMembers {
                    // ملاحظة: لا نضع .id(membersVersion) هنا — كان يُعيد بناء
                    // اللوح بالكامل عند كل upsertMemberLocally (مثلاً
                    // عند إضافة ابن)، فيُفقد scroll position ويرجع للأعلى.
                    // المحتوى يتحدث طبيعياً عبر @EnvironmentObject memberVM.
                    DSCenterPanel(onBackgroundTap: nil) {
                        AdminMemberDetailSheet(member: member)
                    }
                    .background(ClearPresentationBackground())
                }
            }
            .transaction { t in
                // بلا انزلاق من الأسفل — اللوح يظهر بنفسه في المنتصف
                if showAdminControl || pendingEditAction != nil || showEditActions {
                    t.disablesAnimations = true
                }
            }
            // اختيار نوع الطلب — مربّع بمنتصف الشاشة (طلب المالك)
            .fullScreenCover(isPresented: $showEditActions) {
                DSCenterCard(onBackgroundTap: { showEditActions = false }) {
                    editActionsGrid
                }
                .background(ClearPresentationBackground())
            }
            // «طلب تعديل» كذلك لوح بمنتصف الشاشة (طلب المالك)
            .fullScreenCover(item: $pendingEditAction) { action in
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    TreeEditRequestView(member: member, action: action)
                }
                .background(ClearPresentationBackground())
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
        .dsAlert(
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
        .dsAlert(L10n.t("إبلاغ عن عضو", "Report Member"), isPresented: $showReportConfirm) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                .dsAlertField()
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
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK")) { }
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

    /// «عرض التفاصيل» / «إخفاء التفاصيل» — يوسّع المربّع أو يصغّره
    private var detailsToggleButton: some View {
        let expanded = detent == .large
        return Button {
            withAnimation(DS.Anim.snappy) { detent = expanded ? .fraction(0.46) : .large }
        } label: {
            Label(expanded ? L10n.t("إخفاء التفاصيل", "Hide details")
                           : L10n.t("عرض التفاصيل", "Show details"),
                  systemImage: expanded ? "chevron.down" : "chevron.up")
                .font(DS.Font.plex(13, weight: .bold))
                // لون ممتلئ مختلف عن شارة العمر (طلب المالك)
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.lg)
                .frame(height: 38)
                .background(DSActionFill.style(), in: Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    /// «إلغاء» أحمر أعلى المربّع — في الجهة اليسرى مثل بقية المربّعات (طلب المالك)
    private var topCancelButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text(L10n.t("إلغاء", "Cancel"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.error)
                        .padding(.horizontal, DS.Spacing.md)
                        .frame(height: 36)
                        .background(DS.Color.background, in: Capsule())
                        .overlay(Capsule().stroke(DS.Color.textTertiary.opacity(0.2), lineWidth: 0.5))
                        .dsSubtleShadow()
                }
                .buttonStyle(DSScaleButtonStyle())
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.md)
            Spacer()
        }
    }

    private var compactHeroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                // (أُزيل التوهّج المموّه خلف الصورة — كان يُقصّ بإطار مربّع، طلب المالك)
                ZStack {
                    avatarContent
                        .frame(width: 130, height: 130)
                        .clipShape(Circle())
                        // المتوفّى بالأبيض والأسود (طلب المالك)
                        .grayscale(member.isDeceased == true ? 1 : 0)
                        // إطار دائري خفيف جداً بلا توهّج (طلب المالك)
                        .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
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
                            // إطار خفيف لعلامة الوفاة (طلب المالك)
                            .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
                            .offset(x: 48, y: 48)
                    }
                }
            }

            Text(member.displayFullName)
                // أصغر حبّتين (طلب المالك)
                .font(DS.Font.plex(18, weight: .bold))
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
        HStack(spacing: DS.Spacing.sm) {
            if showKinship {
                quickPill(
                    icon: "point.3.connected.trianglepath.dotted",
                    label: L10n.t("صلة القرابة", "Kinship"),
                    color: DS.Color.warning,
                    action: showKinshipPath
                )
            }
            // العمر جنب القرابة (مع مؤشّر متوفّى)
            agePill
        }
    }

    /// حبّة العمر — تظهر جنب زر القرابة. للمتوفّى: رمادي + رمز يوضّح الوفاة.
    @ViewBuilder
    private var agePill: some View {
        let isDeceased = member.isDeceased == true
        let by = year(from: member.birthDate)
        let dy = year(from: member.deathDate)
        if let byStr = by, let byInt = Int(byStr) {
            let end: Int? = isDeceased ? Int(dy ?? "") : Calendar.current.component(.year, from: Date())
            if let end, end >= byInt, end - byInt < 130 {
                let age = end - byInt
                let color = isDeceased ? DS.Color.textSecondary : DS.Color.info
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: isDeceased ? "heart.slash.fill" : "timelapse")
                        .font(DS.Font.scaled(11, weight: .semibold))
                    Text("\(age) " + L10n.t("سنة", "yrs"))
                        .font(DS.Font.scaled(12, weight: .bold))
                    if isDeceased {
                        Text(L10n.t("· متوفّى", "· deceased"))
                            .font(DS.Font.scaled(11, weight: .semibold))
                    }
                }
                .foregroundColor(color)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    private func year(from s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
              let r = s.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return String(s[r])
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

    // MARK: - Father Cell (مسار لأعلى — الأب)

    /// خلية الأب القابلة للضغط — تنقل الشيت والشجرة للأب (مسار لأعلى في الشجرة).
    /// تظهر فقط عند وجود أب، وتحاكي خلايا الأم/الزوج في شيت النساء (relationCell).
    @ViewBuilder
    /// جسم التفاصيل: شبكة أيقونات (المعلومات + الأب + الأبناء) ← السيرة ← الطلبات ← الأزرار
    private var detailsBody: some View {
        VStack(spacing: DS.Spacing.md) {
            infoGrid
                .padding(.horizontal, DS.Spacing.lg)

            familyStrip
                .padding(.horizontal, DS.Spacing.lg)

            bioCard
                .padding(.horizontal, DS.Spacing.lg)

            pendingRequestsCard
                .padding(.horizontal, DS.Spacing.lg)

            actionButtonsSection
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
        }
    }

    // MARK: شريط العائلة — الأب والأبناء بشكل جديد (طلب المالك)

    /// الأب بصورته وحلقة ذهبية، ثم فاصل، ثم الأبناء بصور صغيرة تتمرّر أفقياً.
    /// الضغط على أي صورة يفتح صاحبها.
    @ViewBuilder
    private var familyStrip: some View {
        let father = cachedFather
        let children = cachedChildren
        if father != nil || !children.isEmpty {
            VStack(spacing: 0) {
                // الرأس: يفتح/يخفي الأب والأبناء — مخفيّون بالبداية
                Button {
                    withAnimation(DS.Anim.snappy) { familyOpen.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.fill")
                            .font(DS.Font.plex(12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DS.Color.accent))
                        Text(L10n.t("العائلة", "Family"))
                            .font(DS.Font.plex(13, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                        Text(familySummary(hasFather: father != nil, children: children.count))
                            .font(DS.Font.plex(11.5, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(DS.Font.plex(11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .rotationEffect(.degrees(familyOpen ? 180 : 0))
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if familyOpen {
                    // الأبناء ملاصقون للأب تقريباً (طلب المالك)
                    VStack(alignment: .leading, spacing: 0) {
                        // الأب بالمنتصف بخلفية خفيفة (طلب المالك)
                        if let father {
                            Button { openMemberInTree(father.id) } label: {
                                familyBubble(father, size: 50, ring: DS.Color.warning,
                                             caption: L10n.t("الأب", "Father"))
                                    .padding(.vertical, DS.Spacing.sm)
                                    // الخلفية بعرض المربّع كامل (طلب المالك)
                                    .frame(maxWidth: .infinity)
                                    .background(DS.Color.warning.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(DSScaleButtonStyle())
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)

                        }

                        // الأبناء: شبكة أربعة في كل صف (بدل الصف المتمرّر — طلب المالك)
                        if !children.isEmpty {
                            Text(L10n.t("الأبناء", "Children") + " · \(children.count)")
                                .font(DS.Font.plex(11, weight: .bold))
                                .foregroundColor(DS.Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 2)
                            // الأبناء بالمنتصف: صفوف من أربعة، كل صف متمركز (طلب المالك)
                            VStack(spacing: 4) {
                                ForEach(Array(stride(from: 0, to: children.count, by: 4)), id: \.self) { start in
                                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                                        ForEach(children[start..<min(start + 4, children.count)]) { child in
                                            Button { openMemberInTree(child.id) } label: {
                                                familyBubble(child, size: 42, ring: DS.Color.primary.opacity(0.35),
                                                             caption: nil)
                                            }
                                            .buttonStyle(DSScaleButtonStyle())
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.sm)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.textTertiary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    /// «الأب · ٣ أبناء» — ملخّص تحت العنوان والشريط مقفول
    private func familySummary(hasFather: Bool, children: Int) -> String {
        var parts: [String] = []
        if hasFather { parts.append(L10n.t("الأب", "Father")) }
        if children > 0 { parts.append(L10n.t("\(children) أبناء", "\(children) children")) }
        return parts.joined(separator: " · ")
    }

    /// صورة دائرية بحلقة + الاسم الأول تحتها (+ وصف فوق الاسم للأب)
    private func familyBubble(_ m: FamilyMember, size: CGFloat, ring: Color, caption: String?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let url = m.avatarUrl, let imgUrl = URL(string: url) {
                    CachedAsyncImage(url: imgUrl) { img in img.resizable().scaledToFill() }
                    placeholder: { Circle().fill(DS.Color.primary.opacity(0.10)) }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.10))
                        .frame(width: size, height: size)
                        .overlay(
                            Text(String(m.firstName.prefix(1)))
                                .font(DS.Font.plex(size * 0.36, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                        )
                }
            }
            .overlay(Circle().stroke(ring, lineWidth: 1.5).padding(-2))
            // المتوفّى بالأبيض والأسود (طلب المالك)
            .grayscale(m.isDeceased == true ? 1 : 0)

            if let caption {
                Text(caption)
                    .font(DS.Font.plex(10.5, weight: .bold))
                    .foregroundColor(DS.Color.warning)
            }
            Text(m.firstName)
                .font(DS.Font.plex(11.5, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: size + 18)
        }
    }

    // MARK: شبكة المعلومات الأيقونية (طلب المالك)

    private struct InfoTileData: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: String
        let color: Color
        var ltr = false
    }

    /// المعلومات في بلاطات أيقونية: الميلاد، الهاتف، الوفاة (بلا الأب والأبناء — طلب المالك)
    private var infoTiles: [InfoTileData] {
        cachedBasicInfoRows.enumerated().map { idx, row in
            InfoTileData(id: "info-\(idx)", icon: row.icon, label: row.label, value: row.value,
                         color: row.color, ltr: row.icon == "phone.fill")
        }
    }

    @ViewBuilder
    private var infoGrid: some View {
        let tiles = infoTiles
        if !tiles.isEmpty {
            // بلاطتان في كل صف (طلب المالك)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 2),
                spacing: DS.Spacing.sm
            ) {
                ForEach(tiles) { infoTileView($0) }
            }
        }
    }

    /// بلاطة: دائرة أيقونة ملوّنة، ثم القيمة بارزة والعنوان تحتها — على خلفية
    /// بتدرّج خفيف من لون الأيقونة
    private func infoTileView(_ tile: InfoTileData) -> some View {
        // بلاطة مدمجة: الأيقونة جنب القيمة والعنوان، وخلفية خفيفة جداً (طلب المالك)
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: tile.icon)
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tile.color))

            VStack(alignment: .leading, spacing: 1) {
                Text(tile.label)
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                Text(tile.value)
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .environment(\.layoutDirection, tile.ltr ? .leftToRight : LanguageManager.shared.layoutDirection)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(tile.color.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(tile.color.opacity(0.12), lineWidth: 1)
        )
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
        // ملاحظة: العمر انتقل إلى حبّة جنب زر القرابة (agePill) — لا يُكرّر هنا.
        if let byStr = birthYear {
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

    private struct ChipData: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let label: String
        let color: Color
        var ltr: Bool = false
    }

    private func buildChips(isDeceased: Bool, birthYear: String?, deathYear: String?, phone: String, phoneHidden: Bool) -> [ChipData] {
        var c: [ChipData] = []
        if let by = birthYear {
            c.append(.init(icon: "birthday.cake", text: by, label: L10n.t("الميلاد", "Birth"), color: DS.Color.primary))
        }
        if let byStr = birthYear, let by = Int(byStr) {
            let end = isDeceased ? Int(deathYear ?? "") : Calendar.current.component(.year, from: Date())
            if let end = end, end >= by, end - by < 130 {
                c.append(.init(icon: "timelapse", text: "\(end - by)", label: L10n.t("العمر", "Age"), color: DS.Color.warning))
            }
        }
        if isDeceased, let dy = deathYear {
            c.append(.init(icon: "calendar.badge.exclamationmark", text: dy, label: L10n.t("الوفاة", "Death"), color: DS.Color.error))
        }
        if !isDeceased, !phone.isEmpty {
            c.append(.init(
                icon: "phone.fill",
                text: phoneHidden ? L10n.t("مخفي", "Hidden") : KuwaitPhone.display(phone),
                label: L10n.t("الهاتف", "Phone"),
                color: DS.Color.success, ltr: !phoneHidden
            ))
        }
        return c
    }

    /// دائرة معلومة صغيرة: أيقونة في دائرة ملوّنة + قيمة + تسمية.
    private func circleView(_ c: ChipData) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(c.color.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: c.icon)
                    .font(DS.Font.scaled(18, weight: .semibold))
                    .foregroundColor(c.color)
            }
            Text(c.text)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .environment(\.layoutDirection, c.ltr ? .leftToRight : LanguageManager.shared.layoutDirection)
            Text(c.label)
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 64)
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

    /// صف تفصيلي احترافي: أيقونة دائرية ملوّنة + تسمية + قيمة بمحاذاة النهاية.
    private func detailRow(icon: String, color: Color, label: String, value: String, ltrValue: Bool = false) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(DS.Font.scaled(15, weight: .semibold))
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
                .environment(\.layoutDirection, ltrValue ? .leftToRight : LanguageManager.shared.layoutDirection)
        }
        .padding(.vertical, DS.Spacing.sm + 2)
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

        // الرقم من الجلب المباشر (الإدارة تملكه محلياً أصلاً). السيرفر يعيد
        // nil للمخفيّ، فغيابه هنا يعني «مخفي» فعلاً لا نقصاً في البيانات.
        // العرض يُعيد nil للرقم المخفيّ، فغيابه هنا يعني «مخفي» فعلاً.
        if !isDeceased, let phone = m.phoneNumber, !phone.isEmpty {
            rows.append(.init(
                icon: "phone.fill",
                label: L10n.t("الهاتف", "Phone"),
                value: KuwaitPhone.display(phone),
                color: DS.Color.success
            ))
        } else if !isDeceased, m.isPhoneHidden == true, !isSelf, !canMod {
            rows.append(.init(
                icon: "phone.fill",
                label: L10n.t("الهاتف", "Phone"),
                value: L10n.t("مخفي", "Hidden"),
                color: DS.Color.textTertiary
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

                    // دائرتان قابلتان للضغط: «الأب» + «الأبناء (N)».
                    HStack(alignment: .top, spacing: DS.Spacing.xxxl) {
                        if let father = cachedFather {
                            Button { openMemberInTree(father.id) } label: {
                                familyCircle(
                                    member: father,
                                    label: L10n.t("الأب", "Father"),
                                    sub: father.firstName,
                                    count: nil,
                                    color: DS.Color.success
                                )
                            }
                            .buttonStyle(DSScaleButtonStyle())
                        }
                        if !cachedChildren.isEmpty {
                            Button { showChildrenSheet = true } label: {
                                familyCircle(
                                    member: nil,
                                    label: L10n.t("الأبناء", "Children"),
                                    sub: childrenCountText,
                                    count: cachedChildren.count,
                                    color: DS.Color.primary
                                )
                            }
                            .buttonStyle(DSScaleButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .padding(.horizontal, DS.Spacing.md)
                }
            }
            .sheet(isPresented: $showChildrenSheet) { childrenSheet }
        }
    }

    private func openMemberInTree(_ id: UUID) {
        // الشيت يبقى مفتوح — يتحدث محتواه + الشجرة تتزامن خلفه.
        currentMemberId = id
        NotificationCenter.default.post(
            name: .openMemberInTree, object: nil, userInfo: ["memberId": id]
        )
    }

    /// دائرة عائلة: صورة الأب أو عدد الأبناء + تسمية تحتها.
    private func familyCircle(member: FamilyMember?, label: String, sub: String, count: Int?, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 1.5))
                if let m = member {
                    if let urlStr = m.avatarUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Text(String(m.firstName.prefix(1)))
                                .font(DS.Font.title2).fontWeight(.bold).foregroundColor(color)
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    } else {
                        Text(String(m.firstName.prefix(1)))
                            .font(DS.Font.title2).fontWeight(.bold).foregroundColor(color)
                    }
                } else {
                    Text("\(count ?? 0)")
                        .font(DS.Font.title1)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                }
            }
            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            Text(sub)
                .font(DS.Font.footnote)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 92)
    }

    /// شيت قائمة الأبناء — شبكة صور تُفتح عند الضغط على دائرة «الأبناء».
    private var childrenSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 4),
                    spacing: DS.Spacing.md
                ) {
                    ForEach(cachedChildren) { child in
                        Button {
                            showChildrenSheet = false
                            openMemberInTree(child.id)
                        } label: {
                            childTileFirstName(child)
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("الأبناء", "Children") + " (\(cachedChildren.count))")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                                .font(DS.Font.scaled(11, weight: .bold))
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
                        trailing: "\(bioStations.count) " + L10n.t("حدث", "entries"),
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
            VStack(spacing: DS.Spacing.lg) {
                HStack(alignment: .top, spacing: DS.Spacing.xxl) {
                    if !isViewingSelf {
                        circleActionButton(
                            icon: "pencil.and.list.clipboard",
                            label: L10n.t("طلب تعديل", "Request Edit"),
                            tint: DS.Color.primary,
                            filled: true
                        ) { showEditActions = true }

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

                // اختيار نوع الطلب صار مربّعاً بمنتصف الشاشة (طلب المالك) —
                // يُعرض في fullScreenCover أدناه، لا داخل التفاصيل.
            }
        }
    }

    /// شبكة أنواع طلبات التعديل — مربّع بمنتصف الشاشة (طلب المالك).
    private var editActionsGrid: some View {
        VStack(spacing: DS.Spacing.md) {
            Text(L10n.t("اختر نوع الطلب", "Choose Request Type"))
                .font(DS.Font.plex(17, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.md), count: 3),
                spacing: DS.Spacing.lg
            ) {
                ForEach(availableEditActions, id: \.rawValue) { action in
                    editActionCircle(for: action)
                }
            }

            Button {
                showEditActions = false
            } label: {
                Text(L10n.t("إلغاء", "Cancel"))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.mutedBackground.opacity(0.8)))
            }
            .buttonStyle(DSScaleButtonStyle())
            .padding(.top, DS.Spacing.xs)
        }
    }

    private var availableEditActions: [TreeEditAction] {
        if member.isDeceased == true {
            return [.add, .editName, .editBirth, .addDeathDate, .addPhoto, .delete]
        }
        return [.add, .editName, .editPhone, .editBirth, .addPhoto, .deceased, .delete]
    }

    private func editActionColor(for action: TreeEditAction) -> Color {
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
        }
    }

    private func editActionLabel(for action: TreeEditAction) -> String {
        switch action {
        case .add: return L10n.t("إضافة ابن", "Add Son")
        case .editName: return L10n.t("تعديل اسم", "Edit Name")
        case .editPhone: return L10n.t("تعديل رقم", "Edit Phone")
        case .editBirth: return L10n.t("تعديل ميلاد", "Edit Birth")
        case .deceased: return L10n.t("تسجيل وفاة", "Deceased")
        case .addDeathDate: return L10n.t("تاريخ وفاة", "Death Date")
        case .addPhoto: return L10n.t("إضافة صورة", "Add Photo")
        case .delete: return L10n.t("حذف", "Delete")
        case .other: return L10n.t("طلب آخر", "Other")
        }
    }

    private func editActionCircle(for action: TreeEditAction) -> some View {
        let tint = editActionColor(for: action)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // نُغلق مربّع الاختيار أولاً ثم نفتح نموذج الطلب (عرضان متتاليان)
            showEditActions = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                pendingEditAction = action
            }
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .overlay(Circle().stroke(tint.opacity(0.28), lineWidth: 1))
                        .frame(width: 64, height: 64)
                    Image(systemName: action.iconName)
                        .font(DS.Font.scaled(24, weight: .semibold))
                        .foregroundColor(tint)
                }
                Text(editActionLabel(for: action))
                    .font(DS.Font.plex(12, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(editActionLabel(for: action))
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
                        .dsGlass(Circle())
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

/// ارتفاعات الشيت (0.46 / كامل) — تُطبَّق فقط عند العرض كشيت
private struct SheetDetents: ViewModifier {
    let enabled: Bool
    @Binding var detent: PresentationDetent

    func body(content: Content) -> some View {
        if enabled {
            content
                .presentationDetents([.fraction(0.46), .large], selection: $detent)
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
