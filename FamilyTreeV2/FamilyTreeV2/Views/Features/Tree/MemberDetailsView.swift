import SwiftUI
import PhotosUI

struct MemberDetailsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) var dismiss
    // لون القسم الذي فُتحت منه التفاصيل (الشجرة، الرئيسية، الإدارة، حسابي) — كحلي «الإطار» يتبعه،
    // وكذلك صورة العضو الافتراضية وفقاعات الأب والأبناء (طلب المالك ٢٠٢٦-١٠-٠٥: «تتلوّن بلون القسم»)؛
    // ألوان المعاني (تنبيه، خطأ، متوفّى) كما هي
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
    private var chromeGradient: LinearGradient { section?.gradient ?? DS.Color.gradientPrimary }

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
    /// «طلب إضافة» (ابن، ابنة، زوجة) — مربّع اختيار بمنتصف الشاشة مثل «طلب تعديل»
    @State private var showAddActions = false
    @State private var pendingEditAction: TreeEditAction? = nil
    /// من يُطلب إضافته مع «إضافة» (`pendingEditAction == .add`)
    @State private var pendingAddKind: TreeAddKind = .son
    @State private var showReportConfirm = false
    @State private var reportReason = ""
    @State private var reportSent = false
    /// حظر العضو / إلغاء حظره (Guideline 1.2) — بجانب «إبلاغ»
    @State private var blockTarget: BlockTarget? = nil
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        // جلسات الاستخدام: «صفحة العضو» ما دامت ظاهرة
        panel.appUsageScreen(.memberDetails)
    }

    @ViewBuilder
    private var panel: some View {
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
                        memberHeaderBand
                            // السحب لأسفل على الرأس يصغّر المربّع الموسّع
                            .dsDetailsSwipe(collapses: detent == .large) { _ in setDetailsOpen(false) }
                            .readHeight($panelHeaderH)
                    }
                    ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        if isLandscape {
                            // الوضع الأفقي: المربّع الأطول (حتى ارتفاع الشاشة) بكل التفاصيل على عمودين —
                            // الصورة والاسم والإجراءات يميناً، والمعلومات والعائلة والسيرة يساراً، ويتمرّر
                            HStack(alignment: .top, spacing: DS.Landscape.columnSpacing) {
                                VStack(spacing: DS.Spacing.md) {
                                    compactHeroSection
                                        .padding(.top, DS.Spacing.lg)

                                    quickActionsRow
                                        .padding(.horizontal, DS.Spacing.lg)

                                    // «تعديل مباشر» (أو «طلب إضافة») داخل التفاصيل نفسها — «طلب تعديل» في الشريط السفلي
                                    roleActionButton
                                        .padding(.horizontal, DS.Spacing.lg)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(spacing: DS.Spacing.md) {
                                    infoGrid

                                    familyStrip

                                    bioCard

                                    pendingRequestsCard

                                    if !centered {
                                        actionButtonsSection
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.top, DS.Spacing.lg)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.bottom, centered ? DS.Spacing.md : DS.Spacing.xxxl)
                            // المربّع على قدر المحتوى كله (مصغّراً وموسّعاً — لا زرّ «عرض التفاصيل» أفقياً)
                            .background(
                                GeometryReader { geo in
                                    let h = chromeReady ? geo.size.height + panelChromeH : 0
                                    Color.clear
                                        .preference(key: SheetContentHeightKey.self, value: h)
                                        .preference(key: DSPanelCollapsedHeightKey.self, value: h)
                                }
                            )
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

                                // الإجراء («تعديل مباشر» / «طلب تعديل») بجانب «عرض التفاصيل» — داخل التفاصيل
                                // نفسها، ظاهر مصغّراً وموسّعاً (طلب المالك ٢٠٢٦-١٠-٢٤؛ كان في الشريط السفلي وحده)
                                headerButtons
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .dsStaggerIn(2)
                            }
                            .id("detailsTop")
                            .background(
                                GeometryReader { geo in
                                    // بعد قياس الشريط السفلي فقط (نفس سبب مربّعات الإضافة)
                                    Color.clear.preference(key: DSPanelCollapsedHeightKey.self,
                                                           value: chromeReady ? geo.size.height + DS.Spacing.lg + panelChromeH : 0)
                                }
                            )
                            // السحب لأعلى يوسّع المربّع (مع زرّ «عرض التفاصيل» لا بدله — طلب المالك ٢٠٢٦-١٠-٢٤)
                            .dsDetailsSwipe(expands: centered && detent != .large) { _ in setDetailsOpen(true) }

                            if centered {
                                // التفاصيل تبقى في مكانها ويُقصّ المربّع فوقها عند الإخفاء —
                                // فلا تختفي فجأة (طلب المالك): يتحرّك الارتفاع وحده
                                detailsBody
                                    .opacity(detent == .large ? 1 : 0)
                                    .allowsHitTesting(detent == .large)
                            } else if detent == .large {
                                detailsBody
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
                    // أفقياً كل التفاصيل ظاهرة فتتمرّر دائماً؛ العمودي كما هو
                    .scrollDisabled(centered && detent != .large && !isLandscape)
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
                if pendingEditAction != nil || showEditActions || showAddActions {
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
            // «طلب إضافة» — نفس المربّع: ابن، ابنة، زوجة
            .fullScreenCover(isPresented: $showAddActions) {
                DSCenterPanel(onBackgroundTap: { showAddActions = false }, hugsContent: true) {
                    addActionsGrid
                }
                .background(ClearPresentationBackground())
            }
            // «طلب تعديل» كذلك لوح بمنتصف الشاشة (طلب المالك)
            .fullScreenCover(item: $pendingEditAction) { action in
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    TreeEditRequestView(member: member, action: action,
                                        addKind: action == .add ? pendingAddKind : .son)
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
        // الحالة الفارغة الواحدة: المجسّم + العنوان + سطر
        DSEmptyView(L10n.t("هذا العضو حذف حسابه", "This member deleted their account"),
                    message: L10n.t("البيانات غير متوفرة", "Data unavailable"),
                    icon: "person.slash.fill", tint: DS.Color.textTertiary)
    }

    // MARK: - Hero Section (Compact circular)

    /// «عرض التفاصيل» / «إخفاء التفاصيل» — الزرّ نفسه في الشجرتين (`DSDetailsToggle`، طلب المالك ٢٠٢٦-١٠-٢٤
    /// «شنو سويت عرض التفاصيل؟»): زرّ واضح بسهم يدور مع التوسيع — والسحب لأعلى/لأسفل يفعل الشيء نفسه
    private var detailsToggleButton: some View {
        DSDetailsToggle(isExpanded: detent == .large) { setDetailsOpen(detent != .large) }
    }

    /// التوسيع والتصغير بنابض ارتفاع المربّع نفسه — «تقليل الحركة»: مباشرة
    private func setDetailsOpen(_ open: Bool) {
        guard open != (detent == .large) else { return }
        withAnimation(reduceMotion ? nil : DS.Anim.smooth) { detent = open ? .large : .fraction(0.46) }
    }

    private var compactHeroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                // (أُزيل التوهّج المموّه خلف الصورة — كان يُقصّ بإطار مربّع، طلب المالك)
                ZStack {
                    avatarContent
                        .frame(width: DS.Icon.memberHero, height: DS.Icon.memberHero)
                        .clipShape(Circle())
                        // المتوفّى بالأبيض والأسود (طلب المالك)
                        .grayscale(member.isDeceased == true ? 1 : 0)
                        // إطار دائري خفيف جداً بلا توهّج (طلب المالك) — حلقة «مجسّمات» بلون القسم
                        .modifier(MemberTrialRing(side: DS.Icon.memberHero))
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
                            .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                            .overlay(
                                Image(systemName: "heart.slash.fill")
                                    .dsGlyph(DS.Glyph.xlCompact)
                                    .foregroundColor(DS.Color.textTertiary)
                            )
                            // إطار خفيف لعلامة الوفاة (طلب المالك)
                            .overlay(Circle().stroke(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                            .offset(x: 48, y: 48)
                            // القارئ الصوتي: علامة الوفاة تُقرأ كلمةً لا اسم رمز
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(L10n.t("متوفّى", "Deceased"))
                    }
                }
            }

            Text(member.displayFullName)
                .dsFont(.title)
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
                // شريحة العُدّة (٣٤، ومساحة ضغط ٤٤ داخلها) — نفسها في تفاصيل النساء
                DSChipButton(L10n.t("صلة القرابة", "Kinship"),
                             icon: "point.3.connected.trianglepath.dotted",
                             tint: DS.Color.palm,   // الهوية: القرابة أخضر العائلة (لا لون حالة)
                             size: .small, action: showKinshipPath)
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
                // حبّة ساكنة بمقاس شريحة العُدّة وشكلها (جنب شريحة «صلة القرابة»)
                HStack(spacing: DS.Spacing.xsm) {
                    Image(systemName: isDeceased ? "heart.slash.fill" : "timelapse")
                        .dsGlyph(DS.Glyph.sm)
                        .accessibilityHidden(true)   // زخرفة
                    Text("\(age) " + L10n.t("سنة", "yrs"))
                        .dsFont(.chip)
                    if isDeceased {
                        Text(L10n.t("· متوفّى", "· deceased"))
                            .dsFont(.caption)
                    }
                }
                .lineLimit(1)
                .foregroundColor(color)
                .padding(.horizontal, DSBox.chipPadding)
                .frame(minHeight: DSBox.chipHeight)
                .background(Capsule().fill(color.opacity(DS.Opacity.tintFill)))
                .overlay(Capsule().strokeBorder(color.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                .accessibilityElement(children: .combine)   // الحبّة تُقرأ جملةً واحدة
            }
        }
    }

    private func year(from s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
              let r = s.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return String(s[r])
    }

    // MARK: - التفاصيل

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

    /// عدد الأبناء في السطر الواحد تحت الأب
    private static let childrenPerRow = 3

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
                tint: DS.Color.palm,   // الهوية: العائلة أخضر العائلة (لا لون حالة)
                trailing: familySummary(hasFather: father != nil, children: children.count),
                isOpen: $familyOpen
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    // الأب بالمنتصف بخلفية خفيفة بعرض القسم (طلب المالك)
                    if let father {
                        Button { openMemberInTree(father.id) } label: {
                            familyBubble(father, size: 50, caption: L10n.t("الأب", "Father"))
                                .padding(.vertical, DS.Spacing.sm)
                                .frame(maxWidth: .infinity)
                                .dsRowBox()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        // القارئ الصوتي: «الأب، الاسم» بلا حرف الصورة البديلة
                        .accessibilityLabel(L10n.t("الأب، \(father.firstName)", "Father, \(father.firstName)"))
                    }

                    // الأبناء: كل ٣ أبناء في سطر تحت الأب، كل سطر متمركز — ٧ أبناء = ٣ أسطر (٣+٣+١)
                    // (طلب المالك ٢٠٢٦-١٠-٠٧؛ كانت صفوفاً من أربعة)
                    if !children.isEmpty {
                        VStack(spacing: DS.Spacing.sm) {
                            Text(L10n.t("الأبناء", "Children") + " · \(children.count)")
                                .dsFont(.familyLabel)   // ١١ ثقيل كما كان
                                .foregroundColor(DS.Color.fieldLabel)
                                .frame(maxWidth: .infinity)
                            VStack(spacing: DS.Spacing.xs) {
                                ForEach(Array(stride(from: 0, to: children.count, by: Self.childrenPerRow)), id: \.self) { start in
                                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                                        ForEach(children[start..<min(start + Self.childrenPerRow, children.count)]) { child in
                                            Button { openMemberInTree(child.id) } label: {
                                                familyBubble(child, size: 42, caption: nil)
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

    /// صورة دائرية بحلقة + الاسم الأول تحتها (+ وصف فوق الاسم للأب) — بلون القسم
    private func familyBubble(_ m: FamilyMember, size: CGFloat, caption: String?) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                if let url = m.avatarUrl, let imgUrl = URL(string: url) {
                    CachedAsyncImage(url: imgUrl) { img in img.resizable().scaledToFill() }
                    placeholder: { Circle().fill(chromeInk.opacity(DS.Opacity.tintFill)) }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(chromeInk.opacity(DS.Opacity.tintFill))
                        .frame(width: size, height: size)
                        .overlay(
                            Text(String(m.firstName.prefix(1)))
                                .font(DS.Font.plex(size * 0.36, weight: .bold))
                                .foregroundColor(chromeInk)
                        )
                }
            }
            // حلقة «مجسّمات» — «الحالي» الحلقة القديمة بلون القسم
            .modifier(MemberTrialRing(side: size, inset: -DS.Spacing.xxs))
            // المتوفّى بالأبيض والأسود (طلب المالك)
            .grayscale(m.isDeceased == true ? 1 : 0)

            // خط العائلة كما كان قبل التوحيد (طلب المالك ٢٠٢٦-١٠-٠٧ «الخط صغير أبيه نفس السابق»):
            // «الأب» ١٠٫٥ عريض، والاسم ١١٫٥ عريض
            if let caption {
                Text(caption)
                    .dsFont(.badgeCompact)
                    .foregroundColor(chromeInk)
            }
            Text(m.firstName)
                .dsFont(.chipCompact)
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
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(tile.label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(tile.value)
                    .dsFieldFont(.body)
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

    // MARK: - Basic Info

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
        if let phone = m.dsVisiblePhone(viewerId: authVM.currentUser?.id, viewerCanModerate: canMod) {
            rows.append(.init(
                icon: "phone.fill",
                label: L10n.t("الهاتف", "Phone"),
                value: KuwaitPhone.display(phone),
                color: DS.Color.sea
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

    private func openMemberInTree(_ id: UUID) {
        // الشيت يبقى مفتوح — يتحدث محتواه + الشجرة تتزامن خلفه.
        currentMemberId = id
        NotificationCenter.default.post(
            name: .openMemberInTree, object: nil, userInfo: ["memberId": id]
        )
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
                        // الزرّ الواحد (٤٤) بدور الحذف — أحمر
                        DSButton(L10n.t("حذف السيرة", "Delete Biography"), icon: "trash", role: .destructive) {
                            showDeleteBioAlert = true
                        }
                    }
                }
            }
        }
    }

    private func bioStationRow(index: Int, total: Int, station: FamilyMember.BioStation) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            VStack(spacing: 0) {
                // نقطة الخط الزمني على قرص خفيف بلون القسم (مقاس عنوان القسم)
                ZStack {
                    Circle()
                        .fill(chromeInk.opacity(DS.Opacity.tintFill))
                        .frame(width: DS.Icon.section, height: DS.Icon.section)
                    Circle()
                        .fill(chromeGradient)
                        .frame(width: DS.Spacing.sm, height: DS.Spacing.sm)
                }

                if index < total - 1 {
                    Rectangle()
                        .fill(chromeInk.opacity(DS.Opacity.tintFillStrong))
                        .frame(width: DS.Spacing.xxs)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: DS.Icon.section)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if let year = station.year, !year.isEmpty {
                    DSStatusChip(text: year, tint: chromeInk, size: .mini)
                }
                Text(station.title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                if !station.details.isEmpty {
                    Text(station.details)
                        .dsFieldFont(.subtitle)
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
            case .add: return DS.Color.palm
            case .editName: return DS.Color.info
            case .editPhone: return chromeInk
            case .editBirth: return DS.Color.palm
            case .deceased: return DS.Color.textTertiary
            case .addDeathDate: return DS.Color.textTertiary
            case .addPhoto: return chromeInk
            case .delete: return DS.Color.error
            case .other: return DS.Color.accent
            case .none: return DS.Color.warning
            }
        }()

        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t(actionLabelAr, actionLabelEn))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("قيد المراجعة", "Under review"))
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
            DSStatusChip(text: L10n.t("معلّق", "Pending"), tint: DS.Color.warning, size: .mini)
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
                    // «تعديل مباشر» / «طلب إضافة» صارا زرّ الدور تحت الاسم (`roleActionButton`)؛ و«طلب تعديل»
                    // هنا لعرض الشيت وحده (المربّع بالمنتصف يضعه في شريطه السفلي) — لا يضيع من أي عرض
                    if !isViewingSelf {
                        circleActionButton(
                            icon: "pencil.and.list.clipboard",
                            label: L10n.t("طلب تعديل", "Request Edit"),
                            tint: chromeInk,
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

                    if showsDeathAnnounce {
                        circleActionButton(
                            icon: NewsTypeHelper.icon(for: "وفاة"),
                            label: L10n.t("إعلان وفاة", "Obituary"),
                            tint: chromeInk
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
                // نفس مربّعات مربّع الإجراءات في شجرة النساء: مقاس واحد، أسطر متوازنة بلا يتيم (٦ = ٣+٣، ٥ = ٣+٢)
                DSActionTileGrid {
                    ForEach(availableEditActions, id: \.rawValue) { action in
                        DSActionTile(editActionLabel(for: action), icon: action.iconName,
                                     tint: action == .delete ? DS.Color.error : chromeInk) { pick(action) }
                    }
                }
            }
        }
    }

    /// التعديلات — والإضافة صارت زرّها «طلب إضافة» تحت الاسم (طلب المالك ٢٠٢٦-١٠-٢٤ «اذا يبي يسوي طلبات اضافة؟»)
    private var availableEditActions: [TreeEditAction] {
        if member.isDeceased == true {
            return [.editName, .editBirth, .addDeathDate, .addPhoto, .delete]
        }
        return [.editName, .editPhone, .editBirth, .addPhoto, .deceased, .delete]
    }

    /// «طلب إضافة» — ابن (يُضاف تلقائياً عند القبول)، أو ابنة أو زوجة (تُضيفها الإدارة في شجرة النساء)؛
    /// كلها طلب «تعديل الشجرة» نفسه (`submitTreeEditRequest`) الذي يقبله السيرفر لأي عضو مفعّل
    private var addActionsGrid: some View {
        DSComposer(
            title: L10n.t("طلب إضافة", "Request an addition"),
            subtitle: member.displayFullName,
            icon: "person.badge.plus",
            tint: DS.Color.composerProject,
            actionTitle: "",
            showsAction: false,
            canSubmit: false,
            note: L10n.t("يصل الطلب للإدارة لمراجعته", "The request goes to the admins for review"),
            onSubmit: {},
            onCancel: { showAddActions = false }
        ) {
            DSComposerSection(title: L10n.t("من تريد إضافته؟", "Who are you adding?"),
                              icon: "plus.circle.fill", tint: DSMemberKit.addTint) {
                DSActionTileGrid {
                    ForEach(TreeAddKind.allCases) { kind in
                        DSActionTile(kind.tileTitle, icon: kind.icon, tint: DSMemberKit.addTint) {
                            pick(.add, kind: kind, closing: { showAddActions = false })
                        }
                    }
                }
            }
            .environment(\.dsBoxTint, nil)
        }
    }

    /// نُغلق مربّع الاختيار أولاً ثم نفتح نموذج الطلب (عرضان متتاليان)
    private func pick(_ action: TreeEditAction, kind: TreeAddKind = .son, closing: (() -> Void)? = nil) {
        pendingAddKind = kind
        if let closing { closing() } else { showEditActions = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pendingEditAction = action
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
                // القرص المجسّم الواحد (`DSStateIcon`) بلون الإجراء
                DSStateIcon(icon, tint: tint, size: DS.Icon.sizeLg, mapsChrome: !filled)
                    .accessibilityHidden(true)   // زخرفة — التسمية تحتها تكفي
                Text(label)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
        .buttonStyle(DSPressStyle())
    }

    // MARK: - إعلان وفاة (مكان ثابت — طلب المالك «وين الوفاة؟»)

    /// يظهر للمتوفى الذي لم يُعلن عنه بعد، للمالك والمدير (نشر المحتوى والإشعارات — السيرفر يفرضه)
    private var showsDeathAnnounce: Bool {
        member.isDeceased == true && authVM.isAdmin && deathAnnounced == false
            && DeathRecency.isRecent(member.deathDate)
    }

    private func refreshDeathAnnounced() async {
        guard member.isDeceased == true, authVM.isAdmin else { return }
        let ids = await DeathAnnouncementPresenter.announcedIDs()
        deathAnnounced = ids.contains(member.id)
    }

    private func openDeathAnnouncement() {
        DeathAnnouncementPresenter.open(DeathAnnouncementTarget(
            id: member.id, name: member.fullName, isFemale: member.isFemale,
            deathDate: member.deathDate))
    }

    private var deathAnnounceButton: some View {
        // زرّ إضافي = الزرّ الواحد بدور الثانوي (رمادي) — الإجراء الرئيسي تحته بلون القسم
        DSButton(L10n.t("إعلان وفاة", "Death announcement"), icon: NewsTypeHelper.icon(for: "وفاة"),
                 role: .cancel) {
            openDeathAnnouncement()
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

    /// «طلب تعديل» لغير صاحب الملف — في الشريط السفلي بجانب «إغلاق» كما كان (طلب المالك ٢٠٢٦-١٠-٢٤)،
    /// للأعضاء والإدارة
    private var showsRequestEdit: Bool { !isViewingSelf && !member.isDeleted }

    /// «طلب إضافة» لغير الإدارة على غيره — ابن أو ابنة أو زوجة (كان «إضافة ابن» مخفياً داخل «طلب تعديل»)
    private var showsRequestAdd: Bool { !isViewingSelf && !member.isDeleted && !authVM.canEditMembers }

    /// زرّ الدور تحت الاسم — بمقاس «طلب تعديل» و«إغلاق» نفسه ولون دوره (`DSMemberKit`، طلب المالك ٢٠٢٦-١٠-٢٤
    /// «احجم الازرار نبي وحدها»): «تعديل مباشر» ذهبي للمالك والمدير والمراقب (`canEditMembers`) والقلم يكتب،
    /// و«طلب إضافة» أخضر العائلة لغيرهم ورمزه يقفز
    @ViewBuilder private var roleActionButton: some View {
        if authVM.canEditMembers && !member.isDeleted {
            DSLiveButton(L10n.t("تعديل مباشر", "Direct Edit"), icon: "pencil",
                         tint: DSMemberKit.directTint, motion: .write,
                         hint: L10n.t("يفتح إدارة السجل", "Opens the member record"), size: .compact) {
                showAdminControl = true
            }
        } else if showsRequestAdd {
            DSLiveButton(L10n.t("طلب إضافة", "Request addition"), icon: "person.badge.plus",
                         tint: DSMemberKit.addTint, motion: .pop,
                         hint: L10n.t("ابن أو ابنة أو زوجة — يصل الطلب للإدارة",
                                      "A son, daughter or wife — the request goes to the admins"), size: .compact) {
                showAddActions = true
            }
        }
    }

    /// صفّ الرأس: زرّ الدور + «عرض التفاصيل» بعرضين متساويين — فوق بعض من «حجم النص» ٢× وأكبر (لا يُقصّ النص)
    private var headerButtons: some View {
        let layout = dynamicTypeSize >= .xxLarge ? AnyLayout(VStackLayout(spacing: DSBox.buttonSpacing))
                                                 : AnyLayout(HStackLayout(spacing: DSBox.buttonSpacing))
        return layout {
            roleActionButton
            detailsToggleButton
        }
    }

    /// «طلب تعديل» في الشريط السفلي
    @ViewBuilder private var requestEditButton: some View {
        if showsRequestEdit {
            DSButton(L10n.t("طلب تعديل", "Request Edit"), icon: "pencil.and.list.clipboard") {
                showEditActions = true
            }
        }
    }

    /// شريط ثابت أسفل المربّع: «إبلاغ» و«حظر» صغيران، «إغلاق» — زرّ التعديل صار داخل التفاصيل (`headerButtons`)
    private var panelFooter: some View {
        VStack(spacing: DS.Spacing.sm) {
            // إعلان وفاة — للمتوفى الذي لم يُعلن عنه، لمن يعتمد الوفيات
            if showsDeathAnnounce { deathAnnounceButton }
            // صفّ الأزرار بمواصفة `DSBox` الواحدة («طلب تعديل» بلون القسم، «إغلاق» رمادي، الأيقونات مربّعة بنفس
            // الارتفاع) — من «حجم النص» ٢× وأكبر «طلب تعديل» سطر كامل وحده فوقها (لا يُقصّ)
            if dynamicTypeSize >= .xxLarge {
                VStack(spacing: DSBox.buttonSpacing) {
                    requestEditButton
                    HStack(spacing: DSBox.buttonSpacing) { panelSecondaryButtons }
                }
            } else {
                HStack(spacing: DSBox.buttonSpacing) {
                    requestEditButton
                    panelSecondaryButtons
                }
            }
        }
        // نفس شريط أزرار مربّعات العمل (`DSComposer`): هوامشه وخطّه الشعري من `DSBox`
        .padding(.horizontal, DSBox.footerHorizontal)
        .padding(.top, DSBox.footerTop)
        .padding(.bottom, DSBox.footerBottom)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke)).frame(height: DS.Border.width)
                }
        )
    }

    /// إبلاغ، حظر، إغلاق
    @ViewBuilder private var panelSecondaryButtons: some View {
            // إبلاغ عن العضو — متاح لغير صاحب الملف (سياسة Apple)
            if !isViewingSelf && !member.isDeleted {
                Button { showReportConfirm = true } label: {
                    squareIcon("exclamationmark.bubble.fill", tint: DS.Color.warning)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("إبلاغ", "Report"))
            }
            // حظر العضو بجانب «إبلاغ» (Guideline 1.2) — ولإلغاء الحظر إن كان محظوراً
            if canShowBlock {
                Button { requestBlockToggle() } label: {
                    squareIcon(isMemberBlocked ? "hand.raised.slash.fill" : "hand.raised.fill",
                               tint: isMemberBlocked ? DS.Color.textSecondary : DS.Color.error)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(isMemberBlocked ? L10n.t("إلغاء حظر العضو", "Unblock member")
                                                    : L10n.t("حظر العضو", "Block member"))
            }
            PanelCloseButton()
    }

    /// زرّ أيقونة مربّع بارتفاع الزرّ الواحد (إبلاغ، حظر) بلون معناه الخفيف
    private func squareIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .dsGlyph(DS.Glyph.lg)
            .foregroundColor(tint)
            .frame(width: DSBox.buttonHeight, height: DSBox.buttonHeight)
            .background(tint.opacity(DS.Opacity.tintFill), in: DSBox.buttonShape)
    }

    /// رأس ملوّن مثل مربّعات الإضافة (فوق الصورة، بلا تداخل) — يظهر فقط مع showsHeaderBand
    private var memberHeaderBand: some View {
        DSComposerHeader(
            title: L10n.t("تفاصيل العضو", "Member Details"),
            subtitle: L10n.t("من شجرة العائلة", "From the family tree"),
            icon: "person.text.rectangle.fill",
            tint: member.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy
        )
        // علم دولة الرقم (غير الكويت) في زاوية الرأس — طلب المالك ٢٠٢٦-١٠-٢٤ «علم السعودية للرقم السعودي»؛
        // بقاعدة صفّ «الهاتف» نفسها: لا علم إن لم يحقّ للمشاهد رؤية الرقم
        .overlay(alignment: .trailing) {
            DSPhoneCountryBadge(phone: member.dsVisiblePhone(viewerId: authVM.currentUser?.id,
                                                             viewerCanModerate: authVM.canModerate))
                .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Floating Close Button

    private var floatingCloseButton: some View {
        VStack {
            HStack {
                Spacer()
                // زر الإغلاق الموحّد فوق السطح (DSNavButtons)
                DSCloseButton { dismiss() }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            Spacer()
        }
    }

    // MARK: - Kinship Path

    private func showKinshipPath() {
        guard let currentUser = authVM.currentUser else { return }
        let result = KinshipCalculator.calculate(from: currentUser, to: member, lookup: memberVM._memberById)

        var pathIds = result.pathA.map(\.id) + result.pathB.map(\.id)
        if let ancestor = result.commonAncestor {
            pathIds.append(ancestor.id)
        }

        dismiss()

        // الطلب المركزي: تاب الشجرة ← شجرة العائلة ← المسار — يعمل من الرئيسية والإشعارات أيضاً
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(
                name: .requestKinshipPath,
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
                    // أثناء تحميل الصورة: الصورة الافتراضية نفسها (بلا دوّارة)
                    defaultAvatar
                }
            } else {
                defaultAvatar
            }
        }
    }

    /// الصورة الافتراضية بلون القسم (طلب المالك ٢٠٢٦-١٠-٠٥): أرضية خفيفة + قرص العضو المجسّم
    private var defaultAvatar: some View {
        LinearGradient(
            colors: [chromeInk.opacity(DS.Opacity.tintFillStrong), DS.Color.accent.opacity(DS.Opacity.tintFill)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.58
                DSStateIcon("person.fill", tint: chromeInk, size: side, mapsChrome: false)
                    .frame(width: g.size.width, height: g.size.height)
            }
            .accessibilityHidden(true)
        )
    }

    private var avatarPreviewOverlay: some View {
        ZStack(alignment: .topTrailing) {
            DS.Color.overlayDark.opacity(DS.Opacity.mediaDim).ignoresSafeArea()

            GeometryReader { _ in
                avatarContent
                    .frame(width: DS.Icon.avatarPreview, height: DS.Icon.avatarPreview)
                    .background(chromeInk.opacity(DS.Opacity.tintFill))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(chromeGradient, lineWidth: 4))
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

            // زر الإغلاق الموحّد فوق عارض الصورة (DSNavButtons)
            DSCloseButton(context: .onMedia) {
                avatarPreviewScale = 1
                lastAvatarPreviewScale = 1
                showAvatarPreview = false
            }
            .padding(DS.Spacing.lg)
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
        // «إغلاق» = زرّ الإلغاء في مواصفة `DSBox` الواحدة
        Button(L10n.t("إغلاق", "Close")) {
            if let panelClose { panelClose() } else { dismiss() }
        }
        .buttonStyle(DSBoxButtonStyle(role: .cancel))
    }
}

// MARK: - حلقة الصور الدائرية (الصورة، الأب، الأبناء) بأسلوب «مجسّمات»

/// طين ناعم: حافة متدرجة بلون القسم وظلّ لطيف تحتها — شفافياتها من لمسة الطين الواحدة (`DS.Card`)
private struct MemberTrialRing: ViewModifier {
    let side: CGFloat
    /// سالب = الحلقة خارج الصورة (فقاعات العائلة)
    var inset: CGFloat = 0
    @Environment(\.dsSection) private var section
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let s = section ?? .home
        let dark = scheme == .dark
        let w = max(DS.Card.highlightWidth, side * 0.03)
        content
            .overlay(Circle().strokeBorder(LinearGradient(colors: [DS.Color.textOnPrimary.opacity(dark ? DS.Card.highlightDark : DS.Card.highlightLight),
                                                                   s.ink.opacity(DS.Opacity.tintStroke)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: w)
                .padding(inset))
            .shadow(color: s.deep.opacity(dark ? DS.Card.shadowDark : DS.Card.shadowLight),
                    radius: side * 0.07, x: 0, y: side * 0.035)
    }
}
