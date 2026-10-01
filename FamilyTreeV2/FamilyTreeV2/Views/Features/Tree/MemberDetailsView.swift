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
    /// حظر العضو / إلغاء حظره (Guideline 1.2) — بجانب «إبلاغ»
    @State private var blockTarget: BlockTarget? = nil
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
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

    /// هل حظر المستخدم الحالي هذا العضو؟ (يخفي عنه أخباره وتعليقاته)
    private var isMemberBlocked: Bool {
        blockedStore.isBlocked(id: member.id, name: member.fullName)
    }

    /// «حظر» لغير صاحب الملف ولغير المتوفى (لا ينشر شيئاً) — ويبقى «إلغاء الحظر» متاحاً دائماً
    private var canShowBlock: Bool {
        !isViewingSelf && !member.isDeleted && (member.isDeceased != true || isMemberBlocked)
    }

    private func requestBlockToggle() {
        blockTarget = BlockTarget(id: member.id, name: member.fullName,
                                  otherNames: [member.displayFullName])
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

    @State private var heroIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ارتفاع شريط الأزرار السفلي (والرأس إن وُجد) — يدخل في ارتفاع المربّع المصغّر والموسّع
    @State private var panelFooterH: CGFloat = 0
    /// أُعلن عن وفاته؟ nil = لم يُتحقق بعد (لا يظهر زر «إعلان وفاة»)
    @State private var deathAnnounced: Bool? = nil
    @State private var panelHeaderH: CGFloat = 0
    /// رأس ملوّن مثل مربّعات الإضافة فوق الصورة (لا يتداخل معها) — خيار للمالك
    private static let showsHeaderBand = true   // قرار المالك: الشكل (ب) — رأس ملوّن مثل بقية المربّعات
    private var panelChromeH: CGFloat { centered ? panelHeaderH + panelFooterH : 0 }
    /// الشريط (والرأس إن وُجد) قيس — قبلها لا نُبلِّغ ارتفاعاً ناقصاً
    private var chromeReady: Bool {
        !centered || (panelFooterH > 0 && (!Self.showsHeaderBand || panelHeaderH > 0))
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
                    VStack(spacing: 0) {
                    if centered && Self.showsHeaderBand {
                        memberHeaderBand.readHeight($panelHeaderH)
                    }
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

                                    if !centered {
                                        actionButtonsSection
                                            .padding(.horizontal, DS.Spacing.lg)
                                    }
                                }
                                .padding(.top, DS.Spacing.lg)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.bottom, DS.Spacing.xxxl)
                        } else {
                        VStack(spacing: DS.Spacing.md) {
                            // الرأس: الصورة والاسم والقرابة وزر التفاصيل — ارتفاعه = المربّع المصغّر
                            VStack(spacing: DS.Spacing.md) {
                                // الرأس المتدرّج خلف الصورة أُزيل (لم يعجب المالك) — الشكل السابق مع حركة دخول
                                compactHeroSection
                                    .padding(.top, DS.Spacing.lg)

                                quickActionsRow
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .dsStaggerIn(1)

                                if centered {
                                    detailsToggleButton
                                        .dsStaggerIn(2)
                                }
                            }
                            .id("detailsTop")
                            .background(
                                GeometryReader { geo in
                                    // بعد قياس الشريط السفلي فقط (نفس سبب مربّعات الإضافة)
                                    Color.clear.preference(key: DSPanelCollapsedHeightKey.self,
                                                           value: chromeReady ? geo.size.height + DS.Spacing.lg + panelChromeH : 0)
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

                            Spacer(minLength: centered ? DS.Spacing.md : 60)
                        }
                        // المربّع بحجم محتواه (طلب المالك)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: SheetContentHeightKey.self,
                                                       value: chromeReady ? geo.size.height + panelChromeH : 0)
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
                    // شريط أزرار ثابت أسفل المربّع — مثل كل المربّعات: الإجراء كحلي يمين و«إغلاق» يسار
                    if centered {
                        panelFooter.readHeight($panelFooterH)
                    }
                    }
                }

                if !centered { floatingCloseButton }
            }
            .onAppear { recomputeCache() }
            .onChange(of: currentMemberId) { _ in recomputeCache() }
            .onChange(of: memberVM.membersVersion) { _ in recomputeCache() }
            .onChange(of: adminRequestVM.treeEditRequests.count) { _ in recomputeCache() }
            .task(id: member.isDeceased) { await refreshDeathAnnounced() }
            .onReceive(NotificationCenter.default.publisher(for: .deathAnnouncementPublished)) { note in
                if (note.object as? UUID) == member.id { deathAnnounced = true }
            }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            // تنسيق الألوان: أقسام التفاصيل بلون شريطها (كحلي، ورمادي للمتوفى) مثل باقي المربّعات
            .environment(\.dsBoxTint, member.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy)
            // ارتفاعات الشيت فقط في وضع الشيت — داخل المربّع تدفع الاختيار إلى «large»
            .modifier(SheetDetents(enabled: !centered, detent: $detent))
            // التعديل المباشر نموذج طويل — مربّع طويل من الأسفل (توصية أبل)
            .dsTallBox(isPresented: $showAdminControl) {
                if authVM.canEditMembers {
                    // ملاحظة: لا نضع .id(membersVersion) هنا — كان يُعيد بناء
                    // اللوح بالكامل عند كل upsertMemberLocally (مثلاً
                    // عند إضافة ابن)، فيُفقد scroll position ويرجع للأعلى.
                    // المحتوى يتحدث طبيعياً عبر @EnvironmentObject memberVM.
                    AdminMemberDetailSheet(member: member)
                }
            }
            .transaction { t in
                // بلا انزلاق من الأسفل — اللوح يظهر بنفسه في المنتصف
                if pendingEditAction != nil || showEditActions {
                    t.disablesAnimations = true
                }
            }
            // اختيار نوع الطلب — مربّع بمنتصف الشاشة (طلب المالك)
            .fullScreenCover(isPresented: $showEditActions) {
                DSCenterPanel(onBackgroundTap: { showEditActions = false }, hugsContent: true) {
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
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.",
                        "Thank you — your report reached the admins and will be reviewed within 24 hours."))
        }
        // حظر العضو / إلغاء الحظر — نفس رسائل «إبلاغ» (بلاغ تلقائي للإدارة عند الحظر)
        .dsBlockMemberFlow(target: $blockTarget)
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
            .accessibilityHidden(true)   // زخرفة — النص تحتها يشرح
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
                // مساحة ضغط ٤٤ نقطة (حد أبل) بلا تغيير الحبّة ولا ارتفاع المربّع المصغّر
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .padding(.vertical, -3)
        }
        .buttonStyle(DSScaleButtonStyle())
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
                        .scaleEffect(heroIn || reduceMotion ? 1 : 0.6)
                        .opacity(heroIn ? 1 : 0)
                        .onTapGesture { showAvatarPreview = true }
                        // القارئ الصوتي: الصورة تُفتح مكبّرة — زر باسم واضح
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.t("معاينة الصورة", "Preview photo"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { showAvatarPreview = true }

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
                            // القارئ الصوتي: علامة الوفاة تُقرأ كلمةً لا اسم رمز
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(L10n.t("متوفّى", "Deceased"))
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
                .offset(y: heroIn || reduceMotion ? 0 : 10)
                .opacity(heroIn ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.55, dampingFraction: 0.68).delay(0.05)) { heroIn = true }
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
                        .accessibilityHidden(true)   // زخرفة
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
                .accessibilityElement(children: .combine)   // الحبّة تُقرأ جملةً واحدة
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
                    .accessibilityHidden(true)   // زخرفة — النص يكفي
                Text(label)
                    .font(DS.Font.scaled(12, weight: .bold))
            }
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs + 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            // مساحة ضغط ٤٤ نقطة (حد أبل): الحشو يوسّع منطقة الضغط والسالب يعيد الحجم
            // كما كان — الحبّة وارتفاع المربّع المصغّر بلا تغيير
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.vertical, -8)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Father Cell (مسار لأعلى — الأب)

    /// خلية الأب القابلة للضغط — تنقل الشيت والشجرة للأب (مسار لأعلى في الشجرة).
    /// تظهر فقط عند وجود أب، وتحاكي خلايا الأم/الزوج في شيت النساء (relationCell).
    @ViewBuilder
    /// جسم التفاصيل: شبكة أيقونات (المعلومات + الأب + الأبناء) ← السيرة ← الطلبات ← الأزرار
    private var detailsBody: some View {
        // الأقسام تدخل تباعاً عند «عرض التفاصيل» (نفس حركة مربّعات الإضافة)
        let open = detent == .large
        return VStack(spacing: DS.Spacing.md) {
            infoGrid
                .dsStaggerWhen(0, active: open)

            familyStrip
                .dsStaggerWhen(1, active: open)

            bioCard
                .dsStaggerWhen(2, active: open)

            pendingRequestsCard
                .dsStaggerWhen(3, active: open)

            // داخل المربّع الأزرار في الشريط السفلي؛ في الصفحة تبقى هنا
            if !centered {
                actionButtonsSection
                    .padding(.top, DS.Spacing.sm)
                    .dsStaggerWhen(4, active: open)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: شريط العائلة — الأب والأبناء بشكل جديد (طلب المالك)

    /// الأب بصورته وحلقة ذهبية، ثم فاصل، ثم الأبناء بصور صغيرة تتمرّر أفقياً.
    /// الضغط على أي صورة يفتح صاحبها.
    @ViewBuilder
    private var familyStrip: some View {
        let father = cachedFather
        let children = cachedChildren
        if father != nil || !children.isEmpty {
            // نفس أقسام المربّعات — العنوان يفتح/يخفي الأب والأبناء (مخفيّون بالبداية)
            DSComposerSection(
                title: L10n.t("العائلة", "Family"),
                icon: "person.2.fill",
                tint: DS.Color.success,
                trailing: familySummary(hasFather: father != nil, children: children.count),
                isOpen: $familyOpen
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    // الأب بالمنتصف بخلفية خفيفة بعرض القسم (طلب المالك)
                    if let father {
                        Button { openMemberInTree(father.id) } label: {
                            familyBubble(father, size: 50, ring: DS.Color.warning,
                                         caption: L10n.t("الأب", "Father"))
                                .padding(.vertical, DS.Spacing.sm)
                                .frame(maxWidth: .infinity)
                                .dsRowBox()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        // القارئ الصوتي: «الأب، الاسم» بلا حرف الصورة البديلة
                        .accessibilityLabel(L10n.t("الأب، \(father.firstName)", "Father, \(father.firstName)"))
                    }

                    // الأبناء: صفوف من أربعة، كل صف متمركز (طلب المالك)
                    if !children.isEmpty {
                        VStack(spacing: DS.Spacing.sm) {
                            Text(L10n.t("الأبناء", "Children") + " · \(children.count)")
                                .font(DS.Font.plex(12, weight: .heavy))
                                .foregroundColor(DS.Color.fieldLabel)
                                .frame(maxWidth: .infinity)
                            VStack(spacing: 4) {
                                ForEach(Array(stride(from: 0, to: children.count, by: 4)), id: \.self) { start in
                                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                                        ForEach(children[start..<min(start + 4, children.count)]) { child in
                                            Button { openMemberInTree(child.id) } label: {
                                                familyBubble(child, size: 42, ring: DS.Color.primary.opacity(0.35),
                                                             caption: nil)
                                            }
                                            .buttonStyle(DSScaleButtonStyle())
                                            // القارئ الصوتي: الاسم (+ «متوفّى») بلا حرف الصورة البديلة
                                            .accessibilityLabel(child.firstName
                                                                + (child.isDeceased == true ? L10n.t("، متوفّى", ", deceased") : ""))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .dsRowBox()
                    }
                }
            }
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
            DSComposerSection(title: L10n.t("المعلومات", "Info"),
                              icon: "person.text.rectangle.fill",
                              tint: DS.Color.primary) {
                // صفّان في كل سطر (طلب المالك) — بنفس صفوف «تعديل البيانات»؛
                // صفوف عادية لا LazyVGrid حتى يُقاس الارتفاع كاملاً
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                        let end = min(start + 2, tiles.count)
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(tiles[start..<end]) { infoTileView($0) }
                            if end - start < 2 {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    /// صف معلومة: أيقونة الحقل + العنوان الغامق + القيمة — نفس صفوف المربّعات
    private func infoTileView(_ tile: InfoTileData) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: tile.icon, tint: tile.color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.label)
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(tile.value)
                    .font(DS.Font.plex(14))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .environment(\.layoutDirection, tile.ltr ? .leftToRight : LanguageManager.shared.layoutDirection)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «العنوان، القيمة» عنصراً واحداً
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
            // نفس قسم «السيرة الذاتية» في «تعديل البيانات»
            DSComposerSection(
                title: L10n.t("السيرة الذاتية", "Biography"),
                icon: "text.quote",
                tint: DS.Color.accent,
                trailing: "\(bioStations.count) " + L10n.t("حدث", "entries")
            ) {
                VStack(spacing: DS.Spacing.sm) {
                    VStack(spacing: 0) {
                        ForEach(Array(bioStations.enumerated()), id: \.element.id) { index, station in
                            bioStationRow(index: index, total: bioStations.count, station: station)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .dsRowBox()

                    if authVM.isAdmin || isViewingSelf {
                        Button {
                            showDeleteBioAlert = true
                        } label: {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .accessibilityHidden(true)   // زخرفة — النص يكفي
                                Text(L10n.t("حذف السيرة", "Delete Biography"))
                                    .font(DS.Font.plex(13, weight: .bold))
                            }
                            .foregroundColor(DS.Color.error)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(DS.Color.error.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            // مساحة ضغط ٤٤ نقطة (حد أبل) بلا تغيير ارتفاع الزر الظاهر
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .padding(.vertical, -2)
                        }
                        .buttonStyle(DSScaleButtonStyle())
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
        .accessibilityElement(children: .combine)   // الحدث (السنة، العنوان، التفاصيل) عنصراً واحداً
    }

    // MARK: - Pending Requests Card

    @ViewBuilder
    private var pendingRequestsCard: some View {
        if canSeePendingRequests && !cachedPendingRequests.isEmpty {
            DSComposerSection(
                title: L10n.t("طلبات معلّقة", "Pending Requests"),
                icon: "clock.badge.exclamationmark.fill",
                tint: DS.Color.warning,
                trailing: "\(cachedPendingRequests.count)"
            ) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(cachedPendingRequests.indices, id: \.self) { index in
                        pendingRequestRow(cachedPendingRequests[index])
                    }
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

        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(actionLabelAr, actionLabelEn))
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("قيد المراجعة", "Under review"))
                    .font(DS.Font.plex(12.5))
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
            Text(L10n.t("معلّق", "Pending"))
                .font(DS.Font.plex(11, weight: .bold))
                .foregroundColor(DS.Color.warning)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(DS.Color.warning.opacity(0.12), in: Capsule())
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)   // الطلب وحالته عنصراً واحداً
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

                        // حظر العضو بجانب «إبلاغ» (Guideline 1.2)
                        if canShowBlock {
                            circleActionButton(
                                icon: isMemberBlocked ? "hand.raised.slash.fill" : "hand.raised.fill",
                                label: isMemberBlocked ? L10n.t("إلغاء الحظر", "Unblock")
                                                       : L10n.t("حظر", "Block"),
                                tint: isMemberBlocked ? DS.Color.textSecondary : DS.Color.error
                            ) { requestBlockToggle() }
                        }
                    }

                    if authVM.canEditMembers {
                        circleActionButton(
                            icon: "pencil",
                            label: L10n.t("تعديل مباشر", "Direct Edit"),
                            tint: DS.Color.primary
                        ) { showAdminControl = true }
                    }

                    if showsDeathAnnounce {
                        circleActionButton(
                            icon: NewsTypeHelper.icon(for: "وفاة"),
                            label: L10n.t("إعلان وفاة", "Obituary"),
                            tint: NewsTypeHelper.color(for: "وفاة")
                        ) { openDeathAnnouncement() }
                    }
                }
                .frame(maxWidth: .infinity)

                // اختيار نوع الطلب صار مربّعاً بمنتصف الشاشة (طلب المالك) —
                // يُعرض في fullScreenCover أدناه، لا داخل التفاصيل.
            }
        }
    }

    /// اختيار نوع الطلب — نفس تصميم المربّعات: رأس ملوّن + قسم + «إلغاء» (طلب المالك)
    private var editActionsGrid: some View {
        DSComposer(
            title: L10n.t("طلب تعديل", "Edit Request"),
            subtitle: member.displayFullName,
            icon: "pencil.and.list.clipboard",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            canSubmit: false,
            note: L10n.t("يصل الطلب للإدارة لمراجعته", "The request goes to the admins for review"),
            onSubmit: {},
            onCancel: { showEditActions = false }
        ) {
            DSComposerSection(title: L10n.t("اختر نوع الطلب", "Choose Request Type"),
                              icon: "square.grid.2x2.fill",
                              tint: DS.Color.primary) {
                // صفوف عادية لا LazyVGrid — الشبكة الكسولة تُبلِّغ ارتفاعاً ناقصاً فيُقصّ آخر صف
                let actions = availableEditActions
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(stride(from: 0, to: actions.count, by: 3)), id: \.self) { start in
                        let end = min(start + 3, actions.count)
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(actions[start..<end], id: \.rawValue) { action in
                                editActionCircle(for: action)
                            }
                            ForEach(0..<(3 - (end - start)), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
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
            // مربّع نوع الطلب — مثل مربّعات التصنيف في «خبر جديد»
            VStack(spacing: 6) {
                Image(systemName: action.iconName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(tint.opacity(0.14)))
                Text(editActionLabel(for: action))
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .dsRowBox()
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
                .accessibilityHidden(true)   // زخرفة — التسمية تحتها تكفي
                Text(label)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - إعلان وفاة (مكان ثابت — طلب المالك «وين الوفاة؟»)

    /// يظهر للمتوفى الذي لم يُعلن عنه بعد، لمن يعتمد الوفيات (المالك والمدير والمراقب)
    private var showsDeathAnnounce: Bool {
        member.isDeceased == true && authVM.canApproveTreeRequests && deathAnnounced == false
            && DeathRecency.isRecent(member.deathDate)
    }

    private func refreshDeathAnnounced() async {
        guard member.isDeceased == true, authVM.canApproveTreeRequests else { return }
        let ids = await DeathAnnouncementPresenter.announcedIDs()
        deathAnnounced = ids.contains(member.id)
    }

    private func openDeathAnnouncement() {
        DeathAnnouncementPresenter.open(DeathAnnouncementTarget(
            id: member.id, name: member.fullName, isFemale: member.isFemale,
            deathDate: member.deathDate))
    }

    private var deathAnnounceButton: some View {
        let tint = NewsTypeHelper.color(for: "وفاة")
        return Button { openDeathAnnouncement() } label: {
            HStack(spacing: 7) {
                Image(systemName: NewsTypeHelper.icon(for: "وفاة"))
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(L10n.t("إعلان وفاة", "Death announcement"))
                    .font(DS.Font.plex(14.5, weight: .bold))
            }
            .foregroundColor(tint.dsReadableGlyph)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
    }

    // MARK: - Panel Footer (نفس شريط مربّعات الإضافة)

    private struct PanelAction {
        let title: String
        let icon: String
        let run: () -> Void
    }

    /// الإجراء الرئيسي: «تعديل مباشر» لمن يعدّل الأعضاء، وإلا «طلب تعديل» لغير صاحب الملف
    private var primaryPanelAction: PanelAction? {
        guard !member.isDeleted else { return nil }
        if authVM.canEditMembers {
            return PanelAction(title: L10n.t("تعديل مباشر", "Direct Edit"), icon: "pencil") {
                showAdminControl = true
            }
        }
        if !isViewingSelf {
            return PanelAction(title: L10n.t("طلب تعديل", "Request Edit"), icon: "pencil.and.list.clipboard") {
                showEditActions = true
            }
        }
        return nil
    }

    /// شريط ثابت أسفل المربّع: الإجراء كحلي يمين، «إبلاغ» صغير، «إغلاق» يسار
    private var panelFooter: some View {
        VStack(spacing: DS.Spacing.sm) {
            // إعلان وفاة — للمتوفى الذي لم يُعلن عنه، لمن يعتمد الوفيات
            if showsDeathAnnounce { deathAnnounceButton }
        HStack(spacing: DS.Spacing.sm) {
            if let primary = primaryPanelAction {
                Button(action: primary.run) {
                    HStack(spacing: 7) {
                        Image(systemName: primary.icon).font(.system(size: 14, weight: .bold))
                            .accessibilityHidden(true)   // زخرفة — النص يكفي
                        Text(primary.title).font(DS.Font.plex(15, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(DSActionFill.style(),
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                }
            }
            // إبلاغ عن العضو — متاح لغير صاحب الملف (سياسة Apple)
            if !isViewingSelf && !member.isDeleted {
                Button { showReportConfirm = true } label: {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                        .frame(width: 48, height: 48)
                        .background(DS.Color.warning.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                }
                .accessibilityLabel(L10n.t("إبلاغ", "Report"))
            }
            // حظر العضو بجانب «إبلاغ» (Guideline 1.2) — ولإلغاء الحظر إن كان محظوراً
            if canShowBlock {
                Button { requestBlockToggle() } label: {
                    Image(systemName: isMemberBlocked ? "hand.raised.slash.fill" : "hand.raised.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isMemberBlocked ? DS.Color.textSecondary : DS.Color.error)
                        .frame(width: 48, height: 48)
                        .background((isMemberBlocked ? DS.Color.textSecondary : DS.Color.error).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                }
                .accessibilityLabel(isMemberBlocked ? L10n.t("إلغاء حظر العضو", "Unblock member")
                                                    : L10n.t("حظر العضو", "Block member"))
            }
            PanelCloseButton()
        }
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.md)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(0.12)).frame(height: 1)
                }
        )
    }

    /// رأس ملوّن مثل مربّعات الإضافة (فوق الصورة، بلا تداخل) — يظهر فقط مع showsHeaderBand
    private var memberHeaderBand: some View {
        DSComposerHeader(
            title: L10n.t("تفاصيل العضو", "Member Details"),
            subtitle: L10n.t("من شجرة العائلة", "From the family tree"),
            icon: "person.text.rectangle.fill",
            tint: member.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy
        )
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
                        // مساحة ضغط ٤٤ نقطة (حد أبل) — الدائرة ومكانها كما هما
                        .padding(3)
                        .contentShape(Rectangle())
                        .padding(-3)
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

/// «إغلاق» في شريط المربّع السفلي (يسار، مثل «إلغاء» بقية المربّعات) — عرض مستقل
/// حتى يقرأ إغلاق المربّع المتحرّك من داخله (قراءته من MemberDetailsView كانت فارغة)
private struct PanelCloseButton: View {
    @Environment(\.dsPanelClose) private var panelClose
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let panelClose { panelClose() } else { dismiss() }
        } label: {
            Text(L10n.t("إغلاق", "Close"))
                .font(DS.Font.plex(15, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.mutedBackground.opacity(0.8)))
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}
