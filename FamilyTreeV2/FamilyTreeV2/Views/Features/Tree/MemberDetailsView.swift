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
    /// «الطلبات المرسلة» من «تابِعه» أو خانة «طلبك قيد المراجعة» (بطاقة «AB»، البندان ٥ و٧)
    @State private var showSentRequests = false
    /// «إضافة ابن» على عقدته هو — العضو يضيف ابنه بنفسه (قرار المالك ٢٠٢٦-١٠-٢٧)
    @State private var showSelfAddChild = false
    /// نموذج الطلب المختار من «طلب تعديل» — «ابن» هنا أبناء ذكور فقط (البنت والزوجة في شجرة النساء)
    @State private var pendingEditAction: TreeEditAction? = nil
    @State private var showReportConfirm = false
    /// «طلب حذف» لابنه هو (§11): تأكيد «عائلتي» ثم `remove_self_child` — طلب للمالك والمدير
    @State private var confirmSelfRemoval = false
    @State private var selfRemovalSent = false
    @State private var selfRemovalError: String? = nil
    /// مربّع «اتصال / واتساب» من بلاطة الهاتف (تدقيق ٢٠٢٦-١١-١٠ #3) — الرقم الظاهر فقط
    @State private var phoneActionsNumber: String? = nil
    @Environment(\.openURL) private var openURL
    @State private var reportReason = ""
    @State private var reportSent = false
    @State private var reportFailed = false
    /// حظر العضو / إلغاء حظره (Guideline 1.2) — بجانب «إبلاغ»
    @State private var blockTarget: BlockTarget? = nil
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
    /// قسم «العائلة» تحت المعلومات مطويّ ومغلق بالبداية (طلب المالك ٢٠٢٦-١١-٠٦)
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


    private func recomputeCache() {
        let m = member
        cachedFather = m.fatherId.flatMap { memberVM.member(byId: $0) }
        cachedChildren = memberVM.allMembers
            .filter { $0.fatherId == m.id && $0.isCountable }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
        // طلبات شجرة النساء عن عقدة أخرى (بنته مثلاً) تظهر في تفاصيلها هي لا هنا
        cachedPendingRequests = adminRequestVM.treeEditRequests.filter { r in
            guard r.memberId == m.id else { return false }
            let node = r.treeEditPayload?.womenNodeId
            return node == nil || node == m.id
        }
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

    /// الحساب المقيّد («أكمل حسابك»، طلب المالك ٢٠٢٦-١١-٠٧): تفاصيل غيره مقفولة — القائمة من السيرفر
    @ObservedObject private var lineage = LineageGateStore.shared   // ينقل تغيّر «صلاحيات الأعضاء حسب الفئة» أيضاً
    private var lineageLocked: Bool { !isViewingSelf && lineage.isLocked(.memberDetails) }

    var body: some View {
        if lineageLocked {
            lineageLockedPanel
        } else {
            // جلسات الاستخدام: «صفحة العضو» ما دامت ظاهرة
            panel.appUsageScreen(.memberDetails)
        }
    }

    /// المربّع نفسه بحالة القفل الهادئة — «أكمل حسابك» يُغلقه ثم يفتح الصفحة (لا تُعرض نافذتان معاً)
    @ViewBuilder
    private var lineageLockedPanel: some View {
        let box = LineageLockedView(section: section, style: .card, onOpen: {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { LineageGateStore.shared.openPage() }
        }, onHidden: { dismiss() })
        .padding(DS.Spacing.lg)
        .background(GeometryReader { geo in
            Color.clear
                .preference(key: SheetContentHeightKey.self, value: geo.size.height)
                .preference(key: DSPanelCollapsedHeightKey.self, value: geo.size.height)
        })
        if centered {
            DSExpandableCenterPanel(isExpanded: .constant(false), onClose: { dismiss() }) { box }
        } else {
            box
        }
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
                // أرضية «AB» الكريمية الخفيفة (كحلي الرأس في الداكن)
                DS.MemberCard.boxBackground.ignoresSafeArea()

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
                                    // أفقياً كل الألواح ظاهرة من الفتح — تدخل تباعاً بعد الرأس (A1)
                                    infoGrid.dsStaggerIn(3)

                                    familyStrip.dsStaggerIn(4)

                                    bioCard.dsStaggerIn(5)

                                    pendingRequestsCard.dsStaggerIn(6)

                                    if !centered {
                                        actionButtonsSection.dsStaggerIn(7)
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
            // اختيار نوع الطلب، و«طلب تعديل»، و«إضافة ابن» — مربّعات المنتصف الموحّدة (`dsCenterBox`)
            // بدل نوافذ مكتوبة باليد (طلب المالك ٢٠٢٦-١١-١٠)
            .dsCenterBox(isPresented: $showEditActions, onBackgroundTap: { showEditActions = false }) {
                editActionsGrid
            }
            .dsCenterBox(item: $pendingEditAction) { action in
                TreeEditRequestView(member: member, action: action)
            }
            // «طلب حذف» (§11): بعد إغلاق النموذج تُقرأ «طلباتي» فتظهر «بانتظار الحذف»
            .onChange(of: pendingEditAction) { action in
                if action == nil, showsDeleteRequest {
                    Task { await adminRequestVM.fetchMyPendingRequests(force: true) }
                }
            }
            .task(id: showsDeleteRequest) {
                if showsDeleteRequest { await adminRequestVM.fetchMyPendingRequests() }
            }
            // «طلبك عنه» وخانة «طلبك قيد المراجعة» تقرأ طلباتك أنت (البندان ٥ و٧) — الجلب محدود كل ٢٠ ثانية
            .task { if !isViewingSelf { await adminRequestVM.fetchMyPendingRequests() } }
            .dsTallBox(isPresented: $showSentRequests) {
                MemberCardSentRequestsBox(onClose: { showSentRequests = false })
            }
            .dsCenterBox(isPresented: $showSelfAddChild) {
                AddChildSheet(member: member)
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
            Text(L10n.t("حذف السيرة الذاتية؟", "Delete biography?"))
        }
        .dsAlert(SelfRemovalText.confirmTitle, isPresented: $confirmSelfRemoval) {
            Button(SelfRemovalText.sendButton) { sendSelfRemoval() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(SelfRemovalText.confirmMessage(member.firstName))
        }
        .dsAlert(SelfRemovalText.sentTitle, isPresented: $selfRemovalSent, moment: .sentForApproval) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(SelfRemovalText.sentMessage)
        }
        .dsAlert(L10n.t("تعذّر الإرسال", "Couldn't send"),
                 isPresented: Binding(get: { selfRemovalError != nil }, set: { if !$0 { selfRemovalError = nil } })) {
            Button(L10n.t("حسناً", "OK")) { selfRemovalError = nil }
        } message: {
            Text(selfRemovalError ?? "")
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
                        reason: reason,
                        source: RequestSource(.tree, .member(target.fullName),
                                              RequestSourceStep("flag.fill", "بلاغ عن ملف عضو"))
                    )
                    if ok { await MainActor.run { reportSent = true } } else { await MainActor.run { reportFailed = true } }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { reportReason = "" }
        } message: {
            Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة ملف هذا العضو.",
                       "Enter a reason; it will be sent to the admins to review this member's profile."))
        }
        .dsAlert(L10n.t("تعذّر الإبلاغ", "Couldn't report"), isPresented: $reportFailed) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("تعذّر الإبلاغ. حاول مرة أخرى.", "Couldn't send the report. Please try again."))
        }
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
            Button(L10n.t("حسناً", "OK")) { }
        } message: {
            Text(L10n.t("وصل البلاغ إلى الإدارة، وتتم مراجعته خلال ٢٤ ساعة.",
                        "Thank you — your report reached the admins and will be reviewed within 24 hours."))
        }
        // بلاطة الهاتف: «اتصال» / «واتساب» — الرقم الظاهر فقط (تدقيق ٢٠٢٦-١١-١٠ #3)
        .dsAlert(L10n.t("التواصل", "Contact"),
                 isPresented: Binding(get: { phoneActionsNumber != nil },
                                      set: { if !$0 { phoneActionsNumber = nil } }),
                 icon: "phone.fill") {
            if let url = KuwaitPhone.telURL(phoneActionsNumber) {
                Button(L10n.t("اتصال", "Call")) { openURL(url) }
            }
            if let url = KuwaitPhone.whatsappURL(phoneActionsNumber) {
                Button(L10n.t("واتساب", "WhatsApp")) { openURL(url) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
        } message: {
            Text(verbatim: "\u{2066}\(KuwaitPhone.display(phoneActionsNumber))\u{2069}")
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
        DSDetailsToggle(isExpanded: detent == .large, tile: true, tint: DS.Color.actionNavy) { setDetailsOpen(detent != .large) }
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
                        // «AB»: فراغ بلون الأرضية ثم خط ذهبي رفيع وظلّ خفيف
                        .memberCardAvatarFrame(side: DS.Icon.memberHero)
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
                                Image(systemName: "leaf.fill")
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

            DSBalancedText(member.displayFullName)
                .dsFont(.memberNameTitle)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.lg)
                .offset(y: heroIn || reduceMotion ? 0 : 10)
                .opacity(heroIn ? 1 : 0)
            // زخرفة «AB» تحت الاسم: خط ذهبي في وسطه معيّن
            MemberCardOrnament()
                .opacity(heroIn ? 1 : 0)
            // طلب حذف معلّق من المشاهد على هذا الشخص (§11)
            if showsDeleteRequest && deletionPending {
                DSStatusChip(text: SelfRemovalText.pendingChip, tint: DS.Color.slate, size: .mini)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.55, dampingFraction: 0.68).delay(0.05)) { heroIn = true }
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsRow: some View {
        let showKinship = !isViewingSelf && !member.isDeleted && authVM.memberSees(.memberDetailsKinship)
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

    /// حبّة العمر — تظهر جنب زر القرابة. للمتوفّى: رمادي + رمز يوضّح الوفاة. العدد بعربي صحيح «5 سنوات» (البند ٩)
    @ViewBuilder
    private var agePill: some View {
        let isDeceased = member.isDeceased == true
        if let age = MemberCardLogic.age(birth: member.birthDate, death: member.deathDate, deceased: isDeceased,
                                         nowYear: Calendar.current.component(.year, from: Date())) {
            MemberCardStaticChip(text: MemberCardLogic.yearsText(age),
                                 icon: isDeceased ? "leaf.fill" : "timelapse",
                                 tint: isDeceased ? DS.Color.textSecondary : DS.Color.info,
                                 trailing: isDeceased ? L10n.t("· متوفّى", "· deceased") : nil)
        }
    }

    // MARK: - التفاصيل

    /// جسم التفاصيل: شبكة أيقونات (المعلومات + الأب + الأبناء) ← السيرة ← الطلبات ← الأزرار
    private var detailsBody: some View {
        // الأقسام تدخل تباعاً عند «عرض التفاصيل» (نفس حركة مربّعات الإضافة)
        let open = detent == .large
        return VStack(spacing: DS.Spacing.md) {
            // المعلومات أولاً، وتحتها العائلة مطويّة ومغلقة (طلب المالك ٢٠٢٦-١١-٠٦)
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

    // MARK: العائلة — تحت المعلومات، مطويّة ومغلقة بالبداية (طلب المالك ٢٠٢٦-١١-٠٦): الأب بطاقة بصورته واسمه
    // وعمره، والأبناء مرقّمون من الأكبر بشبكة ثابتة — شجرة الرجال بلا أم ولا زوجات («ما تنضاف الام و النساء نهائيا»)

    /// الضغط على الأب أو الابن يفتح صاحبه والشجرة تتبعه
    @ViewBuilder
    private var familyStrip: some View {
        let father = cachedFather
        let children = cachedChildren
        // «العائلة» مطفأة لفئته (بطاقته هو دائماً)
        if (father != nil || !children.isEmpty) && (isViewingSelf || authVM.memberSees(.memberDetailsFamily)) {
            // «AB»: لوح كريمي بمربّع أخضر العائلة — مطويّاً صور الأقارب بأدوارهم و«عرض ‹»
            MemberCardFamilyBox(
                summary: familySummary(hasFather: father != nil, children: children.count),
                relatives: (father.map { [MemberCardRelative(member: $0, role: L10n.t("الأب", "Father"))] } ?? [])
                    + children.map { MemberCardRelative(member: $0, role: $0.firstName) },
                isOpen: $familyOpen,
                face: { familyAvatar($0, size: DS.MemberCard.face) }
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if let father {
                        DSFamilyPersonRow(role: L10n.t("الأب", "Father"), tint: chromeInk,
                                          name: father.displayFullName,
                                          detail: DSMemberAge.detail(father),
                                          onTap: { openMemberInTree(father.id) }) {
                            familyAvatar(father, size: DSMemberKit.parentAvatar)
                        }
                    }
                    if !children.isEmpty {
                        DSFamilyChildrenBlock(
                            groups: [.init(id: "children", title: nil, tint: chromeInk, members: children)],
                            avatar: { familyAvatar($0, size: DSMemberKit.childAvatar) },
                            onTap: { openMemberInTree($0.id) })
                    }
                }
            }
        }
    }

    /// «الأب · ٣ أبناء» — بجانب العنوان (ملخّص والقسم مغلق)
    private func familySummary(hasFather: Bool, children: Int) -> String {
        var parts: [String] = []
        if hasFather { parts.append(L10n.t("الأب", "Father")) }
        if children > 0 { parts.append(L10n.t("\(children) أبناء", "\(children) children")) }
        return parts.joined(separator: " · ")
    }

    /// صورة دائرية بلون القسم (الحرف الأول بلا صورة)، والمتوفّى بالأبيض والأسود
    private func familyAvatar(_ m: FamilyMember, size: CGFloat) -> some View {
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
        .modifier(MemberTrialRing(side: size, inset: -DS.Spacing.xxs))
        .grayscale(m.isDeceased == true ? 1 : 0)
        .accessibilityHidden(true)
    }

    // MARK: شبكة المعلومات الأيقونية (طلب المالك)

    private struct InfoTileData: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: String
        let color: Color
        var ltr = false
        /// الرقم الخام لبلاطة الهاتف الظاهر — يجعلها قابلة للضغط (اتصال/واتساب)
        var phone: String? = nil
        /// «مخفي عن الأعضاء» بقفل تحت رقم المرأة (البند ٨)
        var caption: String? = nil
    }

    /// المعلومات في بلاطات أيقونية: الميلاد، الهاتف، الوفاة (بلا الأب والأبناء — طلب المالك)
    private var infoTiles: [InfoTileData] {
        cachedBasicInfoRows.enumerated().map { idx, row in
            InfoTileData(id: "info-\(idx)", icon: row.icon, label: row.label, value: row.value,
                         color: row.color, ltr: row.icon == "phone.fill", phone: row.phone, caption: row.caption)
        }
    }

    @ViewBuilder
    private var infoGrid: some View {
        let tiles = infoTiles
        if !tiles.isEmpty {
            // «AB»: لوح كريمي بمربّع بترولي — صفوف بيضاء
            MemberCardSection(title: L10n.t("المعلومات", "Info"),
                              icon: "person.text.rectangle.fill",
                              fill: DS.Color.seaFill) {
                // «AB»: صفّ كامل لكل معلومة (الرقم كاملاً بلا قصّ)
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(tiles) { infoTileView($0) }
                }
            }
        }
    }

    /// بلاطة الهاتف الظاهر تفتح «اتصال / واتساب»؛ غيرها للقراءة فقط
    @ViewBuilder
    private func infoTileView(_ tile: InfoTileData) -> some View {
        if let phone = tile.phone {
            Button { phoneActionsNumber = phone } label: { infoTileBody(tile) }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("اضغط للاتصال أو المراسلة عبر واتساب", "Tap to call or message on WhatsApp"))
        } else {
            infoTileBody(tile)
        }
    }

    /// صف معلومة «AB»: أيقونة في مربّع خفيف + العنوان الصغير + القيمة (+ قفل «مخفي عن الأعضاء»)
    private func infoTileBody(_ tile: InfoTileData) -> some View {
        MemberCardInfoRow(icon: tile.icon, label: tile.label, value: tile.value, tint: tile.color,
                          ltr: tile.ltr, lockCaption: tile.caption, tappable: tile.phone != nil)
    }

    // MARK: - Basic Info

    private struct InfoRowData {
        let icon: String
        let label: String
        let value: String
        let color: Color
        /// الرقم الخام حين يكون ظاهراً للمشاهد (نفس قاعدة العرض)
        var phone: String? = nil
        var caption: String? = nil
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
                : (isDeceased ? Self.yearOnly(birth) : (DateHelper.displayDate(birth) ?? birth))
            rows.append(.init(
                icon: "calendar",
                label: L10n.t("الميلاد", "Birth"),
                value: displayValue,
                color: shouldHide ? DS.Color.textTertiary : DS.Color.primary
            ))
        }

        // الرقم (البند ٨): رقم المرأة لا يراه العضو أبداً — لا صفّ ولا «مخفي»؛ الإدارة الأربعة وهي نفسها يرونه
        // وتحته «مخفي عن الأعضاء». الرجل المخفي كما كان («مخفي» للعضو). السيرفر يعيد nil للمخفيّ أصلاً.
        let phone = m.dsVisiblePhone(viewerId: authVM.currentUser?.id, viewerCanModerate: canMod)
        // «صلاحيات الأعضاء حسب الفئة»: «الهاتف والاتصال» مطفأ لفئته — لا صفّ (والسيرفر لا يرسل الرقم)
        let contactShown = isSelf || canMod || authVM.memberSees(.memberDetailsContact)
        if contactShown { switch MemberCardLogic.phoneRow(hasPhone: phone != nil, isFemale: m.isFemale,
                                        isPhoneHidden: m.isPhoneHidden == true, isDeceased: isDeceased,
                                        viewerIsSelf: isSelf, viewerIsStaff: canMod) {
        case .shown(let hiddenCaption):
            if let phone {
                rows.append(.init(
                    icon: "phone.fill",
                    label: L10n.t("الهاتف", "Phone"),
                    value: KuwaitPhone.display(phone),
                    color: DS.Color.sea,
                    phone: phone,
                    caption: hiddenCaption ? L10n.t("مخفي عن الأعضاء", "Hidden from members") : nil
                ))
            }
        case .hiddenWord:
            rows.append(.init(
                icon: "phone.fill",
                label: L10n.t("الهاتف", "Phone"),
                value: L10n.t("مخفي", "Hidden"),
                color: DS.Color.textTertiary
            ))
        case .none:
            break
        } }

        if isDeceased,
           let death = m.deathDate, !death.isEmpty {
            rows.append(.init(
                icon: "calendar.badge.minus",
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
            // «AB»: لوح كريمي بمربّع كحلي، وعدد الأحداث في الدائرة الذهبية
            MemberCardSection(
                title: L10n.t("السيرة الذاتية", "Biography"),
                icon: "text.quote",
                fill: DS.Color.navyFill,
                count: bioStations.count
            ) {
                VStack(spacing: DS.Spacing.sm) {
                    VStack(spacing: 0) {
                        ForEach(Array(bioStations.enumerated()), id: \.element.id) { index, station in
                            bioStationRow(index: index, total: bioStations.count, station: station)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, DS.Spacing.md)
                    .memberCardInset()

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
                        .dsReadingFont(.readingSecondary)
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

    /// البند ٧: «طلبك عنه» = طلباتك أنت مع «تابِعه» للعضو والمشرف؛ القائمة كاملة لمن يقرّر طلبات الشجرة (المالك والمدير
    /// والمراقب) وكل طلب يفتح في «الوارد» (`MemberPendingRequestsLink`)
    @ViewBuilder
    private var pendingRequestsCard: some View {
        let mine = myRequestsAboutMember
        // «طلبك عنه» مطفأ لفئته: لا قائمة لطلباته (قائمة الإدارة كما هي)
        let mode = MemberCardLogic.requestsSection(canModerateTree: authVM.canModerateTree,
                                                   allCount: cachedPendingRequests.count,
                                                   mineCount: authVM.memberSees(.memberDetailsMyRequests) ? mine.count : 0)
        MemberCardRequestsSection(
            requests: mode == .all ? cachedPendingRequests : mine,
            mode: mode,
            female: member.isFemale,
            onOpen: { request in
                if mode == .all { MemberPendingRequestsLink.open(request) { dismiss() } } else { showSentRequests = true }
            }
        )
    }

    /// طلباتك أنت المعلّقة عنه (`myPendingRequests` يقرأ صفوفك فقط) — بقاعدة `MemberCardLogic.mineInFamily`
    private var myRequestsAboutMember: [AdminRequest] {
        let refs = adminRequestVM.myPendingRequests.map(Self.ref)
        let ids = Set(MemberCardLogic.mineInFamily(refs, memberId: member.id, viewer: authVM.currentUser?.id).map(\.id))
        return adminRequestVM.myPendingRequests.filter { ids.contains($0.id) }
    }

    static func ref(_ r: AdminRequest) -> MemberCardLogic.RequestRef {
        let payload = r.treeEditPayload
        return MemberCardLogic.RequestRef(id: r.id, memberId: r.memberId, requesterId: r.requesterId,
                                          womenNode: payload?.womenNodeId,
                                          kind: payload?.women?.kind ?? payload?.action ?? r.requestType)
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
                        if authVM.memberSees(.memberDetailsEditRequest) {
                            circleActionButton(
                                icon: "pencil.and.list.clipboard",
                                label: L10n.t("طلب تعديل", "Request Edit"),
                                tint: chromeInk,
                                filled: true
                            ) { showEditActions = true }
                        }

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
            note: L10n.t("يُرسل الطلب إلى الإدارة للمراجعة", "The request goes to the admins for review"),
            onSubmit: {},
            onCancel: { showEditActions = false }
        ) {
            // «AB»: خانات ملوّنة بنوعها، وتحت كل خانة لمن الطلب وسطر صادق (البندان ٢ و٣)، وخانة عليها طلبك
            // المعلّق تقول «طلبك قيد المراجعة · افتحه» وتفتحه (البند ٥)
            let actions = availableEditActions
            let mine = MemberCardLogic.mineInFamily(adminRequestVM.myPendingRequests.map(Self.ref),
                                                    memberId: member.id, viewer: authVM.currentUser?.id)
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                MemberCardGridTitle()
                MemberRequestGrid {
                    ForEach(Array(actions.enumerated()), id: \.element.rawValue) { i, action in
                        let pending = MemberCardLogic.pending(kind: action.rawValue, in: mine) != nil
                        let honesty = MemberCardLogic.familyHonesty(action.rawValue)
                        MemberRequestTile(title: editActionLabel(for: action),
                                          subtitle: editActionSubtitle(action),
                                          icon: editActionIcon(action),
                                          palette: editActionPalette(action),
                                          line: pending ? MemberCardLogic.pendingTileText : honesty.text,
                                          lineStyle: pending ? .pending : (honesty.isWarning ? .warning : .honest)) {
                            if pending { openSentRequests() } else { pick(action) }
                        }
                        .dsEntrance(delay: DSMotion.staggerDelay(i, base: DSMotion.sectionsAfterHeader),
                                    scale: DSMotionRules.tilePopScale, animation: DSMotion.iconPop,
                                    anchor: .center)   // الخانات تقفز تباعاً (A1)
                    }
                }
                // لماذا لا «تعديل رقم» ولا «إضافة صورة» (البند ١)
                MemberCardStrip(text: MemberCardLogic.familyGridNote(isFemale: member.isFemale))
            }
        }
        .environment(\.dsComposerBackground, DS.MemberCard.boxBackground)
    }

    /// يغلق «طلب تعديل» ثم يفتح «الطلبات المرسلة» — نافذة واحدة في كل مرّة
    private func openSentRequests() {
        showEditActions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration + 0.15) { showSentRequests = true }
    }

    /// لون الخانة: الإضافة أخضر، التعديل كحلي، الوفاة رمادي، الحذف أحمر
    private func editActionPalette(_ action: TreeEditAction) -> MemberTilePalette {
        switch action {
        case .add: return .add
        case .deceased, .addDeathDate: return .record
        case .delete: return .delete
        case .other: return .other
        default: return .edit
        }
    }

    /// «حذف من الشجرة» إخفاء — رمز العين المشطوبة (البند ٣)
    private func editActionIcon(_ action: TreeEditAction) -> String {
        action == .delete ? "eye.slash" : action.iconName
    }

    /// الطلبات — «إضافة ابن» أولها كما كان (طلب المالك ٢٠٢٦-١٠-٢٥: «طلب إضافة» بشجرة النساء وحدها)
    /// البند ١: لا «تعديل رقم» على بطاقة غيرك، ولا «إضافة صورة» لأنثى — القائمة من `MemberCardLogic.familyKinds`
    private var availableEditActions: [TreeEditAction] {
        MemberCardLogic.familyKinds(isFemale: member.isFemale, isDeceased: member.isDeceased == true)
            .compactMap { TreeEditAction(rawValue: $0) }
    }


    /// نُغلق مربّع الاختيار أولاً ثم نفتح نموذج الطلب (عرضان متتاليان)
    private func pick(_ action: TreeEditAction, closing: (() -> Void)? = nil) {
        if let closing { closing() } else { showEditActions = false }
        // بعد خروج مربّع الاختيار (حركة الخروج ثم إغلاق نافذته) — نافذة واحدة في كل مرّة
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration + 0.15) {
            // ابنه هو: «طلب حذف» بمسار «عائلتي» (كان زرّ الشريط السفلي، صار خانة داخل «طلب تعديل» فقط)
            if action == .delete && showsDeleteRequest && isOwnChild { confirmSelfRemoval = true; return }
            pendingEditAction = action
        }
    }

    /// سطر «لمن» تحت كل بطاقة طلب (طلب المالك ٢٠٢٦-١٠-٢٥ «حط توضيح») — من اسم العضو المختار
    private func editActionSubtitle(_ action: TreeEditAction) -> String {
        let who = "«" + (member.firstName.isEmpty ? member.fullName : member.firstName) + "»"
        switch action {
        case .add: return L10n.t("ابن لـ", "Son of ") + who
        case .editName: return L10n.t("اسم ", "Name of ") + who
        case .editPhone: return L10n.t("رقم ", "Phone of ") + who
        case .editBirth: return L10n.t("ميلاد ", "Birth of ") + who
        case .deceased: return L10n.t("وفاة ", "Death of ") + who
        case .addDeathDate: return L10n.t("تاريخ وفاة ", "Death date of ") + who
        case .addPhoto: return L10n.t("صورة لـ", "Photo of ") + who
        case .delete: return who
        case .other: return who
        }
    }

    private func editActionLabel(for action: TreeEditAction) -> String {
        switch action {
        // «ابن» (طلب المالك ٢٠٢٦-١٠-٢٥ «خلها مسمى ابن») — أبناء ذكور فقط، والسطر تحته يقول لمن
        case .add: return L10n.t("ابن", "Son")
        case .editName: return L10n.t("تعديل اسم", "Edit Name")
        case .editPhone: return L10n.t("تعديل رقم", "Edit Phone")
        case .editBirth: return L10n.t("تعديل ميلاد", "Edit Birth")
        case .deceased: return L10n.t("تسجيل وفاة", "Deceased")
        case .addDeathDate: return L10n.t("تاريخ وفاة", "Death Date")
        case .addPhoto: return L10n.t("إضافة صورة", "Add Photo")
        // البند ٣: في شجرة العائلة الحذف إخفاء — «حذف من الشجرة» وتحته «يُخفى ويبقى في السجل»
        case .delete: return L10n.t("حذف من الشجرة", "Remove from tree")
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
        if !isViewingSelf && authVM.memberSees(.memberDetailsEditRequest) {
            return PanelAction(title: L10n.t("طلب تعديل", "Request Edit"), icon: "pencil.and.list.clipboard") {
                showEditActions = true
            }
        }
        return nil
    }

    /// «طلب تعديل» لغير صاحب الملف — في الشريط السفلي بجانب «إغلاق» كما كان (طلب المالك ٢٠٢٦-١٠-٢٤)،
    /// للأعضاء والإدارة
    private var showsRequestEdit: Bool {
        !isViewingSelf && !member.isDeleted && authVM.memberSees(.memberDetailsEditRequest)
    }

    /// زرّ الدور تحت الاسم (`DSMemberKit`): «تعديل مباشر» ذهبي للمالك والمدير والمراقب (`canEditMembers`)
    /// والقلم يكتب. «طلب إضافة» في شجرة النساء وحدها (طلب المالك ٢٠٢٦-١٠-٢٥) — هنا «إضافة ابن» داخل «طلب تعديل»
    @ViewBuilder private var roleActionButton: some View {
        if authVM.canEditMembers && !member.isDeleted {
            DSLiveButton(L10n.t("تعديل مباشر", "Direct Edit"), icon: "pencil",
                         tint: DSMemberKit.directTint, motion: .write,
                         hint: L10n.t("يفتح إدارة السجل", "Opens the member record"), tile: true) {
                showAdminControl = true
            }
        } else if isViewingSelf && !member.isDeleted && authVM.memberSees(.profileMyFamily) {
            DSLiveButton(L10n.t("إضافة ابن", "Add Child"), icon: "plus",
                         tint: DSMemberKit.directTint, motion: .write,
                         hint: L10n.t("إضافة ابن إلى الشجرة", "Adds your child to the tree"), tile: true) {
                showSelfAddChild = true
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

    // MARK: «طلب حذف» ظاهر (§11، طلب المالك ٢٠٢٦-١١-١٣ «حط طلب حذف في تفاصيل الأعضاء»)

    /// لغير الإدارة، لغير صاحب الملف، ولمن لا يبدو مسجّلاً في التطبيق (`looksRegistered` — نفس الأندرويد) —
    /// الإدارة كما كانت. خانة «حذف» داخل «طلب تعديل» باقية، والسيرفر يرفض حذف صاحب الحساب (`has_account`)
    private var showsDeleteRequest: Bool {
        guard !authVM.canModerate, !isViewingSelf, !member.isDeleted, authVM.currentUser != nil else { return false }
        let staff: [FamilyMember.UserRole] = [.owner, .admin, .monitor, .supervisor]
        return !member.looksRegistered && member.role != .pending && !staff.contains(member.role)
    }

    /// ابنه هو (أبوه = المشاهد) — مسار «عائلتي» بدل «تعديل الشجرة — حذف»
    private var isOwnChild: Bool {
        guard let me = authVM.currentUser?.id else { return false }
        return member.fatherId == me
    }

    /// طلب حذف معلّق للمشاهد على هذا الشخص
    private var deletionPending: Bool {
        SelfRemovalText.isPendingAny(member.id, in: adminRequestVM.myPendingRequests)
    }

    @ViewBuilder private var deleteRequestButton: some View {
        if showsDeleteRequest {
            DSDeleteRequestButton(pending: deletionPending) {
                if isOwnChild { confirmSelfRemoval = true } else { pendingEditAction = .delete }
            }
        }
    }

    private func sendSelfRemoval() {
        let id = member.id
        Task {
            switch await memberVM.removeSelfChild(id: id) {
            case .requested:
                await adminRequestVM.fetchMyPendingRequests(force: true)
                selfRemovalSent = true
            case .deleted:
                await adminRequestVM.fetchMyPendingRequests(force: true)
                dismiss()
            case .failed, .serverMissing:
                selfRemovalError = memberVM.errorMessage ?? L10n.t("تعذّر إرسال الطلب.", "Couldn't send the request.")
            }
            memberVM.errorMessage = nil
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
            // «طلب حذف» داخل «طلب تعديل» فقط — لا زرّ منفصل هنا (طلب المالك ٢٠٢٦-١١-١٧ «ابى الترتيب القديم»)
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
            DS.MemberCard.boxBackground
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.MemberCard.panelLine).frame(height: DS.Border.width)
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
        // زرّ × في طرف الرأس يغلق المربّع (طلب المالك ٢٠٢٦-١١-٠٧) — مثل بقية المربّعات، و«إغلاق» السفلي باقٍ
        DSPanelCloseReader { close in
            DSComposerHeader(
                title: L10n.t("تفاصيل العضو", "Member Details"),
                subtitle: L10n.t("من شجرة العائلة", "From the family tree"),
                icon: "person.text.rectangle.fill",
                tint: member.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
                onClose: close
            )
        }
        // «AB»: خط ذهبي رفيع تحت الرأس الكحلي
        .overlay(alignment: .bottom) { MemberCardBandHairline() }
        // علم دولة الرقم (غير الكويت) في زاوية الرأس — طلب المالك ٢٠٢٦-١٠-٢٤ «علم السعودية للرقم السعودي»؛
        // بقاعدة صفّ «الهاتف» نفسها: لا علم إن لم يحقّ للمشاهد رؤية الرقم (ولا لرقم امرأة عند العضو). قبل زرّ × لا تحته
        .overlay(alignment: .trailing) {
            DSPhoneCountryBadge(phone: member.isFemale && !authVM.canModerate && !isViewingSelf ? nil
                                : member.dsVisiblePhone(viewerId: authVM.currentUser?.id,
                                                        viewerCanModerate: authVM.canModerate))
                .padding(.leading, DS.Spacing.lg)
                .padding(.trailing, DS.Theme.isCalm ? DS.Spacing.lg : DSFamilyKit.badgeInsetWithClose)
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
        let lookup = memberVM._memberById
        let member = member
        Task { @MainActor in
            // جهة الأم من شجرة النساء (خالك، ابن خالتك…) — K1
            let result = await KinshipCalculator.familyTree(from: currentUser, to: member, lookup: lookup)

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
                        "pathIds": pathIds,
                        "viaMother": result.viaMother
                    ]
                )
            }
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
